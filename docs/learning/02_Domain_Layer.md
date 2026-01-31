# 📚 الدرس #2: طبقة Domain - الكيانات والقواعد

## 🎯 ما هي طبقة Domain؟

**طبقة Domain** هي **قلب التطبيق**. تحتوي على:
- **الكيانات (Entities)**: الجداول في قاعدة البيانات
- **الـ Enums**: القيم الثابتة (مثل أنواع المستخدمين)
- **الواجهات (Interfaces)**: عقود الخدمات

**💡 القاعدة الذهبية:** هذه الطبقة **لا تعتمد على أي طبقة أخرى!**

---

## 📁 هيكل المجلد

```
src/Backend/Core/Sadara.Domain/
├── Entities/           ← الكيانات (جداول قاعدة البيانات)
│   ├── BaseEntity.cs   ← الكيان الأساسي
│   ├── User.cs         ← المستخدمون
│   ├── Company.cs      ← الشركات
│   ├── Customer.cs     ← العملاء
│   ├── Order.cs        ← الطلبات
│   └── ...
├── Enums/              ← التعدادات
│   └── Enums.cs        ← كل الـ Enums
└── Interfaces/         ← الواجهات
```

---

## 🏗️ الكيان الأساسي (BaseEntity)

### الملف: `BaseEntity.cs`

```csharp
public abstract class BaseEntity
{
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }
    public bool IsDeleted { get; set; } = false;
    public DateTime? DeletedAt { get; set; }
}

public abstract class BaseEntity<TId> : BaseEntity
{
    public TId Id { get; set; } = default!;
}
```

### ماذا يفعل؟

| الخاصية | الوظيفة |
|---------|---------|
| `CreatedAt` | تاريخ الإنشاء (تلقائي) |
| `UpdatedAt` | تاريخ آخر تعديل |
| `IsDeleted` | Soft Delete (حذف منطقي) |
| `DeletedAt` | متى تم الحذف |
| `Id` | المعرف الفريد (Guid عادةً) |

### 💡 لماذا Soft Delete؟

بدلاً من حذف السجل نهائياً:
```sql
-- ❌ حذف فعلي (خطر!)
DELETE FROM Users WHERE Id = '...'

-- ✅ حذف منطقي (آمن)
UPDATE Users SET IsDeleted = true, DeletedAt = NOW() WHERE Id = '...'
```

**الفوائد:**
- استرجاع البيانات إذا حُذفت بالخطأ
- تتبع تاريخي كامل
- لا يتأثر التقارير

---

## 👤 كيان المستخدم (User)

### الملف: `User.cs`

```csharp
public class User : BaseEntity<Guid>
{
    // معلومات أساسية
    public string? Username { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string PhoneNumber { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public UserRole Role { get; set; } = UserRole.Citizen;
    
    // معلومات الشركة (للموظفين)
    public Guid? CompanyId { get; set; }
    public string? Department { get; set; }
    
    // صلاحيات V1 (بسيطة)
    public string? FirstSystemPermissions { get; set; }
    // مثال: {"attendance":true,"agent":false}
    
    // صلاحيات V2 (مفصلة)
    public string? SecondSystemPermissionsV2 { get; set; }
    // مثال: {"users":{"view":true,"add":true,"edit":false}}
}
```

### أنواع المستخدمين

```
+--------+-----------+-------+------------------------------------+
| الرقم  | الدور     | Role  | الوصف                              |
+--------+-----------+-------+------------------------------------+
|   0    | مواطن     | Citizen | يستخدم تطبيق المواطن PWA         |
|  10    | موظف      | Employee | صلاحيات محدودة في شركته        |
|  14    | مشرف      | Manager | صلاحيات إدارية جزئية            |
|  20    | مدير شركة | CompanyAdmin | صلاحيات كاملة على شركته    |
|  99    | مدير نظام | SuperAdmin | صلاحيات كاملة على كل النظام  |
+--------+-----------+-------+------------------------------------+
```

### نظام الصلاحيات المزدوج

**V1 - بسيط (Boolean):**
```json
{
  "attendance": true,
  "agent": false,
  "settings": true
}
```
**السؤال:** هل يملك الصلاحية؟ نعم أو لا.

**V2 - مفصل (Actions):**
```json
{
  "users": {
    "view": true,
    "add": true,
    "edit": false,
    "delete": false
  },
  "subscriptions": {
    "view": true,
    "add": false,
    "edit": false,
    "delete": false
  }
}
```
**السؤال:** ماذا يستطيع أن يفعل؟ (عرض، إضافة، تعديل، حذف)

---

## 🏢 كيان الشركة (Company)

### الملف: `Company.cs`

```csharp
public class Company : BaseEntity<Guid>
{
    public string Name { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty;  // للدخول
    public bool IsActive { get; set; } = true;
    
    // الاشتراك
    public DateTime SubscriptionStartDate { get; set; }
    public DateTime SubscriptionEndDate { get; set; }
    public SubscriptionPlan SubscriptionPlan { get; set; }
    public int MaxUsers { get; set; } = 10;
    
    // مدير الشركة
    public Guid? AdminUserId { get; set; }
    
    // ربط نظام المواطن
    public bool IsCitizenPortalEnabled { get; set; } = false;
}
```

### العلاقة بين Company و User

```
┌─────────────────┐
│     Company     │
│  (شركة الصدارة)  │
└────────┬────────┘
         │ 1:N (شركة واحدة لها موظفين كثر)
         ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  User (مدير)    │    │  User (موظف 1)  │    │  User (موظف 2)  │
│ CompanyId = X   │    │ CompanyId = X   │    │ CompanyId = X   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

---

## 📦 التعدادات (Enums)

### الملف: `Enums/Enums.cs`

```csharp
// أدوار المستخدمين
public enum UserRole
{
    Citizen = 0,        // مواطن
    Employee = 10,      // موظف
    Manager = 14,       // مشرف
    CompanyAdmin = 20,  // مدير شركة
    SuperAdmin = 99     // مدير نظام
}

// حالة الطلب
public enum OrderStatus
{
    Pending = 0,        // قيد الانتظار
    Confirmed = 1,      // مؤكد
    Processing = 2,     // قيد المعالجة
    Shipped = 3,        // تم الشحن
    Delivered = 4,      // تم التوصيل
    Cancelled = 5       // ملغي
}

// طريقة الدفع
public enum PaymentMethod
{
    CashOnDelivery = 0, // الدفع عند الاستلام
    ZainCash = 1,
    FastPay = 2,
    Wallet = 3
}
```

### 💡 لماذا نستخدم Enum بدل String؟

```csharp
// ❌ سيء - خطأ إملائي ممكن
user.Role = "admin";  // "Admin"? "ADMIN"? "administrator"?

// ✅ جيد - القيم محددة
user.Role = UserRole.CompanyAdmin;
```

---

## 🔗 بقية الكيانات

| الكيان | الملف | الوظيفة |
|--------|-------|---------|
| `Customer` | Customer.cs | عملاء الشركة |
| `Order` | Order.cs | الطلبات |
| `Payment` | Payment.cs | المدفوعات |
| `Product` | Product.cs | المنتجات |
| `Subscription` | Subscription.cs | الاشتراكات |
| `Citizen` | Citizen.cs | بيانات المواطنين |
| `SupportTicket` | SupportTicket.cs | تذاكر الدعم |

---

## 🎯 قواعد مهمة

### 1. الكيان لا يعتمد على أي شيء

```csharp
// ✅ صحيح - لا using خارجية
namespace Sadara.Domain.Entities;

public class User : BaseEntity<Guid>
{
    public string Name { get; set; }
}
```

```csharp
// ❌ خطأ - اعتماد على Infrastructure
using Sadara.Infrastructure.Data;  // ممنوع!
```

### 2. الكيان لا يحتوي منطق عمل معقد

```csharp
// ✅ صحيح - خصائص مساعدة بسيطة
public bool IsCompanyAdminOrAbove => Role >= UserRole.CompanyAdmin;
```

```csharp
// ❌ خطأ - منطق معقد (ضعه في Service)
public async Task SendEmail() { ... }
```

### 3. استخدم Navigation Properties للعلاقات

```csharp
public class Order : BaseEntity<Guid>
{
    // Foreign Key
    public Guid CustomerId { get; set; }
    
    // Navigation Property
    public virtual Customer Customer { get; set; }
}
```

---

## 🔄 كيف تضيف كيان جديد؟

### الخطوة 1: أنشئ الملف
```csharp
// src/Backend/Core/Sadara.Domain/Entities/Invoice.cs
public class Invoice : BaseEntity<Guid>
{
    public string InvoiceNumber { get; set; }
    public decimal Amount { get; set; }
    public Guid CustomerId { get; set; }
    public virtual Customer Customer { get; set; }
}
```

### الخطوة 2: سجّله في DbContext
```csharp
// في SadaraDbContext.cs
public DbSet<Invoice> Invoices => Set<Invoice>();
```

### الخطوة 3: أنشئ Migration
```powershell
cd src/Backend/Core/Sadara.Infrastructure
dotnet ef migrations add AddInvoice
```

---

## 📝 تمارين

1. **افتح `Order.cs`** - ما العلاقة بينه وبين `Customer`؟
2. **افتح `Payment.cs`** - ما الـ Enums المستخدمة؟
3. **فكر:** لماذا `CompanyId` في User هو `Guid?` (nullable)؟

---

## 🔗 الدرس التالي

[03_Infrastructure.md](./03_Infrastructure.md) - طبقة Infrastructure (قاعدة البيانات)
