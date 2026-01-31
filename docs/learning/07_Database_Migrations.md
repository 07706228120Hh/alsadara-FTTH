# 📚 الدرس #7: قاعدة البيانات و Migrations

## 🎯 ما هي قاعدة البيانات؟

**قاعدة البيانات** = مخزن دائم للبيانات.

في هذا المشروع نستخدم **PostgreSQL** مع **Entity Framework Core**.

---

## 🗃️ PostgreSQL

### ما هو PostgreSQL؟

قاعدة بيانات علائقية (Relational Database) مفتوحة المصدر:
- **مجانية** ومفتوحة المصدر
- **قوية** وموثوقة
- **JSON Support** (مهم للصلاحيات)

### الاتصال

```json
// appsettings.json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Database=sadara_db;Username=postgres;Password=yourpassword"
  }
}
```

### أو من Environment Variable

```powershell
$env:DATABASE_URL = "Host=72.61.183.61;Database=sadara_db;Username=postgres;Password=secret"
```

---

## 📊 الجداول الرئيسية

```sql
-- المستخدمون
CREATE TABLE "Users" (
    "Id" UUID PRIMARY KEY,
    "FullName" VARCHAR(100) NOT NULL,
    "PhoneNumber" VARCHAR(20) UNIQUE NOT NULL,
    "PasswordHash" TEXT NOT NULL,
    "Email" VARCHAR(100),
    "Role" INTEGER NOT NULL,
    "CompanyId" UUID,
    "IsActive" BOOLEAN DEFAULT TRUE,
    "IsDeleted" BOOLEAN DEFAULT FALSE,
    "CreatedAt" TIMESTAMP DEFAULT NOW(),
    "UpdatedAt" TIMESTAMP
);

-- الشركات
CREATE TABLE "Companies" (
    "Id" UUID PRIMARY KEY,
    "Name" VARCHAR(200) NOT NULL,
    "Code" VARCHAR(50) UNIQUE NOT NULL,
    "IsActive" BOOLEAN DEFAULT TRUE,
    "AdminUserId" UUID,
    "CreatedAt" TIMESTAMP DEFAULT NOW()
);

-- الطلبات
CREATE TABLE "Orders" (
    "Id" UUID PRIMARY KEY,
    "CustomerId" BIGINT NOT NULL,
    "TotalAmount" DECIMAL(18,2),
    "Status" INTEGER DEFAULT 0,
    "CreatedAt" TIMESTAMP DEFAULT NOW()
);
```

---

## 🔄 Migrations - إدارة تغييرات قاعدة البيانات

### ما هي Migration؟

**Migration** = سجل تغييرات قاعدة البيانات.

```
مثل Git للكود، لكن لقاعدة البيانات:

Migration_1: إنشاء جدول Users
Migration_2: إضافة عمود Email  
Migration_3: إنشاء جدول Companies
Migration_4: إضافة علاقة User -> Company
```

### موقع الـ Migrations

```
src/Backend/Core/Sadara.Infrastructure/
└── Data/
    └── Migrations/
        ├── 20240101_InitialCreate.cs
        ├── 20240115_AddCompanies.cs
        ├── 20240120_AddPermissions.cs
        └── SadaraDbContextModelSnapshot.cs
```

---

## 🛠️ أوامر Migrations

### 1️⃣ إنشاء Migration جديدة

```powershell
cd src/Backend/Core/Sadara.Infrastructure

# إنشاء migration
dotnet ef migrations add AddNewFeature --startup-project ../../API/Sadara.API

# مثال: إضافة جدول Invoices
dotnet ef migrations add AddInvoicesTable --startup-project ../../API/Sadara.API
```

### 2️⃣ تطبيق Migrations

```powershell
# تطبيق كل التغييرات
dotnet ef database update --startup-project ../../API/Sadara.API

# تطبيق migration محددة
dotnet ef database update AddCompanies --startup-project ../../API/Sadara.API
```

### 3️⃣ التراجع عن Migration

```powershell
# إزالة آخر migration (قبل التطبيق)
dotnet ef migrations remove --startup-project ../../API/Sadara.API

# التراجع لـ migration سابقة (بعد التطبيق)
dotnet ef database update PreviousMigration --startup-project ../../API/Sadara.API
```

### 4️⃣ إنشاء سكربت SQL

```powershell
# لمراجعة التغييرات قبل تطبيقها
dotnet ef migrations script --startup-project ../../API/Sadara.API -o migration.sql
```

---

## 📝 مثال على ملف Migration

### الملف: `20240120_AddInvoices.cs`

```csharp
public partial class AddInvoices : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // إنشاء الجدول
        migrationBuilder.CreateTable(
            name: "Invoices",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                InvoiceNumber = table.Column<string>(maxLength: 50, nullable: false),
                CustomerId = table.Column<long>(nullable: false),
                Amount = table.Column<decimal>(precision: 18, scale: 2, nullable: false),
                IsPaid = table.Column<bool>(nullable: false, defaultValue: false),
                CreatedAt = table.Column<DateTime>(nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_Invoices", x => x.Id);
                table.ForeignKey(
                    name: "FK_Invoices_Customers",
                    column: x => x.CustomerId,
                    principalTable: "Customers",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Restrict);
            });

        // إضافة فهرس
        migrationBuilder.CreateIndex(
            name: "IX_Invoices_CustomerId",
            table: "Invoices",
            column: "CustomerId");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // التراجع - حذف الجدول
        migrationBuilder.DropTable(name: "Invoices");
    }
}
```

---

## 🔄 تدفق العمل مع Migrations

```
┌─────────────────────────────────────────────────────────┐
│  1. تعديل Entity في Domain                             │
│     public class Invoice : BaseEntity<Guid> { ... }    │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│  2. إضافة DbSet في DbContext                            │
│     public DbSet<Invoice> Invoices => Set<Invoice>();  │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│  3. إنشاء Migration                                     │
│     dotnet ef migrations add AddInvoices               │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│  4. مراجعة ملف Migration                                │
│     التأكد من صحة Up() و Down()                        │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│  5. تطبيق Migration                                     │
│     dotnet ef database update                          │
└─────────────────────────────────────────────────────────┘
```

---

## 🌱 SeedData - البيانات الأولية

### الملف: `Data/SeedData.cs`

```csharp
public static class SeedData
{
    public static async Task SeedAsync(SadaraDbContext context)
    {
        // إنشاء مدير النظام
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
        }

        // إضافة الصلاحيات
        if (!await context.Permissions.AnyAsync())
        {
            var permissions = new List<Permission>
            {
                new() { Name = "users", NameAr = "المستخدمين", SystemType = 2 },
                new() { Name = "orders", NameAr = "الطلبات", SystemType = 2 },
                new() { Name = "payments", NameAr = "المدفوعات", SystemType = 2 },
            };
            
            await context.Permissions.AddRangeAsync(permissions);
        }

        await context.SaveChangesAsync();
    }
}
```

### استدعاء SeedData في Program.cs

```csharp
// في Program.cs
using (var scope = app.Services.CreateScope())
{
    var context = scope.ServiceProvider.GetRequiredService<SadaraDbContext>();
    await SeedData.SeedAsync(context);
}
```

---

## 🔌 الاتصال بـ pgAdmin

### Docker Compose

```yaml
# docker/docker-compose.yaml
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: yourpassword
      POSTGRES_DB: sadara_db
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  pgadmin:
    image: dpage/pgadmin4
    environment:
      PGADMIN_DEFAULT_EMAIL: admin@admin.com
      PGADMIN_DEFAULT_PASSWORD: admin
    ports:
      - "5050:80"
```

### التشغيل

```powershell
cd docker
docker-compose up -d
```

### الوصول لـ pgAdmin

- **URL:** http://localhost:5050
- **Email:** admin@admin.com
- **Password:** admin

---

## 📊 استعلامات مفيدة

### عرض كل المستخدمين

```sql
SELECT "Id", "FullName", "PhoneNumber", "Role", "IsActive"
FROM "Users"
WHERE "IsDeleted" = false
ORDER BY "CreatedAt" DESC;
```

### عرض الشركات مع عدد الموظفين

```sql
SELECT 
    c."Name",
    c."Code",
    COUNT(u."Id") as "EmployeeCount"
FROM "Companies" c
LEFT JOIN "Users" u ON u."CompanyId" = c."Id" AND u."IsDeleted" = false
WHERE c."IsDeleted" = false
GROUP BY c."Id", c."Name", c."Code";
```

### عرض الصلاحيات لمستخدم

```sql
SELECT 
    u."FullName",
    u."FirstSystemPermissions",
    u."SecondSystemPermissionsV2"
FROM "Users" u
WHERE u."Id" = 'user-guid-here';
```

---

## ⚠️ نصائح مهمة

### 1. لا تعدل Migrations بعد تطبيقها

```csharp
// ❌ خطأ - تعديل migration مطبقة
// ✅ صحيح - إنشاء migration جديدة للتعديل
```

### 2. احتفظ بنسخة احتياطية قبل التغييرات

```powershell
# نسخ احتياطي
pg_dump -U postgres sadara_db > backup.sql

# استرجاع
psql -U postgres sadara_db < backup.sql
```

### 3. استخدم Transactions للعمليات المعقدة

```csharp
using var transaction = await _context.Database.BeginTransactionAsync();
try
{
    // عمليات متعددة
    await _context.SaveChangesAsync();
    await transaction.CommitAsync();
}
catch
{
    await transaction.RollbackAsync();
    throw;
}
```

---

## 📝 تمارين

1. **أنشئ Migration** لإضافة عمود `Notes` لجدول Orders
2. **اكتب استعلام SQL** لعرض الطلبات مع أسماء العملاء
3. **فكر:** لماذا نستخدم Soft Delete بدل الحذف الفعلي؟

---

## 🔗 الدرس التالي

[08_Permissions_System.md](./08_Permissions_System.md) - نظام الصلاحيات بالتفصيل
