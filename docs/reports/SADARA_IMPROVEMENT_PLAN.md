# خطة تطوير منصة الصدارة — متكاملة ومفصّلة (Improvement Master Plan)

> **تاريخ الإصدار:** 2026-09-27 · **الإصدار الحالي:** v2.3.9+314 · **الفرع النشِط:** `hotfix/disable-tech-fees`
> **الحالة:** مسوّدة للاعتماد البشري. لا يُنفَّذ أي بند مُعلّم بـ🔒 قبل موافقة صريحة (طبقاً لـ CLAUDE.md).

---

## 0. لقطة الحالة الراهنة (حقائق مبنيّة على قراءة الكود)

| البُعد | الواقع الحالي | الملف/الدليل |
|--------|----------------|--------------|
| Backend | .NET 9 Clean Architecture، 57 controller، 51 migration | `src/Backend` |
| توزيع الأسطر | Controllers ≈ 51,455 سطر / Application = 554 سطر فقط | منطق الأعمال في الـControllers |
| أكبر Controllers | Accounting 6355، Inventory 5266، FtthAccounting 4262، InternalData 4183 | `src/Backend/API/Sadara.API/Controllers` |
| أكبر ملفات Flutter | operators_dashboard 14,307 · subscription_details 13,354 · home_page 6,468 | `src/Apps/CompanyDesktop/alsadara-ftth/lib` |
| العزل متعدد الشركات | فلتر مركزي **جاهز لكن خامل** (`Tenancy:EnforceIsolation=false`) | `SadaraDbContext.cs:1642-1696` |
| ختم CompanyId على الكتابة | **مُفعّل** (مستقل عن علَم القراءة، بعد hotfix) | `SadaraDbContext.cs:1716-1756` |
| المصادقة | JWT **HS256** (سرّ متماثل)، 60 دقيقة | `Program.cs:95-160` |
| الصلاحيات | فحص DB لكل طلب، **fail-open** إن غابت V2 | `RequirePermissionAttribute.cs:111` |
| CORS | `AllowAnyOrigin+AnyHeader+AnyMethod`؛ `AllowedOrigins` معرَّف ولا يُقرأ | `Program.cs:196-204` |
| Rate limiting | عام 600/دقيقة/IP فقط؛ لا حدّ خاص بالمصادقة | `Program.cs:206-220` |
| الاختبارات | تكامل فقط (~1169 سطر: Summary + TenantIsolation)؛ لا اختبارات وحدة | `tests/Sadara.Integration.Tests` |
| CI | يبني Flutter/Windows فقط؛ لا بناء/اختبار Backend | `.github/workflows/build-windows.yml` |
| النشر | SCP يدوي + `systemctl restart` | يدوي، هشّ |

### 🔴 مخاطر حرجة مؤكَّدة الآن
1. **سرّ مكشوف مُلتزَم في git**: `Security:InternalApiKey = "sadara-internal-2024-secure-key"` في `appsettings.json` (متتبَّع). هذا المفتاح يمنح تجاوز عزل الشركات عبر `X-Api-Key`.
2. **سرّ JWT تطويري مُلتزَم**: `Jwt:Secret = "DEV_ONLY_...2024!"` في `appsettings.json` (يجب التأكد أن الإنتاج يتجاوزه فعلياً بمتغيّر بيئة).
3. **CORS مفتوح للجميع** رغم وجود قائمة أصول جاهزة غير مُستخدَمة.
4. **العزل خامل** ⇒ الاعتماد على فلترة يدوية لكل controller (أثبت انحدار CompanyId هشاشتها).
5. **الصلاحيات fail-open** ⇒ مستخدم بلا V2 يتجاوز الفحص.

---

## استراتيجية التنفيذ العامة

- **مبدأ**: أمانٌ أولاً بأقل نصف قطر انفجار، ثم تفعيل العزل (البوابة الكبرى)، ثم شبكة أمان الاختبارات وCI، ثم الديون المعمارية طويلة النَّفَس.
- **كل مرحلة**: فرع مستقل + PR + مراجعة (`code-reviewer-agent`) + اختبار قبل الدمج.
- **لا نشر إنتاج ولا migration ولا تغيير أسرار/عزل بدون موافقة بشرية صريحة** (🔒).
- **نسخة احتياطية إلزامية** (DB dump + نسخة DLLs) قبل أي نشر backend.

---

## المرحلة 0 — الحواجز التمهيدية (Guardrails)

**الهدف:** إنشاء شبكة أمان قبل أي تعديل جوهري.

| # | الخطوة | الملفات/الأدوات | تحقّق | مخاطرة |
|---|--------|-----------------|-------|--------|
| 0.1 | إضافة بوابة CI للـBackend: `dotnet build` + `dotnet test` على كل PR | `.github/workflows/backend-ci.yml` (جديد) | البناء والاختبارات تعمل على PR | منخفضة |
| 0.2 | التأكد أن بيئة staging منفصلة أو إنشاؤها (منفذ/قاعدة مستقلة على نفس VPS) | `docker-compose` / systemd unit ثانٍ | staging يستجيب على `/health` | متوسطة |
| 0.3 | توثيق/أتمتة سكربت نسخ احتياطي + rollback (dump + DLLs) | `scripts/deploy/` | استرجاع تجريبي ناجح لـstaging | متوسطة |
| 0.4 | تنظيف المستودع: إزالة `*.zip`، `tmp_*.json`، `publish_*/`، `node_modules/` من التتبّع + توسيع `.gitignore` | `.gitignore` | `git status` نظيف؛ الحجم أصغر | منخفضة |

**المخرجات:** CI أخضر، staging حيّ، سكربت rollback مُختبَر، مستودع نظيف.

---

## المرحلة 1 — تحصين أمني سريع (نصف قطر انفجار منخفض)

**الهدف:** إغلاق الثغرات الحرجة دون تغيير سلوك الأعمال. **تتطلب موافقة على تغيير الأسرار والمصادقة (🔒).**

### 1.1 🔒 تدوير وإزالة `InternalApiKey` المكشوف — **P0**
- توليد مفتاح جديد قوي، وضعه في متغيّر بيئة `SADARA_INTERNAL_API_KEY` على الخادم فقط (الكود يقرأه أصلاً كـfallback في `CurrentTenant.cs:71-72`).
- إزالة القيمة من `appsettings.json` (تركها فارغة).
- تحديث تكامل n8n بالمفتاح الجديد.
- **الكود القديم في السجل**: المفتاح القديم يبقى في تاريخ git ⇒ اعتباره «محروقاً» نهائياً (التدوير يبطله).
- **تحقّق:** طلب بـX-Api-Key القديم يُرفض؛ الجديد يعمل من n8n.

### 1.2 🔒 تدوير سرّ JWT والتأكد من مصدره الإنتاجي — **P1**
- التأكد أن الإنتاج يقرأ `Jwt:Secret` من متغيّر بيئة (لا من `appsettings.json`).
- توليد سرّ إنتاجي جديد ≥ 256-bit، إزالة قيمة الـDEV من الملف المتتبَّع.
- **أثر جانبي:** تدوير السرّ يُبطل كل التوكنات الحالية ⇒ إعادة تسجيل دخول للجميع ⇒ يُنفَّذ في نافذة صيانة معلنة.

### 1.3 تقييد CORS — **P1**
- تعديل `Program.cs:196-204` و`308` لقراءة `Security:AllowedOrigins`/`Cors:AllowedOrigins` من الإعداد بدل `AllowAll`، مع `WithOrigins(...).AllowCredentials()` للنطاقات المعروفة فقط.
- إبقاء `AllowAll` لبيئة Development فقط عبر شرط `IsDevelopment()`.
- **تحقّق:** طلب من أصل غير مُصرَّح يُرفض؛ التطبيق والبوابة يعملان.

### 1.4 حدّ معدّل خاص بالمصادقة — **P2**
- إضافة سياسة rate-limit صارمة (مثل 10/دقيقة/IP) على `login`, `send-otp`, `forgot-password`, `reset-password` عبر `[EnableRateLimiting("auth")]` (مضافة في `Program.cs`).
- الأهداف: `AuthController.cs:18,39,46,53` و`UnifiedAuthController.cs:67,360`.
- **تحقّق:** تجاوز الحد يعيد 429 على login فقط دون تأثير على بقية الـAPI.

### 1.5 تصلّب endpoints الإدارية — **P2**
- تدقيق `DatabaseAdminController.cs` (1950 سطر) و`SuperAdminController.cs` و`ServerController.cs`: تأكيد `[Authorize(Policy="SuperAdminOnly")]` على كل الإجراءات.
- **تحقّق:** مستخدم غير SuperAdmin ⇒ 403 على كل مسارات الإدارة.

**بوابة الخروج من المرحلة 1:** مراجعة `security-auditor-agent` + `penetration-testing-agent` على staging.

---

## المرحلة 2 — تفعيل عزل الشركات (البوابة الكبرى) 🔒

**الهدف:** تحويل العزل من «فلترة يدوية هشّة» إلى «فلتر مركزي على مستوى قاعدة البيانات».
**هذه أخطر مرحلة** — تغيّر عزل المستأجرين (يتطلب موافقة صريحة + خطة rollback).

البوابات المطلوبة (موثّقة في الكود نفسه، `appsettings.json:22` و`SadaraDbContext.cs:1649`):

### 2.1 ضبط `Tenancy:DefaultCompanyId`
- تحديد شركة الصدارة الأساسية ووضع GUID الحقيقي في متغيّر بيئة/إعداد الإنتاج.
- **تحقّق:** أي إدراج في سياق تجاوز يُختَم بها (لا صفوف يتيمة جديدة).

### 2.2 معالجة `IptvSubscriber` (الحالة الخاصة)
- `IptvSubscriber.CompanyId` من نوع **`string`** ⇒ الفلتر المركزي (Guid/Guid? فقط) **لا يغطّيه**.
- خياران: (أ) ترحيل العمود إلى `Guid?` عبر migration + backfill، أو (ب) فلتر يدوي مخصّص له كما في `InternetPlan`.
- **يتطلب migration (🔒) + خطة rollback.**

### 2.3 Backfill لكل الكيانات المستأجَرة (30 كياناً تحمل CompanyId)
- الكيانات: Accounting, Agent, Announcement, AttendanceRecord, Chat, Citizen, CitizenCommerce, CompanyFtthSettings, DailySettlementReport, Department, EmployeeLocation, FtthSubscriberCache, FtthSyncLog, ISPSubscriber, Inventory, IptvSubscriber, ReminderSettings, ServiceAndPermission, Subscription, SubscriptionLog, SupportTicket, TaskAudit, User, WhatsAppBatchReport, WhatsAppData, ZoneMaintenanceFee, ZoneStatistic … (تُستثنى `Company` و`System` والقوالب العامة).
- سكربت تدقيق: `SELECT COUNT(*) WHERE CompanyId IS NULL OR CompanyId = '00000000-...'` لكل جدول.
- تعبئة الصفوف اليتيمة بشركتها الصحيحة (أو DefaultCompanyId عند تعذّر التحديد) **بعد نسخة احتياطية**.
- **معيار البوابة:** `verify = 0` صفٌّ يتيم في كل الجداول.

### 2.4 التحقق على staging قبل الإنتاج
- نسخ بيانات إنتاج (منقّحة) إلى staging، تفعيل `EnforceIsolation=true` هناك.
- تشغيل `TenantIsolationTests.cs` + سيناريوهات يدوية: مستخدمو شركتين مختلفتين لا يرى أحدهما بيانات الآخر؛ SuperAdmin يرى الكل؛ الباقات العامة تظهر؛ تسجيل الدخول يعمل.

### 2.5 التفعيل التدريجي على الإنتاج
- نافذة صيانة + نسخة احتياطية كاملة.
- قلب العلَم `SADARA_ENFORCE_ISOLATION=true`، إعادة تشغيل، مراقبة لصيقة (لوحات كل شركة، صفر تسريب، صفر «قوائم فارغة»).
- **Rollback فوري:** إعادة العلَم إلى false + إعادة تشغيل (العلَم مصمَّم للنشر المحايد).

**بوابة الخروج:** توقيع `security-auditor-agent` + `database-postgres-agent` + موافقة بشرية على النشر والـmigration.

---

## المرحلة 3 — شبكة أمان الاختبارات وCI

**الهدف:** رفع التغطية من ~1169 سطر تكامل إلى تغطية وحدة للمسارات الحرجة.

| # | الخطوة | التغطية المستهدفة |
|---|--------|-------------------|
| 3.1 | اختبارات وحدة لـ`RequirePermissionAttribute.HasPermission` (الوراثة الهرمية + fail-open/closed) | الصلاحيات |
| 3.2 | اختبارات وحدة لمنطق المحاسبة (القيود مدين/دائن، idempotency) | المحاسبة |
| 3.3 | توسعة `TenantIsolationTests` لتغطي كل كيان مستأجَر + IptvSubscriber | العزل |
| 3.4 | اختبارات تكامل لمسارات المهام (`/summary` متعدد الأقسام) | المهام |
| 3.5 | ربط الاختبارات ببوابة CI (المرحلة 0.1) كشرط دمج | CI |

**تحقّق:** فشل أي اختبار يمنع الدمج تلقائياً.

---

## المرحلة 4 — إعادة الهيكلة المعمارية (Backend)

**الهدف:** استعادة Clean Architecture الفعلية. **تدريجي، سلوك ثابت، على مراحل صغيرة قابلة للمراجعة** (`refactor-agent`).

### 4.1 إخراج منطق الأعمال من God Controllers إلى Application Services
- البدء بـ`AccountingController` (6355 سطر) → `AccountingService` في طبقة Application.
- ثم `InventoryController` (5266) و`FtthAccountingController` (4262).
- نمط: Controller نحيل (تحقّق + توجيه) ↔ Service (منطق) ↔ Repository (بيانات).
- **معيار:** لا تغيير في العقود (نفس الـDTOs/المسارات)؛ اختبارات المرحلة 3 تحرس السلوك.

### 4.2 تفكيك `SadaraDbContext` (1757 سطر)
- نقل تهيئة كل كيان إلى `IEntityTypeConfiguration<T>` مستقل تحت `Infrastructure/Data/Configurations`.
- الإبقاء على منطق العزل/الختم مركزياً كما هو.

### 4.3 توحيد النماذج
- توحيد نوع `CompanyId` عبر الكيانات (حسم `IptvSubscriber` string) وتطبيق `ITenantScoped` صراحةً على كل كيان مستأجَر.
- تقسيم `Enums.cs` و`Services.cs` (ملفات جامعة) إلى ملفات لكل نوع.

---

## المرحلة 5 — إعادة هيكلة Flutter

**الهدف:** كسر الملفات العملاقة وتحسين قابلية الصيانة والأداء (`mobile-agent` + `ui-ux-agent`).

| # | الخطوة |
|---|--------|
| 5.1 | تفكيك `ftth_operators_dashboard_page.dart` (14,307 سطر) إلى widgets + إخراج نداءات API إلى service |
| 5.2 | تفكيك `subscription_details_page.dart` (13,354) و`home_page.dart` (6,468) بنفس النمط |
| 5.3 | توحيد طبقة الشبكة: اعتماد `dio` وإزالة `http` المزدوج (interceptor موحّد + معالجة توكن مركزية) |
| 5.4 | فصل منطق الأعمال عن الـUI عبر providers/services (استمرار نمط `provider` الحالي) |
| 5.5 | تدقيق أداء: repaint، pagination، حجم الحزمة (`performance-agent`) |

**معيار:** لا تراجع وظيفي؛ اختبار يدوي للشاشات المعاد تشكيلها قبل الإصدار.

---

## المرحلة 6 — DevOps وأتمتة النشر

| # | الخطوة |
|---|--------|
| 6.1 | خط نشر backend مؤتمت: build → نسخة احتياطية → SCP → restart → فحص `/health` مزدوج → rollback آلي عند الفشل |
| 6.2 | فصل بيئات واضح (dev/staging/prod) بإعدادات وأسرار مستقلة |
| 6.3 | مراقبة/تنبيه: تجميع سجلات Serilog + تنبيه عند 5xx/إعادة تشغيل |
| 6.4 | معالجة الهجرات: إيقاف `MigrateAsync` الصامت (`Program.cs:351-352` يبتلع الاستثناء) → هجرات صريحة مُراجَعة بخطة rollback |

---

## المرحلة 7 — استراتيجي (بعد الاستقرار)

- **7.1 الانتقال إلى JWT RS256** (العمل جاهز على فرع `feature/distributed-identity-rs256`): مفتاح خاص للتوقيع/عام للتحقق، تمهيداً للمعمارية الموزّعة.
- **7.2 المعمارية الموزّعة** (`ADR-001`): مركز هوية/ترخيص + عقدة محلية لكل شركة (API+PostgreSQL) — قرار كبير يُبنى على SuperAdmin الموجود لا يُكرّره.

---

## سجل المخاطر وخطط التراجع

| الخطر | المرحلة | الأثر | التخفيف / Rollback |
|-------|---------|-------|--------------------|
| تدوير JWT يُخرج كل المستخدمين | 1.2 | إعادة دخول شاملة | نافذة صيانة معلنة |
| تفعيل العزل يُخفي بيانات صفوف يتيمة | 2 | «قوائم فارغة» | backfill/verify=0 قبل التفعيل + قلب العلَم لـfalse فوراً |
| migration الـIptvSubscriber | 2.2 | فقد ربط | نسخة احتياطية + سكربت عكسي |
| refactor يكسر سلوكاً | 4,5 | انحدار | اختبارات المرحلة 3 + مراحل صغيرة + مراجعة |
| نشر يدوي ينقطع (Connection reset) | 6 | نشر جزئي | أتمتة + rollback آلي (المرحلة 0.3) |

---

## التسلسل والاعتماديات

```
المرحلة 0 (حواجز) ──► المرحلة 1 (أمن سريع) ──► المرحلة 3 (اختبارات) ──► المرحلة 2 (تفعيل العزل)
       │                                              │                         ▲
       └──────────────────────────────────────────────┴─ المرحلة 4/5 (refactor) ┘
المرحلة 6 (DevOps) بالتوازي بعد 0 · المرحلة 7 بعد استقرار 2
```

- المرحلة 2 (العزل) تعتمد على 3 (اختبارات) و0.2/0.3 (staging+rollback).
- refactor (4,5) يعتمد على 3 (شبكة أمان).

---

## بوابات الموافقة البشرية (طبقاً لـ CLAUDE.md) 🔒

يجب موافقة صريحة قبل: تغيير الأسرار (1.1، 1.2)، تغيير عزل المستأجرين (2)، أي migration (2.2)، أي نشر إنتاج، وأي عملية git مدمّرة/force push. عند الشك ⇒ تقرير لا تنفيذ.

---

## نقطة البداية الموصى بها

**المرحلة 0 + البند 1.1 (تدوير `InternalApiKey`) + 1.3 (تقييد CORS)** — أعلى قيمة أمنية بأقل مخاطرة، وتُمهّد لبوابة العزل الكبرى.
