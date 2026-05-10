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

        // IgnoreQueryFilters لتجنب تكرار الرقم عند وجود سجلات محذوفة (soft-delete)
        int count = 0;
        if (prefix == "PO")
        {
            count = await _unitOfWork.PurchaseOrders.AsQueryable()
                .IgnoreQueryFilters()
                .CountAsync(po => po.CompanyId == companyId && po.OrderNumber.StartsWith(pattern));
        }
        else if (prefix == "SO")
        {
            count = await _unitOfWork.SalesOrders.AsQueryable()
                .IgnoreQueryFilters()
                .CountAsync(so => so.CompanyId == companyId && so.OrderNumber.StartsWith(pattern));
        }
        else if (prefix == "TD")
        {
            count = await _unitOfWork.TechnicianDispensings.AsQueryable()
                .IgnoreQueryFilters()
                .CountAsync(td => td.CompanyId == companyId && td.VoucherNumber.StartsWith(pattern));
        }
        else if (prefix == "INV" || prefix == "PINV")
        {
            count = await _unitOfWork.Invoices.AsQueryable()
                .IgnoreQueryFilters()
                .CountAsync(i => i.CompanyId == companyId && i.InvoiceNumber.StartsWith(pattern));
        }
        else if (prefix == "RV" || prefix == "PV")
        {
            count = await _unitOfWork.PaymentVouchers.AsQueryable()
                .IgnoreQueryFilters()
                .CountAsync(v => v.CompanyId == companyId && v.VoucherNumber.StartsWith(pattern));
        }
        else if (prefix == "SR" || prefix == "PR")
        {
            count = await _unitOfWork.ReturnOrders.AsQueryable()
                .IgnoreQueryFilters()
                .CountAsync(r => r.CompanyId == companyId && r.ReturnNumber.StartsWith(pattern));
        }
        else if (prefix == "CU")
        {
            count = await _unitOfWork.InventoryCustomers.AsQueryable()
                .IgnoreQueryFilters()
                .CountAsync(c => c.CompanyId == companyId && c.CustomerCode.StartsWith(pattern));
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

            if (order.Status == PurchaseOrderStatus.Cancelled)
                return BadRequest(new { success = false, message = "أمر الشراء ملغي مسبقاً" });

            if (order.Status == PurchaseOrderStatus.Received)
                return BadRequest(new { success = false, message = "لا يمكن إلغاء أمر شراء مستلم بالكامل — استخدم مرتجع مشتريات" });

            // Draft / Approved: إلغاء بسيط بدون عكس مخزون
            if (order.Status == PurchaseOrderStatus.Draft || order.Status == PurchaseOrderStatus.Approved)
            {
                order.Status = PurchaseOrderStatus.Cancelled;
                order.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.PurchaseOrders.Update(order);
                await _unitOfWork.SaveChangesAsync();
                return Ok(new { success = true, message = "تم إلغاء أمر الشراء بنجاح" });
            }

            // PartiallyReceived: إلغاء مع عكس المخزون المستلم
            await _unitOfWork.BeginTransactionAsync();
            try
            {
                var currentUserId = GetCurrentUserId();
                var orderItems = (await _unitOfWork.PurchaseOrderItems.FindAsync(
                    poi => poi.PurchaseOrderId == id)).ToList();

                foreach (var poItem in orderItems)
                {
                    if (poItem.ReceivedQuantity <= 0) continue;

                    var stock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                        ws => ws.WarehouseId == order.WarehouseId
                           && ws.InventoryItemId == poItem.InventoryItemId
                           && !ws.IsDeleted);

                    if (stock != null)
                    {
                        var stockBefore = stock.CurrentQuantity;
                        stock.CurrentQuantity -= poItem.ReceivedQuantity;
                        if (stock.CurrentQuantity < 0) stock.CurrentQuantity = 0;
                        stock.UpdatedAt = DateTime.UtcNow;
                        _unitOfWork.WarehouseStocks.Update(stock);

                        await _unitOfWork.StockMovements.AddAsync(new StockMovement
                        {
                            InventoryItemId = poItem.InventoryItemId,
                            WarehouseId = order.WarehouseId,
                            MovementType = StockMovementType.PurchaseReturn,
                            Quantity = poItem.ReceivedQuantity,
                            StockBefore = stockBefore,
                            StockAfter = stock.CurrentQuantity,
                            UnitCost = stock.AverageCost,
                            ReferenceType = "PurchaseOrder",
                            ReferenceId = order.Id.ToString(),
                            ReferenceNumber = order.OrderNumber,
                            Description = $"إلغاء أمر شراء - إرجاع مستلم - {order.OrderNumber}",
                            CreatedById = currentUserId,
                            CompanyId = order.CompanyId
                        });
                    }
                }

                order.Status = PurchaseOrderStatus.Cancelled;
                order.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.PurchaseOrders.Update(order);

                await _unitOfWork.SaveChangesAsync();
                await _unitOfWork.CommitTransactionAsync();

                return Ok(new { success = true, message = "تم إلغاء أمر الشراء وإرجاع المخزون المستلم" });
            }
            catch
            {
                await _unitOfWork.RollbackTransactionAsync();
                throw;
            }
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
    /// تعديل أمر بيع (Draft فقط)
    /// </summary>
    [HttpPut("sales/{id}")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> UpdateSalesOrder(Guid id, [FromBody] CreateSalesOrderRequest request)
    {
        try
        {
            var order = await _unitOfWork.SalesOrders.GetByIdAsync(id);
            if (order == null || order.IsDeleted)
                return NotFound(new { success = false, message = "أمر البيع غير موجود" });

            if (order.Status != SalesOrderStatus.Draft)
                return BadRequest(new { success = false, message = "لا يمكن تعديل أمر بيع مؤكد أو ملغي" });

            // حذف البنود القديمة
            var oldItems = (await _unitOfWork.SalesOrderItems.FindAsync(
                soi => soi.SalesOrderId == id)).ToList();
            foreach (var old in oldItems)
                _unitOfWork.SalesOrderItems.Delete(old);

            // إضافة البنود الجديدة
            decimal totalAmount = 0;
            foreach (var itemDto in request.Items)
            {
                var lineTotal = itemDto.Quantity * itemDto.UnitPrice;
                totalAmount += lineTotal;

                await _unitOfWork.SalesOrderItems.AddAsync(new SalesOrderItem
                {
                    SalesOrderId = order.Id,
                    InventoryItemId = itemDto.InventoryItemId,
                    Quantity = itemDto.Quantity,
                    UnitPrice = itemDto.UnitPrice,
                    TotalPrice = lineTotal
                });
            }

            order.CustomerName = request.CustomerName ?? order.CustomerName;
            order.CustomerPhone = request.CustomerPhone ?? order.CustomerPhone;
            order.WarehouseId = request.WarehouseId;
            order.PaymentMethod = request.PaymentMethod;
            order.Notes = request.Notes ?? order.Notes;
            order.TotalAmount = totalAmount;
            order.NetAmount = totalAmount;
            order.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.SalesOrders.Update(order);

            await _unitOfWork.SaveChangesAsync();
            return Ok(new { success = true, message = "تم تعديل أمر البيع بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل أمر البيع");
            return StatusCode(500, new { success = false, message = $"خطأ: {ex.Message}" });
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
                                MovementType = StockMovementType.SalesReturn,
                                Quantity = soItem.Quantity,
                                StockBefore = stockBefore,
                                StockAfter = stock.CurrentQuantity,
                                UnitCost = stock.AverageCost,
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
                    TechnicianName = td.Technician!.FullName,
                    td.WarehouseId,
                    WarehouseName = td.Warehouse!.Name,
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
            return StatusCode(500, new { success = false, message = $"خطأ في إنشاء عملية الصرف: {ex.Message}" });
        }
    }

    /// <summary>
    /// حذف سند صرف (soft delete) مع إرجاع المخزون
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

            await _unitOfWork.BeginTransactionAsync();
            try
            {
                var currentUserId = GetCurrentUserId();
                var dispensingItems = await _unitOfWork.TechnicianDispensingItems.FindAsync(
                    tdi => tdi.TechnicianDispensingId == id);

                // ── إرجاع الكميات إلى المخزون (عكس عملية الصرف) ──
                if (dispensing.Status == DispensingStatus.Approved || dispensing.Status == DispensingStatus.PartialReturn)
                {
                    foreach (var tdItem in dispensingItems)
                    {
                        // الكمية الفعلية المصروفة التي لم تُرجع بعد
                        var netDispensed = tdItem.Quantity - tdItem.ReturnedQuantity;
                        if (netDispensed <= 0) continue;

                        var stock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                            ws => ws.WarehouseId == dispensing.WarehouseId
                               && ws.InventoryItemId == tdItem.InventoryItemId
                               && !ws.IsDeleted);

                        if (stock != null)
                        {
                            var stockBefore = stock.CurrentQuantity;
                            stock.CurrentQuantity += netDispensed;
                            stock.LastStockInDate = DateTime.UtcNow;
                            stock.UpdatedAt = DateTime.UtcNow;
                            _unitOfWork.WarehouseStocks.Update(stock);

                            // حركة مخزنية عكسية
                            await _unitOfWork.StockMovements.AddAsync(new StockMovement
                            {
                                InventoryItemId = tdItem.InventoryItemId,
                                WarehouseId = dispensing.WarehouseId,
                                MovementType = StockMovementType.TechnicianReturn,
                                Quantity = netDispensed,
                                StockBefore = stockBefore,
                                StockAfter = stock.CurrentQuantity,
                                UnitCost = stock.AverageCost,
                                ReferenceType = "TechnicianDispensing",
                                ReferenceId = dispensing.Id.ToString(),
                                ReferenceNumber = dispensing.VoucherNumber,
                                Description = $"حذف سند صرف - إرجاع تلقائي - {dispensing.VoucherNumber}",
                                CreatedById = currentUserId,
                                CompanyId = dispensing.CompanyId
                            });
                        }
                    }
                }

                dispensing.IsDeleted = true;
                dispensing.DeletedAt = DateTime.UtcNow;
                dispensing.Status = DispensingStatus.Cancelled;
                _unitOfWork.TechnicianDispensings.Update(dispensing);

                await _unitOfWork.SaveChangesAsync();
                await _unitOfWork.CommitTransactionAsync();

                return Ok(new { success = true, message = "تم حذف سند الصرف وإرجاع المواد للمخزون" });
            }
            catch
            {
                await _unitOfWork.RollbackTransactionAsync();
                throw;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف سند صرف");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// تعديل سند صرف — تحديث الفني أو المواد أو الكميات
    /// </summary>
    [HttpPut("dispensing/{id}")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> UpdateDispensing(Guid id, [FromBody] UpdateDispensingRequest request)
    {
        try
        {
            var dispensing = await _unitOfWork.TechnicianDispensings.GetByIdAsync(id);
            if (dispensing == null || dispensing.IsDeleted)
                return NotFound(new { success = false, message = "سند الصرف غير موجود" });

            await _unitOfWork.BeginTransactionAsync();
            try
            {
                var currentUserId = GetCurrentUserId();
                var oldItems = (await _unitOfWork.TechnicianDispensingItems.FindAsync(
                    tdi => tdi.TechnicianDispensingId == id)).ToList();

                // ── 1. عكس جميع الكميات القديمة (إرجاع للمخزون) ──
                if (dispensing.Status == DispensingStatus.Approved || dispensing.Status == DispensingStatus.PartialReturn)
                {
                    foreach (var oldItem in oldItems)
                    {
                        var netDispensed = oldItem.Quantity - oldItem.ReturnedQuantity;
                        if (netDispensed > 0)
                        {
                            var stock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                                ws => ws.WarehouseId == dispensing.WarehouseId
                                   && ws.InventoryItemId == oldItem.InventoryItemId
                                   && !ws.IsDeleted);

                            if (stock != null)
                            {
                                var stockBefore = stock.CurrentQuantity;
                                stock.CurrentQuantity += netDispensed;
                                stock.UpdatedAt = DateTime.UtcNow;
                                _unitOfWork.WarehouseStocks.Update(stock);

                                await _unitOfWork.StockMovements.AddAsync(new StockMovement
                                {
                                    InventoryItemId = oldItem.InventoryItemId,
                                    WarehouseId = dispensing.WarehouseId,
                                    MovementType = StockMovementType.TechnicianReturn,
                                    Quantity = netDispensed,
                                    StockBefore = stockBefore,
                                    StockAfter = stock.CurrentQuantity,
                                    UnitCost = stock.AverageCost,
                                    ReferenceType = "TechnicianDispensing",
                                    ReferenceId = dispensing.Id.ToString(),
                                    ReferenceNumber = dispensing.VoucherNumber,
                                    Description = $"تعديل سند صرف - إرجاع تلقائي - {dispensing.VoucherNumber}",
                                    CreatedById = currentUserId,
                                    CompanyId = dispensing.CompanyId
                                });
                            }
                        }
                        // حذف بند الصرف القديم (في كل الحالات)
                        _unitOfWork.TechnicianDispensingItems.Delete(oldItem);
                    }
                }
                else
                {
                    // لم يُصرف بعد — نحذف البنود فقط بدون عكس مخزني
                    foreach (var oldItem in oldItems)
                    {
                        _unitOfWork.TechnicianDispensingItems.Delete(oldItem);
                    }
                }

                // ── 2. تحديث بيانات السند ──
                var targetWarehouseId = request.WarehouseId ?? dispensing.WarehouseId;
                dispensing.TechnicianId = request.TechnicianId ?? dispensing.TechnicianId;
                dispensing.WarehouseId = targetWarehouseId;
                dispensing.Notes = request.Notes ?? dispensing.Notes;
                dispensing.UpdatedAt = DateTime.UtcNow;

                // ── 3. إضافة البنود الجديدة وخصم من المخزون ──
                foreach (var itemDto in request.Items)
                {
                    var newItem = new TechnicianDispensingItem
                    {
                        TechnicianDispensingId = dispensing.Id,
                        InventoryItemId = itemDto.InventoryItemId,
                        Quantity = itemDto.Quantity,
                        ReturnedQuantity = 0
                    };
                    await _unitOfWork.TechnicianDispensingItems.AddAsync(newItem);

                    // خصم من المخزون
                    var stock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                        s => s.WarehouseId == targetWarehouseId && s.InventoryItemId == itemDto.InventoryItemId && !s.IsDeleted);

                    if (stock == null || stock.CurrentQuantity < itemDto.Quantity)
                    {
                        await _unitOfWork.RollbackTransactionAsync();
                        var itemName = (await _unitOfWork.InventoryItems.GetByIdAsync(itemDto.InventoryItemId))?.Name ?? "مادة غير معروفة";
                        return BadRequest(new { success = false, message = $"المخزون غير كافٍ للمادة: {itemName} (المتاح: {stock?.CurrentQuantity ?? 0})" });
                    }

                    var oldQty = stock.CurrentQuantity;
                    stock.CurrentQuantity -= itemDto.Quantity;
                    stock.LastStockOutDate = DateTime.UtcNow;
                    stock.UpdatedAt = DateTime.UtcNow;
                    _unitOfWork.WarehouseStocks.Update(stock);

                    await _unitOfWork.StockMovements.AddAsync(new StockMovement
                    {
                        InventoryItemId = itemDto.InventoryItemId,
                        WarehouseId = targetWarehouseId,
                        MovementType = StockMovementType.TechnicianDispensing,
                        Quantity = itemDto.Quantity,
                        StockBefore = oldQty,
                        StockAfter = stock.CurrentQuantity,
                        UnitCost = stock.AverageCost,
                        ReferenceType = "TechnicianDispensing",
                        ReferenceId = dispensing.Id.ToString(),
                        ReferenceNumber = dispensing.VoucherNumber,
                        Description = $"تعديل سند صرف - {dispensing.VoucherNumber}",
                        CreatedById = currentUserId,
                        CompanyId = dispensing.CompanyId
                    });
                }

                // إعادة ضبط الحالة
                dispensing.Status = DispensingStatus.Approved;
                _unitOfWork.TechnicianDispensings.Update(dispensing);

                await _unitOfWork.SaveChangesAsync();
                await _unitOfWork.CommitTransactionAsync();

                return Ok(new { success = true, message = "تم تعديل سند الصرف بنجاح" });
            }
            catch
            {
                await _unitOfWork.RollbackTransactionAsync();
                throw;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل سند الصرف");
            return StatusCode(500, new { success = false, message = $"خطأ في تعديل سند الصرف: {ex.Message}" });
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
                    UserName = sm.CreatedBy != null ? sm.CreatedBy.FullName : null,
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
                .Include(tdi => tdi.TechnicianDispensing!).ThenInclude(td => td.Technician)
                .Include(tdi => tdi.InventoryItem)
                .Where(tdi => tdi.TechnicianDispensing != null
                    && tdi.TechnicianDispensing.CompanyId == companyId
                    && tdi.TechnicianDispensing.Status == DispensingStatus.Approved
                    && tdi.TechnicianDispensing.Type == DispensingType.Dispensing
                    && !tdi.TechnicianDispensing.IsDeleted
                    && tdi.Quantity > tdi.ReturnedQuantity)
                .Select(tdi => new
                {
                    TechnicianId = tdi.TechnicianDispensing!.TechnicianId,
                    TechnicianName = tdi.TechnicianDispensing.Technician!.FullName,
                    tdi.InventoryItemId,
                    ItemName = tdi.InventoryItem!.Name,
                    ItemSKU = tdi.InventoryItem.SKU,
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

    // ══════════════════════════════════════════════════════════════════
    //  التقارير المتقدمة — Advanced Reports
    // ══════════════════════════════════════════════════════════════════

    /// <summary>أرباح وخسائر المبيعات</summary>
    [HttpGet("reports/profit-loss")]
    public async Task<IActionResult> GetProfitLossReport([FromQuery] Guid companyId,
        [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null)
    {
        try
        {
            var query = _unitOfWork.InvoiceItems.AsQueryable()
                .Where(ii => ii.Invoice != null && ii.Invoice.CompanyId == companyId
                    && ii.Invoice.InvoiceType == InvoiceType.Sales
                    && ii.Invoice.Status != InvoiceStatus.Draft && ii.Invoice.Status != InvoiceStatus.Cancelled);

            if (from.HasValue) query = query.Where(ii => ii.Invoice!.InvoiceDate >= from.Value);
            if (to.HasValue) query = query.Where(ii => ii.Invoice!.InvoiceDate <= to.Value.AddDays(1));

            var items = await query.GroupBy(ii => new { ii.InventoryItemId, ii.ItemName })
                .Select(g => new
                {
                    g.Key.InventoryItemId,
                    g.Key.ItemName,
                    QuantitySold = g.Sum(x => x.Quantity),
                    TotalRevenue = g.Sum(x => x.TotalPrice),
                    TotalCost = g.Sum(x => x.CostAtSale * x.Quantity),
                    Profit = g.Sum(x => x.TotalPrice) - g.Sum(x => x.CostAtSale * x.Quantity)
                })
                .OrderByDescending(x => x.Profit)
                .ToListAsync();

            return Ok(new
            {
                success = true,
                data = items,
                summary = new
                {
                    totalRevenue = items.Sum(x => x.TotalRevenue),
                    totalCost = items.Sum(x => x.TotalCost),
                    totalProfit = items.Sum(x => x.Profit)
                }
            });
        }
        catch (Exception ex) { _logger.LogError(ex, "خطأ تقرير الأرباح"); return StatusCode(500, new { success = false, message = "خطأ داخلي" }); }
    }

    /// <summary>أعمار ديون العملاء</summary>
    [HttpGet("reports/customer-aging")]
    public async Task<IActionResult> GetCustomerAgingReport([FromQuery] Guid companyId)
    {
        try
        {
            var now = DateTime.UtcNow;
            var invoices = await _unitOfWork.Invoices.AsQueryable()
                .Where(i => i.CompanyId == companyId && i.InvoiceType == InvoiceType.Sales
                    && i.RemainingAmount > 0 && i.Status != InvoiceStatus.Cancelled && i.Status != InvoiceStatus.Draft)
                .Select(i => new
                {
                    i.CustomerId,
                    CustomerName = i.Customer != null ? i.Customer.FullName : i.EntityName,
                    i.InvoiceNumber, i.InvoiceDate, i.NetAmount, i.RemainingAmount,
                    DaysOverdue = (now - i.InvoiceDate).Days
                }).ToListAsync();

            var grouped = invoices.GroupBy(i => new { i.CustomerId, i.CustomerName })
                .Select(g => new
                {
                    g.Key.CustomerId, g.Key.CustomerName,
                    TotalDue = g.Sum(x => x.RemainingAmount),
                    Current = g.Where(x => x.DaysOverdue <= 30).Sum(x => x.RemainingAmount),
                    Days31_60 = g.Where(x => x.DaysOverdue > 30 && x.DaysOverdue <= 60).Sum(x => x.RemainingAmount),
                    Days61_90 = g.Where(x => x.DaysOverdue > 60 && x.DaysOverdue <= 90).Sum(x => x.RemainingAmount),
                    Over90 = g.Where(x => x.DaysOverdue > 90).Sum(x => x.RemainingAmount),
                    InvoiceCount = g.Count()
                }).OrderByDescending(x => x.TotalDue).ToList();

            return Ok(new { success = true, data = grouped, total = grouped.Count });
        }
        catch (Exception ex) { _logger.LogError(ex, "خطأ تقرير أعمار ديون العملاء"); return StatusCode(500, new { success = false, message = "خطأ داخلي" }); }
    }

    /// <summary>أعمار ديون الموردين</summary>
    [HttpGet("reports/supplier-aging")]
    public async Task<IActionResult> GetSupplierAgingReport([FromQuery] Guid companyId)
    {
        try
        {
            var now = DateTime.UtcNow;
            var invoices = await _unitOfWork.Invoices.AsQueryable()
                .Where(i => i.CompanyId == companyId && i.InvoiceType == InvoiceType.Purchase
                    && i.RemainingAmount > 0 && i.Status != InvoiceStatus.Cancelled && i.Status != InvoiceStatus.Draft)
                .Select(i => new
                {
                    i.SupplierId,
                    SupplierName = i.Supplier != null ? i.Supplier.Name : i.EntityName,
                    i.InvoiceNumber, i.InvoiceDate, i.NetAmount, i.RemainingAmount,
                    DaysOverdue = (now - i.InvoiceDate).Days
                }).ToListAsync();

            var grouped = invoices.GroupBy(i => new { i.SupplierId, i.SupplierName })
                .Select(g => new
                {
                    g.Key.SupplierId, g.Key.SupplierName,
                    TotalDue = g.Sum(x => x.RemainingAmount),
                    Current = g.Where(x => x.DaysOverdue <= 30).Sum(x => x.RemainingAmount),
                    Days31_60 = g.Where(x => x.DaysOverdue > 30 && x.DaysOverdue <= 60).Sum(x => x.RemainingAmount),
                    Days61_90 = g.Where(x => x.DaysOverdue > 60 && x.DaysOverdue <= 90).Sum(x => x.RemainingAmount),
                    Over90 = g.Where(x => x.DaysOverdue > 90).Sum(x => x.RemainingAmount),
                    InvoiceCount = g.Count()
                }).OrderByDescending(x => x.TotalDue).ToList();

            return Ok(new { success = true, data = grouped, total = grouped.Count });
        }
        catch (Exception ex) { _logger.LogError(ex, "خطأ تقرير أعمار ديون الموردين"); return StatusCode(500, new { success = false, message = "خطأ داخلي" }); }
    }

    /// <summary>أكثر المواد مبيعاً</summary>
    [HttpGet("reports/top-selling")]
    public async Task<IActionResult> GetTopSellingReport([FromQuery] Guid companyId,
        [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null, [FromQuery] int top = 20)
    {
        try
        {
            var query = _unitOfWork.InvoiceItems.AsQueryable()
                .Where(ii => ii.Invoice != null && ii.Invoice.CompanyId == companyId
                    && ii.Invoice.InvoiceType == InvoiceType.Sales
                    && ii.Invoice.Status != InvoiceStatus.Draft && ii.Invoice.Status != InvoiceStatus.Cancelled);

            if (from.HasValue) query = query.Where(ii => ii.Invoice!.InvoiceDate >= from.Value);
            if (to.HasValue) query = query.Where(ii => ii.Invoice!.InvoiceDate <= to.Value.AddDays(1));

            var items = await query.GroupBy(ii => new { ii.InventoryItemId, ii.ItemName })
                .Select(g => new
                {
                    g.Key.InventoryItemId, g.Key.ItemName,
                    TotalQuantity = g.Sum(x => x.Quantity),
                    TotalRevenue = g.Sum(x => x.TotalPrice),
                    InvoiceCount = g.Select(x => x.InvoiceId).Distinct().Count()
                })
                .OrderByDescending(x => x.TotalQuantity)
                .Take(top)
                .ToListAsync();

            return Ok(new { success = true, data = items });
        }
        catch (Exception ex) { _logger.LogError(ex, "خطأ تقرير الأكثر مبيعاً"); return StatusCode(500, new { success = false, message = "خطأ داخلي" }); }
    }

    /// <summary>المخزون الراكد (بدون حركة خلال X يوم)</summary>
    [HttpGet("reports/slow-moving")]
    public async Task<IActionResult> GetSlowMovingReport([FromQuery] Guid companyId, [FromQuery] int days = 30)
    {
        try
        {
            var cutoff = DateTime.UtcNow.AddDays(-days);
            var items = await _unitOfWork.InventoryItems.AsQueryable()
                .Where(i => i.CompanyId == companyId && i.IsActive)
                .Where(i => !i.Movements.Any(m => m.CreatedAt >= cutoff))
                .Select(i => new
                {
                    i.Id, i.Name, i.SKU,
                    TotalStock = i.Stocks.Where(s => !s.IsDeleted).Sum(s => s.CurrentQuantity),
                    StockValue = i.Stocks.Where(s => !s.IsDeleted).Sum(s => s.CurrentQuantity * s.AverageCost),
                    LastMovement = i.Movements.OrderByDescending(m => m.CreatedAt).Select(m => (DateTime?)m.CreatedAt).FirstOrDefault()
                })
                .Where(x => x.TotalStock > 0)
                .OrderByDescending(x => x.StockValue)
                .ToListAsync();

            return Ok(new { success = true, data = items, total = items.Count });
        }
        catch (Exception ex) { _logger.LogError(ex, "خطأ تقرير المخزون الراكد"); return StatusCode(500, new { success = false, message = "خطأ داخلي" }); }
    }

    /// <summary>دفتر حركة مادة محددة</summary>
    [HttpGet("reports/item-ledger/{itemId}")]
    public async Task<IActionResult> GetItemLedger(Guid itemId, [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null)
    {
        try
        {
            var item = await _unitOfWork.InventoryItems.GetByIdAsync(itemId);
            if (item == null) return NotFound(new { success = false, message = "المادة غير موجودة" });

            var query = _unitOfWork.StockMovements.AsQueryable().Where(m => m.InventoryItemId == itemId);
            if (from.HasValue) query = query.Where(m => m.CreatedAt >= from.Value);
            if (to.HasValue) query = query.Where(m => m.CreatedAt <= to.Value.AddDays(1));

            var movements = await query.OrderBy(m => m.CreatedAt)
                .Select(m => new
                {
                    m.Id, MovementType = m.MovementType.ToString(), m.Quantity,
                    m.StockBefore, m.StockAfter, m.UnitCost,
                    m.ReferenceNumber, m.Description,
                    WarehouseName = m.Warehouse != null ? m.Warehouse.Name : null,
                    m.CreatedAt
                }).ToListAsync();

            return Ok(new { success = true, data = new { item = new { item.Id, item.Name, item.SKU }, movements }, total = movements.Count });
        }
        catch (Exception ex) { _logger.LogError(ex, "خطأ دفتر حركة المادة"); return StatusCode(500, new { success = false, message = "خطأ داخلي" }); }
    }

    /// <summary>ملخص مبيعات اليوم</summary>
    [HttpGet("reports/daily-sales")]
    public async Task<IActionResult> GetDailySalesReport([FromQuery] Guid companyId)
    {
        try
        {
            var today = DateTime.UtcNow.Date;
            var invoices = await _unitOfWork.Invoices.AsQueryable()
                .Where(i => i.CompanyId == companyId && i.InvoiceType == InvoiceType.Sales
                    && i.InvoiceDate >= today && i.Status != InvoiceStatus.Cancelled && i.Status != InvoiceStatus.Draft)
                .ToListAsync();

            var totalSales = invoices.Sum(i => i.NetAmount);
            var totalCash = invoices.Where(i => i.PaymentType == InvoicePaymentType.Cash).Sum(i => i.NetAmount);
            var totalCredit = invoices.Where(i => i.PaymentType != InvoicePaymentType.Cash).Sum(i => i.NetAmount);
            var totalPaid = invoices.Sum(i => i.PaidAmount);

            return Ok(new
            {
                success = true,
                data = new
                {
                    date = today,
                    invoiceCount = invoices.Count,
                    totalSales, totalCash, totalCredit, totalPaid,
                    totalRemaining = totalSales - totalPaid
                }
            });
        }
        catch (Exception ex) { _logger.LogError(ex, "خطأ تقرير مبيعات اليوم"); return StatusCode(500, new { success = false, message = "خطأ داخلي" }); }
    }

    // ══════════════════════════════════════════════════════════════════
    //  Helpers — القيود المحاسبية التلقائية
    // ══════════════════════════════════════════════════════════════════

    /// <summary>
    /// إنشاء قيد محاسبي مرحّل تلقائياً وإرجاع معرفه
    /// </summary>
    private async Task<Guid?> CreateJournalEntryForInventory(
        Guid companyId, Guid createdById, string description,
        JournalReferenceType referenceType, string? referenceId,
        List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)> lines)
    {
        if (lines.Count == 0) return null;

        // رقم القيد التسلسلي
        var year = DateTime.UtcNow.Year;
        var prefix = $"JE-{year}-";
        var maxEntry = await _unitOfWork.JournalEntries.AsQueryable()
            .IgnoreQueryFilters()
            .Where(j => j.CompanyId == companyId && j.EntryDate.Year == year)
            .Select(j => j.EntryNumber)
            .MaxAsync();
        int nextNum = 1;
        if (maxEntry != null && maxEntry.StartsWith(prefix))
        {
            if (int.TryParse(maxEntry.Substring(prefix.Length), out var maxNum))
                nextNum = maxNum + 1;
        }
        var entryNumber = $"{prefix}{nextNum:D4}";

        var entryId = Guid.NewGuid();
        var entry = new JournalEntry
        {
            Id = entryId,
            EntryNumber = entryNumber,
            EntryDate = DateTime.UtcNow,
            Description = description,
            TotalDebit = lines.Sum(l => l.DebitAmount),
            TotalCredit = lines.Sum(l => l.CreditAmount),
            ReferenceType = referenceType,
            ReferenceId = referenceId,
            Status = JournalEntryStatus.Posted,
            CompanyId = companyId,
            CreatedById = createdById,
            ApprovedById = createdById,
            ApprovedAt = DateTime.UtcNow,
            Lines = lines.Select(l => new JournalEntryLine
            {
                AccountId = l.AccountId,
                DebitAmount = l.DebitAmount,
                CreditAmount = l.CreditAmount,
                Description = l.LineDescription
            }).ToList()
        };

        await _unitOfWork.JournalEntries.AddAsync(entry);

        // تحديث أرصدة الحسابات فوراً
        foreach (var line in lines)
        {
            var account = await _unitOfWork.Accounts.GetByIdAsync(line.AccountId);
            if (account == null) continue;

            if (account.AccountType == AccountType.Assets || account.AccountType == AccountType.Expenses)
                account.CurrentBalance += line.DebitAmount - line.CreditAmount;
            else
                account.CurrentBalance += line.CreditAmount - line.DebitAmount;

            _unitOfWork.Accounts.Update(account);
        }

        return entryId;
    }

    /// <summary>
    /// جلب حساب مربوط من InventoryAccountMapping
    /// </summary>
    private async Task<Guid?> GetMappedAccountId(Guid companyId, string accountKey)
    {
        var mapping = await _unitOfWork.InventoryAccountMappings.AsQueryable()
            .FirstOrDefaultAsync(m => m.CompanyId == companyId && m.AccountKey == accountKey);
        return mapping?.AccountId;
    }

    /// <summary>
    /// جلب حساب المورد أو العميل — يبحث في AccountId المباشر أو ينشئ تلقائياً
    /// </summary>
    private async Task<Guid?> GetEntityAccountId(Guid companyId, string entityType, Guid entityId)
    {
        if (entityType == "Customer")
        {
            var customer = await _unitOfWork.InventoryCustomers.GetByIdAsync(entityId);
            if (customer?.AccountId != null) return customer.AccountId;
            // fallback: حساب ذمم مدينة العام
            return await GetMappedAccountId(companyId, "accounts_receivable");
        }
        else
        {
            var supplier = await _unitOfWork.Suppliers.GetByIdAsync(entityId);
            if (supplier?.AccountId != null) return supplier.AccountId;
            // fallback: حساب ذمم دائنة العام
            return await GetMappedAccountId(companyId, "accounts_payable");
        }
    }

    /// <summary>
    /// تحديث رصيد الصندوق + إنشاء حركة نقدية
    /// </summary>
    private async Task UpdateCashBox(Guid cashBoxId, decimal amount, bool isDeposit,
        string description, JournalReferenceType refType, string? refId, Guid createdById)
    {
        var box = await _unitOfWork.CashBoxes.GetByIdAsync(cashBoxId);
        if (box == null) return;

        if (isDeposit)
            box.CurrentBalance += amount;
        else
            box.CurrentBalance -= amount;

        _unitOfWork.CashBoxes.Update(box);

        var transaction = new CashTransaction
        {
            CashBoxId = cashBoxId,
            TransactionType = isDeposit ? CashTransactionType.Deposit : CashTransactionType.Withdrawal,
            Amount = amount,
            BalanceAfter = box.CurrentBalance,
            Description = description,
            ReferenceType = refType,
            ReferenceId = refId,
            CreatedById = createdById
        };
        await _unitOfWork.CashTransactions.AddAsync(transaction);
    }

    // ══════════════════════════════════════════════════════════════════
    //  بذر الحسابات الافتراضية + ربط المخزون
    // ══════════════════════════════════════════════════════════════════

    /// <summary>
    /// بذر الحسابات المحاسبية الافتراضية لنظام المخازن (يُستدعى مرة واحدة عند التفعيل)
    /// </summary>
    [HttpPost("accounts/seed")]
    [RequirePermission("inventory", "add")]
    public async Task<IActionResult> SeedInventoryAccounts([FromBody] SeedAccountsRequest request)
    {
        try
        {
            // التحقق من عدم البذر المسبق
            var existing = await _unitOfWork.InventoryAccountMappings.AsQueryable()
                .AnyAsync(m => m.CompanyId == request.CompanyId);
            if (existing)
                return Ok(new { success = true, message = "الحسابات مُعدّة مسبقاً", alreadySeeded = true });

            var companyId = request.CompanyId;
            var userId = GetCurrentUserId();

            // تعريف الحسابات المطلوبة (كود، اسم، نوع، أب)
            var accountDefs = new (string code, string name, AccountType type, string? parentCode, string? mappingKey)[]
            {
                ("1130", "المخزون (بضاعة)", AccountType.Assets, null, "inventory"),
                ("1140", "ذمم مدينة (عملاء)", AccountType.Assets, null, "accounts_receivable"),
                ("2110", "ذمم دائنة (موردين)", AccountType.Liabilities, null, "accounts_payable"),
                ("4100", "إيرادات المبيعات", AccountType.Revenue, null, "sales_revenue"),
                ("5100", "تكلفة البضاعة المباعة", AccountType.Expenses, null, "cogs"),
                ("5300", "مردودات المبيعات", AccountType.Expenses, null, "sales_returns"),
                ("5310", "مردودات المشتريات", AccountType.Assets, null, "purchase_returns"),
                ("2120", "ضريبة مستحقة", AccountType.Liabilities, null, "tax_payable"),
            };

            var mappings = new List<InventoryAccountMapping>();

            foreach (var def in accountDefs)
            {
                // بحث عن الحساب إذا موجود
                var account = await _unitOfWork.Accounts.AsQueryable()
                    .FirstOrDefaultAsync(a => a.Code == def.code && a.CompanyId == companyId);

                if (account == null)
                {
                    // إنشاء الحساب
                    account = new Account
                    {
                        Id = Guid.NewGuid(),
                        Code = def.code,
                        Name = def.name,
                        AccountType = def.type,
                        IsSystemAccount = true,
                        IsLeaf = true,
                        IsActive = true,
                        Level = 3,
                        CompanyId = companyId
                    };
                    await _unitOfWork.Accounts.AddAsync(account);
                }

                if (def.mappingKey != null)
                {
                    mappings.Add(new InventoryAccountMapping
                    {
                        CompanyId = companyId,
                        AccountKey = def.mappingKey,
                        AccountId = account.Id
                    });
                }
            }

            foreach (var m in mappings)
                await _unitOfWork.InventoryAccountMappings.AddAsync(m);

            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = $"تم إنشاء {mappings.Count} حساب وربطهم بالمخزون", alreadySeeded = false });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في بذر حسابات المخزون");
            return StatusCode(500, new { success = false, message = $"خطأ: {ex.Message}" });
        }
    }

    /// <summary>
    /// جلب ربط الحسابات الحالي
    /// </summary>
    [HttpGet("accounts/mappings")]
    public async Task<IActionResult> GetAccountMappings([FromQuery] Guid companyId)
    {
        var mappings = await _unitOfWork.InventoryAccountMappings.AsQueryable()
            .Where(m => m.CompanyId == companyId)
            .Select(m => new
            {
                m.AccountKey,
                m.AccountId,
                AccountName = m.Account != null ? m.Account.Name : null,
                AccountCode = m.Account != null ? m.Account.Code : null
            }).ToListAsync();

        return Ok(new { success = true, data = mappings });
    }

    // ══════════════════════════════════════════════════════════════════
    //  العملاء — Customers
    // ══════════════════════════════════════════════════════════════════

    [HttpGet("customers")]
    public async Task<IActionResult> GetCustomers([FromQuery] Guid companyId, [FromQuery] string? search = null,
        [FromQuery] InventoryCustomerType? type = null, [FromQuery] bool? activeOnly = true)
    {
        try
        {
            var query = _unitOfWork.InventoryCustomers.AsQueryable()
                .Where(c => c.CompanyId == companyId);

            if (activeOnly == true) query = query.Where(c => c.IsActive);
            if (type.HasValue) query = query.Where(c => c.CustomerType == type);
            if (!string.IsNullOrWhiteSpace(search))
                query = query.Where(c => c.FullName.Contains(search) || c.Phone!.Contains(search) || c.CustomerCode.Contains(search));

            var customers = await query.OrderBy(c => c.FullName)
                .Select(c => new
                {
                    c.Id, c.CustomerCode, c.FullName, c.Phone, c.Phone2, c.Email,
                    c.City, c.Area, CustomerType = c.CustomerType.ToString(),
                    c.CreditLimit, c.TotalSales, c.TotalPayments, c.Balance,
                    c.IsActive, c.CreatedAt
                }).ToListAsync();

            return Ok(new { success = true, data = customers, total = customers.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب العملاء");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    [HttpGet("customers/{id}")]
    public async Task<IActionResult> GetCustomerDetails(Guid id)
    {
        try
        {
            var c = await _unitOfWork.InventoryCustomers.AsQueryable()
                .Where(x => x.Id == id)
                .Select(x => new
                {
                    x.Id, x.CustomerCode, x.FullName, x.Phone, x.Phone2, x.Email,
                    x.City, x.Area, x.Address, CustomerType = x.CustomerType.ToString(),
                    x.CreditLimit, x.TotalSales, x.TotalPayments, x.Balance,
                    x.TaxNumber, x.Notes, x.IsActive, x.AccountId, x.CompanyId, x.CreatedAt,
                    InvoiceCount = x.Invoices.Count(i => !i.IsDeleted)
                }).FirstOrDefaultAsync();

            if (c == null) return NotFound(new { success = false, message = "العميل غير موجود" });
            return Ok(new { success = true, data = c });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب تفاصيل العميل");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    [HttpPost("customers")]
    [RequirePermission("inventory", "add")]
    public async Task<IActionResult> CreateCustomer([FromBody] CreateInventoryCustomerRequest req)
    {
        try
        {
            var code = await GenerateOrderNumber("CU", req.CompanyId);
            var customer = new InventoryCustomer
            {
                Id = Guid.NewGuid(),
                CustomerCode = code,
                FullName = req.FullName,
                Phone = req.Phone,
                Phone2 = req.Phone2,
                Email = req.Email,
                City = req.City,
                Area = req.Area,
                Address = req.Address,
                CustomerType = req.CustomerType,
                CreditLimit = req.CreditLimit,
                TaxNumber = req.TaxNumber,
                Notes = req.Notes,
                CompanyId = req.CompanyId
            };

            await _unitOfWork.InventoryCustomers.AddAsync(customer);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, data = new { customer.Id, customer.CustomerCode }, message = "تم إضافة العميل" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إضافة العميل");
            return StatusCode(500, new { success = false, message = $"خطأ: {ex.Message}" });
        }
    }

    [HttpPut("customers/{id}")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> UpdateCustomer(Guid id, [FromBody] UpdateInventoryCustomerRequest req)
    {
        try
        {
            var customer = await _unitOfWork.InventoryCustomers.GetByIdAsync(id);
            if (customer == null) return NotFound(new { success = false, message = "العميل غير موجود" });

            if (req.FullName != null) customer.FullName = req.FullName;
            if (req.Phone != null) customer.Phone = req.Phone;
            if (req.Phone2 != null) customer.Phone2 = req.Phone2;
            if (req.Email != null) customer.Email = req.Email;
            if (req.City != null) customer.City = req.City;
            if (req.Area != null) customer.Area = req.Area;
            if (req.Address != null) customer.Address = req.Address;
            if (req.CustomerType.HasValue) customer.CustomerType = req.CustomerType.Value;
            if (req.CreditLimit.HasValue) customer.CreditLimit = req.CreditLimit.Value;
            if (req.TaxNumber != null) customer.TaxNumber = req.TaxNumber;
            if (req.Notes != null) customer.Notes = req.Notes;
            if (req.IsActive.HasValue) customer.IsActive = req.IsActive.Value;

            _unitOfWork.InventoryCustomers.Update(customer);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تعديل العميل" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تعديل العميل");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    [HttpDelete("customers/{id}")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> DeleteCustomer(Guid id)
    {
        try
        {
            var customer = await _unitOfWork.InventoryCustomers.GetByIdAsync(id);
            if (customer == null) return NotFound(new { success = false, message = "العميل غير موجود" });
            if (customer.Balance != 0)
                return BadRequest(new { success = false, message = $"لا يمكن حذف العميل — رصيده {customer.Balance:N0}" });

            customer.IsDeleted = true;
            customer.DeletedAt = DateTime.UtcNow;
            _unitOfWork.InventoryCustomers.Update(customer);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حذف العميل" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف العميل");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    [HttpGet("customers/{id}/statement")]
    public async Task<IActionResult> GetCustomerStatement(Guid id, [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null)
    {
        try
        {
            var customer = await _unitOfWork.InventoryCustomers.GetByIdAsync(id);
            if (customer == null) return NotFound(new { success = false, message = "العميل غير موجود" });

            // فواتير
            var invoicesQuery = _unitOfWork.Invoices.AsQueryable()
                .Where(i => i.CustomerId == id && i.Status != InvoiceStatus.Draft && i.Status != InvoiceStatus.Cancelled);
            if (from.HasValue) invoicesQuery = invoicesQuery.Where(i => i.InvoiceDate >= from.Value);
            if (to.HasValue) invoicesQuery = invoicesQuery.Where(i => i.InvoiceDate <= to.Value.AddDays(1));

            var invoices = await invoicesQuery.OrderBy(i => i.InvoiceDate)
                .Select(i => new { Date = i.InvoiceDate, Reference = i.InvoiceNumber, Description = "فاتورة بيع", Debit = i.NetAmount, Credit = 0m })
                .ToListAsync();

            // سندات قبض
            var vouchersQuery = _unitOfWork.PaymentVouchers.AsQueryable()
                .Where(v => v.EntityType == VoucherEntityType.Customer && v.EntityId == id);
            if (from.HasValue) vouchersQuery = vouchersQuery.Where(v => v.VoucherDate >= from.Value);
            if (to.HasValue) vouchersQuery = vouchersQuery.Where(v => v.VoucherDate <= to.Value.AddDays(1));

            var vouchers = await vouchersQuery.OrderBy(v => v.VoucherDate)
                .Select(v => new { Date = v.VoucherDate, Reference = v.VoucherNumber, Description = "سند قبض", Debit = 0m, Credit = v.Amount })
                .ToListAsync();

            // مرتجعات
            var returnsQuery = _unitOfWork.ReturnOrders.AsQueryable()
                .Where(r => r.CustomerId == id && r.ReturnType == ReturnType.SalesReturn && r.Status == ReturnStatus.Confirmed);
            if (from.HasValue) returnsQuery = returnsQuery.Where(r => r.ReturnDate >= from.Value);
            if (to.HasValue) returnsQuery = returnsQuery.Where(r => r.ReturnDate <= to.Value.AddDays(1));

            var returns = await returnsQuery.OrderBy(r => r.ReturnDate)
                .Select(r => new { Date = r.ReturnDate, Reference = r.ReturnNumber, Description = "مرتجع مبيعات", Debit = 0m, Credit = r.TotalAmount })
                .ToListAsync();

            // دمج وترتيب
            var allEntries = invoices.Concat(vouchers).Concat(returns).OrderBy(e => e.Date).ToList();

            // حساب الرصيد التراكمي
            decimal runningBalance = 0;
            var statement = allEntries.Select(e =>
            {
                runningBalance += e.Debit - e.Credit;
                return new { e.Date, e.Reference, e.Description, e.Debit, e.Credit, Balance = runningBalance };
            }).ToList();

            return Ok(new
            {
                success = true,
                data = new
                {
                    customer = new { customer.Id, customer.CustomerCode, customer.FullName, customer.Balance },
                    statement,
                    totalDebit = allEntries.Sum(e => e.Debit),
                    totalCredit = allEntries.Sum(e => e.Credit),
                    closingBalance = runningBalance
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب كشف حساب العميل");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    // ══════════════════════════════════════════════════════════════════
    //  الفواتير — Invoices
    // ══════════════════════════════════════════════════════════════════

    [HttpGet("invoices")]
    public async Task<IActionResult> GetInvoices([FromQuery] Guid companyId, [FromQuery] InvoiceType? type = null,
        [FromQuery] InvoiceStatus? status = null, [FromQuery] Guid? customerId = null, [FromQuery] Guid? supplierId = null,
        [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null)
    {
        try
        {
            var query = _unitOfWork.Invoices.AsQueryable().Where(i => i.CompanyId == companyId);

            if (type.HasValue) query = query.Where(i => i.InvoiceType == type);
            if (status.HasValue) query = query.Where(i => i.Status == status);
            if (customerId.HasValue) query = query.Where(i => i.CustomerId == customerId);
            if (supplierId.HasValue) query = query.Where(i => i.SupplierId == supplierId);
            if (from.HasValue) query = query.Where(i => i.InvoiceDate >= from.Value);
            if (to.HasValue) query = query.Where(i => i.InvoiceDate <= to.Value.AddDays(1));

            var invoices = await query.OrderByDescending(i => i.InvoiceDate)
                .Select(i => new
                {
                    i.Id, i.InvoiceNumber, InvoiceType = i.InvoiceType.ToString(),
                    PaymentType = i.PaymentType.ToString(), i.EntityName,
                    i.CustomerId, i.SupplierId, i.InvoiceDate, i.DueDate,
                    i.SubTotal, i.DiscountAmount, i.TaxAmount, i.NetAmount,
                    i.PaidAmount, i.RemainingAmount, Status = i.Status.ToString(),
                    WarehouseName = i.Warehouse != null ? i.Warehouse.Name : null,
                    ItemsCount = i.Items.Count, i.CreatedAt
                }).ToListAsync();

            return Ok(new { success = true, data = invoices, total = invoices.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب الفواتير");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    [HttpGet("invoices/{id}")]
    public async Task<IActionResult> GetInvoiceDetails(Guid id)
    {
        try
        {
            var invoice = await _unitOfWork.Invoices.AsQueryable().Where(i => i.Id == id)
                .Select(i => new
                {
                    i.Id, i.InvoiceNumber, InvoiceType = i.InvoiceType.ToString(),
                    PaymentType = i.PaymentType.ToString(),
                    i.CustomerId, CustomerName = i.Customer != null ? i.Customer.FullName : null,
                    i.SupplierId, SupplierName = i.Supplier != null ? i.Supplier.Name : null,
                    i.EntityName, i.WarehouseId,
                    WarehouseName = i.Warehouse != null ? i.Warehouse.Name : null,
                    i.InvoiceDate, i.DueDate, i.SubTotal,
                    DiscountType = i.DiscountType.ToString(), i.DiscountValue, i.DiscountAmount,
                    i.TaxRate, i.TaxAmount, i.NetAmount, i.PaidAmount, i.RemainingAmount,
                    Status = i.Status.ToString(), i.Notes, i.JournalEntryId, i.CashBoxId,
                    i.CompanyId, i.CreatedAt,
                    CreatedByName = i.CreatedBy != null ? i.CreatedBy.FullName : null,
                    Items = i.Items.Select(item => new
                    {
                        item.Id, item.InventoryItemId, item.ItemName, item.Quantity,
                        item.UnitPrice, item.DiscountPercent, item.DiscountAmount,
                        item.TaxAmount, item.TotalPrice, item.CostAtSale, item.Notes
                    }).ToList(),
                    Vouchers = i.PaymentVouchers.Where(v => !v.IsDeleted).Select(v => new
                    {
                        v.Id, v.VoucherNumber, v.Amount, v.VoucherDate,
                        PaymentMethod = v.PaymentMethod.ToString()
                    }).ToList()
                }).FirstOrDefaultAsync();

            if (invoice == null) return NotFound(new { success = false, message = "الفاتورة غير موجودة" });
            return Ok(new { success = true, data = invoice });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب تفاصيل الفاتورة");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    [HttpPost("invoices")]
    [RequirePermission("inventory", "add")]
    public async Task<IActionResult> CreateInvoice([FromBody] CreateInvoiceRequest req)
    {
        try
        {
            var prefix = req.InvoiceType == InvoiceType.Sales ? "INV" : "PINV";
            var invoiceNumber = await GenerateOrderNumber(prefix, req.CompanyId);
            var userId = GetCurrentUserId();

            // اسم الكيان
            string? entityName = null;
            if (req.CustomerId.HasValue)
            {
                var cust = await _unitOfWork.InventoryCustomers.GetByIdAsync(req.CustomerId.Value);
                entityName = cust?.FullName;
            }
            else if (req.SupplierId.HasValue)
            {
                var sup = await _unitOfWork.Suppliers.GetByIdAsync(req.SupplierId.Value);
                entityName = sup?.Name;
            }

            var invoice = new Invoice
            {
                Id = Guid.NewGuid(),
                InvoiceNumber = invoiceNumber,
                InvoiceType = req.InvoiceType,
                PaymentType = req.PaymentType,
                CustomerId = req.CustomerId,
                SupplierId = req.SupplierId,
                EntityName = entityName ?? req.EntityName,
                WarehouseId = req.WarehouseId,
                InvoiceDate = DateTime.UtcNow,
                DueDate = req.DueDate,
                DiscountType = req.DiscountType,
                DiscountValue = req.DiscountValue,
                TaxRate = req.TaxRate,
                Status = InvoiceStatus.Draft,
                Notes = req.Notes,
                CashBoxId = req.CashBoxId,
                CreatedById = userId,
                CompanyId = req.CompanyId
            };

            // حساب البنود
            decimal subTotal = 0;
            foreach (var itemDto in req.Items)
            {
                var invItem = await _unitOfWork.InventoryItems.GetByIdAsync(itemDto.InventoryItemId);
                var lineDiscount = itemDto.DiscountPercent > 0
                    ? (itemDto.UnitPrice * itemDto.Quantity * itemDto.DiscountPercent / 100m)
                    : 0;
                var lineTotal = (itemDto.UnitPrice * itemDto.Quantity) - lineDiscount;

                // تكلفة الوحدة (لحساب الربح في البيع)
                decimal costAtSale = 0;
                if (req.InvoiceType == InvoiceType.Sales)
                {
                    var stock = await _unitOfWork.WarehouseStocks.AsQueryable()
                        .FirstOrDefaultAsync(s => s.WarehouseId == req.WarehouseId && s.InventoryItemId == itemDto.InventoryItemId && !s.IsDeleted);
                    costAtSale = stock?.AverageCost ?? 0;
                }

                var invoiceItem = new InvoiceItem
                {
                    InvoiceId = invoice.Id,
                    InventoryItemId = itemDto.InventoryItemId,
                    ItemName = invItem?.Name ?? "",
                    Quantity = itemDto.Quantity,
                    UnitPrice = itemDto.UnitPrice,
                    DiscountPercent = itemDto.DiscountPercent,
                    DiscountAmount = lineDiscount,
                    TotalPrice = lineTotal,
                    CostAtSale = costAtSale,
                    Notes = itemDto.Notes
                };
                await _unitOfWork.InvoiceItems.AddAsync(invoiceItem);
                subTotal += lineTotal;
            }

            // الخصم العام
            decimal discountAmount = req.DiscountType == DiscountType.Percentage
                ? subTotal * req.DiscountValue / 100m
                : req.DiscountValue;

            var afterDiscount = subTotal - discountAmount;
            var taxAmount = afterDiscount * req.TaxRate / 100m;
            var netAmount = afterDiscount + taxAmount;

            invoice.SubTotal = subTotal;
            invoice.DiscountAmount = discountAmount;
            invoice.TaxAmount = taxAmount;
            invoice.NetAmount = netAmount;
            invoice.RemainingAmount = netAmount;

            // إذا نقد → المدفوع = الصافي
            if (req.PaymentType == InvoicePaymentType.Cash)
            {
                invoice.PaidAmount = netAmount;
                invoice.RemainingAmount = 0;
            }
            else if (req.PaymentType == InvoicePaymentType.Partial)
            {
                invoice.PaidAmount = req.PaidAmount;
                invoice.RemainingAmount = netAmount - req.PaidAmount;
            }

            await _unitOfWork.Invoices.AddAsync(invoice);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, data = new { invoice.Id, invoice.InvoiceNumber, invoice.NetAmount }, message = "تم إنشاء الفاتورة" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء الفاتورة");
            return StatusCode(500, new { success = false, message = $"خطأ: {ex.Message}" });
        }
    }

    /// <summary>
    /// تأكيد الفاتورة — يخصم/يضيف المخزون + ينشئ القيد المحاسبي + يحدث الأرصدة
    /// </summary>
    [HttpPost("invoices/{id}/confirm")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> ConfirmInvoice(Guid id)
    {
        try
        {
            var invoice = await _unitOfWork.Invoices.AsQueryable()
                .Include(i => i.Items)
                .FirstOrDefaultAsync(i => i.Id == id);

            if (invoice == null) return NotFound(new { success = false, message = "الفاتورة غير موجودة" });
            if (invoice.Status != InvoiceStatus.Draft)
                return BadRequest(new { success = false, message = "الفاتورة ليست مسودة" });

            var userId = GetCurrentUserId();
            var isSales = invoice.InvoiceType == InvoiceType.Sales;

            // ── 1. حركات المخزون ──
            decimal totalCost = 0;
            foreach (var item in invoice.Items)
            {
                var stock = await _unitOfWork.WarehouseStocks.AsQueryable()
                    .FirstOrDefaultAsync(s => s.WarehouseId == invoice.WarehouseId && s.InventoryItemId == item.InventoryItemId && !s.IsDeleted);

                int oldQty = stock?.CurrentQuantity ?? 0;
                int newQty;

                if (isSales)
                {
                    // بيع → خصم من المخزون
                    newQty = oldQty - item.Quantity;
                    if (stock != null) { stock.CurrentQuantity = newQty; stock.LastStockOutDate = DateTime.UtcNow; _unitOfWork.WarehouseStocks.Update(stock); }
                    totalCost += item.CostAtSale * item.Quantity;
                }
                else
                {
                    // شراء → إضافة للمخزون + تحديث التكلفة المتوسطة
                    newQty = oldQty + item.Quantity;
                    if (stock != null)
                    {
                        var totalValue = (stock.AverageCost * oldQty) + (item.UnitPrice * item.Quantity);
                        stock.AverageCost = newQty > 0 ? totalValue / newQty : item.UnitPrice;
                        stock.CurrentQuantity = newQty;
                        stock.LastStockInDate = DateTime.UtcNow;
                        _unitOfWork.WarehouseStocks.Update(stock);
                    }
                    else
                    {
                        await _unitOfWork.WarehouseStocks.AddAsync(new WarehouseStock
                        {
                            WarehouseId = invoice.WarehouseId,
                            InventoryItemId = item.InventoryItemId,
                            CurrentQuantity = item.Quantity,
                            AverageCost = item.UnitPrice,
                            LastStockInDate = DateTime.UtcNow,
                            CompanyId = invoice.CompanyId
                        });
                    }
                }

                // حركة مخزنية
                await _unitOfWork.StockMovements.AddAsync(new StockMovement
                {
                    InventoryItemId = item.InventoryItemId,
                    WarehouseId = invoice.WarehouseId,
                    MovementType = isSales ? StockMovementType.SalesOut : StockMovementType.PurchaseIn,
                    Quantity = item.Quantity,
                    StockBefore = oldQty,
                    StockAfter = isSales ? oldQty - item.Quantity : oldQty + item.Quantity,
                    UnitCost = isSales ? item.CostAtSale : item.UnitPrice,
                    ReferenceType = "Invoice",
                    ReferenceId = invoice.Id.ToString(),
                    ReferenceNumber = invoice.InvoiceNumber,
                    Description = $"{(isSales ? "بيع" : "شراء")} - {invoice.InvoiceNumber}",
                    CreatedById = userId,
                    CompanyId = invoice.CompanyId
                });
            }

            // ── 2. القيد المحاسبي ──
            var inventoryAccId = await GetMappedAccountId(invoice.CompanyId, "inventory");
            var cogsAccId = await GetMappedAccountId(invoice.CompanyId, "cogs");
            var revenueAccId = await GetMappedAccountId(invoice.CompanyId, "sales_revenue");

            if (inventoryAccId != null)
            {
                var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>();

                if (isSales)
                {
                    // فاتورة بيع
                    Guid? debitAccId;
                    if (invoice.PaymentType == InvoicePaymentType.Cash && invoice.CashBoxId.HasValue)
                    {
                        // نقد → مدين الصندوق (عبر حساب الصندوق المربوط)
                        var cashBox = await _unitOfWork.CashBoxes.GetByIdAsync(invoice.CashBoxId.Value);
                        debitAccId = cashBox?.LinkedAccountId ?? await GetMappedAccountId(invoice.CompanyId, "accounts_receivable");
                    }
                    else
                    {
                        // آجل → مدين حساب العميل
                        debitAccId = invoice.CustomerId.HasValue
                            ? await GetEntityAccountId(invoice.CompanyId, "Customer", invoice.CustomerId.Value)
                            : await GetMappedAccountId(invoice.CompanyId, "accounts_receivable");
                    }

                    if (debitAccId != null && revenueAccId != null)
                    {
                        lines.Add((debitAccId.Value, invoice.NetAmount, 0, "إيراد مبيعات"));
                        lines.Add((revenueAccId.Value, 0, invoice.NetAmount, "إيراد مبيعات"));
                    }
                    if (cogsAccId != null && totalCost > 0)
                    {
                        lines.Add((cogsAccId.Value, totalCost, 0, "تكلفة بضاعة مباعة"));
                        lines.Add((inventoryAccId.Value, 0, totalCost, "خصم من المخزون"));
                    }
                }
                else
                {
                    // فاتورة شراء
                    Guid? creditAccId;
                    if (invoice.PaymentType == InvoicePaymentType.Cash && invoice.CashBoxId.HasValue)
                    {
                        var cashBox = await _unitOfWork.CashBoxes.GetByIdAsync(invoice.CashBoxId.Value);
                        creditAccId = cashBox?.LinkedAccountId ?? await GetMappedAccountId(invoice.CompanyId, "accounts_payable");
                    }
                    else
                    {
                        creditAccId = invoice.SupplierId.HasValue
                            ? await GetEntityAccountId(invoice.CompanyId, "Supplier", invoice.SupplierId.Value)
                            : await GetMappedAccountId(invoice.CompanyId, "accounts_payable");
                    }

                    if (creditAccId != null)
                    {
                        lines.Add((inventoryAccId.Value, invoice.NetAmount, 0, "إضافة للمخزون"));
                        lines.Add((creditAccId.Value, 0, invoice.NetAmount, isSales ? "" : "مشتريات"));
                    }
                }

                if (lines.Count > 0)
                {
                    var jeId = await CreateJournalEntryForInventory(
                        invoice.CompanyId, userId,
                        $"{(isSales ? "فاتورة بيع" : "فاتورة شراء")} - {invoice.InvoiceNumber}",
                        isSales ? JournalReferenceType.SalesInvoice : JournalReferenceType.PurchaseInvoice,
                        invoice.Id.ToString(), lines);
                    invoice.JournalEntryId = jeId;
                }
            }

            // ── 3. تحديث الصندوق (إذا نقد) ──
            if (invoice.PaymentType == InvoicePaymentType.Cash && invoice.CashBoxId.HasValue)
            {
                await UpdateCashBox(invoice.CashBoxId.Value, invoice.NetAmount,
                    isDeposit: isSales, // بيع = إيداع، شراء = سحب
                    $"{(isSales ? "فاتورة بيع" : "فاتورة شراء")} - {invoice.InvoiceNumber}",
                    isSales ? JournalReferenceType.SalesInvoice : JournalReferenceType.PurchaseInvoice,
                    invoice.Id.ToString(), userId);
            }

            // ── 4. تحديث رصيد العميل/المورد (إذا آجل) ──
            if (invoice.PaymentType != InvoicePaymentType.Cash)
            {
                if (isSales && invoice.CustomerId.HasValue)
                {
                    var cust = await _unitOfWork.InventoryCustomers.GetByIdAsync(invoice.CustomerId.Value);
                    if (cust != null)
                    {
                        cust.TotalSales += invoice.NetAmount;
                        cust.Balance += invoice.RemainingAmount;
                        _unitOfWork.InventoryCustomers.Update(cust);
                    }
                }
                else if (!isSales && invoice.SupplierId.HasValue)
                {
                    var sup = await _unitOfWork.Suppliers.GetByIdAsync(invoice.SupplierId.Value);
                    if (sup != null)
                    {
                        sup.TotalPurchases += invoice.NetAmount;
                        sup.Balance += invoice.RemainingAmount;
                        _unitOfWork.Suppliers.Update(sup);
                    }
                }
            }

            // ── 5. تحديث حالة الفاتورة ──
            invoice.Status = invoice.RemainingAmount <= 0 ? InvoiceStatus.Paid
                : invoice.PaidAmount > 0 ? InvoiceStatus.PartiallyPaid
                : InvoiceStatus.Confirmed;

            _unitOfWork.Invoices.Update(invoice);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تأكيد الفاتورة", data = new { invoice.Id, Status = invoice.Status.ToString(), invoice.JournalEntryId } });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تأكيد الفاتورة");
            return StatusCode(500, new { success = false, message = $"خطأ: {ex.Message}" });
        }
    }

    [HttpPost("invoices/{id}/cancel")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> CancelInvoice(Guid id)
    {
        try
        {
            var invoice = await _unitOfWork.Invoices.GetByIdAsync(id);
            if (invoice == null) return NotFound(new { success = false, message = "الفاتورة غير موجودة" });
            if (invoice.Status == InvoiceStatus.Cancelled)
                return BadRequest(new { success = false, message = "الفاتورة ملغاة مسبقاً" });

            if (invoice.Status == InvoiceStatus.Draft)
            {
                invoice.Status = InvoiceStatus.Cancelled;
                _unitOfWork.Invoices.Update(invoice);
                await _unitOfWork.SaveChangesAsync();
                return Ok(new { success = true, message = "تم إلغاء المسودة" });
            }

            // ── إلغاء فاتورة مؤكدة مع عكس المخزون والأرصدة ──
            await _unitOfWork.BeginTransactionAsync();
            try
            {
                var currentUserId = GetCurrentUserId();
                var invoiceItems = await _unitOfWork.InvoiceItems.FindAsync(ii => ii.InvoiceId == id);
                var isSales = invoice.InvoiceType == InvoiceType.Sales;

                // ── 1. عكس حركات المخزون ──
                foreach (var item in invoiceItems)
                {
                    var stock = await _unitOfWork.WarehouseStocks.FirstOrDefaultAsync(
                        ws => ws.WarehouseId == invoice.WarehouseId
                           && ws.InventoryItemId == item.InventoryItemId
                           && !ws.IsDeleted);

                    if (stock != null)
                    {
                        var stockBefore = stock.CurrentQuantity;
                        if (isSales)
                        {
                            // فاتورة بيع: إرجاع الكميات
                            stock.CurrentQuantity += item.Quantity;
                        }
                        else
                        {
                            // فاتورة شراء: سحب الكميات
                            stock.CurrentQuantity -= item.Quantity;
                            if (stock.CurrentQuantity < 0) stock.CurrentQuantity = 0;
                        }
                        stock.UpdatedAt = DateTime.UtcNow;
                        _unitOfWork.WarehouseStocks.Update(stock);

                        await _unitOfWork.StockMovements.AddAsync(new StockMovement
                        {
                            InventoryItemId = item.InventoryItemId,
                            WarehouseId = invoice.WarehouseId,
                            MovementType = isSales ? StockMovementType.SalesReturn : StockMovementType.PurchaseReturn,
                            Quantity = item.Quantity,
                            StockBefore = stockBefore,
                            StockAfter = stock.CurrentQuantity,
                            UnitCost = stock.AverageCost,
                            ReferenceType = "Invoice",
                            ReferenceId = invoice.Id.ToString(),
                            ReferenceNumber = invoice.InvoiceNumber,
                            Description = $"إلغاء فاتورة - {invoice.InvoiceNumber}",
                            CreatedById = currentUserId,
                            CompanyId = invoice.CompanyId
                        });
                    }
                }

                // ── 2. عكس رصيد العميل/المورد ──
                if (isSales && invoice.CustomerId.HasValue && invoice.PaymentType != InvoicePaymentType.Cash)
                {
                    var cust = await _unitOfWork.InventoryCustomers.GetByIdAsync(invoice.CustomerId.Value);
                    if (cust != null) { cust.TotalSales -= invoice.NetAmount; cust.Balance -= invoice.RemainingAmount; _unitOfWork.InventoryCustomers.Update(cust); }
                }
                else if (!isSales && invoice.SupplierId.HasValue && invoice.PaymentType != InvoicePaymentType.Cash)
                {
                    var sup = await _unitOfWork.Suppliers.GetByIdAsync(invoice.SupplierId.Value);
                    if (sup != null) { sup.TotalPurchases -= invoice.NetAmount; sup.Balance -= invoice.RemainingAmount; _unitOfWork.Suppliers.Update(sup); }
                }

                invoice.Status = InvoiceStatus.Cancelled;
                invoice.UpdatedAt = DateTime.UtcNow;
                _unitOfWork.Invoices.Update(invoice);

                await _unitOfWork.SaveChangesAsync();
                await _unitOfWork.CommitTransactionAsync();

                return Ok(new { success = true, message = "تم إلغاء الفاتورة وعكس المخزون والأرصدة" });
            }
            catch
            {
                await _unitOfWork.RollbackTransactionAsync();
                throw;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إلغاء الفاتورة");
            return StatusCode(500, new { success = false, message = $"خطأ: {ex.Message}" });
        }
    }

    // ══════════════════════════════════════════════════════════════════
    //  سندات القبض والصرف — Payment Vouchers
    // ══════════════════════════════════════════════════════════════════

    [HttpGet("vouchers")]
    public async Task<IActionResult> GetVouchers([FromQuery] Guid companyId, [FromQuery] VoucherType? type = null,
        [FromQuery] Guid? entityId = null, [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null)
    {
        try
        {
            var query = _unitOfWork.PaymentVouchers.AsQueryable().Where(v => v.CompanyId == companyId);
            if (type.HasValue) query = query.Where(v => v.VoucherType == type);
            if (entityId.HasValue) query = query.Where(v => v.EntityId == entityId);
            if (from.HasValue) query = query.Where(v => v.VoucherDate >= from.Value);
            if (to.HasValue) query = query.Where(v => v.VoucherDate <= to.Value.AddDays(1));

            var vouchers = await query.OrderByDescending(v => v.VoucherDate)
                .Select(v => new
                {
                    v.Id, v.VoucherNumber, VoucherType = v.VoucherType.ToString(),
                    EntityType = v.EntityType.ToString(), v.EntityId, v.EntityName,
                    v.Amount, PaymentMethod = v.PaymentMethod.ToString(),
                    v.VoucherDate, v.InvoiceId, v.Notes, v.CreatedAt
                }).ToListAsync();

            return Ok(new { success = true, data = vouchers, total = vouchers.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب السندات");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    [HttpPost("vouchers")]
    [RequirePermission("inventory", "add")]
    public async Task<IActionResult> CreateVoucher([FromBody] CreateVoucherRequest req)
    {
        try
        {
            var prefix = req.VoucherType == VoucherType.Receipt ? "RV" : "PV";
            var voucherNumber = await GenerateOrderNumber(prefix, req.CompanyId);
            var userId = GetCurrentUserId();

            var voucher = new PaymentVoucher
            {
                Id = Guid.NewGuid(),
                VoucherNumber = voucherNumber,
                VoucherType = req.VoucherType,
                EntityType = req.EntityType,
                EntityId = req.EntityId,
                EntityName = req.EntityName,
                Amount = req.Amount,
                PaymentMethod = req.PaymentMethod,
                CashBoxId = req.CashBoxId,
                VoucherDate = DateTime.UtcNow,
                InvoiceId = req.InvoiceId,
                Notes = req.Notes,
                CreatedById = userId,
                CompanyId = req.CompanyId
            };

            // ── القيد المحاسبي ──
            Guid? entityAccId;
            Guid? cashAccId = null;

            if (req.CashBoxId.HasValue)
            {
                var cashBox = await _unitOfWork.CashBoxes.GetByIdAsync(req.CashBoxId.Value);
                cashAccId = cashBox?.LinkedAccountId;
            }
            cashAccId ??= await GetMappedAccountId(req.CompanyId, "accounts_receivable"); // fallback

            if (req.VoucherType == VoucherType.Receipt)
            {
                // سند قبض من عميل
                entityAccId = await GetEntityAccountId(req.CompanyId, "Customer", req.EntityId);
                if (entityAccId != null && cashAccId != null)
                {
                    var jeId = await CreateJournalEntryForInventory(req.CompanyId, userId,
                        $"سند قبض - {voucherNumber} - {req.EntityName}",
                        JournalReferenceType.CustomerReceipt, voucher.Id.ToString(),
                        new List<(Guid, decimal, decimal, string?)>
                        {
                            (cashAccId.Value, req.Amount, 0, "قبض نقدي"),
                            (entityAccId.Value, 0, req.Amount, $"من العميل {req.EntityName}")
                        });
                    voucher.JournalEntryId = jeId;
                }

                // تحديث رصيد العميل
                var cust = await _unitOfWork.InventoryCustomers.GetByIdAsync(req.EntityId);
                if (cust != null) { cust.TotalPayments += req.Amount; cust.Balance -= req.Amount; _unitOfWork.InventoryCustomers.Update(cust); }
            }
            else
            {
                // سند صرف لمورد
                entityAccId = await GetEntityAccountId(req.CompanyId, "Supplier", req.EntityId);
                var apAccId = await GetMappedAccountId(req.CompanyId, "accounts_payable");
                entityAccId ??= apAccId;

                if (entityAccId != null && cashAccId != null)
                {
                    var jeId = await CreateJournalEntryForInventory(req.CompanyId, userId,
                        $"سند صرف - {voucherNumber} - {req.EntityName}",
                        JournalReferenceType.SupplierPayment, voucher.Id.ToString(),
                        new List<(Guid, decimal, decimal, string?)>
                        {
                            (entityAccId.Value, req.Amount, 0, $"دفع للمورد {req.EntityName}"),
                            (cashAccId.Value, 0, req.Amount, "صرف نقدي")
                        });
                    voucher.JournalEntryId = jeId;
                }

                // تحديث رصيد المورد
                var sup = await _unitOfWork.Suppliers.GetByIdAsync(req.EntityId);
                if (sup != null) { sup.TotalPayments += req.Amount; sup.Balance -= req.Amount; _unitOfWork.Suppliers.Update(sup); }
            }

            // تحديث الصندوق
            if (req.CashBoxId.HasValue)
            {
                await UpdateCashBox(req.CashBoxId.Value, req.Amount,
                    isDeposit: req.VoucherType == VoucherType.Receipt,
                    $"{(req.VoucherType == VoucherType.Receipt ? "سند قبض" : "سند صرف")} - {voucherNumber}",
                    req.VoucherType == VoucherType.Receipt ? JournalReferenceType.CustomerReceipt : JournalReferenceType.SupplierPayment,
                    voucher.Id.ToString(), userId);
            }

            // تحديث الفاتورة المرتبطة
            if (req.InvoiceId.HasValue)
            {
                var inv = await _unitOfWork.Invoices.GetByIdAsync(req.InvoiceId.Value);
                if (inv != null)
                {
                    inv.PaidAmount += req.Amount;
                    inv.RemainingAmount = inv.NetAmount - inv.PaidAmount;
                    if (inv.RemainingAmount <= 0) { inv.RemainingAmount = 0; inv.Status = InvoiceStatus.Paid; }
                    else inv.Status = InvoiceStatus.PartiallyPaid;
                    _unitOfWork.Invoices.Update(inv);
                }
            }

            await _unitOfWork.PaymentVouchers.AddAsync(voucher);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, data = new { voucher.Id, voucher.VoucherNumber }, message = $"تم إنشاء {(req.VoucherType == VoucherType.Receipt ? "سند القبض" : "سند الصرف")}" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء السند");
            return StatusCode(500, new { success = false, message = $"خطأ: {ex.Message}" });
        }
    }

    /// <summary>
    /// حذف سند قبض/صرف مع عكس الأرصدة والقيد المحاسبي
    /// </summary>
    [HttpDelete("vouchers/{id}")]
    [RequirePermission("inventory", "delete")]
    public async Task<IActionResult> DeleteVoucher(Guid id)
    {
        try
        {
            var voucher = await _unitOfWork.PaymentVouchers.GetByIdAsync(id);
            if (voucher == null || voucher.IsDeleted)
                return NotFound(new { success = false, message = "السند غير موجود" });

            await _unitOfWork.BeginTransactionAsync();
            try
            {
                // ── عكس رصيد العميل/المورد ──
                if (voucher.VoucherType == VoucherType.Receipt)
                {
                    var cust = await _unitOfWork.InventoryCustomers.GetByIdAsync(voucher.EntityId);
                    if (cust != null) { cust.TotalPayments -= voucher.Amount; cust.Balance += voucher.Amount; _unitOfWork.InventoryCustomers.Update(cust); }
                }
                else
                {
                    var sup = await _unitOfWork.Suppliers.GetByIdAsync(voucher.EntityId);
                    if (sup != null) { sup.TotalPayments -= voucher.Amount; sup.Balance += voucher.Amount; _unitOfWork.Suppliers.Update(sup); }
                }

                // ── عكس الفاتورة المرتبطة ──
                if (voucher.InvoiceId.HasValue)
                {
                    var inv = await _unitOfWork.Invoices.GetByIdAsync(voucher.InvoiceId.Value);
                    if (inv != null)
                    {
                        inv.PaidAmount -= voucher.Amount;
                        if (inv.PaidAmount < 0) inv.PaidAmount = 0;
                        inv.RemainingAmount = inv.NetAmount - inv.PaidAmount;
                        inv.Status = inv.PaidAmount <= 0 ? InvoiceStatus.Confirmed : InvoiceStatus.PartiallyPaid;
                        _unitOfWork.Invoices.Update(inv);
                    }
                }

                // ── عكس الصندوق ──
                if (voucher.CashBoxId.HasValue)
                {
                    var cashBox = await _unitOfWork.CashBoxes.GetByIdAsync(voucher.CashBoxId.Value);
                    if (cashBox != null)
                    {
                        if (voucher.VoucherType == VoucherType.Receipt)
                            cashBox.CurrentBalance -= voucher.Amount;
                        else
                            cashBox.CurrentBalance += voucher.Amount;
                        _unitOfWork.CashBoxes.Update(cashBox);
                    }
                }

                voucher.IsDeleted = true;
                voucher.DeletedAt = DateTime.UtcNow;
                _unitOfWork.PaymentVouchers.Update(voucher);

                await _unitOfWork.SaveChangesAsync();
                await _unitOfWork.CommitTransactionAsync();

                return Ok(new { success = true, message = "تم حذف السند وعكس الأرصدة" });
            }
            catch
            {
                await _unitOfWork.RollbackTransactionAsync();
                throw;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف السند");
            return StatusCode(500, new { success = false, message = $"خطأ: {ex.Message}" });
        }
    }

    // ══════════════════════════════════════════════════════════════════
    //  المرتجعات — Returns
    // ══════════════════════════════════════════════════════════════════

    [HttpGet("returns")]
    public async Task<IActionResult> GetReturns([FromQuery] Guid companyId, [FromQuery] ReturnType? type = null,
        [FromQuery] ReturnStatus? status = null, [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null)
    {
        try
        {
            var query = _unitOfWork.ReturnOrders.AsQueryable().Where(r => r.CompanyId == companyId);
            if (type.HasValue) query = query.Where(r => r.ReturnType == type);
            if (status.HasValue) query = query.Where(r => r.Status == status);
            if (from.HasValue) query = query.Where(r => r.ReturnDate >= from.Value);
            if (to.HasValue) query = query.Where(r => r.ReturnDate <= to.Value.AddDays(1));

            var returns = await query.OrderByDescending(r => r.ReturnDate)
                .Select(r => new
                {
                    r.Id, r.ReturnNumber, ReturnType = r.ReturnType.ToString(),
                    OriginalInvoiceNumber = r.OriginalInvoice != null ? r.OriginalInvoice.InvoiceNumber : null,
                    CustomerName = r.Customer != null ? r.Customer.FullName : null,
                    SupplierName = r.Supplier != null ? r.Supplier.Name : null,
                    r.TotalAmount, RefundMethod = r.RefundMethod.ToString(),
                    Status = r.Status.ToString(), r.ReturnDate, r.Reason,
                    ItemsCount = r.Items.Count, r.CreatedAt
                }).ToListAsync();

            return Ok(new { success = true, data = returns, total = returns.Count });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب المرتجعات");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    [HttpPost("returns")]
    [RequirePermission("inventory", "add")]
    public async Task<IActionResult> CreateReturn([FromBody] CreateReturnRequest req)
    {
        try
        {
            var prefix = req.ReturnType == ReturnType.SalesReturn ? "SR" : "PR";
            var returnNumber = await GenerateOrderNumber(prefix, req.CompanyId);
            var userId = GetCurrentUserId();

            decimal totalAmount = req.Items.Sum(i => i.UnitPrice * i.Quantity);

            var returnOrder = new ReturnOrder
            {
                Id = Guid.NewGuid(),
                ReturnNumber = returnNumber,
                ReturnType = req.ReturnType,
                OriginalInvoiceId = req.OriginalInvoiceId,
                CustomerId = req.CustomerId,
                SupplierId = req.SupplierId,
                WarehouseId = req.WarehouseId,
                TotalAmount = totalAmount,
                RefundMethod = req.RefundMethod,
                CashBoxId = req.CashBoxId,
                Status = ReturnStatus.Draft,
                ReturnDate = DateTime.UtcNow,
                Reason = req.Reason,
                Notes = req.Notes,
                CreatedById = userId,
                CompanyId = req.CompanyId
            };

            foreach (var itemDto in req.Items)
            {
                await _unitOfWork.ReturnOrderItems.AddAsync(new ReturnOrderItem
                {
                    ReturnOrderId = returnOrder.Id,
                    InventoryItemId = itemDto.InventoryItemId,
                    Quantity = itemDto.Quantity,
                    UnitPrice = itemDto.UnitPrice,
                    TotalPrice = itemDto.UnitPrice * itemDto.Quantity,
                    Reason = itemDto.Reason
                });
            }

            await _unitOfWork.ReturnOrders.AddAsync(returnOrder);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, data = new { returnOrder.Id, returnOrder.ReturnNumber }, message = "تم إنشاء المرتجع" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إنشاء المرتجع");
            return StatusCode(500, new { success = false, message = $"خطأ: {ex.Message}" });
        }
    }

    /// <summary>
    /// تأكيد المرتجع — إرجاع/خصم المخزون + قيد محاسبي + تحديث أرصدة
    /// </summary>
    [HttpPost("returns/{id}/confirm")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> ConfirmReturn(Guid id)
    {
        try
        {
            var ret = await _unitOfWork.ReturnOrders.AsQueryable()
                .Include(r => r.Items)
                .FirstOrDefaultAsync(r => r.Id == id);

            if (ret == null) return NotFound(new { success = false, message = "المرتجع غير موجود" });
            if (ret.Status != ReturnStatus.Draft)
                return BadRequest(new { success = false, message = "المرتجع ليس مسودة" });

            var userId = GetCurrentUserId();
            var isSalesReturn = ret.ReturnType == ReturnType.SalesReturn;

            // ── 1. حركات المخزون ──
            foreach (var item in ret.Items)
            {
                var stock = await _unitOfWork.WarehouseStocks.AsQueryable()
                    .FirstOrDefaultAsync(s => s.WarehouseId == ret.WarehouseId && s.InventoryItemId == item.InventoryItemId && !s.IsDeleted);

                int oldQty = stock?.CurrentQuantity ?? 0;

                if (isSalesReturn)
                {
                    // مرتجع بيع → إرجاع للمخزون
                    if (stock != null) { stock.CurrentQuantity += item.Quantity; stock.LastStockInDate = DateTime.UtcNow; _unitOfWork.WarehouseStocks.Update(stock); }
                }
                else
                {
                    // مرتجع شراء → خصم من المخزون
                    if (stock != null) { stock.CurrentQuantity -= item.Quantity; stock.LastStockOutDate = DateTime.UtcNow; _unitOfWork.WarehouseStocks.Update(stock); }
                }

                await _unitOfWork.StockMovements.AddAsync(new StockMovement
                {
                    InventoryItemId = item.InventoryItemId,
                    WarehouseId = ret.WarehouseId,
                    MovementType = isSalesReturn ? StockMovementType.SalesReturn : StockMovementType.PurchaseReturn,
                    Quantity = item.Quantity,
                    StockBefore = oldQty,
                    StockAfter = isSalesReturn ? oldQty + item.Quantity : oldQty - item.Quantity,
                    UnitCost = item.UnitPrice,
                    ReferenceType = "ReturnOrder",
                    ReferenceId = ret.Id.ToString(),
                    ReferenceNumber = ret.ReturnNumber,
                    Description = $"{(isSalesReturn ? "مرتجع بيع" : "مرتجع شراء")} - {ret.ReturnNumber}",
                    CreatedById = userId,
                    CompanyId = ret.CompanyId
                });
            }

            // ── 2. القيد المحاسبي ──
            var inventoryAccId = await GetMappedAccountId(ret.CompanyId, "inventory");
            var cogsAccId = await GetMappedAccountId(ret.CompanyId, "cogs");
            var salesRetAccId = await GetMappedAccountId(ret.CompanyId, "sales_returns");

            if (inventoryAccId != null)
            {
                var lines = new List<(Guid AccountId, decimal DebitAmount, decimal CreditAmount, string? LineDescription)>();

                if (isSalesReturn)
                {
                    Guid? creditAccId = ret.RefundMethod == RefundMethod.Cash && ret.CashBoxId.HasValue
                        ? (await _unitOfWork.CashBoxes.GetByIdAsync(ret.CashBoxId.Value))?.LinkedAccountId
                        : ret.CustomerId.HasValue
                            ? await GetEntityAccountId(ret.CompanyId, "Customer", ret.CustomerId.Value)
                            : await GetMappedAccountId(ret.CompanyId, "accounts_receivable");

                    if (salesRetAccId != null && creditAccId != null)
                    {
                        lines.Add((salesRetAccId.Value, ret.TotalAmount, 0, "مردودات مبيعات"));
                        lines.Add((creditAccId.Value, 0, ret.TotalAmount, "إرجاع للعميل"));
                    }
                    if (cogsAccId != null)
                    {
                        lines.Add((inventoryAccId.Value, ret.TotalAmount, 0, "إرجاع للمخزون"));
                        lines.Add((cogsAccId.Value, 0, ret.TotalAmount, "عكس تكلفة مباعة"));
                    }
                }
                else
                {
                    Guid? debitAccId = ret.RefundMethod == RefundMethod.Cash && ret.CashBoxId.HasValue
                        ? (await _unitOfWork.CashBoxes.GetByIdAsync(ret.CashBoxId.Value))?.LinkedAccountId
                        : ret.SupplierId.HasValue
                            ? await GetEntityAccountId(ret.CompanyId, "Supplier", ret.SupplierId.Value)
                            : await GetMappedAccountId(ret.CompanyId, "accounts_payable");

                    if (debitAccId != null)
                    {
                        lines.Add((debitAccId.Value, ret.TotalAmount, 0, "مرتجع مشتريات"));
                        lines.Add((inventoryAccId.Value, 0, ret.TotalAmount, "خصم من المخزون"));
                    }
                }

                if (lines.Count > 0)
                {
                    var jeId = await CreateJournalEntryForInventory(ret.CompanyId, userId,
                        $"{(isSalesReturn ? "مرتجع مبيعات" : "مرتجع مشتريات")} - {ret.ReturnNumber}",
                        isSalesReturn ? JournalReferenceType.SalesReturn : JournalReferenceType.PurchaseReturn,
                        ret.Id.ToString(), lines);
                    ret.JournalEntryId = jeId;
                }
            }

            // ── 3. تحديث الصندوق (إذا نقد) ──
            if (ret.RefundMethod == RefundMethod.Cash && ret.CashBoxId.HasValue)
            {
                await UpdateCashBox(ret.CashBoxId.Value, ret.TotalAmount,
                    isDeposit: !isSalesReturn, // مرتجع بيع = سحب، مرتجع شراء = إيداع
                    $"{(isSalesReturn ? "مرتجع بيع" : "مرتجع شراء")} - {ret.ReturnNumber}",
                    isSalesReturn ? JournalReferenceType.SalesReturn : JournalReferenceType.PurchaseReturn,
                    ret.Id.ToString(), userId);
            }

            // ── 4. تحديث رصيد العميل/المورد ──
            if (ret.RefundMethod == RefundMethod.DeductFromBalance)
            {
                if (isSalesReturn && ret.CustomerId.HasValue)
                {
                    var cust = await _unitOfWork.InventoryCustomers.GetByIdAsync(ret.CustomerId.Value);
                    if (cust != null) { cust.Balance -= ret.TotalAmount; _unitOfWork.InventoryCustomers.Update(cust); }
                }
                else if (!isSalesReturn && ret.SupplierId.HasValue)
                {
                    var sup = await _unitOfWork.Suppliers.GetByIdAsync(ret.SupplierId.Value);
                    if (sup != null) { sup.Balance -= ret.TotalAmount; _unitOfWork.Suppliers.Update(sup); }
                }
            }

            ret.Status = ReturnStatus.Confirmed;
            _unitOfWork.ReturnOrders.Update(ret);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم تأكيد المرتجع", data = new { ret.Id, ret.JournalEntryId } });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تأكيد المرتجع");
            return StatusCode(500, new { success = false, message = $"خطأ: {ex.Message}" });
        }
    }

    /// <summary>
    /// إلغاء مرتجع (Draft فقط)
    /// </summary>
    [HttpPost("returns/{id}/cancel")]
    [RequirePermission("inventory", "edit")]
    public async Task<IActionResult> CancelReturn(Guid id)
    {
        try
        {
            var ret = await _unitOfWork.ReturnOrders.GetByIdAsync(id);
            if (ret == null || ret.IsDeleted)
                return NotFound(new { success = false, message = "المرتجع غير موجود" });

            if (ret.Status != ReturnStatus.Draft)
                return BadRequest(new { success = false, message = "لا يمكن إلغاء مرتجع مؤكد — يمكن فقط إلغاء المسودات" });

            ret.Status = ReturnStatus.Cancelled;
            ret.UpdatedAt = DateTime.UtcNow;
            _unitOfWork.ReturnOrders.Update(ret);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم إلغاء المرتجع" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في إلغاء المرتجع");
            return StatusCode(500, new { success = false, message = "خطأ داخلي" });
        }
    }

    /// <summary>
    /// حذف مرتجع (Draft فقط — soft delete)
    /// </summary>
    [HttpDelete("returns/{id}")]
    [RequirePermission("inventory", "delete")]
    public async Task<IActionResult> DeleteReturn(Guid id)
    {
        try
        {
            var ret = await _unitOfWork.ReturnOrders.GetByIdAsync(id);
            if (ret == null || ret.IsDeleted)
                return NotFound(new { success = false, message = "المرتجع غير موجود" });

            if (ret.Status != ReturnStatus.Draft)
                return BadRequest(new { success = false, message = "لا يمكن حذف مرتجع مؤكد — يمكن فقط حذف المسودات" });

            ret.IsDeleted = true;
            ret.DeletedAt = DateTime.UtcNow;
            _unitOfWork.ReturnOrders.Update(ret);
            await _unitOfWork.SaveChangesAsync();

            return Ok(new { success = true, message = "تم حذف المرتجع" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف المرتجع");
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

public class UpdateDispensingRequest
{
    public Guid? TechnicianId { get; set; }
    public Guid? WarehouseId { get; set; }
    public string? Notes { get; set; }
    public List<DispensingItemDto> Items { get; set; } = new();
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


public class SeedAccountsRequest
{
    public Guid CompanyId { get; set; }
}

// ── Customer DTOs ──
public class CreateInventoryCustomerRequest
{
    public string FullName { get; set; } = string.Empty;
    public string? Phone { get; set; }
    public string? Phone2 { get; set; }
    public string? Email { get; set; }
    public string? City { get; set; }
    public string? Area { get; set; }
    public string? Address { get; set; }
    public InventoryCustomerType CustomerType { get; set; } = InventoryCustomerType.Cash;
    public decimal CreditLimit { get; set; } = 0;
    public string? TaxNumber { get; set; }
    public string? Notes { get; set; }
    public Guid CompanyId { get; set; }
}

public class UpdateInventoryCustomerRequest
{
    public string? FullName { get; set; }
    public string? Phone { get; set; }
    public string? Phone2 { get; set; }
    public string? Email { get; set; }
    public string? City { get; set; }
    public string? Area { get; set; }
    public string? Address { get; set; }
    public InventoryCustomerType? CustomerType { get; set; }
    public decimal? CreditLimit { get; set; }
    public string? TaxNumber { get; set; }
    public string? Notes { get; set; }
    public bool? IsActive { get; set; }
}

// ── Invoice DTOs ──
public class CreateInvoiceRequest
{
    public InvoiceType InvoiceType { get; set; }
    public InvoicePaymentType PaymentType { get; set; } = InvoicePaymentType.Cash;
    public Guid? CustomerId { get; set; }
    public Guid? SupplierId { get; set; }
    public string? EntityName { get; set; }
    public Guid WarehouseId { get; set; }
    public DateTime? DueDate { get; set; }
    public DiscountType DiscountType { get; set; } = DiscountType.Percentage;
    public decimal DiscountValue { get; set; } = 0;
    public decimal TaxRate { get; set; } = 0;
    public decimal PaidAmount { get; set; } = 0;
    public Guid? CashBoxId { get; set; }
    public string? Notes { get; set; }
    public Guid CompanyId { get; set; }
    public List<CreateInvoiceItemDto> Items { get; set; } = new();
}

public class CreateInvoiceItemDto
{
    public Guid InventoryItemId { get; set; }
    public int Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public decimal DiscountPercent { get; set; } = 0;
    public string? Notes { get; set; }
}

// ── Voucher DTOs ──
public class CreateVoucherRequest
{
    public VoucherType VoucherType { get; set; }
    public VoucherEntityType EntityType { get; set; }
    public Guid EntityId { get; set; }
    public string EntityName { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public PaymentMethod PaymentMethod { get; set; } = PaymentMethod.CashOnDelivery;
    public Guid? CashBoxId { get; set; }
    public Guid? InvoiceId { get; set; }
    public string? Notes { get; set; }
    public Guid CompanyId { get; set; }
}

// ── Return DTOs ──
public class CreateReturnRequest
{
    public ReturnType ReturnType { get; set; }
    public Guid OriginalInvoiceId { get; set; }
    public Guid? CustomerId { get; set; }
    public Guid? SupplierId { get; set; }
    public Guid WarehouseId { get; set; }
    public RefundMethod RefundMethod { get; set; } = RefundMethod.DeductFromBalance;
    public Guid? CashBoxId { get; set; }
    public string? Reason { get; set; }
    public string? Notes { get; set; }
    public Guid CompanyId { get; set; }
    public List<CreateReturnItemDto> Items { get; set; } = new();
}

public class CreateReturnItemDto
{
    public Guid InventoryItemId { get; set; }
    public int Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public string? Reason { get; set; }
}
