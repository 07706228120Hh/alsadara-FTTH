using System.Security.Claims;
using System.Security.Cryptography;
using System.IdentityModel.Tokens.Jwt;
using Microsoft.AspNetCore.Mvc;
using Microsoft.IdentityModel.Tokens;

// ═══════════════════════════════════════════════════════════════════════════
// بوابة الهوية المركزية (نموذج أوّلي). سلطة الهوية والترخيص فقط:
//   • تصادق مدير الشركة (اسم/كلمة مرور) وتتحقق أن الشركة مفعّلة وترخيصها ساري.
//   • تُصدر "بطاقة دخول" JWT موقّعة بـ RS256 صالحة 24 ساعة.
//   • تنشر المفتاح العام عبر /.well-known/jwks.json ليتحقق منه كل عقدة شركة ذاتياً.
//   • أوامر مدير النظام: تسجيل شركة + إنشاء حساب مديرها.
// معزول تماماً: تخزين في الذاكرة، لا قاعدة بيانات، لا مساس بالإنتاج.
// ═══════════════════════════════════════════════════════════════════════════

var builder = WebApplication.CreateBuilder(args);
builder.Logging.ClearProviders();
builder.Logging.AddSimpleConsole(o => o.SingleLine = true);
var app = builder.Build();

// ── مفتاح المركز (RSA): تحميل من ملف أو إنشاء وحفظ ──
var keysDir = Path.Combine(AppContext.BaseDirectory, "keys");
Directory.CreateDirectory(keysDir);
var privPath = Path.Combine(keysDir, "center_private.pem");
var pubPath  = Path.Combine(keysDir, "center_public.pem");
var rsa = RSA.Create(2048);
if (File.Exists(privPath))
    rsa.ImportFromPem(File.ReadAllText(privPath));
else
{
    File.WriteAllText(privPath, rsa.ExportRSAPrivateKeyPem());  // سرّي — يبقى في المركز
    File.WriteAllText(pubPath,  rsa.ExportRSAPublicKeyPem());   // عام — يُوزَّع على العقد
}
const string Kid = "sadara-center-2026";
var privateKey = new RsaSecurityKey(rsa) { KeyId = Kid };
var pub = rsa.ExportParameters(false);

// ── مخازن في الذاكرة (إثبات فقط) + بيانات تجريبية مبدئية ──
var companies = new List<Company>
{
    new("company-7A3F", "شركة النور للإنترنت", true, DateTime.UtcNow.AddYears(1)),
};
var users = new List<AppUser>
{
    new("nour_admin", Hash("P@ssw0rd!"), "company-7A3F", "CompanyManager",
        new[] { "subscribers.view", "subscribers.edit", "accounting.view", "tickets.manage" },
        "node-nour-office-01"),
};
const string AdminKey = "super-admin-demo-key"; // الإنتاج: حساب مدير النظام/سر قوي

// ── الصحّة ──
app.MapGet("/health", () => Results.Ok(new { status = "ok", service = "sadara-identity-gateway", kid = Kid }));

// ── نشر المفتاح العام (JWKS) — تستهلكه كل عقدة للتحقق من البطاقات ──
app.MapGet("/.well-known/jwks.json", () => Results.Json(new
{
    keys = new[]
    {
        new
        {
            kty = "RSA", use = "sig", alg = "RS256", kid = Kid,
            n = Base64UrlEncoder.Encode(pub.Modulus),
            e = Base64UrlEncoder.Encode(pub.Exponent),
        }
    }
}));

// ── تسجيل الدخول: يتحقق ويُصدر بطاقة RS256 صالحة 24 ساعة ──
app.MapPost("/auth/login", (LoginReq req) =>
{
    var user = users.FirstOrDefault(u => u.Username == req.Username);
    if (user is null || !Verify(req.Password, user.PasswordHash))
        return Results.Json(new { error = "invalid_credentials" }, statusCode: 401);

    var company = companies.FirstOrDefault(c => c.Id == user.CompanyId);
    if (company is null) return Results.Json(new { error = "company_not_found" }, statusCode: 404);
    if (!company.Active) return Results.Json(new { error = "company_suspended" }, statusCode: 403);
    if (company.LicenseExp < DateTime.UtcNow) return Results.Json(new { error = "license_expired" }, statusCode: 403);

    var now = DateTime.UtcNow;
    var claims = new[]
    {
        new Claim(JwtRegisteredClaimNames.Sub, user.Username),
        new Claim(ClaimTypes.Name, user.Username),
        new Claim(ClaimTypes.Role, user.Role),
        new Claim("company_id", company.Id),
        new Claim("company_name", company.Name),
        new Claim("node_id", user.NodeId),
        new Claim("permissions", string.Join(",", user.Permissions)),
        new Claim("license_exp", company.LicenseExp.ToString("yyyy-MM-dd")),
    };
    var token = new JwtSecurityToken(
        issuer: "sadara-center", audience: "sadara-company-node",
        claims: claims, notBefore: now, expires: now.AddHours(24),
        signingCredentials: new SigningCredentials(privateKey, SecurityAlgorithms.RsaSha256));
    var jwt = new JwtSecurityTokenHandler().WriteToken(token);

    return Results.Ok(new
    {
        access_token = jwt, token_type = "Bearer", expires_in = 86400,
        company = company.Name, node_id = user.NodeId, permissions = user.Permissions
    });
});

// ── مدير النظام: تسجيل شركة جديدة ──
app.MapPost("/admin/companies", ([FromHeader(Name = "X-Admin-Key")] string? adminKey, CompanyReq req) =>
{
    if (adminKey != AdminKey)
        return Results.Json(new { error = "forbidden" }, statusCode: 403);
    var id = "company-" + Guid.NewGuid().ToString("N")[..4].ToUpperInvariant();
    companies.Add(new(id, req.Name, true, DateTime.UtcNow.AddYears(1)));
    return Results.Ok(new { company_id = id, name = req.Name, active = true });
});

// ── مدير النظام: إنشاء حساب مدير شركة ──
app.MapPost("/admin/users", ([FromHeader(Name = "X-Admin-Key")] string? adminKey, UserReq req) =>
{
    if (adminKey != AdminKey)
        return Results.Json(new { error = "forbidden" }, statusCode: 403);
    if (companies.All(c => c.Id != req.CompanyId))
        return Results.Json(new { error = "company_not_found" }, statusCode: 404);
    if (users.Any(u => u.Username == req.Username))
        return Results.Json(new { error = "user_exists" }, statusCode: 409);
    users.Add(new(req.Username, Hash(req.Password), req.CompanyId, "CompanyManager",
        req.Permissions ?? Array.Empty<string>(), req.NodeId ?? ("node-" + req.CompanyId)));
    return Results.Ok(new { username = req.Username, company_id = req.CompanyId });
});

app.Run("http://127.0.0.1:5080");


// ═══════════════════════════ دوال + أنواع ═══════════════════════════
static string Hash(string pw)
{
    var salt = RandomNumberGenerator.GetBytes(16);
    var hash = Rfc2898DeriveBytes.Pbkdf2(pw, salt, 100_000, HashAlgorithmName.SHA256, 32);
    return Convert.ToBase64String(salt) + "." + Convert.ToBase64String(hash);
}
static bool Verify(string pw, string stored)
{
    var parts = stored.Split('.');
    if (parts.Length != 2) return false;
    var salt = Convert.FromBase64String(parts[0]);
    var expected = Convert.FromBase64String(parts[1]);
    var actual = Rfc2898DeriveBytes.Pbkdf2(pw, salt, 100_000, HashAlgorithmName.SHA256, 32);
    return CryptographicOperations.FixedTimeEquals(actual, expected);
}

record Company(string Id, string Name, bool Active, DateTime LicenseExp);
record AppUser(string Username, string PasswordHash, string CompanyId, string Role, string[] Permissions, string NodeId);
record LoginReq(string Username, string Password);
record CompanyReq(string Name);
record UserReq(string Username, string Password, string CompanyId, string[]? Permissions, string? NodeId);
