using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using Sadara.Domain.Interfaces;
using Sadara.API.Authorization;

namespace Sadara.API.Controllers;

/// <summary>
/// نظام إدارة المخازن - المستودعات، التصنيفات، المواد، الموردين، الشراء، البيع، صرف الفنيين، الحركات، التقارير
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
[RequirePermission("inventory", "view")]
[Tags("Inventory")]
public class InventoryController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;
    private readonly ILogger<InventoryController> _logger;

    public InventoryController(IUnitOfWork unitOfWork, ILogger<InventoryController> logger)
    {
        _unitOfWork = unitOfWork;
        _logger = logger;
    }

    private Guid GetCurrentUserId()
    {
        var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value
                       ?? User.FindFirst("sub")?.Value;
        if (!string.IsNullOrEmpty(userIdClaim) && Guid.TryParse(userIdClaim, out var userId))
            return userId;
        return Guid.Empty;
    }

    private async Task<string> GenerateOrderNumber(string prefix, Guid companyId)
    {
        var year = DateTime.UtcNow.Year;
        var pattern = $"{prefix}-{year}-";

        int count = 0;
        if (prefix == "PO")
        {
            count = await _unitOfWork.PurchaseOrders.CountAsync(
                po => po.CompanyId == companyId && po.OrderNumber.StartsWith(pattern));
        }
        else if (prefix == "SO")
        {
            count = await _unitOfWork.SalesOrders.CountAsync(
                so => so.CompanyId == companyId && so.OrderNumber.StartsWith(pattern));
        }
        else if (prefix == "TD")
        {
            count = await _unitOfWork.TechnicianDispensings.CountAsync(
                td => td.CompanyId == companyId && td.VoucherNumber.StartsWith(pattern));
        }

        return $"{pattern}{(count + 1).ToString("D4")}";
    }

    // ==================== المستودعات - Warehouses ====================

    /// <summary>
    /// جلب قائمة المستودعات
    /// </summary>
    [HttpGet("warehouses")]
    public async Task<IActionResult> GetWarehouses([FromQuery] Guid? companyId = null)
    {
        try
        {
            var query = _unitOfWork.Warehouses.AsQueryable().Where(w => !w.IsDeleted);
            if (companyId.HasValue)
                query = query.Where(w => w.CompanyId == companyId);

            var warehouses = await query.OrderBy(w => w.Name).Select(w => new
            {
                w.Id,
                w.Name,
                w.Code,
                w.Address,
                w.Description,
                w.IsActive,
                w.IsDefault,
                w.ManagerUserId,
                ManagerName = w.ManagerUser != null ? w.ManagerUser.FullName : null,
                w.CompanyId,
                w.CreatedAt,
                StockCount = w.Stocks.Count(s => s.CurrentQuantity > 0)
            }).ToListAsync();

            return Ok(new { success = true, data = warehouses, total = warehouses.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب المستودعات");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إنشاء مستودع جديد
    /// </summary>
    [HttpPost("warehouses")]
    [RequirePermission("inventory", "add")]
    public async Task<IActionResult> CreateWarehouse([FromBody] CreateWarehouseRequest request)
    {
        try
        {
            var warehouse = new Warehouse
            {
                Id = Guid.NewGuid(),
                Name = request.Name,
                Code = request.Code,
                Address = request.Address,
                Description = request.Description,
                IsDefault = request.IsDefault,
                IsActive = true,
                ManagerUserId = request.ManagerUserId,
                CompanyId = request.CompanyId
            };

            // إذا كان افتراضي، إلغاء الافتراضي من المستودعات الأخرى
            if (request.IsDefault)
            {
                var existingDefaults = await _unitOfWork.Warehouses.FindAsync(
                    w => w.CompanyId == request.CompanyId && w.IsDefault && !w.IsDeleted);
                foreach (var d in existingDefaults)
                {
                    d.IsDefault = false;
                    _unitOfWork.Warehouses.Update(d);
                }
            }

            await _unitOfWork.Warehouses.AddAsync(warehouse);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, data = new { warehouse.Id, warehouse.Name, warehouse.Code }, message = "تم إنشاء المستودع بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء مستودع");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تعديل مستودع
    /// </summary>
    [HttpPut("warehouses/{id}")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> UpdateWarehouse(Guid id, [FromBody] UpdateWarehouseRequest request)
    {
        try
        {
            var warehouse = await _unitOfWork.Warehouses.GetByIdAsync(id);
            if (warehouse == null || warehouse.IsDeleted)
                return NotFound(new { success = false, message = "المستودع غير موجود" });

            warehouse.Name = request.Name ?? warehouse.Name;
            warehouse.Code = request.Code ?? warehouse.Code;
            warehouse.Address = request.Address ?? warehouse.Address;
            warehouse.Description = request.Description ?? warehouse.Description;
            warehouse.IsActive = request.IsActive ?? warehouse.IsActive;
            warehouse.ManagerUserId = request.ManagerUserId ?? warehouse.ManagerUserId;
            warehouse.UpdatedAt = DateTime.UtcNow;

            if (request.IsDefault == true)
            {
                var existingDefaults = await _unitOfWork.Warehouses.FindAsync(
                    w => w.CompanyId == warehouse.CompanyId && w.IsDefault && w.Id != id && !w.IsDeleted);
                foreach (var d in existingDefaults)
                {
                    d.IsDefault = false;
                    _unitOfWork.Warehouses.Update(d);
                }
                warehouse.IsDefault = true;
            }
            else if (request.IsDefault == false)
            {
                warehouse.IsDefault = false;
            }

            _unitOfWork.Warehouses.Update(warehouse);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تعديل المستودع بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل مستودع");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// حذف مستودع (حذف ناعم)
    /// </summary>
    [HttpDelete("warehouses/{id}")]
    [RequirePermission("inventory", "delete")]
    public async Task<IActionResult> DeleteWarehouse(Guid id)
    {
        try
        {
            var warehouse = await _unitOfWork.Warehouses.GetByIdAsync(id);
            if (warehouse == null || warehouse.IsDeleted)
                return NotFound(new { success = false, message = "المستودع غير موجود" });

            // التحقق من عدم وجود مخزون
            var hasStock = await _unitOfWork.WarehouseStocks.AnyAsync(
                ws => ws.WarehouseId == id && ws.CurrentQuantity > 0);
            if (hasStock)
                return BadRequest(new { success = false, message = "لا يمكن حذف المستودع لوجود مخزون فيه" });

            warehouse.IsDeleted = true;
            warehouse.DeletedAt = DateTime.UtcNow;
            warehouse.IsActive = false;
            _unitOfWork.Warehouses.Update(warehouse);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حذف المستودع بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف مستودع");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== التصنيفات - Categories ====================

    /// <summary>
    /// جلب تصنيفات المواد
    /// </summary>
    [HttpGet("categories")]
    public async Task<IActionResult> GetCategories([FromQuery] Guid? companyId = null)
    {
        try
        {
            var query = _unitOfWork.InventoryCategories.AsQueryable().Where(c => !c.IsDeleted);
            if (companyId.HasValue)
                query = query.Where(c => c.CompanyId == companyId);

            var categories = await query.OrderBy(c => c.SortOrder).ThenBy(c => c.Name).Select(c => new
            {
                c.Id,
                c.Name,
                c.NameEn,
                c.ParentCategoryId,
                c.SortOrder,
                c.IsActive,
                c.CompanyId,
                c.CreatedAt,
                ItemCount = _unitOfWork.InventoryItems.AsQueryable()
                    .Count(i => i.CategoryId == c.Id && !i.IsDeleted)
            }).ToListAsync();

            return Ok(new { success = true, data = categories, total = categories.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب التصنيفات");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إنشاء تصنيف جديد
    /// </summary>
    [HttpPost("categories")]
    [RequirePermission("inventory", "add")]
    public async Task<IActionResult> CreateCategory([FromBody] CreateInventoryCategoryRequest request)
    {
        try
        {
            var category = new InventoryCategory
            {
                Name = request.Name,
                NameEn = request.NameEn,
                ParentCategoryId = request.ParentCategoryId,
                SortOrder = request.SortOrder,
                IsActive = true,
                CompanyId = request.CompanyId
            };

            await _unitOfWork.InventoryCategories.AddAsync(category);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, data = new { category.Id, category.Name }, message = "تم إنشاء التصنيف بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء تصنيف");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تعديل تصنيف
    /// </summary>
    [HttpPut("categories/{id}")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> UpdateCategory(int id, [FromBody] UpdateInventoryCategoryRequest request)
    {
        try
        {
            var category = await _unitOfWork.InventoryCategories.GetByIdAsync(id);
            if (category == null || category.IsDeleted)
                return NotFound(new { success = false, message = "التصنيف غير موجود" });

            category.Name = request.Name ?? category.Name;
            category.NameEn = request.NameEn ?? category.NameEn;
            category.ParentCategoryId = request.ParentCategoryId ?? category.ParentCategoryId;
            category.SortOrder = request.SortOrder ?? category.SortOrder;
            category.IsActive = request.IsActive ?? category.IsActive;
            category.UpdatedAt = DateTime.UtcNow;

            _unitOfWork.InventoryCategories.Update(category);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تعديل التصنيف بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل تصنيف");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// حذف تصنيف (حذف ناعم)
    /// </summary>
    [HttpDelete("categories/{id}")]
    [RequirePermission("inventory", "delete")]
    public async Task<IActionResult> DeleteCategory(int id)
    {
        try
        {
            var category = await _unitOfWork.InventoryCategories.GetByIdAsync(id);
            if (category == null || category.IsDeleted)
                return NotFound(new { success = false, message = "التصنيف غير موجود" });

            // التحقق من عدم وجود مواد مرتبطة
            var hasItems = await _unitOfWork.InventoryItems.AnyAsync(
                i => i.CategoryId == id && !i.IsDeleted);
            if (hasItems)
                return BadRequest(new { success = false, message = "لا يمكن حذف التصنيف لوجود مواد مرتبطة به" });

            category.IsDeleted = true;
            category.DeletedAt = DateTime.UtcNow;
            _unitOfWork.InventoryCategories.Update(category);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حذف التصنيف بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف تصنيف");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== المواد - Items ====================

    /// <summary>
    /// جلب قائمة المواد مع الفلاتر
    /// </summary>
    [HttpGet("items")]
    public async Task<IActionResult> GetItems(
        [FromQuery] Guid? companyId = null,
        [FromQuery] int? categoryId = null,
        [FromQuery] string? search = null,
        [FromQuery] bool? lowStockOnly = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        try
        {
            var query = _unitOfWork.InventoryItems.AsQueryable().Where(i => !i.IsDeleted);

            if (companyId.HasValue)
                query = query.Where(i => i.CompanyId == companyId);
            if (categoryId.HasValue)
                query = query.Where(i => i.CategoryId == categoryId);
            if (!string.IsNullOrWhiteSpace(search))
                query = query.Where(i => i.Name.Contains(search) || i.SKU.Contains(search));

            // جلب مع مجموع المخزون
            var itemsQuery = query.Select(i => new
            {
                i.Id,
                i.Name,
                i.NameEn,
                i.SKU,
                i.Barcode,
                i.Description,
                i.CategoryId,
                CategoryName = i.Category != null ? i.Category.Name : null,
                Unit = i.Unit.ToString(),
                i.CostPrice,
                i.SellingPrice,
                i.WholesalePrice,
                i.MinStockLevel,
                i.MaxStockLevel,
                i.ImageUrl,
                i.IsActive,
                i.CompanyId,
                i.CreatedAt,
                TotalStock = i.Stocks.Where(s => !s.IsDeleted).Sum(s => s.CurrentQuantity)
            });

            if (lowStockOnly == true)
                itemsQuery = itemsQuery.Where(i => i.TotalStock < i.MinStockLevel);

            var total = await itemsQuery.CountAsync();
            var items = await itemsQuery
                .OrderBy(i => i.Name)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();

            return Ok(new { success = true, data = items, total, page, pageSize });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب المواد");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// جلب تفاصيل مادة مع أرصدة المستودعات
    /// </summary>
    [HttpGet("items/{id}")]
    public async Task<IActionResult> GetItemDetails(Guid id)
    {
        try
        {
            var item = await _unitOfWork.InventoryItems.AsQueryable()
                .Where(i => i.Id == id && !i.IsDeleted)
                .Select(i => new
                {
                    i.Id,
                    i.Name,
                    i.NameEn,
                    i.SKU,
                    i.Barcode,
                    i.Description,
                    i.CategoryId,
                    CategoryName = i.Category != null ? i.Category.Name : null,
                    Unit = i.Unit.ToString(),
                    i.CostPrice,
                    i.SellingPrice,
                    i.MinStockLevel,
                    i.MaxStockLevel,
                    i.ImageUrl,
                    i.IsActive,
                    i.CompanyId,
                    i.CreatedAt,
                    i.UpdatedAt,
                    TotalStock = i.Stocks.Where(s => !s.IsDeleted).Sum(s => s.CurrentQuantity),
                    Stocks = i.Stocks.Where(s => !s.IsDeleted).Select(s => new
                    {
                        s.Id,
                        s.WarehouseId,
                        WarehouseName = s.Warehouse != null ? s.Warehouse.Name : null,
                        s.CurrentQuantity,
                        s.ReservedQuantity,
                        s.AverageCost,
                        s.LastStockInDate,
                        s.LastStockOutDate
                    }).ToList()
                }).FirstOrDefaultAsync();

            if (item == null)
                return NotFound(new { success = false, message = "المادة غير موجودة" });

            return Ok(new { success = true, data = item });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب تفاصيل المادة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// جلب المواد منخفضة المخزون
    /// </summary>
    [HttpGet("items/low-stock")]
    public async Task<IActionResult> GetLowStockItems([FromQuery] Guid? companyId = null)
    {
        try
        {
            var query = _unitOfWork.InventoryItems.AsQueryable()
                .Where(i => !i.IsDeleted && i.IsActive);

            if (companyId.HasValue)
                query = query.Where(i => i.CompanyId == companyId);

            var items = await query.Select(i => new
            {
                i.Id,
                i.Name,
                i.NameEn,
                i.SKU,
                i.MinStockLevel,
                i.MaxStockLevel,
                CategoryName = i.Category != null ? i.Category.Name : null,
                Unit = i.Unit.ToString(),
                i.CompanyId,
                TotalStock = i.Stocks.Where(s => !s.IsDeleted).Sum(s => s.CurrentQuantity)
            })
            .Where(i => i.TotalStock < i.MinStockLevel)
            .OrderBy(i => i.TotalStock)
            .ToListAsync();

            return Ok(new { success = true, data = items, total = items.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب المواد منخفضة المخزون");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إنشاء مادة جديدة
    /// </summary>
    [HttpPost("items")]
    [RequirePermission("inventory", "add")]
    public async Task<IActionResult> CreateItem([FromBody] CreateItemRequest request)
    {
        try
        {
            // التحقق من عدم تكرار SKU
            var exists = await _unitOfWork.InventoryItems.AnyAsync(
                i => i.SKU == request.SKU && i.CompanyId == request.CompanyId && !i.IsDeleted);
            if (exists)
                return BadRequest(new { success = false, message = "رمز المادة (SKU) موجود مسبقاً" });

            var item = new InventoryItem
            {
                Id = Guid.NewGuid(),
                Name = request.Name,
                NameEn = request.NameEn,
                SKU = request.SKU,
                Barcode = request.Barcode,
                Description = request.Description,
                CategoryId = request.CategoryId,
                Unit = request.Unit,
                CostPrice = request.CostPrice,
                SellingPrice = request.SellingPrice,
                WholesalePrice = request.WholesalePrice,
                MinStockLevel = request.MinStockLevel,
                MaxStockLevel = request.MaxStockLevel,
                ImageUrl = request.ImageUrl,
                IsActive = true,
                CompanyId = request.CompanyId
            };

            await _unitOfWork.InventoryItems.AddAsync(item);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, data = new { item.Id, item.Name, item.SKU }, message = "تم إنشاء المادة بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء مادة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تعديل مادة
    /// </summary>
    [HttpPut("items/{id}")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> UpdateItem(Guid id, [FromBody] UpdateItemRequest request)
    {
        try
        {
            var item = await _unitOfWork.InventoryItems.GetByIdAsync(id);
            if (item == null || item.IsDeleted)
                return NotFound(new { success = false, message = "المادة غير موجودة" });

            // التحقق من عدم تكرار SKU
            if (!string.IsNullOrEmpty(request.SKU) && request.SKU != item.SKU)
            {
                var exists = await _unitOfWork.InventoryItems.AnyAsync(
                    i => i.SKU == request.SKU && i.CompanyId == item.CompanyId && i.Id != id && !i.IsDeleted);
                if (exists)
                    return BadRequest(new { success = false, message = "رمز المادة (SKU) موجود مسبقاً" });
            }

            item.Name = request.Name ?? item.Name;
            item.NameEn = request.NameEn ?? item.NameEn;
            item.SKU = request.SKU ?? item.SKU;
            item.Barcode = request.Barcode ?? item.Barcode;
            item.Description = request.Description ?? item.Description;
            item.CategoryId = request.CategoryId ?? item.CategoryId;
            item.Unit = request.Unit ?? item.Unit;
            item.CostPrice = request.CostPrice ?? item.CostPrice;
            item.SellingPrice = request.SellingPrice ?? item.SellingPrice;
            item.WholesalePrice = request.WholesalePrice ?? item.WholesalePrice;
            item.MinStockLevel = request.MinStockLevel ?? item.MinStockLevel;
            item.MaxStockLevel = request.MaxStockLevel ?? item.MaxStockLevel;
            item.ImageUrl = request.ImageUrl ?? item.ImageUrl;
            item.IsActive = request.IsActive ?? item.IsActive;
            item.UpdatedAt = DateTime.UtcNow;

            _unitOfWork.InventoryItems.Update(item);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تعديل المادة بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل مادة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// حذف مادة (حذف ناعم)
    /// </summary>
    [HttpDelete("items/{id}")]
    [RequirePermission("inventory", "delete")]
    public async Task<IActionResult> DeleteItem(Guid id)
    {
        try
        {
            var item = await _unitOfWork.InventoryItems.GetByIdAsync(id);
            if (item == null || item.IsDeleted)
                return NotFound(new { success = false, message = "المادة غير موجودة" });

            // التحقق من عدم وجود مخزون
            var hasStock = await _unitOfWork.WarehouseStocks.AnyAsync(
                ws => ws.InventoryItemId == id && ws.CurrentQuantity > 0);
            if (hasStock)
                return BadRequest(new { success = false, message = "لا يمكن حذف المادة لوجود مخزون لها" });

            item.IsDeleted = true;
            item.DeletedAt = DateTime.UtcNow;
            item.IsActive = false;
            _unitOfWork.InventoryItems.Update(item);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حذف المادة بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف مادة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== الموردين - Suppliers ====================

    /// <summary>
    /// جلب قائمة الموردين
    /// </summary>
    [HttpGet("suppliers")]
    public async Task<IActionResult> GetSuppliers(
        [FromQuery] Guid? companyId = null,
        [FromQuery] string? search = null)
    {
        try
        {
            var query = _unitOfWork.Suppliers.AsQueryable().Where(s => !s.IsDeleted);
            if (companyId.HasValue)
                query = query.Where(s => s.CompanyId == companyId);
            if (!string.IsNullOrWhiteSpace(search))
                query = query.Where(s => s.Name.Contains(search) || (s.Phone != null && s.Phone.Contains(search)));

            var suppliers = await query.OrderBy(s => s.Name).Select(s => new
            {
                s.Id,
                s.Name,
                s.ContactPerson,
                s.Phone,
                s.Email,
                s.Address,
                s.TaxNumber,
                s.Notes,
                s.IsActive,
                s.CompanyId,
                s.CreatedAt,
                PurchaseOrdersCount = s.PurchaseOrders.Count(po => !po.IsDeleted),
                TotalPurchases = s.PurchaseOrders.Where(po => !po.IsDeleted && po.Status != PurchaseOrderStatus.Cancelled)
                    .Sum(po => po.NetAmount)
            }).ToListAsync();

            return Ok(new { success = true, data = suppliers, total = suppliers.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب الموردين");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// جلب تفاصيل مورد
    /// </summary>
    [HttpGet("suppliers/{id}")]
    public async Task<IActionResult> GetSupplierDetails(Guid id)
    {
        try
        {
            var supplier = await _unitOfWork.Suppliers.AsQueryable()
                .Where(s => s.Id == id && !s.IsDeleted)
                .Select(s => new
                {
                    s.Id,
                    s.Name,
                    s.ContactPerson,
                    s.Phone,
                    s.Email,
                    s.Address,
                    s.TaxNumber,
                    s.Notes,
                    s.IsActive,
                    s.CompanyId,
                    s.CreatedAt,
                    s.UpdatedAt,
                    PurchaseOrdersCount = s.PurchaseOrders.Count(po => !po.IsDeleted),
                    TotalPurchases = s.PurchaseOrders.Where(po => !po.IsDeleted && po.Status != PurchaseOrderStatus.Cancelled)
                        .Sum(po => po.NetAmount)
                }).FirstOrDefaultAsync();

            if (supplier == null)
                return NotFound(new { success = false, message = "المورد غير موجود" });

            return Ok(new { success = true, data = supplier });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب تفاصيل المورد");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إنشاء مورد جديد
    /// </summary>
    [HttpPost("suppliers")]
    [RequirePermission("inventory", "add")]
    public async Task<IActionResult> CreateSupplier([FromBody] CreateSupplierRequest request)
    {
        try
        {
            var supplier = new Supplier
            {
                Id = Guid.NewGuid(),
                Name = request.Name,
                ContactPerson = request.ContactPerson,
                Phone = request.Phone,
                Email = request.Email,
                Address = request.Address,
                TaxNumber = request.TaxNumber,
                Notes = request.Notes,
                IsActive = true,
                CompanyId = request.CompanyId
            };

            await _unitOfWork.Suppliers.AddAsync(supplier);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, data = new { supplier.Id, supplier.Name }, message = "تم إنشاء المورد بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء مورد");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تعديل مورد
    /// </summary>
    [HttpPut("suppliers/{id}")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> UpdateSupplier(Guid id, [FromBody] UpdateSupplierRequest request)
    {
        try
        {
            var supplier = await _unitOfWork.Suppliers.GetByIdAsync(id);
            if (supplier == null || supplier.IsDeleted)
                return NotFound(new { success = false, message = "المورد غير موجود" });

            supplier.Name = request.Name ?? supplier.Name;
            supplier.ContactPerson = request.ContactPerson ?? supplier.ContactPerson;
            supplier.Phone = request.Phone ?? supplier.Phone;
            supplier.Email = request.Email ?? supplier.Email;
            supplier.Address = request.Address ?? supplier.Address;
            supplier.TaxNumber = request.TaxNumber ?? supplier.TaxNumber;
            supplier.Notes = request.Notes ?? supplier.Notes;
            supplier.IsActive = request.IsActive ?? supplier.IsActive;
            supplier.UpdatedAt = DateTime.UtcNow;

            _unitOfWork.Suppliers.Update(supplier);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تعديل المورد بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل مورد");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// حذف مورد (حذف ناعم)
    /// </summary>
    [HttpDelete("suppliers/{id}")]
    [RequirePermission("inventory", "delete")]
    public async Task<IActionResult> DeleteSupplier(Guid id)
    {
        try
        {
            var supplier = await _unitOfWork.Suppliers.GetByIdAsync(id);
            if (supplier == null || supplier.IsDeleted)
                return NotFound(new { success = false, message = "المورد غير موجود" });

            supplier.IsDeleted = true;
            supplier.DeletedAt = DateTime.UtcNow;
            supplier.IsActive = false;
            _unitOfWork.Suppliers.Update(supplier);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حذف المورد بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف مورد");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== أوامر الشراء - Purchase Orders ====================

    /// <summary>
    /// جلب أوامر الشراء
    /// </summary>
    [HttpGet("purchases")]
    public async Task<IActionResult> GetPurchaseOrders(
        [FromQuery] Guid? companyId = null,
        [FromQuery] PurchaseOrderStatus? status = null,
        [FromQuery] Guid? supplierId = null,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        try
        {
            var query = _unitOfWork.PurchaseOrders.AsQueryable().Where(po => !po.IsDeleted);

            if (companyId.HasValue)
                query = query.Where(po => po.CompanyId == companyId);
            if (status.HasValue)
                query = query.Where(po => po.Status == status);
            if (supplierId.HasValue)
                query = query.Where(po => po.SupplierId == supplierId);
            if (from.HasValue)
                query = query.Where(po => po.OrderDate >= DateTime.SpecifyKind(from.Value.AddHours(-3), DateTimeKind.Utc));
            if (to.HasValue)
                query = query.Where(po => po.OrderDate <= DateTime.SpecifyKind(to.Value.AddHours(-3), DateTimeKind.Utc));

            var total = await query.CountAsync();
            var orders = await query
                .OrderByDescending(po => po.OrderDate)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(po => new
                {
                    po.Id,
                    po.OrderNumber,
                    po.SupplierId,
                    SupplierName = po.Supplier != null ? po.Supplier.Name : null,
                    po.WarehouseId,
                    WarehouseName = po.Warehouse != null ? po.Warehouse.Name : null,
                    po.OrderDate,
                    po.ExpectedDeliveryDate,
                    po.ReceivedDate,
                    Status = po.Status.ToString(),
                    po.TotalAmount,
                    po.DiscountAmount,
                    po.TaxAmount,
                    po.NetAmount,
                    po.Notes,
                    po.CompanyId,
                    po.CreatedAt,
                    ItemsCount = po.Items.Count
                }).ToListAsync();

            return Ok(new { success = true, data = orders, total, page, pageSize });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب أوامر الشراء");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// جلب تفاصيل أمر شراء
    /// </summary>
    [HttpGet("purchases/{id}")]
    public async Task<IActionResult> GetPurchaseOrderDetails(Guid id)
    {
        try
        {
            var order = await _unitOfWork.PurchaseOrders.AsQueryable()
                .Where(po => po.Id == id && !po.IsDeleted)
                .Select(po => new
                {
                    po.Id,
                    po.OrderNumber,
                    po.SupplierId,
                    SupplierName = po.Supplier != null ? po.Supplier.Name : null,
                    po.WarehouseId,
                    WarehouseName = po.Warehouse != null ? po.Warehouse.Name : null,
                    po.OrderDate,
                    po.ExpectedDeliveryDate,
                    po.ReceivedDate,
                    Status = po.Status.ToString(),
                    po.TotalAmount,
                    po.DiscountAmount,
                    po.TaxAmount,
                    po.NetAmount,
                    po.Notes,
                    po.AttachmentUrl,
                    po.CreatedById,
                    po.ApprovedById,
                    po.CompanyId,
                    po.CreatedAt,
                    po.UpdatedAt,
                    Items = po.Items.Select(item => new
                    {
                        item.Id,
                        item.InventoryItemId,
                        ItemName = item.InventoryItem != null ? item.InventoryItem.Name : null,
                        ItemSKU = item.InventoryItem != null ? item.InventoryItem.SKU : null,
                        item.Quantity,
                        item.ReceivedQuantity,
                        item.UnitPrice,
                        item.TotalPrice,
                        item.Notes
                    }).ToList()
                }).FirstOrDefaultAsync();

            if (order == null)
                return NotFound(new { success = false, message = "أمر الشراء غير موجود" });

            return Ok(new { success = true, data = order });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب تفاصيل أمر الشراء");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إنشاء أمر شراء جديد (مسودة)
    /// </summary>
    [HttpPost("purchases")]
    [RequirePermission("inventory", "add")]
    public async Task<IActionResult> CreatePurchaseOrder([FromBody] CreatePurchaseOrderRequest request)
    {
        try
        {
            var orderNumber = await GenerateOrderNumber("PO", request.CompanyId);
            var currentUserId = GetCurrentUserId();

            var order = new PurchaseOrder
            {
                Id = Guid.NewGuid(),
                OrderNumber = orderNumber,
                SupplierId = request.SupplierId,
                WarehouseId = request.WarehouseId,
                OrderDate = DateTime.UtcNow,
                ExpectedDeliveryDate = request.ExpectedDeliveryDate.HasValue
                    ? DateTime.SpecifyKind(request.ExpectedDeliveryDate.Value, DateTimeKind.Utc)
                    : null,
                Status = PurchaseOrderStatus.Draft,
                Notes = request.Notes,
                CreatedById = currentUserId,
                CompanyId = request.CompanyId
            };

            decimal totalAmount = 0;
            foreach (var itemDto in request.Items)
            {
                var lineTotal = itemDto.Quantity * itemDto.UnitPrice;
                totalAmount += lineTotal;

                var orderItem = new PurchaseOrderItem
                {
                    PurchaseOrderId = order.Id,
                    InventoryItemId = itemDto.InventoryItemId,
                    Quantity = itemDto.Quantity,
                    ReceivedQuantity = itemDto.Quantity, // مستلم بالكامل مباشرة
                    UnitPrice = itemDto.UnitPrice,
                    TotalPrice = lineTotal
                };
                await _unitOfWork.PurchaseOrderItems.AddAsync(orderItem);

                // ── تحديث المخزون مباشرة ──
                var stock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                    s => s.WarehouseId == order.WarehouseId && s.InventoryItemId == itemDto.InventoryItemId && !s.IsDeleted);

                var isNewStock = false;
                if (stock == null)
                {
                    isNewStock = true;
                    stock = new WarehouseStock
                    {
                        WarehouseId = order.WarehouseId,
                        InventoryItemId = itemDto.InventoryItemId,
                        CurrentQuantity = 0,
                        AverageCost = 0,
                        CompanyId = request.CompanyId
                    };
                }

                var oldQty = stock.CurrentQuantity;
                var oldAvg = stock.AverageCost;
                var newQty = oldQty + itemDto.Quantity;
                stock.AverageCost = newQty > 0
                    ? ((oldQty * oldAvg) + (itemDto.Quantity * itemDto.UnitPrice)) / newQty
                    : itemDto.UnitPrice;
                stock.CurrentQuantity = newQty;
                stock.LastStockInDate = DateTime.UtcNow;

                if (isNewStock)
                    await _unitOfWork.WarehouseStocks.AddAsync(stock);
                else
                    _unitOfWork.WarehouseStocks.Update(stock);

                // ── حركة مخزنية ──
                await _unitOfWork.StockMovements.AddAsync(new StockMovement
                {
                    InventoryItemId = itemDto.InventoryItemId,
                    WarehouseId = order.WarehouseId,
                    MovementType = StockMovementType.PurchaseIn,
                    Quantity = itemDto.Quantity,
                    StockBefore = oldQty,
                    StockAfter = newQty,
                    UnitCost = itemDto.UnitPrice,
                    ReferenceType = "PurchaseOrder",
                    ReferenceId = order.Id.ToString(),
                    ReferenceNumber = orderNumber,
                    Description = $"شراء من {orderNumber}",
                    CreatedById = currentUserId,
                    CompanyId = request.CompanyId
                });
            }

            order.TotalAmount = totalAmount;
            order.DiscountAmount = request.DiscountAmount ?? 0;
            order.TaxAmount = request.TaxAmount ?? 0;
            order.NetAmount = totalAmount - (request.DiscountAmount ?? 0) + (request.TaxAmount ?? 0);
            order.Status = PurchaseOrderStatus.Received; // مستلم مباشرة
            order.ReceivedDate = DateTime.UtcNow;
            order.ApprovedById = currentUserId;

            await _unitOfWork.PurchaseOrders.AddAsync(order);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, data = new { order.Id, order.OrderNumber }, message = "تم إنشاء فاتورة الشراء وإضافة المواد للمخزون" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء أمر شراء");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تعديل أمر شراء (فقط إذا كان مسودة)
    /// </summary>
    [HttpPut("purchases/{id}")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> UpdatePurchaseOrder(Guid id, [FromBody] UpdatePurchaseOrderRequest request)
    {
        try
        {
            var order = await _unitOfWork.PurchaseOrders.GetByIdAsync(id);
            if (order == null || order.IsDeleted)
                return NotFound(new { success = false, message = "أمر الشراء غير موجود" });

            // السماح بتعديل المسودة والمستلمة
            if (order.Status == PurchaseOrderStatus.Cancelled)
                return BadRequest(new { success = false, message = "لا يمكن تعديل أمر شراء ملغي" });

            order.SupplierId = request.SupplierId ?? order.SupplierId;
            order.WarehouseId = request.WarehouseId ?? order.WarehouseId;
            order.ExpectedDeliveryDate = request.ExpectedDeliveryDate ?? order.ExpectedDeliveryDate;
            order.Notes = request.Notes ?? order.Notes;
            order.UpdatedAt = DateTime.UtcNow;

            // إعادة بناء البنود إذا تم تمريرها
            if (request.Items != null && request.Items.Count > 0)
            {
                // حذف البنود القديمة
                var oldItems = await _unitOfWork.PurchaseOrderItems.FindAsync(
                    poi => poi.PurchaseOrderId == id);
                foreach (var oldItem in oldItems)
                    _unitOfWork.PurchaseOrderItems.Delete(oldItem);

                decimal totalAmount = 0;
                foreach (var itemDto in request.Items)
                {
                    var lineTotal = itemDto.Quantity * itemDto.UnitPrice;
                    totalAmount += lineTotal;

                    var orderItem = new PurchaseOrderItem
                    {
                        PurchaseOrderId = order.Id,
                        InventoryItemId = itemDto.InventoryItemId,
                        Quantity = itemDto.Quantity,
                        ReceivedQuantity = 0,
                        UnitPrice = itemDto.UnitPrice,
                        TotalPrice = lineTotal
                    };
                    await _unitOfWork.PurchaseOrderItems.AddAsync(orderItem);
                }

                order.TotalAmount = totalAmount;
                order.NetAmount = totalAmount;
            }

            _unitOfWork.PurchaseOrders.Update(order);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تعديل أمر الشراء بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل أمر شراء");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// اعتماد أمر شراء
    /// </summary>
    [HttpPost("purchases/{id}/approve")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> ApprovePurchaseOrder(Guid id)
    {
        try
        {
            var order = await _unitOfWork.PurchaseOrders.GetByIdAsync(id);
            if (order == null || order.IsDeleted)
                return NotFound(new { success = false, message = "أمر الشراء غير موجود" });

            if (order.Status != PurchaseOrderStatus.Draft)
                return BadRequest(new { success = false, message = "لا يمكن اعتماد أمر شراء غير مسودة" });

            order.Status = PurchaseOrderStatus.Approved;
            order.ApprovedById = GetCurrentUserId();
            order.UpdatedAt = DateTime.UtcNow;

            _unitOfWork.PurchaseOrders.Update(order);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم اعتماد أمر الشراء بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في اعتماد أمر شراء");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// استلام مواد أمر شراء
    /// </summary>
    [HttpPost("purchases/{id}/receive")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> ReceivePurchaseOrder(Guid id, [FromBody] ReceivePurchaseOrderRequest request)
    {
        try
        {
            var order = await _unitOfWork.PurchaseOrders.GetByIdAsync(id);
            if (order == null || order.IsDeleted)
                return NotFound(new { success = false, message = "أمر الشراء غير موجود" });

            if (order.Status != PurchaseOrderStatus.Approved && order.Status != PurchaseOrderStatus.PartiallyReceived)
                return BadRequest(new { success = false, message = "لا يمكن استلام مواد أمر شراء غير معتمد" });

            await _unitOfWork.BeginTransactionAsync();
            try
            {
                var currentUserId = GetCurrentUserId();
                var allItems = await _unitOfWork.PurchaseOrderItems.FindAsync(
                    poi => poi.PurchaseOrderId == id);
                var itemsList = allItems.ToList();

                foreach (var receiveItem in request.Items)
                {
                    var poItem = itemsList.FirstOrDefault(i => i.Id == receiveItem.PurchaseOrderItemId);
                    if (poItem == null)
                        continue;

                    if (receiveItem.ReceivedQuantity <= 0)
                        continue;

                    // تحديث الكمية المستلمة
                    poItem.ReceivedQuantity += receiveItem.ReceivedQuantity;
                    _unitOfWork.PurchaseOrderItems.Update(poItem);

                    // جلب أو إنشاء سجل المخزون
                    var stock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                        ws => ws.WarehouseId == order.WarehouseId
                           && ws.InventoryItemId == poItem.InventoryItemId
                           && !ws.IsDeleted);

                    int oldQty = 0;
                    decimal oldAvgCost = 0;

                    if (stock == null)
                    {
                        stock = new WarehouseStock
                        {
                            WarehouseId = order.WarehouseId,
                            InventoryItemId = poItem.InventoryItemId,
                            CurrentQuantity = 0,
                            ReservedQuantity = 0,
                            AverageCost = 0,
                            CompanyId = order.CompanyId
                        };
                        await _unitOfWork.WarehouseStocks.AddAsync(stock);
                    }
                    else
                    {
                        oldQty = stock.CurrentQuantity;
                        oldAvgCost = stock.AverageCost;
                    }

                    // حساب متوسط التكلفة المرجح
                    var totalOldValue = oldQty * oldAvgCost;
                    var newValue = receiveItem.ReceivedQuantity * poItem.UnitPrice;
                    var newTotalQty = oldQty + receiveItem.ReceivedQuantity;
                    stock.AverageCost = newTotalQty > 0 ? (totalOldValue + newValue) / newTotalQty : poItem.UnitPrice;

                    var stockBefore = stock.CurrentQuantity;
                    stock.CurrentQuantity += receiveItem.ReceivedQuantity;
                    stock.LastStockInDate = DateTime.UtcNow;
                    stock.UpdatedAt = DateTime.UtcNow;
                    _unitOfWork.WarehouseStocks.Update(stock);

                    // إنشاء حركة مخزنية
                    var movement = new StockMovement
                    {
                        InventoryItemId = poItem.InventoryItemId,
                        WarehouseId = order.WarehouseId,
                        MovementType = StockMovementType.PurchaseIn,
                        Quantity = receiveItem.ReceivedQuantity,
                        StockBefore = stockBefore,
                        StockAfter = stock.CurrentQuantity,
                        UnitCost = poItem.UnitPrice,
                        ReferenceType = "PurchaseOrder",
                        ReferenceId = order.Id.ToString(),
                        ReferenceNumber = order.OrderNumber,
                        Description = $"استلام من أمر شراء {order.OrderNumber}",
                        CreatedById = currentUserId,
                        CompanyId = order.CompanyId
                    };
                    await _unitOfWork.StockMovements.AddAsync(movement);
                }

                // التحقق هل تم استلام كل البنود بالكامل
                var allFullyReceived = itemsList.All(i => i.ReceivedQuantity >= i.Quantity);
                if (allFullyReceived)
                {
                    order.Status = PurchaseOrderStatus.Received;
                    order.ReceivedDate = DateTime.UtcNow;
                }
                else
                {
                    order.Status = PurchaseOrderStatus.PartiallyReceived;
                }
                order.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.PurchaseOrders.Update(order);

                await _unitOfWork.SaveChangesAsync();
                await _unitOfWork.CommitTransactionAsync();

                return Ok(new { success = true, message = allFullyReceived ? "تم استلام جميع المواد بنجاح" : "تم استلام المواد جزئياً" });
            }
            catch
            {
                await _unitOfWork.RollbackTransactionAsync();
                throw;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في استلام مواد أمر الشراء");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إلغاء أمر شراء
    /// </summary>
    [HttpPost("purchases/{id}/cancel")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> CancelPurchaseOrder(Guid id)
    {
        try
        {
            var order = await _unitOfWork.PurchaseOrders.GetByIdAsync(id);
            if (order == null || order.IsDeleted)
                return NotFound(new { success = false, message = "أمر الشراء غير موجود" });

            if (order.Status != PurchaseOrderStatus.Draft && order.Status != PurchaseOrderStatus.Approved)
                return BadRequest(new { success = false, message = "لا يمكن إلغاء أمر شراء تم استلامه" });

            order.Status = PurchaseOrderStatus.Cancelled;
            order.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.PurchaseOrders.Update(order);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم إلغاء أمر الشراء بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إلغاء أمر شراء");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== المبيعات - Sales Orders ====================

    /// <summary>
    /// جلب عمليات البيع
    /// </summary>
    [HttpGet("sales")]
    public async Task<IActionResult> GetSalesOrders(
        [FromQuery] Guid? companyId = null,
        [FromQuery] SalesOrderStatus? status = null,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        try
        {
            var query = _unitOfWork.SalesOrders.AsQueryable().Where(so => !so.IsDeleted);

            if (companyId.HasValue)
                query = query.Where(so => so.CompanyId == companyId);
            if (status.HasValue)
                query = query.Where(so => so.Status == status);
            if (from.HasValue)
                query = query.Where(so => so.OrderDate >= DateTime.SpecifyKind(from.Value.AddHours(-3), DateTimeKind.Utc));
            if (to.HasValue)
                query = query.Where(so => so.OrderDate <= DateTime.SpecifyKind(to.Value.AddHours(-3), DateTimeKind.Utc));

            var total = await query.CountAsync();
            var orders = await query
                .OrderByDescending(so => so.OrderDate)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(so => new
                {
                    so.Id,
                    so.OrderNumber,
                    so.CustomerName,
                    so.CustomerPhone,
                    so.WarehouseId,
                    WarehouseName = so.Warehouse != null ? so.Warehouse.Name : null,
                    so.OrderDate,
                    Status = so.Status.ToString(),
                    so.TotalAmount,
                    so.DiscountAmount,
                    so.TaxAmount,
                    so.NetAmount,
                    PaymentMethod = so.PaymentMethod.ToString(),
                    so.Notes,
                    so.CompanyId,
                    so.CreatedAt,
                    ItemsCount = so.Items.Count
                }).ToListAsync();

            return Ok(new { success = true, data = orders, total, page, pageSize });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب عمليات البيع");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// جلب تفاصيل عملية بيع
    /// </summary>
    [HttpGet("sales/{id}")]
    public async Task<IActionResult> GetSalesOrderDetails(Guid id)
    {
        try
        {
            var order = await _unitOfWork.SalesOrders.AsQueryable()
                .Where(so => so.Id == id && !so.IsDeleted)
                .Select(so => new
                {
                    so.Id,
                    so.OrderNumber,
                    so.CustomerName,
                    so.CustomerPhone,
                    so.WarehouseId,
                    WarehouseName = so.Warehouse != null ? so.Warehouse.Name : null,
                    so.OrderDate,
                    Status = so.Status.ToString(),
                    so.TotalAmount,
                    so.DiscountAmount,
                    so.TaxAmount,
                    so.NetAmount,
                    PaymentMethod = so.PaymentMethod.ToString(),
                    so.Notes,
                    so.CreatedById,
                    so.CompanyId,
                    so.CreatedAt,
                    so.UpdatedAt,
                    Items = so.Items.Select(item => new
                    {
                        item.Id,
                        item.InventoryItemId,
                        ItemName = item.InventoryItem != null ? item.InventoryItem.Name : null,
                        ItemSKU = item.InventoryItem != null ? item.InventoryItem.SKU : null,
                        item.Quantity,
                        item.UnitPrice,
                        item.TotalPrice
                    }).ToList()
                }).FirstOrDefaultAsync();

            if (order == null)
                return NotFound(new { success = false, message = "عملية البيع غير موجودة" });

            return Ok(new { success = true, data = order });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب تفاصيل عملية البيع");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إنشاء عملية بيع جديدة
    /// </summary>
    [HttpPost("sales")]
    [RequirePermission("inventory", "add")]
    public async Task<IActionResult> CreateSalesOrder([FromBody] CreateSalesOrderRequest request)
    {
        try
        {
            // التحقق من توفر المخزون
            foreach (var itemDto in request.Items)
            {
                var stock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                    ws => ws.WarehouseId == request.WarehouseId
                       && ws.InventoryItemId == itemDto.InventoryItemId
                       && !ws.IsDeleted);

                var available = stock?.CurrentQuantity ?? 0;
                if (available < itemDto.Quantity)
                {
                    var itemName = (await _unitOfWork.InventoryItems.GetByIdAsync(itemDto.InventoryItemId))?.Name ?? "مادة غير معروفة";
                    return BadRequest(new { success = false, message = $"المخزون غير كافٍ للمادة: {itemName} (المتاح: {available}، المطلوب: {itemDto.Quantity})" });
                }
            }

            var orderNumber = await GenerateOrderNumber("SO", request.CompanyId);
            var currentUserId = GetCurrentUserId();

            var order = new SalesOrder
            {
                Id = Guid.NewGuid(),
                OrderNumber = orderNumber,
                CustomerName = request.CustomerName,
                CustomerPhone = request.CustomerPhone,
                WarehouseId = request.WarehouseId,
                OrderDate = DateTime.UtcNow,
                Status = SalesOrderStatus.Draft,
                PaymentMethod = request.PaymentMethod,
                Notes = request.Notes,
                CreatedById = currentUserId,
                CompanyId = request.CompanyId
            };

            decimal totalAmount = 0;
            foreach (var itemDto in request.Items)
            {
                var lineTotal = itemDto.Quantity * itemDto.UnitPrice;
                totalAmount += lineTotal;

                var orderItem = new SalesOrderItem
                {
                    SalesOrderId = order.Id,
                    InventoryItemId = itemDto.InventoryItemId,
                    Quantity = itemDto.Quantity,
                    UnitPrice = itemDto.UnitPrice,
                    TotalPrice = lineTotal
                };
                await _unitOfWork.SalesOrderItems.AddAsync(orderItem);
            }

            order.TotalAmount = totalAmount;
            order.NetAmount = totalAmount;

            await _unitOfWork.SalesOrders.AddAsync(order);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, data = new { order.Id, order.OrderNumber }, message = "تم إنشاء عملية البيع بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء عملية بيع");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تأكيد عملية بيع (خصم من المخزون)
    /// </summary>
    [HttpPost("sales/{id}/confirm")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> ConfirmSalesOrder(Guid id)
    {
        try
        {
            var order = await _unitOfWork.SalesOrders.GetByIdAsync(id);
            if (order == null || order.IsDeleted)
                return NotFound(new { success = false, message = "عملية البيع غير موجودة" });

            if (order.Status != SalesOrderStatus.Draft)
                return BadRequest(new { success = false, message = "لا يمكن تأكيد عملية بيع غير مسودة" });

            await _unitOfWork.BeginTransactionAsync();
            try
            {
                var currentUserId = GetCurrentUserId();
                var orderItems = await _unitOfWork.SalesOrderItems.FindAsync(
                    soi => soi.SalesOrderId == id);

                foreach (var soItem in orderItems)
                {
                    var stock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                        ws => ws.WarehouseId == order.WarehouseId
                           && ws.InventoryItemId == soItem.InventoryItemId
                           && !ws.IsDeleted);

                    if (stock == null || stock.CurrentQuantity < soItem.Quantity)
                    {
                        await _unitOfWork.RollbackTransactionAsync();
                        var itemName = (await _unitOfWork.InventoryItems.GetByIdAsync(soItem.InventoryItemId))?.Name ?? "مادة غير معروفة";
                        return BadRequest(new { success = false, message = $"المخزون غير كافٍ للمادة: {itemName}" });
                    }

                    var stockBefore = stock.CurrentQuantity;
                    stock.CurrentQuantity -= soItem.Quantity;
                    stock.LastStockOutDate = DateTime.UtcNow;
                    stock.UpdatedAt = DateTime.UtcNow;
                    _unitOfWork.WarehouseStocks.Update(stock);

                    var movement = new StockMovement
                    {
                        InventoryItemId = soItem.InventoryItemId,
                        WarehouseId = order.WarehouseId,
                        MovementType = StockMovementType.SalesOut,
                        Quantity = soItem.Quantity,
                        StockBefore = stockBefore,
                        StockAfter = stock.CurrentQuantity,
                        UnitCost = soItem.UnitPrice,
                        ReferenceType = "SalesOrder",
                        ReferenceId = order.Id.ToString(),
                        ReferenceNumber = order.OrderNumber,
                        Description = $"بيع - {order.OrderNumber}",
                        CreatedById = currentUserId,
                        CompanyId = order.CompanyId
                    };
                    await _unitOfWork.StockMovements.AddAsync(movement);
                }

                order.Status = SalesOrderStatus.Confirmed;
                order.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.SalesOrders.Update(order);

                await _unitOfWork.SaveChangesAsync();
                await _unitOfWork.CommitTransactionAsync();

                return Ok(new { success = true, message = "تم تأكيد عملية البيع بنجاح" });
            }
            catch
            {
                await _unitOfWork.RollbackTransactionAsync();
                throw;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تأكيد عملية البيع");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إلغاء عملية بيع (إرجاع المخزون إذا كانت مؤكدة)
    /// </summary>
    [HttpPost("sales/{id}/cancel")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> CancelSalesOrder(Guid id)
    {
        try
        {
            var order = await _unitOfWork.SalesOrders.GetByIdAsync(id);
            if (order == null || order.IsDeleted)
                return NotFound(new { success = false, message = "عملية البيع غير موجودة" });

            if (order.Status == SalesOrderStatus.Cancelled)
                return BadRequest(new { success = false, message = "عملية البيع ملغية مسبقاً" });

            await _unitOfWork.BeginTransactionAsync();
            try
            {
                var currentUserId = GetCurrentUserId();

                // إذا كانت مؤكدة، إرجاع المخزون
                if (order.Status == SalesOrderStatus.Confirmed || order.Status == SalesOrderStatus.Delivered)
                {
                    var orderItems = await _unitOfWork.SalesOrderItems.FindAsync(
                        soi => soi.SalesOrderId == id);

                    foreach (var soItem in orderItems)
                    {
                        var stock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                            ws => ws.WarehouseId == order.WarehouseId
                               && ws.InventoryItemId == soItem.InventoryItemId
                               && !ws.IsDeleted);

                        if (stock != null)
                        {
                            var stockBefore = stock.CurrentQuantity;
                            stock.CurrentQuantity += soItem.Quantity;
                            stock.UpdatedAt = DateTime.UtcNow;
                            _unitOfWork.WarehouseStocks.Update(stock);

                            var movement = new StockMovement
                            {
                                InventoryItemId = soItem.InventoryItemId,
                                WarehouseId = order.WarehouseId,
                                MovementType = StockMovementType.PurchaseIn,
                                Quantity = soItem.Quantity,
                                StockBefore = stockBefore,
                                StockAfter = stock.CurrentQuantity,
                                UnitCost = soItem.UnitPrice,
                                ReferenceType = "SalesOrder",
                                ReferenceId = order.Id.ToString(),
                                ReferenceNumber = order.OrderNumber,
                                Description = $"إرجاع مخزون - إلغاء بيع {order.OrderNumber}",
                                CreatedById = currentUserId,
                                CompanyId = order.CompanyId
                            };
                            await _unitOfWork.StockMovements.AddAsync(movement);
                        }
                    }
                }

                order.Status = SalesOrderStatus.Cancelled;
                order.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.SalesOrders.Update(order);

                await _unitOfWork.SaveChangesAsync();
                await _unitOfWork.CommitTransactionAsync();

                return Ok(new { success = true, message = "تم إلغاء عملية البيع بنجاح" });
            }
            catch
            {
                await _unitOfWork.RollbackTransactionAsync();
                throw;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إلغاء عملية البيع");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== صرف الفنيين - Technician Dispensing ====================

    /// <summary>
    /// جلب عمليات صرف الفنيين
    /// </summary>
    [HttpGet("dispensing")]
    public async Task<IActionResult> GetTechnicianDispensings(
        [FromQuery] Guid? companyId = null,
        [FromQuery] Guid? technicianId = null,
        [FromQuery] Guid? serviceRequestId = null,
        [FromQuery] DispensingStatus? status = null,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null)
    {
        try
        {
            var query = _unitOfWork.TechnicianDispensings.AsQueryable().Where(td => !td.IsDeleted);

            if (companyId.HasValue)
                query = query.Where(td => td.CompanyId == companyId);
            if (technicianId.HasValue)
                query = query.Where(td => td.TechnicianId == technicianId);
            if (serviceRequestId.HasValue)
                query = query.Where(td => td.ServiceRequestId == serviceRequestId);
            if (status.HasValue)
                query = query.Where(td => td.Status == status);
            if (from.HasValue)
                query = query.Where(td => td.DispensingDate >= DateTime.SpecifyKind(from.Value.AddHours(-3), DateTimeKind.Utc));
            if (to.HasValue)
                query = query.Where(td => td.DispensingDate <= DateTime.SpecifyKind(to.Value.AddHours(-3), DateTimeKind.Utc));

            var dispensings = await query
                .OrderByDescending(td => td.DispensingDate)
                .Select(td => new
                {
                    td.Id,
                    td.VoucherNumber,
                    td.TechnicianId,
                    TechnicianName = td.Technician != null ? td.Technician.FullName : null,
                    td.WarehouseId,
                    WarehouseName = td.Warehouse != null ? td.Warehouse.Name : null,
                    td.ServiceRequestId,
                    td.DispensingDate,
                    Status = td.Status.ToString(),
                    Type = td.Type.ToString(),
                    td.Notes,
                    td.CompanyId,
                    td.CreatedAt,
                    ItemsCount = td.Items.Count
                }).ToListAsync();

            return Ok(new { success = true, data = dispensings, total = dispensings.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب عمليات صرف الفنيين");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// جلب تفاصيل عملية صرف
    /// </summary>
    [HttpGet("dispensing/{id}")]
    public async Task<IActionResult> GetDispensingDetails(Guid id)
    {
        try
        {
            var dispensing = await _unitOfWork.TechnicianDispensings.AsQueryable()
                .Where(td => td.Id == id && !td.IsDeleted)
                .Select(td => new
                {
                    td.Id,
                    td.VoucherNumber,
                    td.TechnicianId,
                    TechnicianName = td.Technician != null ? td.Technician.FullName : null,
                    td.WarehouseId,
                    WarehouseName = td.Warehouse != null ? td.Warehouse.Name : null,
                    td.ServiceRequestId,
                    td.DispensingDate,
                    Status = td.Status.ToString(),
                    Type = td.Type.ToString(),
                    td.Notes,
                    td.CreatedById,
                    td.ApprovedById,
                    td.CompanyId,
                    td.CreatedAt,
                    td.UpdatedAt,
                    Items = td.Items.Select(item => new
                    {
                        item.Id,
                        item.InventoryItemId,
                        ItemName = item.InventoryItem != null ? item.InventoryItem.Name : null,
                        ItemSKU = item.InventoryItem != null ? item.InventoryItem.SKU : null,
                        item.Quantity,
                        item.ReturnedQuantity,
                        RemainingQuantity = item.Quantity - item.ReturnedQuantity,
                        item.Notes
                    }).ToList()
                }).FirstOrDefaultAsync();

            if (dispensing == null)
                return NotFound(new { success = false, message = "عملية الصرف غير موجودة" });

            return Ok(new { success = true, data = dispensing });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب تفاصيل عملية الصرف");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إنشاء عملية صرف فني جديدة
    /// </summary>
    [HttpPost("dispensing")]
    [RequirePermission("inventory", "add")]
    public async Task<IActionResult> CreateTechnicianDispensing([FromBody] CreateDispensingRequest request)
    {
        try
        {
            var voucherNumber = await GenerateOrderNumber("TD", request.CompanyId);
            var currentUserId = GetCurrentUserId();

            var dispensing = new TechnicianDispensing
            {
                Id = Guid.NewGuid(),
                VoucherNumber = voucherNumber,
                TechnicianId = request.TechnicianId,
                WarehouseId = request.WarehouseId,
                ServiceRequestId = request.ServiceRequestId,
                DispensingDate = DateTime.UtcNow,
                Status = DispensingStatus.Approved, // مصروف مباشرة
                Type = request.Type,
                Notes = request.Notes,
                CreatedById = currentUserId,
                ApprovedById = currentUserId,
                CompanyId = request.CompanyId
            };

            foreach (var itemDto in request.Items)
            {
                var dispensingItem = new TechnicianDispensingItem
                {
                    TechnicianDispensingId = dispensing.Id,
                    InventoryItemId = itemDto.InventoryItemId,
                    Quantity = itemDto.Quantity,
                    ReturnedQuantity = 0
                };
                await _unitOfWork.TechnicianDispensingItems.AddAsync(dispensingItem);

                // ── تحديث المخزون مباشرة (خصم من المستودع) ──
                var stock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                    s => s.WarehouseId == request.WarehouseId && s.InventoryItemId == itemDto.InventoryItemId && !s.IsDeleted);

                var oldQty = stock?.CurrentQuantity ?? 0;
                var newQty = oldQty - itemDto.Quantity;
                if (newQty < 0) newQty = 0;

                if (stock != null)
                {
                    stock.CurrentQuantity = newQty;
                    stock.LastStockOutDate = DateTime.UtcNow;
                    _unitOfWork.WarehouseStocks.Update(stock);
                }

                // ── حركة مخزنية ──
                await _unitOfWork.StockMovements.AddAsync(new StockMovement
                {
                    InventoryItemId = itemDto.InventoryItemId,
                    WarehouseId = request.WarehouseId,
                    MovementType = StockMovementType.TechnicianDispensing,
                    Quantity = itemDto.Quantity,
                    StockBefore = oldQty,
                    StockAfter = newQty,
                    ReferenceType = "TechnicianDispensing",
                    ReferenceId = dispensing.Id.ToString(),
                    ReferenceNumber = voucherNumber,
                    Description = $"صرف فني - {voucherNumber}",
                    CreatedById = currentUserId,
                    CompanyId = request.CompanyId
                });
            }

            await _unitOfWork.TechnicianDispensings.AddAsync(dispensing);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, data = new { dispensing.Id, dispensing.VoucherNumber }, message = "تم صرف المواد بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء عملية صرف");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// حذف سند صرف (soft delete)
    /// </summary>
    [HttpDelete("dispensing/{id}")]
    [RequirePermission("inventory", "delete")]
    public async Task<IActionResult> DeleteDispensing(Guid id)
    {
        try
        {
            var dispensing = await _unitOfWork.TechnicianDispensings.GetByIdAsync(id);
            if (dispensing == null || dispensing.IsDeleted)
                return NotFound(new { success = false, message = "سند الصرف غير موجود" });

            dispensing.IsDeleted = true;
            dispensing.DeletedAt = DateTime.UtcNow;
            _unitOfWork.TechnicianDispensings.Update(dispensing);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حذف سند الصرف" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف سند صرف");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// الموافقة على عملية صرف ومعالجتها
    /// </summary>
    [HttpPost("dispensing/{id}/approve")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> ApproveDispensing(Guid id)
    {
        try
        {
            var dispensing = await _unitOfWork.TechnicianDispensings.GetByIdAsync(id);
            if (dispensing == null || dispensing.IsDeleted)
                return NotFound(new { success = false, message = "عملية الصرف غير موجودة" });

            if (dispensing.Status != DispensingStatus.Pending)
                return BadRequest(new { success = false, message = "لا يمكن الموافقة على عملية ليست بانتظار الموافقة" });

            await _unitOfWork.BeginTransactionAsync();
            try
            {
                var currentUserId = GetCurrentUserId();
                var dispensingItems = await _unitOfWork.TechnicianDispensingItems.FindAsync(
                    tdi => tdi.TechnicianDispensingId == id);

                foreach (var tdItem in dispensingItems)
                {
                    var stock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                        ws => ws.WarehouseId == dispensing.WarehouseId
                           && ws.InventoryItemId == tdItem.InventoryItemId
                           && !ws.IsDeleted);

                    if (dispensing.Type == DispensingType.Dispensing)
                    {
                        // صرف: خصم من المخزون
                        if (stock == null || stock.CurrentQuantity < tdItem.Quantity)
                        {
                            await _unitOfWork.RollbackTransactionAsync();
                            var itemName = (await _unitOfWork.InventoryItems.GetByIdAsync(tdItem.InventoryItemId))?.Name ?? "مادة غير معروفة";
                            return BadRequest(new { success = false, message = $"المخزون غير كافٍ للمادة: {itemName}" });
                        }

                        var stockBefore = stock.CurrentQuantity;
                        stock.CurrentQuantity -= tdItem.Quantity;
                        stock.LastStockOutDate = DateTime.UtcNow;
                        stock.UpdatedAt = DateTime.UtcNow;
                        _unitOfWork.WarehouseStocks.Update(stock);

                        var movement = new StockMovement
                        {
                            InventoryItemId = tdItem.InventoryItemId,
                            WarehouseId = dispensing.WarehouseId,
                            MovementType = StockMovementType.TechnicianDispensing,
                            Quantity = tdItem.Quantity,
                            StockBefore = stockBefore,
                            StockAfter = stock.CurrentQuantity,
                            UnitCost = stock.AverageCost,
                            ReferenceType = "TechnicianDispensing",
                            ReferenceId = dispensing.Id.ToString(),
                            ReferenceNumber = dispensing.VoucherNumber,
                            Description = $"صرف فني - {dispensing.VoucherNumber}",
                            CreatedById = currentUserId,
                            CompanyId = dispensing.CompanyId
                        };
                        await _unitOfWork.StockMovements.AddAsync(movement);
                    }
                    else
                    {
                        // إرجاع: إضافة للمخزون
                        if (stock == null)
                        {
                            stock = new WarehouseStock
                            {
                                WarehouseId = dispensing.WarehouseId,
                                InventoryItemId = tdItem.InventoryItemId,
                                CurrentQuantity = 0,
                                ReservedQuantity = 0,
                                AverageCost = 0,
                                CompanyId = dispensing.CompanyId
                            };
                            await _unitOfWork.WarehouseStocks.AddAsync(stock);
                        }

                        var stockBefore = stock.CurrentQuantity;
                        stock.CurrentQuantity += tdItem.Quantity;
                        stock.LastStockInDate = DateTime.UtcNow;
                        stock.UpdatedAt = DateTime.UtcNow;
                        _unitOfWork.WarehouseStocks.Update(stock);

                        var movement = new StockMovement
                        {
                            InventoryItemId = tdItem.InventoryItemId,
                            WarehouseId = dispensing.WarehouseId,
                            MovementType = StockMovementType.TechnicianReturn,
                            Quantity = tdItem.Quantity,
                            StockBefore = stockBefore,
                            StockAfter = stock.CurrentQuantity,
                            UnitCost = stock.AverageCost,
                            ReferenceType = "TechnicianDispensing",
                            ReferenceId = dispensing.Id.ToString(),
                            ReferenceNumber = dispensing.VoucherNumber,
                            Description = $"إرجاع فني - {dispensing.VoucherNumber}",
                            CreatedById = currentUserId,
                            CompanyId = dispensing.CompanyId
                        };
                        await _unitOfWork.StockMovements.AddAsync(movement);
                    }
                }

                dispensing.Status = DispensingStatus.Approved;
                dispensing.ApprovedById = currentUserId;
                dispensing.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.TechnicianDispensings.Update(dispensing);

                await _unitOfWork.SaveChangesAsync();
                await _unitOfWork.CommitTransactionAsync();

                return Ok(new { success = true, message = "تم الموافقة على عملية الصرف ومعالجتها بنجاح" });
            }
            catch
            {
                await _unitOfWork.RollbackTransactionAsync();
                throw;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في الموافقة على عملية الصرف");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// إرجاع مواد من فني (إرجاع جزئي أو كامل)
    /// </summary>
    [HttpPost("dispensing/{id}/return")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> ReturnDispensingItems(Guid id, [FromBody] ReturnDispensingRequest request)
    {
        try
        {
            var dispensing = await _unitOfWork.TechnicianDispensings.GetByIdAsync(id);
            if (dispensing == null || dispensing.IsDeleted)
                return NotFound(new { success = false, message = "عملية الصرف غير موجودة" });

            if (dispensing.Status != DispensingStatus.Approved && dispensing.Status != DispensingStatus.PartialReturn)
                return BadRequest(new { success = false, message = "لا يمكن إرجاع مواد من عملية لم تتم الموافقة عليها" });

            await _unitOfWork.BeginTransactionAsync();
            try
            {
                var currentUserId = GetCurrentUserId();
                var allItems = await _unitOfWork.TechnicianDispensingItems.FindAsync(
                    tdi => tdi.TechnicianDispensingId == id);
                var itemsList = allItems.ToList();

                foreach (var returnItem in request.Items)
                {
                    var tdItem = itemsList.FirstOrDefault(i => i.Id == returnItem.TechnicianDispensingItemId);
                    if (tdItem == null)
                        continue;

                    if (returnItem.ReturnQuantity <= 0)
                        continue;

                    var maxReturnable = tdItem.Quantity - tdItem.ReturnedQuantity;
                    var actualReturn = Math.Min(returnItem.ReturnQuantity, maxReturnable);

                    if (actualReturn <= 0)
                        continue;

                    tdItem.ReturnedQuantity += actualReturn;
                    _unitOfWork.TechnicianDispensingItems.Update(tdItem);

                    // إضافة للمخزون
                    var stock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                        ws => ws.WarehouseId == dispensing.WarehouseId
                           && ws.InventoryItemId == tdItem.InventoryItemId
                           && !ws.IsDeleted);

                    if (stock == null)
                    {
                        stock = new WarehouseStock
                        {
                            WarehouseId = dispensing.WarehouseId,
                            InventoryItemId = tdItem.InventoryItemId,
                            CurrentQuantity = 0,
                            ReservedQuantity = 0,
                            AverageCost = 0,
                            CompanyId = dispensing.CompanyId
                        };
                        await _unitOfWork.WarehouseStocks.AddAsync(stock);
                    }

                    var stockBefore = stock.CurrentQuantity;
                    stock.CurrentQuantity += actualReturn;
                    stock.LastStockInDate = DateTime.UtcNow;
                    stock.UpdatedAt = DateTime.UtcNow;
                    _unitOfWork.WarehouseStocks.Update(stock);

                    var movement = new StockMovement
                    {
                        InventoryItemId = tdItem.InventoryItemId,
                        WarehouseId = dispensing.WarehouseId,
                        MovementType = StockMovementType.TechnicianReturn,
                        Quantity = actualReturn,
                        StockBefore = stockBefore,
                        StockAfter = stock.CurrentQuantity,
                        UnitCost = stock.AverageCost,
                        ReferenceType = "TechnicianDispensing",
                        ReferenceId = dispensing.Id.ToString(),
                        ReferenceNumber = dispensing.VoucherNumber,
                        Description = $"إرجاع فني - {dispensing.VoucherNumber}",
                        CreatedById = currentUserId,
                        CompanyId = dispensing.CompanyId
                    };
                    await _unitOfWork.StockMovements.AddAsync(movement);
                }

                // تحديث حالة الصرف
                var allFullyReturned = itemsList.All(i => i.ReturnedQuantity >= i.Quantity);
                var anyReturned = itemsList.Any(i => i.ReturnedQuantity > 0);

                if (allFullyReturned)
                    dispensing.Status = DispensingStatus.FullReturn;
                else if (anyReturned)
                    dispensing.Status = DispensingStatus.PartialReturn;

                dispensing.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.TechnicianDispensings.Update(dispensing);

                await _unitOfWork.SaveChangesAsync();
                await _unitOfWork.CommitTransactionAsync();

                return Ok(new { success = true, message = allFullyReturned ? "تم إرجاع جميع المواد بنجاح" : "تم إرجاع المواد جزئياً" });
            }
            catch
            {
                await _unitOfWork.RollbackTransactionAsync();
                throw;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إرجاع مواد من فني");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// جلب المواد الحالية بحوزة فني
    /// </summary>
    [HttpGet("dispensing/technician/{technicianId}")]
    public async Task<IActionResult> GetTechnicianHoldings(Guid technicianId)
    {
        try
        {
            var holdings = await _unitOfWork.TechnicianDispensingItems.AsQueryable()
                .Where(tdi => tdi.TechnicianDispensing != null
                    && tdi.TechnicianDispensing.TechnicianId == technicianId
                    && tdi.TechnicianDispensing.Status == DispensingStatus.Approved
                    && tdi.TechnicianDispensing.Type == DispensingType.Dispensing
                    && !tdi.TechnicianDispensing.IsDeleted
                    && tdi.Quantity > tdi.ReturnedQuantity)
                .Select(tdi => new
                {
                    tdi.Id,
                    DispensingId = tdi.TechnicianDispensingId,
                    VoucherNumber = tdi.TechnicianDispensing != null ? tdi.TechnicianDispensing.VoucherNumber : null,
                    DispensingDate = tdi.TechnicianDispensing != null ? tdi.TechnicianDispensing.DispensingDate : DateTime.MinValue,
                    tdi.InventoryItemId,
                    ItemName = tdi.InventoryItem != null ? tdi.InventoryItem.Name : null,
                    ItemSKU = tdi.InventoryItem != null ? tdi.InventoryItem.SKU : null,
                    tdi.Quantity,
                    tdi.ReturnedQuantity,
                    RemainingQuantity = tdi.Quantity - tdi.ReturnedQuantity
                }).ToListAsync();

            return Ok(new { success = true, data = holdings, total = holdings.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب مواد الفني");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// صرف مواد من عُهدة الفني للعميل (من المهمة)
    /// يخصم من عُهدة الفني فقط ولا يؤثر على المخزون
    /// </summary>
    [HttpPost("dispensing/use-from-holdings")]
    [RequirePermission("inventory", "add")]
    public async Task<IActionResult> UseFromTechnicianHoldings([FromBody] UseFromHoldingsRequest request)
    {
        try
        {
            var currentUserId = GetCurrentUserId();

            foreach (var itemReq in request.Items)
            {
                // نبحث عن بنود الصرف المعتمدة للفني لهذه المادة
                var holdingItems = await _unitOfWork.TechnicianDispensingItems.AsQueryable()
                    .Where(tdi => tdi.TechnicianDispensing != null
                        && tdi.TechnicianDispensing.TechnicianId == request.TechnicianId
                        && tdi.TechnicianDispensing.Status == DispensingStatus.Approved
                        && tdi.TechnicianDispensing.Type == DispensingType.Dispensing
                        && !tdi.TechnicianDispensing.IsDeleted
                        && tdi.InventoryItemId == itemReq.InventoryItemId
                        && tdi.Quantity > tdi.ReturnedQuantity)
                    .OrderBy(tdi => tdi.CreatedAt) // FIFO — الأقدم أولاً
                    .ToListAsync();

                var totalAvailable = holdingItems.Sum(h => h.Quantity - h.ReturnedQuantity);

                // خصم من العُهدة بنظام FIFO (ما توفر منها)
                var remaining = itemReq.Quantity;
                foreach (var h in holdingItems)
                {
                    if (remaining <= 0) break;
                    var canUse = h.Quantity - h.ReturnedQuantity;
                    var used = Math.Min(canUse, remaining);
                    h.ReturnedQuantity += used;
                    remaining -= used;
                    _unitOfWork.TechnicianDispensingItems.Update(h);
                }

                // إذا الكمية المطلوبة أكبر من المتوفرة → إنشاء سجل سالب (عجز)
                // سيُستقطع تلقائياً عند تعزيز الفني من المستودع لاحقاً
                if (remaining > 0)
                {
                    // إنشاء سجل صرف جديد بكمية سالبة (عجز) للفني
                    var deficitDispensing = new TechnicianDispensing
                    {
                        Id = Guid.NewGuid(),
                        VoucherNumber = $"TD-DEF-{DateTime.UtcNow:yyMMddHHmmss}",
                        TechnicianId = request.TechnicianId,
                        WarehouseId = Guid.Empty,
                        ServiceRequestId = request.ServiceRequestId,
                        DispensingDate = DateTime.UtcNow,
                        Status = DispensingStatus.Approved,
                        Type = DispensingType.Dispensing,
                        Notes = $"صرف بعجز — الفني لا يملك رصيد كافٍ (عجز: {remaining})",
                        CreatedById = currentUserId,
                        CompanyId = request.CompanyId,
                        Items = new List<TechnicianDispensingItem>
                        {
                            new TechnicianDispensingItem
                            {
                                InventoryItemId = itemReq.InventoryItemId,
                                Quantity = remaining,
                                ReturnedQuantity = remaining, // مصروف بالكامل
                            }
                        }
                    };
                    await _unitOfWork.TechnicianDispensings.AddAsync(deficitDispensing);
                }

                // حركة مخزنية للتوثيق
                await _unitOfWork.StockMovements.AddAsync(new StockMovement
                {
                    InventoryItemId = itemReq.InventoryItemId,
                    WarehouseId = Guid.Empty,
                    MovementType = StockMovementType.TechnicianDispensing,
                    Quantity = itemReq.Quantity,
                    StockBefore = totalAvailable,
                    StockAfter = totalAvailable - itemReq.Quantity,
                    ReferenceType = "TaskDispensing",
                    ReferenceId = request.ServiceRequestId?.ToString(),
                    Description = totalAvailable >= itemReq.Quantity
                        ? "صرف من عُهدة الفني للعميل - مهمة"
                        : $"صرف من عُهدة الفني للعميل - مهمة (عجز: {itemReq.Quantity - totalAvailable})",
                    CreatedById = currentUserId,
                    CompanyId = request.CompanyId
                });
            }

            await _unitOfWork.SaveChangesAsync();
            return Ok(new { success = true, message = "تم صرف المواد بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في صرف من عُهدة الفني");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== المخزون والحركات - Stock & Movements ====================

    /// <summary>
    /// جلب أرصدة المخزون الحالية
    /// </summary>
    [HttpGet("stock")]
    public async Task<IActionResult> GetStock(
        [FromQuery] Guid? companyId = null,
        [FromQuery] Guid? warehouseId = null)
    {
        try
        {
            var query = _unitOfWork.WarehouseStocks.AsQueryable().Where(ws => !ws.IsDeleted);

            if (companyId.HasValue)
                query = query.Where(ws => ws.CompanyId == companyId);
            if (warehouseId.HasValue)
                query = query.Where(ws => ws.WarehouseId == warehouseId);

            var stock = await query.Select(ws => new
            {
                ws.Id,
                ws.WarehouseId,
                WarehouseName = ws.Warehouse != null ? ws.Warehouse.Name : null,
                ws.InventoryItemId,
                ItemName = ws.InventoryItem != null ? ws.InventoryItem.Name : null,
                ItemSKU = ws.InventoryItem != null ? ws.InventoryItem.SKU : null,
                Unit = ws.InventoryItem != null ? ws.InventoryItem.Unit.ToString() : null,
                ws.CurrentQuantity,
                ws.ReservedQuantity,
                AvailableQuantity = ws.CurrentQuantity - ws.ReservedQuantity,
                ws.AverageCost,
                TotalValue = ws.CurrentQuantity * ws.AverageCost,
                ws.LastStockInDate,
                ws.LastStockOutDate,
                ws.CompanyId
            }).OrderBy(ws => ws.ItemName).ToListAsync();

            return Ok(new { success = true, data = stock, total = stock.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب أرصدة المخزون");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// جلب مخزون مستودع محدد
    /// </summary>
    [HttpGet("stock/{warehouseId}")]
    public async Task<IActionResult> GetWarehouseStock(Guid warehouseId)
    {
        try
        {
            var stock = await _unitOfWork.WarehouseStocks.AsQueryable()
                .Where(ws => ws.WarehouseId == warehouseId && !ws.IsDeleted)
                .Select(ws => new
                {
                    ws.Id,
                    ws.WarehouseId,
                    WarehouseName = ws.Warehouse != null ? ws.Warehouse.Name : null,
                    ws.InventoryItemId,
                    ItemName = ws.InventoryItem != null ? ws.InventoryItem.Name : null,
                    ItemSKU = ws.InventoryItem != null ? ws.InventoryItem.SKU : null,
                    Unit = ws.InventoryItem != null ? ws.InventoryItem.Unit.ToString() : null,
                    ws.CurrentQuantity,
                    ws.ReservedQuantity,
                    AvailableQuantity = ws.CurrentQuantity - ws.ReservedQuantity,
                    ws.AverageCost,
                    TotalValue = ws.CurrentQuantity * ws.AverageCost,
                    ws.LastStockInDate,
                    ws.LastStockOutDate,
                    ws.CompanyId
                }).OrderBy(ws => ws.ItemName).ToListAsync();

            return Ok(new { success = true, data = stock, total = stock.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب مخزون المستودع");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تعديل جرد يدوي
    /// </summary>
    [HttpPost("stock/adjust")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> AdjustStock([FromBody] AdjustStockRequest request)
    {
        try
        {
            var currentUserId = GetCurrentUserId();

            var stock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                ws => ws.WarehouseId == request.WarehouseId
                   && ws.InventoryItemId == request.InventoryItemId
                   && !ws.IsDeleted);

            int oldQuantity = 0;

            if (stock == null)
            {
                stock = new WarehouseStock
                {
                    WarehouseId = request.WarehouseId,
                    InventoryItemId = request.InventoryItemId,
                    CurrentQuantity = request.NewQuantity,
                    ReservedQuantity = 0,
                    AverageCost = 0,
                    CompanyId = request.CompanyId
                };
                await _unitOfWork.WarehouseStocks.AddAsync(stock);
            }
            else
            {
                oldQuantity = stock.CurrentQuantity;
                stock.CurrentQuantity = request.NewQuantity;
                stock.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.WarehouseStocks.Update(stock);
            }

            var movement = new StockMovement
            {
                InventoryItemId = request.InventoryItemId,
                WarehouseId = request.WarehouseId,
                MovementType = StockMovementType.Adjustment,
                Quantity = Math.Abs(request.NewQuantity - oldQuantity),
                StockBefore = oldQuantity,
                StockAfter = request.NewQuantity,
                Description = $"تعديل جرد: {request.Reason}",
                CreatedById = currentUserId,
                CompanyId = request.CompanyId
            };
            await _unitOfWork.StockMovements.AddAsync(movement);

            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تعديل الجرد بنجاح", data = new { oldQuantity, newQuantity = request.NewQuantity } });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل الجرد");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تحويل مواد بين مستودعات
    /// </summary>
    [HttpPost("stock/transfer")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> TransferStock([FromBody] TransferStockRequest request)
    {
        try
        {
            if (request.FromWarehouseId == request.ToWarehouseId)
                return BadRequest(new { success = false, message = "لا يمكن التحويل من وإلى نفس المستودع" });

            await _unitOfWork.BeginTransactionAsync();
            try
            {
                var currentUserId = GetCurrentUserId();

                foreach (var transferItem in request.Items)
                {
                    // التحقق من المخزون المصدر
                    var sourceStock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                        ws => ws.WarehouseId == request.FromWarehouseId
                           && ws.InventoryItemId == transferItem.InventoryItemId
                           && !ws.IsDeleted);

                    if (sourceStock == null || sourceStock.CurrentQuantity < transferItem.Quantity)
                    {
                        await _unitOfWork.RollbackTransactionAsync();
                        var itemName = (await _unitOfWork.InventoryItems.GetByIdAsync(transferItem.InventoryItemId))?.Name ?? "مادة غير معروفة";
                        return BadRequest(new { success = false, message = $"المخزون غير كافٍ للمادة: {itemName}" });
                    }

                    // خصم من المصدر
                    var sourceStockBefore = sourceStock.CurrentQuantity;
                    sourceStock.CurrentQuantity -= transferItem.Quantity;
                    sourceStock.LastStockOutDate = DateTime.UtcNow;
                    sourceStock.UpdatedAt = DateTime.UtcNow;
                    _unitOfWork.WarehouseStocks.Update(sourceStock);

                    var transferOutMovement = new StockMovement
                    {
                        InventoryItemId = transferItem.InventoryItemId,
                        WarehouseId = request.FromWarehouseId,
                        MovementType = StockMovementType.TransferOut,
                        Quantity = transferItem.Quantity,
                        StockBefore = sourceStockBefore,
                        StockAfter = sourceStock.CurrentQuantity,
                        UnitCost = sourceStock.AverageCost,
                        ReferenceType = "Transfer",
                        ReferenceId = request.ToWarehouseId.ToString(),
                        Description = $"تحويل صادر إلى مستودع آخر",
                        CreatedById = currentUserId,
                        CompanyId = sourceStock.CompanyId
                    };
                    await _unitOfWork.StockMovements.AddAsync(transferOutMovement);

                    // إضافة للوجهة
                    var destStock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                        ws => ws.WarehouseId == request.ToWarehouseId
                           && ws.InventoryItemId == transferItem.InventoryItemId
                           && !ws.IsDeleted);

                    if (destStock == null)
                    {
                        destStock = new WarehouseStock
                        {
                            WarehouseId = request.ToWarehouseId,
                            InventoryItemId = transferItem.InventoryItemId,
                            CurrentQuantity = 0,
                            ReservedQuantity = 0,
                            AverageCost = sourceStock.AverageCost,
                            CompanyId = sourceStock.CompanyId
                        };
                        await _unitOfWork.WarehouseStocks.AddAsync(destStock);
                    }

                    var destStockBefore = destStock.CurrentQuantity;
                    destStock.CurrentQuantity += transferItem.Quantity;
                    destStock.LastStockInDate = DateTime.UtcNow;
                    destStock.UpdatedAt = DateTime.UtcNow;
                    _unitOfWork.WarehouseStocks.Update(destStock);

                    var transferInMovement = new StockMovement
                    {
                        InventoryItemId = transferItem.InventoryItemId,
                        WarehouseId = request.ToWarehouseId,
                        MovementType = StockMovementType.TransferIn,
                        Quantity = transferItem.Quantity,
                        StockBefore = destStockBefore,
                        StockAfter = destStock.CurrentQuantity,
                        UnitCost = sourceStock.AverageCost,
                        ReferenceType = "Transfer",
                        ReferenceId = request.FromWarehouseId.ToString(),
                        Description = $"تحويل وارد من مستودع آخر",
                        CreatedById = currentUserId,
                        CompanyId = sourceStock.CompanyId
                    };
                    await _unitOfWork.StockMovements.AddAsync(transferInMovement);
                }

                await _unitOfWork.SaveChangesAsync();
                await _unitOfWork.CommitTransactionAsync();

                return Ok(new { success = true, message = "تم التحويل بنجاح" });
            }
            catch
            {
                await _unitOfWork.RollbackTransactionAsync();
                throw;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تحويل المخزون");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// جلب سجل الحركات المخزنية
    /// </summary>
    [HttpGet("movements")]
    public async Task<IActionResult> GetStockMovements(
        [FromQuery] Guid? companyId = null,
        [FromQuery] Guid? inventoryItemId = null,
        [FromQuery] Guid? warehouseId = null,
        [FromQuery] StockMovementType? movementType = null,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        try
        {
            var query = _unitOfWork.StockMovements.AsQueryable().Where(sm => !sm.IsDeleted);

            if (companyId.HasValue)
                query = query.Where(sm => sm.CompanyId == companyId);
            if (inventoryItemId.HasValue)
                query = query.Where(sm => sm.InventoryItemId == inventoryItemId);
            if (warehouseId.HasValue)
                query = query.Where(sm => sm.WarehouseId == warehouseId);
            if (movementType.HasValue)
                query = query.Where(sm => sm.MovementType == movementType);
            if (from.HasValue)
                query = query.Where(sm => sm.CreatedAt >= DateTime.SpecifyKind(from.Value.AddHours(-3), DateTimeKind.Utc));
            if (to.HasValue)
                query = query.Where(sm => sm.CreatedAt <= DateTime.SpecifyKind(to.Value.AddHours(-3), DateTimeKind.Utc));

            var total = await query.CountAsync();
            var movements = await query
                .OrderByDescending(sm => sm.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(sm => new
                {
                    sm.Id,
                    sm.InventoryItemId,
                    ItemName = sm.InventoryItem != null ? sm.InventoryItem.Name : null,
                    ItemSKU = sm.InventoryItem != null ? sm.InventoryItem.SKU : null,
                    sm.WarehouseId,
                    WarehouseName = sm.Warehouse != null ? sm.Warehouse.Name : null,
                    MovementType = sm.MovementType.ToString(),
                    sm.Quantity,
                    sm.StockBefore,
                    sm.StockAfter,
                    sm.UnitCost,
                    sm.ReferenceType,
                    sm.ReferenceId,
                    sm.ReferenceNumber,
                    sm.Description,
                    sm.CreatedById,
                    CreatedByName = sm.CreatedBy != null ? sm.CreatedBy.FullName : null,
                    sm.CompanyId,
                    sm.CreatedAt
                }).ToListAsync();

            return Ok(new { success = true, data = movements, total, page, pageSize });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب الحركات المخزنية");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ==================== التقارير - Reports ====================

    /// <summary>
    /// ملخص لوحة المعلومات
    /// </summary>
    [HttpGet("reports/summary")]
    public async Task<IActionResult> GetReportSummary([FromQuery] Guid companyId)
    {
        try
        {
            var totalItems = await _unitOfWork.InventoryItems.CountAsync(
                i => i.CompanyId == companyId && !i.IsDeleted && i.IsActive);

            var stockData = await _unitOfWork.WarehouseStocks.AsQueryable()
                .Where(ws => ws.CompanyId == companyId && !ws.IsDeleted)
                .GroupBy(ws => 1)
                .Select(g => new
                {
                    TotalValue = g.Sum(ws => ws.CurrentQuantity * ws.AverageCost)
                }).FirstOrDefaultAsync();

            var totalValue = stockData?.TotalValue ?? 0;

            // عدد المواد منخفضة المخزون
            var lowStockCount = await _unitOfWork.InventoryItems.AsQueryable()
                .Where(i => i.CompanyId == companyId && !i.IsDeleted && i.IsActive)
                .Where(i => i.Stocks.Where(s => !s.IsDeleted).Sum(s => s.CurrentQuantity) < i.MinStockLevel)
                .CountAsync();

            var today = DateTime.UtcNow.AddHours(3).Date;
            var todayMovementsCount = await _unitOfWork.StockMovements.CountAsync(
                sm => sm.CompanyId == companyId && !sm.IsDeleted && sm.CreatedAt >= today);

            var recentMovements = await _unitOfWork.StockMovements.AsQueryable()
                .Where(sm => sm.CompanyId == companyId && !sm.IsDeleted)
                .OrderByDescending(sm => sm.CreatedAt)
                .Take(10)
                .Select(sm => new
                {
                    sm.Id,
                    ItemName = sm.InventoryItem != null ? sm.InventoryItem.Name : null,
                    WarehouseName = sm.Warehouse != null ? sm.Warehouse.Name : null,
                    MovementType = sm.MovementType.ToString(),
                    sm.Quantity,
                    sm.StockBefore,
                    sm.StockAfter,
                    sm.Description,
                    sm.CreatedAt
                }).ToListAsync();

            return Ok(new
            {
                success = true,
                data = new
                {
                    totalItems,
                    totalValue,
                    lowStockCount,
                    todayMovementsCount,
                    recentMovements
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب ملخص التقارير");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تقرير تقييم المخزون
    /// </summary>
    [HttpGet("reports/valuation")]
    public async Task<IActionResult> GetInventoryValuation([FromQuery] Guid companyId)
    {
        try
        {
            var valuation = await _unitOfWork.InventoryItems.AsQueryable()
                .Where(i => i.CompanyId == companyId && !i.IsDeleted && i.IsActive)
                .Select(i => new
                {
                    i.Id,
                    i.Name,
                    i.NameEn,
                    i.SKU,
                    CategoryName = i.Category != null ? i.Category.Name : null,
                    Unit = i.Unit.ToString(),
                    TotalQuantity = i.Stocks.Where(s => !s.IsDeleted).Sum(s => s.CurrentQuantity),
                    AverageCost = i.Stocks.Where(s => !s.IsDeleted && s.CurrentQuantity > 0)
                        .Select(s => s.AverageCost).FirstOrDefault(),
                    TotalValue = i.Stocks.Where(s => !s.IsDeleted).Sum(s => s.CurrentQuantity * s.AverageCost)
                })
                .OrderBy(i => i.Name)
                .ToListAsync();

            var grandTotal = valuation.Sum(v => v.TotalValue);

            return Ok(new { success = true, data = valuation, total = valuation.Count, grandTotal });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب تقرير التقييم");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تقرير المواد بحوزة الفنيين
    /// </summary>
    [HttpGet("reports/technician-holdings")]
    public async Task<IActionResult> GetTechnicianHoldingsReport([FromQuery] Guid companyId)
    {
        try
        {
            var holdings = await _unitOfWork.TechnicianDispensingItems.AsQueryable()
                .Where(tdi => tdi.TechnicianDispensing != null
                    && tdi.TechnicianDispensing.CompanyId == companyId
                    && tdi.TechnicianDispensing.Status == DispensingStatus.Approved
                    && tdi.TechnicianDispensing.Type == DispensingType.Dispensing
                    && !tdi.TechnicianDispensing.IsDeleted
                    && tdi.Quantity > tdi.ReturnedQuantity)
                .Select(tdi => new
                {
                    TechnicianId = tdi.TechnicianDispensing!.TechnicianId,
                    TechnicianName = tdi.TechnicianDispensing.Technician != null ? tdi.TechnicianDispensing.Technician.FullName : null,
                    tdi.InventoryItemId,
                    ItemName = tdi.InventoryItem != null ? tdi.InventoryItem.Name : null,
                    ItemSKU = tdi.InventoryItem != null ? tdi.InventoryItem.SKU : null,
                    tdi.Quantity,
                    tdi.ReturnedQuantity,
                    RemainingQuantity = tdi.Quantity - tdi.ReturnedQuantity,
                    VoucherNumber = tdi.TechnicianDispensing.VoucherNumber,
                    DispensingDate = tdi.TechnicianDispensing.DispensingDate
                }).ToListAsync();

            // تجميع حسب الفني
            var grouped = holdings
                .GroupBy(h => new { h.TechnicianId, h.TechnicianName })
                .Select(g => new
                {
                    g.Key.TechnicianId,
                    g.Key.TechnicianName,
                    TotalItems = g.Sum(x => x.RemainingQuantity),
                    Items = g.Select(x => new
                    {
                        x.InventoryItemId,
                        x.ItemName,
                        x.ItemSKU,
                        x.Quantity,
                        x.ReturnedQuantity,
                        x.RemainingQuantity,
                        x.VoucherNumber,
                        x.DispensingDate
                    }).ToList()
                })
                .OrderBy(g => g.TechnicianName)
                .ToList();

            return Ok(new { success = true, data = grouped, total = grouped.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب تقرير حيازات الفنيين");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }
}

// ==================== Request DTOs (inline في نفس الملف) ====================

public class CreateWarehouseRequest
{
    public string Name { get; set; } = string.Empty;
    public string? Code { get; set; }
    public string? Address { get; set; }
    public string? Description { get; set; }
    public bool IsDefault { get; set; }
    public Guid? ManagerUserId { get; set; }
    public Guid CompanyId { get; set; }
}

public class UpdateWarehouseRequest
{
    public string? Name { get; set; }
    public string? Code { get; set; }
    public string? Address { get; set; }
    public string? Description { get; set; }
    public bool? IsDefault { get; set; }
    public bool? IsActive { get; set; }
    public Guid? ManagerUserId { get; set; }
}

public class CreateInventoryCategoryRequest
{
    public string Name { get; set; } = string.Empty;
    public string? NameEn { get; set; }
    public int? ParentCategoryId { get; set; }
    public int SortOrder { get; set; }
    public Guid CompanyId { get; set; }
}

public class UpdateInventoryCategoryRequest
{
    public string? Name { get; set; }
    public string? NameEn { get; set; }
    public int? ParentCategoryId { get; set; }
    public int? SortOrder { get; set; }
    public bool? IsActive { get; set; }
}

public class CreateItemRequest
{
    public string Name { get; set; } = string.Empty;
    public string? NameEn { get; set; }
    public string SKU { get; set; } = string.Empty;
    public string? Barcode { get; set; }
    public string? Description { get; set; }
    public int? CategoryId { get; set; }
    public InventoryUnitType Unit { get; set; } = InventoryUnitType.Piece;
    public decimal CostPrice { get; set; }
    public decimal? SellingPrice { get; set; }
    public decimal? WholesalePrice { get; set; }
    public int MinStockLevel { get; set; }
    public int MaxStockLevel { get; set; }
    public string? ImageUrl { get; set; }
    public Guid CompanyId { get; set; }
}

public class UpdateItemRequest
{
    public string? Name { get; set; }
    public string? NameEn { get; set; }
    public string? SKU { get; set; }
    public string? Barcode { get; set; }
    public string? Description { get; set; }
    public int? CategoryId { get; set; }
    public InventoryUnitType? Unit { get; set; }
    public decimal? CostPrice { get; set; }
    public decimal? SellingPrice { get; set; }
    public decimal? WholesalePrice { get; set; }
    public int? MinStockLevel { get; set; }
    public int? MaxStockLevel { get; set; }
    public string? ImageUrl { get; set; }
    public bool? IsActive { get; set; }
}

public class CreateSupplierRequest
{
    public string Name { get; set; } = string.Empty;
    public string? ContactPerson { get; set; }
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public string? Address { get; set; }
    public string? TaxNumber { get; set; }
    public string? Notes { get; set; }
    public Guid CompanyId { get; set; }
}

public class UpdateSupplierRequest
{
    public string? Name { get; set; }
    public string? ContactPerson { get; set; }
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public string? Address { get; set; }
    public string? TaxNumber { get; set; }
    public string? Notes { get; set; }
    public bool? IsActive { get; set; }
}

public class CreatePurchaseOrderRequest
{
    public Guid SupplierId { get; set; }
    public Guid WarehouseId { get; set; }
    public DateTime? ExpectedDeliveryDate { get; set; }
    public string? Notes { get; set; }
    public decimal? DiscountAmount { get; set; }
    public decimal? TaxAmount { get; set; }
    public Guid CompanyId { get; set; }
    public List<PurchaseOrderItemDto> Items { get; set; } = new();
}

public class PurchaseOrderItemDto
{
    public Guid InventoryItemId { get; set; }
    public int Quantity { get; set; }
    public decimal UnitPrice { get; set; }
}

public class UpdatePurchaseOrderRequest
{
    public Guid? SupplierId { get; set; }
    public Guid? WarehouseId { get; set; }
    public DateTime? ExpectedDeliveryDate { get; set; }
    public string? Notes { get; set; }
    public List<PurchaseOrderItemDto>? Items { get; set; }
}

public class ReceivePurchaseOrderRequest
{
    public List<ReceiveItemDto> Items { get; set; } = new();
}

public class ReceiveItemDto
{
    public long PurchaseOrderItemId { get; set; }
    public int ReceivedQuantity { get; set; }
}

public class CreateSalesOrderRequest
{
    public string? CustomerName { get; set; }
    public string? CustomerPhone { get; set; }
    public Guid WarehouseId { get; set; }
    public PaymentMethod PaymentMethod { get; set; } = PaymentMethod.CashOnDelivery;
    public string? Notes { get; set; }
    public Guid CompanyId { get; set; }
    public List<SalesOrderItemDto> Items { get; set; } = new();
}

public class SalesOrderItemDto
{
    public Guid InventoryItemId { get; set; }
    public int Quantity { get; set; }
    public decimal UnitPrice { get; set; }
}

public class CreateDispensingRequest
{
    public Guid TechnicianId { get; set; }
    public Guid WarehouseId { get; set; }
    public Guid? ServiceRequestId { get; set; }
    public DispensingType Type { get; set; } = DispensingType.Dispensing;
    public string? Notes { get; set; }
    public Guid CompanyId { get; set; }
    public List<DispensingItemDto> Items { get; set; } = new();
}

public class DispensingItemDto
{
    public Guid InventoryItemId { get; set; }
    public int Quantity { get; set; }
}

public class ReturnDispensingRequest
{
    public List<ReturnItemDto> Items { get; set; } = new();
}

public class ReturnItemDto
{
    public long TechnicianDispensingItemId { get; set; }
    public int ReturnQuantity { get; set; }
}

public class AdjustStockRequest
{
    public Guid WarehouseId { get; set; }
    public Guid InventoryItemId { get; set; }
    public int NewQuantity { get; set; }
    public string Reason { get; set; } = string.Empty;
    public Guid CompanyId { get; set; }
}

public class TransferStockRequest
{
    public Guid FromWarehouseId { get; set; }
    public Guid ToWarehouseId { get; set; }
    public List<TransferItemDto> Items { get; set; } = new();
}

public class TransferItemDto
{
    public Guid InventoryItemId { get; set; }
    public int Quantity { get; set; }
}

public class UseFromHoldingsRequest
{
    public Guid TechnicianId { get; set; }
    public Guid? ServiceRequestId { get; set; }
    public Guid CompanyId { get; set; }
    public List<UseFromHoldingsItemDto> Items { get; set; } = new();
}

public class UseFromHoldingsItemDto
{
    public Guid InventoryItemId { get; set; }
    public int Quantity { get; set; }
}
