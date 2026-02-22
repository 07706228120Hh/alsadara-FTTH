-- ═══════════════════════════════════════════════════════════════
-- هجرة صلاحيات V3 — إضافة المفاتيح الفرعية الهرمية
-- تاريخ: 2025
-- الوصف: يضيف مفاتيح فرعية (hr.*, attendance.*, accounting.*, tasks.*)
--         إلى JSON الصلاحيات V2 الموجود في جدول Users
-- القاعدة: المفتاح الفرعي يرث قيمة الأب
-- ═══════════════════════════════════════════════════════════════

-- ════════════════════════════════
-- 1. دالة مساعدة لبناء كائن إجراءات V2 من قيمة view
-- ════════════════════════════════
CREATE OR REPLACE FUNCTION build_v2_actions(has_view boolean)
RETURNS jsonb AS $$
BEGIN
  RETURN jsonb_build_object(
    'view', COALESCE(has_view, false),
    'add', COALESCE(has_view, false),
    'edit', COALESCE(has_view, false),
    'delete', COALESCE(has_view, false),
    'export', false,
    'import', false,
    'print', false,
    'send', false
  );
END;
$$ LANGUAGE plpgsql;

-- ════════════════════════════════
-- 2. دالة لتوريث صلاحيات الأب إلى الأبناء في النظام الأول
-- ════════════════════════════════
CREATE OR REPLACE FUNCTION migrate_first_system_v2_subkeys(user_id uuid)
RETURNS void AS $$
DECLARE
  v2_json jsonb;
  v1_json jsonb;
  parent_val jsonb;
  parent_view boolean;
BEGIN
  -- قراءة V2 الحالي
  SELECT 
    CASE WHEN "FirstSystemPermissionsV2" IS NOT NULL AND "FirstSystemPermissionsV2" != '' AND "FirstSystemPermissionsV2" != 'null'
         THEN "FirstSystemPermissionsV2"::jsonb ELSE '{}'::jsonb END,
    CASE WHEN "FirstSystemPermissions" IS NOT NULL AND "FirstSystemPermissions" != '' AND "FirstSystemPermissions" != 'null'
         THEN "FirstSystemPermissions"::jsonb ELSE '{}'::jsonb END
  INTO v2_json, v1_json
  FROM "Users"
  WHERE "Id" = user_id;

  -- ═══ مفاتيح جديدة مستقلة (من V1 القديم) ═══
  
  -- hr (من attendance القديم أو users)
  IF NOT v2_json ? 'hr' THEN
    IF v2_json ? 'attendance' THEN
      v2_json := v2_json || jsonb_build_object('hr', v2_json->'attendance');
    ELSIF v1_json ? 'attendance' THEN
      v2_json := v2_json || jsonb_build_object('hr', build_v2_actions((v1_json->>'attendance')::boolean));
    ELSE
      v2_json := v2_json || jsonb_build_object('hr', build_v2_actions(false));
    END IF;
  END IF;

  -- follow_up (من tasks القديم)
  IF NOT v2_json ? 'follow_up' THEN
    IF v2_json ? 'tasks' THEN
      v2_json := v2_json || jsonb_build_object('follow_up', v2_json->'tasks');
    ELSIF v1_json ? 'tasks' THEN
      v2_json := v2_json || jsonb_build_object('follow_up', build_v2_actions((v1_json->>'tasks')::boolean));
    ELSE
      v2_json := v2_json || jsonb_build_object('follow_up', build_v2_actions(false));
    END IF;
  END IF;

  -- audit_dashboard (من tasks القديم)
  IF NOT v2_json ? 'audit_dashboard' THEN
    IF v2_json ? 'tasks' THEN
      v2_json := v2_json || jsonb_build_object('audit_dashboard', v2_json->'tasks');
    ELSIF v1_json ? 'tasks' THEN
      v2_json := v2_json || jsonb_build_object('audit_dashboard', build_v2_actions((v1_json->>'tasks')::boolean));
    ELSE
      v2_json := v2_json || jsonb_build_object('audit_dashboard', build_v2_actions(false));
    END IF;
  END IF;

  -- my_dashboard (من tasks القديم)
  IF NOT v2_json ? 'my_dashboard' THEN
    IF v2_json ? 'tasks' THEN
      v2_json := v2_json || jsonb_build_object('my_dashboard', v2_json->'tasks');
    ELSIF v1_json ? 'tasks' THEN
      v2_json := v2_json || jsonb_build_object('my_dashboard', build_v2_actions((v1_json->>'tasks')::boolean));
    ELSE
      v2_json := v2_json || jsonb_build_object('my_dashboard', build_v2_actions(false));
    END IF;
  END IF;

  -- ═══ مفاتيح فرعية attendance ═══
  IF v2_json ? 'attendance' THEN
    parent_val := v2_json->'attendance';
    parent_view := COALESCE((parent_val->>'view')::boolean, false);
    
    IF NOT v2_json ? 'attendance.dashboard' THEN
      v2_json := v2_json || jsonb_build_object('attendance.dashboard', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'attendance.checkin' THEN
      v2_json := v2_json || jsonb_build_object('attendance.checkin', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'attendance.records' THEN
      v2_json := v2_json || jsonb_build_object('attendance.records', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'attendance.reports' THEN
      v2_json := v2_json || jsonb_build_object('attendance.reports', build_v2_actions(parent_view));
    END IF;
  END IF;

  -- ═══ مفاتيح فرعية hr ═══
  IF v2_json ? 'hr' THEN
    parent_val := v2_json->'hr';
    parent_view := COALESCE((parent_val->>'view')::boolean, false);
    
    IF NOT v2_json ? 'hr.employees' THEN
      v2_json := v2_json || jsonb_build_object('hr.employees', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'hr.salaries' THEN
      v2_json := v2_json || jsonb_build_object('hr.salaries', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'hr.leaves' THEN
      v2_json := v2_json || jsonb_build_object('hr.leaves', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'hr.deductions' THEN
      v2_json := v2_json || jsonb_build_object('hr.deductions', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'hr.advances' THEN
      v2_json := v2_json || jsonb_build_object('hr.advances', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'hr.schedules' THEN
      v2_json := v2_json || jsonb_build_object('hr.schedules', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'hr.departments' THEN
      v2_json := v2_json || jsonb_build_object('hr.departments', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'hr.permissions' THEN
      v2_json := v2_json || jsonb_build_object('hr.permissions', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'hr.reports' THEN
      v2_json := v2_json || jsonb_build_object('hr.reports', build_v2_actions(parent_view));
    END IF;
  END IF;

  -- ═══ مفاتيح فرعية accounting ═══
  IF v2_json ? 'accounting' THEN
    parent_val := v2_json->'accounting';
    parent_view := COALESCE((parent_val->>'view')::boolean, false);
    
    IF NOT v2_json ? 'accounting.dashboard' THEN
      v2_json := v2_json || jsonb_build_object('accounting.dashboard', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.chart' THEN
      v2_json := v2_json || jsonb_build_object('accounting.chart', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.journals' THEN
      v2_json := v2_json || jsonb_build_object('accounting.journals', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.compound_journals' THEN
      v2_json := v2_json || jsonb_build_object('accounting.compound_journals', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.expenses' THEN
      v2_json := v2_json || jsonb_build_object('accounting.expenses', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.fixed_expenses' THEN
      v2_json := v2_json || jsonb_build_object('accounting.fixed_expenses', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.revenue' THEN
      v2_json := v2_json || jsonb_build_object('accounting.revenue', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.salaries' THEN
      v2_json := v2_json || jsonb_build_object('accounting.salaries', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.cashbox' THEN
      v2_json := v2_json || jsonb_build_object('accounting.cashbox', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.collections' THEN
      v2_json := v2_json || jsonb_build_object('accounting.collections', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.client_accounts' THEN
      v2_json := v2_json || jsonb_build_object('accounting.client_accounts', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.agent_transactions' THEN
      v2_json := v2_json || jsonb_build_object('accounting.agent_transactions', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.agent_commission' THEN
      v2_json := v2_json || jsonb_build_object('accounting.agent_commission', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.ftth_operators' THEN
      v2_json := v2_json || jsonb_build_object('accounting.ftth_operators', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.withdrawals' THEN
      v2_json := v2_json || jsonb_build_object('accounting.withdrawals', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.statistics' THEN
      v2_json := v2_json || jsonb_build_object('accounting.statistics', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.funds_overview' THEN
      v2_json := v2_json || jsonb_build_object('accounting.funds_overview', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'accounting.settings' THEN
      v2_json := v2_json || jsonb_build_object('accounting.settings', build_v2_actions(parent_view));
    END IF;
  END IF;

  -- ═══ مفاتيح فرعية tasks ═══
  IF v2_json ? 'tasks' THEN
    parent_val := v2_json->'tasks';
    parent_view := COALESCE((parent_val->>'view')::boolean, false);
    
    IF NOT v2_json ? 'tasks.assign' THEN
      v2_json := v2_json || jsonb_build_object('tasks.assign', build_v2_actions(parent_view));
    END IF;
    IF NOT v2_json ? 'tasks.audit' THEN
      v2_json := v2_json || jsonb_build_object('tasks.audit', build_v2_actions(parent_view));
    END IF;
  END IF;

  -- حفظ النتيجة
  UPDATE "Users"
  SET "FirstSystemPermissionsV2" = v2_json::text,
      "UpdatedAt" = NOW()
  WHERE "Id" = user_id;

END;
$$ LANGUAGE plpgsql;

-- ════════════════════════════════
-- 3. تنفيذ الهجرة على جميع المستخدمين النشطين
-- ════════════════════════════════
DO $$
DECLARE
  rec RECORD;
  total_count int := 0;
  updated_count int := 0;
BEGIN
  RAISE NOTICE '═══ بدء هجرة صلاحيات V3 ═══';
  
  -- عد المستخدمين
  SELECT COUNT(*) INTO total_count
  FROM "Users"
  WHERE "IsDeleted" = false;
  
  RAISE NOTICE 'عدد المستخدمين النشطين: %', total_count;

  FOR rec IN
    SELECT "Id", "FullName"
    FROM "Users"
    WHERE "IsDeleted" = false
  LOOP
    PERFORM migrate_first_system_v2_subkeys(rec."Id");
    updated_count := updated_count + 1;
    
    IF updated_count % 50 = 0 THEN
      RAISE NOTICE 'تم تحديث % من % مستخدم', updated_count, total_count;
    END IF;
  END LOOP;

  RAISE NOTICE '═══ اكتملت الهجرة: % مستخدم تم تحديثه ═══', updated_count;
END;
$$;

-- ════════════════════════════════
-- 4. فحص النتائج
-- ════════════════════════════════
SELECT 
  "Id",
  "FullName",
  LENGTH("FirstSystemPermissionsV2") as v2_length,
  CASE 
    WHEN "FirstSystemPermissionsV2" IS NOT NULL 
    THEN jsonb_object_keys("FirstSystemPermissionsV2"::jsonb)
    ELSE 'NULL'
  END as sample_key
FROM "Users"
WHERE "IsDeleted" = false
  AND "FirstSystemPermissionsV2" IS NOT NULL
  AND "FirstSystemPermissionsV2" != ''
  AND "FirstSystemPermissionsV2" != 'null'
LIMIT 5;

-- ════════════════════════════════
-- 5. تنظيف الدوال المؤقتة
-- ════════════════════════════════
DROP FUNCTION IF EXISTS migrate_first_system_v2_subkeys(uuid);
DROP FUNCTION IF EXISTS build_v2_actions(boolean);

-- ═══ انتهت الهجرة ═══
