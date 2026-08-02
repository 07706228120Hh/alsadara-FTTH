using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;

// ═══════════════════════════════════════════════════════════════════════════
// العقدة المحلية (نموذج أوّلي) = حاسبة الشركة.
//   ① عند الإقلاع: تجلب المفتاح العام من بوابة الهوية مرّة واحدة.
//   ② لكل طلب: تتحقق من بطاقة الدخول ذاتياً (RS256) بالمفتاح العام —
//      دون أي اتصال بالمركز.
//   ③ تطبّق الصلاحيات المكتوبة داخل البطاقة على العمليات المحلية.
// معزول: يمثّل بيانات محلية، لا يمسّ الإنتاج.
// ═══════════════════════════════════════════════════════════════════════════

var gatewayUrl = Environment.GetEnvironmentVariable("GATEWAY_URL") ?? "http://127.0.0.1:5080";
var nodeId     = Environment.GetEnvironmentVariable("NODE_ID")     ?? "node-nour-office-01";

// إعداد العقدة من ملف (يُسلّمه مدير النظام عند التسجيل — يحاكي المُثبِّت)
var nodeConfigPath = Environment.GetEnvironmentVariable("NODE_CONFIG")
    ?? Path.Combine(AppContext.BaseDirectory, "node.config.json");
if (File.Exists(nodeConfigPath))
{
    var cfg = System.Text.Json.JsonSerializer.Deserialize<NodeConfig>(File.ReadAllText(nodeConfigPath));
    if (cfg is not null)
    {
        if (!string.IsNullOrWhiteSpace(cfg.gateway_url)) gatewayUrl = cfg.gateway_url!;
        if (!string.IsNullOrWhiteSpace(cfg.node_id))     nodeId     = cfg.node_id!;
    }
    Console.WriteLine($"[node] حُمّل الإعداد من {nodeConfigPath}");
}

var builder = WebApplication.CreateBuilder(args);
builder.Logging.ClearProviders();
builder.Logging.AddSimpleConsole(o => o.SingleLine = true);

// ① جلب المفتاح العام من البوابة مرّة واحدة عند الإقلاع
string jwksJson;
using (var http = new HttpClient { Timeout = TimeSpan.FromSeconds(10) })
    jwksJson = await http.GetStringAsync($"{gatewayUrl}/.well-known/jwks.json");
var signingKeys = new JsonWebKeySet(jwksJson).GetSigningKeys();
Console.WriteLine($"[node] حُمّل {signingKeys.Count} مفتاح عام من البوابة {gatewayUrl}");

// ② إعداد التحقق الذاتي من البطاقات (RS256) بالمفتاح العام
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        o.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,            ValidIssuer   = "sadara-center",
            ValidateAudience = true,          ValidAudience = "sadara-company-node",
            ValidateIssuerSigningKey = true,  IssuerSigningKeys = signingKeys,
            ValidateLifetime = true,          ClockSkew = TimeSpan.Zero,
        };
    });
builder.Services.AddAuthorization();

var app = builder.Build();
app.UseAuthentication();
app.UseAuthorization();

// معلومات العقدة (عام — بلا بطاقة)
app.MapGet("/node/info", () => Results.Ok(new
{
    node = nodeId,
    gateway = gatewayUrl,
    public_keys_loaded = signingKeys.Count,
    note = "تتحقق من البطاقات ذاتياً بالمفتاح العام — دون سؤال المركز في كل طلب"
}));

// عملية محلية: عرض المشتركين (تتطلب بطاقة + صلاحية subscribers.view)
app.MapGet("/subscribers", (ClaimsPrincipal user) =>
{
    if (!HasPerm(user, "subscribers.view"))
        return Results.Json(new { error = "forbidden_permission", need = "subscribers.view" }, statusCode: 403);
    return Results.Ok(new
    {
        company = user.FindFirst("company_name")?.Value,
        company_id = user.FindFirst("company_id")?.Value,
        source = "قاعدة البيانات المحلية للشركة",
        subscribers = new[]
        {
            new { id = 1, name = "مشترك تجريبي أ", status = "active" },
            new { id = 2, name = "مشترك تجريبي ب", status = "active" },
        }
    });
}).RequireAuthorization();

// عملية محلية: المحاسبة (تتطلب بطاقة + صلاحية accounting.view)
app.MapGet("/accounting", (ClaimsPrincipal user) =>
{
    if (!HasPerm(user, "accounting.view"))
        return Results.Json(new { error = "forbidden_permission", need = "accounting.view" }, statusCode: 403);
    return Results.Ok(new
    {
        company = user.FindFirst("company_name")?.Value,
        balance = 12_500_000,
        currency = "IQD",
        source = "قاعدة البيانات المحلية للشركة"
    });
}).RequireAuthorization();

app.Run("http://127.0.0.1:5090");


// ═══════════════════════════ دوال مساعدة ═══════════════════════════
static bool HasPerm(ClaimsPrincipal user, string perm)
{
    var claim = user.FindFirst("permissions")?.Value ?? "";
    return claim.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Contains(perm);
}

record NodeConfig(string? gateway_url, string? jwks_url, string? company_id, string? company_name, string? node_id);
