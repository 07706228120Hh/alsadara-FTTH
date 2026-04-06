namespace Sadara.Domain.Entities;

/// <summary>
/// كاش بيانات مشتركي FTTH
/// يُملأ من سيرفر FTTH عبر Background Service ويُقدم للتطبيق عبر API
/// </summary>
public class FtthSubscriberCache : BaseEntity<long>
{
    /// <summary>معرف الشركة (tenant)</summary>
    public Guid CompanyId { get; set; }

    // ============ المعرفات ============

    /// <summary>معرف الاشتراك في FTTH</summary>
    public string SubscriptionId { get; set; } = string.Empty;

    /// <summary>معرف العميل في FTTH</summary>
    public string CustomerId { get; set; } = string.Empty;

    // ============ بيانات الاشتراك ============

    /// <summary>اسم المستخدم (username الاتصال)</summary>
    public string Username { get; set; } = string.Empty;

    /// <summary>اسم العرض (اسم العميل)</summary>
    public string DisplayName { get; set; } = string.Empty;

    /// <summary>حالة الاشتراك (ACTIVE, INACTIVE, EXPIRED, SUSPENDED)</summary>
    public string Status { get; set; } = string.Empty;

    /// <summary>هل التجديد تلقائي؟</summary>
    public bool AutoRenew { get; set; }

    /// <summary>اسم الباقة/الخدمة</summary>
    public string ProfileName { get; set; } = string.Empty;

    /// <summary>معرف الحزمة</summary>
    public string? BundleId { get; set; }

    // ============ المنطقة ============

    /// <summary>معرف المنطقة</summary>
    public string? ZoneId { get; set; }

    /// <summary>اسم المنطقة</summary>
    public string ZoneName { get; set; } = string.Empty;

    // ============ التواريخ ============

    /// <summary>تاريخ بداية الاشتراك</summary>
    public string? StartedAt { get; set; }

    /// <summary>تاريخ انتهاء الاشتراك</summary>
    public string? Expires { get; set; }

    /// <summary>فترة الالتزام</summary>
    public string? CommitmentPeriod { get; set; }

    // ============ بيانات الاتصال ============

    /// <summary>رقم الهاتف</summary>
    public string Phone { get; set; } = string.Empty;

    /// <summary>MAC المقفل</summary>
    public string? LockedMac { get; set; }

    // ============ بيانات الشبكة ============

    /// <summary>اسم FDT</summary>
    public string FdtName { get; set; } = string.Empty;

    /// <summary>اسم FAT</summary>
    public string FatName { get; set; } = string.Empty;

    /// <summary>الرقم التسلسلي للجهاز</summary>
    public string DeviceSerial { get; set; } = string.Empty;

    /// <summary>خط العرض GPS</summary>
    public string? GpsLat { get; set; }

    /// <summary>خط الطول GPS</summary>
    public string? GpsLng { get; set; }

    // ============ حالات خاصة ============

    /// <summary>هل اشتراك تجريبي؟</summary>
    public bool IsTrial { get; set; }

    /// <summary>هل معلق (pending)؟</summary>
    public bool IsPending { get; set; }

    /// <summary>هل موقوف؟</summary>
    public bool IsSuspended { get; set; }

    /// <summary>سبب الإيقاف</summary>
    public string? SuspensionReason { get; set; }

    // ============ حالة الجلب ============

    /// <summary>هل تم جلب التفاصيل (FDT/FAT/GPS)؟</summary>
    public bool DetailsFetched { get; set; }

    /// <summary>وقت جلب التفاصيل</summary>
    public DateTime? DetailsFetchedAt { get; set; }

    /// <summary>الخدمات (JSON)</summary>
    public string? ServicesJson { get; set; }

    // ============ العلاقات ============

    /// <summary>الشركة</summary>
    public virtual Company Company { get; set; } = null!;
}
