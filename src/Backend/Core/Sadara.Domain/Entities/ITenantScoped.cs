namespace Sadara.Domain.Entities;

/// <summary>
/// علامة (marker) للكيانات المملوكة لشركة (tenant-scoped) — أساس العزل متعدد الشركات.
///
/// أي كيان يحمل هذه العلامة **ويحوي خاصية CompanyId** (سواء Guid أو Guid?) يُطبَّق عليه
/// تلقائياً الفلتر المركزي في <c>SadaraDbContext</c>:
/// <code>!IsDeleted &amp;&amp; (SuperAdmin/نظام يتجاوز || CompanyId == شركة المستخدم الحالي)</code>
///
/// واجهة فارغة عمداً: قراءة CompanyId تتم بالاسم عبر EF.Property حتى تعمل مع النوعين (Guid و Guid?)
/// دون إجبار توحيد النوع الآن.
/// </summary>
public interface ITenantScoped
{
}
