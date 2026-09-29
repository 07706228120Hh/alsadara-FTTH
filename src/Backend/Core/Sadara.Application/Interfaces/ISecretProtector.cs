namespace Sadara.Application.Interfaces;

/// <summary>
/// تجريد لتشفير/فكّ تشفير الأسرار الحسّاسة (مثل كلمات مرور حسابات الساس)
/// قبل حفظها في قاعدة البيانات — يعتمد على ASP.NET Core Data Protection في التنفيذ.
///
/// ⚠️ قاعدة أمنية: النص الصريح (plaintext) يبقى في الذاكرة فقط أثناء التمرير الداخلي؛
/// لا يُحفظ ولا يُعاد أبداً في أي استجابة API أو سجل (log). يُحفظ في القاعدة النص المشفّر فقط.
/// </summary>
public interface ISecretProtector
{
    /// <summary>يشفّر نصاً صريحاً ويعيد النص المشفّر (يُحفظ في القاعدة).</summary>
    string Protect(string plaintext);

    /// <summary>يفكّ تشفير نصّ مشفّر ويعيد النص الصريح (للاستخدام الداخلي في الذاكرة فقط).</summary>
    string Unprotect(string ciphertext);
}
