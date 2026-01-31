-- Migration: AddCitizenPortalLinkToCompany
-- تطبيق Migration على قاعدة البيانات

-- التحقق من وجود الأعمدة أولاً
DO $$
BEGIN
    -- إضافة عمود IsLinkedToCitizenPortal
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'Companies' AND column_name = 'IsLinkedToCitizenPortal'
    ) THEN
        ALTER TABLE "Companies" 
        ADD COLUMN "IsLinkedToCitizenPortal" boolean NOT NULL DEFAULT false;
        RAISE NOTICE 'تم إضافة عمود IsLinkedToCitizenPortal';
    ELSE
        RAISE NOTICE 'عمود IsLinkedToCitizenPortal موجود بالفعل';
    END IF;

    -- إضافة عمود LinkedById
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'Companies' AND column_name = 'LinkedById'
    ) THEN
        ALTER TABLE "Companies" 
        ADD COLUMN "LinkedById" uuid NULL;
        RAISE NOTICE 'تم إضافة عمود LinkedById';
    ELSE
        RAISE NOTICE 'عمود LinkedById موجود بالفعل';
    END IF;

    -- إضافة عمود LinkedToCitizenPortalAt
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'Companies' AND column_name = 'LinkedToCitizenPortalAt'
    ) THEN
        ALTER TABLE "Companies" 
        ADD COLUMN "LinkedToCitizenPortalAt" timestamp with time zone NULL;
        RAISE NOTICE 'تم إضافة عمود LinkedToCitizenPortalAt';
    ELSE
        RAISE NOTICE 'عمود LinkedToCitizenPortalAt موجود بالفعل';
    END IF;

    -- تحديث سجل Migrations
    IF NOT EXISTS (
        SELECT 1 FROM "__EFMigrationsHistory" 
        WHERE "MigrationId" = '20260128032556_AddCitizenPortalLinkToCompany'
    ) THEN
        INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
        VALUES ('20260128032556_AddCitizenPortalLinkToCompany', '9.0.0');
        RAISE NOTICE 'تم تسجيل Migration في التاريخ';
    ELSE
        RAISE NOTICE 'Migration مسجل بالفعل في التاريخ';
    END IF;
END $$;

-- عرض النتيجة
SELECT 
    column_name, 
    data_type, 
    is_nullable,
    column_default
FROM information_schema.columns 
WHERE table_name = 'Companies' 
    AND column_name IN ('IsLinkedToCitizenPortal', 'LinkedById', 'LinkedToCitizenPortalAt')
ORDER BY column_name;
