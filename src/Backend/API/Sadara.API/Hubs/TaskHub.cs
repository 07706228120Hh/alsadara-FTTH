using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace Sadara.API.Hubs;

/// <summary>
/// SignalR Hub لإشعارات المهام الفورية
/// </summary>
[Authorize]
public class TaskHub : Hub
{
    private readonly ILogger<TaskHub> _logger;

    public TaskHub(ILogger<TaskHub> logger)
    {
        _logger = logger;
    }

    public override async Task OnConnectedAsync()
    {
        // إضافة المستخدم إلى مجموعة الشركة
        var companyId = Context.User?.FindFirst("company_id")?.Value;
        if (!string.IsNullOrEmpty(companyId))
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, $"company_{companyId}");
            _logger.LogInformation("SignalR: {User} connected to company_{CompanyId}", Context.UserIdentifier, companyId);
        }
        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var companyId = Context.User?.FindFirst("company_id")?.Value;
        if (!string.IsNullOrEmpty(companyId))
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"company_{companyId}");
        }
        await base.OnDisconnectedAsync(exception);
    }
}
