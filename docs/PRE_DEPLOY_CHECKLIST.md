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

---

## 6) 🟢 تغييرات آمنة للإنتاج (لا تحتاج تراجعاً — للعلم فقط)

- تحصين عقد البوّابة↔الساس: `extra="forbid"` + `_IntFromAny` + `test_contract.py` (83 اختبار) — دفاعي، يُبقى.
- فوترة الساس (محاسبة موحّدة + طباعة + واتساب + سجل الحركات) — يُبقى.
- توحيد `ApiConfig.vpsBaseUrl` — في الإنتاج يعيد `https://api.ramzalsadara.tech` حرفياً (صفر تغيير سلوك إنتاجي).
- إصلاحات العقد (image_b64 · query · null · أسماء الحقول) — يُبقى.

---

## 7) 🟢 التحقّق بعد النشر

1. تطبيق الهجرتين + نسخة احتياطية سليمة.
2. الـsidecar يعمل (`GET /health` = 200) والباكند يصله.
3. تسجيل دخول موظّف → توجيه صحيح (وكيل/أدمن).
4. تبويبات الساس: الحسابات/لوحة/مشتركون (محلي بعد مزامنة)/تذاكر/تصريح.
5. شاشة «الحسابات» و«وكلاء FTTH/خادمنا» تُحمّل (الآن تضرب الـVPS بتوكن إنتاج صالح).
6. تفعيل اختباري → قيد محاسبي + طباعة + واتساب (على مشترك اختباري).
7. CI: أضِف `dotnet test` + `pytest` (منع الانحدار).

---

## 8) ⚪ مصنوعات تطوير محلية — **لا تُنشَر**

- `run-local-dev.ps1` (سكربت تشغيل محلي، فيه سرّ محلي) — محلي فقط، غير مُلتزَم.
- `C:\SadaraPlatform\.dpkeys` (مفاتيح DataProtection محلية).
- حاوية `sadara-postgres-dev` (Postgres 5480 نسخة محلية).
- متغيّرات البيئة المثبّتة على مستوى المستخدم محلياً (`SADARA_INTERNAL_API_KEY`, `SADARA_SAS_INTERNAL_SECRET`, `DataProtection__KeysPath`).

---

> **القاعدة الذهبية:** كل عملية على الإنتاج تتطلّب موافقة صريحة. ابدأ بـ staging إن توفّر. راجع أيضاً `docs/SAS_AGENT_DEV_ROADMAP.md` و`docs/SAS_AGENT_BILLING_PARITY_PLAN.md`.
