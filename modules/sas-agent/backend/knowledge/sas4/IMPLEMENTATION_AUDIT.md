# تدقيق التطبيق مقابل مرجع SAS4 (حالة 2026-09-28)

تدقيق دقيق حقلاً-بحقل بين كودنا و`sas4_api_full_reference.md` (الـ66 نقطة، مستخرجة من مجموعة
Postman الرسمية). الهدف: تثبيت التطابق قبل التدقيق الحيّ (م5) دون الحاجة لخادم حقيقي.

## المصادر المحفوظة في المشروع
- `sas4_api_full_reference.md` — المرجع البشري الكامل (66 نقطة: method/url/auth/الحمولة/عيّنة الاستجابة). **هو النسخة المحفوظة من مجموعة Postman** (نفس البيانات، أوضح للمطوّر).
- `sas4_api_reference_ar.html` — نسخة HTML عربية.
- `README.md` — خريطة التغطية (أي نقطة نفّذها أي مسار عندنا).
- هذا الملف — التدقيق الحقلي + الإصلاحات المطبّقة.

## 1) حجب الأسرار (أُصلح ✅)
استجابة المتصلين `index/online` (#49) تُعيد `nas_details` بداخله **secret / api_password /
snmp_community**، و`user/overview` (#40) يُعيد **password المشترك صريحاً**. كانت تصل للتطبيق
بلا حجب في مسارات الأدمن/الوكيل.
- **الإصلاح:** أُضيف `_redact` إلى [sas_panel.py](../../app/api/sas_panel.py) (مثيل نظيره في
  `portal_sas.py`) ويُطبَّق على: `users`، `user/{id}`، `user/overview`، `online`، والبروكسي
  العامّ `get`/`post`. أي مفتاح يطابق `(password|secret|api_password|snmp_community|nas_details|\bpin\b)`
  → `"***"` (nas_details يُحجب كاملاً).
- اختباران جديدان: `test_online_redacts_nas_secrets` · `test_user_overview_redacts_password`.

## 2) مواءمة حمولات الإجراءات المالية (أُصلح ✅ — تحوّطياً)
الباكند `POST .../sas/users/{uid}/action` تمرير أمين (يحقن `user_id` فقط)؛ فأسماء الحقول
مسؤولية الواجهة. طابقنا [sas_subscriber_detail.dart](../../../packages/platform_core/lib/src/screens/sas_subscriber_detail.dart)
على الأسماء الموثّقة + أضفنا `transaction_id` (يمنع التكرار) مع إبقاء المرادفات القديمة تحوّطاً:

| الإجراء | # | الحقول الموثّقة | ما نرسله الآن |
|---|---|---|---|
| activate | 29 | method, money_collected, comments, issue_invoice, transaction_id | method:credit + money_collected + transaction_id (+profile_id) |
| addTraffic | 30 | username, amount, target:`rxtx_mbytes`, transaction_id | amount + target + username + transaction_id (+value/traffic) |
| extend | 33 | profile_id, method, transaction_id | method:credit + transaction_id + profile_id (+periods/count) |
| changeProfile | 34 | profile_id, method, transaction_id | profile_id + method:credit + transaction_id |
| deposit | 35 | user_username, amount, comment, transaction_id | user_username + amount + comment + transaction_id |
| withdraw | 36 | user_username, amount, comment, transaction_id | user_username + amount + comment + transaction_id |
| rename | 27 | new_username | new_username ✓ (مطابق أصلاً) |

`method:'credit'` = التفعيل/الدفع من رصيد المدير (الافتراض الأنسب للوكيل). عند التدقيق الحيّ:
إن رفض الخادم قيمةً، بدّلها (`reward_points`/`card`) أو صحّح الاسم، والمرادفات القديمة تبقى حمايةً.

## 3) بنود تحتاج تأكيداً حيّاً (م5)
- **ping (#51)** يتطلّب `radacctid` (من جلسة online) + `username`؛ زرّ ping في تفاصيل المشترك
  قد لا يملك `radacctid` إن لم يكن المشترك متصلاً — استخدمه من قائمة المتصلين.
- **بوابة المشترك (#6–#22):** أسماء حقول `SASUserClient` من التوثيق حرفياً؛ بعض النسخ تختلف —
  تُثبّت عند أول تشغيل حيّ عبر «إعداد الاتصال».
- **register (#7):** مؤجّل (لا تسجيل ذاتي مطلوب حالياً).

## 4) التغطية الإجمالية
واجهة الإدارة (#1–#5, #23–#66) + بوابة المشترك (#6–#22) منفّذة. التفصيل في `README.md`.
الأمان: قراءة=viewer، كتابة=operator، عزل نطاق الوكيل على كل نقطة، وحجب الأسرار (بند 1).
