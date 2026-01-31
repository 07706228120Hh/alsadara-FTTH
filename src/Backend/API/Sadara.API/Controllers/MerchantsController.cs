using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class MerchantsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public MerchantsController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetAll([FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var query = _unitOfWork.Merchants.AsQueryable();
        var total = await query.CountAsync();
        var merchants = await query
            .OrderByDescending(m => m.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return Ok(new { success = true, data = merchants, total, page, pageSize });
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var merchant = await _unitOfWork.Merchants.GetByIdAsync(id);
        if (merchant == null)
            return NotFound(new { success = false, message = "التاجر غير موجود" });

        return Ok(new { success = true, data = merchant });
    }

    [HttpGet("by-user/{userId:guid}")]
    public async Task<IActionResult> GetByUserId(Guid userId)
    {
        var merchant = await _unitOfWork.Merchants.FirstOrDefaultAsync(m => m.UserId == userId);
        if (merchant == null)
            return NotFound(new { success = false, message = "التاجر غير موجود" });

        return Ok(new { success = true, data = merchant });
    }

    [HttpPost]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Create([FromBody] CreateMerchantRequest request)
    {
        var merchant = new Merchant
        {
            Id = Guid.NewGuid(),
            UserId = request.UserId,
            BusinessName = request.BusinessName,
            BusinessNameAr = request.BusinessNameAr ?? request.BusinessName,
            Description = request.Description ?? string.Empty,
            DescriptionAr = request.DescriptionAr ?? string.Empty,
            LogoUrl = request.LogoUrl ?? string.Empty,
            PhoneNumber = request.PhoneNumber ?? string.Empty,
            Email = request.Email ?? string.Empty,
            City = request.City ?? string.Empty,
            Area = request.Area ?? string.Empty,
            FullAddress = request.FullAddress ?? string.Empty,
            SubscriptionPlan = Sadara.Domain.Enums.SubscriptionPlan.Free,
            MaxCustomers = 100,
            CommissionRate = 5m,
            IsActive = true,
            CreatedAt = DateTime.UtcNow
        };

        await _unitOfWork.Merchants.AddAsync(merchant);
        await _unitOfWork.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = merchant.Id }, new { success = true, data = merchant });
    }

    [HttpPut("{id:guid}")]
    [Authorize(Policy = "Merchant")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateMerchantRequest request)
    {
        var merchant = await _unitOfWork.Merchants.GetByIdAsync(id);
        if (merchant == null)
            return NotFound(new { success = false, message = "التاجر غير موجود" });

        merchant.BusinessName = request.BusinessName ?? merchant.BusinessName;
        merchant.BusinessNameAr = request.BusinessNameAr ?? merchant.BusinessNameAr;
        merchant.Description = request.Description ?? merchant.Description;
        merchant.LogoUrl = request.LogoUrl ?? merchant.LogoUrl;
        merchant.PhoneNumber = request.PhoneNumber ?? merchant.PhoneNumber;
        merchant.City = request.City ?? merchant.City;
        merchant.Area = request.Area ?? merchant.Area;
        merchant.FullAddress = request.FullAddress ?? merchant.FullAddress;
        merchant.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Merchants.Update(merchant);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, data = merchant });
    }

    [HttpPatch("{id:guid}/verify")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Verify(Guid id)
    {
        var merchant = await _unitOfWork.Merchants.GetByIdAsync(id);
        if (merchant == null)
            return NotFound(new { success = false, message = "التاجر غير موجود" });

        merchant.IsVerified = true;
        merchant.VerifiedAt = DateTime.UtcNow;
        _unitOfWork.Merchants.Update(merchant);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم توثيق التاجر بنجاح" });
    }

    [HttpPatch("{id:guid}/subscription")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> UpdateSubscription(Guid id, [FromBody] UpdateSubscriptionRequest request)
    {
        var merchant = await _unitOfWork.Merchants.GetByIdAsync(id);
        if (merchant == null)
            return NotFound(new { success = false, message = "التاجر غير موجود" });

        merchant.SubscriptionPlan = request.Plan;
        merchant.MaxCustomers = request.MaxCustomers;
        merchant.SubscriptionExpiresAt = request.ExpiresAt;
        _unitOfWork.Merchants.Update(merchant);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث الاشتراك بنجاح" });
    }

    [HttpGet("{id:guid}/stats")]
    [Authorize(Policy = "Merchant")]
    public async Task<IActionResult> GetStats(Guid id)
    {
        var merchant = await _unitOfWork.Merchants.GetByIdAsync(id);
        if (merchant == null)
            return NotFound(new { success = false, message = "التاجر غير موجود" });

        var customersCount = await _unitOfWork.Customers.CountAsync(c => c.MerchantId == id);
        var productsCount = await _unitOfWork.Products.CountAsync(p => p.MerchantId == id);
        var ordersCount = await _unitOfWork.Orders.CountAsync(o => o.MerchantId == id);

        return Ok(new
        {
            success = true,
            data = new
            {
                totalCustomers = customersCount,
                totalProducts = productsCount,
                totalOrders = ordersCount,
                maxCustomers = merchant.MaxCustomers,
                subscriptionPlan = merchant.SubscriptionPlan.ToString()
            }
        });
    }
}

public record CreateMerchantRequest(
    Guid UserId,
    string BusinessName,
    string? BusinessNameAr,
    string? Description,
    string? DescriptionAr,
    string? LogoUrl,
    string? PhoneNumber,
    string? Email,
    string? City,
    string? Area,
    string? FullAddress
);

public record UpdateMerchantRequest(
    string? BusinessName,
    string? BusinessNameAr,
    string? Description,
    string? LogoUrl,
    string? PhoneNumber,
    string? City,
    string? Area,
    string? FullAddress
);

public record UpdateSubscriptionRequest(
    Sadara.Domain.Enums.SubscriptionPlan Plan,
    int MaxCustomers,
    DateTime? ExpiresAt
);
