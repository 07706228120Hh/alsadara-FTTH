namespace Sadara.API.DTOs.Company;

/// <summary>
/// DTO لربط أو إلغاء ربط الشركة بنظام المواطن
/// </summary>
public class LinkToCitizenPortalDto
{
    /// <summary>معرف الشركة المراد ربطها بنظام المواطن</summary>
    public Guid CompanyId { get; set; }
}
