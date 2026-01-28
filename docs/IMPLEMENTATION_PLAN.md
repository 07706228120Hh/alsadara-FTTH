# 📋 خطة التنفيذ الشاملة - منصة صدارة
## Sadara Platform Implementation Plan

---

## 📑 فهرس المحتويات
1. [نظرة عامة](#نظرة-عامة)
2. [المرحلة 1: نظام الصلاحيات والشركات](#المرحلة-1)
3. [المرحلة 2: نظام الخدمات والعمليات](#المرحلة-2)
4. [المرحلة 3: تطبيق المواطن PWA](#المرحلة-3)
5. [المرحلة 4: تكامل تطبيق الشركة](#المرحلة-4)
6. [المرحلة 5: إعداد VPS والنشر](#المرحلة-5)
7. [المرحلة 6: بوابة الدفع](#المرحلة-6)
8. [المرحلة 7: التحسينات والأمان](#المرحلة-7)

---

## 🎯 نظرة عامة {#نظرة-عامة}

### رؤية المشروع
منصة صدارة هي منصة متكاملة للمواطنين العراقيين تربط بين:
- **تطبيق المواطن (PWA)**: للمواطنين لطلب الخدمات والتسوق
- **تطبيق الشركة (Desktop/Web)**: لإدارة الطلبات والعمليات
- **API موحد**: يربط جميع الأنظمة

### البنية التقنية
```
┌─────────────────────────────────────────────────────────────┐
│                     VPS (72.61.183.61)                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌────────────┐  │
│  │   Sadara API    │  │   PostgreSQL    │  │   Nginx    │  │
│  │   (.NET 9)      │  │   Database      │  │   Proxy    │  │
│  └─────────────────┘  └─────────────────┘  └────────────┘  │
└─────────────────────────────────────────────────────────────┘
           │                    │
           ▼                    ▼
┌──────────────────┐   ┌──────────────────┐
│  Citizen PWA     │   │  Company App     │
│  (Blazor WASM)   │   │  (Flutter)       │
│  - التسجيل       │   │  - إدارة الطلبات │
│  - طلب الخدمات   │   │  - الصلاحيات     │
│  - التسوق        │   │  - التقارير      │
└──────────────────┘   └──────────────────┘
           │                    │
           ▼                    ▼
┌─────────────────────────────────────────────────────────────┐
│                    Firebase Firestore                        │
│              (Real-time Sync & Notifications)                │
└─────────────────────────────────────────────────────────────┘
```

### الوضع الحالي ✅
- [x] Backend Controllers (18 controller)
- [x] Clean Architecture
- [x] Entity Models
- [x] Project Structure Organized
- [x] Git Repository Initialized
- [x] VPS Purchased (Hostinger)
- [x] Firebase Project Created

---

## 🔐 المرحلة 1: نظام الصلاحيات والشركات {#المرحلة-1}

### المدة المقدرة: 5-7 أيام

### 1.1 هيكل الصلاحيات
```
Super Admin (أنت)
    │
    ├── Company 1
    │   ├── Company Admin ← يُنشأ مع الشركة
    │   │   ├── Employee 1 (صلاحيات محددة)
    │   │   ├── Employee 2 (صلاحيات محددة)
    │   │   └── Employee 3 (صلاحيات محددة)
    │   └── Settings, Services, etc.
    │
    └── Company 2
        ├── Company Admin
        │   └── Employees...
        └── ...
```

### 1.2 Entities المطلوبة

#### Company.cs
```csharp
public class Company : BaseEntity
{
    public string Name { get; set; }
    public string NameAr { get; set; }
    public string Code { get; set; } // Unique company code
    public string Logo { get; set; }
    public string Phone { get; set; }
    public string Email { get; set; }
    public string Address { get; set; }
    public string City { get; set; }
    public bool IsActive { get; set; }
    public DateTime? SubscriptionExpiresAt { get; set; }
    
    // Admin User (created with company)
    public Guid AdminUserId { get; set; }
    public User AdminUser { get; set; }
    
    // Navigation
    public ICollection<User> Employees { get; set; }
    public ICollection<CompanyService> Services { get; set; }
}
```

#### Permission.cs
```csharp
public class Permission : BaseEntity
{
    public string Module { get; set; }  // e.g., "Requests", "Users", "Reports"
    public string Action { get; set; }  // "View", "Create", "Edit", "Delete"
    public string Code { get; set; }    // "requests.view", "users.create"
    public string NameAr { get; set; }
    public string Description { get; set; }
}
```

#### UserPermission.cs
```csharp
public class UserPermission : BaseEntity
{
    public Guid UserId { get; set; }
    public User User { get; set; }
    
    public Guid PermissionId { get; set; }
    public Permission Permission { get; set; }
    
    public Guid GrantedById { get; set; } // Company Admin who granted
    public DateTime GrantedAt { get; set; }
}
```

### 1.3 قائمة الصلاحيات الأولية
| Module | Actions | Codes |
|--------|---------|-------|
| Dashboard | View | `dashboard.view` |
| Requests | View, Create, Edit, Delete, Assign | `requests.*` |
| Users | View, Create, Edit, Delete | `users.*` |
| Reports | View, Export | `reports.*` |
| Settings | View, Edit | `settings.*` |
| Services | View, Edit | `services.*` |
| Transactions | View, Create | `transactions.*` |

### 1.4 APIs المطلوبة

```
POST   /api/companies              - إنشاء شركة + أدمن (Super Admin فقط)
GET    /api/companies              - قائمة الشركات (Super Admin)
GET    /api/companies/{id}         - تفاصيل شركة
PUT    /api/companies/{id}         - تعديل شركة
DELETE /api/companies/{id}         - حذف شركة

POST   /api/companies/{id}/employees     - إضافة موظف (Company Admin)
GET    /api/companies/{id}/employees     - قائمة الموظفين
PUT    /api/employees/{id}/permissions   - تعديل صلاحيات موظف
DELETE /api/employees/{id}               - حذف موظف

GET    /api/permissions                  - قائمة الصلاحيات المتاحة
GET    /api/me/permissions               - صلاحياتي الحالية
```

### 1.5 المهام التفصيلية
- [ ] إنشاء Entity: Company
- [ ] إنشاء Entity: Permission
- [ ] إنشاء Entity: UserPermission
- [ ] تحديث Entity: User (إضافة Role, CompanyId)
- [ ] إنشاء CompaniesController
- [ ] إنشاء PermissionsController
- [ ] إنشاء EmployeesController
- [ ] إنشاء Seed Data للصلاحيات
- [ ] إنشاء Permission Middleware
- [ ] اختبار CRUD العمليات

---

## 🔧 المرحلة 2: نظام الخدمات والعمليات {#المرحلة-2}

### المدة المقدرة: 4-5 أيام

### 2.1 مفهوم الخدمات والعمليات
```
الخدمات (Services)          العمليات (Operations)
─────────────────          ────────────────────
├── 🌐 الإنترنت              ├── شراء جديد
│                           ├── تجديد
│                           ├── صيانة
│                           ├── تغيير الباقة
│                           ├── شكوى
│                           └── إلغاء
│
├── 📦 المنتجات              ├── شراء
│                           ├── استبدال
│                           ├── إرجاع
│                           └── شكوى
│
├── 💳 الخدمات المالية       ├── تحويل
│                           ├── دفع فواتير
│                           └── شحن رصيد
│
└── 🔧 خدمات أخرى           └── ...
```

### 2.2 Entities المطلوبة

#### Service.cs
```csharp
public class Service : BaseEntity
{
    public string Name { get; set; }
    public string NameAr { get; set; }
    public string Icon { get; set; }
    public string Color { get; set; }
    public int DisplayOrder { get; set; }
    public bool IsActive { get; set; }
    
    // Navigation
    public ICollection<ServiceOperation> Operations { get; set; }
}
```

#### OperationType.cs
```csharp
public class OperationType : BaseEntity
{
    public string Name { get; set; }
    public string NameAr { get; set; }
    public string Icon { get; set; }
    public bool RequiresApproval { get; set; }
    public bool RequiresTechnician { get; set; }
    public int EstimatedDays { get; set; }
}
```

#### ServiceOperation.cs (Many-to-Many)
```csharp
public class ServiceOperation : BaseEntity
{
    public Guid ServiceId { get; set; }
    public Service Service { get; set; }
    
    public Guid OperationTypeId { get; set; }
    public OperationType OperationType { get; set; }
    
    public decimal? BasePrice { get; set; }
    public bool IsActive { get; set; }
    public string CustomSettings { get; set; } // JSON
}
```

#### ServiceRequest.cs (الطلب الموحد)
```csharp
public class ServiceRequest : BaseEntity
{
    public string RequestNumber { get; set; } // SR-2025-00001
    
    // Service & Operation
    public Guid ServiceId { get; set; }
    public Service Service { get; set; }
    
    public Guid OperationTypeId { get; set; }
    public OperationType OperationType { get; set; }
    
    // Citizen
    public Guid CitizenId { get; set; }
    public User Citizen { get; set; }
    
    // Company (assigned to)
    public Guid? CompanyId { get; set; }
    public Company Company { get; set; }
    
    // Status
    public RequestStatus Status { get; set; }
    public string StatusNote { get; set; }
    
    // Dates
    public DateTime RequestedAt { get; set; }
    public DateTime? AssignedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    public DateTime? CancelledAt { get; set; }
    
    // Details
    public string Details { get; set; } // JSON - flexible fields
    public string Address { get; set; }
    public string Phone { get; set; }
    public decimal? EstimatedCost { get; set; }
    public decimal? FinalCost { get; set; }
    
    // Assignment
    public Guid? AssignedToId { get; set; }
    public User AssignedTo { get; set; }
    
    // Navigation
    public ICollection<RequestComment> Comments { get; set; }
    public ICollection<RequestAttachment> Attachments { get; set; }
}
```

### 2.3 Request Statuses
```csharp
public enum RequestStatus
{
    Pending = 0,        // جديد - بانتظار المراجعة
    Reviewing = 1,      // قيد المراجعة
    Approved = 2,       // موافق عليه
    Assigned = 3,       // تم التعيين
    InProgress = 4,     // قيد التنفيذ
    Completed = 5,      // مكتمل
    Cancelled = 6,      // ملغي
    Rejected = 7,       // مرفوض
    OnHold = 8          // معلق
}
```

### 2.4 APIs المطلوبة
```
# Services
GET    /api/services                    - قائمة الخدمات
GET    /api/services/{id}               - تفاصيل خدمة
GET    /api/services/{id}/operations    - عمليات خدمة معينة

# Operation Types
GET    /api/operation-types             - أنواع العمليات

# Service Requests
POST   /api/requests                    - إنشاء طلب جديد (Citizen)
GET    /api/requests                    - قائمة الطلبات (مع فلترة)
GET    /api/requests/{id}               - تفاصيل طلب
PUT    /api/requests/{id}/status        - تحديث حالة
PUT    /api/requests/{id}/assign        - تعيين موظف
POST   /api/requests/{id}/comments      - إضافة تعليق
```

### 2.5 Seed Data للخدمات والعمليات
```sql
-- Services
INSERT INTO Services VALUES 
('Internet', 'الإنترنت', 'wifi', '#3B82F6', 1, true),
('Products', 'المنتجات', 'shopping-bag', '#10B981', 2, true),
('Financial', 'الخدمات المالية', 'credit-card', '#8B5CF6', 3, true);

-- Operation Types
INSERT INTO OperationTypes VALUES
('Purchase', 'شراء جديد', 'plus', false, false, 3),
('Renewal', 'تجديد', 'refresh', false, false, 1),
('Maintenance', 'صيانة', 'wrench', false, true, 2),
('Change', 'تغيير', 'swap', true, false, 2),
('Complaint', 'شكوى', 'alert', false, false, 5),
('Cancel', 'إلغاء', 'x', true, false, 1);

-- Service Operations (which services support which operations)
INSERT INTO ServiceOperations (ServiceId, OperationTypeId, IsActive) VALUES
(InternetId, PurchaseId, true),
(InternetId, RenewalId, true),
(InternetId, MaintenanceId, true),
(InternetId, ChangeId, true),
(InternetId, ComplaintId, true),
(InternetId, CancelId, true),
(ProductsId, PurchaseId, true),
(ProductsId, ComplaintId, true);
```

---

## 📱 المرحلة 3: تطبيق المواطن PWA {#المرحلة-3}

### المدة المقدرة: 10-12 يوم

### 3.1 التقنية المستخدمة
- **Blazor WebAssembly** - PWA
- **MudBlazor** - UI Components
- **Firebase** - Push Notifications

### 3.2 هيكل المشروع
```
src/Apps/CitizenWeb/
├── Sadara.CitizenPWA/
│   ├── Pages/
│   │   ├── Index.razor           # الصفحة الرئيسية
│   │   ├── Auth/
│   │   │   ├── Login.razor
│   │   │   ├── Register.razor
│   │   │   └── Profile.razor
│   │   ├── Services/
│   │   │   ├── ServicesList.razor
│   │   │   ├── ServiceDetails.razor
│   │   │   └── NewRequest.razor
│   │   ├── Requests/
│   │   │   ├── MyRequests.razor
│   │   │   └── RequestDetails.razor
│   │   ├── Shop/
│   │   │   ├── Products.razor
│   │   │   ├── ProductDetails.razor
│   │   │   ├── Cart.razor
│   │   │   └── Checkout.razor
│   │   └── Settings/
│   │       └── Settings.razor
│   ├── Components/
│   │   ├── Layout/
│   │   ├── Shared/
│   │   └── Forms/
│   ├── Services/
│   │   ├── ApiService.cs
│   │   ├── AuthService.cs
│   │   └── NotificationService.cs
│   ├── wwwroot/
│   │   ├── manifest.json
│   │   └── service-worker.js
│   └── Program.cs
```

### 3.3 الصفحات الرئيسية

#### الصفحة الرئيسية
```
┌─────────────────────────────────────┐
│  🏠 مرحباً، أحمد                    │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│                                     │
│  ┌─────────┐ ┌─────────┐ ┌────────┐│
│  │ 🌐      │ │ 📦      │ │ 💳     ││
│  │ الإنترنت │ │ المنتجات │ │ المالية ││
│  └─────────┘ └─────────┘ └────────┘│
│                                     │
│  📋 طلباتي الأخيرة                  │
│  ─────────────────────────          │
│  ├── طلب صيانة #1234 - قيد التنفيذ │
│  ├── تجديد اشتراك #1233 - مكتمل    │
│  └── شراء جهاز #1232 - تم التسليم  │
│                                     │
│  🛒 سلة المشتريات (3)               │
│                                     │
└─────────────────────────────────────┘
```

### 3.4 المهام التفصيلية
- [ ] إنشاء مشروع Blazor WASM جديد
- [ ] إضافة MudBlazor
- [ ] إعداد PWA (manifest.json, service-worker)
- [ ] صفحة تسجيل الدخول/التسجيل
- [ ] الصفحة الرئيسية
- [ ] قائمة الخدمات
- [ ] نموذج طلب جديد
- [ ] قائمة طلباتي
- [ ] تفاصيل الطلب
- [ ] المتجر والسلة
- [ ] صفحة الدفع
- [ ] الإشعارات
- [ ] تحسين للموبايل (Responsive)

---

## 🖥️ المرحلة 4: تكامل تطبيق الشركة {#المرحلة-4}

### المدة المقدرة: 7-10 أيام

### 4.1 الواجهة المطلوبة - Tabbed Requests View
```
┌─────────────────────────────────────────────────────────────┐
│  🏢 لوحة تحكم الشركة                              🔔 👤 ⚙️  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────┬──────────┬──────────┬──────────┬───────────┐ │
│  │ 🌐 الإنترنت │ 📦 المنتجات │ 💳 المالية │ 🔧 أخرى   │ + جديد │ │
│  └──────────┴──────────┴──────────┴──────────┴───────────┘ │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │ 🔍 بحث... │ 📅 التاريخ │ 📊 الحالة │ 👤 الموظف │ ⬇️ │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │ # │ نوع العملية │ المواطن   │ الحالة  │ التاريخ │ ⋮ │ │
│  ├───┼────────────┼───────────┼─────────┼─────────┼───┤ │
│  │ 1 │ 🔄 تجديد   │ أحمد محمد │ 🟡 جديد │ 15/01  │ ⋮ │ │
│  │ 2 │ 🔧 صيانة   │ سارة علي  │ 🔵 قيد   │ 14/01  │ ⋮ │ │
│  │ 3 │ ➕ شراء    │ محمد خالد │ 🟢 مكتمل │ 13/01  │ ⋮ │ │
│  │ 4 │ 📝 شكوى   │ فاطمة     │ 🔴 مرفوض │ 12/01  │ ⋮ │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                             │
│  📊 إحصائيات: جديد (12) | قيد التنفيذ (8) | مكتمل (45)    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 التعديلات على Flutter App
الملفات الموجودة في: `src/Apps/CompanyDesktop/alsadara-ftth/`

#### تحديث Models
```dart
// lib/models/service_request.dart
class ServiceRequest {
  final String id;
  final String requestNumber;
  final String serviceId;
  final String serviceName;
  final String operationTypeId;
  final String operationTypeName;
  final String citizenId;
  final String citizenName;
  final String citizenPhone;
  final RequestStatus status;
  final String? assignedToId;
  final String? assignedToName;
  final DateTime requestedAt;
  final DateTime? completedAt;
  final String? details;
  final String? address;
  
  // ...
}
```

#### إنشاء صفحة الطلبات الموحدة
```dart
// lib/pages/unified_requests_page.dart
class UnifiedRequestsPage extends StatefulWidget {
  // Tab-based view for all services
  // Filter by operation type
  // Real-time updates from API
}
```

### 4.3 المهام التفصيلية
- [ ] تحديث Models للطلبات الجديدة
- [ ] إنشاء صفحة الطلبات الموحدة (Tabbed)
- [ ] ربط مع API الجديد
- [ ] فلترة حسب نوع العملية
- [ ] Real-time updates (WebSocket/Firebase)
- [ ] صفحة تفاصيل الطلب
- [ ] نظام التعيين للموظفين
- [ ] إشعارات الطلبات الجديدة

---

## 🖥️ المرحلة 5: إعداد VPS والنشر {#المرحلة-5}

### المدة المقدرة: 2-3 أيام

### 5.1 معلومات VPS
- **Provider**: Hostinger KVM 2
- **IP**: 72.61.183.61
- **OS**: Ubuntu 24.04 LTS
- **Specs**: 8GB RAM, 2 CPU, 100GB SSD

### 5.2 خطوات الإعداد

#### 1. الاتصال وتحديث النظام
```bash
ssh root@72.61.183.61

# Update system
apt update && apt upgrade -y

# Install essentials
apt install -y curl wget git unzip
```

#### 2. تثبيت .NET 9
```bash
# Add Microsoft repository
wget https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
apt update

# Install .NET 9
apt install -y dotnet-sdk-9.0
```

#### 3. تثبيت PostgreSQL
```bash
# Install PostgreSQL
apt install -y postgresql postgresql-contrib

# Setup database
sudo -u postgres psql
CREATE USER sadara WITH PASSWORD 'YOUR_SECURE_PASSWORD';
CREATE DATABASE sadara_db OWNER sadara;
GRANT ALL PRIVILEGES ON DATABASE sadara_db TO sadara;
\q

# Allow remote connections (if needed)
# Edit /etc/postgresql/16/main/postgresql.conf
# Edit /etc/postgresql/16/main/pg_hba.conf
```

#### 4. تثبيت Nginx
```bash
apt install -y nginx

# Configure site
nano /etc/nginx/sites-available/sadara
```

#### 5. إعداد Nginx Config
```nginx
server {
    listen 80;
    server_name api.sadara.iq;

    location / {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80;
    server_name sadara.iq www.sadara.iq;

    location / {
        root /var/www/sadara-citizen;
        try_files $uri $uri/ /index.html;
    }
}
```

#### 6. SSL Certificate
```bash
apt install -y certbot python3-certbot-nginx
certbot --nginx -d api.sadara.iq -d sadara.iq -d www.sadara.iq
```

#### 7. نشر API
```bash
# Create app directory
mkdir -p /var/www/sadara-api
cd /var/www/sadara-api

# Deploy (from local)
# On local machine:
dotnet publish -c Release -o ./publish
scp -r ./publish/* root@72.61.183.61:/var/www/sadara-api/

# Create service
nano /etc/systemd/system/sadara-api.service
```

```ini
[Unit]
Description=Sadara API
After=network.target

[Service]
WorkingDirectory=/var/www/sadara-api
ExecStart=/usr/bin/dotnet Sadara.API.dll
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=sadara-api
User=www-data
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://localhost:5000

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable sadara-api
systemctl start sadara-api
```

### 5.3 المهام التفصيلية
- [ ] الاتصال بـ VPS
- [ ] تثبيت .NET 9
- [ ] تثبيت PostgreSQL
- [ ] إعداد قاعدة البيانات
- [ ] تثبيت Nginx
- [ ] إعداد SSL
- [ ] نشر API
- [ ] نشر Citizen PWA
- [ ] اختبار النظام

---

## 💳 المرحلة 6: بوابة الدفع {#المرحلة-6}

### المدة المقدرة: 3-4 أيام

### 6.1 ZainCash Integration

#### بنية الإعدادات الديناميكية
```csharp
public class PaymentSettings : BaseEntity
{
    public string Provider { get; set; } // "ZainCash", "FastPay", etc.
    public string MerchantId { get; set; }
    public string SecretKey { get; set; }
    public string ApiUrl { get; set; }
    public string CallbackUrl { get; set; }
    public bool IsProduction { get; set; }
    public bool IsActive { get; set; }
    public string ExtraSettings { get; set; } // JSON
}
```

### 6.2 Payment Flow
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Citizen   │────▶│  Sadara API │────▶│  ZainCash   │
│   (PWA)     │     │             │     │   API       │
└─────────────┘     └─────────────┘     └─────────────┘
      │                   │                   │
      │  1. Checkout      │                   │
      │──────────────────▶│                   │
      │                   │  2. Create Order  │
      │                   │──────────────────▶│
      │                   │  3. Payment URL   │
      │                   │◀──────────────────│
      │  4. Redirect      │                   │
      │◀──────────────────│                   │
      │                   │                   │
      │  5. Pay on ZainCash                   │
      │──────────────────────────────────────▶│
      │                   │                   │
      │                   │  6. Callback      │
      │                   │◀──────────────────│
      │  7. Confirmation  │                   │
      │◀──────────────────│                   │
```

### 6.3 APIs المطلوبة
```
POST /api/payments/initiate      - بدء عملية الدفع
POST /api/payments/callback      - استقبال نتيجة الدفع
GET  /api/payments/{id}/status   - حالة الدفع
GET  /api/payments/my            - مدفوعاتي
```

---

## 🔒 المرحلة 7: التحسينات والأمان {#المرحلة-7}

### المدة المقدرة: 3-4 أيام

### 7.1 Security Checklist
- [ ] JWT Token Security
- [ ] Rate Limiting
- [ ] Input Validation
- [ ] SQL Injection Prevention
- [ ] XSS Prevention
- [ ] CORS Configuration
- [ ] HTTPS Enforcement
- [ ] Password Hashing (bcrypt)
- [ ] Audit Logging
- [ ] Error Handling (no sensitive data)

### 7.2 Performance
- [ ] Response Caching
- [ ] Database Indexing
- [ ] Query Optimization
- [ ] Lazy Loading
- [ ] Pagination

### 7.3 Monitoring
- [ ] Health Checks
- [ ] Logging (Serilog)
- [ ] Error Tracking
- [ ] Performance Metrics

---

## 📅 الجدول الزمني الكلي

| المرحلة | المدة | تاريخ البدء | تاريخ الانتهاء |
|---------|-------|------------|---------------|
| المرحلة 1: الصلاحيات | 5-7 أيام | - | - |
| المرحلة 2: الخدمات | 4-5 أيام | - | - |
| المرحلة 3: PWA | 10-12 يوم | - | - |
| المرحلة 4: تطبيق الشركة | 7-10 أيام | - | - |
| المرحلة 5: VPS | 2-3 أيام | - | - |
| المرحلة 6: الدفع | 3-4 أيام | - | - |
| المرحلة 7: الأمان | 3-4 أيام | - | - |
| **المجموع** | **34-45 يوم** | - | - |

---

## 🚀 الخطوة التالية

**ابدأ بالمرحلة 1: نظام الصلاحيات والشركات**

للبدء، أخبرني وسأقوم بـ:
1. إنشاء الـ Entities الجديدة (Company, Permission, UserPermission)
2. تحديث User Entity
3. إنشاء Controllers الجديدة
4. إنشاء Migration

---

## 📝 ملاحظات مهمة

1. **Firebase**: يُستخدم فقط للـ Real-time sync والإشعارات، البيانات الأساسية في PostgreSQL
2. **الصلاحيات**: يتم تخزينها في الـ JWT Token لتقليل الاستعلامات
3. **الطلبات**: جدول موحد لكل أنواع الطلبات مع Details كـ JSON
4. **PWA**: يمكن تثبيته على أي جهاز (موبايل/ديسكتوب) بدون app stores

---

**تم إنشاء هذه الخطة بتاريخ**: $(Get-Date -Format "yyyy-MM-dd")

**آخر تحديث**: $(Get-Date -Format "yyyy-MM-dd HH:mm")
