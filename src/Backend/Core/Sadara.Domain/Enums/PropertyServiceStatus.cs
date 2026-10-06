namespace Sadara.Domain.Enums;

/// <summary>
/// حالة الخدمة المرتبطة بالعقار.
/// </summary>
public enum PropertyServiceStatus
{
    /// <summary>فعّالة.</summary>
    Active = 0,

    /// <summary>موقوفة مؤقتاً.</summary>
    Suspended = 1,

    /// <summary>منتهية.</summary>
    Ended = 2
}
