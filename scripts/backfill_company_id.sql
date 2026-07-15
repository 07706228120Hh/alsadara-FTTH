-- ═══════════════════════════════════════════════════════════════════════════
-- backfill_company_id.sql
-- تعبئة رجعية لعمود CompanyId قبل تفعيل عزل الشركات (Global Query Filter).
--
-- الغرض: ضمان ألّا يبقى أي سجل في جداول FTTH بـ CompanyId فارغ (NULL أو Guid صفري)،
--        وإلا سيختفي ذلك السجل عن جميع المستخدمين بمجرّد تفعيل الفلتر.
--
-- المنطق: بما أن النظام حالياً لشركة واحدة (رمز الصدارة)، تُسنَد كل الصفوف الناقصة
--         إلى الشركة الوحيدة الموجودة (أقدم شركة). آمن ومنطقي 100% لأن كل البيانات لها.
--
-- خصائص أمان:
--   • دفاعي وعام: يمرّ على كل جدول به عمود CompanyId من نوع uuid تلقائياً
--     (فيتجاوز جدول IptvSubscribers لأن عموده نصّي — لا يُلمَس).
--   • غير هدّام: UPDATE فقط للصفوف الناقصة؛ لا حذف، لا تعديل لصفوف مكتملة.
--   • idempotent: إعادة تشغيله لا تضرّ (لن يجد صفوفاً ناقصة في المرة الثانية).
--
-- ⚠️ التشغيل: يُنفَّذ على الإنتاج فقط بعد:
--     (1) نسخة احتياطية pg_dump متحقَّقة،
--     (2) تجربة على نسخة مستعادة (scratch DB)،
--     (3) موافقة صريحة.
--   الأمر:  sudo -u postgres psql -d sadara_db -f backfill_company_id.sql
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_company uuid;
    r          RECORD;
    v_count    bigint;
    v_total    bigint := 0;
BEGIN
    -- الشركة الوحيدة (رمز الصدارة) — أقدم شركة موجودة
    SELECT "Id" INTO v_company
    FROM "Companies"
    ORDER BY "CreatedAt" ASC
    LIMIT 1;

    IF v_company IS NULL THEN
        RAISE EXCEPTION 'لا توجد أي شركة في جدول Companies — أوقف الـ backfill.';
    END IF;

    RAISE NOTICE 'الشركة المستهدفة للتعبئة: %', v_company;

    -- المرور على كل جدول به عمود CompanyId من نوع uuid (يتجاوز الأعمدة النصّية مثل IptvSubscribers)
    FOR r IN
        SELECT table_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND column_name  = 'CompanyId'
          AND data_type    = 'uuid'
          -- استثناء: قوالب الصلاحيات null فيها = "عام" (متوافق مع TenantFilterExclusions في DbContext)
          AND table_name <> 'PermissionTemplates'
        ORDER BY table_name
    LOOP
        EXECUTE format(
            'UPDATE %I
               SET "CompanyId" = $1
             WHERE "CompanyId" IS NULL
                OR "CompanyId" = ''00000000-0000-0000-0000-000000000000''',
            r.table_name
        ) USING v_company;

        GET DIAGNOSTICS v_count = ROW_COUNT;
        v_total := v_total + v_count;
        IF v_count > 0 THEN
            RAISE NOTICE '  % : عُبّئ % صف/صفوف', r.table_name, v_count;
        END IF;
    END LOOP;

    RAISE NOTICE 'اكتمل الـ backfill. إجمالي الصفوف المعبّأة: %', v_total;
END $$;

-- ═══ تحقّق بعد التشغيل (للمراجعة اليدوية) ═══
-- يجب أن يُرجع صفراً لكل جدول بعد الـ backfill:
--   SELECT c.table_name,
--          (SELECT COUNT(*) FROM information_schema.columns) AS _
--   -- استعلام تحقّق يدوي لكل جدول حسب الحاجة.
