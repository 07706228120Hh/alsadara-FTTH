using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;
using Sadara.Infrastructure.Data;

namespace Sadara.Infrastructure.Repositories;

/// <summary>
/// Unit of Work pattern implementation
/// Manages transactions and repository access
/// </summary>
public class UnitOfWork : IUnitOfWork
{
    private readonly SadaraDbContext _context;
    private bool _disposed;

    // Core entity repositories
    private IRepository<User, Guid>? _users;
    private IRepository<Merchant, Guid>? _merchants;
    private IRepository<Customer, long>? _customers;
    private IRepository<Product, Guid>? _products;
    private IRepository<Order, Guid>? _orders;
    private IRepository<OrderItem, Guid>? _orderItems;
    private IRepository<Payment, Guid>? _payments;

    // Commerce entity repositories
    private IRepository<Category, Guid>? _categories;
    private IRepository<City, Guid>? _cities;
    private IRepository<Area, Guid>? _areas;
    private IRepository<Review, Guid>? _reviews;
    private IRepository<WishlistItem, Guid>? _wishlistItems;
    private IRepository<CartItem, Guid>? _cartItems;
    private IRepository<Address, Guid>? _addresses;
    private IRepository<Coupon, Guid>? _coupons;

    // System entity repositories
    private IRepository<Notification, long>? _notifications;
    private IRepository<Advertising, int>? _advertisings;
    private IRepository<AppVersion, int>? _appVersions;
    private IRepository<Setting, int>? _settings;

    // Company & Multi-tenant repositories (نظام الشركات - مطابق لـ Flutter)
    private IRepository<Company, Guid>? _companies;
    private IRepository<CompanyService, int>? _companyServices;

    // Permission repositories (نظام الصلاحيات المتقدم)
    private IRepository<Permission, int>? _permissions;
    private IRepository<UserPermission, long>? _userPermissions;

    // Service & Request repositories (نظام الخدمات والطلبات)
    private IRepository<Service, int>? _services;
    private IRepository<OperationType, int>? _operationTypes;
    private IRepository<ServiceOperation, int>? _serviceOperations;
    private IRepository<ServiceRequest, Guid>? _serviceRequests;
    private IRepository<ServiceRequestComment, long>? _serviceRequestComments;
    private IRepository<ServiceRequestAttachment, long>? _serviceRequestAttachments;
    private IRepository<ServiceRequestStatusHistory, long>? _serviceRequestStatusHistories;

    // Subscription Logs (سجل عمليات الاشتراكات)
    private IRepository<SubscriptionLog, long>? _subscriptionLogs;

    // Citizen Portal (بوابة المواطن)
    private IRepository<Citizen, Guid>? _citizens;
    private IRepository<InternetPlan, Guid>? _internetPlans;
    private IRepository<CitizenSubscription, Guid>? _citizenSubscriptions;

    // Agent System (نظام الوكلاء)
    private IRepository<Agent, Guid>? _agents;
    private IRepository<AgentTransaction, long>? _agentTransactions;
    private IRepository<AgentCommissionRate, long>? _agentCommissionRates;

    // Attendance & Work Centers (الحضور والمراكز)
    private IRepository<AttendanceRecord, long>? _attendanceRecords;
    private IRepository<WorkCenter, int>? _workCenters;
    private IRepository<AttendanceAuditLog, long>? _attendanceAuditLogs;
    private IRepository<WorkSchedule, int>? _workSchedules;

    // Leave Management (نظام الإجازات)
    private IRepository<LeaveRequest, long>? _leaveRequests;
    private IRepository<LeaveBalance, long>? _leaveBalances;

    // Withdrawal Requests (طلبات سحب الأموال)
    private IRepository<WithdrawalRequest, long>? _withdrawalRequests;

    // ISP Data (بيانات مشتركي الإنترنت)
    private IRepository<ISPSubscriber, long>? _ispSubscribers;
    private IRepository<ZoneStatistic, int>? _zoneStatistics;

    // IPTV Subscribers (مشتركي التلفزيون عبر الإنترنت)
    private IRepository<IptvSubscriber, long>? _iptvSubscribers;

    // Accounting System (نظام المحاسبة)
    private IRepository<Account, Guid>? _accounts;
    private IRepository<JournalEntry, Guid>? _journalEntries;
    private IRepository<JournalEntryLine, long>? _journalEntryLines;
    private IRepository<CashBox, Guid>? _cashBoxes;
    private IRepository<CashTransaction, long>? _cashTransactions;
    private IRepository<EmployeeSalary, long>? _employeeSalaries;
    private IRepository<SalaryPolicy, int>? _salaryPolicies;
    private IRepository<TechnicianCollection, long>? _technicianCollections;
    private IRepository<TechnicianTransaction, long>? _technicianTransactions;
    private IRepository<Expense, long>? _expenses;
    private IRepository<EmployeeDeductionBonus, long>? _employeeDeductionBonuses;
    private IRepository<FixedExpense, long>? _fixedExpenses;
    private IRepository<FixedExpensePayment, long>? _fixedExpensePayments;
    private IRepository<TaskAudit, long>? _taskAudits;
    private IRepository<Department, int>? _departments;
    private IRepository<DepartmentTask, int>? _departmentTasks;

    // Daily Settlement Reports (تقارير التسديدات اليومية)
    private IRepository<DailySettlementReport, long>? _dailySettlementReports;

    // WhatsApp Conversations (محادثات واتساب)
    private IRepository<WhatsAppConversation, long>? _whatsAppConversations;
    private IRepository<WhatsAppMessage, long>? _whatsAppMessages;
    private IRepository<WhatsAppBatchReport, long>? _whatsAppBatchReports;
    private IRepository<EmployeeLocation, long>? _employeeLocations;
    private IRepository<EmployeeLocationLog, long>? _employeeLocationLogs;

    public UnitOfWork(SadaraDbContext context)
    {
        _context = context;
    }

    #region Repository Properties

    // Core entities
    public IRepository<User, Guid> Users =>
        _users ??= new Repository<User, Guid>(_context);

    public IRepository<Merchant, Guid> Merchants =>
        _merchants ??= new Repository<Merchant, Guid>(_context);

    public IRepository<Customer, long> Customers =>
        _customers ??= new Repository<Customer, long>(_context);

    public IRepository<Product, Guid> Products =>
        _products ??= new Repository<Product, Guid>(_context);

    public IRepository<Order, Guid> Orders =>
        _orders ??= new Repository<Order, Guid>(_context);

    public IRepository<OrderItem, Guid> OrderItems =>
        _orderItems ??= new Repository<OrderItem, Guid>(_context);

    public IRepository<Payment, Guid> Payments =>
        _payments ??= new Repository<Payment, Guid>(_context);

    // Commerce entities
    public IRepository<Category, Guid> Categories =>
        _categories ??= new Repository<Category, Guid>(_context);

    public IRepository<City, Guid> Cities =>
        _cities ??= new Repository<City, Guid>(_context);

    public IRepository<Area, Guid> Areas =>
        _areas ??= new Repository<Area, Guid>(_context);

    public IRepository<Review, Guid> Reviews =>
        _reviews ??= new Repository<Review, Guid>(_context);

    public IRepository<WishlistItem, Guid> WishlistItems =>
        _wishlistItems ??= new Repository<WishlistItem, Guid>(_context);

    public IRepository<CartItem, Guid> CartItems =>
        _cartItems ??= new Repository<CartItem, Guid>(_context);

    public IRepository<Address, Guid> Addresses =>
        _addresses ??= new Repository<Address, Guid>(_context);

    public IRepository<Coupon, Guid> Coupons =>
        _coupons ??= new Repository<Coupon, Guid>(_context);

    // System entities
    public IRepository<Notification, long> Notifications =>
        _notifications ??= new Repository<Notification, long>(_context);

    public IRepository<Advertising, int> Advertisings =>
        _advertisings ??= new Repository<Advertising, int>(_context);

    public IRepository<AppVersion, int> AppVersions =>
        _appVersions ??= new Repository<AppVersion, int>(_context);

    public IRepository<Setting, int> Settings =>
        _settings ??= new Repository<Setting, int>(_context);

    // Company & Multi-tenant entities
    public IRepository<Company, Guid> Companies =>
        _companies ??= new Repository<Company, Guid>(_context);

    public IRepository<CompanyService, int> CompanyServices =>
        _companyServices ??= new Repository<CompanyService, int>(_context);

    // Permission entities
    public IRepository<Permission, int> Permissions =>
        _permissions ??= new Repository<Permission, int>(_context);

    public IRepository<UserPermission, long> UserPermissions =>
        _userPermissions ??= new Repository<UserPermission, long>(_context);

    // Service & Request entities
    public IRepository<Service, int> Services =>
        _services ??= new Repository<Service, int>(_context);

    public IRepository<OperationType, int> OperationTypes =>
        _operationTypes ??= new Repository<OperationType, int>(_context);

    public IRepository<ServiceOperation, int> ServiceOperations =>
        _serviceOperations ??= new Repository<ServiceOperation, int>(_context);

    public IRepository<ServiceRequest, Guid> ServiceRequests =>
        _serviceRequests ??= new Repository<ServiceRequest, Guid>(_context);

    public IRepository<ServiceRequestComment, long> ServiceRequestComments =>
        _serviceRequestComments ??= new Repository<ServiceRequestComment, long>(_context);

    public IRepository<ServiceRequestAttachment, long> ServiceRequestAttachments =>
        _serviceRequestAttachments ??= new Repository<ServiceRequestAttachment, long>(_context);

    public IRepository<ServiceRequestStatusHistory, long> ServiceRequestStatusHistories =>
        _serviceRequestStatusHistories ??= new Repository<ServiceRequestStatusHistory, long>(_context);

    // Subscription Logs
    public IRepository<SubscriptionLog, long> SubscriptionLogs =>
        _subscriptionLogs ??= new Repository<SubscriptionLog, long>(_context);

    // Citizen Portal (بوابة المواطن)
    public IRepository<Citizen, Guid> Citizens =>
        _citizens ??= new Repository<Citizen, Guid>(_context);

    public IRepository<InternetPlan, Guid> InternetPlans =>
        _internetPlans ??= new Repository<InternetPlan, Guid>(_context);

    public IRepository<CitizenSubscription, Guid> CitizenSubscriptions =>
        _citizenSubscriptions ??= new Repository<CitizenSubscription, Guid>(_context);

    // Agent System (نظام الوكلاء)
    public IRepository<Agent, Guid> Agents =>
        _agents ??= new Repository<Agent, Guid>(_context);

    public IRepository<AgentTransaction, long> AgentTransactions =>
        _agentTransactions ??= new Repository<AgentTransaction, long>(_context);

    public IRepository<AgentCommissionRate, long> AgentCommissionRates =>
        _agentCommissionRates ??= new Repository<AgentCommissionRate, long>(_context);

    // Attendance & Work Centers (الحضور والمراكز)
    public IRepository<AttendanceRecord, long> AttendanceRecords =>
        _attendanceRecords ??= new Repository<AttendanceRecord, long>(_context);

    public IRepository<WorkCenter, int> WorkCenters =>
        _workCenters ??= new Repository<WorkCenter, int>(_context);

    public IRepository<AttendanceAuditLog, long> AttendanceAuditLogs =>
        _attendanceAuditLogs ??= new Repository<AttendanceAuditLog, long>(_context);

    public IRepository<WorkSchedule, int> WorkSchedules =>
        _workSchedules ??= new Repository<WorkSchedule, int>(_context);

    // Leave Management (نظام الإجازات)
    public IRepository<LeaveRequest, long> LeaveRequests =>
        _leaveRequests ??= new Repository<LeaveRequest, long>(_context);

    public IRepository<LeaveBalance, long> LeaveBalances =>
        _leaveBalances ??= new Repository<LeaveBalance, long>(_context);

    // Withdrawal Requests (طلبات سحب الأموال)
    public IRepository<WithdrawalRequest, long> WithdrawalRequests =>
        _withdrawalRequests ??= new Repository<WithdrawalRequest, long>(_context);

    // ISP Data (بيانات مشتركي الإنترنت)
    public IRepository<ISPSubscriber, long> ISPSubscribers =>
        _ispSubscribers ??= new Repository<ISPSubscriber, long>(_context);

    public IRepository<ZoneStatistic, int> ZoneStatistics =>
        _zoneStatistics ??= new Repository<ZoneStatistic, int>(_context);

    // IPTV Subscribers (مشتركي التلفزيون عبر الإنترنت)
    public IRepository<IptvSubscriber, long> IptvSubscribers =>
        _iptvSubscribers ??= new Repository<IptvSubscriber, long>(_context);

    // Accounting System (نظام المحاسبة)
    public IRepository<Account, Guid> Accounts =>
        _accounts ??= new Repository<Account, Guid>(_context);

    public IRepository<JournalEntry, Guid> JournalEntries =>
        _journalEntries ??= new Repository<JournalEntry, Guid>(_context);

    public IRepository<JournalEntryLine, long> JournalEntryLines =>
        _journalEntryLines ??= new Repository<JournalEntryLine, long>(_context);

    public IRepository<CashBox, Guid> CashBoxes =>
        _cashBoxes ??= new Repository<CashBox, Guid>(_context);

    public IRepository<CashTransaction, long> CashTransactions =>
        _cashTransactions ??= new Repository<CashTransaction, long>(_context);

    public IRepository<EmployeeSalary, long> EmployeeSalaries =>
        _employeeSalaries ??= new Repository<EmployeeSalary, long>(_context);

    public IRepository<SalaryPolicy, int> SalaryPolicies =>
        _salaryPolicies ??= new Repository<SalaryPolicy, int>(_context);

    public IRepository<TechnicianCollection, long> TechnicianCollections =>
        _technicianCollections ??= new Repository<TechnicianCollection, long>(_context);

    public IRepository<TechnicianTransaction, long> TechnicianTransactions =>
        _technicianTransactions ??= new Repository<TechnicianTransaction, long>(_context);

    public IRepository<Expense, long> Expenses =>
        _expenses ??= new Repository<Expense, long>(_context);

    public IRepository<EmployeeDeductionBonus, long> EmployeeDeductionBonuses =>
        _employeeDeductionBonuses ??= new Repository<EmployeeDeductionBonus, long>(_context);

    public IRepository<FixedExpense, long> FixedExpenses =>
        _fixedExpenses ??= new Repository<FixedExpense, long>(_context);

    public IRepository<FixedExpensePayment, long> FixedExpensePayments =>
        _fixedExpensePayments ??= new Repository<FixedExpensePayment, long>(_context);

    // Task Audit (تدقيق المهام)
    public IRepository<TaskAudit, long> TaskAudits =>
        _taskAudits ??= new Repository<TaskAudit, long>(_context);

    // Departments (الأقسام ومهامها)
    public IRepository<Department, int> Departments =>
        _departments ??= new Repository<Department, int>(_context);

    public IRepository<DepartmentTask, int> DepartmentTasks =>
        _departmentTasks ??= new Repository<DepartmentTask, int>(_context);

    // Daily Settlement Reports (تقارير التسديدات اليومية)
    public IRepository<DailySettlementReport, long> DailySettlementReports =>
        _dailySettlementReports ??= new Repository<DailySettlementReport, long>(_context);

    // WhatsApp Conversations (محادثات واتساب)
    public IRepository<WhatsAppConversation, long> WhatsAppConversations =>
        _whatsAppConversations ??= new Repository<WhatsAppConversation, long>(_context);

    public IRepository<WhatsAppMessage, long> WhatsAppMessages =>
        _whatsAppMessages ??= new Repository<WhatsAppMessage, long>(_context);

    public IRepository<WhatsAppBatchReport, long> WhatsAppBatchReports =>
        _whatsAppBatchReports ??= new Repository<WhatsAppBatchReport, long>(_context);

    // Employee Location (تتبع الموظفين)
    public IRepository<EmployeeLocation, long> EmployeeLocations =>
        _employeeLocations ??= new Repository<EmployeeLocation, long>(_context);

    public IRepository<EmployeeLocationLog, long> EmployeeLocationLogs =>
        _employeeLocationLogs ??= new Repository<EmployeeLocationLog, long>(_context);

    #endregion

    #region Transaction Management

    public async Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        return await _context.SaveChangesAsync(cancellationToken);
    }

    public async Task BeginTransactionAsync(CancellationToken cancellationToken = default)
    {
        await _context.Database.BeginTransactionAsync(cancellationToken);
    }

    public async Task CommitTransactionAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            await _context.SaveChangesAsync(cancellationToken);
            await _context.Database.CommitTransactionAsync(cancellationToken);
        }
        catch
        {
            await RollbackTransactionAsync(cancellationToken);
            throw;
        }
    }

    public async Task RollbackTransactionAsync(CancellationToken cancellationToken = default)
    {
        await _context.Database.RollbackTransactionAsync(cancellationToken);
    }

    #endregion

    #region Dispose Pattern

    protected virtual void Dispose(bool disposing)
    {
        if (!_disposed)
        {
            if (disposing)
            {
                _context.Dispose();
            }
            _disposed = true;
        }
    }

    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }

    #endregion
}
