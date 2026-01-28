# 🗄️ توثيق قاعدة البيانات

## 📊 الجداول الرئيسية

### 👥 المستخدمون والشركات

```sql
-- الشركات
CREATE TABLE Companies (
    Id SERIAL PRIMARY KEY,
    Name VARCHAR(200) NOT NULL,
    NameEn VARCHAR(200),
    Logo VARCHAR(500),
    Address TEXT,
    Phone VARCHAR(20),
    Email VARCHAR(100),
    IsActive BOOLEAN DEFAULT TRUE,
    AdminUserId INT,
    CreatedAt TIMESTAMP DEFAULT NOW()
);

-- المستخدمون
CREATE TABLE Users (
    Id SERIAL PRIMARY KEY,
    FullName VARCHAR(200) NOT NULL,
    Phone VARCHAR(20) UNIQUE NOT NULL,
    Email VARCHAR(100),
    PasswordHash VARCHAR(500),
    Role VARCHAR(50) NOT NULL, -- SuperAdmin, CompanyAdmin, Employee, Citizen
    CompanyId INT REFERENCES Companies(Id),
    IsActive BOOLEAN DEFAULT TRUE,
    CreatedAt TIMESTAMP DEFAULT NOW()
);
```

### 🔐 الصلاحيات

```sql
-- الصلاحيات المتاحة
CREATE TABLE Permissions (
    Id SERIAL PRIMARY KEY,
    Code VARCHAR(100) UNIQUE NOT NULL,
    NameAr VARCHAR(200),
    NameEn VARCHAR(200),
    Module VARCHAR(50), -- Users, Services, Requests, Settings
    Action VARCHAR(50)  -- View, Create, Edit, Delete
);

-- صلاحيات المستخدم
CREATE TABLE UserPermissions (
    Id SERIAL PRIMARY KEY,
    UserId INT REFERENCES Users(Id),
    PermissionId INT REFERENCES Permissions(Id),
    GrantedBy INT REFERENCES Users(Id),
    GrantedAt TIMESTAMP DEFAULT NOW()
);
```

### 🛠️ الخدمات والعمليات

```sql
-- الخدمات الرئيسية (إنترنت، منتجات، ...)
CREATE TABLE Services (
    Id SERIAL PRIMARY KEY,
    Code VARCHAR(50) UNIQUE NOT NULL,
    NameAr VARCHAR(200) NOT NULL,
    NameEn VARCHAR(200),
    Icon VARCHAR(100),
    DisplayOrder INT DEFAULT 0,
    IsActive BOOLEAN DEFAULT TRUE
);

-- أنواع العمليات (شراء، تجديد، صيانة، ...)
CREATE TABLE OperationTypes (
    Id SERIAL PRIMARY KEY,
    Code VARCHAR(50) UNIQUE NOT NULL,
    NameAr VARCHAR(200) NOT NULL,
    NameEn VARCHAR(200),
    Icon VARCHAR(100),
    IsActive BOOLEAN DEFAULT TRUE
);

-- ربط الخدمات بالعمليات المتاحة
CREATE TABLE ServiceOperations (
    Id SERIAL PRIMARY KEY,
    ServiceId INT REFERENCES Services(Id),
    OperationTypeId INT REFERENCES OperationTypes(Id),
    DisplayOrder INT DEFAULT 0,
    IsActive BOOLEAN DEFAULT TRUE,
    FormSchema JSONB -- تعريف حقول النموذج
);
```

### 📝 الطلبات

```sql
-- طلبات المواطنين
CREATE TABLE ServiceRequests (
    Id SERIAL PRIMARY KEY,
    RequestNumber VARCHAR(50) UNIQUE NOT NULL,
    ServiceId INT REFERENCES Services(Id),
    OperationTypeId INT REFERENCES OperationTypes(Id),
    CustomerId INT REFERENCES Users(Id),
    CompanyId INT REFERENCES Companies(Id),
    Status VARCHAR(50) DEFAULT 'New',
    Priority VARCHAR(20) DEFAULT 'Normal',
    AssignedToId INT REFERENCES Users(Id),
    RequestData JSONB,
    Notes TEXT,
    CreatedAt TIMESTAMP DEFAULT NOW(),
    UpdatedAt TIMESTAMP,
    CompletedAt TIMESTAMP
);

-- سجل تغييرات الحالة
CREATE TABLE RequestStatusHistory (
    Id SERIAL PRIMARY KEY,
    RequestId INT REFERENCES ServiceRequests(Id),
    OldStatus VARCHAR(50),
    NewStatus VARCHAR(50),
    ChangedById INT REFERENCES Users(Id),
    Notes TEXT,
    CreatedAt TIMESTAMP DEFAULT NOW()
);
```

---

## 📊 البيانات الأولية

```sql
-- الخدمات الافتراضية
INSERT INTO Services (Code, NameAr, NameEn, Icon, DisplayOrder) VALUES
('internet', 'الإنترنت', 'Internet', 'wifi', 1),
('products', 'المنتجات', 'Products', 'shopping_cart', 2);

-- العمليات الافتراضية
INSERT INTO OperationTypes (Code, NameAr, NameEn, Icon) VALUES
('purchase', 'شراء', 'Purchase', 'add_shopping_cart'),
('renewal', 'تجديد', 'Renewal', 'refresh'),
('maintenance', 'صيانة', 'Maintenance', 'build'),
('change', 'تغيير', 'Change', 'swap_horiz'),
('complaint', 'شكوى', 'Complaint', 'report_problem'),
('cancellation', 'إلغاء', 'Cancellation', 'cancel');

-- ربط عمليات الإنترنت
INSERT INTO ServiceOperations (ServiceId, OperationTypeId, DisplayOrder) VALUES
(1, 1, 1), -- إنترنت - شراء
(1, 2, 2), -- إنترنت - تجديد
(1, 3, 3), -- إنترنت - صيانة
(1, 4, 4), -- إنترنت - تغيير
(1, 5, 5), -- إنترنت - شكوى
(1, 6, 6); -- إنترنت - إلغاء

-- ربط عمليات المنتجات
INSERT INTO ServiceOperations (ServiceId, OperationTypeId, DisplayOrder) VALUES
(2, 1, 1), -- منتجات - شراء
(2, 4, 2), -- منتجات - تغيير (استبدال)
(2, 5, 3); -- منتجات - شكوى
```
