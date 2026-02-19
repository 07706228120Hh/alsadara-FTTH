namespace Sadara.Domain.Entities;

/// <summary>سجل الحضور والانصراف للموظفين</summary>
public class AttendanceRecord : BaseEntity<long>
{
    /// <summary>معرف المستخدم (الموظف)</summary>
    public Guid UserId { get; set; }
    
    /// <summary>اسم المستخدم</summary>
    public string UserName { get; set; } = string.Empty;
    
    /// <summary>معرف الشركة</summary>
    public Guid? CompanyId { get; set; }
    
    /// <summary>تاريخ اليوم</summary>
    public DateOnly Date { get; set; }
    
    /// <summary>وقت تسجيل الحضور</summary>
    public DateTime? CheckInTime { get; set; }
    
    /// <summary>وقت تسجيل الانصراف</summary>
    public DateTime? CheckOutTime { get; set; }
    
    /// <summary>اسم المركز/الفرع</summary>
    public string? CenterName { get; set; }
    
    /// <summary>موقع تسجيل الحضور (خط العرض)</summary>
    public double? CheckInLatitude { get; set; }
    
    /// <summary>موقع تسجيل الحضور (خط الطول)</summary>
    public double? CheckInLongitude { get; set; }
    
    /// <summary>موقع تسجيل الانصراف (خط العرض)</summary>
    public double? CheckOutLatitude { get; set; }
    
    /// <summary>موقع تسجيل الانصراف (خط الطول)</summary>
    public double? CheckOutLongitude { get; set; }
    
    /// <summary>كود الأمان المستخدم</summary>
    public string? SecurityCode { get; set; }
    
    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }
    
    // Navigation
    public User? User { get; set; }
}

/// <summary>مراكز العمل مع مواقعها الجغرافية</summary>
public class WorkCenter : BaseEntity<int>
{
    /// <summary>اسم المركز</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>خط العرض</summary>
    public double Latitude { get; set; }
    
    /// <summary>خط الطول</summary>
    public double Longitude { get; set; }
    
    /// <summary>نصف القطر المسموح (بالأمتار)</summary>
    public double RadiusMeters { get; set; } = 200;
    
    /// <summary>معرف الشركة</summary>
    public Guid? CompanyId { get; set; }
    
    /// <summary>هل المركز نشط</summary>
    public bool IsActive { get; set; } = true;
}
