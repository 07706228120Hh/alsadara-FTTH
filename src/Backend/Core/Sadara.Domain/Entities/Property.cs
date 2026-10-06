using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

/// <summary>
/// العقار (المنزل/المنشأة) — النواة المحايدة لسجل العقارات المستقل، محوره QR دائم.
///
/// الـQR يشير للعقار (هوية ثابتة لا تتغيّر)؛ يُربط به المواطن (<see cref="PropertyResident"/>)
/// ثم خدمات متعدّدة (<see cref="PropertyService"/>). الخدمات تتغيّر، العقار والـQR يبقيان.
///
/// معزول بالمستأجرين عبر <see cref="CompanyId"/> (يوسم <see cref="ITenantScoped"/>)
/// وبالمنشئ عبر <see cref="CreatedByUserId"/> (دفاع بالعمق/تتبّع).
/// </summary>
public class Property : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرّف الشركة المالكة (مفتاح العزل بين المستأجرين).</summary>
    public Guid CompanyId { get; set; }

    /// <summary>معرّف المستخدم (الموظّف) الذي أنشأ العقار — للتتبّع والدفاع بالعمق.</summary>
    public Guid CreatedByUserId { get; set; }

    /// <summary>
    /// رمز الـQR الدائم الفريد للعقار (مثل Base32/Guid). يُشفَّر في الـQR كـ<c>SADARA|P:&lt;QrToken&gt;</c>.
    /// ثابت مدى الحياة ولا يحمل بيانات خدمة (تتغيّر) — يشير للعقار فقط.
    /// </summary>
    public string QrToken { get; set; } = string.Empty;

    /// <summary>رقم العقار الوطني (NPN) الذرّي لكل محافظة — القيمة الخام (تسلسل داخل المحافظة).</summary>
    public string Npn { get; set; } = string.Empty;

    /// <summary>صيغة العرض الكاملة لرقم العقار الوطني (مثل: "NPN-GG-0000123").</summary>
    public string NpnDisplay { get; set; } = string.Empty;

    /// <summary>معرّف الموقع العراقي (IQ-PIN) المشتق من الإحداثيات — القيمة الخام (قد يكون فارغاً بلا إحداثيات).</summary>
    public string? IqPin { get; set; }

    /// <summary>صيغة العرض لمعرّف الموقع العراقي (IQ-PIN) — للعرض/النسخ.</summary>
    public string? IqPinDisplay { get; set; }

    /// <summary>رمز المحافظة (رقمي) — أساس تخصيص NPN الذرّي لكل محافظة.</summary>
    public int GovCode { get; set; }

    /// <summary>المحافظة.</summary>
    public string Governorate { get; set; } = string.Empty;

    /// <summary>المنطقة.</summary>
    public string Area { get; set; } = string.Empty;

    /// <summary>الحي/القطاع.</summary>
    public string District { get; set; } = string.Empty;

    /// <summary>أقرب نقطة دالّة (Landmark).</summary>
    public string? Landmark { get; set; }

    /// <summary>تفاصيل العنوان الإضافية.</summary>
    public string? AddressDetails { get; set; }

    /// <summary>خط العرض (Latitude).</summary>
    public double? Latitude { get; set; }

    /// <summary>خط الطول (Longitude).</summary>
    public double? Longitude { get; set; }

    /// <summary>نوع العقار (سكني/تجاري).</summary>
    public PropertyType PropertyType { get; set; }

    /// <summary>نوع الملكية (مِلك/إيجار).</summary>
    public PropertyOwnership Ownership { get; set; }

    /// <summary>مسار صورة العقار (اختياري).</summary>
    public string? PhotoPath { get; set; }

    /// <summary>ملاحظات.</summary>
    public string? Notes { get; set; }

    // ============ العلاقات ============

    /// <summary>الشركة المالكة.</summary>
    public virtual Company Company { get; set; } = null!;

    /// <summary>المواطنون المرتبطون بالعقار (مالك/مستأجر/ساكن).</summary>
    public virtual ICollection<PropertyResident> Residents { get; set; } = new List<PropertyResident>();

    /// <summary>الخدمات المرتبطة بالعقار (إنترنت/ماستر/…).</summary>
    public virtual ICollection<PropertyService> Services { get; set; } = new List<PropertyService>();
}
