namespace Sadara.Domain.Entities;

/// <summary>
/// سجلّ تدقيق دائم لكل عملية كشف كلمة مرور (FTTH أو ساس) ضمن ميزة «الحسابات المرتبطة».
/// حدث حسّاس لا يكفيه <c>ILogger</c> وحده، فيُخزَّن دائماً في قاعدة البيانات لأغراض المراجعة الأمنية.
///
/// معزول بمستأجرين عبر <see cref="CompanyId"/> (يوسم <see cref="ITenantScoped"/>) فيأخذ الفلتر
/// المركزي في <c>SadaraDbContext</c> تلقائياً عند تفعيل العزل.
///
/// ⚠️ بيانات تدقيق فقط — لا تُخزَّن هنا كلمة المرور ولا أي سرّ إطلاقاً، فقط «مَن كشف ماذا ومتى».
/// </summary>
public class CredentialRevealAudit : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرف الشركة المالكة (مفتاح العزل بين المستأجرين)</summary>
    public Guid CompanyId { get; set; }

    /// <summary>معرف المستخدم الذي طلب كشف كلمة المرور (مرجع تدقيق، بلا مفتاح أجنبي)</summary>
    public Guid RequestedByUserId { get; set; }

    /// <summary>معرف الحساب المكشوف (حساب FTTH أو ساس حسب <see cref="Provider"/>)</summary>
    public Guid AccountId { get; set; }

    /// <summary>مزوّد الحساب المكشوف: "Ftth" أو "Sas"</summary>
    public string Provider { get; set; } = string.Empty;

    /// <summary>معرف مالك الحساب المكشوف (مرجع تدقيق، بلا مفتاح أجنبي)</summary>
    public Guid OwnerUserId { get; set; }

    /// <summary>توقيت الكشف (UTC)</summary>
    public DateTime RevealedAtUtc { get; set; }

    // ============ العلاقات ============

    /// <summary>الشركة المالكة</summary>
    public virtual Company Company { get; set; } = null!;
}
