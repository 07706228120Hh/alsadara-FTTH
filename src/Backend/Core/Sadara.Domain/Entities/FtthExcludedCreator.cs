namespace Sadara.Domain.Entities;

/// <summary>
/// منفّذ عمليات FTTH مُستبعَد من المقارنة والمزامنة (لكل شركة).
/// مثال: رقم بطاقة/حساب كـ"1838865" لعمليات تُدفع بالكارت ولا تدخل حسابات الشركة.
/// عند المزامنة والمقارنة: أي عملية <c>createdBy</c> يطابق <see cref="Identifier"/>
/// (بلا حساسية لحالة الأحرف) تُتخطّى — لا SubscriptionLog ولا قيد محاسبي.
/// معزول بمستأجرين عبر <see cref="CompanyId"/> (<see cref="ITenantScoped"/>).
/// </summary>
public class FtthExcludedCreator : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرف الشركة المالكة (مفتاح العزل بين المستأجرين)</summary>
    public Guid CompanyId { get; set; }

    /// <summary>
    /// المعرّف المستبعَد: رقم أو اسم كما يصل في <c>createdBy</c> من FTTH (مثل "1838865").
    /// المطابقة بلا حساسية لحالة الأحرف وبعد trim.
    /// </summary>
    public string Identifier { get; set; } = string.Empty;

    /// <summary>ملاحظة اختيارية يكتبها المستخدم (سبب الاستبعاد) — قابلة للتعديل.</summary>
    public string? Note { get; set; }

    /// <summary>هل الاستبعاد فعّال؟ (يُتيح تعطيله مؤقتاً دون حذفه)</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>معرّف المستخدم الذي أضاف الاستبعاد (تدقيق).</summary>
    public Guid? CreatedById { get; set; }

    // ============ العلاقات ============

    /// <summary>الشركة المالكة</summary>
    public virtual Company Company { get; set; } = null!;
}
