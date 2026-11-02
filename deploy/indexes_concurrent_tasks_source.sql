-- فهارس وسم المهمة بحساب مصدر ومنطقة (ميزة tasks-source-account-region)
-- تُنشأ خارج معاملة EF عبر CREATE INDEX CONCURRENTLY لتفادي قفل الكتابة
-- على جدول ServiceRequests الحيّ الكبير على الإنتاج.
--
-- ملاحظات تشغيل حرجة:
--   * CREATE INDEX CONCURRENTLY لا يعمل داخل كتلة معاملة — شغّل كل أمر
--     على حدة (psql بلا -1/--single-transaction، وبلا BEGIN/COMMIT).
--   * شغّله بعد تطبيق هجرة 20261102132426_AddServiceRequestSourceAccountRegion
--     (التي تضيف الأعمدة فقط).
--   * IF NOT EXISTS تجعله idempotent. إن فشل CONCURRENTLY في منتصفه يترك
--     فهرساً INVALID — احذفه بـ: DROP INDEX CONCURRENTLY IF EXISTS "<name>"; ثم أعد التشغيل.
--   * لا موافقة؟ لا تشغّل على الإنتاج. نسخة احتياطية أولاً.

CREATE INDEX CONCURRENTLY IF NOT EXISTS "IX_ServiceRequests_CompanyId_SourceAccountType_SourceAccountId"
  ON "ServiceRequests" ("CompanyId", "SourceAccountType", "SourceAccountId");

CREATE INDEX CONCURRENTLY IF NOT EXISTS "IX_ServiceRequests_CompanyId_RegionRef"
  ON "ServiceRequests" ("CompanyId", "RegionRef");
