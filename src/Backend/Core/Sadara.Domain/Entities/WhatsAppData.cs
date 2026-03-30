namespace Sadara.Domain.Entities;

/// <summary>
/// محادثة واتساب — رقم الهاتف هو المعرف الفريد
/// </summary>
public class WhatsAppConversation : BaseEntity<long>
{
    /// <summary>رقم الهاتف (فريد — مثل: 9647XXXXXXXXX)</summary>
    public string PhoneNumber { get; set; } = string.Empty;

    /// <summary>اسم المشترك</summary>
    public string? UserName { get; set; }

    /// <summary>اسم جهة الاتصال</summary>
    public string? ContactName { get; set; }

    /// <summary>آخر رسالة</summary>
    public string LastMessage { get; set; } = string.Empty;

    /// <summary>وقت آخر رسالة (UTC)</summary>
    public DateTime LastMessageTime { get; set; }

    /// <summary>نوع آخر رسالة (text, image, audio, video, document)</summary>
    public string LastMessageType { get; set; } = "text";

    /// <summary>عدد الرسائل غير المقروءة</summary>
    public int UnreadCount { get; set; } = 0;

    /// <summary>هل آخر رسالة واردة</summary>
    public bool IsIncoming { get; set; } = false;

    /// <summary>معرف الشركة</summary>
    public Guid? CompanyId { get; set; }

    /// <summary>الرسائل</summary>
    public virtual List<WhatsAppMessage> Messages { get; set; } = new();
}

/// <summary>
/// رسالة واتساب
/// </summary>
public class WhatsAppMessage : BaseEntity<long>
{
    /// <summary>معرف الرسالة من Meta/n8n</summary>
    public string ExternalMessageId { get; set; } = string.Empty;

    /// <summary>المحادثة الأب</summary>
    public long ConversationId { get; set; }
    public virtual WhatsAppConversation? Conversation { get; set; }

    /// <summary>رقم الهاتف</summary>
    public string PhoneNumber { get; set; } = string.Empty;

    /// <summary>نص الرسالة</summary>
    public string Text { get; set; } = string.Empty;

    /// <summary>نوع الرسالة (text, image, audio, video, document)</summary>
    public string MessageType { get; set; } = "text";

    /// <summary>الاتجاه (incoming / outgoing)</summary>
    public string Direction { get; set; } = "incoming";

    /// <summary>حالة الرسالة (pending, sent, delivered, read, failed, received)</summary>
    public string Status { get; set; } = "received";

    /// <summary>اسم جهة الاتصال</summary>
    public string? ContactName { get; set; }

    /// <summary>معرف الوسائط من Meta API</summary>
    public string? MediaId { get; set; }

    /// <summary>رابط الوسائط</summary>
    public string? MediaUrl { get; set; }

    /// <summary>نوع MIME</summary>
    public string? MimeType { get; set; }

    /// <summary>اسم الملف</summary>
    public string? MediaFileName { get; set; }
}
