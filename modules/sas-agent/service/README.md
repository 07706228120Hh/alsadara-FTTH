# SAS Sidecar — خدمة الساس الداخلية

خدمة FastAPI نحيلة، **بلا حالة**، تعمل على `127.0.0.1:8100` حصراً.
تُنادى من بوّابة الصدارة .NET فقط — غير مكشوفة للإنترنت.

---

## الهدف

تستقبل اعتماد SAS4 (`serverUrl + username + password`) من .NET في كل طلب،
تناديه عبر عملاء SAS المجرَّبَين (`sas_client.py` / `sas_user_client.py`)،
وتعيد JSON خاماً. لا تحتفظ بأي حالة بين الطلبات.

---

## متغيّرات البيئة

| المتغيّر | الوصف | إلزامي؟ |
|---|---|---|
| `SADARA_SAS_INTERNAL_SECRET` | السرّ المشترك مع بوّابة .NET — يُرسَل في رأس `X-Internal-Secret` | **نعم (fail-closed)** |
| `SADARA_SAS_DOCS` | اضبطه على `1` لتفعيل `/docs` في بيئة التطوير | لا (افتراضي: مُخفى) |

**fail-closed:** إن لم يُضبط `SADARA_SAS_INTERNAL_SECRET`، تُرفض **كل** الطلبات بـ 503.

---

## التشغيل السريع

```bash
# 1. تثبيت الاعتمادات (من مجلد service/)
pip install -r requirements.txt

# 2. تعيين السرّ (مطلوب)
export SADARA_SAS_INTERNAL_SECRET="$(python -c 'import secrets; print(secrets.token_hex(32))')"

# 3. تشغيل الخدمة
bash run.sh          # Linux/macOS
# أو
run.bat              # Windows
```

الخدمة تستمع على `http://127.0.0.1:8100`.

---

## الأمان (fail-closed)

كل نقطة نهاية (عدا `/health`) تتطلّب رأس `X-Internal-Secret`.

- **SADARA_SAS_INTERNAL_SECRET غير مضبوط** → 503 (الخدمة ترفض كل الطلبات).
- **الرأس غائب أو خاطئ** → 401.
- المقارنة بـ `secrets.compare_digest` (زمن ثابت — لا timing attack).
- كلمات المرور/التوكنات لا تظهر في السجلات. كل استجابة SAS تمرّ عبر `_redact` قبل إعادتها.
- بلا حالة: لا توكنات SAS مخزَّنة — كل طلب يُنشئ جلسة مستقلّة.

---

## جسم الطلب الأساسي

كل النقاط (عدا `/health`) تتقبّل جسم JSON يحمل دائماً:

```json
{
  "serverUrl": "sas.isp.iq",
  "username":  "admin",
  "password":  "***"
}
```

---

## نقاط النهاية الكاملة

### داخلي

| المسار | الفعل | الوصف |
|---|---|---|
| `GET /health` | — | فحص الإقلاع (بلا مصادقة) |

---

### لوحة الوكيل والعمليات العامة

| المسار | حقول إضافية | رد .NET | وصف |
|---|---|---|---|
| `POST /login` | — | `{success, sessionHandle, message}` | تسجيل دخول SAS4 |
| `POST /dashboard` | — | `{subscribers:{…}, finance:{…}}` | لوحة الوكيل |
| `POST /subscribers` | `query:{page,count,search,sortBy,direction}` | JSON خام (index/user) | قائمة المشتركين |
| `POST /report` | `query:{page,count,search}` | JSON خام (index/manager) | تقرير الوكيل |
| `POST /packages` | — | JSON خام (list/profile/0) | قائمة الباقات |
| `POST /finance` | — | JSON خام (advancedDashboard/finance) | ملخّص مالي |
| `POST /system-health` | — | JSON خام (advancedDashboard/systemHealth) | صحّة النظام |
| `POST /renewal/candidates` | `days?:int=7, query?:{}` | `[{id,username,name,expiry,profile}]` | مشتركون قريبو الانتهاء |
| `POST /renewal/bulk` | `subscriberIds:[], months?, profileId?, dryRun?` | `[{id,ok,message}]` | تجديد/تفعيل دفعة |
| `POST /online` | `query:{page,count,search}` | `{data,total,page,count}` مُنقَّى | المتصلون الآن |

---

### تفاصيل المشترك (قراءة)

| المسار | حقول إضافية | رد .NET | وصف |
|---|---|---|---|
| `POST /users/detail` | `uid:int` | JSON خام مُنقَّى (GET user/{id}) | كل بيانات مشترك |
| `POST /users/overview` | `uid:int` | JSON خام مُنقَّى (GET user/overview/{id}) | نظرة عامة |
| `POST /users/history` | `uid:int, page?, count?, sortBy?, direction?, search?` | JSON خام (POST index/UserHistory/{id}) | سجلّ المشترك |
| `POST /users/extend-data` | `uid:int, profile_id?:int` | `{extension:{…}, allowed_extensions:{…}\|null}` | بيانات التمديد |

---

### إجراءات المشترك (كتابة)

| المسار | حقول إضافية | رد .NET | وصف |
|---|---|---|---|
| `POST /users/action` | `uid:int, action:str, payload?:{}` | JSON خام من SAS | إجراء مفرد |
| `POST /users/bulk-action` | `action:str, user_ids:[int], payload?:{}` | `{action,total,ok,failed,results}` | إجراء جماعي (حدّ 300) |

الإجراءات المسموحة في `action`: `activate` · `extend` · `changeProfile` · `addTraffic` · `deposit` · `withdraw` · `ping` · `rename`

كل عنصر في `results` يحمل `{user_id, ok, error?}`.

---

### إنشاء / تعديل / حذف / استرداد

| المسار | حقول إضافية | رد .NET | وصف |
|---|---|---|---|
| `POST /users/create` | `payload:{username,password,…}` | JSON خام من SAS | إنشاء مشترك |
| `POST /users/update` | `uid:int, changes:{حقل:قيمة}` | JSON خام من SAS | تعديل مشترك (تحميل-دمج-حفظ) |
| `POST /users/delete` | `uid:int` | JSON خام من SAS | حذف مشترك |
| `POST /users/refund-data` | `uid:int` | JSON خام مُنقَّى | بيانات الاسترداد |
| `POST /users/refund` | `uid:int` | JSON خام من SAS | تنفيذ الاسترداد |

الحقول القابلة للتعديل في `/users/update`:
`enabled` · `profile_id` · `site_id` · `mac_auth` · `allowed_macs` · `firstname` · `lastname` · `company` · `email` · `phone` · `city` · `address` · `apartment` · `street` · `contract_id` · `national_id` · `notes` · `simultaneous_sessions` · `static_ip` · `auto_renew` · `user_type` · `expiration` · `password`

---

### الوكلاء (managers)

| المسار | حقول إضافية | رد .NET | وصف |
|---|---|---|---|
| `POST /managers` | `query:{page,count,search}` | `{data,total,page,count}` | قائمة الوكلاء |
| `POST /managers/action` | `mid:int, action:str, payload?:{}` | JSON خام من SAS | إجراء على وكيل |
| `POST /managers/delete` | `mid:int` | JSON خام من SAS | حذف وكيل |

الإجراءات المسموحة في `/managers/action`:
`deposit` · `withdraw` · `addRewardPoints` · `deductRewardPoints` · `payDebt` · `add` · `edit` · `rename`

---

### ملخّص مشتركين محلي رخيص — POST /subscribers/summary

نقطة قراءة **بلا أي نداء SAS4** — تحسب الإحصاءات من `local_subscribers` (المزامَن مسبقاً) مباشرةً.
آمنة للاستدعاء الدوري (auto-refresh).

#### طلب /subscribers/summary

```json
POST /subscribers/summary
X-Internal-Secret: <secret>

{ "accountId": "uuid-of-sas-account" }
```

#### استجابة /subscribers/summary

```json
{
  "total":   150,
  "active":  120,
  "expired": 30,
  "online":  45,
  "expiry": {
    "overdue": 10,
    "today":    3,
    "soon3":    8,
    "soon7":   18
  },
  "last_sync": "2026-10-01 09:45:00"
}
```

حساب فارغ (لا مزامنة بعد أو `account_id` غير موجود) → كل الأصفار و `last_sync: null` بلا خطأ.

#### مصادر الحسابات

| الحقل | المصدر | الملاحظة |
|---|---|---|
| `total` | `COUNT(*)` من `local_subscribers WHERE account_id=?` | — |
| `active` | `COUNT(status='active')` | كما في آخر مزامنة |
| `expired` | `COUNT(status='expired')` | كما في آخر مزامنة |
| `online` | `COUNT(online=1)` | كما في آخر مزامنة (ليس حيّاً) |
| `expiry.*` | `_expiry_counts(expirations)` — نفس منطق `/sync` | تُعيد: overdue/today/soon3/soon7 |
| `last_sync` | `MAX(synced_at)` من سجلّات الحساب | null إن لا سجلّات |

#### أمان /subscribers/summary وعزله

- **fail-closed:** يتطلّب `X-Internal-Secret` (مثل كل النقاط).
- **عزل صارم:** الاستعلام `WHERE account_id = ?` — لا يمكن الوصول لبيانات حساب آخر.
- **لا SASClient:** لا استيراد ولا نداء لأي عميل SAS — SQLite فقط.
- منطق حساب `expiry` مُستخرَج في دالة مشتركة `_expiry_counts` ويُستدعى أيضاً من `/sync` و `/subscribers/local` — لا تكرار.

---

### البروكسي العام المقيَّد بقائمة بيضاء

| المسار | حقول إضافية | رد .NET | وصف |
|---|---|---|---|
| `POST /sas/get` | `path:str` | JSON خام مُنقَّى | GET مقيَّد بـ `_GET_ALLOW` |
| `POST /sas/post` | `path:str, payload?:{}` | JSON خام مُنقَّى | POST مقيَّد بـ `_POST_ALLOW` |

أي مسار خارج القائمة يُرفض بـ 400.

#### _GET_ALLOW (قراءة)
`auth` · `user/{id}` · `user/overview/{id}` · `user/activationData/{id}` · `user/extensionData/{id}` · `user/refundData/{id}` · `user/refund/{id}` · `allowedExtensions/{id}` · `mac/{id}` · `customRadiusAttribute/user/{id}` · `list/profile/{id}` · `site` · `manager/tree` · `usersReport/summary` · `usersReport/perManager` · `usersReport/map` · `syslog/events` · `resources/menu` · `resources/languages` · `resources/language/{lang}` · `advancedDashboard/(subscribers|finance|systemHealth|CpuUsage|MemoryUsage|DiskUsage)`

#### _POST_ALLOW (قوائم بترقيم/تقارير)
`index/UserHistory/{id}` · `index/UserJournal/{id}` · `index/UserSessions[/{id}]` · `index/UserInvoices[/{id}]` · `index/UserReceipts/{id}` · `index/UserDocuments/{id}` · `index/Quota/{id}` · `user/traffic` · `userNetworksTraffic` · `index/activations` · `index/ManagerInvoices[/{id}]` · `index/ManagerReceipts[/{id}]` · `index/ManagerJournal[/{id}]` · `index/ManagerDebtsJournal` · `index/dataExportJob` · `report/depodrawal` · `report/activations` · `report/profits` · `usersReport/registration` · `usersReport/perProfile` · `index/userauthlog` · `index/syslog`

---

## نقاط التذاكر المحلية (tickets) — تخزين SQLite بلا نداء SAS

جميع النقاط:

- POST فقط (جسم JSON).
- تتطلب `X-Internal-Secret` (fail-closed مع بقية الخدمة).
- لا اعتماد SAS — كل العمليات على SQLite المحلية فقط.
- العزل الصارم: كل استعلام يحمل `WHERE company_id = ? AND owner_user_id = ?`.

### جداول SQLite الجديدة

#### tickets

| العمود | النوع | وصف |
|---|---|---|
| `id` | INTEGER PK AUTOINCREMENT | معرّف التذكرة |
| `company_id` | TEXT NOT NULL | معرّف الشركة |
| `owner_user_id` | TEXT NOT NULL | معرّف الوكيل المالك |
| `subscriber_ref` | TEXT | مرجع المشترك (اختياري) |
| `subject` | TEXT NOT NULL | عنوان التذكرة |
| `body` | TEXT | نصّ التذكرة |
| `category` | TEXT | `complaint\|outage\|billing\|speed\|other` |
| `priority` | TEXT | `low\|normal\|high\|urgent` |
| `status` | TEXT | `open\|in_progress\|resolved\|closed` |
| `created_by` | TEXT | اسم المُنشئ |
| `created_at` | TEXT | ISO UTC |
| `updated_at` | TEXT | ISO UTC (يُحدَّث عند كل رد أو تعديل) |

#### ticket_replies

| العمود | النوع | وصف |
|---|---|---|
| `id` | INTEGER PK AUTOINCREMENT | معرّف الرد |
| `ticket_id` | INTEGER FK → tickets.id | التذكرة المرتبطة |
| `body` | TEXT NOT NULL | نصّ الرد |
| `is_internal` | INTEGER 0/1 | ردّ داخلي (لا يُعرض للمشترك) |
| `author` | TEXT | اسم صاحب الرد |
| `created_at` | TEXT | ISO UTC |

### نقاط النهاية

| المسار | جسم الطلب | الرد |
|---|---|---|
| `POST /tickets/stats` | `{companyId, ownerUserId}` | `{total, open, in_progress, resolved, closed}` |
| `POST /tickets/list` | `{companyId, ownerUserId, status?, category?, search?, page?, count?}` | `{total, page, count, tickets:[…]}` |
| `POST /tickets/create` | `{companyId, ownerUserId, subject, body?, category?, priority?, subscriber_ref?, created_by?}` | التذكرة المُنشأة |
| `POST /tickets/get` | `{companyId, ownerUserId, ticket_id}` | التذكرة + ردودها (is_internal مخفية) |
| `POST /tickets/reply` | `{companyId, ownerUserId, ticket_id, body, is_internal?, author?}` | `{id, ticket_id, status}` |
| `POST /tickets/update` | `{companyId, ownerUserId, ticket_id, status?, priority?, category?}` | التذكرة المحدَّثة |

### سلوكيات تلقائية

- ردّ عام (`is_internal=false`) على تذكرة `open` ينقلها إلى `in_progress`.
- `ticket_id` في get/reply/update يُتحقَّق منه مقابل `company_id + owner_user_id` — 404 إن لم يتطابق (لا 403 — لا يكشف وجود تذاكر آخرين).
- الردود الداخلية (`is_internal=1`) لا تُعاد في `/tickets/get`.

---

## ملخّص وكلاء الشركة (البلنك الموحّد) — POST /admin/agents-summary

نقطة **إدارية** مُجمِّعة تُعيد صورة شاملة لمجموعة حسابات تخصّ شركة واحدة.

### الأمان والعزل

- تتطلّب `X-Internal-Secret` (fail-closed مثل بقية الخدمة).
- **العزل الصارم**: كل استعلام SQL يحمل `WHERE company_id = ? AND account_id IN (…)` — بيانات حساب خارج الشركة مستحيلة هيكلياً.
- أي `account_id` في القائمة لا يملك سجلّات محلية أو تصاريح للشركة المُحدَّدة يُتجاهَل (لا يظهر في `items`).
- حدّ 500 معرّف في الطلب الواحد — يتجاوزه يُقلَّص بصمت.

### عقد الطلب

```json
POST /admin/agents-summary
X-Internal-Secret: <secret>

{
  "companyId":  "uuid-or-id-of-company",
  "accountIds": ["uuid-acc-1", "uuid-acc-2", "…"]
}
```

### عقد الاستجابة

```json
{
  "items": [
    {
      "account_id":      "uuid-acc-1",
      "declared_total":  120,
      "declared_active": 98,
      "actual_total":    115,
      "actual_active":   102,
      "diff":            5,
      "verdict":         "matched",
      "last_sync":       "2026-09-30 14:22:00"
    },
    {
      "account_id":      "uuid-acc-2",
      "declared_total":  null,
      "declared_active": null,
      "actual_total":    80,
      "actual_active":   70,
      "diff":            null,
      "verdict":         "no_report",
      "last_sync":       "2026-09-28 09:10:00"
    }
  ]
}
```

### منطق الحكم (مُشترَك مع /reconciliation)

الحكم يُحسَب بدالة `_compute_verdict(declared, actual)` المُستخرَجة من `/reconciliation`:

| الحكم | الشرط |
|---|---|
| `matched` | `\|diff\| <= max(5, 5% من actual)` |
| `company_suspicious` | `diff > 0` — الوكيل يصرّح أكثر مما تُظهره السجلّات |
| `agent_suspicious` | `diff < 0` — السجلّات أكثر من تصريح الوكيل |
| `no_report` | لا تصريح مُقدَّم بعد |

### مصادر البيانات

| الحقل | المصدر |
|---|---|
| `declared_total` / `declared_active` | آخر صفّ في `agent_reports` للحساب ضمن الشركة |
| `actual_total` / `actual_active` | `COUNT / SUM` من `local_subscribers` مع `company_id + account_id` |
| `last_sync` | `MAX(synced_at)` من `local_subscribers` |

---

## نقاط العقارات المحلية (premises) — تخزين SQLite بلا نداء SAS

جميع النقاط:

- POST فقط (جسم JSON).
- تتطلّب `X-Internal-Secret` (fail-closed مع بقية الخدمة).
- لا اعتماد SAS — كل العمليات على SQLite المحلية فقط.
- العزل الصارم: كل استعلام يحمل `WHERE company_id = ? AND owner_user_id = ?`.
- تخصيص NPN ذرّي: `threading.Lock + commit` قبل تحرير القفل.
- حمولة QR: `SADARA|NPN:…|PIN:…|GEO:…`

### جداول SQLite — وحدة العقارات (premises)

#### premises

| العمود | النوع | وصف |
|---|---|---|
| `id` | INTEGER PK AUTOINCREMENT | معرّف العقار |
| `company_id` | TEXT NOT NULL | معرّف الشركة (عزل) |
| `owner_user_id` | TEXT NOT NULL | معرّف الوكيل المالك (عزل) |
| `npn` | TEXT | رقم العقار الوطني (11 خانة) |
| `npn_display` | TEXT | صيغة العرض GG-NNNN-NNNN-C |
| `iqpin` | TEXT | رمز الموقع (10 رموز) |
| `iqpin_display` | TEXT | صيغة العرض 3-3-4 |
| `gov_code` | INTEGER | كود المحافظة |
| `qr_payload` | TEXT | `SADARA\|NPN:…\|PIN:…\|GEO:…` |
| `lat` / `lon` | REAL | إحداثيات |
| `governorate` | TEXT | المحافظة |
| `area` | TEXT | الحي/المنطقة |
| `landmark` | TEXT | أقرب نقطة دالة |
| `phone` / `phone_norm` | TEXT | الهاتف الخام والمطبَّع |
| `ownership` | TEXT | `owned\|rent` |
| `ptype` | TEXT | `residential\|commercial` |
| `photo_path` | TEXT | مسار نسبي للصورة |
| `created_at` / `updated_at` | TEXT | ISO UTC |

#### premises_subscribers

| العمود | النوع | وصف |
|---|---|---|
| `id` | INTEGER PK AUTOINCREMENT | — |
| `premises_id` | INTEGER FK → premises.id | العقار |
| `subscriber_ref` | TEXT UNIQUE | مرجع الاشتراك (username) — اشتراك لعقار واحد |
| `linked_at` | TEXT | ISO UTC |

#### npn_counter

| العمود | النوع | وصف |
|---|---|---|
| `gov_code` | INTEGER PK | كود المحافظة |
| `last_seq` | INTEGER | آخر تسلسل مُخصَّص (يُزاد ذرّياً) |

### نقاط النهاية — وحدة العقارات

| المسار | جسم الطلب | الرد |
|---|---|---|
| `POST /premises/list` | `{companyId, ownerUserId, search?, ownership?, ptype?, page?, count?}` | `{premises:[…], total, page, count}` |
| `POST /premises/create` | `{companyId, ownerUserId, governorate, area, landmark, lat?, lon?, phone?, ownership?, ptype?}` | العقار المُنشأ |
| `POST /premises/get` | `{companyId, ownerUserId, premises_id}` | العقار + subscribers |
| `POST /premises/update` | `{companyId, ownerUserId, premises_id, governorate?, area?, …}` | العقار المحدَّث |
| `POST /premises/delete` | `{companyId, ownerUserId, premises_id}` | `{ok, unlinked}` |
| `POST /premises/photo/upload` | `{companyId, ownerUserId, premises_id, image_b64, ext}` | `{ok, has_photo}` |
| `POST /premises/photo/get` | `{companyId, ownerUserId, premises_id}` | FileResponse (الصورة مباشرةً) |
| `POST /premises/link` | `{companyId, ownerUserId, premises_id, subscriber_ref}` | `{ok, subscriber_count}` |
| `POST /premises/unlink` | `{companyId, ownerUserId, premises_id, subscriber_ref}` | `{ok, subscriber_count}` |
| `POST /premises/subscribers` | `{companyId, ownerUserId, premises_id}` | `{subscribers:[…], count}` |
| `POST /premises/by-subscriber` | `{companyId, ownerUserId, subscriber_ref}` | `{premises:{…}\|null}` |
| `POST /premises/link-candidates` | `{companyId, ownerUserId, search?, limit?}` | `{candidates:[…], count}` |

### ملاحظات تصميمية

- الصورة ترفع Base64 (لا multipart/form-data) — متوافق مع نمط JSON الموحّد في الخدمة.
- `/premises/photo/get` يعيد `FileResponse` مباشرةً (محتوى الصورة) — يمكن استبداله بمسار نسبي حسب حاجة العميل.
- عند تغيّر `lat`/`lon` في update: IQ-Pin وQR يُعادان حسابهما؛ NPN يبقى ثابتاً.
- عند ربط اشتراك (`link`) مرتبط بعقار آخر: يُنقَل تلقائياً (UNIQUE على subscriber_ref).
- `link-candidates` يبحث في `local_subscribers` (مزامَنة مسبقاً) — لا نداء SAS.

---

## _redact — حجب الأسرار

كل استجابة SAS تمرّ عبر `_redact` قبل إعادتها. المفاتيح المطابقة للنمط التالي تُستبدل بـ `"***"`:

```
password | secret | api_password | snmp_community | nas_details | pin
```

التطبيق: متكرّر على dict/list بأي عمق.

---

## تفاصيل نقاط التجديد

### `POST /renewal/candidates`

```json
// طلب
{ "serverUrl": "sas.isp.iq", "username": "admin", "password": "***",
  "days": 7, "query": {} }

// رد
[
  { "id": 42, "username": "user1", "name": "أحمد علي",
    "expiry": "2026-10-03 00:00:00", "profile": "10MB" }
]
```

### `POST /renewal/bulk`

```json
// طلب
{ "serverUrl": "sas.isp.iq", "username": "admin", "password": "***",
  "subscriberIds": [42, 43, 44], "months": 1, "dryRun": false }

// رد
[
  { "id": 42, "ok": true,  "message": "تمّ" },
  { "id": 43, "ok": false, "message": "SAS أعاد 404 …" }
]
```

- **idempotency:** `uuid5(NAMESPACE_URL, "{baseUrl}:{id}:{YYYYMMDDHHMM}")` — إعادة الطلب خلال الدقيقة ذاتها تُنتج نفس uuid.
- **dryRun:** لا نداء كتابي — يعيد `{ok:null, message:"[dryRun] سيُنفَّذ …"}`.
- **فشل جزئي:** الخطأ في مشترك واحد مُسجَّل في نتيجته ولا يوقف الدفعة.

---

## استيراد العملاء

```python
from integrations.sas_client import SASClient, SASError
from integrations.sas_user_client import SASUserClient
```

`app.py` يضبط `sys.path` لتشمل `../backend/app` — مصدر الحقيقة واحد.

---

## النشر بـ systemd

```ini
# /etc/systemd/system/sadara-sas-sidecar.service
[Unit]
Description=Sadara SAS Sidecar
After=network.target

[Service]
Type=simple
User=sadara
WorkingDirectory=/opt/sadara/modules/sas-agent/service
EnvironmentFile=/etc/sadara/sas-sidecar.env
ExecStart=/opt/sadara/venv/bin/python -m uvicorn app:app --host 127.0.0.1 --port 8100
Restart=on-failure
RestartSec=5
IPAddressAllow=127.0.0.0/8
IPAddressDeny=any

[Install]
WantedBy=multi-user.target
```
