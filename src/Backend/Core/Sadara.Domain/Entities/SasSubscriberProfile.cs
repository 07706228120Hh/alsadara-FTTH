namespace Sadara.Domain.Entities;

/// <summary>
/// بيانات مواطن موسّعة لمشترك ساس — بيانات يُدخلها الوكيل (لا SAS4)، منفصلة عن التخزين المحلي للمشتركين
/// (local_subscribers) لتبقى عبر المزامنة. مفتاح الربط: (الشركة + حساب الساس + معرّف المشترك في الساس).
///
/// معزول بمستأجرين عبر <see cref="CompanyId"/> (يوسم <see cref="ITenantScoped"/>) — يطبَّق عليه فلتر المستأجر المركزي.
/// فهرس فريد (CompanyId + SasAccountId + SubscriberUid) لضمان صفّ واحد لكل مشترك ضمن الحساب.
/// </summary>
public class SasSubscriberProfile : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرف الشركة المالكة (مفتاح العزل بين المستأجرين)</summary>
    public Guid CompanyId { get; set; }

    /// <summary>معرّف حساب الساس الذي يخصّه هذا المشترك (SasAccount.Id)</summary>
    public Guid SasAccountId { get; set; }

    /// <summary>معرّف المشترك في نظام الساس (uid) — مفتاح الربط مع مشترك SAS4</summary>
    public string SubscriberUid { get; set; } = string.Empty;

    /// <summary>اسم المستخدم للمشترك في نظام الساس (عرضي — من SAS4)</summary>
    public string? SubscriberUsername { get; set; }

    // ============ هوية ============

    /// <summary>الرقم الوطني/هوية الأحوال</summary>
    public string? NationalId { get; set; }

    /// <summary>الاسم الرباعي الكامل</summary>
    public string? FullNameQuad { get; set; }

    /// <summary>تاريخ الميلاد</summary>
    public DateTime? BirthDate { get; set; }

    /// <summary>الجنس</summary>
    public string? Gender { get; set; }

    // ============ تواصل ============

    /// <summary>هاتف بديل</summary>
    public string? AltPhone { get; set; }

    /// <summary>رقم واتساب</summary>
    public string? WhatsappNumber { get; set; }

    /// <summary>البريد الإلكتروني</summary>
    public string? Email { get; set; }

    // ============ موقع/عقار ============

    /// <summary>تفاصيل العنوان</summary>
    public string? AddressDetail { get; set; }

    /// <summary>خط العرض (إحداثي الموقع)</summary>
    public double? Latitude { get; set; }

    /// <summary>خط الطول (إحداثي الموقع)</summary>
    public double? Longitude { get; set; }

    /// <summary>نوع العقار</summary>
    public string? PropertyType { get; set; }

    /// <summary>نقطة دالّة/معلم قريب</summary>
    public string? Landmark { get; set; }
}
