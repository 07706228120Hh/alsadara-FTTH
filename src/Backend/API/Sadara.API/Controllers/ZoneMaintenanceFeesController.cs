using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.API.Authorization;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;
using Sadara.Infrastructure.Data;

namespace Sadara.API.Controllers;

/// <summary>إدارة أجور صيانة الزونات</summary>
[ApiController]
[Route("api/zone-maintenance-fees")]
public class ZoneMaintenanceFeesController(IUnitOfWork unitOfWork, SadaraDbContext db) : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork = unitOfWork;
    private readonly SadaraDbContext _db = db;

    /// <summary>جلب كل أجور الصيانة</summary>
    [HttpGet]
    [Authorize]
    [RequirePermission("accounting.ftth_operators", "view")]
    public async Task<IActionResult> GetAll([FromQuery] Guid? companyId, [FromQuery] Guid? partnerId)
    {
        var query = _unitOfWork.ZoneMaintenanceFees.AsQueryable();
        if (companyId.HasValue)
            query = query.Where(z => z.CompanyId == companyId.Value);
        // فلتر الشريك: المحدّد + الاحتياطية (بلا شريك) عند اختيار شريك.
        if (partnerId.HasValue)
            query = query.Where(z => z.PartnerId == partnerId.Value || z.PartnerId == null);

        var fees = await query.OrderBy(z => z.ZoneName).ToListAsync();
        return Ok(new { success = true, data = fees });
    }

    /// <summary>
    /// مناطق شريك محدّد — مستخرَجة من عمليات الشريك المُزامَنة (SubscriptionLogs).
    /// مصدر موثوق ومُقيَّد بالشريك (بعكس locations/zones العام)، بلا اعتماد على لوحة FTTH.
    /// </summary>
    [HttpGet("partner-zones")]
    [Authorize]
    [RequirePermission("accounting.ftth_operators", "view")]
    public async Task<IActionResult> GetPartnerZones([FromQuery] Guid partnerId, [FromQuery] Guid? companyId)
    {
        // حلّ معرّف شريك FTTH (PartnerAccountId) — العمليات قد تحمله أو تحمل معرّف الكيان.
        var ftthPid = await _db.FtthPartners
            .Where(p => p.Id == partnerId && !p.IsDeleted)
            .Select(p => p.PartnerAccountId)
            .FirstOrDefaultAsync();
        var entityId = partnerId.ToString();

        var q = _db.SubscriptionLogs.Where(l => !l.IsDeleted
            && l.ZoneName != null && l.ZoneName != ""
            && (l.PartnerId == entityId || (ftthPid != null && l.PartnerId == ftthPid)));
        if (companyId.HasValue)
            q = q.Where(l => l.CompanyId == companyId.Value);

        var zones = await q
            .GroupBy(l => l.ZoneName!)
            .Select(g => new
            {
                zoneName = g.Key,
                zoneId = g.Max(x => x.ZoneId),
                count = g.Count()
            })
            .OrderByDescending(x => x.count)
            .ToListAsync();

        return Ok(new { success = true, data = zones });
    }

    /// <summary>
    /// جلب أجور صيانة زون محدد بالاسم — يُستخدم من شاشة التفعيل.
    /// عند تمرير ftthPartnerId (معرّف شريك FTTH، مثل "2261175") يُحلّ لكيان الشريك
    /// وتُرجَّح أجرة ذلك الشريك على الأجرة الاحتياطية (بلا شريك).
    /// </summary>
    [HttpGet("check")]
    [AllowAnonymous]
    public async Task<IActionResult> CheckZone(
        [FromQuery] string zoneName,
        [FromQuery] Guid? companyId,
        [FromQuery] string? ftthPartnerId)
    {
        if (string.IsNullOrWhiteSpace(zoneName))
            return Ok(new { success = true, hasMaintenanceFee = false, amount = 0 });

        // حلّ معرّف شريك FTTH → معرّف كيان الشريك عندنا (إن وُجد).
        Guid? partnerEntityId = null;
        if (!string.IsNullOrWhiteSpace(ftthPartnerId))
        {
            var pq = _db.FtthPartners.Where(p => !p.IsDeleted && p.PartnerAccountId == ftthPartnerId);
            if (companyId.HasValue)
                pq = pq.Where(p => p.CompanyId == companyId.Value);
            partnerEntityId = await pq.Select(p => (Guid?)p.Id).FirstOrDefaultAsync();
        }

        var query = _unitOfWork.ZoneMaintenanceFees.AsQueryable()
            .Where(z => z.IsEnabled && z.ZoneName == zoneName);

        if (companyId.HasValue)
            query = query.Where(z => z.CompanyId == companyId.Value);

        // فلتر الشريك: المحدّد + الاحتياطية (بلا شريك) عند حلّ شريك.
        if (partnerEntityId.HasValue)
            query = query.Where(z => z.PartnerId == partnerEntityId.Value || z.PartnerId == null);

        var fees = await query.ToListAsync();
        if (fees.Count == 0)
            return Ok(new { success = true, hasMaintenanceFee = false, amount = 0 });

        // ترجيح أجرة الشريك المحلول على الأجرة الاحتياطية (بلا شريك).
        var fee = partnerEntityId.HasValue
            ? (fees.FirstOrDefault(f => f.PartnerId == partnerEntityId.Value) ?? fees[0])
            : fees[0];

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
    [RequirePermission("accounting.ftth_operators", "edit")]
    public async Task<IActionResult> Create([FromBody] CreateZoneMaintenanceFeeDto dto)
    {
        // تحقق من عدم التكرار — لكل (شركة + شريك + زون): نفس الزون مسموح لشركاء مختلفين.
        var exists = await _unitOfWork.ZoneMaintenanceFees.AsQueryable()
            .AnyAsync(z => z.ZoneName == dto.ZoneName && z.CompanyId == dto.CompanyId
                && z.PartnerId == dto.PartnerId);
        if (exists)
            return BadRequest(new { success = false, message = $"أجور صيانة للزون '{dto.ZoneName}' موجودة مسبقاً لهذا الشريك" });

        var fee = new ZoneMaintenanceFee
        {
            Id = Guid.NewGuid(),
            ZoneName = dto.ZoneName,
            ZoneId = dto.ZoneId,
            MaintenanceAmount = dto.MaintenanceAmount,
            Notes = dto.Notes,
            IsEnabled = dto.IsEnabled ?? true,
            PartnerId = dto.PartnerId,
            CompanyId = dto.CompanyId
        };

        await _unitOfWork.ZoneMaintenanceFees.AddAsync(fee);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, data = fee, message = "تم إضافة أجور الصيانة" });
    }

    /// <summary>إضافة أجور صيانة لعدة زونات دفعة واحدة</summary>
    [HttpPost("bulk")]
    [Authorize]
    [RequirePermission("accounting.ftth_operators", "edit")]
    public async Task<IActionResult> BulkCreate([FromBody] BulkZoneMaintenanceFeeDto dto)
    {
        int added = 0, skipped = 0;
        foreach (var zone in dto.Zones)
        {
            var exists = await _unitOfWork.ZoneMaintenanceFees.AsQueryable()
                .AnyAsync(z => z.ZoneName == zone.ZoneName && z.CompanyId == dto.CompanyId
                    && z.PartnerId == dto.PartnerId);
            if (exists) { skipped++; continue; }

            var fee = new ZoneMaintenanceFee
            {
                Id = Guid.NewGuid(),
                ZoneName = zone.ZoneName,
                ZoneId = zone.ZoneId,
                MaintenanceAmount = zone.MaintenanceAmount,
                Notes = zone.Notes,
                IsEnabled = true,
                PartnerId = dto.PartnerId,
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
    [RequirePermission("accounting.ftth_operators", "edit")]
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
    [RequirePermission("accounting.ftth_operators", "edit")]
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
    Guid CompanyId,
    Guid? PartnerId = null
);

public record UpdateZoneMaintenanceFeeDto(
    string? ZoneName,
    decimal? MaintenanceAmount,
    string? Notes,
    bool? IsEnabled
);

public record BulkZoneMaintenanceFeeDto(
    Guid CompanyId,
    List<BulkZoneItem> Zones,
    Guid? PartnerId = null
);

public record BulkZoneItem(
    string ZoneName,
    string? ZoneId,
    decimal MaintenanceAmount,
    string? Notes
);
