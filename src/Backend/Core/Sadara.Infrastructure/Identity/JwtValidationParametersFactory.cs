using Microsoft.IdentityModel.Tokens;
using System.Text;

namespace Sadara.Infrastructure.Identity;

/// <summary>
/// مصنع ثابت قابل للاختبار لبناء <see cref="TokenValidationParameters"/> الخاصة بالتحقّق من JWT.
///
/// ═══ لماذا هذا المصنع (تحصين أمني — توصية testing-qa) ═══
/// كانت هذه البارامترات تُبنى inline داخل lambda الـ <c>.AddJwtBearer(...)</c> في
/// <c>src/Backend/API/Sadara.API/Program.cs</c>، فلم يكن بالإمكان استدعاؤها من الاختبار الأمني.
/// نتيجةً لذلك كان اختبار alg confusion يعيد بناء البارامترات نصّاً بنصّ — وأي انحراف مستقبلي
/// بين Program.cs والاختبار لن يُلتقَط. باستخراج البناء إلى مصنع واحد يستدعيه Program.cs والاختبار
/// معاً، صار اختبار alg confusion يغطّي المسار الإنتاجي الفعلي بدل إعادة بنائه.
///
/// ═══ مطابقة السلوك (100%) ═══
/// يبني هذا المصنع نفس <see cref="TokenValidationParameters"/> الموجودة سابقاً في Program.cs حرفياً:
///   • <c>IssuerSigningKeys</c> = مفتاح HS256 المتماثل <c>SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret))</c>
///     دائماً (fail-closed: <c>Jwt:Secret</c> مطلوب قبل الاستدعاء) + المفتاح العام RS256 إن مُرِّر (≠ null).
///   • <c>ValidateIssuerSigningKey</c> = true — لا نقبل توكناً بلا مفتاح توقيع معروف.
///   • <c>ValidAlgorithms</c> = { HmacSha256, RsaSha256 } — تحصين إلزامي ضد alg confusion (RS256↔HS256)
///     و alg:none. لا نعتمد الافتراضي أبداً.
///   • <c>ValidateIssuer/ValidateAudience/ValidateLifetime</c> = true؛ نفس issuer/audience الممرَّرين.
///   • <c>ClockSkew</c> = <see cref="TimeSpan.Zero"/>.
///
/// اتجاه Clean Architecture: المصنع في Infrastructure (يعتمد على Microsoft.IdentityModel) — مقبول.
/// </summary>
public static class JwtValidationParametersFactory
{
    /// <summary>
    /// يبني بارامترات التحقّق من JWT بنفس منطق Program.cs حرفياً.
    /// </summary>
    /// <param name="secret">سرّ HS256 المتماثل. يُشفَّر بـ UTF8 ليطابق مسار التوقيع (JwtTokenSigner يستخدم UTF8).</param>
    /// <param name="issuer">قيمة <c>ValidIssuer</c>.</param>
    /// <param name="audience">قيمة <c>ValidAudience</c>.</param>
    /// <param name="rs256PublicKey">المفتاح العام RS256 (مع KeyId). <c>null</c> ⇒ HS256 فقط (وضع OFF).</param>
    public static TokenValidationParameters Build(
        string secret,
        string issuer,
        string audience,
        RsaSecurityKey? rs256PublicKey)
    {
        // قائمة مفاتيح التوقيع:
        //   • مفتاح HS256 المتماثل (Encoding.UTF8) — مضاف دائماً (fail-closed: Jwt:Secret مطلوب قبل الاستدعاء).
        //   • مفتاح RS256 العام — يُضاف فقط إن مُرِّر (≠ null، أي Jwt:Algorithm=RS256 مع مفتاح صالح).
        // عند OFF أو غياب مفتاح RS256 ⇒ القائمة = مفتاح HS256 فقط ⇒ السلوك مطابق للحالي.
        var signingKeys = new List<SecurityKey>
        {
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret)) // HS256 — دائماً
        };
        if (rs256PublicKey is not null)
        {
            signingKeys.Add(rs256PublicKey);
        }

        return new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKeys = signingKeys,
            // تحصين إلزامي ضد alg confusion (RS256↔HS256) و alg:none: نحصر الخوارزميات المقبولة صراحةً.
            // لا نعتمد الافتراضي أبداً. المكتبة تختار المفتاح المطابق لنوع الخوارزمية المُعلَنة، فلا يُقبل
            // توكن يدّعي HS256 موقّعاً بمادة المفتاح العام RSA ولا العكس.
            ValidAlgorithms = new[] { SecurityAlgorithms.HmacSha256, SecurityAlgorithms.RsaSha256 },
            ValidateIssuer = true,
            ValidIssuer = issuer,
            ValidateAudience = true,
            ValidAudience = audience,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.Zero
        };
    }
}
