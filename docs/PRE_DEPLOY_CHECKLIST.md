# قائمة فحص ما قبل النشر — وحدة وكيل الساس + تعديلات الجلسة

> ⚠️ **لا تنشر قبل إتمام كل بند هنا.** كل ما يلي راكمناه أثناء التطوير/الاختبار المحلي على فرع `feature/sas-agent-integration`.
> آخر تحديث: أكتوبر 2026.

---

## 1) 🔴 علامات التطوير المحلي — يجب إعادتها إلى `true` قبل البناء (إلزامي)

| الملف | السطر | الحالي (محلي) | قبل النشر |
|---|---|---|---|
| `src/Apps/CompanyDesktop/alsadara-ftth/lib/services/api/api_config.dart` | **14** | `static const bool isProduction = false;` | `= true;` |
| `src/Apps/CompanyDesktop/alsadara-ftth/lib/services/sadara_api_service.dart` | **24** | `static const bool _isProduction = false;` | `= true;` |

> أثرها: `isProduction` يتحكّم بعنوان كل الـAPI (Sadara + VPS/ramzalsadara عبر `ApiConfig.vpsBaseUrl`). لو بقيت `false` سيضرب الإنتاج **localhost** ويفشل. **لم تُلتزَم هاتان القيمتان عمداً** — غيّرهما يدوياً قبل `flutter build`.

---

## 2) 🔴 متغيّرات بيئة الباكند (.NET) على الإنتاج (إلزامي)

ضُبطت محلياً فقط؛ على الإنتاج اضبطها بقيم الإنتاج:

| المتغيّر | الغرض | ملاحظة |
|---|---|---|
| `ASPNETCORE_ENVIRONMENT` | `Production` (لا Development) | يُفعّل fail-closed للسرّ الداخلي للساس |
| `ConnectionStrings__DefaultConnection` | Postgres الإنتاج | — |
| `SADARA_INTERNAL_API_KEY` | مفتاح X-Api-Key الداخلي | **🔴 دوّره — انظر بند 5**؛ يجب أن يطابق ما يرسله التطبيق + n8n |
| `SADARA_SAS_INTERNAL_SECRET` | سرّ الصدارة↔خدمة الساس | نفس القيمة على الباكند والـsidecar |
| `DataProtection__KeysPath` | مسار مفاتيح فكّ تشفير كلمات مرور الساس | **ثابت** ومحفوظ؛ فقدانه/تغييره = تعذّر فكّ كلمات مرور حسابات الساس المخزّنة |
| `SasService__BaseUrl` | عنوان الـsidecar | افتراضي `http://127.0.0.1:8100` |

---

## 3) 🔴 الهجرات (Migrations) — تطبيق على قاعدة الإنتاج (إضافية بحتة)

لم تُطبَّق على الإنتاج بعد. خذ **نسخة احتياطية** أولاً، وخطة تراجع (Down جاهز):

| الهجرة | الأثر |
|---|---|
| `20260929225841_AddSasAgentModule` | جدولان: `SasAccounts` + `CompanySasSettings` |
| `20261001111515_AddSasSourceToSubscriptionLog` | 4 أعمدة على `SubscriptionLogs`: `Source`(int افتراضي 0) · `SasAccountId`(uuid null) · `SubscriberUid`(text null) · `SubscriberUsername`(text null) |
| `20261001220456_AddSasPricingAndProfile` | جدولان: `SasPackagePrices` (تسعير الباقات) + `SasSubscriberProfiles` (حقول المواطن الـ11) |
| `20261001224100_AddSasCitizenPayment` | جدول `SasCitizenPayments` (تسديدات ذمم المواطنين) |
| `20261002165714_AddSasRegionAndSubscriberRegionLink` | جدول `SasRegions` (مناطق + أجور صيانة) + عمود `RegionId`(uuid null) على `SasSubscriberProfiles` + فهارس/FK |

> ⚠️ **خمس هجرات ساس لا أربع** (أُضيفت `AddSasRegionAndSubscriberRegionLink` في 2026-10-02). طبّقها جميعاً بالترتيب الزمني.

> الحساب المحاسبي `1180` (ذمم المشتركين) يُنشأ تلقائياً لكل شركة عند أوّل تحصيل «آجل» (`EnsureFixedParentAccount`) — لا يحتاج بذرة يدوية.

> ملاحظة: الإنتاج يستخدم `migrations.sql` يدوياً (لا MigrateAsync تلقائي). طبّق الهجرتين يدوياً أو عبر `dotnet ef database update`.

---

## 4) 🟠 خدمات يجب نشرها

- **خدمة الساس (sidecar)**: `modules/sas-agent/service` كـ systemd على `127.0.0.1:8100` (venv + `pip install -r requirements.txt` + `SADARA_SAS_INTERNAL_SECRET`). **غير مكشوفة للإنترنت.** بياناتها SQLite في `data/sas.db` (مجلد قابل للكتابة).
- **خادم الواتساب** (اختياري): `modules/sas-agent/whatsapp-server` — `npm install` (Node) + systemd + **مسح QR مرّة**. أو الاكتفاء بنمط `app` (wa.me يدوي).

---

## 5) 🔴 أمن الأسرار — تدوير + نقل (إلزامي قبل الإنتاج)

- **`sadara-internal-2024-secure-key`**: مفتاح X-Api-Key **مكشوف في المستودع ومثبّت في عدّة ملفات** بالتطبيق (`AppSecrets._defaultInternalApiKey` + `subscription_logs_service` + `daily_settlement_page` + `account_records_page` + `database_admin_page` + `location_*` + `ftth_operators_dashboard_page`…). 
  - **دوّر القيمة** على الـVPS (`SADARA_INTERNAL_API_KEY`) + حدّث التطبيق (يفضّل عبر `AppSecrets`/متغيّر بيئة لا ثابت) + حدّث **n8n**.
- `Security:InternalApiKey` القديم المكشوف سابقاً في المستودع — مدوَّر ضمن ما سبق.
- السرّ المحلي للساس `sadara-sas-dev-secret-2026` (تطوير فقط) — استبدله بسرّ إنتاجي قوي.
- **🔴 أسرار مُتتبَّعة في Git (تدقيق devops 2026-10-05 — أزِلها من التتبّع قبل الدمج):**
  - `n8n-workflows/n8n-whatsapp-templates-CREDENTIALS.json` + `n8n-auto-reminder-workflow.json` — تحوي المفتاح الداخلي مباشرةً (انقل الأسرار إلى credentials n8n لا ملف ملتزم).
  - `tmp_n8n.json` · `tmp_n8n2.json` · `tmp_exec_detail.json` · `tmp_ex2.json` · `tmp_ex3.json` · `tmp_exec.json` — مخرجات n8n مؤقتة. `git rm --cached` + `.gitignore`.
  - `.claude/settings.local.json` — يحوي المفتاح. `git rm --cached` + `.gitignore`.

---

## 6) 🟢 تغييرات آمنة للإنتاج (لا تحتاج تراجعاً — للعلم فقط)

- تحصين عقد البوّابة↔الساس: `extra="forbid"` + `_IntFromAny` + `test_contract.py` (83 اختبار) — دفاعي، يُبقى.
- فوترة الساس (محاسبة موحّدة + طباعة + واتساب + سجل الحركات) — يُبقى.
- توحيد `ApiConfig.vpsBaseUrl` — في الإنتاج يعيد `https://api.ramzalsadara.tech` حرفياً (صفر تغيير سلوك إنتاجي).
- إصلاحات العقد (image_b64 · query · null · أسماء الحقول) — يُبقى.

---

## 6.5) 🆕 تعديلات جلسة 2026-10-04 (تحسين تدفّق تفعيل الساس)

راكمناها على `feature/sas-agent-integration` — تدخل ضمن نفس النشر:

**الباكند (.NET — تُنشر مع publish، بلا migration):**
- نقطة نهاية جديدة: `POST /api/sas-agent/accounts/{id}/subscription-logs/{logId}/whatsapp-sent` (`SasAgentController.MarkSubscriptionLogWhatsAppSent`) تضبط `IsWhatsAppSent=true` عند الإرسال الفعلي. **لا تحتاج migration** — العمود `IsWhatsAppSent` موجود منذ `20260206224918_AddSubscriptionLogs` (منشور إنتاجاً). عزل ثلاثي + idempotent. **مراجعة أمنية: معتمدة (لا P0/P1/P2).**

**التطبيق (Flutter — يدخل في بناء الإصدار):**
- دمج نافذتي (الأشهر) + (التحصيل) في **نافذة واحدة** غنية (إجمالي حيّ + زر «تفعيل وتحصيل»).
- **طباعة صامتة** للإيصالات عبر `directPrintPdf` بدل حوار ويندوز (`layoutPdf`) — إيصالات FTTH تبقى على سلوكها (silent=false افتراضياً). لا تُرسَل مهمة لطابعة غير متاحة (لا حوار «Waiting for printer connection»).
- **منتقي طابعة الإيصالات** الجديد في «إعدادات الشركة ← إعدادات طابعة الإيصالات» (مفتاح `receipt_printer_name`) + زر تجربة.
- **عرض حالة واتساب** بعد التفعيل (أُرسل/فشل/يدوي/لا رقم/الخادم غير جاهز) + تبليغ الخادم.

**🟠 خطوة ما بعد تثبيت التطبيق (لكل جهاز وكيل):** افتح «إعدادات طابعة الإيصالات» واختر **الطابعة الحرارية** واحفظها + «تجربة طباعة». بدونها تُطبع على الطابعة الافتراضية المتاحة (قد لا تكون الحرارية).

---

## 7) 🟢 التحقّق بعد النشر

1. تطبيق الهجرتين + نسخة احتياطية سليمة.
2. الـsidecar يعمل (`GET /health` = 200) والباكند يصله.
3. تسجيل دخول موظّف → توجيه صحيح (وكيل/أدمن).
4. تبويبات الساس: الحسابات/لوحة/مشتركون (محلي بعد مزامنة)/تذاكر/تصريح.
5. شاشة «الحسابات» و«وكلاء FTTH/خادمنا» تُحمّل (الآن تضرب الـVPS بتوكن إنتاج صالح).
6. تفعيل اختباري → قيد محاسبي + طباعة + واتساب (على مشترك اختباري).
7. **النافذة الموحّدة**: التفعيل يفتح نافذة واحدة (لا نافذتين) + الإجمالي يتحدّث حيّاً.
8. **الطباعة الصامتة**: بعد اختيار طابعة الإيصالات، التفعيل يطبع مباشرة **بلا حوار ويندوز**.
9. **نقطة واتساب**: `POST /api/sas-agent/accounts/{id}/subscription-logs/{logId}/whatsapp-sent` ← 200؛ وحالة الإرسال تظهر للمستخدم؛ و`IsWhatsAppSent` يُحدَّث عند الإرسال الفعلي.
10. CI: أضِف `dotnet test` + `pytest` (منع الانحدار).

---

## 8) ⚪ مصنوعات تطوير محلية — **لا تُنشَر**

- `run-local-dev.ps1` (سكربت تشغيل محلي، فيه سرّ محلي) — محلي فقط، غير مُلتزَم.
- `C:\SadaraPlatform\.dpkeys` (مفاتيح DataProtection محلية).
- حاوية `sadara-postgres-dev` (Postgres 5480 نسخة محلية).
- متغيّرات البيئة المثبّتة على مستوى المستخدم محلياً (`SADARA_INTERNAL_API_KEY`, `SADARA_SAS_INTERNAL_SECRET`, `DataProtection__KeysPath`).
- **🔴 احذف `src/Backend/API/Sadara.API/Controllers/SasDevController.cs`** (متحكّم محاكاة فوترة للاختبار — محصور بـ Development فيعيد 404 في الإنتاج، لكن يُفضّل حذفه قبل النشر).
- سجلّات الساس المحاكاة في القاعدة (`SubscriptionLogs WHERE Source=1 AND "FtthTransactionId" LIKE 'SIM-%'`) — بيانات اختبار محلية؛ لا تُرحَّل للإنتاج.

---

> **القاعدة الذهبية:** كل عملية على الإنتاج تتطلّب موافقة صريحة. ابدأ بـ staging إن توفّر. راجع أيضاً `docs/SAS_AGENT_DEV_ROADMAP.md` و`docs/SAS_AGENT_BILLING_PARITY_PLAN.md`.
