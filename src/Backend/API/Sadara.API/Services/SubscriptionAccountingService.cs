using Microsoft.EntityFrameworkCore;
using Sadara.API.Constants;
using Sadara.API.Controllers;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Services;

/// <summary>
/// خدمة محاسبة الاشتراكات المشتركة — القيد المزدوج الموحّد لتفعيل/تجديد الاشتراكات
/// (FTTH والساس معاً، دفتر واحد / نفس شجرة الحسابات / نفس المنطق).
///
/// المنطق منقول حرفياً من <c>FtthAccountingController.CreateAccountingEntry</c> (المرجع الأدق)
/// ليُعاد استخدامه من مسار الساس (<c>SasAgentController.ActivateBilled</c>) دون لمس نقاط FTTH القائمة.
/// توحيد FTTH عليها دَين مؤجّل (لا يُفرض الآن تفادياً لأي انحدار).
///
/// المعادلات (مطابقة للمرجع):
///   netFromCompany        = BasePrice > 0 ? BasePrice − CompanyDiscount
///                           : SystemDiscountEnabled ? PlanPrice : PlanPrice − CompanyDiscount
///   companyDiscountProfit = SystemDiscountEnabled ? 0 : CompanyDiscount
///   revenue               = MaintenanceFee + companyDiscountProfit
///   collectedAmount       = netFromCompany + revenue − ManualDiscount
///
/// القيد (Posted فوراً، متوازن جبرياً):
///   مدين  حساب التحصيل (حسب CollectionType)   = collectedAmount
///   مدين  مصاريف العروض 5110                   = ManualDiscount
///   دائن  رصيد الصفحة   11102                   = netFromCompany
///   دائن  إيراد الصيانة 4110                    = MaintenanceFee
///   دائن  إيراد خصم الشركة 4120                 = companyDiscountProfit
///
/// العزل: <paramref name="companyId"/> / <paramref name="userId"/> يُمرَّران صراحةً (مختومان من المستدعي
/// خادمياً، لا من العميل) ويُستخدمان في كل مساعد (FindOrCreateSubAccount/FindAccountByCode/
/// CreateAndPostJournalEntry) — نفس نمط FTTH (لا فلتر تلقائي).
/// </summary>
public interface ISubscriptionAccountingService
{
    /// <summary>
    /// يُنشئ القيد المحاسبي المزدوج لسجل اشتراك (FTTH أو ساس) ويعيد معرّف القيد المُنشأ، أو null
    /// عند غياب حساب جوهري (رصيد الصفحة 11102) أو تعذّر توازن القيد.
    ///
    /// ⚠️ لا يحفظ أو يربط <c>JournalEntryId</c> على السجل نفسه — المستدعي مسؤول عن ذلك (كما في FTTH)
    /// ليتحكّم بدورة حياة المعاملة (try/catch لإبقاء السجل حتى لو فشل القيد).
    /// </summary>
    /// <param name="log">سجل الاشتراك (مُنشأ ومحفوظ مسبقاً — نحتاج <c>Id</c> مرجعاً للقيد).</param>
    /// <param name="input">حقول التسعير/التحصيل (تُشتق عادةً من نفس السجل، ومُمرَّرة صراحةً للوضوح).</param>
    /// <param name="companyId">معرّف الشركة (العزل) — مختوم خادمياً.</param>
    /// <param name="userId">معرّف المستخدم المُنفِّذ (منشئ القيد) — مختوم خادمياً.</param>
    Task<Guid?> RecordAsync(
        SubscriptionLog log,
        SubscriptionAccountingInput input,
        Guid companyId,
        Guid userId,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// مدخلات التسعير/التحصيل لقيد الاشتراك (مجمّعة في بنية واحدة للوضوح).
/// القيم الافتراضية صفرية/آمنة؛ المستدعي يملؤها عادةً من حقول <see cref="SubscriptionLog"/> نفسها.
/// </summary>
public sealed class SubscriptionAccountingInput
{
    /// <summary>السعر الأساسي للباقة (كلفة الوكيل/«رصيد الصفحة»).</summary>
    public decimal BasePrice { get; init; }

    /// <summary>خصم الشركة.</summary>
    public decimal CompanyDiscount { get; init; }

    /// <summary>خصم يدوي اختياري (منّا للعميل).</summary>
    public decimal ManualDiscount { get; init; }

    /// <summary>أجور الصيانة/الهامش.</summary>
    public decimal MaintenanceFee { get; init; }

    /// <summary>سعر الباقة المعروض/المُحصَّل الخام (يُستخدم عند BasePrice=0 — منطق البديل).</summary>
    public decimal PlanPrice { get; init; }

    /// <summary>هل خصم الشركة مفعّل (ممرّر للعميل)؟ عند false يتحوّل الخصم إلى ربح شركة (4120).</summary>
    public bool SystemDiscountEnabled { get; init; } = true;

    /// <summary>نوع التحصيل: cash | credit | master | agent | technician.</summary>
    public string CollectionType { get; init; } = "cash";

    /// <summary>الوكيل المرتبط (مطلوب عند CollectionType=agent).</summary>
    public Guid? LinkedAgentId { get; init; }

    /// <summary>الفني المرتبط (مطلوب عند CollectionType=technician).</summary>
    public Guid? LinkedTechnicianId { get; init; }

    /// <summary>اسم الباقة (للوصف).</summary>
    public string? PlanName { get; init; }

    /// <summary>اسم العميل/المشترك (للوصف).</summary>
    public string? CustomerName { get; init; }

    /// <summary>نوع العملية (purchase/renewal/…) — للوصف وتصنيف معاملة الوكيل.</summary>
    public string? OperationType { get; init; }

    /// <summary>اسم المُفعِّل الاحتياطي (fallback) إن تعذّر إيجاد اسم المستخدم.</summary>
    public string? ActivatedBy { get; init; }

    /// <summary>تاريخ القيد (اختياري) — إن null يُحتسب تاريخ اليوم بتوقيت بغداد.</summary>
    public DateTime? EntryDate { get; init; }
}

/// <inheritdoc cref="ISubscriptionAccountingService"/>
public sealed class SubscriptionAccountingService : ISubscriptionAccountingService
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<SubscriptionAccountingService> _logger;

    public SubscriptionAccountingService(IUnitOfWork unitOfWork, ILogger<SubscriptionAccountingService> logger)
    {
        _unitOfWork = unitOfWork;
        _logger = logger;
    }

    /// <inheritdoc />
    public async Task<Guid?> RecordAsync(
        SubscriptionLog log,
        SubscriptionAccountingInput input,
        Guid companyId,
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        var collectionType = string.IsNullOrWhiteSpace(input.CollectionType) ? "cash" : input.CollectionType;

        // اسم المشغل: أولوية FullName من User > ActivatedBy
        var operatorUser = await _unitOfWork.Users.AsQueryable()
            .Where(u => u.Id == userId)
            .Select(u => new { u.FullName })
            .FirstOrDefaultAsync(cancellationToken);
        var operatorName = operatorUser?.FullName ?? input.ActivatedBy ?? "مشغل";
        var planName = input.PlanName ?? "اشتراك";
        var customerName = input.CustomerName ?? "عميل";
        var opType = input.OperationType?.ToLower() == "purchase" ? "شراء" : "تجديد";

        // ═══ حساب المبالغ ═══
        var basePrice = input.BasePrice;
        var companyDiscount = input.CompanyDiscount;
        var manualDiscount = input.ManualDiscount;
        var maintenanceFee = input.MaintenanceFee;
        var systemDiscountEnabled = input.SystemDiscountEnabled;

        // المستقطع من رصيد الصفحة (ثابت!)
        decimal netFromCompany;
        if (basePrice > 0)
            netFromCompany = basePrice - companyDiscount;
        else if (systemDiscountEnabled)
            netFromCompany = input.PlanPrice;
        else
            netFromCompany = input.PlanPrice - companyDiscount;
        if (netFromCompany <= 0) netFromCompany = input.PlanPrice;

        // ربح خصم الشركة = خصم الشركة عند عدم تفعيله
        var companyDiscountProfit = systemDiscountEnabled ? 0 : companyDiscount;

        // الإيرادات = أجور صيانة + خصم شركة (إذا لم يُمرر)
        var revenue = maintenanceFee + companyDiscountProfit;

        // حماية: الخصم اليدوي لا يتجاوز الإجمالي المتاح (لضمان توازن القيد)
        var maxDiscount = netFromCompany + revenue;
        if (manualDiscount > maxDiscount)
        {
            _logger.LogWarning("خصم يدوي {Discount} أكبر من الإجمالي {Max} — تم تقليصه تلقائياً. عملية={LogId}",
                manualDiscount, maxDiscount, log.Id);
            manualDiscount = maxDiscount;
        }

        // الإجمالي = المستقطع + الإيرادات - المصاريف (ما يدفعه العميل)
        var collectedAmount = netFromCompany + revenue - manualDiscount;

        // ═══ جلب الحسابات ═══
        // دائن: رصيد الصفحة الداخلي (11102) — حساب جوهري؛ غيابه يُلغي القيد
        var pageBalanceAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.PageBalance, companyId);
        if (pageBalanceAccount == null)
        {
            _logger.LogWarning("حساب رصيد الصفحة 11102 غير موجود للشركة {CompanyId}", companyId);
            return null;
        }

        // دائن: إيراد صيانة (4110)
        var maintenanceRevenueAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.MaintenanceRevenue, companyId);
        if (maintenanceRevenueAccount == null)
            _logger.LogWarning("حساب إيراد الصيانة 4110 غير موجود — سيتم تجاهل رسوم الصيانة في القيد");

        // دائن: إيراد خصم الشركة (4120)
        var discountRevenueAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.CompanyDiscountRevenue, companyId);
        if (discountRevenueAccount == null)
            _logger.LogWarning("حساب إيراد خصم الشركة 4120 غير موجود — سيتم تجاهل ربح الخصم في القيد");

        // مدين: مصاريف عروض (5110)
        var promotionExpenseAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.PromotionExpense, companyId);
        if (promotionExpenseAccount == null)
            _logger.LogWarning("حساب مصاريف العروض 5110 غير موجود — سيتم تجاهل الخصم الاختياري في القيد");

        // ═══ تحديد حساب التحصيل (الطرف المدين الرئيسي) ═══
        Account debitAccount;
        string description;

        switch (collectionType.ToLower())
        {
            case "cash":
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.Cash, userId, $"صندوق {operatorName}", companyId);
                await _unitOfWork.SaveChangesAsync(cancellationToken);
                description = $"{opType} {planName} - {customerName} - نقد عبر {operatorName}";
                break;

            case "credit":
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.OperatorReceivables, userId, $"ذمة {operatorName}", companyId);
                await _unitOfWork.SaveChangesAsync(cancellationToken);
                description = $"{opType} {planName} - {customerName} - آجل على {operatorName}";
                break;

            case "master":
                debitAccount = await ServiceRequestAccountingHelper.FindAccountByCode(_unitOfWork, AccountCodes.ElectronicPayment, companyId)
                    ?? throw new Exception("حساب صندوق الدفع الإلكتروني 1170 غير موجود");
                description = $"{opType} {planName} - {customerName} - ماستر (إلكتروني)";
                break;

            case "agent":
                if (!input.LinkedAgentId.HasValue)
                    throw new Exception("يجب تحديد الوكيل عند اختيار نوع الدفع 'وكيل'");

                var agent = await _unitOfWork.Agents.GetByIdAsync(input.LinkedAgentId.Value, cancellationToken);
                if (agent == null)
                    throw new Exception("الوكيل غير موجود");

                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.AgentReceivables, agent.Id, agent.Name, companyId);
                await _unitOfWork.SaveChangesAsync(cancellationToken);
                description = $"{opType} {planName} - {customerName} - على وكيل {agent.Name} عبر {operatorName}";

                // تحديث رصيد الوكيل + إنشاء AgentTransaction
                agent.TotalCharges += collectedAmount;
                agent.NetBalance = agent.TotalPayments - agent.TotalCharges;
                _unitOfWork.Agents.Update(agent);

                var agentTx = new AgentTransaction
                {
                    AgentId = agent.Id,
                    CompanyId = agent.CompanyId,
                    Type = TransactionType.Charge,
                    Category = input.OperationType?.ToLower() == "purchase"
                        ? TransactionCategory.NewSubscription
                        : TransactionCategory.RenewalSubscription,
                    Amount = collectedAmount,
                    BalanceAfter = agent.NetBalance,
                    Description = $"{opType} {planName} - {customerName}",
                    ReferenceNumber = log.Id.ToString(),
                    CreatedById = userId,
                    Notes = $"تفعيل عبر {operatorName}"
                };
                await _unitOfWork.AgentTransactions.AddAsync(agentTx, cancellationToken);
                break;

            case "technician":
                if (!input.LinkedTechnicianId.HasValue)
                    throw new Exception("يجب تحديد الفني عند اختيار نوع الدفع 'فني'");

                var tech = await _unitOfWork.Users.GetByIdAsync(input.LinkedTechnicianId.Value, cancellationToken);
                if (tech == null)
                    throw new Exception("الفني غير موجود");

                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.TechnicianReceivables, tech.Id, tech.FullName, companyId);
                await _unitOfWork.SaveChangesAsync(cancellationToken);
                description = $"{opType} {planName} - {customerName} - على فني {tech.FullName} عبر {operatorName}";

                // تحديث رصيد الفني + إنشاء TechnicianTransaction
                tech.TechTotalCharges += collectedAmount;
                tech.TechNetBalance = tech.TechTotalPayments - tech.TechTotalCharges;
                _unitOfWork.Users.Update(tech);

                var techCompanyId = companyId != Guid.Empty ? companyId : (tech.CompanyId ?? companyId);
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
                    CompanyId = techCompanyId,
                    CreatedAt = DateTime.UtcNow
                };
                await _unitOfWork.TechnicianTransactions.AddAsync(techTx, cancellationToken);
                break;

            default:
                debitAccount = await ServiceRequestAccountingHelper.FindOrCreateSubAccount(_unitOfWork, AccountCodes.Cash, userId, $"صندوق {operatorName}", companyId);
                await _unitOfWork.SaveChangesAsync(cancellationToken);
                description = $"{opType} {planName} - {customerName} - عبر {operatorName}";
                break;
        }

        // ═══ بناء سطور القيد ═══
        var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>();

        // مدين: حساب التحصيل (المبلغ المحصّل من العميل) — دائماً
        lines.Add((debitAccount.Id, Math.Max(collectedAmount, 0), 0, $"{debitAccount.Name} - {opType} {planName}"));

        // مدين: مصاريف عروض (الخصم الاختياري) — دائماً
        if (promotionExpenseAccount != null)
            lines.Add((promotionExpenseAccount.Id, manualDiscount, 0, $"خصم اختياري - {customerName}"));

        // دائن: رصيد الصفحة (صافي الشركة) — دائماً
        lines.Add((pageBalanceAccount.Id, 0, Math.Max(netFromCompany, 0), $"خصم من رصيد الصفحة - {opType} {planName}"));

        // دائن: إيراد صيانة — دائماً (حتى لو 0) لتسهيل التعديل لاحقاً
        if (maintenanceRevenueAccount != null)
            lines.Add((maintenanceRevenueAccount.Id, 0, maintenanceFee, $"إيراد صيانة - {customerName}"));

        // دائن: إيراد خصم الشركة — دائماً (حتى لو 0) لتسهيل التعديل لاحقاً
        if (discountRevenueAccount != null)
            lines.Add((discountRevenueAccount.Id, 0, companyDiscountProfit, $"إيراد خصم الشركة - {customerName}"));

        if (lines.Count < 2)
        {
            _logger.LogWarning("لا توجد سطور كافية للقيد المحاسبي — تم التخطي");
            return null;
        }

        // ═══ فحص التوازن قبل الحفظ ═══
        var checkDebit = lines.Sum(l => l.DebitAmount);
        var checkCredit = lines.Sum(l => l.CreditAmount);
        if (checkDebit != checkCredit)
        {
            _logger.LogError("⛔ قيد غير متوازن! مدين={Debit} دائن={Credit} عملية={LogId} عميل={Customer}",
                checkDebit, checkCredit, log.Id, customerName);
            // تصحيح تلقائي: إذا الفرق = ManualDiscount ومصاريف العروض مفقودة → إضافتها
            var diff = checkCredit - checkDebit;
            if (diff > 0 && promotionExpenseAccount != null && diff == manualDiscount)
            {
                var promoIdx = lines.FindIndex(l => l.AccountId == promotionExpenseAccount.Id);
                if (promoIdx >= 0)
                    lines[promoIdx] = (promotionExpenseAccount.Id, diff, 0, $"خصم اختياري - {customerName}");
                else
                    lines.Add((promotionExpenseAccount.Id, diff, 0, $"خصم اختياري - {customerName}"));
            }
            else
            {
                _logger.LogError("⛔ تم إلغاء إنشاء القيد — فرق غير قابل للتصحيح: {Diff}", diff);
                return null;
            }
        }

        // تاريخ القيد = تاريخ المعاملة (بتوقيت بغداد UTC+3) بدلاً من تاريخ اليوم
        DateTime? entryDate = null;
        if (input.EntryDate.HasValue)
        {
            entryDate = DateTime.SpecifyKind(
                input.EntryDate.Value.AddHours(3).Date.AddHours(12 - 3),
                DateTimeKind.Utc);
        }

        // ═══ نوع المرجع حسب المصدر: الساس => SasSubscription، FTTH => FtthSubscription ═══
        var referenceType = log.Source == SubscriptionLogSource.Sas
            ? JournalReferenceType.SasSubscription
            : JournalReferenceType.FtthSubscription;

        // إنشاء القيد
        await ServiceRequestAccountingHelper.CreateAndPostJournalEntry(
            _unitOfWork, companyId, userId, description,
            referenceType, log.Id.ToString(), lines,
            entryDate);

        await _unitOfWork.SaveChangesAsync(cancellationToken);

        // جلب القيد المُنشأ وربطه بالمعاملات
        var entry = await _unitOfWork.JournalEntries.AsQueryable()
            .Where(j => j.ReferenceType == referenceType
                && j.ReferenceId == log.Id.ToString()
                && j.CompanyId == companyId)
            .OrderByDescending(j => j.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);

        // ربط JournalEntryId بالمعاملات المُنشأة
        if (entry != null)
        {
            var linkedTechTx = await _unitOfWork.TechnicianTransactions.AsQueryable()
                .FirstOrDefaultAsync(t => t.ReferenceNumber == log.Id.ToString() && t.JournalEntryId == null && !t.IsDeleted, cancellationToken);
            if (linkedTechTx != null)
            {
                linkedTechTx.JournalEntryId = entry.Id;
                _unitOfWork.TechnicianTransactions.Update(linkedTechTx);
            }

            var linkedAgentTx = await _unitOfWork.AgentTransactions.AsQueryable()
                .FirstOrDefaultAsync(t => t.ReferenceNumber == log.Id.ToString() && t.JournalEntryId == null && !t.IsDeleted, cancellationToken);
            if (linkedAgentTx != null)
            {
                linkedAgentTx.JournalEntryId = entry.Id;
                _unitOfWork.AgentTransactions.Update(linkedAgentTx);
            }

            await _unitOfWork.SaveChangesAsync(cancellationToken);
        }

        return entry?.Id;
    }
}
