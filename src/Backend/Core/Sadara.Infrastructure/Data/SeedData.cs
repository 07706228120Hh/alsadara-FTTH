using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;
using Sadara.Domain.Enums;
using System.Security.Cryptography;
using System.Text;

namespace Sadara.Infrastructure.Data;

/// <summary>
/// بيانات البذر الأولية للنظام
/// </summary>
public static class SeedData
{
    /// <summary>
    /// تهيئة البيانات الأولية
    /// </summary>
    public static async Task SeedAsync(SadaraDbContext context)
    {
        await SeedPermissionGroupsAsync(context);
        await SeedPermissionsAsync(context);
        await SeedPermissionTemplatesAsync(context);
        await SeedServicesAsync(context);
        await SeedOperationTypesAsync(context);
        await SeedSuperAdminAsync(context);
        await context.SaveChangesAsync();
    }

    #region Permission Groups

    private static async Task SeedPermissionGroupsAsync(SadaraDbContext context)
    {
        if (await context.PermissionGroups.AnyAsync()) return;

        var permissionGroups = new List<PermissionGroup>
        {
            // مجموعة إدارة المستخدمين
            new() { Id = 1, Code = "users", Name = "Users Management", NameAr = "إدارة المستخدمين", Description = "صلاحيات إدارة المستخدمين", Icon = "people", SystemType = SystemType.All, DisplayOrder = 1 },
            
            // مجموعة إدارة الشركات
            new() { Id = 2, Code = "companies", Name = "Companies Management", NameAr = "إدارة الشركات", Description = "صلاحيات إدارة الشركات", Icon = "business", SystemType = SystemType.SecondSystem, DisplayOrder = 2 },
            
            // مجموعة طلبات الخدمات
            new() { Id = 3, Code = "requests", Name = "Service Requests", NameAr = "طلبات الخدمات", Description = "صلاحيات إدارة طلبات الخدمات", Icon = "assignment", SystemType = SystemType.All, DisplayOrder = 3 },
            
            // مجموعة المنتجات والخدمات
            new() { Id = 4, Code = "products", Name = "Products & Services", NameAr = "المنتجات والخدمات", Description = "صلاحيات إدارة المنتجات والخدمات", Icon = "inventory", SystemType = SystemType.All, DisplayOrder = 4 },
            
            // مجموعة الطلبيات
            new() { Id = 5, Code = "orders", Name = "Orders", NameAr = "الطلبيات", Description = "صلاحيات إدارة الطلبيات", Icon = "shopping_cart", SystemType = SystemType.All, DisplayOrder = 5 },
            
            // مجموعة التقارير والتحليلات
            new() { Id = 6, Code = "reports", Name = "Reports & Analytics", NameAr = "التقارير والتحليلات", Description = "صلاحيات عرض التقارير والتحليلات", Icon = "analytics", SystemType = SystemType.All, DisplayOrder = 6 },
            
            // مجموعة الإعدادات
            new() { Id = 7, Code = "settings", Name = "Settings", NameAr = "الإعدادات", Description = "صلاحيات إدارة الإعدادات", Icon = "settings", SystemType = SystemType.SecondSystem, DisplayOrder = 7 },
            
            // مجموعة نظام المواطن
            new() { Id = 8, Code = "citizen", Name = "Citizen Portal", NameAr = "نظام المواطن", Description = "صلاحيات إدارة نظام المواطن", Icon = "person", SystemType = SystemType.CitizenPortal, DisplayOrder = 8 },
            
            // مجموعة الاشتراكات
            new() { Id = 9, Code = "subscriptions", Name = "Subscriptions", NameAr = "الاشتراكات", Description = "صلاحيات إدارة الاشتراكات", Icon = "card_membership", SystemType = SystemType.CitizenPortal, DisplayOrder = 9 },
            
            // مجموعة المدفوعات
            new() { Id = 10, Code = "payments", Name = "Payments", NameAr = "المدفوعات", Description = "صلاحيات إدارة المدفوعات", Icon = "payments", SystemType = SystemType.All, DisplayOrder = 10 },
            
            // مجموعة تذاكر الدعم
            new() { Id = 11, Code = "support", Name = "Support Tickets", NameAr = "تذاكر الدعم", Description = "صلاحيات إدارة تذاكر الدعم", Icon = "support", SystemType = SystemType.CitizenPortal, DisplayOrder = 11 },
            
            // مجموعة إدارة النظام (SuperAdmin فقط)
            new() { Id = 12, Code = "admin", Name = "System Administration", NameAr = "إدارة النظام", Description = "صلاحيات مدير النظام الأعلى", Icon = "admin_panel_settings", SystemType = SystemType.All, DisplayOrder = 99 }
        };

        await context.PermissionGroups.AddRangeAsync(permissionGroups);
        await context.SaveChangesAsync();
    }

    #endregion

    #region Permissions

    private static async Task SeedPermissionsAsync(SadaraDbContext context)
    {
        if (await context.Permissions.AnyAsync()) return;

        var permissions = new List<Permission>
        {
            // ==================== Users Management (Group 1) ====================
            new() { Id = 1, PermissionGroupId = 1, Module = "users", Action = "view", Code = "users.view", Name = "View Users", NameAr = "عرض المستخدمين", Description = "View all users", SystemType = SystemType.All, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 1 },
            new() { Id = 2, PermissionGroupId = 1, Module = "users", Action = "create", Code = "users.create", Name = "Create User", NameAr = "إنشاء مستخدم", Description = "Create new users", SystemType = SystemType.All, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 2 },
            new() { Id = 3, PermissionGroupId = 1, Module = "users", Action = "edit", Code = "users.edit", Name = "Edit User", NameAr = "تعديل مستخدم", Description = "Edit existing users", SystemType = SystemType.All, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 3 },
            new() { Id = 4, PermissionGroupId = 1, Module = "users", Action = "delete", Code = "users.delete", Name = "Delete User", NameAr = "حذف مستخدم", Description = "Delete users", SystemType = SystemType.All, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 4 },
            new() { Id = 5, PermissionGroupId = 1, Module = "users", Action = "permissions", Code = "users.permissions", Name = "Manage Permissions", NameAr = "إدارة صلاحيات المستخدمين", Description = "Manage user permissions", SystemType = SystemType.All, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 5 },
            
            // ==================== Companies Management (Group 2) ====================
            new() { Id = 10, PermissionGroupId = 2, Module = "companies", Action = "view", Code = "companies.view", Name = "View Companies", NameAr = "عرض الشركات", Description = "View all companies", SystemType = SystemType.SecondSystem, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 10 },
            new() { Id = 11, PermissionGroupId = 2, Module = "companies", Action = "create", Code = "companies.create", Name = "Create Company", NameAr = "إنشاء شركة", Description = "Create new company", SystemType = SystemType.SecondSystem, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 11 },
            new() { Id = 12, PermissionGroupId = 2, Module = "companies", Action = "edit", Code = "companies.edit", Name = "Edit Company", NameAr = "تعديل شركة", Description = "Edit existing company", SystemType = SystemType.SecondSystem, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 12 },
            new() { Id = 13, PermissionGroupId = 2, Module = "companies", Action = "delete", Code = "companies.delete", Name = "Delete Company", NameAr = "حذف شركة", Description = "Delete company", SystemType = SystemType.SecondSystem, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 13 },
            new() { Id = 14, PermissionGroupId = 2, Module = "companies", Action = "employees", Code = "companies.employees", Name = "Manage Employees", NameAr = "إدارة موظفي الشركة", Description = "Manage company employees", SystemType = SystemType.SecondSystem, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 14 },
            new() { Id = 15, PermissionGroupId = 2, Module = "companies", Action = "link_citizen", Code = "companies.link_citizen", Name = "Link Citizen Portal", NameAr = "ربط نظام المواطن", Description = "Link company to citizen portal", SystemType = SystemType.SecondSystem, IsFirstSystem = false, IsSecondSystem = true, RequiresLinkedCompany = false, DisplayOrder = 15 },
            
            // ==================== Service Requests (Group 3) ====================
            new() { Id = 20, PermissionGroupId = 3, Module = "requests", Action = "view", Code = "requests.view", Name = "View Requests", NameAr = "عرض الطلبات", Description = "View service requests", SystemType = SystemType.All, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 20 },
            new() { Id = 21, PermissionGroupId = 3, Module = "requests", Action = "create", Code = "requests.create", Name = "Create Request", NameAr = "إنشاء طلب", Description = "Create service request", SystemType = SystemType.All, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 21 },
            new() { Id = 22, PermissionGroupId = 3, Module = "requests", Action = "approve", Code = "requests.approve", Name = "Approve Requests", NameAr = "الموافقة على الطلبات", Description = "Approve service requests", SystemType = SystemType.All, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 22 },
            new() { Id = 23, PermissionGroupId = 3, Module = "requests", Action = "reject", Code = "requests.reject", Name = "Reject Requests", NameAr = "رفض الطلبات", Description = "Reject service requests", SystemType = SystemType.All, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 23 },
            new() { Id = 24, PermissionGroupId = 3, Module = "requests", Action = "assign", Code = "requests.assign", Name = "Assign Requests", NameAr = "تعيين الطلبات", Description = "Assign requests to employees", SystemType = SystemType.All, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 24 },
            new() { Id = 25, PermissionGroupId = 3, Module = "requests", Action = "complete", Code = "requests.complete", Name = "Complete Requests", NameAr = "إنجاز الطلبات", Description = "Complete service requests", SystemType = SystemType.All, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 25 },
            
            // ==================== Products/Services Catalog (Group 4) ====================
            new() { Id = 30, PermissionGroupId = 4, Module = "products", Action = "view", Code = "products.view", Name = "View Products", NameAr = "عرض المنتجات", Description = "View products", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 30 },
            new() { Id = 31, PermissionGroupId = 4, Module = "products", Action = "create", Code = "products.create", Name = "Create Product", NameAr = "إضافة منتج", Description = "Create new product", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 31 },
            new() { Id = 32, PermissionGroupId = 4, Module = "products", Action = "edit", Code = "products.edit", Name = "Edit Product", NameAr = "تعديل منتج", Description = "Edit existing product", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 32 },
            new() { Id = 33, PermissionGroupId = 4, Module = "products", Action = "delete", Code = "products.delete", Name = "Delete Product", NameAr = "حذف منتج", Description = "Delete product", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 33 },
            
            // ==================== Orders (Group 5) ====================
            new() { Id = 40, PermissionGroupId = 5, Module = "orders", Action = "view", Code = "orders.view", Name = "View Orders", NameAr = "عرض الطلبيات", Description = "View orders", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 40 },
            new() { Id = 41, PermissionGroupId = 5, Module = "orders", Action = "process", Code = "orders.process", Name = "Process Orders", NameAr = "معالجة الطلبيات", Description = "Process orders", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 41 },
            new() { Id = 42, PermissionGroupId = 5, Module = "orders", Action = "cancel", Code = "orders.cancel", Name = "Cancel Orders", NameAr = "إلغاء الطلبيات", Description = "Cancel orders", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 42 },
            
            // ==================== Reports & Analytics (Group 6) ====================
            new() { Id = 50, PermissionGroupId = 6, Module = "reports", Action = "view", Code = "reports.view", Name = "View Reports", NameAr = "عرض التقارير", Description = "View reports", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 50 },
            new() { Id = 51, PermissionGroupId = 6, Module = "reports", Action = "export", Code = "reports.export", Name = "Export Reports", NameAr = "تصدير التقارير", Description = "Export reports", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 51 },
            new() { Id = 52, PermissionGroupId = 6, Module = "analytics", Action = "dashboard", Code = "analytics.dashboard", Name = "Analytics Dashboard", NameAr = "لوحة التحليلات", Description = "View analytics dashboard", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 52 },
            
            // ==================== System Settings (Group 7) ====================
            new() { Id = 60, PermissionGroupId = 7, Module = "settings", Action = "view", Code = "settings.view", Name = "View Settings", NameAr = "عرض الإعدادات", Description = "View system settings", SystemType = SystemType.SecondSystem, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 60 },
            new() { Id = 61, PermissionGroupId = 7, Module = "settings", Action = "edit", Code = "settings.edit", Name = "Edit Settings", NameAr = "تعديل الإعدادات", Description = "Edit system settings", SystemType = SystemType.SecondSystem, IsFirstSystem = false, IsSecondSystem = true, DisplayOrder = 61 },
            
            // ==================== Citizen Portal (Group 8) - يتطلب شركة مرتبطة ====================
            new() { Id = 70, PermissionGroupId = 8, Module = "citizen", Action = "view", Code = "citizen.view", Name = "View Citizens", NameAr = "عرض المواطنين", Description = "View citizens list", SystemType = SystemType.CitizenPortal, IsFirstSystem = false, IsSecondSystem = true, RequiresLinkedCompany = true, DisplayOrder = 70 },
            new() { Id = 71, PermissionGroupId = 8, Module = "citizen", Action = "create", Code = "citizen.create", Name = "Create Citizen", NameAr = "إضافة مواطن", Description = "Create new citizen", SystemType = SystemType.CitizenPortal, IsFirstSystem = false, IsSecondSystem = true, RequiresLinkedCompany = true, DisplayOrder = 71 },
            new() { Id = 72, PermissionGroupId = 8, Module = "citizen", Action = "edit", Code = "citizen.edit", Name = "Edit Citizen", NameAr = "تعديل مواطن", Description = "Edit citizen info", SystemType = SystemType.CitizenPortal, IsFirstSystem = false, IsSecondSystem = true, RequiresLinkedCompany = true, DisplayOrder = 72 },
            new() { Id = 73, PermissionGroupId = 8, Module = "citizen", Action = "delete", Code = "citizen.delete", Name = "Delete Citizen", NameAr = "حذف مواطن", Description = "Delete citizen", SystemType = SystemType.CitizenPortal, IsFirstSystem = false, IsSecondSystem = true, RequiresLinkedCompany = true, DisplayOrder = 73 },
            new() { Id = 74, PermissionGroupId = 8, Module = "citizen", Action = "portal_dashboard", Code = "citizen.portal_dashboard", Name = "Portal Dashboard", NameAr = "لوحة نظام المواطن", Description = "Access citizen portal dashboard", SystemType = SystemType.CitizenPortal, IsFirstSystem = false, IsSecondSystem = true, RequiresLinkedCompany = true, DisplayOrder = 74 },
            
            // ==================== Subscriptions (Group 9) - يتطلب شركة مرتبطة ====================
            new() { Id = 80, PermissionGroupId = 9, Module = "subscriptions", Action = "view", Code = "subscriptions.view", Name = "View Subscriptions", NameAr = "عرض الاشتراكات", Description = "View subscriptions", SystemType = SystemType.CitizenPortal, IsFirstSystem = false, IsSecondSystem = true, RequiresLinkedCompany = true, DisplayOrder = 80 },
            new() { Id = 81, PermissionGroupId = 9, Module = "subscriptions", Action = "create", Code = "subscriptions.create", Name = "Create Subscription", NameAr = "إنشاء اشتراك", Description = "Create new subscription", SystemType = SystemType.CitizenPortal, IsFirstSystem = false, IsSecondSystem = true, RequiresLinkedCompany = true, DisplayOrder = 81 },
            new() { Id = 82, PermissionGroupId = 9, Module = "subscriptions", Action = "edit", Code = "subscriptions.edit", Name = "Edit Subscription", NameAr = "تعديل اشتراك", Description = "Edit subscription", SystemType = SystemType.CitizenPortal, IsFirstSystem = false, IsSecondSystem = true, RequiresLinkedCompany = true, DisplayOrder = 82 },
            new() { Id = 83, PermissionGroupId = 9, Module = "subscriptions", Action = "cancel", Code = "subscriptions.cancel", Name = "Cancel Subscription", NameAr = "إلغاء اشتراك", Description = "Cancel subscription", SystemType = SystemType.CitizenPortal, IsFirstSystem = false, IsSecondSystem = true, RequiresLinkedCompany = true, DisplayOrder = 83 },
            new() { Id = 84, PermissionGroupId = 9, Module = "subscriptions", Action = "manage_plans", Code = "subscriptions.manage_plans", Name = "Manage Plans", NameAr = "إدارة الباقات", Description = "Manage subscription plans", SystemType = SystemType.CitizenPortal, IsFirstSystem = false, IsSecondSystem = true, RequiresLinkedCompany = true, DisplayOrder = 84 },
            
            // ==================== Payments (Group 10) ====================
            new() { Id = 85, PermissionGroupId = 10, Module = "payments", Action = "view", Code = "payments.view", Name = "View Payments", NameAr = "عرض المدفوعات", Description = "View payments", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 85 },
            new() { Id = 86, PermissionGroupId = 10, Module = "payments", Action = "record", Code = "payments.record", Name = "Record Payment", NameAr = "تسجيل دفعة", Description = "Record payment", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 86 },
            new() { Id = 87, PermissionGroupId = 10, Module = "payments", Action = "refund", Code = "payments.refund", Name = "Process Refund", NameAr = "معالجة استرداد", Description = "Process refund", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 87 },
            
            // ==================== Support Tickets (Group 11) - يتطلب شركة مرتبطة ====================
            new() { Id = 88, PermissionGroupId = 11, Module = "support", Action = "view", Code = "support.view", Name = "View Tickets", NameAr = "عرض التذاكر", Description = "View support tickets", SystemType = SystemType.CitizenPortal, IsFirstSystem = false, IsSecondSystem = true, RequiresLinkedCompany = true, DisplayOrder = 88 },
            new() { Id = 89, PermissionGroupId = 11, Module = "support", Action = "respond", Code = "support.respond", Name = "Respond to Tickets", NameAr = "الرد على التذاكر", Description = "Respond to tickets", SystemType = SystemType.CitizenPortal, IsFirstSystem = false, IsSecondSystem = true, RequiresLinkedCompany = true, DisplayOrder = 89 },
            
            // ==================== Super Admin (Group 12) ====================
            new() { Id = 90, PermissionGroupId = 12, Module = "admin", Action = "superadmin", Code = "admin.superadmin", Name = "Super Admin", NameAr = "مدير النظام الأعلى", Description = "Super admin full access", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 90 },
            new() { Id = 91, PermissionGroupId = 12, Module = "admin", Action = "firebase", Code = "admin.firebase", Name = "Firebase Management", NameAr = "إدارة Firebase", Description = "Firebase management", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 91 },
            new() { Id = 92, PermissionGroupId = 12, Module = "admin", Action = "vps", Code = "admin.vps", Name = "VPS Management", NameAr = "إدارة VPS", Description = "VPS management", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 92 },
            new() { Id = 93, PermissionGroupId = 12, Module = "admin", Action = "database", Code = "admin.database", Name = "Database Management", NameAr = "إدارة قاعدة البيانات", Description = "Database management", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 93 },
            new() { Id = 94, PermissionGroupId = 12, Module = "admin", Action = "logs", Code = "admin.logs", Name = "View Logs", NameAr = "عرض السجلات", Description = "View system logs", SystemType = SystemType.All, IsFirstSystem = true, IsSecondSystem = true, DisplayOrder = 94 },
            new() { Id = 95, PermissionGroupId = 12, Module = "admin", Action = "citizen_portal", Code = "admin.citizen_portal", Name = "Citizen Portal Admin", NameAr = "إدارة نظام المواطن", Description = "Full citizen portal management", SystemType = SystemType.CitizenPortal, IsFirstSystem = false, IsSecondSystem = true, RequiresLinkedCompany = false, DisplayOrder = 95 },
        };

        await context.Permissions.AddRangeAsync(permissions);
        await context.SaveChangesAsync();
    }

    #endregion

    #region Permission Templates

    private static async Task SeedPermissionTemplatesAsync(SadaraDbContext context)
    {
        if (await context.PermissionTemplates.AnyAsync()) return;

        // قوالب صلاحيات النظام (متاحة لجميع الشركات)
        var templates = new List<PermissionTemplate>
        {
            // قالب الموظف العادي
            new()
            {
                Id = 1,
                Code = "employee_basic",
                Name = "Basic Employee",
                NameAr = "موظف عادي",
                Description = "صلاحيات الموظف الأساسية - عرض فقط",
                SystemType = SystemType.All,
                IsSystemTemplate = true,
                IsActive = true,
                CreatedAt = DateTime.UtcNow
            },
            // قالب المشرف
            new()
            {
                Id = 2,
                Code = "supervisor",
                Name = "Supervisor",
                NameAr = "مشرف",
                Description = "صلاحيات المشرف - عرض وتعديل",
                SystemType = SystemType.All,
                IsSystemTemplate = true,
                IsActive = true,
                CreatedAt = DateTime.UtcNow
            },
            // قالب المدير
            new()
            {
                Id = 3,
                Code = "manager",
                Name = "Manager",
                NameAr = "مدير",
                Description = "صلاحيات المدير - تحكم كامل في الشركة",
                SystemType = SystemType.All,
                IsSystemTemplate = true,
                IsActive = true,
                CreatedAt = DateTime.UtcNow
            },
            // قالب موظف نظام المواطن
            new()
            {
                Id = 4,
                Code = "citizen_portal_employee",
                Name = "Citizen Portal Employee",
                NameAr = "موظف نظام المواطن",
                Description = "صلاحيات موظف نظام المواطن",
                SystemType = SystemType.CitizenPortal,
                IsSystemTemplate = true,
                IsActive = true,
                CreatedAt = DateTime.UtcNow
            },
            // قالب مدير نظام المواطن
            new()
            {
                Id = 5,
                Code = "citizen_portal_manager",
                Name = "Citizen Portal Manager",
                NameAr = "مدير نظام المواطن",
                Description = "صلاحيات مدير نظام المواطن",
                SystemType = SystemType.CitizenPortal,
                IsSystemTemplate = true,
                IsActive = true,
                CreatedAt = DateTime.UtcNow
            }
        };

        await context.PermissionTemplates.AddRangeAsync(templates);
        await context.SaveChangesAsync();

        // ربط الصلاحيات بالقوالب
        var templatePermissions = new List<TemplatePermission>
        {
            // قالب الموظف العادي - عرض فقط
            new() { TemplateId = 1, PermissionId = 1 },  // users.view
            new() { TemplateId = 1, PermissionId = 20 }, // requests.view
            new() { TemplateId = 1, PermissionId = 30 }, // products.view
            new() { TemplateId = 1, PermissionId = 40 }, // orders.view
            
            // قالب المشرف - عرض + تعديل
            new() { TemplateId = 2, PermissionId = 1 },  // users.view
            new() { TemplateId = 2, PermissionId = 20 }, // requests.view
            new() { TemplateId = 2, PermissionId = 21 }, // requests.create
            new() { TemplateId = 2, PermissionId = 22 }, // requests.approve
            new() { TemplateId = 2, PermissionId = 24 }, // requests.assign
            new() { TemplateId = 2, PermissionId = 30 }, // products.view
            new() { TemplateId = 2, PermissionId = 31 }, // products.create
            new() { TemplateId = 2, PermissionId = 32 }, // products.edit
            new() { TemplateId = 2, PermissionId = 40 }, // orders.view
            new() { TemplateId = 2, PermissionId = 41 }, // orders.process
            new() { TemplateId = 2, PermissionId = 50 }, // reports.view
            
            // قالب المدير - تحكم كامل
            new() { TemplateId = 3, PermissionId = 1 },  // users.view
            new() { TemplateId = 3, PermissionId = 2 },  // users.create
            new() { TemplateId = 3, PermissionId = 3 },  // users.edit
            new() { TemplateId = 3, PermissionId = 4 },  // users.delete
            new() { TemplateId = 3, PermissionId = 5 },  // users.permissions
            new() { TemplateId = 3, PermissionId = 20 }, // requests.view
            new() { TemplateId = 3, PermissionId = 21 }, // requests.create
            new() { TemplateId = 3, PermissionId = 22 }, // requests.approve
            new() { TemplateId = 3, PermissionId = 23 }, // requests.reject
            new() { TemplateId = 3, PermissionId = 24 }, // requests.assign
            new() { TemplateId = 3, PermissionId = 25 }, // requests.complete
            new() { TemplateId = 3, PermissionId = 30 }, // products.view
            new() { TemplateId = 3, PermissionId = 31 }, // products.create
            new() { TemplateId = 3, PermissionId = 32 }, // products.edit
            new() { TemplateId = 3, PermissionId = 33 }, // products.delete
            new() { TemplateId = 3, PermissionId = 40 }, // orders.view
            new() { TemplateId = 3, PermissionId = 41 }, // orders.process
            new() { TemplateId = 3, PermissionId = 42 }, // orders.cancel
            new() { TemplateId = 3, PermissionId = 50 }, // reports.view
            new() { TemplateId = 3, PermissionId = 51 }, // reports.export
            new() { TemplateId = 3, PermissionId = 52 }, // analytics.dashboard
            new() { TemplateId = 3, PermissionId = 60 }, // settings.view
            new() { TemplateId = 3, PermissionId = 61 }, // settings.edit
            
            // قالب موظف نظام المواطن
            new() { TemplateId = 4, PermissionId = 70 }, // citizen.view
            new() { TemplateId = 4, PermissionId = 71 }, // citizen.create
            new() { TemplateId = 4, PermissionId = 72 }, // citizen.edit
            new() { TemplateId = 4, PermissionId = 80 }, // subscriptions.view
            new() { TemplateId = 4, PermissionId = 81 }, // subscriptions.create
            new() { TemplateId = 4, PermissionId = 85 }, // payments.view
            new() { TemplateId = 4, PermissionId = 86 }, // payments.record
            new() { TemplateId = 4, PermissionId = 88 }, // support.view
            new() { TemplateId = 4, PermissionId = 89 }, // support.respond
            
            // قالب مدير نظام المواطن - تحكم كامل
            new() { TemplateId = 5, PermissionId = 70 }, // citizen.view
            new() { TemplateId = 5, PermissionId = 71 }, // citizen.create
            new() { TemplateId = 5, PermissionId = 72 }, // citizen.edit
            new() { TemplateId = 5, PermissionId = 73 }, // citizen.delete
            new() { TemplateId = 5, PermissionId = 74 }, // citizen.portal_dashboard
            new() { TemplateId = 5, PermissionId = 80 }, // subscriptions.view
            new() { TemplateId = 5, PermissionId = 81 }, // subscriptions.create
            new() { TemplateId = 5, PermissionId = 82 }, // subscriptions.edit
            new() { TemplateId = 5, PermissionId = 83 }, // subscriptions.cancel
            new() { TemplateId = 5, PermissionId = 84 }, // subscriptions.manage_plans
            new() { TemplateId = 5, PermissionId = 85 }, // payments.view
            new() { TemplateId = 5, PermissionId = 86 }, // payments.record
            new() { TemplateId = 5, PermissionId = 87 }, // payments.refund
            new() { TemplateId = 5, PermissionId = 88 }, // support.view
            new() { TemplateId = 5, PermissionId = 89 }, // support.respond
            new() { TemplateId = 5, PermissionId = 50 }, // reports.view
            new() { TemplateId = 5, PermissionId = 51 }, // reports.export
            new() { TemplateId = 5, PermissionId = 52 }, // analytics.dashboard
        };

        await context.TemplatePermissions.AddRangeAsync(templatePermissions);
        await context.SaveChangesAsync();
    }

    #endregion

    #region Services

    private static async Task SeedServicesAsync(SadaraDbContext context)
    {
        if (await context.Services.AnyAsync()) return;

        var services = new List<Service>
        {
            // خدمات صيانة المنازل
            new()
            {
                Id = 1,
                Name = "Home Maintenance",
                NameAr = "صيانة المنازل",
                Description = "خدمات إصلاح وصيانة المنازل",
                Icon = "home-repair",
                Color = "#3B82F6",
                IsActive = true,
                DisplayOrder = 1,
                CreatedAt = DateTime.UtcNow
            },
            // خدمات الكهرباء
            new()
            {
                Id = 2,
                Name = "Electrical Services",
                NameAr = "خدمات الكهرباء",
                Description = "تركيب وإصلاح الكهرباء",
                Icon = "electric-bolt",
                Color = "#F59E0B",
                IsActive = true,
                DisplayOrder = 2,
                CreatedAt = DateTime.UtcNow
            },
            // خدمات السباكة
            new()
            {
                Id = 3,
                Name = "Plumbing Services",
                NameAr = "خدمات السباكة",
                Description = "تركيب وإصلاح السباكة",
                Icon = "plumbing",
                Color = "#06B6D4",
                IsActive = true,
                DisplayOrder = 3,
                CreatedAt = DateTime.UtcNow
            },
            // خدمات التكييف
            new()
            {
                Id = 4,
                Name = "AC Services",
                NameAr = "خدمات التكييف",
                Description = "تركيب وصيانة التكييف",
                Icon = "ac-unit",
                Color = "#10B981",
                IsActive = true,
                DisplayOrder = 4,
                CreatedAt = DateTime.UtcNow
            },
            // خدمات التنظيف
            new()
            {
                Id = 5,
                Name = "Cleaning Services",
                NameAr = "خدمات التنظيف",
                Description = "خدمات التنظيف الاحترافية",
                Icon = "cleaning",
                Color = "#8B5CF6",
                IsActive = true,
                DisplayOrder = 5,
                CreatedAt = DateTime.UtcNow
            },
            // خدمات النقل
            new()
            {
                Id = 6,
                Name = "Moving Services",
                NameAr = "خدمات النقل",
                Description = "خدمات النقل والتوصيل",
                Icon = "local-shipping",
                Color = "#EF4444",
                IsActive = true,
                DisplayOrder = 6,
                CreatedAt = DateTime.UtcNow
            },
            // خدمات الدهان
            new()
            {
                Id = 7,
                Name = "Painting Services",
                NameAr = "خدمات الدهان",
                Description = "الدهان الداخلي والخارجي",
                Icon = "format-paint",
                Color = "#EC4899",
                IsActive = true,
                DisplayOrder = 7,
                CreatedAt = DateTime.UtcNow
            },
            // خدمات النجارة
            new()
            {
                Id = 8,
                Name = "Carpentry Services",
                NameAr = "خدمات النجارة",
                Description = "النجارة وأعمال الخشب",
                Icon = "carpentry",
                Color = "#A78BFA",
                IsActive = true,
                DisplayOrder = 8,
                CreatedAt = DateTime.UtcNow
            }
        };

        await context.Services.AddRangeAsync(services);
    }

    #endregion

    #region Operation Types

    private static async Task SeedOperationTypesAsync(SadaraDbContext context)
    {
        if (await context.OperationTypes.AnyAsync()) return;

        var operationTypes = new List<OperationType>
        {
            // تركيب
            new()
            {
                Id = 1,
                Name = "Installation",
                NameAr = "تركيب",
                Icon = "build",
                IsActive = true,
                RequiresApproval = false,
                RequiresTechnician = true,
                EstimatedDays = 1,
                DisplayOrder = 1,
                CreatedAt = DateTime.UtcNow
            },
            // إصلاح
            new()
            {
                Id = 2,
                Name = "Repair",
                NameAr = "إصلاح",
                Icon = "handyman",
                IsActive = true,
                RequiresApproval = false,
                RequiresTechnician = true,
                EstimatedDays = 1,
                DisplayOrder = 2,
                CreatedAt = DateTime.UtcNow
            },
            // صيانة دورية
            new()
            {
                Id = 3,
                Name = "Periodic Maintenance",
                NameAr = "صيانة دورية",
                Icon = "schedule",
                IsActive = true,
                RequiresApproval = false,
                RequiresTechnician = true,
                EstimatedDays = 1,
                DisplayOrder = 3,
                CreatedAt = DateTime.UtcNow
            },
            // فحص
            new()
            {
                Id = 4,
                Name = "Inspection",
                NameAr = "فحص",
                Icon = "search",
                IsActive = true,
                RequiresApproval = false,
                RequiresTechnician = true,
                EstimatedDays = 1,
                DisplayOrder = 4,
                CreatedAt = DateTime.UtcNow
            },
            // استبدال
            new()
            {
                Id = 5,
                Name = "Replacement",
                NameAr = "استبدال",
                Icon = "swap-horiz",
                IsActive = true,
                RequiresApproval = true,
                RequiresTechnician = true,
                EstimatedDays = 2,
                DisplayOrder = 5,
                CreatedAt = DateTime.UtcNow
            },
            // طوارئ
            new()
            {
                Id = 6,
                Name = "Emergency",
                NameAr = "طوارئ",
                Icon = "warning",
                IsActive = true,
                RequiresApproval = false,
                RequiresTechnician = true,
                EstimatedDays = 0,
                DisplayOrder = 6,
                CreatedAt = DateTime.UtcNow
            },
            // استشارة
            new()
            {
                Id = 7,
                Name = "Consultation",
                NameAr = "استشارة",
                Icon = "help",
                IsActive = true,
                RequiresApproval = false,
                RequiresTechnician = false,
                EstimatedDays = 1,
                DisplayOrder = 7,
                CreatedAt = DateTime.UtcNow
            }
        };

        await context.OperationTypes.AddRangeAsync(operationTypes);
        await context.SaveChangesAsync();

        // Seed Service Operations (linking services with operation types)
        await SeedServiceOperationsAsync(context);
    }

    private static async Task SeedServiceOperationsAsync(SadaraDbContext context)
    {
        if (await context.ServiceOperations.AnyAsync()) return;

        var serviceOperations = new List<ServiceOperation>();
        var services = await context.Services.ToListAsync();
        var operationTypes = await context.OperationTypes.ToListAsync();

        foreach (var service in services)
        {
            foreach (var opType in operationTypes)
            {
                var basePrice = (service.Id, opType.Id) switch
                {
                    // Home Maintenance prices (IQD)
                    (1, 1) => 50000m, // Installation
                    (1, 2) => 35000m, // Repair
                    (1, 3) => 25000m, // Periodic Maintenance
                    (1, 4) => 15000m, // Inspection
                    (1, 5) => 60000m, // Replacement
                    (1, 6) => 75000m, // Emergency
                    (1, 7) => 10000m, // Consultation
                    
                    // Electrical prices
                    (2, 1) => 60000m,
                    (2, 2) => 40000m,
                    (2, 3) => 30000m,
                    (2, 4) => 20000m,
                    (2, 5) => 70000m,
                    (2, 6) => 90000m,
                    (2, 7) => 15000m,
                    
                    // Default price for other combinations
                    _ => 30000m
                };

                serviceOperations.Add(new ServiceOperation
                {
                    ServiceId = service.Id,
                    OperationTypeId = opType.Id,
                    BasePrice = basePrice,
                    IsActive = true,
                    CreatedAt = DateTime.UtcNow
                });
            }
        }

        await context.ServiceOperations.AddRangeAsync(serviceOperations);
    }

    #endregion

    #region Super Admin

    private static async Task SeedSuperAdminAsync(SadaraDbContext context)
    {
        if (await context.Users.AnyAsync(u => u.Role == UserRole.SuperAdmin)) return;

        // Create password hash for "Admin@123!"
        var passwordHash = HashPassword("Admin@123!");

        var superAdmin = new User
        {
            Id = Guid.NewGuid(),
            FullName = "مدير النظام",
            PhoneNumber = "9647700000001",
            Email = "admin@sadara.iq",
            PasswordHash = passwordHash,
            Role = UserRole.SuperAdmin,
            IsActive = true,
            IsPhoneVerified = true,
            City = "Baghdad",
            Area = "Green Zone",
            CreatedAt = DateTime.UtcNow
        };

        await context.Users.AddAsync(superAdmin);
        await context.SaveChangesAsync();

        // Assign all permissions to super admin
        var permissions = await context.Permissions.ToListAsync();
        foreach (var permission in permissions)
        {
            await context.UserPermissions.AddAsync(new UserPermission
            {
                UserId = superAdmin.Id,
                PermissionId = permission.Id,
                IsGranted = true,
                GrantedAt = DateTime.UtcNow,
                GrantedById = superAdmin.Id
            });
        }
    }

    private static string HashPassword(string password)
    {
        return BCrypt.Net.BCrypt.HashPassword(password);
    }

    #endregion
}
