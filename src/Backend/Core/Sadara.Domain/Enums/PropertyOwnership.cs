namespace Sadara.Domain.Enums;

/// <summary>
/// نوع ملكية العقار (مِلك أو إيجار).
/// </summary>
public enum PropertyOwnership
{
    /// <summary>مملوك — العقار مِلك لصاحبه.</summary>
    Owned = 0,

    /// <summary>إيجار — العقار مستأجَر.</summary>
    Rent = 1
}
