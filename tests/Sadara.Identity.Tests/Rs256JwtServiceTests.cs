using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using FluentAssertions;
using Microsoft.IdentityModel.Tokens;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Identity;
using Xunit;

namespace Sadara.Identity.Tests;

/// <summary>
/// اختبارات وحدة/تشفير لـ Rs256JwtService (ADR-002) — معزولة تماماً عن قاعدة البيانات.
/// المتطلب 1 (توقيع/تحقّق + kid + claims) والمتطلب 2 (تحصين alg confusion).
/// </summary>
public class Rs256JwtServiceTests
{
    // مُنشئ عام يولّد مفتاح RSA-2048 مؤقتاً في الذاكرة لكل اختبار.
    private static Rs256JwtService NewService(string? keyId = null, int expiryMinutes = 60, string? pemOverride = null)
    {
        var pem = pemOverride ?? TestSupport.GenerateEphemeralRsaPrivateKeyPem(2048);
        return new Rs256JwtService(pem, TestSupport.Issuer, TestSupport.Audience, expiryMinutes, keyId);
    }

    // ============ المتطلب 1: توليد/توقيع/تحقّق + kid + claims ============

    [Fact]
    public void GenerateAccessToken_ThenValidate_WithSameService_Succeeds()
    {
        var svc = NewService();
        var user = TestSupport.BuildUser(companyId: Guid.NewGuid());

        var token = svc.GenerateAccessToken(user);

        token.Should().NotBeNullOrWhiteSpace();
        svc.ValidateToken(token).Should().BeTrue(
            "التوكن الموقّع بـ RS256 يجب أن يُقبَل عند التحقّق بنفس المفتاح");
    }

    [Fact]
    public void GenerateAccessToken_VerifiesWithPublicKeyOnly_UsingRs256()
    {
        // نتحقّق يدوياً بالمفتاح العام فقط (لا جزء خاص) لإثبات صحّة التوقيع غير المتماثل.
        var svc = NewService();
        var user = TestSupport.BuildUser(companyId: Guid.NewGuid());
        var token = svc.GenerateAccessToken(user);

        var publicParams = svc.ExportPublicKeyParameters();
        publicParams.D.Should().BeNull("المُعامِلات المُصدَّرة يجب أن تكون عامة فقط بلا أي جزء خاص");

        using var publicRsa = RSA.Create();
        publicRsa.ImportParameters(publicParams);
        var publicKey = new RsaSecurityKey(publicRsa);

        var handler = new JwtSecurityTokenHandler();
        var validationParams = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = publicKey,
            ValidAlgorithms = new[] { SecurityAlgorithms.RsaSha256 },
            ValidateIssuer = true,
            ValidIssuer = TestSupport.Issuer,
            ValidateAudience = true,
            ValidAudience = TestSupport.Audience,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.Zero
        };

        var act = () => handler.ValidateToken(token, validationParams, out _);
        act.Should().NotThrow("التوقيع صالح مقابل المفتاح العام باستخدام RS256");
    }

    [Fact]
    public void GenerateAccessToken_Header_ContainsKidAndRs256Algorithm()
    {
        var svc = NewService();
        var token = svc.GenerateAccessToken(TestSupport.BuildUser());

        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);

        jwt.Header.Alg.Should().Be(SecurityAlgorithms.RsaSha256, "خوارزمية الرأس يجب أن تكون RS256");
        jwt.Header.Kid.Should().NotBeNullOrWhiteSpace("kid يجب أن يوجد في رأس التوكن");
        jwt.Header.Kid.Should().Be(svc.KeyId, "kid في الرأس يجب أن يطابق KeyId المُعلن للخدمة (لمطابقة JWKS)");
    }

    [Fact]
    public void GenerateAccessToken_CarriesExpectedClaims_IncludingCompanyId()
    {
        var svc = NewService();
        var userId = Guid.NewGuid();
        var companyId = Guid.NewGuid();
        var merchantId = Guid.NewGuid();
        var user = TestSupport.BuildUser(
            id: userId,
            companyId: companyId,
            fullName: "أحمد الفني",
            phone: "07711112222",
            role: UserRole.Technician,
            merchantId: merchantId);

        var token = svc.GenerateAccessToken(user);
        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);

        string? Claim(string type) => jwt.Claims.FirstOrDefault(c => c.Type == type)?.Value;

        // نفس مجموعة claims الحالية في JwtService (HS256) — ADR-002 §4.
        Claim(JwtRegisteredClaimNames.Sub).Should().Be(userId.ToString());
        Claim(ClaimTypes.NameIdentifier).Should().Be(userId.ToString());
        Claim(ClaimTypes.Name).Should().Be("أحمد الفني");
        Claim(ClaimTypes.MobilePhone).Should().Be("07711112222");
        Claim(ClaimTypes.Role).Should().Be(UserRole.Technician.ToString());
        Claim("MerchantId").Should().Be(merchantId.ToString());
        Claim("company_id").Should().Be(companyId.ToString(), "عزل المستأجر يعتمد على company_id في التوكن");
        Claim(JwtRegisteredClaimNames.Jti).Should().NotBeNullOrWhiteSpace("jti يجب أن يكون فريداً لكل توكن");
    }

    [Fact]
    public void GenerateAccessToken_CompanyIdClaim_IsEmpty_WhenUserHasNoCompany()
    {
        // مثل SuperAdmin بلا شركة: company_id يجب أن يكون فارغاً (لا يُحذف الـ claim).
        var svc = NewService();
        var user = TestSupport.BuildUser(companyId: null, role: UserRole.SuperAdmin);

        var token = svc.GenerateAccessToken(user);
        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);

        var companyClaim = jwt.Claims.FirstOrDefault(c => c.Type == "company_id");
        companyClaim.Should().NotBeNull("الـ claim موجود دائماً");
        companyClaim!.Value.Should().BeEmpty("من لا شركة له يحمل company_id فارغاً");
    }

    [Fact]
    public void Kid_IsStable_ForSameKey_AndDiffers_AcrossKeys()
    {
        var pem = TestSupport.GenerateEphemeralRsaPrivateKeyPem(2048);
        var a = NewService(pemOverride: pem);
        var b = NewService(pemOverride: pem);
        var different = NewService(); // مفتاح آخر

        a.KeyId.Should().Be(b.KeyId, "kid مشتقّ من المفتاح العام ⇒ ثابت لنفس المفتاح");
        a.KeyId.Should().NotBe(different.KeyId, "مفتاح مختلف ⇒ kid مختلف");
    }

    [Fact]
    public void GenerateRefreshToken_IsRandom_AndBase64()
    {
        var svc = NewService();
        var t1 = svc.GenerateRefreshToken();
        var t2 = svc.GenerateRefreshToken();

        t1.Should().NotBe(t2);
        var act = () => Convert.FromBase64String(t1);
        act.Should().NotThrow();
    }

    // ============ المتطلب 2: تحصين ضد alg confusion ============

    [Fact]
    public void ValidateToken_RejectsToken_SignedWithHs256_UsingModulusAsHmacKey()
    {
        // هجوم alg confusion الكلاسيكي: توقيع HS256 بالمفتاح العام RSA كسرّ HMAC.
        // يجب أن يرفضه المتحقّق لأنه يقبل RS256 فقط (ValidAlgorithms).
        var svc = NewService();
        var publicParams = svc.ExportPublicKeyParameters();
        var hmacKeyBytes = publicParams.Modulus!; // "السرّ" المُخمَّن في هجوم الخلط

        var handler = new JwtSecurityTokenHandler();
        var hs256Creds = new SigningCredentials(
            new SymmetricSecurityKey(hmacKeyBytes),
            SecurityAlgorithms.HmacSha256);

        var forged = handler.WriteToken(new JwtSecurityToken(
            issuer: TestSupport.Issuer,
            audience: TestSupport.Audience,
            claims: new[] { new Claim(ClaimTypes.Name, "attacker") },
            expires: DateTime.UtcNow.AddMinutes(10),
            signingCredentials: hs256Creds));

        svc.ValidateToken(forged).Should().BeFalse(
            "التحقّق مقيّد بـ ValidAlgorithms=[RS256] فيجب رفض أي توكن HS256");
    }

    [Fact]
    public void ValidateToken_RejectsToken_SignedWithDifferentRs256Key()
    {
        // توكن موقّع بمفتاح RSA آخر يجب أن يُرفض (فشل تحقّق التوقيع).
        var signer = NewService();
        var verifier = NewService(); // مفتاح مختلف تماماً

        var token = signer.GenerateAccessToken(TestSupport.BuildUser(companyId: Guid.NewGuid()));

        verifier.ValidateToken(token).Should().BeFalse(
            "المفتاح العام المختلف لا يجب أن يتحقّق من توقيع مفتاح آخر");
    }

    [Fact]
    public void ValidateToken_RejectsAlgNone_UnsignedToken()
    {
        // توكن alg=none (بلا توقيع) — يجب أن يُرفض دائماً.
        var svc = NewService();
        // رأس alg=none + payload، بلا توقيع.
        static string B64(string s) => Base64UrlEncoder.Encode(Encoding.UTF8.GetBytes(s));
        var header = B64("{\"alg\":\"none\",\"typ\":\"JWT\"}");
        var payload = B64($"{{\"iss\":\"{TestSupport.Issuer}\",\"aud\":\"{TestSupport.Audience}\"}}");
        var noneToken = $"{header}.{payload}.";

        svc.ValidateToken(noneToken).Should().BeFalse("alg=none غير مقبول إطلاقاً");
    }

    [Fact]
    public void ValidateToken_RejectsExpiredToken()
    {
        var svc = NewService(expiryMinutes: -5); // منتهٍ سلفاً
        var token = svc.GenerateAccessToken(TestSupport.BuildUser());

        svc.ValidateToken(token).Should().BeFalse("التوكن المنتهي يجب أن يُرفض (ClockSkew=0)");
    }

    [Fact]
    public void Constructor_Throws_WhenPrivateKeyMissing_FailClosed()
    {
        var act = () => new Rs256JwtService("", TestSupport.Issuer, TestSupport.Audience);
        act.Should().Throw<InvalidOperationException>("غياب المفتاح الخاص يجب أن يفشل مغلقاً (fail-closed)");
    }
}
