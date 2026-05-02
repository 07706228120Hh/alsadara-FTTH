using Sadara.Domain.Entities;

namespace Sadara.API.Constants;

/// <summary>
/// أكواد الحسابات الثابتة المستخدمة في النظام المحاسبي
/// بدلاً من تكرار الأكواد النصية في كل Controller
/// </summary>
public static class AccountCodes
{
    // ═══════════════════════════════════════════
    // الأصول - Assets (1000)
    // ═══════════════════════════════════════════

    /// <summary>النقد والصندوق - أب لجميع الصناديق</summary>
    public const string Cash = "1110";

    /// <summary>القاصة</summary>
    public const string PettyCash = "11101";

    /// <summary>رصيد الصفحة - المحور المركزي للتفعيلات</summary>
    public const string PageBalance = "11102";

    /// <summary>صندوق الشركة الرئيسي - يستقبل الكاش من المشغلين</summary>
    public const string CompanyMainCash = "11104";

    /// <summary>تحصيلات تحت التسليم - أب لحسابات الفنيين</summary>
    public const string TechnicianReceivables = "1140";

    /// <summary>ذمم الوكلاء - أب لحسابات الوكلاء</summary>
    public const string AgentReceivables = "1150";

    /// <summary>ذمم المشغلين - أب لحسابات ذمم المشغلين</summary>
    public const string OperatorReceivables = "1160";

    /// <summary>صندوق الدفع الإلكتروني (ماستر كارد)</summary>
    public const string ElectronicPayment = "1170";

    // ═══════════════════════════════════════════
    // الالتزامات - Liabilities (2000)
    // ═══════════════════════════════════════════

    /// <summary>رواتب مستحقة</summary>
    public const string SalariesPayable = "2120";

    /// <summary>مصاريف ثابتة مستحقة - أب</summary>
    public const string AccruedFixedExpenses = "2200";

    /// <summary>إيجار مستحق</summary>
    public const string RentPayable = "2210";

    /// <summary>تكلفة مولد مستحقة</summary>
    public const string GeneratorPayable = "2220";

    /// <summary>إنترنت مستحق</summary>
    public const string InternetPayable = "2230";

    /// <summary>كهرباء مستحقة</summary>
    public const string ElectricityPayable = "2240";

    /// <summary>ماء مستحق</summary>
    public const string WaterPayable = "2250";

    /// <summary>مصاريف ثابتة أخرى مستحقة</summary>
    public const string OtherFixedPayable = "2260";

    // ═══════════════════════════════════════════
    // الإيرادات - Revenue (4000)
    // ═══════════════════════════════════════════

    /// <summary>إيرادات التجديد / إيراد الصيانة</summary>
    public const string MaintenanceRevenue = "4110";

    /// <summary>إيرادات الشراء / إيراد خصم الشركة</summary>
    public const string CompanyDiscountRevenue = "4120";

    // ═══════════════════════════════════════════
    // المصروفات - Expenses (5000)
    // ═══════════════════════════════════════════

    /// <summary>الرواتب والأجور</summary>
    public const string SalaryExpense = "5100";

    /// <summary>مصاريف العروض والخصومات الترويجية</summary>
    public const string PromotionExpense = "5110";

    /// <summary>إيجار</summary>
    public const string RentExpense = "5200";

    /// <summary>إيجار مكاتب</summary>
    public const string OfficeRentExpense = "5210";

    /// <summary>مولد</summary>
    public const string GeneratorExpense = "5220";

    /// <summary>إنترنت</summary>
    public const string InternetExpense = "5230";

    /// <summary>كهرباء</summary>
    public const string ElectricityExpense = "5240";

    /// <summary>ماء</summary>
    public const string WaterExpense = "5250";

    /// <summary>مصروفات متنوعة (fallback)</summary>
    public const string MiscExpense = "5700";

    /// <summary>عمولات الوكلاء</summary>
    public const string AgentCommissions = "5900";

    // ═══════════════════════════════════════════
    // الحسابات المعروفة غير المشغلين تحت 1110
    // ═══════════════════════════════════════════

    /// <summary>
    /// أكواد معروفة تحت 1110 ليست حسابات مشغلين
    /// تُستخدم لاستثنائها عند حساب مستحقات المشغلين
    /// </summary>
    public static readonly HashSet<string> KnownNonOperatorCashCodes = new()
    {
        Cash,           // 1110
        PettyCash,      // 11101
        PageBalance,    // 11102
        "11103",        // صندوق (محجوز)
        CompanyMainCash // 11104
    };

    // ═══════════════════════════════════════════
    // Helper: ربط فئات المصاريف الثابتة بأكواد المصروفات
    // ═══════════════════════════════════════════

    /// <summary>
    /// يُرجع كود حساب المصروف المقابل لفئة المصروف الثابت
    /// </summary>
    public static string GetFixedExpenseAccountCode(FixedExpenseCategory category) => category switch
    {
        FixedExpenseCategory.OfficeRent => OfficeRentExpense,
        FixedExpenseCategory.GeneratorCost => GeneratorExpense,
        FixedExpenseCategory.Internet => InternetExpense,
        FixedExpenseCategory.Electricity => ElectricityExpense,
        FixedExpenseCategory.Water => WaterExpense,
        _ => RentExpense
    };

    /// <summary>
    /// يُرجع كود حساب الالتزام المقابل لفئة المصروف الثابت
    /// </summary>
    public static string GetFixedExpenseLiabilityCode(FixedExpenseCategory category) => category switch
    {
        FixedExpenseCategory.OfficeRent => RentPayable,
        FixedExpenseCategory.GeneratorCost => GeneratorPayable,
        FixedExpenseCategory.Internet => InternetPayable,
        FixedExpenseCategory.Electricity => ElectricityPayable,
        FixedExpenseCategory.Water => WaterPayable,
        _ => OtherFixedPayable
    };
}
