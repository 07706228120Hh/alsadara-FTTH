-- العثور على شركة الفني أو أي شركة موجودة
-- ثم إدراج المعاملة

-- أولاً: إعادة الرصيد لأن UPDATE نجح لكن INSERT فشل
UPDATE "Users" 
SET "TechTotalCharges" = 0,
    "TechNetBalance" = 0,
    "UpdatedAt" = NOW()
WHERE "FullName" = 'علي علي' AND "IsDeleted" = false;

-- الحصول على CompanyId من جدول الشركات
INSERT INTO "TechnicianTransactions" (
    "TechnicianId", "Type", "Category", "Amount", "BalanceAfter", 
    "Description", "ReferenceNumber", "ServiceRequestId", 
    "CompanyId", "CreatedAt", "IsDeleted", "CreatedById"
)
SELECT 
    u."Id",
    0,  -- Charge
    4,  -- Subscription
    35000,
    -35000,
    'شراء اشتراك: SR-20260219-8A61AD',
    'SR-20260219-8A61AD',
    '4b2d101b-454e-467a-a13c-93ebb45d66a2',
    (SELECT "Id" FROM "Companies" WHERE "IsDeleted" = false LIMIT 1),
    NOW(),
    false,
    u."Id"
FROM "Users" u
WHERE u."FullName" = 'علي علي' AND u."IsDeleted" = false
LIMIT 1;

-- تحديث رصيد الفني
UPDATE "Users" 
SET "TechTotalCharges" = 35000,
    "TechNetBalance" = "TechTotalPayments" - 35000,
    "UpdatedAt" = NOW()
WHERE "FullName" = 'علي علي' AND "IsDeleted" = false;

-- التحقق
SELECT "FullName", "TechTotalCharges", "TechTotalPayments", "TechNetBalance" FROM "Users" WHERE "FullName" = 'علي علي' AND "IsDeleted" = false;
SELECT "Id", "Amount", "Type", "Category", "Description", "BalanceAfter" FROM "TechnicianTransactions" WHERE "IsDeleted" = false;
