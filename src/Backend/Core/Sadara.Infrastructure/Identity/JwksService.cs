using Microsoft.IdentityModel.Tokens;
using System.Text.Json.Serialization;

namespace Sadara.Infrastructure.Identity;

/// <summary>
/// خدمة نشر مجموعة مفاتيح JSON العامة (JWKS) لنقطة <c>/.well-known/jwks.json</c> — ADR-002.
///
/// شروط أمنية إلزامية (security-auditor):
/// - عند وضع HS256 (الافتراضي/OFF) أو غياب مفتاح RS256 مهيّأ → تُعيد <c>{ "keys": [] }</c>.
///   HS256 سرّ متماثل ولا يُنشَر مفتاح عام له إطلاقاً.
/// - ممنوع توليد مفتاح تلقائياً هنا (خلافاً لسلوك الـ PoC). لا يُنشَر إلا المفتاح العام لمفتاح RS256 مُهيّأ مسبقاً وحُقن صراحةً.
/// - تُصدِّر المُعامِلات العامة فقط (modulus/exponent) — لا أي جزء خاص.
/// </summary>
public class JwksService
{
    // مصدر المفتاح العام. null = لا مفتاح RS256 مهيّأ ⇒ مجموعة فارغة (OFF).
    private readonly Rs256JwtService? _rs256Service;

    /// <summary>
    /// يُحقن <paramref name="rs256Service"/> فقط في وضع RS256. في وضع HS256 يُمرَّر null (مجموعة فارغة).
    /// </summary>
    public JwksService(Rs256JwtService? rs256Service = null)
    {
        _rs256Service = rs256Service;
    }

    /// <summary>
    /// يبني JWK Set للنشر. مجموعة فارغة عند غياب مفتاح RS256 مهيّأ. لا توليد تلقائي.
    /// </summary>
    public JwksResponse GetJwks()
    {
        if (_rs256Service is null)
            return new JwksResponse { Keys = new List<JwkModel>() };

        var p = _rs256Service.ExportPublicKeyParameters();
        if (p.Modulus is null || p.Exponent is null)
            return new JwksResponse { Keys = new List<JwkModel>() };

        var jwk = new JwkModel
        {
            KeyType = "RSA",
            Use = "sig",
            Algorithm = SecurityAlgorithms.RsaSha256,
            KeyId = _rs256Service.KeyId,
            Modulus = Base64UrlEncoder.Encode(p.Modulus),
            Exponent = Base64UrlEncoder.Encode(p.Exponent)
        };

        return new JwksResponse { Keys = new List<JwkModel> { jwk } };
    }
}

/// <summary>غلاف مجموعة المفاتيح بصيغة JWKS القياسية (RFC 7517).</summary>
public class JwksResponse
{
    [JsonPropertyName("keys")]
    public List<JwkModel> Keys { get; set; } = new();
}

/// <summary>مفتاح عام RSA بصيغة JWK (المُعامِلات العامة فقط).</summary>
public class JwkModel
{
    [JsonPropertyName("kty")]
    public string KeyType { get; set; } = "RSA";

    [JsonPropertyName("use")]
    public string Use { get; set; } = "sig";

    [JsonPropertyName("alg")]
    public string Algorithm { get; set; } = SecurityAlgorithms.RsaSha256;

    [JsonPropertyName("kid")]
    public string KeyId { get; set; } = string.Empty;

    [JsonPropertyName("n")]
    public string Modulus { get; set; } = string.Empty;

    [JsonPropertyName("e")]
    public string Exponent { get; set; } = string.Empty;
}
