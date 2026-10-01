namespace Sadara.Domain.Entities;

/// <summary>
/// تسعير باقة ساس (SAS4 profile) لحساب ساس معيّن داخل شركة — أساس نظام الأرباح.
/// لكل باقة: كلفة (ما تدفعه الشركة للمزوّد) + سعر بيع (للمواطن). الربح = <c>SellingPrice − Cost</c> (محسوب، ليس عموداً).
///
/// معزول بمستأجرين عبر <see cref="CompanyId"/> (يوسم <see cref="ITenantScoped"/>) — يطبَّق عليه فلتر المستأجر المركزي.
/// فهرس فريد (CompanyId + SasAccountId + ProfileId) لمنع تكرار تسعير الباقة نفسها ضمن الحساب نفسه.
/// </summary>
public class SasPackagePrice : BaseEntity<Guid>, ITenantScoped
{
    /// <summary>معرف الشركة المالكة (مفتاح العزل بين المستأجرين)</summary>
    public Guid CompanyId { get; set; }

    /// <summary>
    /// معرّف حساب الساس الذي يخصّه هذا التسعير (SasAccount.Id).
    /// قد يكون null لتسعير على مستوى الشركة غير مرتبط بحساب بعينه.
    /// </summary>
    public Guid? SasAccountId { get; set; }

    /// <summary>معرّف الباقة/البروفايل في نظام الساس (SAS4 profile id) — مفتاح الربط مع باقات SAS4</summary>
    public string ProfileId { get; set; } = string.Empty;

    /// <summary>اسم الباقة/البروفايل (عرضي — يُحدَّث من باقات SAS4)</summary>
    public string ProfileName { get; set; } = string.Empty;

    /// <summary>الكلفة: ما تدفعه الشركة للمزوّد عن هذه الباقة</summary>
    public decimal Cost { get; set; }

    /// <summary>سعر البيع: ما يُحصَّل من المواطن عن هذه الباقة</summary>
    public decimal SellingPrice { get; set; }

    /// <summary>هل التسعير مفعّل؟</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>ملاحظات اختيارية حول التسعير</summary>
    public string? Notes { get; set; }
}
