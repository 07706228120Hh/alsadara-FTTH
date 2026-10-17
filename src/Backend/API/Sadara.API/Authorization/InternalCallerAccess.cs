using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Authorization;

/// <summary>How the caller of an internal endpoint authenticated.</summary>
public enum InternalAuthMode
{
    /// <summary>No credentials at all (or an invalid API key without a JWT) => 401.</summary>
    None,

    /// <summary>
    /// Legacy server-to-server / old-app path: valid <c>X-Api-Key</c> matching server configuration.
    /// Behaviour is intentionally unchanged (trusted, no tenant scoping) until the key is rotated.
    /// </summary>
    ApiKey,

    /// <summary>Valid JWT of an active company employee (or SuperAdmin) found in the Users table.</summary>
    Jwt,

    /// <summary>A JWT was presented but does not map to an active staff user (agent/citizen/deleted/mismatch) => 403.</summary>
    Rejected,
}

/// <summary>
/// Resolved identity of a caller of <c>/api/internal/*</c>.
/// For <see cref="InternalAuthMode.Jwt"/> the company and user ALWAYS come from the token + database,
/// never from the request body/query.
/// </summary>
public sealed class InternalCaller
{
    public InternalAuthMode Mode { get; init; }
    public Guid? UserId { get; init; }
    public Guid? CompanyId { get; init; }
    public bool IsSuperAdmin { get; init; }
    public UserRole? Role { get; init; }
    public string? FirstSystemPermissionsV2 { get; init; }
    public string? SecondSystemPermissionsV2 { get; init; }

    /// <summary>For <see cref="InternalAuthMode.None"/>: a Bearer token was sent but did not authenticate (expired/invalid).</summary>
    public bool PresentedBearerToken { get; init; }

    /// <summary>Identity names of the JWT user (to match legacy name-keyed records such as settlement reports).</summary>
    public string? FullName { get; init; }
    public string? Username { get; init; }
    public string? FtthUsername { get; init; }

    /// <summary>Does <paramref name="name"/> designate this JWT caller (FTTH username, username or full name)?</summary>
    public bool IsNamed(string? name)
    {
        if (!IsJwt || string.IsNullOrWhiteSpace(name)) return false;
        var n = name.Trim();
        return Matches(FtthUsername) || Matches(Username) || Matches(FullName);

        bool Matches(string? v) => !string.IsNullOrWhiteSpace(v)
            && string.Equals(v.Trim(), n, StringComparison.OrdinalIgnoreCase);
    }

    public bool IsApiKey => Mode == InternalAuthMode.ApiKey;
    public bool IsJwt => Mode == InternalAuthMode.Jwt;

    /// <summary>JWT caller that is bound to a single company (i.e. not SuperAdmin).</summary>
    public bool IsTenantBound => IsJwt && !IsSuperAdmin;

    /// <summary>Legacy key and SuperAdmin are not tenant-bound; everybody else must match the company.</summary>
    public bool CanAccessCompany(Guid? companyId)
    {
        if (IsApiKey || IsSuperAdmin) return true;
        return IsJwt && companyId.HasValue && CompanyId.HasValue && companyId.Value == CompanyId.Value;
    }

    /// <summary>
    /// Same semantics as <see cref="RequirePermissionAttribute"/> (hierarchical V2 keys; fail-open on an
    /// empty V2 column unless <paramref name="failClosed"/>). Legacy key and SuperAdmin pass.
    /// </summary>
    public bool HasPermission(string key, string action, bool failClosed = false,
        PermissionSystem system = PermissionSystem.First)
    {
        if (IsApiKey || IsSuperAdmin) return true;
        if (!IsJwt) return false;
        var json = system == PermissionSystem.First ? FirstSystemPermissionsV2 : SecondSystemPermissionsV2;
        return RequirePermissionAttribute.HasPermission(json, key, action, failClosed);
    }

    /// <summary>Company management roles (CompanyAdmin/Manager) — full employee management in their company.</summary>
    public bool IsCompanyManager => IsJwt && Role is UserRole.CompanyAdmin or UserRole.Manager;

    /// <summary>
    /// May manage employees (create/update/password/permissions/delete) of its own company:
    /// SuperAdmin, CompanyAdmin/Manager role, or an EXPLICIT (fail-closed) grant on one of the
    /// user-management permission keys. Fail-closed here so an empty V2 column never grants user management.
    /// </summary>
    public bool CanManageEmployees(string action)
    {
        if (IsApiKey || IsSuperAdmin) return true;
        if (!IsJwt) return false;
        if (Role is UserRole.CompanyAdmin or UserRole.Manager) return true;
        foreach (var key in EmployeeManagementPermissionKeys)
        {
            if (RequirePermissionAttribute.HasPermission(FirstSystemPermissionsV2, key, action, failClosed: true))
                return true;
        }
        return false;
    }

    /// <summary>
    /// Management tier of <see cref="UserRole"/>. Below it the enum is NOT hierarchical
    /// (Employee=10 &lt; Viewer=11 &lt; Technician=12 &lt; TechnicalLeader=13 are peers, not ranks),
    /// so a numeric comparison is only meaningful inside this set.
    /// </summary>
    public static readonly IReadOnlySet<UserRole> ManagementRoles =
        new HashSet<UserRole> { UserRole.Manager, UserRole.CompanyAdmin, UserRole.SuperAdmin };

    public static bool IsManagementRole(UserRole role) => ManagementRoles.Contains(role);

    /// <summary>
    /// May a tenant-bound caller act on (read sensitive data / edit / reset password / delete) a user
    /// holding <paramref name="targetRole"/>? Non-management staff roles: yes (subject to
    /// <see cref="CanManageEmployees"/>). Management roles: only if not above the caller
    /// (Manager on Manager ok; Manager on CompanyAdmin denied; nobody here touches SuperAdmin).
    /// </summary>
    public bool CanActOnRole(UserRole targetRole)
    {
        if (IsApiKey || IsSuperAdmin) return true;
        if (!IsJwt || Role is null) return false;
        if (targetRole == UserRole.SuperAdmin) return false;
        if (!IsManagementRole(targetRole)) return targetRole >= UserRole.Employee; // staff peers only
        return IsManagementRole(Role.Value) && targetRole <= Role.Value;
    }

    /// <summary>
    /// May the caller ASSIGN <paramref name="newRole"/> (create/update)? Never a role higher than its own:
    /// non-management staff roles are assignable by anyone allowed to manage employees; management roles
    /// only by an equal-or-higher manager (same rule as <see cref="CanActOnRole"/>).
    /// </summary>
    public bool CanAssignRole(UserRole newRole) => CanActOnRole(newRole);

    private static readonly string[] EmployeeManagementPermissionKeys =
        { "users", "hr.employees", "hr.permissions" };
}

/// <summary>
/// Shared resolution of "legacy internal API key OR company JWT" for internal endpoints.
/// The key value is read from configuration only (<c>Security:InternalApiKey</c> or env
/// <c>SADARA_INTERNAL_API_KEY</c>); fail-closed when not configured. The value is never logged.
/// </summary>
public static class InternalCallerAccess
{
    private const string ApiKeyHeader = "X-Api-Key";
    private const string CacheItemKey = "__sadara_internal_caller";

    /// <summary>Constant-time check of the X-Api-Key header against server configuration.</summary>
    public static bool IsValidInternalApiKey(HttpRequest request, IConfiguration configuration)
    {
        var provided = request.Headers[ApiKeyHeader].FirstOrDefault();
        if (string.IsNullOrEmpty(provided)) return false;

        var configured = configuration["Security:InternalApiKey"]
                         ?? Environment.GetEnvironmentVariable("SADARA_INTERNAL_API_KEY");
        if (string.IsNullOrEmpty(configured)) return false; // fail-closed

        var a = Encoding.UTF8.GetBytes(provided);
        var b = Encoding.UTF8.GetBytes(configured);
        return a.Length == b.Length && CryptographicOperations.FixedTimeEquals(a, b);
    }

    /// <summary>
    /// Resolves the caller once per request (cached in HttpContext.Items).
    /// Order: valid API key => <see cref="InternalAuthMode.ApiKey"/>; authenticated JWT => DB lookup
    /// of the user (must be an active, non-deleted staff user; company must match the token claim);
    /// otherwise <see cref="InternalAuthMode.None"/>.
    /// </summary>
    public static async Task<InternalCaller> ResolveAsync(HttpContext http, IConfiguration configuration, IUnitOfWork unitOfWork)
    {
        if (http.Items.TryGetValue(CacheItemKey, out var cached) && cached is InternalCaller c)
            return c;

        var caller = await ResolveCoreAsync(http, configuration, unitOfWork);
        http.Items[CacheItemKey] = caller;
        return caller;
    }

    private static async Task<InternalCaller> ResolveCoreAsync(HttpContext http, IConfiguration configuration, IUnitOfWork unitOfWork)
    {
        if (IsValidInternalApiKey(http.Request, configuration))
            return new InternalCaller { Mode = InternalAuthMode.ApiKey };

        var principal = http.User;
        if (principal?.Identity?.IsAuthenticated != true)
        {
            // Bearer presented but not authenticated (expired/invalid token) ⇒ session-expired message, not "Invalid API Key".
            var authHeader = http.Request.Headers.Authorization.FirstOrDefault();
            return new InternalCaller
            {
                Mode = InternalAuthMode.None,
                PresentedBearerToken = authHeader != null
                    && authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase),
            };
        }

        var rejected = new InternalCaller { Mode = InternalAuthMode.Rejected };

        var userIdRaw = principal.FindFirst(ClaimTypes.NameIdentifier)?.Value
                        ?? principal.FindFirst("sub")?.Value
                        ?? principal.FindFirst("nameid")?.Value;
        if (!Guid.TryParse(userIdRaw, out var userId))
            return rejected;

        var user = await unitOfWork.Users.AsQueryable()
            .Where(u => u.Id == userId && !u.IsDeleted)
            .Select(u => new
            {
                u.Id, u.CompanyId, u.Role, u.IsActive,
                u.FirstSystemPermissionsV2, u.SecondSystemPermissionsV2,
                u.FullName, u.Username, u.FtthUsername,
            })
            .FirstOrDefaultAsync();

        // Only real staff users: not agents/citizens/merchants, not deleted, not deactivated.
        if (user == null || !user.IsActive || user.Role < UserRole.Employee)
            return rejected;

        var isSuperAdmin = user.Role == UserRole.SuperAdmin;

        if (!isSuperAdmin)
        {
            if (!user.CompanyId.HasValue || user.CompanyId.Value == Guid.Empty)
                return rejected;

            // A stale token from another company must not be honoured.
            var tokenCompanyRaw = principal.FindFirst("company_id")?.Value ?? principal.FindFirst("companyId")?.Value;
            if (Guid.TryParse(tokenCompanyRaw, out var tokenCompany) && tokenCompany != user.CompanyId.Value)
                return rejected;
        }

        return new InternalCaller
        {
            Mode = InternalAuthMode.Jwt,
            UserId = user.Id,
            CompanyId = isSuperAdmin ? null : user.CompanyId,
            IsSuperAdmin = isSuperAdmin,
            Role = user.Role,
            FirstSystemPermissionsV2 = user.FirstSystemPermissionsV2,
            SecondSystemPermissionsV2 = user.SecondSystemPermissionsV2,
            FullName = user.FullName,
            Username = user.Username,
            FtthUsername = user.FtthUsername,
        };
    }
}
