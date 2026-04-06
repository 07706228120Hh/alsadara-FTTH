namespace Sadara.Domain.Entities;

public class UserFcmToken : BaseEntity<long>
{
    public Guid UserId { get; set; }
    public string Token { get; set; } = string.Empty;
    public string? DeviceId { get; set; }
    public string? DevicePlatform { get; set; } // android, ios, windows, web
    public DateTime LastActiveAt { get; set; } = DateTime.UtcNow;

    public User User { get; set; } = null!;
}
