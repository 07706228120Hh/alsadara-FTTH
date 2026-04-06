namespace Sadara.Domain.Entities;

// ═══════════════════════════════════════════════════════════════
// نظام المحادثة الداخلي — Sadara Chat
// ═══════════════════════════════════════════════════════════════

/// <summary>نوع غرفة المحادثة</summary>
public enum ChatRoomType
{
    /// <summary>محادثة خاصة بين شخصين</summary>
    Direct = 0,
    /// <summary>محادثة قسم</summary>
    Department = 1,
    /// <summary>بث للجميع (إعلان عام)</summary>
    Broadcast = 2,
    /// <summary>مجموعة مخصصة</summary>
    Group = 3,
}

/// <summary>نوع الرسالة</summary>
public enum ChatMessageType
{
    Text = 0,
    Image = 1,
    Audio = 2,
    Location = 3,
    Contact = 4,
    File = 5,
}

/// <summary>
/// غرفة محادثة — تمثل محادثة خاصة أو مجموعة أو بث
/// </summary>
public class ChatRoom : BaseEntity<Guid>
{
    /// <summary>معرف الشركة</summary>
    public Guid CompanyId { get; set; }

    /// <summary>نوع الغرفة</summary>
    public ChatRoomType Type { get; set; } = ChatRoomType.Direct;

    /// <summary>معرف القسم (لمحادثات الأقسام فقط)</summary>
    public int? DepartmentId { get; set; }

    /// <summary>اسم الغرفة (للمجموعات والبث — null للخاصة)</summary>
    public string? Name { get; set; }

    /// <summary>صورة الغرفة (للمجموعات)</summary>
    public string? AvatarUrl { get; set; }

    /// <summary>منشئ الغرفة</summary>
    public Guid CreatedByUserId { get; set; }

    /// <summary>وقت آخر رسالة (لترتيب القائمة)</summary>
    public DateTime? LastMessageAt { get; set; }

    /// <summary>آخر رسالة (للعرض في القائمة)</summary>
    public string? LastMessagePreview { get; set; }

    /// <summary>اسم مرسل آخر رسالة</summary>
    public string? LastMessageSenderName { get; set; }

    // Navigation
    public virtual Company Company { get; set; } = null!;
    public virtual Department? Department { get; set; }
    public virtual User CreatedByUser { get; set; } = null!;
    public virtual ICollection<ChatRoomMember> Members { get; set; } = new List<ChatRoomMember>();
    public virtual ICollection<ChatMessage> Messages { get; set; } = new List<ChatMessage>();
}

/// <summary>
/// عضو في غرفة محادثة
/// </summary>
public class ChatRoomMember : BaseEntity<long>
{
    /// <summary>معرف الغرفة</summary>
    public Guid ChatRoomId { get; set; }

    /// <summary>معرف المستخدم</summary>
    public Guid UserId { get; set; }

    /// <summary>وقت الانضمام</summary>
    public DateTime JoinedAt { get; set; } = DateTime.UtcNow;

    /// <summary>آخر وقت قراءة (لحساب الغير مقروء)</summary>
    public DateTime? LastReadAt { get; set; }

    /// <summary>هل كتم الإشعارات</summary>
    public bool IsMuted { get; set; } = false;

    /// <summary>هل المحادثة مثبّتة</summary>
    public bool IsPinned { get; set; } = false;

    /// <summary>هل هو مدير الغرفة</summary>
    public bool IsAdmin { get; set; } = false;

    // Navigation
    public virtual ChatRoom ChatRoom { get; set; } = null!;
    public virtual User User { get; set; } = null!;
}

/// <summary>
/// رسالة في المحادثة
/// </summary>
public class ChatMessage : BaseEntity<Guid>
{
    /// <summary>معرف الغرفة</summary>
    public Guid ChatRoomId { get; set; }

    /// <summary>معرف المرسل</summary>
    public Guid SenderId { get; set; }

    /// <summary>نوع الرسالة</summary>
    public ChatMessageType MessageType { get; set; } = ChatMessageType.Text;

    /// <summary>
    /// محتوى الرسالة:
    /// - Text: النص مباشرة
    /// - Location: JSON {"lat":33.3,"lng":44.4,"address":"..."}
    /// - Contact: JSON {"name":"أحمد","phone":"07712345678"}
    /// - Image/Audio/File: URL المرفق
    /// </summary>
    public string? Content { get; set; }

    /// <summary>رد على رسالة (null = رسالة جديدة)</summary>
    public Guid? ReplyToMessageId { get; set; }

    /// <summary>تم إعادة توجيه الرسالة</summary>
    public bool IsForwarded { get; set; } = false;

    // Navigation
    public virtual ChatRoom ChatRoom { get; set; } = null!;
    public virtual User Sender { get; set; } = null!;
    public virtual ChatMessage? ReplyToMessage { get; set; }
    public virtual ICollection<ChatAttachment> Attachments { get; set; } = new List<ChatAttachment>();
    public virtual ICollection<ChatMention> Mentions { get; set; } = new List<ChatMention>();
    public virtual ICollection<ChatMessageRead> ReadReceipts { get; set; } = new List<ChatMessageRead>();
    public virtual ICollection<ChatReaction> Reactions { get; set; } = new List<ChatReaction>();
}

/// <summary>
/// مرفق رسالة (صورة، صوت، ملف)
/// </summary>
public class ChatAttachment : BaseEntity<long>
{
    /// <summary>معرف الرسالة</summary>
    public Guid ChatMessageId { get; set; }

    /// <summary>اسم الملف الأصلي</summary>
    public string FileName { get; set; } = string.Empty;

    /// <summary>المسار على السيرفر</summary>
    public string FilePath { get; set; } = string.Empty;

    /// <summary>حجم الملف بالبايت</summary>
    public long FileSize { get; set; }

    /// <summary>نوع الملف MIME</summary>
    public string MimeType { get; set; } = string.Empty;

    /// <summary>مسار الصورة المصغرة (للصور فقط)</summary>
    public string? ThumbnailPath { get; set; }

    /// <summary>مدة الصوت بالثواني (للصوتيات فقط)</summary>
    public int? DurationSeconds { get; set; }

    // Navigation
    public virtual ChatMessage ChatMessage { get; set; } = null!;
}

/// <summary>
/// تاق/إشارة لموظف في رسالة (@mention)
/// </summary>
public class ChatMention : BaseEntity<long>
{
    /// <summary>معرف الرسالة</summary>
    public Guid ChatMessageId { get; set; }

    /// <summary>معرف الموظف المذكور</summary>
    public Guid MentionedUserId { get; set; }

    /// <summary>هل تم إرسال الإشعار</summary>
    public bool IsNotified { get; set; } = false;

    // Navigation
    public virtual ChatMessage ChatMessage { get; set; } = null!;
    public virtual User MentionedUser { get; set; } = null!;
}

/// <summary>
/// تفاعل (Reaction) على رسالة
/// </summary>
public class ChatReaction : BaseEntity<long>
{
    public Guid ChatMessageId { get; set; }
    public Guid UserId { get; set; }

    /// <summary>الإيموجي: 👍 ❤️ 😂 😮 😢 🙏</summary>
    public string Emoji { get; set; } = string.Empty;

    public virtual ChatMessage ChatMessage { get; set; } = null!;
    public virtual User User { get; set; } = null!;
}

/// <summary>
/// إيصال قراءة رسالة
/// </summary>
public class ChatMessageRead : BaseEntity<long>
{
    /// <summary>معرف الرسالة</summary>
    public Guid ChatMessageId { get; set; }

    /// <summary>معرف القارئ</summary>
    public Guid UserId { get; set; }

    /// <summary>وقت القراءة</summary>
    public DateTime ReadAt { get; set; } = DateTime.UtcNow;

    // Navigation
    public virtual ChatMessage ChatMessage { get; set; } = null!;
    public virtual User User { get; set; } = null!;
}
