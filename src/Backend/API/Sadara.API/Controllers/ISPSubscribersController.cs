using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ISPSubscribersController(IUnitOfWork unitOfWork) : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork = unitOfWork;

    /// <summary>جلب جميع المشتركين مع التصفية</summary>
    [HttpGet]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetAll(
        [FromQuery] string? region,
        [FromQuery] string? search,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var query = _unitOfWork.ISPSubscribers.AsQueryable();

        if (!string.IsNullOrEmpty(region))
            query = query.Where(s => s.Region == region);

        if (!string.IsNullOrEmpty(search))
            query = query.Where(s => s.Name.Contains(search) || 
                                     (s.PhoneNumber != null && s.PhoneNumber.Contains(search)));

        var total = await query.CountAsync();
        var items = await query
            .OrderBy(s => s.Name)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return Ok(new { total, page, pageSize, items });
    }

    /// <summary>جلب قائمة المناطق</summary>
    [HttpGet("regions")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetRegions()
    {
        var regions = await _unitOfWork.ISPSubscribers.AsQueryable()
            .Where(s => s.Region != null && s.Region != "")
            .Select(s => s.Region!)
            .Distinct()
            .OrderBy(r => r)
            .ToListAsync();

        return Ok(regions);
    }

    /// <summary>بحث القرابة (يدعم البحث الغامض)</summary>
    [HttpGet("kinship-search")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> KinshipSearch(
        [FromQuery] string? name,
        [FromQuery] string? motherName,
        [FromQuery] string? region)
    {
        var query = _unitOfWork.ISPSubscribers.AsQueryable();

        if (!string.IsNullOrEmpty(region))
            query = query.Where(s => s.Region == region);

        // جلب جميع البيانات للبحث الغامض (يتم على مستوى التطبيق)
        var allSubscribers = await query.ToListAsync();

        // إذا لم يكن هناك بحث محدد، إرجاع الكل
        if (string.IsNullOrEmpty(name) && string.IsNullOrEmpty(motherName))
        {
            return Ok(allSubscribers.Take(200));
        }

        // تصفية حسب الاسم أو اسم الأم (يمكن للعميل تنفيذ خوارزمية Levenshtein)
        var results = allSubscribers.Where(s =>
        {
            bool match = true;
            if (!string.IsNullOrEmpty(name))
                match = match && (s.Name.Contains(name, StringComparison.OrdinalIgnoreCase));
            if (!string.IsNullOrEmpty(motherName))
                match = match && (s.MotherName != null && s.MotherName.Contains(motherName, StringComparison.OrdinalIgnoreCase));
            return match;
        }).Take(500).ToList();

        return Ok(results);
    }

    /// <summary>جلب مشتركين حسب المنطقة</summary>
    [HttpGet("by-region/{region}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetByRegion(string region)
    {
        var subscribers = await _unitOfWork.ISPSubscribers.AsQueryable()
            .Where(s => s.Region == region)
            .OrderBy(s => s.Name)
            .ToListAsync();

        return Ok(subscribers);
    }

    /// <summary>إضافة مشترك جديد</summary>
    [HttpPost]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Create([FromBody] CreateISPSubscriberRequest request)
    {
        var subscriber = new ISPSubscriber
        {
            Name = request.Name,
            Region = request.Region,
            Agent = request.Agent,
            Dash = request.Dash,
            MotherName = request.MotherName,
            PhoneNumber = request.PhoneNumber,
            CompanyId = request.CompanyId,
        };

        await _unitOfWork.ISPSubscribers.AddAsync(subscriber);
        await _unitOfWork.SaveChangesAsync();

        return Ok(subscriber);
    }

    /// <summary>إضافة مشتركين بالجملة (استيراد)</summary>
    [HttpPost("bulk")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> BulkCreate([FromBody] List<CreateISPSubscriberRequest> requests)
    {
        var subscribers = requests.Select(r => new ISPSubscriber
        {
            Name = r.Name,
            Region = r.Region,
            Agent = r.Agent,
            Dash = r.Dash,
            MotherName = r.MotherName,
            PhoneNumber = r.PhoneNumber,
            CompanyId = r.CompanyId,
        }).ToList();

        foreach (var s in subscribers)
            await _unitOfWork.ISPSubscribers.AddAsync(s);

        await _unitOfWork.SaveChangesAsync();

        return Ok(new { message = $"تم إضافة {subscribers.Count} مشترك", count = subscribers.Count });
    }

    /// <summary>تحديث مشترك</summary>
    [HttpPut("{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Update(long id, [FromBody] CreateISPSubscriberRequest request)
    {
        var subscriber = await _unitOfWork.ISPSubscribers.GetByIdAsync(id);
        if (subscriber == null) return NotFound();

        subscriber.Name = request.Name;
        subscriber.Region = request.Region;
        subscriber.Agent = request.Agent;
        subscriber.Dash = request.Dash;
        subscriber.MotherName = request.MotherName;
        subscriber.PhoneNumber = request.PhoneNumber;
        subscriber.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.ISPSubscribers.Update(subscriber);
        await _unitOfWork.SaveChangesAsync();

        return Ok(subscriber);
    }

    /// <summary>حذف مشترك</summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Delete(long id)
    {
        var subscriber = await _unitOfWork.ISPSubscribers.GetByIdAsync(id);
        if (subscriber == null) return NotFound();

        subscriber.IsDeleted = true;
        subscriber.DeletedAt = DateTime.UtcNow;
        _unitOfWork.ISPSubscribers.Update(subscriber);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { message = "تم الحذف بنجاح" });
    }
}

public record CreateISPSubscriberRequest(
    string Name, string? Region, string? Agent, string? Dash, 
    string? MotherName, string? PhoneNumber, Guid? CompanyId);
