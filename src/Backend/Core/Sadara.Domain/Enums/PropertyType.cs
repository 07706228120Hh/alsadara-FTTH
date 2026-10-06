namespace Sadara.Domain.Enums;

/// <summary>
/// نوع العقار في سجل العقارات المستقل (محوره QR، محايد الخدمة).
/// </summary>
public enum PropertyType
{
    /// <summary>سكني — منزل/شقة سكنية.</summary>
    Residential = 0,

    /// <summary>تجاري — محل/مكتب/منشأة تجارية.</summary>
    Commercial = 1
}
