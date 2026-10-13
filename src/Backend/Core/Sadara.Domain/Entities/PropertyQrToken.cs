using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

/// <summary>
/// رمز QR مولّد مسبقاً ضمن «مخزون الرموز» لسجل العقارات.
///
/// تُولَّد دفعات من الرموز الفارغة (<see cref="PropertyQrTokenStatus.Unused"/>) وتُطبَع، ثم يُربط
/// كل رمز بعقار لاحقاً عند المسح/الملء (يُعبّأ <see cref="PropertyId"/> وتتحوّل الحالة إلى
/// <see cref="PropertyQrTokenStatus.Used"/>). الرمز نفسه (<see cref="QrToken"/>) دائم ولا يتغيّر.
///
/// معزول بالمستأجرين عبر <see cref="CompanyId"/> (يوسم <see cref="ITenantScoped"/>)
/// وبالمنشئ عبر <see cref="CreatedByUserId"/> (دفاع بالعمق/تتبّع) — بنفس نمط <see cref="Property"/>.
/// </summary>
public class PropertyQrToken : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرّف الشركة المالكة (مفتاح العزل بين المستأجرين).</summary>
    public Guid CompanyId { get; set; }

    /// <summary>معرّف المستخدم (الموظّف) الذي ولّد الدفعة — للتتبّع والدفاع بالعمق.</summary>
    public Guid CreatedByUserId { get; set; }

    /// <summary>معرّف الدفعة التي وُلِّد ضمنها هذا الرمز (كل عملية توليد = دفعة واحدة).</summary>
    public Guid BatchId { get; set; }

    /// <summary>التسلسل داخل الدفعة (يبدأ من 1).</summary>
    public int Serial { get; set; }

    /// <summary>
    /// رمز الـQR الدائم الفريد (نفس نمط <see cref="Property.QrToken"/>). يُشفَّر في الـQR كـ<c>SADARA|P:&lt;QrToken&gt;</c>.
    /// ثابت مدى الحياة؛ عند الملء يُنسخ إلى العقار المرتبط.
    /// </summary>
    public string QrToken { get; set; } = string.Empty;

    /// <summary>حالة الرمز: فارغ (مطبوع لم يُستخدَم) أو مستخدَم (مربوط بعقار).</summary>
    public PropertyQrTokenStatus Status { get; set; } = PropertyQrTokenStatus.Unused;

    /// <summary>العقار المرتبط عند الملء (<c>null</c> ما دام الرمز فارغاً).</summary>
    public Guid? PropertyId { get; set; }

    /// <summary>ملاحظة اختيارية لوصف الدفعة.</summary>
    public string? Note { get; set; }

    // ============ العلاقات ============

    /// <summary>الشركة المالكة.</summary>
    public virtual Company Company { get; set; } = null!;

    /// <summary>العقار المرتبط (اختياري — يُعبّأ عند الملء).</summary>
    public virtual Property? Property { get; set; }
}
