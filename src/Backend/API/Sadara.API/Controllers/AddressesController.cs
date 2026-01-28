using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class AddressesController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public AddressesController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet]
    public async Task<IActionResult> GetMyAddresses()
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        var addresses = await _unitOfWork.Addresses.AsQueryable()
            .Where(a => a.CustomerId == customer.Id)
            .OrderByDescending(a => a.IsDefault)
            .ThenByDescending(a => a.CreatedAt)
            .Select(a => new
            {
                a.Id,
                a.Label,
                a.FullAddress,
                a.Street,
                a.Building,
                a.Floor,
                a.Apartment,
                a.AdditionalInfo,
                a.Latitude,
                a.Longitude,
                a.IsDefault,
                city = new { a.City.Id, a.City.Name, a.City.NameAr },
                area = a.Area != null ? new { a.Area.Id, a.Area.Name, a.Area.NameAr } : null
            })
            .ToListAsync();

        return Ok(new { success = true, data = addresses });
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        var address = await _unitOfWork.Addresses.AsQueryable()
            .Where(a => a.Id == id && a.CustomerId == customer.Id)
            .Select(a => new
            {
                a.Id,
                a.Label,
                a.FullAddress,
                a.Street,
                a.Building,
                a.Floor,
                a.Apartment,
                a.AdditionalInfo,
                a.Latitude,
                a.Longitude,
                a.IsDefault,
                a.CityId,
                a.AreaId,
                city = new { a.City.Id, a.City.Name, a.City.NameAr },
                area = a.Area != null ? new { a.Area.Id, a.Area.Name, a.Area.NameAr } : null
            })
            .FirstOrDefaultAsync();

        if (address == null)
            return NotFound(new { success = false, message = "العنوان غير موجود" });

        return Ok(new { success = true, data = address });
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateAddressRequest request)
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        // Validate city
        var cityExists = await _unitOfWork.Cities.AnyAsync(c => c.Id == request.CityId && c.IsActive);
        if (!cityExists)
            return BadRequest(new { success = false, message = "المدينة غير موجودة" });

        // Validate area if provided
        if (request.AreaId.HasValue)
        {
            var areaExists = await _unitOfWork.Areas
                .AnyAsync(a => a.Id == request.AreaId && a.CityId == request.CityId && a.IsActive);
            if (!areaExists)
                return BadRequest(new { success = false, message = "المنطقة غير موجودة أو لا تتبع للمدينة المحددة" });
        }

        // If this is the first address or marked as default, make it default
        var hasAddresses = await _unitOfWork.Addresses.AnyAsync(a => a.CustomerId == customer.Id);
        var shouldBeDefault = request.IsDefault || !hasAddresses;

        // If setting as default, unset other defaults
        if (shouldBeDefault)
        {
            var existingDefaults = await _unitOfWork.Addresses.AsQueryable()
                .Where(a => a.CustomerId == customer.Id && a.IsDefault)
                .ToListAsync();

            foreach (var addr in existingDefaults)
            {
                addr.IsDefault = false;
                _unitOfWork.Addresses.Update(addr);
            }
        }

        var address = new Sadara.Domain.Entities.Address
        {
            CustomerId = customer.Id,
            Label = request.Label,
            FullAddress = request.FullAddress,
            Street = request.Street,
            Building = request.Building,
            Floor = request.Floor,
            Apartment = request.Apartment,
            AdditionalInfo = request.AdditionalInfo,
            CityId = request.CityId,
            AreaId = request.AreaId,
            Latitude = request.Latitude,
            Longitude = request.Longitude,
            IsDefault = shouldBeDefault
        };

        await _unitOfWork.Addresses.AddAsync(address);
        await _unitOfWork.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = address.Id }, new
        {
            success = true,
            message = "تم إضافة العنوان بنجاح",
            data = address.Id
        });
    }

    [HttpPut("{id}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateAddressRequest request)
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        var address = await _unitOfWork.Addresses.GetByIdAsync(id);
        if (address == null || address.CustomerId != customer.Id)
            return NotFound(new { success = false, message = "العنوان غير موجود" });

        // Validate city if changed
        if (request.CityId.HasValue && request.CityId != address.CityId)
        {
            var cityExists = await _unitOfWork.Cities.AnyAsync(c => c.Id == request.CityId && c.IsActive);
            if (!cityExists)
                return BadRequest(new { success = false, message = "المدينة غير موجودة" });
        }

        // Update fields
        address.Label = request.Label ?? address.Label;
        address.FullAddress = request.FullAddress ?? address.FullAddress;
        address.Street = request.Street ?? address.Street;
        address.Building = request.Building ?? address.Building;
        address.Floor = request.Floor ?? address.Floor;
        address.Apartment = request.Apartment ?? address.Apartment;
        address.AdditionalInfo = request.AdditionalInfo ?? address.AdditionalInfo;
        address.CityId = request.CityId ?? address.CityId;
        address.AreaId = request.AreaId ?? address.AreaId;
        address.Latitude = request.Latitude ?? address.Latitude;
        address.Longitude = request.Longitude ?? address.Longitude;
        address.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Addresses.Update(address);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث العنوان بنجاح" });
    }

    [HttpPatch("{id}/default")]
    public async Task<IActionResult> SetAsDefault(Guid id)
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        var address = await _unitOfWork.Addresses.GetByIdAsync(id);
        if (address == null || address.CustomerId != customer.Id)
            return NotFound(new { success = false, message = "العنوان غير موجود" });

        // Unset other defaults
        var existingDefaults = await _unitOfWork.Addresses.AsQueryable()
            .Where(a => a.CustomerId == customer.Id && a.IsDefault && a.Id != id)
            .ToListAsync();

        foreach (var addr in existingDefaults)
        {
            addr.IsDefault = false;
            _unitOfWork.Addresses.Update(addr);
        }

        address.IsDefault = true;
        address.UpdatedAt = DateTime.UtcNow;
        _unitOfWork.Addresses.Update(address);

        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تعيين العنوان كافتراضي" });
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        var address = await _unitOfWork.Addresses.GetByIdAsync(id);
        if (address == null || address.CustomerId != customer.Id)
            return NotFound(new { success = false, message = "العنوان غير موجود" });

        var wasDefault = address.IsDefault;

        _unitOfWork.Addresses.Delete(address);
        await _unitOfWork.SaveChangesAsync();

        // If deleted address was default, set another as default
        if (wasDefault)
        {
            var nextAddress = await _unitOfWork.Addresses.AsQueryable()
                .Where(a => a.CustomerId == customer.Id)
                .OrderByDescending(a => a.CreatedAt)
                .FirstOrDefaultAsync();

            if (nextAddress != null)
            {
                nextAddress.IsDefault = true;
                _unitOfWork.Addresses.Update(nextAddress);
                await _unitOfWork.SaveChangesAsync();
            }
        }

        return Ok(new { success = true, message = "تم حذف العنوان بنجاح" });
    }
}

public class CreateAddressRequest
{
    public string Label { get; set; } = string.Empty; // e.g., "المنزل", "العمل"
    public string FullAddress { get; set; } = string.Empty;
    public string? Street { get; set; }
    public string? Building { get; set; }
    public string? Floor { get; set; }
    public string? Apartment { get; set; }
    public string? AdditionalInfo { get; set; }
    public Guid CityId { get; set; }
    public Guid? AreaId { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public bool IsDefault { get; set; }
}

public class UpdateAddressRequest
{
    public string? Label { get; set; }
    public string? FullAddress { get; set; }
    public string? Street { get; set; }
    public string? Building { get; set; }
    public string? Floor { get; set; }
    public string? Apartment { get; set; }
    public string? AdditionalInfo { get; set; }
    public Guid? CityId { get; set; }
    public Guid? AreaId { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
}
