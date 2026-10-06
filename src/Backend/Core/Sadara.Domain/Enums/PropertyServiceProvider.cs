namespace Sadara.Domain.Enums;

/// <summary>
/// مزوّد الخدمة المرتبطة بالعقار (مصدر الربط التقني).
/// </summary>
public enum PropertyServiceProvider
{
    /// <summary>نظام الساز (SAS4) — إنترنت ساز.</summary>
    Sas = 0,

    /// <summary>نظام FTTH الخارجي.</summary>
    Ftth = 1,

    /// <summary>مزوّد خارجي/يدوي (ماستر وغيره).</summary>
    External = 2
}
