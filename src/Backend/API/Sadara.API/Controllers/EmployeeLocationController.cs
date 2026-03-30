using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>
/// API لتتبع مواقع الموظفين — بديل Google Sheets
/// </summary>
[ApiController]
[Route("api/employee-location")]
[Tags("EmployeeLocation")]
public class EmployeeLocationController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IConfiguration _configuration;
    private readonly ILogger<EmployeeLocationController> _logger;

    public EmployeeLocationController(
        IUnitOfWork unitOfWork,
        IConfiguration configuration,
        ILogger<EmployeeLocationController> logger)
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
            ?? "";
        return !string.IsNullOrEmpty(apiKey) && apiKey == configKey;
    }

    // ══════════════════════════════════════
    // POST /api/employee-location
    // تحديث موقع (upsert)
    // ══════════════════════════════════════

    [HttpPost]
    [AllowAnonymous]
    public async Task<IActionResult> UpdateLocation([FromBody] LocationUpdateRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            if (string.IsNullOrWhiteSpace(request.UserId))
                return BadRequest(new { success = false, message = "userId مطلوب" });

            var now = DateTime.UtcNow;

            var existing = await _unitOfWork.EmployeeLocations
                .FirstOrDefaultAsync(e => e.UserId == request.UserId);

            if (existing != null)
            {
                existing.Latitude = request.Latitude;
                existing.Longitude = request.Longitude;
                existing.IsActive = true;
                existing.LastUpdate = now;
                existing.UpdatedAt = now;
                if (request.Department != null) existing.Department = request.Department;
                if (request.Center != null) existing.Center = request.Center;
                if (request.Phone != null) existing.Phone = request.Phone;
                _unitOfWork.EmployeeLocations.Update(existing);
            }
            else
            {
                var location = new EmployeeLocation
                {
                    UserId = request.UserId,
                    Department = request.Department,
                    Center = request.Center,
                    Phone = request.Phone,
                    Latitude = request.Latitude,
                    Longitude = request.Longitude,
                    IsActive = true,
                    LastUpdate = now,
                };
                await _unitOfWork.EmployeeLocations.AddAsync(location);
            }

            // حفظ سجل تاريخي (كل 30 ثانية على الأقل)
            var lastLog = await _unitOfWork.EmployeeLocationLogs.AsQueryable()
                .Where(l => l.UserId == request.UserId)
                .OrderByDescending(l => l.RecordedAt)
                .FirstOrDefaultAsync();

            if (lastLog == null || (now - lastLog.RecordedAt).TotalSeconds >= 30)
            {
                await _unitOfWork.EmployeeLocationLogs.AddAsync(new EmployeeLocationLog
                {
                    UserId = request.UserId!,
                    Latitude = request.Latitude,
                    Longitude = request.Longitude,
                    RecordedAt = now,
                });
            }

            await _unitOfWork.SaveChangesAsync();
            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating employee location");
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // DELETE /api/employee-location/{userId}
    // إيقاف مشاركة الموقع
    // ══════════════════════════════════════

    [HttpDelete("{userId}")]
    [AllowAnonymous]
    public async Task<IActionResult> StopSharing(string userId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var existing = await _unitOfWork.EmployeeLocations
                .FirstOrDefaultAsync(e => e.UserId == userId);

            if (existing != null)
            {
                existing.IsActive = false;
                existing.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.EmployeeLocations.Update(existing);
                await _unitOfWork.SaveChangesAsync();
            }

            return Ok(new { success = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error stopping location sharing for {UserId}", userId);
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // GET /api/employee-location/active
    // جلب كل المواقع النشطة
    // ══════════════════════════════════════

    [HttpGet("active")]
    [AllowAnonymous]
    public async Task<IActionResult> GetActiveLocations()
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var locations = await _unitOfWork.EmployeeLocations.AsQueryable()
                .Where(e => e.IsActive)
                .Select(e => new
                {
                    userId = e.UserId,
                    department = e.Department,
                    center = e.Center,
                    phone = e.Phone,
                    lat = e.Latitude,
                    lng = e.Longitude,
                    active = e.IsActive,
                    lastUpdate = e.LastUpdate.ToString("o"),
                })
                .ToListAsync();

            return Ok(new { success = true, data = locations });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting active locations");
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // GET /api/employee-location/alerts
    // تنبيهات: موظف أوقف المشاركة أو لم يحدّث منذ فترة
    // ══════════════════════════════════════

    [HttpGet("alerts")]
    [AllowAnonymous]
    public async Task<IActionResult> GetAlerts([FromQuery] int staleMinutes = 5)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var cutoff = DateTime.UtcNow.AddMinutes(-staleMinutes);

            // موظفين نشطين لكن لم يحدّثوا منذ فترة
            var stale = await _unitOfWork.EmployeeLocations.AsQueryable()
                .Where(e => e.IsActive && e.LastUpdate < cutoff)
                .Select(e => new
                {
                    userId = e.UserId,
                    department = e.Department,
                    lastUpdate = e.LastUpdate.ToString("o"),
                    minutesAgo = (int)(DateTime.UtcNow - e.LastUpdate).TotalMinutes,
                    alertType = "stale",
                })
                .ToListAsync();

            // موظفين أوقفوا المشاركة اليوم
            var todayStart = DateTime.UtcNow.Date;
            var stopped = await _unitOfWork.EmployeeLocations.AsQueryable()
                .Where(e => !e.IsActive && e.UpdatedAt != null && e.UpdatedAt > todayStart)
                .Select(e => new
                {
                    userId = e.UserId,
                    department = e.Department,
                    lastUpdate = e.LastUpdate.ToString("o"),
                    minutesAgo = (int)(DateTime.UtcNow - e.LastUpdate).TotalMinutes,
                    alertType = "stopped",
                })
                .ToListAsync();

            var alerts = stale.Cast<object>().Concat(stopped.Cast<object>()).ToList();
            return Ok(new { success = true, data = alerts, staleCount = stale.Count, stoppedCount = stopped.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting location alerts");
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // GET /api/employee-location/history/{userId}
    // سجل المواقع لموظف (آخر 24 ساعة)
    // ══════════════════════════════════════

    [HttpGet("history/{userId}")]
    [AllowAnonymous]
    public async Task<IActionResult> GetHistory(string userId, [FromQuery] int hours = 24)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var since = DateTime.UtcNow.AddHours(-hours);

            var logs = await _unitOfWork.EmployeeLocationLogs.AsQueryable()
                .Where(l => l.UserId == userId && l.RecordedAt >= since)
                .OrderBy(l => l.RecordedAt)
                .Select(l => new
                {
                    lat = l.Latitude,
                    lng = l.Longitude,
                    recordedAt = l.RecordedAt.ToString("o"),
                })
                .ToListAsync();

            // حساب المسافة الإجمالية
            double totalDistance = 0;
            for (int i = 1; i < logs.Count; i++)
            {
                var prev = logs[i - 1];
                var curr = logs[i];
                totalDistance += HaversineDistance(prev.lat, prev.lng, curr.lat, curr.lng);
            }

            return Ok(new
            {
                success = true,
                data = logs,
                totalPoints = logs.Count,
                totalDistanceKm = Math.Round(totalDistance / 1000, 2),
                hours,
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting location history for {UserId}", userId);
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    /// <summary>حساب المسافة بالمتر (Haversine)</summary>
    private static double HaversineDistance(double lat1, double lon1, double lat2, double lon2)
    {
        const double R = 6371000;
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLon = (lon2 - lon1) * Math.PI / 180;
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(lat1 * Math.PI / 180) * Math.Cos(lat2 * Math.PI / 180) *
                Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        return R * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }

    // ══════════════════════════════════════
    // Request DTO
    // ══════════════════════════════════════

    public class LocationUpdateRequest
    {
        public string? UserId { get; set; }
        public string? Department { get; set; }
        public string? Center { get; set; }
        public string? Phone { get; set; }
        public double Latitude { get; set; }
        public double Longitude { get; set; }
    }
}
