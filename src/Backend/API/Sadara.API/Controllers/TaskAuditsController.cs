using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Sadara.Application.Interfaces;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;
using Microsoft.EntityFrameworkCore;

namespace Sadara.API.Controllers;

/// <summary>
/// تدقيق المهام - حفظ واسترجاع حالة التدقيق والتقييم
/// Phase 0-D: every read/write is scoped to the caller company from the token (SuperAdmin keeps
/// cross-company access). An audit is visible when its CompanyId is the caller company, or — for
/// legacy rows saved without CompanyId — when its RequestNumber belongs to a task of the caller company.
/// </summary>
[ApiController]
[Route("api/[controller]")]
// Phase 0-D remediation (C1): company employees only (agent/citizen tokens rejected) + DB employee check.
[Authorize(Policy = "CompanyEmployee")]
[RequireEmployeeUser]
public class TaskAuditsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<TaskAuditsController> _logger;
    private readonly ICurrentTenant _tenant;

    public TaskAuditsController(IUnitOfWork unitOfWork, ILogger<TaskAuditsController> logger, ICurrentTenant tenant)
    {
        _unitOfWork = unitOfWork;
        _logger = logger;
        _tenant = tenant;
    }

    // ═══════ Tenant scope helpers (Phase 0-D) ═══════

    private bool HasCompanyScope() => _tenant.IsSuperAdmin || _tenant.CompanyId.HasValue;

    private ObjectResult CompanyScopeForbidden() =>
        StatusCode(StatusCodes.Status403Forbidden,
            new { success = false, message = "تعذّر تحديد شركة المستخدم من رمز الدخول — لا يمكن الوصول" });

    /// <summary>
    /// Audits of the caller company: CompanyId match, or legacy CompanyId=null rows whose RequestNumber
    /// belongs to a task of the caller company. SuperAdmin: unrestricted.
    /// </summary>
    private IQueryable<TaskAudit> ScopedAudits()
    {
        var query = _unitOfWork.TaskAudits.AsQueryable();
        if (_tenant.IsSuperAdmin)
            return query;

        var companyId = _tenant.CompanyId;
        var companyRequestNumbers = _unitOfWork.ServiceRequests.AsQueryable()
            .Where(r => r.CompanyId == companyId)
            .Select(r => r.RequestNumber);

        return query.Where(a =>
            a.CompanyId == companyId
            || (a.CompanyId == null && a.RequestNumber != null && companyRequestNumbers.Contains(a.RequestNumber)));
    }

    /// <summary>
    /// Writes are refused for a RequestNumber that belongs to another company's task (non-SuperAdmin).
    /// A RequestNumber that matches no task at all is allowed (legacy behaviour).
    /// </summary>
    private async Task<bool> RequestNumberBelongsToOtherCompanyAsync(string requestNumber)
    {
        if (_tenant.IsSuperAdmin)
            return false;
        var companyId = _tenant.CompanyId;
        return await _unitOfWork.ServiceRequests.AsQueryable()
            .AnyAsync(r => r.RequestNumber == requestNumber && r.CompanyId != companyId)
            && !await _unitOfWork.ServiceRequests.AsQueryable()
                .AnyAsync(r => r.RequestNumber == requestNumber && r.CompanyId == companyId);
    }

    /// <summary>CompanyId of a new audit: the token company (client value honoured only for SuperAdmin).</summary>
    private Guid? NewAuditCompanyId(SaveTaskAuditDto dto) =>
        _tenant.IsSuperAdmin ? (dto.CompanyId ?? _tenant.CompanyId) : _tenant.CompanyId;

    /// <summary>
    /// جلب جميع سجلات التدقيق
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        try
        {
            if (!HasCompanyScope())
                return CompanyScopeForbidden();

            var audits = await ScopedAudits()
                .OrderByDescending(a => a.AuditedAt ?? a.CreatedAt)
                .ToListAsync();

            return Ok(new { success = true, data = audits });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب سجلات التدقيق");
            return StatusCode(500, new { success = false, message = "خطأ في جلب البيانات" });
        }
    }

    /// <summary>
    /// جلب تدقيق مهمة محددة بالـ RequestNumber
    /// </summary>
    [HttpGet("by-request/{requestNumber}")]
    public async Task<IActionResult> GetByRequestNumber(string requestNumber)
    {
        try
        {
            if (!HasCompanyScope())
                return CompanyScopeForbidden();

            var audit = await ScopedAudits()
                .FirstOrDefaultAsync(a => a.RequestNumber == requestNumber);

            if (audit == null)
                return Ok(new { success = true, data = (object?)null });

            return Ok(new { success = true, data = audit });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب تدقيق المهمة {RequestNumber}", requestNumber);
            return StatusCode(500, new { success = false, message = "خطأ في جلب البيانات" });
        }
    }

    /// <summary>
    /// جلب جميع سجلات التدقيق كـ Map (requestNumber -> audit)
    /// للتحميل المجمع في Flutter
    /// </summary>
    [HttpGet("bulk")]
    public async Task<IActionResult> GetBulk()
    {
        try
        {
            if (!HasCompanyScope())
                return CompanyScopeForbidden();

            var audits = await ScopedAudits()
                .Where(a => a.RequestNumber != null)
                .ToListAsync();

            // Duplicate RequestNumbers (no unique index) would throw in ToDictionary ⇒ keep the latest.
            var map = audits
                .GroupBy(a => a.RequestNumber!)
                .ToDictionary(
                    g => g.Key,
                    g =>
                    {
                        var a = g.OrderByDescending(x => x.UpdatedAt ?? x.AuditedAt ?? x.CreatedAt).First();
                        return new
                        {
                            a.AuditStatus,
                            a.Rating,
                            a.Notes,
                            a.AuditedBy,
                            a.AuditedAt
                        };
                    });

            return Ok(new { success = true, data = map });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب سجلات التدقيق المجمعة");
            return StatusCode(500, new { success = false, message = "خطأ في جلب البيانات" });
        }
    }

    /// <summary>
    /// حفظ أو تحديث تدقيق مهمة
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> SaveAudit([FromBody] SaveTaskAuditDto dto)
    {
        try
        {
            if (!HasCompanyScope())
                return CompanyScopeForbidden();

            if (!string.IsNullOrEmpty(dto.RequestNumber)
                && await RequestNumberBelongsToOtherCompanyAsync(dto.RequestNumber))
                return NotFound(new { success = false, message = "المهمة غير موجودة" });

            // البحث عن تدقيق موجود (ضمن شركة المستخدم فقط)
            var existing = await ScopedAudits()
                .FirstOrDefaultAsync(a => a.RequestNumber == dto.RequestNumber);

            if (existing != null)
            {
                // تحديث
                existing.AuditStatus = dto.AuditStatus ?? existing.AuditStatus;
                existing.Rating = dto.Rating ?? existing.Rating;
                existing.Notes = dto.Notes ?? existing.Notes;
                existing.AuditedBy = dto.AuditedBy ?? existing.AuditedBy;
                existing.AuditedAt = DateTime.UtcNow;
                existing.UpdatedAt = DateTime.UtcNow;

                _unitOfWork.TaskAudits.Update(existing);
            }
            else
            {
                // إنشاء جديد
                var audit = new TaskAudit
                {
                    RequestNumber = dto.RequestNumber,
                    ServiceRequestId = dto.ServiceRequestId ?? Guid.Empty,
                    AuditStatus = dto.AuditStatus ?? "لم يتم",
                    Rating = dto.Rating ?? 0,
                    Notes = dto.Notes,
                    AuditedBy = dto.AuditedBy,
                    AuditedAt = DateTime.UtcNow,
                    CompanyId = NewAuditCompanyId(dto),
                };

                await _unitOfWork.TaskAudits.AddAsync(audit);
            }

            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حفظ التدقيق بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حفظ تدقيق المهمة {RequestNumber}", dto.RequestNumber);
            return StatusCode(500, new { success = false, message = "خطأ في حفظ البيانات" });
        }
    }

    /// <summary>
    /// حفظ مجمع لعدة سجلات تدقيق
    /// </summary>
    [HttpPost("bulk")]
    public async Task<IActionResult> SaveBulk([FromBody] List<SaveTaskAuditDto> dtos)
    {
        try
        {
            if (!HasCompanyScope())
                return CompanyScopeForbidden();

            var requestNumbers = dtos.Select(d => d.RequestNumber).Where(r => r != null).ToList();
            var existingAudits = await ScopedAudits()
                .Where(a => a.RequestNumber != null && requestNumbers.Contains(a.RequestNumber))
                .ToListAsync();

            var existingMap = existingAudits
                .GroupBy(a => a.RequestNumber!)
                .ToDictionary(g => g.Key, g => g.OrderByDescending(x => x.UpdatedAt ?? x.AuditedAt ?? x.CreatedAt).First());

            var saved = 0;
            foreach (var dto in dtos)
            {
                if (string.IsNullOrEmpty(dto.RequestNumber)) continue;

                if (existingMap.TryGetValue(dto.RequestNumber, out var existing))
                {
                    existing.AuditStatus = dto.AuditStatus ?? existing.AuditStatus;
                    existing.Rating = dto.Rating ?? existing.Rating;
                    existing.Notes = dto.Notes ?? existing.Notes;
                    existing.AuditedBy = dto.AuditedBy ?? existing.AuditedBy;
                    existing.AuditedAt = DateTime.UtcNow;
                    existing.UpdatedAt = DateTime.UtcNow;
                    _unitOfWork.TaskAudits.Update(existing);
                    saved++;
                }
                else
                {
                    // Never create an audit attached to another company's task.
                    if (await RequestNumberBelongsToOtherCompanyAsync(dto.RequestNumber))
                    {
                        _logger.LogWarning("Bulk audit: RequestNumber {RequestNumber} belongs to another company — skipped",
                            dto.RequestNumber);
                        continue;
                    }

                    var audit = new TaskAudit
                    {
                        RequestNumber = dto.RequestNumber,
                        ServiceRequestId = dto.ServiceRequestId ?? Guid.Empty,
                        AuditStatus = dto.AuditStatus ?? "لم يتم",
                        Rating = dto.Rating ?? 0,
                        Notes = dto.Notes,
                        AuditedBy = dto.AuditedBy,
                        AuditedAt = DateTime.UtcNow,
                        CompanyId = NewAuditCompanyId(dto),
                    };
                    await _unitOfWork.TaskAudits.AddAsync(audit);
                    saved++;
                }
            }

            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = $"تم حفظ {saved} سجل تدقيق بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في الحفظ المجمع للتدقيق");
            return StatusCode(500, new { success = false, message = "خطأ في حفظ البيانات" });
        }
    }
}

/// <summary>
/// DTO لحفظ/تحديث تدقيق مهمة
/// </summary>
public class SaveTaskAuditDto
{
    public string? RequestNumber { get; set; }
    public Guid? ServiceRequestId { get; set; }
    public string? AuditStatus { get; set; }
    public int? Rating { get; set; }
    public string? Notes { get; set; }
    public string? AuditedBy { get; set; }
    public Guid? CompanyId { get; set; }
}
