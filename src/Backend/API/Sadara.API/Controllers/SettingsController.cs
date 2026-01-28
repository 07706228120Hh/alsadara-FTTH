using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = "Admin")]
public class SettingsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public SettingsController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var settings = await _unitOfWork.Settings.AsQueryable()
            .OrderBy(s => s.Category)
            .ThenBy(s => s.Key)
            .Select(s => new
            {
                s.Id,
                s.Key,
                s.Value,
                s.Category,
                s.Description,
                s.IsPublic,
                s.UpdatedAt
            })
            .ToListAsync();

        return Ok(new { success = true, data = settings });
    }

    [HttpGet("public")]
    [AllowAnonymous]
    public async Task<IActionResult> GetPublic()
    {
        var settings = await _unitOfWork.Settings.AsQueryable()
            .Where(s => s.IsPublic)
            .ToDictionaryAsync(s => s.Key, s => s.Value);

        return Ok(new { success = true, data = settings });
    }

    [HttpGet("{key}")]
    [AllowAnonymous]
    public async Task<IActionResult> GetByKey(string key)
    {
        var setting = await _unitOfWork.Settings.FirstOrDefaultAsync(s => s.Key == key);
        
        if (setting == null)
            return NotFound(new { success = false, message = "الإعداد غير موجود" });

        // Check if public setting or admin request
        if (!setting.IsPublic && !User.IsInRole("Admin"))
            return Forbid();

        return Ok(new { success = true, data = new { setting.Key, setting.Value } });
    }

    [HttpGet("category/{category}")]
    public async Task<IActionResult> GetByCategory(string category)
    {
        var settings = await _unitOfWork.Settings.AsQueryable()
            .Where(s => s.Category == category)
            .ToDictionaryAsync(s => s.Key, s => s.Value);

        return Ok(new { success = true, data = settings });
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateSettingRequest request)
    {
        var exists = await _unitOfWork.Settings.AnyAsync(s => s.Key == request.Key);
        if (exists)
            return BadRequest(new { success = false, message = "الإعداد موجود مسبقاً" });

        var setting = new Sadara.Domain.Entities.Setting
        {
            Key = request.Key,
            Value = request.Value,
            Category = request.Category,
            Description = request.Description,
            IsPublic = request.IsPublic
        };

        await _unitOfWork.Settings.AddAsync(setting);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم إنشاء الإعداد بنجاح" });
    }

    [HttpPut("{key}")]
    public async Task<IActionResult> Update(string key, [FromBody] UpdateSettingRequest request)
    {
        var setting = await _unitOfWork.Settings.FirstOrDefaultAsync(s => s.Key == key);
        if (setting == null)
            return NotFound(new { success = false, message = "الإعداد غير موجود" });

        setting.Value = request.Value ?? setting.Value;
        setting.Description = request.Description ?? setting.Description;
        setting.IsPublic = request.IsPublic ?? setting.IsPublic;
        setting.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Settings.Update(setting);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث الإعداد بنجاح" });
    }

    [HttpPut("bulk")]
    public async Task<IActionResult> BulkUpdate([FromBody] Dictionary<string, string> settings)
    {
        foreach (var kvp in settings)
        {
            var setting = await _unitOfWork.Settings.FirstOrDefaultAsync(s => s.Key == kvp.Key);
            if (setting != null)
            {
                setting.Value = kvp.Value;
                setting.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.Settings.Update(setting);
            }
        }

        await _unitOfWork.SaveChangesAsync();
        return Ok(new { success = true, message = "تم تحديث الإعدادات بنجاح" });
    }

    [HttpDelete("{key}")]
    public async Task<IActionResult> Delete(string key)
    {
        var setting = await _unitOfWork.Settings.FirstOrDefaultAsync(s => s.Key == key);
        if (setting == null)
            return NotFound(new { success = false, message = "الإعداد غير موجود" });

        _unitOfWork.Settings.Delete(setting);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف الإعداد بنجاح" });
    }
}

public class CreateSettingRequest
{
    public string Key { get; set; } = string.Empty;
    public string Value { get; set; } = string.Empty;
    public string Category { get; set; } = "General";
    public string? Description { get; set; }
    public bool IsPublic { get; set; }
}

public class UpdateSettingRequest
{
    public string? Value { get; set; }
    public string? Description { get; set; }
    public bool? IsPublic { get; set; }
}
