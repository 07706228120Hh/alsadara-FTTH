namespace Sadara.Domain.Entities;

/// <summary>مشترك ISP - بيانات مشتركي الإنترنت</summary>
public class ISPSubscriber : BaseEntity<long>
{
    /// <summary>اسم المشترك</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>المنطقة</summary>
    public string? Region { get; set; }
    
    /// <summary>الوكيل</summary>
    public string? Agent { get; set; }
    
    /// <summary>الداش (معرف الشبكة)</summary>
    public string? Dash { get; set; }
    
    /// <summary>اسم الأم (للبحث بالقرابة)</summary>
    public string? MotherName { get; set; }
    
    /// <summary>رقم الهاتف</summary>
    public string? PhoneNumber { get; set; }
    
    /// <summary>معرف الشركة</summary>
    public Guid? CompanyId { get; set; }
}
