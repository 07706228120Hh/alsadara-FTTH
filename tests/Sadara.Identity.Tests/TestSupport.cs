using System.Security.Cryptography;
using Microsoft.Extensions.Configuration;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;

namespace Sadara.Identity.Tests;

/// <summary>
/// أدوات مساعدة للاختبارات المعزولة عن قاعدة البيانات.
///
/// ملاحظات أمنية:
/// - مفاتيح RSA للاختبار تُولَّد وقت التشغيل في الذاكرة فقط، ولا تُكتب إلى المستودع ولا تُطبع.
/// - سرّ HS256 المستخدم في الاختبار قيمة تجريبية محلية غير مرتبطة بأي سرّ إنتاجي.
/// </summary>
internal static class TestSupport
{
    public const string Issuer = "sadara-test-issuer";
    public const string Audience = "sadara-test-audience";

    /// <summary>
    /// يبني IConfiguration في الذاكرة بإعداد Jwt الافتراضي (HS256؛ Jwt:Algorithm غير مضبوط عمداً).
    /// يستخدمه JwtTokenSigner في الوضع OFF. لا appsettings ولا اتصال DB.
    /// </summary>
    public static IConfiguration BuildConfig(string secret, int expiryMinutes = 60)
        => new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Jwt:Secret"] = secret,
                ["Jwt:Issuer"] = Issuer,
                ["Jwt:Audience"] = Audience,
                ["Jwt:ExpiryMinutes"] = expiryMinutes.ToString(),
                // Jwt:Algorithm غير مضبوط عمداً ⇒ HS256 الافتراضي (flag OFF).
            })
            .Build();

    /// <summary>
    /// يولّد زوج مفاتيح RSA-2048 مؤقتاً ويعيد المفتاح الخاص بصيغة PEM (نصّ في الذاكرة فقط).
    /// لا يُكتب إلى قرص ولا يُطبع في أي مخرجات.
    /// </summary>
    public static string GenerateEphemeralRsaPrivateKeyPem(int keySizeBits = 2048)
    {
        using var rsa = RSA.Create(keySizeBits);
        return rsa.ExportPkcs8PrivateKeyPem();
    }

    /// <summary>
    /// مستخدم اختبار يحمل نفس الحقول التي تُقرأ في GenerateAccessToken (بما فيها CompanyId).
    /// </summary>
    public static User BuildUser(
        Guid? id = null,
        Guid? companyId = null,
        string fullName = "مستخدم اختبار",
        string phone = "07700000000",
        UserRole role = UserRole.Employee,
        Guid? merchantId = null)
    {
        var user = new User
        {
            Id = id ?? Guid.NewGuid(),
            FullName = fullName,
            PhoneNumber = phone,
            Role = role,
            CompanyId = companyId
        };

        if (merchantId.HasValue)
            user.Merchant = new Merchant { Id = merchantId.Value };

        return user;
    }
}
