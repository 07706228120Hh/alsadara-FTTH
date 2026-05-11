using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
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
    private readonly SadaraDbContext _context;

    public SubscriberCacheController(
        IUnitOfWork unitOfWork,
        IConfiguration configuration,
        ILogger<SubscriberCacheController> logger,
        SadaraDbContext context)
    {
        _unitOfWork = unitOfWork;
        _configuration = configuration;
        _logger = logger;
        _context = context;
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

    /// <summary>رفع بيانات المشتركين من الجهاز الرئيسي (Master Device)</summary>
    [HttpPost("{tenantId}/upload")]
    public async Task<IActionResult> Upload(Guid tenantId, [FromBody] MasterUploadRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        // التحقق أن وضع الجهاز الرئيسي مفعّل
        var settings = await _context.CompanyFtthSettings
            .FirstOrDefaultAsync(x => x.CompanyId == tenantId && !x.IsDeleted);

        if (settings == null)
            return NotFound(new { success = false, message = "لم يتم إعداد FTTH بعد" });

        if (!settings.IsMasterSyncEnabled)
            return BadRequest(new { success = false, message = "وضع الجهاز الرئيسي غير مفعّل" });

        if (request.Subscribers == null || request.Subscribers.Count == 0)
            return Ok(new { success = true, received = 0, newCount = 0, updatedCount = 0, skippedCount = 0 });

        _logger.LogInformation("Master upload: batch {Batch}/{Total}, {Count} subscribers",
            request.BatchIndex + 1, request.TotalBatches, request.Subscribers.Count);

        // جلب الموجودين في DB للمقارنة
        var incomingIds = request.Subscribers.Select(s => s.SubscriptionId).Where(id => !string.IsNullOrEmpty(id)).ToHashSet();
        var existing = await _context.FtthSubscriberCaches
            .IgnoreQueryFilters()
            .Where(x => x.CompanyId == tenantId && incomingIds.Contains(x.SubscriptionId))
            .ToDictionaryAsync(x => x.SubscriptionId);

        int newCount = 0, updatedCount = 0, skippedCount = 0;

        foreach (var sub in request.Subscribers)
        {
            if (string.IsNullOrEmpty(sub.SubscriptionId)) continue;

            if (existing.TryGetValue(sub.SubscriptionId, out var entity))
            {
                // إعادة إحياء المحذوف
                if (entity.IsDeleted) { entity.IsDeleted = false; entity.DeletedAt = null; }

                // مقارنة — هل تغيّر؟
                if (entity.Status == sub.Status && entity.Expires == sub.Expires
                    && entity.DisplayName == sub.DisplayName && entity.Phone == sub.Phone
                    && entity.FdtName == sub.FdtName && entity.FatName == sub.FatName)
                {
                    skippedCount++;
                    continue;
                }

                // تحديث كل الحقول
                MapDtoToEntity(sub, entity);
                entity.UpdatedAt = DateTime.UtcNow;
                _context.FtthSubscriberCaches.Update(entity);
                updatedCount++;
            }
            else
            {
                // جديد
                var newEntity = new FtthSubscriberCache
                {
                    CompanyId = tenantId,
                    SubscriptionId = sub.SubscriptionId,
                };
                MapDtoToEntity(sub, newEntity);
                _context.FtthSubscriberCaches.Add(newEntity);
                newCount++;
            }
        }

        await _context.SaveChangesAsync();

        // عند آخر دفعة: تحديث الإعدادات + كتابة سجل
        if (request.IsLastBatch)
        {
            var totalInDb = await _context.FtthSubscriberCaches
                .CountAsync(x => x.CompanyId == tenantId && !x.IsDeleted);

            settings.CurrentDbCount = totalInDb;
            settings.LastSyncAt = DateTime.UtcNow;
            settings.LastSyncError = null;
            settings.ConsecutiveFailures = 0;
            settings.UpdatedAt = DateTime.UtcNow;
            _context.CompanyFtthSettings.Update(settings);

            _context.FtthSyncLogs.Add(new FtthSyncLog
            {
                CompanyId = tenantId,
                StartedAt = DateTime.UtcNow,
                CompletedAt = DateTime.UtcNow,
                Status = "Success",
                TriggerSource = "MasterDevice",
                SubscribersCount = totalInDb,
            });

            await _context.SaveChangesAsync();
            _logger.LogInformation("Master upload DONE: {Total} in DB", totalInDb);
        }

        return Ok(new { success = true, received = request.Subscribers.Count, newCount, updatedCount, skippedCount });
    }

    private static void MapDtoToEntity(MasterSubscriberDto dto, FtthSubscriberCache e)
    {
        e.CustomerId = dto.CustomerId;
        e.Username = dto.Username;
        e.DisplayName = dto.DisplayName;
        e.Status = dto.Status;
        e.AutoRenew = dto.AutoRenew;
        e.ProfileName = dto.ProfileName;
        e.BundleId = dto.BundleId;
        e.ZoneId = dto.ZoneId;
        e.ZoneName = dto.ZoneName;
        e.StartedAt = dto.StartedAt;
        e.Expires = dto.Expires;
        e.CommitmentPeriod = dto.CommitmentPeriod;
        e.Phone = dto.Phone;
        e.LockedMac = dto.LockedMac;
        e.FdtName = dto.FdtName;
        e.FatName = dto.FatName;
        e.DeviceSerial = dto.DeviceSerial;
        e.GpsLat = dto.GpsLat;
        e.GpsLng = dto.GpsLng;
        e.IsTrial = dto.IsTrial;
        e.IsPending = dto.IsPending;
        e.IsSuspended = dto.IsSuspended;
        e.SuspensionReason = dto.SuspensionReason;
        e.DetailsFetched = dto.DetailsFetched;
        // لا نعيد تعيين DetailsFetchedAt إذا كانت التفاصيل مجلوبة مسبقاً
        if (dto.DetailsFetched && e.DetailsFetchedAt == null)
            e.DetailsFetchedAt = DateTime.UtcNow;
        else if (!dto.DetailsFetched)
            e.DetailsFetchedAt = null;
        e.ServicesJson = dto.ServicesJson;
    }
}

// ============ DTOs للرفع من الجهاز الرئيسي ============

public class MasterUploadRequest
{
    public List<MasterSubscriberDto> Subscribers { get; set; } = new();
    public int BatchIndex { get; set; }
    public int TotalBatches { get; set; }
    public bool IsLastBatch { get; set; }
}

public class MasterSubscriberDto
{
    public string SubscriptionId { get; set; } = "";
    public string CustomerId { get; set; } = "";
    public string Username { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public string Status { get; set; } = "";
    public bool AutoRenew { get; set; }
    public string ProfileName { get; set; } = "";
    public string? BundleId { get; set; }
    public string? ZoneId { get; set; }
    public string ZoneName { get; set; } = "";
    public string? StartedAt { get; set; }
    public string? Expires { get; set; }
    public string? CommitmentPeriod { get; set; }
    public string Phone { get; set; } = "";
    public string? LockedMac { get; set; }
    public string FdtName { get; set; } = "";
    public string FatName { get; set; } = "";
    public string DeviceSerial { get; set; } = "";
    public string? GpsLat { get; set; }
    public string? GpsLng { get; set; }
    public bool IsTrial { get; set; }
    public bool IsPending { get; set; }
    public bool IsSuspended { get; set; }
    public string? SuspensionReason { get; set; }
    public bool DetailsFetched { get; set; }
    public string? ServicesJson { get; set; }
}
