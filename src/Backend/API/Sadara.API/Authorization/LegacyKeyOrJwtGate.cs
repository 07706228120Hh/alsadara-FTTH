using Microsoft.AspNetCore.Mvc;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Authorization;

/// <summary>
/// Phase 0 / stream A2: shared gate for the controllers that used to accept ONLY the hardcoded internal
/// API key (EmployeeLocation, Reminder, WhatsApp, CompanyFtthSettings, IptvSubscribers, SubscriberCache,
/// ZoneStatistics, LocationHub).
///
/// Built on <see cref="InternalCallerAccess"/> (same identity resolution as /api/internal):
///   - legacy <c>X-Api-Key</c> (value from server configuration only, constant-time compare) keeps the
///     old, unscoped server-to-server behaviour until the key is rotated (n8n, smoke script, old apps);
///   - a JWT must belong to an ACTIVE staff user (Employee..CompanyAdmin, or SuperAdmin) whose company
///     matches the token; citizens/agents/merchants/deleted users are rejected (403);
///   - CompanyId/UserId on the JWT path always come from the token + database, never from the request.
/// </summary>
public static class LegacyKeyOrJwtGate
{
    public const string MsgUnauthenticated = "غير مصرّح — يلزم تسجيل الدخول";
    public const string MsgRejected = "غير مصرّح لهذا الحساب";
    public const string MsgOtherCompany = "لا تملك صلاحية الوصول لبيانات شركة أخرى";
    public const string MsgNoPermission = "لا تملك صلاحية كافية لهذه العملية";
    public const string MsgManagerOnly = "هذه العملية متاحة لمدير الشركة فقط";

    /// <summary>
    /// Resolves the caller once per request. Returns an error result for <see cref="InternalAuthMode.None"/>
    /// (401) and <see cref="InternalAuthMode.Rejected"/> (403); otherwise <c>Error == null</c>.
    /// </summary>
    public static async Task<(InternalCaller Caller, IActionResult? Error)> AuthorizeAsync(
        HttpContext http, IConfiguration configuration, IUnitOfWork unitOfWork)
    {
        var caller = await InternalCallerAccess.ResolveAsync(http, configuration, unitOfWork);
        return caller.Mode switch
        {
            InternalAuthMode.None => (caller, Unauthorized()),
            InternalAuthMode.Rejected => (caller, Forbidden(MsgRejected)),
            _ => (caller, null),
        };
    }

    /// <summary>
    /// Constant-time check of a key value delivered outside the X-Api-Key header (SignalR query string)
    /// against server configuration. Fail-closed when no key is configured. The value is never logged.
    /// </summary>
    public static bool IsValidInternalApiKeyValue(string? provided, IConfiguration configuration)
    {
        if (string.IsNullOrEmpty(provided)) return false;
        var configured = configuration["Security:InternalApiKey"]
                         ?? Environment.GetEnvironmentVariable("SADARA_INTERNAL_API_KEY");
        if (string.IsNullOrEmpty(configured)) return false;
        var a = System.Text.Encoding.UTF8.GetBytes(provided);
        var b = System.Text.Encoding.UTF8.GetBytes(configured);
        return a.Length == b.Length && System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(a, b);
    }

    public static IActionResult Unauthorized() =>
        new ObjectResult(new { success = false, message = MsgUnauthenticated }) { StatusCode = 401 };

    public static IActionResult Forbidden(string message) =>
        new ObjectResult(new { success = false, message }) { StatusCode = 403 };

    /// <summary>
    /// Manager-level caller: legacy key, SuperAdmin, or a JWT CompanyAdmin/Manager
    /// (same set the app treats as "مدير").
    /// </summary>
    public static bool IsCompanyManager(this InternalCaller caller) =>
        caller.IsApiKey || caller.IsSuperAdmin
        || (caller.IsJwt && caller.Role is UserRole.CompanyAdmin or UserRole.Manager);

    /// <summary>Manager-level caller OR an explicit grant (see <see cref="InternalCaller.HasPermission"/>).</summary>
    public static bool IsManagerOrHasPermission(this InternalCaller caller, string key, string action = "view",
        bool failClosed = false) =>
        caller.IsCompanyManager() || caller.HasPermission(key, action, failClosed);

    /// <summary>
    /// Mirrors the app's "default visible" semantics for optional UI features: allowed unless the
    /// permission key is present in the user's V2 permissions with the action explicitly false.
    /// Legacy key / SuperAdmin pass.
    /// </summary>
    public static bool NotExplicitlyDenied(this InternalCaller caller, string key, string action = "view")
    {
        if (caller.IsApiKey || caller.IsSuperAdmin) return true;
        if (!caller.IsJwt) return false;
        var json = caller.FirstSystemPermissionsV2;
        if (string.IsNullOrWhiteSpace(json)) return true;
        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(json);
            foreach (var feature in doc.RootElement.EnumerateObject())
            {
                if (!string.Equals(feature.Name, key, StringComparison.OrdinalIgnoreCase)) continue;
                if (feature.Value.ValueKind != System.Text.Json.JsonValueKind.Object) return true;
                foreach (var a in feature.Value.EnumerateObject())
                {
                    if (!string.Equals(a.Name, action, StringComparison.OrdinalIgnoreCase)) continue;
                    return a.Value.ValueKind switch
                    {
                        System.Text.Json.JsonValueKind.False => false,
                        System.Text.Json.JsonValueKind.String => !string.Equals(a.Value.GetString(), "false",
                            StringComparison.OrdinalIgnoreCase),
                        _ => true,
                    };
                }
                return true;
            }
            return true;
        }
        catch
        {
            return false; // malformed permissions => deny
        }
    }

    /// <summary>
    /// Platform default company (<c>Tenancy:DefaultCompanyId</c>) — the same value the DbContext stamps on
    /// rows inserted from a bypass context (legacy key / n8n). Unstamped legacy rows (CompanyId = null) of
    /// the single-tenant integrations (WhatsApp inbox, reminders, zone statistics) belong to it.
    /// </summary>
    public static Guid? DefaultCompanyId(IConfiguration configuration)
    {
        var raw = configuration["Tenancy:DefaultCompanyId"];
        return Guid.TryParse(raw, out var id) && id != Guid.Empty ? id : null;
    }

    /// <summary>
    /// May the caller see/modify rows whose CompanyId is NULL (unstamped legacy data)?
    /// Legacy key and SuperAdmin: yes (unchanged). JWT company user: only when its company is the configured
    /// default company; fail-closed when <c>Tenancy:DefaultCompanyId</c> is not configured.
    /// </summary>
    public static bool OwnsUnstampedRows(this InternalCaller caller, IConfiguration configuration)
    {
        if (caller.IsApiKey || caller.IsSuperAdmin) return true;
        if (!caller.IsTenantBound) return false;
        var def = DefaultCompanyId(configuration);
        return def.HasValue && caller.CompanyId == def.Value;
    }
}
