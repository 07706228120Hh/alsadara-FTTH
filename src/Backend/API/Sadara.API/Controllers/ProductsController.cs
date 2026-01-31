using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ProductsController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public ProductsController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet]
    public async Task<IActionResult> GetAll([FromQuery] Guid? merchantId, [FromQuery] string? search, [FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var query = _unitOfWork.Products.AsQueryable();

        if (merchantId.HasValue)
            query = query.Where(p => p.MerchantId == merchantId.Value);

        if (!string.IsNullOrWhiteSpace(search))
        {
            var searchTerm = search!; // search is not null here due to the check above
            query = query.Where(p => p.Name.Contains(searchTerm) || p.NameAr.Contains(searchTerm));
        }

        var total = await query.CountAsync();
        var products = await query
            .OrderByDescending(p => p.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return Ok(new { success = true, data = products, total, page, pageSize });
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var product = await _unitOfWork.Products.GetByIdAsync(id);
        if (product == null)
            return NotFound(new { success = false, message = "المنتج غير موجود" });

        return Ok(new { success = true, data = product });
    }

    [HttpGet("merchant/{merchantId:guid}")]
    public async Task<IActionResult> GetByMerchant(Guid merchantId)
    {
        var products = await _unitOfWork.Products.FindAsync(p => p.MerchantId == merchantId && p.IsAvailable);
        return Ok(new { success = true, data = products });
    }

    [HttpGet("featured")]
    public async Task<IActionResult> GetFeatured([FromQuery] int count = 10)
    {
        var products = await _unitOfWork.Products.AsQueryable()
            .Where(p => p.IsFeatured && p.IsAvailable)
            .OrderByDescending(p => p.CreatedAt)
            .Take(count)
            .ToListAsync();

        return Ok(new { success = true, data = products });
    }

    [HttpPost]
    [Authorize(Policy = "Merchant")]
    public async Task<IActionResult> Create([FromBody] CreateProductRequest request)
    {
        var product = new Product
        {
            Id = Guid.NewGuid(),
            MerchantId = request.MerchantId,
            Name = request.Name,
            NameAr = request.NameAr ?? request.Name,
            Description = request.Description ?? string.Empty,
            DescriptionAr = request.DescriptionAr ?? string.Empty,
            SKU = request.SKU ?? string.Empty,
            Price = request.Price,
            DiscountPrice = request.DiscountPrice,
            CostPrice = request.CostPrice ?? 0,
            StockQuantity = request.StockQuantity,
            IsAvailable = true,
            CreatedAt = DateTime.UtcNow
        };

        await _unitOfWork.Products.AddAsync(product);
        await _unitOfWork.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = product.Id }, new { success = true, data = product });
    }

    [HttpPut("{id:guid}")]
    [Authorize(Policy = "Merchant")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateProductRequest request)
    {
        var product = await _unitOfWork.Products.GetByIdAsync(id);
        if (product == null)
            return NotFound(new { success = false, message = "المنتج غير موجود" });

        product.Name = request.Name ?? product.Name;
        product.NameAr = request.NameAr ?? product.NameAr;
        product.Description = request.Description ?? product.Description;
        product.Price = request.Price ?? product.Price;
        product.DiscountPrice = request.DiscountPrice;
        product.StockQuantity = request.StockQuantity ?? product.StockQuantity;
        product.IsAvailable = request.IsAvailable ?? product.IsAvailable;
        product.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Products.Update(product);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, data = product });
    }

    [HttpDelete("{id:guid}")]
    [Authorize(Policy = "Merchant")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var product = await _unitOfWork.Products.GetByIdAsync(id);
        if (product == null)
            return NotFound(new { success = false, message = "المنتج غير موجود" });

        product.IsDeleted = true;
        product.DeletedAt = DateTime.UtcNow;
        _unitOfWork.Products.Update(product);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف المنتج بنجاح" });
    }
}

public record CreateProductRequest(
    Guid MerchantId,
    string Name,
    string? NameAr,
    string? Description,
    string? DescriptionAr,
    string? SKU,
    decimal Price,
    decimal? DiscountPrice,
    decimal? CostPrice,
    int StockQuantity
);

public record UpdateProductRequest(
    string? Name,
    string? NameAr,
    string? Description,
    decimal? Price,
    decimal? DiscountPrice,
    int? StockQuantity,
    bool? IsAvailable
);

