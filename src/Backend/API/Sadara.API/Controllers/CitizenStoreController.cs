using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Infrastructure.Data;
using System.Security.Claims;

namespace Sadara.API.Controllers;

/// <summary>
/// متجر المنتجات للمواطنين
/// </summary>
[ApiController]
[Route("api/citizen/store")]
[Tags("Citizen Store")]
public class CitizenStoreController : ControllerBase
{
    private readonly SadaraDbContext _context;
    private readonly ILogger<CitizenStoreController> _logger;

    public CitizenStoreController(SadaraDbContext context, ILogger<CitizenStoreController> logger)
    {
        _context = context;
        _logger = logger;
    }

    // ==================== التصنيفات ====================

    /// <summary>
    /// الحصول على تصنيفات المنتجات
    /// </summary>
    [HttpGet("categories")]
    public async Task<IActionResult> GetCategories([FromQuery] Guid? companyId)
    {
        try
        {
            var query = _context.ProductCategories
                .Where(c => c.IsActive)
                .AsQueryable();

            if (companyId.HasValue)
                query = query.Where(c => c.CompanyId == companyId || c.CompanyId == null);

            var categories = await query
                .OrderBy(c => c.SortOrder)
                .Select(c => new CategoryResponse
                {
                    Id = c.Id,
                    Name = c.Name,
                    NameAr = c.NameAr,
                    Description = c.Description,
                    ImageUrl = c.IconUrl,
                    Icon = c.IconUrl,
                    ProductCount = c.Products.Count(p => p.IsActive && p.StockQuantity > 0)
                })
                .ToListAsync();

            return Ok(new { success = true, categories });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting categories");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    // ==================== المنتجات ====================

    /// <summary>
    /// الحصول على المنتجات
    /// </summary>
    [HttpGet("products")]
    public async Task<IActionResult> GetProducts(
        [FromQuery] Guid? companyId,
        [FromQuery] Guid? categoryId,
        [FromQuery] string? search,
        [FromQuery] decimal? minPrice,
        [FromQuery] decimal? maxPrice,
        [FromQuery] bool? isFeatured,
        [FromQuery] string? sortBy = "popular",
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        try
        {
            var query = _context.StoreProducts
                .Include(p => p.Category)
                .Where(p => p.IsActive && p.StockQuantity > 0)
                .AsQueryable();

            if (companyId.HasValue)
                query = query.Where(p => p.CompanyId == companyId);

            if (categoryId.HasValue)
                query = query.Where(p => p.CategoryId == categoryId);

            if (!string.IsNullOrEmpty(search))
                query = query.Where(p => p.Name.Contains(search) || p.NameAr.Contains(search) || p.Description!.Contains(search));

            if (minPrice.HasValue)
                query = query.Where(p => p.Price >= minPrice);

            if (maxPrice.HasValue)
                query = query.Where(p => p.Price <= maxPrice);

            if (isFeatured.HasValue && isFeatured.Value)
                query = query.Where(p => p.IsFeatured);

            // الترتيب
            query = sortBy?.ToLower() switch
            {
                "price-asc" => query.OrderBy(p => p.Price),
                "price-desc" => query.OrderByDescending(p => p.Price),
                "newest" => query.OrderByDescending(p => p.CreatedAt),
                "name" => query.OrderBy(p => p.NameAr),
                _ => query.OrderByDescending(p => p.SoldCount).ThenBy(p => p.SortOrder) // popular
            };

            var total = await query.CountAsync();

            var products = await query
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(p => new ProductResponse
                {
                    Id = p.Id,
                    SKU = p.SKU,
                    Name = p.Name,
                    NameAr = p.NameAr,
                    Description = p.Description,
                    ImageUrl = p.ImageUrl,
                    Images = p.AdditionalImages,
                    Price = p.Price,
                    OriginalPrice = p.DiscountPrice,
                    DiscountPercent = p.DiscountPrice.HasValue ? (int)((1 - p.Price / p.DiscountPrice.Value) * 100) : null,
                    CategoryId = p.CategoryId,
                    CategoryName = p.Category != null ? p.Category.NameAr : null,
                    StockQuantity = p.StockQuantity,
                    IsFeatured = p.IsFeatured,
                    AverageRating = p.AverageRating,
                    ReviewCount = p.ReviewCount
                })
                .ToListAsync();

            return Ok(new
            {
                success = true,
                total,
                page,
                pageSize,
                totalPages = (int)Math.Ceiling((double)total / pageSize),
                products
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting products");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// الحصول على تفاصيل منتج
    /// </summary>
    [HttpGet("products/{id}")]
    public async Task<IActionResult> GetProduct(Guid id)
    {
        try
        {
            var product = await _context.StoreProducts
                .Include(p => p.Category)
                .Include(p => p.Company)
                .Where(p => p.Id == id && p.IsActive)
                .Select(p => new ProductDetailResponse
                {
                    Id = p.Id,
                    SKU = p.SKU,
                    Name = p.Name,
                    NameAr = p.NameAr,
                    Description = p.Description,
                    ImageUrl = p.ImageUrl,
                    Images = p.AdditionalImages,
                    Price = p.Price,
                    OriginalPrice = p.DiscountPrice,
                    DiscountPercent = p.DiscountPrice.HasValue ? (int)((1 - p.Price / p.DiscountPrice.Value) * 100) : null,
                    CategoryId = p.CategoryId,
                    CategoryName = p.Category != null ? p.Category.NameAr : null,
                    CompanyId = p.CompanyId,
                    CompanyName = p.Company!.NameAr,
                    CompanyLogo = p.Company.LogoUrl,
                    StockQuantity = p.StockQuantity,
                    IsInStock = p.StockQuantity > 0,
                    IsFeatured = p.IsFeatured,
                    AverageRating = p.AverageRating,
                    ReviewCount = p.ReviewCount
                })
                .FirstOrDefaultAsync();

            if (product == null)
                return NotFound(new { success = false, messageAr = "المنتج غير موجود", message = "Product not found" });

            return Ok(new { success = true, product });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting product");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// الحصول على المنتجات المميزة
    /// </summary>
    [HttpGet("products/featured")]
    public async Task<IActionResult> GetFeaturedProducts([FromQuery] Guid? companyId, [FromQuery] int limit = 10)
    {
        try
        {
            var query = _context.StoreProducts
                .Where(p => p.IsActive && p.IsFeatured && p.StockQuantity > 0)
                .AsQueryable();

            if (companyId.HasValue)
                query = query.Where(p => p.CompanyId == companyId);

            var products = await query
                .OrderBy(p => p.SortOrder)
                .Take(limit)
                .Select(p => new ProductResponse
                {
                    Id = p.Id,
                    Name = p.Name,
                    NameAr = p.NameAr,
                    ImageUrl = p.ImageUrl,
                    Price = p.Price,
                    OriginalPrice = p.DiscountPrice,
                    DiscountPercent = p.DiscountPrice.HasValue ? (int)((1 - p.Price / p.DiscountPrice.Value) * 100) : null,
                    AverageRating = p.AverageRating
                })
                .ToListAsync();

            return Ok(new { success = true, products });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting featured products");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    // ==================== الطلبات ====================

    /// <summary>
    /// إنشاء طلب جديد
    /// </summary>
    [HttpPost("orders")]
    [Authorize(AuthenticationSchemes = "CitizenJwt")]
    public async Task<IActionResult> CreateOrder([FromBody] CreateOrderRequest request)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var citizen = await _context.Citizens.FindAsync(citizenId);
            if (citizen == null)
                return NotFound(new { success = false, messageAr = "المستخدم غير موجود", message = "User not found" });

            if (request.Items == null || !request.Items.Any())
                return BadRequest(new { success = false, messageAr = "الطلب فارغ", message = "Order is empty" });

            // التحقق من المنتجات والمخزون
            var productIds = request.Items.Select(i => i.ProductId).ToList();
            var products = await _context.StoreProducts
                .Where(p => productIds.Contains(p.Id) && p.IsActive)
                .ToListAsync();

            if (products.Count != productIds.Count)
                return BadRequest(new { success = false, messageAr = "بعض المنتجات غير متوفرة", message = "Some products are not available" });

            decimal subtotal = 0;
            var orderItems = new List<StoreOrderItem>();

            foreach (var item in request.Items)
            {
                var product = products.First(p => p.Id == item.ProductId);

                if (product.StockQuantity < item.Quantity)
                    return BadRequest(new { success = false, messageAr = $"الكمية المطلوبة من {product.NameAr} غير متوفرة", message = $"Insufficient stock for {product.Name}" });

                var itemTotal = product.Price * item.Quantity;
                subtotal += itemTotal;

                orderItems.Add(new StoreOrderItem
                {
                    Id = Guid.NewGuid(),
                    ProductId = product.Id,
                    ProductName = product.NameAr,
                    Quantity = item.Quantity,
                    UnitPrice = product.Price,
                    TotalPrice = itemTotal
                });

                // تقليل المخزون
                product.StockQuantity -= item.Quantity;
            }

            // حساب التكاليف
            var deliveryFee = request.DeliveryMethod == "delivery" ? 50m : 0m; // TODO: حساب الشحن بشكل صحيح
            var totalAmount = subtotal + deliveryFee;

            var orderNumber = $"ORD-{DateTime.UtcNow:yyyyMMdd}-{Guid.NewGuid().ToString("N").Substring(0, 6).ToUpper()}";

            var order = new StoreOrder
            {
                Id = Guid.NewGuid(),
                OrderNumber = orderNumber,
                CitizenId = citizenId!.Value,
                CompanyId = citizen.CompanyId ?? Guid.Empty,
                Status = StoreOrderStatus.Pending,
                SubTotal = subtotal,
                DeliveryFee = deliveryFee,
                DiscountAmount = 0,
                TotalAmount = totalAmount,
                DeliveryAddress = request.ShippingAddress ?? citizen.FullAddress,
                DeliveryCity = request.City ?? citizen.City,
                ContactPhone = request.ContactPhone ?? citizen.PhoneNumber,
                Notes = request.Notes,
                PaymentMethod = PaymentMethod.CashOnDelivery,
                CreatedAt = DateTime.UtcNow
            };

            // ربط العناصر بالطلب
            foreach (var item in orderItems)
            {
                item.StoreOrderId = order.Id;
            }

            _context.StoreOrders.Add(order);
            _context.StoreOrderItems.AddRange(orderItems);
            await _context.SaveChangesAsync();

            _logger.LogInformation("New order created: {OrderNumber}", orderNumber);

            return Ok(new
            {
                success = true,
                messageAr = "تم إنشاء الطلب بنجاح",
                message = "Order created successfully",
                order = new
                {
                    order.Id,
                    orderNumber,
                    status = "Pending",
                    statusAr = "قيد المراجعة",
                    totalAmount
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating order");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// الحصول على طلباتي
    /// </summary>
    [HttpGet("orders")]
    [Authorize(AuthenticationSchemes = "CitizenJwt")]
    public async Task<IActionResult> GetMyOrders([FromQuery] StoreOrderStatus? status = null)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var query = _context.StoreOrders
                .Include(o => o.Company)
                .Where(o => o.CitizenId == citizenId);

            if (status.HasValue)
                query = query.Where(o => o.Status == status);

            var orders = await query
                .OrderByDescending(o => o.CreatedAt)
                .Select(o => new OrderResponse
                {
                    Id = o.Id,
                    OrderNumber = o.OrderNumber,
                    Status = o.Status.ToString(),
                    StatusAr = GetStatusArabic(o.Status),
                    CompanyName = o.Company!.NameAr,
                    ItemCount = o.Items.Count,
                    TotalAmount = o.TotalAmount,
                    PaymentMethod = o.PaymentMethod.ToString(),
                    PaymentStatus = o.PaymentStatus.ToString(),
                    PaymentStatusAr = GetPaymentStatusArabic(o.PaymentStatus),
                    CreatedAt = o.CreatedAt,
                    DeliveredAt = o.ActualDeliveryDate
                })
                .ToListAsync();

            return Ok(new
            {
                success = true,
                count = orders.Count,
                orders
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting orders");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// الحصول على تفاصيل طلب
    /// </summary>
    [HttpGet("orders/{id}")]
    [Authorize(AuthenticationSchemes = "CitizenJwt")]
    public async Task<IActionResult> GetOrder(Guid id)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var order = await _context.StoreOrders
                .Include(o => o.Company)
                .Include(o => o.Items)
                    .ThenInclude(i => i.Product)
                .Where(o => o.Id == id && o.CitizenId == citizenId)
                .FirstOrDefaultAsync();

            if (order == null)
                return NotFound(new { success = false, messageAr = "الطلب غير موجود", message = "Order not found" });

            var response = new OrderDetailResponse
            {
                Id = order.Id,
                OrderNumber = order.OrderNumber,
                Status = order.Status.ToString(),
                StatusAr = GetStatusArabic(order.Status),
                CompanyId = order.CompanyId,
                CompanyName = order.Company!.NameAr,
                CompanyLogo = order.Company.LogoUrl,
                CompanyPhone = order.Company.Phone,
                Subtotal = order.SubTotal,
                ShippingCost = order.DeliveryFee,
                DiscountAmount = order.DiscountAmount,
                TotalAmount = order.TotalAmount,
                ShippingAddress = order.DeliveryAddress,
                ShippingCity = order.DeliveryCity,
                ContactPhone = order.ContactPhone,
                Notes = order.Notes,
                PaymentMethod = order.PaymentMethod.ToString(),
                PaymentStatus = order.PaymentStatus.ToString(),
                PaymentStatusAr = GetPaymentStatusArabic(order.PaymentStatus),
                CancellationReason = order.CancellationReason,
                CreatedAt = order.CreatedAt,
                DeliveredAt = order.ActualDeliveryDate,
                CancelledAt = order.CancelledAt,
                Items = order.Items.Select(i => new OrderItemResponse
                {
                    Id = i.Id,
                    ProductId = i.ProductId,
                    ProductName = i.ProductName,
                    ProductImage = i.Product?.ImageUrl,
                    Quantity = i.Quantity,
                    UnitPrice = i.UnitPrice,
                    TotalPrice = i.TotalPrice
                }).ToList()
            };

            return Ok(new { success = true, order = response });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting order");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// إلغاء طلب
    /// </summary>
    [HttpPost("orders/{id}/cancel")]
    [Authorize(AuthenticationSchemes = "CitizenJwt")]
    public async Task<IActionResult> CancelOrder(Guid id, [FromBody] CancelOrderRequest request)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var order = await _context.StoreOrders
                .Include(o => o.Items)
                .FirstOrDefaultAsync(o => o.Id == id && o.CitizenId == citizenId);

            if (order == null)
                return NotFound(new { success = false, messageAr = "الطلب غير موجود", message = "Order not found" });

            if (order.Status != StoreOrderStatus.Pending && order.Status != StoreOrderStatus.Confirmed)
                return BadRequest(new { success = false, messageAr = "لا يمكن إلغاء الطلب في هذه المرحلة", message = "Cannot cancel order at this stage" });

            // إرجاع المخزون
            foreach (var item in order.Items)
            {
                var product = await _context.StoreProducts.FindAsync(item.ProductId);
                if (product != null)
                {
                    product.StockQuantity += item.Quantity;
                }
            }

            order.Status = StoreOrderStatus.Cancelled;
            order.CancellationReason = request.Reason;
            order.CancelledAt = DateTime.UtcNow;
            order.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            return Ok(new
            {
                success = true,
                messageAr = "تم إلغاء الطلب",
                message = "Order cancelled"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error cancelling order");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    /// <summary>
    /// تتبع الطلب
    /// </summary>
    [HttpGet("orders/{id}/track")]
    [Authorize(AuthenticationSchemes = "CitizenJwt")]
    public async Task<IActionResult> TrackOrder(Guid id)
    {
        try
        {
            var citizenId = GetCurrentCitizenId();
            if (citizenId == null)
                return Unauthorized();

            var order = await _context.StoreOrders
                .Where(o => o.Id == id && o.CitizenId == citizenId)
                .Select(o => new
                {
                    o.Id,
                    o.OrderNumber,
                    o.Status,
                    o.CreatedAt,
                    o.ActualDeliveryDate,
                    o.CancelledAt
                })
                .FirstOrDefaultAsync();

            if (order == null)
                return NotFound(new { success = false, messageAr = "الطلب غير موجود", message = "Order not found" });

            var timeline = new List<object>
            {
                new { status = "Pending", statusAr = "تم الطلب", date = order.CreatedAt, completed = true }
            };
            
            if (order.ActualDeliveryDate.HasValue)
                timeline.Add(new { status = "Delivered", statusAr = "تم التسليم", date = order.ActualDeliveryDate, completed = true });

            if (order.CancelledAt.HasValue)
                timeline.Add(new { status = "Cancelled", statusAr = "ملغي", date = order.CancelledAt, completed = true });

            return Ok(new
            {
                success = true,
                order = new
                {
                    order.OrderNumber,
                    status = order.Status.ToString(),
                    statusAr = GetStatusArabic(order.Status)
                },
                timeline
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error tracking order");
            return StatusCode(500, new { success = false, messageAr = "حدث خطأ", message = "Error occurred" });
        }
    }

    // ==================== Helper Methods ====================

    private Guid? GetCurrentCitizenId()
    {
        var claim = User.FindFirst(ClaimTypes.NameIdentifier);
        if (claim == null || !Guid.TryParse(claim.Value, out var id))
            return null;
        return id;
    }

    private static string GetStatusArabic(StoreOrderStatus status) => status switch
    {
        StoreOrderStatus.Pending => "قيد المراجعة",
        StoreOrderStatus.Confirmed => "مؤكد",
        StoreOrderStatus.Processing => "قيد التجهيز",
        StoreOrderStatus.Shipped => "تم الشحن",
        StoreOrderStatus.Delivered => "تم التسليم",
        StoreOrderStatus.Cancelled => "ملغي",
        StoreOrderStatus.Returned => "مرتجع",
        _ => status.ToString()
    };

    private static string GetPaymentStatusArabic(PaymentStatus status) => status switch
    {
        PaymentStatus.Pending => "قيد الانتظار",
        PaymentStatus.Success => "مدفوع",
        PaymentStatus.Failed => "فشل",
        PaymentStatus.Refunded => "مسترد",
        PaymentStatus.Cancelled => "ملغي",
        _ => status.ToString()
    };
}

// ==================== DTOs ====================

public class CategoryResponse
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string NameAr { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? ImageUrl { get; set; }
    public string? Icon { get; set; }
    public int ProductCount { get; set; }
}

public class ProductResponse
{
    public Guid Id { get; set; }
    public string? SKU { get; set; }
    public string Name { get; set; } = string.Empty;
    public string NameAr { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? ImageUrl { get; set; }
    public string? Images { get; set; }
    public decimal Price { get; set; }
    public decimal? OriginalPrice { get; set; }
    public int? DiscountPercent { get; set; }
    public Guid? CategoryId { get; set; }
    public string? CategoryName { get; set; }
    public int StockQuantity { get; set; }
    public bool IsFeatured { get; set; }
    public decimal? AverageRating { get; set; }
    public int ReviewCount { get; set; }
    public string? Badge { get; set; }
}

public class ProductDetailResponse : ProductResponse
{
    public Guid CompanyId { get; set; }
    public string CompanyName { get; set; } = string.Empty;
    public string? CompanyLogo { get; set; }
    public bool IsInStock { get; set; }
}

public class CreateOrderRequest
{
    public List<OrderItemRequest> Items { get; set; } = new();
    public string? ShippingAddress { get; set; }
    public string? City { get; set; }
    public string? District { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public string? ContactPhone { get; set; }
    public string? Notes { get; set; }
    public string? PaymentMethod { get; set; }
    public string? DeliveryMethod { get; set; }
}

public class OrderItemRequest
{
    public Guid ProductId { get; set; }
    public int Quantity { get; set; } = 1;
}

public class OrderResponse
{
    public Guid Id { get; set; }
    public string OrderNumber { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string StatusAr { get; set; } = string.Empty;
    public string CompanyName { get; set; } = string.Empty;
    public int ItemCount { get; set; }
    public decimal TotalAmount { get; set; }
    public string? PaymentMethod { get; set; }
    public string PaymentStatus { get; set; } = string.Empty;
    public string PaymentStatusAr { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public DateTime? DeliveredAt { get; set; }
}

public class OrderDetailResponse : OrderResponse
{
    public Guid CompanyId { get; set; }
    public string? CompanyLogo { get; set; }
    public string? CompanyPhone { get; set; }
    public decimal Subtotal { get; set; }
    public decimal ShippingCost { get; set; }
    public decimal DiscountAmount { get; set; }
    public string? ShippingAddress { get; set; }
    public string? ShippingCity { get; set; }
    public string? ContactPhone { get; set; }
    public string? Notes { get; set; }
    public string? CancellationReason { get; set; }
    public DateTime? CancelledAt { get; set; }
    public List<OrderItemResponse> Items { get; set; } = new();
}

public class OrderItemResponse
{
    public Guid Id { get; set; }
    public Guid ProductId { get; set; }
    public string ProductName { get; set; } = string.Empty;
    public string? ProductImage { get; set; }
    public int Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal TotalPrice { get; set; }
}

public class CancelOrderRequest
{
    public string? Reason { get; set; }
}
