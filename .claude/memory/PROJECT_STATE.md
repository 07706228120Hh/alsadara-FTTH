# PROJECT_STATE — حالة مشروع Sadara Platform

ملف الحالة المركزي لنظام الوكلاء (Agents) في منصة الصدارة. تاريخ تأسيس نظام الوكلاء: 2026-06-25.

## الحالة الحالية
- **الإصدار المنشور (latest)**: **2.4.33+348** (2026-11-02، tag `v2.4.33` = Latest، فرع `feature/tasks-source-account-region` مدفوع حتى commit `baed849`؛ ويندوز 49.8MB + أندرويد arm64 55MB؛ التحديث التلقائي حيّ، manifest تُرجع 2.4.33). **⚠️ `main` لم يُزامَن بعد (FF مؤجَّل).** الباكند منشور ومتحقَّق (deploy `20261102_191535`، 65 DLL، health=200، logErrors=0). ميزتان: (1) ربط المهام بحساب مصدر (FTTH/ساس) + شريك رئيسي + منطقة + endpoint `source-pool` + فلتر خادمي + تحقّق شريك خادمي؛ (2) تحويل رصيد العمولة إلى المحفظة الرئيسية FTTH + صلاحية `transfer_commission`.
- **الهجرة المنشورة**: `AddServiceRequestSourceAccountRegion` طُبِّقت **أعمدةً فقط** (7 أعمدة nullable + `SourceAccountType` int default 0)، والفهرسان أُنشئا يدوياً `CREATE INDEX CONCURRENTLY` (`IX_ServiceRequests_CompanyId_SourceAccountType_SourceAccountId`, `IX_ServiceRequests_CompanyId_RegionRef`) ومُتحقَّقان. نسخة احتياطية `db_20261102_191535.sql.gz` + `dll_20261102_191535`.
- **rollback**: الإصدار `gh release edit v2.4.32 --latest`؛ الباكند `cp /root/backups/dll_20261102_191535/*.dll /var/www/sadara-api/ && systemctl restart sadara-api`؛ الفهرسان `DROP INDEX CONCURRENTLY IF EXISTS`.
- **إصدار سابق**: 2.4.32+347 (2026-11-01، `release/v2.4.32`، commits `8ec1623`+`2f6f63c`) — واجهة ميزات المخزون (تنبيهات + تصدير Excel + دُفعات/صلاحية StockBatch) + باكند منشور.
- **تاريخ آخر تحديث للذاكرة**: 2026-11-02.
- **⚠️ تفاوت مواءمة**: السرد التفصيلي الأحدث للإصدارات محفوظ في ذاكرة المستخدم `C:\Users\Msi-x88\.claude\projects\c--SadaraPlatform\memory\MEMORY.md` (v2.4.x كاملاً)؛ ملفات `.claude/memory/` بالمستودع كانت عالقة على v2.2.25+304 حتى هذا التحديث. **يجب مزامنة الموقعين** لتفادي تضارب الحقائق. الأقسام الأمنية أدناه تاريخية (2026-06) وقد تجاوزها الواقع (العزل المركزي صار حيّاً، إلخ).

### آخر ميزة مسجّلة — v2.4.33: ربط المهام بحساب مصدر ومنطقة + تحويل العمولة (2026-11-02، منشور)

- **الميزة 1 — ربط المهام**: وسم كل مهمة (ServiceRequest) بـ: حساب مصدر (FTTH/ساس من مجمّع الشركة) + شريك رئيسي (مكتب 11/مدينة الصدر) + منطقة. الوسم **يدوي** يختاره المدير/الليدر. الباكند: enum `TaskSourceAccountType` + 7 أعمدة nullable على ServiceRequest؛ endpoint `GET /api/tasks/source-pool` (عزل من التوكن، بلا أسرار، صلاحية `tasks/add` أو `tasks/edit`)؛ **فلتر خادمي + تحقّق شريك خادمياً**. الواجهة: منسدلات متتالية + شارات + فلتر (Flutter).
- **الميزة 2 — تحويل العمولة**: تحويل رصيد العمولة إلى المحفظة الرئيسية FTTH + صلاحية `transfer_commission` (تحصين idempotency + مضيف موحّد + TOCTOU). **⚠️ يعتمد على فرض خادم FTTH الخارجي للتفويض/المبلغ/idempotency — غير مؤكّد (انظر RISKS).**
- **الهجرة منشورة**: `AddServiceRequestSourceAccountRegion` طُبِّقت أعمدةً فقط (7 nullable + `SourceAccountType` int default 0)؛ الفهرسان `CREATE INDEX CONCURRENTLY` يدوياً ومُتحقَّقان.
- **الحالة**: مناطق الساس مربوطة بالكامل (SasRegion عبر source-pool)؛ FTTH حتى مستوى الشريك + منطقة نصّية. **المرحلة 2 مؤجَّلة** (زونات FTTH الحيّة، تعتمد على فرع `feature/ftth-credentials-unification` المحجوز لترخيص linked_accounts). مزامنة `main` FF مؤجَّلة.
- التفاصيل والقرارات الستة للمالك: `docs/design/TASKS_SOURCE_ACCOUNT_REGION.md`.

## ما هو المشروع
منصة FTTH/ISP + تجارة إلكترونية للمواطنين والشركات، Multi-tenant بحسب `CompanyId`.

## التقنيات المكتشفة
- **Backend**: .NET 9 — Clean Architecture (API / Application / Domain / Infrastructure).
- **Database**: PostgreSQL (`sadara_db`) على VPS رئيسي `72.61.183.61`. EF Core 9 + Npgsql، 84 migration.
- **Apps**: Flutter/Dart — `alsadara-ftth` (Windows + Android + iOS)، `CitizenWeb` (PWA — تعارض README Blazor vs Flutter)، `screen_test_app` (تجريبي).
- **Auth**: JWT Bearer + نظام صلاحيات مخصص (`ServiceAndPermission`, `RequirePermissionAttribute`, `IdentityServices`) + مصادقة مزدوجة (`dual_auth_service.dart`).
- **Push**: Firebase FCM.
- **CI/CD**: GitHub Actions يبني مثبّت Windows فقط؛ النشر backend يدوي عبر SCP.

## الملفات/المسارات المهمة
| المهمة | المسار |
|--------|--------|
| API + Controllers (57) | `src/Backend/API/Sadara.API` |
| Application layer | `src/Backend/Core/Sadara.Application` |
| Domain entities (37+) | `src/Backend/Core/Sadara.Domain` |
| Infrastructure + Migrations (84) | `src/Backend/Core/Sadara.Infrastructure` |
| تطبيق FTTH | `src/Apps/CompanyDesktop/alsadara-ftth` |
| تطبيق المواطن | `src/Apps/CitizenWeb` |

## آخر إجراء أمني (2026-06-26)
- **المرحلة 1 (مطبَّقة، بموافقة المستخدم)**: إزالة fallback لمفتاح ثابت (fail-closed) في `DatabaseAdminController.cs` (فلتر ApiKeyOrJwtAuth) و`SuperAdminController.cs:GenerateJwtToken`. `dotnet build` ✅ 0 errors. لم يُلمس n8n/DB/إنتاج، لا deploy/push.
- **مكتشَف حرج أثناء المراجعة**: نفس القيم المسرّبة مكتوبة في `appsettings.json` (Jwt:Secret سطر 20، InternalApiKey سطر 42) → السلسلة **لم تُغلق بعد**؛ المرحلة 1 ضرورية لكن غير كافية.
- **التالي (بانتظار موافقة)**: المرحلة 1c (إزالة القيم من appsettings + حقن من env/secret store + تدوير)، ثم المرحلة 2 (نفس النمط في `Program.cs:54,91` و`FtthAccountingController:2768` و9 controllers)، ثم المرحلتان 2-4 (AllowAnonymous، عزل المستأجر، CORS/rate-limit).

## المشاكل المعروفة (مختصر — التفاصيل في RISKS.md)
- **P0**: `.env` نظيف ومتجاهَل ✅. لكن أسرار مسرّبة في `appsettings.json` وملفات n8n متتبَّعة. `DatabaseAdminController` (مرحلة 1 مطبَّقة جزئياً) + `SuperAdminController` (9× AllowAnonymous + عزل مستأجر) ما زالا يحتاجان استكمال.
- **P1**: ملفات `tmp_*.json` بالجذر قد تحوي بيانات حقيقية. binaries ضخمة + node_modules ملتزمة بالريبو. اعتماد كامل على مزوّد FTTH خارجي خلف Cloudflare.
- **P2**: تغطية اختبارات شبه معدومة مقابل 57 controller. 84 migration بلا CD مؤتمت.
- **P3**: تكرار وثائق/أدلة بناء في الجذر.

## آخر التوصيات
1. تأمين الأسرار فوراً (التحقق من `.gitignore`، تدوير المفاتيح المسرّبة).
2. إزالة `tmp_*.json` و binaries و node_modules من الريبو.
3. تدقيق صلاحيات `DatabaseAdmin`/`SuperAdmin`.

## ما يجب فعله لاحقاً
- رفع تغطية الاختبارات.
- توثيق طبيعة `CitizenWeb` (Blazor أم Flutter — Unknown).
- تثبيت بوابة Cloudflare (whitelist IP بدل الجسر المؤقت).
- أتمتة نشر الـ backend (CD آمن).
