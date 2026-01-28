using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class CitiesController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public CitiesController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var cities = await _unitOfWork.Cities.AsQueryable()
            .Where(c => c.IsActive)
            .OrderBy(c => c.DisplayOrder)
            .ThenBy(c => c.Name)
            .Select(c => new
            {
                c.Id,
                c.Name,
                c.NameAr,
                c.GovernorateCode,
                c.DisplayOrder,
                areaCount = c.Areas.Count(a => a.IsActive)
            })
            .ToListAsync();

        return Ok(new { success = true, data = cities });
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var city = await _unitOfWork.Cities.AsQueryable()
            .Where(c => c.Id == id)
            .Select(c => new
            {
                c.Id,
                c.Name,
                c.NameAr,
                c.GovernorateCode,
                c.DisplayOrder,
                c.IsActive,
                c.DeliveryFee,
                areaCount = c.Areas.Count(a => a.IsActive)
            })
            .FirstOrDefaultAsync();

        if (city == null)
            return NotFound(new { success = false, message = "المدينة غير موجودة" });

        return Ok(new { success = true, data = city });
    }

    [HttpGet("{id}/areas")]
    public async Task<IActionResult> GetCityAreas(Guid id)
    {
        var cityExists = await _unitOfWork.Cities.AnyAsync(c => c.Id == id);
        if (!cityExists)
            return NotFound(new { success = false, message = "المدينة غير موجودة" });

        var areas = await _unitOfWork.Areas.AsQueryable()
            .Where(a => a.CityId == id && a.IsActive)
            .OrderBy(a => a.Name)
            .Select(a => new
            {
                a.Id,
                a.Name,
                a.NameAr,
                a.DeliveryFee
            })
            .ToListAsync();

        return Ok(new { success = true, data = areas });
    }

    [HttpGet("with-areas")]
    public async Task<IActionResult> GetAllWithAreas()
    {
        var cities = await _unitOfWork.Cities.AsQueryable()
            .Where(c => c.IsActive)
            .OrderBy(c => c.DisplayOrder)
            .Select(c => new
            {
                c.Id,
                c.Name,
                c.NameAr,
                c.DeliveryFee,
                areas = c.Areas
                    .Where(a => a.IsActive)
                    .OrderBy(a => a.Name)
                    .Select(a => new
                    {
                        a.Id,
                        a.Name,
                        a.NameAr,
                        a.DeliveryFee
                    })
                    .ToList()
            })
            .ToListAsync();

        return Ok(new { success = true, data = cities });
    }

    [HttpPost]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Create([FromBody] CreateCityRequest request)
    {
        var city = new Sadara.Domain.Entities.City
        {
            Name = request.Name,
            NameAr = request.NameAr,
            GovernorateCode = request.GovernorateCode,
            DisplayOrder = request.DisplayOrder,
            DeliveryFee = request.DeliveryFee,
            IsActive = true
        };

        await _unitOfWork.Cities.AddAsync(city);
        await _unitOfWork.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = city.Id }, new
        {
            success = true,
            message = "تم إنشاء المدينة بنجاح",
            data = city.Id
        });
    }

    [HttpPut("{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateCityRequest request)
    {
        var city = await _unitOfWork.Cities.GetByIdAsync(id);
        if (city == null)
            return NotFound(new { success = false, message = "المدينة غير موجودة" });

        city.Name = request.Name ?? city.Name;
        city.NameAr = request.NameAr ?? city.NameAr;
        city.GovernorateCode = request.GovernorateCode ?? city.GovernorateCode;
        city.DisplayOrder = request.DisplayOrder ?? city.DisplayOrder;
        city.DeliveryFee = request.DeliveryFee ?? city.DeliveryFee;
        city.IsActive = request.IsActive ?? city.IsActive;
        city.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Cities.Update(city);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث المدينة بنجاح" });
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var city = await _unitOfWork.Cities.GetByIdAsync(id);
        if (city == null)
            return NotFound(new { success = false, message = "المدينة غير موجودة" });

        _unitOfWork.Cities.Delete(city);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف المدينة بنجاح" });
    }
}

[ApiController]
[Route("api/[controller]")]
public class AreasController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public AreasController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var areas = await _unitOfWork.Areas.AsQueryable()
            .Where(a => a.IsActive)
            .OrderBy(a => a.Name)
            .Select(a => new
            {
                a.Id,
                a.Name,
                a.NameAr,
                a.CityId,
                cityName = a.City.Name,
                cityNameAr = a.City.NameAr,
                a.DeliveryFee
            })
            .ToListAsync();

        return Ok(new { success = true, data = areas });
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var area = await _unitOfWork.Areas.AsQueryable()
            .Where(a => a.Id == id)
            .Select(a => new
            {
                a.Id,
                a.Name,
                a.NameAr,
                a.CityId,
                cityName = a.City.Name,
                cityNameAr = a.City.NameAr,
                a.DeliveryFee,
                a.IsActive
            })
            .FirstOrDefaultAsync();

        if (area == null)
            return NotFound(new { success = false, message = "المنطقة غير موجودة" });

        return Ok(new { success = true, data = area });
    }

    [HttpPost]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Create([FromBody] CreateAreaRequest request)
    {
        var cityExists = await _unitOfWork.Cities.AnyAsync(c => c.Id == request.CityId);
        if (!cityExists)
            return BadRequest(new { success = false, message = "المدينة غير موجودة" });

        var area = new Sadara.Domain.Entities.Area
        {
            Name = request.Name,
            NameAr = request.NameAr,
            CityId = request.CityId,
            DeliveryFee = request.DeliveryFee,
            IsActive = true
        };

        await _unitOfWork.Areas.AddAsync(area);
        await _unitOfWork.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = area.Id }, new
        {
            success = true,
            message = "تم إنشاء المنطقة بنجاح",
            data = area.Id
        });
    }

    [HttpPut("{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateAreaRequest request)
    {
        var area = await _unitOfWork.Areas.GetByIdAsync(id);
        if (area == null)
            return NotFound(new { success = false, message = "المنطقة غير موجودة" });

        area.Name = request.Name ?? area.Name;
        area.NameAr = request.NameAr ?? area.NameAr;
        area.DeliveryFee = request.DeliveryFee ?? area.DeliveryFee;
        area.IsActive = request.IsActive ?? area.IsActive;
        area.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Areas.Update(area);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث المنطقة بنجاح" });
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var area = await _unitOfWork.Areas.GetByIdAsync(id);
        if (area == null)
            return NotFound(new { success = false, message = "المنطقة غير موجودة" });

        _unitOfWork.Areas.Delete(area);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف المنطقة بنجاح" });
    }
}

public class CreateCityRequest
{
    public string Name { get; set; } = string.Empty;
    public string NameAr { get; set; } = string.Empty;
    public string? GovernorateCode { get; set; }
    public int DisplayOrder { get; set; }
    public decimal DeliveryFee { get; set; }
}

public class UpdateCityRequest
{
    public string? Name { get; set; }
    public string? NameAr { get; set; }
    public string? GovernorateCode { get; set; }
    public int? DisplayOrder { get; set; }
    public decimal? DeliveryFee { get; set; }
    public bool? IsActive { get; set; }
}

public class CreateAreaRequest
{
    public string Name { get; set; } = string.Empty;
    public string NameAr { get; set; } = string.Empty;
    public Guid CityId { get; set; }
    public decimal DeliveryFee { get; set; }
}

public class UpdateAreaRequest
{
    public string? Name { get; set; }
    public string? NameAr { get; set; }
    public decimal? DeliveryFee { get; set; }
    public bool? IsActive { get; set; }
}
