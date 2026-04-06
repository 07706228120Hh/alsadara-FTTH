namespace Sadara.Application.Interfaces;

/// <summary>
/// FCM Push Notification Service
/// خدمة إرسال إشعارات Firebase Cloud Messaging
/// </summary>
public interface IFcmNotificationService
{
    Task SendToUserAsync(Guid userId, string title, string body, Dictionary<string, string>? data = null);
    Task SendToUsersAsync(IEnumerable<Guid> userIds, string title, string body, Dictionary<string, string>? data = null);
}
