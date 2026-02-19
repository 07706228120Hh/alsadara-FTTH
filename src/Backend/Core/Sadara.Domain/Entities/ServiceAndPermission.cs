using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

/// <summary>
/// مجموعة الصلاحيات - لتنظيم الصلاحيات في فئات
/// </summary>
public class PermissionGroup : BaseEntity<int>
{
    /// <summary>كود المجموعة الفريد - مثل "employees", "finance"</summary>
    public string Code { get; set; } = string.Empty;
    
    /// <summary>الاسم بالعربي</summary>
    public string NameAr { get; set; } = string.Empty;
    
    /// <summary>الاسم بالإنجليزي</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>الوصف</summary>
    public string? Description { get; set; }
    
    /// <summary>نوع النظام الذي تنتمي إليه المجموعة</summary>
    public SystemType SystemType { get; set; } = SystemType.SecondSystem;
    
    /// <summary>الأيقونة</summary>
    public string? Icon { get; set; }
    
    /// <summary>ترتيب العرض</summary>
    public int DisplayOrder { get; set; } = 0;
    
    /// <summary>هل المجموعة نشطة؟</summary>
    public bool IsActive { get; set; } = true;
    
    // Navigation
    public virtual ICollection<Permission> Permissions { get; set; } = new List<Permission>();
}

/// <summary>
/// تعريف الصلاحية - مثل "عرض المستخدمين"، "تعديل الطلبات"
/// </summary>
public class Permission : BaseEntity<int>
{
    /// <summary>معرف مجموعة الصلاحيات</summary>
    public int? PermissionGroupId { get; set; }
    
    /// <summary>الوحدة/القسم - مثل "users", "requests", "reports"</summary>
    public string Module { get; set; } = string.Empty;
    
    /// <summary>الإجراء - مثل "view", "create", "edit", "delete"</summary>
    public string Action { get; set; } = string.Empty;
    
    /// <summary>كود الصلاحية الفريد - مثل "users.view", "requests.create"</summary>
    public string Code { get; set; } = string.Empty;
    
    /// <summary>الاسم بالعربي</summary>
    public string NameAr { get; set; } = string.Empty;
    
    /// <summary>الاسم بالإنجليزي</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>وصف الصلاحية</summary>
    public string? Description { get; set; }
    
    /// <summary>نوع النظام الذي تنتمي إليه الصلاحية</summary>
    public SystemType SystemType { get; set; } = SystemType.SecondSystem;
    
    /// <summary>هل تتطلب أن تكون الشركة مرتبطة بنظام المواطن؟</summary>
    public bool RequiresLinkedCompany { get; set; } = false;
    
    /// <summary>هل هي صلاحية للنظام الأول؟ (للتوافق مع القديم)</summary>
    public bool IsFirstSystem { get; set; } = false;
    
    /// <summary>هل هي صلاحية للنظام الثاني؟ (للتوافق مع القديم)</summary>
    public bool IsSecondSystem { get; set; } = true;
    
    /// <summary>الترتيب للعرض</summary>
    public int DisplayOrder { get; set; } = 0;
    
    /// <summary>هل الصلاحية نشطة؟</summary>
    public bool IsActive { get; set; } = true;
    
    // Navigation
    public virtual PermissionGroup? PermissionGroup { get; set; }
    public virtual ICollection<UserPermission> UserPermissions { get; set; } = new List<UserPermission>();
    public virtual ICollection<TemplatePermission> TemplatePermissions { get; set; } = new List<TemplatePermission>();
}

/// <summary>
/// صلاحيات المستخدم - يمنحها مدير الشركة للموظفين
/// </summary>
public class UserPermission : BaseEntity<long>
{
    /// <summary>معرف المستخدم</summary>
    public Guid UserId { get; set; }
    
    /// <summary>معرف الصلاحية</summary>
    public int PermissionId { get; set; }
    
    /// <summary>هل الصلاحية ممنوحة؟</summary>
    public bool IsGranted { get; set; } = true;
    
    /// <summary>من منح الصلاحية</summary>
    public Guid GrantedById { get; set; }
    
    /// <summary>تاريخ المنح</summary>
    public DateTime GrantedAt { get; set; } = DateTime.UtcNow;
    
    /// <summary>تاريخ انتهاء الصلاحية (اختياري)</summary>
    public DateTime? ExpiresAt { get; set; }
    
    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }
    
    // Navigation
    public virtual User User { get; set; } = null!;
    public virtual Permission Permission { get; set; } = null!;
    public virtual User GrantedBy { get; set; } = null!;
}

/// <summary>
/// قالب صلاحيات - مجموعة صلاحيات معدة مسبقاً
/// </summary>
public class PermissionTemplate : BaseEntity<int>
{
    /// <summary>كود القالب الفريد</summary>
    public string Code { get; set; } = string.Empty;
    
    /// <summary>الاسم بالعربي</summary>
    public string NameAr { get; set; } = string.Empty;
    
    /// <summary>الاسم بالإنجليزي</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>الوصف</summary>
    public string? Description { get; set; }
    
    /// <summary>معرف الشركة (null = قالب عام)</summary>
    public Guid? CompanyId { get; set; }
    
    /// <summary>نوع النظام</summary>
    public SystemType SystemType { get; set; } = SystemType.SecondSystem;
    
    /// <summary>هل هو قالب النظام (لا يمكن تعديله)؟</summary>
    public bool IsSystemTemplate { get; set; } = false;
    
    /// <summary>هل القالب نشط؟</summary>
    public bool IsActive { get; set; } = true;
    
    // Navigation
    public virtual Company? Company { get; set; }
    public virtual ICollection<TemplatePermission> TemplatePermissions { get; set; } = new List<TemplatePermission>();
}

/// <summary>
/// ربط الصلاحيات بالقوالب
/// </summary>
public class TemplatePermission : BaseEntity<long>
{
    public int TemplateId { get; set; }
    public int PermissionId { get; set; }
    
    // Navigation
    public virtual PermissionTemplate Template { get; set; } = null!;
    public virtual Permission Permission { get; set; } = null!;
}

/// <summary>
/// الخدمة الرئيسية - مثل "الإنترنت"، "المنتجات"
/// </summary>
public class Service : BaseEntity<int>
{
    /// <summary>اسم الخدمة بالعربي</summary>
    public string NameAr { get; set; } = string.Empty;
    
    /// <summary>اسم الخدمة بالإنجليزي</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>الأيقونة</summary>
    public string? Icon { get; set; }
    
    /// <summary>اللون</summary>
    public string? Color { get; set; }
    
    /// <summary>الوصف</summary>
    public string? Description { get; set; }
    
    /// <summary>ترتيب العرض</summary>
    public int DisplayOrder { get; set; } = 0;
    
    /// <summary>هل الخدمة نشطة؟</summary>
    public bool IsActive { get; set; } = true;
    
    // Navigation
    public virtual ICollection<ServiceOperation> Operations { get; set; } = new List<ServiceOperation>();
    public virtual ICollection<CompanyService> CompanyServices { get; set; } = new List<CompanyService>();
}

/// <summary>
/// نوع العملية - مثل "شراء"، "تجديد"، "صيانة"
/// </summary>
public class OperationType : BaseEntity<int>
{
    /// <summary>اسم العملية بالعربي</summary>
    public string NameAr { get; set; } = string.Empty;
    
    /// <summary>اسم العملية بالإنجليزي</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>الأيقونة</summary>
    public string? Icon { get; set; }
    
    /// <summary>هل تحتاج موافقة؟</summary>
    public bool RequiresApproval { get; set; } = false;
    
    /// <summary>هل تحتاج فني؟</summary>
    public bool RequiresTechnician { get; set; } = false;
    
    /// <summary>المدة المقدرة بالأيام</summary>
    public int EstimatedDays { get; set; } = 1;
    
    /// <summary>ترتيب العرض</summary>
    public int DisplayOrder { get; set; } = 0;
    
    /// <summary>هل نشط؟</summary>
    public bool IsActive { get; set; } = true;
    
    // Navigation
    public virtual ICollection<ServiceOperation> ServiceOperations { get; set; } = new List<ServiceOperation>();
}

/// <summary>
/// ربط الخدمة بالعمليات المتاحة لها
/// </summary>
public class ServiceOperation : BaseEntity<int>
{
    public int ServiceId { get; set; }
    public int OperationTypeId { get; set; }
    
    /// <summary>السعر الأساسي (اختياري)</summary>
    public decimal? BasePrice { get; set; }
    
    /// <summary>هل مفعل؟</summary>
    public bool IsActive { get; set; } = true;
    
    /// <summary>إعدادات خاصة (JSON)</summary>
    public string? CustomSettings { get; set; }
    
    // Navigation
    public virtual Service Service { get; set; } = null!;
    public virtual OperationType OperationType { get; set; } = null!;
}

/// <summary>
/// طلب خدمة موحد - يستخدم لكل أنواع الطلبات
/// </summary>
public class ServiceRequest : BaseEntity<Guid>
{
    /// <summary>رقم الطلب - SR-2025-00001</summary>
    public string RequestNumber { get; set; } = string.Empty;
    
    // ============ الخدمة والعملية ============
    
    public int ServiceId { get; set; }
    public int OperationTypeId { get; set; }
    
    // ============ المواطن ============
    
    /// <summary>معرف المواطن الذي طلب (اختياري لطلبات الوكلاء)</summary>
    public Guid? CitizenId { get; set; }
    
    // ============ الوكيل ============
    
    /// <summary>معرف الوكيل الذي أنشأ الطلب (اختياري - null لطلبات المواطنين المباشرة)</summary>
    public Guid? AgentId { get; set; }
    
    // ============ الشركة ============
    
    /// <summary>الشركة المسؤولة (اختياري - يمكن أن يكون null إذا لم يُعين بعد)</summary>
    public Guid? CompanyId { get; set; }
    
    // ============ الحالة ============
    
    public ServiceRequestStatus Status { get; set; } = ServiceRequestStatus.Pending;
    
    /// <summary>ملاحظة على الحالة</summary>
    public string? StatusNote { get; set; }
    
    // ============ التواريخ ============
    
    public DateTime RequestedAt { get; set; } = DateTime.UtcNow;
    public DateTime? ReviewedAt { get; set; }
    public DateTime? AssignedAt { get; set; }
    public DateTime? StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    public DateTime? CancelledAt { get; set; }
    
    // ============ التفاصيل ============
    
    /// <summary>تفاصيل إضافية (JSON) - حقول مرنة حسب نوع الطلب</summary>
    public string? Details { get; set; }
    
    /// <summary>عنوان التنفيذ</summary>
    public string? Address { get; set; }
    
    /// <summary>المدينة</summary>
    public string? City { get; set; }
    
    /// <summary>المنطقة</summary>
    public string? Area { get; set; }
    
    /// <summary>رقم الهاتف للتواصل</summary>
    public string? ContactPhone { get; set; }
    
    /// <summary>التكلفة المقدرة</summary>
    public decimal? EstimatedCost { get; set; }
    
    /// <summary>التكلفة النهائية</summary>
    public decimal? FinalCost { get; set; }
    
    /// <summary>باقة الإنترنت المرتبطة بالطلب (لحساب العمولة)</summary>
    public Guid? InternetPlanId { get; set; }
    
    /// <summary>الأولوية (1-5)</summary>
    public int Priority { get; set; } = 3;
    
    // ============ التعيين ============
    
    /// <summary>الموظف المعين</summary>
    public Guid? AssignedToId { get; set; }
    
    /// <summary>الفني المعين (إذا كان نوع العملية يحتاج فني)</summary>
    public Guid? TechnicianId { get; set; }
    
    // ============ التقييم ============
    
    /// <summary>تقييم المواطن (1-5)</summary>
    public int? Rating { get; set; }
    
    /// <summary>تعليق المواطن</summary>
    public string? RatingComment { get; set; }
    
    public DateTime? RatedAt { get; set; }
    
    // ============ Navigation ============
    
    public virtual Service Service { get; set; } = null!;
    public virtual OperationType OperationType { get; set; } = null!;
    public virtual User? Citizen { get; set; }
    public virtual Agent? Agent { get; set; }
    public virtual Company? Company { get; set; }
    public virtual InternetPlan? InternetPlan { get; set; }
    public virtual User? AssignedTo { get; set; }
    public virtual User? Technician { get; set; }
    
    public virtual ICollection<ServiceRequestComment> Comments { get; set; } = new List<ServiceRequestComment>();
    public virtual ICollection<ServiceRequestAttachment> Attachments { get; set; } = new List<ServiceRequestAttachment>();
    public virtual ICollection<ServiceRequestStatusHistory> StatusHistory { get; set; } = new List<ServiceRequestStatusHistory>();
}

/// <summary>
/// تعليقات على طلب الخدمة
/// </summary>
public class ServiceRequestComment : BaseEntity<long>
{
    public Guid ServiceRequestId { get; set; }
    public Guid UserId { get; set; }
    
    public string Content { get; set; } = string.Empty;
    
    /// <summary>هل مرئي للمواطن؟</summary>
    public bool IsVisibleToCitizen { get; set; } = true;
    
    /// <summary>هل هو رد تلقائي من النظام؟</summary>
    public bool IsSystemGenerated { get; set; } = false;
    
    // Navigation
    public virtual ServiceRequest ServiceRequest { get; set; } = null!;
    public virtual User User { get; set; } = null!;
}

/// <summary>
/// مرفقات طلب الخدمة
/// </summary>
public class ServiceRequestAttachment : BaseEntity<long>
{
    public Guid ServiceRequestId { get; set; }
    public Guid UploadedById { get; set; }
    
    public string FileName { get; set; } = string.Empty;
    public string FileUrl { get; set; } = string.Empty;
    public string? FileType { get; set; }
    public long FileSizeBytes { get; set; }
    
    /// <summary>وصف المرفق</summary>
    public string? Description { get; set; }
    
    // Navigation
    public virtual ServiceRequest ServiceRequest { get; set; } = null!;
    public virtual User UploadedBy { get; set; } = null!;
}

/// <summary>
/// سجل تغييرات حالة الطلب
/// </summary>
public class ServiceRequestStatusHistory : BaseEntity<long>
{
    public Guid ServiceRequestId { get; set; }
    public Guid? ChangedById { get; set; }
    
    public ServiceRequestStatus FromStatus { get; set; }
    public ServiceRequestStatus ToStatus { get; set; }
    
    public string? Note { get; set; }
    
    // Navigation
    public virtual ServiceRequest ServiceRequest { get; set; } = null!;
    public virtual User? ChangedBy { get; set; }
}
