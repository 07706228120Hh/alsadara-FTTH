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
