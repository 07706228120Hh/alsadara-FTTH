# 🏗️ البنية التحتية لمنصة صدارة
## Sadara Platform Infrastructure Design

---

## 📊 نظرة عامة

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           Sadara Platform Architecture                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐         │
│   │  CompanyDesktop │    │   CitizenWeb    │    │   CitizenApp    │         │
│   │  (Flutter Win)  │    │  (Flutter Web)  │    │ (Flutter Mobile)│         │
│   └────────┬────────┘    └────────┬────────┘    └────────┬────────┘         │
│            │                      │                      │                   │
│            └──────────────────────┼──────────────────────┘                   │
│                                   │                                          │
│                                   ▼                                          │
│                    ┌──────────────────────────────┐                         │
│                    │     Sadara Platform API      │                         │
│                    │    (ASP.NET Core + EF)       │                         │
│                    │      72.61.183.61:443        │                         │
│                    └──────────────┬───────────────┘                         │
│                                   │                                          │
│                                   ▼                                          │
│                    ┌──────────────────────────────┐                         │
│                    │     PostgreSQL Database      │                         │
│                    │         sadara_db            │                         │
│                    └──────────────────────────────┘                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 🗄️ هيكل قاعدة البيانات

### 1️⃣ جدول الشركات (Companies)

```sql
CREATE TABLE "Companies" (
    "Id"                          UUID PRIMARY KEY,
    "Name"                        VARCHAR(200) NOT NULL,     -- اسم الشركة
    "NameAr"                      VARCHAR(200),              -- الاسم بالعربي
    "Code"                        VARCHAR(50) UNIQUE,        -- كود الشركة الفريد
    "Email"                       VARCHAR(200),
    "Phone"                       VARCHAR(20),
    "Address"                     TEXT,
    "City"                        VARCHAR(100),
    "LogoUrl"                     TEXT,
    "IsActive"                    BOOLEAN DEFAULT TRUE,
    
    -- معلومات الاشتراك
    "SubscriptionStartDate"       TIMESTAMP,
    "SubscriptionEndDate"         TIMESTAMP,
    "SubscriptionPlan"            INT,                       -- Basic=0, Professional=1, Enterprise=2
    "MaxUsers"                    INT DEFAULT 10,
    
    -- الميزات المفعلة (JSON)
    "EnabledFirstSystemFeatures"  JSONB,                     -- {"attendance":true,"agent":false}
    "EnabledSecondSystemFeatures" JSONB,                     -- {"users":true,"subscriptions":true}
    
    -- ربط نظام المواطن (شركة واحدة فقط = true)
    "IsLinkedToCitizenPortal"     BOOLEAN DEFAULT FALSE,
    "LinkedToCitizenPortalAt"     TIMESTAMP,
    "LinkedById"                  UUID,
    
    -- مدير الشركة
    "AdminUserId"                 UUID,
    
    "CreatedAt"                   TIMESTAMP DEFAULT NOW(),
    "UpdatedAt"                   TIMESTAMP
);
```

**📌 ملاحظة مهمة:**
- `IsLinkedToCitizenPortal = true` → هذه الشركة هي المرتبطة بتطبيق المواطن
- **شركة واحدة فقط** يمكن أن تكون مرتبطة بنظام المواطن في كل وقت

---

### 2️⃣ جدول المستخدمين/الموظفين (Users)

```sql
CREATE TABLE "Users" (
    "Id"                       UUID PRIMARY KEY,
    "FullName"                 VARCHAR(200) NOT NULL,
    "PhoneNumber"              VARCHAR(20) UNIQUE NOT NULL,
    "PasswordHash"             TEXT NOT NULL,
    "Email"                    VARCHAR(200),
    "Role"                     INT NOT NULL,                -- الدور (انظر أدناه)
    "IsActive"                 BOOLEAN DEFAULT TRUE,
    "IsPhoneVerified"          BOOLEAN DEFAULT FALSE,
    
    -- معلومات الشركة (للموظفين فقط)
    "CompanyId"                UUID REFERENCES "Companies"("Id"),
    "Department"               VARCHAR(100),                -- القسم
    "EmployeeCode"             VARCHAR(50),                 -- كود الموظف
    "Center"                   VARCHAR(100),                -- المركز/الفرع
    
    -- الصلاحيات (JSON)
    "FirstSystemPermissions"   JSONB,                       -- صلاحيات النظام الأول
    "SecondSystemPermissions"  JSONB,                       -- صلاحيات النظام الثاني
    
    -- الأمان
    "RefreshToken"             TEXT,
    "LastLoginAt"              TIMESTAMP,
    
    "CreatedAt"                TIMESTAMP DEFAULT NOW(),
    "UpdatedAt"                TIMESTAMP
);
```

**🔑 الأدوار (UserRole):**
```csharp
public enum UserRole
{
    Citizen = 0,        // مواطن (لا يستخدم في هذا الجدول)
    Employee = 1,       // موظف عادي
    Technician = 2,     // فني
    Accountant = 3,     // محاسب
    Manager = 4,        // مدير قسم
    CompanyAdmin = 5,   // مدير الشركة
    Support = 6,        // دعم فني
    SuperAdmin = 7      // مدير النظام الرئيسي
}
```

---

### 3️⃣ جدول المواطنين (Citizens)

```sql
CREATE TABLE "Citizens" (
    "Id"                       UUID PRIMARY KEY,
    "FullName"                 VARCHAR(200) NOT NULL,
    "PhoneNumber"              VARCHAR(20) UNIQUE NOT NULL,   -- المعرف الرئيسي
    "PasswordHash"             TEXT NOT NULL,
    "Email"                    VARCHAR(200),
    "ProfileImageUrl"          TEXT,
    
    -- العنوان
    "City"                     VARCHAR(100),                  -- المحافظة
    "District"                 VARCHAR(100),                  -- المنطقة/الحي
    "FullAddress"              TEXT,                          -- العنوان التفصيلي
    "Latitude"                 DOUBLE PRECISION,
    "Longitude"                DOUBLE PRECISION,
    
    -- 🔗 الربط بالشركة
    "CompanyId"                UUID NOT NULL REFERENCES "Companies"("Id"),
    "AssignedToCompanyAt"      TIMESTAMP DEFAULT NOW(),
    
    -- حالة الحساب
    "IsActive"                 BOOLEAN DEFAULT TRUE,
    "IsPhoneVerified"          BOOLEAN DEFAULT FALSE,
    "IsBanned"                 BOOLEAN DEFAULT FALSE,
    
    -- الإحصائيات
    "TotalRequests"            INT DEFAULT 0,
    "TotalPaid"                DECIMAL(18,2) DEFAULT 0,
    "LoyaltyPoints"            INT DEFAULT 0,
    
    "CreatedAt"                TIMESTAMP DEFAULT NOW(),
    "UpdatedAt"                TIMESTAMP
);
```

**📌 ملاحظة:**
- كل مواطن **يجب** أن يكون مرتبطاً بشركة واحدة (`CompanyId`)
- عند تسجيل مواطن جديد، يتم ربطه تلقائياً بالشركة التي `IsLinkedToCitizenPortal = true`

---

### 4️⃣ جدول باقات الإنترنت (InternetPlans)

```sql
CREATE TABLE "InternetPlans" (
    "Id"                UUID PRIMARY KEY,
    "CompanyId"         UUID REFERENCES "Companies"("Id"),  -- null = عامة لكل الشركات
    "Name"              VARCHAR(200) NOT NULL,
    "NameAr"            VARCHAR(200),
    "Description"       TEXT,
    "SpeedMbps"         INT,                                -- السرعة بالميغا
    "DataLimitGB"       INT,                                -- حد البيانات (null = unlimited)
    "MonthlyPrice"      DECIMAL(18,2) NOT NULL,
    "YearlyPrice"       DECIMAL(18,2),
    "InstallationFee"   DECIMAL(18,2) DEFAULT 0,
    "Features"          JSONB,                              -- ["WiFi مجاني", "راوتر مجاني"]
    "IsFeatured"        BOOLEAN DEFAULT FALSE,
    "IsActive"          BOOLEAN DEFAULT TRUE,
    "SortOrder"         INT DEFAULT 0,
    "CreatedAt"         TIMESTAMP DEFAULT NOW()
);
```

---

### 5️⃣ جدول اشتراكات المواطنين (CitizenSubscriptions)

```sql
CREATE TABLE "CitizenSubscriptions" (
    "Id"                     UUID PRIMARY KEY,
    "SubscriptionNumber"     VARCHAR(50) UNIQUE,            -- رقم الاشتراك
    "CitizenId"              UUID NOT NULL REFERENCES "Citizens"("Id"),
    "InternetPlanId"         UUID NOT NULL REFERENCES "InternetPlans"("Id"),
    "CompanyId"              UUID NOT NULL REFERENCES "Companies"("Id"),
    
    -- الحالة
    "Status"                 INT DEFAULT 0,                 -- Pending=0, AwaitingInstallation=1, Active=2, etc.
    "StartDate"              TIMESTAMP,
    "EndDate"                TIMESTAMP,
    "AutoRenew"              BOOLEAN DEFAULT FALSE,
    
    -- معلومات التركيب
    "InstallationAddress"    TEXT,
    "InstallationLatitude"   DOUBLE PRECISION,
    "InstallationLongitude"  DOUBLE PRECISION,
    "InstalledAt"            TIMESTAMP,
    "InstalledById"          UUID REFERENCES "Users"("Id"),
    
    -- المعدات
    "RouterSerialNumber"     VARCHAR(100),
    "ONUSerialNumber"        VARCHAR(100),
    
    -- المالية
    "AgreedPrice"            DECIMAL(18,2),
    "TotalPaid"              DECIMAL(18,2) DEFAULT 0,
    "OutstandingBalance"     DECIMAL(18,2) DEFAULT 0,
    
    "CreatedAt"              TIMESTAMP DEFAULT NOW(),
    "UpdatedAt"              TIMESTAMP
);
```

---

## 🔐 آلية المصادقة

### تطبيق الشركات (CompanyDesktop)

```
┌─────────────────────────────────────────────────────────────┐
│                   Company App Authentication                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   الموظف يدخل:                                              │
│   ├── رقم الهاتف: 07701234567                               │
│   └── كلمة المرور: ********                                 │
│                                                             │
│              ▼                                              │
│   ┌─────────────────────────────────────┐                  │
│   │  POST /api/auth/login               │                  │
│   │  {                                  │                  │
│   │    "phoneNumber": "07701234567",    │                  │
│   │    "password": "..."                │                  │
│   │  }                                  │                  │
│   └────────────────┬────────────────────┘                  │
│                    ▼                                        │
│   ┌─────────────────────────────────────┐                  │
│   │  API يتحقق من:                      │                  │
│   │  1. Users table (Role >= Employee)  │                  │
│   │  2. Company is active               │                  │
│   │  3. User permissions                │                  │
│   └────────────────┬────────────────────┘                  │
│                    ▼                                        │
│   ┌─────────────────────────────────────┐                  │
│   │  Response:                          │                  │
│   │  {                                  │                  │
│   │    "token": "JWT...",               │                  │
│   │    "user": {...},                   │                  │
│   │    "company": {...},                │                  │
│   │    "permissions": {...}             │                  │
│   │  }                                  │                  │
│   └─────────────────────────────────────┘                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### تطبيق المواطن (CitizenWeb/App)

```
┌─────────────────────────────────────────────────────────────┐
│                  Citizen App Authentication                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   المواطن يدخل:                                             │
│   ├── رقم الهاتف: 07727707702                               │
│   └── كلمة المرور: ********                                 │
│                                                             │
│              ▼                                              │
│   ┌─────────────────────────────────────┐                  │
│   │  POST /api/citizen/login            │                  │
│   │  {                                  │                  │
│   │    "phoneNumber": "07727707702",    │                  │
│   │    "password": "..."                │                  │
│   │  }                                  │                  │
│   └────────────────┬────────────────────┘                  │
│                    ▼                                        │
│   ┌─────────────────────────────────────┐                  │
│   │  API يتحقق من:                      │                  │
│   │  1. Citizens table                  │                  │
│   │  2. IsActive = true                 │                  │
│   │  3. IsPhoneVerified = true          │                  │
│   └────────────────┬────────────────────┘                  │
│                    ▼                                        │
│   ┌─────────────────────────────────────┐                  │
│   │  Response:                          │                  │
│   │  {                                  │                  │
│   │    "token": "JWT...",               │                  │
│   │    "citizen": {...},                │                  │
│   │    "company": {...}  // الشركة      │                  │
│   │  }                                  │                  │
│   └─────────────────────────────────────┘                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔗 الربط بين التطبيقين

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Data Flow Between Apps                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌───────────────────┐                    ┌───────────────────┐            │
│   │   CompanyDesktop  │                    │    CitizenWeb     │            │
│   │   (إدارة الشركة)  │                    │  (بوابة المواطن)  │            │
│   └─────────┬─────────┘                    └─────────┬─────────┘            │
│             │                                        │                      │
│   ┌─────────┴─────────────────────────────────────────┴─────────┐          │
│   │                                                             │          │
│   │   ما يفعله موظف الشركة:              ما يراه المواطن:       │          │
│   │   ─────────────────────              ──────────────────     │          │
│   │                                                             │          │
│   │   1. إنشاء باقات إنترنت    ────►    يرى الباقات المتاحة     │          │
│   │      POST /api/plans                 GET /api/citizen/plans │          │
│   │                                                             │          │
│   │   2. إدارة اشتراكات       ────►    يرى اشتراكاته           │          │
│   │      /api/subscriptions             /api/citizen/subscriptions│         │
│   │                                                             │          │
│   │   3. إدارة الدعم الفني    ────►    يرسل تذاكر دعم          │          │
│   │      /api/support                   /api/citizen/support    │          │
│   │                                                             │          │
│   │   4. إدارة المنتجات       ────►    يتصفح المتجر            │          │
│   │      /api/products                  /api/citizen/store      │          │
│   │                                                             │          │
│   │   5. إدارة العملاء        ────►    ملفه الشخصي             │          │
│   │      /api/citizens                  /api/citizen/profile    │          │
│   │                                                             │          │
│   └─────────────────────────────────────────────────────────────┘          │
│                                                                             │
│                              ▼                                              │
│                    ┌─────────────────────┐                                 │
│                    │   Shared Database   │                                 │
│                    │     PostgreSQL      │                                 │
│                    │     sadara_db       │                                 │
│                    └─────────────────────┘                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 📋 الـ API Endpoints

### 🏢 للشركات (يتطلب JWT + Role >= Employee)

| Endpoint | Method | الوصف |
|----------|--------|-------|
| `/api/auth/login` | POST | تسجيل دخول الموظف |
| `/api/companies/{id}` | GET | بيانات الشركة |
| `/api/users` | GET/POST | إدارة الموظفين |
| `/api/plans` | GET/POST/PUT/DELETE | إدارة الباقات |
| `/api/subscriptions` | GET/POST/PUT | إدارة الاشتراكات |
| `/api/citizens` | GET | قائمة المواطنين (عملاء الشركة) |
| `/api/products` | GET/POST/PUT/DELETE | إدارة المنتجات |
| `/api/support` | GET/PUT | إدارة تذاكر الدعم |
| `/api/dashboard` | GET | إحصائيات الشركة |

### 👤 للمواطنين (يتطلب JWT + CitizenId)

| Endpoint | Method | الوصف |
|----------|--------|-------|
| `/api/citizen/register` | POST | تسجيل مواطن جديد |
| `/api/citizen/login` | POST | تسجيل دخول المواطن |
| `/api/citizen/verify-phone` | POST | تفعيل الهاتف |
| `/api/citizen/profile` | GET/PUT | الملف الشخصي |
| `/api/citizen/plans` | GET | الباقات المتاحة |
| `/api/citizen/subscriptions` | GET/POST | اشتراكاتي |
| `/api/citizen/support` | GET/POST | تذاكر الدعم |
| `/api/citizen/store/products` | GET | تصفح المتجر |
| `/api/citizen/store/orders` | GET/POST | طلباتي |

---

## 🔄 آلية ربط المواطن بالشركة

### عند تسجيل مواطن جديد:

```csharp
// في CitizenAuthController.cs - Register

// 1. البحث عن الشركة المرتبطة بنظام المواطن
var linkedCompany = await _context.Companies
    .FirstOrDefaultAsync(c => c.IsLinkedToCitizenPortal && c.IsActive);

if (linkedCompany == null)
    return BadRequest("لا توجد شركة مفعلة لنظام المواطن");

// 2. إنشاء المواطن وربطه بالشركة
var citizen = new Citizen
{
    FullName = request.FullName,
    PhoneNumber = fullPhone,
    CompanyId = linkedCompany.Id,  // ✅ الربط التلقائي
    // ...
};
```

### تغيير الشركة المرتبطة (SuperAdmin فقط):

```csharp
// في SuperAdminController.cs

[HttpPost("link-company-to-citizen-portal/{companyId}")]
[Authorize(Roles = "SuperAdmin")]
public async Task<IActionResult> LinkCompanyToCitizenPortal(Guid companyId)
{
    // 1. إلغاء ربط الشركة السابقة
    var previousLinked = await _context.Companies
        .FirstOrDefaultAsync(c => c.IsLinkedToCitizenPortal);
    
    if (previousLinked != null)
    {
        previousLinked.IsLinkedToCitizenPortal = false;
    }
    
    // 2. ربط الشركة الجديدة
    var company = await _context.Companies.FindAsync(companyId);
    company.IsLinkedToCitizenPortal = true;
    company.LinkedToCitizenPortalAt = DateTime.UtcNow;
    
    await _context.SaveChangesAsync();
    
    // ⚠️ ملاحظة: المواطنون الحاليون يبقون مرتبطين بالشركة القديمة
    // المواطنون الجدد فقط سيرتبطون بالشركة الجديدة
}
```

---

## 📱 التطبيقات وأين تحفظ البيانات

### CompanyDesktop (Flutter Windows)

| البيانات | المصدر الحالي | المصدر المطلوب |
|----------|--------------|----------------|
| تسجيل الدخول | ⚠️ admin.ftth.iq (خارجي) | ✅ Sadara API `/api/auth/login` |
| المستأجرين | ⚠️ Firebase Firestore | ✅ Sadara API `/api/companies` |
| الموظفين | ⚠️ Firebase Firestore | ✅ Sadara API `/api/users` |
| الاشتراكات | ⚠️ admin.ftth.iq | ✅ Sadara API `/api/subscriptions` |
| المهام | ⚠️ Firebase Firestore | ✅ Sadara API `/api/tasks` |

### CitizenWeb (Flutter Web)

| البيانات | المصدر |
|----------|--------|
| تسجيل الدخول | ✅ Sadara API `/api/citizen/login` |
| الباقات | ✅ Sadara API `/api/citizen/plans` |
| الاشتراكات | ✅ Sadara API `/api/citizen/subscriptions` |
| المتجر | ✅ Sadara API `/api/citizen/store` |
| الدعم | ✅ Sadara API `/api/citizen/support` |

---

## 🎯 خطة التوحيد

### المرحلة 1: توحيد المصادقة ✅
- [x] إنشاء `/api/auth/login` للموظفين
- [x] إنشاء `/api/citizen/login` للمواطنين
- [x] دعم أرقام الهاتف العراقية والسعودية

### المرحلة 2: توحيد بيانات الشركات 🔄
- [ ] تعديل CompanyDesktop لاستخدام Sadara API
- [ ] ترحيل بيانات Firebase إلى PostgreSQL
- [ ] إزالة الاعتماد على admin.ftth.iq

### المرحلة 3: توحيد الاشتراكات 📋
- [ ] ربط اشتراكات المواطنين بالشركة
- [ ] إنشاء dashboard موحد للشركة

### المرحلة 4: توحيد المتجر والمنتجات 🛒
- [ ] ربط المنتجات بالشركة
- [ ] إنشاء نظام طلبات موحد

---

## 📞 أرقام الهاتف المدعومة

```
┌─────────────────────────────────────────────────────────────┐
│                   Supported Phone Formats                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   🇮🇶 العراق (+964):                                        │
│   ├── 07701234567                                           │
│   ├── 7701234567                                            │
│   ├── +9647701234567                                        │
│   ├── 009647701234567                                       │
│   └── أكواد: 750-759 (Korek), 770-779 (Asia Cell),         │
│             780-789 (Zain), 790-799                         │
│                                                             │
│   🇸🇦 السعودية (+966):                                      │
│   ├── 0512345678                                            │
│   ├── 512345678                                             │
│   ├── +966512345678                                         │
│   └── 00966512345678                                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 ملفات الإعداد

### API Configuration (appsettings.Production.json)
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Database=sadara_db;Username=sadara_user;Password=..."
  },
  "Jwt": {
    "Secret": "...",
    "Issuer": "SadaraPlatform",
    "Audience": "SadaraApps",
    "ExpiryMinutes": 60
  }
}
```

### Flutter API Config (api_config.dart)
```dart
class ApiConfig {
  // للتطوير
  // static const String baseUrl = 'http://localhost:5000';
  
  // للإنتاج
  static const String baseUrl = 'http://72.61.183.61';
}
```

---

## 📝 الخلاصة

| التطبيق | المستخدم | جدول البيانات | نقطة الوصول |
|---------|----------|--------------|-------------|
| CompanyDesktop | موظف/مدير | Users + Companies | `/api/auth/*` |
| CitizenWeb | مواطن | Citizens | `/api/citizen/*` |
| Both | - | Shared DB | PostgreSQL |

**🔑 المفتاح الأساسي للربط:**
- `Company.IsLinkedToCitizenPortal = true` → الشركة المرتبطة بنظام المواطن
- `Citizen.CompanyId` → ربط المواطن بالشركة
- كل البيانات في قاعدة بيانات واحدة `sadara_db`
