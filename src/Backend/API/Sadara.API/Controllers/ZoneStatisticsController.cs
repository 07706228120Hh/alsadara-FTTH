using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ZoneStatisticsController(IUnitOfWork unitOfWork) : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork = unitOfWork;

    /// <summary>جلب إحصائيات جميع المناطق</summary>
    [HttpGet]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetAll([FromQuery] string? search)
    {
        var query = _unitOfWork.ZoneStatistics.AsQueryable();

        if (!string.IsNullOrEmpty(search))
            query = query.Where(z => z.ZoneName.Contains(search) || 
                                     (z.RegionName != null && z.RegionName.Contains(search)));

        var zones = await query.OrderBy(z => z.ZoneName).ToListAsync();
        return Ok(zones);
    }

    /// <summary>جلب ملخص إحصائي (مجاميع ومتوسطات)</summary>
    [HttpGet("summary")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetSummary()
    {
        var zones = await _unitOfWork.ZoneStatistics.AsQueryable().ToListAsync();

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
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Create([FromBody] CreateZoneStatisticRequest request)
    {
        var zone = new ZoneStatistic
        {
            ZoneName = request.ZoneName,
            Fats = request.Fats,
            TotalUsers = request.TotalUsers,
            ActiveUsers = request.ActiveUsers,
            InactiveUsers = request.InactiveUsers,
            RegionName = request.RegionName,
            CompanyId = request.CompanyId,
        };

        await _unitOfWork.ZoneStatistics.AddAsync(zone);
        await _unitOfWork.SaveChangesAsync();

        return Ok(zone);
    }

    /// <summary>إضافة إحصائيات بالجملة</summary>
    [HttpPost("bulk")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> BulkCreate([FromBody] List<CreateZoneStatisticRequest> requests)
    {
        var zones = requests.Select(r => new ZoneStatistic
        {
            ZoneName = r.ZoneName,
            Fats = r.Fats,
            TotalUsers = r.TotalUsers,
            ActiveUsers = r.ActiveUsers,
            InactiveUsers = r.InactiveUsers,
            RegionName = r.RegionName,
            CompanyId = r.CompanyId,
        }).ToList();

        foreach (var z in zones)
            await _unitOfWork.ZoneStatistics.AddAsync(z);

        await _unitOfWork.SaveChangesAsync();

        return Ok(new { message = $"تم إضافة {zones.Count} منطقة", count = zones.Count });
    }

    /// <summary>تحديث إحصائية منطقة</summary>
    [HttpPut("{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Update(int id, [FromBody] CreateZoneStatisticRequest request)
    {
        var zone = await _unitOfWork.ZoneStatistics.GetByIdAsync(id);
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

    /// <summary>حذف إحصائية منطقة</summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Delete(int id)
    {
        var zone = await _unitOfWork.ZoneStatistics.GetByIdAsync(id);
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
