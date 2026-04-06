namespace Sadara.Domain.Entities;

/// <summary>
/// موقع موظف — سجل واحد لكل موظف (upsert)
/// </summary>
public class EmployeeLocation : BaseEntity<long>
{
    /// <summary>اسم المستخدم (فريد)</summary>
    public string UserId { get; set; } = string.Empty;

    /// <summary>القسم</summary>
    public string? Department { get; set; }

    /// <summary>المركز</summary>
    public string? Center { get; set; }

    /// <summary>رقم الهاتف</summary>
    public string? Phone { get; set; }

    /// <summary>خط العرض</summary>
    public double Latitude { get; set; }

    /// <summary>خط الطول</summary>
    public double Longitude { get; set; }

    /// <summary>هل يشارك الموقع حالياً</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>آخر تحديث</summary>
    public DateTime LastUpdate { get; set; } = DateTime.UtcNow;

    /// <summary>معرف الشركة</summary>
    public Guid? CompanyId { get; set; }
}

/// <summary>
/// سجل تاريخي لمواقع الموظفين — يحفظ كل موقع كسجل منفصل
/// </summary>
public class EmployeeLocationLog : BaseEntity<long>
{
    public string UserId { get; set; } = string.Empty;
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public DateTime RecordedAt { get; set; } = DateTime.UtcNow;

    // ═══ حقول كشف الموقع الوهمي ═══
    public double? Accuracy { get; set; }
    public double? Altitude { get; set; }
    public double? Speed { get; set; }
    public bool IsMocked { get; set; }
    public bool IsFakeDetected { get; set; }
    public string? FakeReasons { get; set; }
    public int TeleportCount { get; set; }
    public int FakeFlagCount { get; set; }
}
