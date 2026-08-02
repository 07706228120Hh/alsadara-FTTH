using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using FluentAssertions;
using Microsoft.IdentityModel.Tokens;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Identity;
using Xunit;

namespace Sadara.Identity.Tests;

/// <summary>
/// المتطلب 4: تكافؤ OFF — الوضع الافتراضي (HS256) لا يزال ينتج ويتحقّق من توكن HS256.
/// يُختبر JwtService الحالي مباشرة بسرّ تجريبي محلي، دون أي اتصال بقاعدة بيانات.
/// السرّ أدناه قيمة اختبار محلية غير مرتبطة بأي سرّ إنتاجي.
/// </summary>
public class Hs256OffEquivalenceTests
{
    // سرّ اختبار محلي (لا علاقة له بأي سرّ إنتاجي؛ طوله كافٍ لـ HMAC-SHA256).
    private const string TestSecret = "unit-test-only-hs256-secret-key-do-not-use-in-prod-0123456789";

    // بعد التوحيد (ADR-003 خطوة 0): JwtService يستهلك IJwtTokenSigner.
    // عند flag OFF (لا Jwt:Algorithm) المُوقّع يعمل HS256 بنفس السرّ — سلوك مطابق للسابق.
    private static JwtService NewHs256(int expiryMinutes = 60)
    {
        var config = TestSupport.BuildConfig(TestSecret, expiryMinutes); // Jwt:Algorithm غير مضبوط ⇒ HS256
        var signer = new JwtTokenSigner(config);
        return new JwtService(signer, TestSecret, TestSupport.Issuer, TestSupport.Audience, expiryMinutes);
    }

    [Fact]
    public void Hs256_GeneratedToken_UsesHmacSha256_Header()
    {
        var svc = NewHs256();
        var token = svc.GenerateAccessToken(TestSupport.BuildUser(companyId: Guid.NewGuid()));

        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);

        jwt.Header.Alg.Should().Be(SecurityAlgorithms.HmacSha256, "الوضع الافتراضي يجب أن يبقى HS256");
        jwt.Header.Kid.Should().BeNull("HS256 لا يحمل kid (لا JWKS لسرّ متماثل)");
    }

    [Fact]
    public void Hs256_GenerateThenValidate_Succeeds()
    {
        var svc = NewHs256();
        var token = svc.GenerateAccessToken(TestSupport.BuildUser(companyId: Guid.NewGuid()));

        svc.ValidateToken(token).Should().BeTrue("HS256 يجب أن يتحقّق من توكنه بنفس السرّ");
    }

    [Fact]
    public void Hs256_CarriesSameClaimSet_IncludingCompanyId()
    {
        var svc = NewHs256();
        var userId = Guid.NewGuid();
        var companyId = Guid.NewGuid();
        var user = TestSupport.BuildUser(id: userId, companyId: companyId, role: UserRole.Manager);

        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(svc.GenerateAccessToken(user));
        string? Claim(string type) => jwt.Claims.FirstOrDefault(c => c.Type == type)?.Value;

        Claim(JwtRegisteredClaimNames.Sub).Should().Be(userId.ToString());
        Claim(ClaimTypes.Role).Should().Be(UserRole.Manager.ToString());
        Claim("company_id").Should().Be(companyId.ToString());
    }

    [Fact]
    public void Hs256_Token_IsNotVerifiableAsRs256()
    {
        // تكافؤ عزل الخوارزميات: توكن HS256 لا يُقبَل عبر متحقّق RS256 (والعكس مُختبَر في Rs256JwtServiceTests).
        var hs256 = NewHs256();
        var token = hs256.GenerateAccessToken(TestSupport.BuildUser());

        var rs256 = new Rs256JwtService(
            TestSupport.GenerateEphemeralRsaPrivateKeyPem(2048),
            TestSupport.Issuer,
            TestSupport.Audience);

        rs256.ValidateToken(token).Should().BeFalse("متحقّق RS256 يجب أن يرفض توكن HS256");
    }

    [Fact]
    public void Hs256_ValidateToken_RejectsTamperedSignature()
    {
        var svc = NewHs256();
        var token = svc.GenerateAccessToken(TestSupport.BuildUser());

        // عبث بالجزء الأخير (التوقيع).
        var parts = token.Split('.');
        parts[2] = Base64UrlEncoder.Encode(Encoding.UTF8.GetBytes("tampered"));
        var tampered = string.Join('.', parts);

        svc.ValidateToken(tampered).Should().BeFalse("التوقيع المعبوث يجب أن يُرفض");
    }
}
