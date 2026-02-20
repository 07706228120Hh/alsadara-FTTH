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
                
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, "1150", agent.Id, $"ذمة وكيل {agent.Name}", companyId);
                await _unitOfWork.SaveChangesAsync();
                description = $"{opType} {planName} - {customerName} - على وكيل {agent.Name} عبر {operatorName}";
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

        // جلب القيد المُنشأ
        var entry = await _unitOfWork.JournalEntries.AsQueryable()
            .Where(j => j.ReferenceType == JournalReferenceType.FtthSubscription
                && j.ReferenceId == log.Id.ToString()
                && j.CompanyId == companyId)
            .OrderByDescending(j => j.CreatedAt)
            .FirstOrDefaultAsync();

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
                        l.CustomerName,
                        l.PlanName,
                        l.PlanPrice,
                        l.OperationType,
                        l.CollectionType,
                        l.ActivationDate,
                        l.ZoneId,
                        l.JournalEntryId,
                        l.IsReconciled,
                        l.PaymentMethod,
                        l.TechnicianName
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
                query = query.Where(l => l.CompanyId == companyId);
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

            // تجميع حسب UserId
            var grouped = await query
                .GroupBy(l => l.UserId)
                .Select(g => new
                {
                    UserId = g.Key,
                    TotalCount = g.Count(),
                    TotalAmount = g.Sum(l => l.PlanPrice ?? 0),
                    CashAmount = g.Where(l => l.CollectionType == "cash").Sum(l => l.PlanPrice ?? 0),
                    CashCount = g.Count(l => l.CollectionType == "cash"),
                    CreditAmount = g.Where(l => l.CollectionType == "credit").Sum(l => l.PlanPrice ?? 0),
                    CreditCount = g.Count(l => l.CollectionType == "credit"),
                    MasterAmount = g.Where(l => l.CollectionType == "master").Sum(l => l.PlanPrice ?? 0),
                    MasterCount = g.Count(l => l.CollectionType == "master"),
                    AgentAmount = g.Where(l => l.CollectionType == "agent").Sum(l => l.PlanPrice ?? 0),
                    AgentCount = g.Count(l => l.CollectionType == "agent"),
                    UnclassifiedAmount = g.Where(l => l.CollectionType == null || l.CollectionType == "").Sum(l => l.PlanPrice ?? 0),
                    UnclassifiedCount = g.Count(l => l.CollectionType == null || l.CollectionType == "")
                })
                .ToListAsync();

            // جلب أسماء المستخدمين
            var userIds = grouped.Where(g => g.UserId.HasValue).Select(g => g.UserId!.Value).ToList();
            var users = await _unitOfWork.Users.AsQueryable()
                .Where(u => userIds.Contains(u.Id))
                .Select(u => new { u.Id, u.FullName, u.Username, u.FtthUsername })
                .ToListAsync();

            var result = grouped.Select(g =>
            {
                var user = g.UserId.HasValue ? users.FirstOrDefault(u => u.Id == g.UserId.Value) : null;
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
                    unclassifiedAmount = g.UnclassifiedAmount,
                    unclassifiedCount = g.UnclassifiedCount,
                    netOwed = g.CashAmount + g.CreditAmount // نقد + آجل (يجب تسليمها/تحصيلها)
                };
            }).OrderByDescending(x => x.totalAmount).ToList();

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
                    totalNetOwed = result.Sum(r => r.netOwed)
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

            // صندوق المشغل (حصّل الكاش)
            var operatorCashAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, "1110", dto.OperatorUserId,
                $"صندوق {user.FullName}", dto.CompanyId);
            await _unitOfWork.SaveChangesAsync();

            var description = $"تحصيل آجل - المشغل {user.FullName} - مبلغ {dto.Amount:N0}";
            if (!string.IsNullOrEmpty(dto.CustomerName))
                description += $" - العميل {dto.CustomerName}";

            var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>
            {
                (operatorCashAccount.Id, dto.Amount, 0, $"تحصيل نقدي → صندوق {user.FullName}"),
                (operatorDebtAccount.Id, 0, dto.Amount, $"تسوية ذمة {user.FullName}")
            };

            await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
                _unitOfWork, dto.CompanyId, dto.CollectedById ?? dto.OperatorUserId,
                description, JournalReferenceType.OperatorCreditCollection,
                dto.OperatorUserId.ToString(), lines);

            // تحديث حالة السجل إذا محدد
            if (dto.SubscriptionLogId.HasValue)
            {
                var log = await _unitOfWork.SubscriptionLogs.GetByIdAsync(dto.SubscriptionLogId.Value);
                if (log != null)
                {
                    log.PaymentStatus = "مسدد";
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
    string? CollectionType,        // cash | credit | master | agent
    string? FtthTransactionId,
    Guid? ServiceRequestId,
    Guid? LinkedAgentId
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
