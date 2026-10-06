using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

/// <summary>
/// موصّل الخدمة العام للعقار (قابل للتوسّع): إنترنت الآن، ماستر/أي خدمة مستقبلاً.
/// إضافة خدمة جديدة = صفّ <see cref="ServiceType"/> جديد، بلا إعادة هيكلة.
/// معزول بالمستأجرين عبر <see cref="CompanyId"/> (يوسم <see cref="ITenantScoped"/>).
/// </summary>
public class PropertyService : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرّف الشركة المالكة (مفتاح العزل بين المستأجرين).</summary>
    public Guid CompanyId { get; set; }

    /// <summary>معرّف العقار المرتبط.</summary>
    public Guid PropertyId { get; set; }

    /// <summary>نوع الخدمة (إنترنت/ماستر/IPTV/أخرى).</summary>
    public PropertyServiceType ServiceType { get; set; }

    /// <summary>مزوّد الخدمة (ساز/FTTH/خارجي).</summary>
    public PropertyServiceProvider ProviderType { get; set; }

    /// <summary>
    /// مرجع المزوّد النصّي: SasAccountId+Uid للإنترنت-ساز، أو CitizenSubscriptionId لـFTTH،
    /// أو حرّ لماستر وغيره (اختياري).
    /// </summary>
    public string? ProviderRefId { get; set; }

    /// <summary>مرجع المشترك لدى المزوّد (اسم مستخدم/رقم مشترك) (اختياري).</summary>
    public string? SubscriberRef { get; set; }

    /// <summary>حالة الخدمة (فعّالة/موقوفة/منتهية).</summary>
    public PropertyServiceStatus Status { get; set; }

    /// <summary>تاريخ بدء الخدمة (اختياري).</summary>
    public DateTime? StartDate { get; set; }

    /// <summary>تاريخ انتهاء الخدمة (اختياري).</summary>
    public DateTime? EndDate { get; set; }

    /// <summary>ملاحظات.</summary>
    public string? Notes { get; set; }

    // ============ العلاقات ============

    /// <summary>العقار المرتبط.</summary>
    public virtual Property Property { get; set; } = null!;
}
