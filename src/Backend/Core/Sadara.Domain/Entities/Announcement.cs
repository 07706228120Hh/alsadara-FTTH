namespace Sadara.Domain.Entities;

// ═══════════════════════════════════════════════════════════════
// نظام الإعلانات والتبليغات — Sadara Announcements
// ═══════════════════════════════════════════════════════════════

/// <summary>نوع الاستهداف</summary>
public enum AnnouncementTargetType
{
    /// <summary>الكل</summary>
    All = 0,
    /// <summary>حسب القسم</summary>
    Department = 1,
    /// <summary>حسب الدور</summary>
    Role = 2,
    /// <summary>حسب الموقع/المركز</summary>
    Location = 3,
    /// <summary>مخصص — أسماء محددة</summary>
    Custom = 4,
}

/// <summary>
/// إعلان / تبليغ
/// </summary>
public class Announcement : BaseEntity<long>
{
    /// <summary>معرف الشركة</summary>
    public Guid CompanyId { get; set; }

    /// <summary>عنوان الإعلان</summary>
    public string Title { get; set; } = string.Empty;

    /// <summary>محتوى الإعلان (نص)</summary>
    public string Body { get; set; } = string.Empty;

    /// <summary>رابط الصورة المرفقة (إن وُجد)</summary>
    public string? ImageUrl { get; set; }

    /// <summary>نوع الاستهداف</summary>
    public AnnouncementTargetType TargetType { get; set; } = AnnouncementTargetType.All;

    /// <summary>قيمة الاستهداف (اسم القسم، الدور، أو المركز) — null عند All أو Custom</summary>
    public string? TargetValue { get; set; }

    /// <summary>هل الإعلان منشور (مرئي للموظفين)</summary>
    public bool IsPublished { get; set; } = true;

    /// <summary>هل الإعلان عاجل (يتطلب تأكيد "قرأت وفهمت")</summary>
    public bool IsUrgent { get; set; } = false;

    /// <summary>هل الإعلان مثبت (يبقى في الأعلى)</summary>
    public bool IsPinned { get; set; } = false;

    /// <summary>تاريخ انتهاء الإعلان (null = بلا انتهاء)</summary>
    public DateTime? ExpiresAt { get; set; }

    /// <summary>معرف المنشئ</summary>
    public Guid CreatedByUserId { get; set; }

    // Navigation
    public virtual Company Company { get; set; } = null!;
    public virtual User CreatedByUser { get; set; } = null!;
    public virtual ICollection<AnnouncementTarget> Targets { get; set; } = new List<AnnouncementTarget>();
    public virtual ICollection<AnnouncementRead> Reads { get; set; } = new List<AnnouncementRead>();
}

/// <summary>
/// مستهدف بالإعلان — عند الاستهداف المخصص (Custom)
/// </summary>
public class AnnouncementTarget : BaseEntity<long>
{
    /// <summary>معرف الإعلان</summary>
    public long AnnouncementId { get; set; }

    /// <summary>معرف المستخدم المستهدف</summary>
    public Guid UserId { get; set; }

    // Navigation
    public virtual Announcement Announcement { get; set; } = null!;
    public virtual User User { get; set; } = null!;
}

/// <summary>
/// سجل قراءة الإعلان
/// </summary>
public class AnnouncementRead : BaseEntity<long>
{
    /// <summary>معرف الإعلان</summary>
    public long AnnouncementId { get; set; }

    /// <summary>معرف المستخدم الذي قرأ</summary>
    public Guid UserId { get; set; }

    /// <summary>وقت القراءة</summary>
    public DateTime ReadAt { get; set; } = DateTime.UtcNow;

    // Navigation
    public virtual Announcement Announcement { get; set; } = null!;
    public virtual User User { get; set; } = null!;
}
