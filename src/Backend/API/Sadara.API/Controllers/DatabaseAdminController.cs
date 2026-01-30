using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using Sadara.Infrastructure.Data;
using System.Text.Json;

namespace Sadara.API.Controllers;

/// <summary>
/// فلتر للتحقق من API Key أو JWT Token
/// </summary>
public class ApiKeyOrJwtAuthAttribute : Attribute, IAuthorizationFilter
{
    private const string ApiKeyHeader = "X-Api-Key";
    private const string ValidApiKey = "sadara-internal-2024-secure-key";

    public void OnAuthorization(AuthorizationFilterContext context)
    {
        // تحقق من API Key أولاً
        if (context.HttpContext.Request.Headers.TryGetValue(ApiKeyHeader, out var apiKey))
        {
            if (apiKey == ValidApiKey)
            {
                return; // مصرح
            }
        }

        // تحقق من JWT Token
        if (context.HttpContext.User.Identity?.IsAuthenticated == true)
        {
            if (context.HttpContext.User.IsInRole("SuperAdmin"))
            {
                return; // مصرح
            }
        }

        // غير مصرح
        context.Result = new UnauthorizedResult();
    }
}

/// <summary>
/// وحدة تحكم إدارة قاعدة البيانات - للمسؤول فقط
/// تتيح عرض وتعديل وحذف بيانات جميع الجداول
/// </summary>
[ApiController]
[Route("api/[controller]")]
[ApiKeyOrJwtAuth]
public class DatabaseAdminController : ControllerBase
{
    private readonly SadaraDbContext _context;
    private readonly ILogger<DatabaseAdminController> _logger;

    public DatabaseAdminController(SadaraDbContext context, ILogger<DatabaseAdminController> logger)
    {
        _context = context;
        _logger = logger;
    }

    /// <summary>
    /// الحصول على قائمة جميع الجداول المتاحة
    /// </summary>
    [HttpGet("tables")]
    public IActionResult GetTables()
    {
        try
        {
            var tables = new List<object>
            {
                // Core entities
                new { name = "Users", displayName = "المستخدمين", icon = "person", category = "Core" },
                new { name = "Merchants", displayName = "التجار", icon = "store", category = "Core" },
                new { name = "Customers", displayName = "العملاء", icon = "people", category = "Core" },
                new { name = "Products", displayName = "المنتجات", icon = "inventory", category = "Core" },
                new { name = "Orders", displayName = "الطلبات", icon = "shopping_cart", category = "Core" },
                new { name = "Payments", displayName = "المدفوعات", icon = "payment", category = "Core" },
                
                // Commerce entities
                new { name = "Categories", displayName = "التصنيفات", icon = "category", category = "Commerce" },
                new { name = "Cities", displayName = "المدن", icon = "location_city", category = "Commerce" },
                new { name = "Areas", displayName = "المناطق", icon = "map", category = "Commerce" },
                new { name = "Coupons", displayName = "القسائم", icon = "local_offer", category = "Commerce" },
                
                // System entities
                new { name = "Notifications", displayName = "الإشعارات", icon = "notifications", category = "System" },
                new { name = "Advertisings", displayName = "الإعلانات", icon = "campaign", category = "System" },
                new { name = "AppVersions", displayName = "إصدارات التطبيق", icon = "system_update", category = "System" },
                new { name = "Settings", displayName = "الإعدادات", icon = "settings", category = "System" },
                
                // Company entities
                new { name = "Companies", displayName = "الشركات", icon = "business", category = "Company" },
                
                // Permission entities
                new { name = "PermissionGroups", displayName = "مجموعات الصلاحيات", icon = "security", category = "Permissions" },
                new { name = "Permissions", displayName = "الصلاحيات", icon = "lock", category = "Permissions" },
                new { name = "UserPermissions", displayName = "صلاحيات المستخدمين", icon = "verified_user", category = "Permissions" },
                
                // Service entities
                new { name = "Services", displayName = "الخدمات", icon = "build", category = "Services" },
                new { name = "ServiceRequests", displayName = "طلبات الخدمات", icon = "assignment", category = "Services" },
                
                // Citizen Portal
                new { name = "Citizens", displayName = "المواطنين", icon = "badge", category = "CitizenPortal" },
                new { name = "InternetPlans", displayName = "باقات الإنترنت", icon = "wifi", category = "CitizenPortal" },
                new { name = "CitizenSubscriptions", displayName = "اشتراكات المواطنين", icon = "subscriptions", category = "CitizenPortal" },
                new { name = "SupportTickets", displayName = "تذاكر الدعم", icon = "support_agent", category = "CitizenPortal" },
            };

            return Ok(new { success = true, data = tables });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب قائمة الجداول");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// الحصول على بيانات جدول معين مع دعم الصفحات
    /// </summary>
    [HttpGet("table/{tableName}")]
    public async Task<IActionResult> GetTableData(string tableName, int page = 1, int pageSize = 50, string? search = null)
    {
        try
        {
            object? data = null;
            int totalCount = 0;

            switch (tableName.ToLower())
            {
                case "users":
                    var usersQuery = _context.Users.IgnoreQueryFilters().AsQueryable();
                    if (!string.IsNullOrEmpty(search))
                        usersQuery = usersQuery.Where(x => x.FullName.Contains(search) || x.PhoneNumber.Contains(search) || (x.Email != null && x.Email.Contains(search)));
                    totalCount = await usersQuery.CountAsync();
                    data = await usersQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.FullName, x.PhoneNumber, x.Email, x.Role, x.IsActive, x.IsDeleted, x.CreatedAt, x.LastLoginAt }).ToListAsync();
                    break;

                case "merchants":
                    var merchantsQuery = _context.Merchants.IgnoreQueryFilters().AsQueryable();
                    if (!string.IsNullOrEmpty(search))
                        merchantsQuery = merchantsQuery.Where(x => x.BusinessName.Contains(search));
                    totalCount = await merchantsQuery.CountAsync();
                    data = await merchantsQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.BusinessName, x.PhoneNumber, x.CommissionRate, x.WalletBalance, x.IsActive, x.IsDeleted, x.CreatedAt }).ToListAsync();
                    break;

                case "customers":
                    var customersQuery = _context.Customers.IgnoreQueryFilters().AsQueryable();
                    totalCount = await customersQuery.CountAsync();
                    data = await customersQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.UserId, x.TotalOrders, x.TotalSpent, x.IsDeleted, x.CreatedAt }).ToListAsync();
                    break;

                case "products":
                    var productsQuery = _context.Products.IgnoreQueryFilters().AsQueryable();
                    if (!string.IsNullOrEmpty(search))
                        productsQuery = productsQuery.Where(x => (x.Name != null && x.Name.Contains(search)) || (x.NameAr != null && x.NameAr.Contains(search)));
                    totalCount = await productsQuery.CountAsync();
                    data = await productsQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Name, x.NameAr, x.Price, x.IsActive, x.IsDeleted, x.CreatedAt }).ToListAsync();
                    break;

                case "orders":
                    var ordersQuery = _context.Orders.IgnoreQueryFilters().AsQueryable();
                    totalCount = await ordersQuery.CountAsync();
                    data = await ordersQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.OrderNumber, x.TotalAmount, x.Status, x.PaymentStatus, x.IsDeleted, x.CreatedAt }).ToListAsync();
                    break;

                case "payments":
                    var paymentsQuery = _context.Payments.AsQueryable();
                    totalCount = await paymentsQuery.CountAsync();
                    data = await paymentsQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Amount, x.Status, x.TransactionId, x.CreatedAt }).ToListAsync();
                    break;

                case "categories":
                    var categoriesQuery = _context.Categories.AsQueryable();
                    if (!string.IsNullOrEmpty(search))
                        categoriesQuery = categoriesQuery.Where(x => x.Name.Contains(search) || x.NameAr.Contains(search));
                    totalCount = await categoriesQuery.CountAsync();
                    data = await categoriesQuery.OrderBy(x => x.Name).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Name, x.NameAr, x.IsActive, x.CreatedAt }).ToListAsync();
                    break;

                case "cities":
                    var citiesQuery = _context.Cities.AsQueryable();
                    if (!string.IsNullOrEmpty(search))
                        citiesQuery = citiesQuery.Where(x => x.Name.Contains(search) || x.NameAr.Contains(search));
                    totalCount = await citiesQuery.CountAsync();
                    data = await citiesQuery.OrderBy(x => x.Name).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Name, x.NameAr, x.IsActive, x.DeliveryFee, x.CreatedAt }).ToListAsync();
                    break;

                case "areas":
                    var areasQuery = _context.Areas.Include(x => x.City).AsQueryable();
                    if (!string.IsNullOrEmpty(search))
                        areasQuery = areasQuery.Where(x => x.Name.Contains(search) || x.NameAr.Contains(search));
                    totalCount = await areasQuery.CountAsync();
                    data = await areasQuery.OrderBy(x => x.Name).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Name, x.NameAr, x.IsActive, x.DeliveryFee, CityName = x.City != null ? x.City.Name : null, x.CreatedAt }).ToListAsync();
                    break;

                case "notifications":
                    var notificationsQuery = _context.Notifications.AsQueryable();
                    totalCount = await notificationsQuery.CountAsync();
                    data = await notificationsQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Title, x.Body, x.Type, x.IsRead, x.UserId, x.CreatedAt }).ToListAsync();
                    break;

                case "advertisings":
                    var advertisingsQuery = _context.Advertisings.AsQueryable();
                    totalCount = await advertisingsQuery.CountAsync();
                    data = await advertisingsQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Title, x.IsActive, x.CreatedAt }).ToListAsync();
                    break;

                case "appversions":
                    var appVersionsQuery = _context.AppVersions.AsQueryable();
                    totalCount = await appVersionsQuery.CountAsync();
                    data = await appVersionsQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Version, x.Platform, x.ReleaseNotes, x.CreatedAt }).ToListAsync();
                    break;

                case "settings":
                    var settingsQuery = _context.Settings.AsQueryable();
                    if (!string.IsNullOrEmpty(search))
                        settingsQuery = settingsQuery.Where(x => x.Key.Contains(search));
                    totalCount = await settingsQuery.CountAsync();
                    data = await settingsQuery.OrderBy(x => x.Key).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Key, x.Value, x.Description, x.UpdatedAt }).ToListAsync();
                    break;

                case "companies":
                    var companiesQuery = _context.Companies.AsQueryable();
                    if (!string.IsNullOrEmpty(search))
                        companiesQuery = companiesQuery.Where(x => (x.Name != null && x.Name.Contains(search)) || (x.NameAr != null && x.NameAr.Contains(search)));
                    totalCount = await companiesQuery.CountAsync();
                    data = await companiesQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Name, x.NameAr, x.Phone, x.Email, x.IsActive, x.CreatedAt }).ToListAsync();
                    break;

                case "permissiongroups":
                    var permGroupsQuery = _context.PermissionGroups.AsQueryable();
                    totalCount = await permGroupsQuery.CountAsync();
                    data = await permGroupsQuery.OrderBy(x => x.Name).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Name, x.NameAr, x.Description, x.CreatedAt }).ToListAsync();
                    break;

                case "permissions":
                    var permissionsQuery = _context.Permissions.AsQueryable();
                    totalCount = await permissionsQuery.CountAsync();
                    data = await permissionsQuery.OrderBy(x => x.Name).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Name, x.NameAr, x.Code, x.CreatedAt }).ToListAsync();
                    break;

                case "userpermissions":
                    var userPermsQuery = _context.UserPermissions.AsQueryable();
                    totalCount = await userPermsQuery.CountAsync();
                    data = await userPermsQuery.OrderByDescending(x => x.GrantedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.UserId, x.PermissionId, x.GrantedAt }).ToListAsync();
                    break;

                case "services":
                    var servicesQuery = _context.Services.AsQueryable();
                    if (!string.IsNullOrEmpty(search))
                        servicesQuery = servicesQuery.Where(x => x.Name.Contains(search) || x.NameAr.Contains(search));
                    totalCount = await servicesQuery.CountAsync();
                    data = await servicesQuery.OrderBy(x => x.Name).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Name, x.NameAr, x.IsActive, x.CreatedAt }).ToListAsync();
                    break;

                case "servicerequests":
                    var serviceReqQuery = _context.ServiceRequests.AsQueryable();
                    totalCount = await serviceReqQuery.CountAsync();
                    data = await serviceReqQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.RequestNumber, x.Status, x.Priority, x.CreatedAt }).ToListAsync();
                    break;

                case "citizens":
                    var citizensQuery = _context.Citizens.AsQueryable();
                    if (!string.IsNullOrEmpty(search))
                        citizensQuery = citizensQuery.Where(x => x.FullName.Contains(search) || x.PhoneNumber.Contains(search));
                    totalCount = await citizensQuery.CountAsync();
                    data = await citizensQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.FullName, x.PhoneNumber, x.Email, x.City, x.IsActive, x.CreatedAt }).ToListAsync();
                    break;

                case "internetplans":
                    var plansQuery = _context.InternetPlans.AsQueryable();
                    if (!string.IsNullOrEmpty(search))
                        plansQuery = plansQuery.Where(x => x.Name.Contains(search) || x.NameAr.Contains(search));
                    totalCount = await plansQuery.CountAsync();
                    data = await plansQuery.OrderBy(x => x.Name).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Name, x.NameAr, x.SpeedMbps, x.MonthlyPrice, x.DurationMonths, x.IsActive, x.CreatedAt }).ToListAsync();
                    break;

                case "citizensubscriptions":
                    var subsQuery = _context.CitizenSubscriptions.Include(x => x.Citizen).Include(x => x.Plan).AsQueryable();
                    totalCount = await subsQuery.CountAsync();
                    data = await subsQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.SubscriptionNumber, x.CitizenId, CitizenName = x.Citizen != null ? x.Citizen.FullName : null, PlanName = x.Plan != null ? x.Plan.Name : null, x.Status, x.StartDate, x.EndDate, x.CreatedAt }).ToListAsync();
                    break;

                case "supporttickets":
                    var ticketsQuery = _context.SupportTickets.AsQueryable();
                    totalCount = await ticketsQuery.CountAsync();
                    data = await ticketsQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.TicketNumber, x.Subject, x.Status, x.Priority, x.CitizenId, x.CreatedAt }).ToListAsync();
                    break;

                case "coupons":
                    var couponsQuery = _context.Coupons.AsQueryable();
                    if (!string.IsNullOrEmpty(search))
                        couponsQuery = couponsQuery.Where(x => x.Code.Contains(search));
                    totalCount = await couponsQuery.CountAsync();
                    data = await couponsQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Code, x.DiscountType, x.DiscountValue, x.UsageLimit, x.UsedCount, x.IsActive, x.CreatedAt }).ToListAsync();
                    break;

                default:
                    return NotFound(new { success = false, message = $"الجدول '{tableName}' غير موجود" });
            }

            return Ok(new
            {
                success = true,
                data = data,
                pagination = new
                {
                    page = page,
                    pageSize = pageSize,
                    totalCount = totalCount,
                    totalPages = (int)Math.Ceiling((double)totalCount / pageSize)
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب بيانات الجدول: {TableName}", tableName);
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام: " + ex.Message });
        }
    }

    /// <summary>
    /// الحصول على سجل واحد من جدول معين
    /// </summary>
    [HttpGet("table/{tableName}/{id}")]
    public async Task<IActionResult> GetRecord(string tableName, string id)
    {
        try
        {
            if (!Guid.TryParse(id, out var guidId))
            {
                return BadRequest(new { success = false, message = "معرف غير صالح" });
            }

            object? data = null;

            switch (tableName.ToLower())
            {
                case "users":
                    data = await _context.Users.IgnoreQueryFilters().FirstOrDefaultAsync(x => x.Id == guidId);
                    break;
                case "companies":
                    data = await _context.Companies.FirstOrDefaultAsync(x => x.Id == guidId);
                    break;
                case "cities":
                    data = await _context.Cities.FirstOrDefaultAsync(x => x.Id == guidId);
                    break;
                case "areas":
                    data = await _context.Areas.Include(x => x.City).FirstOrDefaultAsync(x => x.Id == guidId);
                    break;
                case "categories":
                    data = await _context.Categories.FirstOrDefaultAsync(x => x.Id == guidId);
                    break;
                case "internetplans":
                    data = await _context.InternetPlans.FirstOrDefaultAsync(x => x.Id == guidId);
                    break;
                default:
                    return NotFound(new { success = false, message = $"الجدول '{tableName}' غير مدعوم للعرض الفردي" });
            }

            if (data == null)
                return NotFound(new { success = false, message = "السجل غير موجود" });

            return Ok(new { success = true, data = data });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب السجل من الجدول: {TableName}", tableName);
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// تحديث سجل في جدول معين
    /// </summary>
    [HttpPut("table/{tableName}/{id}")]
    public async Task<IActionResult> UpdateRecord(string tableName, string id, [FromBody] JsonElement data)
    {
        try
        {
            if (!Guid.TryParse(id, out var guidId))
            {
                return BadRequest(new { success = false, message = "معرف غير صالح" });
            }

            switch (tableName.ToLower())
            {
                case "users":
                    var user = await _context.Users.IgnoreQueryFilters().FirstOrDefaultAsync(x => x.Id == guidId);
                    if (user == null) return NotFound(new { success = false, message = "المستخدم غير موجود" });
                    
                    // دعم كلا الصيغتين: camelCase و PascalCase
                    if (data.TryGetProperty("fullName", out var fullName)) user.FullName = fullName.GetString()!;
                    else if (data.TryGetProperty("FullName", out var fullName2)) user.FullName = fullName2.GetString()!;
                    
                    if (data.TryGetProperty("email", out var email)) user.Email = email.GetString();
                    else if (data.TryGetProperty("Email", out var email2)) user.Email = email2.GetString();
                    
                    if (data.TryGetProperty("phoneNumber", out var phone)) user.PhoneNumber = phone.GetString()!;
                    else if (data.TryGetProperty("PhoneNumber", out var phone2)) user.PhoneNumber = phone2.GetString()!;
                    
                    if (data.TryGetProperty("isActive", out var isActive)) user.IsActive = isActive.GetBoolean();
                    else if (data.TryGetProperty("IsActive", out var isActive2)) user.IsActive = isActive2.GetBoolean();
                    
                    if (data.TryGetProperty("isDeleted", out var isDeleted)) user.IsDeleted = isDeleted.GetBoolean();
                    else if (data.TryGetProperty("IsDeleted", out var isDeleted2)) user.IsDeleted = isDeleted2.GetBoolean();
                    
                    user.UpdatedAt = DateTime.UtcNow;
                    _context.Users.Update(user);
                    break;

                case "cities":
                    var city = await _context.Cities.FirstOrDefaultAsync(x => x.Id == guidId);
                    if (city == null) return NotFound(new { success = false, message = "المدينة غير موجودة" });
                    
                    // دعم كلا الصيغتين
                    if (data.TryGetProperty("name", out var cityName)) city.Name = cityName.GetString()!;
                    else if (data.TryGetProperty("Name", out var cityName2)) city.Name = cityName2.GetString()!;
                    
                    if (data.TryGetProperty("nameAr", out var cityNameAr)) city.NameAr = cityNameAr.GetString()!;
                    else if (data.TryGetProperty("NameAr", out var cityNameAr2)) city.NameAr = cityNameAr2.GetString()!;
                    
                    if (data.TryGetProperty("isActive", out var cityIsActive)) city.IsActive = cityIsActive.GetBoolean();
                    else if (data.TryGetProperty("IsActive", out var cityIsActive2)) city.IsActive = cityIsActive2.GetBoolean();
                    
                    if (data.TryGetProperty("deliveryFee", out var deliveryFee)) city.DeliveryFee = deliveryFee.GetDecimal();
                    else if (data.TryGetProperty("DeliveryFee", out var deliveryFee2)) city.DeliveryFee = deliveryFee2.GetDecimal();
                    
                    city.UpdatedAt = DateTime.UtcNow;
                    _context.Cities.Update(city);
                    break;

                case "areas":
                    var area = await _context.Areas.FirstOrDefaultAsync(x => x.Id == guidId);
                    if (area == null) return NotFound(new { success = false, message = "المنطقة غير موجودة" });
                    
                    // دعم كلا الصيغتين
                    if (data.TryGetProperty("name", out var areaName)) area.Name = areaName.GetString()!;
                    else if (data.TryGetProperty("Name", out var areaName2)) area.Name = areaName2.GetString()!;
                    
                    if (data.TryGetProperty("nameAr", out var areaNameAr)) area.NameAr = areaNameAr.GetString()!;
                    else if (data.TryGetProperty("NameAr", out var areaNameAr2)) area.NameAr = areaNameAr2.GetString()!;
                    
                    if (data.TryGetProperty("isActive", out var areaIsActive)) area.IsActive = areaIsActive.GetBoolean();
                    else if (data.TryGetProperty("IsActive", out var areaIsActive2)) area.IsActive = areaIsActive2.GetBoolean();
                    
                    if (data.TryGetProperty("deliveryFee", out var areaDeliveryFee)) area.DeliveryFee = areaDeliveryFee.GetDecimal();
                    else if (data.TryGetProperty("DeliveryFee", out var areaDeliveryFee2)) area.DeliveryFee = areaDeliveryFee2.GetDecimal();
                    
                    area.UpdatedAt = DateTime.UtcNow;
                    _context.Areas.Update(area);
                    break;

                case "companies":
                    var company = await _context.Companies.FirstOrDefaultAsync(x => x.Id == guidId);
                    if (company == null) return NotFound(new { success = false, message = "الشركة غير موجودة" });
                    
                    // دعم كلا الصيغتين
                    if (data.TryGetProperty("name", out var compName)) company.Name = compName.GetString()!;
                    else if (data.TryGetProperty("Name", out var compName2)) company.Name = compName2.GetString()!;
                    
                    if (data.TryGetProperty("nameAr", out var compNameAr)) company.NameAr = compNameAr.GetString()!;
                    else if (data.TryGetProperty("NameAr", out var compNameAr2)) company.NameAr = compNameAr2.GetString()!;
                    
                    if (data.TryGetProperty("phone", out var compPhone)) company.Phone = compPhone.GetString();
                    else if (data.TryGetProperty("Phone", out var compPhone2)) company.Phone = compPhone2.GetString();
                    
                    if (data.TryGetProperty("email", out var compEmail)) company.Email = compEmail.GetString();
                    else if (data.TryGetProperty("Email", out var compEmail2)) company.Email = compEmail2.GetString();
                    
                    if (data.TryGetProperty("isActive", out var compIsActive)) company.IsActive = compIsActive.GetBoolean();
                    else if (data.TryGetProperty("IsActive", out var compIsActive2)) company.IsActive = compIsActive2.GetBoolean();
                    
                    company.UpdatedAt = DateTime.UtcNow;
                    _context.Companies.Update(company);
                    break;

                default:
                    return BadRequest(new { success = false, message = $"تحديث الجدول '{tableName}' غير مدعوم حالياً" });
            }

            await _context.SaveChangesAsync();
            _logger.LogInformation("تم تحديث سجل في الجدول {TableName} بواسطة المسؤول", tableName);

            return Ok(new { success = true, message = "تم التحديث بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تحديث السجل في الجدول: {TableName}", tableName);
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// حذف سجل من جدول معين (Soft Delete للجداول التي تدعمه)
    /// </summary>
    [HttpDelete("table/{tableName}/{id}")]
    public async Task<IActionResult> DeleteRecord(string tableName, string id, [FromQuery] bool hardDelete = false)
    {
        try
        {
            if (!Guid.TryParse(id, out var guidId))
            {
                return BadRequest(new { success = false, message = "معرف غير صالح" });
            }

            switch (tableName.ToLower())
            {
                case "users":
                    var user = await _context.Users.IgnoreQueryFilters().FirstOrDefaultAsync(x => x.Id == guidId);
                    if (user == null) return NotFound(new { success = false, message = "المستخدم غير موجود" });
                    
                    if (hardDelete)
                        _context.Users.Remove(user);
                    else
                    {
                        user.IsDeleted = true;
                        user.UpdatedAt = DateTime.UtcNow;
                    }
                    break;

                case "cities":
                    var city = await _context.Cities.FirstOrDefaultAsync(x => x.Id == guidId);
                    if (city == null) return NotFound(new { success = false, message = "المدينة غير موجودة" });
                    _context.Cities.Remove(city);
                    break;

                case "areas":
                    var area = await _context.Areas.FirstOrDefaultAsync(x => x.Id == guidId);
                    if (area == null) return NotFound(new { success = false, message = "المنطقة غير موجودة" });
                    _context.Areas.Remove(area);
                    break;

                case "categories":
                    var category = await _context.Categories.FirstOrDefaultAsync(x => x.Id == guidId);
                    if (category == null) return NotFound(new { success = false, message = "التصنيف غير موجود" });
                    _context.Categories.Remove(category);
                    break;

                default:
                    return BadRequest(new { success = false, message = $"حذف من الجدول '{tableName}' غير مدعوم حالياً" });
            }

            await _context.SaveChangesAsync();
            _logger.LogWarning("تم حذف سجل من الجدول {TableName} بواسطة المسؤول (hardDelete: {HardDelete})", tableName, hardDelete);

            return Ok(new { success = true, message = "تم الحذف بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف السجل من الجدول: {TableName}", tableName);
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }

    /// <summary>
    /// الحصول على إحصائيات قاعدة البيانات
    /// </summary>
    [HttpGet("stats")]
    public async Task<IActionResult> GetDatabaseStats()
    {
        try
        {
            var stats = new
            {
                users = await _context.Users.IgnoreQueryFilters().CountAsync(),
                activeUsers = await _context.Users.CountAsync(),
                merchants = await _context.Merchants.IgnoreQueryFilters().CountAsync(),
                customers = await _context.Customers.IgnoreQueryFilters().CountAsync(),
                products = await _context.Products.IgnoreQueryFilters().CountAsync(),
                orders = await _context.Orders.IgnoreQueryFilters().CountAsync(),
                companies = await _context.Companies.CountAsync(),
                cities = await _context.Cities.CountAsync(),
                areas = await _context.Areas.CountAsync(),
                citizens = await _context.Citizens.CountAsync(),
                internetPlans = await _context.InternetPlans.CountAsync(),
                subscriptions = await _context.CitizenSubscriptions.CountAsync(),
                supportTickets = await _context.SupportTickets.CountAsync(),
            };

            return Ok(new { success = true, data = stats });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب إحصائيات قاعدة البيانات");
            return StatusCode(500, new { success = false, message = "حدث خطأ في النظام" });
        }
    }
}
