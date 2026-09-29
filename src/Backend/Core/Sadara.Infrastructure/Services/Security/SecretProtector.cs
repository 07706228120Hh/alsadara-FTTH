using Microsoft.AspNetCore.DataProtection;
using Sadara.Application.Interfaces;

namespace Sadara.Infrastructure.Services.Security;

/// <summary>
/// تنفيذ <see cref="ISecretProtector"/> عبر ASP.NET Core Data Protection.
///
/// يستخدم <c>purpose</c> ثابتاً خاصاً بأسرار حسابات الساس بحيث لا يمكن فكّ تشفير
/// سرّ ساس بمُحمٍّ (protector) لغرض آخر (عزل الأغراض من ضمانات Data Protection).
///
/// ⚠️ لا يُسجَّل النص الصريح ولا المشفّر في أي log هنا؛ عند فشل فكّ التشفير
/// (مفتاح مفقود/تالف) يُرمى استثناء ليُعالَج في طبقة أعلى دون تسريب المحتوى.
/// </summary>
public class SecretProtector : ISecretProtector
{
    /// <summary>غرض التشفير الثابت لأسرار حسابات الساس — لا يُغيّر بعد الإطلاق كي تبقى الأسرار المخزّنة قابلة للفكّ.</summary>
    private const string Purpose = "Sadara.SasAccount.Password";

    private readonly IDataProtector _protector;

    public SecretProtector(IDataProtectionProvider provider)
    {
        _protector = provider.CreateProtector(Purpose);
    }

    public string Protect(string plaintext)
    {
        // نسمح بالنص الفارغ (حساب بلا كلمة مرور محفوظة) دون تشفير قيمة فارغة.
        if (string.IsNullOrEmpty(plaintext)) return string.Empty;
        return _protector.Protect(plaintext);
    }

    public string Unprotect(string ciphertext)
    {
        if (string.IsNullOrEmpty(ciphertext)) return string.Empty;
        return _protector.Unprotect(ciphertext);
    }
}
