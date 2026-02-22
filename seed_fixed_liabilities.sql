-- Add fixed expense liability accounts under 2000 (Liabilities)
-- Company: Sadara Company (3ebc4eb3-3511-487d-94d4-1812376491eb)
-- Parent 2000 ID: b75257fb-a86e-49a7-8c2f-34e67b3e55b8

DO $$
DECLARE
    v_company_id UUID := '3ebc4eb3-3511-487d-94d4-1812376491eb';
    v_parent_2000 UUID := 'b75257fb-a86e-49a7-8c2f-34e67b3e55b8';
    v_parent_2200 UUID;
    v_exists BOOLEAN;
BEGIN
    -- Check if 2200 already exists
    SELECT EXISTS(SELECT 1 FROM "Accounts" WHERE "Code" = '2200' AND "CompanyId" = v_company_id AND "IsDeleted" = false) INTO v_exists;
    
    IF v_exists THEN
        RAISE NOTICE 'Account 2200 already exists, skipping';
        SELECT "Id" INTO v_parent_2200 FROM "Accounts" WHERE "Code" = '2200' AND "CompanyId" = v_company_id AND "IsDeleted" = false;
    ELSE
        v_parent_2200 := gen_random_uuid();
        INSERT INTO "Accounts" ("Id", "Code", "Name", "NameEn", "AccountType", "ParentAccountId", "OpeningBalance", "CurrentBalance", "IsSystemAccount", "Level", "IsLeaf", "IsActive", "Description", "CompanyId", "CreatedAt", "IsDeleted")
        VALUES (v_parent_2200, '2200', 'مصاريف ثابتة مستحقة', 'Accrued Fixed Expenses', 2, v_parent_2000, 0, 0, true, 2, false, true, NULL, v_company_id, NOW(), false);
        RAISE NOTICE 'Created account 2200';
    END IF;

    -- 2210 - Rent Payable
    IF NOT EXISTS(SELECT 1 FROM "Accounts" WHERE "Code" = '2210' AND "CompanyId" = v_company_id AND "IsDeleted" = false) THEN
        INSERT INTO "Accounts" ("Id", "Code", "Name", "NameEn", "AccountType", "ParentAccountId", "OpeningBalance", "CurrentBalance", "IsSystemAccount", "Level", "IsLeaf", "IsActive", "Description", "CompanyId", "CreatedAt", "IsDeleted")
        VALUES (gen_random_uuid(), '2210', 'إيجار مستحق', 'Rent Payable', 2, v_parent_2200, 0, 0, true, 3, true, true, NULL, v_company_id, NOW(), false);
        RAISE NOTICE 'Created account 2210';
    END IF;

    -- 2220 - Generator Cost Payable
    IF NOT EXISTS(SELECT 1 FROM "Accounts" WHERE "Code" = '2220' AND "CompanyId" = v_company_id AND "IsDeleted" = false) THEN
        INSERT INTO "Accounts" ("Id", "Code", "Name", "NameEn", "AccountType", "ParentAccountId", "OpeningBalance", "CurrentBalance", "IsSystemAccount", "Level", "IsLeaf", "IsActive", "Description", "CompanyId", "CreatedAt", "IsDeleted")
        VALUES (gen_random_uuid(), '2220', 'تكلفة مولد مستحقة', 'Generator Cost Payable', 2, v_parent_2200, 0, 0, true, 3, true, true, NULL, v_company_id, NOW(), false);
        RAISE NOTICE 'Created account 2220';
    END IF;

    -- 2230 - Internet Payable
    IF NOT EXISTS(SELECT 1 FROM "Accounts" WHERE "Code" = '2230' AND "CompanyId" = v_company_id AND "IsDeleted" = false) THEN
        INSERT INTO "Accounts" ("Id", "Code", "Name", "NameEn", "AccountType", "ParentAccountId", "OpeningBalance", "CurrentBalance", "IsSystemAccount", "Level", "IsLeaf", "IsActive", "Description", "CompanyId", "CreatedAt", "IsDeleted")
        VALUES (gen_random_uuid(), '2230', 'إنترنت مستحق', 'Internet Payable', 2, v_parent_2200, 0, 0, true, 3, true, true, NULL, v_company_id, NOW(), false);
        RAISE NOTICE 'Created account 2230';
    END IF;

    -- 2240 - Electricity Payable
    IF NOT EXISTS(SELECT 1 FROM "Accounts" WHERE "Code" = '2240' AND "CompanyId" = v_company_id AND "IsDeleted" = false) THEN
        INSERT INTO "Accounts" ("Id", "Code", "Name", "NameEn", "AccountType", "ParentAccountId", "OpeningBalance", "CurrentBalance", "IsSystemAccount", "Level", "IsLeaf", "IsActive", "Description", "CompanyId", "CreatedAt", "IsDeleted")
        VALUES (gen_random_uuid(), '2240', 'كهرباء مستحقة', 'Electricity Payable', 2, v_parent_2200, 0, 0, true, 3, true, true, NULL, v_company_id, NOW(), false);
        RAISE NOTICE 'Created account 2240';
    END IF;

    -- 2250 - Water Payable
    IF NOT EXISTS(SELECT 1 FROM "Accounts" WHERE "Code" = '2250' AND "CompanyId" = v_company_id AND "IsDeleted" = false) THEN
        INSERT INTO "Accounts" ("Id", "Code", "Name", "NameEn", "AccountType", "ParentAccountId", "OpeningBalance", "CurrentBalance", "IsSystemAccount", "Level", "IsLeaf", "IsActive", "Description", "CompanyId", "CreatedAt", "IsDeleted")
        VALUES (gen_random_uuid(), '2250', 'ماء مستحق', 'Water Payable', 2, v_parent_2200, 0, 0, true, 3, true, true, NULL, v_company_id, NOW(), false);
        RAISE NOTICE 'Created account 2250';
    END IF;

    -- 2260 - Other Fixed Expenses Payable
    IF NOT EXISTS(SELECT 1 FROM "Accounts" WHERE "Code" = '2260' AND "CompanyId" = v_company_id AND "IsDeleted" = false) THEN
        INSERT INTO "Accounts" ("Id", "Code", "Name", "NameEn", "AccountType", "ParentAccountId", "OpeningBalance", "CurrentBalance", "IsSystemAccount", "Level", "IsLeaf", "IsActive", "Description", "CompanyId", "CreatedAt", "IsDeleted")
        VALUES (gen_random_uuid(), '2260', 'مصاريف ثابتة أخرى مستحقة', 'Other Fixed Expenses Payable', 2, v_parent_2200, 0, 0, true, 3, true, true, NULL, v_company_id, NOW(), false);
        RAISE NOTICE 'Created account 2260';
    END IF;

    RAISE NOTICE 'Done - fixed expense liability accounts seeded';
END $$;
