using Sadara.Application.Interfaces;

namespace Sadara.Api.Tests.Fakes;

/// <summary>
/// سياق مستأجر وهمي بسيط (بلا Moq). يحتاجه مُنشئ CompaniesController فقط؛
/// دالة GenerateJwtToken قيد الاختبار لا تقرأ أي عضو منه، فالقيم هنا محايدة.
/// </summary>
public sealed class FakeCurrentTenant : ICurrentTenant
{
    public Guid? CompanyId => null;
    public bool IsSuperAdmin => false;
    public bool BypassTenantFilter => true;
    public Guid? DefaultCompanyId => null;
}
