using Microsoft.AspNetCore.SignalR;
using Sadara.API.Authorization;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Hubs;

/// <summary>
/// SignalR Hub — بث مباشر لمواقع الموظفين
/// كل الأجهزة المتصلة تستلم تحديثات فورية بدون Polling
///
/// المصادقة (المرحلة 0 / A2):
///   - JWT عبر <c>?access_token=</c> (يقرؤه JwtBearer في Program.cs لمسارات /hubs): موظف نشط له
///     صلاحية التتبّع (مدير/مشرف أو منح صريح لـ tracking) ⇒ ينضم لمجموعة شركته فقط
///     (<see cref="CompanyGroup"/>)؛ SuperAdmin ⇒ مجموعة المشاهدين العامة.
///   - LEGACY: <c>?apiKey=</c> بقيمة من إعداد الخادم فقط ⇒ مجموعة المشاهدين العامة (النسخ القديمة)
///     حتى تدوير المفتاح.
/// </summary>
public class LocationHub : Hub
{
    /// <summary>Unscoped watchers: legacy key connections and SuperAdmin.</summary>
    public const string LegacyWatchersGroup = "watchers";

    /// <summary>Company-scoped watchers (JWT).</summary>
    public static string CompanyGroup(Guid companyId) => $"location_company_{companyId:N}";

    private readonly IConfiguration _configuration;
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<LocationHub> _logger;

    public LocationHub(IConfiguration configuration, IServiceScopeFactory scopeFactory, ILogger<LocationHub> logger)
    {
        _configuration = configuration;
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    /// <summary>عند الاتصال — التحقق من JWT (موظف الشركة) أو المفتاح القديم</summary>
    public override async Task OnConnectedAsync()
    {
        var http = Context.GetHttpContext();
        if (http == null)
        {
            Context.Abort();
            return;
        }

        // LEGACY: old installed apps connect with ?apiKey= (value compared against server config only).
        var apiKey = http.Request.Query["apiKey"].FirstOrDefault();
        if (LegacyKeyOrJwtGate.IsValidInternalApiKeyValue(apiKey, _configuration))
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, LegacyWatchersGroup);
            await base.OnConnectedAsync();
            return;
        }

        var group = await ResolveJwtGroupAsync(http);
        if (group == null)
        {
            Context.Abort();
            return;
        }

        await Groups.AddToGroupAsync(Context.ConnectionId, group);
        await base.OnConnectedAsync();
    }

    /// <summary>Returns the group a JWT watcher may join, or null when not allowed.</summary>
    private async Task<string?> ResolveJwtGroupAsync(HttpContext http)
    {
        if (http.User?.Identity?.IsAuthenticated != true) return null;
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var uow = scope.ServiceProvider.GetRequiredService<IUnitOfWork>();
            var caller = await InternalCallerAccess.ResolveAsync(http, _configuration, uow);
            if (!caller.IsJwt) return null;
            if (!caller.IsManagerOrHasPermission("tracking", "view", failClosed: true)) return null;
            if (caller.IsSuperAdmin) return LegacyWatchersGroup;
            return caller.CompanyId.HasValue ? CompanyGroup(caller.CompanyId.Value) : null;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "LocationHub: failed to resolve JWT watcher");
            return null;
        }
    }

    private static IReadOnlyList<string> TargetGroups(Guid? companyId) =>
        companyId.HasValue
            ? new[] { LegacyWatchersGroup, CompanyGroup(companyId.Value) }
            : new[] { LegacyWatchersGroup };

    /// <summary>
    /// يُستدعى من EmployeeLocationController عند استلام موقع جديد.
    /// يبث للمشاهدين العامّين (المفتاح القديم/SuperAdmin) ولمشاهدي شركة الموظف فقط.
    /// </summary>
    public static async Task BroadcastLocationUpdate(IHubContext<LocationHub> hubContext, object locationData,
        Guid? companyId = null)
    {
        await hubContext.Clients.Groups(TargetGroups(companyId)).SendAsync("LocationUpdated", locationData);
    }

    /// <summary>
    /// إبلاغ المشاهدين بأن موظف أوقف المشاركة
    /// </summary>
    public static async Task BroadcastUserStopped(IHubContext<LocationHub> hubContext, string userId,
        Guid? companyId = null)
    {
        await hubContext.Clients.Groups(TargetGroups(companyId)).SendAsync("UserStopped", userId);
    }
}
