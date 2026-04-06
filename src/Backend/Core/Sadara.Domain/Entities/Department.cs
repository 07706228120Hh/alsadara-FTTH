namespace Sadara.Domain.Entities;

/// <summary>
/// قسم الشركة - كل شركة لها أقسام خاصة بها
/// </summary>
public class Department : BaseEntity<int>
{
    /// <summary>اسم القسم بالعربي</summary>
    public string NameAr { get; set; } = string.Empty;

    /// <summary>اسم القسم بالإنجليزي (اختياري)</summary>
    public string? Name { get; set; }

    /// <summary>معرف الشركة المالكة</summary>
    public Guid CompanyId { get; set; }

    /// <summary>ترتيب العرض</summary>
    public int SortOrder { get; set; } = 0;

    /// <summary>هل القسم نشط؟</summary>
    public bool IsActive { get; set; } = true;

    // Navigation
    public Company Company { get; set; } = null!;
    public ICollection<DepartmentTask> Tasks { get; set; } = new List<DepartmentTask>();
    public ICollection<UserDepartment> UserDepartments { get; set; } = new List<UserDepartment>();
}

/// <summary>
/// مهمة مرتبطة بقسم معين
/// </summary>
public class DepartmentTask : BaseEntity<int>
{
    /// <summary>اسم المهمة بالعربي</summary>
    public string NameAr { get; set; } = string.Empty;

    /// <summary>اسم المهمة بالإنجليزي (اختياري)</summary>
    public string? Name { get; set; }

    /// <summary>معرف القسم</summary>
    public int DepartmentId { get; set; }

    /// <summary>ترتيب العرض</summary>
    public int SortOrder { get; set; } = 0;

    /// <summary>هل المهمة نشطة؟</summary>
    public bool IsActive { get; set; } = true;

    // Navigation
    public Department Department { get; set; } = null!;
}
