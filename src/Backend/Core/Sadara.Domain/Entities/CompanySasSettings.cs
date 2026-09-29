namespace Sadara.Domain.Entities;

/// <summary>
/// إعدادات الساس (SAS) على مستوى الشركة (علاقة 1‑1 مع الشركة).
/// تحمل عنوان خادم الساس الافتراضي الذي يرثه موظفو الشركة وإعدادات المزامنة التلقائية.
/// معزولة بمستأجرين عبر <see cref="CompanyId"/> (توسم <see cref="ITenantScoped"/>).
/// </summary>
public class CompanySasSettings : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرف الشركة (مفتاح العزل بين المستأجرين — فريد لكل شركة)</summary>
    public Guid CompanyId { get; set; }

    /// <summary>عنوان خادم الساس الافتراضي للشركة (يرثه الموظفون عند ربط حساباتهم)</summary>
    public string DefaultServerUrl { get; set; } = string.Empty;

    /// <summary>فاصل المزامنة بالدقائق</summary>
    public int SyncIntervalMinutes { get; set; } = 60;

    /// <summary>هل المزامنة التلقائية مفعلة؟</summary>
    public bool IsAutoSyncEnabled { get; set; } = true;

    /// <summary>آخر وقت مزامنة ناجحة على مستوى الشركة</summary>
    public DateTime? LastSyncAt { get; set; }

    /// <summary>آخر خطأ مزامنة</summary>
    public string? LastSyncError { get; set; }

    // ============ العلاقات ============

    /// <summary>الشركة</summary>
    public virtual Company Company { get; set; } = null!;
}
