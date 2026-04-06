using Microsoft.AspNetCore.SignalR;

namespace Sadara.API.Hubs;

/// <summary>
/// SignalR Hub — بث مباشر لمواقع الموظفين
/// كل الأجهزة المتصلة تستلم تحديثات فورية بدون Polling
/// </summary>
public class LocationHub : Hub
{
    private readonly IConfiguration _configuration;

    public LocationHub(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    /// <summary>عند الاتصال — التحقق من API Key</summary>
    public override async Task OnConnectedAsync()
    {
        var apiKey = Context.GetHttpContext()?.Request.Query["apiKey"].FirstOrDefault();
        var configKey = _configuration["Security:InternalApiKey"]
            ?? Environment.GetEnvironmentVariable("SADARA_INTERNAL_API_KEY")
            ?? "";

        if (string.IsNullOrEmpty(apiKey) || apiKey != configKey)
        {
            Context.Abort();
            return;
        }

        // انضمام لمجموعة "admins" (مشاهدي الخريطة)
        await Groups.AddToGroupAsync(Context.ConnectionId, "watchers");
        await base.OnConnectedAsync();
    }

    /// <summary>
    /// يُستدعى من EmployeeLocationController عند استلام موقع جديد
    /// يبث لجميع المتصلين فوراً
    /// </summary>
    public static async Task BroadcastLocationUpdate(IHubContext<LocationHub> hubContext, object locationData)
    {
        await hubContext.Clients.Group("watchers").SendAsync("LocationUpdated", locationData);
    }

    /// <summary>
    /// إبلاغ المشاهدين بأن موظف أوقف المشاركة
    /// </summary>
    public static async Task BroadcastUserStopped(IHubContext<LocationHub> hubContext, string userId)
    {
        await hubContext.Clients.Group("watchers").SendAsync("UserStopped", userId);
    }
}
