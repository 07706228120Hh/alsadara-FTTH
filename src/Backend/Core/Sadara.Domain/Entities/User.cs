using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

public class User : BaseEntity<Guid>
{
    /// <summary>اسم المستخدم للدخول (للموظفين ومدير النظام)</summary>
    public string? Username { get; set; }
    
    public string FullName { get; set; } = string.Empty;
    public string PhoneNumber { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public string? Email { get; set; }
    public UserRole Role { get; set; } = UserRole.Citizen;
    public string? ProfileImageUrl { get; set; }
    public bool IsActive { get; set; } = true;
    public bool IsPhoneVerified { get; set; } = false;
    
    // ============ معلومات الموقع ============
    public string? City { get; set; }
    public string? Area { get; set; }
    public string? Address { get; set; }
    
    // ============ معلومات الشركة (للموظفين) ============
    
    /// <summary>الشركة التي يعمل بها الموظف</summary>
    public Guid? CompanyId { get; set; }
    
    /// <summary>القسم في الشركة</summary>
    public string? Department { get; set; }
    
    /// <summary>كود الموظف</summary>
    public string? EmployeeCode { get; set; }
    
    /// <summary>المركز/الفرع</summary>
    public string? Center { get; set; }
    
    /// <summary>الراتب (اختياري)</summary>
    public decimal? Salary { get; set; }

    // ============ بيانات HR ============
    
    /// <summary>رقم الهوية الوطنية</summary>
    public string? NationalId { get; set; }
    
    /// <summary>تاريخ الميلاد</summary>
    public DateTime? DateOfBirth { get; set; }
    
    /// <summary>تاريخ التعيين</summary>
    public DateTime? HireDate { get; set; }
    
    /// <summary>نوع العقد: permanent/contract/partTime</summary>
    public string? ContractType { get; set; }
    
    /// <summary>رقم الحساب البنكي</summary>
    public string? BankAccountNumber { get; set; }
    
    /// <summary>اسم البنك</summary>
    public string? BankName { get; set; }
    
    /// <summary>جهة اتصال الطوارئ - الاسم</summary>
    public string? EmergencyContactName { get; set; }
    
    /// <summary>جهة اتصال الطوارئ - الرقم</summary>
    public string? EmergencyContactPhone { get; set; }
    
    /// <summary>ملاحظات HR</summary>
    public string? HrNotes { get; set; }

    // ============ الحساب المالي للفني (ملخص محسوب) ============

    /// <summary>إجمالي الأجور المترتبة على الفني</summary>
    public decimal TechTotalCharges { get; set; } = 0;

    /// <summary>إجمالي التسديدات من الفني</summary>
    public decimal TechTotalPayments { get; set; } = 0;

    /// <summary>الصافي = التسديدات - الأجور (سالب = عليه)</summary>
    public decimal TechNetBalance { get; set; } = 0;
    
    /// <summary>
    /// صلاحيات النظام الأول (JSON)
    /// مثال: {"attendance":true,"agent":false}
    /// </summary>
    public string? FirstSystemPermissions { get; set; }
    
    /// <summary>
    /// صلاحيات النظام الثاني (JSON)
    /// مثال: {"users":true,"subscriptions":false}
    /// </summary>
    public string? SecondSystemPermissions { get; set; }
    
    // ============ V2 - صلاحيات مفصلة (إجراءات) ============
    
    /// <summary>
    /// صلاحيات النظام الأول V2 (JSON) - مع إجراءات مفصلة
    /// مثال: {"attendance":{"view":true,"add":false,"edit":false,"delete":false}}
    /// </summary>
    public string? FirstSystemPermissionsV2 { get; set; }
    
    /// <summary>
    /// صلاحيات النظام الثاني V2 (JSON) - مع إجراءات مفصلة
    /// مثال: {"users":{"view":true,"add":true,"edit":false,"delete":false,"export":false}}
    /// </summary>
    public string? SecondSystemPermissionsV2 { get; set; }
    
    // ============ الأمان والجلسة ============
    
    public string? RefreshToken { get; set; }
    public DateTime? RefreshTokenExpiryTime { get; set; }
    public string? VerificationCode { get; set; }
    public DateTime? VerificationCodeExpiresAt { get; set; }
    public int FailedLoginAttempts { get; set; } = 0;
    public DateTime? LockoutEnd { get; set; }
    public DateTime? LastLoginAt { get; set; }
    public string? LastLoginDeviceId { get; set; }
    public string? LastLoginDeviceInfo { get; set; }
    
    /// <summary>بصمة الجهاز المسجلة للحضور (لا يمكن تسجيل حضور من جهاز مختلف)</summary>
    public string? RegisteredDeviceFingerprint { get; set; }
    
    // ============ FTTH Integration ============
    
    /// <summary>اسم المستخدم في نظام FTTH (null = فني فقط، ليس مشغل FTTH)</summary>
    public string? FtthUsername { get; set; }
    
    /// <summary>كلمة مرور FTTH مشفرة (AES) — null إذا ليس مشغل FTTH</summary>
    public string? FtthPasswordEncrypted { get; set; }
    
    // ============ Navigation ============
    
    public virtual Merchant? Merchant { get; set; }
    public virtual Company? Company { get; set; }
    public virtual ICollection<UserPermission> UserPermissions { get; set; } = new List<UserPermission>();
    
    // ============ خصائص مساعدة ============
    
    /// <summary>هل هو مدير شركة أو أعلى؟</summary>
    public bool IsCompanyAdminOrAbove => Role >= UserRole.CompanyAdmin;
    
    /// <summary>هل هو مشرف أو أعلى؟</summary>
    public bool IsManagerOrAbove => Role >= UserRole.Manager;
    
    /// <summary>هل هو موظف شركة؟</summary>
    public bool IsCompanyEmployee => CompanyId.HasValue && Role >= UserRole.Employee && Role < UserRole.CompanyAdmin;
    
    /// <summary>هل هو مواطن (زبون)؟</summary>
    public bool IsCitizen => Role == UserRole.Citizen;
}

