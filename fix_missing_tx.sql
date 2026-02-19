-- تسجيل المعاملة المالية للطلب المكتمل الذي لم يُسجل بسبب النشر المتأخر
-- الطلب: SR-20260219-8A61AD | المبلغ: 35000 | الفني: علي علي

-- 1. إدراج معاملة الخصم
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
    COALESCE((SELECT "CompanyId" FROM "ServiceRequests" WHERE "Id" = '4b2d101b-454e-467a-a13c-93ebb45d66a2'), '00000000-0000-0000-0000-000000000000'),
    NOW(),
    false,
    u."Id"
FROM "Users" u
WHERE u."FullName" = 'علي علي' AND u."IsDeleted" = false
LIMIT 1;

-- 2. تحديث رصيد الفني
UPDATE "Users" 
SET "TechTotalCharges" = 35000,
    "TechNetBalance" = "TechTotalPayments" - 35000,
    "UpdatedAt" = NOW()
WHERE "FullName" = 'علي علي' AND "IsDeleted" = false;

-- 3. التحقق
SELECT "FullName", "TechTotalCharges", "TechTotalPayments", "TechNetBalance" FROM "Users" WHERE "FullName" = 'علي علي' AND "IsDeleted" = false;
SELECT "Id", "Amount", "Type", "Category", "Description", "BalanceAfter" FROM "TechnicianTransactions" WHERE "IsDeleted" = false;
