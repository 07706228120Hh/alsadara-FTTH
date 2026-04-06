namespace Sadara.Domain.Entities;

/// <summary>
/// جدول ربط الموظف بأقسام متعددة (Many-to-Many)
/// </summary>
public class UserDepartment : BaseEntity<int>
{
    /// <summary>معرف المستخدم/الموظف</summary>
    public Guid UserId { get; set; }

    /// <summary>معرف القسم</summary>
    public int DepartmentId { get; set; }

    /// <summary>هل هو القسم الرئيسي للموظف؟</summary>
    public bool IsPrimary { get; set; } = false;

    // Navigation
    public User User { get; set; } = null!;
    public Department Department { get; set; } = null!;
}
