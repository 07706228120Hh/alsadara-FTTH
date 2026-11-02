namespace Sadara.Domain.Enums;

/// <summary>
/// نوع «الحساب المصدر» الذي تُوسَم به المهمة (ServiceRequest).
/// يحدّد الجدول الذي يشير إليه <c>SourceAccountId</c> (FtthAccount أو SasAccount).
/// النوع المخزَّن في القاعدة = int.
/// </summary>
public enum TaskSourceAccountType
{
    /// <summary>بلا حساب مصدر (المهام القديمة/غير الموسومة) — الافتراضي.</summary>
    None = 0,

    /// <summary>حساب FTTH (مرجع إلى <see cref="Sadara.Domain.Entities.FtthAccount"/>).</summary>
    Ftth = 1,

    /// <summary>حساب ساس (مرجع إلى <see cref="Sadara.Domain.Entities.SasAccount"/>).</summary>
    Sas = 2
}
