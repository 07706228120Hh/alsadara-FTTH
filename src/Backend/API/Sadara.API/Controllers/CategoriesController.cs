using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Interfaces;

namespace Sadara.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class CategoriesController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public CategoriesController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var categories = await _unitOfWork.Categories.AsQueryable()
            .Where(c => c.IsActive)
            .OrderBy(c => c.DisplayOrder)
            .ThenBy(c => c.Name)
            .Select(c => new
            {
                c.Id,
                c.Name,
                c.NameAr,
                c.Description,
                c.DescriptionAr,
                c.ImageUrl,
                c.ParentCategoryId,
                c.DisplayOrder,
                productCount = c.Products.Count(p => p.IsActive)
            })
            .ToListAsync();

        return Ok(new { success = true, data = categories });
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var category = await _unitOfWork.Categories.AsQueryable()
            .Where(c => c.Id == id)
            .Select(c => new
            {
                c.Id,
                c.Name,
                c.NameAr,
                c.Description,
                c.DescriptionAr,
                c.ImageUrl,
                c.ParentCategoryId,
                c.DisplayOrder,
                c.IsActive,
                productCount = c.Products.Count(p => p.IsActive)
            })
            .FirstOrDefaultAsync();

        if (category == null)
            return NotFound(new { success = false, message = "الفئة غير موجودة" });

        return Ok(new { success = true, data = category });
    }

    [HttpGet("{id}/products")]
    public async Task<IActionResult> GetCategoryProducts(
        Guid id,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        var categoryExists = await _unitOfWork.Categories.AnyAsync(c => c.Id == id);
        if (!categoryExists)
            return NotFound(new { success = false, message = "الفئة غير موجودة" });

        var query = _unitOfWork.Products.AsQueryable()
            .Where(p => p.CategoryId == id && p.IsActive);

        var totalItems = await query.CountAsync();
        var totalPages = (int)Math.Ceiling(totalItems / (double)pageSize);

        var products = await query
            .OrderByDescending(p => p.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(p => new
            {
                p.Id,
                p.Name,
                p.NameAr,
                p.Price,
                p.DiscountPrice,
                p.ImageUrl,
                p.StockQuantity,
                p.AverageRating
            })
            .ToListAsync();

        return Ok(new
        {
            success = true,
            data = products,
            pagination = new
            {
                currentPage = page,
                pageSize,
                totalItems,
                totalPages
            }
        });
    }

    [HttpGet("tree")]
    public async Task<IActionResult> GetCategoryTree()
    {
        var categories = await _unitOfWork.Categories.AsQueryable()
            .Where(c => c.IsActive && c.ParentCategoryId == null)
            .OrderBy(c => c.DisplayOrder)
            .Select(c => new
            {
                c.Id,
                c.Name,
                c.NameAr,
                c.ImageUrl,
                children = c.SubCategories
                    .Where(sc => sc.IsActive)
                    .OrderBy(sc => sc.DisplayOrder)
                    .Select(sc => new
                    {
                        sc.Id,
                        sc.Name,
                        sc.NameAr,
                        sc.ImageUrl
                    })
                    .ToList()
            })
            .ToListAsync();

        return Ok(new { success = true, data = categories });
    }

    [HttpPost]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Create([FromBody] CreateCategoryRequest request)
    {
        var category = new Sadara.Domain.Entities.Category
        {
            Name = request.Name,
            NameAr = request.NameAr,
            Description = request.Description,
            DescriptionAr = request.DescriptionAr,
            ImageUrl = request.ImageUrl,
            ParentCategoryId = request.ParentCategoryId,
            DisplayOrder = request.DisplayOrder,
            IsActive = true
        };

        await _unitOfWork.Categories.AddAsync(category);
        await _unitOfWork.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = category.Id }, new
        {
            success = true,
            message = "تم إنشاء الفئة بنجاح",
            data = category.Id
        });
    }

    [HttpPut("{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateCategoryRequest request)
    {
        var category = await _unitOfWork.Categories.GetByIdAsync(id);
        if (category == null)
            return NotFound(new { success = false, message = "الفئة غير موجودة" });

        category.Name = request.Name ?? category.Name;
        category.NameAr = request.NameAr ?? category.NameAr;
        category.Description = request.Description ?? category.Description;
        category.DescriptionAr = request.DescriptionAr ?? category.DescriptionAr;
        category.ImageUrl = request.ImageUrl ?? category.ImageUrl;
        category.ParentCategoryId = request.ParentCategoryId;
        category.DisplayOrder = request.DisplayOrder ?? category.DisplayOrder;
        category.IsActive = request.IsActive ?? category.IsActive;
        category.UpdatedAt = DateTime.UtcNow;

        _unitOfWork.Categories.Update(category);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم تحديث الفئة بنجاح" });
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = "Admin")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var category = await _unitOfWork.Categories.GetByIdAsync(id);
        if (category == null)
            return NotFound(new { success = false, message = "الفئة غير موجودة" });

        // Check if category has products
        var hasProducts = await _unitOfWork.Products.AnyAsync(p => p.CategoryId == id);
        if (hasProducts)
            return BadRequest(new { success = false, message = "لا يمكن حذف الفئة لوجود منتجات مرتبطة بها" });

        _unitOfWork.Categories.Delete(category);
        await _unitOfWork.SaveChangesAsync();

        return Ok(new { success = true, message = "تم حذف الفئة بنجاح" });
    }
}

public class CreateCategoryRequest
{
    public string Name { get; set; } = string.Empty;
    public string NameAr { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? DescriptionAr { get; set; }
    public string? ImageUrl { get; set; }
    public Guid? ParentCategoryId { get; set; }
    public int DisplayOrder { get; set; }
}

public class UpdateCategoryRequest
{
    public string? Name { get; set; }
    public string? NameAr { get; set; }
    public string? Description { get; set; }
    public string? DescriptionAr { get; set; }
    public string? ImageUrl { get; set; }
    public Guid? ParentCategoryId { get; set; }
    public int? DisplayOrder { get; set; }
    public bool? IsActive { get; set; }
}
