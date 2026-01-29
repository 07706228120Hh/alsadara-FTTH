using Sadara.Domain.Entities;

namespace Sadara.Domain.Interfaces;

public interface IRepository<T, TId> where T : class
{
    Task<T?> GetByIdAsync(TId id, CancellationToken ct = default);
    Task<IEnumerable<T>> GetAllAsync(CancellationToken ct = default);
    Task<IEnumerable<T>> FindAsync(System.Linq.Expressions.Expression<Func<T, bool>> predicate, CancellationToken ct = default);
    Task<T?> FirstOrDefaultAsync(System.Linq.Expressions.Expression<Func<T, bool>> predicate, CancellationToken ct = default);
    Task<T> AddAsync(T entity, CancellationToken ct = default);
    void Update(T entity);
    void Delete(T entity);
    Task<bool> AnyAsync(System.Linq.Expressions.Expression<Func<T, bool>> predicate, CancellationToken ct = default);
    Task<int> CountAsync(System.Linq.Expressions.Expression<Func<T, bool>>? predicate = null, CancellationToken ct = default);
    IQueryable<T> AsQueryable();
    Task<IEnumerable<T>> GetWithIncludesAsync(System.Linq.Expressions.Expression<Func<T, bool>>? filter, CancellationToken ct, params System.Linq.Expressions.Expression<Func<T, object>>[] includes);
}

public interface IUnitOfWork : IDisposable
{
    // Core entities
    IRepository<User, Guid> Users { get; }
    IRepository<Merchant, Guid> Merchants { get; }
    IRepository<Customer, long> Customers { get; }
    IRepository<Product, Guid> Products { get; }
    IRepository<Order, Guid> Orders { get; }
    IRepository<OrderItem, Guid> OrderItems { get; }
    IRepository<Payment, Guid> Payments { get; }
    
    // Commerce entities
    IRepository<Category, Guid> Categories { get; }
    IRepository<City, Guid> Cities { get; }
    IRepository<Area, Guid> Areas { get; }
    IRepository<Review, Guid> Reviews { get; }
    IRepository<WishlistItem, Guid> WishlistItems { get; }
    IRepository<CartItem, Guid> CartItems { get; }
    IRepository<Address, Guid> Addresses { get; }
    IRepository<Coupon, Guid> Coupons { get; }
    
    // System entities
    IRepository<Notification, long> Notifications { get; }
    IRepository<Advertising, int> Advertisings { get; }
    IRepository<AppVersion, int> AppVersions { get; }
    IRepository<Setting, int> Settings { get; }

    // Company & Multi-tenant entities (نظام الشركات - مطابق لـ Flutter)
    IRepository<Company, Guid> Companies { get; }
    IRepository<CompanyService, int> CompanyServices { get; }

    // Permission entities (نظام الصلاحيات المتقدم)
    IRepository<Permission, int> Permissions { get; }
    IRepository<UserPermission, long> UserPermissions { get; }

    // Service & Request entities (نظام الخدمات والطلبات)
    IRepository<Service, int> Services { get; }
    IRepository<OperationType, int> OperationTypes { get; }
    IRepository<ServiceOperation, int> ServiceOperations { get; }
    IRepository<ServiceRequest, Guid> ServiceRequests { get; }
    IRepository<ServiceRequestComment, long> ServiceRequestComments { get; }
    IRepository<ServiceRequestAttachment, long> ServiceRequestAttachments { get; }
    IRepository<ServiceRequestStatusHistory, long> ServiceRequestStatusHistories { get; }

    Task<int> SaveChangesAsync(CancellationToken ct = default);
    Task BeginTransactionAsync(CancellationToken ct = default);
    Task CommitTransactionAsync(CancellationToken ct = default);
    Task RollbackTransactionAsync(CancellationToken ct = default);
}

public interface IPasswordHasher
{
    string HashPassword(string password);
    bool VerifyPassword(string password, string hashedPassword);
}

public interface IJwtService
{
    string GenerateAccessToken(User user);
    string GenerateRefreshToken();
    bool ValidateToken(string token);
}

public interface ISmsService
{
    Task<bool> SendSmsAsync(string phoneNumber, string message);
}

public interface INotificationService
{
    Task SendPushNotificationAsync(string deviceToken, string title, string body, object? data = null);
}

public interface IFileStorageService
{
    Task<string> UploadAsync(Stream fileStream, string fileName, string folder);
    Task<bool> DeleteAsync(string filePath);
}

public interface ICacheService
{
    Task<T?> GetAsync<T>(string key);
    Task SetAsync<T>(string key, T value, TimeSpan? expiration = null);
    Task RemoveAsync(string key);
}
