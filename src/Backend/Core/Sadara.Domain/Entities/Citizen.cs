namespace Sadara.Domain.Entities;

/// <summary>
/// المواطن - العميل النهائي للخدمات
/// كل مواطن ينتمي لشركة واحدة يحددها مدير النظام
/// </summary>
public class Citizen : BaseEntity<Guid>
{
    // ============ معلومات أساسية ============
    
    /// <summary>الاسم الكامل</summary>
    public string FullName { get; set; } = string.Empty;
    
    /// <summary>رقم الهاتف (المعرف الرئيسي)</summary>
    public string PhoneNumber { get; set; } = string.Empty;
    
    /// <summary>كلمة المرور المشفرة</summary>
    public string PasswordHash { get; set; } = string.Empty;
    
    /// <summary>البريد الإلكتروني</summary>
    public string? Email { get; set; }
    
    /// <summary>صورة الملف الشخصي</summary>
    public string? ProfileImageUrl { get; set; }
    
    /// <summary>الجنس</summary>
    public Gender? Gender { get; set; }
    
    /// <summary>تاريخ الميلاد</summary>
    public DateTime? DateOfBirth { get; set; }
    
    // ============ العنوان ============
    
    /// <summary>المحافظة</summary>
    public string? City { get; set; }
    
    /// <summary>المنطقة/الحي</summary>
    public string? District { get; set; }
    
    /// <summary>العنوان التفصيلي</summary>
    public string? FullAddress { get; set; }
    
    /// <summary>خط العرض</summary>
    public double? Latitude { get; set; }
    
    /// <summary>خط الطول</summary>
    public double? Longitude { get; set; }
    
    // ============ الشركة المرتبطة ============
    
    /// <summary>الشركة التي يتبع لها المواطن (قد تكون فارغة إذا لم توجد شركة مربوطة بنظام المواطن)</summary>
    public Guid? CompanyId { get; set; }
    
    /// <summary>تاريخ ربط المواطن بالشركة</summary>
    public DateTime? AssignedToCompanyAt { get; set; }
    
    /// <summary>من قام بربط المواطن (مدير النظام)</summary>
    public Guid? AssignedById { get; set; }
    
    // ============ حالة الحساب ============
    
    /// <summary>هل الحساب نشط؟</summary>
    public bool IsActive { get; set; } = true;
    
    /// <summary>هل تم التحقق من الهاتف؟</summary>
    public bool IsPhoneVerified { get; set; } = false;
    
    /// <summary>هل الحساب محظور؟</summary>
    public bool IsBanned { get; set; } = false;
    
    /// <summary>سبب الحظر</summary>
    public string? BanReason { get; set; }
    
    /// <summary>تاريخ الحظر</summary>
    public DateTime? BannedAt { get; set; }
    
    // ============ التحقق والأمان ============
    
    /// <summary>رمز التحقق</summary>
    public string? VerificationCode { get; set; }
    
    /// <summary>تاريخ انتهاء رمز التحقق</summary>
    public DateTime? VerificationCodeExpiresAt { get; set; }
    
    /// <summary>عدد محاولات تسجيل الدخول الفاشلة</summary>
    public int FailedLoginAttempts { get; set; } = 0;
    
    /// <summary>تاريخ انتهاء القفل</summary>
    public DateTime? LockoutEnd { get; set; }
    
    // ============ معلومات الجهاز ============
    
    /// <summary>معرف الجهاز</summary>
    public string? DeviceId { get; set; }
    
    /// <summary>معلومات الجهاز</summary>
    public string? DeviceInfo { get; set; }
    
    /// <summary>توكن Firebase للإشعارات</summary>
    public string? FirebaseToken { get; set; }
    
    /// <summary>آخر تسجيل دخول</summary>
    public DateTime? LastLoginAt { get; set; }
    
    /// <summary>آخر إصدار للتطبيق</summary>
    public string? LastAppVersion { get; set; }
    
    /// <summary>لغة التطبيق المفضلة</summary>
    public string LanguagePreference { get; set; } = "ar";
    
    // ============ الإحصائيات ============
    
    /// <summary>إجمالي الطلبات</summary>
    public int TotalRequests { get; set; } = 0;
    
    /// <summary>إجمالي المدفوع</summary>
    public decimal TotalPaid { get; set; } = 0;
    
    /// <summary>نقاط الولاء</summary>
    public int LoyaltyPoints { get; set; } = 0;
    
    // ============ ملاحظات ============
    
    /// <summary>ملاحظات داخلية</summary>
    public string? InternalNotes { get; set; }
    
    // ============ Navigation Properties ============
    
    /// <summary>الشركة</summary>
    public virtual Company? Company { get; set; }
    
    /// <summary>من قام بالتعيين</summary>
    public virtual User? AssignedBy { get; set; }
    
    /// <summary>طلبات الخدمة</summary>
    public virtual ICollection<ServiceRequest> ServiceRequests { get; set; } = new List<ServiceRequest>();
    
    /// <summary>اشتراكات المواطن</summary>
    public virtual ICollection<CitizenSubscription> Subscriptions { get; set; } = new List<CitizenSubscription>();
    
    /// <summary>تذاكر الدعم</summary>
    public virtual ICollection<SupportTicket> SupportTickets { get; set; } = new List<SupportTicket>();
    
    /// <summary>المدفوعات</summary>
    public virtual ICollection<CitizenPayment> Payments { get; set; } = new List<CitizenPayment>();
}

/// <summary>
/// الجنس
/// </summary>
public enum Gender
{
    Male = 0,
    Female = 1
}
