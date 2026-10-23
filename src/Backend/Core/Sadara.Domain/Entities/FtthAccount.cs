namespace Sadara.Domain.Entities;

/// <summary>
/// حساب FTTH مربوط بموظف داخل الشركة.
/// يدعم عدّة حسابات FTTH للموظف الواحد (الحسابات المرتبطة المتعددة لكل موظف)،
/// بنفس نمط <see cref="SasAccount"/>.
/// معزول بمستأجرين عبر <see cref="CompanyId"/> (يوسم <see cref="ITenantScoped"/>)
/// وبمالك عبر <see cref="OwnerUserId"/> (دفاع بالعمق فوق فلتر المستأجر).
/// ملاحظة: الحقلان القديمان <c>User.FtthUsername</c>/<c>User.FtthPasswordEncrypted</c>
/// يبقيان كما هما (حساب FTTH الأساسي الموروث)؛ هذا الكيان يضيف ربطاً متعدّداً فوقهما.
/// </summary>
public class FtthAccount : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرف الشركة المالكة (مفتاح العزل بين المستأجرين)</summary>
    public Guid CompanyId { get; set; }

    /// <summary>معرف الموظف المالك للحساب (User) — يُطابَق مع المستخدم الحالي كدفاع بالعمق</summary>
    public Guid OwnerUserId { get; set; }

    /// <summary>تسمية وصفية للحساب يختارها الموظف (مثل: «حسابي الرئيسي»)</summary>
    public string Label { get; set; } = string.Empty;

    /// <summary>عنوان خادم نظام FTTH</summary>
    public string ServerUrl { get; set; } = "https://admin.ftth.iq";

    /// <summary>اسم المستخدم على نظام FTTH</summary>
    public string Username { get; set; } = string.Empty;

    /// <summary>
    /// معرّف عضو الفريق على خادم FTTH (team member id، مثل "1838865").
    /// يُجلب من <c>/api/teams/members</c> عند الربط. تسجّل بعض العمليات المنفّذ بهذا الرقم
    /// بدل اسم المستخدم، فنطابق المزامنة به كمفتاح أول (ثم Username ثم اسم المالك).
    /// </summary>
    public string? FtthMemberId { get; set; }

    /// <summary>
    /// كلمة مرور FTTH مشفّرة (تُحفظ مشفّرة عبر ISecretProtector في المتحكم لاحقاً).
    /// ⚠️ لا يُعاد هذا الحقل أبداً في أي استجابة API — يُفكّ تشفيره داخلياً فقط عند تسجيل الدخول لنظام FTTH.
    /// </summary>
    public string PasswordEncrypted { get; set; } = string.Empty;

    /// <summary>دور المستخدم في نظام FTTH (role.displayValue) — تخزين اختياري للعرض فقط</summary>
    public string? Role { get; set; }

    /// <summary>هل الحساب مفعّل؟</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>هل هذا هو الحساب الافتراضي (الأساسي) للموظف؟</summary>
    public bool IsPrimary { get; set; } = false;

    /// <summary>آخر وقت تحقّق ناجح من صحة بيانات الاعتماد</summary>
    public DateTime? LastVerifiedAt { get; set; }

    /// <summary>آخر وقت تسجيل دخول ناجح بهذا الحساب</summary>
    public DateTime? LastLoginAt { get; set; }

    /// <summary>حالة الحساب (نص وصفي مختصر): "Unverified" / "Verified" / "Invalid"</summary>
    public string? Status { get; set; }

    // ============ العلاقات ============

    /// <summary>الشركة المالكة</summary>
    public virtual Company Company { get; set; } = null!;
}
