using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>
/// تكامل FTTH مع نظام المحاسبة
/// حفظ عمليات التفعيل مع قيود محاسبية تلقائية + كشف حساب المشغل + المطابقة
/// </summary>
[ApiController]
[Route("api/ftth-accounting")]
[Authorize]
[Tags("FTTH Accounting")]
public class FtthAccountingController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<FtthAccountingController> _logger;

    public FtthAccountingController(IUnitOfWork unitOfWork, ILogger<FtthAccountingController> logger)
    {
        _unitOfWork = unitOfWork;
        _logger = logger;
    }

    // ==================== 1. حفظ عملية مع قيد محاسبي ====================

    /// <summary>
    /// حفظ سجل عملية FTTH مع إنشاء قيد محاسبي تلقائي
    /// يُستدعى من Flutter بعد كل تفعيل/تجديد
    /// </summary>
    [HttpPost("log-with-accounting")]
    public async Task<IActionResult> LogWithAccounting([FromBody] FtthLogWithAccountingDto dto)
    {
        try
        {
            // 1. إنشاء SubscriptionLog
            var log = new SubscriptionLog
            {
                CustomerId = dto.CustomerId,
                CustomerName = dto.CustomerName,
                PhoneNumber = dto.PhoneNumber,
                SubscriptionId = dto.SubscriptionId,
                PlanName = dto.PlanName,
                PlanPrice = dto.PlanPrice,
                CommitmentPeriod = dto.CommitmentPeriod,
                BundleId = dto.BundleId,
                CurrentStatus = dto.CurrentStatus,
                DeviceUsername = dto.DeviceUsername,
                OperationType = dto.OperationType,
                ActivatedBy = dto.ActivatedBy,
                ActivationDate = dto.ActivationDate,
                ActivationTime = dto.ActivationTime,
                SessionId = dto.SessionId,
                ZoneId = dto.ZoneId,
                ZoneName = dto.ZoneName,
                FbgInfo = dto.FbgInfo,
                FatInfo = dto.FatInfo,
                FdtInfo = dto.FdtInfo,
                WalletBalanceBefore = dto.WalletBalanceBefore,
                WalletBalanceAfter = dto.WalletBalanceAfter,
                PartnerWalletBalanceBefore = dto.PartnerWalletBalanceBefore,
                CustomerWalletBalanceBefore = dto.CustomerWalletBalanceBefore,
                Currency = dto.Currency,
                PaymentMethod = dto.PaymentMethod,
                PartnerName = dto.PartnerName,
                PartnerId = dto.PartnerId,
                UserId = dto.UserId,
                CompanyId = dto.CompanyId,
                IsPrinted = dto.IsPrinted,
                IsWhatsAppSent = dto.IsWhatsAppSent,
                SubscriptionNotes = dto.SubscriptionNotes,
                StartDate = dto.StartDate,
                EndDate = dto.EndDate,
                TechnicianName = dto.TechnicianName,
                PaymentStatus = dto.PaymentStatus,
                // حقول التكامل الجديدة
                CollectionType = dto.CollectionType,
                FtthTransactionId = dto.FtthTransactionId,
                ServiceRequestId = dto.ServiceRequestId,
                LinkedAgentId = dto.LinkedAgentId,
                IsReconciled = false
            };

            await _unitOfWork.SubscriptionLogs.AddAsync(log);
            await _unitOfWork.SaveChangesAsync();

            // 2. إنشاء قيد محاسبي (إذا يوجد CompanyId وUserId ومبلغ)
            Guid? journalEntryId = null;
            if (dto.CompanyId.HasValue && dto.UserId.HasValue && dto.PlanPrice.HasValue && dto.PlanPrice > 0)
            {
                try
                {
                    journalEntryId = await CreateAccountingEntry(log, dto);
                    if (journalEntryId.HasValue)
                    {
                        log.JournalEntryId = journalEntryId;
                        _unitOfWork.SubscriptionLogs.Update(log);
                        await _unitOfWork.SaveChangesAsync();
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "فشل إنشاء القيد المحاسبي للسجل {LogId} — السجل حُفظ بدونه", log.Id);
                }
            }

            return Ok(new
            {
                success = true,
                message = "تم حفظ السجل بنجاح",
                logId = log.Id,
                journalEntryId,
                hasAccounting = journalEntryId.HasValue
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حفظ سجل FTTH مع المحاسبة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي: " + ex.Message });
        }
    }

    /// <summary>
    /// إنشاء القيد المحاسبي حسب نوع التحصيل
    /// </summary>
    private async Task<Guid?> CreateAccountingEntry(SubscriptionLog log, FtthLogWithAccountingDto dto)
    {
        var companyId = dto.CompanyId!.Value;
        var userId = dto.UserId!.Value;
        var amount = dto.PlanPrice!.Value;
        var collectionType = dto.CollectionType ?? "cash";

        // تحديد حساب الإيراد (تجديد أو شراء)
        var revenueCode = dto.OperationType?.ToLower() == "purchase" ? "4120" : "4110";
        var revenueAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, revenueCode, companyId);
        
        // fallback إلى 4100 إذا لم يوجد 4110/4120
        if (revenueAccount == null)
            revenueAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, "4100", companyId);
        if (revenueAccount == null)
        {
            _logger.LogWarning("حساب الإيراد غير موجود للشركة {CompanyId}", companyId);
            return null;
        }

        // تحديد الطرف المدين حسب نوع التحصيل
        Account debitAccount;
        string description;
        var operatorName = dto.ActivatedBy ?? "مشغل";
        var planName = dto.PlanName ?? "اشتراك";
        var customerName = dto.CustomerName ?? "عميل";
        var opType = dto.OperationType?.ToLower() == "purchase" ? "شراء" : "تجديد";

        switch (collectionType.ToLower())
        {
            case "cash":
                // نقد → صندوق المشغل (فرعي تحت 1110)
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, "1110", userId, $"صندوق {operatorName}", companyId);
                await _unitOfWork.SaveChangesAsync(); // حفظ الحساب الجديد قبل القيد
                description = $"{opType} {planName} - {customerName} - نقد عبر {operatorName}";
                break;

            case "credit":
                // آجل → ذمة المشغل (فرعي تحت 1160)
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, "1160", userId, $"ذمة {operatorName}", companyId);
                await _unitOfWork.SaveChangesAsync();
                description = $"{opType} {planName} - {customerName} - آجل على {operatorName}";
                break;

            case "master":
                // ماستر → صندوق الدفع الإلكتروني (1170)
                debitAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, "1170", companyId)
                    ?? throw new Exception("حساب صندوق الدفع الإلكتروني 1170 غير موجود");
                description = $"{opType} {planName} - {customerName} - ماستر (إلكتروني)";
                break;

            case "agent":
                // وكيل → ذمة الوكيل (فرعي تحت 1150)
                if (!dto.LinkedAgentId.HasValue)
                    throw new Exception("يجب تحديد الوكيل عند اختيار نوع الدفع 'وكيل'");
                
                var agent = await _unitOfWork.Agents.GetByIdAsync(dto.LinkedAgentId.Value);
                if (agent == null)
                    throw new Exception("الوكيل غير موجود");
                
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, "1150", agent.Id, agent.Name, companyId);
                await _unitOfWork.SaveChangesAsync();
                description = $"{opType} {planName} - {customerName} - على وكيل {agent.Name} عبر {operatorName}";

                // ═══ توحيد: تحديث رصيد الوكيل + إنشاء AgentTransaction ═══
                agent.TotalCharges += amount;
                agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
                _unitOfWork.Agents.Update(agent);

                var agentTxCategory = dto.OperationType?.ToLower() == "purchase"
                    ? TransactionCategory.NewSubscription
                    : TransactionCategory.RenewalSubscription;

                var agentTx = new AgentTransaction
                {
                    AgentId = agent.Id,
                    Type = TransactionType.Charge,
                    Category = agentTxCategory,
                    Amount = amount,
                    BalanceAfter = agent.NetBalance,
                    Description = $"{opType} {planName} - {customerName}",
                    ReferenceNumber = log.Id.ToString(),
                    CreatedById = userId,
                    Notes = $"تفعيل عبر {operatorName}"
                };
                await _unitOfWork.AgentTransactions.AddAsync(agentTx);
                break;

            case "technician":
                // فني → ذمة الفني (فرعي تحت 1140)
                if (!dto.LinkedTechnicianId.HasValue)
                    throw new Exception("يجب تحديد الفني عند اختيار نوع الدفع 'فني'");
                
                var tech = await _unitOfWork.Users.GetByIdAsync(dto.LinkedTechnicianId.Value);
                if (tech == null)
                    throw new Exception("الفني غير موجود");
                
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, "1140", tech.Id, tech.FullName, companyId);
                await _unitOfWork.SaveChangesAsync();
                description = $"{opType} {planName} - {customerName} - على فني {tech.FullName} عبر {operatorName}";

                // ═══ توحيد: تحديث رصيد الفني + إنشاء TechnicianTransaction ═══
                tech.TechTotalCharges += amount;
                tech.TechNetBalance = tech.TechTotalPayments - tech.TechTotalCharges;
                _unitOfWork.Users.Update(tech);

                var techTxCategory = dto.OperationType?.ToLower() == "purchase"
                    ? TechnicianTransactionCategory.Subscription
                    : TechnicianTransactionCategory.Subscription;

                var techTx = new TechnicianTransaction
                {
                    TechnicianId = tech.Id,
                    Type = TechnicianTransactionType.Charge,
                    Category = techTxCategory,
                    Amount = amount,
                    BalanceAfter = tech.TechNetBalance,
                    Description = $"{opType} {planName} - {customerName}",
                    ReferenceNumber = log.Id.ToString(),
                    CreatedById = userId,
                    CompanyId = companyId,
                    CreatedAt = DateTime.UtcNow
                };
                await _unitOfWork.TechnicianTransactions.AddAsync(techTx);
                break;

            default:
                // افتراضي: نقد
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, "1110", userId, $"صندوق {operatorName}", companyId);
                await _unitOfWork.SaveChangesAsync();
                description = $"{opType} {planName} - {customerName} - عبر {operatorName}";
                break;
        }

        // إنشاء القيد
        var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
        {
            (debitAccount.Id, amount, 0, $"{debitAccount.Name} - {opType} {planName}"),
            (revenueAccount.Id, 0, amount, $"إيراد {opType} - {customerName}")
        };

        await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
            _unitOfWork, companyId, userId, description,
            JournalReferenceType.FtthSubscription, log.Id.ToString(), lines);

        await _unitOfWork.SaveChangesAsync();

        // جلب القيد المُنشأ وربطه بالمعاملات
        var entry = await _unitOfWork.JournalEntries.AsQueryable()
            .Where(j => j.ReferenceType == JournalReferenceType.FtthSubscription
                && j.ReferenceId == log.Id.ToString()
                && j.CompanyId == companyId)
            .OrderByDescending(j => j.CreatedAt)
            .FirstOrDefaultAsync();

        // ربط JournalEntryId بالمعاملات المُنشأة
        if (entry != null)
        {
            var linkedTechTx = await _unitOfWork.TechnicianTransactions.AsQueryable()
                .FirstOrDefaultAsync(t => t.ReferenceNumber == log.Id.ToString() && t.JournalEntryId == null && !t.IsDeleted);
            if (linkedTechTx != null)
            {
                linkedTechTx.JournalEntryId = entry.Id;
                _unitOfWork.TechnicianTransactions.Update(linkedTechTx);
            }

            var linkedAgentTx = await _unitOfWork.AgentTransactions.AsQueryable()
                .FirstOrDefaultAsync(t => t.ReferenceNumber == log.Id.ToString() && t.JournalEntryId == null && !t.IsDeleted);
            if (linkedAgentTx != null)
            {
                linkedAgentTx.JournalEntryId = entry.Id;
                _unitOfWork.AgentTransactions.Update(linkedAgentTx);
            }

            await _unitOfWork.SaveChangesAsync();
        }

        return entry?.Id;
    }

    // ==================== 2. كشف حساب المشغل ====================

    /// <summary>
    /// ملخص مالي لمشغل FTTH محدد
    /// </summary>
    [HttpGet("operator-summary/{userId}")]
    public async Task<IActionResult> GetOperatorSummary(
        Guid userId,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] Guid? companyId = null)
    {
        try
        {
            var user = await _unitOfWork.Users.GetByIdAsync(userId);
            if (user == null)
                return NotFound(new { success = false, message = "المستخدم غير موجود" });

            var query = _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => l.UserId == userId);

            if (companyId.HasValue)
                query = query.Where(l => l.CompanyId == companyId);
            if (from.HasValue)
                query = query.Where(l => l.ActivationDate >= from.Value);
            if (to.HasValue)
                query = query.Where(l => l.ActivationDate <= to.Value.Date.AddDays(1));

            var logs = await query.OrderByDescending(l => l.ActivationDate).ToListAsync();

            var totalAmount = logs.Sum(l => l.PlanPrice ?? 0);
            var cashAmount = logs.Where(l => l.CollectionType == "cash").Sum(l => l.PlanPrice ?? 0);
            var creditAmount = logs.Where(l => l.CollectionType == "credit").Sum(l => l.PlanPrice ?? 0);
            var masterAmount = logs.Where(l => l.CollectionType == "master").Sum(l => l.PlanPrice ?? 0);
            var agentAmount = logs.Where(l => l.CollectionType == "agent").Sum(l => l.PlanPrice ?? 0);
            var technicianAmount = logs.Where(l => l.CollectionType == "technician").Sum(l => l.PlanPrice ?? 0);

            // حساب النقد المسلّم والآجل المحصّل من CashTransactions
            decimal deliveredCash = 0;
            decimal collectedCredit = 0;

            if (companyId.HasValue)
            {
                // البحث عن صندوق المشغل
                var operatorCashAccount = await _unitOfWork.Accounts.AsQueryable()
                    .FirstOrDefaultAsync(a => a.Code.StartsWith("1110")
                        && a.Description == userId.ToString()
                        && a.CompanyId == companyId);

                // البحث عن ذمة المشغل
                var operatorCreditAccount = await _unitOfWork.Accounts.AsQueryable()
                    .FirstOrDefaultAsync(a => a.Code.StartsWith("1160")
                        && a.Description == userId.ToString()
                        && a.CompanyId == companyId);

                // النقد المسلّم = المبالغ الدائنة في صندوق المشغل (تحويل للشركة)
                if (operatorCashAccount != null)
                {
                    deliveredCash = await _unitOfWork.JournalEntryLines.AsQueryable()
                        .Where(l => l.AccountId == operatorCashAccount.Id && l.CreditAmount > 0)
                        .Join(_unitOfWork.JournalEntries.AsQueryable()
                            .Where(j => j.ReferenceType == JournalReferenceType.OperatorCashDelivery
                                && j.Status != JournalEntryStatus.Voided),
                            l => l.JournalEntryId, j => j.Id, (l, j) => l.CreditAmount)
                        .SumAsync(x => x);
                }

                // الآجل المحصّل = المبالغ الدائنة في ذمة المشغل
                if (operatorCreditAccount != null)
                {
                    collectedCredit = await _unitOfWork.JournalEntryLines.AsQueryable()
                        .Where(l => l.AccountId == operatorCreditAccount.Id && l.CreditAmount > 0)
                        .Join(_unitOfWork.JournalEntries.AsQueryable()
                            .Where(j => j.ReferenceType == JournalReferenceType.OperatorCreditCollection
                                && j.Status != JournalEntryStatus.Voided),
                            l => l.JournalEntryId, j => j.Id, (l, j) => l.CreditAmount)
                        .SumAsync(x => x);
                }
            }

            var remainingCash = cashAmount - deliveredCash;
            var remainingCredit = creditAmount - collectedCredit;

            return Ok(new
            {
                success = true,
                data = new
                {
                    operatorId = userId,
                    operatorName = user.FullName,
                    operatorUsername = user.Username,
                    ftthUsername = user.FtthUsername,
                    totalActivations = logs.Count,
                    totalAmount,
                    cashAmount,
                    cashCount = logs.Count(l => l.CollectionType == "cash"),
                    creditAmount,
                    creditCount = logs.Count(l => l.CollectionType == "credit"),
                    masterAmount,
                    masterCount = logs.Count(l => l.CollectionType == "master"),
                    agentAmount,
                    agentCount = logs.Count(l => l.CollectionType == "agent"),
                    technicianAmount,
                    technicianCount = logs.Count(l => l.CollectionType == "technician"),
                    // عمليات بدون تصنيف (قديمة)
                    unclassifiedAmount = logs.Where(l => string.IsNullOrEmpty(l.CollectionType)).Sum(l => l.PlanPrice ?? 0),
                    unclassifiedCount = logs.Count(l => string.IsNullOrEmpty(l.CollectionType)),
                    deliveredCash,
                    collectedCredit,
                    remainingCash,
                    remainingCredit,
                    netOwed = remainingCash + remainingCredit,
                    transactions = logs.Select(l => new
                    {
                        l.Id,
                        l.CustomerId,
                        l.CustomerName,
                        l.PhoneNumber,
                        l.SubscriptionId,
                        l.PlanName,
                        l.PlanPrice,
                        l.CommitmentPeriod,
                        l.CurrentStatus,
                        l.DeviceUsername,
                        l.OperationType,
                        l.ActivatedBy,
                        l.ActivationDate,
                        l.ActivationTime,
                        l.ZoneId,
                        l.ZoneName,
                        l.FbgInfo,
                        l.FatInfo,
                        l.FdtInfo,
                        l.WalletBalanceBefore,
                        l.WalletBalanceAfter,
                        l.PaymentMethod,
                        l.PartnerName,
                        l.TechnicianName,
                        l.PaymentStatus,
                        l.StartDate,
                        l.EndDate,
                        l.CollectionType,
                        l.IsReconciled,
                        l.JournalEntryId,
                        l.IsPrinted,
                        l.IsWhatsAppSent,
                        l.SubscriptionNotes,
                        l.LinkedAgentId,
                        l.LinkedTechnicianId,
                        l.RenewalCycleMonths,
                        l.PaidMonths
                    })
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب ملخص المشغل {UserId}", userId);
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 3. لوحة تحكم المشغلين ====================

    /// <summary>
    /// ملخص كل المشغلين (للمدير)
    /// </summary>
    [HttpGet("operators-dashboard")]
    public async Task<IActionResult> GetOperatorsDashboard(
        [FromQuery] Guid? companyId = null,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null)
    {
        try
        {
            var query = _unitOfWork.SubscriptionLogs.AsQueryable();

            if (companyId.HasValue)
                // تضمين السجلات القديمة التي لم يُحدد لها CompanyId (للتوافق مع البيانات السابقة)
                query = query.Where(l => l.CompanyId == companyId || l.CompanyId == null);
            if (from.HasValue)
            {
                var fromUtc = DateTime.SpecifyKind(from.Value.Date, DateTimeKind.Utc);
                query = query.Where(l => l.ActivationDate >= fromUtc);
            }
            if (to.HasValue)
            {
                var toUtc = DateTime.SpecifyKind(to.Value.Date.AddDays(1), DateTimeKind.Utc);
                query = query.Where(l => l.ActivationDate <= toUtc);
            }

            // تجميع حسب UserId مع تفصيل أنواع العمليات
            var grouped = await query
                .GroupBy(l => l.UserId)
                .Select(g => new
                {
                    UserId = g.Key,
                    TotalCount = g.Count(),
                    TotalAmount = g.Sum(l => l.PlanPrice ?? 0),
                    // حسب نوع التحصيل
                    CashAmount = g.Where(l => l.CollectionType == "cash").Sum(l => l.PlanPrice ?? 0),
                    CashCount = g.Count(l => l.CollectionType == "cash"),
                    CreditAmount = g.Where(l => l.CollectionType == "credit").Sum(l => l.PlanPrice ?? 0),
                    CreditCount = g.Count(l => l.CollectionType == "credit"),
                    MasterAmount = g.Where(l => l.CollectionType == "master").Sum(l => l.PlanPrice ?? 0),
                    MasterCount = g.Count(l => l.CollectionType == "master"),
                    AgentAmount = g.Where(l => l.CollectionType == "agent").Sum(l => l.PlanPrice ?? 0),
                    AgentCount = g.Count(l => l.CollectionType == "agent"),
                    TechnicianAmount = g.Where(l => l.CollectionType == "technician").Sum(l => l.PlanPrice ?? 0),
                    TechnicianCount = g.Count(l => l.CollectionType == "technician"),
                    UnclassifiedAmount = g.Where(l => l.CollectionType == null || l.CollectionType == "").Sum(l => l.PlanPrice ?? 0),
                    UnclassifiedCount = g.Count(l => l.CollectionType == null || l.CollectionType == ""),
                    // حسب نوع العملية
                    PurchaseCount = g.Count(l => l.OperationType != null && (l.OperationType.ToUpper().Contains("PURCHASE") || l.OperationType.ToUpper().Contains("SUBSCRIBE"))),
                    PurchaseAmount = g.Where(l => l.OperationType != null && (l.OperationType.ToUpper().Contains("PURCHASE") || l.OperationType.ToUpper().Contains("SUBSCRIBE"))).Sum(l => l.PlanPrice ?? 0),
                    RenewalCount = g.Count(l => l.OperationType != null && l.OperationType.ToUpper().Contains("RENEW")),
                    RenewalAmount = g.Where(l => l.OperationType != null && l.OperationType.ToUpper().Contains("RENEW")).Sum(l => l.PlanPrice ?? 0),
                    ChangeCount = g.Count(l => l.OperationType != null && l.OperationType.ToUpper().Contains("CHANGE") && !l.OperationType.ToUpper().Contains("SCHEDULE")),
                    ChangeAmount = g.Where(l => l.OperationType != null && l.OperationType.ToUpper().Contains("CHANGE") && !l.OperationType.ToUpper().Contains("SCHEDULE")).Sum(l => l.PlanPrice ?? 0),
                    ScheduleCount = g.Count(l => l.OperationType != null && l.OperationType.ToUpper().Contains("SCHEDULE")),
                    ScheduleAmount = g.Where(l => l.OperationType != null && l.OperationType.ToUpper().Contains("SCHEDULE")).Sum(l => l.PlanPrice ?? 0),
                    // مطابقة
                    ReconciledCount = g.Count(l => l.IsReconciled)
                })
                .ToListAsync();

            // جلب أسماء المستخدمين
            var userIds = grouped.Where(g => g.UserId.HasValue).Select(g => g.UserId!.Value).ToList();
            var users = await _unitOfWork.Users.AsQueryable()
                .Where(u => userIds.Contains(u.Id))
                .Select(u => new { u.Id, u.FullName, u.Username, u.FtthUsername })
                .ToListAsync();

            // ── حساب النقد المسلّم والآجل المحصّل لكل مشغل ──
            var userIdStrings = userIds.Select(id => id.ToString()).ToList();

            // حسابات صناديق المشغلين (1110)
            var operatorCashAccounts = await _unitOfWork.Accounts.AsQueryable()
                .Where(a => a.Code.StartsWith("1110") && a.Description != null
                    && userIdStrings.Contains(a.Description)
                    && (!companyId.HasValue || a.CompanyId == companyId))
                .Select(a => new { a.Id, a.Description })
                .ToListAsync();

            // حسابات ذمم المشغلين (1160)
            var operatorCreditAccounts = await _unitOfWork.Accounts.AsQueryable()
                .Where(a => a.Code.StartsWith("1160") && a.Description != null
                    && userIdStrings.Contains(a.Description)
                    && (!companyId.HasValue || a.CompanyId == companyId))
                .Select(a => new { a.Id, a.Description })
                .ToListAsync();

            // النقد المسلّم لكل مشغل (CreditAmount في صندوقه عبر OperatorCashDelivery)
            var cashAccountIds = operatorCashAccounts.Select(a => a.Id).ToList();
            var deliveredByAccount = cashAccountIds.Any()
                ? await _unitOfWork.JournalEntryLines.AsQueryable()
                    .Where(l => cashAccountIds.Contains(l.AccountId) && l.CreditAmount > 0)
                    .Join(_unitOfWork.JournalEntries.AsQueryable()
                        .Where(j => j.ReferenceType == JournalReferenceType.OperatorCashDelivery
                            && j.Status != JournalEntryStatus.Voided),
                        l => l.JournalEntryId, j => j.Id,
                        (l, j) => new { l.AccountId, l.CreditAmount })
                    .GroupBy(x => x.AccountId)
                    .Select(g => new { AccountId = g.Key, Total = g.Sum(x => x.CreditAmount) })
                    .ToListAsync()
                : new List<dynamic>().Select(x => new { AccountId = Guid.Empty, Total = 0m }).ToList();

            // الآجل المحصّل لكل مشغل (CreditAmount في ذمته عبر OperatorCreditCollection)
            var creditAccountIds = operatorCreditAccounts.Select(a => a.Id).ToList();
            var collectedByAccount = creditAccountIds.Any()
                ? await _unitOfWork.JournalEntryLines.AsQueryable()
                    .Where(l => creditAccountIds.Contains(l.AccountId) && l.CreditAmount > 0)
                    .Join(_unitOfWork.JournalEntries.AsQueryable()
                        .Where(j => j.ReferenceType == JournalReferenceType.OperatorCreditCollection
                            && j.Status != JournalEntryStatus.Voided),
                        l => l.JournalEntryId, j => j.Id,
                        (l, j) => new { l.AccountId, l.CreditAmount })
                    .GroupBy(x => x.AccountId)
                    .Select(g => new { AccountId = g.Key, Total = g.Sum(x => x.CreditAmount) })
                    .ToListAsync()
                : new List<dynamic>().Select(x => new { AccountId = Guid.Empty, Total = 0m }).ToList();

            var result = grouped.Select(g =>
            {
                var user = g.UserId.HasValue ? users.FirstOrDefault(u => u.Id == g.UserId.Value) : null;
                var userIdStr = g.UserId?.ToString();

                // النقد المسلّم لهذا المشغل
                var cashAccId = operatorCashAccounts.FirstOrDefault(a => a.Description == userIdStr)?.Id;
                var delivered = cashAccId.HasValue
                    ? deliveredByAccount.FirstOrDefault(d => d.AccountId == cashAccId.Value)?.Total ?? 0m
                    : 0m;

                // الآجل المحصّل لهذا المشغل
                var creditAccId = operatorCreditAccounts.FirstOrDefault(a => a.Description == userIdStr)?.Id;
                var collected = creditAccId.HasValue
                    ? collectedByAccount.FirstOrDefault(c => c.AccountId == creditAccId.Value)?.Total ?? 0m
                    : 0m;

                var remainingCash = g.CashAmount - delivered;
                var remainingCredit = g.CreditAmount - collected;

                return new
                {
                    userId = g.UserId,
                    operatorName = user?.FullName ?? g.UserId?.ToString() ?? "غير معروف",
                    username = user?.Username,
                    ftthUsername = user?.FtthUsername,
                    totalCount = g.TotalCount,
                    totalAmount = g.TotalAmount,
                    cashAmount = g.CashAmount,
                    cashCount = g.CashCount,
                    creditAmount = g.CreditAmount,
                    creditCount = g.CreditCount,
                    masterAmount = g.MasterAmount,
                    masterCount = g.MasterCount,
                    agentAmount = g.AgentAmount,
                    agentCount = g.AgentCount,
                    technicianAmount = g.TechnicianAmount,
                    technicianCount = g.TechnicianCount,
                    unclassifiedAmount = g.UnclassifiedAmount,
                    unclassifiedCount = g.UnclassifiedCount,
                    deliveredCash = delivered,
                    collectedCredit = collected,
                    netOwed = remainingCash + remainingCredit,
                    // أنواع العمليات
                    purchaseCount = g.PurchaseCount,
                    purchaseAmount = g.PurchaseAmount,
                    renewalCount = g.RenewalCount,
                    renewalAmount = g.RenewalAmount,
                    changeCount = g.ChangeCount,
                    changeAmount = g.ChangeAmount,
                    scheduleCount = g.ScheduleCount,
                    scheduleAmount = g.ScheduleAmount,
                    reconciledCount = g.ReconciledCount
                };
            }).OrderByDescending(x => x.totalAmount).ToList();

            // ── توزيعات إضافية ──

            // توزيع أنواع العمليات
            var operationTypes = await query
                .GroupBy(l => l.OperationType ?? "غير محدد")
                .Select(g => new { type = g.Key, count = g.Count(), amount = g.Sum(l => l.PlanPrice ?? 0) })
                .OrderByDescending(x => x.count)
                .ToListAsync();

            // توزيع المناطق
            var zones = await query
                .Where(l => l.ZoneName != null && l.ZoneName != "")
                .GroupBy(l => l.ZoneName!)
                .Select(g => new { zone = g.Key, count = g.Count(), amount = g.Sum(l => l.PlanPrice ?? 0) })
                .OrderByDescending(x => x.count)
                .Take(20)
                .ToListAsync();

            // توزيع الباقات
            var plans = await query
                .Where(l => l.PlanName != null && l.PlanName != "")
                .GroupBy(l => l.PlanName!)
                .Select(g => new { plan = g.Key, count = g.Count(), amount = g.Sum(l => l.PlanPrice ?? 0) })
                .OrderByDescending(x => x.count)
                .Take(20)
                .ToListAsync();

            // توزيع الفنيين
            var technicians = await query
                .Where(l => l.TechnicianName != null && l.TechnicianName != "")
                .GroupBy(l => l.TechnicianName!)
                .Select(g => new { technician = g.Key, count = g.Count(), amount = g.Sum(l => l.PlanPrice ?? 0) })
                .OrderByDescending(x => x.count)
                .Take(15)
                .ToListAsync();

            // توزيع يومي
            var daily = await query
                .Where(l => l.ActivationDate != null)
                .GroupBy(l => l.ActivationDate!.Value.Date)
                .Select(g => new { date = g.Key, count = g.Count(), amount = g.Sum(l => l.PlanPrice ?? 0) })
                .OrderBy(x => x.date)
                .ToListAsync();

            // إحصائيات المطابقة
            var totalRecords = result.Sum(r => r.totalCount);
            var reconciledTotal = result.Sum(r => r.reconciledCount);

            return Ok(new
            {
                success = true,
                data = result,
                summary = new
                {
                    totalOperators = result.Count,
                    totalActivations = result.Sum(r => r.totalCount),
                    totalAmount = result.Sum(r => r.totalAmount),
                    totalCash = result.Sum(r => r.cashAmount),
                    totalCredit = result.Sum(r => r.creditAmount),
                    totalMaster = result.Sum(r => r.masterAmount),
                    totalAgent = result.Sum(r => r.agentAmount),
                    totalTechnician = result.Sum(r => r.technicianAmount),
                    totalNetOwed = result.Sum(r => r.netOwed),
                    totalUnclassified = result.Sum(r => r.unclassifiedAmount),
                    totalUnclassifiedCount = result.Sum(r => r.unclassifiedCount),
                    // تفصيل أنواع العمليات
                    totalPurchase = result.Sum(r => r.purchaseAmount),
                    totalPurchaseCount = result.Sum(r => r.purchaseCount),
                    totalRenewal = result.Sum(r => r.renewalAmount),
                    totalRenewalCount = result.Sum(r => r.renewalCount),
                    totalChange = result.Sum(r => r.changeAmount),
                    totalChangeCount = result.Sum(r => r.changeCount),
                    totalSchedule = result.Sum(r => r.scheduleAmount),
                    totalScheduleCount = result.Sum(r => r.scheduleCount),
                    // مطابقة
                    reconciledCount = reconciledTotal,
                    reconciledPercentage = totalRecords > 0
                        ? Math.Round((double)reconciledTotal / totalRecords * 100, 1)
                        : 0
                },
                distributions = new
                {
                    operationTypes,
                    zones,
                    plans,
                    technicians,
                    daily = daily.Select(d => new
                    {
                        date = d.date.ToString("yyyy-MM-dd"),
                        d.count,
                        d.amount
                    })
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب لوحة المشغلين");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 4. تسليم نقد من المشغل ====================

    /// <summary>
    /// تسليم نقد من المشغل لصندوق الشركة
    /// </summary>
    [HttpPost("deliver-cash")]
    public async Task<IActionResult> DeliverCash([FromBody] OperatorCashDeliveryDto dto)
    {
        try
        {
            var user = await _unitOfWork.Users.GetByIdAsync(dto.OperatorUserId);
            if (user == null)
                return NotFound(new { success = false, message = "المشغل غير موجود" });

            // صندوق المشغل (فرعي تحت 1110)
            var operatorAccount = await _unitOfWork.Accounts.AsQueryable()
                .FirstOrDefaultAsync(a => a.Code.StartsWith("1110")
                    && a.Description == dto.OperatorUserId.ToString()
                    && a.CompanyId == dto.CompanyId && a.IsActive);

            if (operatorAccount == null)
                return BadRequest(new { success = false, message = "لا يوجد حساب صندوق لهذا المشغل" });

            // صندوق الشركة
            var companyCashAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, "1110", dto.CompanyId);
            if (companyCashAccount == null)
                return BadRequest(new { success = false, message = "حساب صندوق الشركة غير موجود" });

            // إذا كان صندوق الشركة هو نفسه (ليس فرعي) نستخدمه مباشرة
            // لكن إذا 1110 أصبح أب (isLeaf=false) نحتاج نبحث عن فرعي للشركة
            if (!companyCashAccount.IsLeaf)
            {
                var companySubCash = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, "1110", dto.CompanyId, "صندوق الشركة الرئيسي", dto.CompanyId);
                await _unitOfWork.SaveChangesAsync();
                companyCashAccount = companySubCash;
            }

            var description = $"تسليم نقد من المشغل {user.FullName} - مبلغ {dto.Amount:N0}";
            var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
            {
                (companyCashAccount.Id, dto.Amount, 0, $"إيداع صندوق الشركة من {user.FullName}"),
                (operatorAccount.Id, 0, dto.Amount, $"تسليم نقد من صندوق {user.FullName}")
            };

            await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                _unitOfWork, dto.CompanyId, dto.DeliveredById ?? dto.OperatorUserId,
                description, JournalReferenceType.OperatorCashDelivery,
                dto.OperatorUserId.ToString(), lines);

            // تحديث صندوق CashBox إذا محدد
            if (dto.CashBoxId.HasValue)
            {
                var cashBox = await _unitOfWork.CashBoxes.GetByIdAsync(dto.CashBoxId.Value);
                if (cashBox != null)
                {
                    cashBox.CurrentBalance += dto.Amount;
                    _unitOfWork.CashBoxes.Update(cashBox);

                    var tx = new CashTransaction
                    {
                        CashBoxId = cashBox.Id,
                        TransactionType = CashTransactionType.Deposit,
                        Amount = dto.Amount,
                        BalanceAfter = cashBox.CurrentBalance,
                        Description = description,
                        ReferenceType = JournalReferenceType.OperatorCashDelivery,
                        ReferenceId = dto.OperatorUserId.ToString(),
                        CreatedById = dto.DeliveredById ?? dto.OperatorUserId
                    };
                    await _unitOfWork.CashTransactions.AddAsync(tx);
                }
            }

            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = $"تم تسليم {dto.Amount:N0} بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تسليم النقد");
            return StatusCode(500, new { success = false, message = "خطأ: " + ex.Message });
        }
    }

    // ==================== 4.5 قائمة عملاء الآجل غير المسددين ====================

    /// <summary>
    /// جلب عملاء الآجل غير المسددين لمشغل معين
    /// </summary>
    [HttpGet("credit-customers/{operatorUserId}")]
    public async Task<IActionResult> GetCreditCustomers(Guid operatorUserId, [FromQuery] Guid? companyId = null)
    {
        try
        {
            var query = _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => l.UserId == operatorUserId
                    && (l.PaymentStatus == null || l.PaymentStatus != "مسدد")
                    && (
                        // آجل عادي
                        l.CollectionType == "credit"
                        // أو نقد لكن عليه دورة تكرار ولم يُسدد بالكامل (الشهر الأول نقد والباقي آجل)
                        || (l.CollectionType == "cash" && l.RenewalCycleMonths != null && l.RenewalCycleMonths > 1 && l.PaidMonths < l.RenewalCycleMonths)
                    ));

            if (companyId.HasValue)
                query = query.Where(l => l.CompanyId == companyId);

            var logs = await query
                .OrderByDescending(l => l.ActivationDate)
                .Select(l => new
                {
                    l.Id,
                    l.CustomerName,
                    l.CustomerId,
                    l.PhoneNumber,
                    l.PlanName,
                    Amount = l.PlanPrice ?? 0,
                    l.OperationType,
                    l.ActivationDate,
                    l.PaymentStatus,
                    l.CollectionType,
                    l.RenewalCycleMonths,
                    l.PaidMonths,
                    l.NextRenewalDate,
                    MonthlyAmount = l.PlanPrice ?? 0,
                    RemainingMonths = (l.RenewalCycleMonths ?? 1) - l.PaidMonths,
                    RemainingAmount = ((l.RenewalCycleMonths ?? 1) - l.PaidMonths) * (l.PlanPrice ?? 0)
                })
                .ToListAsync();

            return Ok(new { success = true, data = logs });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب عملاء الآجل");
            return StatusCode(500, new { success = false, message = "خطأ: " + ex.Message });
        }
    }

    // ==================== 4.6 تحديد دورة التجديد المتكرر ====================

    /// <summary>
    /// تحديد أو تعديل دورة التجديد المتكرر لسجل اشتراك
    /// </summary>
    [HttpPost("set-renewal-cycle")]
    public async Task<IActionResult> SetRenewalCycle([FromBody] SetRenewalCycleDto dto)
    {
        try
        {
            var log = await _unitOfWork.SubscriptionLogs.GetByIdAsync(dto.LogId);
            if (log == null)
                return NotFound(new { success = false, message = "السجل غير موجود" });

            log.RenewalCycleMonths = dto.CycleMonths;
            
            // إذا العملية نقد، الشهر الأول مدفوع تلقائياً
            if (dto.PaidMonths.HasValue)
                log.PaidMonths = dto.PaidMonths.Value;
            else if (log.CollectionType == "cash" && dto.CycleMonths.HasValue && dto.CycleMonths > 1)
                log.PaidMonths = 1; // الشهر الأول نقد
            else
                log.PaidMonths = 0;

            if (dto.CycleMonths.HasValue && dto.CycleMonths > 0 && log.ActivationDate.HasValue)
            {
                // NextRenewalDate = ActivationDate + (PaidMonths + 1) أشهر
                log.NextRenewalDate = log.ActivationDate.Value.AddMonths(log.PaidMonths + 1);
            }
            else
            {
                log.NextRenewalDate = null;
            }

            log.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.SubscriptionLogs.Update(log);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تحديد دورة التجديد بنجاح",
                renewalCycleMonths = log.RenewalCycleMonths,
                paidMonths = log.PaidMonths,
                nextRenewalDate = log.NextRenewalDate });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تحديد دورة التجديد");
            return StatusCode(500, new { success = false, message = "خطأ: " + ex.Message });
        }
    }

    // ==================== 4.7 تحصيل شهر واحد من التكرار ====================

    /// <summary>
    /// تحصيل شهر واحد من اشتراك مكرر (دفع جزئي)
    /// </summary>
    [HttpPost("collect-renewal-month")]
    public async Task<IActionResult> CollectRenewalMonth([FromBody] CollectRenewalMonthDto dto)
    {
        try
        {
            var log = await _unitOfWork.SubscriptionLogs.GetByIdAsync(dto.LogId);
            if (log == null)
                return NotFound(new { success = false, message = "السجل غير موجود" });

            if (log.RenewalCycleMonths == null || log.RenewalCycleMonths <= 0)
                return BadRequest(new { success = false, message = "هذا السجل ليس متكرراً" });

            if (log.PaidMonths >= log.RenewalCycleMonths)
                return BadRequest(new { success = false, message = "تم سداد جميع الأشهر بالفعل" });

            var monthlyAmount = log.PlanPrice ?? 0;
            var monthsToCollect = dto.MonthsCount ?? 1;
            var remainingMonths = (log.RenewalCycleMonths.Value) - log.PaidMonths;
            if (monthsToCollect > remainingMonths)
                monthsToCollect = remainingMonths;

            var collectAmount = monthlyAmount * monthsToCollect;

            if (!log.UserId.HasValue)
                return BadRequest(new { success = false, message = "السجل غير مرتبط بمشغل" });

            var user = await _unitOfWork.Users.GetByIdAsync(log.UserId.Value);
            if (user == null)
                return NotFound(new { success = false, message = "المشغل غير موجود" });

            // ذمة المشغل
            var debtAccount = await _unitOfWork.Accounts.AsQueryable()
                .FirstOrDefaultAsync(a => a.Code.StartsWith("1160")
                    && a.Description == log.UserId.ToString()
                    && a.CompanyId == dto.CompanyId && a.IsActive);

            if (debtAccount == null)
                return BadRequest(new { success = false, message = "لا يوجد حساب ذمة لهذا المشغل" });

            // صندوق الشركة الرئيسي (11104)
            var mainCashBox = await _unitOfWork.Accounts.AsQueryable()
                .FirstOrDefaultAsync(a => a.Code == "11104" && a.IsActive
                    && a.CompanyId == dto.CompanyId);
            if (mainCashBox == null)
                return BadRequest(new { success = false, message = "لا يوجد حساب صندوق الشركة الرئيسي (11104)" });

            var description = $"تحصيل شهر {log.PaidMonths + 1}-{log.PaidMonths + monthsToCollect}/{log.RenewalCycleMonths} - {log.CustomerName} - {log.PlanName} - {collectAmount:N0}";

            var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
            {
                (mainCashBox.Id, collectAmount, 0, $"تحصيل شهر مكرر → صندوق الشركة الرئيسي"),
                (debtAccount.Id, 0, collectAmount, $"تسوية ذمة {user.FullName} - شهر {log.PaidMonths + 1}")
            };

            await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                _unitOfWork, dto.CompanyId, log.UserId.Value,
                description, JournalReferenceType.OperatorCreditCollection,
                log.UserId.ToString()!, lines);

            // تحديث السجل
            log.PaidMonths += monthsToCollect;
            if (log.PaidMonths >= log.RenewalCycleMonths)
            {
                log.PaymentStatus = "مسدد";
                log.CollectionType = "cash";
                log.NextRenewalDate = null;
            }
            else
            {
                // تحديث NextRenewalDate للشهر التالي
                if (log.ActivationDate.HasValue)
                    log.NextRenewalDate = log.ActivationDate.Value.AddMonths(log.PaidMonths + 1);
            }
            log.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.SubscriptionLogs.Update(log);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new {
                success = true,
                message = $"تم تحصيل {collectAmount:N0} ({monthsToCollect} شهر) بنجاح",
                paidMonths = log.PaidMonths,
                totalMonths = log.RenewalCycleMonths,
                isFullyPaid = log.PaidMonths >= log.RenewalCycleMonths,
                nextRenewalDate = log.NextRenewalDate
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تحصيل شهر مكرر");
            return StatusCode(500, new { success = false, message = "خطأ: " + ex.Message });
        }
    }

    // ==================== 5. تحصيل دين آجل ====================

    /// <summary>
    /// تحصيل دين آجل من مشغل (العميل دفع لاحقاً)
    /// </summary>
    [HttpPost("collect-credit")]
    public async Task<IActionResult> CollectCredit([FromBody] OperatorCreditCollectionDto dto)
    {
        try
        {
            var user = await _unitOfWork.Users.GetByIdAsync(dto.OperatorUserId);
            if (user == null)
                return NotFound(new { success = false, message = "المشغل غير موجود" });

            // ذمة المشغل (فرعي تحت 1160)
            var operatorDebtAccount = await _unitOfWork.Accounts.AsQueryable()
                .FirstOrDefaultAsync(a => a.Code.StartsWith("1160")
                    && a.Description == dto.OperatorUserId.ToString()
                    && a.CompanyId == dto.CompanyId && a.IsActive);

            if (operatorDebtAccount == null)
                return BadRequest(new { success = false, message = "لا يوجد حساب ذمة لهذا المشغل" });

            // صندوق الشركة الرئيسي (11104) - التحصيل يذهب مباشرة للشركة
            var mainCashBox = await _unitOfWork.Accounts.AsQueryable()
                .FirstOrDefaultAsync(a => a.Code == "11104" && a.IsActive
                    && a.CompanyId == dto.CompanyId);
            if (mainCashBox == null)
                return BadRequest(new { success = false, message = "لا يوجد حساب صندوق الشركة الرئيسي (11104)" });

            var description = $"تحصيل آجل - المشغل {user.FullName} - مبلغ {dto.Amount:N0}";
            if (!string.IsNullOrEmpty(dto.CustomerName))
                description += $" - العميل {dto.CustomerName}";

            var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
            {
                (mainCashBox.Id, dto.Amount, 0, $"تحصيل آجل → صندوق الشركة الرئيسي"),
                (operatorDebtAccount.Id, 0, dto.Amount, $"تسوية ذمة {user.FullName}")
            };

            await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                _unitOfWork, dto.CompanyId, dto.CollectedById ?? dto.OperatorUserId,
                description, JournalReferenceType.OperatorCreditCollection,
                dto.OperatorUserId.ToString(), lines);

            // تحديث حالة السجل إذا محدد — يصبح نقد بعد التسديد
            if (dto.SubscriptionLogId.HasValue)
            {
                var log = await _unitOfWork.SubscriptionLogs.GetByIdAsync(dto.SubscriptionLogId.Value);
                if (log != null)
                {
                    log.PaymentStatus = "مسدد";
                    log.CollectionType = "cash";
                    _unitOfWork.SubscriptionLogs.Update(log);
                }
            }

            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = $"تم تحصيل {dto.Amount:N0} بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تحصيل الآجل");
            return StatusCode(500, new { success = false, message = "خطأ: " + ex.Message });
        }
    }

    // ==================== 6. ربط بيانات FTTH بالمستخدم ====================

    /// <summary>
    /// حفظ/تحديث بيانات FTTH للمستخدم
    /// </summary>
    [HttpPost("link-ftth-account")]
    public async Task<IActionResult> LinkFtthAccount([FromBody] LinkFtthAccountDto dto)
    {
        try
        {
            var user = await _unitOfWork.Users.GetByIdAsync(dto.UserId);
            if (user == null)
                return NotFound(new { success = false, message = "المستخدم غير موجود" });

            user.FtthUsername = dto.FtthUsername;
            user.FtthPasswordEncrypted = dto.FtthPasswordEncrypted;
            _unitOfWork.Users.Update(user);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم ربط حساب FTTH بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في ربط حساب FTTH");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// جلب بيانات FTTH للمستخدم
    /// </summary>
    [HttpGet("ftth-credentials/{userId}")]
    public async Task<IActionResult> GetFtthCredentials(Guid userId)
    {
        try
        {
            var user = await _unitOfWork.Users.GetByIdAsync(userId);
            if (user == null)
                return NotFound(new { success = false, message = "المستخدم غير موجود" });

            return Ok(new
            {
                success = true,
                data = new
                {
                    hasFtthAccount = !string.IsNullOrEmpty(user.FtthUsername),
                    ftthUsername = user.FtthUsername,
                    ftthPasswordEncrypted = user.FtthPasswordEncrypted
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب بيانات FTTH");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 7. قائمة الوكلاء (للاستخدام في Flutter dropdown) ====================

    /// <summary>
    /// جلب قائمة الوكلاء النشطين (للدروبداون في واجهة التجديد)
    /// </summary>
    [HttpGet("agents-list")]
    public async Task<IActionResult> GetAgentsList([FromQuery] Guid? companyId = null)
    {
        try
        {
            var query = _unitOfWork.Agents.AsQueryable()
                .Where(a => a.Status == AgentStatus.Active);

            if (companyId.HasValue)
                query = query.Where(a => a.CompanyId == companyId);

            var agents = await query
                .Select(a => new { a.Id, a.Name, a.AgentCode, a.PhoneNumber })
                .OrderBy(a => a.Name)
                .ToListAsync();

            return Ok(new { success = true, data = agents });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب قائمة الوكلاء");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 7.5 قائمة الفنيين ====================

    /// <summary>
    /// جلب قائمة الفنيين النشطين (للدروبداون في واجهة التجديد)
    /// </summary>
    [HttpGet("technicians-list")]
    public async Task<IActionResult> GetTechniciansList([FromQuery] Guid? companyId = null)
    {
        try
        {
            var query = _unitOfWork.Users.AsQueryable()
                .Where(u => !u.IsDeleted && (u.Role == UserRole.Technician || u.Role == UserRole.TechnicalLeader));

            if (companyId.HasValue)
                query = query.Where(u => u.CompanyId == companyId);

            var technicians = await query
                .Select(u => new { u.Id, Name = u.FullName, u.Username, u.PhoneNumber })
                .OrderBy(u => u.Name)
                .ToListAsync();

            return Ok(new { success = true, data = technicians });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب قائمة الفنيين");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 8. قائمة المشغلين مع حالة الربط ====================

    /// <summary>
    /// جلب كل المستخدمين الذين لديهم صلاحية تشغيل FTTH مع حالة الربط
    /// </summary>
    [HttpGet("operators-linking")]
    public async Task<IActionResult> GetOperatorsLinking([FromQuery] Guid? companyId = null)
    {
        try
        {
            var query = _unitOfWork.Users.AsQueryable().Where(u => !u.IsDeleted);
            if (companyId.HasValue)
                query = query.Where(u => u.CompanyId == companyId);

            var users = await query
                .Select(u => new
                {
                    u.Id,
                    u.FullName,
                    u.Username,
                    u.PhoneNumber,
                    u.FtthUsername,
                    u.FtthPasswordEncrypted,
                    hasLink = u.FtthUsername != null && u.FtthUsername != "",
                    u.CompanyId
                })
                .OrderBy(u => u.FullName)
                .ToListAsync();

            return Ok(new { success = true, data = users });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب قائمة المشغلين");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 9. مزامنة عمليات FTTH دفعة واحدة ====================

    /// <summary>
    /// حفظ دفعة من عمليات FTTH في SubscriptionLog مع FtthTransactionId
    /// يُستدعى من Flutter عند الضغط على زر المزامنة
    /// يتجاهل العمليات المحفوظة مسبقاً (بناءً على FtthTransactionId)
    /// </summary>
    [HttpPost("sync-ftth-transactions")]
    public async Task<IActionResult> SyncFtthTransactions([FromBody] SyncFtthTransactionsDto dto)
    {
        try
        {
            if (dto.Transactions == null || dto.Transactions.Count == 0)
                return BadRequest(new { success = false, message = "لا توجد عمليات للمزامنة" });

            // جلب معرّفات العمليات المحفوظة مسبقاً
            var existingIds = await _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => l.FtthTransactionId != null && l.FtthTransactionId != "")
                .Select(l => l.FtthTransactionId!)
                .ToListAsync();
            var existingSet = new HashSet<string>(existingIds);

            // خريطة FtthUsername → UserId
            var userMap = await _unitOfWork.Users.AsQueryable()
                .Where(u => u.FtthUsername != null && u.FtthUsername != "" && !u.IsDeleted)
                .Select(u => new { u.Id, u.FtthUsername, u.FullName, u.CompanyId })
                .ToListAsync();
            var ftthToUser = userMap.ToDictionary(
                u => u.FtthUsername!.ToLower().Trim(),
                u => new { u.Id, u.FullName, u.CompanyId });

            int saved = 0, skipped = 0, failed = 0, updated = 0;
            var errors = new List<string>();

            foreach (var tx in dto.Transactions)
            {
                // تحديث السجلات الموجودة إذا كانت بياناتها ناقصة
                if (!string.IsNullOrEmpty(tx.FtthTransactionId) && existingSet.Contains(tx.FtthTransactionId))
                {
                    // تحقق إن كانت البيانات الجديدة أفضل
                    bool hasNewData = !string.IsNullOrEmpty(tx.CollectionType) || !string.IsNullOrEmpty(tx.CreatedBy);
                    if (hasNewData)
                    {
                        var existing = await _unitOfWork.SubscriptionLogs.AsQueryable()
                            .FirstOrDefaultAsync(l => l.FtthTransactionId == tx.FtthTransactionId && !l.IsDeleted);
                        if (existing != null)
                        {
                            bool needsUpdate = false;
                            if (string.IsNullOrEmpty(existing.CollectionType) && !string.IsNullOrEmpty(tx.CollectionType))
                            {
                                existing.CollectionType = tx.CollectionType;
                                needsUpdate = true;
                            }
                            if (string.IsNullOrEmpty(existing.ActivatedBy) && !string.IsNullOrEmpty(tx.CreatedBy))
                            {
                                existing.ActivatedBy = tx.CreatedBy;
                                var key = tx.CreatedBy.ToLower().Trim();
                                if (ftthToUser.TryGetValue(key, out var u))
                                {
                                    existing.UserId = u.Id;
                                    existing.CompanyId ??= u.CompanyId;
                                }
                                needsUpdate = true;
                            }
                            if (needsUpdate)
                            {
                                _unitOfWork.SubscriptionLogs.Update(existing);
                                updated++;
                                continue;
                            }
                        }
                    }
                    skipped++;
                    continue;
                }

                try
                {
                    // البحث عن المشغل
                    Guid? userId = null;
                    Guid? companyId = dto.CompanyId;
                    if (!string.IsNullOrEmpty(tx.CreatedBy))
                    {
                        var key = tx.CreatedBy.ToLower().Trim();
                        if (ftthToUser.TryGetValue(key, out var user))
                        {
                            userId = user.Id;
                            companyId ??= user.CompanyId;
                        }
                    }

                    var log = new SubscriptionLog
                    {
                        CustomerId = tx.CustomerId,
                        CustomerName = tx.CustomerName,
                        SubscriptionId = tx.SubscriptionId,
                        PlanName = tx.PlanName,
                        PlanPrice = tx.Amount != null ? Math.Abs(tx.Amount.Value) : null,
                        OperationType = tx.OperationType,
                        ActivatedBy = tx.CreatedBy,
                        ActivationDate = tx.OccuredAt,
                        ZoneId = tx.ZoneId,
                        DeviceUsername = tx.DeviceUsername,
                        FtthTransactionId = tx.FtthTransactionId,
                        UserId = userId,
                        CompanyId = companyId,
                        CollectionType = tx.CollectionType,
                        IsReconciled = true,
                        ReconciliationNotes = "مزامنة تلقائية من FTTH"
                    };

                    await _unitOfWork.SubscriptionLogs.AddAsync(log);
                    saved++;

                    if (!string.IsNullOrEmpty(tx.FtthTransactionId))
                        existingSet.Add(tx.FtthTransactionId);
                }
                catch (Exception ex)
                {
                    failed++;
                    errors.Add($"{tx.FtthTransactionId}: {ex.Message}");
                }
            }

            await _unitOfWork.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                message = $"تمت المزامنة: {saved} محفوظ، {updated} محدّث، {skipped} موجود مسبقاً، {failed} فشل",
                saved,
                updated,
                skipped,
                failed,
                errors = errors.Take(10).ToList()
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في مزامنة عمليات FTTH");
            return StatusCode(500, new { success = false, message = "خطأ: " + ex.Message });
        }
    }

    // ==================== 10. تسليم/تحصيل سريع من Tab1 ====================

    /// <summary>
    /// تسليم نقد سريع - يستخدم userId مباشرة
    /// </summary>
    [HttpPost("quick-deliver")]
    public async Task<IActionResult> QuickDeliver([FromBody] QuickDeliverDto dto)
    {
        try
        {
            var user = await _unitOfWork.Users.GetByIdAsync(dto.OperatorUserId);
            if (user == null)
                return NotFound(new { success = false, message = "المشغل غير موجود" });

            // صندوق المشغل
            var operatorAccount = await _unitOfWork.Accounts.AsQueryable()
                .FirstOrDefaultAsync(a => a.Code.StartsWith("1110")
                    && a.Description == dto.OperatorUserId.ToString()
                    && a.CompanyId == dto.CompanyId && a.IsActive);

            if (operatorAccount == null)
            {
                // إنشاء حساب صندوق للمشغل تلقائياً
                operatorAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(
                    _unitOfWork, "1110", dto.OperatorUserId, $"صندوق {user.FullName}", dto.CompanyId);
                await _unitOfWork.SaveChangesAsync();
            }

            // صندوق الشركة الرئيسي
            var mainCashAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, "1110", dto.CompanyId);
            if (mainCashAccount == null)
                return BadRequest(new { success = false, message = "حساب صندوق الشركة غير موجود" });

            if (!mainCashAccount.IsLeaf)
            {
                var companySub = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(
                    _unitOfWork, "1110", dto.CompanyId, "صندوق الشركة الرئيسي", dto.CompanyId);
                await _unitOfWork.SaveChangesAsync();
                mainCashAccount = companySub;
            }

            var description = $"تسليم نقد من {user.FullName} - مبلغ {dto.Amount:N0}";
            if (!string.IsNullOrEmpty(dto.Notes))
                description += $" - {dto.Notes}";

            var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
            {
                (mainCashAccount.Id, dto.Amount, 0, $"إيداع صندوق الشركة من {user.FullName}"),
                (operatorAccount.Id, 0, dto.Amount, $"تسليم نقد من صندوق {user.FullName}")
            };

            await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                _unitOfWork, dto.CompanyId, dto.OperatorUserId,
                description, JournalReferenceType.OperatorCashDelivery,
                dto.OperatorUserId.ToString(), lines);

            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = $"تم تسليم {dto.Amount:N0} بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في التسليم السريع");
            return StatusCode(500, new { success = false, message = "خطأ: " + ex.Message });
        }
    }

    /// <summary>
    /// تحصيل آجل سريع
    /// </summary>
    [HttpPost("quick-collect")]
    public async Task<IActionResult> QuickCollect([FromBody] QuickCollectDto dto)
    {
        try
        {
            var user = await _unitOfWork.Users.GetByIdAsync(dto.OperatorUserId);
            if (user == null)
                return NotFound(new { success = false, message = "المشغل غير موجود" });

            // ذمة المشغل
            var debtAccount = await _unitOfWork.Accounts.AsQueryable()
                .FirstOrDefaultAsync(a => a.Code.StartsWith("1160")
                    && a.Description == dto.OperatorUserId.ToString()
                    && a.CompanyId == dto.CompanyId && a.IsActive);

            if (debtAccount == null)
                return BadRequest(new { success = false, message = "لا يوجد حساب ذمة لهذا المشغل" });

            // صندوق الشركة الرئيسي (11104) - التحصيل يذهب مباشرة للشركة
            var mainCashBox = await _unitOfWork.Accounts.AsQueryable()
                .FirstOrDefaultAsync(a => a.Code == "11104" && a.IsActive
                    && a.CompanyId == dto.CompanyId);
            if (mainCashBox == null)
                return BadRequest(new { success = false, message = "لا يوجد حساب صندوق الشركة الرئيسي (11104)" });

            var description = $"تحصيل آجل - {user.FullName} - مبلغ {dto.Amount:N0}";
            if (!string.IsNullOrEmpty(dto.CustomerName))
                description += $" - العميل {dto.CustomerName}";
            if (!string.IsNullOrEmpty(dto.Notes))
                description += $" - {dto.Notes}";

            var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
            {
                (mainCashBox.Id, dto.Amount, 0, $"تحصيل آجل → صندوق الشركة الرئيسي"),
                (debtAccount.Id, 0, dto.Amount, $"تسوية ذمة {user.FullName}")
            };

            await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                _unitOfWork, dto.CompanyId, dto.OperatorUserId,
                description, JournalReferenceType.OperatorCreditCollection,
                dto.OperatorUserId.ToString(), lines);

            // تحديث حالة السجلات المحددة — تتحول من آجل إلى نقد بعد التسديد
            if (dto.SubscriptionLogIds != null && dto.SubscriptionLogIds.Any())
            {
                foreach (var logId in dto.SubscriptionLogIds)
                {
                    var log = await _unitOfWork.SubscriptionLogs.GetByIdAsync(logId);
                    if (log != null)
                    {
                        if (log.RenewalCycleMonths.HasValue && log.RenewalCycleMonths > 1)
                        {
                            // اشتراك مكرر — يُحسب كتحصيل شهر واحد فقط
                            log.PaidMonths += 1;
                            if (log.PaidMonths >= log.RenewalCycleMonths)
                            {
                                log.PaymentStatus = "مسدد";
                                log.CollectionType = "cash";
                                log.NextRenewalDate = null;
                            }
                            else if (log.ActivationDate.HasValue)
                            {
                                log.NextRenewalDate = log.ActivationDate.Value.AddMonths(log.PaidMonths + 1);
                            }
                        }
                        else
                        {
                            // اشتراك عادي (غير مكرر) — يُسدد بالكامل
                            log.PaymentStatus = "مسدد";
                            log.CollectionType = "cash";
                        }
                        log.UpdatedAt = DateTime.UtcNow;
                        _unitOfWork.SubscriptionLogs.Update(log);
                    }
                }
            }

            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = $"تم تحصيل {dto.Amount:N0} بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في التحصيل السريع");
            return StatusCode(500, new { success = false, message = "خطأ: " + ex.Message });
        }
    }

    // ==================== 12. لوحة مراقبة الأموال الموحدة ====================

    /// <summary>
    /// عرض أرصدة جميع الصناديق والذمم مع تفصيل لكل مشغل/وكيل/فني
    /// </summary>
    [HttpGet("funds-overview")]
    public async Task<IActionResult> GetFundsOverview([FromQuery] Guid? companyId = null)
    {
        try
        {
            // 1. جلب جميع الحسابات الفرعية المهمة
            var accountsQuery = _unitOfWork.Accounts.AsQueryable()
                .Where(a => a.IsActive && !a.IsDeleted);
            if (companyId.HasValue)
                accountsQuery = accountsQuery.Where(a => a.CompanyId == companyId);

            var allAccounts = await accountsQuery.ToListAsync();

            // ═══ دالة مساعدة: جلب الحساب الرئيسي وفرعياته ═══
            List<object> GetSubAccountDetails(string parentCode, string categoryName)
            {
                var parent = allAccounts.FirstOrDefault(a => a.Code == parentCode && a.ParentAccountId == null);
                if (parent == null) parent = allAccounts.FirstOrDefault(a => a.Code == parentCode);
                if (parent == null) return new List<object>();

                var subs = allAccounts
                    .Where(a => a.ParentAccountId == parent.Id && a.IsActive)
                    .Select(a => new
                    {
                        a.Id,
                        a.Code,
                        a.Name,
                        a.CurrentBalance,
                        PersonId = a.Description // يحتوي Guid الشخص
                    })
                    .OrderByDescending(a => a.CurrentBalance)
                    .ToList<object>();

                return subs;
            }

            decimal GetParentBalance(string code)
            {
                var parent = allAccounts.FirstOrDefault(a => a.Code == code && a.ParentAccountId == null)
                    ?? allAccounts.FirstOrDefault(a => a.Code == code);
                if (parent == null) return 0;
                var subs = allAccounts.Where(a => a.ParentAccountId == parent.Id && a.IsActive).ToList();
                return subs.Any() ? subs.Sum(a => a.CurrentBalance) : parent.CurrentBalance;
            }

            // 2. حسابات كل فئة
            var cashBoxTotal = GetParentBalance("1110");
            var cashBoxDetails = GetSubAccountDetails("1110", "صناديق المشغلين");

            var operatorDebtTotal = GetParentBalance("1160");
            var operatorDebtDetails = GetSubAccountDetails("1160", "ذمم المشغلين");

            var agentDebtTotal = GetParentBalance("1150");
            var agentDebtDetails = GetSubAccountDetails("1150", "ذمم الوكلاء");

            var techDebtTotal = GetParentBalance("1140");
            var techDebtDetails = GetSubAccountDetails("1140", "ذمم الفنيين");

            var electronicTotal = GetParentBalance("1170");
            var electronicDetails = GetSubAccountDetails("1170", "الدفع الإلكتروني");

            var renewalRevenue = GetParentBalance("4110");
            var purchaseRevenue = GetParentBalance("4120");

            // 3. إحصائيات العمليات (آخر 30 يوم)
            var thirtyDaysAgo = DateTime.UtcNow.AddDays(-30);
            var recentLogs = await _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => !l.IsDeleted && l.ActivationDate >= thirtyDaysAgo)
                .GroupBy(l => l.CollectionType)
                .Select(g => new { Type = g.Key, Count = g.Count(), Total = g.Sum(l => l.PlanPrice ?? 0) })
                .ToListAsync();

            var result = new
            {
                success = true,
                data = new
                {
                    // ═══ ملخص إجمالي ═══
                    summary = new
                    {
                        totalCash = cashBoxTotal,
                        totalOperatorDebt = operatorDebtTotal,
                        totalAgentDebt = agentDebtTotal,
                        totalTechDebt = techDebtTotal,
                        totalElectronic = electronicTotal,
                        totalRenewalRevenue = renewalRevenue,
                        totalPurchaseRevenue = purchaseRevenue,
                        grandTotal = cashBoxTotal + operatorDebtTotal + agentDebtTotal + techDebtTotal + electronicTotal
                    },
                    // ═══ تفاصيل كل فئة ═══
                    cashBoxes = new { total = cashBoxTotal, items = cashBoxDetails },
                    operatorDebts = new { total = operatorDebtTotal, items = operatorDebtDetails },
                    agentDebts = new { total = agentDebtTotal, items = agentDebtDetails },
                    technicianDebts = new { total = techDebtTotal, items = techDebtDetails },
                    electronic = new { total = electronicTotal, items = electronicDetails },
                    // ═══ إيرادات ═══
                    revenue = new { renewal = renewalRevenue, purchase = purchaseRevenue, total = renewalRevenue + purchaseRevenue },
                    // ═══ إحصائيات آخر 30 يوم ═══
                    recentActivity = recentLogs.Select(r => new { type = r.Type ?? "unknown", count = r.Count, total = r.Total })
                }
            };

            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب لوحة مراقبة الأموال");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== 13. إعادة حساب أرصدة الحسابات ====================

    /// <summary>
    /// إعادة حساب CurrentBalance لجميع الحسابات من سطور القيود المحاسبية
    /// يُستخدم لإصلاح أي تباين بين القيود والأرصدة
    /// </summary>
    [HttpPost("recalculate-balances")]
    [Authorize(Policy = "SuperAdmin")]
    public async Task<IActionResult> RecalculateAccountBalances([FromQuery] Guid? companyId = null)
    {
        try
        {
            var accountsQuery = _unitOfWork.Accounts.AsQueryable()
                .Where(a => a.IsActive && !a.IsDeleted);
            if (companyId.HasValue)
                accountsQuery = accountsQuery.Where(a => a.CompanyId == companyId);

            var accounts = await accountsQuery.ToListAsync();
            int fixedCount = 0;

            foreach (var account in accounts)
            {
                // حساب الرصيد من سطور القيود
                var lines = await _unitOfWork.JournalEntries.AsQueryable()
                    .Where(je => !je.IsDeleted)
                    .SelectMany(je => je.Lines)
                    .Where(jel => jel.AccountId == account.Id && !jel.IsDeleted)
                    .ToListAsync();

                decimal expectedBalance;
                if (account.AccountType == AccountType.Assets || account.AccountType == AccountType.Expenses)
                    expectedBalance = lines.Sum(l => l.DebitAmount - l.CreditAmount);
                else
                    expectedBalance = lines.Sum(l => l.CreditAmount - l.DebitAmount);

                if (account.CurrentBalance != expectedBalance)
                {
                    var oldBalance = account.CurrentBalance;
                    account.CurrentBalance = expectedBalance;
                    _unitOfWork.Accounts.Update(account);
                    fixedCount++;
                    _logger.LogInformation("تصحيح رصيد {Code} {Name}: {Old} → {New}",
                        account.Code, account.Name, oldBalance, expectedBalance);
                }
            }

            await _unitOfWork.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                message = $"تم إعادة حساب الأرصدة — {fixedCount} حساب تم تصحيحه من {accounts.Count}",
                totalAccounts = accounts.Count,
                fixedAccounts = fixedCount
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إعادة حساب الأرصدة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي: " + ex.Message });
        }
    }

    // ==================== 14. إعادة إنشاء القيود المفقودة ====================

    /// <summary>
    /// إعادة محاولة إنشاء القيود المحاسبية للسجلات التي فشل إنشاء قيدها
    /// </summary>
    [HttpPost("retry-missing-entries")]
    [Authorize(Policy = "SuperAdmin")]
    public async Task<IActionResult> RetryMissingEntries([FromQuery] Guid? companyId = null)
    {
        try
        {
            // جلب السجلات التي ليس لها قيد محاسبي
            var query = _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => !l.IsDeleted && l.JournalEntryId == null
                    && l.CompanyId.HasValue && l.UserId.HasValue
                    && l.PlanPrice.HasValue && l.PlanPrice > 0
                    && l.CollectionType != null);
            if (companyId.HasValue)
                query = query.Where(l => l.CompanyId == companyId);

            var orphanLogs = await query.ToListAsync();
            int successCount = 0;
            int failCount = 0;
            var errors = new List<string>();

            foreach (var log in orphanLogs)
            {
                try
                {
                    var dto = new FtthLogWithAccountingDto(
                        log.CustomerId, log.CustomerName, log.PhoneNumber,
                        log.SubscriptionId, log.PlanName, log.PlanPrice,
                        log.CommitmentPeriod, log.BundleId, log.CurrentStatus,
                        log.DeviceUsername, log.OperationType, log.ActivatedBy,
                        log.ActivationDate, log.ActivationTime, log.SessionId,
                        log.ZoneId, log.ZoneName, log.FbgInfo, log.FatInfo, log.FdtInfo,
                        log.WalletBalanceBefore, log.WalletBalanceAfter,
                        log.PartnerWalletBalanceBefore, log.CustomerWalletBalanceBefore,
                        log.Currency, log.PaymentMethod, log.PartnerName, log.PartnerId,
                        log.UserId, log.CompanyId, log.IsPrinted, log.IsWhatsAppSent,
                        log.SubscriptionNotes, log.StartDate, log.EndDate,
                        log.TechnicianName, log.PaymentStatus,
                        log.CollectionType, log.FtthTransactionId, log.ServiceRequestId,
                        log.LinkedAgentId, log.LinkedTechnicianId);

                    var jeId = await CreateAccountingEntry(log, dto);
                    if (jeId.HasValue)
                    {
                        log.JournalEntryId = jeId;
                        _unitOfWork.SubscriptionLogs.Update(log);
                        await _unitOfWork.SaveChangesAsync();
                        successCount++;
                    }
                    else
                    {
                        failCount++;
                        errors.Add($"Log {log.Id}: لم يتم إنشاء القيد");
                    }
                }
                catch (Exception ex)
                {
                    failCount++;
                    errors.Add($"Log {log.Id} ({log.CollectionType}): {ex.Message}");
                    _logger.LogWarning(ex, "فشل إعادة إنشاء القيد للسجل {LogId}", log.Id);
                }
            }

            return Ok(new
            {
                success = true,
                message = $"تم معالجة {orphanLogs.Count} سجل — {successCount} نجح، {failCount} فشل",
                total = orphanLogs.Count,
                succeeded = successCount,
                failed = failCount,
                errors = errors.Take(20)
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إعادة إنشاء القيود المفقودة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي: " + ex.Message });
        }
    }

    /// <summary>
    /// تصحيح السجلات القديمة التي لا تحتوي على CompanyId
    /// يقوم بإسناد CompanyId تلقائياً من جدول Users بناءً على UserId
    /// </summary>
    /// <summary>
    /// تصحيح السجلات التي لا تحتوي على UserId أو CollectionType
    /// يربط ActivatedBy (FTTH username) بـ User.FtthUsername لاستخراج UserId
    /// يضبط CollectionType = 'cash' افتراضياً للسجلات التي لا تحتوي عليه
    /// </summary>
    [HttpPost("fix-missing-userids")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> FixMissingUserIds([FromQuery] Guid? companyId = null)
    {
        try
        {
            var query = _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => !l.IsDeleted && (l.UserId == null || l.CollectionType == null || l.CollectionType == ""));

            if (companyId.HasValue)
                query = query.Where(l => l.CompanyId == companyId || l.CompanyId == null);

            var logsToFix = await query.ToListAsync();

            if (!logsToFix.Any())
                return Ok(new { success = true, message = "لا توجد سجلات تحتاج إصلاح", updated = 0 });

            // جلب جميع المستخدمين مع FtthUsername لمطابقة ActivatedBy
            var allUsers = await _unitOfWork.Users.AsQueryable()
                .Where(u => u.FtthUsername != null && u.FtthUsername != "")
                .Select(u => new { u.Id, u.FtthUsername, u.CompanyId })
                .ToListAsync();

            var ftthUsernameMap = allUsers
                .GroupBy(u => u.FtthUsername!.ToLower())
                .ToDictionary(g => g.Key, g => g.First());

            int updatedUserId = 0;
            int updatedCollectionType = 0;

            foreach (var log in logsToFix)
            {
                bool changed = false;

                // ربط UserId من ActivatedBy
                if (log.UserId == null && !string.IsNullOrEmpty(log.ActivatedBy))
                {
                    var key = log.ActivatedBy.ToLower();
                    if (ftthUsernameMap.TryGetValue(key, out var matchedUser))
                    {
                        log.UserId = matchedUser.Id;
                        // إسناد CompanyId أيضاً إذا كان فارغاً
                        if (!log.CompanyId.HasValue && matchedUser.CompanyId.HasValue)
                            log.CompanyId = matchedUser.CompanyId;
                        updatedUserId++;
                        changed = true;
                    }
                }

                // ضبط CollectionType الافتراضي
                if (string.IsNullOrEmpty(log.CollectionType))
                {
                    log.CollectionType = "cash";
                    updatedCollectionType++;
                    changed = true;
                }

                if (changed)
                    _unitOfWork.SubscriptionLogs.Update(log);
            }

            if (updatedUserId > 0 || updatedCollectionType > 0)
                await _unitOfWork.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                message = $"تم ربط {updatedUserId} مستخدم، وتصنيف {updatedCollectionType} سجل كنقد",
                total = logsToFix.Count,
                updatedUserId,
                updatedCollectionType
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تصحيح معرفات المستخدمين");
            return StatusCode(500, new { success = false, message = "خطأ داخلي: " + ex.Message });
        }
    }

    /// <summary>
    /// تعيين جميع السجلات ذات UserId=null لمستخدم محدد (للسجلات القديمة بلا ActivatedBy)
    /// </summary>
    [HttpPost("assign-unknown-records")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> AssignUnknownRecords([FromQuery] Guid targetUserId, [FromQuery] Guid? companyId = null)
    {
        try
        {
            var user = await _unitOfWork.Users.GetByIdAsync(targetUserId);
            if (user == null)
                return NotFound(new { success = false, message = "المستخدم غير موجود" });

            var query = _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => !l.IsDeleted && l.UserId == null);

            if (companyId.HasValue)
                query = query.Where(l => l.CompanyId == companyId || l.CompanyId == null);

            var logs = await query.ToListAsync();
            if (!logs.Any())
                return Ok(new { success = true, message = "لا توجد سجلات بدون مستخدم", updated = 0 });

            foreach (var log in logs)
            {
                log.UserId = targetUserId;
                log.ActivatedBy = user.FtthUsername ?? user.Username ?? log.ActivatedBy;
                if (!log.CompanyId.HasValue && user.CompanyId.HasValue)
                    log.CompanyId = user.CompanyId;
                _unitOfWork.SubscriptionLogs.Update(log);
            }

            await _unitOfWork.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                message = $"تم تعيين {logs.Count} سجل للمستخدم {user.FullName}",
                updated = logs.Count
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعيين السجلات");
            return StatusCode(500, new { success = false, message = "خطأ داخلي: " + ex.Message });
        }
    }

    [HttpPost("fix-orphan-records")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> FixOrphanRecords([FromQuery] Guid? targetCompanyId = null)
    {
        try
        {
            // جلب كل السجلات التي ليس لها CompanyId
            var orphanQuery = _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => !l.IsDeleted && l.CompanyId == null);

            var orphanLogs = await orphanQuery.ToListAsync();

            if (!orphanLogs.Any())
                return Ok(new { success = true, message = "لا توجد سجلات يتيمة", updated = 0 });

            // جلب كل المستخدمين لمطابقتهم
            var userIds = orphanLogs
                .Where(l => l.UserId.HasValue)
                .Select(l => l.UserId!.Value)
                .Distinct()
                .ToList();

            var users = await _unitOfWork.Users.AsQueryable()
                .Where(u => userIds.Contains(u.Id))
                .Select(u => new { u.Id, u.CompanyId })
                .ToListAsync();

            var userCompanyMap = users.ToDictionary(u => u.Id, u => u.CompanyId);

            int updatedCount = 0;
            int skippedCount = 0;

            foreach (var log in orphanLogs)
            {
                Guid? resolvedCompany = targetCompanyId;

                if (!resolvedCompany.HasValue && log.UserId.HasValue
                    && userCompanyMap.TryGetValue(log.UserId.Value, out var userCompany))
                {
                    resolvedCompany = userCompany;
                }

                if (resolvedCompany.HasValue)
                {
                    log.CompanyId = resolvedCompany;
                    _unitOfWork.SubscriptionLogs.Update(log);
                    updatedCount++;
                }
                else
                {
                    skippedCount++;
                }
            }

            if (updatedCount > 0)
                await _unitOfWork.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                message = $"تم تحديث {updatedCount} سجل، تخطي {skippedCount} (لم يُعثر على شركتهم)",
                total = orphanLogs.Count,
                updated = updatedCount,
                skipped = skippedCount
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تصحيح السجلات اليتيمة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي: " + ex.Message });
        }
    }

}

// ==================== DTOs ====================

public record FtthLogWithAccountingDto(
    // حقول SubscriptionLog الأساسية
    string? CustomerId,
    string? CustomerName,
    string? PhoneNumber,
    string? SubscriptionId,
    string? PlanName,
    decimal? PlanPrice,
    int? CommitmentPeriod,
    string? BundleId,
    string? CurrentStatus,
    string? DeviceUsername,
    string? OperationType,
    string? ActivatedBy,
    DateTime? ActivationDate,
    string? ActivationTime,
    string? SessionId,
    string? ZoneId,
    string? ZoneName,
    string? FbgInfo,
    string? FatInfo,
    string? FdtInfo,
    decimal? WalletBalanceBefore,
    decimal? WalletBalanceAfter,
    decimal? PartnerWalletBalanceBefore,
    decimal? CustomerWalletBalanceBefore,
    string? Currency,
    string? PaymentMethod,
    string? PartnerName,
    string? PartnerId,
    Guid? UserId,
    Guid? CompanyId,
    bool IsPrinted,
    bool IsWhatsAppSent,
    string? SubscriptionNotes,
    string? StartDate,
    string? EndDate,
    string? TechnicianName,
    string? PaymentStatus,
    // حقول التكامل الجديدة
    string? CollectionType,        // cash | credit | master | agent | technician
    string? FtthTransactionId,
    Guid? ServiceRequestId,
    Guid? LinkedAgentId,
    Guid? LinkedTechnicianId
);

public record OperatorCashDeliveryDto(
    Guid OperatorUserId,
    decimal Amount,
    Guid CompanyId,
    Guid? CashBoxId,
    Guid? DeliveredById,
    string? Notes
);

public record OperatorCreditCollectionDto(
    Guid OperatorUserId,
    decimal Amount,
    Guid CompanyId,
    long? SubscriptionLogId,
    string? CustomerName,
    Guid? CollectedById
);

public record LinkFtthAccountDto(
    Guid UserId,
    string FtthUsername,
    string? FtthPasswordEncrypted
);

public record SetRenewalCycleDto(
    long LogId,
    int? CycleMonths,
    int? PaidMonths = 0
);

public record CollectRenewalMonthDto(
    long LogId,
    Guid CompanyId,
    int? MonthsCount = 1
);

public record SyncFtthTransactionsDto(
    Guid? CompanyId,
    List<SyncFtthTransactionItem> Transactions
);

public record SyncFtthTransactionItem(
    string? FtthTransactionId,
    string? CustomerId,
    string? CustomerName,
    string? SubscriptionId,
    string? PlanName,
    decimal? Amount,
    string? OperationType,
    string? CreatedBy,
    DateTime? OccuredAt,
    string? ZoneId,
    string? DeviceUsername,
    string? CollectionType
);

public record QuickDeliverDto(
    Guid OperatorUserId,
    decimal Amount,
    Guid CompanyId,
    string? Notes
);

public record QuickCollectDto(
    Guid OperatorUserId,
    decimal Amount,
    Guid CompanyId,
    string? Notes,
    List<long>? SubscriptionLogIds = null,
    string? CustomerName = null
);
