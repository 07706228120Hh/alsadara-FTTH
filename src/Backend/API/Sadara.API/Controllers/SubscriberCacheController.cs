using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Interfaces;
using Sadara.Infrastructure.Data;

namespace Sadara.API.Controllers;

/// <summary>
/// تنزيل بيانات المشتركين المخزنة في الكاش
/// يُستخدم من تطبيق Flutter بدلاً من الاتصال المباشر بـ FTTH
/// </summary>
[ApiController]
[Route("api/subscriber-cache")]
[Produces("application/json")]
public class SubscriberCacheController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IConfiguration _configuration;
    private readonly ILogger<SubscriberCacheController> _logger;

    public SubscriberCacheController(
        IUnitOfWork unitOfWork,
        IConfiguration configuration,
        ILogger<SubscriberCacheController> logger)
    {
        _unitOfWork = unitOfWork;
        _configuration = configuration;
        _logger = logger;
    }

    private bool ValidateApiKey()
    {
        var apiKey = Request.Headers["X-Api-Key"].FirstOrDefault();
        var configKey = _configuration["Security:InternalApiKey"]
            ?? Environment.GetEnvironmentVariable("SADARA_INTERNAL_API_KEY")
            ?? "sadara-internal-2024-secure-key";
        return !string.IsNullOrEmpty(apiKey) && apiKey == configKey;
    }

    /// <summary>تنزيل كامل لبيانات المشتركين</summary>
    [HttpGet("{tenantId}/download")]
    public async Task<IActionResult> Download(Guid tenantId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var subscribers = await _unitOfWork.FtthSubscriberCaches.AsQueryable()
            .Where(x => x.CompanyId == tenantId)
            .Select(x => new
            {
                x.SubscriptionId,
                x.CustomerId,
                x.Username,
                x.DisplayName,
                x.Status,
                x.AutoRenew,
                x.ProfileName,
                x.BundleId,
                x.ZoneId,
                x.ZoneName,
                x.StartedAt,
                x.Expires,
                x.CommitmentPeriod,
                x.Phone,
                x.LockedMac,
                x.FdtName,
                x.FatName,
                x.DeviceSerial,
                x.GpsLat,
                x.GpsLng,
                x.IsTrial,
                x.IsPending,
                x.IsSuspended,
                x.SuspensionReason,
                x.DetailsFetched,
                x.DetailsFetchedAt,
                x.ServicesJson,
                x.UpdatedAt,
            })
            .ToListAsync();

        return Ok(new
        {
            success = true,
            count = subscribers.Count,
            data = subscribers,
        });
    }

    /// <summary>تنزيل التحديثات منذ تاريخ معين (مزامنة تزايدية)</summary>
    [HttpGet("{tenantId}/updated-since")]
    public async Task<IActionResult> UpdatedSince(Guid tenantId, [FromQuery] DateTime since)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        // تحويل إلى UTC إذا لم يكن كذلك
        var sinceUtc = since.Kind == DateTimeKind.Utc ? since : since.ToUniversalTime();

        var updates = await _unitOfWork.FtthSubscriberCaches.AsQueryable()
            .Where(x => x.CompanyId == tenantId && x.UpdatedAt > sinceUtc)
            .Select(x => new
            {
                x.SubscriptionId,
                x.CustomerId,
                x.Username,
                x.DisplayName,
                x.Status,
                x.AutoRenew,
                x.ProfileName,
                x.BundleId,
                x.ZoneId,
                x.ZoneName,
                x.StartedAt,
                x.Expires,
                x.CommitmentPeriod,
                x.Phone,
                x.LockedMac,
                x.FdtName,
                x.FatName,
                x.DeviceSerial,
                x.GpsLat,
                x.GpsLng,
                x.IsTrial,
                x.IsPending,
                x.IsSuspended,
                x.SuspensionReason,
                x.DetailsFetched,
                x.DetailsFetchedAt,
                x.ServicesJson,
                x.UpdatedAt,
            })
            .ToListAsync();

        return Ok(new
        {
            success = true,
            count = updates.Count,
            data = updates,
        });
    }

    /// <summary>جلب عدد المشتركين وآخر تحديث</summary>
    [HttpGet("{tenantId}")]
    public async Task<IActionResult> GetInfo(Guid tenantId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var query = _unitOfWork.FtthSubscriberCaches.AsQueryable()
            .Where(x => x.CompanyId == tenantId);

        var count = await query.CountAsync();
        var lastUpdate = count > 0
            ? await query.MaxAsync(x => x.UpdatedAt)
            : null;

        return Ok(new
        {
            success = true,
            count,
            lastUpdate,
        });
    }
}
