# تقرير حالة وتسليم — 2026-08-02

ملف مرجعي شامل لِما أُنجز في جلسة العمل وحالة كل شيء الآن. (الإصدار السابق: 2.2.25 → الحالي المُصدَر: **2.3.0**)

---

## 1) ما هو حيّ الآن (منشور على الإنتاج / للمستخدمين)

| العنصر | الحالة | الدليل |
|--------|--------|--------|
| **إصدار التطبيق v2.3.0** | ✅ منشور، `releases/latest` = v2.3.0 | https://github.com/07706228120Hh/alsadara-FTTH/releases/tag/v2.3.0 |
| **auto-update** | ✅ فعّال (2.3.0 > 2.2.25) — الأجهزة تُحدَّث تلقائياً | — |
| **backend — endpoint الملخّص** (المرحلة 1) | ✅ منشور وحيّ (`Sadara.API.dll` فقط، 2026-08-01) | `/api/servicerequests/summary` يردّ 401؛ صفر 5xx |
| **تنظيف الإنتاج** | ✅ القاعدة 473MB → 304MB | حذف 366K صف EmployeeLocationLogs + VACUUM SubscriberCaches |

## 2) الإصدار v2.3.0 — ماذا يحوي

**نظام المهام:** لوحة تُحسب على الخادم (بدل تحميل 10K صف) · إصلاح المهام المرفوضة (كانت تظهر «مفتوحة») · توحيد ألوان الحالات · caching فوري · تطبيع أسماء الفنيين · إصلاح تطابق القسم «ال».
**الواجهة:** إصلاحات overflow على الهاتف · أسهم RTL · مناطق لمس ≥44px · مبالغ بفواصل · مكوّنات مشتركة.
**واتساب/الأجهزة الجديدة:** تضمين وتثبيت شهادة ISRG Root X1 في المُثبِّت (يُصلح فشل تجديد واتساب) · رسائل n8n أوضح.
**تنظيف:** حذف كود Firestore الميّت للمهام.

## 3) حالة git (كلها محفوظة على القرص؛ release/v2.3.0 مدفوع لـ origin)

| الفرع | HEAD | الحالة |
|-------|------|--------|
| `release/v2.3.0` | `9002b11` | ✅ **مدفوع** + tag `v2.3.0` مرفوع + Release منشور |
| `feature/tasks-optimization` | `59870bd` | محلي (8 commits تحسين المهام) — محتوى ضمن release/v2.3.0 |
| `feature/phase1-security` | `829dc31` | محلي (عزل الشركات + شهادة) — الشهادة ضمن release/v2.3.0 |
| `master` | `4cce630` | v2.2.25 (لم يُدمج فيه الإصدار — النشر عبر tag) |

> كل العمل موجود على origin عبر `release/v2.3.0`. الفرعان الآخران محليان لكن محتواهما المُصدَر مدموج في release/v2.3.0.

## 4) المتبقّي وعوائقه

| البند | العائق | من يلزم |
|-------|--------|---------|
| **تفعيل عزل الشركات** (يحجب نشر backend م2 الكامل) | **غير جاهز — 3× P0** | المستخدم + security + database |
| **فوترة GitHub** (CI الإصدار معطّل — لهذا نُشر v2.3.0 يدوياً) | حساب GitHub `07706228120Hh` | المستخدم فقط |
| **توقيع Authenticode للمُثبِّت** | يحتاج شهادة توقيع كود | المستخدم فقط |
| **backend المرحلة 2** (أعمدة Department/TechnicianName) | كود جاهز؛ نشره منفصلاً ممكن عبر فرع من main؛ غير عاجل (م1 تعمل بـ79ms) | موافقة نشر |
| **م6 أرشفة المهام القديمة · م7ب Details→jsonb** | بيانات/schema إنتاج، غير عاجلة | موافقة |

### عوائق عزل الشركات P0 (تفصيل — من architecture-evolution-agent 2026-08-02)
- **G1:** `Tenancy:DefaultCompanyId` غير مضبوط في `appsettings.Production.json` ← ختم CompanyId خامل ← تراكم صفوف null ← يكرّر كسر يوليو (خطأ 23505). (`SadaraDbContext.cs:1715`)
- **G2:** الـbackfill قديم (الكود القديم استمرّ يُدرج null بعد تراجع 2026-07-16) ← ~483K صف null ستختفي خلف الفلتر ← يلزم backfill جديد + verify=0 قبل النشر.
- **G3:** `Security:InternalApiKey` مسرَّب في `appsettings.json:46` ولم يُدوَّر.
- **جذر المشكلة:** الفلتر المركزي في `SadaraDbContext.cs:1641-1676` **نشط دائماً بلا feature flag** ← أي نشر لـ`Infrastructure.dll` من `feature/phase1-security` يُفعّل العزل + يطبّق كل الـmigrations (`Program.cs:351`).
- **التوصية:** flag `Tenancy:EnforceIsolation` (افتراضي OFF) لفصل النشر عن التفعيل — يفكّ حجب م2 أيضاً.

## 5) الخطوات القادمة الموصى بها (بالأولوية)
1. **المستخدم:** حلّ فوترة GitHub (لإعادة CI التلقائي) + قرار شهادة توقيع الكود.
2. **راقب** أول جهاز يلتقط تحديث v2.3.0 (خاصة لوحة المهام + تجديد واتساب على جهاز جديد).
3. **بموافقة:** تنفيذ flag العزل (كود) ← يفكّ حجب backend المرحلة 2.
4. **بتنسيق ومراجعة:** إغلاق عوائق العزل P0 (G1/G2/G3) → تفعيل عزل منسّق.
5. **إن ظهر خلل بـ v2.3.0:** rollback = أعِد تعيين `v2.2.25` كـlatest + احذف أصل v2.3.0؛ الإصلاح السريع = إصدار v2.3.1 أعلى (التطبيق لا يرجع لأقدم).

## 6) مراجع
- release notes: `docs/release-notes/v2.3.0.md` · CHANGELOG: `src/Apps/CompanyDesktop/alsadara-ftth/CHANGELOG.md`
- دليل الإصدار: `docs/RELEASE_RUNBOOK.md` (§8 rollback) · تصميم مزامنة واتساب: `docs/design/company_whatsapp_settings.md`
- المُثبِّت المبنيّ محلياً: `src/Apps/CompanyDesktop/alsadara-ftth/build/installer/Alsadara-Setup-v2.3.0.exe`
- الذاكرة: `tasks-system-optimization`, `tenant-isolation-status`, `release-runbook`, `data-retention-cleanup`, `whatsapp-renewal-fresh-device` (في مجلد ذاكرة المستخدم).
