using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class WishlistController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public WishlistController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet]
    public async Task<IActionResult> GetWishlist()
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        var wishlistItems = await _unitOfWork.WishlistItems.AsQueryable()
            .Where(w => w.CustomerId == customer.Id)
            .OrderByDescending(w => w.CreatedAt)
            .Select(w => new
            {
                w.Id,
                w.CreatedAt,
                product = new
                {
                    w.Product.Id,
                    w.Product.Name,
                    w.Product.NameAr,
                    w.Product.Price,
                    w.Product.DiscountPrice,
                    w.Product.ImageUrl,
                    w.Product.StockQuantity,
                    w.Product.IsActive,
                    inStock = w.Product.StockQuantity > 0
                }
            })
            .ToListAsync();

        return Ok(new { success = true, data = wishlistItems });
    }

    [HttpPost("{productId}")]
    public async Task<IActionResult> AddToWishlist(Guid productId)
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        // Check if product exists
        var productExists = await _unitOfWork.Products.AnyAsync(p => p.Id == productId && p.IsActive);
        if (!productExists)
            return NotFound(new { success = false, message = "المنتج غير موجود" });

        // Check if already in wishlist
        var existingItem = await _unitOfWork.WishlistItems
            .FirstOrDefaultAsync(w => w.CustomerId == customer.Id && w.ProductId == productId);
        
        if (existingItem != null)
            return BadRequest(new { success = false, message = "المنتج موجود في المفضلة مسبقاً" });

        var wishlistItem = new Sadara.Domain.Entities.WishlistItem
        {
            CustomerId = customer.Id,
            ProductId = productId
        };

        await _unitOfWork.WishlistItems.AddAsync(wishlistItem);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تمت الإضافة للمفضلة بنجاح" });
    }

    [HttpDelete("{productId}")]
    public async Task<IActionResult> RemoveFromWishlist(Guid productId)
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        var wishlistItem = await _unitOfWork.WishlistItems
            .FirstOrDefaultAsync(w => w.CustomerId == customer.Id && w.ProductId == productId);

        if (wishlistItem == null)
            return NotFound(new { success = false, message = "المنتج غير موجود في المفضلة" });

        _unitOfWork.WishlistItems.Delete(wishlistItem);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تمت الإزالة من المفضلة بنجاح" });
    }

    [HttpDelete]
    public async Task<IActionResult> ClearWishlist()
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        var wishlistItems = await _unitOfWork.WishlistItems.AsQueryable()
            .Where(w => w.CustomerId == customer.Id)
            .ToListAsync();

        foreach (var item in wishlistItems)
        {
            _unitOfWork.WishlistItems.Delete(item);
        }

        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم مسح المفضلة بنجاح" });
    }

    [HttpGet("check/{productId}")]
    public async Task<IActionResult> CheckInWishlist(Guid productId)
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        var isInWishlist = await _unitOfWork.WishlistItems
            .AnyAsync(w => w.CustomerId == customer.Id && w.ProductId == productId);

        return Ok(new { success = true, data = new { isInWishlist } });
    }

    [HttpPost("move-to-cart/{productId}")]
    public async Task<IActionResult> MoveToCart(Guid productId)
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        // Check if item is in wishlist
        var wishlistItem = await _unitOfWork.WishlistItems
            .FirstOrDefaultAsync(w => w.CustomerId == customer.Id && w.ProductId == productId);

        if (wishlistItem == null)
            return NotFound(new { success = false, message = "المنتج غير موجود في المفضلة" });

        // Check if product is available
        var product = await _unitOfWork.Products.GetByIdAsync(productId);
        if (product == null || !product.IsActive || product.StockQuantity <= 0)
            return BadRequest(new { success = false, message = "المنتج غير متاح حالياً" });

        // Add to cart
        var existingCartItem = await _unitOfWork.CartItems
            .FirstOrDefaultAsync(c => c.CustomerId == customer.Id && c.ProductId == productId);

        if (existingCartItem != null)
        {
            existingCartItem.Quantity += 1;
            _unitOfWork.CartItems.Update(existingCartItem);
        }
        else
        {
            var cartItem = new Sadara.Domain.Entities.CartItem
            {
                CustomerId = customer.Id,
                ProductId = productId,
                Quantity = 1
            };
            await _unitOfWork.CartItems.AddAsync(cartItem);
        }

        // Remove from wishlist
        _unitOfWork.WishlistItems.Delete(wishlistItem);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم نقل المنتج إلى السلة بنجاح" });
    }
}
