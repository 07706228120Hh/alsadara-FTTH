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

## نقاط النهاية

كل النقاط تتطلّب رأس `X-Internal-Secret` مطابقاً للمتغيّر البيئي.

| المسار | الفعل | الوصف | مطابق لـ .NET |
|---|---|---|---|
| `GET /health` | — | فحص الإقلاع (بلا مصادقة) | — |
| `POST /login` | `{serverUrl, username, password}` | تسجيل دخول SAS4 | `LoginAsync` |
| `POST /dashboard` | `{serverUrl, username, password}` | لوحة الوكيل (subscribers + finance) | `GetDashboardAsync` |
| `POST /subscribers` | `{serverUrl, username, password, query:{page,count,search,…}}` | قائمة مشتركي الوكيل | `GetSubscribersAsync` |
| `POST /report` | `{serverUrl, username, password, query:{page,count,…}}` | تقرير الوكيل (المديرون/البلنك) | `GetReportAsync` |
| `POST /packages` | `{serverUrl, username, password}` | قائمة باقات/بروفايلات SAS4 (JSON خام) | `GetPackagesAsync` |
| `POST /finance` | `{serverUrl, username, password}` | ملخّص مالي `advancedDashboard/finance` (JSON خام) | `GetFinanceAsync` |
| `POST /system-health` | `{serverUrl, username, password}` | صحّة النظام `advancedDashboard/systemHealth` (JSON خام) | `GetSystemHealthAsync` |
| `POST /renewal/candidates` | `{serverUrl, username, password, days?:int=7, query?:{}}` | المشتركون المنتهي اشتراكهم خلال `days` يوماً — مرتَّبون تصاعدياً حسب الانتهاء — `[{id,username,name,expiry,profile}]` | `GetRenewalCandidatesAsync` |
| `POST /renewal/bulk` | `{serverUrl, username, password, subscriberIds:[], months?:int, profileId?, dryRun?:bool=false}` | تجديد/تفعيل دفعة مشتركين (idempotent بـ uuid5) — `[{id,ok,message}]` | `BulkRenewAsync` |

### تفاصيل نقطتَي التجديد

#### `POST /renewal/candidates`

```json
// طلب
{ "serverUrl": "sas.isp.iq", "username": "admin", "password": "***",
  "days": 7, "query": {} }

// رد  (مصفوفة — فارغة إن لا يوجد منتهٍ قريباً)
[
  { "id": 42, "username": "user1", "name": "أحمد علي",
    "expiry": "2026-10-03 00:00:00", "profile": "10MB" }
]
```

- يجلب كامل قائمة المشتركين عبر `iter_all("user")` (حتى 2000 سجل).
- يُحلَّل حقل `expiration` (أو `expire`) بصيغ: `YYYY-MM-DDTHH:MM:SS` · `YYYY-MM-DD HH:MM:SS` · `YYYY-MM-DD`.
- يُعيد المشتركين المنتهيين الآن + المنتهين خلال `days` يوماً.

#### `POST /renewal/bulk`

```json
// طلب
{ "serverUrl": "sas.isp.iq", "username": "admin", "password": "***",
  "subscriberIds": [42, 43, 44],
  "months": 1, "profileId": null, "dryRun": false }

// رد
[
  { "id": 42, "ok": true,  "message": "تمّ" },
  { "id": 43, "ok": false, "message": "SAS أعاد 404 على user/43/extend …" },
  { "id": 44, "ok": true,  "message": "تمّ" }
]
```

- **idempotency:** كل عملية تحمل `uuid5(NAMESPACE_URL, "{baseUrl}:{id}:{YYYYMMDDHHMM}")` — إعادة الطلب خلال نفس الدقيقة تُنتج نفس uuid فترفضها SAS4 دون تأثير.
- **dryRun:** يعيد `[{id, ok:null, message:"[dryRun] سيُنفَّذ …"}]` دون أي نداء كتابي.
- **فشل جزئي:** الخطأ في مشترك واحد يُسجَّل في نتيجته ولا يوقف الدفعة.

---

## الأمان

- **loopback only:** uvicorn يُقيَّد بـ `--host 127.0.0.1` — لا يقبل اتصالاً خارجياً.
- **X-Internal-Secret:** مقارنة بـ `secrets.compare_digest` (زمن ثابت — لا timing attack).
- **بلا تسجيل اعتماد:** كلمات المرور والتوكنات لا تظهر في السجلات أبداً.
- **بلا حالة:** لا توكنات SAS مخزَّنة — كل طلب يُنشئ جلسة SAS مستقلّة ويُغلقها.

---

## استيراد العملاء

بدلاً من نسخ الملفين، تضبط `app.py` مسار `sys.path` لتشمل
`../backend/app` وتستورد منه مباشرةً:

```python
from integrations.sas_client import SASClient, SASError
from integrations.sas_user_client import SASUserClient
```

**لماذا هذا أنظف من النسخ:** مصدر الحقيقة واحد — أي تعديل على عملاء SAS
يُطبَّق تلقائياً على الخدمة دون تزامن يدوي.

---

## النشر بـ systemd (للإنتاج — خطوات فقط، لا تنفيذ فعلي هنا)

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
# منع الوصول لخارج loopback على مستوى systemd (طبقة دفاع إضافية)
IPAddressAllow=127.0.0.0/8
IPAddressDeny=any

[Install]
WantedBy=multi-user.target
```

```bash
# ملف البيئة (محمي بـ chmod 600 + chown sadara)
# /etc/sadara/sas-sidecar.env
SADARA_SAS_INTERNAL_SECRET=<سرّ قوي مولَّد بـ secrets.token_hex(32)>
```

```bash
# تفعيل وتشغيل
systemctl daemon-reload
systemctl enable --now sadara-sas-sidecar
systemctl status sadara-sas-sidecar
```

---

## فجوات العقد المتبقية

| البند | الوضع |
|---|---|
| `/dashboard` يعيد `{subscribers, finance}` مُدمَجَين بدلاً من JSON واحد خام | الصدارة .NET تتوقّع `string` خاماً — إن احتاجت نشاطاً محدداً فالتوافق يستلزم تعديلاً في `SasServiceClient.cs` |
| `/report` يعيد بيانات `index/manager` — ليس تقرير مالي مخصَّصاً | SAS4 لا يوفّر نقطة نهاية «تقرير وكيل» موحّدة؛ يُستكمل حين تُحدَّد البنية المطلوبة |
| `/renewal/bulk` يستخدم `/admin/api/` مباشرةً (SASClient) بدلاً من بوابة المشترك | SAS4 يمدّد المشترك عبر `/admin/api/user/{id}/extend` و`/activate` إداريّاً — هذا السلوك الصحيح للوكيل/المدير. `SASUserClient` متاح لو احتاجت نقاط بوابة المشترك في المستقبل |
