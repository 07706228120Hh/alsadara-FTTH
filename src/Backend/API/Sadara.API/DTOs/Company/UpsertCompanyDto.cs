namespace Sadara.API.DTOs.Company;

/// <summary>
/// DTO لإنشاء أو تحديث شركة
/// </summary>
public class UpsertCompanyDto
{
    public string Name { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string? Phone { get; set; }
    public string? Address { get; set; }
    public string? City { get; set; }
    public string? LogoUrl { get; set; }
    public string? Description { get; set; }
    
    // الاشتراك
    public DateTime SubscriptionEndDate { get; set; }
    public string SubscriptionPlan { get; set; } = "Basic";
    public int MaxUsers { get; set; } = 10;
    
    // الصلاحيات (JSON strings)
    public string? EnabledFirstSystemFeatures { get; set; }
    public string? EnabledSecondSystemFeatures { get; set; }
}
