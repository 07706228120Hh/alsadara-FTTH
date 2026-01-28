using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ReviewsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public ReviewsController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet("product/{productId}")]
    [AllowAnonymous]
    public async Task<IActionResult> GetProductReviews(
        Guid productId,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        var productExists = await _unitOfWork.Products.AnyAsync(p => p.Id == productId);
        if (!productExists)
            return NotFound(new { success = false, message = "المنتج غير موجود" });

        var query = _unitOfWork.Reviews.AsQueryable()
            .Where(r => r.ProductId == productId && r.IsApproved);

        var totalItems = await query.CountAsync();
        var totalPages = (int)Math.Ceiling(totalItems / (double)pageSize);

        var reviews = await query
            .OrderByDescending(r => r.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(r => new
            {
                r.Id,
                r.Rating,
                r.Comment,
                r.CreatedAt,
                customer = new
                {
                    r.Customer.Id,
                    r.Customer.FullName
                }
            })
            .ToListAsync();

        // Calculate rating summary
        var ratingStats = await _unitOfWork.Reviews.AsQueryable()
            .Where(r => r.ProductId == productId && r.IsApproved)
            .GroupBy(r => r.Rating)
            .Select(g => new { rating = g.Key, count = g.Count() })
            .ToListAsync();

        var totalReviews = ratingStats.Sum(r => r.count);
        var averageRating = totalReviews > 0 
            ? ratingStats.Sum(r => r.rating * r.count) / (double)totalReviews 
            : 0;

        return Ok(new
        {
            success = true,
            data = reviews,
            summary = new
            {
                averageRating = Math.Round(averageRating, 1),
                totalReviews,
                ratingDistribution = ratingStats.ToDictionary(r => r.rating, r => r.count)
            },
            pagination = new
            {
                currentPage = page,
                pageSize,
                totalItems,
                totalPages
            }
        });
    }

    [HttpGet("merchant/{merchantId}")]
    [AllowAnonymous]
    public async Task<IActionResult> GetMerchantReviews(
        Guid merchantId,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        var merchantExists = await _unitOfWork.Merchants.AnyAsync(m => m.Id == merchantId);
        if (!merchantExists)
            return NotFound(new { success = false, message = "التاجر غير موجود" });

        var query = _unitOfWork.Reviews.AsQueryable()
            .Where(r => r.Product.MerchantId == merchantId && r.IsApproved);

        var totalItems = await query.CountAsync();
        var totalPages = (int)Math.Ceiling(totalItems / (double)pageSize);

        var reviews = await query
            .OrderByDescending(r => r.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(r => new
            {
                r.Id,
                r.Rating,
                r.Comment,
                r.CreatedAt,
                product = new { r.Product.Id, r.Product.Name, r.Product.NameAr },
                customer = new { r.Customer.Id, r.Customer.FullName }
            })
            .ToListAsync();

        return Ok(new
        {
            success = true,
            data = reviews,
            pagination = new { currentPage = page, pageSize, totalItems, totalPages }
        });
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateReviewRequest request)
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        // Check if product exists
        var productExists = await _unitOfWork.Products.AnyAsync(p => p.Id == request.ProductId);
        if (!productExists)
            return NotFound(new { success = false, message = "المنتج غير موجود" });

        // Check if customer already reviewed this product
        var existingReview = await _unitOfWork.Reviews
            .AnyAsync(r => r.ProductId == request.ProductId && r.CustomerId == customer.Id);
        if (existingReview)
            return BadRequest(new { success = false, message = "لقد قمت بتقييم هذا المنتج مسبقاً" });

        // Check if customer has purchased this product
        var hasPurchased = await _unitOfWork.OrderItems.AsQueryable()
            .AnyAsync(oi => oi.ProductId == request.ProductId && 
                           oi.Order.CustomerId == customer.Id &&
                           oi.Order.Status == Sadara.Domain.Enums.OrderStatus.Delivered);

        if (!hasPurchased)
            return BadRequest(new { success = false, message = "يجب شراء المنتج قبل تقييمه" });

        var review = new Sadara.Domain.Entities.Review
        {
            ProductId = request.ProductId,
            CustomerId = customer.Id,
            Rating = request.Rating,
            Comment = request.Comment,
            IsApproved = false // Requires admin approval
        };

        await _unitOfWork.Reviews.AddAsync(review);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم إرسال تقييمك وسيتم مراجعته قريباً" });
    }

    [HttpPut("{id}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateReviewRequest request)
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        var review = await _unitOfWork.Reviews.GetByIdAsync(id);
        if (review == null)
            return NotFound(new { success = false, message = "التقييم غير موجود" });

        if (review.CustomerId != customer.Id)
            return Forbid();

        review.Rating = request.Rating ?? review.Rating;
        review.Comment = request.Comment ?? review.Comment;
        review.IsApproved = false; // Requires re-approval after edit
        review.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Reviews.Update(review);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث التقييم وسيتم مراجعته قريباً" });
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var review = await _unitOfWork.Reviews.GetByIdAsync(id);
        if (review == null)
            return NotFound(new { success = false, message = "التقييم غير موجود" });

        // Admin or owner can delete
        var isAdmin = User.IsInRole("Admin");
        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);

        if (!isAdmin && (customer == null || review.CustomerId != customer.Id))
            return Forbid();

        _unitOfWork.Reviews.Delete(review);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف التقييم بنجاح" });
    }

    [HttpPatch("{id}/approve")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Approve(Guid id)
    {
        var review = await _unitOfWork.Reviews.GetByIdAsync(id);
        if (review == null)
            return NotFound(new { success = false, message = "التقييم غير موجود" });

        review.IsApproved = true;
        review.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Reviews.Update(review);
        await _unitOfWork.SaveChangesAsync();

        // Update product average rating
        await UpdateProductRating(review.ProductId);

        return Ok(new { success = true, message = "تم الموافقة على التقييم" });
    }

    [HttpGet("pending")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> GetPendingReviews([FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var query = _unitOfWork.Reviews.AsQueryable()
            .Where(r => !r.IsApproved);

        var totalItems = await query.CountAsync();
        var totalPages = (int)Math.Ceiling(totalItems / (double)pageSize);

        var reviews = await query
            .OrderBy(r => r.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(r => new
            {
                r.Id,
                r.Rating,
                r.Comment,
                r.CreatedAt,
                product = new { r.Product.Id, r.Product.Name, r.Product.NameAr },
                customer = new { r.Customer.Id, r.Customer.FullName }
            })
            .ToListAsync();

        return Ok(new
        {
            success = true,
            data = reviews,
            pagination = new { currentPage = page, pageSize, totalItems, totalPages }
        });
    }

    private async Task UpdateProductRating(Guid productId)
    {
        var stats = await _unitOfWork.Reviews.AsQueryable()
            .Where(r => r.ProductId == productId && r.IsApproved)
            .GroupBy(r => r.ProductId)
            .Select(g => new { avgRating = g.Average(r => r.Rating), count = g.Count() })
            .FirstOrDefaultAsync();

        var product = await _unitOfWork.Products.GetByIdAsync(productId);
        if (product != null && stats != null)
        {
            product.AverageRating = (decimal)stats.avgRating;
            product.ReviewCount = stats.count;
            _unitOfWork.Products.Update(product);
            await _unitOfWork.SaveChangesAsync();
        }
    }
}

public class CreateReviewRequest
{
    public Guid ProductId { get; set; }
    public int Rating { get; set; }
    public string? Comment { get; set; }
}

public class UpdateReviewRequest
{
    public int? Rating { get; set; }
    public string? Comment { get; set; }
}
