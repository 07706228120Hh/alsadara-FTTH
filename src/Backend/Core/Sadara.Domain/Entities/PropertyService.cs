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

    // ============ حقول خاصة بالنوع ============

    /// <summary>اسم الوكيل (خاص بخدمة الإنترنت).</summary>
    public string? AgentName { get; set; }

    /// <summary>رقم الحساب (خاص بخدمة الماستر).</summary>
    public string? AccountNumber { get; set; }

    /// <summary>مسار صورة الماستر (خاص بخدمة الماستر) — ملف خاص يُخدَم عبر نقطة مُصرّحة.</summary>
    public string? MasterPhotoPath { get; set; }

    /// <summary>مسار صورة هوية الأحوال المدنية (حسّاس) — ملف خاص يُخدَم عبر نقطة مُصرّحة فقط.</summary>
    public string? CivilIdPhotoPath { get; set; }

    // ============ العلاقات ============

    /// <summary>العقار المرتبط.</summary>
    public virtual Property Property { get; set; } = null!;
}
