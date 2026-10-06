namespace Sadara.Domain.Enums;

/// <summary>
/// علاقة المواطن (Citizen) بالعقار المرتبط به في سجل العقارات.
/// </summary>
public enum ResidentRelationship
{
    /// <summary>مالك العقار.</summary>
    Owner = 0,

    /// <summary>مستأجر العقار.</summary>
    Tenant = 1,

    /// <summary>ساكن (غير مالك ولا مستأجر رسمي).</summary>
    Resident = 2
}
