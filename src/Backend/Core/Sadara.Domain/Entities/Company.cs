using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

/// <summary>
/// نموذج الشركة - متوافق مع Tenant في Flutter
/// كل شركة لها مدير (CompanyAdmin) وموظفين
/// </summary>
public class Company : BaseEntity<Guid>
{
    /// <summary>اسم الشركة</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>اسم الشركة بالعربي (اختياري إذا كان Name عربي)</summary>
    public string? NameAr { get; set; }
    
    /// <summary>كود الشركة الفريد - يُستخدم لتسجيل الدخول</summary>
    public string Code { get; set; } = string.Empty;
    
    /// <summary>البريد الإلكتروني</summary>
    public string? Email { get; set; }
    
    /// <summary>رقم الهاتف</summary>
    public string? Phone { get; set; }
    
    /// <summary>العنوان</summary>
    public string? Address { get; set; }
    
    /// <summary>المدينة</summary>
    public string? City { get; set; }
    
    /// <summary>رابط الشعار</summary>
    public string? LogoUrl { get; set; }
    
    /// <summary>وصف الشركة</summary>
    public string? Description { get; set; }
    
    /// <summary>هل الشركة نشطة؟</summary>
    public bool IsActive { get; set; } = true;
    
    /// <summary>سبب التعليق (إذا كانت معلقة)</summary>
    public string? SuspensionReason { get; set; }
    
    /// <summary>تاريخ التعليق</summary>
    public DateTime? SuspendedAt { get; set; }
    
    /// <summary>من قام بالتعليق</summary>
    public Guid? SuspendedById { get; set; }
    
    // ============ معلومات الاشتراك ============
    
    /// <summary>تاريخ بداية الاشتراك</summary>
    public DateTime SubscriptionStartDate { get; set; } = DateTime.UtcNow;
    
    /// <summary>تاريخ انتهاء الاشتراك</summary>
    public DateTime SubscriptionEndDate { get; set; } = DateTime.UtcNow.AddDays(30);
    
    /// <summary>نوع خطة الاشتراك</summary>
    public SubscriptionPlan SubscriptionPlan { get; set; } = SubscriptionPlan.Basic;
    
    /// <summary>الحد الأقصى للمستخدمين</summary>
    public int MaxUsers { get; set; } = 10;
    
    // ============ الميزات المفعلة ============
    
    /// <summary>
    /// ميزات النظام الأول المفعلة (JSON)
    /// مثال: {"attendance":true,"agent":false}
    /// </summary>
    public string? EnabledFirstSystemFeatures { get; set; }
    
    /// <summary>
    /// ميزات النظام الثاني المفعلة (JSON)
    /// مثال: {"users":true,"subscriptions":true}
    /// </summary>
    public string? EnabledSecondSystemFeatures { get; set; }
    
    // ============ V2 - صلاحيات مفصلة (إجراءات) ============
    
    /// <summary>
    /// ميزات النظام الأول V2 (JSON) - مع إجراءات مفصلة
    /// مثال: {"attendance":{"view":true,"add":false,"edit":false,"delete":false}}
    /// </summary>
    public string? EnabledFirstSystemFeaturesV2 { get; set; }
    
    /// <summary>
    /// ميزات النظام الثاني V2 (JSON) - مع إجراءات مفصلة
    /// مثال: {"users":{"view":true,"add":true,"edit":false,"delete":false,"export":false}}
    /// </summary>
    public string? EnabledSecondSystemFeaturesV2 { get; set; }
    
    // ============ معرف المدير ============
    
    /// <summary>معرف مدير الشركة (المستخدم الأول)</summary>
    public Guid? AdminUserId { get; set; }
    
    // ============ ربط نظام المواطن ============
    
    /// <summary>
    /// هل هذه الشركة مرتبطة بنظام المواطن؟
    /// ملاحظة: شركة واحدة فقط يجب أن تكون true في كل وقت
    /// </summary>
    public bool IsLinkedToCitizenPortal { get; set; } = false;
    
    /// <summary>تاريخ ربط الشركة بنظام المواطن</summary>
    public DateTime? LinkedToCitizenPortalAt { get; set; }
    
    /// <summary>من قام بربط الشركة بنظام المواطن (مدير النظام)</summary>
    public Guid? LinkedById { get; set; }
    
    // ============ العلاقات ============
    
    /// <summary>مدير الشركة</summary>
    public virtual User? AdminUser { get; set; }
    
    /// <summary>موظفو الشركة</summary>
    public virtual ICollection<User> Employees { get; set; } = new List<User>();
    
    /// <summary>الخدمات المفعلة للشركة</summary>
    public virtual ICollection<CompanyService> CompanyServices { get; set; } = new List<CompanyService>();
    
    // ============ الخصائص المحسوبة ============
    
    /// <summary>الأيام المتبقية من الاشتراك</summary>
    public int DaysRemaining => (SubscriptionEndDate - DateTime.UtcNow).Days;
    
    /// <summary>هل الاشتراك منتهي؟</summary>
    public bool IsExpired => DateTime.UtcNow > SubscriptionEndDate;
    
    /// <summary>هل ينتهي قريباً (خلال 7 أيام)؟</summary>
    public bool IsExpiringSoon => DaysRemaining <= 7 && DaysRemaining >= 0;
    
    /// <summary>حالة الاشتراك</summary>
    public CompanySubscriptionStatus SubscriptionStatus
    {
        get
        {
            if (!IsActive) return CompanySubscriptionStatus.Suspended;
            if (IsExpired) return CompanySubscriptionStatus.Expired;
            if (IsExpiringSoon) return CompanySubscriptionStatus.Critical;
            if (DaysRemaining <= 30) return CompanySubscriptionStatus.Warning;
            return CompanySubscriptionStatus.Active;
        }
    }
}

/// <summary>
/// ربط الشركة بالخدمات المتاحة لها
/// </summary>
public class CompanyService : BaseEntity<int>
{
    public Guid CompanyId { get; set; }
    public int ServiceId { get; set; }
    
    /// <summary>هل الخدمة مفعلة لهذه الشركة؟</summary>
    public bool IsEnabled { get; set; } = true;
    
    /// <summary>إعدادات خاصة بالشركة (JSON)</summary>
    public string? CustomSettings { get; set; }
    
    // Navigation
    public virtual Company Company { get; set; } = null!;
    public virtual Service Service { get; set; } = null!;
}
