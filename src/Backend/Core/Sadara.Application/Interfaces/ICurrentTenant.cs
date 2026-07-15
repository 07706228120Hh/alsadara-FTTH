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
}
