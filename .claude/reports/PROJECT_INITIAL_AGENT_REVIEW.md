# Project Initial Agent Review

> مراجعة أولية لمنصّة الصدارة أجراها نظام الوكلاء عند التأسيس — 2026-06-25. كل ما هو غير مؤكد مُعلَّم بـ **Unknown**.

## 1. Project Type

منصة متكاملة لإدارة خدمات الإنترنت FTTH/ISP + تجارة إلكترونية، متعددة المستأجرين بحسب الشركة (`Company`). تخدم: موظفي الشركات، مشغّلي FTTH، والمواطنين. تتكوّن من خادم API مركزي + تطبيق سطح مكتب/موبايل للشركة + بوابة مواطن.

## 2. Technology Stack

| الطبقة | التقنية |
|--------|---------|
| Backend | .NET 9، Clean Architecture، EF Core 9، SignalR، JWT |
| Database | PostgreSQL (Npgsql)، `sadara_db` على VPS `72.61.183.61`، 84 EF migration |
| App (الشركة) | Flutter — Windows desktop + Android + iOS (`alsadara-ftth`) |
| Web (المواطن) | Flutter/Dart PWA — **Unknown**: README يصفه Blazor WASM |
| Auth | JWT Bearer + نظام صلاحيات مخصص + مصادقة مزدوجة |
| Notifications | Firebase Cloud Messaging (FCM) |
| DevOps | Docker، GitHub Actions (`build-windows.yml`)، Inno Setup، نشر SCP يدوي |

## 3. Main Components

- `src/Backend/API/Sadara.API` — 57 controller، Hubs، Authorization، DTOs، Services.
- `src/Backend/Core/Sadara.Application` — Services، DTOs، Interfaces، Mapping، Validators.
- `src/Backend/Core/Sadara.Domain` — 37+ entity، Enums، Interfaces.
- `src/Backend/Core/Sadara.Infrastructure` — Data/Migrations، Identity، Repositories، Services.
- `src/Apps/CompanyDesktop/alsadara-ftth` — التطبيق الرئيسي.
- `src/Apps/CitizenWeb` — بوابة المواطن.
- `tests/` — ثلاثة مشاريع اختبار (API/Domain/Integration).

## 4. Critical Files

| الملف | السبب |
|------|-------|
| `.env` | يحوي أسرار إنتاج حقيقية (DB, JWT, تشفير, VPS, SMTP, Firebase) |
| `Infrastructure/Identity/IdentityServices.cs` | منطق المصادقة |
| `API/Authorization/RequirePermissionAttribute.cs` | تطبيق الصلاحيات |
| `Controllers/DatabaseAdminController.cs`, `SuperAdminController.cs` | endpoints إدارية فائقة الصلاحية |
| `Infrastructure/Data/Migrations/*` | 84 migration تمسّ مخطط الإنتاج |
| `docker/docker-compose.yaml`، `.github/workflows/build-windows.yml` | البنية التحتية والبناء |

## 5. Security Notes

- **P0**: أسرار حقيقية في `.env` ومجلدي `secrets/`/`.secrets/` داخل الشجرة — يجب التأكد من استبعادها في `.gitignore` ومن تاريخ git؛ تدوير أي مفتاح مكشوف.
- **P0**: `DatabaseAdminController` و `SuperAdminController` تحتاج تدقيق صلاحيات دقيق.
- عزل المستأجرين يعتمد على `CompanyId` — يجب التحقق من تطبيقه عبر كل الاستعلامات (RLS؟ **Unknown**).
- لا يوجد دليل على rate limiting أو CORS صارم — **Unknown**، يلزم تدقيق.

## 6. Database Notes

- PostgreSQL على VPS واحد للإنتاج (`72.61.183.61`)؛ لا CD مؤتمت — النشر يدوي عالي الخطورة البشرية.
- 84 migration؛ أي تغيير schema يجب أن يمرّ على `database-postgres-agent` مع Impact/Migration/Rollback/Test plan وموافقة بشرية.
- استراتيجية النسخ الاحتياطي/الاستعادة قبل migrations — **Unknown**، يلزم توثيق.

## 7. Testing Notes

- توجد ثلاثة مشاريع اختبار لكنها تبدو شبه فارغة؛ التغطية الفعلية **Unknown** ومرجّحة منخفضة جداً مقابل 57 controller.
- لا توجد إشارة لاختبارات E2E للتطبيقات — **Unknown**.
- أولوية: اختبارات للمسارات الحرجة (Auth، Accounting، Tenancy).

## 8. DevOps Notes

- CI يبني مثبّت Windows فقط (`build-windows.yml`)؛ لا CI للـ backend (بناء/اختبار) — فجوة.
- النشر: SCP يدوي للـ DLLs + `systemctl restart sadara-api`؛ التطبيق عبر Inno Setup → GitHub Releases → تحديث تلقائي.
- Docker موجود لكن مدى استخدامه في الإنتاج **Unknown**.
- ملفات مؤقتة/كبيرة و`node_modules` في الجذر تلوّث الريبو.

## 9. Documentation Notes

- يوجد README عربي شامل + أدلة متعددة (`BUILD_AND_RELEASE_GUIDE.md`، `DEPLOYMENT_GUIDE.md`، `FILES_INVENTORY.md`، `docs/`) — لكن متفرقة وبعضها مكرر.
- تعارض موثّق: توصيف CitizenWeb بين Blazor و Flutter.

## 10. Missing Information (Unknown)

- إطار الاختبار الفعلي ونسبة التغطية.
- وجود/غياب RLS وrate limiting وإعداد CORS.
- استراتيجية النسخ الاحتياطي لقاعدة الإنتاج.
- تقنية CitizenWeb الحقيقية (Blazor مقابل Flutter).
- مدى الاعتماد الإنتاجي على Docker.
- آلية إدارة الأسرار في الإنتاج (هل تُحقن من `.env` على الخادم؟).

## 11. Suggested Next Actions

1. تشغيل `security-workflow` على بند الأسرار (P0) أولاً.
2. تدقيق الـ controllers الإدارية (P0).
3. تنظيف الريبو من المؤقتات/الـ binaries (P1).
4. سدّ فجوات الـ **Unknown** أعلاه بفحص موجّه قبل أي تطوير كبير.
5. وضع خطة رفع تغطية الاختبارات (P2).
6. البدء دائماً من `00-project-manager` وفق نموذج التشغيل في `CLAUDE.md`.
