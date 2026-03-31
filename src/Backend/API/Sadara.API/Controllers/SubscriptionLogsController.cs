using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>
/// سجل عمليات الاشتراكات (بديل Google Sheets)
/// يُستخدم لتخزين وجلب سجلات التجديد والشراء والتفعيل
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class SubscriptionLogsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<SubscriptionLogsController> _logger;

    public SubscriptionLogsController(IUnitOfWork unitOfWork, ILogger<SubscriptionLogsController> logger)
    {
        _unitOfWork = unitOfWork;
        _logger = logger;
    }

    /// <summary>
    /// جلب جميع السجلات مع تصفية وترقيم
    /// </summary>
    [HttpGet]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetAll(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] string? zoneId = null,
        [FromQuery] string? operationType = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        var query = _unitOfWork.SubscriptionLogs.AsQueryable();

        // تطبيق الفلاتر
        if (!string.IsNullOrEmpty(zoneId))
            query = query.Where(x => x.ZoneId == zoneId);

        if (!string.IsNullOrEmpty(operationType))
            query = query.Where(x => x.OperationType == operationType);

        if (fromDate.HasValue)
            query = query.Where(x => x.ActivationDate >= fromDate.Value);

        if (toDate.HasValue)
            query = query.Where(x => x.ActivationDate <= toDate.Value);

        var total = await query.CountAsync();
        var logs = await query
            .OrderByDescending(x => x.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return Ok(new { success = true, data = logs, total, page, pageSize });
    }

    /// <summary>
    /// جلب سجل واحد بالمعرف
    /// </summary>
    [HttpGet("{id:long}")]
    [Authorize]
    public async Task<IActionResult> GetById(long id)
    {
        var log = await _unitOfWork.SubscriptionLogs.GetByIdAsync(id);
        if (log == null)
            return NotFound(new { success = false, message = "السجل غير موجود" });

        return Ok(new { success = true, data = log });
    }

    /// <summary>
    /// إضافة سجل جديد (يُستخدم من Flutter بعد كل عملية تجديد/شراء)
    /// </summary>
    [HttpPost]
    [Authorize]
    public async Task<IActionResult> Create([FromBody] CreateSubscriptionLogRequest request)
    {
        var log = new SubscriptionLog
        {
            // معلومات العميل
            CustomerId = request.CustomerId,
            CustomerName = request.CustomerName,
            PhoneNumber = request.PhoneNumber,

            // معلومات الاشتراك
            SubscriptionId = request.SubscriptionId,
            PlanName = request.PlanName,
            PlanPrice = request.PlanPrice,
            CommitmentPeriod = request.CommitmentPeriod,
            BundleId = request.BundleId,
            CurrentStatus = request.CurrentStatus,
            DeviceUsername = request.DeviceUsername,

            // معلومات العملية
            OperationType = request.OperationType,
            ActivatedBy = request.ActivatedBy,
            ActivationDate = request.ActivationDate ?? DateTime.UtcNow,
            ActivationTime = request.ActivationTime,
            SessionId = request.SessionId,
            LastUpdateDate = DateTime.UtcNow,

            // معلومات الموقع
            ZoneId = request.ZoneId,
            ZoneName = request.ZoneName,
            FbgInfo = request.FbgInfo,
            FatInfo = request.FatInfo,
            FdtInfo = request.FdtInfo,

            // معلومات المحفظة
            WalletBalanceBefore = request.WalletBalanceBefore,
            WalletBalanceAfter = request.WalletBalanceAfter,
            PartnerWalletBalanceBefore = request.PartnerWalletBalanceBefore,
            CustomerWalletBalanceBefore = request.CustomerWalletBalanceBefore,
            Currency = request.Currency,
            PaymentMethod = request.PaymentMethod,

            // معلومات الشريك/الموظف
            PartnerName = request.PartnerName,
            PartnerId = request.PartnerId,
            UserId = request.UserId,
            CompanyId = request.CompanyId,

            // حالة العملية
            IsPrinted = request.IsPrinted,
            IsWhatsAppSent = request.IsWhatsAppSent,
            SubscriptionNotes = request.SubscriptionNotes,

            // معلومات إضافية
            StartDate = request.StartDate,
            EndDate = request.EndDate,
            ApiResponse = request.ApiResponse,

            // معلومات التوصيل والدفع
            TechnicianName = request.TechnicianName,
            PaymentStatus = request.PaymentStatus,

            // حقول تكامل المحاسبة
            CollectionType = request.CollectionType,
            LinkedAgentId = request.LinkedAgentId,
            LinkedTechnicianId = request.LinkedTechnicianId
        };

        // حماية من التكرار
        if (!string.IsNullOrEmpty(log.SessionId))
        {
            var duplicate = await _unitOfWork.SubscriptionLogs.AsQueryable()
                .AnyAsync(l => l.SessionId == log.SessionId && !l.IsDeleted);
            if (duplicate)
            {
                var existing = await _unitOfWork.SubscriptionLogs.AsQueryable()
                    .FirstOrDefaultAsync(l => l.SessionId == log.SessionId && !l.IsDeleted);
                return Ok(new { success = true, id = existing?.Id, duplicate = true });
            }
        }

        await _unitOfWork.SubscriptionLogs.AddAsync(log);
        await _unitOfWork.SaveChangesAsync();

        // إنشاء القيد المحاسبي تلقائياً إذا توفرت المعلومات
        if (log.CompanyId.HasValue && log.UserId.HasValue
            && log.PlanPrice.HasValue && log.PlanPrice > 0
            && !string.IsNullOrEmpty(log.CollectionType))
        {
            try
            {
                var userId = log.UserId.Value;
                var companyId = log.CompanyId.Value;
                var amount = log.PlanPrice.Value;
                var operatorName = log.ActivatedBy ?? "مشغل";
                var planName = log.PlanName ?? "اشتراك";
                var customerName = log.CustomerName ?? "عميل";
                var isPurchase = log.OperationType?.ToLower() == "purchase";
                var opType = isPurchase ? "شراء" : "تجديد";

                var revenueCode = isPurchase ? "4120" : "4110";
                var revenueAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, revenueCode, companyId)
                    ?? await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, "4100", companyId);
                if (revenueAccount == null)
                {
                    _logger.LogWarning("⚠️ حساب الإيراد {Code} غير موجود للشركة {CompanyId} — السجل {LogId} بدون قيد", revenueCode, companyId, log.Id);
                    goto noAccounting;
                }

                Account? debitAccount = null;
                string description = "";

                switch (log.CollectionType.ToLower())
                {
                    case "cash":
                        debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, "1110", userId, $"صندوق {operatorName}", companyId);
                        await _unitOfWork.SaveChangesAsync();
                        description = $"{opType} {planName} - {customerName} - نقد عبر {operatorName}";
                        break;

                    case "credit":
                        debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, "1160", userId, $"ذمة {operatorName}", companyId);
                        await _unitOfWork.SaveChangesAsync();
                        description = $"{opType} {planName} - {customerName} - آجل على {operatorName}";
                        break;

                    case "master":
                        debitAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, "1170", companyId);
                        if (debitAccount == null) goto noAccounting;
                        description = $"{opType} {planName} - {customerName} - ماستر";
                        break;

                    case "agent":
                        if (!log.LinkedAgentId.HasValue) goto noAccounting;
                        var agent = await _unitOfWork.Agents.GetByIdAsync(log.LinkedAgentId.Value);
                        if (agent == null) goto noAccounting;
                        debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, "1150", agent.Id, agent.Name, companyId);
                        await _unitOfWork.SaveChangesAsync();
                        agent.TotalCharges += amount;
                        agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
                        _unitOfWork.Agents.Update(agent);
                        description = $"{opType} {planName} - {customerName} - على وكيل {agent.Name} عبر {operatorName}";
                        break;

                    case "technician":
                        if (!log.LinkedTechnicianId.HasValue) goto noAccounting;
                        var tech = await _unitOfWork.Users.GetByIdAsync(log.LinkedTechnicianId.Value);
                        if (tech == null) goto noAccounting;
                        // حفظ اسم الفني في سجل العملية للعرض لاحقاً
                        if (string.IsNullOrEmpty(log.TechnicianName))
                            log.TechnicianName = tech.FullName;
                        debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, "1140", tech.Id, tech.FullName, companyId);
                        await _unitOfWork.SaveChangesAsync();
                        tech.TechTotalCharges += amount;
                        tech.TechNetBalance = tech.TechTotalPayments - tech.TechTotalCharges;
                        _unitOfWork.Users.Update(tech);
                        var techTx = new TechnicianTransaction
                        {
                            TechnicianId = tech.Id,
                            Type = TechnicianTransactionType.Charge,
                            Category = TechnicianTransactionCategory.Subscription,
                            Amount = amount,
                            BalanceAfter = tech.TechNetBalance,
                            Description = $"{opType} {planName} - {customerName}",
                            ReferenceNumber = log.Id.ToString(),
                            CreatedById = userId,
                            CompanyId = companyId,
                            CreatedAt = DateTime.UtcNow
                        };
                        await _unitOfWork.TechnicianTransactions.AddAsync(techTx);
                        description = $"{opType} {planName} - {customerName} - على فني {tech.FullName} عبر {operatorName}";
                        break;

                    default:
                        goto noAccounting;
                }

                if (debitAccount != null)
                {
                    var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
                    {
                        (debitAccount.Id, amount, 0, $"{debitAccount.Name} - {opType} {planName}"),
                        (revenueAccount.Id, 0, amount, $"إيراد {opType} - {customerName}")
                    };

                    await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                        _unitOfWork, companyId, userId, description,
                        JournalReferenceType.FtthSubscription, log.Id.ToString(), lines);

                    await _unitOfWork.SaveChangesAsync();

                    var entry = await _unitOfWork.JournalEntries.AsQueryable()
                        .Where(j => j.ReferenceType == JournalReferenceType.FtthSubscription
                            && j.ReferenceId == log.Id.ToString())
                        .OrderByDescending(j => j.CreatedAt)
                        .FirstOrDefaultAsync();
                    if (entry != null)
                    {
                        log.JournalEntryId = entry.Id;
                        _unitOfWork.SubscriptionLogs.Update(log);
                        await _unitOfWork.SaveChangesAsync();
                    }
                }

                noAccounting:;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "⚠️ فشل إنشاء القيد المحاسبي للسجل {LogId} — السجل حُفظ بدون قيد", log.Id);
            }
        }

        return CreatedAtAction(nameof(GetById), new { id = log.Id }, new
        {
            success = true,
            data = log,
            hasAccounting = log.JournalEntryId.HasValue,
            accountingWarning = !log.JournalEntryId.HasValue && log.PlanPrice > 0
                ? "تم حفظ السجل بدون قيد محاسبي — تحقق من إعدادات الحسابات"
                : null
        });
    }

    /// <summary>
    /// تحديث سجل موجود (مثلاً لتحديث حالة الطباعة أو الواتساب)
    /// </summary>
    [HttpPut("{id:long}")]
    [Authorize]
    public async Task<IActionResult> Update(long id, [FromBody] UpdateSubscriptionLogRequest request)
    {
        var log = await _unitOfWork.SubscriptionLogs.GetByIdAsync(id);
        if (log == null)
            return NotFound(new { success = false, message = "السجل غير موجود" });

        // تحديث الحقول القابلة للتعديل
        if (request.IsPrinted.HasValue)
            log.IsPrinted = request.IsPrinted.Value;

        if (request.IsWhatsAppSent.HasValue)
            log.IsWhatsAppSent = request.IsWhatsAppSent.Value;

        if (!string.IsNullOrEmpty(request.SubscriptionNotes))
            log.SubscriptionNotes = request.SubscriptionNotes;

        log.UpdatedAt = DateTime.UtcNow;
        _unitOfWork.SubscriptionLogs.Update(log);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, data = log });
    }

    /// <summary>
    /// حذف سجل (soft delete)
    /// </summary>
    [HttpDelete("{id:long}")]
    [Authorize(Policy = "SuperAdmin")]
    public async Task<IActionResult> Delete(long id)
    {
        var log = await _unitOfWork.SubscriptionLogs.GetByIdAsync(id);
        if (log == null)
            return NotFound(new { success = false, message = "السجل غير موجود" });

        // عكس رصيد الفني إذا كان مرتبطاً
        if (log.LinkedTechnicianId.HasValue && log.PlanPrice.HasValue)
        {
            var tech = await _unitOfWork.Users.GetByIdAsync(log.LinkedTechnicianId.Value);
            if (tech != null)
            {
                tech.TechTotalCharges -= log.PlanPrice.Value;
                tech.TechNetBalance = tech.TechTotalPayments - tech.TechTotalCharges;
                _unitOfWork.Users.Update(tech);

                // حذف معاملة الفني المرتبطة
                var techTx = await _unitOfWork.TechnicianTransactions.AsQueryable()
                    .FirstOrDefaultAsync(t => t.ReferenceNumber == log.Id.ToString() && !t.IsDeleted);
                if (techTx != null)
                {
                    techTx.IsDeleted = true;
                    techTx.DeletedAt = DateTime.UtcNow;
                    _unitOfWork.TechnicianTransactions.Update(techTx);
                }
            }
        }

        // عكس رصيد الوكيل إذا كان مرتبطاً
        if (log.LinkedAgentId.HasValue && log.PlanPrice.HasValue)
        {
            var agent = await _unitOfWork.Agents.GetByIdAsync(log.LinkedAgentId.Value);
            if (agent != null)
            {
                agent.TotalCharges -= log.PlanPrice.Value;
                agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
                _unitOfWork.Agents.Update(agent);

                // حذف معاملة الوكيل المرتبطة
                var agentTx = await _unitOfWork.AgentTransactions.AsQueryable()
                    .FirstOrDefaultAsync(t => t.ReferenceNumber == log.Id.ToString() && !t.IsDeleted);
                if (agentTx != null)
                {
                    agentTx.IsDeleted = true;
                    agentTx.DeletedAt = DateTime.UtcNow;
                    _unitOfWork.AgentTransactions.Update(agentTx);
                }
            }
        }

        log.IsDeleted = true;
        log.DeletedAt = DateTime.UtcNow;
        _unitOfWork.SubscriptionLogs.Update(log);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("تم حذف سجل الاشتراك {LogId} مع عكس الأرصدة", id);
        return Ok(new { success = true, message = "تم حذف السجل وعكس الأرصدة بنجاح" });
    }

    /// <summary>
    /// البحث عن سجلات باستخدام رقم الاشتراك
    /// </summary>
    [HttpGet("subscription/{subscriptionId}")]
    [Authorize]
    public async Task<IActionResult> GetBySubscription(string subscriptionId)
    {
        var logs = await _unitOfWork.SubscriptionLogs
            .FindAsync(x => x.SubscriptionId == subscriptionId);

        return Ok(new { success = true, data = logs });
    }

    /// <summary>
    /// جلب إحصائيات سريعة
    /// </summary>
    [HttpGet("stats")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetStats([FromQuery] DateTime? date = null)
    {
        var targetDate = date?.Date ?? DateTime.UtcNow.Date;
        var query = _unitOfWork.SubscriptionLogs.AsQueryable()
            .Where(x => x.ActivationDate.HasValue && x.ActivationDate.Value.Date == targetDate);

        var stats = new
        {
            totalOperations = await query.CountAsync(),
            renewals = await query.CountAsync(x => x.OperationType == "renewal"),
            purchases = await query.CountAsync(x => x.OperationType == "purchase"),
            changes = await query.CountAsync(x => x.OperationType == "change"),
            totalRevenue = await query.SumAsync(x => x.PlanPrice ?? 0)
        };

        return Ok(new { success = true, data = stats, date = targetDate });
    }

    /// <summary>
    /// جلب سجلات التوصيلات (التي لها فني منفذ) مجمعة حسب الفني
    /// بديل getFilteredConnectionsWithNotes من Google Sheets
    /// </summary>
    [HttpGet("connections")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetConnections(
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] string? technicianName = null,
        [FromQuery] string? zoneId = null,
        [FromQuery] string? operationType = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 500)
    {
        var query = _unitOfWork.SubscriptionLogs.AsQueryable()
            .Where(x => !string.IsNullOrEmpty(x.TechnicianName));

        if (!string.IsNullOrEmpty(technicianName))
            query = query.Where(x => x.TechnicianName == technicianName);

        if (!string.IsNullOrEmpty(zoneId))
            query = query.Where(x => x.ZoneId == zoneId);

        if (!string.IsNullOrEmpty(operationType))
            query = query.Where(x => x.OperationType == operationType);

        if (fromDate.HasValue)
            query = query.Where(x => x.ActivationDate >= fromDate.Value);

        if (toDate.HasValue)
            query = query.Where(x => x.ActivationDate <= toDate.Value);

        var total = await query.CountAsync();
        var logs = await query
            .OrderByDescending(x => x.ActivationDate ?? x.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(x => new
            {
                x.Id,
                x.CustomerId,
                x.CustomerName,
                x.PhoneNumber,
                x.SubscriptionId,
                x.PlanName,
                x.PlanPrice,
                x.OperationType,
                x.ActivatedBy,
                x.ActivationDate,
                x.ZoneId,
                x.CurrentStatus,
                x.Currency,
                x.PaymentMethod,
                x.TechnicianName,
                x.PaymentStatus,
                x.DeviceUsername,
            })
            .ToListAsync();

        // تجميع حسب الفني
        var grouped = logs
            .GroupBy(x => x.TechnicianName ?? "غير محدد")
            .ToDictionary(g => g.Key, g => g.ToList());

        return Ok(new { success = true, data = grouped, total, page, pageSize });
    }

    /// <summary>
    /// تحديث حالة الدفع لسجل معين
    /// </summary>
    [HttpPatch("{id:long}/payment-status")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> UpdatePaymentStatus(long id, [FromBody] UpdatePaymentStatusRequest request)
    {
        var log = await _unitOfWork.SubscriptionLogs.GetByIdAsync(id);
        if (log == null)
            return NotFound(new { success = false, message = "السجل غير موجود" });

        log.PaymentStatus = request.PaymentStatus;
        log.UpdatedAt = DateTime.UtcNow;
        _unitOfWork.SubscriptionLogs.Update(log);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث حالة الدفع", data = new { log.Id, log.PaymentStatus } });
    }

    /// <summary>
    /// تحديث حالة الدفع لمجموعة سجلات (دفع الكل لفني معين)
    /// </summary>
    [HttpPatch("bulk-payment-status")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> BulkUpdatePaymentStatus([FromBody] BulkUpdatePaymentStatusRequest request)
    {
        var logs = await _unitOfWork.SubscriptionLogs
            .FindAsync(x => request.Ids.Contains(x.Id));

        foreach (var log in logs)
        {
            log.PaymentStatus = request.PaymentStatus;
            log.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.SubscriptionLogs.Update(log);
        }

        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = $"تم تحديث {logs.Count()} سجل", count = logs.Count() });
    }
}

#region DTOs

/// <summary>
/// طلب إنشاء سجل اشتراك جديد
/// </summary>
public class CreateSubscriptionLogRequest
{
    // معلومات العميل
    public string? CustomerId { get; set; }
    public string? CustomerName { get; set; }
    public string? PhoneNumber { get; set; }

    // معلومات الاشتراك
    public string? SubscriptionId { get; set; }
    public string? PlanName { get; set; }
    public decimal? PlanPrice { get; set; }
    public int? CommitmentPeriod { get; set; }
    public string? BundleId { get; set; }
    public string? CurrentStatus { get; set; }
    public string? DeviceUsername { get; set; }

    // معلومات العملية
    public string? OperationType { get; set; }
    public string? ActivatedBy { get; set; }
    public DateTime? ActivationDate { get; set; }
    public string? ActivationTime { get; set; }
    public string? SessionId { get; set; }

    // معلومات الموقع
    public string? ZoneId { get; set; }
    public string? ZoneName { get; set; }
    public string? FbgInfo { get; set; }
    public string? FatInfo { get; set; }
    public string? FdtInfo { get; set; }

    // معلومات المحفظة
    public decimal? WalletBalanceBefore { get; set; }
    public decimal? WalletBalanceAfter { get; set; }
    public decimal? PartnerWalletBalanceBefore { get; set; }
    public decimal? CustomerWalletBalanceBefore { get; set; }
    public string? Currency { get; set; }
    public string? PaymentMethod { get; set; }

    // معلومات الشريك/الموظف
    public string? PartnerName { get; set; }
    public string? PartnerId { get; set; }
    public Guid? UserId { get; set; }
    public Guid? CompanyId { get; set; }

    // حالة العملية
    public bool IsPrinted { get; set; }
    public bool IsWhatsAppSent { get; set; }
    public string? SubscriptionNotes { get; set; }

    // معلومات إضافية
    public string? StartDate { get; set; }
    public string? EndDate { get; set; }
    public string? ApiResponse { get; set; }

    // معلومات التوصيل والدفع
    public string? TechnicianName { get; set; }
    public string? PaymentStatus { get; set; }

    // حقول تكامل المحاسبة
    public string? CollectionType { get; set; }       // cash | credit | master | agent | technician
    public Guid? LinkedAgentId { get; set; }
    public Guid? LinkedTechnicianId { get; set; }
}

/// <summary>
/// طلب تحديث سجل اشتراك
/// </summary>
public class UpdateSubscriptionLogRequest
{
    public bool? IsPrinted { get; set; }
    public bool? IsWhatsAppSent { get; set; }
    public string? SubscriptionNotes { get; set; }
}

/// <summary>
/// طلب تحديث حالة الدفع
/// </summary>
public class UpdatePaymentStatusRequest
{
    public string PaymentStatus { get; set; } = "";
}

/// <summary>
/// طلب تحديث حالة الدفع لمجموعة سجلات
/// </summary>
public class BulkUpdatePaymentStatusRequest
{
    public List<long> Ids { get; set; } = new();
    public string PaymentStatus { get; set; } = "";
}

#endregion
