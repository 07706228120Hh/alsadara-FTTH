# مرجع واجهة SAS4 API — SAS Radius v4 (Snono Systems)

> المصدر: توثيق Postman الرسمي «SAS4 for developers»
> (https://documenter.getpostman.com/view/11765341/U16byA2y) — استُخرج بالكامل (66 نقطة نهاية)
> ودُقّق حيّاً مقابل `demo4.sasradius.com` (v4.59.1). هذا هو المرجع المعتمد لكل تكامل SAS في المنصة.
> التنفيذ العملي: `backend/app/integrations/sas_client.py`.

---

## 1) الأساسيات

- **قاعدة لوحة الإدارة (Admin):** `http(s)://<host>/admin/api/index.php/api/`
- **قاعدة بوابة المستخدم (User Portal):** `http(s)://<host>/user/api/index.php/api/`
- **المصادقة:** JWT — `POST login` يُعيد `{status, token}`؛ كل طلب لاحق يحمل `Authorization: Bearer <token>`.
  في المتصفح يُخزَّن التوكن باسم `sas4_jwt` في localStorage. (كل نقطة نهاية تتطلب مصادقة عدا `login`.)
- **تشفير الحمولة (POST فقط):** جسم كل POST = `{"payload": "<AES>"}` حيث `<AES>` ناتج
  `CryptoJS.AES.encrypt(JSON.stringify(body), "abcdefghijuklmno0123456789012345")` —
  أي **AES-256-CBC بصيغة OpenSSL** (`Salted__` + salt(8) + ciphertext، ومفتاح/IV مشتقّان بـ EVP_BytesToKey/MD5).
  عبارة المرور ثابتة ومضمّنة في اللوحة (ليست سرّاً). فكّ التشفير بنفس العبارة.
- **أنواع البيانات:** String (UTF-8) · Number (صحيح) · Datetime (ISO8601، UTC+00:00) · Decimal (نقدي، خانتان عشريتان).

### الترقيم والفرز والبحث (لكل قوائم `index/<entity>` — POST)
معاملات الحمولة: `page` (رقم) · `count` (رقم) · `sortBy` (نص) · `direction` (`asc|desc`) · `columns` (مصفوفة أعمدة، اختياري) · `search` (نص بحث حر).
**مغلّف الاستجابة (Laravel paginator):**
```
current_page, data[], first_page_url, from, last_page, last_page_url,
next_page_url, path, per_page, prev_page_url, to, total
```
`data` مصفوفة السجلّات؛ `total` العدد الكلّي (استخدمه لإيقاف الترقيم).

---

## 2) المصادقة (Admin)

| العملية | الطريقة | المسار | الحمولة/الإخراج |
|---|---|---|---|
| تسجيل الدخول | POST | `login` | in: `{username, password}` → out: `{status, token}` |
| معلومات التوكن | GET | `auth` | out: `{status, client, permissions, features, license_status, license_expiration}` |

`Get Token Information` مفيد للمنصة: يكشف صلاحيات مستخدم API والميزات المرخّصة وحالة/انتهاء الترخيص.

---

## 3) المشتركون (Users) — الأهم للمنصة

### القائمة — `POST index/user`
حمولة الترقيم أعلاه. كل عنصر في `data[]`:
```
id, username, firstname, lastname, city, phone, profile_id, balance, expiration,
last_online, parent_id, email, static_ip, enabled, company, notes,
simultaneous_sessions, address, contract_id, created_at, n_row, status,
online_status, used_traffic, parent_username, profile_details, daily_traffic_details
```
- `parent_id`/`parent_username` = **الوكيل (Manager)** المالك — أساس ربط المشترك بوكيله في التدقيق.
- `expiration` + `status` + `online_status` = حالة الاشتراك والاتصال.
- `profile_id`/`profile_details` = الباقة. `used_traffic`/`daily_traffic_details` = الاستهلاك.

### كل بيانات مشترك — `GET user/{id}`
```
id, username, profile_id, enabled, expiration, address, city, country, mac_auth,
static_ip, group_id, service, firstname, lastname, email, phone, company, apartment,
street, contract_id, parent_id, created_at, updated_at, deleted_at, last_ip_address,
last_online, user_type, created_by, national_id, simultaneous_sessions,
mikrotik_winbox_group, mikrotik_framed_route, mikrotik_addresslist,
mikrotik_ipv6_prefix, balance, notes, picture, pin_tries, site_id, gps_lat, ...
```
(`gps_lat`/`gps_lng`, `national_id`, `last_ip_address` مفيدة للخريطة والتدقيق.)

### نظرة عامة — `GET user/overview/{id}`
```
username, parent_username, profile_name, profile_id, expiration, status, created_at,
created_by, balance, password, firstname, lastname, phone, address, city, email,
remaining_rx, remaining_tx, ...
```

### إجراءات المشترك (POST ما لم يُذكر)
| العملية | الطريقة | المسار |
|---|---|---|
| إنشاء | POST | `user` → out `{status, message}` |
| إعادة تسمية | POST | `user/rename/{user_id}` |
| بيانات التفعيل | GET | `user/activationData/{user_id}` |
| تفعيل خدمة | POST | `user/activate` |
| إضافة ترافيك | POST | `user/addTraffic` |
| بيانات التمديد | GET | `user/extensionData/{id}` |
| باقات التمديد المسموحة | GET | `allowedExtensions/{profile_id}` |
| تمديد الخدمة | POST | `user/extend` |
| تغيير الباقة | POST | `user/changeProfile` |
| إيداع رصيد | POST | `user/deposit` |
| سحب رصيد | POST | `user/withdraw` |
| بيانات الإلغاء | GET | `user/refundData/{id}` |
| إلغاء/استرداد | GET | `user/refund/{id}` |
| حذف | DELETE | `user/{id}` |
| MAC | GET | `mac/{id}` |
| سمة Radius مخصّصة | GET | `customRadiusAttribute/user/{id}` |
| المواقع | GET | `site` |
| قائمة الباقات لمشترك | GET | `list/profile/{id}` → `[{id, name}]` |
| السجلّ (History) | POST | `index/UserHistory/{id}` → عناصر: `id, event, description, created_by_manager_id, created_at, manager_details, user_details` |
| القيود (Journal) | POST | `index/UserJournal/{id}` |
| ترافيك الشبكات | POST | `userNetworksTraffic` |
| ترافيك المشترك | POST | `user/traffic` |

---

## 4) المتصلون الآن (Online) — أساس كشف الدمج

### `POST index/online`
كل جلسة في `data[]` (حقول RADIUS accounting):
```
radacctid, nasipaddress, framedipaddress, profile_id, framedprotocol,
acctsessiontime, acctstarttime, acctinputoctets, acctoutputoctets, username,
callingstationid, calledstationid, fup, user_profile_name, user_profile_id,
status, oui, daily_usage_percentage, nas_details, user_details
```
- `nasipaddress` = جهاز NAS/BNG المُخدِّم · `framedipaddress` = IP المشترك · `callingstationid` = MAC/معرّف الطرف.
- **هذه الحقول هي مدخل «كشف الدمج»**: جلسات متزامنة على أكثر من `nasipaddress`، أو `framedipaddress`/`callingstationid` متعدّدة لنفس المشترك = مؤشرات Load Balancing/Bonding/Failover.
- إجراء إضافي: `POST user/ping`.

---

## 5) الوكلاء/المدراء (Managers) — أساس الوكلاء والتدقيق

| العملية | الطريقة | المسار | ملاحظات |
|---|---|---|---|
| قائمة مبسّطة | GET | `index/manager` | `[{id, username}]` |
| شجرة الملكية | GET | `manager/tree` | `[{id, parent_id, username}]` — هرم الوكلاء |
| قائمة كاملة | POST | `index/manager` | حقول كل وكيل ↓ |
| إضافة | POST | `manager` | حمولة ↓ |
| تعديل | POST | `manager/{id}` |  |
| حذف | DELETE | `manager/{id}` |  |
| إعادة تسمية | POST | `manager/{id}` |  |
| إيداع للوكيل | POST | `manager/deposit` |  |
| قروض/إيداع | POST | `manager/deposit` |  |
| سحب | POST | `manager/withdraw` |  |
| نقاط مكافأة (إضافة) | POST | `manager/addRewardPoints` |  |
| نقاط مكافأة (خصم) | POST | `manager/deductRewardPoints` |  |
| سداد دين | POST | `manager/payDebt` |  |

**حقول الوكيل (POST index/manager → data[]):**
```
id, username, firstname, lastname, city, phone, acl_group_id, balance, parent_id,
enabled, reward_points, created_at, discount_rate, users_count,
acl_group_details, parent_details
```
- **`users_count`** = عدد مشتركي الوكيل لدى الشركة — **هذا بالضبط رقم «ما تذكره الشركة» في تبويب التدقيق** (يُقارَن بما يذكره الوكيل).
- `parent_id` = الوكيل الأعلى (هرم). `balance`/`reward_points`/`discount_rate` = المالية.

**حمولة إضافة وكيل (Add Manager):**
```json
{"username":"...", "enabled":1, "password":"...", "confirm_password":"...",
 "acl_group_id":21, "parent_id":1, "firstname":"...", "lastname":"...",
 "company":null, "email":null, "phone":null, "city":null, "address":null,
 "notes":null, "subscriber_prefix":null, ...}
```

---

## 6) الباقات (Profiles)

| العملية | الطريقة | المسار | الإخراج |
|---|---|---|---|
| قائمة مبسّطة | GET | `list/profile/0` | `[{id, name}]` |

(`list/profile/{group_id}` يفلتر حسب المجموعة؛ `0` = الكل.)

---

## 7) موارد بعد المصادقة (Resources)

| العملية | الطريقة | المسار | الإخراج |
|---|---|---|---|
| اللغات المتاحة | GET | `resources/languages` | `[{id, name, direction, author, font}]` |
| ملف ترجمة | GET | `resources/language/{code}` | `{info, words}` |
| القوائم/الصلاحيات | GET | `resources/menu` | عناصر: `{name, title, icon, link, weight, parent, acl}` |

---

## 8) بوابة المستخدم (User Portal) — قاعدة `/user/api/index.php/api/`

نقاط نهاية موجّهة للمشترك النهائي (تطبيق/موقع الشركة للعملاء)، لا لإدارة المنصة، لكنها مرجع مفيد:

| العملية | الطريقة | المسار |
|---|---|---|
| دخول | POST | `auth/login` |
| تسجيل | POST | `register` |
| الفواتير | POST | `index/invoice` |
| تغيير الاشتراك | POST | `service` |
| جلسات المستخدم | POST | `index/session` |
| ترافيك المستخدم | POST | `traffic` |
| استبدال كود | POST | `redeem` |
| تفعيل اشتراك | POST | `user/activate` |
| تفعيل تمديد | POST | `user/extend` |
| تغيير كلمة المرور | POST | `user` |
| كلمات اللغة | GET | `resources/language/{code}` |
| تفاصيل وصلاحيات المستخدم | GET | `user` |
| معلومات الرصيد | GET | `dashboard` |
| الباقات/الخدمات | GET | `service` / `packages` |
| القوائم | GET | `resources/menu` |
| التمديدات | GET | `extensions/{id}` |

---

## 9) نقاط النهاية الجاهزة للّوحة (لوحة SAS الداخلية — مؤكَّدة حيّاً)

خارج توثيق Postman لكنها تُستدعى من لوحة SAS وتفيد الملخّصات (GET، بلا ترقيم):
- `advancedDashboard/subscribers` → `{status, data:{active, expired, expiring_today, expiring_soon, fup, managers, offline, online, total}}` — **صورة الشركة كاملة بطلب واحد** (تعتمده حالياً خدمة المزامنة).
- `advancedDashboard/finance` · `advancedDashboard/systemHealth` · `advancedDashboard/CpuUsage` · `advancedDashboard/MemoryUsage` · `advancedDashboard/DiskUsage`.

---

## 10) خريطة الاستخدام في المنصة (ما نسحبه ولأي تبويب)

| تبويب المنصة | نقطة SAS | الحقول المفتاحية |
|---|---|---|
| عام / اللوحة الوطنية | `advancedDashboard/subscribers` | total, active, online, expired, managers |
| الوكلاء | `POST index/manager` + `manager/tree` | username, users_count, parent_id, balance |
| التدقيق (وكيل مقابل شركة) | `index/manager.users_count` مقابل عدّ `index/user` حسب `parent_id` | فرق الأعداد لكل `@` |
| المشتركون | `POST index/user` (ترقيم) | username, parent_username, profile, expiration, status |
| كشف الدمج | `POST index/online` | nasipaddress, framedipaddress, callingstationid, acctsessiontime |
| الباقات | `list/profile/0` | id, name |
| المالية | `advancedDashboard/finance` + `user/deposit|withdraw` | balance |

> ملاحظة تنفيذ: النسخة الأولى من `sas_sync.py` تسحب `advancedDashboard/subscribers` فقط (ملخّص). التوسعة التالية: `index/manager` (الوكلاء + users_count) ثم `index/online` (كشف الدمج) ثم `index/user` (المشتركون بالترقيم).
