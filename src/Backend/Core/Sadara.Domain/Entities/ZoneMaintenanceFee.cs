namespace Sadara.Domain.Entities;

/// <summary>أجور صيانة الزونات — تحدد مبلغ صيانة ثابت لكل زون</summary>
public class ZoneMaintenanceFee : BaseEntity<Guid>
{
    /// <summary>اسم الزون (FBG)</summary>
    public string ZoneName { get; set; } = string.Empty;

    /// <summary>معرف الزون من سيرفر FTTH</summary>
    public string? ZoneId { get; set; }

    /// <summary>مبلغ أجور الصيانة</summary>
    public decimal MaintenanceAmount { get; set; }

    /// <summary>ملاحظات</summary>
    public string? Notes { get; set; }

    /// <summary>مفعّل أم لا</summary>
    public bool IsEnabled { get; set; } = true;

    /// <summary>معرف الشركة</summary>
    public Guid CompanyId { get; set; }
    public Company? Company { get; set; }
}
