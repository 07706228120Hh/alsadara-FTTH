using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;
using Sadara.Infrastructure.Data;

namespace Sadara.API.Controllers;

/// <summary>
/// إدارة إعدادات مزامنة FTTH للشركات
/// يستخدم API Key للمصادقة (نفس نمط InternalDataController)
/// </summary>
[ApiController]
[Route("api/company-ftth-settings")]
[Produces("application/json")]
public class CompanyFtthSettingsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly IConfiguration _configuration;
    private readonly SadaraDbContext _context;
    private readonly ILogger<CompanyFtthSettingsController> _logger;

    public CompanyFtthSettingsController(
        IUnitOfWork unitOfWork,
        IConfiguration configuration,
        SadaraDbContext context,
        ILogger<CompanyFtthSettingsController> logger)
    {
        _unitOfWork = unitOfWork;
        _configuration = configuration;
        _context = context;
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

    /// <summary>جلب إعدادات FTTH للشركة</summary>
    [HttpGet("{companyId}")]
    public async Task<IActionResult> GetSettings(Guid companyId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var settings = await _unitOfWork.CompanyFtthSettings.AsQueryable()
            .FirstOrDefaultAsync(x => x.CompanyId == companyId);

        if (settings == null)
        {
            // ApiClient يفك الـ wrapper ويُعيد data — لذا نضع exists في data
            return Ok(new { success = true, data = new { exists = false } });
        }

        // ApiClient يفك الـ wrapper: { success, data } → يُعيد data فقط
        // Flutter يتوقع camelCase + exists=true
        return Ok(new
        {
            success = true,
            data = new
            {
                exists = true,
                id = settings.Id,
                companyId = settings.CompanyId,
                ftthUsername = settings.FtthUsername,
                ftthPassword = settings.FtthPassword, // Flutter يحتاجها لإعادة عرضها
                syncIntervalMinutes = settings.SyncIntervalMinutes,
                isAutoSyncEnabled = settings.IsAutoSyncEnabled,
                syncStartHour = settings.SyncStartHour,
                syncEndHour = settings.SyncEndHour,
                lastSyncAt = settings.LastSyncAt,
                lastSyncError = settings.LastSyncError,
                isSyncInProgress = settings.IsSyncInProgress,
                currentDbCount = settings.CurrentDbCount,
                consecutiveFailures = settings.ConsecutiveFailures,
            }
        });
    }

    /// <summary>حفظ إعدادات FTTH</summary>
    [HttpPost]
    public async Task<IActionResult> SaveSettings([FromBody] SaveFtthSettingsRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        if (string.IsNullOrEmpty(request.FtthUsername) || string.IsNullOrEmpty(request.FtthPassword))
            return BadRequest(new { success = false, message = "اسم المستخدم وكلمة المرور مطلوبان" });

        var existing = await _unitOfWork.CompanyFtthSettings.AsQueryable()
            .FirstOrDefaultAsync(x => x.CompanyId == request.CompanyId);

        if (existing != null)
        {
            existing.FtthUsername = request.FtthUsername;
            existing.FtthPassword = request.FtthPassword;
            existing.SyncIntervalMinutes = request.SyncIntervalMinutes;
            existing.IsAutoSyncEnabled = request.IsAutoSyncEnabled;
            existing.SyncStartHour = request.SyncStartHour;
            existing.SyncEndHour = request.SyncEndHour;
            existing.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.CompanyFtthSettings.Update(existing);
        }
        else
        {
            var settings = new CompanyFtthSettings
            {
                Id = Guid.NewGuid(),
                CompanyId = request.CompanyId,
                FtthUsername = request.FtthUsername,
                FtthPassword = request.FtthPassword,
                SyncIntervalMinutes = request.SyncIntervalMinutes,
                IsAutoSyncEnabled = request.IsAutoSyncEnabled,
                SyncStartHour = request.SyncStartHour,
                SyncEndHour = request.SyncEndHour,
            };
            await _unitOfWork.CompanyFtthSettings.AddAsync(settings);
        }

        await _unitOfWork.SaveChangesAsync();
        return Ok(new { success = true, message = "تم حفظ الإعدادات بنجاح" });
    }

    /// <summary>اختبار اتصال FTTH</summary>
    [HttpPost("{companyId}/test")]
    public async Task<IActionResult> TestConnection(Guid companyId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var settings = await _unitOfWork.CompanyFtthSettings.AsQueryable()
            .FirstOrDefaultAsync(x => x.CompanyId == companyId);

        if (settings == null)
            return NotFound(new { success = false, message = "لم يتم إعداد FTTH بعد" });

        try
        {
            using var httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };

            // FTTH WAF يتطلب هذه الـ headers — بدونها يرفض بـ 418
            httpClient.DefaultRequestHeaders.Add("Origin", "https://admin.ftth.iq");
            httpClient.DefaultRequestHeaders.Add("Referer", "https://admin.ftth.iq/");
            httpClient.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
            httpClient.DefaultRequestHeaders.Add("x-client-app", "53d57a7f-3f89-4e9d-873b-3d071bc6dd9f");
            httpClient.DefaultRequestHeaders.Add("x-user-role", "0");

            var content = new FormUrlEncodedContent(new[]
            {
                new KeyValuePair<string, string>("username", settings.FtthUsername),
                new KeyValuePair<string, string>("password", settings.FtthPassword),
                new KeyValuePair<string, string>("grant_type", "password"),
                new KeyValuePair<string, string>("scope", "openid profile"),
            });

            var response = await httpClient.PostAsync(
                "https://admin.ftth.iq/api/auth/Contractor/token", content);

            if (response.IsSuccessStatusCode)
            {
                // جلب عدد المشتركين لعرضه في الواجهة
                int totalSubscribers = 0;
                try
                {
                    var json = await response.Content.ReadAsStringAsync();
                    var tokenDoc = System.Text.Json.JsonDocument.Parse(json);
                    var accessToken = tokenDoc.RootElement.GetProperty("access_token").GetString();

                    using var countClient = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
                    countClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {accessToken}");
                    countClient.DefaultRequestHeaders.Add("Origin", "https://admin.ftth.iq");
                    countClient.DefaultRequestHeaders.Add("Referer", "https://admin.ftth.iq/");
                    countClient.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
                    countClient.DefaultRequestHeaders.Add("x-client-app", "53d57a7f-3f89-4e9d-873b-3d071bc6dd9f");
                    countClient.DefaultRequestHeaders.Add("x-user-role", "0");

                    var subRes = await countClient.GetStringAsync(
                        "https://admin.ftth.iq/api/subscriptions?pageNumber=1&pageSize=1&hierarchyLevel=0");
                    var subDoc = System.Text.Json.JsonDocument.Parse(subRes);
                    if (subDoc.RootElement.TryGetProperty("totalCount", out var tc))
                        totalSubscribers = tc.GetInt32();
                }
                catch { /* تجاهل — العدد اختياري */ }

                return Ok(new { success = true, data = new { success = true, message = "الاتصال ناجح", totalSubscribers } });
            }

            return Ok(new
            {
                success = false,
                message = $"فشل الاتصال: {response.StatusCode}",
                statusCode = (int)response.StatusCode
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "FTTH connection test failed for company {CompanyId}", companyId);
            return Ok(new { success = false, message = $"فشل الاتصال: {ex.Message}" });
        }
    }

    /// <summary>جلب حالة المزامنة</summary>
    [HttpGet("{companyId}/sync-status")]
    public async Task<IActionResult> GetSyncStatus(Guid companyId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var settings = await _unitOfWork.CompanyFtthSettings.AsQueryable()
            .FirstOrDefaultAsync(x => x.CompanyId == companyId);

        if (settings == null)
        {
            // sync-status: Flutter يقرأ من body مباشرة (بدون data wrapper)
            // لأن ApiClient يفك success+data wrapper
            // لكن هنا لا يوجد data — Flutter يقرأ body كاملاً
            return Ok(new
            {
                success = true,
                data = new
                {
                    configured = false,
                    currentDbCount = 0,
                    lastSyncAt = (DateTime?)null,
                    isSyncInProgress = false,
                    consecutiveFailures = 0,
                }
            });
        }

        return Ok(new
        {
            success = true,
            data = new
            {
                configured = true,
                currentDbCount = settings.CurrentDbCount,
                lastSyncAt = settings.LastSyncAt,
                lastSyncError = settings.LastSyncError,
                isSyncInProgress = settings.IsSyncInProgress,
                consecutiveFailures = settings.ConsecutiveFailures,
                // تقدم المزامنة الحالية
                syncStage = settings.SyncStage,
                syncProgress = settings.SyncProgress,
                syncMessage = settings.SyncMessage,
                syncFetchedCount = settings.SyncFetchedCount,
                syncTotalCount = settings.SyncTotalCount,
            }
        });
    }

    /// <summary>تشغيل مزامنة يدوية</summary>
    [HttpPost("{companyId}/trigger-sync")]
    public async Task<IActionResult> TriggerSync(Guid companyId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var settings = await _unitOfWork.CompanyFtthSettings.AsQueryable()
            .FirstOrDefaultAsync(x => x.CompanyId == companyId);

        if (settings == null)
            return NotFound(new { success = false, message = "لم يتم إعداد FTTH بعد" });

        if (settings.IsSyncInProgress)
            return Ok(new { success = false, message = "المزامنة قيد التنفيذ بالفعل" });

        // تفعيل المزامنة — الـ BackgroundService سيلتقطها
        settings.IsSyncInProgress = true;
        settings.UpdatedAt = DateTime.UtcNow;
        _unitOfWork.CompanyFtthSettings.Update(settings);

        // إنشاء سجل مزامنة جديد
        var log = new FtthSyncLog
        {
            CompanyId = companyId,
            StartedAt = DateTime.UtcNow,
            Status = "InProgress",
            TriggerSource = "Manual",
        };
        await _unitOfWork.FtthSyncLogs.AddAsync(log);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تشغيل المزامنة" });
    }

    /// <summary>إلغاء المزامنة الجارية</summary>
    [HttpPost("{companyId}/cancel-sync")]
    public async Task<IActionResult> CancelSync(Guid companyId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var settings = await _unitOfWork.CompanyFtthSettings.AsQueryable()
            .FirstOrDefaultAsync(x => x.CompanyId == companyId);

        if (settings == null)
            return NotFound(new { success = false, message = "لم يتم إعداد FTTH بعد" });

        settings.IsSyncInProgress = false;
        settings.UpdatedAt = DateTime.UtcNow;
        _unitOfWork.CompanyFtthSettings.Update(settings);

        // تحديث آخر سجل
        var lastLog = await _unitOfWork.FtthSyncLogs.AsQueryable()
            .Where(x => x.CompanyId == companyId && x.Status == "InProgress")
            .OrderByDescending(x => x.StartedAt)
            .FirstOrDefaultAsync();

        if (lastLog != null)
        {
            lastLog.Status = "Cancelled";
            lastLog.CompletedAt = DateTime.UtcNow;
            lastLog.DurationSeconds = (int)(DateTime.UtcNow - lastLog.StartedAt).TotalSeconds;
            _unitOfWork.FtthSyncLogs.Update(lastLog);
        }

        await _unitOfWork.SaveChangesAsync();
        return Ok(new { success = true, message = "تم إلغاء المزامنة" });
    }

    /// <summary>جلب سجل المزامنات</summary>
    [HttpGet("{companyId}/sync-logs")]
    public async Task<IActionResult> GetSyncLogs(Guid companyId, [FromQuery] int limit = 50)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var logs = await _unitOfWork.FtthSyncLogs.AsQueryable()
            .Where(x => x.CompanyId == companyId)
            .OrderByDescending(x => x.StartedAt)
            .Take(limit)
            .Select(x => new
            {
                x.Id,
                x.StartedAt,
                x.CompletedAt,
                x.Status,
                x.SubscribersCount,
                x.PhonesCount,
                x.DetailsCount,
                x.NewCount,
                x.UpdatedCount,
                x.ErrorMessage,
                x.DurationSeconds,
                x.IsIncremental,
                x.TriggerSource,
            })
            .ToListAsync();

        return Ok(new { success = true, data = logs });
    }

    /// <summary>حذف سجل مزامنة واحد</summary>
    [HttpDelete("{companyId}/sync-logs/{logId}")]
    public async Task<IActionResult> DeleteSyncLog(Guid companyId, long logId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var log = await _unitOfWork.FtthSyncLogs.AsQueryable()
            .FirstOrDefaultAsync(x => x.Id == logId && x.CompanyId == companyId);

        if (log == null)
            return NotFound(new { success = false, message = "السجل غير موجود" });

        log.IsDeleted = true;
        log.DeletedAt = DateTime.UtcNow;
        _unitOfWork.FtthSyncLogs.Update(log);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف السجل" });
    }

    /// <summary>حذف كل سجلات المزامنة</summary>
    [HttpDelete("{companyId}/sync-logs")]
    public async Task<IActionResult> DeleteAllSyncLogs(Guid companyId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var logs = await _unitOfWork.FtthSyncLogs.AsQueryable()
            .Where(x => x.CompanyId == companyId)
            .ToListAsync();

        foreach (var log in logs)
        {
            log.IsDeleted = true;
            log.DeletedAt = DateTime.UtcNow;
            _unitOfWork.FtthSyncLogs.Update(log);
        }

        await _unitOfWork.SaveChangesAsync();
        return Ok(new { success = true, message = $"تم حذف {logs.Count} سجل" });
    }

    /// <summary>إحصائيات البيانات الناقصة</summary>
    [HttpGet("{companyId}/missing-stats")]
    public async Task<IActionResult> GetMissingStats(Guid companyId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var query = _unitOfWork.FtthSubscriberCaches.AsQueryable()
            .Where(x => x.CompanyId == companyId);

        var total = await query.CountAsync();
        var withoutPhone = await query.CountAsync(x => x.Phone == "");
        var withoutFat = await query.CountAsync(x => x.FatName == "");
        var withoutDetails = await query.CountAsync(x => !x.DetailsFetched);

        return Ok(new
        {
            success = true,
            data = new
            {
                total,
                withoutPhone,
                withoutFat,
                withoutFdt = withoutFat, // التطبيق قد يستخدم هذا الاسم
                withoutDetails,
                withPhone = total - withoutPhone,
                withFat = total - withoutFat,
                withFdt = total - withoutFat,
                withDetails = total - withoutDetails,
            }
        });
    }

    /// <summary>إعادة جلب البيانات الناقصة</summary>
    [HttpPost("{companyId}/refetch-missing")]
    public async Task<IActionResult> RefetchMissing(Guid companyId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var settings = await _unitOfWork.CompanyFtthSettings.AsQueryable()
            .FirstOrDefaultAsync(x => x.CompanyId == companyId);

        if (settings == null)
            return NotFound(new { success = false, message = "لم يتم إعداد FTTH بعد" });

        if (settings.IsSyncInProgress)
            return Ok(new { success = false, message = "المزامنة قيد التنفيذ بالفعل" });

        // تشغيل مزامنة لجلب البيانات الناقصة
        settings.IsSyncInProgress = true;
        settings.UpdatedAt = DateTime.UtcNow;
        _unitOfWork.CompanyFtthSettings.Update(settings);

        var log = new FtthSyncLog
        {
            CompanyId = companyId,
            StartedAt = DateTime.UtcNow,
            Status = "InProgress",
            TriggerSource = "RefetchMissing",
        };
        await _unitOfWork.FtthSyncLogs.AddAsync(log);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تشغيل جلب البيانات الناقصة" });
    }

    // ═══════════════════════════════════════
    // إحصائيات تفصيلية + إدارة البيانات
    // ═══════════════════════════════════════

    /// <summary>إحصائيات تفصيلية مع شريط تقدم</summary>
    [HttpGet("{companyId}/detailed-stats")]
    public async Task<IActionResult> GetDetailedStats(Guid companyId)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var query = _context.FtthSubscriberCaches
            .Where(x => x.CompanyId == companyId && !x.IsDeleted);

        var total = await query.CountAsync();
        if (total == 0)
            return Ok(new { success = true, data = new { total = 0 } });

        var withPhone = await query.CountAsync(x => x.Phone != "");
        var withUsername = await query.CountAsync(x => x.Username != "");
        var withFdt = await query.CountAsync(x => x.FdtName != "");
        var withFat = await query.CountAsync(x => x.FatName != "");
        var withGps = await query.CountAsync(x => x.GpsLat != null && x.GpsLat != "");
        var withDetails = await query.CountAsync(x => x.DetailsFetched);
        var active = await query.CountAsync(x => x.Status == "Active");
        var expired = await query.CountAsync(x => x.Status == "Expired");
        var suspended = await query.CountAsync(x => x.Status == "Suspended");

        // حساب النسب المئوية
        double pctPhone = total > 0 ? Math.Round(withPhone * 100.0 / total, 1) : 0;
        double pctDetails = total > 0 ? Math.Round(withDetails * 100.0 / total, 1) : 0;
        double pctUsername = total > 0 ? Math.Round(withUsername * 100.0 / total, 1) : 0;

        // نسبة الاكتمال الإجمالية (اشتراكات 40% + تفاصيل 30% + هواتف 30%)
        double overallPct = Math.Round(
            40.0 + // الاشتراكات موجودة دائماً
            (withDetails * 30.0 / total) +
            (withPhone * 30.0 / total), 1);

        return Ok(new
        {
            success = true,
            data = new
            {
                total,
                // الهواتف
                withPhone,
                withoutPhone = total - withPhone,
                phonePct = pctPhone,
                // التفاصيل (FDT/FAT/GPS/Username)
                withDetails,
                withoutDetails = total - withDetails,
                detailsPct = pctDetails,
                // حقول فردية
                withUsername,
                withoutUsername = total - withUsername,
                usernamePct = pctUsername,
                withFdt,
                withFat,
                withGps,
                // الحالات
                active,
                expired,
                suspended,
                other = total - active - expired - suspended,
                // الاكتمال
                overallPct,
            }
        });
    }

    /// <summary>مسح بيانات محددة من الكاش</summary>
    [HttpPost("{companyId}/clear-data")]
    public async Task<IActionResult> ClearData(Guid companyId, [FromBody] ClearDataRequest request)
    {
        if (!ValidateApiKey())
            return Unauthorized(new { success = false, message = "Invalid API Key" });

        var query = _context.FtthSubscriberCaches
            .Where(x => x.CompanyId == companyId && !x.IsDeleted);

        int affected = 0;

        switch (request.Type?.ToLower())
        {
            case "all":
                // مسح كل شيء
                var allItems = await query.ToListAsync();
                foreach (var item in allItems)
                {
                    item.IsDeleted = true;
                    item.DeletedAt = DateTime.UtcNow;
                }
                affected = allItems.Count;

                // إعادة تعيين العداد
                var settingsAll = await _context.CompanyFtthSettings
                    .FirstOrDefaultAsync(x => x.CompanyId == companyId && !x.IsDeleted);
                if (settingsAll != null)
                {
                    settingsAll.CurrentDbCount = 0;
                    settingsAll.UpdatedAt = DateTime.UtcNow;
                }
                break;

            case "phones":
                // مسح أرقام الهواتف فقط
                var phoneSubs = await query.Where(x => x.Phone != "").ToListAsync();
                foreach (var sub in phoneSubs)
                    sub.Phone = "";
                affected = phoneSubs.Count;
                break;

            case "details":
                // مسح التفاصيل (FDT/FAT/GPS/Username)
                var detailSubs = await query.Where(x => x.DetailsFetched).ToListAsync();
                foreach (var sub in detailSubs)
                {
                    sub.FdtName = "";
                    sub.FatName = "";
                    sub.DeviceSerial = "";
                    sub.Username = "";
                    sub.GpsLat = null;
                    sub.GpsLng = null;
                    sub.DetailsFetched = false;
                    sub.DetailsFetchedAt = null;
                }
                affected = detailSubs.Count;
                break;

            case "subscriptions":
                // مسح الاشتراكات (= مسح الكل)
                var subs = await query.ToListAsync();
                foreach (var sub in subs)
                {
                    sub.IsDeleted = true;
                    sub.DeletedAt = DateTime.UtcNow;
                }
                affected = subs.Count;

                var settingsSub = await _context.CompanyFtthSettings
                    .FirstOrDefaultAsync(x => x.CompanyId == companyId && !x.IsDeleted);
                if (settingsSub != null)
                {
                    settingsSub.CurrentDbCount = 0;
                    settingsSub.UpdatedAt = DateTime.UtcNow;
                }
                break;

            default:
                return BadRequest(new { success = false, message = "النوع غير معروف. استخدم: all, phones, details, subscriptions" });
        }

        await _context.SaveChangesAsync();

        return Ok(new
        {
            success = true,
            message = $"تم مسح {affected} سجل ({request.Type})",
            affected,
        });
    }
}

// ============ DTOs ============

public record ClearDataRequest(string? Type);

public record SaveFtthSettingsRequest(
    Guid CompanyId,
    string FtthUsername,
    string FtthPassword,
    int SyncIntervalMinutes = 60,
    bool IsAutoSyncEnabled = true,
    int SyncStartHour = 6,
    int SyncEndHour = 23);
