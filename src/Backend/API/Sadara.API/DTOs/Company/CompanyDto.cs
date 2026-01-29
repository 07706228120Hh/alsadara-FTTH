namespace Sadara.API.DTOs.Company;

/// <summary>
/// DTO لعرض معلومات الشركة
/// </summary>
public class CompanyDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string? Phone { get; set; }
    public string? Address { get; set; }
    public string? LogoUrl { get; set; }
    public bool IsActive { get; set; }
    public string? SuspensionReason { get; set; }
    
    // معلومات الاشتراك
    public DateTime SubscriptionStartDate { get; set; }
    public DateTime SubscriptionEndDate { get; set; }
    public string SubscriptionPlan { get; set; } = string.Empty;
    public int MaxUsers { get; set; }
    public int DaysRemaining { get; set; }
    public bool IsExpired { get; set; }
    
    // ربط نظام المواطن
    public bool IsLinkedToCitizenPortal { get; set; }
    public DateTime? LinkedToCitizenPortalAt { get; set; }
    
    // معلومات إضافية
    public DateTime CreatedAt { get; set; }
}
