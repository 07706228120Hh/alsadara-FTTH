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

    // Subscription Logs (سجل عمليات الاشتراكات - بديل Google Sheets)
    public DbSet<SubscriptionLog> SubscriptionLogs => Set<SubscriptionLog>();

    // ==================== Agent System (نظام الوكلاء) ====================
    public DbSet<Agent> Agents => Set<Agent>();
    public DbSet<AgentTransaction> AgentTransactions => Set<AgentTransaction>();
    public DbSet<AgentCommissionRate> AgentCommissionRates => Set<AgentCommissionRate>();

    // ==================== Attendance & Work Centers (الحضور والمراكز) ====================
    public DbSet<AttendanceRecord> AttendanceRecords => Set<AttendanceRecord>();
    public DbSet<WorkCenter> WorkCenters => Set<WorkCenter>();
    public DbSet<AttendanceAuditLog> AttendanceAuditLogs => Set<AttendanceAuditLog>();
    public DbSet<WorkSchedule> WorkSchedules => Set<WorkSchedule>();

    // ==================== Leave Management (نظام الإجازات) ====================
    public DbSet<LeaveRequest> LeaveRequests => Set<LeaveRequest>();
    public DbSet<WithdrawalRequest> WithdrawalRequests => Set<WithdrawalRequest>();
    public DbSet<LeaveBalance> LeaveBalances => Set<LeaveBalance>();

    // ==================== ISP Data (بيانات مشتركي الإنترنت) ====================
    public DbSet<ISPSubscriber> ISPSubscribers => Set<ISPSubscriber>();
    public DbSet<IptvSubscriber> IptvSubscribers => Set<IptvSubscriber>();
    public DbSet<ZoneStatistic> ZoneStatistics => Set<ZoneStatistic>();

    // ==================== Accounting System (نظام المحاسبة) ====================
    public DbSet<Account> Accounts => Set<Account>();
    public DbSet<JournalEntry> JournalEntries => Set<JournalEntry>();
    public DbSet<JournalEntryLine> JournalEntryLines => Set<JournalEntryLine>();
    public DbSet<CashBox> CashBoxes => Set<CashBox>();
    public DbSet<CashTransaction> CashTransactions => Set<CashTransaction>();
    public DbSet<EmployeeSalary> EmployeeSalaries => Set<EmployeeSalary>();
    public DbSet<SalaryPolicy> SalaryPolicies => Set<SalaryPolicy>();
    public DbSet<TechnicianCollection> TechnicianCollections => Set<TechnicianCollection>();
    public DbSet<TechnicianTransaction> TechnicianTransactions => Set<TechnicianTransaction>();
    public DbSet<Expense> Expenses => Set<Expense>();
    public DbSet<EmployeeDeductionBonus> EmployeeDeductionBonuses => Set<EmployeeDeductionBonus>();
    public DbSet<FixedExpense> FixedExpenses => Set<FixedExpense>();
    public DbSet<FixedExpensePayment> FixedExpensePayments => Set<FixedExpensePayment>();

    // ==================== Task Audit (تدقيق المهام) ====================
    public DbSet<TaskAudit> TaskAudits => Set<TaskAudit>();

    // ==================== Departments (أقسام الشركة ومهامها) ====================
    public DbSet<Department> Departments => Set<Department>();
    public DbSet<DepartmentTask> DepartmentTasks => Set<DepartmentTask>();

    // ==================== Daily Settlement Reports (تقارير التسديدات اليومية) ====================
    public DbSet<DailySettlementReport> DailySettlementReports => Set<DailySettlementReport>();

    // ==================== WhatsApp Conversations (محادثات واتساب) ====================
    public DbSet<WhatsAppConversation> WhatsAppConversations => Set<WhatsAppConversation>();
    public DbSet<WhatsAppMessage> WhatsAppMessages => Set<WhatsAppMessage>();
    public DbSet<WhatsAppBatchReport> WhatsAppBatchReports => Set<WhatsAppBatchReport>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Global query filter for soft delete
        modelBuilder.Entity<User>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<Merchant>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<Customer>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<Product>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<Order>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<SubscriptionLog>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<Agent>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<AgentTransaction>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<AgentCommissionRate>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<AttendanceRecord>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<AttendanceRecord>()
            .Property(e => e.Status).HasConversion<int>().HasDefaultValue(AttendanceStatus.Present);
        modelBuilder.Entity<AttendanceRecord>()
            .HasOne(e => e.WorkSchedule).WithMany().HasForeignKey(e => e.WorkScheduleId).OnDelete(DeleteBehavior.SetNull);
        modelBuilder.Entity<WorkCenter>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<AttendanceAuditLog>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<WorkSchedule>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<LeaveRequest>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<LeaveRequest>()
            .Property(e => e.LeaveType).HasConversion<int>();
        modelBuilder.Entity<LeaveRequest>()
            .Property(e => e.Status).HasConversion<int>().HasDefaultValue(LeaveRequestStatus.Pending);
        modelBuilder.Entity<LeaveBalance>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<LeaveBalance>()
            .Property(e => e.LeaveType).HasConversion<int>();
        modelBuilder.Entity<WithdrawalRequest>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<WithdrawalRequest>()
            .Property(e => e.Status).HasConversion<int>().HasDefaultValue(WithdrawalRequestStatus.Pending);
        modelBuilder.Entity<ISPSubscriber>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<IptvSubscriber>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<ZoneStatistic>().HasQueryFilter(x => !x.IsDeleted);

        // Accounting entities query filters
        modelBuilder.Entity<Account>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<JournalEntry>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<JournalEntryLine>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<CashBox>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<CashTransaction>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<EmployeeSalary>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<SalaryPolicy>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<TechnicianCollection>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<TechnicianTransaction>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<Expense>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<EmployeeDeductionBonus>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<FixedExpense>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<FixedExpensePayment>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<TaskAudit>().HasQueryFilter(x => !x.IsDeleted);

        // Department entities query filters
        modelBuilder.Entity<Department>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<DepartmentTask>().HasQueryFilter(x => !x.IsDeleted);

        // Daily Settlement Reports
        modelBuilder.Entity<DailySettlementReport>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<DailySettlementReport>()
            .Property(e => e.ItemsJson).HasColumnType("jsonb");

        // WhatsApp Conversations
        modelBuilder.Entity<WhatsAppConversation>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<WhatsAppConversation>()
            .HasIndex(x => x.PhoneNumber).IsUnique();
        modelBuilder.Entity<WhatsAppConversation>()
            .HasIndex(x => x.LastMessageTime);

        modelBuilder.Entity<WhatsAppMessage>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<WhatsAppMessage>()
            .HasOne(m => m.Conversation)
            .WithMany(c => c.Messages)
            .HasForeignKey(m => m.ConversationId)
            .OnDelete(DeleteBehavior.Cascade);
        modelBuilder.Entity<WhatsAppMessage>()
            .HasIndex(x => x.ExternalMessageId);
        modelBuilder.Entity<WhatsAppMessage>()
            .HasIndex(x => new { x.ConversationId, x.CreatedAt });

        // WhatsApp Batch Reports
        modelBuilder.Entity<WhatsAppBatchReport>().HasQueryFilter(x => !x.IsDeleted);
        modelBuilder.Entity<WhatsAppBatchReport>()
            .HasIndex(x => x.BatchId).IsUnique();

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

        // Department (أقسام الشركة)
        modelBuilder.Entity<Department>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.CompanyId);
            entity.HasIndex(e => new { e.CompanyId, e.NameAr }).IsUnique();
            entity.Property(e => e.NameAr).HasMaxLength(100).IsRequired();
            entity.Property(e => e.Name).HasMaxLength(100);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Cascade);
        });

        // DepartmentTask (مهام القسم)
        modelBuilder.Entity<DepartmentTask>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.DepartmentId);
            entity.HasIndex(e => new { e.DepartmentId, e.NameAr }).IsUnique();
            entity.Property(e => e.NameAr).HasMaxLength(100).IsRequired();
            entity.Property(e => e.Name).HasMaxLength(100);
            entity.HasOne(e => e.Department).WithMany(d => d.Tasks).HasForeignKey(e => e.DepartmentId).OnDelete(DeleteBehavior.Cascade);
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
            entity.HasIndex(e => e.AgentId);
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
            entity.HasOne(e => e.Citizen).WithMany().HasForeignKey(e => e.CitizenId).IsRequired(false).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.Agent).WithMany().HasForeignKey(e => e.AgentId).IsRequired(false).OnDelete(DeleteBehavior.SetNull);
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
            entity.HasOne(e => e.ChangedBy).WithMany().HasForeignKey(e => e.ChangedById).IsRequired(false).OnDelete(DeleteBehavior.SetNull);
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
            entity.Property(e => e.ProfitAmount).HasPrecision(18, 2);
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

        // ==================== Agent System (نظام الوكلاء) ====================

        // Agent (الوكيل)
        modelBuilder.Entity<Agent>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.AgentCode).IsUnique();
            entity.HasIndex(e => e.PhoneNumber).IsUnique();
            entity.HasIndex(e => e.CompanyId);
            entity.HasIndex(e => e.Status);
            entity.Property(e => e.AgentCode).HasMaxLength(20).IsRequired();
            entity.Property(e => e.Name).HasMaxLength(100).IsRequired();
            entity.Property(e => e.PhoneNumber).HasMaxLength(20).IsRequired();
            entity.Property(e => e.PasswordHash).HasMaxLength(500).IsRequired();
            entity.Property(e => e.Email).HasMaxLength(100);
            entity.Property(e => e.City).HasMaxLength(100);
            entity.Property(e => e.Area).HasMaxLength(100);
            entity.Property(e => e.FullAddress).HasMaxLength(500);
            entity.Property(e => e.PageId).HasMaxLength(100);
            entity.Property(e => e.ProfileImageUrl).HasMaxLength(500);
            entity.Property(e => e.Notes).HasColumnType("text");
            entity.Property(e => e.TotalCharges).HasPrecision(18, 2);
            entity.Property(e => e.TotalPayments).HasPrecision(18, 2);
            entity.Property(e => e.NetBalance).HasPrecision(18, 2);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
        });

        // AgentTransaction (المعاملات المالية للوكيل)
        modelBuilder.Entity<AgentTransaction>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.AgentId);
            entity.HasIndex(e => e.Type);
            entity.HasIndex(e => e.CreatedAt);
            entity.Property(e => e.Amount).HasPrecision(18, 2);
            entity.Property(e => e.BalanceAfter).HasPrecision(18, 2);
            entity.Property(e => e.Description).HasMaxLength(500).IsRequired();
            entity.Property(e => e.ReferenceNumber).HasMaxLength(100);
            entity.Property(e => e.Notes).HasColumnType("text");
            entity.HasOne(e => e.Agent).WithMany(a => a.Transactions).HasForeignKey(e => e.AgentId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.ServiceRequest).WithMany().HasForeignKey(e => e.ServiceRequestId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.Citizen).WithMany().HasForeignKey(e => e.CitizenId).OnDelete(DeleteBehavior.SetNull);
        });

        // AgentCommissionRate (نسب عمولات الوكلاء لكل باقة)
        modelBuilder.Entity<AgentCommissionRate>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.AgentId, e.InternetPlanId }).IsUnique();
            entity.HasIndex(e => e.CompanyId);
            entity.Property(e => e.CommissionPercentage).HasPrecision(5, 2);
            entity.Property(e => e.Notes).HasMaxLength(500);
            entity.HasOne(e => e.Agent).WithMany().HasForeignKey(e => e.AgentId).OnDelete(DeleteBehavior.Cascade);
            entity.HasOne(e => e.InternetPlan).WithMany().HasForeignKey(e => e.InternetPlanId).OnDelete(DeleteBehavior.Cascade);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
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

        // ==================== Accounting System (نظام المحاسبة) ====================

        // Account (شجرة الحسابات)
        modelBuilder.Entity<Account>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.CompanyId, e.Code }).IsUnique();
            entity.HasIndex(e => e.CompanyId);
            entity.HasIndex(e => e.AccountType);
            entity.HasIndex(e => e.ParentAccountId);
            entity.Property(e => e.Code).HasMaxLength(50).IsRequired();
            entity.Property(e => e.Name).HasMaxLength(200).IsRequired();
            entity.Property(e => e.NameEn).HasMaxLength(200);
            entity.Property(e => e.Description).HasMaxLength(500);
            entity.Property(e => e.OpeningBalance).HasPrecision(18, 2);
            entity.Property(e => e.CurrentBalance).HasPrecision(18, 2);
            entity.HasOne(e => e.ParentAccount).WithMany(a => a.SubAccounts).HasForeignKey(e => e.ParentAccountId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
        });

        // JournalEntry (القيد المحاسبي)
        modelBuilder.Entity<JournalEntry>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.CompanyId, e.EntryNumber }).IsUnique();
            entity.HasIndex(e => e.CompanyId);
            entity.HasIndex(e => e.EntryDate);
            entity.HasIndex(e => e.Status);
            entity.HasIndex(e => e.ReferenceType);
            entity.Property(e => e.EntryNumber).HasMaxLength(50).IsRequired();
            entity.Property(e => e.Description).HasMaxLength(500).IsRequired();
            entity.Property(e => e.Notes).HasColumnType("text");
            entity.Property(e => e.ReferenceId).HasMaxLength(100);
            entity.Property(e => e.TotalDebit).HasPrecision(18, 2);
            entity.Property(e => e.TotalCredit).HasPrecision(18, 2);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.CreatedBy).WithMany().HasForeignKey(e => e.CreatedById).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.ApprovedBy).WithMany().HasForeignKey(e => e.ApprovedById).OnDelete(DeleteBehavior.SetNull);
        });

        // JournalEntryLine (سطر القيد)
        modelBuilder.Entity<JournalEntryLine>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.JournalEntryId);
            entity.HasIndex(e => e.AccountId);
            entity.Property(e => e.DebitAmount).HasPrecision(18, 2);
            entity.Property(e => e.CreditAmount).HasPrecision(18, 2);
            entity.Property(e => e.Description).HasMaxLength(500);
            entity.Property(e => e.EntityType).HasMaxLength(50);
            entity.Property(e => e.EntityId).HasMaxLength(100);
            entity.HasOne(e => e.JournalEntry).WithMany(j => j.Lines).HasForeignKey(e => e.JournalEntryId).OnDelete(DeleteBehavior.Cascade);
            entity.HasOne(e => e.Account).WithMany(a => a.JournalEntryLines).HasForeignKey(e => e.AccountId).OnDelete(DeleteBehavior.Restrict);
        });

        // CashBox (الصندوق/القاصة)
        modelBuilder.Entity<CashBox>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.CompanyId);
            entity.Property(e => e.Name).HasMaxLength(200).IsRequired();
            entity.Property(e => e.CurrentBalance).HasPrecision(18, 2);
            entity.Property(e => e.Notes).HasColumnType("text");
            entity.HasOne(e => e.ResponsibleUser).WithMany().HasForeignKey(e => e.ResponsibleUserId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.LinkedAccount).WithMany().HasForeignKey(e => e.LinkedAccountId).OnDelete(DeleteBehavior.SetNull);
        });

        // CashTransaction (حركة الصندوق)
        modelBuilder.Entity<CashTransaction>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.CashBoxId);
            entity.HasIndex(e => e.CreatedAt);
            entity.Property(e => e.Amount).HasPrecision(18, 2);
            entity.Property(e => e.BalanceAfter).HasPrecision(18, 2);
            entity.Property(e => e.Description).HasMaxLength(500).IsRequired();
            entity.Property(e => e.ReferenceId).HasMaxLength(100);
            entity.HasOne(e => e.CashBox).WithMany(c => c.Transactions).HasForeignKey(e => e.CashBoxId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.JournalEntry).WithMany().HasForeignKey(e => e.JournalEntryId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.CreatedBy).WithMany().HasForeignKey(e => e.CreatedById).OnDelete(DeleteBehavior.Restrict);
        });

        // EmployeeSalary (راتب الموظف)
        modelBuilder.Entity<EmployeeSalary>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.UserId, e.Year, e.Month }).IsUnique();
            entity.HasIndex(e => e.CompanyId);
            entity.HasIndex(e => e.Status);
            entity.Property(e => e.BaseSalary).HasPrecision(18, 2);
            entity.Property(e => e.Allowances).HasPrecision(18, 2);
            entity.Property(e => e.Deductions).HasPrecision(18, 2);
            entity.Property(e => e.Bonuses).HasPrecision(18, 2);
            entity.Property(e => e.NetSalary).HasPrecision(18, 2);
            entity.Property(e => e.LateDeduction).HasPrecision(18, 2);
            entity.Property(e => e.AbsentDeduction).HasPrecision(18, 2);
            entity.Property(e => e.EarlyDepartureDeduction).HasPrecision(18, 2);
            entity.Property(e => e.UnpaidLeaveDeduction).HasPrecision(18, 2);
            entity.Property(e => e.OvertimeBonus).HasPrecision(18, 2);
            entity.Property(e => e.Notes).HasColumnType("text");
            entity.HasOne(e => e.User).WithMany().HasForeignKey(e => e.UserId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.JournalEntry).WithMany().HasForeignKey(e => e.JournalEntryId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
        });

        // SalaryPolicy (سياسة الرواتب)
        modelBuilder.Entity<SalaryPolicy>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.CompanyId);
            entity.Property(e => e.Name).HasMaxLength(200);
            entity.Property(e => e.DeductionPerLateMinute).HasPrecision(18, 4);
            entity.Property(e => e.MaxLateDeductionPercent).HasPrecision(5, 2);
            entity.Property(e => e.AbsentDayMultiplier).HasPrecision(5, 2);
            entity.Property(e => e.DeductionPerEarlyDepartureMinute).HasPrecision(18, 4);
            entity.Property(e => e.OvertimeHourlyMultiplier).HasPrecision(5, 2);
            entity.Property(e => e.UnpaidLeaveDayMultiplier).HasPrecision(5, 2);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
        });

        // TechnicianCollection (تحصيل الفني)
        modelBuilder.Entity<TechnicianCollection>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.TechnicianId);
            entity.HasIndex(e => e.CompanyId);
            entity.HasIndex(e => e.CollectionDate);
            entity.HasIndex(e => e.IsDelivered);
            entity.Property(e => e.Amount).HasPrecision(18, 2);
            entity.Property(e => e.Notes).HasColumnType("text");
            entity.Property(e => e.Description).HasMaxLength(500);
            entity.Property(e => e.ReceiptNumber).HasMaxLength(100);
            entity.HasOne(e => e.Technician).WithMany().HasForeignKey(e => e.TechnicianId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.Citizen).WithMany().HasForeignKey(e => e.CitizenId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.ServiceRequest).WithMany().HasForeignKey(e => e.ServiceRequestId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.DeliveredToUser).WithMany().HasForeignKey(e => e.DeliveredToUserId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.JournalEntry).WithMany().HasForeignKey(e => e.JournalEntryId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.CashBox).WithMany().HasForeignKey(e => e.CashBoxId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
        });

        // Expense (المصروفات)
        modelBuilder.Entity<Expense>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.CompanyId);
            entity.HasIndex(e => e.ExpenseDate);
            entity.HasIndex(e => e.AccountId);
            entity.Property(e => e.Amount).HasPrecision(18, 2);
            entity.Property(e => e.Description).HasMaxLength(500).IsRequired();
            entity.Property(e => e.Category).HasMaxLength(100);
            entity.Property(e => e.AttachmentUrl).HasMaxLength(500);
            entity.Property(e => e.Notes).HasColumnType("text");
            entity.HasOne(e => e.Account).WithMany().HasForeignKey(e => e.AccountId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.JournalEntry).WithMany().HasForeignKey(e => e.JournalEntryId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.PaidFromCashBox).WithMany().HasForeignKey(e => e.PaidFromCashBoxId).OnDelete(DeleteBehavior.SetNull);
            entity.HasOne(e => e.CreatedBy).WithMany().HasForeignKey(e => e.CreatedById).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
        });

        // EmployeeDeductionBonus (خصومات ومكافآت الموظفين)
        modelBuilder.Entity<EmployeeDeductionBonus>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.UserId, e.Year, e.Month });
            entity.HasIndex(e => e.CompanyId);
            entity.HasIndex(e => e.Type);
            entity.Property(e => e.Amount).HasPrecision(18, 2);
            entity.Property(e => e.Description).HasMaxLength(500).IsRequired();
            entity.Property(e => e.Category).HasMaxLength(100);
            entity.Property(e => e.Notes).HasColumnType("text");
            entity.Property(e => e.Type).HasConversion<int>();
            entity.HasOne(e => e.User).WithMany().HasForeignKey(e => e.UserId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.Company).WithMany().HasForeignKey(e => e.CompanyId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.CreatedBy).WithMany().HasForeignKey(e => e.CreatedById).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(e => e.AppliedToSalary).WithMany().HasForeignKey(e => e.AppliedToSalaryId).OnDelete(DeleteBehavior.SetNull);
        });

        // EmployeeSalary precision for new fields
        modelBuilder.Entity<EmployeeSalary>(entity =>
        {
            entity.Property(e => e.ManualDeductions).HasPrecision(18, 2);
            entity.Property(e => e.ManualBonuses).HasPrecision(18, 2);
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
