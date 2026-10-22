-- ════════════════════════════════════════════════════════════════════════════
-- تسوية أرصدة الفنيين (#12) — تحليل للقراءة فقط (SELECT، لا UPDATE/DELETE).
-- يقارن لكل فني: رصيد الدفتر المحاسبي (حسابات 1140x الفرعية) مقابل الرصيد
-- المخزّن (Users.TechTotalCharges/TechTotalPayments)، ويُظهر الفرق ومصدره.
--
-- التشغيل (على النسخة المرآة read-only `sadara_db_mirror` أو نسخة احتياطية — لا الإنتاج):
--   psql -d sadara_db_mirror -f docs/reports/technician-balance-reconciliation.sql
--
-- ⚠️ لا يغيّر أي بيانات. قرار التوحيد مؤجَّل لقرار المالك + مراجعة محاسب (القرار الحالي: لا تلمسه).
-- ════════════════════════════════════════════════════════════════════════════

-- 1) تفصيل لكل فني: الدفتر مقابل المخزّن + الفرق
WITH ledger AS (
    -- رصيد حساب ذمة الفني الفرعي من قيود الأستاذ (مدين - دائن)؛ حساب الفني يُربط بـ Description = technicianId
    SELECT
        a."Description"::uuid              AS technician_id,
        SUM(l."DebitAmount" - l."CreditAmount") AS ledger_balance
    FROM "Accounts" a
    JOIN "JournalEntryLines" l ON l."AccountId" = a."Id"
    JOIN "JournalEntries" j     ON j."Id" = l."JournalEntryId" AND j."Status" = 1  -- Posted
    WHERE a."Code" LIKE '1140%' AND a."IsLeaf" = true
      AND a."Description" ~ '^[0-9a-fA-F-]{36}$'
    GROUP BY a."Description"
),
stored AS (
    SELECT
        u."Id"                                              AS technician_id,
        u."FullName",
        u."CompanyId",
        COALESCE(u."TechTotalCharges",0)                    AS tech_charges,
        COALESCE(u."TechTotalPayments",0)                   AS tech_payments,
        COALESCE(u."TechTotalCharges",0) - COALESCE(u."TechTotalPayments",0) AS stored_balance
    FROM "Users" u
    WHERE COALESCE(u."TechTotalCharges",0) <> 0 OR COALESCE(u."TechTotalPayments",0) <> 0
),
txsum AS (
    -- إعادة الحساب من جدول المعاملات نفسه (لمعرفة أي المصدرين أقرب للمعاملات)
    SELECT
        t."TechnicianId"                                     AS technician_id,
        SUM(CASE WHEN t."Type" = 0 THEN t."Amount" ELSE 0 END) AS tx_charges,   -- Charge
        SUM(CASE WHEN t."Type" = 1 THEN t."Amount" ELSE 0 END) AS tx_payments   -- Payment
    FROM "TechnicianTransactions" t
    WHERE t."IsDeleted" = false
    GROUP BY t."TechnicianId"
)
SELECT
    s."FullName",
    s."CompanyId",
    s.stored_balance                                  AS "مخزّن (Charges-Payments)",
    COALESCE(g.ledger_balance,0)                       AS "دفتر 1140x",
    (s.tech_charges - s.tech_payments) -
        (COALESCE(x.tx_charges,0) - COALESCE(x.tx_payments,0)) AS "مخزّن - معاملات",
    COALESCE(g.ledger_balance,0) - s.stored_balance    AS "دفتر - مخزّن (الفرق)"
FROM stored s
LEFT JOIN ledger g ON g.technician_id = s.technician_id
LEFT JOIN txsum  x ON x.technician_id = s.technician_id
ORDER BY ABS(COALESCE(g.ledger_balance,0) - s.stored_balance) DESC;

-- 2) الإجماليات الكلية (المقارنة الكبرى 77.1M مقابل 39.2M)
SELECT
    (SELECT COALESCE(SUM(ledger_balance),0) FROM (
        SELECT SUM(l."DebitAmount" - l."CreditAmount") AS ledger_balance
        FROM "Accounts" a
        JOIN "JournalEntryLines" l ON l."AccountId" = a."Id"
        JOIN "JournalEntries" j ON j."Id" = l."JournalEntryId" AND j."Status" = 1
        WHERE a."Code" LIKE '1140%' AND a."IsLeaf" = true
        GROUP BY a."Id"
    ) q)                                                          AS "إجمالي الدفتر 1140x",
    (SELECT COALESCE(SUM("TechTotalCharges" - "TechTotalPayments"),0) FROM "Users") AS "إجمالي المخزّن";
