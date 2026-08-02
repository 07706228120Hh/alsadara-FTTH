using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using Sadara.Domain.Interfaces;

namespace Sadara.Infrastructure.Identity;

/// <summary>
/// مكوّن توقيع JWT المشترك (ADR-003 خطوة 0 — «إثبات»).
///
/// يفصل آلية التوقيع عن بناء الحمولة:
/// - HS256 (الافتراضي/OFF): يوقّع بـ <c>SymmetricSecurityKey(Encoding.UTF8.GetBytes(Jwt:Secret))</c> + HmacSha256،
///   ويبني التوكن بنفس نمط بناء <c>JwtSecurityToken</c> الذي كان يستخدمه الموضع A حرفياً
///   (نفس معاملات المُنشئ: issuer/audience/claims/expires/signingCredentials؛ بلا notBefore؛ بلا kid).
///   النتيجة: توكن مطابق بنيوياً للحالي (نفس alg=HS256 بلا kid، نفس claims وترتيبها، نفس المدة).
/// - RS256 (خلف flag <c>Jwt:Algorithm=RS256</c>): يعيد استخدام منطق <see cref="Rs256JwtService"/>
///   (RsaSecurityKey من المفتاح المُهيّأ + kid في الرأس)، بلا تغيير في محتوى الحمولة.
///
/// المفتاح الخاص RS256 يُقرأ من مسار ملف PEM خارجي فقط (<c>Jwt:Rs256PrivateKeyPath</c>) — لا يُخزَّن في الكود/appsettings.
/// عند القيمة الافتراضية (HS256) لا يُقرأ أي مفتاح RS256 إطلاقاً.
/// </summary>
public class JwtTokenSigner : IJwtTokenSigner
{
    private readonly bool _useRs256;

    // HS256
    private readonly string? _secret;

    // RS256
    private readonly RSA? _rsa;
    private readonly RsaSecurityKey? _rsaSecurityKey;
    private readonly string? _keyId;

    public JwtTokenSigner(IConfiguration configuration)
    {
        var algorithm = (configuration["Jwt:Algorithm"] ?? "HS256").Trim().ToUpperInvariant();
        _useRs256 = algorithm == "RS256";

        if (_useRs256)
        {
            // fail-closed: RS256 يتطلب مسار مفتاح خاص صالح وموجود.
            var privateKeyPath = configuration["Jwt:Rs256PrivateKeyPath"];
            if (string.IsNullOrWhiteSpace(privateKeyPath) || !File.Exists(privateKeyPath))
                throw new InvalidOperationException(
                    "Jwt:Algorithm=RS256 لكن Jwt:Rs256PrivateKeyPath غير مضبوط أو الملف غير موجود — fail-closed.");

            var privateKeyPem = File.ReadAllText(privateKeyPath);
            if (string.IsNullOrWhiteSpace(privateKeyPem))
                throw new InvalidOperationException("RS256 private key غير مضبوط — fail-closed.");

            _rsa = RSA.Create();
            _rsa.ImportFromPem(privateKeyPem);
            _rsaSecurityKey = new RsaSecurityKey(_rsa);

            // kid: يُمرَّر صراحةً عبر الإعداد أو يُشتقّ من المفتاح العام (نفس منطق Rs256JwtService).
            var configuredKeyId = configuration["Jwt:Rs256KeyId"];
            _keyId = string.IsNullOrWhiteSpace(configuredKeyId) ? ComputeKeyId(_rsa) : configuredKeyId;
            _rsaSecurityKey.KeyId = _keyId;
        }
        else
        {
            // HS256 (الافتراضي) — نفس السرّ الذي يستخدمه الموضع A اليوم.
            _secret = configuration["Jwt:Secret"]
                ?? throw new InvalidOperationException("Jwt:Secret غير مضبوط — fail-closed.");
        }
    }

    public string Sign(IEnumerable<Claim> claims, DateTime expiresUtc, string issuer, string audience)
    {
        SigningCredentials credentials;
        if (_useRs256)
        {
            credentials = new SigningCredentials(_rsaSecurityKey!, SecurityAlgorithms.RsaSha256);
        }
        else
        {
            // مطابق حرفياً للموضع A: SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret)) + HmacSha256.
            var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_secret!));
            credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        }

        // نفس نمط بناء JwtSecurityToken في الموضع A حرفياً:
        // نفس معاملات المُنشئ بالضبط (issuer/audience/claims/expires/signingCredentials)،
        // ولا نمرّر notBefore (يبقى سلوك المُنشئ الافتراضي كما هو اليوم).
        var token = new JwtSecurityToken(
            issuer: issuer,
            audience: audience,
            claims: claims,
            expires: expiresUtc,
            signingCredentials: credentials
        );

        // RS256 فقط: kid في رأس التوكن (header). HS256 لا يُضاف له kid (مطابقة حرفية للحالي).
        if (_useRs256)
            token.Header["kid"] = _keyId;

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static string ComputeKeyId(RSA rsa)
    {
        var publicParams = rsa.ExportParameters(includePrivateParameters: false);
        var modulus = publicParams.Modulus ?? Array.Empty<byte>();
        var hash = SHA256.HashData(modulus);
        return Base64UrlEncoder.Encode(hash);
    }
}
