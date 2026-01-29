-- ============================================
-- Sadara Platform - Database Initialization Script
-- Run this if migrations fail
-- ============================================

-- Create Database
CREATE DATABASE "SadaraDB";

\c "SadaraDB";

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- Companies Table
-- ============================================
CREATE TABLE IF NOT EXISTS "Companies" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "Name" VARCHAR(200) NOT NULL,
    "NameEn" VARCHAR(200),
    "Code" VARCHAR(50) UNIQUE NOT NULL,
    "Logo" VARCHAR(500),
    "Phone" VARCHAR(20),
    "Email" VARCHAR(100),
    "Address" TEXT,
    "City" VARCHAR(100),
    "IsActive" BOOLEAN DEFAULT TRUE,
    "SubscriptionExpiresAt" TIMESTAMP,
    "CreatedAt" TIMESTAMP DEFAULT NOW(),
    "UpdatedAt" TIMESTAMP,
    "IsLinkedToCitizenPortal" BOOLEAN DEFAULT FALSE,
    "LinkedToCitizenPortalAt" TIMESTAMP,
    "LinkedById" UUID
);

-- ============================================
-- Users Table
-- ============================================
CREATE TABLE IF NOT EXISTS "Users" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "FullName" VARCHAR(200) NOT NULL,
    "PhoneNumber" VARCHAR(20) UNIQUE NOT NULL,
    "Email" VARCHAR(100),
    "PasswordHash" VARCHAR(500),
    "Role" VARCHAR(50) NOT NULL DEFAULT 'Employee',
    "CompanyId" UUID REFERENCES "Companies"("Id"),
    "IsActive" BOOLEAN DEFAULT TRUE,
    "IsPhoneVerified" BOOLEAN DEFAULT FALSE,
    "CreatedAt" TIMESTAMP DEFAULT NOW(),
    "UpdatedAt" TIMESTAMP
);

-- ============================================
-- Permissions Table
-- ============================================
CREATE TABLE IF NOT EXISTS "Permissions" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "Code" VARCHAR(100) UNIQUE NOT NULL,
    "NameAr" VARCHAR(200) NOT NULL,
    "NameEn" VARCHAR(200),
    "Module" VARCHAR(50),
    "Action" VARCHAR(50),
    "CreatedAt" TIMESTAMP DEFAULT NOW()
);

-- ============================================
-- UserPermissions Table
-- ============================================
CREATE TABLE IF NOT EXISTS "UserPermissions" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "UserId" UUID REFERENCES "Users"("Id") ON DELETE CASCADE,
    "PermissionId" UUID REFERENCES "Permissions"("Id") ON DELETE CASCADE,
    "GrantedById" UUID REFERENCES "Users"("Id"),
    "GrantedAt" TIMESTAMP DEFAULT NOW(),
    UNIQUE("UserId", "PermissionId")
);

-- ============================================
-- Services Table
-- ============================================
CREATE TABLE IF NOT EXISTS "Services" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "Code" VARCHAR(50) UNIQUE NOT NULL,
    "NameAr" VARCHAR(200) NOT NULL,
    "NameEn" VARCHAR(200),
    "Icon" VARCHAR(100),
    "Color" VARCHAR(20),
    "DisplayOrder" INT DEFAULT 0,
    "IsActive" BOOLEAN DEFAULT TRUE,
    "CreatedAt" TIMESTAMP DEFAULT NOW()
);

-- ============================================
-- OperationTypes Table
-- ============================================
CREATE TABLE IF NOT EXISTS "OperationTypes" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "Code" VARCHAR(50) UNIQUE NOT NULL,
    "NameAr" VARCHAR(200) NOT NULL,
    "NameEn" VARCHAR(200),
    "Icon" VARCHAR(100),
    "RequiresApproval" BOOLEAN DEFAULT FALSE,
    "RequiresTechnician" BOOLEAN DEFAULT FALSE,
    "EstimatedDays" INT DEFAULT 1,
    "IsActive" BOOLEAN DEFAULT TRUE,
    "CreatedAt" TIMESTAMP DEFAULT NOW()
);

-- ============================================
-- ServiceOperations Table (Many-to-Many)
-- ============================================
CREATE TABLE IF NOT EXISTS "ServiceOperations" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "ServiceId" UUID REFERENCES "Services"("Id") ON DELETE CASCADE,
    "OperationTypeId" UUID REFERENCES "OperationTypes"("Id") ON DELETE CASCADE,
    "BasePrice" DECIMAL(18,2),
    "IsActive" BOOLEAN DEFAULT TRUE,
    "CustomSettings" JSONB,
    UNIQUE("ServiceId", "OperationTypeId")
);

-- ============================================
-- ServiceRequests Table
-- ============================================
CREATE TABLE IF NOT EXISTS "ServiceRequests" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "RequestNumber" VARCHAR(50) UNIQUE NOT NULL,
    "ServiceId" UUID REFERENCES "Services"("Id"),
    "OperationTypeId" UUID REFERENCES "OperationTypes"("Id"),
    "CustomerId" UUID REFERENCES "Users"("Id"),
    "CompanyId" UUID REFERENCES "Companies"("Id"),
    "Status" VARCHAR(50) DEFAULT 'Pending',
    "Priority" VARCHAR(20) DEFAULT 'Normal',
    "AssignedToId" UUID REFERENCES "Users"("Id"),
    "Details" JSONB,
    "Address" TEXT,
    "Phone" VARCHAR(20),
    "EstimatedCost" DECIMAL(18,2),
    "FinalCost" DECIMAL(18,2),
    "Notes" TEXT,
    "RequestedAt" TIMESTAMP DEFAULT NOW(),
    "AssignedAt" TIMESTAMP,
    "CompletedAt" TIMESTAMP,
    "CancelledAt" TIMESTAMP,
    "CreatedAt" TIMESTAMP DEFAULT NOW(),
    "UpdatedAt" TIMESTAMP
);

-- ============================================
-- Citizens Table
-- ============================================
CREATE TABLE IF NOT EXISTS "Citizens" (
    "Id" UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    "FullName" VARCHAR(200) NOT NULL,
    "PhoneNumber" VARCHAR(20) UNIQUE NOT NULL,
    "Email" VARCHAR(100),
    "City" VARCHAR(100),
    "Area" VARCHAR(100),
    "Address" TEXT,
    "CompanyId" UUID REFERENCES "Companies"("Id"),
    "IsActive" BOOLEAN DEFAULT TRUE,
    "CreatedAt" TIMESTAMP DEFAULT NOW(),
    "UpdatedAt" TIMESTAMP
);

-- ============================================
-- Indexes for Performance
-- ============================================
CREATE INDEX IF NOT EXISTS "IX_Users_CompanyId" ON "Users"("CompanyId");
CREATE INDEX IF NOT EXISTS "IX_Users_Role" ON "Users"("Role");
CREATE INDEX IF NOT EXISTS "IX_ServiceRequests_CompanyId" ON "ServiceRequests"("CompanyId");
CREATE INDEX IF NOT EXISTS "IX_ServiceRequests_Status" ON "ServiceRequests"("Status");
CREATE INDEX IF NOT EXISTS "IX_ServiceRequests_CustomerId" ON "ServiceRequests"("CustomerId");

-- ============================================
-- Seed Data
-- ============================================

-- Insert Permissions
INSERT INTO "Permissions" ("Code", "NameAr", "NameEn", "Module", "Action") VALUES
('dashboard.view', 'عرض لوحة التحكم', 'View Dashboard', 'Dashboard', 'View'),
('requests.view', 'عرض الطلبات', 'View Requests', 'Requests', 'View'),
('requests.create', 'إنشاء طلبات', 'Create Requests', 'Requests', 'Create'),
('requests.edit', 'تعديل الطلبات', 'Edit Requests', 'Requests', 'Edit'),
('requests.delete', 'حذف الطلبات', 'Delete Requests', 'Requests', 'Delete'),
('requests.assign', 'تعيين الطلبات', 'Assign Requests', 'Requests', 'Assign'),
('users.view', 'عرض المستخدمين', 'View Users', 'Users', 'View'),
('users.create', 'إنشاء مستخدمين', 'Create Users', 'Users', 'Create'),
('users.edit', 'تعديل مستخدمين', 'Edit Users', 'Users', 'Edit'),
('users.delete', 'حذف مستخدمين', 'Delete Users', 'Users', 'Delete'),
('reports.view', 'عرض التقارير', 'View Reports', 'Reports', 'View'),
('reports.export', 'تصدير التقارير', 'Export Reports', 'Reports', 'Export'),
('settings.view', 'عرض الإعدادات', 'View Settings', 'Settings', 'View'),
('settings.edit', 'تعديل الإعدادات', 'Edit Settings', 'Settings', 'Edit')
ON CONFLICT ("Code") DO NOTHING;

-- Insert Services
INSERT INTO "Services" ("Code", "NameAr", "NameEn", "Icon", "Color", "DisplayOrder") VALUES
('internet', 'الإنترنت', 'Internet', 'wifi', '#3B82F6', 1),
('products', 'المنتجات', 'Products', 'shopping-bag', '#10B981', 2),
('financial', 'الخدمات المالية', 'Financial', 'credit-card', '#8B5CF6', 3)
ON CONFLICT ("Code") DO NOTHING;

-- Insert Operation Types
INSERT INTO "OperationTypes" ("Code", "NameAr", "NameEn", "Icon", "RequiresApproval", "RequiresTechnician", "EstimatedDays") VALUES
('purchase', 'شراء جديد', 'New Purchase', 'plus', FALSE, FALSE, 3),
('renewal', 'تجديد', 'Renewal', 'refresh', FALSE, FALSE, 1),
('maintenance', 'صيانة', 'Maintenance', 'wrench', FALSE, TRUE, 2),
('change', 'تغيير', 'Change', 'swap', TRUE, FALSE, 2),
('complaint', 'شكوى', 'Complaint', 'alert', FALSE, FALSE, 5),
('cancellation', 'إلغاء', 'Cancellation', 'x', TRUE, FALSE, 1)
ON CONFLICT ("Code") DO NOTHING;

-- ============================================
-- Create Super Admin User (password: Admin@123)
-- ============================================
-- Note: Hash generated using standard ASP.NET Core Identity
INSERT INTO "Users" ("Id", "FullName", "PhoneNumber", "Email", "PasswordHash", "Role", "IsActive", "IsPhoneVerified")
VALUES (
    '11111111-1111-1111-1111-111111111111',
    'Super Admin',
    '+9647801234567',
    'admin@sadara.com',
    'AQAAAAIAAYagAAAAEOyX...PLACEHOLDER...', -- Replace with actual hash
    'SuperAdmin',
    TRUE,
    TRUE
)
ON CONFLICT ("PhoneNumber") DO NOTHING;

\echo 'Database initialization complete!'
\echo 'IMPORTANT: Update the Super Admin password hash before using in production!'
