# SAS4 API — الحزمة المرجعية الكاملة (Snono Systems · SAS Radius v4)

> المصدر الرسمي: https://documenter.getpostman.com/view/11765341/U16byA2y ("SAS4 for developers")
> استُخرجت المجموعة الكاملة من Postman بتاريخ 2026-09-27: **9 مجلدات (تبويبات) · 66 طلباً** — كل وصف، كل حمولة، كل مثال استجابة، بلا اختصار.
> هذا المجلد هو **المرجع المعتمد** لأي تكامل SAS في تطبيق الوكلاء. أي endpoint غير موجود هنا = غير موثّق رسمياً.

## الملفات

| الملف | ما فيه | متى تستخدمه |
|---|---|---|
| `sas4_api_full_reference.md` | النسخة الكاملة الحرفية من Postman (المقدمة + المجلدات التسعة + 66 طلباً بأوصافها وحمولاتها وكل أمثلة الاستجابات كاملة) | عند تنفيذ أي endpoint جديد أو التحقق من حقل/استجابة |
| `sas4_api_reference_ar.html` | صفحة مرجعية عربية مشروحة (افتحها في المتصفح): كل endpoint بالعربي + الـ payload قبل التشفير + عينة استجابة + شرح التشفير + أكواد Dart/PHP/Python + مصفوفة عمليات المنصة + ملاحظات أمنية | للفهم السريع والتصميم |
| `../sas4_api_reference.md` | الملخص المختصر القديم المدقّق حيّاً على demo4 (v4.59.1) — يبقى كملاحظات تشغيل | ملاحظات ما تحقق منه فعلياً |
| `README.md` (هذا الملف) | الفهرس الكامل + قواعد الاتصال + خريطة التغطية في الكود | نقطة البداية |

## قواعد الاتصال (تنطبق على كل الطلبات)

- **واجهتان**: Admin API `/{host}/admin/api/index.php/api/…` (المدير/الوكيل) و User Portal `/{host}/user/api/index.php/api/…` (المشترك النهائي). الحقل `{{IP-or-Domain}}` في التوثيق = مضيف SAS الخاص بالشركة.
- **المصادقة**: `POST login` (Admin) أو `POST auth/login` (User Portal) → `{"status":200,"token":"<JWT>"}` ثم `Authorization: Bearer <token>` على كل الطلبات. الطلبات التي يظهر فيها `auth: (غير محدد)` في التوثيق تحتاج Bearer عملياً.
- **التشفير**: كل `POST` يُرسل بحقل واحد `payload` = `CryptoJS.AES.encrypt(JSON.stringify(data), KEY)` أي صيغة OpenSSL: `Base64("Salted__" + salt8 + AES-256-CBC(EVP_BytesToKey(MD5)))`. المفتاح المنشور رسمياً: `abcdefghijuklmno0123456789012345`. كل الحمولات في التوثيق تبدأ بـ `U2FsdGVkX1` لهذا السبب. التنفيذ المتوافق موجود في `backend/app/integrations/sas_client.py` (`sas_encrypt`/`sas_decrypt`).
- **الاستجابات**: JSON؛ القوائم بصيغة Laravel pagination (`current_page, data, per_page, total, next_page_url…`). قد يرجع HTTP 200 مع `status: -1` أو رسالة خطأ → افحص `status` داخل الجسم دائماً. الرسائل مفاتيح ترجمة `rsp_*` (تُترجم من `resources/language/{code}`).
- **معاملات القوائم** (داخل الـ payload): `page, count, sortBy, direction (asc/desc), search, columns[]`. التوثيق يكتب أحياناً `diraction` — الصحيح `direction`.
- **العمليات المالية** تحمل `transaction_id` (UUID تولّده أنت) لمنع التكرار؛ بوابة المشترك تستخدم `uuid` لنفس الغرض.

## الفهرس الكامل — 66 طلباً في 9 تبويبات

| # | Method | URL (كما في التوثيق) | الاسم |
|---|---|---|---|
| 1 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/login` | Access Granted Client Credentials |
| 2 | GET | `http://{{IP-or-Domain}}/admin/api/index.php/api/auth` | Get Token Information |
| 3 | GET | `http://{{IP-or-Domain}}/admin/api/index.php/api/resources/languages` | Available Transulations |
| 4 | GET | `http://{{IP-or-Domain}}/admin/api/index.php/api/resources/language/en` | Tansulation File |
| 5 | GET | `http://{{IP-or-Domain}}/admin/api/index.php/api/resources/menu` | Menus |
| 6 | POST | `http://{{IP-or-Domain}}/user/api/index.php/api/auth/login` | Login |
| 7 | POST | `http://{{IP-or-Domain}}/user/api/index.php/api/register` | Register |
| 8 | POST | `http://{{IP-or-Domain}}/user/api/index.php/api/index/invoice` | invoices |
| 9 | POST | `http://{{IP-or-Domain}}/user/api/index.php/api/service` | Change Subscription |
| 10 | POST | `http://{{IP-or-Domain}}/user/api/index.php/api/index/session` | User sessions |
| 11 | POST | `http://{{IP-or-Domain}}/user/api/index.php/api/traffic` | User traffic |
| 12 | POST | `http://{{IP-or-Domain}}/user/api/index.php/api/redeem` | Redeem code |
| 13 | POST | `http://{{IP-or-Domain}}/user/api/index.php/api/user/activate` | Activate user subscription |
| 14 | POST | `http://{{IP-or-Domain}}/user/api/index.php/api/user/extend` | Activate Subscription Extension |
| 15 | POST | `http://{{IP-or-Domain}}/user/api/index.php/api/user` | Change password |
| 16 | GET | `http://{{IP-or-Domain}}/user/api/index.php/api/resources/language/ar` | Language keywords |
| 17 | GET | `http://{{IP-or-Domain}}/user/api/index.php/api/user` | User Details & Permissions |
| 18 | GET | `http://{{IP-or-Domain}}/user/api/index.php/api/dashboard` | Balance Info |
| 19 | GET | `http://{{IP-or-Domain}}/user/api/index.php/api/service` | Profiles / Services |
| 20 | GET | `http://{{IP-or-Domain}}/user/api/index.php/api/packages` | Packages |
| 21 | GET | `http://{{IP-or-Domain}}/user/api/index.php/api/resources/menu` | Menus |
| 22 | GET | `http://{{IP-or-Domain}}/user/api/index.php/api/extensions/2` | Get Extensions |
| 23 | POST | `http://{{IP-or-Domain}}/admin/api/index.php/api/index/user` | Users List |
| 24 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/index/user` | Users List - with search |
| 25 | POST | `http://{{IP-or-Domain}}/admin/api/index.php/api/user` | User - Create |
| 26 | GET | `http://demo4.sasradius.com/admin/api/index.php/api/user/2` | User - All Data |
| 27 | POST | `http://{{IP-or-Domain}}/admin/api/index.php/api/user/rename/{{user_id}}` | User - Rename |
| 28 | GET | `http://{{IP-or-Domain}}/admin/api/index.php/api/user/activationData/{{user_id}}` | User - Activation Data |
| 29 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/user/activate` | User - Activation Service |
| 30 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/user/addTraffic` | User - Add Traffic |
| 31 | GET | `http://demo4.sasradius.com/admin/api/index.php/api/user/extensionData/3` | User - Extension Data |
| 32 | GET | `http://demo4.sasradius.com/admin/api/index.php/api/allowedExtensions/{{profile_id}}` | User - Extension Profiles |
| 33 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/user/extend` | User - Extend Service |
| 34 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/user/changeProfile` | User - Change Profile |
| 35 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/user/deposit` | User - Deposit |
| 36 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/user/withdraw` | User - Withdraw |
| 37 | GET | `http://demo4.sasradius.com/admin/api/index.php/api/user/refundData/2` | User - Cancel Data |
| 38 | GET | `http://demo4.sasradius.com/admin/api/index.php/api/user/refund/2` | User - Cancel Service |
| 39 | DELETE | `http://demo4.sasradius.com/admin/api/index.php/api/user/2` | User - Delete |
| 40 | GET | `http://demo4.sasradius.com/admin/api/index.php/api/user/overview/2` | User - Overview |
| 41 | GET | `http://demo4.sasradius.com/admin/api/index.php/api/mac/2` | User - MAC |
| 42 | GET | `http://demo4.sasradius.com/admin/api/index.php/api/customRadiusAttribute/user/2` | User - Custom Radius Attribute |
| 43 | GET | `http://demo4.sasradius.com/admin/api/index.php/api/site` | User - Site |
| 44 | GET | `http://demo4.sasradius.com/admin/api/index.php/api/list/profile/5` | User - List Profiles |
| 45 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/index/UserHistory/2` | User - History |
| 46 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/index/UserJournal/2` | User - Journal |
| 47 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/userNetworksTraffic` | User - Network Traffic |
| 48 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/user/traffic` | User - Traffic |
| 49 | POST | `http://185.95.184.10/admin/api/index.php/api/index/online` | Online Users List |
| 50 | POST | `http://185.95.184.10/admin/api/index.php/api/index/online` | Online Users List - with search |
| 51 | POST | `http://185.95.184.10/admin/api/index.php/api/user/ping` | Ping User |
| 52 | GET | `http://demo4.sasradius.com/admin/api/index.php/api/index/manager` | Managers - Simple List |
| 53 | GET | `http://demo4.sasradius.com/admin/api/index.php/api/manager/tree` | Managers - Tree |
| 54 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/index/manager` | Managers - List |
| 55 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/manager` | Add Manager |
| 56 | DELETE | `http://demo4.sasradius.com/admin/api/index.php/api/manager/{{ manager_id }}` | Delete Manager |
| 57 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/manager/{{ manager_id }}` | Update Manager |
| 58 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/manager/{{ manager_id }}` | Rename Manager |
| 59 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/manager/deposit` | Manager Deposit |
| 60 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/manager/deposit` | Manager - Deposit Loans |
| 61 | POST | `http://demo4.sasradius.com:/admin/api/index.php/api/manager/withdraw` | Managers - withdraw |
| 62 | GET | `(بدون URL)` | Managers - Add Reward Points |
| 63 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/manager/addRewardPoints` | Managers - Add Reward Points |
| 64 | POST | `http://demo4.sasradius.com:/admin/api/index.php/api/manager/deductRewardPoints` | Managers - Deduct Managers points |
| 65 | POST | `http://demo4.sasradius.com/admin/api/index.php/api/manager/payDebt` | Manager - Pay debt |
| 66 | GET | `http://demo4.sasradius.com/admin/api/index.php/api/list/profile/0` | Profiles - Simple List |
**ملاحظات على التوثيق الأصلي** (موجودة كما هي في الملف الكامل — لا تُصحَّح هناك):
- #62 نسخة GET بلا URL من "Add Reward Points" — خطأ توثيقي؛ الصحيح #63 (POST).
- #12 Redeem code وصفه منسوخ بالخطأ من Packages؛ وظيفته الفعلية تعبئة كرت بـ `pin`.
- #59 Manager Deposit وصفه يعرض payload قائمة بالخطأ؛ الشكل الصحيح كما في #60 مع `is_loan:false`.
- #15 Change password موثّق بأنه "bugged" بانتظار إصلاح.
- #38 Cancel Service (استرداد) و #37 عملية مالية بطلب **GET**.
- #49/#50 استجابة `index/online` تُرجع `nas_details` كاملاً بما فيه `secret`/`api_password`/`snmp_community` — احجبها قبل أي تخزين أو عرض.
- #40 Overview يُرجع كلمة مرور المشترك نصاً واضحاً.
- مجلد **Dashboard** فارغ رسمياً (0 طلبات). الطلبات `advancedDashboard/*` المستخدمة في الكود مأخوذة من لوحة SAS نفسها لا من هذا التوثيق.

## خريطة التغطية في كود تطبيق الوكلاء (حالة 2026-09-28 — محاكاة SAS كاملة)

**تحديث:** أُكملت المحاكاة لتغطّي واجهة الإدارة كاملةً + بوابة المشترك. الباكند:
`api/sas_panel.py` (إدارة) · `integrations/sas_user_client.py` + `api/portal_sas.py` (بوابة المشترك).
الواجهة: `sas_panel_screen`/`sas_subscriber_detail`/`sas_subscriber_form`/`sas_manager_form`/
`sas_license_screen` (إدارة) · `subscriber_portal_screen`/`sas_link_dialog` (مشترك).

| المجال | مُنفَّذ (باكند + واجهة) | ملاحظات |
|---|---|---|
| المصادقة | login (#1) · auth/رخصة/صلاحيات (#2) عبر `sasAuthInfo` + `SasLicenseScreen` | — |
| موارد الواجهة | menu (#5) · languages/language (#3/#4/#16) في القائمة البيضاء | — |
| المشتركون — قوائم/تفاصيل | index/user (#23/24), user/{id} (#26), overview (#40), UserHistory (#45), UserJournal (#46), traffic (#48), userNetworksTraffic (#47), mac (#41), customRadiusAttribute (#42), site (#43), extensionData (#31), activationData (#28), refundData (#37) | تبويب «متقدّم» يعرض MAC/Radius |
| المشتركون — عمليات | activate (#29), addTraffic (#30), extend (#33), changeProfile (#34), deposit (#35), withdraw (#36), rename (#27), ping (#51), delete (#39), **create (#25 نقطة صريحة + نموذج)**, **refund (#37/#38 حوار)** | إنشاء بلا حقن user_id |
| المتصلون | index/online (#49/50) + كشف الدمج | — |
| المدراء (الوكلاء) | index/manager (#52/54), tree (#53), **add (#55) + edit/rename (#57/58) نموذج**, deposit/loans (#59/60), withdraw (#61), reward points (#63/64), payDebt (#65), delete (#56) | محجوبة عن الوكيل |
| الباقات | list/profile/0 (#66) · list/profile/{uid} (#44) | — |
| **بوابة المشترك (User Portal)** | **login (#6), invoices (#8), change subscription (#9), sessions (#10), traffic (#11), redeem (#12), activate (#13), extend (#14), change password (#15), user (#17), balance (#18), service (#19), packages (#20), extensions (#22)** | `SASUserClient`؛ عرضٌ بمصدر مزدوج (بوابة/إدارة) + ربط لمرة واحدة + idempotency بـ transaction_id |
| register (#7) | مؤجّل (التسجيل الذاتي غير مطلوب) | — |
| لوحة | advancedDashboard/subscribers, finance, systemHealth (غير موثّقة رسمياً) | — |

> عند إضافة أي endpoint: خذ المسار والحمولة من `sas4_api_full_reference.md` حرفياً، ثم أضف ملاحظة التحقق الحي في `../sas4_api_reference.md`.

## ملاحظات حول عملية الاستخراج (2026-09-27)

- الاستخراج تم من مجموعة Postman الحيّة عبر المتصفح (`documenter.gw.postman.com/api/collections/11765341/U16byA2y`) — السيرفرات السحابية وبيئة الجهاز المحلية محجوبة عن هذا النطاق، لذا أي تحديث مستقبلي للتوثيق يُعاد استخراجه من المتصفح بنفس الطريقة.
- تُستبدل كل توكنات JWT في الأمثلة بـ `<JWT_TOKEN>` قبل الحفظ — لا تُخزَّن توكنات حقيقية في المستودع.
- **ملف JSON الخام للمجموعة** (`sas4_collection.json`، ~303 KB) لم يُحفظ لأن Chrome منع التنزيل الثاني التلقائي من نفس الموقع. الـ markdown الكامل يغطي المحتوى 100% (66/66 طلباً)، فلا حاجة له إلا عند الرغبة باستيراد المجموعة في Postman/Insomnia: يمكن تنزيله مباشرة من الرابط أعلاه أو السماح لـ Chrome بـ «تنزيلات متعددة» من documenter.getpostman.com ثم إعادة المحاولة.
- قد يظهر ملف فارغ `.git/index.lock` في جذر المشروع بعد تشغيل `git status` من بيئة Claude (نظام ملفات شبكي لا يسمح بحذفه). إن اشتكى git من «index.lock exists» احذفه يدوياً من ويندوز؛ لا يؤثر على أي ملف آخر.
- التحقق الذي أُجري على الملفات: عدد الطلبات في الـ markdown = 66 (مطابق للمصدر)، 9 مجلدات، الأقسام الطويلة (ملف الترجمة 676 مفتاحاً، قائمة المتصلين) كاملة غير مقتطعة، ولا توجد توكنات متبقية.
