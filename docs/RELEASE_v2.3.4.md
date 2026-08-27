# تقرير الإصدار v2.3.4 — ما أُنجز وما تبقّى

> **التاريخ:** 2026-08-26 · **الإصدار:** `2.3.4+309` · **الفرع:** `release/v2.3.4` · **الحالة:** **منشور بالكامل (تطبيق + باكند) — Latest**

هذا التقرير مرجع لمدير المشروع والوكلاء لمزامنة معرفتهم بحالة النظام بعد الإصدار.

---

## 1. ما أُنجز

### 1.1 الباكند (منشور على الإنتاج `72.61.183.61` ومُتحقَّق)
- **إصلاح `/summary` = 500**:
  - `42P08` (بارامترات التاريخ/النص الفارغة بلا نوع) → تنميط صريح `NpgsqlDbType` لكل بارامتر (Uuid/TimestampTz/Text) في q1/q2/q3.
  - `FormatException` (EF's `SqlQueryRaw` يعامل SQL كـString.Format، و`{` في regex الحارس كسره) → تهريب `{{`.
- **جدول الفنيين يطابق البطاقات**: `COALESCE(NULLIF("TechnicianName",''), Details::json->>'technician')` — يقرأ الفني من `Details` عند فراغ العمود (العمود غير مكتمل الـbackfill).
- **فلاتر الأدوار**: `assignee`/`department` في WHERE ترجع لـ`Details` أيضاً.
- **تطبيع اسم العمود**: `ExtractDetailValue` يشذّب + يدمج المسافات الداخلية.
- **علَم `Tenancy:EnforceIsolation`** (افتراضي **OFF**): يحكّم الفلتر المركزي + ختم CompanyId ⇒ نشر الثنائي محايد للعزل؛ التفعيل قرار تشغيلي منفصل.
- **التحقق**: `/summary` يردّ **200** بحركة مشغّلين حقيقية · صفر 500/42P08/FormatException · الخدمة `active`.
- **الترحيلات المطبَّقة عند الإقلاع**: `20260717223916` (CompanyId لأبناء المحاسبة) + `20260801164003` (أعمدة Department/TechnicianName) — أعمدة nullable آمنة.

### 1.2 التطبيق (Flutter — منشور على GitHub Releases، auto-update فعّال)
- **شاشة المهام** (`home_page_tasks.dart`): تبويب «الكل» = عمليات هذا الشهر فقط + تحسينات أداء (إزالة تكرار/حساب مهدور + دمج setState).
- الأصول: `Alsadara-Setup-v2.3.4.exe` (ويندوز، 23MB) + `Alsadara-v2.3.4-arm64.apk` (أندرويد arm64، 51MB).
- `releases/latest` = **v2.3.4** (مؤكَّد).

### 1.3 حادثتان أثناء النشر (حُلّتا فوراً — درس مهم)
- ظهرتا فقط عبر مسار **EF `SqlQueryRaw`** ولم يكشفهما اختبار المرآة بـ**psql**: (1) String.Format braces، (2) 42P08 للبارامترات غير المُنمَّطة.
- **الدرس:** تغييرات SQL في EF `SqlQueryRaw` يجب اختبارها عبر EF لا psql فقط.

### 1.4 النسخ الاحتياطية (للتراجع)
- DB: `/root/backups/sadara_db_pre_v234_20260826_152238.sql.gz` (31MB).
- DLLs: `/var/www/sadara-api.pre_v234_20260826_152238`.

---

## 2. ما تبقّى (بوابات تفعيل العزل — تحتاج موافقة صريحة)

| # | البوابة | النوع | الحالة |
|---|---------|------|:---:|
| 1 | ضبط `Tenancy:DefaultCompanyId` على الإنتاج | إعداد | ⏳ |
| 2 | تدوير `Security:InternalApiKey` (+ n8n + التطبيق) | سرّ إنتاج | ⏳ |
| 3 | إعادة backfill شامل + **verify = 0** | DB | ⏳ |
| 4 | استثناء `InternetPlan` من الفلتر | كود | ❌ لم يُعمل |
| 5 | معالجة `IptvSubscriber` (`CompanyId` من `string`→`Guid`) | كود+DB | ❌ لم يُعمل |
| 6 | `Tenancy:EnforceIsolation=true` + restart + فحص دخان | تشغيل | ⏳ |

---

## 3. ديون مفتوحة

| القضية | الخطورة | الوضع |
|--------|:---:|-------|
| `InternalApiKey` مسرَّب/غير مُدوَّر | 🔴 P0 | كود fail-closed؛ التدوير معلّق |
| `IptvSubscriber` غير معزول (CompanyId نصّي) | 🔴 P0 | يحتاج تحويل نوع + migration |
| `InternetPlan` غير مستثنى | 🟠 P1 | قبل التفعيل |
| مسارات تحديث المهمة تكتب Details خاماً (`:1737,1840`) | 🟢 منخفض | أُصلح الإنشاء فقط |
| `RequirePermissionAttribute` fail-open | 🟠 P2 | يُضعف بوابة التحصيل |
| كشف `FinalCost` بلا صلاحية في `GetAll`/`GetStatistics` | 🟠 P2 | محاذاة لاحقة |
| `User.PlainPassword` نصّي صريح | 🟠 أمني | دَين قديم |

---

## 4. مرجع الملفات ذات الصلة
- خطة الخطوات اللاحقة: `docs/إكمال-الخطوات-اللاحقة.md`
- ذاكرة تحسين المهام: `.claude/memory/tasks-system-optimization.md`
- ذاكرة عزل الشركات: `.claude/memory/tenant-isolation-status.md`
- دليل الإصدار: `.claude/memory/release-runbook.md`

> **قواعد ملزمة:** أي تفعيل عزل / تغيير سرّ / migration على الإنتاج يتطلب موافقة بشرية صريحة + نسخة احتياطية + خطة تراجع.
