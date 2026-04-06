using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Sadara.API.Hubs;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
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
    private readonly IHubContext<LocationHub> _hubContext;
    private readonly IFcmNotificationService _fcm;

    public EmployeeLocationController(
        IUnitOfWork unitOfWork,
        IConfiguration configuration,
        ILogger<EmployeeLocationController> logger,
        IHubContext<LocationHub> hubContext,
        IFcmNotificationService fcm)
    {
        _unitOfWork = unitOfWork;
        _configuration = configuration;
        _logger = logger;
        _hubContext = hubContext;
        _fcm = fcm;
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

            // ══════════════════════════════════════
            // 🛡️ كشف الموقع الوهمي — server-side
            // ══════════════════════════════════════
            var isFake = request.IsFakeDetected || request.IsMocked;
            var serverReasons = new List<string>();

            // فحص server-side: مقارنة مع آخر نقطة
            var lastLog = await _unitOfWork.EmployeeLocationLogs.AsQueryable()
                .Where(l => l.UserId == request.UserId)
                .OrderByDescending(l => l.RecordedAt)
                .FirstOrDefaultAsync();

            if (lastLog != null)
            {
                var elapsed = (now - lastLog.RecordedAt).TotalSeconds;
                if (elapsed > 0 && elapsed < 120)
                {
                    var dist = HaversineDistance(lastLog.Latitude, lastLog.Longitude,
                        request.Latitude, request.Longitude);
                    var speedMs = dist / elapsed;

                    // > 300 كم/س = انتقال مستحيل
                    if (speedMs > 83)
                    {
                        isFake = true;
                        serverReasons.Add($"server:teleport:{speedMs * 3.6:F0}km/h");
                    }
                }

                // نفس الإحداثيات بالضبط لأكثر من 10 دقائق = مشبوه
                if (lastLog.Latitude == request.Latitude &&
                    lastLog.Longitude == request.Longitude &&
                    (now - lastLog.RecordedAt).TotalMinutes > 10)
                {
                    serverReasons.Add("server:frozen_location");
                }
            }

            // دمج أسباب الكشف
            var allReasons = request.FakeReasons ?? "";
            if (serverReasons.Count > 0)
                allReasons = string.IsNullOrEmpty(allReasons)
                    ? string.Join(",", serverReasons)
                    : $"{allReasons},{string.Join(",", serverReasons)}";

            // حفظ سجل تاريخي — ذكي: يحفظ فقط إذا تحرك الموظف أو مر وقت كافٍ
            var shouldLog = false;
            if (lastLog == null)
            {
                shouldLog = true; // أول نقطة
            }
            else
            {
                var elapsed = (now - lastLog.RecordedAt).TotalSeconds;
                var moved = HaversineDistance(lastLog.Latitude, lastLog.Longitude,
                    request.Latitude, request.Longitude);

                // يحفظ إذا: تحرك > 5 متر ومر > 5 ثواني، أو مر > 60 ثانية (حتى لو واقف)
                shouldLog = (moved > 5 && elapsed >= 5) || elapsed >= 60;
            }

            if (shouldLog)
            {
                await _unitOfWork.EmployeeLocationLogs.AddAsync(new EmployeeLocationLog
                {
                    UserId = request.UserId!,
                    Latitude = request.Latitude,
                    Longitude = request.Longitude,
                    RecordedAt = now,
                    Accuracy = request.Accuracy,
                    Altitude = request.Altitude,
                    Speed = request.Speed,
                    IsMocked = request.IsMocked,
                    IsFakeDetected = isFake,
                    FakeReasons = string.IsNullOrEmpty(allReasons) ? null : allReasons,
                    TeleportCount = request.TeleportCount,
                    FakeFlagCount = request.FakeFlagCount,
                });
            }

            await _unitOfWork.SaveChangesAsync();

            // 🔴 بث مباشر — إبلاغ جميع المشاهدين فوراً عبر SignalR
            _ = LocationHub.BroadcastLocationUpdate(_hubContext, new
            {
                userId = request.UserId,
                lat = request.Latitude,
                lng = request.Longitude,
                accuracy = request.Accuracy,
                speed = request.Speed,
                department = existing?.Department ?? request.Department,
                timestamp = now.ToString("o"),
                isFake,
            });

            // 🔔 تنبيه FCM للمدراء عند كشف فيك لوكيشن
            if (isFake)
            {
                _ = SendAlertToManagersAsync(
                    "🚫 موقع وهمي",
                    $"الموظف {request.UserId} يستخدم موقع وهمي ({allReasons})",
                    new Dictionary<string, string>
                    {
                        ["type"] = "fake_location",
                        ["userId"] = request.UserId ?? "",
                        ["reasons"] = allReasons,
                    });
            }

            return Ok(new
            {
                success = true,
                isFakeDetected = isFake,
                reasons = allReasons,
            });
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

            // بث مباشر — إبلاغ المشاهدين أن الموظف أوقف المشاركة
            _ = LocationHub.BroadcastUserStopped(_hubContext, userId);

            // 🔔 تنبيه FCM للمدراء
            _ = SendAlertToManagersAsync(
                "📍 إيقاف مشاركة",
                $"الموظف {userId} أوقف مشاركة موقعه",
                new Dictionary<string, string>
                {
                    ["type"] = "sharing_stopped",
                    ["userId"] = userId,
                });

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
            var staleThreshold = DateTime.UtcNow.AddMinutes(-2);
            var locations = await _unitOfWork.EmployeeLocations.AsQueryable()
                .Where(e => e.IsActive && e.LastUpdate > staleThreshold)
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
    // GET /api/employee-location/tracked-users?hours=24
    // جميع المستخدمين الذين لديهم سجلات خلال فترة معينة
    // ══════════════════════════════════════

    [HttpGet("tracked-users")]
    [AllowAnonymous]
    public async Task<IActionResult> GetTrackedUsers([FromQuery] int hours = 24)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var since = DateTime.UtcNow.AddHours(-hours);
            var users = await _unitOfWork.EmployeeLocationLogs.AsQueryable()
                .Where(l => l.RecordedAt >= since)
                .GroupBy(l => l.UserId)
                .Select(g => new
                {
                    userId = g.Key,
                    points = g.Count(),
                    firstSeen = g.Min(l => l.RecordedAt),
                    lastSeen = g.Max(l => l.RecordedAt),
                    fakeCount = g.Count(l => l.IsFakeDetected),
                })
                .OrderByDescending(x => x.lastSeen)
                .ToListAsync();

            // جلب معلومات إضافية (القسم، المركز) من جدول EmployeeLocations
            var locationInfo = await _unitOfWork.EmployeeLocations.AsQueryable()
                .Where(e => users.Select(u => u.userId).Contains(e.UserId))
                .ToDictionaryAsync(e => e.UserId, e => new { e.Department, e.Center, e.IsActive });

            var result = users.Select(u => new
            {
                u.userId,
                department = locationInfo.ContainsKey(u.userId) ? locationInfo[u.userId].Department : null,
                center = locationInfo.ContainsKey(u.userId) ? locationInfo[u.userId].Center : null,
                isActive = locationInfo.ContainsKey(u.userId) && locationInfo[u.userId].IsActive,
                u.points,
                u.fakeCount,
                fakePercent = u.points > 0 ? Math.Round(u.fakeCount * 100.0 / u.points, 1) : 0,
                firstSeen = u.firstSeen.ToString("o"),
                lastSeen = u.lastSeen.ToString("o"),
            }).ToList();

            return Ok(new { success = true, data = result });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting tracked users");
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
    public async Task<IActionResult> GetHistory(string userId, [FromQuery] int hours = 24, [FromQuery] bool snap = true)
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
                    isFake = l.IsFakeDetected,
                    fakeReasons = l.FakeReasons,
                    speed = l.Speed,
                })
                .ToListAsync();

            // ══════════════════════════════════════
            // 1️⃣ كشف نقاط التوقف (Stop Detection)
            // ══════════════════════════════════════
            var stops = DetectStops(logs.Select(l => (l.lat, l.lng, DateTime.Parse(l.recordedAt))).ToList());

            // ══════════════════════════════════════
            // 2️⃣ OSRM Map Matching — لصق النقاط على الشوارع
            // ══════════════════════════════════════
            List<object>? snappedPath = null;
            double? roadDistanceKm = null;

            if (snap && logs.Count >= 2)
            {
                try
                {
                    var (snapped, dist) = await SnapToRoadsOSRM(
                        logs.Select(l => (l.lat, l.lng)).ToList());
                    snappedPath = snapped;
                    roadDistanceKm = dist;
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "OSRM map matching failed, using raw points");
                }
            }

            // حساب المسافة الإجمالية (Haversine — fallback)
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
                snappedPath,  // المسار الملصوق على الشوارع
                stops,        // نقاط التوقف
                totalPoints = logs.Count,
                totalDistanceKm = Math.Round(totalDistance / 1000, 2),
                roadDistanceKm, // المسافة الفعلية على الطريق
                hours,
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting location history for {UserId}", userId);
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // OSRM Map Matching — لصق GPS على الشوارع
    // يستخدم OSRM العام (مجاني، لا يحتاج مفتاح)
    // ══════════════════════════════════════

    private static readonly HttpClient _httpClient = new() { Timeout = TimeSpan.FromSeconds(15) };

    private async Task<(List<object> points, double distanceKm)> SnapToRoadsOSRM(
        List<(double lat, double lng)> rawPoints)
    {
        // OSRM يقبل حد أقصى ~100 نقطة في الطلب الواحد
        // نقسّم إلى batches إذا أكثر
        const int batchSize = 80;
        var allSnapped = new List<object>();
        double totalDist = 0;

        for (int batch = 0; batch < rawPoints.Count; batch += batchSize)
        {
            var chunk = rawPoints.Skip(batch).Take(batchSize + 5).ToList(); // تداخل 5 نقاط
            if (chunk.Count < 2) break;

            // بناء رابط OSRM Match API
            var coords = string.Join(";", chunk.Select(p => $"{p.lng},{p.lat}"));
            var url = $"https://router.project-osrm.org/match/v1/driving/{coords}"
                    + "?overview=full&geometries=geojson&radiuses="
                    + string.Join(";", chunk.Select(_ => "25")); // نصف قطر 25 متر

            var response = await _httpClient.GetAsync(url);
            if (!response.IsSuccessStatusCode) continue;

            var json = await response.Content.ReadAsStringAsync();
            using var doc = System.Text.Json.JsonDocument.Parse(json);
            var root = doc.RootElement;

            if (root.GetProperty("code").GetString() != "Ok") continue;

            var matchings = root.GetProperty("matchings");
            foreach (var matching in matchings.EnumerateArray())
            {
                totalDist += matching.GetProperty("distance").GetDouble();
                var geometry = matching.GetProperty("geometry").GetProperty("coordinates");
                foreach (var coord in geometry.EnumerateArray())
                {
                    var lng = coord[0].GetDouble();
                    var lat = coord[1].GetDouble();
                    allSnapped.Add(new { lat, lng });
                }
            }
        }

        return (allSnapped, Math.Round(totalDist / 1000, 2));
    }

    // ══════════════════════════════════════
    // كشف نقاط التوقف — أين وقف الموظف ولكم من الوقت
    // ══════════════════════════════════════

    private static List<object> DetectStops(List<(double lat, double lng, DateTime time)> points)
    {
        if (points.Count < 3) return new();

        const double stopRadiusMeters = 30; // إذا بقي ضمن 30 متر = واقف
        const int minStopSeconds = 120;     // يجب أن يبقى 2+ دقيقة ليُعتبر توقف

        var stops = new List<object>();
        int i = 0;

        while (i < points.Count)
        {
            var anchor = points[i];
            int j = i + 1;

            // ابحث عن نقاط قريبة متتالية
            while (j < points.Count)
            {
                var dist = QuickDistance(anchor.lat, anchor.lng, points[j].lat, points[j].lng);
                if (dist > stopRadiusMeters) break;
                j++;
            }

            var duration = (points[Math.Min(j, points.Count) - 1].time - anchor.time).TotalSeconds;
            if (j - i >= 3 && duration >= minStopSeconds)
            {
                // حساب متوسط الموقع
                var avgLat = points.Skip(i).Take(j - i).Average(p => p.lat);
                var avgLng = points.Skip(i).Take(j - i).Average(p => p.lng);
                stops.Add(new
                {
                    lat = Math.Round(avgLat, 6),
                    lng = Math.Round(avgLng, 6),
                    arrivedAt = anchor.time.ToString("o"),
                    leftAt = points[Math.Min(j, points.Count) - 1].time.ToString("o"),
                    durationMinutes = Math.Round(duration / 60, 1),
                    pointCount = j - i,
                });
            }
            i = Math.Max(j, i + 1);
        }

        return stops;
    }

    /// <summary>مسافة تقريبية سريعة بالمتر (بدون sin/cos)</summary>
    private static double QuickDistance(double lat1, double lon1, double lat2, double lon2)
    {
        var dLat = (lat2 - lat1) * 111320;
        var dLon = (lon2 - lon1) * 111320 * 0.7; // تقريب cos(33°) للعراق
        return Math.Sqrt(dLat * dLat + dLon * dLon);
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
    // GET /api/employee-location/daily-report?date=2026-04-03
    // تقرير يومي شامل لجميع الموظفين
    // ══════════════════════════════════════

    [HttpGet("daily-report")]
    [AllowAnonymous]
    public async Task<IActionResult> GetDailyReport([FromQuery] string? date = null)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var targetDate = date != null ? DateTime.Parse(date).Date : DateTime.UtcNow.Date;
            var dayStart = targetDate;
            var dayEnd = targetDate.AddDays(1);

            // جلب كل logs اليوم
            var allLogs = await _unitOfWork.EmployeeLocationLogs.AsQueryable()
                .Where(l => l.RecordedAt >= dayStart && l.RecordedAt < dayEnd)
                .OrderBy(l => l.RecordedAt)
                .ToListAsync();

            var grouped = allLogs.GroupBy(l => l.UserId);

            var report = new List<object>();
            foreach (var group in grouped)
            {
                var logs = group.ToList();
                if (logs.Count < 2) continue;

                // ساعات العمل (من أول نقطة لآخر نقطة)
                var firstSeen = logs.First().RecordedAt;
                var lastSeen = logs.Last().RecordedAt;
                var workHours = (lastSeen - firstSeen).TotalHours;

                // المسافة الإجمالية
                double totalDist = 0;
                for (int i = 1; i < logs.Count; i++)
                    totalDist += HaversineDistance(logs[i - 1].Latitude, logs[i - 1].Longitude,
                        logs[i].Latitude, logs[i].Longitude);

                // نقاط التوقف
                var stops = DetectStops(logs.Select(l => (l.Latitude, l.Longitude, l.RecordedAt)).ToList());
                var totalStopMinutes = stops.Sum(s =>
                    s is { } obj ? ((dynamic)obj).durationMinutes : 0.0);

                // نسبة الفيك
                var fakeCount = logs.Count(l => l.IsFakeDetected);

                // جلب معلومات القسم
                var empInfo = await _unitOfWork.EmployeeLocations
                    .FirstOrDefaultAsync(e => e.UserId == group.Key);

                report.Add(new
                {
                    userId = group.Key,
                    department = empInfo?.Department,
                    center = empInfo?.Center,
                    firstSeen = firstSeen.ToString("o"),
                    lastSeen = lastSeen.ToString("o"),
                    workHours = Math.Round(workHours, 1),
                    totalDistanceKm = Math.Round(totalDist / 1000, 1),
                    totalPoints = logs.Count,
                    stopCount = stops.Count,
                    totalStopMinutes = Math.Round((double)totalStopMinutes, 0),
                    activeMinutes = Math.Round(workHours * 60 - (double)totalStopMinutes, 0),
                    fakeCount,
                    fakePercent = logs.Count > 0 ? Math.Round(fakeCount * 100.0 / logs.Count, 1) : 0,
                });
            }

            return Ok(new
            {
                success = true,
                date = targetDate.ToString("yyyy-MM-dd"),
                employees = report.OrderByDescending(r => ((dynamic)r).workHours).ToList(),
                totalEmployees = report.Count,
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error generating daily report");
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // DELETE /api/employee-location/purge?olderThanDays=30
    // مسح البيانات القديمة — للمدراء فقط
    // ══════════════════════════════════════

    [HttpDelete("purge")]
    [AllowAnonymous]
    public async Task<IActionResult> PurgeOldData([FromQuery] int olderThanDays = 30, [FromQuery] bool all = false)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var callerRole = Request.Headers["X-Caller-Role"].FirstOrDefault();
        if (callerRole != "manager" && callerRole != "admin" && callerRole != "super_admin")
            return StatusCode(403, new { success = false, message = "صلاحية المدير مطلوبة" });

        try
        {
            int logsCount = 0;
            int locationsCount = 0;

            if (all)
            {
                // مسح كل البيانات
                var allLogs = await _unitOfWork.EmployeeLocationLogs.AsQueryable().ToListAsync();
                logsCount = allLogs.Count;
                foreach (var log in allLogs)
                    _unitOfWork.EmployeeLocationLogs.Delete(log);

                var allLocations = await _unitOfWork.EmployeeLocations.AsQueryable().ToListAsync();
                locationsCount = allLocations.Count;
                foreach (var loc in allLocations)
                    _unitOfWork.EmployeeLocations.Delete(loc);
            }
            else
            {
                var cutoff = DateTime.UtcNow.AddDays(-olderThanDays);
                var oldLogs = await _unitOfWork.EmployeeLocationLogs.AsQueryable()
                    .Where(l => l.RecordedAt < cutoff)
                    .ToListAsync();
                logsCount = oldLogs.Count;
                foreach (var log in oldLogs)
                    _unitOfWork.EmployeeLocationLogs.Delete(log);
            }

            await _unitOfWork.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                deletedLogs = logsCount,
                deletedLocations = locationsCount,
                deletedCount = logsCount + locationsCount,
                mode = all ? "all" : $"older_than_{olderThanDays}_days",
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error purging location data");
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
    }

    // ══════════════════════════════════════
    // إرسال تنبيه FCM لجميع المدراء
    // ══════════════════════════════════════

    private async Task SendAlertToManagersAsync(string title, string body, Dictionary<string, string>? data = null)
    {
        try
        {
            // جلب كل المدراء ومدراء الشركات والسوبر أدمن
            var managerRoles = new[] { UserRole.Manager, UserRole.CompanyAdmin, UserRole.SuperAdmin, UserRole.TechnicalLeader };
            var managerIds = await _unitOfWork.Users.AsQueryable()
                .Where(u => u.IsActive && managerRoles.Contains(u.Role))
                .Select(u => u.Id)
                .ToListAsync();

            if (managerIds.Count > 0)
            {
                await _fcm.SendToUsersAsync(managerIds, title, body, data);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to send FCM alert to managers");
        }
    }

    // ══════════════════════════════════════
    // GET /api/employee-location/check-long-stops?minutes=30
    // فحص التوقفات الطويلة وإرسال تنبيهات
    // ══════════════════════════════════════

    [HttpGet("check-long-stops")]
    [AllowAnonymous]
    public async Task<IActionResult> CheckLongStops([FromQuery] int minutes = 30)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        try
        {
            var cutoff = DateTime.UtcNow.AddMinutes(-minutes);

            // موظفين نشطين لكن آخر تحديث قديم
            var longStopped = await _unitOfWork.EmployeeLocations.AsQueryable()
                .Where(e => e.IsActive && e.LastUpdate < cutoff)
                .Select(e => new { e.UserId, e.Department, e.LastUpdate })
                .ToListAsync();

            // إرسال تنبيه لكل واحد
            foreach (var emp in longStopped)
            {
                var mins = (int)(DateTime.UtcNow - emp.LastUpdate).TotalMinutes;
                _ = SendAlertToManagersAsync(
                    "⏱️ توقف طويل",
                    $"الموظف {emp.UserId} ({emp.Department}) متوقف منذ {mins} دقيقة",
                    new Dictionary<string, string>
                    {
                        ["type"] = "long_stop",
                        ["userId"] = emp.UserId,
                        ["minutes"] = mins.ToString(),
                    });
            }

            return Ok(new
            {
                success = true,
                longStoppedCount = longStopped.Count,
                employees = longStopped.Select(e => new
                {
                    e.UserId,
                    e.Department,
                    minutesStopped = (int)(DateTime.UtcNow - e.LastUpdate).TotalMinutes,
                }),
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error checking long stops");
            return StatusCode(500, new { success = false, message = "حدث خطأ" });
        }
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

        // ═══ حقول كشف الموقع الوهمي ═══
        public double? Accuracy { get; set; }
        public double? Altitude { get; set; }
        public double? Speed { get; set; }
        public bool IsMocked { get; set; }
        public bool IsFakeDetected { get; set; }
        public string? FakeReasons { get; set; }
        public int TeleportCount { get; set; }
        public int FakeFlagCount { get; set; }
    }
}
