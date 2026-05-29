using Microsoft.AspNetCore.SignalR;

namespace Sadara.API.Hubs;

/// <summary>
/// خدمة لإرسال إشعارات المهام عبر SignalR من أي كونترولر
/// </summary>
public class TaskHubNotifier
{
    private readonly IHubContext<TaskHub> _hubContext;

    public TaskHubNotifier(IHubContext<TaskHub> hubContext)
    {
        _hubContext = hubContext;
    }

    /// <summary>
    /// إشعار بإنشاء مهمة جديدة
    /// </summary>
    public async Task NotifyTaskCreated(string companyId, object taskData)
    {
        await _hubContext.Clients.Group($"company_{companyId}")
            .SendAsync("TaskCreated", taskData);
    }

    /// <summary>
    /// إشعار بتحديث حالة مهمة
    /// </summary>
    public async Task NotifyTaskUpdated(string companyId, object taskData)
    {
        await _hubContext.Clients.Group($"company_{companyId}")
            .SendAsync("TaskUpdated", taskData);
    }

    /// <summary>
    /// إشعار بتعيين مهمة
    /// </summary>
    public async Task NotifyTaskAssigned(string companyId, object taskData)
    {
        await _hubContext.Clients.Group($"company_{companyId}")
            .SendAsync("TaskAssigned", taskData);
    }

    /// <summary>
    /// إشعار بحذف مهمة
    /// </summary>
    public async Task NotifyTaskDeleted(string companyId, string requestNumber)
    {
        await _hubContext.Clients.Group($"company_{companyId}")
            .SendAsync("TaskDeleted", new { requestNumber });
    }
}
