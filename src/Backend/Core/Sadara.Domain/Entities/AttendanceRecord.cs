namespace Sadara.Domain.Entities;

/// <summary>حالة الحضور</summary>
public enum AttendanceStatus
{
    /// <summary>حاضر في الوقت</summary>
    Present = 0,
    /// <summary>متأخر</summary>
    Late = 1,
    /// <summary>غائب</summary>
    Absent = 2,
    /// <summary>نصف يوم</summary>
    HalfDay = 3,
    /// <summary>انصراف مبكر</summary>
    EarlyDeparture = 4,
}

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
    
    /// <summary>بصمة الجهاز المستخدم للتسجيل</summary>
    public string? DeviceFingerprint { get; set; }

    // ── حقول جدول الدوام والحالة (المرحلة 1) ──

    /// <summary>حالة الحضور (حاضر، متأخر، غائب...)</summary>
    public AttendanceStatus Status { get; set; } = AttendanceStatus.Present;

    /// <summary>دقائق التأخير</summary>
    public int? LateMinutes { get; set; }

    /// <summary>دقائق العمل الإضافي</summary>
    public int? OvertimeMinutes { get; set; }

    /// <summary>دقائق العمل الفعلية</summary>
    public int? WorkedMinutes { get; set; }

    /// <summary>دقائق الانصراف المبكر</summary>
    public int? EarlyDepartureMinutes { get; set; }

    /// <summary>وقت بداية الدوام المتوقع (من جدول العمل)</summary>
    public TimeOnly? ExpectedStartTime { get; set; }

    /// <summary>وقت نهاية الدوام المتوقع (من جدول العمل)</summary>
    public TimeOnly? ExpectedEndTime { get; set; }

    /// <summary>معرف جدول العمل المستخدم</summary>
    public int? WorkScheduleId { get; set; }

    // Navigation
    public User? User { get; set; }
    public WorkSchedule? WorkSchedule { get; set; }
}

/// <summary>سجل تدقيق محاولات الحضور (ناجحة ومرفوضة)</summary>
public class AttendanceAuditLog : BaseEntity<long>
{
    /// <summary>معرف المستخدم الذي حاول التسجيل</summary>
    public Guid UserId { get; set; }
    
    /// <summary>اسم المستخدم</summary>
    public string UserName { get; set; } = string.Empty;
    
    /// <summary>معرف الشركة</summary>
    public Guid? CompanyId { get; set; }
    
    /// <summary>نوع العملية: CheckIn, CheckOut</summary>
    public string ActionType { get; set; } = string.Empty;
    
    /// <summary>هل نجحت العملية</summary>
    public bool IsSuccess { get; set; }
    
    /// <summary>سبب الرفض (إن وجد)</summary>
    public string? RejectionReason { get; set; }
    
    /// <summary>خط العرض المرسل</summary>
    public double? Latitude { get; set; }
    
    /// <summary>خط الطول المرسل</summary>
    public double? Longitude { get; set; }
    
    /// <summary>المسافة المحسوبة من المركز (بالأمتار)</summary>
    public double? DistanceFromCenter { get; set; }
    
    /// <summary>اسم المركز المستهدف</summary>
    public string? CenterName { get; set; }
    
    /// <summary>بصمة الجهاز</summary>
    public string? DeviceFingerprint { get; set; }
    
    /// <summary>بصمة الجهاز المسجلة للمستخدم (للمقارنة)</summary>
    public string? RegisteredDeviceFingerprint { get; set; }
    
    /// <summary>عنوان IP</summary>
    public string? IpAddress { get; set; }
    
    /// <summary>وقت المحاولة</summary>
    public DateTime AttemptTime { get; set; } = DateTime.UtcNow;
}

/// <summary>جدول الدوام (أوقات العمل حسب اليوم والشركة/المركز)</summary>
public class WorkSchedule : BaseEntity<int>
{
    /// <summary>اسم الجدول (مثل: الدوام الرسمي، دوام مسائي)</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>معرف الشركة</summary>
    public Guid? CompanyId { get; set; }

    /// <summary>اسم المركز (null = جميع المراكز)</summary>
    public string? CenterName { get; set; }

    /// <summary>يوم الأسبوع (0=أحد .. 6=سبت). null = جميع أيام العمل</summary>
    public int? DayOfWeek { get; set; }

    /// <summary>وقت بداية الدوام</summary>
    public TimeOnly WorkStartTime { get; set; }

    /// <summary>وقت نهاية الدوام</summary>
    public TimeOnly WorkEndTime { get; set; }

    /// <summary>فترة السماح بالتأخير (بالدقائق)</summary>
    public int LateGraceMinutes { get; set; } = 15;

    /// <summary>حد الانصراف المبكر (بالدقائق قبل نهاية الدوام)</summary>
    public int EarlyDepartureThresholdMinutes { get; set; } = 15;

    /// <summary>هل هذا الجدول الافتراضي</summary>
    public bool IsDefault { get; set; } = false;

    /// <summary>هل الجدول نشط</summary>
    public bool IsActive { get; set; } = true;

    // Navigation
    public Company? Company { get; set; }
}

/// <summary>مراكز العمل مع مواقعها الجغرافية</summary>
public class WorkCenter : BaseEntity<int>
{
    /// <summary>اسم المركز</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>العنوان/الوصف</summary>
    public string? Description { get; set; }
    
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
    
    // Navigation
    public Company? Company { get; set; }
}

// ============================================================
//  نظام الإجازات (المرحلة 2)
// ============================================================

/// <summary>نوع الإجازة</summary>
public enum LeaveType
{
    /// <summary>إجازة سنوية</summary>
    Annual = 0,
    /// <summary>إجازة مرضية</summary>
    Sick = 1,
    /// <summary>إجازة بدون راتب</summary>
    Unpaid = 2,
    /// <summary>إجازة طارئة</summary>
    Emergency = 3,
    /// <summary>إجازة رسمية (عطلة)</summary>
    Official = 4,
    /// <summary>إجازة زواج</summary>
    Marriage = 5,
    /// <summary>إجازة أبوة/أمومة</summary>
    Parental = 6,
    /// <summary>إجازة وفاة</summary>
    Bereavement = 7,
}

/// <summary>حالة طلب الإجازة</summary>
public enum LeaveRequestStatus
{
    /// <summary>بانتظار الموافقة</summary>
    Pending = 0,
    /// <summary>تمت الموافقة</summary>
    Approved = 1,
    /// <summary>مرفوض</summary>
    Rejected = 2,
    /// <summary>ملغي بواسطة الموظف</summary>
    Cancelled = 3,
}

/// <summary>طلب إجازة</summary>
public class LeaveRequest : BaseEntity<long>
{
    /// <summary>معرف الموظف</summary>
    public Guid UserId { get; set; }

    /// <summary>اسم الموظف</summary>
    public string UserName { get; set; } = string.Empty;

    /// <summary>معرف الشركة</summary>
    public Guid? CompanyId { get; set; }

    /// <summary>نوع الإجازة</summary>
    public LeaveType LeaveType { get; set; }

    /// <summary>تاريخ بداية الإجازة</summary>
    public DateOnly StartDate { get; set; }

    /// <summary>تاريخ نهاية الإجازة</summary>
    public DateOnly EndDate { get; set; }

    /// <summary>عدد الأيام</summary>
    public int TotalDays { get; set; }

    /// <summary>سبب الإجازة</summary>
    public string? Reason { get; set; }

    /// <summary>حالة الطلب</summary>
    public LeaveRequestStatus Status { get; set; } = LeaveRequestStatus.Pending;

    /// <summary>معرف المدير الذي وافق/رفض</summary>
    public Guid? ReviewedByUserId { get; set; }

    /// <summary>اسم المدير الذي وافق/رفض</summary>
    public string? ReviewedByUserName { get; set; }

    /// <summary>تاريخ المراجعة</summary>
    public DateTime? ReviewedAt { get; set; }

    /// <summary>ملاحظات المدير</summary>
    public string? ReviewNotes { get; set; }

    /// <summary>مرفق (رابط ملف مثل تقرير طبي)</summary>
    public string? AttachmentUrl { get; set; }

    // Navigation
    public User? User { get; set; }
}

/// <summary>رصيد إجازات الموظف لسنة معينة</summary>
public class LeaveBalance : BaseEntity<long>
{
    /// <summary>معرف الموظف</summary>
    public Guid UserId { get; set; }

    /// <summary>معرف الشركة</summary>
    public Guid? CompanyId { get; set; }

    /// <summary>السنة</summary>
    public int Year { get; set; }

    /// <summary>نوع الإجازة</summary>
    public LeaveType LeaveType { get; set; }

    /// <summary>الرصيد الإجمالي المستحق</summary>
    public int TotalAllowance { get; set; }

    /// <summary>الأيام المستخدمة</summary>
    public int UsedDays { get; set; }

    /// <summary>الرصيد المتبقي</summary>
    public int RemainingDays => TotalAllowance - UsedDays;

    // Navigation
    public User? User { get; set; }
}
