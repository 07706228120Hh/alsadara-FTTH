using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;
using Sadara.API.Authorization;
using System.Security.Claims;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[RequirePermission("attendance", "view")]
public class AttendanceController(IUnitOfWork unitOfWork, ILogger<AttendanceController> logger) : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork = unitOfWork;
    private readonly ILogger<AttendanceController> _logger = logger;

    // ============================================================
    // Layer 3: استخراج UserId من JWT بدلاً من الوثوق بالعميل
    // ============================================================
    private Guid? GetAuthenticatedUserId()
    {
        var claim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value
                 ?? User.FindFirst(JwtRegisteredClaimNames.Sub)?.Value
                 ?? User.FindFirst("sub")?.Value;
        return Guid.TryParse(claim, out var id) ? id : null;
    }

    // ============================================================
    // Layer 2: التحقق من الموقع الجغرافي في السيرفر (Haversine)
    // ============================================================
    private static double CalculateDistanceMeters(double lat1, double lon1, double lat2, double lon2)
    {
        const double R = 6371000; // نصف قطر الأرض بالأمتار
        var dLat = DegreesToRadians(lat2 - lat1);
        var dLon = DegreesToRadians(lon2 - lon1);
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(DegreesToRadians(lat1)) * Math.Cos(DegreesToRadians(lat2)) *
                Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        var c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
        return R * c;
    }

    private static double DegreesToRadians(double degrees) => degrees * Math.PI / 180;

    // ============================================================
    // Layer 5: تسجيل محاولة الحضور (ناجحة أو مرفوضة)
    // ============================================================
    private async Task LogAuditAsync(Guid userId, string userName, Guid? companyId, string actionType,
        bool isSuccess, string? rejectionReason, double? lat, double? lon, double? distance,
        string? centerName, string? deviceFingerprint, string? registeredFingerprint,
        bool isVpnSuspected = false)
    {
        try
        {
            var audit = new AttendanceAuditLog
            {
                UserId = userId,
                UserName = userName,
                CompanyId = companyId,
                ActionType = actionType,
                IsSuccess = isSuccess,
                RejectionReason = rejectionReason,
                Latitude = lat,
                Longitude = lon,
                DistanceFromCenter = distance,
                CenterName = centerName,
                DeviceFingerprint = deviceFingerprint,
                RegisteredDeviceFingerprint = registeredFingerprint,
                IpAddress = GetClientIpAddress(),
                IsVpnSuspected = isVpnSuspected,
                AttemptTime = DateTime.UtcNow,
            };
            await _unitOfWork.AttendanceAuditLogs.AddAsync(audit);
            await _unitOfWork.SaveChangesAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "فشل تسجيل سجل التدقيق للحضور");
        }
    }

    // ============================================================
    // Rate Limiting: فحص عدد المحاولات الفاشلة خلال 15 دقيقة
    // ============================================================
    private async Task<(bool isLimited, int retryAfterSeconds)> IsRateLimitedAsync(Guid userId)
    {
        var threshold = DateTime.UtcNow.AddMinutes(-15);
        var failedCount = await _unitOfWork.AttendanceAuditLogs.AsQueryable()
            .CountAsync(a => a.UserId == userId && !a.IsSuccess && a.AttemptTime > threshold);

        if (failedCount >= 5)
        {
            // أقدم محاولة فاشلة خلال الـ 15 دقيقة — إعادة المحاولة بعد انتهاءها
            var oldest = await _unitOfWork.AttendanceAuditLogs.AsQueryable()
                .Where(a => a.UserId == userId && !a.IsSuccess && a.AttemptTime > threshold)
                .OrderBy(a => a.AttemptTime)
                .Select(a => a.AttemptTime)
                .FirstOrDefaultAsync();

            var retryAfter = (int)(oldest.AddMinutes(15) - DateTime.UtcNow).TotalSeconds;
            return (true, Math.Max(retryAfter, 60));
        }
        return (false, 0);
    }

    // ============================================================
    // كشف VPN (soft — لا يمنع، تسجيل فقط)
    // ============================================================
    private bool DetectVpnSuspicion()
    {
        try
        {
            var forwardedFor = HttpContext.Request.Headers["X-Forwarded-For"].FirstOrDefault();
            var realIp = HttpContext.Request.Headers["X-Real-IP"].FirstOrDefault();
            var connectionIp = HttpContext.Connection.RemoteIpAddress?.ToString();

            // عدة IPs في X-Forwarded-For = proxy/VPN
            if (!string.IsNullOrEmpty(forwardedFor) && forwardedFor.Contains(','))
                return true;

            // عدم تطابق Real-IP مع Connection IP
            if (!string.IsNullOrEmpty(realIp) && !string.IsNullOrEmpty(connectionIp) && realIp != connectionIp)
                return true;

            return false;
        }
        catch { return false; }
    }

    // ============================================================
    // استخراج عنوان IP الحقيقي
    // ============================================================
    private string? GetClientIpAddress()
    {
        var forwardedFor = HttpContext.Request.Headers["X-Forwarded-For"].FirstOrDefault();
        if (!string.IsNullOrEmpty(forwardedFor))
            return forwardedFor.Split(',')[0].Trim();

        return HttpContext.Connection.RemoteIpAddress?.ToString();
    }

    /// <summary>تسجيل حضور - محمي بـ 6 طبقات أمنية</summary>
    [HttpPost("checkin")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> CheckIn([FromBody] CheckInRequest request)
    {
        // ── Layer 3: استخراج UserId من التوكن ──
        var tokenUserId = GetAuthenticatedUserId();
        Guid effectiveUserId;

        if (tokenUserId.HasValue)
        {
            effectiveUserId = tokenUserId.Value;
        }
        else if (request.UserId != Guid.Empty)
        {
            effectiveUserId = request.UserId;
            _logger.LogWarning("⚠️ تسجيل حضور بدون JWT UserId - استخدام UserId من الطلب: {UserId}", request.UserId);
        }
        else
        {
            return BadRequest(new { message = "لا يمكن تحديد هوية المستخدم" });
        }

        // ── Rate Limiting: فحص تجاوز المحاولات الفاشلة ──
        var (isLimited, retryAfterSeconds) = await IsRateLimitedAsync(effectiveUserId);
        if (isLimited)
        {
            return BadRequest(new {
                message = $"تجاوزت الحد الأقصى للمحاولات. حاول بعد {retryAfterSeconds / 60} دقائق.",
                code = "RATE_LIMITED",
                retryAfterSeconds
            });
        }

        // جلب بيانات المستخدم
        var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == effectiveUserId);
        var userName = user?.FullName ?? request.UserName ?? "غير معروف";
        var companyId = user?.CompanyId ?? request.CompanyId;

        // ── كشف VPN (soft — تسجيل فقط) ──
        var vpnSuspected = DetectVpnSuspicion();
        var clientIp = GetClientIpAddress();

        // ── Layer 1: التحقق من بصمة الجهاز مع نظام موافقة المدير ──
        if (!string.IsNullOrEmpty(request.DeviceFingerprint) && user != null)
        {
            if (string.IsNullOrEmpty(user.RegisteredDeviceFingerprint))
            {
                // لا يوجد جهاز مسجل — تحقق من حالة الموافقة
                switch (user.DeviceApprovalStatus)
                {
                    case 0: // None — أول طلب: إنشاء طلب معلق
                        user.PendingDeviceFingerprint = request.DeviceFingerprint;
                        user.DeviceApprovalStatus = 1; // Pending
                        _unitOfWork.Users.Update(user);
                        await _unitOfWork.SaveChangesAsync();

                        await LogAuditAsync(effectiveUserId, userName, companyId, "CheckIn", false,
                            "طلب تسجيل جهاز جديد — بانتظار موافقة المدير",
                            request.Latitude, request.Longitude, null, request.CenterName,
                            request.DeviceFingerprint, null, vpnSuspected);

                        _logger.LogInformation("📱 طلب تسجيل جهاز جديد للمستخدم {UserId} ({UserName})", effectiveUserId, userName);
                        return BadRequest(new { message = "تم إرسال طلب تسجيل جهازك للمدير. يرجى الانتظار حتى الموافقة.", code = "DEVICE_PENDING" });

                    case 1: // Pending — لا تزال بانتظار الموافقة
                        // تحديث البصمة في حالة تغير الجهاز أثناء الانتظار
                        if (user.PendingDeviceFingerprint != request.DeviceFingerprint)
                        {
                            user.PendingDeviceFingerprint = request.DeviceFingerprint;
                            _unitOfWork.Users.Update(user);
                            await _unitOfWork.SaveChangesAsync();
                        }
                        await LogAuditAsync(effectiveUserId, userName, companyId, "CheckIn", false,
                            "بانتظار موافقة المدير على الجهاز",
                            request.Latitude, request.Longitude, null, request.CenterName,
                            request.DeviceFingerprint, null, vpnSuspected);
                        return BadRequest(new { message = "جهازك لا يزال بانتظار موافقة المدير.", code = "DEVICE_PENDING" });

                    case 3: // Rejected — تم الرفض
                        await LogAuditAsync(effectiveUserId, userName, companyId, "CheckIn", false,
                            "تم رفض تسجيل الجهاز",
                            request.Latitude, request.Longitude, null, request.CenterName,
                            request.DeviceFingerprint, null, vpnSuspected);
                        return BadRequest(new { message = "تم رفض تسجيل جهازك. تواصل مع المدير.", code = "DEVICE_REJECTED" });

                    // case 2: Approved — يجب ألا يحدث (لأن RegisteredDeviceFingerprint يُملأ عند الموافقة)
                }
            }
            else if (user.RegisteredDeviceFingerprint != request.DeviceFingerprint)
            {
                // الجهاز لا يتطابق مع الجهاز المسجل
                await LogAuditAsync(effectiveUserId, userName, companyId, "CheckIn", false,
                    $"جهاز غير مسجل. المسجل: {user.RegisteredDeviceFingerprint?.Substring(0, Math.Min(8, user.RegisteredDeviceFingerprint.Length))}..., المرسل: {request.DeviceFingerprint?.Substring(0, Math.Min(8, request.DeviceFingerprint.Length))}...",
                    request.Latitude, request.Longitude, null, request.CenterName,
                    request.DeviceFingerprint, user.RegisteredDeviceFingerprint, vpnSuspected);

                return BadRequest(new { message = "لا يمكن تسجيل الحضور من هذا الجهاز. الجهاز غير مسجل لحسابك.", code = "DEVICE_MISMATCH" });
            }
        }

        // ── Layer 2: التحقق من الموقع الجغرافي في السيرفر ──
        double? distanceFromCenter = null;
        if (request.Latitude.HasValue && request.Longitude.HasValue && !string.IsNullOrEmpty(request.CenterName))
        {
            var centers = await _unitOfWork.WorkCenters.AsQueryable()
                .Where(c => c.IsActive && (c.CompanyId == companyId || c.CompanyId == null))
                .ToListAsync();

            var matchedCenter = centers.FirstOrDefault(c =>
                c.Name.Equals(request.CenterName, StringComparison.OrdinalIgnoreCase));

            if (matchedCenter != null)
            {
                distanceFromCenter = CalculateDistanceMeters(
                    request.Latitude.Value, request.Longitude.Value,
                    matchedCenter.Latitude, matchedCenter.Longitude);

                if (distanceFromCenter > matchedCenter.RadiusMeters)
                {
                    await LogAuditAsync(effectiveUserId, userName, companyId, "CheckIn", false,
                        $"خارج النطاق: {distanceFromCenter:F0}م من المركز (الحد: {matchedCenter.RadiusMeters}م)",
                        request.Latitude, request.Longitude, distanceFromCenter, request.CenterName,
                        request.DeviceFingerprint, user?.RegisteredDeviceFingerprint, vpnSuspected);

                    return BadRequest(new {
                        message = $"أنت خارج نطاق المركز المسموح. المسافة: {distanceFromCenter:F0} متر (الحد الأقصى: {matchedCenter.RadiusMeters} متر)",
                        code = "OUT_OF_RANGE",
                        distance = distanceFromCenter,
                        allowedRadius = matchedCenter.RadiusMeters
                    });
                }
            }
        }

        // ── Layer 6: التحقق من كود الأمان ──
        if (user != null && !string.IsNullOrEmpty(user.AttendanceSecurityCode))
        {
            if (string.IsNullOrEmpty(request.SecurityCode) ||
                request.SecurityCode.Trim() != user.AttendanceSecurityCode.Trim())
            {
                await LogAuditAsync(effectiveUserId, userName, companyId, "CheckIn", false,
                    $"كود أمان خاطئ. المرسل: {request.SecurityCode ?? "(فارغ)"}",
                    request.Latitude, request.Longitude, distanceFromCenter, request.CenterName,
                    request.DeviceFingerprint, user.RegisteredDeviceFingerprint, vpnSuspected);

                return BadRequest(new {
                    message = "كود الأمان غير صحيح. تواصل مع المدير للحصول على الكود الصحيح.",
                    code = "INVALID_SECURITY_CODE"
                });
            }
        }

        // ── التحقق من عدم وجود حضور مسجل لنفس اليوم ──
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var existing = await _unitOfWork.AttendanceRecords
            .FirstOrDefaultAsync(a => a.UserId == effectiveUserId && a.Date == today);

        if (existing != null && existing.CheckInTime != null)
        {
            return BadRequest(new { message = "تم تسجيل الحضور مسبقاً لهذا اليوم" });
        }

        var record = existing ?? new AttendanceRecord
        {
            UserId = effectiveUserId,
            UserName = userName,
            CompanyId = companyId,
            Date = today,
        };

        record.CheckInTime = DateTime.UtcNow;
        record.CenterName = request.CenterName;
        record.CheckInLatitude = request.Latitude;
        record.CheckInLongitude = request.Longitude;
        record.SecurityCode = request.SecurityCode;
        record.DeviceFingerprint = request.DeviceFingerprint;
        record.IpAddress = clientIp;

        // ── حساب التأخير تلقائياً من جدول الدوام ──
        var schedule = await FindScheduleAsync(companyId, request.CenterName, today, user);
        if (schedule != null)
        {
            record.WorkScheduleId = schedule.Id;
            record.ExpectedStartTime = schedule.WorkStartTime;
            record.ExpectedEndTime = schedule.WorkEndTime;

            var (status, lateMinutes) = CalculateLateStatus(record.CheckInTime.Value, schedule);
            record.Status = status;
            record.LateMinutes = lateMinutes;
        }

        if (existing == null)
            await _unitOfWork.AttendanceRecords.AddAsync(record);
        else
            _unitOfWork.AttendanceRecords.Update(record);

        await _unitOfWork.SaveChangesAsync();

        // ── Layer 5: تسجيل نجاح العملية ──
        await LogAuditAsync(effectiveUserId, userName, companyId, "CheckIn", true, null,
            request.Latitude, request.Longitude, distanceFromCenter, request.CenterName,
            request.DeviceFingerprint, user?.RegisteredDeviceFingerprint, vpnSuspected);

        _logger.LogInformation("✅ تسجيل حضور: {UserName} في {Center} (مسافة: {Distance}م)",
            userName, request.CenterName, distanceFromCenter?.ToString("F0") ?? "N/A");

        return Ok(new { message = "تم تسجيل الحضور بنجاح", record, vpnWarning = vpnSuspected });
    }

    /// <summary>تسجيل انصراف - محمي بـ 6 طبقات أمنية</summary>
    [HttpPost("checkout")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> CheckOut([FromBody] CheckOutRequest request)
    {
        // ── Layer 3: استخراج UserId من التوكن ──
        var tokenUserId = GetAuthenticatedUserId();
        Guid effectiveUserId;

        if (tokenUserId.HasValue)
        {
            effectiveUserId = tokenUserId.Value;
        }
        else if (request.UserId != Guid.Empty)
        {
            effectiveUserId = request.UserId;
            _logger.LogWarning("⚠️ تسجيل انصراف بدون JWT UserId - استخدام UserId من الطلب: {UserId}", request.UserId);
        }
        else
        {
            return BadRequest(new { message = "لا يمكن تحديد هوية المستخدم" });
        }

        // ── Rate Limiting ──
        var (isLimited, retryAfterSeconds) = await IsRateLimitedAsync(effectiveUserId);
        if (isLimited)
        {
            return BadRequest(new {
                message = $"تجاوزت الحد الأقصى للمحاولات. حاول بعد {retryAfterSeconds / 60} دقائق.",
                code = "RATE_LIMITED",
                retryAfterSeconds
            });
        }

        var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == effectiveUserId);
        var userName = user?.FullName ?? "غير معروف";
        var companyId = user?.CompanyId;
        var vpnSuspected = DetectVpnSuspicion();
        var clientIp = GetClientIpAddress();

        // ── Layer 1: التحقق من بصمة الجهاز ──
        if (!string.IsNullOrEmpty(request.DeviceFingerprint) && user != null &&
            !string.IsNullOrEmpty(user.RegisteredDeviceFingerprint) &&
            user.RegisteredDeviceFingerprint != request.DeviceFingerprint)
        {
            await LogAuditAsync(effectiveUserId, userName, companyId, "CheckOut", false,
                "جهاز غير مسجل", request.Latitude, request.Longitude, null, null,
                request.DeviceFingerprint, user.RegisteredDeviceFingerprint, vpnSuspected);

            return BadRequest(new { message = "لا يمكن تسجيل الانصراف من هذا الجهاز. الجهاز غير مسجل لحسابك.", code = "DEVICE_MISMATCH" });
        }

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var record = await _unitOfWork.AttendanceRecords
            .FirstOrDefaultAsync(a => a.UserId == effectiveUserId && a.Date == today);

        if (record == null)
        {
            return BadRequest(new { message = "لم يتم تسجيل الحضور اليوم" });
        }

        if (record.CheckOutTime != null)
        {
            return BadRequest(new { message = "تم تسجيل الانصراف مسبقاً" });
        }

        // ── Layer 2: التحقق من الموقع الجغرافي ──
        double? distanceFromCenter = null;
        if (request.Latitude.HasValue && request.Longitude.HasValue && !string.IsNullOrEmpty(record.CenterName))
        {
            var centers = await _unitOfWork.WorkCenters.AsQueryable()
                .Where(c => c.IsActive && (c.CompanyId == companyId || c.CompanyId == null))
                .ToListAsync();

            var matchedCenter = centers.FirstOrDefault(c =>
                c.Name.Equals(record.CenterName, StringComparison.OrdinalIgnoreCase));

            if (matchedCenter != null)
            {
                distanceFromCenter = CalculateDistanceMeters(
                    request.Latitude.Value, request.Longitude.Value,
                    matchedCenter.Latitude, matchedCenter.Longitude);

                if (distanceFromCenter > matchedCenter.RadiusMeters)
                {
                    await LogAuditAsync(effectiveUserId, userName, companyId, "CheckOut", false,
                        $"خارج النطاق: {distanceFromCenter:F0}م (الحد: {matchedCenter.RadiusMeters}م)",
                        request.Latitude, request.Longitude, distanceFromCenter, record.CenterName,
                        request.DeviceFingerprint, user?.RegisteredDeviceFingerprint, vpnSuspected);

                    return BadRequest(new {
                        message = $"أنت خارج نطاق المركز المسموح. المسافة: {distanceFromCenter:F0} متر",
                        code = "OUT_OF_RANGE",
                        distance = distanceFromCenter,
                        allowedRadius = matchedCenter.RadiusMeters
                    });
                }
            }
        }

        record.CheckOutTime = DateTime.UtcNow;
        record.CheckOutLatitude = request.Latitude;
        record.CheckOutLongitude = request.Longitude;
        record.Notes = request.Notes;
        record.IpAddress ??= clientIp;
        record.UpdatedAt = DateTime.UtcNow;

        // ── حساب ساعات العمل والوقت الإضافي والانصراف المبكر ──
        if (record.CheckInTime.HasValue)
        {
            WorkSchedule? schedule = null;
            if (record.WorkScheduleId.HasValue)
                schedule = await _unitOfWork.WorkSchedules.GetByIdAsync(record.WorkScheduleId.Value);
            schedule ??= await FindScheduleAsync(companyId, record.CenterName, today, user);

            if (schedule != null)
            {
                var (workedMinutes, overtimeMinutes, earlyDepartureMinutes, statusOverride) =
                    CalculateCheckOutMetrics(record.CheckInTime.Value, record.CheckOutTime.Value, schedule);

                record.WorkedMinutes = workedMinutes;
                record.OvertimeMinutes = overtimeMinutes;
                record.EarlyDepartureMinutes = earlyDepartureMinutes;

                if (statusOverride.HasValue && record.Status != AttendanceStatus.Late)
                    record.Status = statusOverride.Value;
            }
            else
            {
                record.WorkedMinutes = (int)(record.CheckOutTime.Value - record.CheckInTime.Value).TotalMinutes;
            }
        }

        _unitOfWork.AttendanceRecords.Update(record);
        await _unitOfWork.SaveChangesAsync();

        // ── Layer 5: تسجيل نجاح العملية ──
        await LogAuditAsync(effectiveUserId, userName, companyId, "CheckOut", true, null,
            request.Latitude, request.Longitude, distanceFromCenter, record.CenterName,
            request.DeviceFingerprint, user?.RegisteredDeviceFingerprint, vpnSuspected);

        return Ok(new { message = "تم تسجيل الانصراف بنجاح", record, vpnWarning = vpnSuspected });
    }

    /// <summary>جلب سجل الحضور الشهري لموظف</summary>
    [HttpGet("{userId}/monthly")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetMonthlyAttendance(Guid userId, [FromQuery] int? year, [FromQuery] int? month)
    {
        var targetYear = year ?? DateTime.UtcNow.Year;
        var targetMonth = month ?? DateTime.UtcNow.Month;
        var startDate = new DateOnly(targetYear, targetMonth, 1);
        var endDate = startDate.AddMonths(1).AddDays(-1);

        var records = await _unitOfWork.AttendanceRecords
            .AsQueryable()
            .Where(a => a.UserId == userId && a.Date >= startDate && a.Date <= endDate)
            .OrderBy(a => a.Date)
            .ToListAsync();

        return Ok(new
        {
            userId,
            year = targetYear,
            month = targetMonth,
            totalDays = records.Count,
            lateDays = records.Count(r => r.Status == AttendanceStatus.Late),
            totalLateMinutes = records.Sum(r => r.LateMinutes ?? 0),
            totalOvertimeMinutes = records.Sum(r => r.OvertimeMinutes ?? 0),
            totalWorkedMinutes = records.Sum(r => r.WorkedMinutes ?? 0),
            records = records.Select(r => new
            {
                r.Id,
                date = r.Date.ToString("yyyy-MM-dd"),
                checkInTime = r.CheckInTime?.ToString("HH:mm:ss"),
                checkOutTime = r.CheckOutTime?.ToString("HH:mm:ss"),
                r.CenterName,
                r.SecurityCode,
                r.Notes,
                status = r.Status.ToString(),
                r.LateMinutes,
                r.OvertimeMinutes,
                r.WorkedMinutes,
                r.EarlyDepartureMinutes,
                expectedStartTime = r.ExpectedStartTime?.ToString("HH:mm"),
                expectedEndTime = r.ExpectedEndTime?.ToString("HH:mm"),
            })
        });
    }

    /// <summary>جلب حضور جميع الموظفين لتاريخ معين</summary>
    [HttpGet("daily")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetDailyAttendance([FromQuery] string? date, [FromQuery] Guid? companyId)
    {
        var targetDate = string.IsNullOrEmpty(date) 
            ? DateOnly.FromDateTime(DateTime.UtcNow) 
            : DateOnly.Parse(date);

        var query = _unitOfWork.AttendanceRecords.AsQueryable()
            .Where(a => a.Date == targetDate);

        if (companyId.HasValue)
            query = query.Where(a => a.CompanyId == companyId.Value);

        var records = await query.OrderBy(a => a.UserName).ToListAsync();

        return Ok(records);
    }

    /// <summary>جلب مراكز العمل</summary>
    [HttpGet("centers")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetCenters([FromQuery] Guid? companyId)
    {
        var query = _unitOfWork.WorkCenters.AsQueryable();
        
        if (companyId.HasValue)
            query = query.Where(c => c.CompanyId == companyId.Value);

        var centers = await query.Where(c => c.IsActive).ToListAsync();
        return Ok(centers);
    }

    /// <summary>إضافة مركز عمل</summary>
    [HttpPost("centers")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> AddCenter([FromBody] AddCenterRequest request)
    {
        var center = new WorkCenter
        {
            Name = request.Name,
            Latitude = request.Latitude,
            Longitude = request.Longitude,
            RadiusMeters = request.RadiusMeters ?? 200,
            CompanyId = request.CompanyId,
        };

        await _unitOfWork.WorkCenters.AddAsync(center);
        await _unitOfWork.SaveChangesAsync();

        return Ok(center);
    }

    // ============================================================
    //  جدول الدوام (WorkSchedule) CRUD
    // ============================================================

    /// <summary>جلب جداول الدوام</summary>
    [HttpGet("schedules")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetSchedules([FromQuery] Guid? companyId)
    {
        var query = _unitOfWork.WorkSchedules.AsQueryable().Where(s => s.IsActive);
        if (companyId.HasValue)
            query = query.Where(s => s.CompanyId == companyId.Value || s.CompanyId == null);

        var schedules = await query.OrderBy(s => s.Name).ThenBy(s => s.DayOfWeek).ToListAsync();
        return Ok(schedules);
    }

    /// <summary>إضافة جدول دوام</summary>
    [HttpPost("schedules")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> AddSchedule([FromBody] AddScheduleRequest request)
    {
        var schedule = new WorkSchedule
        {
            Name = request.Name,
            CompanyId = request.CompanyId,
            CenterName = request.CenterName,
            DayOfWeek = request.DayOfWeek,
            WorkStartTime = TimeOnly.Parse(request.WorkStartTime),
            WorkEndTime = TimeOnly.Parse(request.WorkEndTime),
            LateGraceMinutes = request.LateGraceMinutes ?? 15,
            EarlyDepartureThresholdMinutes = request.EarlyDepartureThresholdMinutes ?? 15,
            IsDefault = request.IsDefault ?? false,
            IsActive = true,
        };

        await _unitOfWork.WorkSchedules.AddAsync(schedule);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("📅 تم إنشاء جدول دوام: {Name} ({Start}-{End})",
            schedule.Name, schedule.WorkStartTime, schedule.WorkEndTime);

        return Ok(schedule);
    }

    /// <summary>تعديل جدول دوام</summary>
    [HttpPut("schedules/{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> UpdateSchedule(int id, [FromBody] AddScheduleRequest request)
    {
        var schedule = await _unitOfWork.WorkSchedules.GetByIdAsync(id);
        if (schedule == null) return NotFound(new { message = "جدول الدوام غير موجود" });

        schedule.Name = request.Name;
        schedule.CompanyId = request.CompanyId;
        schedule.CenterName = request.CenterName;
        schedule.DayOfWeek = request.DayOfWeek;
        schedule.WorkStartTime = TimeOnly.Parse(request.WorkStartTime);
        schedule.WorkEndTime = TimeOnly.Parse(request.WorkEndTime);
        schedule.LateGraceMinutes = request.LateGraceMinutes ?? 15;
        schedule.EarlyDepartureThresholdMinutes = request.EarlyDepartureThresholdMinutes ?? 15;
        schedule.IsDefault = request.IsDefault ?? schedule.IsDefault;
        schedule.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.WorkSchedules.Update(schedule);
        await _unitOfWork.SaveChangesAsync();

        return Ok(schedule);
    }

    /// <summary>حذف ناعم لجدول دوام</summary>
    [HttpDelete("schedules/{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> DeleteSchedule(int id)
    {
        var schedule = await _unitOfWork.WorkSchedules.GetByIdAsync(id);
        if (schedule == null) return NotFound(new { message = "جدول الدوام غير موجود" });

        schedule.IsDeleted = true;
        schedule.DeletedAt = DateTime.UtcNow;
        _unitOfWork.WorkSchedules.Update(schedule);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { message = "تم حذف جدول الدوام" });
    }

    // ============================================================
    //  البحث عن جدول الدوام المناسب ليوم وشركة/مركز
    //  الأولوية: وقت خاص بالموظف → جدول مربوط بالموظف → مركز+يوم → مركز+عام → شركة+يوم → شركة افتراضي
    // ============================================================
    private async Task<WorkSchedule?> FindScheduleAsync(Guid? companyId, string? centerName, DateOnly date, User? user = null)
    {
        // ══ الأولوية 1: وقت دوام خاص بالموظف ══
        if (user != null && user.CustomWorkStartTime.HasValue && user.CustomWorkEndTime.HasValue)
        {
            // إنشاء جدول مؤقت (بدون حفظه في DB) يمثل وقت الموظف الخاص
            return new WorkSchedule
            {
                Id = -1, // معرف مؤقت
                Name = "وقت خاص - " + (user.FullName ?? ""),
                CompanyId = companyId,
                WorkStartTime = user.CustomWorkStartTime.Value,
                WorkEndTime = user.CustomWorkEndTime.Value,
                LateGraceMinutes = 15,
                EarlyDepartureThresholdMinutes = 15,
                IsDefault = false,
                IsActive = true,
            };
        }

        // ══ الأولوية 2: جدول دوام مربوط بالموظف ══
        if (user != null && user.WorkScheduleId.HasValue)
        {
            var userSchedule = await _unitOfWork.WorkSchedules.GetByIdAsync(user.WorkScheduleId.Value);
            if (userSchedule != null && userSchedule.IsActive)
                return userSchedule;
        }

        // ══ الأولوية 3-6: البحث بالمركز/الشركة (النظام الأصلي) ══
        var dayOfWeek = (int)date.DayOfWeek; // 0=Sunday .. 6=Saturday

        var schedules = await _unitOfWork.WorkSchedules.AsQueryable()
            .Where(s => s.IsActive && (s.CompanyId == companyId || s.CompanyId == null))
            .ToListAsync();

        // الأولوية 3: مركز + يوم محدد
        var match = schedules
            .Where(s => !string.IsNullOrEmpty(centerName) &&
                        string.Equals(s.CenterName, centerName, StringComparison.OrdinalIgnoreCase) &&
                        s.DayOfWeek == dayOfWeek)
            .FirstOrDefault();

        // الأولوية 4: مركز + يوم عام
        match ??= schedules
            .Where(s => !string.IsNullOrEmpty(centerName) &&
                        string.Equals(s.CenterName, centerName, StringComparison.OrdinalIgnoreCase) &&
                        s.DayOfWeek == null)
            .FirstOrDefault();

        // الأولوية 5: شركة + يوم محدد
        match ??= schedules
            .Where(s => string.IsNullOrEmpty(s.CenterName) && s.DayOfWeek == dayOfWeek)
            .FirstOrDefault();

        // الأولوية 6: شركة افتراضي
        match ??= schedules
            .Where(s => string.IsNullOrEmpty(s.CenterName) && s.DayOfWeek == null && s.IsDefault)
            .FirstOrDefault();

        return match;
    }

    // ============================================================
    //  حساب التأخير عند الحضور
    // ============================================================
    private static (AttendanceStatus status, int lateMinutes) CalculateLateStatus(
        DateTime checkInTime, WorkSchedule schedule)
    {
        var checkInTimeOnly = TimeOnly.FromDateTime(checkInTime);
        var expectedStart = schedule.WorkStartTime;
        var graceEnd = expectedStart.AddMinutes(schedule.LateGraceMinutes);

        if (checkInTimeOnly <= graceEnd)
            return (AttendanceStatus.Present, 0);

        var lateMinutes = (int)(checkInTimeOnly - expectedStart).TotalMinutes;
        return (AttendanceStatus.Late, Math.Max(0, lateMinutes));
    }

    // ============================================================
    //  حساب الوقت الإضافي والانصراف المبكر عند الانصراف
    // ============================================================
    private static (int workedMinutes, int overtimeMinutes, int earlyDepartureMinutes, AttendanceStatus? statusOverride) 
        CalculateCheckOutMetrics(DateTime checkInTime, DateTime checkOutTime, WorkSchedule schedule)
    {
        var workedMinutes = (int)(checkOutTime - checkInTime).TotalMinutes;
        var checkOutTimeOnly = TimeOnly.FromDateTime(checkOutTime);
        var expectedEnd = schedule.WorkEndTime;

        int overtimeMinutes = 0;
        int earlyDepartureMinutes = 0;
        AttendanceStatus? statusOverride = null;

        if (checkOutTimeOnly > expectedEnd)
        {
            overtimeMinutes = (int)(checkOutTimeOnly - expectedEnd).TotalMinutes;
        }
        else if (checkOutTimeOnly < expectedEnd)
        {
            earlyDepartureMinutes = (int)(expectedEnd - checkOutTimeOnly).TotalMinutes;
            if (earlyDepartureMinutes >= schedule.EarlyDepartureThresholdMinutes)
            {
                // إذا عمل أقل من نصف الوقت المتوقع → نصف يوم
                var expectedWorkedMinutes = (int)(schedule.WorkEndTime - schedule.WorkStartTime).TotalMinutes;
                if (workedMinutes < expectedWorkedMinutes / 2)
                    statusOverride = AttendanceStatus.HalfDay;
                else
                    statusOverride = AttendanceStatus.EarlyDeparture;
            }
        }

        return (workedMinutes, overtimeMinutes, earlyDepartureMinutes, statusOverride);
    }

    /// <summary>سجل تدقيق محاولات الحضور (للمديرين)</summary>
    [HttpGet("audit-logs")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetAuditLogs(
        [FromQuery] Guid? userId, [FromQuery] string? date, 
        [FromQuery] bool? failedOnly, [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
    {
        var query = _unitOfWork.AttendanceAuditLogs.AsQueryable();

        if (userId.HasValue)
            query = query.Where(a => a.UserId == userId.Value);

        if (!string.IsNullOrEmpty(date))
        {
            var targetDate = DateOnly.Parse(date);
            query = query.Where(a => DateOnly.FromDateTime(a.AttemptTime) == targetDate);
        }

        if (failedOnly == true)
            query = query.Where(a => !a.IsSuccess);

        var total = await query.CountAsync();
        var logs = await query
            .OrderByDescending(a => a.AttemptTime)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return Ok(new { total, page, pageSize, logs });
    }

    // ============================================================
    //  تعديل سجل حضور (للمديرين)
    // ============================================================

    /// <summary>تعديل سجل حضور موظف</summary>
    [HttpPut("records/{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> UpdateAttendanceRecord(long id, [FromBody] UpdateAttendanceRequest request)
    {
        try
        {
            var record = await _unitOfWork.AttendanceRecords.FirstOrDefaultAsync(r => r.Id == id);
            if (record == null)
                return NotFound(new { success = false, message = "سجل الحضور غير موجود" });

            // تحديث الحقول
            if (request.Status.HasValue)
                record.Status = request.Status.Value;

            if (!string.IsNullOrEmpty(request.CheckInTime))
            {
                var parts = request.CheckInTime.Split(':');
                record.CheckInTime = DateTime.SpecifyKind(record.Date.ToDateTime(new TimeOnly(int.Parse(parts[0]), int.Parse(parts[1]))), DateTimeKind.Utc);
            }
            else if (request.ClearCheckIn == true)
                record.CheckInTime = null;

            if (!string.IsNullOrEmpty(request.CheckOutTime))
            {
                var parts = request.CheckOutTime.Split(':');
                record.CheckOutTime = DateTime.SpecifyKind(record.Date.ToDateTime(new TimeOnly(int.Parse(parts[0]), int.Parse(parts[1]))), DateTimeKind.Utc);
            }
            else if (request.ClearCheckOut == true)
                record.CheckOutTime = null;

            if (request.LateMinutes.HasValue)
                record.LateMinutes = request.LateMinutes.Value;
            if (request.OvertimeMinutes.HasValue)
                record.OvertimeMinutes = request.OvertimeMinutes.Value;
            if (request.EarlyDepartureMinutes.HasValue)
                record.EarlyDepartureMinutes = request.EarlyDepartureMinutes.Value;
            if (request.Notes != null)
                record.Notes = request.Notes;

            // إعادة حساب دقائق العمل إذا تغير وقت الدخول أو الخروج
            if (record.CheckInTime.HasValue && record.CheckOutTime.HasValue)
            {
                record.WorkedMinutes = (int)(record.CheckOutTime.Value - record.CheckInTime.Value).TotalMinutes;
                if (record.WorkedMinutes < 0) record.WorkedMinutes = 0;
            }
            else
            {
                record.WorkedMinutes = 0;
            }

            record.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.AttendanceRecords.Update(record);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("📝 تم تعديل سجل حضور #{Id} للموظف {UserName} بتاريخ {Date}",
                id, record.UserName, record.Date);

            return Ok(new
            {
                success = true,
                message = $"تم تعديل سجل حضور {record.UserName} بتاريخ {record.Date}",
                record = new
                {
                    record.Id,
                    Date = record.Date.ToString("yyyy-MM-dd"),
                    CheckIn = record.CheckInTime?.ToString("HH:mm"),
                    CheckOut = record.CheckOutTime?.ToString("HH:mm"),
                    Status = record.Status.ToString(),
                    record.LateMinutes,
                    record.OvertimeMinutes,
                    record.WorkedMinutes,
                    record.EarlyDepartureMinutes,
                    record.Notes
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل سجل الحضور #{Id}", id);
            return StatusCode(500, new { success = false, message = "خطأ داخلي في الخادم" });
        }
    }

    /// <summary>إنشاء سجل حضور يدوي (للمديرين)</summary>
    [HttpPost("records")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> CreateAttendanceRecord([FromBody] CreateAttendanceRecordRequest request)
    {
        try
        {
            var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == request.UserId);
            if (user == null)
                return NotFound(new { success = false, message = "الموظف غير موجود" });

            // التحقق من عدم وجود سجل لهذا اليوم
            var date = DateOnly.Parse(request.Date);
            var existing = await _unitOfWork.AttendanceRecords.FirstOrDefaultAsync(
                r => r.UserId == request.UserId && r.Date == date);
            if (existing != null)
                return BadRequest(new { success = false, message = "يوجد سجل حضور لهذا اليوم بالفعل. استخدم التعديل بدلاً من الإنشاء." });

            var record = new AttendanceRecord
            {
                UserId = request.UserId,
                UserName = user.FullName,
                CompanyId = user.CompanyId,
                Date = date,
                Status = request.Status,
                Notes = request.Notes ?? "سجل يدوي",
                CreatedAt = DateTime.UtcNow
            };

            if (!string.IsNullOrEmpty(request.CheckInTime))
            {
                var timeParts = request.CheckInTime.Split(':');
                record.CheckInTime = DateTime.SpecifyKind(date.ToDateTime(new TimeOnly(int.Parse(timeParts[0]), int.Parse(timeParts[1]))), DateTimeKind.Utc);
            }
            if (!string.IsNullOrEmpty(request.CheckOutTime))
            {
                var timeParts = request.CheckOutTime.Split(':');
                record.CheckOutTime = DateTime.SpecifyKind(date.ToDateTime(new TimeOnly(int.Parse(timeParts[0]), int.Parse(timeParts[1]))), DateTimeKind.Utc);
            }

            if (record.CheckInTime.HasValue && record.CheckOutTime.HasValue)
                record.WorkedMinutes = (int)(record.CheckOutTime.Value - record.CheckInTime.Value).TotalMinutes;

            record.LateMinutes = request.LateMinutes ?? 0;
            record.OvertimeMinutes = request.OvertimeMinutes ?? 0;
            record.EarlyDepartureMinutes = request.EarlyDepartureMinutes ?? 0;

            await _unitOfWork.AttendanceRecords.AddAsync(record);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("➕ تم إنشاء سجل حضور يدوي للموظف {UserName} بتاريخ {Date}",
                user.FullName, date);

            return Ok(new
            {
                success = true,
                message = $"تم إنشاء سجل حضور {user.FullName} بتاريخ {date}",
                record = new
                {
                    record.Id,
                    Date = record.Date.ToString("yyyy-MM-dd"),
                    CheckIn = record.CheckInTime?.ToString("HH:mm"),
                    CheckOut = record.CheckOutTime?.ToString("HH:mm"),
                    Status = record.Status.ToString(),
                    record.LateMinutes,
                    record.OvertimeMinutes,
                    record.WorkedMinutes,
                    record.EarlyDepartureMinutes,
                    record.Notes
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء سجل حضور يدوي");
            return StatusCode(500, new { success = false, message = "خطأ داخلي في الخادم" });
        }
    }

    /// <summary>حذف سجل حضور (للمديرين)</summary>
    [HttpDelete("records/{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> DeleteAttendanceRecord(long id)
    {
        try
        {
            var record = await _unitOfWork.AttendanceRecords.FirstOrDefaultAsync(r => r.Id == id);
            if (record == null)
                return NotFound(new { success = false, message = "سجل الحضور غير موجود" });

            record.IsDeleted = true;
            record.DeletedAt = DateTime.UtcNow;
            _unitOfWork.AttendanceRecords.Update(record);
            await _unitOfWork.SaveChangesAsync();

            _logger.LogInformation("🗑️ تم حذف سجل حضور #{Id} للموظف {UserName} بتاريخ {Date}",
                id, record.UserName, record.Date);

            return Ok(new { success = true, message = $"تم حذف سجل حضور {record.UserName} بتاريخ {record.Date}" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف سجل الحضور #{Id}", id);
            return StatusCode(500, new { success = false, message = "خطأ داخلي في الخادم" });
        }
    }

    /// <summary>إعادة تعيين بصمة الجهاز لموظف (للمديرين)</summary>
    [HttpPost("reset-device/{userId}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> ResetDeviceFingerprint(Guid userId)
    {
        var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user == null)
            return NotFound(new { message = "المستخدم غير موجود" });

        var oldFingerprint = user.RegisteredDeviceFingerprint;
        user.RegisteredDeviceFingerprint = null;
        user.PendingDeviceFingerprint = null;
        user.DeviceApprovalStatus = 0; // None
        user.DeviceApprovedByUserId = null;
        user.DeviceApprovedAt = null;
        _unitOfWork.Users.Update(user);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("🔓 تم إعادة تعيين بصمة الجهاز للمستخدم {UserId} ({UserName}). القديمة: {Old}",
            userId, user.FullName, oldFingerprint);

        return Ok(new { message = $"تم إعادة تعيين بصمة الجهاز للموظف {user.FullName}. سيحتاج موافقة المدير عند تسجيل جهاز جديد." });
    }

    // ============================================================
    //  نظام موافقة المدير على الأجهزة
    // ============================================================

    /// <summary>جلب طلبات الأجهزة المعلقة</summary>
    [HttpGet("pending-devices")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetPendingDevices([FromQuery] Guid? companyId)
    {
        var query = _unitOfWork.Users.AsQueryable()
            .Where(u => u.DeviceApprovalStatus == 1); // Pending

        if (companyId.HasValue)
            query = query.Where(u => u.CompanyId == companyId.Value);

        var pending = await query
            .OrderByDescending(u => u.UpdatedAt)
            .Select(u => new {
                u.Id,
                u.FullName,
                u.PhoneNumber,
                u.Center,
                u.Department,
                u.CompanyId,
                pendingFingerprint = u.PendingDeviceFingerprint != null ? u.PendingDeviceFingerprint.Substring(0, Math.Min(16, u.PendingDeviceFingerprint.Length)) + "..." : null,
                requestedAt = u.UpdatedAt
            })
            .ToListAsync();

        return Ok(new { count = pending.Count, devices = pending });
    }

    /// <summary>الموافقة على جهاز موظف</summary>
    [HttpPost("approve-device/{userId}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> ApproveDevice(Guid userId)
    {
        var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user == null)
            return NotFound(new { message = "المستخدم غير موجود" });

        if (user.DeviceApprovalStatus != 1)
            return BadRequest(new { message = "لا يوجد طلب معلق لهذا الموظف" });

        var adminUserId = GetAuthenticatedUserId();

        // نقل البصمة المعلقة إلى المسجلة
        user.RegisteredDeviceFingerprint = user.PendingDeviceFingerprint;
        user.PendingDeviceFingerprint = null;
        user.DeviceApprovalStatus = 2; // Approved
        user.DeviceApprovedByUserId = adminUserId;
        user.DeviceApprovedAt = DateTime.UtcNow;
        user.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(user);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("✅ تمت الموافقة على جهاز الموظف {UserName} ({UserId}) بواسطة المدير {AdminId}",
            user.FullName, userId, adminUserId);

        return Ok(new { message = $"تمت الموافقة على جهاز {user.FullName}" });
    }

    /// <summary>رفض جهاز موظف</summary>
    [HttpPost("reject-device/{userId}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> RejectDevice(Guid userId)
    {
        var user = await _unitOfWork.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user == null)
            return NotFound(new { message = "المستخدم غير موجود" });

        if (user.DeviceApprovalStatus != 1)
            return BadRequest(new { message = "لا يوجد طلب معلق لهذا الموظف" });

        user.PendingDeviceFingerprint = null;
        user.DeviceApprovalStatus = 3; // Rejected
        user.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Users.Update(user);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("❌ تم رفض جهاز الموظف {UserName} ({UserId})", user.FullName, userId);

        return Ok(new { message = $"تم رفض جهاز {user.FullName}" });
    }

    // ============================================================
    //  صور السيلفي عند البصمة
    // ============================================================

    /// <summary>رفع صورة سيلفي للحضور/الانصراف</summary>
    [HttpPost("upload-photo")]
    [Authorize(Policy = "Admin")]
    [RequestSizeLimit(5 * 1024 * 1024)] // 5MB max
    public async Task<IActionResult> UploadAttendancePhoto(
        [FromQuery] Guid userId, [FromQuery] string type, IFormFile photo)
    {
        if (photo == null || photo.Length == 0)
            return BadRequest(new { message = "لم يتم إرسال صورة" });

        if (type != "checkin" && type != "checkout")
            return BadRequest(new { message = "نوع الصورة غير صالح. استخدم checkin أو checkout" });

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var record = await _unitOfWork.AttendanceRecords
            .FirstOrDefaultAsync(a => a.UserId == userId && a.Date == today);

        if (record == null)
            return NotFound(new { message = "لا يوجد سجل حضور لهذا اليوم" });

        // حفظ الصورة في مجلد على السيرفر
        var photoDir = Path.Combine("/var/www/sadara-api/attendance-photos", userId.ToString());
        Directory.CreateDirectory(photoDir);

        var fileName = $"{today:yyyy-MM-dd}-{type}.jpg";
        var filePath = Path.Combine(photoDir, fileName);

        using (var stream = new FileStream(filePath, FileMode.Create))
        {
            await photo.CopyToAsync(stream);
        }

        // تحديث السجل بمسار الصورة
        if (type == "checkin")
            record.CheckInPhotoPath = filePath;
        else
            record.CheckOutPhotoPath = filePath;

        record.UpdatedAt = DateTime.UtcNow;
        _unitOfWork.AttendanceRecords.Update(record);
        await _unitOfWork.SaveChangesAsync();

        _logger.LogInformation("📸 تم رفع صورة {Type} للموظف {UserId} بتاريخ {Date}", type, userId, today);

        return Ok(new { message = "تم رفع الصورة بنجاح", path = filePath });
    }

    /// <summary>جلب صورة سيلفي لسجل حضور</summary>
    [HttpGet("photo/{recordId}/{type}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetAttendancePhoto(long recordId, string type)
    {
        var record = await _unitOfWork.AttendanceRecords.FirstOrDefaultAsync(r => r.Id == recordId);
        if (record == null)
            return NotFound(new { message = "سجل الحضور غير موجود" });

        var photoPath = type == "checkin" ? record.CheckInPhotoPath : record.CheckOutPhotoPath;
        if (string.IsNullOrEmpty(photoPath) || !System.IO.File.Exists(photoPath))
            return NotFound(new { message = "لا توجد صورة" });

        var bytes = await System.IO.File.ReadAllBytesAsync(photoPath);
        return File(bytes, "image/jpeg");
    }
}

// حاوية أسماء JWT المسجلة (لتجنب الاعتماد على حزمة إضافية)
internal static class JwtRegisteredClaimNames
{
    public const string Sub = "sub";
}

// DTOs
public record CheckInRequest(Guid UserId, string? UserName, Guid? CompanyId, string? CenterName, 
    double? Latitude, double? Longitude, string? SecurityCode, string? DeviceFingerprint);

public record CheckOutRequest(Guid UserId, double? Latitude, double? Longitude, string? Notes, string? DeviceFingerprint);

public record AddCenterRequest(string Name, double Latitude, double Longitude, double? RadiusMeters, Guid? CompanyId);

public record AddScheduleRequest(
    string Name, 
    Guid? CompanyId, 
    string? CenterName, 
    int? DayOfWeek,
    string WorkStartTime,   // "HH:mm" format
    string WorkEndTime,     // "HH:mm" format
    int? LateGraceMinutes, 
    int? EarlyDepartureThresholdMinutes, 
    bool? IsDefault);

public record UpdateAttendanceRequest(
    AttendanceStatus? Status,
    string? CheckInTime,    // "HH:mm" format
    string? CheckOutTime,   // "HH:mm" format
    bool? ClearCheckIn,
    bool? ClearCheckOut,
    int? LateMinutes,
    int? OvertimeMinutes,
    int? EarlyDepartureMinutes,
    string? Notes);

public record CreateAttendanceRecordRequest(
    Guid UserId,
    string Date,           // "yyyy-MM-dd" format
    AttendanceStatus Status,
    string? CheckInTime,   // "HH:mm" format
    string? CheckOutTime,  // "HH:mm" format
    int? LateMinutes,
    int? OvertimeMinutes,
    int? EarlyDepartureMinutes,
    string? Notes);
