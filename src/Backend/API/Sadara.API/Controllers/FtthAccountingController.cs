using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using Sadara.API.Constants;

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
                message = journalEntryId.HasValue
                    ? "تم حفظ السجل مع القيد المحاسبي بنجاح"
                    : "تم حفظ السجل بدون قيد محاسبي — تحقق من إعدادات الحسابات",
                logId = log.Id,
                journalEntryId,
                hasAccounting = journalEntryId.HasValue,
                accountingWarning = !journalEntryId.HasValue && dto.PlanPrice > 0
                    ? "لم يُنشأ قيد محاسبي — تأكد من وجود الحسابات (4110/4120) ومعلومات الشركة"
                    : null
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
    /// القيد الجديد:
    ///   مدين: حساب التحصيل (المبلغ المحصّل من العميل)
    ///   مدين: مصاريف عروض (الخصم الاختياري — إن وُجد)
    ///   دائن: رصيد الصفحة 11102 (صافي الشركة = السعر - خصم الشركة)
    ///   دائن: إيراد صيانة 4110 (رسوم الصيانة — إن وُجدت)
    ///   دائن: إيراد خصم الشركة 4120 (خصم الشركة غير الممرّر — إن لم يُفعَّل)
    /// </summary>
    private async Task<Guid?> CreateAccountingEntry(SubscriptionLog log, FtthLogWithAccountingDto dto)
    {
        var companyId = dto.CompanyId!.Value;
        var userId = dto.UserId!.Value;
        var collectionType = dto.CollectionType ?? "cash";

        // اسم المشغل: أولوية FullName من User > ActivatedBy
        var operatorUser = await _unitOfWork.Users.AsQueryable()
            .Where(u => u.Id == userId)
            .Select(u => new { u.FullName })
            .FirstOrDefaultAsync();
        var operatorName = operatorUser?.FullName ?? dto.ActivatedBy ?? "مشغل";
        var planName = dto.PlanName ?? "اشتراك";
        var customerName = dto.CustomerName ?? "عميل";
        var opType = dto.OperationType?.ToLower() == "purchase" ? "شراء" : "تجديد";

        // ═══ حساب المبالغ ═══
        var basePrice = dto.BasePrice ?? dto.PlanPrice ?? 0;
        var companyDiscount = dto.CompanyDiscount ?? 0;
        var manualDiscount = dto.ManualDiscount ?? 0;
        var maintenanceFee = dto.MaintenanceFee ?? 0;
        var systemDiscountEnabled = dto.SystemDiscountEnabled;

        // المبلغ المحصّل من العميل
        var collectedAmount = dto.PlanPrice ?? 0;

        // صافي الشركة = السعر الأساسي - خصم الشركة (ثابت دائماً)
        decimal netFromCompany;
        if (basePrice > 0)
        {
            netFromCompany = basePrice - companyDiscount;
        }
        else
        {
            if (systemDiscountEnabled)
                netFromCompany = collectedAmount + manualDiscount - maintenanceFee;
            else
                netFromCompany = collectedAmount + manualDiscount - maintenanceFee - companyDiscount;

            if (netFromCompany <= 0) netFromCompany = collectedAmount;
        }

        // ربح خصم الشركة = خصم الشركة عند عدم تفعيله
        var companyDiscountProfit = systemDiscountEnabled ? 0 : companyDiscount;

        // ═══ جلب الحسابات ═══
        // دائن: رصيد الصفحة الداخلي (11102)
        var pageBalanceAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.PageBalance, companyId);
        if (pageBalanceAccount == null)
        {
            _logger.LogWarning("حساب رصيد الصفحة 11102 غير موجود للشركة {CompanyId}", companyId);
            return null;
        }

        // دائن: إيراد صيانة (4110)
        Account? maintenanceRevenueAccount = null;
        if (maintenanceFee > 0)
        {
            maintenanceRevenueAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.MaintenanceRevenue, companyId);
            if (maintenanceRevenueAccount == null)
                _logger.LogWarning("حساب إيراد الصيانة 4110 غير موجود — سيتم تجاهل رسوم الصيانة في القيد");
        }

        // دائن: إيراد خصم الشركة (4120)
        Account? discountRevenueAccount = null;
        if (companyDiscountProfit > 0)
        {
            discountRevenueAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.CompanyDiscountRevenue, companyId);
            if (discountRevenueAccount == null)
                _logger.LogWarning("حساب إيراد خصم الشركة 4120 غير موجود — سيتم تجاهل ربح الخصم في القيد");
        }

        // مدين: مصاريف عروض (5110)
        Account? promotionExpenseAccount = null;
        if (manualDiscount > 0)
        {
            promotionExpenseAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.PromotionExpense, companyId);
            if (promotionExpenseAccount == null)
                _logger.LogWarning("حساب مصاريف العروض 5110 غير موجود — سيتم تجاهل الخصم الاختياري في القيد");
        }

        // ═══ تحديد حساب التحصيل (الطرف المدين الرئيسي) ═══
        Account debitAccount;
        string description;

        switch (collectionType.ToLower())
        {
            case "cash":
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.Cash, userId, $"صندوق {operatorName}", companyId);
                await _unitOfWork.SaveChangesAsync();
                description = $"{opType} {planName} - {customerName} - نقد عبر {operatorName}";
                break;

            case "credit":
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.OperatorReceivables, userId, $"ذمة {operatorName}", companyId);
                await _unitOfWork.SaveChangesAsync();
                description = $"{opType} {planName} - {customerName} - آجل على {operatorName}";
                break;

            case "master":
                debitAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.ElectronicPayment, companyId)
                    ?? throw new Exception("حساب صندوق الدفع الإلكتروني 1170 غير موجود");
                description = $"{opType} {planName} - {customerName} - ماستر (إلكتروني)";
                break;

            case "agent":
                if (!dto.LinkedAgentId.HasValue)
                    throw new Exception("يجب تحديد الوكيل عند اختيار نوع الدفع 'وكيل'");

                var agent = await _unitOfWork.Agents.GetByIdAsync(dto.LinkedAgentId.Value);
                if (agent == null)
                    throw new Exception("الوكيل غير موجود");

                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.AgentReceivables, agent.Id, agent.Name, companyId);
                await _unitOfWork.SaveChangesAsync();
                description = $"{opType} {planName} - {customerName} - على وكيل {agent.Name} عبر {operatorName}";

                // تحديث رصيد الوكيل + إنشاء AgentTransaction
                agent.TotalCharges += collectedAmount;
                agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
                _unitOfWork.Agents.Update(agent);

                var agentTx = new AgentTransaction
                {
                    AgentId = agent.Id,
                    Type = TransactionType.Charge,
                    Category = dto.OperationType?.ToLower() == "purchase"
                        ? TransactionCategory.NewSubscription
                        : TransactionCategory.RenewalSubscription,
                    Amount = collectedAmount,
                    BalanceAfter = agent.NetBalance,
                    Description = $"{opType} {planName} - {customerName}",
                    ReferenceNumber = log.Id.ToString(),
                    CreatedById = userId,
                    Notes = $"تفعيل عبر {operatorName}"
                };
                await _unitOfWork.AgentTransactions.AddAsync(agentTx);
                break;

            case "technician":
                if (!dto.LinkedTechnicianId.HasValue)
                    throw new Exception("يجب تحديد الفني عند اختيار نوع الدفع 'فني'");

                var tech = await _unitOfWork.Users.GetByIdAsync(dto.LinkedTechnicianId.Value);
                if (tech == null)
                    throw new Exception("الفني غير موجود");

                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.TechnicianReceivables, tech.Id, tech.FullName, companyId);
                await _unitOfWork.SaveChangesAsync();
                description = $"{opType} {planName} - {customerName} - على فني {tech.FullName} عبر {operatorName}";

                // تحديث رصيد الفني + إنشاء TechnicianTransaction
                tech.TechTotalCharges += collectedAmount;
                tech.TechNetBalance = tech.TechTotalPayments - tech.TechTotalCharges;
                _unitOfWork.Users.Update(tech);

                var techTx = new TechnicianTransaction
                {
                    TechnicianId = tech.Id,
                    Type = TechnicianTransactionType.Charge,
                    Category = TechnicianTransactionCategory.Subscription,
                    Amount = collectedAmount,
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
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.Cash, userId, $"صندوق {operatorName}", companyId);
                await _unitOfWork.SaveChangesAsync();
                description = $"{opType} {planName} - {customerName} - عبر {operatorName}";
                break;
        }

        // ═══ بناء سطور القيد ═══
        var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>();

        // مدين: حساب التحصيل (المبلغ المحصّل من العميل)
        if (collectedAmount > 0)
            lines.Add((debitAccount.Id, collectedAmount, 0, $"{debitAccount.Name} - {opType} {planName}"));

        // مدين: مصاريف عروض (الخصم الاختياري)
        if (manualDiscount > 0 && promotionExpenseAccount != null)
            lines.Add((promotionExpenseAccount.Id, manualDiscount, 0, $"خصم اختياري - {customerName}"));

        // دائن: رصيد الصفحة (صافي الشركة)
        if (netFromCompany > 0)
            lines.Add((pageBalanceAccount.Id, 0, netFromCompany, $"خصم من رصيد الصفحة - {opType} {planName}"));

        // دائن: إيراد صيانة
        if (maintenanceFee > 0 && maintenanceRevenueAccount != null)
            lines.Add((maintenanceRevenueAccount.Id, 0, maintenanceFee, $"إيراد صيانة - {customerName}"));

        // دائن: إيراد خصم الشركة (ربح عدم تمرير الخصم)
        if (companyDiscountProfit > 0 && discountRevenueAccount != null)
            lines.Add((discountRevenueAccount.Id, 0, companyDiscountProfit, $"إيراد خصم الشركة - {customerName}"));

        if (lines.Count < 2)
        {
            _logger.LogWarning("لا توجد سطور كافية للقيد المحاسبي — تم التخطي");
            return null;
        }

        // إنشاء القيد
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
        [FromQuery] Guid? companyId = null,
        [FromQuery] bool isTechnician = false)
    {
        try
        {
            var user = await _unitOfWork.Users.GetByIdAsync(userId);
            if (user == null)
                return NotFound(new { success = false, message = "المستخدم غير موجود" });

            var query = _unitOfWork.SubscriptionLogs.AsQueryable();
            if (isTechnician)
                query = query.Where(l => l.LinkedTechnicianId == userId && l.CollectionType == "technician");
            else
                query = query.Where(l => l.UserId == userId);

            if (companyId.HasValue)
                // تضمين السجلات القديمة التي لم يُحدد لها CompanyId (للتوافق مع البيانات السابقة)
                query = query.Where(l => l.CompanyId == companyId || l.CompanyId == null);
            if (from.HasValue)
            {
                var fromUtc = DateTime.SpecifyKind(from.Value.Date.AddHours(-3), DateTimeKind.Utc);
                query = query.Where(l => l.ActivationDate >= fromUtc);
            }
            if (to.HasValue)
            {
                var toUtc = DateTime.SpecifyKind(to.Value.Date.AddDays(1).AddHours(-3), DateTimeKind.Utc);
                query = query.Where(l => l.ActivationDate <= toUtc);
            }

            // فلترة خدمات الإنترنت فقط (استبعاد IPTV, Parental Control, VOIP, VOD, etc.)
            query = query.Where(l => l.PlanName != null && l.PlanName.ToUpper().Contains("FIBER"));

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
                    .FirstOrDefaultAsync(a => a.Code.StartsWith(AccountCodes.Cash)
                        && a.Description == userId.ToString()
                        && a.CompanyId == companyId);

                // البحث عن ذمة المشغل
                var operatorCreditAccount = await _unitOfWork.Accounts.AsQueryable()
                    .FirstOrDefaultAsync(a => a.Code.StartsWith(AccountCodes.OperatorReceivables)
                        && a.Description == userId.ToString()
                        && a.CompanyId == companyId);

                // النقد المسلّم = المبالغ الدائنة في صندوق المشغل — من أي نوع قيد
                if (operatorCashAccount != null)
                {
                    deliveredCash = await _unitOfWork.JournalEntryLines.AsQueryable()
                        .Where(l => l.AccountId == operatorCashAccount.Id && l.CreditAmount > 0 && !l.IsDeleted)
                        .Join(_unitOfWork.JournalEntries.AsQueryable()
                            .Where(j => j.Status != JournalEntryStatus.Voided && !j.IsDeleted),
                            l => l.JournalEntryId, j => j.Id, (l, j) => l.CreditAmount)
                        .SumAsync(x => x);
                }

                // الآجل المحصّل = المبالغ الدائنة في ذمة المشغل — من أي نوع قيد
                if (operatorCreditAccount != null)
                {
                    collectedCredit = await _unitOfWork.JournalEntryLines.AsQueryable()
                        .Where(l => l.AccountId == operatorCreditAccount.Id && l.CreditAmount > 0 && !l.IsDeleted)
                        .Join(_unitOfWork.JournalEntries.AsQueryable()
                            .Where(j => j.Status != JournalEntryStatus.Voided && !j.IsDeleted),
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
                        l.PaidMonths,
                        l.FtthTransactionId,
                        // حقول محاسبية
                        l.BasePrice,
                        l.CompanyDiscount,
                        l.ManualDiscount,
                        l.MaintenanceFee,
                        l.SystemDiscountEnabled,
                        PageDeduction = (l.BasePrice ?? 0) > 0
                            ? (l.BasePrice ?? 0) - (l.CompanyDiscount ?? 0)
                            : l.SystemDiscountEnabled
                                ? (l.PlanPrice ?? 0) + (l.ManualDiscount ?? 0) - (l.MaintenanceFee ?? 0)
                                : (l.PlanPrice ?? 0) + (l.ManualDiscount ?? 0) - (l.MaintenanceFee ?? 0) - (l.CompanyDiscount ?? 0),
                        Revenue = (l.MaintenanceFee ?? 0) + (l.SystemDiscountEnabled ? 0 : (l.CompanyDiscount ?? 0)),
                        Expense = l.ManualDiscount ?? 0,
                        CollectedAmount = (l.PlanPrice ?? 0) + (l.MaintenanceFee ?? 0) + (l.SystemDiscountEnabled ? 0 : (l.CompanyDiscount ?? 0))
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
                var fromUtc = DateTime.SpecifyKind(from.Value.Date.AddHours(-3), DateTimeKind.Utc);
                query = query.Where(l => l.ActivationDate >= fromUtc);
            }
            if (to.HasValue)
            {
                var toUtc = DateTime.SpecifyKind(to.Value.Date.AddDays(1).AddHours(-3), DateTimeKind.Utc);
                query = query.Where(l => l.ActivationDate <= toUtc);
            }

            // فلترة خدمات الإنترنت فقط (استبعاد IPTV, Parental Control, VOIP, VOD, etc.)
            query = query.Where(l => l.PlanName != null && l.PlanName.ToUpper().Contains("FIBER"));

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
                    ReconciledCount = g.Count(l => l.IsReconciled),
                    // حقول محاسبية: المستقطع والإيرادات والمصاريف
                    TotalMaintenanceFee = g.Sum(l => l.MaintenanceFee ?? 0),
                    TotalManualDiscount = g.Sum(l => l.ManualDiscount ?? 0),
                    TotalCompanyDiscountProfit = g.Where(l => !l.SystemDiscountEnabled).Sum(l => l.CompanyDiscount ?? 0),
                    // المستقطع من الصفحة = BasePrice - CompanyDiscount (أو PlanPrice + ManualDiscount - MaintenanceFee إذا لم يوجد BasePrice)
                    PageDeduction = g.Sum(l =>
                        (l.BasePrice ?? 0) > 0
                            ? (l.BasePrice ?? 0) - (l.CompanyDiscount ?? 0)
                            : l.SystemDiscountEnabled
                                ? (l.PlanPrice ?? 0) + (l.ManualDiscount ?? 0) - (l.MaintenanceFee ?? 0)
                                : (l.PlanPrice ?? 0) + (l.ManualDiscount ?? 0) - (l.MaintenanceFee ?? 0) - (l.CompanyDiscount ?? 0)
                    )
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
                .Where(a => a.Code.StartsWith(AccountCodes.Cash) && a.Description != null
                    && userIdStrings.Contains(a.Description)
                    && (!companyId.HasValue || a.CompanyId == companyId))
                .Select(a => new { a.Id, a.Description })
                .ToListAsync();

            // حسابات ذمم المشغلين (1160)
            var operatorCreditAccounts = await _unitOfWork.Accounts.AsQueryable()
                .Where(a => a.Code.StartsWith(AccountCodes.OperatorReceivables) && a.Description != null
                    && userIdStrings.Contains(a.Description)
                    && (!companyId.HasValue || a.CompanyId == companyId))
                .Select(a => new { a.Id, a.Description })
                .ToListAsync();

            // ── النقد المسلّم + الآجل المحصّل: من أي قيد محاسبي (يدوي أو تلقائي) ──
            // المبدأ: CreditAmount في حساب المشغل/الفني = تسديد، بغض النظر عن ReferenceType
            var jeDateQuery = _unitOfWork.JournalEntries.AsQueryable()
                .Where(j => j.Status != JournalEntryStatus.Voided && !j.IsDeleted);
            if (from.HasValue)
            {
                var fromUtcJe = DateTime.SpecifyKind(from.Value.Date.AddHours(-3), DateTimeKind.Utc);
                jeDateQuery = jeDateQuery.Where(j => j.EntryDate >= fromUtcJe);
            }
            if (to.HasValue)
            {
                var toUtcJe = DateTime.SpecifyKind(to.Value.Date.AddDays(1).AddHours(-3), DateTimeKind.Utc);
                jeDateQuery = jeDateQuery.Where(j => j.EntryDate <= toUtcJe);
            }

            // النقد المسلّم: CreditAmount في صندوق المشغل (1110xx) — من أي نوع قيد
            var cashAccountIds = operatorCashAccounts.Select(a => a.Id).ToList();
            var deliveredByAccount = cashAccountIds.Any()
                ? await _unitOfWork.JournalEntryLines.AsQueryable()
                    .Where(l => cashAccountIds.Contains(l.AccountId) && l.CreditAmount > 0 && !l.IsDeleted)
                    .Join(jeDateQuery, l => l.JournalEntryId, j => j.Id,
                        (l, j) => new { l.AccountId, l.CreditAmount })
                    .GroupBy(x => x.AccountId)
                    .Select(g => new { AccountId = g.Key, Total = g.Sum(x => x.CreditAmount) })
                    .ToListAsync()
                : new List<dynamic>().Select(x => new { AccountId = Guid.Empty, Total = 0m }).ToList();

            // الآجل المحصّل: CreditAmount في ذمة المشغل (1160xx) — من أي نوع قيد
            var creditAccountIds = operatorCreditAccounts.Select(a => a.Id).ToList();
            var collectedByAccount = creditAccountIds.Any()
                ? await _unitOfWork.JournalEntryLines.AsQueryable()
                    .Where(l => creditAccountIds.Contains(l.AccountId) && l.CreditAmount > 0 && !l.IsDeleted)
                    .Join(jeDateQuery, l => l.JournalEntryId, j => j.Id,
                        (l, j) => new { l.AccountId, l.CreditAmount })
                    .GroupBy(x => x.AccountId)
                    .Select(g => new { AccountId = g.Key, Total = g.Sum(x => x.CreditAmount) })
                    .ToListAsync()
                : new List<dynamic>().Select(x => new { AccountId = Guid.Empty, Total = 0m }).ToList();

            // ── ذمم الفنيين للمشغلين: حسابات 1140xx المرتبطة بنفس userId ──
            var operatorTechDebtAccounts = await _unitOfWork.Accounts.AsQueryable()
                .Where(a => a.Code.StartsWith(AccountCodes.TechnicianReceivables) && a.Description != null
                    && userIdStrings.Contains(a.Description)
                    && (!companyId.HasValue || a.CompanyId == companyId))
                .Select(a => new { a.Id, a.Description })
                .ToListAsync();

            var opTechAccIds = operatorTechDebtAccounts.Select(a => a.Id).ToList();
            // رصيد ذمة الفني = Debit - Credit (حسب فلتر التاريخ المحدد)
            var operatorTechDebtByAccount = opTechAccIds.Any()
                ? await _unitOfWork.JournalEntryLines.AsQueryable()
                    .Where(l => opTechAccIds.Contains(l.AccountId) && !l.IsDeleted)
                    .Join(jeDateQuery, l => l.JournalEntryId, j => j.Id,
                        (l, j) => new { l.AccountId, l.DebitAmount, l.CreditAmount })
                    .GroupBy(x => x.AccountId)
                    .Select(g => new { AccountId = g.Key, Balance = g.Sum(x => x.DebitAmount) - g.Sum(x => x.CreditAmount) })
                    .ToListAsync()
                : new List<object>().Select(x => new { AccountId = Guid.Empty, Balance = 0m }).ToList();

            // ── إيرادات الفنيين: الأجور فقط (صيانة + تنصيب + توصيل + أخرى) — بدون مبالغ الاشتراكات ──
            var revenueCategories = new[] {
                TechnicianTransactionCategory.Maintenance,      // أجور الصيانة
                TechnicianTransactionCategory.InstallationFee,  // أجور التنصيب
                TechnicianTransactionCategory.DeliveryFee,      // أجور التوصيل
                TechnicianTransactionCategory.OtherFee           // أجور أخرى
            };
            var techRevenueQuery = _unitOfWork.TechnicianTransactions.AsQueryable()
                .Where(t => t.Type == TechnicianTransactionType.Charge && revenueCategories.Contains(t.Category) && !t.IsDeleted);
            if (from.HasValue)
            {
                var fromUtcDf = DateTime.SpecifyKind(from.Value.Date.AddHours(-3), DateTimeKind.Utc);
                techRevenueQuery = techRevenueQuery.Where(t => t.CreatedAt >= fromUtcDf);
            }
            if (to.HasValue)
            {
                var toUtcDf = DateTime.SpecifyKind(to.Value.Date.AddDays(1).AddHours(-3), DateTimeKind.Utc);
                techRevenueQuery = techRevenueQuery.Where(t => t.CreatedAt <= toUtcDf);
            }
            var techRevenueByUser = await techRevenueQuery
                .GroupBy(t => t.TechnicianId)
                .Select(g => new { TechnicianId = g.Key, Total = g.Sum(t => t.Amount) })
                .ToListAsync();

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

                // ذمم فني: إذا كان المشغل عنده حساب فني (1140xx) نحسب رصيده
                var techDebtAccId = g.UserId.HasValue
                    ? operatorTechDebtAccounts.FirstOrDefault(a => a.Description == g.UserId.Value.ToString())?.Id
                    : (Guid?)null;
                var techDebtTotal = techDebtAccId.HasValue
                    ? operatorTechDebtByAccount.FirstOrDefault(d => d.AccountId == techDebtAccId.Value)?.Balance ?? 0m
                    : 0m;

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
                    techDebt = techDebtTotal,
                    // أنواع العمليات
                    purchaseCount = g.PurchaseCount,
                    purchaseAmount = g.PurchaseAmount,
                    renewalCount = g.RenewalCount,
                    renewalAmount = g.RenewalAmount,
                    changeCount = g.ChangeCount,
                    changeAmount = g.ChangeAmount,
                    scheduleCount = g.ScheduleCount,
                    scheduleAmount = g.ScheduleAmount,
                    reconciledCount = g.ReconciledCount,
                    // محاسبية
                    pageDeduction = g.PageDeduction,
                    maintenanceFee = g.TotalMaintenanceFee,
                    manualDiscount = g.TotalManualDiscount,
                    companyDiscountProfit = g.TotalCompanyDiscountProfit,
                    techRevenue = 0m,
                    revenue = g.TotalMaintenanceFee + g.TotalCompanyDiscountProfit,
                    expense = g.TotalManualDiscount
                };
            }).OrderByDescending(x => x.totalAmount).ToList();

            // ── صفوف الفنيين: تجميع المبالغ المحصّلة بواسطة الفنيين ──
            var techRows = await query
                .Where(l => l.LinkedTechnicianId.HasValue && l.CollectionType == "technician")
                .GroupBy(l => l.LinkedTechnicianId)
                .Select(g => new
                {
                    TechId = g.Key,
                    TotalCount = g.Count(),
                    TotalAmount = g.Sum(l => l.PlanPrice ?? 0),
                    PurchaseCount = g.Count(l => l.OperationType != null && (l.OperationType.ToUpper().Contains("PURCHASE") || l.OperationType.ToUpper().Contains("SUBSCRIBE"))),
                    PurchaseAmount = g.Where(l => l.OperationType != null && (l.OperationType.ToUpper().Contains("PURCHASE") || l.OperationType.ToUpper().Contains("SUBSCRIBE"))).Sum(l => l.PlanPrice ?? 0),
                    RenewalCount = g.Count(l => l.OperationType != null && l.OperationType.ToUpper().Contains("RENEW")),
                    RenewalAmount = g.Where(l => l.OperationType != null && l.OperationType.ToUpper().Contains("RENEW")).Sum(l => l.PlanPrice ?? 0),
                    ReconciledCount = g.Count(l => l.IsReconciled)
                })
                .ToListAsync();

            var techUserIds = techRows.Where(t => t.TechId.HasValue).Select(t => t.TechId!.Value).ToList();
            var techUsers = techUserIds.Any()
                ? await _unitOfWork.Users.AsQueryable()
                    .Where(u => techUserIds.Contains(u.Id))
                    .Select(u => new { u.Id, u.FullName, Username = (string?)u.Username })
                    .ToListAsync()
                : new List<object>().Select(x => new { Id = Guid.Empty, FullName = "", Username = (string?)null }).ToList();

            // ── حساب تسديدات الفنيين من القيود المحاسبية (CreditAmount في حساب 1140xx) ──
            var techAccIds = techUserIds.Select(id => id.ToString()).ToList();
            var techAccounts = techAccIds.Any()
                ? await _unitOfWork.Accounts.AsQueryable()
                    .Where(a => a.Code.StartsWith(AccountCodes.TechnicianReceivables) && a.Description != null
                        && techAccIds.Contains(a.Description)
                        && (!companyId.HasValue || a.CompanyId == companyId))
                    .Select(a => new { a.Id, a.Description })
                    .ToListAsync()
                : new List<object>().Select(x => new { Id = Guid.Empty, Description = "" }).ToList();

            var techAccountIds = techAccounts.Select(a => a.Id).ToList();
            // جلب CreditAmount من القيود المرحّلة (تسديدات) مع فلتر التاريخ
            var techJeQuery = _unitOfWork.JournalEntries.AsQueryable()
                .Where(j => j.Status != JournalEntryStatus.Voided && !j.IsDeleted);
            if (from.HasValue)
            {
                var fromUtcTech = DateTime.SpecifyKind(from.Value.Date.AddHours(-3), DateTimeKind.Utc);
                techJeQuery = techJeQuery.Where(j => j.EntryDate >= fromUtcTech);
            }
            if (to.HasValue)
            {
                var toUtcTech = DateTime.SpecifyKind(to.Value.Date.AddDays(1).AddHours(-3), DateTimeKind.Utc);
                techJeQuery = techJeQuery.Where(j => j.EntryDate <= toUtcTech);
            }
            var techPayments = techAccountIds.Any()
                ? await _unitOfWork.JournalEntryLines.AsQueryable()
                    .Where(l => techAccountIds.Contains(l.AccountId) && l.CreditAmount > 0 && !l.IsDeleted)
                    .Join(techJeQuery, l => l.JournalEntryId, j => j.Id,
                        (l, j) => new { l.AccountId, l.CreditAmount })
                    .GroupBy(x => x.AccountId)
                    .Select(g => new { AccountId = g.Key, TotalPayments = g.Sum(x => x.CreditAmount) })
                    .ToListAsync()
                : new List<object>().Select(x => new { AccountId = Guid.Empty, TotalPayments = 0m }).ToList();

            var technicianRows = techRows.Select(t =>
            {
                var techUser = t.TechId.HasValue ? techUsers.FirstOrDefault(u => u.Id == t.TechId.Value) : null;
                var techAccId = t.TechId.HasValue
                    ? techAccounts.FirstOrDefault(a => a.Description == t.TechId.Value.ToString())?.Id
                    : (Guid?)null;
                var paid = techAccId.HasValue
                    ? techPayments.FirstOrDefault(p => p.AccountId == techAccId.Value)?.TotalPayments ?? 0m
                    : 0m;
                return new
                {
                    userId = t.TechId,
                    operatorName = techUser?.FullName ?? "فني غير معروف",
                    username = techUser?.Username,
                    ftthUsername = (string?)null,
                    isTechnician = true,
                    totalCount = t.TotalCount,
                    totalAmount = t.TotalAmount,
                    cashAmount = 0m,
                    cashCount = 0,
                    creditAmount = 0m,
                    creditCount = 0,
                    masterAmount = 0m,
                    masterCount = 0,
                    agentAmount = 0m,
                    agentCount = 0,
                    technicianAmount = t.TotalAmount,
                    technicianCount = t.TotalCount,
                    unclassifiedAmount = 0m,
                    unclassifiedCount = 0,
                    deliveredCash = paid,
                    collectedCredit = 0m,
                    netOwed = t.TotalAmount - paid,
                    purchaseCount = t.PurchaseCount,
                    purchaseAmount = t.PurchaseAmount,
                    renewalCount = t.RenewalCount,
                    renewalAmount = t.RenewalAmount,
                    changeCount = 0,
                    changeAmount = 0m,
                    scheduleCount = 0,
                    scheduleAmount = 0m,
                    reconciledCount = t.ReconciledCount,
                    techRevenue = t.TechId.HasValue
                        ? techRevenueByUser.FirstOrDefault(d => d.TechnicianId == t.TechId.Value)?.Total ?? 0m
                        : 0m,
                    revenue = t.TechId.HasValue
                        ? techRevenueByUser.FirstOrDefault(d => d.TechnicianId == t.TechId.Value)?.Total ?? 0m
                        : 0m,
                    expense = 0m
                };
            }).OrderByDescending(x => x.totalAmount).ToList();

            // دمج الصفوف: المشغلون أولاً ثم الفنيون
            var allRows = result.Cast<object>().Concat(technicianRows.Cast<object>()).ToList();

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
                data = allRows,
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
                    // محاسبية
                    totalPageDeduction = result.Sum(r => r.pageDeduction),
                    totalRevenue = result.Sum(r => r.revenue),
                    totalExpense = result.Sum(r => r.expense),
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
                .FirstOrDefaultAsync(a => a.Code.StartsWith(AccountCodes.Cash)
                    && a.Description == dto.OperatorUserId.ToString()
                    && a.CompanyId == dto.CompanyId && a.IsActive);

            if (operatorAccount == null)
                return BadRequest(new { success = false, message = "لا يوجد حساب صندوق لهذا المشغل" });

            // صندوق الشركة
            var companyCashAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.Cash, dto.CompanyId);
            if (companyCashAccount == null)
                return BadRequest(new { success = false, message = "حساب صندوق الشركة غير موجود" });

            // إذا كان صندوق الشركة هو نفسه (ليس فرعي) نستخدمه مباشرة
            // لكن إذا 1110 أصبح أب (isLeaf=false) نحتاج نبحث عن فرعي للشركة
            if (!companyCashAccount.IsLeaf)
            {
                var companySubCash = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.Cash, dto.CompanyId, "صندوق الشركة الرئيسي", dto.CompanyId);
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

    // ==================== 4.6.1 تعديل بيانات سجل اشتراك ====================

    /// <summary>
    /// تعديل بيانات سجل اشتراك FTTH (نوع التحصيل، الفني، الملاحظات)
    /// </summary>
    [HttpPut("update-subscription-log/{id}")]
    public async Task<IActionResult> UpdateSubscriptionLog(long id, [FromBody] JsonElement body)
    {
        try
        {
            var log = await _unitOfWork.SubscriptionLogs.GetByIdAsync(id);
            if (log == null)
                return NotFound(new { success = false, message = "السجل غير موجود" });

            UpdateFtthLogRequest? request;
            try
            {
                request = System.Text.Json.JsonSerializer.Deserialize<UpdateFtthLogRequest>(body.GetRawText(),
                    new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            }
            catch
            {
                return BadRequest(new { success = false, message = "بيانات غير صالحة" });
            }
            if (request == null)
                return BadRequest(new { success = false, message = "الطلب فارغ" });

            // بيانات العميل
            if (request.CustomerName != null) log.CustomerName = request.CustomerName;
            if (request.PhoneNumber != null) log.PhoneNumber = request.PhoneNumber;
            // بيانات الاشتراك
            if (request.PlanName != null) log.PlanName = request.PlanName;
            if (request.PlanPrice.HasValue) log.PlanPrice = request.PlanPrice.Value;
            if (request.CommitmentPeriod != null) log.CommitmentPeriod = request.CommitmentPeriod;
            if (request.OperationType != null) log.OperationType = request.OperationType;
            if (request.ActivatedBy != null) log.ActivatedBy = request.ActivatedBy;
            if (request.ActivationDate.HasValue)
                log.ActivationDate = DateTime.SpecifyKind(request.ActivationDate.Value.Date.AddHours(12 - 3), DateTimeKind.Utc);
            if (request.ZoneId != null) log.ZoneId = request.ZoneId;
            // التحصيل والربط
            _logger.LogInformation("📋 Update {Id}: CollType={CT}, HasTech={HT}, TechId={TI}, HasAgent={HA}, AgentId={AI}",
                id, request.CollectionType, request.HasLinkedTechnicianId, request.LinkedTechnicianId, request.HasLinkedAgentId, request.LinkedAgentId);
            if (request.CollectionType != null) log.CollectionType = request.CollectionType;
            if (request.HasLinkedTechnicianId) log.LinkedTechnicianId = request.LinkedTechnicianId;
            if (request.HasLinkedAgentId) log.LinkedAgentId = request.LinkedAgentId;
            if (request.TechnicianName != null) log.TechnicianName = request.TechnicianName;
            if (request.PaymentStatus != null) log.PaymentStatus = request.PaymentStatus;
            if (request.PaymentMethod != null) log.PaymentMethod = request.PaymentMethod;
            // حالات
            if (request.IsPrinted.HasValue) log.IsPrinted = request.IsPrinted.Value;
            if (request.IsWhatsAppSent.HasValue) log.IsWhatsAppSent = request.IsWhatsAppSent.Value;
            if (request.IsReconciled.HasValue) log.IsReconciled = request.IsReconciled.Value;
            if (request.ReconciliationNotes != null) log.ReconciliationNotes = request.ReconciliationNotes;
            if (request.SubscriptionNotes != null) log.SubscriptionNotes = request.SubscriptionNotes;
            // محاسبية
            if (request.BasePrice.HasValue) log.BasePrice = request.BasePrice.Value;
            if (request.CompanyDiscount.HasValue) log.CompanyDiscount = request.CompanyDiscount.Value;
            if (request.ManualDiscount.HasValue) log.ManualDiscount = request.ManualDiscount.Value;
            if (request.MaintenanceFee.HasValue) log.MaintenanceFee = request.MaintenanceFee.Value;
            // تكرار
            if (request.RenewalCycleMonths.HasValue) log.RenewalCycleMonths = request.RenewalCycleMonths.Value;
            if (request.PaidMonths.HasValue) log.PaidMonths = request.PaidMonths.Value;

            log.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.SubscriptionLogs.Update(log);
            await _unitOfWork.SaveChangesAsync(); // حفظ تغييرات السجل أولاً

            // ═══ إعادة بناء القيد المحاسبي بالكامل ═══
            string? accountingMessage = null;
            if (log.JournalEntryId.HasValue && log.CompanyId.HasValue && log.UserId.HasValue)
            {
                try
                {
                    var entry = await _unitOfWork.JournalEntries.AsQueryable()
                        .Include(j => j.Lines)
                        .FirstOrDefaultAsync(j => j.Id == log.JournalEntryId.Value && j.Status == JournalEntryStatus.Posted);

                    if (entry != null)
                    {
                        var companyId = log.CompanyId.Value;
                        var collType = log.CollectionType?.ToLower() ?? "cash";
                        var operatorName = log.ActivatedBy ?? "مشغل";
                        var basePrice = log.BasePrice ?? log.PlanPrice ?? 0;
                        var companyDiscount = log.CompanyDiscount ?? 0;
                        var manualDiscount = log.ManualDiscount ?? 0;
                        var maintenanceFee = log.MaintenanceFee ?? 0;
                        var collectedAmount = log.PlanPrice ?? 0;
                        var systemDiscountEnabled = log.SystemDiscountEnabled;

                        decimal netFromCompany;
                        if (basePrice > 0)
                            netFromCompany = basePrice - companyDiscount;
                        else if (systemDiscountEnabled)
                            netFromCompany = collectedAmount + manualDiscount - maintenanceFee;
                        else
                            netFromCompany = collectedAmount + manualDiscount - maintenanceFee - companyDiscount;
                        if (netFromCompany <= 0) netFromCompany = collectedAmount;

                        var companyDiscountProfit = systemDiscountEnabled ? 0 : companyDiscount;

                        // ── 1. عكس أرصدة الأسطر القديمة ──
                        foreach (var oldLine in entry.Lines.Where(l => !l.IsDeleted))
                        {
                            var acct = await _unitOfWork.Accounts.GetByIdAsync(oldLine.AccountId);
                            if (acct == null) continue;
                            if (acct.AccountType == AccountType.Assets || acct.AccountType == AccountType.Expenses)
                                acct.CurrentBalance -= oldLine.DebitAmount - oldLine.CreditAmount;
                            else
                                acct.CurrentBalance -= oldLine.CreditAmount - oldLine.DebitAmount;
                            _unitOfWork.Accounts.Update(acct);
                            // حذف ناعم للسطر القديم
                            oldLine.IsDeleted = true;
                            oldLine.DeletedAt = DateTime.UtcNow;
                            _unitOfWork.JournalEntryLines.Update(oldLine);
                        }

                        // ── 2. بناء الأسطر الجديدة ──
                        var newLines = new List<(Guid AccountId, decimal Debit, decimal Credit, string Desc)>();

                        // مدين: حساب التحصيل
                        Account? debitAcct = null;
                        switch (collType)
                        {
                            case "cash":
                                debitAcct = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.Cash, log.UserId.Value, $"صندوق {operatorName}", companyId);
                                break;
                            case "credit":
                                debitAcct = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.OperatorReceivables, log.UserId.Value, $"ذمة {operatorName}", companyId);
                                break;
                            case "master":
                                debitAcct = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.ElectronicPayment, companyId);
                                break;
                            case "technician":
                                if (log.LinkedTechnicianId.HasValue)
                                {
                                    var tech = await _unitOfWork.Users.GetByIdAsync(log.LinkedTechnicianId.Value);
                                    debitAcct = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.TechnicianReceivables, log.LinkedTechnicianId.Value, tech?.FullName ?? "فني", companyId);
                                }
                                break;
                            case "agent":
                                if (log.LinkedAgentId.HasValue)
                                {
                                    var agent = await _unitOfWork.Agents.GetByIdAsync(log.LinkedAgentId.Value);
                                    if (agent != null)
                                        debitAcct = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.AgentReceivables, agent.Id, agent.Name, companyId);
                                }
                                break;
                        }
                        await _unitOfWork.SaveChangesAsync(); // حفظ الحسابات الجديدة إن أُنشئت

                        _logger.LogInformation("📝 Rebuild entry {Id}: collType={CollType}, debitAcct={Acct}, amount={Amount}, techId={TechId}",
                            id, collType, debitAcct?.Name, collectedAmount, log.LinkedTechnicianId);
                        if (debitAcct != null)
                            newLines.Add((debitAcct.Id, collectedAmount, 0, $"{log.CustomerName} - {collType}"));

                        // مدين: خصم يدوي (مصاريف عروض)
                        if (manualDiscount > 0)
                        {
                            var promoAcct = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.PromotionExpense, companyId);
                            if (promoAcct != null)
                                newLines.Add((promoAcct.Id, manualDiscount, 0, $"خصم يدوي - {log.CustomerName}"));
                        }

                        // دائن: رصيد الصفحة
                        var pageAcct = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.PageBalance, companyId);
                        if (pageAcct != null && netFromCompany > 0)
                            newLines.Add((pageAcct.Id, 0, netFromCompany, $"خصم من رصيد الصفحة - {log.PlanName}"));

                        // دائن: إيراد صيانة
                        if (maintenanceFee > 0)
                        {
                            var maintAcct = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.MaintenanceRevenue, companyId);
                            if (maintAcct != null)
                                newLines.Add((maintAcct.Id, 0, maintenanceFee, $"إيراد صيانة - {log.CustomerName}"));
                        }

                        // دائن: إيراد خصم الشركة
                        if (companyDiscountProfit > 0)
                        {
                            var discAcct = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.CompanyDiscountRevenue, companyId);
                            if (discAcct != null)
                                newLines.Add((discAcct.Id, 0, companyDiscountProfit, $"إيراد خصم الشركة - {log.CustomerName}"));
                        }

                        // ── 3. إضافة الأسطر الجديدة وتحديث الأرصدة ──
                        if (newLines.Count >= 2)
                        {
                            foreach (var nl in newLines)
                            {
                                var newLine = new JournalEntryLine
                                {
                                    JournalEntryId = entry.Id,
                                    AccountId = nl.AccountId,
                                    DebitAmount = nl.Debit,
                                    CreditAmount = nl.Credit,
                                    Description = nl.Desc
                                };
                                await _unitOfWork.JournalEntryLines.AddAsync(newLine);

                                var acct = await _unitOfWork.Accounts.GetByIdAsync(nl.AccountId);
                                if (acct != null)
                                {
                                    if (acct.AccountType == AccountType.Assets || acct.AccountType == AccountType.Expenses)
                                        acct.CurrentBalance += nl.Debit - nl.Credit;
                                    else
                                        acct.CurrentBalance += nl.Credit - nl.Debit;
                                    _unitOfWork.Accounts.Update(acct);
                                }
                            }

                            entry.TotalDebit = newLines.Sum(l => l.Debit);
                            entry.TotalCredit = newLines.Sum(l => l.Credit);
                            // مزامنة تاريخ القيد مع تاريخ المعاملة
                            if (log.ActivationDate.HasValue)
                                entry.EntryDate = log.ActivationDate.Value;
                            entry.Description = $"{log.OperationType ?? "تجديد"} {log.PlanName ?? ""} - {log.CustomerName ?? ""} - {(collType switch { "cash" => "نقد", "credit" => "آجل", "technician" => "فني", "agent" => "وكيل", "master" => "ماستر", _ => collType })} عبر {operatorName}";
                            _unitOfWork.JournalEntries.Update(entry);

                            accountingMessage = "تم تحديث القيد المحاسبي بالكامل";
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "⚠️ فشل تحديث القيد المحاسبي للسجل {Id}", id);
                    accountingMessage = "تم تحديث السجل لكن فشل تحديث القيد المحاسبي";
                }
            }

            await _unitOfWork.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                message = accountingMessage != null
                    ? $"تم تحديث السجل — {accountingMessage}"
                    : "تم تحديث السجل بنجاح",
                accountingUpdated = accountingMessage != null
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تحديث سجل الاشتراك {Id}", id);
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
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
                .FirstOrDefaultAsync(a => a.Code.StartsWith(AccountCodes.OperatorReceivables)
                    && a.Description == log.UserId.ToString()
                    && a.CompanyId == dto.CompanyId && a.IsActive);

            if (debtAccount == null)
                return BadRequest(new { success = false, message = "لا يوجد حساب ذمة لهذا المشغل" });

            // صندوق الشركة الرئيسي (11104)
            var mainCashBox = await _unitOfWork.Accounts.AsQueryable()
                .FirstOrDefaultAsync(a => a.Code == AccountCodes.CompanyMainCash && a.IsActive
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
                .FirstOrDefaultAsync(a => a.Code.StartsWith(AccountCodes.OperatorReceivables)
                    && a.Description == dto.OperatorUserId.ToString()
                    && a.CompanyId == dto.CompanyId && a.IsActive);

            if (operatorDebtAccount == null)
                return BadRequest(new { success = false, message = "لا يوجد حساب ذمة لهذا المشغل" });

            // صندوق الشركة الرئيسي (11104) - التحصيل يذهب مباشرة للشركة
            var mainCashBox = await _unitOfWork.Accounts.AsQueryable()
                .FirstOrDefaultAsync(a => a.Code == AccountCodes.CompanyMainCash && a.IsActive
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
                .Where(u => !u.IsDeleted);

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

    // ==================== 8.5 جلب معرّفات FTTH المحفوظة ====================

    /// <summary>
    /// يرجع بصمات العمليات المحفوظة (FtthTransactionId + composite keys) لتحديد العمليات الناقصة
    /// </summary>
    [HttpGet("existing-ftth-ids")]
    public async Task<IActionResult> GetExistingFtthIds(
        [FromQuery] Guid? companyId = null,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null)
    {
        try
        {
            var baseQuery = _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => !l.IsDeleted && l.PlanName != null && l.PlanName.ToUpper().Contains("FIBER"));

            if (companyId.HasValue)
                baseQuery = baseQuery.Where(l => l.CompanyId == companyId || l.CompanyId == null);
            if (from.HasValue)
            {
                var fromUtc = DateTime.SpecifyKind(from.Value.Date.AddHours(-3), DateTimeKind.Utc);
                baseQuery = baseQuery.Where(l => l.ActivationDate >= fromUtc);
            }
            if (to.HasValue)
            {
                var toUtc = DateTime.SpecifyKind(to.Value.Date.AddDays(1).AddHours(-3), DateTimeKind.Utc);
                baseQuery = baseQuery.Where(l => l.ActivationDate <= toUtc);
            }

            // 1. FtthTransactionId للعمليات المُزامنة
            var ids = await baseQuery
                .Where(l => l.FtthTransactionId != null && l.FtthTransactionId != "")
                .Select(l => l.FtthTransactionId!)
                .ToListAsync();

            // 2. بصمات بمعرّف العميل: customerId|المستقطع|تاريخ
            var fingerprints = await baseQuery
                .Where(l => l.CustomerId != null && l.CustomerId != "")
                .Select(l => new {
                    l.CustomerId, l.PlanPrice, l.ActivationDate,
                    l.BasePrice, l.CompanyDiscount, l.ManualDiscount,
                    l.MaintenanceFee, l.SystemDiscountEnabled
                })
                .ToListAsync();

            var keys = fingerprints.Select(f =>
            {
                var cid = f.CustomerId!.Trim();
                // استخدام المستقطع (PageDeduction) — يطابق المبلغ المخصوم في FTTH
                var pageDeduction = (f.BasePrice ?? 0) > 0
                    ? (f.BasePrice ?? 0) - (f.CompanyDiscount ?? 0)
                    : f.SystemDiscountEnabled
                        ? (f.PlanPrice ?? 0) + (f.ManualDiscount ?? 0) - (f.MaintenanceFee ?? 0)
                        : (f.PlanPrice ?? 0) + (f.ManualDiscount ?? 0) - (f.MaintenanceFee ?? 0) - (f.CompanyDiscount ?? 0);
                var price = (int)pageDeduction;
                // تحويل التاريخ من UTC إلى توقيت بغداد (+3) ليطابق تاريخ FTTH
                var date = f.ActivationDate.HasValue
                    ? f.ActivationDate.Value.AddHours(3).ToString("yyyy-MM-dd")
                    : "";
                return $"{cid}|{price}|{date}";
            }).ToList();

            return Ok(new { success = true, ids, keys });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { success = false, message = ex.Message });
        }
    }

    // ==================== 9. مزامنة عمليات FTTH دفعة واحدة ====================

    /// <summary>
    /// حفظ دفعة من عمليات FTTH في SubscriptionLog مع FtthTransactionId
    /// يُستدعى من Flutter عند الضغط على زر المزامنة
    /// يتجاهل العمليات المحفوظة مسبقاً (بناءً على FtthTransactionId)
    /// </summary>
    [HttpPost("sync-ftth-transactions")]
    [DisableRequestSizeLimit]
    public async Task<IActionResult> SyncFtthTransactions([FromBody] SyncFtthTransactionsDto? dto)
    {
        try
        {
            if (dto == null)
                return BadRequest(new { success = false, message = "البيانات المرسلة فارغة أو بصيغة خاطئة" });
            if (dto.Transactions == null || dto.Transactions.Count == 0)
                return BadRequest(new { success = false, message = "لا توجد عمليات للمزامنة" });

            // جلب معرّفات العمليات المحفوظة مسبقاً
            var existingIds = await _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => l.FtthTransactionId != null && l.FtthTransactionId != "")
                .Select(l => l.FtthTransactionId!)
                .ToListAsync();
            var existingSet = new HashSet<string>(existingIds);

            // خريطة شاملة: FtthUsername / Username / FullName → UserId
            var userMap = await _unitOfWork.Users.AsQueryable()
                .Where(u => !u.IsDeleted)
                .Select(u => new { u.Id, u.FtthUsername, u.Username, u.FullName, u.CompanyId })
                .ToListAsync();
            var ftthToUser = new Dictionary<string, dynamic>();
            foreach (var u in userMap)
            {
                var val = new { u.Id, u.FullName, u.CompanyId };
                // أولوية: FtthUsername > Username > FullName
                if (!string.IsNullOrWhiteSpace(u.FtthUsername))
                {
                    var k = u.FtthUsername.ToLower().Trim();
                    ftthToUser.TryAdd(k, val);
                }
                if (!string.IsNullOrWhiteSpace(u.Username))
                {
                    var k = u.Username.ToLower().Trim();
                    ftthToUser.TryAdd(k, val);
                }
                if (!string.IsNullOrWhiteSpace(u.FullName))
                {
                    var k = u.FullName.ToLower().Trim();
                    ftthToUser.TryAdd(k, val);
                }
            }

            // ═══ جلب أسعار الباقات وأجور الصيانة لحساب الإيرادات تلقائياً ═══
            var allPlans = await _unitOfWork.InternetPlans.AsQueryable()
                .Where(p => !p.IsDeleted && p.IsActive)
                .Select(p => new { p.Name, p.MonthlyPrice, p.CompanyId })
                .ToListAsync();
            // خريطة: اسم الباقة (lowercase) → السعر الشهري
            var planPriceMap = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);
            foreach (var p in allPlans)
            {
                planPriceMap.TryAdd(p.Name, p.MonthlyPrice);
            }

            var allZoneFees = await _unitOfWork.ZoneMaintenanceFees.AsQueryable()
                .Where(z => !z.IsDeleted && z.IsEnabled)
                .Select(z => new { z.ZoneName, z.ZoneId, z.MaintenanceAmount })
                .ToListAsync();
            // خريطة: اسم الزون أو معرفه → مبلغ الصيانة
            var zoneFeeByName = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);
            var zoneFeeById = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);
            foreach (var z in allZoneFees)
            {
                if (!string.IsNullOrWhiteSpace(z.ZoneName))
                    zoneFeeByName.TryAdd(z.ZoneName, z.MaintenanceAmount);
                if (!string.IsNullOrWhiteSpace(z.ZoneId))
                    zoneFeeById.TryAdd(z.ZoneId, z.MaintenanceAmount);
            }

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
                                // ربط بالمشغل: أولاً operatorUserId، ثانياً بحث بالاسم
                                if (!string.IsNullOrEmpty(tx.OperatorUserId) && Guid.TryParse(tx.OperatorUserId, out var directId))
                                {
                                    existing.UserId = directId;
                                }
                                else
                                {
                                    var key = tx.CreatedBy.ToLower().Trim();
                                    if (ftthToUser.TryGetValue(key, out var u))
                                    {
                                        existing.UserId = u.Id;
                                        existing.CompanyId ??= u.CompanyId;
                                    }
                                }
                                needsUpdate = true;
                            }
                            // إذا لا يزال بدون مشغل، حاول الربط من operatorUserId
                            if (existing.UserId == null && !string.IsNullOrEmpty(tx.OperatorUserId) && Guid.TryParse(tx.OperatorUserId, out var opId))
                            {
                                existing.UserId = opId;
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

                    // أولاً: استخدام operatorUserId المرسل مباشرة (من المقارنة)
                    if (!string.IsNullOrEmpty(tx.OperatorUserId) && Guid.TryParse(tx.OperatorUserId, out var directUserId))
                    {
                        userId = directUserId;
                    }
                    // ثانياً: البحث بـ CreatedBy (اسم المستخدم في FTTH)
                    if (userId == null && !string.IsNullOrEmpty(tx.CreatedBy))
                    {
                        var key = tx.CreatedBy.ToLower().Trim();
                        if (ftthToUser.TryGetValue(key, out var user))
                        {
                            userId = user.Id;
                            companyId ??= user.CompanyId;
                        }
                    }
                    // ثالثاً: البحث بـ TechnicianName (أحياناً اسم الفني/المشغل هنا)
                    if (userId == null && !string.IsNullOrEmpty(tx.TechnicianName))
                    {
                        var key = tx.TechnicianName.ToLower().Trim();
                        if (ftthToUser.TryGetValue(key, out var user))
                        {
                            userId = user.Id;
                            companyId ??= user.CompanyId;
                        }
                    }
                    // رابعاً: إذا لم يُربط بأي طريقة — استخدم CompanyId الافتراضي ولا تترك فارغاً
                    if (userId == null)
                    {
                        _logger.LogWarning("عملية {TxId} بدون مشغل: CreatedBy='{CreatedBy}', OperatorUserId='{OpId}'",
                            tx.FtthTransactionId, tx.CreatedBy, tx.OperatorUserId);
                    }

                    var planPrice = tx.Amount != null ? Math.Abs(tx.Amount.Value) : (decimal?)null;
                    var collectionType = !string.IsNullOrEmpty(tx.CollectionType) ? tx.CollectionType : "cash";

                    // ═══ حساب الإيرادات تلقائياً ═══
                    // 1. خصم الشركة = سعر الباقة (من جدول الأسعار) - المبلغ المستقطع (من FTTH)
                    decimal autoCompanyDiscount = 0;
                    decimal autoBasePrice = planPrice ?? 0;
                    if (planPrice.HasValue && !string.IsNullOrEmpty(tx.PlanName))
                    {
                        // بحث مباشر بالاسم
                        if (planPriceMap.TryGetValue(tx.PlanName, out var configuredPrice))
                        {
                            autoBasePrice = configuredPrice;
                            if (configuredPrice > planPrice.Value)
                                autoCompanyDiscount = configuredPrice - planPrice.Value;
                        }
                        else
                        {
                            // بحث جزئي (مثلاً "FIBER 35" في "FIBER 35 - 1 Month")
                            foreach (var kv in planPriceMap)
                            {
                                if (tx.PlanName.Contains(kv.Key, StringComparison.OrdinalIgnoreCase)
                                    || kv.Key.Contains(tx.PlanName, StringComparison.OrdinalIgnoreCase))
                                {
                                    autoBasePrice = kv.Value;
                                    if (kv.Value > planPrice.Value)
                                        autoCompanyDiscount = kv.Value - planPrice.Value;
                                    break;
                                }
                            }
                        }
                    }

                    // 2. أجور الصيانة = من جدول أجور الزونات حسب المنطقة
                    decimal autoMaintenanceFee = 0;
                    if (!string.IsNullOrEmpty(tx.ZoneName) && zoneFeeByName.TryGetValue(tx.ZoneName, out var feeByName))
                        autoMaintenanceFee = feeByName;
                    else if (!string.IsNullOrEmpty(tx.ZoneId) && zoneFeeById.TryGetValue(tx.ZoneId, out var feeById))
                        autoMaintenanceFee = feeById;
                    else if (!string.IsNullOrEmpty(tx.ZoneId) && zoneFeeByName.TryGetValue(tx.ZoneId, out var feeByZoneIdInName))
                        autoMaintenanceFee = feeByZoneIdInName;

                    // تحديد ActivatedBy: أولوية FullName > CreatedBy
                    var activatedByValue = tx.CreatedBy;
                    if (userId.HasValue)
                    {
                        var matchedUser = userMap.FirstOrDefault(u => u.Id == userId.Value);
                        if (matchedUser != null && !string.IsNullOrEmpty(matchedUser.FullName))
                            activatedByValue = matchedUser.FullName;
                    }

                    // تحويل التاريخ لـ UTC بشكل صحيح (FTTH يرسل توقيت بغداد UTC+3)
                    DateTime? activationDateUtc = null;
                    if (tx.OccuredAt.HasValue)
                    {
                        var dt = tx.OccuredAt.Value;
                        // إذا لم يكن UTC، نعتبره توقيت بغداد ونحوّله
                        activationDateUtc = dt.Kind == DateTimeKind.Utc
                            ? dt
                            : DateTime.SpecifyKind(dt.AddHours(-3), DateTimeKind.Utc);
                    }

                    // تحويل القيم الإنجليزية للعربية
                    var operationTypeAr = (tx.OperationType?.ToLower()) switch
                    {
                        "renewal" or "plan_renew" => "تجديد",
                        "purchase" or "plan_purchase" => "شراء",
                        "change" or "plan_change" => "تغيير",
                        "schedule_change" => "جدولة",
                        _ => tx.OperationType ?? "تجديد"
                    };
                    var paymentMethodAr = (tx.PaymentMethod?.ToLower()) switch
                    {
                        "wallet" or "cash" => collectionType == "technician" ? "فني" : collectionType == "agent" ? "وكيل" : collectionType == "master" ? "ماستر" : "نقد",
                        "credit" => "آجل",
                        _ => tx.PaymentMethod ?? (collectionType switch { "cash" => "نقد", "technician" => "فني", "agent" => "وكيل", "master" => "ماستر", "credit" => "آجل", _ => "نقد" })
                    };

                    var log = new SubscriptionLog
                    {
                        CustomerId = tx.CustomerId,
                        CustomerName = tx.CustomerName,
                        PhoneNumber = tx.PhoneNumber,
                        SubscriptionId = tx.SubscriptionId,
                        PlanName = tx.PlanName,
                        PlanPrice = planPrice,
                        CommitmentPeriod = tx.CommitmentPeriod,
                        OperationType = operationTypeAr,
                        ActivatedBy = activatedByValue,
                        ActivationDate = activationDateUtc,
                        ZoneId = tx.ZoneId,
                        ZoneName = tx.ZoneName,
                        DeviceUsername = tx.DeviceUsername,
                        FtthTransactionId = tx.FtthTransactionId,
                        UserId = userId,
                        CompanyId = companyId,
                        CollectionType = collectionType,
                        PaymentMethod = paymentMethodAr,
                        PaymentStatus = tx.PaymentStatus,
                        TechnicianName = tx.TechnicianName,
                        StartDate = tx.StartDate?.ToString("yyyy-MM-dd"),
                        EndDate = tx.EndDate?.ToString("yyyy-MM-dd"),
                        WalletBalanceAfter = tx.RemainingBalance,
                        CurrentStatus = "Active",
                        IsReconciled = true,
                        ReconciliationNotes = "مزامنة تلقائية من FTTH",
                        // إيرادات محسوبة تلقائياً — BasePrice = السعر الأساسي من جدول الأسعار
                        BasePrice = autoBasePrice > 0 ? autoBasePrice : planPrice,
                        CompanyDiscount = autoCompanyDiscount > 0 ? autoCompanyDiscount : null,
                        MaintenanceFee = autoMaintenanceFee > 0 ? autoMaintenanceFee : null,
                    };

                    await _unitOfWork.SubscriptionLogs.AddAsync(log);
                    await _unitOfWork.SaveChangesAsync();
                    saved++;

                    // إنشاء قيد محاسبي تلقائياً لكل عملية مزامنة
                    if (userId.HasValue && companyId.HasValue && planPrice > 0)
                    {
                        try
                        {
                            // المبلغ المحصّل من العميل = المستقطع + أجور الصيانة
                            var totalCollected = (planPrice ?? 0) + autoMaintenanceFee;

                            var accountingDto = new FtthLogWithAccountingDto(
                                tx.CustomerId, tx.CustomerName, null,
                                tx.SubscriptionId, tx.PlanName, totalCollected,   // PlanPrice = ما يدفعه العميل كاملاً
                                null, null, null,
                                tx.DeviceUsername, tx.OperationType, tx.CreatedBy,
                                tx.OccuredAt, null, null,
                                tx.ZoneId, null, null, null, null,
                                null, tx.RemainingBalance,
                                null, null,
                                null, tx.PaymentMethod, null, null,
                                userId, companyId, false, false,
                                null, tx.StartDate?.ToString("yyyy-MM-dd"), tx.EndDate?.ToString("yyyy-MM-dd"),
                                null, null,
                                collectionType, tx.FtthTransactionId, null,
                                null, null,
                                autoBasePrice > 0 ? autoBasePrice : planPrice,    // BasePrice = سعر الباقة (من جدول الأسعار)
                                autoCompanyDiscount,                               // خصم الشركة (معلومات فقط)
                                0,                                                 // ManualDiscount يبقى يدوي فقط
                                autoMaintenanceFee,                                // أجور الصيانة (إيراد)
                                true);                                             // SystemDiscountEnabled=true (الخصم مفعّل = ممرَّر للعميل = ليس إيراد)

                            var jeId = await CreateAccountingEntry(log, accountingDto);
                            if (jeId.HasValue)
                            {
                                log.JournalEntryId = jeId;
                                _unitOfWork.SubscriptionLogs.Update(log);
                            }
                            await _unitOfWork.SaveChangesAsync();
                        }
                        catch (Exception accEx)
                        {
                            _logger.LogWarning(accEx, "فشل إنشاء قيد محاسبي للعملية {TxId}", tx.FtthTransactionId);
                        }
                    }

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

    // ==================== 9.55 تصحيح المستقطع دفعة واحدة ====================

    /// <summary>
    /// تصحيح BasePrice (المستقطع) لعدة سجلات دفعة واحدة حسب مبلغ FTTH الفعلي
    /// </summary>
    [HttpPost("fix-base-prices")]
    public async Task<IActionResult> FixBasePrices([FromBody] List<FixBasePriceItem> items)
    {
        if (items == null || items.Count == 0)
            return BadRequest(new { success = false, message = "لا توجد بيانات" });

        int updated = 0, failed = 0;
        foreach (var item in items)
        {
            try
            {
                var log = await _unitOfWork.SubscriptionLogs.AsQueryable()
                    .FirstOrDefaultAsync(l => l.Id == item.LogId && !l.IsDeleted);
                if (log == null) { failed++; continue; }

                // المستقطع = BasePrice - CompanyDiscount = FtthAmount
                // ∴ BasePrice = FtthAmount + CompanyDiscount
                log.BasePrice = item.FtthAmount + (log.CompanyDiscount ?? 0);
                log.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.SubscriptionLogs.Update(log);
                updated++;
            }
            catch { failed++; }
        }

        await _unitOfWork.SaveChangesAsync();
        return Ok(new { success = true, message = $"تم تصحيح {updated} سجل، {failed} فشل", updated, failed });
    }

    // ==================== 9.6 إعادة حساب الإيرادات للعمليات المتزامنة ====================

    /// <summary>
    /// إعادة حساب الإيرادات (خصم الشركة + أجور الصيانة) للعمليات المتزامنة الموجودة
    /// يُحدّث SubscriptionLog ويُعيد إنشاء القيود المحاسبية بالأرقام الصحيحة
    /// </summary>
    [HttpPost("recalculate-sync-revenues")]
    public async Task<IActionResult> RecalculateSyncRevenues(
        [FromQuery] Guid? companyId = null,
        [FromQuery] Guid? userId = null,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] bool forceAll = false)
    {
        try
        {
            // 1. جلب أسعار الباقات وأجور الصيانة
            var allPlans = await _unitOfWork.InternetPlans.AsQueryable()
                .Where(p => !p.IsDeleted && p.IsActive)
                .Select(p => new { p.Name, p.MonthlyPrice })
                .ToListAsync();
            var planPriceMap = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);
            foreach (var p in allPlans)
                planPriceMap.TryAdd(p.Name, p.MonthlyPrice);

            var allZoneFees = await _unitOfWork.ZoneMaintenanceFees.AsQueryable()
                .Where(z => !z.IsDeleted && z.IsEnabled)
                .Select(z => new { z.ZoneName, z.ZoneId, z.MaintenanceAmount })
                .ToListAsync();
            var zoneFeeByName = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);
            var zoneFeeById = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);
            foreach (var z in allZoneFees)
            {
                if (!string.IsNullOrWhiteSpace(z.ZoneName))
                    zoneFeeByName.TryAdd(z.ZoneName, z.MaintenanceAmount);
                if (!string.IsNullOrWhiteSpace(z.ZoneId))
                    zoneFeeById.TryAdd(z.ZoneId, z.MaintenanceAmount);
            }

            if (!planPriceMap.Any() && !zoneFeeByName.Any())
                return BadRequest(new { success = false, message = "لا توجد أسعار باقات أو أجور صيانة مُعرّفة — أضفها أولاً" });

            // 2. جلب العمليات
            var query = _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => !l.IsDeleted
                    && l.PlanPrice > 0
                    && l.UserId.HasValue && l.CompanyId.HasValue);

            if (companyId.HasValue)
                query = query.Where(l => l.CompanyId == companyId);

            if (userId.HasValue)
                query = query.Where(l => l.UserId == userId);

            // فلتر التاريخ (توقيت بغداد → UTC)
            if (from.HasValue)
            {
                var fromUtc = DateTime.SpecifyKind(from.Value.Date.AddHours(-3), DateTimeKind.Utc);
                query = query.Where(l => l.ActivationDate >= fromUtc);
            }
            if (to.HasValue)
            {
                var toUtc = DateTime.SpecifyKind(to.Value.Date.AddDays(1).AddHours(-3), DateTimeKind.Utc);
                query = query.Where(l => l.ActivationDate <= toUtc);
            }

            // إذا لم يُحدد forceAll أو تاريخ، فقط العمليات بدون إيرادات
            if (!forceAll && !from.HasValue && !to.HasValue)
            {
                query = query.Where(l =>
                    (l.MaintenanceFee == null || l.MaintenanceFee == 0)
                    && (l.CompanyDiscount == null || l.CompanyDiscount == 0));
            }

            // فلترة خدمات الإنترنت فقط
            query = query.Where(l => l.PlanName != null && l.PlanName.ToUpper().Contains("FIBER"));

            var logs = await query.ToListAsync();

            if (!logs.Any())
                return Ok(new { success = true, message = "لا توجد عمليات تحتاج تحديث", updated = 0 });

            int updated = 0, accountingCreated = 0, accountingUpdated = 0, failed = 0;
            var errors = new List<string>();

            foreach (var log in logs)
            {
                try
                {
                    var planPrice = log.PlanPrice ?? 0;

                    // حساب خصم الشركة
                    decimal autoCompanyDiscount = 0;
                    decimal autoBasePrice = planPrice;
                    if (!string.IsNullOrEmpty(log.PlanName))
                    {
                        if (planPriceMap.TryGetValue(log.PlanName, out var configuredPrice))
                        {
                            autoBasePrice = configuredPrice;
                            if (configuredPrice > planPrice)
                                autoCompanyDiscount = configuredPrice - planPrice;
                        }
                        else
                        {
                            foreach (var kv in planPriceMap)
                            {
                                if (log.PlanName.Contains(kv.Key, StringComparison.OrdinalIgnoreCase)
                                    || kv.Key.Contains(log.PlanName, StringComparison.OrdinalIgnoreCase))
                                {
                                    autoBasePrice = kv.Value;
                                    if (kv.Value > planPrice)
                                        autoCompanyDiscount = kv.Value - planPrice;
                                    break;
                                }
                            }
                        }
                    }

                    // حساب أجور الصيانة
                    decimal autoMaintenanceFee = 0;
                    if (!string.IsNullOrEmpty(log.ZoneName) && zoneFeeByName.TryGetValue(log.ZoneName, out var feeByName))
                        autoMaintenanceFee = feeByName;
                    else if (!string.IsNullOrEmpty(log.ZoneId) && zoneFeeById.TryGetValue(log.ZoneId, out var feeById))
                        autoMaintenanceFee = feeById;
                    else if (!string.IsNullOrEmpty(log.ZoneId) && zoneFeeByName.TryGetValue(log.ZoneId, out var feeByZoneIdInName))
                        autoMaintenanceFee = feeByZoneIdInName;

                    // تخطي إذا لا يوجد أي تغيير (لا إيرادات ولا تصحيح BasePrice)
                    var basePriceChanged = autoBasePrice != (log.BasePrice ?? 0) && autoBasePrice > 0;
                    if (autoCompanyDiscount == 0 && autoMaintenanceFee == 0 && !basePriceChanged)
                        continue;

                    // تحديث SubscriptionLog
                    log.BasePrice = autoBasePrice > 0 ? autoBasePrice : log.BasePrice;
                    log.CompanyDiscount = autoCompanyDiscount > 0 ? autoCompanyDiscount : null;
                    log.MaintenanceFee = autoMaintenanceFee > 0 ? autoMaintenanceFee : null;
                    log.SystemDiscountEnabled = autoCompanyDiscount <= 0;
                    _unitOfWork.SubscriptionLogs.Update(log);
                    updated++;

                    // إلغاء القيد القديم إن وُجد
                    if (log.JournalEntryId.HasValue)
                    {
                        var oldJe = await _unitOfWork.JournalEntries.GetByIdAsync(log.JournalEntryId.Value);
                        if (oldJe != null && oldJe.Status != JournalEntryStatus.Voided)
                        {
                            oldJe.Status = JournalEntryStatus.Voided;
                            oldJe.Notes = (oldJe.Notes ?? "") + " | ملغي — إعادة حساب الإيرادات";
                            _unitOfWork.JournalEntries.Update(oldJe);
                            accountingUpdated++;
                        }
                    }

                    // إنشاء قيد محاسبي جديد بالأرقام الصحيحة
                    // المبلغ المحصّل = المستقطع + أجور الصيانة (خصم الشركة مفعّل = ليس إيراد)
                    var sde = log.SystemDiscountEnabled;
                    var totalCollected = planPrice + autoMaintenanceFee + (sde ? 0 : autoCompanyDiscount);
                    var collectionType = log.CollectionType ?? "cash";

                    var accountingDto = new FtthLogWithAccountingDto(
                        log.CustomerId, log.CustomerName, null,
                        log.SubscriptionId, log.PlanName, totalCollected,
                        null, null, null,
                        log.DeviceUsername, log.OperationType, log.ActivatedBy,
                        log.ActivationDate, null, null,
                        log.ZoneId, log.ZoneName, null, null, null,
                        null, log.WalletBalanceAfter,
                        null, null,
                        null, log.PaymentMethod, null, null,
                        log.UserId, log.CompanyId, false, false,
                        null, log.StartDate, log.EndDate,
                        log.TechnicianName, null,
                        collectionType, log.FtthTransactionId, null,
                        null, log.LinkedTechnicianId,
                        autoBasePrice,
                        autoCompanyDiscount,
                        log.ManualDiscount ?? 0,
                        autoMaintenanceFee,
                        sde);                                      // يحافظ على قيمة SystemDiscountEnabled الحالية

                    var jeId = await CreateAccountingEntry(log, accountingDto);
                    if (jeId.HasValue)
                    {
                        log.JournalEntryId = jeId;
                        _unitOfWork.SubscriptionLogs.Update(log);
                        accountingCreated++;
                    }

                    await _unitOfWork.SaveChangesAsync();
                }
                catch (Exception ex)
                {
                    failed++;
                    errors.Add($"Log #{log.Id}: {ex.Message}");
                    _logger.LogWarning(ex, "فشل إعادة حساب الإيرادات للسجل {LogId}", log.Id);
                }
            }

            return Ok(new
            {
                success = true,
                message = $"تم التحديث: {updated} سجل، {accountingCreated} قيد جديد، {accountingUpdated} قيد ملغي، {failed} فشل",
                totalFound = logs.Count,
                updated,
                accountingCreated,
                accountingUpdated,
                failed,
                errors = errors.Take(10).ToList()
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إعادة حساب إيرادات المزامنة");
            return StatusCode(500, new { success = false, message = "خطأ: " + ex.Message });
        }
    }

    // ==================== 9.5 دمج العمليات المكررة ====================

    /// <summary>
    /// دمج عملية مُزامنة (لها FtthTransactionId) مع عملية أصلية (لها بيانات محاسبية)
    /// ينقل FtthTransactionId و CustomerId والمنطقة من المُزامنة للأصلية ثم يحذف المُزامنة
    /// </summary>
    [HttpPost("merge-duplicate")]
    public async Task<IActionResult> MergeDuplicate([FromBody] MergeDuplicateDto dto)
    {
        try
        {
            if (dto.OriginalId <= 0 || dto.DuplicateId <= 0)
                return BadRequest(new { success = false, message = "معرّفات غير صالحة" });

            var original = await _unitOfWork.SubscriptionLogs.AsQueryable()
                .FirstOrDefaultAsync(l => l.Id == dto.OriginalId && !l.IsDeleted);
            var duplicate = await _unitOfWork.SubscriptionLogs.AsQueryable()
                .FirstOrDefaultAsync(l => l.Id == dto.DuplicateId && !l.IsDeleted);

            if (original == null)
                return NotFound(new { success = false, message = "العملية الأصلية غير موجودة" });
            if (duplicate == null)
                return NotFound(new { success = false, message = "العملية المكررة غير موجودة" });

            // نقل المعلومات الناقصة من المكررة للأصلية
            if (string.IsNullOrEmpty(original.FtthTransactionId) && !string.IsNullOrEmpty(duplicate.FtthTransactionId))
                original.FtthTransactionId = duplicate.FtthTransactionId;
            if (string.IsNullOrEmpty(original.CustomerId) && !string.IsNullOrEmpty(duplicate.CustomerId))
                original.CustomerId = duplicate.CustomerId;
            if (string.IsNullOrEmpty(original.SubscriptionId) && !string.IsNullOrEmpty(duplicate.SubscriptionId))
                original.SubscriptionId = duplicate.SubscriptionId;
            if (string.IsNullOrEmpty(original.ZoneId) && !string.IsNullOrEmpty(duplicate.ZoneId))
                original.ZoneId = duplicate.ZoneId;
            if (string.IsNullOrEmpty(original.ZoneName) && !string.IsNullOrEmpty(duplicate.ZoneName))
                original.ZoneName = duplicate.ZoneName;
            if (string.IsNullOrEmpty(original.DeviceUsername) && !string.IsNullOrEmpty(duplicate.DeviceUsername))
                original.DeviceUsername = duplicate.DeviceUsername;
            if (string.IsNullOrEmpty(original.PhoneNumber) && !string.IsNullOrEmpty(duplicate.PhoneNumber))
                original.PhoneNumber = duplicate.PhoneNumber;
            if (string.IsNullOrEmpty(original.StartDate) && !string.IsNullOrEmpty(duplicate.StartDate))
                original.StartDate = duplicate.StartDate;
            if (string.IsNullOrEmpty(original.EndDate) && !string.IsNullOrEmpty(duplicate.EndDate))
                original.EndDate = duplicate.EndDate;
            if (original.WalletBalanceAfter == null && duplicate.WalletBalanceAfter != null)
                original.WalletBalanceAfter = duplicate.WalletBalanceAfter;

            original.IsReconciled = true;
            original.ReconciliationNotes = $"دمج تلقائي — حُذفت المكررة #{duplicate.Id}";

            _unitOfWork.SubscriptionLogs.Update(original);

            // حذف المكررة (soft delete)
            duplicate.IsDeleted = true;
            _unitOfWork.SubscriptionLogs.Update(duplicate);

            // إذا المكررة لها قيد محاسبي — إلغاؤه
            if (duplicate.JournalEntryId.HasValue)
            {
                var je = await _unitOfWork.JournalEntries.GetByIdAsync(duplicate.JournalEntryId.Value);
                if (je != null && je.Status != JournalEntryStatus.Voided)
                {
                    je.Status = JournalEntryStatus.Voided;
                    je.Notes = (je.Notes ?? "") + " | ملغي — دمج مكررات";
                    _unitOfWork.JournalEntries.Update(je);
                }
            }

            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = $"تم الدمج: الأصلية #{original.Id} ← المكررة #{duplicate.Id}" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في دمج العمليات المكررة");
            return StatusCode(500, new { success = false, message = "خطأ: " + ex.Message });
        }
    }

    /// <summary>
    /// دمج مجموعة عمليات مكررة دفعة واحدة
    /// </summary>
    [HttpPost("merge-duplicates-batch")]
    public async Task<IActionResult> MergeDuplicatesBatch([FromBody] List<MergeDuplicateDto> items)
    {
        try
        {
            if (items == null || items.Count == 0)
                return BadRequest(new { success = false, message = "لا توجد عمليات للدمج" });

            int merged = 0, failed = 0;
            var errors = new List<string>();

            foreach (var dto in items)
            {
                try
                {
                    var original = await _unitOfWork.SubscriptionLogs.AsQueryable()
                        .FirstOrDefaultAsync(l => l.Id == dto.OriginalId && !l.IsDeleted);
                    var duplicate = await _unitOfWork.SubscriptionLogs.AsQueryable()
                        .FirstOrDefaultAsync(l => l.Id == dto.DuplicateId && !l.IsDeleted);

                    if (original == null || duplicate == null) { failed++; continue; }

                    if (string.IsNullOrEmpty(original.FtthTransactionId) && !string.IsNullOrEmpty(duplicate.FtthTransactionId))
                        original.FtthTransactionId = duplicate.FtthTransactionId;
                    if (string.IsNullOrEmpty(original.CustomerId) && !string.IsNullOrEmpty(duplicate.CustomerId))
                        original.CustomerId = duplicate.CustomerId;
                    if (string.IsNullOrEmpty(original.SubscriptionId) && !string.IsNullOrEmpty(duplicate.SubscriptionId))
                        original.SubscriptionId = duplicate.SubscriptionId;
                    if (string.IsNullOrEmpty(original.ZoneId) && !string.IsNullOrEmpty(duplicate.ZoneId))
                        original.ZoneId = duplicate.ZoneId;
                    if (string.IsNullOrEmpty(original.ZoneName) && !string.IsNullOrEmpty(duplicate.ZoneName))
                        original.ZoneName = duplicate.ZoneName;
                    if (string.IsNullOrEmpty(original.DeviceUsername) && !string.IsNullOrEmpty(duplicate.DeviceUsername))
                        original.DeviceUsername = duplicate.DeviceUsername;
                    if (string.IsNullOrEmpty(original.PhoneNumber) && !string.IsNullOrEmpty(duplicate.PhoneNumber))
                        original.PhoneNumber = duplicate.PhoneNumber;
                    if (string.IsNullOrEmpty(original.StartDate) && !string.IsNullOrEmpty(duplicate.StartDate))
                        original.StartDate = duplicate.StartDate;
                    if (string.IsNullOrEmpty(original.EndDate) && !string.IsNullOrEmpty(duplicate.EndDate))
                        original.EndDate = duplicate.EndDate;
                    if (original.WalletBalanceAfter == null && duplicate.WalletBalanceAfter != null)
                        original.WalletBalanceAfter = duplicate.WalletBalanceAfter;

                    original.IsReconciled = true;
                    original.ReconciliationNotes = $"دمج تلقائي — حُذفت المكررة #{duplicate.Id}";
                    _unitOfWork.SubscriptionLogs.Update(original);

                    duplicate.IsDeleted = true;
                    _unitOfWork.SubscriptionLogs.Update(duplicate);

                    if (duplicate.JournalEntryId.HasValue)
                    {
                        var je = await _unitOfWork.JournalEntries.GetByIdAsync(duplicate.JournalEntryId.Value);
                        if (je != null && je.Status != JournalEntryStatus.Voided)
                        {
                            je.Status = JournalEntryStatus.Voided;
                            je.Notes = (je.Notes ?? "") + " | ملغي — دمج مكررات";
                            _unitOfWork.JournalEntries.Update(je);
                        }
                    }

                    merged++;
                }
                catch (Exception ex)
                {
                    failed++;
                    errors.Add($"#{dto.OriginalId}←#{dto.DuplicateId}: {ex.Message}");
                }
            }

            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = $"تم دمج {merged} عملية، فشل {failed}", merged, failed, errors = errors.Take(5).ToList() });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في دمج العمليات المكررة");
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
                .FirstOrDefaultAsync(a => a.Code.StartsWith(AccountCodes.Cash)
                    && a.Description == dto.OperatorUserId.ToString()
                    && a.CompanyId == dto.CompanyId && a.IsActive);

            if (operatorAccount == null)
            {
                // إنشاء حساب صندوق للمشغل تلقائياً
                operatorAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(
                    _unitOfWork, AccountCodes.Cash, dto.OperatorUserId, $"صندوق {user.FullName}", dto.CompanyId);
                await _unitOfWork.SaveChangesAsync();
            }

            // صندوق الشركة (11104)
            var mainCashAccount = await _unitOfWork.Accounts.AsQueryable()
                .FirstOrDefaultAsync(a => a.Code == AccountCodes.CompanyMainCash && a.IsActive
                    && a.CompanyId == dto.CompanyId);
            if (mainCashAccount == null)
                return BadRequest(new { success = false, message = "لا يوجد حساب صندوق الشركة (11104)" });

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
                .FirstOrDefaultAsync(a => a.Code.StartsWith(AccountCodes.OperatorReceivables)
                    && a.Description == dto.OperatorUserId.ToString()
                    && a.CompanyId == dto.CompanyId && a.IsActive);

            if (debtAccount == null)
                return BadRequest(new { success = false, message = "لا يوجد حساب ذمة لهذا المشغل" });

            // صندوق الشركة الرئيسي (11104) - التحصيل يذهب مباشرة للشركة
            var mainCashBox = await _unitOfWork.Accounts.AsQueryable()
                .FirstOrDefaultAsync(a => a.Code == AccountCodes.CompanyMainCash && a.IsActive
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
            var cashBoxTotal = GetParentBalance(AccountCodes.Cash);
            var cashBoxDetails = GetSubAccountDetails(AccountCodes.Cash, "صناديق المشغلين");

            var operatorDebtTotal = GetParentBalance(AccountCodes.OperatorReceivables);
            var operatorDebtDetails = GetSubAccountDetails(AccountCodes.OperatorReceivables, "ذمم المشغلين");

            var agentDebtTotal = GetParentBalance(AccountCodes.AgentReceivables);
            var agentDebtDetails = GetSubAccountDetails(AccountCodes.AgentReceivables, "ذمم الوكلاء");

            var techDebtTotal = GetParentBalance(AccountCodes.TechnicianReceivables);
            var techDebtDetails = GetSubAccountDetails(AccountCodes.TechnicianReceivables, "ذمم الفنيين");

            var electronicTotal = GetParentBalance(AccountCodes.ElectronicPayment);
            var electronicDetails = GetSubAccountDetails(AccountCodes.ElectronicPayment, "الدفع الإلكتروني");

            var renewalRevenue = GetParentBalance(AccountCodes.MaintenanceRevenue);
            var purchaseRevenue = GetParentBalance(AccountCodes.CompanyDiscountRevenue);

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
                        log.LinkedAgentId, log.LinkedTechnicianId,
                        log.PlanPrice, 0, 0, log.MaintenanceFee ?? 0, true);

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

    [HttpPost("fix-missing-accounting")]
    [Authorize(Policy = "CompanyAdminOrAbove")]
    public async Task<IActionResult> FixMissingAccounting([FromQuery] Guid? companyId)
    {
        try
        {
            var logsWithout = await _unitOfWork.SubscriptionLogs.AsQueryable()
                .Where(l => l.FtthTransactionId != null && l.JournalEntryId == null
                    && !l.IsDeleted && l.UserId.HasValue && l.CompanyId.HasValue
                    && l.PlanPrice > 0 && l.PlanName != null && l.PlanName.ToUpper().Contains("FIBER"))
                .ToListAsync();

            if (!logsWithout.Any())
                return Ok(new { success = true, message = "لا توجد عمليات بدون قيود", fixed_count = 0 });

            int fixedCount = 0;
            foreach (var log in logsWithout)
            {
                try
                {
                    var dto = new FtthLogWithAccountingDto(
                        log.CustomerId, log.CustomerName, null,
                        log.SubscriptionId, log.PlanName, log.PlanPrice,
                        null, null, null,
                        log.DeviceUsername, log.OperationType, log.ActivatedBy,
                        log.ActivationDate, null, null,
                        log.ZoneId, null, null, null, null,
                        null, log.WalletBalanceAfter,
                        null, null,
                        null, log.PaymentMethod, null, null,
                        log.UserId, log.CompanyId, false, false,
                        null, log.StartDate, log.EndDate,
                        null, null,
                        log.CollectionType ?? "cash", log.FtthTransactionId, null,
                        null, null,
                        log.PlanPrice ?? 0, 0, 0, 0, true);

                    var jeId = await CreateAccountingEntry(log, dto);
                    if (jeId.HasValue)
                    {
                        log.JournalEntryId = jeId;
                        _unitOfWork.SubscriptionLogs.Update(log);
                        await _unitOfWork.SaveChangesAsync();
                        fixedCount++;
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "فشل إصلاح قيد للسجل {LogId}", log.Id);
                }
            }

            return Ok(new { success = true, message = $"تم إصلاح {fixedCount} من {logsWithout.Count} عملية", fixed_count = fixedCount, total = logsWithout.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إصلاح القيود المفقودة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
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
    Guid? LinkedTechnicianId,
    // حقول التسعير التفصيلية
    decimal? BasePrice,            // سعر الباقة الأساسي (قبل أي خصم)
    decimal? CompanyDiscount,      // خصم الشركة (FTTH)
    decimal? ManualDiscount,       // خصم اختياري (منّا)
    decimal? MaintenanceFee,       // رسوم صيانة المنطقة
    bool SystemDiscountEnabled = true  // هل خصم الشركة مفعّل للعميل؟
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
    string? CollectionType,
    string? OperatorUserId = null,
    string? PaymentMethod = null,
    DateTime? StartDate = null,
    DateTime? EndDate = null,
    decimal? RemainingBalance = null,
    bool CreateAccounting = false,
    // حقول إضافية للمزامنة الشاملة
    string? PhoneNumber = null,
    string? ZoneName = null,
    string? TechnicianName = null,
    string? PaymentStatus = null,
    int? CommitmentPeriod = null
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

public record FixBasePriceItem(
    long LogId,
    decimal FtthAmount
);

public record MergeDuplicateDto(
    long OriginalId,
    long DuplicateId
);

public class UpdateFtthLogRequest
{
    // بيانات العميل
    public string? CustomerName { get; set; }
    public string? PhoneNumber { get; set; }
    // بيانات الاشتراك
    public string? PlanName { get; set; }
    public decimal? PlanPrice { get; set; }
    public int? CommitmentPeriod { get; set; }
    public string? OperationType { get; set; }
    public string? ActivatedBy { get; set; }
    public DateTime? ActivationDate { get; set; }
    public string? ZoneId { get; set; }
    // التحصيل والربط
    public string? CollectionType { get; set; }
    public Guid? LinkedTechnicianId { get; set; }
    public Guid? LinkedAgentId { get; set; }
    public string? TechnicianName { get; set; }
    public string? PaymentStatus { get; set; }
    public string? PaymentMethod { get; set; }
    // حالات
    public bool? IsPrinted { get; set; }
    public bool? IsWhatsAppSent { get; set; }
    public bool? IsReconciled { get; set; }
    public string? ReconciliationNotes { get; set; }
    public string? SubscriptionNotes { get; set; }
    // محاسبية
    public decimal? BasePrice { get; set; }
    public decimal? CompanyDiscount { get; set; }
    public decimal? ManualDiscount { get; set; }
    public decimal? MaintenanceFee { get; set; }
    // تكرار
    public int? RenewalCycleMonths { get; set; }
    public int? PaidMonths { get; set; }
    // flag لتحديد إذا أُرسل الحقل فعلاً (لتمييز null المُرسل عن null غير المُرسل)
    public bool HasLinkedTechnicianId { get; set; }
    public bool HasLinkedAgentId { get; set; }
}
