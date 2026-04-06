namespace Sadara.Domain.Entities;

/// <summary>
/// سجل عمليات مزامنة FTTH
/// يحفظ تاريخ كل عملية مزامنة مع النتائج والأخطاء
/// </summary>
public class FtthSyncLog : BaseEntity<long>
{
    /// <summary>معرف الشركة</summary>
    public Guid CompanyId { get; set; }

    /// <summary>وقت البداية</summary>
    public DateTime StartedAt { get; set; } = DateTime.UtcNow;

    /// <summary>وقت الانتهاء</summary>
    public DateTime? CompletedAt { get; set; }

    /// <summary>الحالة (Success, Failed, Cancelled, InProgress)</summary>
    public string Status { get; set; } = "InProgress";

    /// <summary>عدد المشتركين الذين تم جلبهم</summary>
    public int SubscribersCount { get; set; }

    /// <summary>عدد أرقام الهواتف التي تم جلبها</summary>
    public int PhonesCount { get; set; }

    /// <summary>عدد التفاصيل (FDT/FAT) التي تم جلبها</summary>
    public int DetailsCount { get; set; }

    /// <summary>عدد المشتركين الجدد</summary>
    public int NewCount { get; set; }

    /// <summary>عدد المشتركين المحدثين</summary>
    public int UpdatedCount { get; set; }

    /// <summary>رسالة الخطأ (إذا فشلت)</summary>
    public string? ErrorMessage { get; set; }

    /// <summary>مدة المزامنة بالثواني</summary>
    public int DurationSeconds { get; set; }

    /// <summary>هل مزامنة تزايدية أم كاملة؟</summary>
    public bool IsIncremental { get; set; }

    /// <summary>من شغّل المزامنة (Manual, Auto, Trigger)</summary>
    public string TriggerSource { get; set; } = "Auto";

    // ============ العلاقات ============

    /// <summary>الشركة</summary>
    public virtual Company Company { get; set; } = null!;
}
