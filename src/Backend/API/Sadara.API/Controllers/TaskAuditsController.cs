using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;
using Microsoft.EntityFrameworkCore;

namespace Sadara.API.Controllers;

/// <summary>
/// تدقيق المهام - حفظ واسترجاع حالة التدقيق والتقييم
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class TaskAuditsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<TaskAuditsController> _logger;

    public TaskAuditsController(IUnitOfWork unitOfWork, ILogger<TaskAuditsController> logger)
    {
        _unitOfWork = unitOfWork;
        _logger = logger;
    }

    /// <summary>
    /// جلب جميع سجلات التدقيق
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        try
        {
            var audits = await _unitOfWork.TaskAudits
                .AsQueryable()
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
            var audit = await _unitOfWork.TaskAudits
                .AsQueryable()
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
            var audits = await _unitOfWork.TaskAudits
                .AsQueryable()
                .Where(a => a.RequestNumber != null)
                .ToListAsync();

            var map = audits.ToDictionary(
                a => a.RequestNumber!,
                a => new
                {
                    a.AuditStatus,
                    a.Rating,
                    a.Notes,
                    a.AuditedBy,
                    a.AuditedAt
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
            // البحث عن تدقيق موجود
            var existing = await _unitOfWork.TaskAudits
                .AsQueryable()
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
                    CompanyId = dto.CompanyId,
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
            var requestNumbers = dtos.Select(d => d.RequestNumber).Where(r => r != null).ToList();
            var existingAudits = await _unitOfWork.TaskAudits
                .AsQueryable()
                .Where(a => a.RequestNumber != null && requestNumbers.Contains(a.RequestNumber))
                .ToListAsync();

            var existingMap = existingAudits.ToDictionary(a => a.RequestNumber!);

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
                }
                else
                {
                    var audit = new TaskAudit
                    {
                        RequestNumber = dto.RequestNumber,
                        ServiceRequestId = dto.ServiceRequestId ?? Guid.Empty,
                        AuditStatus = dto.AuditStatus ?? "لم يتم",
                        Rating = dto.Rating ?? 0,
                        Notes = dto.Notes,
                        AuditedBy = dto.AuditedBy,
                        AuditedAt = DateTime.UtcNow,
                        CompanyId = dto.CompanyId,
                    };
                    await _unitOfWork.TaskAudits.AddAsync(audit);
                }
            }

            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = $"تم حفظ {dtos.Count} سجل تدقيق بنجاح" });
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
