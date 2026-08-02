using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.Api.Tests.Fakes;

/// <summary>
/// وحدة عمل وهمية يدوية (بلا Moq). تكشف فقط مستودع الشركات؛ بقية المستودعات
/// وعمليات المعاملات ترمي NotSupportedException لأن GetNodeConfig لا يمسّها.
/// </summary>
public sealed class FakeUnitOfWork : IUnitOfWork
{
    private readonly FakeCompanyRepository _companies;

    public FakeUnitOfWork(FakeCompanyRepository companies) => _companies = companies;

    public IRepository<User, Guid> Users => throw new NotSupportedException("Users غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Merchant, Guid> Merchants => throw new NotSupportedException("Merchants غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Customer, long> Customers => throw new NotSupportedException("Customers غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Product, Guid> Products => throw new NotSupportedException("Products غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Order, Guid> Orders => throw new NotSupportedException("Orders غير مستخدم في اختبار GetNodeConfig");
    public IRepository<OrderItem, Guid> OrderItems => throw new NotSupportedException("OrderItems غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Payment, Guid> Payments => throw new NotSupportedException("Payments غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Category, Guid> Categories => throw new NotSupportedException("Categories غير مستخدم في اختبار GetNodeConfig");
    public IRepository<City, Guid> Cities => throw new NotSupportedException("Cities غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Area, Guid> Areas => throw new NotSupportedException("Areas غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Review, Guid> Reviews => throw new NotSupportedException("Reviews غير مستخدم في اختبار GetNodeConfig");
    public IRepository<WishlistItem, Guid> WishlistItems => throw new NotSupportedException("WishlistItems غير مستخدم في اختبار GetNodeConfig");
    public IRepository<CartItem, Guid> CartItems => throw new NotSupportedException("CartItems غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Address, Guid> Addresses => throw new NotSupportedException("Addresses غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Coupon, Guid> Coupons => throw new NotSupportedException("Coupons غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Notification, long> Notifications => throw new NotSupportedException("Notifications غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Advertising, int> Advertisings => throw new NotSupportedException("Advertisings غير مستخدم في اختبار GetNodeConfig");
    public IRepository<AppVersion, int> AppVersions => throw new NotSupportedException("AppVersions غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Setting, int> Settings => throw new NotSupportedException("Settings غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Company, Guid> Companies => _companies;
    public IRepository<CompanyService, int> CompanyServices => throw new NotSupportedException("CompanyServices غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Permission, int> Permissions => throw new NotSupportedException("Permissions غير مستخدم في اختبار GetNodeConfig");
    public IRepository<UserPermission, long> UserPermissions => throw new NotSupportedException("UserPermissions غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Service, int> Services => throw new NotSupportedException("Services غير مستخدم في اختبار GetNodeConfig");
    public IRepository<OperationType, int> OperationTypes => throw new NotSupportedException("OperationTypes غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ServiceOperation, int> ServiceOperations => throw new NotSupportedException("ServiceOperations غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ServiceRequest, Guid> ServiceRequests => throw new NotSupportedException("ServiceRequests غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ServiceRequestComment, long> ServiceRequestComments => throw new NotSupportedException("ServiceRequestComments غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ServiceRequestAttachment, long> ServiceRequestAttachments => throw new NotSupportedException("ServiceRequestAttachments غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ServiceRequestStatusHistory, long> ServiceRequestStatusHistories => throw new NotSupportedException("ServiceRequestStatusHistories غير مستخدم في اختبار GetNodeConfig");
    public IRepository<SubscriptionLog, long> SubscriptionLogs => throw new NotSupportedException("SubscriptionLogs غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Citizen, Guid> Citizens => throw new NotSupportedException("Citizens غير مستخدم في اختبار GetNodeConfig");
    public IRepository<InternetPlan, Guid> InternetPlans => throw new NotSupportedException("InternetPlans غير مستخدم في اختبار GetNodeConfig");
    public IRepository<CitizenSubscription, Guid> CitizenSubscriptions => throw new NotSupportedException("CitizenSubscriptions غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Agent, Guid> Agents => throw new NotSupportedException("Agents غير مستخدم في اختبار GetNodeConfig");
    public IRepository<AgentTransaction, long> AgentTransactions => throw new NotSupportedException("AgentTransactions غير مستخدم في اختبار GetNodeConfig");
    public IRepository<AgentCommissionRate, long> AgentCommissionRates => throw new NotSupportedException("AgentCommissionRates غير مستخدم في اختبار GetNodeConfig");
    public IRepository<AttendanceRecord, long> AttendanceRecords => throw new NotSupportedException("AttendanceRecords غير مستخدم في اختبار GetNodeConfig");
    public IRepository<WorkCenter, int> WorkCenters => throw new NotSupportedException("WorkCenters غير مستخدم في اختبار GetNodeConfig");
    public IRepository<AttendanceAuditLog, long> AttendanceAuditLogs => throw new NotSupportedException("AttendanceAuditLogs غير مستخدم في اختبار GetNodeConfig");
    public IRepository<WorkSchedule, int> WorkSchedules => throw new NotSupportedException("WorkSchedules غير مستخدم في اختبار GetNodeConfig");
    public IRepository<LeaveRequest, long> LeaveRequests => throw new NotSupportedException("LeaveRequests غير مستخدم في اختبار GetNodeConfig");
    public IRepository<LeaveBalance, long> LeaveBalances => throw new NotSupportedException("LeaveBalances غير مستخدم في اختبار GetNodeConfig");
    public IRepository<WithdrawalRequest, long> WithdrawalRequests => throw new NotSupportedException("WithdrawalRequests غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ISPSubscriber, long> ISPSubscribers => throw new NotSupportedException("ISPSubscribers غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ZoneStatistic, int> ZoneStatistics => throw new NotSupportedException("ZoneStatistics غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ZoneMaintenanceFee, Guid> ZoneMaintenanceFees => throw new NotSupportedException("ZoneMaintenanceFees غير مستخدم في اختبار GetNodeConfig");
    public IRepository<IptvSubscriber, long> IptvSubscribers => throw new NotSupportedException("IptvSubscribers غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Account, Guid> Accounts => throw new NotSupportedException("Accounts غير مستخدم في اختبار GetNodeConfig");
    public IRepository<JournalEntry, Guid> JournalEntries => throw new NotSupportedException("JournalEntries غير مستخدم في اختبار GetNodeConfig");
    public IRepository<JournalEntryLine, long> JournalEntryLines => throw new NotSupportedException("JournalEntryLines غير مستخدم في اختبار GetNodeConfig");
    public IRepository<CashBox, Guid> CashBoxes => throw new NotSupportedException("CashBoxes غير مستخدم في اختبار GetNodeConfig");
    public IRepository<CashTransaction, long> CashTransactions => throw new NotSupportedException("CashTransactions غير مستخدم في اختبار GetNodeConfig");
    public IRepository<EmployeeSalary, long> EmployeeSalaries => throw new NotSupportedException("EmployeeSalaries غير مستخدم في اختبار GetNodeConfig");
    public IRepository<SalaryPolicy, int> SalaryPolicies => throw new NotSupportedException("SalaryPolicies غير مستخدم في اختبار GetNodeConfig");
    public IRepository<TechnicianCollection, long> TechnicianCollections => throw new NotSupportedException("TechnicianCollections غير مستخدم في اختبار GetNodeConfig");
    public IRepository<TechnicianTransaction, long> TechnicianTransactions => throw new NotSupportedException("TechnicianTransactions غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Expense, long> Expenses => throw new NotSupportedException("Expenses غير مستخدم في اختبار GetNodeConfig");
    public IRepository<EmployeeDeductionBonus, long> EmployeeDeductionBonuses => throw new NotSupportedException("EmployeeDeductionBonuses غير مستخدم في اختبار GetNodeConfig");
    public IRepository<FixedExpense, long> FixedExpenses => throw new NotSupportedException("FixedExpenses غير مستخدم في اختبار GetNodeConfig");
    public IRepository<FixedExpensePayment, long> FixedExpensePayments => throw new NotSupportedException("FixedExpensePayments غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ClosedPeriod, long> ClosedPeriods => throw new NotSupportedException("ClosedPeriods غير مستخدم في اختبار GetNodeConfig");
    public IRepository<TaskAudit, long> TaskAudits => throw new NotSupportedException("TaskAudits غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Department, int> Departments => throw new NotSupportedException("Departments غير مستخدم في اختبار GetNodeConfig");
    public IRepository<DepartmentTask, int> DepartmentTasks => throw new NotSupportedException("DepartmentTasks غير مستخدم في اختبار GetNodeConfig");
    public IRepository<UserDepartment, int> UserDepartments => throw new NotSupportedException("UserDepartments غير مستخدم في اختبار GetNodeConfig");
    public IRepository<UserFcmToken, long> UserFcmTokens => throw new NotSupportedException("UserFcmTokens غير مستخدم في اختبار GetNodeConfig");
    public IRepository<DailySettlementReport, long> DailySettlementReports => throw new NotSupportedException("DailySettlementReports غير مستخدم في اختبار GetNodeConfig");
    public IRepository<WhatsAppConversation, long> WhatsAppConversations => throw new NotSupportedException("WhatsAppConversations غير مستخدم في اختبار GetNodeConfig");
    public IRepository<WhatsAppMessage, long> WhatsAppMessages => throw new NotSupportedException("WhatsAppMessages غير مستخدم في اختبار GetNodeConfig");
    public IRepository<WhatsAppBatchReport, long> WhatsAppBatchReports => throw new NotSupportedException("WhatsAppBatchReports غير مستخدم في اختبار GetNodeConfig");
    public IRepository<EmployeeLocation, long> EmployeeLocations => throw new NotSupportedException("EmployeeLocations غير مستخدم في اختبار GetNodeConfig");
    public IRepository<EmployeeLocationLog, long> EmployeeLocationLogs => throw new NotSupportedException("EmployeeLocationLogs غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ReminderSettings, long> ReminderSettings => throw new NotSupportedException("ReminderSettings غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ReminderExecutionLog, long> ReminderExecutionLogs => throw new NotSupportedException("ReminderExecutionLogs غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ChatRoom, Guid> ChatRooms => throw new NotSupportedException("ChatRooms غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ChatRoomMember, long> ChatRoomMembers => throw new NotSupportedException("ChatRoomMembers غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ChatMessage, Guid> ChatMessages => throw new NotSupportedException("ChatMessages غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ChatAttachment, long> ChatAttachments => throw new NotSupportedException("ChatAttachments غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ChatMention, long> ChatMentions => throw new NotSupportedException("ChatMentions غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ChatMessageRead, long> ChatMessageReads => throw new NotSupportedException("ChatMessageReads غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ChatReaction, long> ChatReactions => throw new NotSupportedException("ChatReactions غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Announcement, long> Announcements => throw new NotSupportedException("Announcements غير مستخدم في اختبار GetNodeConfig");
    public IRepository<AnnouncementTarget, long> AnnouncementTargets => throw new NotSupportedException("AnnouncementTargets غير مستخدم في اختبار GetNodeConfig");
    public IRepository<AnnouncementRead, long> AnnouncementReads => throw new NotSupportedException("AnnouncementReads غير مستخدم في اختبار GetNodeConfig");
    public IRepository<CompanyFtthSettings, Guid> CompanyFtthSettings => throw new NotSupportedException("CompanyFtthSettings غير مستخدم في اختبار GetNodeConfig");
    public IRepository<FtthSubscriberCache, long> FtthSubscriberCaches => throw new NotSupportedException("FtthSubscriberCaches غير مستخدم في اختبار GetNodeConfig");
    public IRepository<FtthSyncLog, long> FtthSyncLogs => throw new NotSupportedException("FtthSyncLogs غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Warehouse, Guid> Warehouses => throw new NotSupportedException("Warehouses غير مستخدم في اختبار GetNodeConfig");
    public IRepository<InventoryCategory, int> InventoryCategories => throw new NotSupportedException("InventoryCategories غير مستخدم في اختبار GetNodeConfig");
    public IRepository<InventoryItem, Guid> InventoryItems => throw new NotSupportedException("InventoryItems غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Supplier, Guid> Suppliers => throw new NotSupportedException("Suppliers غير مستخدم في اختبار GetNodeConfig");
    public IRepository<PurchaseOrder, Guid> PurchaseOrders => throw new NotSupportedException("PurchaseOrders غير مستخدم في اختبار GetNodeConfig");
    public IRepository<PurchaseOrderItem, long> PurchaseOrderItems => throw new NotSupportedException("PurchaseOrderItems غير مستخدم في اختبار GetNodeConfig");
    public IRepository<SalesOrder, Guid> SalesOrders => throw new NotSupportedException("SalesOrders غير مستخدم في اختبار GetNodeConfig");
    public IRepository<SalesOrderItem, long> SalesOrderItems => throw new NotSupportedException("SalesOrderItems غير مستخدم في اختبار GetNodeConfig");
    public IRepository<TechnicianDispensing, Guid> TechnicianDispensings => throw new NotSupportedException("TechnicianDispensings غير مستخدم في اختبار GetNodeConfig");
    public IRepository<TechnicianDispensingItem, long> TechnicianDispensingItems => throw new NotSupportedException("TechnicianDispensingItems غير مستخدم في اختبار GetNodeConfig");
    public IRepository<StockMovement, long> StockMovements => throw new NotSupportedException("StockMovements غير مستخدم في اختبار GetNodeConfig");
    public IRepository<WarehouseStock, long> WarehouseStocks => throw new NotSupportedException("WarehouseStocks غير مستخدم في اختبار GetNodeConfig");
    public IRepository<InventoryCustomer, Guid> InventoryCustomers => throw new NotSupportedException("InventoryCustomers غير مستخدم في اختبار GetNodeConfig");
    public IRepository<Invoice, Guid> Invoices => throw new NotSupportedException("Invoices غير مستخدم في اختبار GetNodeConfig");
    public IRepository<InvoiceItem, long> InvoiceItems => throw new NotSupportedException("InvoiceItems غير مستخدم في اختبار GetNodeConfig");
    public IRepository<PaymentVoucher, Guid> PaymentVouchers => throw new NotSupportedException("PaymentVouchers غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ReturnOrder, Guid> ReturnOrders => throw new NotSupportedException("ReturnOrders غير مستخدم في اختبار GetNodeConfig");
    public IRepository<ReturnOrderItem, long> ReturnOrderItems => throw new NotSupportedException("ReturnOrderItems غير مستخدم في اختبار GetNodeConfig");
    public IRepository<InventoryAccountMapping, int> InventoryAccountMappings => throw new NotSupportedException("InventoryAccountMappings غير مستخدم في اختبار GetNodeConfig");

    // ===== المعاملات وحفظ التغييرات — غير مستخدمة في هذا الاختبار =====
    public Task<int> SaveChangesAsync(CancellationToken ct = default)
        => throw new NotSupportedException();

    public Task BeginTransactionAsync(CancellationToken ct = default)
        => throw new NotSupportedException();

    public Task CommitTransactionAsync(CancellationToken ct = default)
        => throw new NotSupportedException();

    public Task RollbackTransactionAsync(CancellationToken ct = default)
        => throw new NotSupportedException();

    public void Dispose() { }
}
