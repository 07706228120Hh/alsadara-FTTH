# نقاط SAS4 المكتشَفة حيّاً (خارج التوثيق الرسمي الـ66)

مصدرها **التقاط شبكة لوحة SAS الحيّة** عبر «مستكشف SAS» المدمج في التطبيق (WebView2 يعترض
fetch/XHR)، على خادم مزوّد حقيقي (sas-safer.com، **v4.59.2**)، بتاريخ 2026-09-28.
الحمولات مشفّرة على السلك لكنها تُفكّ بمفتاح SAS المعروف. هذه النقاط **مؤكَّدة بالمسار
والاستجابة الفعليين** وتُستخدَم لقسم «التقارير» وتبويبات المشترك.

## قاعدة مهمة
مسارات القائمة الجانبية (`/report/sessions` …) هي **مسارات واجهة الويب**، ومسار الـ API
مختلف تماماً. النمط الفعلي: **القوائم عبر `index/{Entity}`** (بحرف كبير)، والتقارير
التجميعية عبر `report/{name}` أو `usersReport/{name}`. كلّها **POST** بحمولة قائمة
`{page, count, direction, search}` (بلا `sortBy:'id'` — بعض الجداول بلا عمود id فتُعيد 502).

## التقارير العامّة (قسم «التقارير») — مؤكَّدة ✅

| تقرير (قائمة SAS) | مسار API | أعمدة الاستجابة |
|---|---|---|
| التفعيلات | `index/activations` | created_at, price, activation_method, old/new_expiration, user_details{username,firstname,parent_username}, manager_details, profile_details |
| الجلسات | `index/UserSessions` | radacctid, username, nasipaddress, acctstarttime/stoptime, framedipaddress, callingstationid(MAC), acctinput/outputoctets, acctterminatecause |
| فواتير المشتركين | `index/UserInvoices` | invoice_number, type, amount, user_id, description, paid, payment_method, manager_details, user_details |
| فواتير المدراء | `index/ManagerInvoices` | invoice_number, type, amount, description, payment_method, issuer_details, owner_details |
| السجل المالي | `index/ManagerJournal` | created_at, amount, operation, balance, cr, dr, crid, drid |
| إيصالات المدراء | `index/ManagerReceipts` | receipt_number, type, amount, description, manager_details |
| سجل الديون | `index/ManagerDebtsJournal` | (كسجل مالي؛ فارغ غالباً) |
| انتقال الأموال | `report/depodrawal` | cr, dr, amount, comment, operation, cr_manager, dr_manager |
| محاولات الدخول | `index/userauthlog` | username, reply(Access-Accept/Reject), created_at, mac, nas_ip_address |
| سجل النظام | `index/syslog` | event, description, created_by, ip, manager_details |
| تصدير البيانات | `index/dataExportJob` | مهام التصدير |

## تبويبات المشترك (index/{Entity}/{userId}) — مؤكَّدة ✅

`index/UserSessions/{id}` (جلساته) · `index/UserInvoices/{id}` (فواتيره) ·
`index/UserReceipts/{id}` (إيصالاته) · `index/UserHistory/{id}` (سجله) ·
`index/UserJournal/{id}` (سجله المالي) · `index/UserDocuments/{id}` (وثائقه) ·
`index/Quota/{id}` (حصصه) · `user/traffic` (استهلاكه، مصفوفات 31 يوماً rx/tx/total).

## تقارير تجميعية (شكل مختلف — ليست قوائم صفوف)

- `report/activations` → `{profiles[], data:[{day, profile_id, total}]}` (إحصائيات التفعيل)
- `report/profits` → `{commissions[], activations[]}` (الأرباح)
- `usersReport/summary` (GET) → `{total, active, expired}`
- `usersReport/perManager` (GET) → لكل مدير
- `usersReport/perProfile` (POST) → لكل باقة
- `usersReport/registration` (POST) → التسجيل الشهري

## نقاط مساعدة أخرى مكتشَفة

`auth` (GET: صلاحيات الوكيل + رصيده) · `dashboard` (GET: widgets) ·
`widgetData/internal/{name}` (GET: عدّادات لحظية wd_users_count=455…) ·
`manager/tree`, `manager/overview/{id}`, `manager/{id}`, `manager/ppp/{id}`, `index/acl`,
`nas` (GET: قائمة الـNAS) · `syslog/events` (GET: أنواع الأحداث للفلترة) ·
`resources/menu` (بنية القائمة) · `resources/forms` (تعريفات النماذج) ·
`resources/login` (إعداد صفحة الدخول).

> ملاحظة: عنوان الخادم المخزَّن بصيغة `sas-safer.com:` (بنقطتين وبمنفذ فارغ) — يعمل.
