# PROJECT_STATE — حالة مشروع Sadara Platform

ملف الحالة المركزي لنظام الوكلاء (Agents) في منصة الصدارة. تاريخ تأسيس نظام الوكلاء: 2026-06-25.

## الحالة الحالية
- **الإصدار المنشور (latest)**: **2.4.32+347** (2026-11-01، فرع `release/v2.4.32`، commits `8ec1623`+`2f6f63c`؛ `main` مُزامَن FF). واجهة ميزات المخزون (تنبيهات + تصدير Excel + دُفعات/صلاحية StockBatch) + باكند منشور ومتحقَّق.
- **فرع العمل الحالي**: `feature/tasks-source-account-region` — المرحلة 1 من «ربط المهام بحساب مصدر ومنطقة» (commit `70ca50a`، غير مدفوع/غير منشور).
- **تاريخ آخر تحديث للذاكرة**: 2026-11-02.
- **⚠️ تفاوت مواءمة**: السرد التفصيلي الأحدث للإصدارات محفوظ في ذاكرة المستخدم `C:\Users\Msi-x88\.claude\projects\c--SadaraPlatform\memory\MEMORY.md` (v2.4.x كاملاً)؛ ملفات `.claude/memory/` بالمستودع كانت عالقة على v2.2.25+304 حتى هذا التحديث. **يجب مزامنة الموقعين** لتفادي تضارب الحقائق. الأقسام الأمنية أدناه تاريخية (2026-06) وقد تجاوزها الواقع (العزل المركزي صار حيّاً، إلخ).

### آخر ميزة مسجّلة — المرحلة 1: ربط المهام بحساب مصدر ومنطقة (2026-11-02، غير منشور)

- وسم كل مهمة (ServiceRequest) بـ: حساب مصدر (FTTH/ساس من مجمّع الشركة) + شريك رئيسي (مكتب 11/مدينة الصدر) + منطقة. الوسم **يدوي** يختاره المدير/الليدر.
- الباكند: enum `TaskSourceAccountType` + 7 أعمدة nullable على ServiceRequest؛ endpoint `GET /api/tasks/source-pool` (عزل من التوكن، بلا أسرار، صلاحية `tasks/add` أو `tasks/edit`)؛ تحقّق ملكية + لقطات مختومة خادمياً.
- الهجرة: `AddServiceRequestSourceAccountRegion` — **ملف فقط، لم تُشغَّل على أي قاعدة** (بوّابة موافقة).
- الواجهة: منسدلات متتالية + شارات + فلتر (Flutter). 19 اختبار تكامل + 7 widget كلها خضراء؛ مراجعة أمنية بلا P0/P1؛ بناء ويندوز أصلي ناجح.
- **نطاق المرحلة (أ)**: مناطق الساس مربوطة بالكامل (SasRegion عبر source-pool)؛ FTTH حتى مستوى الشريك + منطقة نصّية. **المرحلة 2 مؤجَّلة** (زونات FTTH الحيّة، تعتمد على فرع `feature/ftth-credentials-unification` المحجوز لترخيص linked_accounts).
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
