using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using Sadara.Infrastructure.Data;
using System.Text.Json;
using ClosedXML.Excel;

namespace Sadara.API.Controllers;

/// <summary>
/// فلتر للتحقق من API Key أو JWT Token
/// يقرأ API Key من الإعدادات (Security:InternalApiKey) أو Environment Variable
/// </summary>
public class ApiKeyOrJwtAuthAttribute : Attribute, IAuthorizationFilter
{
    private const string ApiKeyHeader = "X-Api-Key";

    public void OnAuthorization(AuthorizationFilterContext context)
    {
        // قراءة API Key من الإعدادات أو Environment Variable
        var configuration = context.HttpContext.RequestServices.GetService<IConfiguration>();
        var validApiKey = configuration?["Security:InternalApiKey"] 
            ?? Environment.GetEnvironmentVariable("SADARA_INTERNAL_API_KEY")
            ?? "sadara-internal-2024-secure-key"; // fallback للتطوير فقط

        // تحقق من API Key أولاً
        if (context.HttpContext.Request.Headers.TryGetValue(ApiKeyHeader, out var apiKey))
        {
            if (apiKey == validApiKey)
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
                // Core (9)
                new { name = "Users", displayName = "المستخدمين", icon = "person", category = "Core" },
                new { name = "Merchants", displayName = "التجار", icon = "store", category = "Core" },
                new { name = "Customers", displayName = "العملاء", icon = "people", category = "Core" },
                new { name = "Products", displayName = "المنتجات", icon = "inventory", category = "Core" },
                new { name = "ProductVariants", displayName = "متغيرات المنتجات", icon = "style", category = "Core" },
                new { name = "Orders", displayName = "الطلبات", icon = "shopping_cart", category = "Core" },
                new { name = "OrderItems", displayName = "عناصر الطلبات", icon = "list", category = "Core" },
                new { name = "OrderStatusHistories", displayName = "سجل حالة الطلبات", icon = "history", category = "Core" },
                new { name = "Payments", displayName = "المدفوعات", icon = "payment", category = "Core" },

                // Commerce (8)
                new { name = "Categories", displayName = "التصنيفات", icon = "category", category = "Commerce" },
                new { name = "Cities", displayName = "المدن", icon = "location_city", category = "Commerce" },
                new { name = "Areas", displayName = "المناطق", icon = "map", category = "Commerce" },
                new { name = "Reviews", displayName = "التقييمات", icon = "star", category = "Commerce" },
                new { name = "WishlistItems", displayName = "قائمة الرغبات", icon = "favorite", category = "Commerce" },
                new { name = "CartItems", displayName = "عناصر السلة", icon = "shopping_basket", category = "Commerce" },
                new { name = "Addresses", displayName = "العناوين", icon = "home", category = "Commerce" },
                new { name = "Coupons", displayName = "القسائم", icon = "local_offer", category = "Commerce" },

                // System (4)
                new { name = "Notifications", displayName = "الإشعارات", icon = "notifications", category = "System" },
                new { name = "Advertisings", displayName = "الإعلانات", icon = "campaign", category = "System" },
                new { name = "AppVersions", displayName = "إصدارات التطبيق", icon = "system_update", category = "System" },
                new { name = "Settings", displayName = "الإعدادات", icon = "settings", category = "System" },

                // Company (2)
                new { name = "Companies", displayName = "الشركات", icon = "business", category = "Company" },
                new { name = "CompanyServices", displayName = "خدمات الشركات", icon = "business_center", category = "Company" },

                // Permissions (5)
                new { name = "PermissionGroups", displayName = "مجموعات الصلاحيات", icon = "security", category = "Permissions" },
                new { name = "Permissions", displayName = "الصلاحيات", icon = "lock", category = "Permissions" },
                new { name = "UserPermissions", displayName = "صلاحيات المستخدمين", icon = "verified_user", category = "Permissions" },
                new { name = "PermissionTemplates", displayName = "قوالب الصلاحيات", icon = "content_copy", category = "Permissions" },
                new { name = "TemplatePermissions", displayName = "صلاحيات القوالب", icon = "checklist", category = "Permissions" },

                // Services (7)
                new { name = "Services", displayName = "الخدمات", icon = "build", category = "Services" },
                new { name = "OperationTypes", displayName = "أنواع العمليات", icon = "tune", category = "Services" },
                new { name = "ServiceOperations", displayName = "عمليات الخدمة", icon = "engineering", category = "Services" },
                new { name = "ServiceRequests", displayName = "طلبات الخدمات", icon = "assignment", category = "Services" },
                new { name = "ServiceRequestComments", displayName = "تعليقات الطلبات", icon = "comment", category = "Services" },
                new { name = "ServiceRequestAttachments", displayName = "مرفقات الطلبات", icon = "attach_file", category = "Services" },
                new { name = "ServiceRequestStatusHistories", displayName = "سجل حالة الطلبات", icon = "timeline", category = "Services" },

                // CitizenPortal (10)
                new { name = "Citizens", displayName = "المواطنين", icon = "badge", category = "CitizenPortal" },
                new { name = "InternetPlans", displayName = "باقات الإنترنت", icon = "wifi", category = "CitizenPortal" },
                new { name = "CitizenSubscriptions", displayName = "اشتراكات المواطنين", icon = "subscriptions", category = "CitizenPortal" },
                new { name = "SupportTickets", displayName = "تذاكر الدعم", icon = "support_agent", category = "CitizenPortal" },
                new { name = "TicketMessages", displayName = "رسائل التذاكر", icon = "message", category = "CitizenPortal" },
                new { name = "CitizenPayments", displayName = "مدفوعات المواطنين", icon = "account_balance_wallet", category = "CitizenPortal" },
                new { name = "StoreProducts", displayName = "منتجات المتجر", icon = "shopping_bag", category = "CitizenPortal" },
                new { name = "ProductCategories", displayName = "تصنيفات المنتجات", icon = "folder", category = "CitizenPortal" },
                new { name = "StoreOrders", displayName = "طلبات المتجر", icon = "receipt_long", category = "CitizenPortal" },
                new { name = "StoreOrderItems", displayName = "عناصر الطلبات", icon = "list_alt", category = "CitizenPortal" },

                // Subscriptions (1)
                new { name = "SubscriptionLogs", displayName = "سجلات الاشتراكات", icon = "receipt", category = "Subscriptions" },

                // Agents (3)
                new { name = "Agents", displayName = "الوكلاء", icon = "support_agent", category = "Agents" },
                new { name = "AgentTransactions", displayName = "معاملات الوكلاء", icon = "swap_horiz", category = "Agents" },
                new { name = "AgentCommissionRates", displayName = "عمولات الوكلاء", icon = "percent", category = "Agents" },

                // Attendance (4)
                new { name = "AttendanceRecords", displayName = "سجلات الحضور", icon = "fingerprint", category = "Attendance" },
                new { name = "WorkCenters", displayName = "مراكز العمل", icon = "location_on", category = "Attendance" },
                new { name = "AttendanceAuditLogs", displayName = "سجل تدقيق الحضور", icon = "fact_check", category = "Attendance" },
                new { name = "WorkSchedules", displayName = "جداول العمل", icon = "schedule", category = "Attendance" },

                // Leave (3)
                new { name = "LeaveRequests", displayName = "طلبات الإجازة", icon = "event_busy", category = "Leave" },
                new { name = "WithdrawalRequests", displayName = "طلبات السحب", icon = "money_off", category = "Leave" },
                new { name = "LeaveBalances", displayName = "أرصدة الإجازات", icon = "event_available", category = "Leave" },

                // ISP (3)
                new { name = "ISPSubscribers", displayName = "مشتركي الإنترنت", icon = "router", category = "ISP" },
                new { name = "IptvSubscribers", displayName = "مشتركي IPTV", icon = "tv", category = "ISP" },
                new { name = "ZoneStatistics", displayName = "إحصائيات المناطق", icon = "analytics", category = "ISP" },

                // Accounting (13)
                new { name = "Accounts", displayName = "الحسابات", icon = "account_balance", category = "Accounting" },
                new { name = "JournalEntries", displayName = "القيود المحاسبية", icon = "book", category = "Accounting" },
                new { name = "JournalEntryLines", displayName = "بنود القيود", icon = "format_list_numbered", category = "Accounting" },
                new { name = "CashBoxes", displayName = "الصناديق", icon = "savings", category = "Accounting" },
                new { name = "CashTransactions", displayName = "حركات الصندوق", icon = "swap_vert", category = "Accounting" },
                new { name = "EmployeeSalaries", displayName = "رواتب الموظفين", icon = "payments", category = "Accounting" },
                new { name = "SalaryPolicies", displayName = "سياسات الرواتب", icon = "policy", category = "Accounting" },
                new { name = "TechnicianCollections", displayName = "تحصيلات الفنيين", icon = "collections", category = "Accounting" },
                new { name = "TechnicianTransactions", displayName = "معاملات الفنيين", icon = "sync_alt", category = "Accounting" },
                new { name = "Expenses", displayName = "المصاريف", icon = "receipt_long", category = "Accounting" },
                new { name = "EmployeeDeductionBonuses", displayName = "خصومات ومكافآت", icon = "price_change", category = "Accounting" },
                new { name = "FixedExpenses", displayName = "المصاريف الثابتة", icon = "event_repeat", category = "Accounting" },
                new { name = "FixedExpensePayments", displayName = "دفعات المصاريف", icon = "paid", category = "Accounting" },

                // Tasks (1)
                new { name = "TaskAudits", displayName = "تدقيق المهام", icon = "task_alt", category = "Tasks" },

                // Departments (3)
                new { name = "Departments", displayName = "الأقسام", icon = "corporate_fare", category = "Departments" },
                new { name = "DepartmentTasks", displayName = "مهام الأقسام", icon = "assignment_turned_in", category = "Departments" },
                new { name = "UserDepartments", displayName = "أقسام المستخدمين", icon = "group_work", category = "Departments" },

                // FCM (1)
                new { name = "UserFcmTokens", displayName = "رموز الإشعارات", icon = "key", category = "FCM" },

                // Settlement (1)
                new { name = "DailySettlementReports", displayName = "تقارير التسوية", icon = "summarize", category = "Settlement" },

                // WhatsApp (3)
                new { name = "WhatsAppConversations", displayName = "محادثات واتساب", icon = "chat", category = "WhatsApp" },
                new { name = "WhatsAppMessages", displayName = "رسائل واتساب", icon = "sms", category = "WhatsApp" },
                new { name = "WhatsAppBatchReports", displayName = "تقارير الإرسال", icon = "send", category = "WhatsApp" },

                // Location (2)
                new { name = "EmployeeLocations", displayName = "مواقع الموظفين", icon = "location_on", category = "Location" },
                new { name = "EmployeeLocationLogs", displayName = "سجل المواقع", icon = "share_location", category = "Location" },

                // Reminders (2)
                new { name = "ReminderSettings", displayName = "إعدادات التذكيرات", icon = "alarm", category = "Reminders" },
                new { name = "ReminderExecutionLogs", displayName = "سجل التذكيرات", icon = "notification_important", category = "Reminders" },

                // Chat (7)
                new { name = "ChatRooms", displayName = "غرف المحادثة", icon = "forum", category = "Chat" },
                new { name = "ChatRoomMembers", displayName = "أعضاء الغرف", icon = "group", category = "Chat" },
                new { name = "ChatMessages", displayName = "الرسائل", icon = "chat_bubble", category = "Chat" },
                new { name = "ChatAttachments", displayName = "المرفقات", icon = "attachment", category = "Chat" },
                new { name = "ChatMentions", displayName = "الإشارات", icon = "alternate_email", category = "Chat" },
                new { name = "ChatMessageReads", displayName = "قراءة الرسائل", icon = "done_all", category = "Chat" },
                new { name = "ChatReactions", displayName = "التفاعلات", icon = "add_reaction", category = "Chat" },

                // Announcements (3)
                new { name = "Announcements", displayName = "الإعلانات الداخلية", icon = "campaign", category = "Announcements" },
                new { name = "AnnouncementTargets", displayName = "أهداف الإعلانات", icon = "target", category = "Announcements" },
                new { name = "AnnouncementReads", displayName = "قراءات الإعلانات", icon = "visibility", category = "Announcements" },

                // FTTH (3)
                new { name = "CompanyFtthSettings", displayName = "إعدادات FTTH", icon = "settings_ethernet", category = "FTTH" },
                new { name = "FtthSubscriberCaches", displayName = "كاش المشتركين", icon = "cached", category = "FTTH" },
                new { name = "FtthSyncLogs", displayName = "سجلات المزامنة", icon = "sync", category = "FTTH" },

                // Inventory (13)
                new { name = "Warehouses", displayName = "المستودعات", icon = "warehouse", category = "Inventory" },
                new { name = "InventoryCategories", displayName = "تصنيفات المواد", icon = "category", category = "Inventory" },
                new { name = "InventoryItems", displayName = "المواد المخزنية", icon = "inventory_2", category = "Inventory" },
                new { name = "Suppliers", displayName = "الموردون", icon = "local_shipping", category = "Inventory" },
                new { name = "PurchaseOrders", displayName = "أوامر الشراء", icon = "add_shopping_cart", category = "Inventory" },
                new { name = "PurchaseOrderItems", displayName = "بنود الشراء", icon = "format_list_bulleted", category = "Inventory" },
                new { name = "SalesOrders", displayName = "عمليات البيع", icon = "point_of_sale", category = "Inventory" },
                new { name = "SalesOrderItems", displayName = "بنود البيع", icon = "format_list_numbered", category = "Inventory" },
                new { name = "TechnicianDispensings", displayName = "صرف مواد للفنيين", icon = "handyman", category = "Inventory" },
                new { name = "TechnicianDispensingItems", displayName = "بنود الصرف", icon = "build_circle", category = "Inventory" },
                new { name = "StockMovements", displayName = "حركات المخزن", icon = "swap_horiz", category = "Inventory" },
                new { name = "WarehouseStocks", displayName = "أرصدة المخزون", icon = "inventory", category = "Inventory" },
                new { name = "ZoneMaintenanceFees", displayName = "رسوم صيانة المناطق", icon = "home_repair_service", category = "Inventory" },
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

                case "ticketmessages":
                    var messagesQuery = _context.TicketMessages.AsQueryable();
                    totalCount = await messagesQuery.CountAsync();
                    data = await messagesQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.TicketId, x.Content, x.UserId, x.CitizenId, x.IsRead, x.CreatedAt }).ToListAsync();
                    break;

                case "citizenpayments":
                    var citizenPaymentsQuery = _context.CitizenPayments.AsQueryable();
                    totalCount = await citizenPaymentsQuery.CountAsync();
                    data = await citizenPaymentsQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.CitizenId, x.Amount, x.Method, x.Status, x.ExternalTransactionId, x.TransactionNumber, x.CreatedAt }).ToListAsync();
                    break;

                case "productcategories":
                    var prodCatsQuery = _context.ProductCategories.AsQueryable();
                    if (!string.IsNullOrEmpty(search))
                        prodCatsQuery = prodCatsQuery.Where(x => x.Name.Contains(search) || x.NameAr.Contains(search));
                    totalCount = await prodCatsQuery.CountAsync();
                    data = await prodCatsQuery.OrderBy(x => x.Name).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Name, x.NameAr, x.IsActive, x.CreatedAt }).ToListAsync();
                    break;

                case "storeproducts":
                    var storeProductsQuery = _context.StoreProducts.AsQueryable();
                    if (!string.IsNullOrEmpty(search))
                        storeProductsQuery = storeProductsQuery.Where(x => x.Name.Contains(search) || x.NameAr.Contains(search));
                    totalCount = await storeProductsQuery.CountAsync();
                    data = await storeProductsQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.Name, x.NameAr, x.Price, x.StockQuantity, x.IsActive, x.CreatedAt }).ToListAsync();
                    break;

                case "storeorders":
                    var storeOrdersQuery = _context.StoreOrders.AsQueryable();
                    totalCount = await storeOrdersQuery.CountAsync();
                    data = await storeOrdersQuery.OrderByDescending(x => x.CreatedAt).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.OrderNumber, x.CitizenId, x.TotalAmount, x.Status, x.PaymentStatus, x.CreatedAt }).ToListAsync();
                    break;

                case "storeorderitems":
                    var storeItemsQuery = _context.StoreOrderItems.AsQueryable();
                    totalCount = await storeItemsQuery.CountAsync();
                    data = await storeItemsQuery.OrderByDescending(x => x.Id).Skip((page - 1) * pageSize).Take(pageSize)
                        .Select(x => new { x.Id, x.StoreOrderId, x.ProductId, x.Quantity, x.UnitPrice, x.TotalPrice }).ToListAsync();
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

    // ═══════════════════════════════════════════════════════════════
    // Generic Dynamic Endpoints — يعمل مع أي جدول تلقائياً
    // ═══════════════════════════════════════════════════════════════

    /// <summary>
    /// قراءة بيانات أي جدول ديناميكياً
    /// </summary>
    [HttpGet("generic/{tableName}")]
    public async Task<IActionResult> GetGenericTableData(string tableName, int page = 1, int pageSize = 50, string? search = null, string? sortBy = null, string? sortDir = "desc")
    {
        try
        {
            var entityType = _context.Model.GetEntityTypes()
                .FirstOrDefault(e =>
                    e.GetTableName()?.Equals(tableName, StringComparison.OrdinalIgnoreCase) == true ||
                    e.ClrType.Name.Equals(tableName, StringComparison.OrdinalIgnoreCase) == true);

            if (entityType == null)
                return NotFound(new { success = false, message = $"الجدول '{tableName}' غير موجود" });

            var actualTableName = entityType.GetTableName() ?? tableName;
            var schema = entityType.GetSchema();
            var fullTableName = schema != null ? $"\"{schema}\".\"{actualTableName}\"" : $"\"{actualTableName}\"";

            var properties = entityType.GetProperties().ToList();
            var columns = properties.Select(p => new {
                name = p.GetColumnName(),
                clrName = p.Name,
                type = p.ClrType.Name,
                isNullable = p.IsNullable,
                isPrimaryKey = p.IsPrimaryKey()
            }).ToList();

            var conn = _context.Database.GetDbConnection();
            if (conn.State != System.Data.ConnectionState.Open)
                await conn.OpenAsync();

            using var countCmd = conn.CreateCommand();
            countCmd.CommandText = $"SELECT COUNT(*) FROM {fullTableName}";
            var totalCount = Convert.ToInt32(await countCmd.ExecuteScalarAsync());

            var sortColumn = "\"Id\"";
            if (!string.IsNullOrEmpty(sortBy))
            {
                var matchProp = properties.FirstOrDefault(p =>
                    p.Name.Equals(sortBy, StringComparison.OrdinalIgnoreCase) ||
                    p.GetColumnName().Equals(sortBy, StringComparison.OrdinalIgnoreCase));
                if (matchProp != null) sortColumn = $"\"{matchProp.GetColumnName()}\"";
            }
            else
            {
                var createdAt = properties.FirstOrDefault(p => p.Name == "CreatedAt");
                if (createdAt != null) sortColumn = $"\"{createdAt.GetColumnName()}\"";
            }

            var direction = sortDir?.ToLower() == "asc" ? "ASC" : "DESC";
            var offset = (page - 1) * pageSize;

            using var cmd = conn.CreateCommand();
            cmd.CommandText = $"SELECT * FROM {fullTableName} ORDER BY {sortColumn} {direction} LIMIT {pageSize} OFFSET {offset}";

            var items = new List<Dictionary<string, object?>>();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                var row = new Dictionary<string, object?>();
                for (int i = 0; i < reader.FieldCount; i++)
                {
                    row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                }
                items.Add(row);
            }

            return Ok(new { success = true, tableName = actualTableName, columns, data = items,
                pagination = new { page, pageSize, totalCount, totalPages = (int)Math.Ceiling((double)totalCount / pageSize) } });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب بيانات الجدول: {TableName}", tableName);
            return StatusCode(500, new { success = false, message = "حدث خطأ: " + ex.Message });
        }
    }

    /// <summary>
    /// حذف سجل من أي جدول ديناميكياً
    /// </summary>
    [HttpDelete("generic/{tableName}/{id}")]
    public async Task<IActionResult> DeleteGenericRecord(string tableName, string id)
    {
        try
        {
            var entityType = _context.Model.GetEntityTypes()
                .FirstOrDefault(e =>
                    e.GetTableName()?.Equals(tableName, StringComparison.OrdinalIgnoreCase) == true ||
                    e.ClrType.Name.Equals(tableName, StringComparison.OrdinalIgnoreCase) == true);

            if (entityType == null)
                return NotFound(new { success = false, message = $"الجدول '{tableName}' غير موجود" });

            var actualTableName = entityType.GetTableName() ?? tableName;
            var schema = entityType.GetSchema();
            var fullTableName = schema != null ? $"\"{schema}\".\"{actualTableName}\"" : $"\"{actualTableName}\"";
            var pk = entityType.FindPrimaryKey()?.Properties.FirstOrDefault();
            var pkColumn = pk?.GetColumnName() ?? "Id";

            var conn = _context.Database.GetDbConnection();
            if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync();

            using var cmd = conn.CreateCommand();
            cmd.CommandText = $"DELETE FROM {fullTableName} WHERE \"{pkColumn}\" = @id";
            var param = cmd.CreateParameter();
            param.ParameterName = "id";
            param.Value = Guid.TryParse(id, out var gid) ? gid : int.TryParse(id, out var iid) ? (object)iid : id;
            cmd.Parameters.Add(param);

            var affected = await cmd.ExecuteNonQueryAsync();
            if (affected == 0) return NotFound(new { success = false, message = "السجل غير موجود" });

            _logger.LogWarning("حذف سجل من {Table} (ID: {Id})", tableName, id);
            return Ok(new { success = true, message = "تم الحذف بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في حذف سجل من {TableName}", tableName);
            return StatusCode(500, new { success = false, message = "حدث خطأ: " + ex.Message });
        }
    }

    /// <summary>
    /// تحديث سجل في أي جدول ديناميكياً
    /// </summary>
    [HttpPut("generic/{tableName}/{id}")]
    public async Task<IActionResult> UpdateGenericRecord(string tableName, string id, [FromBody] JsonElement data)
    {
        try
        {
            var entityType = _context.Model.GetEntityTypes()
                .FirstOrDefault(e =>
                    e.GetTableName()?.Equals(tableName, StringComparison.OrdinalIgnoreCase) == true ||
                    e.ClrType.Name.Equals(tableName, StringComparison.OrdinalIgnoreCase) == true);

            if (entityType == null)
                return NotFound(new { success = false, message = $"الجدول '{tableName}' غير موجود" });

            var actualTableName = entityType.GetTableName() ?? tableName;
            var schema = entityType.GetSchema();
            var fullTableName = schema != null ? $"\"{schema}\".\"{actualTableName}\"" : $"\"{actualTableName}\"";
            var pk = entityType.FindPrimaryKey()?.Properties.FirstOrDefault();
            var pkColumn = pk?.GetColumnName() ?? "Id";

            var properties = entityType.GetProperties().Where(p => !p.IsPrimaryKey()).ToList();
            var setClauses = new List<string>();
            var parameters = new List<System.Data.Common.DbParameter>();

            var conn = _context.Database.GetDbConnection();
            if (conn.State != System.Data.ConnectionState.Open) await conn.OpenAsync();

            int pi = 0;
            foreach (var prop in properties)
            {
                var colName = prop.GetColumnName();
                var camelName = char.ToLower(prop.Name[0]) + prop.Name.Substring(1);

                JsonElement value;
                if (data.TryGetProperty(prop.Name, out value) || data.TryGetProperty(camelName, out value) || data.TryGetProperty(colName, out value))
                {
                    setClauses.Add($"\"{colName}\" = @p{pi}");
                    var p = conn.CreateCommand().CreateParameter();
                    p.ParameterName = $"p{pi}";
                    p.Value = _ConvertJson(value, prop.ClrType) ?? DBNull.Value;
                    parameters.Add(p);
                    pi++;
                }
            }

            if (setClauses.Count == 0) return BadRequest(new { success = false, message = "لا توجد حقول للتحديث" });

            using var cmd = conn.CreateCommand();
            cmd.CommandText = $"UPDATE {fullTableName} SET {string.Join(", ", setClauses)} WHERE \"{pkColumn}\" = @id";
            var idParam = cmd.CreateParameter();
            idParam.ParameterName = "id";
            idParam.Value = Guid.TryParse(id, out var gid2) ? gid2 : int.TryParse(id, out var iid2) ? (object)iid2 : id;
            cmd.Parameters.Add(idParam);
            foreach (var p in parameters) cmd.Parameters.Add(p);

            var affected = await cmd.ExecuteNonQueryAsync();
            if (affected == 0) return NotFound(new { success = false, message = "السجل غير موجود" });

            _logger.LogInformation("تحديث سجل في {Table} (ID: {Id})", tableName, id);
            return Ok(new { success = true, message = "تم التحديث بنجاح" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تحديث سجل في {TableName}", tableName);
            return StatusCode(500, new { success = false, message = "حدث خطأ: " + ex.Message });
        }
    }

    private static object? _ConvertJson(JsonElement el, Type t)
    {
        if (el.ValueKind == JsonValueKind.Null) return null;
        var bt = Nullable.GetUnderlyingType(t) ?? t;
        if (bt == typeof(string)) return el.GetString();
        if (bt == typeof(int)) return el.GetInt32();
        if (bt == typeof(long)) return el.GetInt64();
        if (bt == typeof(decimal)) return el.GetDecimal();
        if (bt == typeof(double)) return el.GetDouble();
        if (bt == typeof(bool)) return el.GetBoolean();
        if (bt == typeof(DateTime)) return el.GetDateTime();
        if (bt == typeof(Guid)) return el.GetGuid();
        if (bt.IsEnum) return Enum.Parse(bt, el.GetString() ?? "0");
        return el.GetString();
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

                case "categories":
                    var category = await _context.Categories.FirstOrDefaultAsync(x => x.Id == guidId);
                    if (category == null) return NotFound(new { success = false, message = "التصنيف غير موجود" });
                    
                    if (data.TryGetProperty("name", out var catName)) category.Name = catName.GetString()!;
                    else if (data.TryGetProperty("Name", out var catName2)) category.Name = catName2.GetString()!;
                    
                    if (data.TryGetProperty("nameAr", out var catNameAr)) category.NameAr = catNameAr.GetString()!;
                    else if (data.TryGetProperty("NameAr", out var catNameAr2)) category.NameAr = catNameAr2.GetString()!;
                    
                    if (data.TryGetProperty("isActive", out var catIsActive)) category.IsActive = catIsActive.GetBoolean();
                    else if (data.TryGetProperty("IsActive", out var catIsActive2)) category.IsActive = catIsActive2.GetBoolean();
                    
                    category.UpdatedAt = DateTime.UtcNow;
                    _context.Categories.Update(category);
                    break;

                case "products":
                    var product = await _context.Products.FirstOrDefaultAsync(x => x.Id == guidId);
                    if (product == null) return NotFound(new { success = false, message = "المنتج غير موجود" });
                    
                    if (data.TryGetProperty("name", out var prodName)) product.Name = prodName.GetString()!;
                    else if (data.TryGetProperty("Name", out var prodName2)) product.Name = prodName2.GetString()!;
                    
                    if (data.TryGetProperty("nameAr", out var prodNameAr)) product.NameAr = prodNameAr.GetString()!;
                    else if (data.TryGetProperty("NameAr", out var prodNameAr2)) product.NameAr = prodNameAr2.GetString()!;
                    
                    if (data.TryGetProperty("price", out var prodPrice)) product.Price = prodPrice.GetDecimal();
                    else if (data.TryGetProperty("Price", out var prodPrice2)) product.Price = prodPrice2.GetDecimal();
                    
                    if (data.TryGetProperty("isActive", out var prodIsActive)) product.IsActive = prodIsActive.GetBoolean();
                    else if (data.TryGetProperty("IsActive", out var prodIsActive2)) product.IsActive = prodIsActive2.GetBoolean();
                    
                    product.UpdatedAt = DateTime.UtcNow;
                    _context.Products.Update(product);
                    break;

                case "internetplans":
                    var plan = await _context.InternetPlans.FirstOrDefaultAsync(x => x.Id == guidId);
                    if (plan == null) return NotFound(new { success = false, message = "الباقة غير موجودة" });
                    
                    if (data.TryGetProperty("name", out var planName)) plan.Name = planName.GetString()!;
                    else if (data.TryGetProperty("Name", out var planName2)) plan.Name = planName2.GetString()!;
                    
                    if (data.TryGetProperty("nameAr", out var planNameAr)) plan.NameAr = planNameAr.GetString()!;
                    else if (data.TryGetProperty("NameAr", out var planNameAr2)) plan.NameAr = planNameAr2.GetString()!;
                    
                    if (data.TryGetProperty("monthlyPrice", out var planPrice)) plan.MonthlyPrice = planPrice.GetDecimal();
                    else if (data.TryGetProperty("MonthlyPrice", out var planPrice2)) plan.MonthlyPrice = planPrice2.GetDecimal();
                    
                    if (data.TryGetProperty("speedMbps", out var planSpeed)) plan.SpeedMbps = planSpeed.GetInt32();
                    else if (data.TryGetProperty("SpeedMbps", out var planSpeed2)) plan.SpeedMbps = planSpeed2.GetInt32();
                    
                    if (data.TryGetProperty("isActive", out var planIsActive)) plan.IsActive = planIsActive.GetBoolean();
                    else if (data.TryGetProperty("IsActive", out var planIsActive2)) plan.IsActive = planIsActive2.GetBoolean();
                    
                    plan.UpdatedAt = DateTime.UtcNow;
                    _context.InternetPlans.Update(plan);
                    break;

                case "citizens":
                    var citizen = await _context.Citizens.FirstOrDefaultAsync(x => x.Id == guidId);
                    if (citizen == null) return NotFound(new { success = false, message = "المواطن غير موجود" });
                    
                    if (data.TryGetProperty("fullName", out var citizenName)) citizen.FullName = citizenName.GetString()!;
                    else if (data.TryGetProperty("FullName", out var citizenName2)) citizen.FullName = citizenName2.GetString()!;
                    
                    if (data.TryGetProperty("phoneNumber", out var citizenPhone)) citizen.PhoneNumber = citizenPhone.GetString()!;
                    else if (data.TryGetProperty("PhoneNumber", out var citizenPhone2)) citizen.PhoneNumber = citizenPhone2.GetString()!;
                    
                    if (data.TryGetProperty("email", out var citizenEmail)) citizen.Email = citizenEmail.GetString();
                    else if (data.TryGetProperty("Email", out var citizenEmail2)) citizen.Email = citizenEmail2.GetString();
                    
                    if (data.TryGetProperty("isActive", out var citizenIsActive)) citizen.IsActive = citizenIsActive.GetBoolean();
                    else if (data.TryGetProperty("IsActive", out var citizenIsActive2)) citizen.IsActive = citizenIsActive2.GetBoolean();
                    
                    citizen.UpdatedAt = DateTime.UtcNow;
                    _context.Citizens.Update(citizen);
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

                case "products":
                    var product = await _context.Products.FirstOrDefaultAsync(x => x.Id == guidId);
                    if (product == null) return NotFound(new { success = false, message = "المنتج غير موجود" });
                    if (hardDelete)
                        _context.Products.Remove(product);
                    else
                    {
                        product.IsDeleted = true;
                        product.UpdatedAt = DateTime.UtcNow;
                    }
                    break;

                case "companies":
                    var company = await _context.Companies.FirstOrDefaultAsync(x => x.Id == guidId);
                    if (company == null) return NotFound(new { success = false, message = "الشركة غير موجودة" });
                    if (hardDelete)
                        _context.Companies.Remove(company);
                    else
                    {
                        company.IsDeleted = true;
                        company.UpdatedAt = DateTime.UtcNow;
                    }
                    break;

                case "internetplans":
                    var plan = await _context.InternetPlans.FirstOrDefaultAsync(x => x.Id == guidId);
                    if (plan == null) return NotFound(new { success = false, message = "الباقة غير موجودة" });
                    _context.InternetPlans.Remove(plan);
                    break;

                case "citizens":
                    var citizen = await _context.Citizens.FirstOrDefaultAsync(x => x.Id == guidId);
                    if (citizen == null) return NotFound(new { success = false, message = "المواطن غير موجود" });
                    if (hardDelete)
                        _context.Citizens.Remove(citizen);
                    else
                    {
                        citizen.IsDeleted = true;
                        citizen.UpdatedAt = DateTime.UtcNow;
                    }
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

    /// <summary>
    /// عرض ملخص كامل للبيانات المحاسبية الموجودة
    /// </summary>
    [HttpGet("accounting-summary")]
    public async Task<IActionResult> GetAccountingSummary()
    {
        try
        {
            var subscriptionLogs = await _context.SubscriptionLogs.IgnoreQueryFilters().CountAsync();
            var techTransactions = await _context.TechnicianTransactions.IgnoreQueryFilters().CountAsync();
            var agentTransactions = await _context.AgentTransactions.IgnoreQueryFilters().CountAsync();
            var journalEntries = await _context.JournalEntries.IgnoreQueryFilters().CountAsync();
            var journalLines = await _context.JournalEntryLines.IgnoreQueryFilters().CountAsync();
            var cashBoxes = await _context.CashBoxes.CountAsync();
            var cashTransactions = await _context.CashTransactions.IgnoreQueryFilters().CountAsync();
            var accounts = await _context.Accounts.CountAsync();
            var agents = await _context.Agents.IgnoreQueryFilters().CountAsync();
            var techCollections = await _context.TechnicianCollections.IgnoreQueryFilters().CountAsync();

            // تفاصيل أرصدة الفنيين
            var techUsers = await _context.Users.IgnoreQueryFilters()
                .Where(u => u.Role == Sadara.Domain.Enums.UserRole.Technician)
                .Select(u => new { u.Id, u.FullName, u.TechTotalCharges, u.TechTotalPayments, u.TechNetBalance })
                .ToListAsync();

            // تفاصيل أرصدة الوكلاء
            var agentsList = await _context.Agents.IgnoreQueryFilters()
                .Select(a => new { a.Id, a.Name, a.TotalCharges, a.TotalPayments, a.NetBalance })
                .ToListAsync();

            // تفاصيل الصناديق
            var cashBoxesList = await _context.CashBoxes
                .Select(c => new { c.Id, c.Name, c.CurrentBalance })
                .ToListAsync();

            // تفاصيل الحسابات المحاسبية
            var accountsList = await _context.Accounts
                .Select(a => new { a.Id, a.Name, a.Code, a.AccountType, a.CurrentBalance })
                .ToListAsync();

            return Ok(new
            {
                success = true,
                data = new
                {
                    counts = new
                    {
                        subscriptionLogs,
                        technicianTransactions = techTransactions,
                        agentTransactions,
                        journalEntries,
                        journalEntryLines = journalLines,
                        cashBoxes,
                        cashTransactions,
                        accounts,
                        agents,
                        technicianCollections = techCollections
                    },
                    technicians = techUsers,
                    agentBalances = agentsList,
                    cashBoxBalances = cashBoxesList,
                    accountBalances = accountsList
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب ملخص البيانات المحاسبية");
            return StatusCode(500, new { success = false, message = "حدث خطأ: " + ex.Message });
        }
    }

    /// <summary>
    /// تنظيف البيانات المحاسبية الشاملة وتصفير الأرصدة
    /// </summary>
    [HttpPost("cleanup-accounting")]
    public async Task<IActionResult> CleanupAccounting()
    {
        try
        {
            var report = new Dictionary<string, int>();

            // ═══ حذف الجداول الفرعية أولاً (FK constraints) ═══

            // 1. سطور القيود
            var jelCount = await _context.JournalEntryLines.IgnoreQueryFilters().CountAsync();
            if (jelCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"JournalEntryLines\"");
                report["JournalEntryLines"] = jelCount;
            }

            // 2. القيود المحاسبية
            var jeCount = await _context.JournalEntries.IgnoreQueryFilters().CountAsync();
            if (jeCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"JournalEntries\"");
                report["JournalEntries"] = jeCount;
            }

            // 3. معاملات الفنيين
            var ttCount = await _context.TechnicianTransactions.IgnoreQueryFilters().CountAsync();
            if (ttCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"TechnicianTransactions\"");
                report["TechnicianTransactions"] = ttCount;
            }

            // 4. تحصيلات الفنيين
            var tcCount = await _context.TechnicianCollections.IgnoreQueryFilters().CountAsync();
            if (tcCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"TechnicianCollections\"");
                report["TechnicianCollections"] = tcCount;
            }

            // 5. معاملات الوكلاء
            var atCount = await _context.AgentTransactions.IgnoreQueryFilters().CountAsync();
            if (atCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"AgentTransactions\"");
                report["AgentTransactions"] = atCount;
            }

            // 6. حركات الصندوق
            var ctCount = await _context.CashTransactions.IgnoreQueryFilters().CountAsync();
            if (ctCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"CashTransactions\"");
                report["CashTransactions"] = ctCount;
            }

            // 7. سجلات الاشتراكات
            var slCount = await _context.SubscriptionLogs.IgnoreQueryFilters().CountAsync();
            if (slCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"SubscriptionLogs\"");
                report["SubscriptionLogs"] = slCount;
            }

            // 8. المصروفات
            var expCount = await _context.Expenses.IgnoreQueryFilters().CountAsync();
            if (expCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"Expenses\"");
                report["Expenses"] = expCount;
            }

            // 9. دفعات المصاريف الثابتة
            var fepCount = await _context.FixedExpensePayments.IgnoreQueryFilters().CountAsync();
            if (fepCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"FixedExpensePayments\"");
                report["FixedExpensePayments"] = fepCount;
            }

            // 10. خصومات ومكافآت الموظفين
            var edbCount = await _context.EmployeeDeductionBonuses.IgnoreQueryFilters().CountAsync();
            if (edbCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"EmployeeDeductionBonuses\"");
                report["EmployeeDeductionBonuses"] = edbCount;
            }

            // 11. رواتب الموظفين
            var esCount = await _context.EmployeeSalaries.IgnoreQueryFilters().CountAsync();
            if (esCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"EmployeeSalaries\"");
                report["EmployeeSalaries"] = esCount;
            }

            // 12. تقارير التسوية اليومية
            var dsrCount = await _context.DailySettlementReports.IgnoreQueryFilters().CountAsync();
            if (dsrCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"DailySettlementReports\"");
                report["DailySettlementReports"] = dsrCount;
            }

            // 13. طلبات السحب
            var wrCount = await _context.WithdrawalRequests.IgnoreQueryFilters().CountAsync();
            if (wrCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"WithdrawalRequests\"");
                report["WithdrawalRequests"] = wrCount;
            }

            // ═══ تصفير الأرصدة التراكمية ═══

            // 14. تصفير أرصدة الفنيين (كل المستخدمين الذين لديهم رصيد فني بغض النظر عن الدور)
            var techUsers = await _context.Users.IgnoreQueryFilters()
                .Where(u => u.TechTotalCharges != 0 || u.TechTotalPayments != 0 || u.TechNetBalance != 0)
                .ToListAsync();
            int techReset = 0;
            foreach (var tech in techUsers)
            {
                tech.TechTotalCharges = 0;
                tech.TechTotalPayments = 0;
                tech.TechNetBalance = 0;
                _context.Users.Update(tech);
                techReset++;
            }
            report["TechniciansBalanceReset"] = techReset;

            // 15. تصفير أرصدة الوكلاء
            var agentsList = await _context.Agents.IgnoreQueryFilters().ToListAsync();
            int agentReset = 0;
            foreach (var agent in agentsList)
            {
                if (agent.TotalCharges != 0 || agent.TotalPayments != 0 || agent.NetBalance != 0)
                {
                    agent.TotalCharges = 0;
                    agent.TotalPayments = 0;
                    agent.NetBalance = 0;
                    _context.Agents.Update(agent);
                    agentReset++;
                }
            }
            report["AgentsBalanceReset"] = agentReset;

            // 16. تصفير أرصدة الصناديق
            var boxes = await _context.CashBoxes.ToListAsync();
            int boxReset = 0;
            foreach (var box in boxes)
            {
                if (box.CurrentBalance != 0)
                {
                    box.CurrentBalance = 0;
                    _context.CashBoxes.Update(box);
                    boxReset++;
                }
            }
            report["CashBoxesReset"] = boxReset;

            // 17. تصفير أرصدة الحسابات المحاسبية
            var accountsList = await _context.Accounts.ToListAsync();
            int accReset = 0;
            foreach (var acc in accountsList)
            {
                if (acc.CurrentBalance != 0)
                {
                    acc.CurrentBalance = 0;
                    _context.Accounts.Update(acc);
                    accReset++;
                }
            }
            report["AccountsBalanceReset"] = accReset;

            await _context.SaveChangesAsync();

            _logger.LogWarning("تم تنظيف جميع البيانات المحاسبية: {@Report}", report);

            return Ok(new
            {
                success = true,
                message = "تم تنظيف جميع البيانات المحاسبية بنجاح",
                report
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تنظيف البيانات المحاسبية");
            return StatusCode(500, new { success = false, message = "حدث خطأ: " + ex.Message });
        }
    }

    /// <summary>
    /// تنظيف بيانات الحضور والبصمات والإجازات
    /// </summary>
    [HttpPost("cleanup-attendance")]
    public async Task<IActionResult> CleanupAttendance()
    {
        try
        {
            var report = new Dictionary<string, int>();

            // 1. سجل تدقيق الحضور
            var aalCount = await _context.AttendanceAuditLogs.IgnoreQueryFilters().CountAsync();
            if (aalCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"AttendanceAuditLogs\"");
                report["AttendanceAuditLogs"] = aalCount;
            }

            // 2. سجلات الحضور
            var arCount = await _context.AttendanceRecords.IgnoreQueryFilters().CountAsync();
            if (arCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"AttendanceRecords\"");
                report["AttendanceRecords"] = arCount;
            }

            // 3. طلبات الإجازة
            var lrCount = await _context.LeaveRequests.IgnoreQueryFilters().CountAsync();
            if (lrCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"LeaveRequests\"");
                report["LeaveRequests"] = lrCount;
            }

            // 4. أرصدة الإجازات
            var lbCount = await _context.LeaveBalances.IgnoreQueryFilters().CountAsync();
            if (lbCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"LeaveBalances\"");
                report["LeaveBalances"] = lbCount;
            }

            // 5. تصفير بصمات الأجهزة المسجلة
            var usersWithFingerprints = await _context.Users.IgnoreQueryFilters()
                .Where(u => u.RegisteredDeviceFingerprint != null || u.PendingDeviceFingerprint != null)
                .ToListAsync();
            int fpReset = 0;
            foreach (var user in usersWithFingerprints)
            {
                user.RegisteredDeviceFingerprint = null;
                user.PendingDeviceFingerprint = null;
                user.DeviceApprovalStatus = 0;
                user.DeviceApprovedAt = null;
                user.DeviceApprovedByUserId = null;
                _context.Users.Update(user);
                fpReset++;
            }
            report["DeviceFingerprintsReset"] = fpReset;

            await _context.SaveChangesAsync();

            _logger.LogWarning("تم تنظيف بيانات الحضور والبصمات: {@Report}", report);

            return Ok(new
            {
                success = true,
                message = "تم تنظيف بيانات الحضور والبصمات والإجازات بنجاح",
                report
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تنظيف بيانات الحضور");
            return StatusCode(500, new { success = false, message = "حدث خطأ: " + ex.Message });
        }
    }

    /// <summary>
    /// تنظيف بيانات المخزون والمستودعات
    /// </summary>
    [HttpPost("cleanup-inventory")]
    public async Task<IActionResult> CleanupInventory()
    {
        try
        {
            var report = new Dictionary<string, int>();

            // ═══ حذف الجداول الفرعية أولاً (FK) ═══

            // 1. بنود صرف الفنيين
            var tdiCount = await _context.TechnicianDispensingItems.IgnoreQueryFilters().CountAsync();
            if (tdiCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"TechnicianDispensingItems\"");
                report["TechnicianDispensingItems"] = tdiCount;
            }

            // 2. صرف مواد الفنيين
            var tdCount = await _context.TechnicianDispensings.IgnoreQueryFilters().CountAsync();
            if (tdCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"TechnicianDispensings\"");
                report["TechnicianDispensings"] = tdCount;
            }

            // 3. بنود أوامر الشراء
            var poiCount = await _context.PurchaseOrderItems.IgnoreQueryFilters().CountAsync();
            if (poiCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"PurchaseOrderItems\"");
                report["PurchaseOrderItems"] = poiCount;
            }

            // 4. أوامر الشراء
            var poCount = await _context.PurchaseOrders.IgnoreQueryFilters().CountAsync();
            if (poCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"PurchaseOrders\"");
                report["PurchaseOrders"] = poCount;
            }

            // 5. بنود عمليات البيع
            var soiCount = await _context.SalesOrderItems.IgnoreQueryFilters().CountAsync();
            if (soiCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"SalesOrderItems\"");
                report["SalesOrderItems"] = soiCount;
            }

            // 6. عمليات البيع
            var soCount = await _context.SalesOrders.IgnoreQueryFilters().CountAsync();
            if (soCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"SalesOrders\"");
                report["SalesOrders"] = soCount;
            }

            // 7. حركات المخزن
            var smCount = await _context.StockMovements.IgnoreQueryFilters().CountAsync();
            if (smCount > 0)
            {
                await _context.Database.ExecuteSqlRawAsync("DELETE FROM \"StockMovements\"");
                report["StockMovements"] = smCount;
            }

            // 8. تصفير أرصدة المخزون
            var stocks = await _context.WarehouseStocks.IgnoreQueryFilters().ToListAsync();
            int stockReset = 0;
            foreach (var stock in stocks)
            {
                if (stock.CurrentQuantity != 0 || stock.ReservedQuantity != 0)
                {
                    stock.CurrentQuantity = 0;
                    stock.ReservedQuantity = 0;
                    stock.AverageCost = 0;
                    _context.WarehouseStocks.Update(stock);
                    stockReset++;
                }
            }
            report["WarehouseStocksReset"] = stockReset;

            await _context.SaveChangesAsync();

            _logger.LogWarning("تم تنظيف بيانات المخزون: {@Report}", report);

            return Ok(new
            {
                success = true,
                message = "تم تنظيف بيانات المخزون والمستودعات بنجاح",
                report
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في تنظيف بيانات المخزون");
            return StatusCode(500, new { success = false, message = "حدث خطأ: " + ex.Message });
        }
    }

    /// <summary>
    /// تصفير شامل — جميع العمليات المحاسبية + الحضور + المخزون
    /// </summary>
    [HttpPost("cleanup-all")]
    public async Task<IActionResult> CleanupAll()
    {
        try
        {
            var allReports = new Dictionary<string, object>();

            // 1. تنظيف المحاسبة
            var accResult = await CleanupAccounting() as OkObjectResult;
            if (accResult?.Value != null)
            {
                var val = accResult.Value;
                var reportProp = val.GetType().GetProperty("report");
                if (reportProp != null)
                    allReports["accounting"] = reportProp.GetValue(val)!;
            }

            // 2. تنظيف الحضور
            var attResult = await CleanupAttendance() as OkObjectResult;
            if (attResult?.Value != null)
            {
                var val = attResult.Value;
                var reportProp = val.GetType().GetProperty("report");
                if (reportProp != null)
                    allReports["attendance"] = reportProp.GetValue(val)!;
            }

            // 3. تنظيف المخزون
            var invResult = await CleanupInventory() as OkObjectResult;
            if (invResult?.Value != null)
            {
                var val = invResult.Value;
                var reportProp = val.GetType().GetProperty("report");
                if (reportProp != null)
                    allReports["inventory"] = reportProp.GetValue(val)!;
            }

            _logger.LogWarning("تم التصفير الشامل لجميع العمليات: {@Report}", allReports);

            return Ok(new
            {
                success = true,
                message = "تم تصفير جميع العمليات بنجاح (محاسبة + حضور + مخزون)",
                report = allReports
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في التصفير الشامل");
            return StatusCode(500, new { success = false, message = "حدث خطأ: " + ex.Message });
        }
    }

    /// <summary>
    /// إحصائيات التصفير — عدد السجلات في كل فئة قبل التصفير
    /// </summary>
    [HttpGet("cleanup-stats")]
    public async Task<IActionResult> GetCleanupStats()
    {
        try
        {
            var stats = new Dictionary<string, object>
            {
                ["accounting"] = new
                {
                    JournalEntryLines = await _context.JournalEntryLines.IgnoreQueryFilters().CountAsync(),
                    JournalEntries = await _context.JournalEntries.IgnoreQueryFilters().CountAsync(),
                    TechnicianTransactions = await _context.TechnicianTransactions.IgnoreQueryFilters().CountAsync(),
                    TechnicianCollections = await _context.TechnicianCollections.IgnoreQueryFilters().CountAsync(),
                    AgentTransactions = await _context.AgentTransactions.IgnoreQueryFilters().CountAsync(),
                    CashTransactions = await _context.CashTransactions.IgnoreQueryFilters().CountAsync(),
                    SubscriptionLogs = await _context.SubscriptionLogs.IgnoreQueryFilters().CountAsync(),
                    Expenses = await _context.Expenses.IgnoreQueryFilters().CountAsync(),
                    FixedExpensePayments = await _context.FixedExpensePayments.IgnoreQueryFilters().CountAsync(),
                    EmployeeDeductionBonuses = await _context.EmployeeDeductionBonuses.IgnoreQueryFilters().CountAsync(),
                    EmployeeSalaries = await _context.EmployeeSalaries.IgnoreQueryFilters().CountAsync(),
                    DailySettlementReports = await _context.DailySettlementReports.IgnoreQueryFilters().CountAsync(),
                    WithdrawalRequests = await _context.WithdrawalRequests.IgnoreQueryFilters().CountAsync(),
                },
                ["attendance"] = new
                {
                    AttendanceRecords = await _context.AttendanceRecords.IgnoreQueryFilters().CountAsync(),
                    AttendanceAuditLogs = await _context.AttendanceAuditLogs.IgnoreQueryFilters().CountAsync(),
                    LeaveRequests = await _context.LeaveRequests.IgnoreQueryFilters().CountAsync(),
                    LeaveBalances = await _context.LeaveBalances.IgnoreQueryFilters().CountAsync(),
                    DeviceFingerprints = await _context.Users.IgnoreQueryFilters()
                        .CountAsync(u => u.RegisteredDeviceFingerprint != null || u.PendingDeviceFingerprint != null),
                },
                ["inventory"] = new
                {
                    TechnicianDispensingItems = await _context.TechnicianDispensingItems.IgnoreQueryFilters().CountAsync(),
                    TechnicianDispensings = await _context.TechnicianDispensings.IgnoreQueryFilters().CountAsync(),
                    PurchaseOrderItems = await _context.PurchaseOrderItems.IgnoreQueryFilters().CountAsync(),
                    PurchaseOrders = await _context.PurchaseOrders.IgnoreQueryFilters().CountAsync(),
                    SalesOrderItems = await _context.SalesOrderItems.IgnoreQueryFilters().CountAsync(),
                    SalesOrders = await _context.SalesOrders.IgnoreQueryFilters().CountAsync(),
                    StockMovements = await _context.StockMovements.IgnoreQueryFilters().CountAsync(),
                    WarehouseStocks = await _context.WarehouseStocks.IgnoreQueryFilters().CountAsync(),
                }
            };

            return Ok(new { success = true, data = stats });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في جلب إحصائيات التصفير");
            return StatusCode(500, new { success = false, message = "حدث خطأ: " + ex.Message });
        }
    }

    /// <summary>
    /// أرشفة جميع البيانات التشغيلية كملف Excel قبل التصفير
    /// كل جدول في sheet منفصل
    /// </summary>
    [HttpGet("archive/{category}")]
    public async Task<IActionResult> ArchiveData(string category)
    {
        try
        {
            using var workbook = new XLWorkbook();
            var timestamp = DateTime.Now.ToString("yyyy-MM-dd_HH-mm");

            if (category == "accounting" || category == "all")
            {
                await AddSheet(workbook, "القيود المحاسبية",
                    await _context.JournalEntries.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.EntryNumber, e.EntryDate, e.Description, e.TotalDebit, e.TotalCredit, e.ReferenceType, e.Status, e.Notes, e.CreatedAt })
                        .ToListAsync());

                await AddSheet(workbook, "بنود القيود",
                    await _context.JournalEntryLines.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.JournalEntryId, e.AccountId, e.DebitAmount, e.CreditAmount, e.Description, e.EntityType, e.EntityId })
                        .ToListAsync());

                await AddSheet(workbook, "معاملات الفنيين",
                    await _context.TechnicianTransactions.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.TechnicianId, e.Type, e.Category, e.Amount, e.BalanceAfter, e.Description, e.ReferenceNumber, e.Notes, e.ReceivedBy, e.CreatedAt })
                        .ToListAsync());

                await AddSheet(workbook, "تحصيلات الفنيين",
                    await _context.TechnicianCollections.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.TechnicianId, e.CitizenId, e.Amount, e.CollectionDate, e.IsDelivered, e.DeliveredAt, e.Notes, e.Description, e.PaymentMethod, e.ReceiptNumber, e.ReceivedBy, e.CreatedAt })
                        .ToListAsync());

                await AddSheet(workbook, "معاملات الوكلاء",
                    await _context.AgentTransactions.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.AgentId, e.Type, e.Category, e.Amount, e.BalanceAfter, e.Description, e.ReferenceNumber, e.Notes, e.CreatedAt })
                        .ToListAsync());

                await AddSheet(workbook, "حركات الصندوق",
                    await _context.CashTransactions.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.CashBoxId, e.TransactionType, e.Amount, e.BalanceAfter, e.Description, e.ReferenceType, e.ReferenceId, e.CreatedAt })
                        .ToListAsync());

                await AddSheet(workbook, "المصروفات",
                    await _context.Expenses.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.AccountId, e.Amount, e.Description, e.ExpenseDate, e.Category, e.Notes, e.CreatedAt })
                        .ToListAsync());

                await AddSheet(workbook, "دفعات المصاريف الثابتة",
                    await _context.FixedExpensePayments.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.FixedExpenseId, e.Month, e.Year, e.Amount, e.IsPaid, e.PaidAt, e.Notes })
                        .ToListAsync());

                await AddSheet(workbook, "رواتب الموظفين",
                    await _context.EmployeeSalaries.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.UserId, e.Month, e.Year, e.BaseSalary, e.Allowances, e.Deductions, e.Bonuses, e.NetSalary, e.Status, e.PaidAt, e.AttendanceDays, e.AbsentDays, e.Notes })
                        .ToListAsync());

                await AddSheet(workbook, "خصومات ومكافآت",
                    await _context.EmployeeDeductionBonuses.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.UserId, e.Type, e.Category, e.Amount, e.Month, e.Year, e.Description, e.Notes, e.IsApplied, e.IsRecurring })
                        .ToListAsync());

                await AddSheet(workbook, "تقارير التسوية",
                    await _context.DailySettlementReports.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.ReportDate, e.OperatorName, e.TotalAmount, e.SystemTotal, e.SystemCashTotal, e.SystemCreditTotal, e.TotalExpenses, e.NetCashAmount, e.ReceivedAmount, e.Notes })
                        .ToListAsync());

                await AddSheet(workbook, "طلبات السحب",
                    await _context.WithdrawalRequests.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.UserId, e.UserName, e.Amount, e.Reason, e.Status, e.ReviewedByUserName, e.ReviewedAt, e.ReviewNotes, e.CreatedAt })
                        .ToListAsync());

                await AddSheet(workbook, "سجلات الاشتراكات",
                    await _context.SubscriptionLogs.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.CustomerId, e.CustomerName, e.PhoneNumber, e.SubscriptionId, e.PlanName, e.PlanPrice, e.CurrentStatus, e.CreatedAt })
                        .ToListAsync());

                // أرصدة حالية (للمرجع)
                await AddSheet(workbook, "أرصدة الحسابات",
                    await _context.Accounts.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.Code, e.Name, e.AccountType, e.CurrentBalance, e.OpeningBalance, e.Level, e.IsLeaf })
                        .ToListAsync());

                await AddSheet(workbook, "أرصدة الصناديق",
                    await _context.CashBoxes
                        .Select(e => new { e.Id, e.Name, e.CashBoxType, e.CurrentBalance, e.IsActive })
                        .ToListAsync());

                await AddSheet(workbook, "أرصدة الفنيين",
                    await _context.Users.IgnoreQueryFilters()
                        .Where(u => u.TechTotalCharges != 0 || u.TechTotalPayments != 0 || u.TechNetBalance != 0)
                        .Select(u => new { u.Id, u.FullName, u.Role, u.TechTotalCharges, u.TechTotalPayments, u.TechNetBalance })
                        .ToListAsync());

                await AddSheet(workbook, "أرصدة الوكلاء",
                    await _context.Agents.IgnoreQueryFilters()
                        .Select(a => new { a.Id, a.Name, a.AgentCode, a.TotalCharges, a.TotalPayments, a.NetBalance })
                        .ToListAsync());
            }

            if (category == "attendance" || category == "all")
            {
                await AddSheet(workbook, "سجلات الحضور",
                    await _context.AttendanceRecords.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.UserId, e.UserName, e.Date, e.CheckInTime, e.CheckOutTime, e.CenterName, e.Status, e.LateMinutes, e.OvertimeMinutes, e.WorkedMinutes, e.EarlyDepartureMinutes, e.DeviceFingerprint })
                        .ToListAsync());

                await AddSheet(workbook, "تدقيق الحضور",
                    await _context.AttendanceAuditLogs.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.UserId, e.UserName, e.ActionType, e.IsSuccess, e.RejectionReason, e.CenterName, e.DistanceFromCenter, e.DeviceFingerprint, e.IsVpnSuspected, e.AttemptTime })
                        .ToListAsync());

                await AddSheet(workbook, "طلبات الإجازة",
                    await _context.LeaveRequests.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.UserId, e.UserName, e.LeaveType, e.StartDate, e.EndDate, e.TotalDays, e.Reason, e.Status, e.ReviewedByUserName, e.ReviewedAt })
                        .ToListAsync());

                await AddSheet(workbook, "أرصدة الإجازات",
                    await _context.LeaveBalances.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.UserId, e.Year, e.LeaveType, e.TotalAllowance, e.UsedDays, e.RemainingDays })
                        .ToListAsync());

                await AddSheet(workbook, "بصمات الأجهزة",
                    await _context.Users.IgnoreQueryFilters()
                        .Where(u => u.RegisteredDeviceFingerprint != null || u.PendingDeviceFingerprint != null)
                        .Select(u => new { u.Id, u.FullName, u.RegisteredDeviceFingerprint, u.PendingDeviceFingerprint, u.DeviceApprovalStatus, u.DeviceApprovedAt })
                        .ToListAsync());
            }

            if (category == "inventory" || category == "all")
            {
                await AddSheet(workbook, "صرف مواد الفنيين",
                    await _context.TechnicianDispensings.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.VoucherNumber, e.TechnicianId, e.WarehouseId, e.DispensingDate, e.Status, e.Type, e.Notes, e.CreatedAt })
                        .ToListAsync());

                await AddSheet(workbook, "بنود الصرف",
                    await _context.TechnicianDispensingItems.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.TechnicianDispensingId, e.InventoryItemId, e.Quantity, e.ReturnedQuantity, e.Notes })
                        .ToListAsync());

                await AddSheet(workbook, "أوامر الشراء",
                    await _context.PurchaseOrders.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.OrderNumber, e.SupplierId, e.WarehouseId, e.OrderDate, e.ReceivedDate, e.Status, e.TotalAmount, e.DiscountAmount, e.NetAmount, e.Notes })
                        .ToListAsync());

                await AddSheet(workbook, "بنود الشراء",
                    await _context.PurchaseOrderItems.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.PurchaseOrderId, e.InventoryItemId, e.Quantity, e.ReceivedQuantity, e.UnitPrice, e.TotalPrice })
                        .ToListAsync());

                await AddSheet(workbook, "عمليات البيع",
                    await _context.SalesOrders.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.OrderNumber, e.CustomerName, e.CustomerPhone, e.WarehouseId, e.OrderDate, e.Status, e.TotalAmount, e.DiscountAmount, e.NetAmount, e.PaymentMethod, e.Notes })
                        .ToListAsync());

                await AddSheet(workbook, "بنود البيع",
                    await _context.SalesOrderItems.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.SalesOrderId, e.InventoryItemId, e.Quantity, e.UnitPrice, e.TotalPrice })
                        .ToListAsync());

                await AddSheet(workbook, "حركات المخزن",
                    await _context.StockMovements.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.InventoryItemId, e.WarehouseId, e.MovementType, e.Quantity, e.StockBefore, e.StockAfter, e.UnitCost, e.ReferenceType, e.ReferenceNumber, e.Description, e.CreatedAt })
                        .ToListAsync());

                await AddSheet(workbook, "أرصدة المخزون",
                    await _context.WarehouseStocks.IgnoreQueryFilters()
                        .Select(e => new { e.Id, e.WarehouseId, e.InventoryItemId, e.CurrentQuantity, e.ReservedQuantity, e.AverageCost, e.LastStockInDate, e.LastStockOutDate })
                        .ToListAsync());
            }

            // إذا لم يكن هناك أي بيانات
            if (workbook.Worksheets.Count == 0)
            {
                workbook.AddWorksheet("فارغ").Cell(1, 1).Value = "لا توجد بيانات للأرشفة";
            }

            using var stream = new MemoryStream();
            workbook.SaveAs(stream);
            stream.Position = 0;

            var fileName = $"Sadara_Archive_{category}_{timestamp}.xlsx";

            _logger.LogWarning("تم تصدير أرشيف {Category} بتاريخ {Timestamp}", category, timestamp);

            return File(stream.ToArray(),
                "application/vnd.openxmlformats-officedocument.spreadsheetml.document",
                fileName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "خطأ في أرشفة البيانات");
            return StatusCode(500, new { success = false, message = "حدث خطأ: " + ex.Message });
        }
    }

    /// <summary>
    /// Helper: إضافة sheet لقائمة بيانات
    /// </summary>
    private static Task AddSheet<T>(XLWorkbook workbook, string sheetName, List<T> data)
    {
        // تقصير اسم الـ sheet (max 31 chars in Excel)
        var safeName = sheetName.Length > 31 ? sheetName[..31] : sheetName;
        var ws = workbook.AddWorksheet(safeName);

        if (data.Count == 0)
        {
            ws.Cell(1, 1).Value = "لا توجد بيانات";
            return Task.CompletedTask;
        }

        // Headers
        var props = typeof(T).GetProperties();
        for (int i = 0; i < props.Length; i++)
        {
            var headerCell = ws.Cell(1, i + 1);
            headerCell.Value = props[i].Name;
            headerCell.Style.Font.Bold = true;
            headerCell.Style.Fill.BackgroundColor = XLColor.FromHtml("#1B5E20");
            headerCell.Style.Font.FontColor = XLColor.White;
        }

        // Data rows
        for (int row = 0; row < data.Count; row++)
        {
            for (int col = 0; col < props.Length; col++)
            {
                var val = props[col].GetValue(data[row]);
                var cell = ws.Cell(row + 2, col + 1);

                if (val == null)
                    cell.Value = "";
                else if (val is DateTime dt)
                    cell.Value = dt.ToString("yyyy-MM-dd HH:mm:ss");
                else if (val is DateTimeOffset dto)
                    cell.Value = dto.ToString("yyyy-MM-dd HH:mm:ss");
                else if (val is decimal d)
                    cell.Value = (double)d;
                else if (val is int intVal)
                    cell.Value = intVal;
                else if (val is long longVal)
                    cell.Value = longVal;
                else if (val is double dblVal)
                    cell.Value = dblVal;
                else if (val is bool b)
                    cell.Value = b ? "نعم" : "لا";
                else if (val is Guid g)
                    cell.Value = g.ToString();
                else
                    cell.Value = val.ToString();
            }
        }

        // Auto-fit columns
        ws.Columns().AdjustToContents(1, 100);

        // Freeze header row
        ws.SheetView.FreezeRows(1);

        return Task.CompletedTask;
    }
}
