using System.Security.Cryptography;
using FluentAssertions;
using Microsoft.IdentityModel.Tokens;
using Sadara.Infrastructure.Identity;
using Xunit;

namespace Sadara.Identity.Tests;

/// <summary>
/// اختبارات JwksService (ADR-002 §3.3) — معزولة عن قاعدة البيانات.
/// المتطلب 3: مجموعة فارغة عند OFF، وJWK عام صحيح عند وجود مفتاح، دون كشف أي جزء خاص.
/// </summary>
public class JwksServiceTests
{
    private static Rs256JwtService NewRs256()
        => new Rs256JwtService(
            TestSupport.GenerateEphemeralRsaPrivateKeyPem(2048),
            TestSupport.Issuer,
            TestSupport.Audience);

    [Fact]
    public void GetJwks_ReturnsEmptyKeySet_WhenNoRs256Service_Off()
    {
        // وضع HS256/OFF: يُمرَّر null ⇒ { "keys": [] } (لا يُنشَر مفتاح عام لسرّ متماثل).
        var jwks = new JwksService(null);

        var result = jwks.GetJwks();

        result.Should().NotBeNull();
        result.Keys.Should().NotBeNull();
        result.Keys.Should().BeEmpty("عند OFF لا يُنشَر أي مفتاح");
    }

    [Fact]
    public void GetJwks_ReturnsValidJwk_WhenRs256KeyPresent()
    {
        var rs256 = NewRs256();
        var jwks = new JwksService(rs256);

        var result = jwks.GetJwks();

        result.Keys.Should().HaveCount(1);
        var jwk = result.Keys[0];

        jwk.KeyType.Should().Be("RSA");
        jwk.Use.Should().Be("sig");
        jwk.Algorithm.Should().Be(SecurityAlgorithms.RsaSha256);
        jwk.KeyId.Should().NotBeNullOrWhiteSpace();
        jwk.KeyId.Should().Be(rs256.KeyId, "kid في JWK يجب أن يطابق kid الذي توقّع به التوكنات");
        jwk.Modulus.Should().NotBeNullOrWhiteSpace("n (modulus) مطلوب");
        jwk.Exponent.Should().NotBeNullOrWhiteSpace("e (exponent) مطلوب");
    }

    [Fact]
    public void GetJwks_PublishesPublicModulusAndExponentMatchingTheKey()
    {
        var rs256 = NewRs256();
        var jwks = new JwksService(rs256);

        var jwk = jwks.GetJwks().Keys.Single();

        var expected = rs256.ExportPublicKeyParameters();
        Base64UrlEncoder.DecodeBytes(jwk.Modulus).Should().Equal(expected.Modulus!);
        Base64UrlEncoder.DecodeBytes(jwk.Exponent).Should().Equal(expected.Exponent!);
    }

    [Fact]
    public void GetJwks_PublicKey_CanValidateAnIssuedToken()
    {
        // إثبات فائدة النقطة: بناء مفتاح عام من JWK فقط ⇒ يتحقّق من توكن صادر عن الخدمة.
        var rs256 = NewRs256();
        var token = rs256.GenerateAccessToken(TestSupport.BuildUser(companyId: Guid.NewGuid()));

        var jwk = new JwksService(rs256).GetJwks().Keys.Single();

        var rsaParams = new RSAParameters
        {
            Modulus = Base64UrlEncoder.DecodeBytes(jwk.Modulus),
            Exponent = Base64UrlEncoder.DecodeBytes(jwk.Exponent)
        };
        using var rsa = RSA.Create();
        rsa.ImportParameters(rsaParams);

        var handler = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler();
        var act = () => handler.ValidateToken(token, new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new RsaSecurityKey(rsa) { KeyId = jwk.KeyId },
            ValidAlgorithms = new[] { SecurityAlgorithms.RsaSha256 },
            ValidateIssuer = true,
            ValidIssuer = TestSupport.Issuer,
            ValidateAudience = true,
            ValidAudience = TestSupport.Audience,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.Zero
        }, out _);

        act.Should().NotThrow("المفتاح العام من JWKS يجب أن يتحقّق من التوكن الصادر");
    }

    [Fact]
    public void GetJwks_DoesNotLeakAnyPrivateKeyMaterial()
    {
        // تحصين: يجب ألا يظهر أي حقل خاص (d, p, q, dp, dq, qi) في مخرجات JWK.
        var rs256 = NewRs256();
        var jwk = new JwksService(rs256).GetJwks().Keys.Single();

        var json = System.Text.Json.JsonSerializer.Serialize(jwk);

        // الحقول المسموحة فقط: kty, use, alg, kid, n, e — أي حقل خاص RSA ممنوع.
        json.Should().NotContain("\"d\"");
        json.Should().NotContain("\"p\"");
        json.Should().NotContain("\"q\"");
        json.Should().NotContain("\"dp\"");
        json.Should().NotContain("\"dq\"");
        json.Should().NotContain("\"qi\"");

        // تأكيد قاطع: المُعامِلات الخاصة غير مُصدَّرة أصلاً من الخدمة.
        rs256.ExportPublicKeyParameters().D.Should().BeNull();
    }
}
