using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

/// <summary>
/// باقة اشتراك - مثل: فايبر 50 ميغا، 100 ميغا
/// </summary>
public class InternetPlan : BaseEntity<Guid>
{
    /// <summary>الشركة (null = عام)</summary>
    public Guid? CompanyId { get; set; }
    
    /// <summary>اسم الباقة</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>اسم الباقة بالعربي</summary>
    public string NameAr { get; set; } = string.Empty;
    
    /// <summary>وصف الباقة</summary>
    public string? Description { get; set; }
    
    /// <summary>صورة/أيقونة الباقة</summary>
    public string? ImageUrl { get; set; }
    
    /// <summary>السرعة (ميغابت)</summary>
    public int? SpeedMbps { get; set; }
    
    /// <summary>حد البيانات (جيجابايت، null = غير محدود)</summary>
    public int? DataLimitGB { get; set; }
    
    /// <summary>السعر الشهري</summary>
    public decimal MonthlyPrice { get; set; }
    
    /// <summary>السعر السنوي (مع خصم)</summary>
    public decimal? YearlyPrice { get; set; }
    
    /// <summary>رسوم التركيب</summary>
    public decimal InstallationFee { get; set; } = 0;
    
    /// <summary>المدة بالأشهر</summary>
    public int DurationMonths { get; set; } = 1;
    
    /// <summary>الميزات (JSON array)</summary>
    public string? Features { get; set; }
    
    /// <summary>هل مميزة؟</summary>
    public bool IsFeatured { get; set; } = false;
    
    /// <summary>هل نشطة؟</summary>
    public bool IsActive { get; set; } = true;
    
    /// <summary>الربح لكل اشتراك (المبلغ الصافي بعد خصم التكاليف)</summary>
    public decimal ProfitAmount { get; set; } = 0;
    
    /// <summary>الترتيب</summary>
    public int SortOrder { get; set; } = 0;
    
    /// <summary>اللون (للعرض)</summary>
    public string? Color { get; set; }
    
    /// <summary>الشارة (مثل: "الأكثر طلباً")</summary>
    public string? Badge { get; set; }
    
    // Navigation
    public virtual Company? Company { get; set; }
    public virtual ICollection<CitizenSubscription> CitizenSubscriptions { get; set; } = new List<CitizenSubscription>();
}

/// <summary>
/// اشتراك المواطن في باقة
/// </summary>
public class CitizenSubscription : BaseEntity<Guid>
{
    /// <summary>رقم الاشتراك</summary>
    public string SubscriptionNumber { get; set; } = string.Empty;
    
    /// <summary>المواطن</summary>
    public Guid CitizenId { get; set; }
    
    /// <summary>الباقة</summary>
    public Guid InternetPlanId { get; set; }
    
    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    
    /// <summary>حالة الاشتراك</summary>
    public CitizenSubscriptionStatus Status { get; set; } = CitizenSubscriptionStatus.Pending;
    
    /// <summary>تاريخ البداية</summary>
    public DateTime? StartDate { get; set; }
    
    /// <summary>تاريخ الانتهاء</summary>
    public DateTime? EndDate { get; set; }
    
    /// <summary>تاريخ التجديد القادم</summary>
    public DateTime? NextRenewalDate { get; set; }
    
    /// <summary>هل تجديد تلقائي؟</summary>
    public bool AutoRenew { get; set; } = false;
    
    // ============ معلومات التركيب ============
    
    /// <summary>عنوان التركيب</summary>
    public string? InstallationAddress { get; set; }
    
    /// <summary>خط العرض</summary>
    public double? InstallationLatitude { get; set; }
    
    /// <summary>خط الطول</summary>
    public double? InstallationLongitude { get; set; }
    
    /// <summary>تاريخ التركيب</summary>
    public DateTime? InstalledAt { get; set; }
    
    /// <summary>الفني الذي قام بالتركيب</summary>
    public Guid? InstalledById { get; set; }
    
    // ============ المعدات ============
    
    /// <summary>رقم الراوتر</summary>
    public string? RouterSerialNumber { get; set; }
    
    /// <summary>نوع الراوتر</summary>
    public string? RouterModel { get; set; }
    
    /// <summary>رقم ONU</summary>
    public string? ONUSerialNumber { get; set; }
    
    // ============ المالية ============
    
    /// <summary>السعر المتفق عليه</summary>
    public decimal AgreedPrice { get; set; }
    
    /// <summary>رسوم التركيب</summary>
    public decimal InstallationFee { get; set; } = 0;
    
    /// <summary>إجمالي المدفوع</summary>
    public decimal TotalPaid { get; set; } = 0;
    
    /// <summary>الرصيد المستحق</summary>
    public decimal OutstandingBalance { get; set; } = 0;
    
    // ============ الإلغاء/الإيقاف ============
    
    /// <summary>سبب الإلغاء</summary>
    public string? CancellationReason { get; set; }
    
    /// <summary>تاريخ الإلغاء</summary>
    public DateTime? CancelledAt { get; set; }
    
    /// <summary>من قام بالإلغاء</summary>
    public Guid? CancelledById { get; set; }
    
    /// <summary>سبب الإيقاف</summary>
    public string? SuspensionReason { get; set; }
    
    /// <summary>تاريخ الإيقاف</summary>
    public DateTime? SuspendedAt { get; set; }
    
    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }
    
    // Navigation
    public virtual Citizen? Citizen { get; set; }
    public virtual InternetPlan? Plan { get; set; }
    public virtual Company? Company { get; set; }
    public virtual User? InstalledBy { get; set; }
    public virtual User? CancelledBy { get; set; }
    
    public virtual ICollection<CitizenPayment> Payments { get; set; } = new List<CitizenPayment>();
    
    // ============ خصائص محسوبة ============
    
    /// <summary>هل منتهي؟</summary>
    public bool IsExpired => EndDate.HasValue && DateTime.UtcNow > EndDate.Value;
    
    /// <summary>الأيام المتبقية</summary>
    public int DaysRemaining => EndDate.HasValue ? Math.Max(0, (EndDate.Value - DateTime.UtcNow).Days) : 0;
}

/// <summary>
/// حالة اشتراك المواطن
/// </summary>
public enum CitizenSubscriptionStatus
{
    /// <summary>بانتظار الموافقة</summary>
    Pending = 0,
    
    /// <summary>بانتظار التركيب</summary>
    AwaitingInstallation = 1,
    
    /// <summary>نشط</summary>
    Active = 2,
    
    /// <summary>موقوف مؤقتاً</summary>
    Suspended = 3,
    
    /// <summary>منتهي</summary>
    Expired = 4,
    
    /// <summary>ملغي</summary>
    Cancelled = 5
}
