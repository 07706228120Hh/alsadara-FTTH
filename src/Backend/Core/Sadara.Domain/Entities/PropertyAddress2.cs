namespace Sadara.Domain.Entities;

/// <summary>
/// العنوان 2 — مستوى عنوان يتبع منطقة (<see cref="SasRegion"/>) ضمن بنية المواقع الهرمية
/// لسجل العقارات: المنطقة → العنوان 2 → العنوان 3. بيانات رئيسية معزولة بالشركة.
/// </summary>
public class PropertyAddress2 : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرّف الشركة المالكة (مفتاح العزل بين المستأجرين).</summary>
    public Guid CompanyId { get; set; }

    /// <summary>المنطقة الأب (<see cref="SasRegion"/>).</summary>
    public Guid RegionId { get; set; }

    /// <summary>اسم العنوان 2.</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>هل نشط؟</summary>
    public bool IsActive { get; set; } = true;

    // ============ العلاقات ============

    /// <summary>المنطقة الأب.</summary>
    public virtual SasRegion Region { get; set; } = null!;

    /// <summary>عناوين المستوى الثالث التابعة.</summary>
    public virtual ICollection<PropertyAddress3> Children { get; set; } = new List<PropertyAddress3>();
}
