# PROJECT_STATE — حالة مشروع Sadara Platform

ملف الحالة المركزي لنظام الوكلاء (Agents) في منصة الصدارة. تاريخ تأسيس نظام الوكلاء: 2026-06-25.

## الحالة الحالية
- **الإصدار**: **2.3.0+305** (منشور على GitHub Releases كـ latest، 2026-08-02) — يليه 2.2.25+304.
- **Branch النشِط**: `release/v2.3.0` (`9002b11`، مدفوع لـ origin + tag `v2.3.0`). فروع محلية: `feature/tasks-optimization`، `feature/phase1-security`. `master` عند 4cce630 (لم يُدمج فيه الإصدار — النشر عبر tag).
- **تاريخ آخر تحديث للذاكرة**: 2026-08-02.
- **تفاصيل الجلسة الكاملة**: `docs/SESSION_HANDOFF_2026-08-02.md`.

### إنجازات جلسة 2026-08-02
- **إصدار v2.3.0 منشور وحيّ** (لوحة مهام خادمية + تحسينات واجهة + إصلاح شهادة ISRG Root X1 للأجهزة الجديدة). نُشر **يدوياً** لأن **GitHub Actions مقفل بالفوترة** (كل الإصدارات السابقة فشلت لذلك).
- **backend المرحلة 1** (endpoint `/api/servicerequests/summary`) منشور وحيّ (`Sadara.API.dll` فقط).
- **تنظيف الإنتاج**: القاعدة 473MB → 304MB (حذف 366K صف EmployeeLocationLogs + VACUUM).
- **backend المرحلة 2** (تطبيع أعمدة المهام) كود جاهز غير منشور — محجوب بعزل الشركات.
- **تقييم عزل الشركات**: **غير جاهز للنشر** (3× P0: config الإنتاج + backfill جديد + تدوير InternalApiKey؛ الفلتر نشط بلا flag). راجع `.claude/memory/` أو ذاكرة المستخدم `tenant-isolation-status`.

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
