using Sadara.Domain.Enums;

using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

/// <summary>
/// تذكرة دعم فني
/// </summary>
public class SupportTicket : BaseEntity<Guid>
{
    /// <summary>رقم التذكرة</summary>
    public string TicketNumber { get; set; } = string.Empty;
    
    /// <summary>المواطن</summary>
    public Guid CitizenId { get; set; }
    
    /// <summary>الشركة</summary>
    public Guid CompanyId { get; set; }
    
    /// <summary>الموضوع</summary>
    public string Subject { get; set; } = string.Empty;
    
    /// <summary>الوصف</summary>
    public string Description { get; set; } = string.Empty;
    
    /// <summary>التصنيف</summary>
    public TicketCategory Category { get; set; } = TicketCategory.General;
    
    /// <summary>الأولوية</summary>
    public RequestPriority Priority { get; set; } = RequestPriority.Normal;
    
    /// <summary>الحالة</summary>
    public TicketStatus Status { get; set; } = TicketStatus.Open;
    
    /// <summary>الموظف المعين</summary>
    public Guid? AssignedToId { get; set; }
    
    /// <summary>تاريخ التعيين</summary>
    public DateTime? AssignedAt { get; set; }
    
    /// <summary>تاريخ الحل</summary>
    public DateTime? ResolvedAt { get; set; }
    
    /// <summary>ملاحظات الحل</summary>
    public string? ResolutionNotes { get; set; }
    
    /// <summary>تقييم المواطن</summary>
    public int? Rating { get; set; }
    
    /// <summary>ملاحظات التقييم</summary>
    public string? RatingFeedback { get; set; }
    
    /// <summary>مرفقات (JSON)</summary>
    public string? Attachments { get; set; }
    
    // Navigation
    public virtual Citizen? Citizen { get; set; }
    public virtual Company? Company { get; set; }
    public virtual User? AssignedTo { get; set; }
    public virtual ICollection<TicketMessage> Messages { get; set; } = new List<TicketMessage>();
}

/// <summary>
/// رسالة في تذكرة الدعم
/// </summary>
public class TicketMessage : BaseEntity<Guid>
{
    public Guid TicketId { get; set; }
    
    /// <summary>المرسل (موظف)</summary>
    public Guid? UserId { get; set; }
    
    /// <summary>المرسل (مواطن)</summary>
    public Guid? CitizenId { get; set; }
    
    /// <summary>نص الرسالة</summary>
    public string Content { get; set; } = string.Empty;
    
    /// <summary>مرفقات</summary>
    public string? Attachments { get; set; }
    
    /// <summary>هل قرأها المستلم؟</summary>
    public bool IsRead { get; set; } = false;
    
    /// <summary>تاريخ القراءة</summary>
    public DateTime? ReadAt { get; set; }
    
    // Navigation
    public virtual SupportTicket? Ticket { get; set; }
    public virtual User? User { get; set; }
    public virtual Citizen? Citizen { get; set; }
}

/// <summary>
/// تصنيف التذكرة
/// </summary>
public enum TicketCategory
{
    General = 0,
    Technical = 1,
    Billing = 2,
    Installation = 3,
    Complaint = 4,
    Suggestion = 5
}

/// <summary>
/// حالة التذكرة
/// </summary>
public enum TicketStatus
{
    Open = 0,
    InProgress = 1,
    WaitingCustomer = 2,
    Resolved = 3,
    Closed = 4
}
