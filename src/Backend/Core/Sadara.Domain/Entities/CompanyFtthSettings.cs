namespace Sadara.Domain.Entities;

/// <summary>
/// إعدادات مزامنة FTTH للشركة
/// تحفظ بيانات الدخول وإعدادات المزامنة التلقائية
/// </summary>
public class CompanyFtthSettings : BaseEntity<Guid>
{
    /// <summary>معرف الشركة</summary>
    public Guid CompanyId { get; set; }

    /// <summary>اسم مستخدم FTTH</summary>
    public string FtthUsername { get; set; } = string.Empty;

    /// <summary>كلمة مرور FTTH (مشفرة)</summary>
    public string FtthPassword { get; set; } = string.Empty;

    /// <summary>فاصل المزامنة بالدقائق</summary>
    public int SyncIntervalMinutes { get; set; } = 60;

    /// <summary>هل المزامنة التلقائية مفعلة؟</summary>
    public bool IsAutoSyncEnabled { get; set; } = true;

    /// <summary>ساعة بداية المزامنة (0-23)</summary>
    public int SyncStartHour { get; set; } = 6;

    /// <summary>ساعة نهاية المزامنة (0-23)</summary>
    public int SyncEndHour { get; set; } = 23;

    /// <summary>آخر وقت مزامنة ناجحة</summary>
    public DateTime? LastSyncAt { get; set; }

    /// <summary>آخر خطأ مزامنة</summary>
    public string? LastSyncError { get; set; }

    /// <summary>هل المزامنة قيد التنفيذ حالياً؟</summary>
    public bool IsSyncInProgress { get; set; }

    /// <summary>عدد المشتركين في الكاش</summary>
    public int CurrentDbCount { get; set; }

    /// <summary>عدد الفشل المتتالي</summary>
    public int ConsecutiveFailures { get; set; }

    // ============ تتبع التقدم أثناء المزامنة ============

    /// <summary>المرحلة الحالية (subscribers, details, phones, saving)</summary>
    public string? SyncStage { get; set; }

    /// <summary>نسبة التقدم 0-100</summary>
    public int SyncProgress { get; set; }

    /// <summary>رسالة التقدم</summary>
    public string? SyncMessage { get; set; }

    /// <summary>عدد العناصر المجلوبة حتى الآن</summary>
    public int SyncFetchedCount { get; set; }

    /// <summary>العدد الكلي المتوقع</summary>
    public int SyncTotalCount { get; set; }

    // ============ العلاقات ============

    /// <summary>الشركة</summary>
    public virtual Company Company { get; set; } = null!;
}
