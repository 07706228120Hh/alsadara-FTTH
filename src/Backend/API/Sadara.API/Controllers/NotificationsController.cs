using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class NotificationsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public NotificationsController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet("user/{userId:guid}")]
    [Authorize]
    public async Task<IActionResult> GetByUser(Guid userId, [FromQuery] bool? unreadOnly, [FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var query = _unitOfWork.Notifications.AsQueryable()
            .Where(n => n.UserId == userId);

        if (unreadOnly == true)
            query = query.Where(n => !n.IsRead);

        var total = await query.CountAsync();
        var notifications = await query
            .OrderByDescending(n => n.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return Ok(new { success = true, data = notifications, total, page, pageSize });
    }

    [HttpGet("unread-count/{userId:guid}")]
    [Authorize]
    public async Task<IActionResult> GetUnreadCount(Guid userId)
    {
        var count = await _unitOfWork.Notifications.CountAsync(n => n.UserId == userId && !n.IsRead);
        return Ok(new { success = true, data = count });
    }

    [HttpPatch("{id:long}/read")]
    [Authorize]
    public async Task<IActionResult> MarkAsRead(long id)
    {
        var notification = await _unitOfWork.Notifications.GetByIdAsync(id);
        if (notification == null)
            return NotFound(new { success = false, message = "Notification not found" });

        notification.IsRead = true;
        notification.ReadAt = DateTime.UtcNow;
        _unitOfWork.Notifications.Update(notification);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true });
    }

    [HttpPatch("read-all/{userId:guid}")]
    [Authorize]
    public async Task<IActionResult> MarkAllAsRead(Guid userId)
    {
        var notifications = await _unitOfWork.Notifications.FindAsync(n => n.UserId == userId && !n.IsRead);

        foreach (var notification in notifications)
        {
            notification.IsRead = true;
            notification.ReadAt = DateTime.UtcNow;
            _unitOfWork.Notifications.Update(notification);
        }

        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "All notifications marked as read" });
    }

    [HttpPost("send")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Send([FromBody] SendNotificationRequest request)
    {
        var notification = new Notification
        {
            UserId = request.UserId,
            Title = request.Title,
            TitleAr = request.TitleAr,
            Body = request.Body,
            BodyAr = request.BodyAr,
            Type = request.Type,
            Data = request.Data,
            ImageUrl = request.ImageUrl,
            ActionUrl = request.ActionUrl,
            IsRead = false,
            IsSent = false,
            CreatedAt = DateTime.UtcNow
        };

        await _unitOfWork.Notifications.AddAsync(notification);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, data = notification.Id });
    }

    [HttpDelete("{id:long}")]
    [Authorize]
    public async Task<IActionResult> Delete(long id)
    {
        var notification = await _unitOfWork.Notifications.GetByIdAsync(id);
        if (notification == null)
            return NotFound(new { success = false, message = "Notification not found" });

        _unitOfWork.Notifications.Delete(notification);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true });
    }
}

public class SendNotificationRequest
{
    public Guid UserId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? TitleAr { get; set; }
    public string Body { get; set; } = string.Empty;
    public string? BodyAr { get; set; }
    public Sadara.Domain.Enums.NotificationType Type { get; set; }
    public string? Data { get; set; }
    public string? ImageUrl { get; set; }
    public string? ActionUrl { get; set; }
}
