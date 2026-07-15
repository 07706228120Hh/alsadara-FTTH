-- ═══════════════════════════════════════════════════════════════════════════
-- verify_tenant_backfill.sql
-- تحقّق ما بعد الـ backfill — البوابة الحاسمة قبل تفعيل الفلتر/النشر.
--
-- المنطق: بمجرّد تفعيل الفلتر المركزي، أي صف بـ CompanyId فارغ (NULL أو صفري)
--         في جدول مستأجَر سيختفي عن مستخدمي الشركة. فبعد الـ backfill يجب ألّا
--         يبقى أي صف كهذا. هذا السكربت يمرّ على كل جدول uuid CompanyId
--         (عدا PermissionTemplates — null فيها = "عام") ويفشل بصوت عالٍ إن وجد صفاً ناقصاً.
--
-- يُشغّل على قاعدة scratch بعد apply_tenant_columns.sql ثم backfill_company_id.sql.
--   sudo -u postgres psql -d <scratch_db> -f verify_tenant_backfill.sql
-- النجاح = "لا يوجد أي صف بلا شركة" ⇒ آمن. الفشل = RAISE EXCEPTION يوقف كل شيء.
-- ═══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
    r        RECORD;
    v_nulls  bigint;
    v_total  bigint;
    v_bad    int := 0;
BEGIN
    FOR r IN
        SELECT table_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND column_name  = 'CompanyId'
          AND data_type    = 'uuid'
          AND table_name  <> 'PermissionTemplates'
        ORDER BY table_name
    LOOP
        EXECUTE format(
            'SELECT COUNT(*) FILTER (
                       WHERE "CompanyId" IS NULL
                          OR "CompanyId" = ''00000000-0000-0000-0000-000000000000''),
                    COUNT(*)
               FROM %I', r.table_name)
          INTO v_nulls, v_total;

        IF v_nulls > 0 THEN
            v_bad := v_bad + 1;
            RAISE WARNING '  ❌ % : % صف بلا شركة من أصل % — سيختفي عند التفعيل', r.table_name, v_nulls, v_total;
        ELSE
            RAISE NOTICE  '  ✅ % : % صف، كلها معزولة', r.table_name, v_total;
        END IF;
    END LOOP;

    IF v_bad > 0 THEN
        RAISE EXCEPTION 'فشل التحقّق: % جدول به صفوف بلا شركة. لا تفعّل الفلتر ولا تنشر قبل معالجتها.', v_bad;
    END IF;
    RAISE NOTICE '════════════════════════════════════════════════════';
    RAISE NOTICE '✅ نجح التحقّق: لا يوجد أي صف بلا شركة. آمن لتفعيل الفلتر.';
END $$;
