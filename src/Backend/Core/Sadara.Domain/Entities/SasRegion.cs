namespace Sadara.Domain.Entities;

/// <summary>
/// منطقة جغرافية لمشتركي الساس (تُدار يدوياً من الوكيل) — أساس تجميع المشتركين وتطبيق أجور الصيانة.
/// لكل منطقة <see cref="MaintenanceFee"/> مبلغ صيانة ثابت يُطبَّق تلقائياً على مشتركيها عند التفعيل/التجديد.
///
/// معزولة بمستأجرين عبر <see cref="CompanyId"/> (توسم <see cref="ITenantScoped"/>) — يطبَّق عليها فلتر المستأجر المركزي.
/// فهرس فريد (CompanyId + Name) لمنع تكرار اسم المنطقة ضمن الشركة نفسها.
/// يرتبط بها المشترك عبر <see cref="SasSubscriberProfile.RegionId"/>.
/// </summary>
public class SasRegion : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرف الشركة المالكة (مفتاح العزل بين المستأجرين)</summary>
    public Guid CompanyId { get; set; }

    /// <summary>اسم المنطقة (فريد ضمن الشركة) — مثل: «شارع النسيم»</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>رمز اختياري مختصر للمنطقة (للتقارير/التصفية)</summary>
    public string? Code { get; set; }

    /// <summary>المحافظة التي تتبعها المنطقة (اختياري — للتجميع)</summary>
    public string? Governorate { get; set; }

    /// <summary>المدينة/القضاء (اختياري — للتجميع)</summary>
    public string? City { get; set; }

    /// <summary>مبلغ أجور الصيانة الثابت لهذه المنطقة — يُطبَّق تلقائياً على مشتركيها (≥0)</summary>
    public decimal MaintenanceFee { get; set; }

    /// <summary>هل المنطقة مفعّلة؟</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>ملاحظات اختيارية</summary>
    public string? Notes { get; set; }

    // ============ العلاقات ============

    /// <summary>الشركة المالكة</summary>
    public virtual Company Company { get; set; } = null!;
}
