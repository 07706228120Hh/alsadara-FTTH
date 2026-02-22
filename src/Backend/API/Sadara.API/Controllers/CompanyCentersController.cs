using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

/// <summary>
/// إدارة مراكز الشركة ومواقعها الجغرافية
/// </summary>
[ApiController]
[Route("api/companies/{companyId:guid}/centers")]
[Authorize(Policy = "CompanyAdminOrAbove")]
public class CompanyCentersController(IUnitOfWork unitOfWork) : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork = unitOfWork;

    /// <summary>
    /// جلب جميع مراكز الشركة
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetAll(Guid companyId)
    {
        var centers = await _unitOfWork.WorkCenters.AsQueryable()
            .Where(c => c.CompanyId == companyId)
            .OrderBy(c => c.Name)
            .Select(c => new CenterResponse
            {
                Id = c.Id,
                Name = c.Name,
                Description = c.Description,
                Latitude = c.Latitude,
                Longitude = c.Longitude,
                RadiusMeters = c.RadiusMeters,
                IsActive = c.IsActive,
                CreatedAt = c.CreatedAt,
            })
            .ToListAsync();

        return Ok(new { success = true, data = centers });
    }

    /// <summary>
    /// إضافة مركز جديد
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> Create(Guid companyId, [FromBody] CreateCenterRequest request)
    {
        var company = await _unitOfWork.Companies.GetByIdAsync(companyId);
        if (company == null)
            return NotFound(new { success = false, message = "الشركة غير موجودة" });

        if (string.IsNullOrWhiteSpace(request.Name))
            return BadRequest(new { success = false, message = "اسم المركز مطلوب" });

        // التحقق من عدم تكرار الاسم
        var exists = await _unitOfWork.WorkCenters.AnyAsync(
            c => c.CompanyId == companyId && c.Name == request.Name.Trim());
        if (exists)
            return BadRequest(new { success = false, message = $"المركز '{request.Name}' موجود بالفعل" });

        var center = new WorkCenter
        {
            Name = request.Name.Trim(),
            Description = request.Description?.Trim(),
            Latitude = request.Latitude,
            Longitude = request.Longitude,
            RadiusMeters = request.RadiusMeters ?? 200,
            CompanyId = companyId,
            IsActive = true,
        };

        await _unitOfWork.WorkCenters.AddAsync(center);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new
        {
            success = true,
            message = "تم إضافة المركز بنجاح",
            data = new CenterResponse
            {
                Id = center.Id,
                Name = center.Name,
                Description = center.Description,
                Latitude = center.Latitude,
                Longitude = center.Longitude,
                RadiusMeters = center.RadiusMeters,
                IsActive = center.IsActive,
                CreatedAt = center.CreatedAt,
            }
        });
    }

    /// <summary>
    /// تعديل مركز
    /// </summary>
    [HttpPut("{centerId:int}")]
    public async Task<IActionResult> Update(Guid companyId, int centerId, [FromBody] UpdateCenterRequest request)
    {
        var center = await _unitOfWork.WorkCenters.FirstOrDefaultAsync(
            c => c.Id == centerId && c.CompanyId == companyId);

        if (center == null)
            return NotFound(new { success = false, message = "المركز غير موجود" });

        if (!string.IsNullOrWhiteSpace(request.Name))
        {
            // التحقق من عدم تكرار الاسم
            var nameExists = await _unitOfWork.WorkCenters.AnyAsync(
                c => c.CompanyId == companyId && c.Name == request.Name.Trim() && c.Id != centerId);
            if (nameExists)
                return BadRequest(new { success = false, message = $"المركز '{request.Name}' موجود بالفعل" });
            center.Name = request.Name.Trim();
        }

        if (request.Description != null)
            center.Description = request.Description.Trim();
        if (request.Latitude.HasValue)
            center.Latitude = request.Latitude.Value;
        if (request.Longitude.HasValue)
            center.Longitude = request.Longitude.Value;
        if (request.RadiusMeters.HasValue)
            center.RadiusMeters = request.RadiusMeters.Value;
        if (request.IsActive.HasValue)
            center.IsActive = request.IsActive.Value;

        center.UpdatedAt = DateTime.UtcNow;
        _unitOfWork.WorkCenters.Update(center);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث المركز بنجاح" });
    }

    /// <summary>
    /// حذف مركز (soft delete)
    /// </summary>
    [HttpDelete("{centerId:int}")]
    public async Task<IActionResult> Delete(Guid companyId, int centerId)
    {
        var center = await _unitOfWork.WorkCenters.FirstOrDefaultAsync(
            c => c.Id == centerId && c.CompanyId == companyId);

        if (center == null)
            return NotFound(new { success = false, message = "المركز غير موجود" });

        center.IsDeleted = true;
        center.DeletedAt = DateTime.UtcNow;
        _unitOfWork.WorkCenters.Update(center);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف المركز بنجاح" });
    }
}

// ==================== DTOs ====================

public class CenterResponse
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double RadiusMeters { get; set; }
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
}

public record CreateCenterRequest(
    string Name,
    string? Description,
    double Latitude,
    double Longitude,
    double? RadiusMeters);

public record UpdateCenterRequest(
    string? Name,
    string? Description,
    double? Latitude,
    double? Longitude,
    double? RadiusMeters,
    bool? IsActive);
