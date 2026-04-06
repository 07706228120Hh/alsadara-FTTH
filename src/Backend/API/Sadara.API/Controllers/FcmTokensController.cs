using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>
/// إدارة رموز FCM للإشعارات
/// FCM Token management for push notifications
/// </summary>
[ApiController]
[Route("api/fcm-tokens")]
[Authorize]
public class FcmTokensController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<FcmTokensController> _logger;

    public FcmTokensController(IUnitOfWork unitOfWork, ILogger<FcmTokensController> logger)
    {
        _unitOfWork = unitOfWork;
        _logger = logger;
    }

    /// <summary>
    /// تسجيل رمز FCM جديد أو تحديث موجود
    /// Register or update an FCM token for the current user
    /// </summary>
    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterFcmTokenDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Token))
            return BadRequest(new { success = false, message = "Token is required" });

        var userId = GetCurrentUserId();
        if (userId == Guid.Empty)
            return Unauthorized(new { success = false, message = "Invalid user" });

        // Check if token already exists (for any user)
        var existing = await _unitOfWork.UserFcmTokens.AsQueryable()
            .FirstOrDefaultAsync(t => t.Token == dto.Token && !t.IsDeleted);

        if (existing != null)
        {
            // Update ownership if different user, or just update LastActiveAt
            existing.UserId = userId;
            existing.DeviceId = dto.DeviceId ?? existing.DeviceId;
            existing.DevicePlatform = dto.DevicePlatform ?? existing.DevicePlatform;
            existing.LastActiveAt = DateTime.UtcNow;
            existing.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.UserFcmTokens.Update(existing);
        }
        else
        {
            var token = new UserFcmToken
            {
                UserId = userId,
                Token = dto.Token,
                DeviceId = dto.DeviceId,
                DevicePlatform = dto.DevicePlatform,
                LastActiveAt = DateTime.UtcNow,
                CreatedAt = DateTime.UtcNow
            };
            await _unitOfWork.UserFcmTokens.AddAsync(token);
        }

        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("FCM token registered for user {UserId}, platform: {Platform}", userId, dto.DevicePlatform);

        return Ok(new { success = true, message = "Token registered successfully" });
    }

    /// <summary>
    /// إلغاء تسجيل رمز FCM (عند تسجيل الخروج)
    /// Unregister an FCM token (on logout)
    /// </summary>
    [HttpDelete("unregister")]
    public async Task<IActionResult> Unregister([FromBody] UnregisterFcmTokenDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Token))
            return BadRequest(new { success = false, message = "Token is required" });

        var userId = GetCurrentUserId();

        var token = await _unitOfWork.UserFcmTokens.AsQueryable()
            .FirstOrDefaultAsync(t => t.Token == dto.Token && t.UserId == userId && !t.IsDeleted);

        if (token != null)
        {
            token.IsDeleted = true;
            token.DeletedAt = DateTime.UtcNow;
            _unitOfWork.UserFcmTokens.Update(token);
            await _unitOfWork.SaveChangesAsync();
        }

        return Ok(new { success = true, message = "Token unregistered successfully" });
    }

    private Guid GetCurrentUserId()
    {
        var claim = User.FindFirst("sub") ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier);
        return claim != null ? Guid.Parse(claim.Value) : Guid.Empty;
    }
}

public class RegisterFcmTokenDto
{
    public string Token { get; set; } = string.Empty;
    public string? DeviceId { get; set; }
    public string? DevicePlatform { get; set; }
}

public class UnregisterFcmTokenDto
{
    public string Token { get; set; } = string.Empty;
}
