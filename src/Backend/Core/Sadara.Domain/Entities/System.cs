using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

public class Notification : BaseEntity<long>
{
    public Guid UserId { get; set; }
    public Guid? CompanyId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? TitleAr { get; set; }
    public string Body { get; set; } = string.Empty;
    public string? BodyAr { get; set; }
    public NotificationType Type { get; set; }
    public string? Data { get; set; }
    public string? ImageUrl { get; set; }
    public string? ActionUrl { get; set; }
    public bool IsRead { get; set; } = false;
    public DateTime? ReadAt { get; set; }
    public bool IsSent { get; set; } = false;
    public DateTime? SentAt { get; set; }
    
    /// <summary>معرف الكيان المرتبط (مثل ServiceRequest.Id)</summary>
    public Guid? ReferenceId { get; set; }
    
    /// <summary>نوع الكيان المرتبط (مثل "ServiceRequest")</summary>
    public string? ReferenceType { get; set; }

    public virtual User User { get; set; } = null!;
}

public class Setting : BaseEntity<int>
{
    public Guid? MerchantId { get; set; }
    public string Key { get; set; } = string.Empty;
    public string Value { get; set; } = string.Empty;
    public string Category { get; set; } = "General";
    public string? Description { get; set; }
    public string Type { get; set; } = "string";
    public bool IsPublic { get; set; } = false;

    public virtual Merchant? Merchant { get; set; }
}

public class AuditLog : BaseEntity<long>
{
    public Guid? UserId { get; set; }
    public string Action { get; set; } = string.Empty;
    public string EntityName { get; set; } = string.Empty;
    public string? EntityId { get; set; }
    public string? OldValues { get; set; }
    public string? NewValues { get; set; }
    public string? IpAddress { get; set; }
    public string? UserAgent { get; set; }
}

public class AppVersion : BaseEntity<int>
{
    public string Platform { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
    public string? MinVersion { get; set; }
    public string? DownloadUrl { get; set; }
    public string? ReleaseNotes { get; set; }
    public bool ForceUpdate { get; set; } = false;
    public bool IsActive { get; set; } = true;
}

public class Advertising : BaseEntity<int>
{
    public string? Title { get; set; }
    public string? Type { get; set; }
    public string? Image { get; set; }
    public string? TargetUrl { get; set; }
    public Guid? MerchantId { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public int ViewCount { get; set; } = 0;
    public int ClickCount { get; set; } = 0;
    public bool IsActive { get; set; } = true;
    public int SortOrder { get; set; } = 0;
}
