using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using FluentAssertions;
using Microsoft.IdentityModel.Tokens;
using Sadara.Infrastructure.Identity;
using Xunit;

namespace Sadara.Api.Tests;

/// <summary>
/// اختبار أمني معزول (P0) لإثبات صلابة "التشغيل المزدوج للتحقّق" (Dual-verify) ضد
/// هجوم alg confusion و alg:none، إضافةً إلى قبول التوكنات الصحيحة (HS256 و RS256).
///
/// ═══ ما الذي يُختبَر بالضبط ═══
/// هذا الاختبار يستدعي **المصنع الإنتاجي الفعلي** `JwtValidationParametersFactory.Build(...)`
/// (في `Sadara.Infrastructure.Identity`) — نفس الدالة التي يستدعيها `Program.cs` داخل
/// `.AddJwtBearer(...)` لبناء `options.TokenValidationParameters`. المصنع يبني:
///   • IssuerSigningKeys = { new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret)),   // HS256 دائماً
///                           rs256PublicKey (مع KeyId) عند التهيئة (≠ null) }             // RS256
///   • ValidAlgorithms   = { SecurityAlgorithms.HmacSha256, SecurityAlgorithms.RsaSha256 }
///   • ValidateIssuerSigningKey = ValidateIssuer = ValidateAudience = ValidateLifetime = true
///   • ClockSkew = TimeSpan.Zero
///   • ValidIssuer / ValidAudience = نفس القيم.
///
/// ثم يشغّل `new JwtSecurityTokenHandler().ValidateToken(...)` مباشرةً على هذه البارامترات.
///
/// ✅ إغلاق الفجوة (كانت documented gap): بعد استخراج البناء إلى المصنع، صار الاختبار يغطّي المسار
/// الإنتاجي الفعلي لا نسخة موازية. أي انحراف مستقبلي في منطق بناء البارامترات يُلتقَط هنا تلقائياً،
/// لأن Program.cs والاختبار يستهلكان نفس `JwtValidationParametersFactory.Build`.
/// (يبقى ما لا يُغطَّى: تركيب الـ ASP.NET middleware نفسه وربط JwtBearerEvents — خارج نطاق هذا الاختبار.)
///
/// السرّ والمفاتيح أدناه قيم اختبار محلية مولّدة لحظياً، لا علاقة لها بأي سرّ إنتاجي.
/// </summary>
public class DualVerifyAlgConfusionTests
{
    private const string Secret = "unit-test-only-hs256-secret-key-do-not-use-in-prod-0123456789";
    private const string Issuer = "SadaraPlatform";
    private const string Audience = "SadaraClients";

    // مفتاح RSA "الشرعي" للخادم (الجزء العام يدخل قائمة IssuerSigningKeys؛ الخاص يوقّع RS256 الصحيح).
    private static readonly RSA ServerRsa = CreateRsa();
    // مفتاح RSA للمهاجم (لا يُعرّفه الخادم إطلاقاً) — لإثبات رفض RS256 الموقّع بمفتاح غريب.
    private static readonly RSA AttackerRsa = CreateRsa();

    private static RSA CreateRsa()
    {
        var rsa = RSA.Create(2048);
        return rsa;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // بناء البارامترات عبر المصنع الإنتاجي الفعلي (JwtValidationParametersFactory)
    // — نفس الدالة التي يستدعيها Program.cs. لا إعادة بناء يدوية.
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>البارامترات في وضع "التشغيل المزدوج" (RS256 مهيّأ): HS256 + RS256 معاً — كما Program.cs عند Algorithm=RS256.</summary>
    private static TokenValidationParameters BuildDualVerifyParameters()
    {
        // rs256SingletonForJwks != null ⇒ يُمرَّر المفتاح العام RS256 (بنفس شكل Program.cs: RsaSecurityKey مع KeyId).
        var rs256PublicKey = new RsaSecurityKey(ServerRsa.ExportParameters(includePrivateParameters: false))
        {
            KeyId = "server-rs256-kid"
        };
        return JwtValidationParametersFactory.Build(Secret, Issuer, Audience, rs256PublicKey);
    }

    /// <summary>البارامترات في وضع "OFF" (RS256 غير مهيّأ): HS256 فقط — يُمرَّر null للمفتاح العام (كما Program.cs عند HS256).</summary>
    private static TokenValidationParameters BuildHs256OnlyParameters()
        => JwtValidationParametersFactory.Build(Secret, Issuer, Audience, rs256PublicKey: null);

    // ─────────────────────────────────────────────────────────────────────────
    // مولّدات التوكنات (صحيحة وهجومية)
    // ─────────────────────────────────────────────────────────────────────────

    private static Claim[] SampleClaims() => new[]
    {
        new Claim(ClaimTypes.NameIdentifier, "42"),
        new Claim(ClaimTypes.Name, "Test User"),
        new Claim(ClaimTypes.Role, "User"),
    };

    /// <summary>توكن HS256 صحيح موقّع بالسرّ المتماثل (UTF8) — يجب أن يُقبل.</summary>
    private static string MakeValidHs256()
    {
        var creds = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(Secret)),
            SecurityAlgorithms.HmacSha256);
        return WriteToken(creds, SecurityAlgorithms.HmacSha256);
    }

    /// <summary>توكن HS256 بسرّ خاطئ — يجب أن يُرفض.</summary>
    private static string MakeHs256WrongSecret()
    {
        var creds = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes("totally-different-wrong-secret-value-9876543210zzzz")),
            SecurityAlgorithms.HmacSha256);
        return WriteToken(creds, SecurityAlgorithms.HmacSha256);
    }

    /// <summary>توكن RS256 صحيح موقّع بمفتاح الخادم الخاص (العام في القائمة) — يجب أن يُقبل.</summary>
    private static string MakeValidRs256()
    {
        var creds = new SigningCredentials(new RsaSecurityKey(ServerRsa), SecurityAlgorithms.RsaSha256);
        return WriteToken(creds, SecurityAlgorithms.RsaSha256);
    }

    /// <summary>توكن RS256 موقّع بمفتاح المهاجم الخاص (غير معروف للخادم) — يجب أن يُرفض.</summary>
    private static string MakeRs256AttackerKey()
    {
        var creds = new SigningCredentials(new RsaSecurityKey(AttackerRsa), SecurityAlgorithms.RsaSha256);
        return WriteToken(creds, SecurityAlgorithms.RsaSha256);
    }

    /// <summary>
    /// جوهر هجوم alg confusion (P0): توكن رأسه alg:HS256، لكنه موقّع بـ HMAC-SHA256
    /// باستخدام "بايتات المفتاح العام RSA" كسرّ HMAC. نبنيه يدوياً لأن مكتبة JWT لا تسمح
    /// بتوقيع رمزي بمادة مفتاح خاطئة. hmacSecret تُمرَّر لتغطية شكلين للاستغلال (PEM أو modulus).
    /// </summary>
    private static string MakeAlgConfusionToken(byte[] hmacSecret)
    {
        var header = Base64UrlEncoder.Encode(Encoding.UTF8.GetBytes(
            "{\"alg\":\"HS256\",\"typ\":\"JWT\"}"));

        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var exp = DateTimeOffset.UtcNow.AddMinutes(30).ToUnixTimeSeconds();
        // نضبط iss/aud/exp/nbf ليجتاز فحوصات الـ issuer/audience/lifetime — فيبقى فحص التوقيع وحده هو الحاسم.
        var payloadJson =
            $"{{\"nameid\":\"42\",\"iss\":\"{Issuer}\",\"aud\":\"{Audience}\",\"nbf\":{now},\"exp\":{exp},\"iat\":{now}}}";
        var payload = Base64UrlEncoder.Encode(Encoding.UTF8.GetBytes(payloadJson));

        var signingInput = $"{header}.{payload}";
        using var hmac = new HMACSHA256(hmacSecret);
        var sig = hmac.ComputeHash(Encoding.UTF8.GetBytes(signingInput));
        var sigEncoded = Base64UrlEncoder.Encode(sig);

        return $"{signingInput}.{sigEncoded}";
    }

    /// <summary>توكن alg:none بلا توقيع (الجزء الثالث فارغ) — يجب أن يُرفض.</summary>
    private static string MakeAlgNoneToken()
    {
        var header = Base64UrlEncoder.Encode(Encoding.UTF8.GetBytes(
            "{\"alg\":\"none\",\"typ\":\"JWT\"}"));
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var exp = DateTimeOffset.UtcNow.AddMinutes(30).ToUnixTimeSeconds();
        var payloadJson =
            $"{{\"nameid\":\"42\",\"iss\":\"{Issuer}\",\"aud\":\"{Audience}\",\"nbf\":{now},\"exp\":{exp},\"iat\":{now}}}";
        var payload = Base64UrlEncoder.Encode(Encoding.UTF8.GetBytes(payloadJson));
        return $"{header}.{payload}."; // توقيع فارغ
    }

    private static string WriteToken(SigningCredentials creds, string alg)
    {
        var token = new JwtSecurityToken(
            issuer: Issuer,
            audience: Audience,
            claims: SampleClaims(),
            notBefore: DateTime.UtcNow,
            expires: DateTime.UtcNow.AddMinutes(30),
            signingCredentials: creds);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static ClaimsPrincipal Validate(string token, TokenValidationParameters tvp) =>
        new JwtSecurityTokenHandler().ValidateToken(token, tvp, out _);

    // ═════════════════════════════════════════════════════════════════════════
    // النواقل — وضع التشغيل المزدوج (HS256 + RS256)
    // ═════════════════════════════════════════════════════════════════════════

    [Fact] // (1) HS256 صحيح ⇒ يُقبل
    public void Dual_ValidHs256_IsAccepted()
    {
        var tvp = BuildDualVerifyParameters();
        var principal = Validate(MakeValidHs256(), tvp);
        principal.Should().NotBeNull();
        principal.FindFirst(ClaimTypes.NameIdentifier)!.Value.Should().Be("42");
    }

    [Fact] // (2) RS256 صحيح (العام في القائمة) ⇒ يُقبل
    public void Dual_ValidRs256_IsAccepted()
    {
        var tvp = BuildDualVerifyParameters();
        var principal = Validate(MakeValidRs256(), tvp);
        principal.Should().NotBeNull();
        principal.FindFirst(ClaimTypes.NameIdentifier)!.Value.Should().Be("42");
    }

    [Fact] // (3.a) P0 — alg confusion: HS256 موقّع بـ PEM (SPKI) للمفتاح العام كسرّ ⇒ يُرفض
    public void Dual_AlgConfusion_PublicKeyPemAsHmacSecret_IsRejected()
    {
        var tvp = BuildDualVerifyParameters();
        var pemBytes = Encoding.UTF8.GetBytes(ServerRsa.ExportSubjectPublicKeyInfoPem());
        var forged = MakeAlgConfusionToken(pemBytes);

        var act = () => Validate(forged, tvp);
        act.Should().Throw<SecurityTokenException>();
    }

    [Fact] // (3.b) P0 — alg confusion: HS256 موقّع ببايتات المُعامِل (modulus) للمفتاح العام كسرّ ⇒ يُرفض
    public void Dual_AlgConfusion_PublicKeyModulusAsHmacSecret_IsRejected()
    {
        var tvp = BuildDualVerifyParameters();
        var modulus = ServerRsa.ExportParameters(false).Modulus!;
        var forged = MakeAlgConfusionToken(modulus);

        var act = () => Validate(forged, tvp);
        act.Should().Throw<SecurityTokenException>();
    }

    [Fact] // (3.c) P0 — alg confusion: HS256 موقّع بـ DER (SPKI) الخام للمفتاح العام كسرّ ⇒ يُرفض
    public void Dual_AlgConfusion_PublicKeyDerAsHmacSecret_IsRejected()
    {
        var tvp = BuildDualVerifyParameters();
        var der = ServerRsa.ExportSubjectPublicKeyInfo();
        var forged = MakeAlgConfusionToken(der);

        var act = () => Validate(forged, tvp);
        act.Should().Throw<SecurityTokenException>();
    }

    [Fact] // (4) alg:none ⇒ يُرفض
    public void Dual_AlgNone_IsRejected()
    {
        var tvp = BuildDualVerifyParameters();
        var forged = MakeAlgNoneToken();

        var act = () => Validate(forged, tvp);
        act.Should().Throw<SecurityTokenException>();
    }

    [Fact] // (5) RS256 بمفتاح خاص مختلف (مهاجم) ⇒ يُرفض
    public void Dual_Rs256_AttackerKey_IsRejected()
    {
        var tvp = BuildDualVerifyParameters();
        var forged = MakeRs256AttackerKey();

        var act = () => Validate(forged, tvp);
        act.Should().Throw<SecurityTokenException>();
    }

    [Fact] // (6) HS256 بسرّ خاطئ ⇒ يُرفض
    public void Dual_Hs256_WrongSecret_IsRejected()
    {
        var tvp = BuildDualVerifyParameters();
        var forged = MakeHs256WrongSecret();

        var act = () => Validate(forged, tvp);
        act.Should().Throw<SecurityTokenException>();
    }

    // ═════════════════════════════════════════════════════════════════════════
    // (7) الحياد — وضع OFF (HS256 فقط، بلا مفتاح RS256): محاكاة غياب rs256SingletonForJwks
    // ═════════════════════════════════════════════════════════════════════════

    [Fact] // (7.a) في وضع HS256-only: HS256 صحيح ⇒ يُقبل
    public void Hs256Only_ValidHs256_IsAccepted()
    {
        var tvp = BuildHs256OnlyParameters();
        var principal = Validate(MakeValidHs256(), tvp);
        principal.Should().NotBeNull();
    }

    [Fact] // (7.b) في وضع HS256-only: RS256 (لا مفتاح عام في القائمة) ⇒ يُرفض
    public void Hs256Only_ValidRs256_IsRejected()
    {
        var tvp = BuildHs256OnlyParameters();
        var rs256 = MakeValidRs256();

        var act = () => Validate(rs256, tvp);
        act.Should().Throw<SecurityTokenException>();
    }
}
