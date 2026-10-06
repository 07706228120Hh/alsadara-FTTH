namespace Sadara.Domain.Entities;

/// <summary>
/// العنوان 3 — مستوى عنوان يتبع <see cref="PropertyAddress2"/> ضمن بنية المواقع الهرمية
/// لسجل العقارات: المنطقة → العنوان 2 → العنوان 3. بيانات رئيسية معزولة بالشركة.
/// </summary>
public class PropertyAddress3 : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرّف الشركة المالكة (مفتاح العزل بين المستأجرين).</summary>
    public Guid CompanyId { get; set; }

    /// <summary>العنوان 2 الأب.</summary>
    public Guid Address2Id { get; set; }

    /// <summary>اسم العنوان 3.</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>هل نشط؟</summary>
    public bool IsActive { get; set; } = true;

    // ============ العلاقات ============

    /// <summary>العنوان 2 الأب.</summary>
    public virtual PropertyAddress2 Address2 { get; set; } = null!;
}
