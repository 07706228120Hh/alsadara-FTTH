namespace Sadara.Domain.Entities;

/// <summary>
/// عدّاد تخصيص رقم العقار الوطني (NPN) الذرّي لكل محافظة.
///
/// التخصيص يتمّ داخل معاملة قاعدة مع row-lock (<c>FOR UPDATE</c>) بدل قفل الذاكرة —
/// أدقّ وآمن تحت التزامن في بيئة متعدّدة العمليات.
///
/// ملاحظة: ليس كياناً مُستأجَراً (NPN وطني عبر كل الشركات لكل محافظة)؛ لا <c>CompanyId</c>.
/// </summary>
public class PropertyNpnCounter
{
    /// <summary>رمز المحافظة (رقمي) — المفتاح الأساسي.</summary>
    public int GovCode { get; set; }

    /// <summary>آخر تسلسل مُخصَّص لهذه المحافظة.</summary>
    public int LastSeq { get; set; }
}
