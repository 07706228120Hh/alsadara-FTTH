using Microsoft.EntityFrameworkCore;
using Sadara.Domain.Entities;

namespace Sadara.Infrastructure.Data;

public class SadaraDbContext : DbContext
{
    public SadaraDbContext(DbContextOptions<SadaraDbContext> options) : base(options) { }

    // Core entities
    public DbSet<User> Users => Set<User>();
    public DbSet<Merchant> Merchants => Set<Merchant>();
    public DbSet<Customer> Customers => Set<Customer>();
    public DbSet<Product> Products => Set<Product>();
    public DbSet<ProductVariant> ProductVariants => Set<ProductVariant>();
    public DbSet<Order> Orders => Set<Order>();
    public DbSet<OrderItem> OrderItems => Set<OrderItem>();
    public DbSet<OrderStatusHistory> OrderStatusHistories => Set<OrderStatusHistory>();
    public DbSet<Payment> Payments => Set<Payment>();

    // Commerce entities
    public DbSet<Category> Categories => Set<Category>();
    public DbSet<City> Cities => Set<City>();
    public DbSet<Area> Areas => Set<Area>();
    public DbSet<Review> Reviews => Set<Review>();
    public DbSet<WishlistItem> WishlistItems => Set<WishlistItem>();
    public DbSet<CartItem> CartItems => Set<CartItem>();
    public DbSet<Address> Addresses => Set<Address>();
    public DbSet<Coupon> Coupons => Set<Coupon>();

    // System entities
    public DbSet<Notification> Notifications => Set<Notification>();
    public DbSet<Advertising> Advertisings => Set<Advertising>();
    public DbSet<AppVersion> AppVersions => Set<AppVersion>();
    public DbSet<Setting> Settings => Set<Setting>();

    // Company & Multi-tenant entities (مطابق لنظام Flutter)
    public DbSet<Company> Companies => Set<Company>();
    public DbSet<CompanyService> CompanyServices => Set<CompanyService>();

    // Permission entities (نظام الصلاحيات المتقدم)
    public DbSet<PermissionGroup> PermissionGroups => Set<PermissionGroup>();
    public DbSet<Permission> Permissions => Set<Permission>();
    public DbSet<UserPermission> UserPermissions => Set<UserPermission>();
    public DbSet<PermissionTemplate> PermissionTemplates => Set<PermissionTemplate>();
    public DbSet<TemplatePermission> TemplatePermissions => Set<TemplatePermission>();

    // Service & Request entities (نظام الخدمات والطلبات)
    public DbSet<Service> Services => Set<Service>();
    public DbSet<OperationType> OperationTypes => Set<OperationType>();
    public DbSet<ServiceOperation> ServiceOperations => Set<ServiceOperation>();
    public DbSet<ServiceRequest> ServiceRequests => Set<ServiceRequest>();
    public DbSet<ServiceRequestComment> ServiceRequestComments => Set<ServiceRequestComment>();
    public DbSet<ServiceRequestAttachment> ServiceRequestAttachments => Set<ServiceRequestAttachment>();
    public DbSet<ServiceRequestStatusHistory> ServiceRequestStatusHistories => Set<ServiceRequestStatusHistory>();

    // ==================== Citizen Portal Entities (نظام المواطن) ====================
    public DbSet<Citizen> Citizens => Set<Citizen>();
    public DbSet<InternetPlan> InternetPlans => Set<InternetPlan>();
    public DbSet<CitizenSubscription> CitizenSubscriptions => Set<CitizenSubscription>();
    public DbSet<SupportTicket> SupportTickets => Set<SupportTicket>();
    public DbSet<TicketMessage> TicketMessages => Set<TicketMessage>();
    public DbSet<CitizenPayment> CitizenPayments => Set<CitizenPayment>();
    public DbSet<StoreProduct> StoreProducts => Set<StoreProduct>();
    public DbSet<ProductCategory> ProductCategories => Set<ProductCategory>();
    public DbSet<StoreOrder> StoreOrders => Set<StoreOrder>();
    public DbSet<StoreOrderItem> StoreOrderItems => Set<StoreOrderItem>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Global query filter for soft delete
        modelBuilder.Entity<User>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<Merchant>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<Customer>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<Product>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<Order>().HasQueryFilter(x => !x.IsDeleted);

        // User
        modelBuilder.Entity<User>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.PhoneNumber).IsUnique();
            entity.HasIndex(e => e.Email);
            entity.Property(e => e.FullName).HasMaxLength(100).IsRequired();
            entity.Property(e => e.PhoneNumber).HasMaxLength(20).IsRequired();
            entity.Property(e => e.Email).HasMaxLength(100);
        });

        // Merchant
        modelBuilder.Entity<Merchant>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.UserId).IsUnique();
            entity.HasOne(e => e.User).WithOne(u => u.Merchant).HasForeignKey<Merchant>(e => e.UserId);
            entity.Property(e => e.BusinessName).HasMaxLength(200).IsRequired();
            entity.Property(e => e.PhoneNumber).HasMaxLength(20).IsRequired();
            entity.Property(e => e.CommissionRate).HasPrecision(5, 2);
            entity.Property(e => e.WalletBalance).HasPrecision(18, 2);
        });

        // Customer
        modelBuilder.Entity<Customer>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.MerchantId, e.PhoneNumber }).IsUnique();
            entity.HasIndex(e => e.MerchantId);
            entity.HasIndex(e => e.City);
            entity.HasIndex(e => e.CreatedAt);
            entity.HasOne(e => e.Merchant).WithMany(m => m.Customers).HasForeignKey(e => e.MerchantId);
            entity.Property(e => e.FullName).HasMaxLength(100).IsRequired();
            entity.Property(e => e.PhoneNumber).HasMaxLength(20).IsRequired();
            entity.Property(e => e.CustomerCode).HasMaxLength(20).IsRequired();
            entity.Property(e => e.TotalSpent).HasPrecision(18, 2);
            entity.Property(e => e.WalletBalance).HasPrecision(18, 2);
        });

        // Product
        modelBuilder.Entity<Product>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.MerchantId);
            entity.HasIndex(e => e.SKU);
            entity.HasOne(e => e.Merchant).WithMany(m => m.Products).HasForeignKey(e => e.MerchantId);
            entity.HasOne(e => e.Category).WithMany(c => c.Products).HasForeignKey(e => e.CategoryId);
            entity.Property(e => e.Name).HasMaxLength(200).IsRequired();
            entity.Property(e => e.SKU).HasMaxLength(50);
            entity.Property(e => e.Price).HasPrecision(18, 2);
            entity.Property(e => e.DiscountPrice).HasPrecision(18, 2);
            entity.Property(e => e.CostPrice).HasPrecision(18, 2);
            entity.Property(e => e.AverageRating).HasPrecision(3, 2);
        });

        // Category
        modelBuilder.Entity<Category>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasOne(e => e.ParentCategory).WithMany(c => c.SubCategories).HasForeignKey(e => e.ParentCategoryId);
            entity.Property(e => e.Name).HasMaxLength(100).IsRequired();
            entity.Property(e => e.NameAr).HasMaxLength(100).IsRequired();
        });

        // City
        modelBuilder.Entity<City>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Name).HasMaxLength(100).IsRequired();
            entity.Property(e => e.NameAr).HasMaxLength(100).IsRequired();
            entity.Property(e => e.DeliveryFee).HasPrecision(18, 2);
        });

        // Area
        modelBuilder.Entity<Area>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasOne(e => e.City).WithMany(c => c.Areas).HasForeignKey(e => e.CityId);
            entity.Property(e => e.Name).HasMaxLength(100).IsRequired();
            entity.Property(e => e.NameAr).HasMaxLength(100).IsRequired();
            entity.Property(e => e.DeliveryFee).HasPrecision(18, 2);
        });

        // Review
        modelBuilder.Entity<Review>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.ProductId, e.CustomerId }).IsUnique();
            entity.HasOne(e => e.Product).WithMany(p => p.Reviews).HasForeignKey(e => e.ProductId);
            entity.HasOne(e => e.Customer).WithMany().HasForeignKey(e => e.CustomerId);
        });

        // WishlistItem
        modelBuilder.Entity<WishlistItem>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.CustomerId, e.ProductId }).IsUnique();
            entity.HasOne(e => e.Customer).WithMany().HasForeignKey(e => e.CustomerId);
            entity.HasOne(e => e.Product).WithMany().HasForeignKey(e => e.ProductId);
        });

        // CartItem
        modelBuilder.Entity<CartItem>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.CustomerId, e.ProductId }).IsUnique();
            entity.HasOne(e => e.Customer).WithMany().HasForeignKey(e => e.CustomerId);
            entity.HasOne(e => e.Product).WithMany().HasForeignKey(e => e.ProductId);
        });

        // Address
        modelBuilder.Entity<Address>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.CustomerId);
            entity.HasOne(e => e.Customer).WithMany().HasForeignKey(e => e.CustomerId);
            entity.HasOne(e => e.City).WithMany().HasForeignKey(e => e.CityId);
            entity.HasOne(e => e.Area).WithMany().HasForeignKey(e => e.AreaId);
            entity.Property(e => e.Label).HasMaxLength(50).IsRequired();
            entity.Property(e => e.FullAddress).HasMaxLength(500).IsRequired();
        });

        // Coupon
        modelBuilder.Entity<Coupon>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.Code).IsUnique();
            entity.Property(e => e.Code).HasMaxLength(50).IsRequired();
            entity.Property(e => e.DiscountValue).HasPrecision(18, 2);
            entity.Property(e => e.MinimumOrderAmount).HasPrecision(18, 2);
            entity.Property(e => e.MaximumDiscountAmount).HasPrecision(18, 2);
        });

        // ProductVariant
        modelBuilder.Entity<ProductVariant>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasOne(e => e.Product).WithMany(p => p.Variants).HasForeignKey(e => e.ProductId);
            entity.Property(e => e.Name).HasMaxLength(100).IsRequired();
            entity.Property(e => e.PriceAdjustment).HasPrecision(18, 2);
        });

        // Order
        modelBuilder.Entity<Order>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.OrderNumber).IsUnique();
            entity.HasIndex(e => e.MerchantId);
            entity.HasIndex(e => e.CustomerId);
            entity.HasIndex(e => e.Status);
            entity.HasIndex(e => e.CreatedAt);
            entity.HasOne(e => e.Merchant).WithMany(m => m.Orders).HasForeignKey(e => e.MerchantId);
            entity.HasOne(e => e.Customer).WithMany(c => c.Orders).HasForeignKey(e => e.CustomerId);
            entity.Property(e => e.OrderNumber).HasMaxLength(50).IsRequired();
            entity.Property(e => e.SubTotal).HasPrecision(18, 2);
            entity.Property(e => e.DiscountAmount).HasPrecision(18, 2);
            entity.Property(e => e.DeliveryFee).HasPrecision(18, 2);
            entity.Property(e => e.TotalAmount).HasPrecision(18, 2);
        });

        // OrderItem
        modelBuilder.Entity<OrderItem>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasOne(e => e.Order).WithMany(o => o.Items).HasForeignKey(e => e.OrderId);
            entity.HasOne(e => e.Product).WithMany(p => p.OrderItems).HasForeignKey(e => e.ProductId);
            entity.Property(e => e.ProductName).HasMaxLength(200).IsRequired();
            entity.Property(e => e.UnitPrice).HasPrecision(18, 2);
            entity.Property(e => e.DiscountAmount).HasPrecision(18, 2);
            entity.Property(e => e.TotalPrice).HasPrecision(18, 2);
        });

        // OrderStatusHistory
        modelBuilder.Entity<OrderStatusHistory>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasOne(e => e.Order).WithMany(o => o.StatusHistory).HasForeignKey(e => e.OrderId);
        });

        // Payment
        modelBuilder.Entity<Payment>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.TransactionId);
            entity.HasOne(e => e.Order).WithMany(o => o.Payments).HasForeignKey(e => e.OrderId);
            entity.Property(e => e.Amount).HasPrecision(18, 2);
        });

        // Notification
        modelBuilder.Entity<Notification>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.UserId);
            entity.Property(e => e.Title).HasMaxLength(200).IsRequired();
        });

        // Setting
        modelBuilder.Entity<Setting>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.Key).IsUnique();
            entity.Property(e => e.Key).HasMaxLength(100).IsRequired();
            entity.Property(e => e.Value).HasMaxLength(1000);
        });

        // Advertising
        modelBuilder.Entity<Advertising>(entity =>
        {
            entity.HasKey(e => e.Id);
        });

        // AppVersion
        modelBuilder.Entity<AppVersion>(entity =>
        {
            entity.HasKey(e => e.Id);
        });

        // ==================== Company & Multi-tenant Entities ====================
        
        // Company (مطابق لـ Tenant في Flutter)
        modelBuilder.Entity<Company>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.Code).IsUnique();
            entity.HasIndex(e => e.Name);
            entity.HasIndex(e => e.AdminUserId);
            entity.Property(e => e.Name).HasMaxLength(200).IsRequired();
            entity.Property(e => e.Code).HasMaxLength(50).IsRequired();
            entity.Property(e => e.Email).HasMaxLength(100);
            entity.Property(e => e.Phone).HasMaxLength(20);
            entity.Property(e => e.Address).HasMaxLength(500);
            entity.Property(e => e.City).HasMaxLength(100);
            entity.Property(e => e.LogoUrl).HasMaxLength(500);
            entity.Property(e => e.Description).HasMaxLength(1000);
            entity.Property(e => e.SuspensionReason).HasMaxLength(500);
            entity.Property(e => e.EnabledFirstSystemFeatures).HasColumnType("text"); // JSON
            entity.Property(e => e.EnabledSecondSystemFeatures).HasColumnType("text"); // JSON
            entity.HasOne(e => e.AdminUser).WithMany().HasForeignKey(e => e.AdminUserId).OnDelete(DeleteBehavior.SetNull);
        });

        // CompanyService (ربط الشركات بالخدمات)
        modelBuilder.Entity<CompanyService>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.CompanyId, e.ServiceId }).IsUnique();
            entity.HasOne(e => e.Company).WithMany(c => c.CompanyServices).HasForeignKey(e => e.CompanyId);
            entity.HasOne(e => e.Service).WithMany(s => s.CompanyServices).HasForeignKey(e => e.ServiceId);
            entity.Property(e => e.CustomSettings).HasColumnType("text"); // JSON
        });

        // User-Company relationship update
        modelBuilder.Entity<User>(entity =>
        {
            // Existing configurations are already defined above
            // Add Company relationship
            entity.HasOne(e => e.Company).WithMany(c => c.Employees).HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.SetNull);
            entity.HasIndex(e => e.CompanyId);
            entity.Property(e => e.Department).HasMaxLength(100);
            entity.Property(e => e.EmployeeCode).HasMaxLength(50);
            entity.Property(e => e.Center).HasMaxLength(100);
            entity.Property(e => e.Salary).HasPrecision(18, 2);
            entity.Property(e => e.FirstSystemPermissions).HasColumnType("text"); // JSON
            entity.Property(e => e.SecondSystemPermissions).HasColumnType("text"); // JSON
        });

        // ==================== Permission Entities ====================

        // Permission (صلاحية فردية)
        modelBuilder.Entity<Permission>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.Code).IsUnique();
            entity.HasIndex(e => e.Module);
            entity.HasIndex(e => e.PermissionGroupId);
            entity.Property(e => e.Module).HasMaxLength(100).IsRequired();
            entity.Property(e => e.Action).HasMaxLength(100).IsRequired();
            entity.Property(e => e.Code).HasMaxLength(100).IsRequired();
            entity.Property(e => e.Name).HasMaxLength(200).IsRequired();
            entity.Property(e => e.NameAr).HasMaxLength(200).IsRequired();
            entity.Property(e => e.Description).HasMaxLength(500);
            entity.HasOne(e => e.PermissionGroup).WithMany(g => g.Permissions).HasForeignKey(e => e.PermissionGroupId).OnDelete(DeleteBehavior.SetNull);
        });

        // UserPermission (صلاحية مُسندة لمستخدم)
        modelBuilder.Entity<UserPermission>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.UserId, e.PermissionId }).IsUnique();
            entity.HasOne(e => e.User).WithMany(u => u.UserPermissions).HasForeignKey(e => e.UserId);
            entity.HasOne(e => e.Permission).WithMany(p => p.UserPermissions).HasForeignKey(e => e.PermissionId);
            entity.HasOne(e => e.GrantedBy).WithMany().HasForeignKey(e => e.GrantedById).OnDelete(DeleteBehavior.SetNull);
            entity.Property(e => e.Notes).HasMaxLength(500);
        });

        // PermissionGroup (مجموعة صلاحيات)
        modelBuilder.Entity<PermissionGroup>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.Code).IsUnique();
            entity.Property(e => e.Code).HasMaxLength(100).IsRequired();
            entity.Property(e => e.Name).HasMaxLength(200).IsRequired();
            entity.Property(e => e.NameAr).HasMaxLength(200).IsRequired();
            entity.Property(e => e.Description).HasMaxLength(500);
            entity.Property(e => e.Icon).HasMaxLength(100);
        });

        // PermissionTemplate (قالب صلاحيات)
        modelBuilder.Entity<PermissionTemplate>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.Code).IsUnique();
            entity.HasIndex(e => e.CompanyId);
            entity.Property(e => e.Code).HasMaxLength(100).IsRequired();
            entity.Property(e => e.Name).HasMaxLength(200).IsRequired();
            entity.Property(e => e.NameAr).HasMaxLength(200).IsRequired();
            entity.Property(e => e.Description).HasMaxLength(500);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Cascade);
        });

        // TemplatePermission (ربط القالب بالصلاحية)
        modelBuilder.Entity<TemplatePermission>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.TemplateId, e.PermissionId }).IsUnique();
            entity.HasOne(e => e.Template).WithMany(t => t.TemplatePermissions).HasForeignKey(e => e.TemplateId).OnDelete(DeleteBehavior.Cascade);
            entity.HasOne(e => e.Permission).WithMany(p => p.TemplatePermissions).HasForeignKey(e => e.PermissionId).OnDelete(DeleteBehavior.Cascade);
        });

        // ==================== Service & Request Entities ====================

        // Service (خدمة رئيسية)
        modelBuilder.Entity<Service>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Name).HasMaxLength(200).IsRequired();
            entity.Property(e => e.NameAr).HasMaxLength(200).IsRequired();
            entity.Property(e => e.Description).HasMaxLength(500);
            entity.Property(e => e.Icon).HasMaxLength(100);
            entity.Property(e => e.Color).HasMaxLength(20);
        });

        // OperationType (نوع العملية)
        modelBuilder.Entity<OperationType>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Name).HasMaxLength(200).IsRequired();
            entity.Property(e => e.NameAr).HasMaxLength(200).IsRequired();
            entity.Property(e => e.Icon).HasMaxLength(100);
        });

        // ServiceOperation (ربط الخدمة بالعملية)
        modelBuilder.Entity<ServiceOperation>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.ServiceId, e.OperationTypeId }).IsUnique();
            entity.HasOne(e => e.Service).WithMany(s => s.Operations).HasForeignKey(e => e.ServiceId);
            entity.HasOne(e => e.OperationType).WithMany(o => o.ServiceOperations).HasForeignKey(e => e.OperationTypeId);
            entity.Property(e => e.BasePrice).HasPrecision(18, 2);
            entity.Property(e => e.CustomSettings).HasColumnType("text"); // JSON
        });

        // ServiceRequest (طلب خدمة)
        modelBuilder.Entity<ServiceRequest>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.RequestNumber).IsUnique();
            entity.HasIndex(e => e.CompanyId);
            entity.HasIndex(e => e.CitizenId);
            entity.HasIndex(e => e.AssignedToId);
            entity.HasIndex(e => e.Status);
            entity.HasIndex(e => e.Priority);
            entity.HasIndex(e => e.CreatedAt);
            entity.Property(e => e.RequestNumber).HasMaxLength(50).IsRequired();
            entity.Property(e => e.Details).HasColumnType("text"); // JSON
            entity.Property(e => e.Address).HasMaxLength(500);
            entity.Property(e => e.City).HasMaxLength(100);
            entity.Property(e => e.Area).HasMaxLength(100);
            entity.Property(e => e.ContactPhone).HasMaxLength(20);
            entity.Property(e => e.StatusNote).HasMaxLength(500);
            entity.Property(e => e.RatingComment).HasMaxLength(1000);
            entity.Property(e => e.EstimatedCost).HasPrecision(18, 2);
            entity.Property(e => e.FinalCost).HasPrecision(18, 2);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.Service).WithMany().HasForeignKey(e => e.ServiceId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.OperationType).WithMany().HasForeignKey(e => e.OperationTypeId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.Citizen).WithMany().HasForeignKey(e => e.CitizenId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.AssignedTo).WithMany().HasForeignKey(e => e.AssignedToId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.Technician).WithMany().HasForeignKey(e => e.TechnicianId).OnDelete(DeleteBehavior.SetNull);
        });

        // ServiceRequestComment (تعليق على طلب)
        modelBuilder.Entity<ServiceRequestComment>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.ServiceRequestId);
            entity.Property(e => e.Content).HasColumnType("text").IsRequired();
            entity.HasOne(e => e.ServiceRequest).WithMany(r => r.Comments).HasForeignKey(e => e.ServiceRequestId);
            entity.HasOne(e => e.User).WithMany().HasForeignKey(e => e.UserId).OnDelete(DeleteBehavior.Restrict);
        });

        // ServiceRequestAttachment (مرفق طلب)
        modelBuilder.Entity<ServiceRequestAttachment>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.ServiceRequestId);
            entity.Property(e => e.FileName).HasMaxLength(200).IsRequired();
            entity.Property(e => e.FileUrl).HasMaxLength(500).IsRequired();
            entity.Property(e => e.FileType).HasMaxLength(100);
            entity.Property(e => e.Description).HasMaxLength(500);
            entity.HasOne(e => e.ServiceRequest).WithMany(r => r.Attachments).HasForeignKey(e => e.ServiceRequestId);
            entity.HasOne(e => e.UploadedBy).WithMany().HasForeignKey(e => e.UploadedById).OnDelete(DeleteBehavior.Restrict);
        });

        // ServiceRequestStatusHistory (تاريخ حالات الطلب)
        modelBuilder.Entity<ServiceRequestStatusHistory>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.ServiceRequestId);
            entity.Property(e => e.Note).HasMaxLength(500);
            entity.HasOne(e => e.ServiceRequest).WithMany(r => r.StatusHistory).HasForeignKey(e => e.ServiceRequestId);
            entity.HasOne(e => e.ChangedBy).WithMany().HasForeignKey(e => e.ChangedById).OnDelete(DeleteBehavior.Restrict);
        });

        // ==================== Citizen Portal Entities ====================

        // Citizen (المواطن)
        modelBuilder.Entity<Citizen>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.PhoneNumber).IsUnique();
            entity.HasIndex(e => e.CompanyId);
            entity.HasIndex(e => e.City);
            entity.HasQueryFilter(e => !e.IsDeleted);
            entity.Property(e => e.FullName).HasMaxLength(100).IsRequired();
            entity.Property(e => e.PhoneNumber).HasMaxLength(20).IsRequired();
            entity.Property(e => e.Email).HasMaxLength(100);
            entity.Property(e => e.City).HasMaxLength(100);
            entity.Property(e => e.District).HasMaxLength(100);
            entity.Property(e => e.FullAddress).HasMaxLength(500);
            entity.Property(e => e.LanguagePreference).HasMaxLength(10).HasDefaultValue("ar");
            entity.Property(e => e.TotalPaid).HasPrecision(18, 2);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.AssignedBy).WithMany().HasForeignKey(e => e.AssignedById).OnDelete(DeleteBehavior.SetNull);
        });

        // InternetPlan (باقة الاشتراك)
        modelBuilder.Entity<InternetPlan>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.CompanyId);
            entity.Property(e => e.Name).HasMaxLength(100).IsRequired();
            entity.Property(e => e.NameAr).HasMaxLength(100).IsRequired();
            entity.Property(e => e.Description).HasMaxLength(500);
            entity.Property(e => e.MonthlyPrice).HasPrecision(18, 2);
            entity.Property(e => e.YearlyPrice).HasPrecision(18, 2);
            entity.Property(e => e.InstallationFee).HasPrecision(18, 2);
            entity.Property(e => e.Features).HasColumnType("text");
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Cascade);
        });

        // CitizenSubscription (اشتراك المواطن)
        modelBuilder.Entity<CitizenSubscription>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.SubscriptionNumber).IsUnique();
            entity.HasIndex(e => e.CitizenId);
            entity.HasIndex(e => e.CompanyId);
            entity.HasIndex(e => e.Status);
            entity.Property(e => e.SubscriptionNumber).HasMaxLength(50).IsRequired();
            entity.Property(e => e.InstallationAddress).HasMaxLength(500);
            entity.Property(e => e.RouterSerialNumber).HasMaxLength(100);
            entity.Property(e => e.RouterModel).HasMaxLength(100);
            entity.Property(e => e.ONUSerialNumber).HasMaxLength(100);
            entity.Property(e => e.AgreedPrice).HasPrecision(18, 2);
            entity.Property(e => e.InstallationFee).HasPrecision(18, 2);
            entity.Property(e => e.TotalPaid).HasPrecision(18, 2);
            entity.Property(e => e.OutstandingBalance).HasPrecision(18, 2);
            entity.HasOne(e => e.Citizen).WithMany(c => c.Subscriptions).HasForeignKey(e => e.CitizenId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.Plan).WithMany(p => p.CitizenSubscriptions).HasForeignKey(e => e.InternetPlanId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.InstalledBy).WithMany().HasForeignKey(e => e.InstalledById).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.CancelledBy).WithMany().HasForeignKey(e => e.CancelledById).OnDelete(DeleteBehavior.SetNull);
        });

        // SupportTicket (تذكرة الدعم)
        modelBuilder.Entity<SupportTicket>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.TicketNumber).IsUnique();
            entity.HasIndex(e => e.CitizenId);
            entity.HasIndex(e => e.CompanyId);
            entity.HasIndex(e => e.Status);
            entity.Property(e => e.TicketNumber).HasMaxLength(50).IsRequired();
            entity.Property(e => e.Subject).HasMaxLength(200).IsRequired();
            entity.Property(e => e.Description).HasColumnType("text");
            entity.Property(e => e.ResolutionNotes).HasColumnType("text");
            entity.Property(e => e.Attachments).HasColumnType("text");
            entity.HasOne(e => e.Citizen).WithMany(c => c.SupportTickets).HasForeignKey(e => e.CitizenId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.AssignedTo).WithMany().HasForeignKey(e => e.AssignedToId).OnDelete(DeleteBehavior.SetNull);
        });

        // TicketMessage (رسالة في التذكرة)
        modelBuilder.Entity<TicketMessage>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.TicketId);
            entity.Property(e => e.Content).HasColumnType("text").IsRequired();
            entity.Property(e => e.Attachments).HasColumnType("text");
            entity.HasOne(e => e.Ticket).WithMany(t => t.Messages).HasForeignKey(e => e.TicketId).OnDelete(DeleteBehavior.Cascade);
            entity.HasOne(e => e.User).WithMany().HasForeignKey(e => e.UserId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.Citizen).WithMany().HasForeignKey(e => e.CitizenId).OnDelete(DeleteBehavior.SetNull);
        });

        // CitizenPayment (مدفوعات المواطن)
        modelBuilder.Entity<CitizenPayment>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.TransactionNumber).IsUnique();
            entity.HasIndex(e => e.CitizenId);
            entity.HasIndex(e => e.CompanyId);
            entity.HasIndex(e => e.Status);
            entity.Property(e => e.TransactionNumber).HasMaxLength(100).IsRequired();
            entity.Property(e => e.Amount).HasPrecision(18, 2);
            entity.Property(e => e.ExternalTransactionId).HasMaxLength(200);
            entity.Property(e => e.GatewayResponse).HasColumnType("text");
            entity.HasOne(e => e.Citizen).WithMany(c => c.Payments).HasForeignKey(e => e.CitizenId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.Subscription).WithMany(s => s.Payments).HasForeignKey(e => e.CitizenSubscriptionId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.RecordedBy).WithMany().HasForeignKey(e => e.RecordedById).OnDelete(DeleteBehavior.SetNull);
        });

        // ProductCategory (تصنيف المنتجات)
        modelBuilder.Entity<ProductCategory>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.CompanyId);
            entity.Property(e => e.Name).HasMaxLength(100).IsRequired();
            entity.Property(e => e.NameAr).HasMaxLength(100).IsRequired();
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Cascade);
        });

        // StoreProduct (منتج في المتجر)
        modelBuilder.Entity<StoreProduct>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.CompanyId);
            entity.HasIndex(e => e.CategoryId);
            entity.Property(e => e.Name).HasMaxLength(200).IsRequired();
            entity.Property(e => e.NameAr).HasMaxLength(200).IsRequired();
            entity.Property(e => e.SKU).HasMaxLength(50);
            entity.Property(e => e.Price).HasPrecision(18, 2);
            entity.Property(e => e.DiscountPrice).HasPrecision(18, 2);
            entity.Property(e => e.AverageRating).HasPrecision(3, 2);
            entity.Property(e => e.AdditionalImages).HasColumnType("text");
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.Category).WithMany(c => c.Products).HasForeignKey(e => e.CategoryId).OnDelete(DeleteBehavior.SetNull);
        });

        // StoreOrder (طلب من المتجر)
        modelBuilder.Entity<StoreOrder>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.OrderNumber).IsUnique();
            entity.HasIndex(e => e.CitizenId);
            entity.HasIndex(e => e.CompanyId);
            entity.HasIndex(e => e.Status);
            entity.Property(e => e.OrderNumber).HasMaxLength(50).IsRequired();
            entity.Property(e => e.DeliveryAddress).HasMaxLength(500);
            entity.Property(e => e.ContactPhone).HasMaxLength(20);
            entity.Property(e => e.SubTotal).HasPrecision(18, 2);
            entity.Property(e => e.DeliveryFee).HasPrecision(18, 2);
            entity.Property(e => e.DiscountAmount).HasPrecision(18, 2);
            entity.Property(e => e.TotalAmount).HasPrecision(18, 2);
            entity.HasOne(e => e.Citizen).WithMany().HasForeignKey(e => e.CitizenId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.DeliveredBy).WithMany().HasForeignKey(e => e.DeliveredById).OnDelete(DeleteBehavior.SetNull);
        });

        // StoreOrderItem (عنصر في الطلب)
        modelBuilder.Entity<StoreOrderItem>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.StoreOrderId);
            entity.Property(e => e.ProductName).HasMaxLength(200).IsRequired();
            entity.Property(e => e.UnitPrice).HasPrecision(18, 2);
            entity.Property(e => e.TotalPrice).HasPrecision(18, 2);
            entity.HasOne(e => e.Order).WithMany(o => o.Items).HasForeignKey(e => e.StoreOrderId).OnDelete(DeleteBehavior.Cascade);
            entity.HasOne(e => e.Product).WithMany(p => p.OrderItems).HasForeignKey(e => e.ProductId).OnDelete(DeleteBehavior.Restrict);
        });
    }

    public override Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        foreach (var entry in ChangeTracker.Entries<BaseEntity>())
        {
            switch (entry.State)
            {
                case EntityState.Added:
                    entry.Entity.CreatedAt = DateTime.UtcNow;
                    break;
                case EntityState.Modified:
                    entry.Entity.UpdatedAt = DateTime.UtcNow;
                    break;
            }
        }
        return base.SaveChangesAsync(cancellationToken);
    }
}
