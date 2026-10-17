# المرحلة 1 / التيار F — ضمانات المخطّط ضد الترحيل المزدوج

> الحالة: **مُعدّة محلياً فقط — لم تُطبَّق على الإنتاج**. كل خطوة إنتاج (سكربت تنظيف، هجرة، نشر) تحتاج موافقة المالك الصريحة.
> أرقام البيانات من المرآة `sadara_db_mirror` (آخر مزامنة 2026-08-19 — قديمة؛ أعد تشغيل `sql/00_preflight_readonly.sql` على الإنتاج قبل القرار).

## 1. ما الذي أُضيف

| # | الهجرة | الفهرس | الشرط (partial) |
|---|---|---|---|
| A | `20261017204954_AddUniqueSubscriptionLogFtthTransaction` | `UX_SubscriptionLogs_Company_FtthTx` على `SubscriptionLogs("CompanyId","FtthTransactionId") NULLS NOT DISTINCT` | `"FtthTransactionId" IS NOT NULL AND NOT "IsDeleted"` |
| B | `20261017205105_AddUniqueTechnicianChargePerServiceRequest` | `UX_TechnicianTransactions_ServiceRequest_Category_Charge` على `TechnicianTransactions("ServiceRequestId","Category")` | `"ServiceRequestId" IS NOT NULL AND NOT "IsDeleted" AND "Type" = 0` (`TechnicianTransactionType.Charge = 0`، مخزّن integer) |

- التكوين في `SadaraDbContext.OnModelCreating` (كتلة «Phase 1 / Stream F»). أُبقي فهرس الـ FK الكامل `IX_TechnicianTransactions_ServiceRequestId` صراحةً، وإلا كان EF سيحذفه ظنّاً أن الفهرس الجزئي يغطيه (لا يغطي الدفعات/المحذوف).
- `NULLS NOT DISTINCT` (PostgreSQL ≥ 15؛ الإنتاج 16.x، المرآة 16.13، docker-compose 15): صفّ بـ `CompanyId = NULL` (فجوة ختم قديمة) لا يتجاوز الحماية.
- B يطابق قاعدة التطبيق الموجودة في `ServiceRequestsController.RegisterFeeOnUser` («أجر حيّ واحد لكل مهمة+فئة»). شحنات الاشتراك (`Category=4`) بلا `ServiceRequestId` فلا يشملها B — ملف H أدناه.

### سلوك الهجرة (Up)
كتلة `DO` واحدة لكل هجرة:
1. إن كان الفهرس موجوداً **وصالحاً** (بُني يدوياً مسبقاً) ⇒ تتخطّى بإشعار. إن كان موجوداً **غير صالح** (بناء CONCURRENTLY فاشل) ⇒ تفشل برسالة وتلميح `DROP INDEX CONCURRENTLY`.
2. `lock_timeout = 5s` (محلي للمعاملة، ويُعاد للقيمة السابقة بعد البناء).
3. `LOCK TABLE ... IN SHARE MODE` ثم فحص التكرار تحت القفل نفسه.
4. وجود تكرار ⇒ `RAISE EXCEPTION` واضحة مثل:
   `UX_TechnicianTransactions_ServiceRequest_Category_Charge: 1 duplicate live task-fee charge groups (2 rows). Migration aborted, nothing applied.` مع HINT يشير لسكربت التنظيف.
5. `CREATE UNIQUE INDEX`.

Down: `DROP INDEX IF EXISTS` فقط (لا مساس بالبيانات).

## 2. تحليل الأثر (Impact analysis)
- **البيانات**: لا تغيير في أي صف بالهجرتين. التنظيف في سكربتات منفصلة بموافقة.
- **الكتابة**: أي إدراج/تعديل يُنتج تكراراً حيّاً يفشل بـ `PostgresException` `SqlState = 23505` و`ConstraintName` = اسم الفهرس. المتحكّمات الحالية لا تعالجه ⇒ الطلب المكرّر (double-submit/سباق) يعود 500 بدل ترحيل مزدوج. التيارات الموازية تعالجه (409 أو نجاح idempotent). **ملاحظات لها**:
  - لا تُرجع `PostgresException.Detail` للعميل (يحوي `CompanyId` وقيم المفتاح).
  - «إبطال ثم إعادة شحن» للمفتاح نفسه في `SaveChanges` واحد قد يفشل: EF لا يعرف أن `IsDeleted` في شرط الفهرس فقد يرسل INSERT قبل UPDATE، والفحص فوري (غير مؤجّل). نفّذ الإبطال في `SaveChanges` أول ثم الشحن في ثانٍ داخل معاملة واحدة.
  - إكمال المهمة يحفظ الأجر مع تغيير الحالة؛ فشل 23505 هناك يُفشل الحفظ كله — عالِجه كـ «مسجّل مسبقاً».
- **القراءة**: لا أثر. الفهرس A يسرّع فحوص idempotency بـ `(CompanyId, FtthTransactionId)`.
- **الحجم**: A يغطي ~955 صفاً حيّاً (من 21,877)، B ~2.9 ألف صف ⇒ كلفة كتابة/تخزين مهملة.
- **الاختبارات**: مجموعات الاختبار تبني المخطّط بـ `EnsureCreated` من النموذج ⇒ تحصل على الفهرسين تلقائياً؛ 322 اختباراً سابقاً ناجحة معها.

## 3. تحليل الأقفال ولماذا ليس `CONCURRENTLY`
- `deploy/deploy-backend.sh` يولّد `dotnet ef migrations script --idempotent` ويمرّره لـ `psql -v ON_ERROR_STOP=1`. سكربت EF 9 لـ Npgsql: **معاملة واحدة** (`START TRANSACTION … COMMIT`) و**كل جملة داخل `DO $EF$`**. `CREATE INDEX CONCURRENTLY` ممنوع داخل معاملة وداخل دالة/`DO` ⇒ مستحيل في هذا المسار (و`suppressTransaction` لا يزيل غلاف `DO`). كذلك `Program.cs` يستدعي `MigrateAsync()` عند كل إقلاع (EF 9 = معاملة واحدة لكل الهجرات المعلّقة).
- البناء العادي يأخذ قفل **SHARE**: القراءة مسموحة، INSERT/UPDATE/DELETE على الجدول تنتظر. الجداول صغيرة (المرآة: `SubscriptionLogs` 22,167 صفاً/14MB، `TechnicianTransactions` 16,951/4.7MB) ⇒ الفحص+البناء بالمللي ثانية.
- القفل يبقى حتى `COMMIT` السكربت كله. الهجرتان آخر هجرات المستودع ⇒ بعدهما إدراجات السجل فقط. **لكن** السكربت يطبّق كل الهجرات المعلّقة؛ تاريخ المرآة يتوقّف عند `20260715020420` (قديم) — تحقّق من البند 8 في `00_preflight` على الإنتاج.
- `lock_timeout 5s`: إن كانت معاملة طويلة تمسك الجدول، نفشل خلال 5 ثوانٍ بدل الاصطفاف (الاصطفاف خلف معاملة طويلة يحجب حتى القراءات الجديدة خلفنا). الفشل ⇒ تراجع المعاملة كاملة ⇒ `set -e` يوقف النشر **قبل** نسخ الـ DLLs. أعد المحاولة.
- **خيار صفر-حجب (اختياري)**: بعد التنظيف، يبني المالك الفهرسين يدوياً خارج أي معاملة، ثم ينشر عادياً (الهجرة تكتشف الفهرس الصالح وتسجّل التاريخ فقط):
  ```sql
  SET lock_timeout = '5s';
  CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS "UX_SubscriptionLogs_Company_FtthTx"
    ON "SubscriptionLogs" ("CompanyId", "FtthTransactionId") NULLS NOT DISTINCT
    WHERE "FtthTransactionId" IS NOT NULL AND NOT "IsDeleted";
  CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS "UX_TechnicianTransactions_ServiceRequest_Category_Charge"
    ON "TechnicianTransactions" ("ServiceRequestId", "Category")
    WHERE "ServiceRequestId" IS NOT NULL AND NOT "IsDeleted" AND "Type" = 0;
  ```
  فشل CONCURRENTLY (تكرار) يترك فهرساً INVALID ⇒ `DROP INDEX CONCURRENTLY IF EXISTS ...` ثم أعد. لا ضرورة له بهذه الأحجام.

## 4. سكربتات ما قبل الهجرة (`docs/tasks-finance-fix/sql/`) — لم يُنفَّذ أيٌّ منها على الإنتاج
| الملف | النوع | المحتوى |
|---|---|---|
| `00_preflight_readonly.sql` | قراءة فقط | الإصدار، وجود الفهارس، مانع A (المرآة: 0)، مانع B (المرآة: مجموعة واحدة)، ملخص H، المعاملات الطويلة، الأحجام، ذيل تاريخ الهجرات |
| `01_resolve_duplicate_task_fee.sql` | كتابة — **شرط لـ B** | معاينة ← معاملة: جدول تدقيق `finance_fix_audit.affected_rows` (نسخة jsonb كاملة لكل صف) ← soft-delete للأحدث في كل مجموعة مع ملاحظة عكس ← تحقّق العدد = `expected_rows` وإلا تراجع. ينتهي بـ `ROLLBACK` افتراضياً (تشغيل جاف). قسم UNDO في آخره |
| `02_report_duplicate_subscription_charges_readonly.sql` | قراءة فقط | تقرير H: 148 سجل اشتراك، 395 صف شحن، **247 زائداً = 9,691,000 د.ع** (246 قيدها محذوف فعلياً، 1 قيدها ملغى+محذوف)؛ لكل مجموعة صف واحد قيده Posted حيّ (KEEP). تفصيل لكل صف + أثر لكل فني |
| `03_DRAFT_cleanup_duplicate_subscription_charges.sql` | **مسودة** | محظور حتى قرار «المصدر الواحد لرصيد الفني» (المرحلة 4). ثلاث أقفال أمان: إعداد موافقة صريح، `ROLLBACK` افتراضي، `expected_rows`. يلمس فقط الصفوف المعكوس قيدها في مجموعات فيها قيد Posted واحد؛ المجموعات الغامضة للمراجعة اليدوية. لا يعدّل `Users.TechTotalCharges` (إعادة احتساب الكاش خطوة المرحلة 4) |
| `99_rollback_indexes.sql` | طوارئ | `DROP INDEX CONCURRENTLY IF EXISTS` للفهرسين مع إبقاء صفوف التاريخ |

مجموعة B الوحيدة في المرآة: المهمة `26072713341408` (`d2f24743-…-934d6eed9006`)، صيانة 2×1,000، الصفّان 29314 (يبقى) و29315 (يُبطَل)، بفارق 3ms وبنفس `BalanceAfter = 57,000` (سباق نقر مزدوج) وبلا قيد محاسبي. لا يُعدَّل رصيد الفني المخزّن لأن السباق على لقطة المستخدم نفسها يعني غالباً أن الكاش احتسب الأجر مرة واحدة.

## 5. ترتيب النشر (scripts → migrations → DLLs)
1. موافقة المالك على: 01 (تنفيذ فعلي)، الهجرتين، النشر.
2. `00_preflight_readonly.sql` على الإنتاج (جلسة read-only) ومراجعة البنود 3/4/6/8.
3. نسخة احتياطية (`pg_dump sadara_db | gzip` إلى `/root/backups/`).
4. `01` تشغيلاً جافاً ← مراجعة المعاينة ← ضبط `expected_rows` ← `COMMIT` (فقط إن كان البند 4 > 0).
5. `00` مجدداً: البندان 3 و4 = 0.
6. (اختياري) البناء `CONCURRENTLY` اليدوي — §3.
7. `bash deploy/deploy-backend.sh` — يطبّق الهجرات ثم ينسخ الـ DLLs. يُفضَّل أن يضمّ الإصدار نفسه معالجة 23505 من التيارات الأخرى (بين الهجرة ونسخ الـ DLLs: المكرّر يعود 500 بدل ترحيل مزدوج — مقبول).
8. تحقّق: `00` البند 2 يُظهر الفهرسين `indisvalid = t`؛ سجل `sadara-api` بلا `Migration note:` ولا 500.
9. `02` يُسلَّم للمالك/المحاسب؛ `03` يبقى مسودة.

## 6. خطة التراجع (Rollback)
- **المفضّلة (EF)**: `dotnet ef migrations script 20261017205105_AddUniqueTechnicianChargePerServiceRequest 20261012203130_AddPropertyQrTokens --idempotent --project src/Backend/Core/Sadara.Infrastructure --startup-project src/Backend/API/Sadara.API -o rollback.sql` ثم `psql -v ON_ERROR_STOP=1 -f rollback.sql` ⇒ `DROP INDEX IF EXISTS` ×2 + حذف صفّي التاريخ. **تحذير**: `MigrateAsync` عند الإقلاع سيعيد بناءهما ما دامت الـ DLLs الجديدة منشورة ⇒ أرجع الـ DLLs أيضاً (`/root/backups/dll_<TS>`) أو استخدم الطارئ.
- **طارئ بلا حجب**: `sql/99_rollback_indexes.sql` (`DROP INDEX CONCURRENTLY`، يبقي التاريخ فلا يُعاد البناء). لإعادة التفعيل لاحقاً: نفّذ `UpSql` من ملف الهجرة يدوياً (idempotent).
- التطبيق يعمل بلا الفهارس (السلوك السابق)؛ معالجة 23505 تصبح غير مستخدمة فقط.
- **التنظيف**: قسم UNDO في 01/03 يعيد الصفوف من `finance_fix_audit.affected_rows`. إن كان B مطبّقاً فسيرفض الفهرس إعادة التكرار (صحيح) ⇒ تراجع عن B أولاً.
- **الملاذ الأخير**: `/root/backups/db_<TS>.sql.gz` من خطوة 3 في `deploy-backend.sh`.

## 7. خطة الاختبار
آلي — `tests/Sadara.Integration.Tests/DoublePostingIndexTests.cs` (حاوية Postgres 16 خاصة، 17 اختباراً):
- دلالات القيد: تكرار نفس الشركة+العملية مرفوض؛ `CompanyId = NULL` لا يتجاوز؛ شركة أخرى/عملية أخرى/`NULL` FtthTransactionId مقبولة؛ المحذوف لا يتعارض، واستعادة محذوف فوق حيّ مرفوضة؛ أجر مكرّر لنفس المهمة+الفئة مرفوض؛ فئة أخرى/دفعة/تعديل/بلا مهمة مقبولة؛ إعادة الشحن بعد الإبطال مقبولة؛ فهرس FK باقٍ.
- مسار النشر الحقيقي: سكربت EF idempotent عبر `psql -v ON_ERROR_STOP=1` داخل الحاوية: بيانات نظيفة ⇒ الفهرسان + صفّا التاريخ، والإعادة no-op؛ تكرار A أو B ⇒ خروج ≠ 0 برسالة واضحة و**لا شيء مطبّق** (حتى A حين يفشل B)؛ فهرس مبني CONCURRENTLY مسبقاً ⇒ يُحترم؛ سكربت التراجع ⇒ حذف الفهرسين والتاريخ.
- مسار الإقلاع `MigrateAsync`: نظيف ⇒ يطبّق؛ تكرار ⇒ `PostgresException` بالرسالة ولا شيء مطبّق.
- السكربتات: 01 الجاف لا يغيّر شيئاً، 01 المُلتزم يبطل الأحدث ويدوّن التدقيق ثم تنجح الهجرة، وإعادته تفشل بصوت؛ 02 يعمل read-only؛ 03 يرفض بلا موافقة، ونسخته الموافَق عليها تمسّ الصفوف المعكوسة فقط؛ 99 يحذف الفهرسين ويبقي التاريخ.

يدوي قبل الإنتاج: استعادة آخر نسخة إنتاج في قاعدة مؤقتة **غير إنتاجية** ← 00 ← 01 (جاف ثم التزام) ← سكربت النشر ← قياس زمن القفل ← تشغيل الـ API عليها والتحقّق من التفعيل/إكمال مهمة/نقر مزدوج (409 لا 500 بعد دمج التيارات الأخرى). المرآة تكفي لـ SQL بـ psql لكنها read-only ولا تكفي لمسار EF.

## 8. اعتبارات أمنية
- A مقيّد بالشركة: نفس `FtthTransactionId` في شركتين مسموح (عزل المستأجر)، و`NULLS NOT DISTINCT` يسدّ ثغرة `CompanyId = NULL`.
- رسالة 23505 تحوي قيم المفتاح (`CompanyId`) ⇒ لا تُعرض للعميل؛ رسالة عربية عامة فقط.
- `finance_fix_audit` مخطّط جديد ينشئه مستخدم postgres؛ لا صلاحيات لـ PUBLIC افتراضياً (PG ≥ 15). يحوي نسخاً من صفوف مالية ⇒ لا تمنح مستخدم التطبيق صلاحية عليه، واحذفه بعد إغلاق المرحلة بموافقة.
- لا تعطيل RLS/قيود، لا حذف صفوف (soft-delete فقط وبموافقة)، لا أسرار في السكربتات.

## 9. ما يحتاج موافقة المالك
1. تشغيل `01` فعلياً (`COMMIT`) على الإنتاج — يبطل صفاً واحداً (حسب المرآة) من أجور المهام.
2. تطبيق الهجرتين A وB على الإنتاج (عبر `deploy-backend.sh`) — وتوقيت النشر.
3. (اختياري) البناء `CONCURRENTLY` اليدوي المسبق.
4. لاحقاً، بعد قرار المصدر الواحد ومراجعة المحاسب: `03` (247 صفاً / 9.69 مليون حسب المرآة).
