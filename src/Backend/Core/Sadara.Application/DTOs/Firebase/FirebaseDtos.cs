namespace Sadara.Application.DTOs.Firebase;

// Firebase DTOs
public class FirebaseUserInfo
{
    public string Uid { get; set; } = string.Empty;
    public string? PhoneNumber { get; set; }
    public string? Email { get; set; }
    public string? DisplayName { get; set; }
    public bool Disabled { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? LastSignInAt { get; set; }
}

public class FirebaseAuthStats
{
    public int TotalUsers { get; set; }
    public int ActiveUsers { get; set; }
    public int DisabledUsers { get; set; }
    public int VerifiedUsers { get; set; }
    public DateTime LastUpdated { get; set; }
}
