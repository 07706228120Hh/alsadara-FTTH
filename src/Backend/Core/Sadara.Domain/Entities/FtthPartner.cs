namespace Sadara.Domain.Entities;

/// <summary>
/// شريك FTTH رئيسي للشركة. الحساب الرئيسي للشريك هو **مصدر الجلب الموثوق** لعمليات
/// كل مشغّليه (الفروع) عبر <c>walletOwnerType=partner</c>.
/// الموظف الواحد قد يملك حسابات فرعية عند عدّة شركاء (كل حساب يُربط بشريكه).
/// معزول بمستأجرين عبر <see cref="CompanyId"/> (<see cref="ITenantScoped"/>).
/// </summary>
public class FtthPartner : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرف الشركة المالكة (مفتاح العزل بين المستأجرين)</summary>
    public Guid CompanyId { get; set; }

    /// <summary>اسم وصفي للشريك يختاره المستخدم (مثل: «مكتب 11»)</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>اسم مستخدم الحساب الرئيسي للشريك (مصدر الجلب)</summary>
    public string MainUsername { get; set; } = string.Empty;

    /// <summary>
    /// كلمة مرور الحساب الرئيسي مشفّرة (عبر ISecretProtector).
    /// ⚠️ لا تُعاد أبداً في أي استجابة — تُفكّ داخلياً فقط لتسجيل الدخول الخادمي والجلب.
    /// </summary>
    public string MainPasswordEncrypted { get; set; } = string.Empty;

    /// <summary>
    /// معرّف حساب الشريك الرقمي على FTTH (AccountId من JWT، مثل "2261175").
    /// يُلتقط عند توثيق الحساب الرئيسي؛ يميّز الشريك عند تصادم أسماء المستخدمين.
    /// </summary>
    public string? PartnerAccountId { get; set; }

    /// <summary>عنوان خادم FTTH للشريك</summary>
    public string ServerUrl { get; set; } = "https://admin.ftth.iq";

    /// <summary>هل الشريك مفعّل (يُجلب منه)؟</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>حالة التحقّق: "Unverified" / "Verified" / "Invalid"</summary>
    public string? Status { get; set; }

    /// <summary>آخر توثيق ناجح للحساب الرئيسي</summary>
    public DateTime? LastVerifiedAt { get; set; }

    // ============ العلاقات ============

    /// <summary>الشركة المالكة</summary>
    public virtual Company Company { get; set; } = null!;
}
