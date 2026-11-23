# تقرير الجاهزية النهائي — منع الهجرات التلقائية في الإنتاج + نشر Code-Only — 2026-11-23

> **بيئة التطوير فقط. لم يُلمَس الإنتاج** (لا اتصال، لا نشر، لا إعادة تشغيل). هذا تقرير جاهزية يتوقّف عند بوابة الموافقة النهائية للمالك قبل أي نشر.

## 1) الخلفية والسبب الجذري
الموافقة على نشر `e3a6ff6` بطريقة Code-Only اشترطت **عدم تنفيذ أي Migration**. فحص `Program.cs` كشف أن التطبيق نفسه يستدعي `Database.MigrateAsync()` **عند كل إقلاع في الإنتاج** داخل `try/catch` يبتلع الخطأ. ⇒ أي `systemctl restart` كان سيُطلق محاولة هجرة (تمسّ `__EFMigrationsHistory`)، بصرف النظر عن تجاوز خطوة الهجرات في سكربت النشر. هذه بوابة سلامة أوقفت النشر (الشرطان 2 و18 من موافقة المالك)، فاعتمد المالك **الخيار (ب): إصلاح `Program.cs` محلياً** لمنع الاستدعاء نهائياً في الإنتاج.

## 2) الإصلاح (محصور بالنطاق — منع الهجرات التلقائية فقط)
صنف نقي قابل للاختبار `src/Backend/API/Sadara.API/Startup/StartupDatabasePolicy.cs`:
- **`Decide(isInMemory, isDevelopment)`**: `InMemory ⇒ EnsureCreated` · `Development ⇒ Migrate` · **`Production/Staging/غير محدّد ⇒ None`** (ASP.NET Core يعتبر البيئة غير المضبوطة = Production ⇒ `IsDevelopment=false` ⇒ `None`).
- **`ApplyAsync(database, strategy)`**: المكان **الوحيد** المسموح له بمسّ المخطط عند الإقلاع؛ فرع `None` لا يفعل شيئاً.

`Program.cs` (كتلة الإقلاع): تستدعي `Decide` ثم `ApplyAsync`، وتُسجّل سطر Serilog للـ`None`. **لم تعد تبتلع نتيجة هجرة، بل تمنع الاستدعاء نفسه** في الإنتاج.

**SeedData بلا تغيير** (الشرط 6) — متحقَّق أنه idempotent وآمن (البند 4 أدناه).

## 3) فحص كل مسارات الإقلاع (الشرط 5)
بحث شامل في `src/**/*.cs` عن `Migrate/MigrateAsync/EnsureCreated/GetPendingMigrations/__EFMigrationsHistory`:
- الاستدعاء الوحيد للهجرة عند الإقلاع كان في `Program.cs` (عولِج).
- الـ`HostedService`ـان (`FtthSyncBackgroundService`, `SasSyncBackgroundService`) **لا** يستدعيان أي هجرة.
- استدعاءات `ExecuteSql*` الأخرى ليست عند الإقلاع ولا تغيّر المخطط: `pg_advisory_lock` (أقفال)، DELETE في `DatabaseAdminController` (نقطة إدارية صريحة محمية)، `ExecuteUpdate` في `SessionController` (وقت تشغيل).
- **لا يوجد سكربت نشر/هوك يستدعي هجرة** عند التشغيل بعد هذا الإصلاح.

## 4) مراجعة SeedData على الإنتاج (الشروط 6–8)
`SeedData.SeedAsync` يُنفَّذ عند كل إقلاع (بلا تغيير). كل دوال البذر محروسة بـ`if (await …AnyAsync()) return` وتضيف صفوفاً جديدة **فقط حين تكون المجموعة فارغة**، ولا تُحدِّث أو تحذف أي صف قائم:
PermissionGroups · Permissions · PermissionTemplates · Services · OperationTypes (+ ServiceOperations) · InternetPlans · **SuperAdmin** (`AnyAsync(u => u.Role == SuperAdmin)` ⇒ يرجع فوراً على الإنتاج ⇒ **لا إنشاء SuperAdmin، لا تطبيق `Admin@123!`، لا منح صلاحيات**).
على قاعدة مأهولة: كل الحرّاس يقصرون ⇒ لا تغييرات متعقَّبة ⇒ `SaveChangesAsync` النهائي بلا أثر. **لا كتابة فعلية على الإنتاج عند الإقلاع.**

## 5) الاختبارات (الشروط 11–12) — 333 ناجح / 0 فاشل / 0 متخطّى
اختبارات الإقلاع العشرة (10/10):
- **`StartupDatabasePolicyTests`** (نقية، بلا Docker، لا تُتخطّى أبداً): `Production ⇒ None` · `Development ⇒ Migrate` · `InMemory ⇒ EnsureCreated` (كل التوليفات). **حارس الانحدار الحقيقي للثابت الحرج.**
- **`StartupMigrationSafetyTests`** (Postgres حقيقي، Testcontainers):
  - `ProductionStrategy_None_AppliedForReal_DoesNotTouch_EFMigrationsHistory`: يزرع جدول history، **يستدعي فعلاً** `ApplyAsync(None)`، ويؤكّد عدم تغيّر أي صف. (لو رُجِّع None إلى Migrate ⇒ الاختبار يفشل.)
  - `DevelopmentStrategy_Migrate_AppliedForReal_PopulatesSchemaAndHistory_OnFreshDatabase`: ينشئ قاعدة منفصلة، **يستدعي فعلاً** `ApplyAsync(Migrate)`، ويؤكّد امتلاء `__EFMigrationsHistory`، ثم يحذف القاعدة.
  - `SeedData_IsNoOp_OnPopulatedDatabase`: تشغيل `SeedAsync` مرتين ⇒ ثبات العدّ وثبات hash الأدمن (بمعاملة تُلغى، بلا تلويث).

## 6) المراجعة المستقلة (الشرط 10) — APPROVE نهائي
`code-reviewer` مستقل، جولتان:
1. **الجولة 1:** APPROVE للكود الإنتاجي (صحيح/آمن/محصور) + كشف **P2** (الاختبار الأول كان «إخضراراً زائفاً» لا يستدعي مسار الإقلاع).
2. **الجولة 2 (بعد معالجة P2 باستخراج `ApplyAsync` واستدعائه فعلياً):** **APPROVE نهائي** — P2 مُغلقة، الاستخراج نظيف بلا أثر جانبي، الاختبارات تحمي فعلاً من انحدار يُعيد `MigrateAsync`.
- **ملاحظتا P3 (خارج النطاق، لا تحجبان):** (أ) الحارس مبني على **اسم البيئة** لا علَم إنتاج صريح ⇒ **يجب تثبيت `ASPNETCORE_ENVIRONMENT=Production` في وحدة systemd** على الخادم. (ب) حُرّاس SeedData «الكل أو لا شيء» لا تَبذُر صفوف صلاحيات **جديدة** على قواعد مأهولة (دَيْن سابق).

## 7) الإصدار النهائي والفروقات
- **SHA النهائي للنشر: `a76eb1c1f1a92fc5f2253e77aca19c99bafa956b`** (`a76eb1c`، فرع `main`، محلي، **غير مدفوع/غير منشور**).
- يضمّ **كل `e3a6ff6`** (تحصين المحاسبة/الأمن) + إصلاح الإقلاع هذا. `e3a6ff6` سلف مؤكَّد لـ`a76eb1c`.
- **صفر Migration في كامل الدلتا `805e7e2..a76eb1c`** (مؤكَّد). ملفات إصلاح الإقلاع = 4:
  `Program.cs` (معدّل) · `Startup/StartupDatabasePolicy.cs` (جديد) · `StartupDatabasePolicyTests.cs` (جديد) · `StartupMigrationSafetyTests.cs` (جديد). (308+ / 13−).

## 8) خطة النشر Code-Only (بلا أي Migration) — للتنفيذ بعد الموافقة النهائية فقط
بعد هذا الإصلاح، النشر خالٍ من الهجرات **من طرفين**: لا السكربت ولا التطبيق سيهاجر.
1. **بناء متكامل:** `dotnet publish` للإصدار `a76eb1c` (Release)، لا نسخ DLLs انتقائي.
2. **نسخ احتياطي + تحقّق استعادة** في بيئة معزولة قبل أي لمس للإنتاج (DB `pg_dump` + كل DLLs الحالية + الإعدادات/الأسرار/`keys` DataProtection).
3. **مسار Code-Only منفصل** (لا `deploy-backend.sh` بصيغته الحالية لأنه يولّد خطوة هجرات): نشر مخرجات `publish` مع **الحفاظ على** `appsettings.Production.json`/`.env`/الأسرار/مجلد `keys`/`ASPNETCORE_ENVIRONMENT=Production`.
4. **يُفضّل مجلد إصدار جديد + تحويل قابل للتراجع** بدل الاستبدال المباشر أثناء التشغيل.
5. **تحقّق صارم بعد التشغيل:** `active` + `/health=200` + صفر أخطاء تحميل/`MissingMethodException`/`BadImageFormat` + **التأكد من سطر Serilog «Startup DB migration skipped … not Development»** (دليل حيّ أن الإنتاج لم يهاجر).
6. **بعد النشر:** `integrity-check` ومقارنة بخط الأساس (28 غير متوازن / −364,000 / 4 ازدواج 5110 / 3192 سطر 5110) — لا زيادة؛ التحقّق من الدخول/المزامنة/تجديد وتغيير FTTH/صلاحيات العرض والكتابة؛ مراقبة ≥60 دقيقة.
7. **التراجع:** استعادة DLLs/مجلد الإصدار السابق + `systemctl restart` (كود فقط ⇒ بلا هجرة عكسية). لا استعادة قاعدة إنتاج ولا `Authz:FailOpen=true` دون موافقة مستقلة.

## 9) القيود المُلتزَمة والمعلّق
- **مُلتزَم:** لا Migration على الإنتاج · لا تعديل `__EFMigrationsHistory` · لا تعديل بيانات/صلاحيات · لا تصحيح القيود الـ28 · لا `recalculate`/تسوية · لا توسيع نطاق.
- **معلّق (يحتاج موافقة مستقلة):** C3–C6 · تصحيح الـ28 التاريخي · انحراف المعروض/الأستاذ +95.4M · أي تسوية مالية · تثبيت `ASPNETCORE_ENVIRONMENT=Production` في systemd (توصية بنية تحتية، خارج المستودع).

## 10) الحالة
**الإصلاح مطوّر ومُختبَر ومُراجَع (APPROVE نهائي) في بيئة التطوير. متوقّف عند بوابة الموافقة النهائية — لا نشر ولا إعادة تشغيل للإنتاج دون موافقة جديدة صريحة من المالك.**
