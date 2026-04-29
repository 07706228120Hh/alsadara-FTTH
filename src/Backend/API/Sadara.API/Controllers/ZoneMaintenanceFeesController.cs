using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>إدارة أجور صيانة الزونات</summary>
[ApiController]
[Route("api/zone-maintenance-fees")]
public class ZoneMaintenanceFeesController(IUnitOfWork unitOfWork) : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork = unitOfWork;

    /// <summary>جلب كل أجور الصيانة</summary>
    [HttpGet]
    [Authorize]
    public async Task<IActionResult> GetAll([FromQuery] Guid? companyId)
    {
        var query = _unitOfWork.ZoneMaintenanceFees.AsQueryable();
        if (companyId.HasValue)
            query = query.Where(z => z.CompanyId == companyId.Value);

        var fees = await query.OrderBy(z => z.ZoneName).ToListAsync();
        return Ok(new { success = true, data = fees });
    }

    /// <summary>جلب أجور صيانة زون محدد بالاسم — يُستخدم من شاشة التفعيل</summary>
    [HttpGet("check")]
    [AllowAnonymous]
    public async Task<IActionResult> CheckZone([FromQuery] string zoneName, [FromQuery] Guid? companyId)
    {
        if (string.IsNullOrWhiteSpace(zoneName))
            return Ok(new { success = true, hasMaintenanceFee = false, amount = 0 });

        var query = _unitOfWork.ZoneMaintenanceFees.AsQueryable()
            .Where(z => z.IsEnabled && z.ZoneName == zoneName);

        if (companyId.HasValue)
            query = query.Where(z => z.CompanyId == companyId.Value);

        var fee = await query.FirstOrDefaultAsync();
        if (fee == null)
            return Ok(new { success = true, hasMaintenanceFee = false, amount = 0 });

        return Ok(new
        {
            success = true,
            hasMaintenanceFee = true,
            amount = fee.MaintenanceAmount,
            notes = fee.Notes,
            zoneName = fee.ZoneName
        });
    }

    /// <summary>إنشاء أجور صيانة لزون</summary>
    [HttpPost]
    [Authorize]
    public async Task<IActionResult> Create([FromBody] CreateZoneMaintenanceFeeDto dto)
    {
        // تحقق من عدم التكرار
        var exists = await _unitOfWork.ZoneMaintenanceFees.AsQueryable()
            .AnyAsync(z => z.ZoneName == dto.ZoneName && z.CompanyId == dto.CompanyId);
        if (exists)
            return BadRequest(new { success = false, message = $"أجور صيانة للزون '{dto.ZoneName}' موجودة مسبقاً" });

        var fee = new ZoneMaintenanceFee
        {
            Id = Guid.NewGuid(),
            ZoneName = dto.ZoneName,
            ZoneId = dto.ZoneId,
            MaintenanceAmount = dto.MaintenanceAmount,
            Notes = dto.Notes,
            IsEnabled = dto.IsEnabled ?? true,
            CompanyId = dto.CompanyId
        };

        await _unitOfWork.ZoneMaintenanceFees.AddAsync(fee);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, data = fee, message = "تم إضافة أجور الصيانة" });
    }

    /// <summary>إضافة أجور صيانة لعدة زونات دفعة واحدة</summary>
    [HttpPost("bulk")]
    [Authorize]
    public async Task<IActionResult> BulkCreate([FromBody] BulkZoneMaintenanceFeeDto dto)
    {
        int added = 0, skipped = 0;
        foreach (var zone in dto.Zones)
        {
            var exists = await _unitOfWork.ZoneMaintenanceFees.AsQueryable()
                .AnyAsync(z => z.ZoneName == zone.ZoneName && z.CompanyId == dto.CompanyId);
            if (exists) { skipped++; continue; }

            var fee = new ZoneMaintenanceFee
            {
                Id = Guid.NewGuid(),
                ZoneName = zone.ZoneName,
                ZoneId = zone.ZoneId,
                MaintenanceAmount = zone.MaintenanceAmount,
                Notes = zone.Notes,
                IsEnabled = true,
                CompanyId = dto.CompanyId
            };
            await _unitOfWork.ZoneMaintenanceFees.AddAsync(fee);
            added++;
        }
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = $"تم إضافة {added} زون (تخطي {skipped} مكرر)" });
    }

    /// <summary>تعديل أجور صيانة</summary>
    [HttpPut("{id}")]
    [Authorize]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateZoneMaintenanceFeeDto dto)
    {
        var fee = await _unitOfWork.ZoneMaintenanceFees.GetByIdAsync(id);
        if (fee == null)
            return NotFound(new { success = false, message = "غير موجود" });

        if (dto.MaintenanceAmount.HasValue) fee.MaintenanceAmount = dto.MaintenanceAmount.Value;
        if (dto.Notes != null) fee.Notes = dto.Notes;
        if (dto.IsEnabled.HasValue) fee.IsEnabled = dto.IsEnabled.Value;
        if (dto.ZoneName != null) fee.ZoneName = dto.ZoneName;

        _unitOfWork.ZoneMaintenanceFees.Update(fee);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, data = fee, message = "تم التحديث" });
    }

    /// <summary>حذف أجور صيانة</summary>
    [HttpDelete("{id}")]
    [Authorize]
    public async Task<IActionResult> Delete(Guid id)
    {
        var fee = await _unitOfWork.ZoneMaintenanceFees.GetByIdAsync(id);
        if (fee == null)
            return NotFound(new { success = false, message = "غير موجود" });

        _unitOfWork.ZoneMaintenanceFees.Delete(fee);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم الحذف" });
    }
}

public record CreateZoneMaintenanceFeeDto(
    string ZoneName,
    string? ZoneId,
    decimal MaintenanceAmount,
    string? Notes,
    bool? IsEnabled,
    Guid CompanyId
);

public record UpdateZoneMaintenanceFeeDto(
    string? ZoneName,
    decimal? MaintenanceAmount,
    string? Notes,
    bool? IsEnabled
);

public record BulkZoneMaintenanceFeeDto(
    Guid CompanyId,
    List<BulkZoneItem> Zones
);

public record BulkZoneItem(
    string ZoneName,
    string? ZoneId,
    decimal MaintenanceAmount,
    string? Notes
);
