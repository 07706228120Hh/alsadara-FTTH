-- ════════════════════════════════════════════════════════════════════════════
-- خطة migration لـ idempotency التجديد (#2) — مُجهّزة، غير مُطبّقة.
-- الهدف: فهرس فريد يمنع سجلّي SubscriptionLog بنفس FtthTransactionId لنفس الشركة.
--
-- ⚠️ لا تُطبَّق إلا بموافقة صريحة + خطة rollback + مراجعة database-postgres-agent.
-- ⚠️ الفحص على مستوى التطبيق (FtthAccountingController.LogWithAccounting) يحمي من الآن؛
--    هذا الفهرس هو الحماية النهائية ضد سباق التزامن.
-- ════════════════════════════════════════════════════════════════════════════

-- الخطوة 0 (تشخيص): كم سجلاً مكرّراً موجود حالياً؟ (يجب أن يكون 0 قبل إنشاء الفهرس)
SELECT "FtthTransactionId", "CompanyId", COUNT(*) AS dup_count
FROM "SubscriptionLogs"
WHERE "IsDeleted" = false AND "FtthTransactionId" IS NOT NULL AND "FtthTransactionId" <> ''
GROUP BY "FtthTransactionId", "CompanyId"
HAVING COUNT(*) > 1
ORDER BY dup_count DESC;

-- الخطوة 1 (إزالة التكرار — بموافقة فقط): احتفظ بالأقدم (أو ذي القيد المحاسبي) واحذف البقية حذفاً ناعماً.
-- راجَع يدوياً قبل التنفيذ — قد يوجد قيد محاسبي مرتبط بالمكرّر يجب تسويته أولاً.
-- UPDATE "SubscriptionLogs" s SET "IsDeleted" = true, "DeletedAt" = now()
-- FROM (
--   SELECT "Id", row_number() OVER (
--            PARTITION BY "FtthTransactionId", "CompanyId"
--            ORDER BY ("JournalEntryId" IS NOT NULL) DESC, "CreatedAt" ASC
--          ) AS rn
--   FROM "SubscriptionLogs"
--   WHERE "IsDeleted" = false AND "FtthTransactionId" IS NOT NULL AND "FtthTransactionId" <> ''
-- ) d
-- WHERE s."Id" = d."Id" AND d.rn > 1;

-- الخطوة 2 (الفهرس الفريد الجزئي — بعد أن تصبح الخطوة 0 ترجع صفر صفوف):
-- CONCURRENTLY لتجنّب قفل الجدول في الإنتاج (خارج معاملة).
-- CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS "IX_SubscriptionLogs_FtthTxn_Company_Unique"
--   ON "SubscriptionLogs" ("FtthTransactionId", "CompanyId")
--   WHERE "IsDeleted" = false AND "FtthTransactionId" IS NOT NULL AND "FtthTransactionId" <> '';

-- ملاحظة EF: المكافئ عبر EF Core = HasIndex(x => new { x.FtthTransactionId, x.CompanyId })
--   .IsUnique().HasFilter("\"IsDeleted\" = false AND \"FtthTransactionId\" IS NOT NULL") ثم
--   dotnet ef migrations add AddSubscriptionLogFtthTxnUniqueIndex — بعد إزالة التكرار.
-- rollback: DROP INDEX CONCURRENTLY IF EXISTS "IX_SubscriptionLogs_FtthTxn_Company_Unique";
