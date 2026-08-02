using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.IdentityModel.Tokens.Jwt;
using Microsoft.IdentityModel.Tokens;

// ═══════════════════════════════════════════════════════════════════════════
// إثبات فكرة: "بطاقة الدخول" في المعمارية الموزّعة (RS256).
// المركز يوقّع بالمفتاح الخاص — كل عقدة شركة تتحقق بالمفتاح العام وحده،
// دون أي اتصال بالمركز في كل طلب. لا يمسّ هذا الإثبات أي كود إنتاج.
// ═══════════════════════════════════════════════════════════════════════════

Console.OutputEncoding = Encoding.UTF8;

void Line(string s = "") => Console.WriteLine(s);
Line("══════════════════════════════════════════════════════════");
Line("  إثبات فكرة: بطاقة الدخول RS256 (توقيع مركزي / تحقق محلي)");
Line("══════════════════════════════════════════════════════════");
Line();

// ① المركز يولّد زوج مفاتيح: خاص (سرّي للتوقيع) + عام (يُوزَّع على العقد)
using var rsa = RSA.Create(2048);
var privateKey = new RsaSecurityKey(rsa.ExportParameters(true));   // يبقى في المركز فقط
var publicKey  = new RsaSecurityKey(rsa.ExportParameters(false));  // يُوزَّع على كل شركة
Line("① المركز أنشأ زوج مفاتيح RSA-2048:");
Line("   • مفتاح خاص → يبقى في المركز فقط (للتوقيع)");
Line("   • مفتاح عام → يُوزَّع على حواسيب الشركات (للتحقق)");
Line();

var handler = new JwtSecurityTokenHandler();
var now = DateTime.UtcNow;

// ② المركز يوقّع بطاقة دخول لمدير شركة، صالحة 24 ساعة
var claims = new[]
{
    new Claim(JwtRegisteredClaimNames.Sub, "user-1024"),
    new Claim(ClaimTypes.Name, "مدير شركة النور"),
    new Claim(ClaimTypes.Role, "CompanyManager"),
    new Claim("company_id", "company-7A3F"),
    new Claim("company_name", "شركة النور للإنترنت"),
    new Claim("node_id", "node-nour-office-01"),
    new Claim("permissions", "subscribers.view,subscribers.edit,accounting.view,tickets.manage"),
    new Claim("license_exp", now.AddYears(1).ToString("yyyy-MM-dd")),
};
var token = new JwtSecurityToken(
    issuer: "sadara-center",
    audience: "sadara-company-node",
    claims: claims,
    notBefore: now,
    expires: now.AddHours(24),
    signingCredentials: new SigningCredentials(privateKey, SecurityAlgorithms.RsaSha256));
var jwt = handler.WriteToken(token);
Line("② المركز وقّع بطاقة دخول (JWT) لمدير \"شركة النور\"، صالحة 24 ساعة:");
Line("   " + jwt[..60] + "...");
Line();

// ③ عقدة الشركة تتحقق بالمفتاح العام وحده (بلا اتصال بالمركز)
var validation = new TokenValidationParameters
{
    ValidateIssuerSigningKey = true,
    IssuerSigningKey = publicKey,          // ← المفتاح العام فقط
    ValidateIssuer = true,   ValidIssuer   = "sadara-center",
    ValidateAudience = true, ValidAudience = "sadara-company-node",
    ValidateLifetime = true, ClockSkew     = TimeSpan.Zero,
};
try
{
    var principal = handler.ValidateToken(jwt, validation, out var validated);
    var v = (JwtSecurityToken)validated;
    Line("③ عقدة \"شركة النور\" تحققت من البطاقة بالمفتاح العام فقط ✅");
    Line("   (تحقق ذاتي — دون أي اتصال بالمركز)");
    Line();
    Line("   البيانات المقروءة من البطاقة:");
    Line("   • المستخدم  : " + principal.FindFirst(ClaimTypes.Name)?.Value);
    Line("   • الدور     : " + principal.FindFirst(ClaimTypes.Role)?.Value);
    Line("   • الشركة    : " + principal.FindFirst("company_name")?.Value +
                              " (" + principal.FindFirst("company_id")?.Value + ")");
    Line("   • العقدة    : " + principal.FindFirst("node_id")?.Value);
    Line("   • الصلاحيات : " + principal.FindFirst("permissions")?.Value);
    Line("   • تنتهي في  : " + v.ValidTo.ToLocalTime() + "  (بعد ~24 ساعة)");
    Line();
}
catch (Exception ex)
{
    Line("③ فشل التحقق (غير متوقع): " + ex.Message);
}

// ④ اختبار أمني: مهاجم يزوّر بطاقة بمفتاح خاص مختلف → يجب أن تُرفض
Line("④ اختبار أمني — مهاجم يزوّر بطاقة بمفتاحه الخاص:");
using var attackerRsa = RSA.Create(2048);
var forged = new JwtSecurityToken(
    issuer: "sadara-center", audience: "sadara-company-node",
    claims: claims, notBefore: now, expires: now.AddHours(24),
    signingCredentials: new SigningCredentials(
        new RsaSecurityKey(attackerRsa.ExportParameters(true)), SecurityAlgorithms.RsaSha256));
try
{
    handler.ValidateToken(handler.WriteToken(forged), validation, out _);
    Line("   ❌ خطر! قُبلت بطاقة مزوّرة — يجب ألا يحدث");
}
catch
{
    Line("   ✅ رُفضت البطاقة المزوّرة — لا انتحال للمركز بدون مفتاحه الخاص");
    Line();
}

Line("══════════════════════════════════════════════════════════");
Line("  الخلاصة: المركز وحده يوقّع، وكل عقدة تتحقق ذاتياً وتكشف التزوير.");
Line("══════════════════════════════════════════════════════════");
