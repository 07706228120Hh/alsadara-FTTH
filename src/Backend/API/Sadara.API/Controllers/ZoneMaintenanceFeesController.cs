using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.API.Authorization;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>إدارة أجور صيانة الزونات</summary>
/// <remarks>
/// Phase 0-B (tenant isolation): company-employee roles only, permission gate on every action,
/// company always taken from the token for non-SuperAdmin callers (client CompanyId is ignored),
/// and Update/Delete verify the record belongs to the caller's company.
/// </remarks>
[ApiController]
[Route("api/zone-maintenance-fees")]
[Authorize(Policy = FtthAccessGate.EmployeePolicy)]
public class ZoneMaintenanceFeesController(IUnitOfWork unitOfWork, ICurrentTenant tenant) : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork = unitOfWork;
    private readonly ICurrentTenant _tenant = tenant;

    /// <summary>Read scope: SuperAdmin keeps the requested company (null = all); others = token company.</summary>
    private bool TryGetReadScope(Guid? requested, out Guid? scope)
    {
        if (_tenant.IsSuperAdmin)
        {
            scope = requested.HasValue && requested.Value != Guid.Empty ? requested : null;
            return true;
        }
        scope = _tenant.CompanyId;
        return scope.HasValue && scope.Value != Guid.Empty;
    }

    /// <summary>Write company: SuperAdmin may target the requested company (fallback: token); others = token.</summary>
    private bool TryGetWriteCompany(Guid? requested, out Guid companyId)
    {
        Guid? resolved = _tenant.IsSuperAdmin
            ? (requested.HasValue && requested.Value != Guid.Empty ? requested : _tenant.CompanyId)
            : _tenant.CompanyId;
        companyId = resolved ?? Guid.Empty;
        return companyId != Guid.Empty;
    }

    private ObjectResult NoCompany() =>
        StatusCode(403, new { success = false, message = "لا توجد شركة مرتبطة بحسابك" });

    /// <summary>جلب كل أجور الصيانة</summary>
    [HttpGet]
    [RequirePermission("accounting", "view")]
    public async Task<IActionResult> GetAll([FromQuery] Guid? companyId)
    {
        if (!TryGetReadScope(companyId, out var scope))
            return NoCompany();

        var query = _unitOfWork.ZoneMaintenanceFees.AsQueryable();
        if (scope.HasValue)
            query = query.Where(z => z.CompanyId == scope.Value);

        var fees = await query.OrderBy(z => z.ZoneName).ToListAsync();
        return Ok(new { success = true, data = fees });
    }

    /// <summary>جلب أجور صيانة زون محدد بالاسم — يُستخدم من شاشة التفعيل</summary>
    /// <remarks>
    /// Was [AllowAnonymous]; the only caller (activation screen via AccountingService) sends the employee
    /// JWT, so anonymous access is removed. The fee amount is not sensitive and a refusal here could make
    /// the activation post a wrong (zero) fee, so ANY active employee of the company may read it — no
    /// permission key, but still company-scoped (client companyId ignored for non-SuperAdmin).
    /// </remarks>
    [HttpGet("check")]
    public async Task<IActionResult> CheckZone([FromQuery] string zoneName, [FromQuery] Guid? companyId)
    {
        if (!await FtthAccessGate.IsActiveEmployeeAsync(_unitOfWork, User))
            return StatusCode(403, new { success = false, message = "لا تملك صلاحية كافية" });

        if (!TryGetReadScope(companyId, out var scope))
            return NoCompany();

        if (string.IsNullOrWhiteSpace(zoneName))
            return Ok(new { success = true, hasMaintenanceFee = false, amount = 0 });

        var query = _unitOfWork.ZoneMaintenanceFees.AsQueryable()
            .Where(z => z.IsEnabled && z.ZoneName == zoneName);

        if (scope.HasValue)
            query = query.Where(z => z.CompanyId == scope.Value);

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
    [RequirePermission("accounting", "add")]
    public async Task<IActionResult> Create([FromBody] CreateZoneMaintenanceFeeDto dto)
    {
        // Isolation: company from token (client CompanyId ignored for non-SuperAdmin).
        if (!TryGetWriteCompany(dto.CompanyId, out var companyId))
            return NoCompany();

        // تحقق من عدم التكرار
        var exists = await _unitOfWork.ZoneMaintenanceFees.AsQueryable()
            .AnyAsync(z => z.ZoneName == dto.ZoneName && z.CompanyId == companyId);
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
            CompanyId = companyId
        };

        await _unitOfWork.ZoneMaintenanceFees.AddAsync(fee);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, data = fee, message = "تم إضافة أجور الصيانة" });
    }

    /// <summary>إضافة أجور صيانة لعدة زونات دفعة واحدة</summary>
    [HttpPost("bulk")]
    [RequirePermission("accounting", "add")]
    public async Task<IActionResult> BulkCreate([FromBody] BulkZoneMaintenanceFeeDto dto)
    {
        // Isolation: company from token (client CompanyId ignored for non-SuperAdmin).
        if (!TryGetWriteCompany(dto.CompanyId, out var companyId))
            return NoCompany();

        int added = 0, skipped = 0;
        foreach (var zone in dto.Zones)
        {
            var exists = await _unitOfWork.ZoneMaintenanceFees.AsQueryable()
                .AnyAsync(z => z.ZoneName == zone.ZoneName && z.CompanyId == companyId);
            if (exists) { skipped++; continue; }

            var fee = new ZoneMaintenanceFee
            {
                Id = Guid.NewGuid(),
                ZoneName = zone.ZoneName,
                ZoneId = zone.ZoneId,
                MaintenanceAmount = zone.MaintenanceAmount,
                Notes = zone.Notes,
                IsEnabled = true,
                CompanyId = companyId
            };
            await _unitOfWork.ZoneMaintenanceFees.AddAsync(fee);
            added++;
        }
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = $"تم إضافة {added} زون (تخطي {skipped} مكرر)" });
    }

    /// <summary>تعديل أجور صيانة</summary>
    [HttpPut("{id}")]
    [RequirePermission("accounting", "edit")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateZoneMaintenanceFeeDto dto)
    {
        if (!TryGetReadScope(null, out var scope))
            return NoCompany();

        var fee = await _unitOfWork.ZoneMaintenanceFees.GetByIdAsync(id);
        // Isolation: another company's record is reported as not found.
        if (fee == null || (scope.HasValue && fee.CompanyId != scope.Value))
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
    [RequirePermission("accounting", "delete")]
    public async Task<IActionResult> Delete(Guid id)
    {
        if (!TryGetReadScope(null, out var scope))
            return NoCompany();

        var fee = await _unitOfWork.ZoneMaintenanceFees.GetByIdAsync(id);
        // Isolation: another company's record is reported as not found.
        if (fee == null || (scope.HasValue && fee.CompanyId != scope.Value))
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
