namespace Sadara.Domain.Enums;

/// <summary>
/// نوع الخدمة المرتبطة بالعقار — قابل للتوسّع بلا إعادة هيكلة (ماستر/أي خدمة مستقبلية).
/// </summary>
public enum PropertyServiceType
{
    /// <summary>إنترنت (ساز/FTTH).</summary>
    Internet = 0,

    /// <summary>خدمة ماستر.</summary>
    Master = 1,

    /// <summary>تلفزيون عبر الإنترنت (IPTV).</summary>
    Iptv = 2,

    /// <summary>خدمة أخرى (حرّة).</summary>
    Other = 99
}
