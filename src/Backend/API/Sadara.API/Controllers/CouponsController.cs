using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class CouponsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public CouponsController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetAll(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] bool? isActive = null)
    {
        var query = _unitOfWork.Coupons.AsQueryable();

        if (isActive.HasValue)
        {
            query = query.Where(c => c.IsActive == isActive.Value);
        }

        var totalItems = await query.CountAsync();
        var totalPages = (int)Math.Ceiling(totalItems / (double)pageSize);

        var coupons = await query
            .OrderByDescending(c => c.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(c => new
            {
                c.Id,
                c.Code,
                c.Description,
                c.DescriptionAr,
                discountType = c.DiscountType.ToString(),
                c.DiscountValue,
                c.MinimumOrderAmount,
                c.MaximumDiscountAmount,
                c.UsageLimit,
                c.UsedCount,
                c.StartDate,
                c.EndDate,
                c.IsActive,
                isExpired = c.EndDate < DateTime.UtcNow,
                isExhausted = c.UsageLimit.HasValue && c.UsedCount >= c.UsageLimit
            })
            .ToListAsync();

        return Ok(new
        {
            success = true,
            data = coupons,
            pagination = new { currentPage = page, pageSize, totalItems, totalPages }
        });
    }

    [HttpGet("{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var coupon = await _unitOfWork.Coupons.GetByIdAsync(id);
        if (coupon == null)
            return NotFound(new { success = false, message = "الكوبون غير موجود" });

        return Ok(new
        {
            success = true,
            data = new
            {
                coupon.Id,
                coupon.Code,
                coupon.Description,
                coupon.DescriptionAr,
                discountType = coupon.DiscountType.ToString(),
                coupon.DiscountValue,
                coupon.MinimumOrderAmount,
                coupon.MaximumDiscountAmount,
                coupon.UsageLimit,
                coupon.UsedCount,
                coupon.StartDate,
                coupon.EndDate,
                coupon.IsActive,
                coupon.MerchantId,
                coupon.CategoryId
            }
        });
    }

    [HttpPost("validate")]
    [Authorize]
    public async Task<IActionResult> ValidateCoupon([FromBody] ValidateCouponRequest request)
    {
        var coupon = await _unitOfWork.Coupons.FirstOrDefaultAsync(c => c.Code == request.Code);
        
        if (coupon == null)
            return NotFound(new { success = false, message = "الكوبون غير موجود", isValid = false });

        if (!coupon.IsActive)
            return BadRequest(new { success = false, message = "الكوبون غير مفعل", isValid = false });

        if (coupon.StartDate > DateTime.UtcNow)
            return BadRequest(new { success = false, message = "الكوبون لم يبدأ بعد", isValid = false });

        if (coupon.EndDate < DateTime.UtcNow)
            return BadRequest(new { success = false, message = "الكوبون منتهي الصلاحية", isValid = false });

        if (coupon.UsageLimit.HasValue && coupon.UsedCount >= coupon.UsageLimit)
            return BadRequest(new { success = false, message = "تم استنفاد الكوبون", isValid = false });

        if (coupon.MinimumOrderAmount.HasValue && request.OrderTotal < coupon.MinimumOrderAmount)
            return BadRequest(new
            {
                success = false,
                message = $"الحد الأدنى للطلب {coupon.MinimumOrderAmount} دينار",
                isValid = false,
                minimumAmount = coupon.MinimumOrderAmount
            });

        // Calculate discount
        decimal discount = 0;
        if (coupon.DiscountType == Sadara.Domain.Enums.DiscountType.Percentage)
        {
            discount = request.OrderTotal * (coupon.DiscountValue / 100);
            if (coupon.MaximumDiscountAmount.HasValue && discount > coupon.MaximumDiscountAmount)
                discount = coupon.MaximumDiscountAmount.Value;
        }
        else // Fixed amount
        {
            discount = coupon.DiscountValue;
            if (discount > request.OrderTotal)
                discount = request.OrderTotal;
        }

        return Ok(new
        {
            success = true,
            isValid = true,
            data = new
            {
                coupon.Code,
                discountType = coupon.DiscountType.ToString(),
                coupon.DiscountValue,
                calculatedDiscount = discount,
                finalTotal = request.OrderTotal - discount
            }
        });
    }

    [HttpPost]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Create([FromBody] CreateCouponRequest request)
    {
        // Check if code already exists
        var exists = await _unitOfWork.Coupons.AnyAsync(c => c.Code == request.Code);
        if (exists)
            return BadRequest(new { success = false, message = "رمز الكوبون مستخدم مسبقاً" });

        var coupon = new Sadara.Domain.Entities.Coupon
        {
            Code = request.Code.ToUpper(),
            Description = request.Description,
            DescriptionAr = request.DescriptionAr,
            DiscountType = Enum.Parse<Sadara.Domain.Enums.DiscountType>(request.DiscountType),
            DiscountValue = request.DiscountValue,
            MinimumOrderAmount = request.MinimumOrderAmount,
            MaximumDiscountAmount = request.MaximumDiscountAmount,
            UsageLimit = request.UsageLimit,
            UsedCount = 0,
            StartDate = request.StartDate,
            EndDate = request.EndDate,
            IsActive = request.IsActive,
            MerchantId = request.MerchantId,
            CategoryId = request.CategoryId
        };

        await _unitOfWork.Coupons.AddAsync(coupon);
        await _unitOfWork.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = coupon.Id }, new
        {
            success = true,
            message = "تم إنشاء الكوبون بنجاح",
            data = coupon.Id
        });
    }

    [HttpPut("{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateCouponRequest request)
    {
        var coupon = await _unitOfWork.Coupons.GetByIdAsync(id);
        if (coupon == null)
            return NotFound(new { success = false, message = "الكوبون غير موجود" });

        // Check if new code conflicts
        if (!string.IsNullOrEmpty(request.Code) && request.Code != coupon.Code)
        {
            var exists = await _unitOfWork.Coupons.AnyAsync(c => c.Code == request.Code && c.Id != id);
            if (exists)
                return BadRequest(new { success = false, message = "رمز الكوبون مستخدم مسبقاً" });
            coupon.Code = request.Code.ToUpper();
        }

        coupon.Description = request.Description ?? coupon.Description;
        coupon.DescriptionAr = request.DescriptionAr ?? coupon.DescriptionAr;
        coupon.DiscountValue = request.DiscountValue ?? coupon.DiscountValue;
        coupon.MinimumOrderAmount = request.MinimumOrderAmount ?? coupon.MinimumOrderAmount;
        coupon.MaximumDiscountAmount = request.MaximumDiscountAmount ?? coupon.MaximumDiscountAmount;
        coupon.UsageLimit = request.UsageLimit ?? coupon.UsageLimit;
        coupon.StartDate = request.StartDate ?? coupon.StartDate;
        coupon.EndDate = request.EndDate ?? coupon.EndDate;
        coupon.IsActive = request.IsActive ?? coupon.IsActive;
        coupon.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Coupons.Update(coupon);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث الكوبون بنجاح" });
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var coupon = await _unitOfWork.Coupons.GetByIdAsync(id);
        if (coupon == null)
            return NotFound(new { success = false, message = "الكوبون غير موجود" });

        _unitOfWork.Coupons.Delete(coupon);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف الكوبون بنجاح" });
    }

    [HttpPatch("{id}/toggle")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> ToggleActive(Guid id)
    {
        var coupon = await _unitOfWork.Coupons.GetByIdAsync(id);
        if (coupon == null)
            return NotFound(new { success = false, message = "الكوبون غير موجود" });

        coupon.IsActive = !coupon.IsActive;
        coupon.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Coupons.Update(coupon);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new
        {
            success = true,
            message = coupon.IsActive ? "تم تفعيل الكوبون" : "تم إلغاء تفعيل الكوبون"
        });
    }
}

public class ValidateCouponRequest
{
    public string Code { get; set; } = string.Empty;
    public decimal OrderTotal { get; set; }
}

public class CreateCouponRequest
{
    public string Code { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? DescriptionAr { get; set; }
    public string DiscountType { get; set; } = "Percentage"; // Percentage or Fixed
    public decimal DiscountValue { get; set; }
    public decimal? MinimumOrderAmount { get; set; }
    public decimal? MaximumDiscountAmount { get; set; }
    public int? UsageLimit { get; set; }
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public bool IsActive { get; set; } = true;
    public Guid? MerchantId { get; set; }
    public Guid? CategoryId { get; set; }
}

public class UpdateCouponRequest
{
    public string? Code { get; set; }
    public string? Description { get; set; }
    public string? DescriptionAr { get; set; }
    public decimal? DiscountValue { get; set; }
    public decimal? MinimumOrderAmount { get; set; }
    public decimal? MaximumDiscountAmount { get; set; }
    public int? UsageLimit { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public bool? IsActive { get; set; }
}
