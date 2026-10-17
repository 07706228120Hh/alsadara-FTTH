using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.API.Authorization;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>
/// إحصائيات المناطق (الزونات).
/// المصادقة (المرحلة 0 / A2): JWT موظف الشركة (كان SuperAdmin فقط) أو المفتاح القديم.
/// مسار JWT: صفوف شركة التوكن فقط (+ الصفوف القديمة غير المختومة للشركة الافتراضية فقط)،
/// وكل كتابة تُختم بشركة التوكن (CompanyId في الجسم يُتجاهل). مسار المفتاح القديم دون تغيير.
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class ZoneStatisticsController(IUnitOfWork unitOfWork, IConfiguration configuration) : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork = unitOfWork;
    private readonly IConfiguration _configuration = configuration;

    private const string ZonesPermission = "zones";

    /// <summary>
    /// القراءة: صلاحية المناطق، أو المحاسبة (صفحة أجور صيانة الزونات تقرأ أسماء الزونات).
    /// الكتابة: صلاحية المناطق (دلالة RequirePermission). المدير/المشرف يمرّ.
    /// </summary>
    private async Task<(InternalCaller Caller, IActionResult? Error)> AuthorizeAsync(bool write)
    {
        var (caller, error) = await LegacyKeyOrJwtGate.AuthorizeAsync(HttpContext, _configuration, _unitOfWork);
        if (error != null) return (caller, error);
        if (!caller.IsJwt) return (caller, null);

        var allowed = caller.IsManagerOrHasPermission(ZonesPermission, "view")
                      || (!write && caller.HasPermission("accounting", "view"));
        return allowed
            ? (caller, null)
            : (caller, LegacyKeyOrJwtGate.Forbidden(LegacyKeyOrJwtGate.MsgNoPermission));
    }

    private IQueryable<ZoneStatistic> Scoped(InternalCaller caller)
    {
        var q = _unitOfWork.ZoneStatistics.AsQueryable();
        if (!caller.IsTenantBound) return q;
        var cid = caller.CompanyId;
        var ownsUnstamped = caller.OwnsUnstampedRows(_configuration);
        return q.Where(z => z.CompanyId == cid || (ownsUnstamped && z.CompanyId == null));
    }

    /// <summary>الشركة المختومة على الكتابة: شركة التوكن لمستخدم الشركة، وإلا قيمة الطلب (السلوك القديم).</summary>
    private static Guid? StampCompany(InternalCaller caller, Guid? requested) =>
        caller.IsTenantBound ? caller.CompanyId : requested;

    /// <summary>جلب إحصائيات جميع المناطق</summary>
    [HttpGet]
    public async Task<IActionResult> GetAll([FromQuery] string? search)
    {
        var (caller, authError) = await AuthorizeAsync(write: false);
        if (authError != null) return authError;

        var query = Scoped(caller);

        if (!string.IsNullOrEmpty(search))
            query = query.Where(z => z.ZoneName.Contains(search) ||
                                     (z.RegionName != null && z.RegionName.Contains(search)));

        var zones = await query.OrderBy(z => z.ZoneName).ToListAsync();
        return Ok(zones);
    }

    /// <summary>جلب ملخص إحصائي (مجاميع ومتوسطات)</summary>
    [HttpGet("summary")]
    public async Task<IActionResult> GetSummary()
    {
        var (caller, authError) = await AuthorizeAsync(write: false);
        if (authError != null) return authError;

        var zones = await Scoped(caller).ToListAsync();

        if (!zones.Any())
            return Ok(new { totalZones = 0, totalUsers = 0, totalActive = 0, totalInactive = 0, totalFats = 0 });

        return Ok(new
        {
            totalZones = zones.Count,
            totalUsers = zones.Sum(z => z.TotalUsers),
            totalActive = zones.Sum(z => z.ActiveUsers),
            totalInactive = zones.Sum(z => z.InactiveUsers),
            totalFats = zones.Sum(z => z.Fats),
            avgUsersPerZone = Math.Round(zones.Average(z => z.TotalUsers), 1),
            avgFatsPerZone = Math.Round(zones.Average(z => z.Fats), 1),
            minFats = zones.Min(z => z.Fats),
            maxFats = zones.Max(z => z.Fats),
            minUsers = zones.Min(z => z.TotalUsers),
            maxUsers = zones.Max(z => z.TotalUsers),
        });
    }

    /// <summary>إضافة إحصائية منطقة</summary>
    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateZoneStatisticRequest request)
    {
        var (caller, authError) = await AuthorizeAsync(write: true);
        if (authError != null) return authError;

        var zone = new ZoneStatistic
        {
            ZoneName = request.ZoneName,
            Fats = request.Fats,
            TotalUsers = request.TotalUsers,
            ActiveUsers = request.ActiveUsers,
            InactiveUsers = request.InactiveUsers,
            RegionName = request.RegionName,
            CompanyId = StampCompany(caller, request.CompanyId),
        };

        await _unitOfWork.ZoneStatistics.AddAsync(zone);
        await _unitOfWork.SaveChangesAsync();

        return Ok(zone);
    }

    /// <summary>إضافة إحصائيات بالجملة</summary>
    [HttpPost("bulk")]
    public async Task<IActionResult> BulkCreate([FromBody] List<CreateZoneStatisticRequest> requests)
    {
        var (caller, authError) = await AuthorizeAsync(write: true);
        if (authError != null) return authError;

        var zones = requests.Select(r => new ZoneStatistic
        {
            ZoneName = r.ZoneName,
            Fats = r.Fats,
            TotalUsers = r.TotalUsers,
            ActiveUsers = r.ActiveUsers,
            InactiveUsers = r.InactiveUsers,
            RegionName = r.RegionName,
            CompanyId = StampCompany(caller, r.CompanyId),
        }).ToList();

        foreach (var z in zones)
            await _unitOfWork.ZoneStatistics.AddAsync(z);

        await _unitOfWork.SaveChangesAsync();

        return Ok(new { message = $"تم إضافة {zones.Count} منطقة", count = zones.Count });
    }

    /// <summary>تحديث إحصائية منطقة</summary>
    [HttpPut("{id}")]
    public async Task<IActionResult> Update(int id, [FromBody] CreateZoneStatisticRequest request)
    {
        var (caller, authError) = await AuthorizeAsync(write: true);
        if (authError != null) return authError;

        var zone = await Scoped(caller).FirstOrDefaultAsync(z => z.Id == id);
        if (zone == null) return NotFound();

        zone.ZoneName = request.ZoneName;
        zone.Fats = request.Fats;
        zone.TotalUsers = request.TotalUsers;
        zone.ActiveUsers = request.ActiveUsers;
        zone.InactiveUsers = request.InactiveUsers;
        zone.RegionName = request.RegionName;
        zone.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.ZoneStatistics.Update(zone);
        await _unitOfWork.SaveChangesAsync();

        return Ok(zone);
    }

    /// <summary>مزامنة الزونات من FTTH — إضافة الجديد وتحديث Fats فقط للموجود</summary>
    [HttpPost("sync")]
    public async Task<IActionResult> SyncZones([FromBody] List<SyncZoneRequest> requests)
    {
        var (caller, authError) = await AuthorizeAsync(write: true);
        if (authError != null) return authError;

        if (requests == null || requests.Count == 0)
            return BadRequest(new { message = "لا توجد بيانات للمزامنة" });

        // المطابقة بالاسم داخل نطاق الطالب فقط (لا تعديل زونات شركة أخرى بنفس الاسم).
        var existingZones = await Scoped(caller).ToListAsync();
        var existingMap = existingZones
            .GroupBy(z => z.ZoneName.Trim().ToLowerInvariant())
            .ToDictionary(g => g.Key, g => g.First());

        int added = 0, updated = 0, unchanged = 0;

        foreach (var req in requests)
        {
            if (string.IsNullOrWhiteSpace(req.ZoneName)) continue;

            var key = req.ZoneName.Trim().ToLowerInvariant();

            if (existingMap.TryGetValue(key, out var existing))
            {
                if (existing.Fats != req.Fats)
                {
                    existing.Fats = req.Fats;
                    existing.UpdatedAt = DateTime.UtcNow;
                    _unitOfWork.ZoneStatistics.Update(existing);
                    updated++;
                }
                else
                {
                    unchanged++;
                }
            }
            else
            {
                var zone = new ZoneStatistic
                {
                    ZoneName = req.ZoneName.Trim(),
                    Fats = req.Fats,
                    TotalUsers = 0,
                    ActiveUsers = 0,
                    InactiveUsers = 0,
                    CompanyId = StampCompany(caller, req.CompanyId),
                };
                await _unitOfWork.ZoneStatistics.AddAsync(zone);
                existingMap[key] = zone;
                added++;
            }
        }

        await _unitOfWork.SaveChangesAsync();

        return Ok(new { added, updated, unchanged, total = added + updated + unchanged });
    }

    /// <summary>حذف إحصائية منطقة</summary>
    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        var (caller, authError) = await AuthorizeAsync(write: true);
        if (authError != null) return authError;

        var zone = await Scoped(caller).FirstOrDefaultAsync(z => z.Id == id);
        if (zone == null) return NotFound();

        zone.IsDeleted = true;
        zone.DeletedAt = DateTime.UtcNow;
        _unitOfWork.ZoneStatistics.Update(zone);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { message = "تم الحذف بنجاح" });
    }
}

public record CreateZoneStatisticRequest(
    string ZoneName, int Fats, int TotalUsers, int ActiveUsers,
    int InactiveUsers, string? RegionName, Guid? CompanyId);

public record SyncZoneRequest(string ZoneName, int Fats, Guid? CompanyId);
