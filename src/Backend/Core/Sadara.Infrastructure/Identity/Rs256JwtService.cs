using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.IdentityModel.Tokens;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.Infrastructure.Identity;

/// <summary>
/// تنفيذ RS256 (توقيع غير متماثل) لعقد <see cref="IJwtService"/> — أول زيادة آمنة (ADR-002).
///
/// ملاحظات معمارية/أمنية (ADR-002 + شروط security-auditor):
/// - ينفّذ نفس عقد <see cref="IJwtService"/> الثلاثي حرفياً، ونفس مجموعة الـ claims الحالية في <c>JwtService</c> (HS256)
///   دون إضافة أي claim وظيفي جديد — التغيير محصور في آلية التوقيع فقط. يُضاف <c>kid</c> في رأس التوكن (header) لا في الحمولة.
/// - المفتاح الخاص RS256 يُحمَّل من مسار ملف PEM خارجي فقط (متغيّر بيئة/إعداد) — لا يُكتب في أي appsettings*.json.
/// - يُستخدم فقط عندما <c>Jwt:Algorithm == "RS256"</c>. عند القيمة الافتراضية (HS256/OFF) لا يُسجَّل هذا التنفيذ إطلاقاً،
///   ويبقى <c>JwtService</c> (HS256) هو المنتِج والمتحقّق الوحيد فعلياً.
/// </summary>
public class Rs256JwtService : IJwtService
{
    private readonly RSA _rsa;
    private readonly string _issuer;
    private readonly string _audience;
    private readonly int _expiryMinutes;
    private readonly string _keyId;
    private readonly RsaSecurityKey _securityKey;

    /// <param name="privateKeyPem">محتوى مفتاح RSA الخاص بصيغة PEM (يُقرأ من ملف خارجي — لا يُخزَّن في المستودع).</param>
    /// <param name="keyId">مُعرّف المفتاح (kid) لدعم التدوير عبر JWKS لاحقاً.</param>
    public Rs256JwtService(
        string privateKeyPem,
        string issuer,
        string audience,
        int expiryMinutes = 60,
        string? keyId = null)
    {
        if (string.IsNullOrWhiteSpace(privateKeyPem))
            throw new InvalidOperationException("RS256 private key غير مضبوط — fail-closed.");

        _rsa = RSA.Create();
        _rsa.ImportFromPem(privateKeyPem);

        _issuer = issuer;
        _audience = audience;
        _expiryMinutes = expiryMinutes;
        _securityKey = new RsaSecurityKey(_rsa);

        // kid ثابت مشتقّ من المفتاح العام (thumbprint) ما لم يُمرَّر صراحةً — يتيح مطابقة JWKS.
        _keyId = string.IsNullOrWhiteSpace(keyId) ? ComputeKeyId(_rsa) : keyId!;
        _securityKey.KeyId = _keyId;
    }

    public string GenerateAccessToken(User user)
    {
        var credentials = new SigningCredentials(_securityKey, SecurityAlgorithms.RsaSha256);

        // نفس مجموعة الـ claims الحالية في JwtService (HS256) — لا تغيير في محتوى الحمولة (ADR-002 §4).
        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new Claim(ClaimTypes.Name, user.FullName),
            new Claim(ClaimTypes.MobilePhone, user.PhoneNumber),
            new Claim(ClaimTypes.Role, user.Role.ToString()),
            new Claim("MerchantId", user.Merchant?.Id.ToString() ?? ""),
            // عزل المستأجر: هوية شركة المستخدم في التوكن (أساس الفلتر المركزي). فارغ لمن لا شركة له (مثل SuperAdmin).
            new Claim("company_id", user.CompanyId?.ToString() ?? "")
        };

        var token = new JwtSecurityToken(
            issuer: _issuer,
            audience: _audience,
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(_expiryMinutes),
            signingCredentials: credentials
        );

        // kid في رأس التوكن (header) — يُمكّن العقد من مطابقة المفتاح العام عبر JWKS لاحقاً.
        token.Header["kid"] = _keyId;

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public string GenerateRefreshToken()
    {
        var randomNumber = new byte[64];
        using var rng = RandomNumberGenerator.Create();
        rng.GetBytes(randomNumber);
        return Convert.ToBase64String(randomNumber);
    }

    public bool ValidateToken(string token)
    {
        try
        {
            var tokenHandler = new JwtSecurityTokenHandler();

            tokenHandler.ValidateToken(token, new TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = _securityKey,
                // تحصين ضد alg confusion: نقبل RS256 فقط في هذا المسار.
                ValidAlgorithms = new[] { SecurityAlgorithms.RsaSha256 },
                ValidateIssuer = true,
                ValidIssuer = _issuer,
                ValidateAudience = true,
                ValidAudience = _audience,
                ValidateLifetime = true,
                ClockSkew = TimeSpan.Zero
            }, out _);

            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// مُعرّف المفتاح (kid) للمفتاح الحالي — يستهلكه <see cref="JwksService"/> لبناء JWK Set.
    /// </summary>
    public string KeyId => _keyId;

    /// <summary>
    /// المفتاح العام (public parameters فقط) لبناء نقطة JWKS. لا يكشف أي جزء خاص.
    /// </summary>
    public RSAParameters ExportPublicKeyParameters() => _rsa.ExportParameters(includePrivateParameters: false);

    private static string ComputeKeyId(RSA rsa)
    {
        // kid = Base64Url لـ SHA-256 على المُعامِل (modulus) العام — ثابت لنفس المفتاح، لا يكشف الجزء الخاص.
        var publicParams = rsa.ExportParameters(includePrivateParameters: false);
        var modulus = publicParams.Modulus ?? Array.Empty<byte>();
        var hash = SHA256.HashData(modulus);
        return Base64UrlEncoder.Encode(hash);
    }
}
