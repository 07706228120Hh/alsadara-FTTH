namespace Sadara.Domain.Entities;

/// <summary>إحصائيات المنطقة - بيانات FBG وإحصائيات المشتركين</summary>
public class ZoneStatistic : BaseEntity<int>
{
    /// <summary>اسم المنطقة (FBG)</summary>
    public string ZoneName { get; set; } = string.Empty;
    
    /// <summary>عدد منافذ FATS</summary>
    public int Fats { get; set; }
    
    /// <summary>إجمالي المستخدمين</summary>
    public int TotalUsers { get; set; }
    
    /// <summary>المستخدمين النشطين</summary>
    public int ActiveUsers { get; set; }
    
    /// <summary>المستخدمين غير المشتركين/غير النشطين</summary>
    public int InactiveUsers { get; set; }
    
    /// <summary>اسم المنطقة الجغرافية</summary>
    public string? RegionName { get; set; }
    
    /// <summary>معرف الشركة</summary>
    public Guid? CompanyId { get; set; }
}
