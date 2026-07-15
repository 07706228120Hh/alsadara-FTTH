using Sadara.Application.Interfaces;

namespace Sadara.Infrastructure.Data;

/// <summary>
/// مستأجر النظام — يُستخدم في سياق design-time (توليد/تشغيل الهجرات) وأي سياق بلا مستخدم
/// (خدمات خلفية، seed). يتجاوز فلتر العزل بالكامل (يرى كل الشركات) كسلوك مدير النظام.
/// </summary>
public sealed class SystemTenant : ICurrentTenant
{
    public Guid? CompanyId => null;
    public bool IsSuperAdmin => true;
    public bool BypassTenantFilter => true;
}
