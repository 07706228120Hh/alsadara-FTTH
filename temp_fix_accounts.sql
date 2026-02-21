-- ═══════════════════════════════════════════════════════════
-- إصلاح أرصدة الحسابات + إنشاء الحسابات المفقودة
-- ═══════════════════════════════════════════════════════════

-- 1. إعادة حساب CurrentBalance لكل حساب من سطور القيود
-- أصول ومصروفات: Debit - Credit
-- إيرادات والتزامات وحقوق ملكية: Credit - Debit
UPDATE "Accounts" a SET "CurrentBalance" = COALESCE(
    (SELECT 
        CASE WHEN a."AccountType" IN (1, 5) 
            THEN SUM(jel."DebitAmount" - jel."CreditAmount")
            ELSE SUM(jel."CreditAmount" - jel."DebitAmount")
        END
    FROM "JournalEntryLines" jel
    JOIN "JournalEntries" je ON jel."JournalEntryId" = je."Id"
    WHERE jel."AccountId" = a."Id" 
      AND je."IsDeleted" = false 
      AND jel."IsDeleted" = false
    ), 0)
WHERE a."IsActive" = true AND a."IsDeleted" = false;

-- التحقق من النتائج
SELECT a."Code", a."Name", a."CurrentBalance"
FROM "Accounts" a
WHERE a."IsActive" = true AND a."IsDeleted" = false AND a."CurrentBalance" != 0
ORDER BY a."Code";

-- 2. إنشاء الحسابات المفقودة

-- جلب CompanyId و ParentAccountId لحساب 1100
-- حساب 1160: ذمم المشغلين (آجل) — تحت 1100
INSERT INTO "Accounts" ("Id", "Code", "Name", "NameEn", "AccountType", "ParentAccountId", "OpeningBalance", "CurrentBalance", "IsSystemAccount", "Level", "IsLeaf", "IsActive", "IsDeleted", "Description", "CompanyId", "CreatedAt")
SELECT 
    gen_random_uuid(),
    '1160',
    'ذمم المشغلين (آجل)',
    'Operator Credit Receivables',
    1, -- Assets
    "Id", -- parent = 1100
    0, 0, true, 2, true, true, false,
    'حسابات آجل المشغلين',
    "CompanyId",
    NOW()
FROM "Accounts" WHERE "Code" = '1100' AND "IsDeleted" = false
AND NOT EXISTS (SELECT 1 FROM "Accounts" WHERE "Code" = '1160' AND "IsDeleted" = false);

-- حساب 1170: الدفع الإلكتروني (ماستر) — تحت 1100
INSERT INTO "Accounts" ("Id", "Code", "Name", "NameEn", "AccountType", "ParentAccountId", "OpeningBalance", "CurrentBalance", "IsSystemAccount", "Level", "IsLeaf", "IsActive", "IsDeleted", "Description", "CompanyId", "CreatedAt")
SELECT 
    gen_random_uuid(),
    '1170',
    'الدفع الإلكتروني',
    'Electronic Payments',
    1, -- Assets
    "Id", -- parent = 1100
    0, 0, true, 2, true, true, false,
    'مدفوعات إلكترونية (ماستر)',
    "CompanyId",
    NOW()
FROM "Accounts" WHERE "Code" = '1100' AND "IsDeleted" = false
AND NOT EXISTS (SELECT 1 FROM "Accounts" WHERE "Code" = '1170' AND "IsDeleted" = false);

-- حساب 4110: إيرادات التجديد — تحت 4000
INSERT INTO "Accounts" ("Id", "Code", "Name", "NameEn", "AccountType", "ParentAccountId", "OpeningBalance", "CurrentBalance", "IsSystemAccount", "Level", "IsLeaf", "IsActive", "IsDeleted", "Description", "CompanyId", "CreatedAt")
SELECT 
    gen_random_uuid(),
    '4110',
    'إيرادات التجديد',
    'Renewal Revenue',
    4, -- Revenue
    "Id", -- parent = 4000
    0, 0, true, 2, true, true, false,
    'إيرادات تجديد الاشتراكات',
    "CompanyId",
    NOW()
FROM "Accounts" WHERE "Code" = '4000' AND "IsDeleted" = false
AND NOT EXISTS (SELECT 1 FROM "Accounts" WHERE "Code" = '4110' AND "IsDeleted" = false);

-- حساب 4120: إيرادات الشراء — تحت 4000
INSERT INTO "Accounts" ("Id", "Code", "Name", "NameEn", "AccountType", "ParentAccountId", "OpeningBalance", "CurrentBalance", "IsSystemAccount", "Level", "IsLeaf", "IsActive", "IsDeleted", "Description", "CompanyId", "CreatedAt")
SELECT 
    gen_random_uuid(),
    '4120',
    'إيرادات الشراء',
    'Purchase Revenue',
    4, -- Revenue
    "Id", -- parent = 4000
    0, 0, true, 2, true, true, false,
    'إيرادات شراء الاشتراكات الجديدة',
    "CompanyId",
    NOW()
FROM "Accounts" WHERE "Code" = '4000' AND "IsDeleted" = false
AND NOT EXISTS (SELECT 1 FROM "Accounts" WHERE "Code" = '4120' AND "IsDeleted" = false);

-- تحديث IsLeaf على الحسابات الأب التي أصبحت لديها فرعيات
UPDATE "Accounts" SET "IsLeaf" = false 
WHERE "Code" IN ('1100', '4000') AND "IsDeleted" = false AND "IsLeaf" = true;

-- 3. عرض جميع الحسابات بعد الإصلاح
SELECT a."Code", a."Name", a."CurrentBalance", a."AccountType", a."IsLeaf"
FROM "Accounts" a
WHERE a."IsActive" = true AND a."IsDeleted" = false
ORDER BY a."Code";
