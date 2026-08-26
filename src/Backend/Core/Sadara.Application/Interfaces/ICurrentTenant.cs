namespace Sadara.Application.Interfaces;

/// <summary>
/// سياق المستأجر (الشركة) للطلب الحالي — أساس العزل متعدد الشركات (Multi-Tenancy).
///
/// يُشتق من التوكن (claim الشركة + الدور). القاعدة:
///  - مستخدم شركة عادي  => CompanyId = شركته، BypassTenantFilter = false (يرى بيانات شركته فقط).
///  - مدير النظام SuperAdmin => IsSuperAdmin = true، BypassTenantFilter = true (يرى كل الشركات / أي نظام).
///  - سياق نظام بلا HttpContext (خدمات خلفية / هجرات / seed) => BypassTenantFilter = true.
///
/// يُستخدم في <c>SadaraDbContext</c> لتطبيق Global Query Filter على كيانات FTTH،
/// بحيث يصبح عزل الشركة افتراضياً على مستوى قاعدة البيانات ولا يعتمد على انضباط كل استعلام.
/// </summary>
public interface ICurrentTenant
{
    /// <summary>معرّف شركة المستخدم الحالي (من التوكن)، أو null إذا كان SuperAdmin أو سياق نظام.</summary>
    Guid? CompanyId { get; }

    /// <summary>هل المستخدم الحالي مدير نظام (SuperAdmin) — يتجاوز عزل الشركات ويصل لأي شركة/نظام.</summary>
    bool IsSuperAdmin { get; }

    /// <summary>
    /// هل يُتجاوز فلتر العزل لهذا الطلب؟ يكون true لـ SuperAdmin أو لأي سياق نظام بلا مستخدم
    /// (خدمات الخلفية، الهجرات، seed). عند true تُرجع الاستعلامات بيانات كل الشركات.
    /// </summary>
    bool BypassTenantFilter { get; }

    /// <summary>
    /// الشركة الافتراضية للمنصّة (المرتبطة بشركة واحدة: رمز الصدارة)، تُقرأ من الإعداد
    /// <c>Tenancy:DefaultCompanyId</c>. تُستخدم كضمان مركزي: أي إدراج كيان تينانت يصل بـ
    /// <c>CompanyId</c> فارغ في سياق تجاوز (مفتاح API/مجهول) يُختَم بها كي لا يبقى صفّ بلا شركة
    /// (فيُخفى عن قراءات JWT). null = غير مُهيّأة ⇒ لا خَتم (سلوك محايد).
    /// </summary>
    Guid? DefaultCompanyId { get; }

    /// <summary>
    /// هل يُفعَّل عزل الشركات (الفلتر المركزي عند القراءة + ختم CompanyId عند الإدراج)؟
    /// يُقرأ من الإعداد <c>Tenancy:EnforceIsolation</c>. الافتراضي <b>false</b> (معطّل) —
    /// كي يبقى نشر الثنائي محايداً ولا يُفعّل العزل تلقائياً؛ التفعيل قرار تشغيلي منفصل يُتخذ
    /// بعد اكتمال البوابات (DefaultCompanyId + backfill/verify=0 + تدوير مفتاح API الداخلي).
    /// </summary>
    bool EnforceIsolation { get; }
}
