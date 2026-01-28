using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class CartController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public CartController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet]
    public async Task<IActionResult> GetCart()
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        var cartItems = await _unitOfWork.CartItems.AsQueryable()
            .Where(c => c.CustomerId == customer.Id)
            .Select(c => new
            {
                c.Id,
                c.Quantity,
                product = new
                {
                    c.Product.Id,
                    c.Product.Name,
                    c.Product.NameAr,
                    c.Product.Price,
                    c.Product.DiscountPrice,
                    c.Product.ImageUrl,
                    c.Product.StockQuantity,
                    c.Product.IsActive,
                    merchantId = c.Product.MerchantId
                }
            })
            .ToListAsync();

        var subtotal = cartItems.Sum(item => 
            (item.product.DiscountPrice ?? item.product.Price) * item.Quantity);

        return Ok(new
        {
            success = true,
            data = new
            {
                items = cartItems,
                itemCount = cartItems.Count,
                totalQuantity = cartItems.Sum(i => i.Quantity),
                subtotal
            }
        });
    }

    [HttpPost]
    public async Task<IActionResult> AddToCart([FromBody] AddToCartRequest request)
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        // Check if product exists and is available
        var product = await _unitOfWork.Products.GetByIdAsync(request.ProductId);
        if (product == null || !product.IsActive)
            return NotFound(new { success = false, message = "المنتج غير موجود" });

        if (product.StockQuantity < request.Quantity)
            return BadRequest(new { success = false, message = "الكمية المطلوبة غير متوفرة" });

        // Check if already in cart
        var existingItem = await _unitOfWork.CartItems
            .FirstOrDefaultAsync(c => c.CustomerId == customer.Id && c.ProductId == request.ProductId);

        if (existingItem != null)
        {
            var newQuantity = existingItem.Quantity + request.Quantity;
            if (newQuantity > product.StockQuantity)
                return BadRequest(new { success = false, message = "الكمية المطلوبة تتجاوز المخزون المتاح" });

            existingItem.Quantity = newQuantity;
            existingItem.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.CartItems.Update(existingItem);
        }
        else
        {
            var cartItem = new Sadara.Domain.Entities.CartItem
            {
                CustomerId = customer.Id,
                ProductId = request.ProductId,
                Quantity = request.Quantity
            };
            await _unitOfWork.CartItems.AddAsync(cartItem);
        }

        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تمت الإضافة للسلة بنجاح" });
    }

    [HttpPut("{itemId}")]
    public async Task<IActionResult> UpdateQuantity(Guid itemId, [FromBody] UpdateCartItemRequest request)
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        var cartItem = await _unitOfWork.CartItems.AsQueryable()
            .Include(c => c.Product)
            .FirstOrDefaultAsync(c => c.Id == itemId && c.CustomerId == customer.Id);

        if (cartItem == null)
            return NotFound(new { success = false, message = "العنصر غير موجود في السلة" });

        if (request.Quantity <= 0)
        {
            _unitOfWork.CartItems.Delete(cartItem);
            await _unitOfWork.SaveChangesAsync();
            return Ok(new { success = true, message = "تمت إزالة العنصر من السلة" });
        }

        if (request.Quantity > cartItem.Product.StockQuantity)
            return BadRequest(new { success = false, message = "الكمية المطلوبة غير متوفرة" });

        cartItem.Quantity = request.Quantity;
        cartItem.UpdatedAt = DateTime.UtcNow;
        _unitOfWork.CartItems.Update(cartItem);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث الكمية بنجاح" });
    }

    [HttpDelete("{itemId}")]
    public async Task<IActionResult> RemoveFromCart(Guid itemId)
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        var cartItem = await _unitOfWork.CartItems
            .FirstOrDefaultAsync(c => c.Id == itemId && c.CustomerId == customer.Id);

        if (cartItem == null)
            return NotFound(new { success = false, message = "العنصر غير موجود في السلة" });

        _unitOfWork.CartItems.Delete(cartItem);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تمت إزالة العنصر من السلة بنجاح" });
    }

    [HttpDelete]
    public async Task<IActionResult> ClearCart()
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        var cartItems = await _unitOfWork.CartItems.AsQueryable()
            .Where(c => c.CustomerId == customer.Id)
            .ToListAsync();

        foreach (var item in cartItems)
        {
            _unitOfWork.CartItems.Delete(item);
        }

        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم مسح السلة بنجاح" });
    }

    [HttpGet("count")]
    public async Task<IActionResult> GetCartCount()
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return Ok(new { success = true, data = new { count = 0 } });

        var count = await _unitOfWork.CartItems.CountAsync(c => c.CustomerId == customer.Id);

        return Ok(new { success = true, data = new { count } });
    }

    [HttpPost("validate")]
    public async Task<IActionResult> ValidateCart()
    {
        var userIdClaim = User.FindFirst("sub")?.Value ?? User.FindFirst("userId")?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { success = false, message = "يرجى تسجيل الدخول" });

        var customer = await _unitOfWork.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BadRequest(new { success = false, message = "لم يتم العثور على بيانات العميل" });

        var cartItems = await _unitOfWork.CartItems.AsQueryable()
            .Include(c => c.Product)
            .Where(c => c.CustomerId == customer.Id)
            .ToListAsync();

        var issues = new List<object>();
        var removedItems = new List<Guid>();

        foreach (var item in cartItems)
        {
            if (!item.Product.IsActive)
            {
                issues.Add(new { productId = item.ProductId, issue = "المنتج غير متاح", itemId = item.Id });
                removedItems.Add(item.Id);
                _unitOfWork.CartItems.Delete(item);
            }
            else if (item.Product.StockQuantity == 0)
            {
                issues.Add(new { productId = item.ProductId, issue = "المنتج نفد من المخزون", itemId = item.Id });
                removedItems.Add(item.Id);
                _unitOfWork.CartItems.Delete(item);
            }
            else if (item.Quantity > item.Product.StockQuantity)
            {
                issues.Add(new
                {
                    productId = item.ProductId,
                    issue = $"الكمية المتاحة {item.Product.StockQuantity} فقط",
                    itemId = item.Id,
                    availableQuantity = item.Product.StockQuantity
                });
                item.Quantity = item.Product.StockQuantity;
                _unitOfWork.CartItems.Update(item);
            }
        }

        if (issues.Any())
        {
            await _unitOfWork.SaveChangesAsync();
        }

        return Ok(new
        {
            success = true,
            data = new
            {
                isValid = !issues.Any(),
                issues,
                removedItems
            }
        });
    }
}

public class AddToCartRequest
{
    public Guid ProductId { get; set; }
    public int Quantity { get; set; } = 1;
}

public class UpdateCartItemRequest
{
    public int Quantity { get; set; }
}
