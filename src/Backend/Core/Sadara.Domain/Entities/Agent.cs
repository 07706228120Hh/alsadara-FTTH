namespace Sadara.Domain.Entities;

// ═══════════════════════════════════════════════════════════════
// 🏪 نظام الوكلاء - Agent System
// الوكيل يدخل بوابة المواطن ويجري عمليات
// تظهر في شاشة الشركة + مدير النظام
// ═══════════════════════════════════════════════════════════════

/// <summary>
/// نوع الوكيل
/// </summary>
public enum AgentType
{
    /// <summary>وكيل خاص</summary>
    Private = 0,
    
    /// <summary>وكيل عام</summary>
    Public = 1
}

/// <summary>
/// حالة الوكيل
/// </summary>
public enum AgentStatus
{
    /// <summary>نشط</summary>
    Active = 0,
    
    /// <summary>معلق</summary>
    Suspended = 1,
    
    /// <summary>محظور</summary>
    Banned = 2,
    
    /// <summary>غير مفعل</summary>
    Inactive = 3
}

/// <summary>
/// الوكيل - يعمل كوسيط بين الشركة والمواطنين
/// يدخل بوابة المواطن ويجري العمليات (تسجيل، تحصيل، صيانة...)
/// كل وكيل له حساب مالي (أجور عليه + تسديد منه = صافي)
/// </summary>
public class Agent : BaseEntity<Guid>
{
    // ============ معلومات أساسية ============
    
    /// <summary>كود الوكيل (يتولد تلقائياً) مثل AGT-0001</summary>
    public string AgentCode { get; set; } = string.Empty;
    
    /// <summary>اسم الوكيل</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>نوع الوكيل</summary>
    public AgentType Type { get; set; } = AgentType.Private;
    
    /// <summary>رقم الهاتف (يُستخدم لتسجيل الدخول)</summary>
    public string PhoneNumber { get; set; } = string.Empty;
    
    /// <summary>كلمة المرور المشفرة</summary>
    public string PasswordHash { get; set; } = string.Empty;
    
    /// <summary>البريد الإلكتروني</summary>
    public string? Email { get; set; }
    
    // ============ الموقع ============
    
    /// <summary>المدينة / المحافظة</summary>
    public string? City { get; set; }
    
    /// <summary>المنطقة / الحي</summary>
    public string? Area { get; set; }
    
    /// <summary>العنوان التفصيلي</summary>
    public string? FullAddress { get; set; }
    
    /// <summary>خط العرض</summary>
    public double? Latitude { get; set; }
    
    /// <summary>خط الطول</summary>
    public double? Longitude { get; set; }
    
    // ============ معرف الصفحة والشركة ============
    
    /// <summary>معرف الصفحة (للربط مع نظام خارجي أو رقم صفحة)</summary>
    public string? PageId { get; set; }
    
    /// <summary>الشركة التي يتبع لها الوكيل</summary>
    public Guid CompanyId { get; set; }
    
    // ============ الحالة ============
    
    /// <summary>حالة الوكيل</summary>
    public AgentStatus Status { get; set; } = AgentStatus.Active;
    
    /// <summary>صورة الوكيل</summary>
    public string? ProfileImageUrl { get; set; }
    
    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }
    
    /// <summary>آخر تسجيل دخول</summary>
    public DateTime? LastLoginAt { get; set; }
    
    // ============ الحساب المالي (ملخص محسوب) ============
    
    /// <summary>إجمالي الأجور (المبالغ المترتبة على الوكيل)</summary>
    public decimal TotalCharges { get; set; } = 0;
    
    /// <summary>إجمالي التسديدات (المبالغ التي دفعها الوكيل)</summary>
    public decimal TotalPayments { get; set; } = 0;
    
    /// <summary>الصافي = الأجور - التسديدات (موجب = عليه، سالب = له)</summary>
    public decimal NetBalance { get; set; } = 0;
    
    // ============ Navigation Properties ============
    
    /// <summary>الشركة</summary>
    public virtual Company? Company { get; set; }
    
    /// <summary>المعاملات المالية</summary>
    public virtual ICollection<AgentTransaction> Transactions { get; set; } = new List<AgentTransaction>();
}

/// <summary>
/// نوع المعاملة المالية
/// </summary>
public enum TransactionType
{
    /// <summary>أجور - مبلغ مترتب على الوكيل (صرف)</summary>
    Charge = 0,
    
    /// <summary>تسديد - الوكيل يدفع من المبلغ المترتب عليه (قبض)</summary>
    Payment = 1,
    
    /// <summary>خصم - خصم من رصيد الوكيل</summary>
    Discount = 2,
    
    /// <summary>تعديل - تعديل يدوي من المدير</summary>
    Adjustment = 3
}

/// <summary>
/// فئة المعاملة - ما سبب هذه المعاملة؟
/// </summary>
public enum TransactionCategory
{
    /// <summary>تسجيل مشترك جديد</summary>
    NewSubscription = 0,
    
    /// <summary>تجديد اشتراك</summary>
    RenewalSubscription = 1,
    
    /// <summary>صيانة</summary>
    Maintenance = 2,
    
    /// <summary>تحصيل فواتير</summary>
    BillCollection = 3,
    
    /// <summary>تركيب جديد</summary>
    Installation = 4,
    
    /// <summary>نقل خدمة</summary>
    ServiceTransfer = 5,
    
    /// <summary>تسديد نقدي</summary>
    CashPayment = 6,
    
    /// <summary>تحويل بنكي</summary>
    BankTransfer = 7,
    
    /// <summary>أخرى</summary>
    Other = 99
}

/// <summary>
/// المعاملة المالية للوكيل
/// كل عملية يقوم بها الوكيل أو تُسجل عليه تُنشئ معاملة هنا
/// </summary>
public class AgentTransaction : BaseEntity<long>
{
    /// <summary>الوكيل صاحب المعاملة</summary>
    public Guid AgentId { get; set; }
    
    /// <summary>نوع المعاملة (أجور / تسديد / خصم / تعديل)</summary>
    public TransactionType Type { get; set; }
    
    /// <summary>فئة المعاملة (سبب العملية)</summary>
    public TransactionCategory Category { get; set; }
    
    /// <summary>المبلغ (دائماً موجب)</summary>
    public decimal Amount { get; set; }
    
    /// <summary>الرصيد بعد المعاملة</summary>
    public decimal BalanceAfter { get; set; }
    
    /// <summary>وصف المعاملة</summary>
    public string Description { get; set; } = string.Empty;
    
    /// <summary>رقم المرجع (مثل رقم الفاتورة أو رقم طلب الخدمة)</summary>
    public string? ReferenceNumber { get; set; }
    
    /// <summary>معرف طلب الخدمة المرتبط (إن وجد)</summary>
    public Guid? ServiceRequestId { get; set; }
    
    /// <summary>معرف المواطن المرتبط (إن وجد)</summary>
    public Guid? CitizenId { get; set; }
    
    /// <summary>من أنشأ المعاملة (مدير / وكيل / نظام)</summary>
    public Guid? CreatedById { get; set; }
    
    /// <summary>ملاحظات إضافية</summary>
    public string? Notes { get; set; }
    
    // ============ Navigation Properties ============
    
    /// <summary>الوكيل</summary>
    public virtual Agent? Agent { get; set; }
    
    /// <summary>طلب الخدمة</summary>
    public virtual ServiceRequest? ServiceRequest { get; set; }
    
    /// <summary>المواطن</summary>
    public virtual Citizen? Citizen { get; set; }
}

// ═══════════════════════════════════════════════════════════════
// 💰 نسب عمولات الوكلاء - Agent Commission Rates
// لكل وكيل × لكل باقة = نسبة مئوية من ربح الباقة
// ═══════════════════════════════════════════════════════════════

/// <summary>
/// نسبة عمولة الوكيل لباقة معينة
/// العمولة = ProfitAmount (من InternetPlan) × CommissionPercentage / 100
/// </summary>
public class AgentCommissionRate : BaseEntity<long>
{
    /// <summary>معرف الوكيل</summary>
    public Guid AgentId { get; set; }
    
    /// <summary>معرف باقة الإنترنت</summary>
    public Guid InternetPlanId { get; set; }
    
    /// <summary>نسبة العمولة المئوية (مثال: 10 = 10%)</summary>
    public decimal CommissionPercentage { get; set; }
    
    /// <summary>معرف الشركة</summary>
    public Guid CompanyId { get; set; }
    
    /// <summary>هل مفعّل؟</summary>
    public bool IsActive { get; set; } = true;
    
    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }
    
    // ============ Navigation Properties ============
    
    /// <summary>الوكيل</summary>
    public virtual Agent? Agent { get; set; }
    
    /// <summary>باقة الإنترنت</summary>
    public virtual InternetPlan? InternetPlan { get; set; }
    
    /// <summary>الشركة</summary>
    public virtual Company? Company { get; set; }
}
