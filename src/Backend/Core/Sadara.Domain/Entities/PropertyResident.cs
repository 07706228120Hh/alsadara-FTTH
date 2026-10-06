using Sadara.Domain.Enums;

namespace Sadara.Domain.Entities;

/// <summary>
/// ربط المواطن (Citizen الموجود) بالعقار — علاقة متعدّد-لمتعدّد مع بيانات إضافية:
/// عقار قد يضمّ أكثر من مواطن؛ ومواطن قد يرتبط بأكثر من عقار.
/// معزول بالمستأجرين عبر <see cref="CompanyId"/> (يوسم <see cref="ITenantScoped"/>).
/// </summary>
public class PropertyResident : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرّف الشركة المالكة (مفتاح العزل بين المستأجرين).</summary>
    public Guid CompanyId { get; set; }

    /// <summary>معرّف العقار المرتبط.</summary>
    public Guid PropertyId { get; set; }

    /// <summary>معرّف المواطن (Citizen الموجود) المرتبط.</summary>
    public Guid CitizenId { get; set; }

    /// <summary>علاقة المواطن بالعقار (مالك/مستأجر/ساكن).</summary>
    public ResidentRelationship Relationship { get; set; }

    /// <summary>هل هذا المواطن هو جهة الاتصال الأساسية للعقار؟</summary>
    public bool IsPrimary { get; set; }

    // ============ العلاقات ============

    /// <summary>العقار المرتبط.</summary>
    public virtual Property Property { get; set; } = null!;

    /// <summary>المواطن المرتبط.</summary>
    public virtual Citizen Citizen { get; set; } = null!;
}
