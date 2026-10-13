namespace Sadara.Domain.Enums;

/// <summary>
/// حالة رمز الـQR المولّد مسبقاً في مخزون الرموز (<see cref="Entities.PropertyQrToken"/>).
///
/// الرمز يُولَّد ويُطبَع فارغاً (<see cref="Unused"/>) ثم يُربط بعقار عند المسح/الملء فيصبح <see cref="Used"/>.
/// </summary>
public enum PropertyQrTokenStatus
{
    /// <summary>فارغ — مولّد ومطبوع ولم يُربط بعقار بعد.</summary>
    Unused = 0,

    /// <summary>مستخدَم — رُبط بعقار عند الملء (<c>PropertyId</c> مُعبّأ).</summary>
    Used = 1
}
