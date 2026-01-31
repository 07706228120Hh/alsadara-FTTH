# 📚 الدرس #3: طبقة Infrastructure - قاعدة البيانات

## 🎯 ما هي طبقة Infrastructure؟

**طبقة Infrastructure** تتعامل مع **الموارد الخارجية**:
- قاعدة البيانات (PostgreSQL)
- Entity Framework Core
- Repository Pattern
- Unit of Work Pattern

**💡 هذه الطبقة تعرف كيف تحفظ وتجلب البيانات.**

---

## 📁 هيكل المجلد

```
src/Backend/Core/Sadara.Infrastructure/
├── Data/
│   ├── SadaraDbContext.cs  ← اتصال قاعدة البيانات
│   ├── SeedData.cs         ← بيانات أولية
│   └── Migrations/         ← تغييرات قاعدة البيانات
│
├── Repositories/
│   ├── Repository.cs       ← Repository عام
│   └── UnitOfWork.cs       ← Unit of Work
│
└── Services/
    └── ...                 ← خدمات خارجية
```

---

## 🗃️ DbContext - الاتصال بقاعدة البيانات

### الملف: `Data/SadaraDbContext.cs`

```csharp
public class SadaraDbContext : DbContext
{
    public SadaraDbContext(DbContextOptions<SadaraDbContext> options) 
        : base(options) { }

    // الجداول
    public DbSet<User> Users => Set<User>();
    public DbSet<Company> Companies => Set<Company>();
    public DbSet<Order> Orders => Set<Order>();
    // ... باقي الجداول

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // إعدادات الجداول
    }
}
```

### ماذا يفعل DbContext؟

```
┌─────────────────────────────────────────────────────────┐
│                    تطبيقك (C#)                          │
│   var user = await _context.Users.FirstAsync();        │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                   DbContext                             │
│  • يحول C# إلى SQL                                      │
│  • يدير الاتصال                                         │
│  • يتتبع التغييرات                                      │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                 PostgreSQL                              │
│  SELECT * FROM "Users" WHERE "Id" = '...'              │
└─────────────────────────────────────────────────────────┘
```

### DbSet - تمثيل الجدول

```csharp
// DbSet<User> يمثل جدول Users
public DbSet<User> Users => Set<User>();

// الاستخدام:
var users = await _context.Users.ToListAsync();
// SQL: SELECT * FROM "Users"

var activeUsers = await _context.Users
    .Where(u => u.IsActive)
    .ToListAsync();
// SQL: SELECT * FROM "Users" WHERE "IsActive" = true
```

---

## 🔍 Query Filters - فلترة تلقائية

### ما هو Query Filter؟

```csharp
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    // كل استعلام على Users سيتجاهل المحذوفين تلقائياً
    modelBuilder.Entity<User>()
        .HasQueryFilter(x => !x.IsDeleted);
}
```

### كيف يعمل؟

```csharp
// أنت تكتب:
var users = await _context.Users.ToListAsync();

// Entity Framework يُنفذ:
// SELECT * FROM "Users" WHERE "IsDeleted" = false

// لتجاهل الفلتر (رؤية المحذوفين):
var allUsers = await _context.Users
    .IgnoreQueryFilters()
    .ToListAsync();
```

**💡 فائدة:** لا تحتاج كتابة `!IsDeleted` في كل استعلام!

---

## 📦 Repository Pattern

### الملف: `Repositories/Repository.cs`

```csharp
public class Repository<T, TId> : IRepository<T, TId> where T : class
{
    protected readonly SadaraDbContext _context;
    protected readonly DbSet<T> _dbSet;

    public Repository(SadaraDbContext context)
    {
        _context = context;
        _dbSet = context.Set<T>();
    }

    // جلب بالمعرف
    public async Task<T?> GetByIdAsync(TId id, CancellationToken ct = default)
    {
        return await _dbSet.FindAsync(new object[] { id! }, ct);
    }

    // جلب الكل
    public async Task<IEnumerable<T>> GetAllAsync(CancellationToken ct = default)
    {
        return await _dbSet.ToListAsync(ct);
    }

    // بحث بشرط
    public async Task<T?> FirstOrDefaultAsync(
        Expression<Func<T, bool>> predicate, 
        CancellationToken ct = default)
    {
        return await _dbSet.FirstOrDefaultAsync(predicate, ct);
    }

    // إضافة
    public async Task<T> AddAsync(T entity, CancellationToken ct = default)
    {
        await _dbSet.AddAsync(entity, ct);
        return entity;
    }

    // تحديث
    public void Update(T entity)
    {
        _dbSet.Update(entity);
    }

    // حذف
    public void Delete(T entity)
    {
        _dbSet.Remove(entity);
    }
}
```

### لماذا Repository Pattern؟

```csharp
// ❌ بدون Repository - منطق متكرر
public class UserController
{
    public async Task<User> GetUser(Guid id)
    {
        return await _context.Users
            .Where(u => !u.IsDeleted && u.IsActive)
            .FirstOrDefaultAsync(u => u.Id == id);
    }
}

public class OrderController
{
    public async Task<User> GetOrderUser(Guid userId)
    {
        return await _context.Users
            .Where(u => !u.IsDeleted && u.IsActive)  // نفس المنطق!
            .FirstOrDefaultAsync(u => u.Id == userId);
    }
}

// ✅ مع Repository - المنطق موحد
public class UserRepository : Repository<User, Guid>
{
    public async Task<User?> GetActiveUserAsync(Guid id)
    {
        return await _dbSet
            .Where(u => u.IsActive)
            .FirstOrDefaultAsync(u => u.Id == id);
    }
}
```

---

## 🔄 Unit of Work Pattern

### الملف: `Repositories/UnitOfWork.cs`

```csharp
public class UnitOfWork : IUnitOfWork
{
    private readonly SadaraDbContext _context;

    // Repositories (Lazy Loading)
    private IRepository<User, Guid>? _users;
    private IRepository<Company, Guid>? _companies;
    private IRepository<Order, Guid>? _orders;

    public UnitOfWork(SadaraDbContext context)
    {
        _context = context;
    }

    // الوصول للـ Repositories
    public IRepository<User, Guid> Users =>
        _users ??= new Repository<User, Guid>(_context);

    public IRepository<Company, Guid> Companies =>
        _companies ??= new Repository<Company, Guid>(_context);

    public IRepository<Order, Guid> Orders =>
        _orders ??= new Repository<Order, Guid>(_context);

    // حفظ كل التغييرات
    public async Task<int> SaveChangesAsync(CancellationToken ct = default)
    {
        return await _context.SaveChangesAsync(ct);
    }
}
```

### لماذا Unit of Work؟

```csharp
// السيناريو: إنشاء طلب مع تحديث رصيد العميل
public async Task CreateOrderAsync(Order order, decimal discount)
{
    // 1. إضافة الطلب
    await _unitOfWork.Orders.AddAsync(order);
    
    // 2. خصم من رصيد العميل
    var customer = await _unitOfWork.Customers.GetByIdAsync(order.CustomerId);
    customer.WalletBalance -= discount;
    _unitOfWork.Customers.Update(customer);
    
    // 3. حفظ الكل معاً (Transaction واحدة)
    await _unitOfWork.SaveChangesAsync();
    
    // إذا فشل أي شيء، يتم التراجع عن الكل!
}
```

### 💡 تشبيه بسيط

```
Unit of Work = عربة التسوق 🛒

1. تضع منتجات في العربة (AddAsync, Update)
2. لا شيء يُخصم من حسابك بعد
3. عند الدفع (SaveChangesAsync) = كل شيء يُحفظ معاً
4. إذا فشلت البطاقة = ترجع كل المنتجات للرفوف
```

---

## 🔌 الاستخدام في Controller

```csharp
[ApiController]
[Route("api/[controller]")]
public class UsersController : ControllerBase
{
    private readonly IUnitOfWork _unitOfWork;

    public UsersController(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetUser(Guid id)
    {
        var user = await _unitOfWork.Users.GetByIdAsync(id);
        if (user == null) return NotFound();
        return Ok(user);
    }

    [HttpPost]
    public async Task<IActionResult> CreateUser(User user)
    {
        await _unitOfWork.Users.AddAsync(user);
        await _unitOfWork.SaveChangesAsync();
        return CreatedAtAction(nameof(GetUser), new { id = user.Id }, user);
    }
}
```

---

## 📊 Entity Configuration

### تكوين الجدول في OnModelCreating

```csharp
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    // User
    modelBuilder.Entity<User>(entity =>
    {
        // المفتاح الأساسي
        entity.HasKey(e => e.Id);
        
        // فهرس فريد على رقم الهاتف
        entity.HasIndex(e => e.PhoneNumber).IsUnique();
        
        // إعدادات الحقول
        entity.Property(e => e.FullName)
            .HasMaxLength(100)
            .IsRequired();
        
        entity.Property(e => e.PhoneNumber)
            .HasMaxLength(20)
            .IsRequired();
    });

    // Order - العلاقات
    modelBuilder.Entity<Order>(entity =>
    {
        // علاقة Order -> Customer (كثير لواحد)
        entity.HasOne(e => e.Customer)
            .WithMany(c => c.Orders)
            .HasForeignKey(e => e.CustomerId);
        
        // علاقة Order -> OrderItems (واحد لكثير)
        entity.HasMany(e => e.OrderItems)
            .WithOne(i => i.Order)
            .HasForeignKey(i => i.OrderId);
    });
}
```

---

## 🔄 Migrations - تغييرات قاعدة البيانات

### ما هي Migration؟

**Migration** = سجل تغييرات قاعدة البيانات.

```
Migration_1: إنشاء جدول Users
Migration_2: إضافة عمود Email لـ Users  
Migration_3: إنشاء جدول Orders
```

### أوامر Migration

```powershell
# الموقع
cd src/Backend/Core/Sadara.Infrastructure

# إنشاء migration جديدة
dotnet ef migrations add AddEmailToUser

# تطبيق التغييرات
dotnet ef database update

# التراجع عن آخر migration
dotnet ef migrations remove
```

### مثال على ملف Migration

```csharp
// Migrations/20240115_AddEmailToUser.cs
public partial class AddEmailToUser : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<string>(
            name: "Email",
            table: "Users",
            type: "character varying(100)",
            maxLength: 100,
            nullable: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "Email",
            table: "Users");
    }
}
```

---

## 🌱 SeedData - البيانات الأولية

### الملف: `Data/SeedData.cs`

```csharp
public static class SeedData
{
    public static async Task SeedAsync(SadaraDbContext context)
    {
        // إنشاء مدير النظام إذا لم يوجد
        if (!await context.Users.AnyAsync(u => u.Role == UserRole.SuperAdmin))
        {
            var admin = new User
            {
                Id = Guid.NewGuid(),
                FullName = "مدير النظام",
                Username = "admin",
                PhoneNumber = "07700000000",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword("Admin@123"),
                Role = UserRole.SuperAdmin,
                IsActive = true
            };
            
            await context.Users.AddAsync(admin);
            await context.SaveChangesAsync();
        }
    }
}
```

---

## 🎯 ملخص العلاقات

```
┌─────────────────────────────────────────────────────────────┐
│                        Controller                           │
│                            │                                │
│                    يستخدم IUnitOfWork                       │
│                            ▼                                │
├─────────────────────────────────────────────────────────────┤
│                       UnitOfWork                            │
│                            │                                │
│              يوفر Repositories + SaveChanges                │
│                            ▼                                │
├─────────────────────────────────────────────────────────────┤
│                       Repository<T>                         │
│                            │                                │
│              يغلف DbSet ويوفر عمليات CRUD                   │
│                            ▼                                │
├─────────────────────────────────────────────────────────────┤
│                       DbContext                             │
│                            │                                │
│              يتصل بقاعدة البيانات                           │
│                            ▼                                │
├─────────────────────────────────────────────────────────────┤
│                      PostgreSQL                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 📝 تمارين

1. **افتح `SadaraDbContext.cs`** - كم DbSet موجود؟
2. **ابحث عن Query Filter** - أي كيانات تستخدمه؟
3. **في `UnitOfWork.cs`** - ما معنى `??=`؟

---

## 🔗 الدرس التالي

[04_API_Layer.md](./04_API_Layer.md) - طبقة API (Controllers)
