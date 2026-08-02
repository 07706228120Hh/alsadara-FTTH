# نسخة محلية مطابقة لقاعدة الإنتاج (Local DB Mirror)

الهدف: الاحتفاظ بنسخة محلية على جهاز التطوير مطابقة لقاعدة الإنتاج `sadara_db`
(على `72.61.183.61`)، بحيث لو انمسحت قاعدة الإنتاج تبقى النسخة المحلية سليمة
ويمكن القراءة منها.

آخر تحديث: 2026-08-02

---

## ⚠️ حقيقة تقنية أساسية (اقرأها أولاً)

**الـ Replication وحده لا يحميك من المسح.** أي `DELETE` / `TRUNCATE` / `DROP DATABASE`
على الإنتاج يُنسخ حرفياً إلى النسخة الحيّة فيُمحى منها أيضاً. الحماية الحقيقية ضد
المسح والخطأ البشري هي **النسخ المجمّدة (snapshots) عبر `pg_dump`** المحفوظة كأرشيف.

لذلك يعتمد هذا الحل تصميماً هجيناً:

| المرحلة | الأداة | تحمي من | الحالة |
|---------|--------|---------|--------|
| **1 — نسخ مجمّدة كل 6 ساعات** | `pg_dump`/`pg_restore` | المسح، الحذف، الخطأ البشري، تلف السيرفر | ✅ جاهزة |
| **2 — نسخة حيّة (Logical Replication)** | native logical replication | قراءة شبه-لحظية فقط (ليست حماية من المسح) | ⏸ تحتاج موافقة |

**شبكة الأمان الحقيقية هي المرحلة 1.** المرحلة 2 إضافية للقراءة الحيّة فقط.

---

## البيئة (مُتحقَّق منها)

- الإنتاج: PostgreSQL **16.14** (Ubuntu 24.04)، قاعدة `sadara_db`، الحجم ~304 MB.
  - `wal_level=replica` حالياً، `max_replication_slots=10`، `max_wal_senders=10`.
- المحلي: PostgreSQL **16.13** يعمل كخدمة `postgresql-x64-16` على المنفذ 5432
  (يطابق الإصدار الرئيسي للسيرفر — ضروري للاستعادة وللـ replication).
- SSH إلى السيرفر يعمل بالمفاتيح (بدون كلمة مرور).
- المصادقة المحلية: `scram-sha-256` (تحتاج كلمة مرور عبر `pgpass.conf`).

---

## المرحلة 1 — النسخ المجمّدة (جاهزة)

### ملفات الحل

| الملف | الوظيفة |
|-------|---------|
| `scripts/setup_db_mirror_pgpass.ps1` | إعداد كلمة مرور postgres المحلي مرّة واحدة (بأمان، لا تظهر) |
| `scripts/db_mirror_sync.ps1` | المزامنة: dump على السيرفر → تنزيل → استعادة محلية + أرشفة |
| `scripts/register_db_mirror_task.ps1` | جدولة المزامنة كل 6 ساعات (Windows Task Scheduler) |

### آلية العمل (`db_mirror_sync.ps1`)

1. `pg_dump -Fc -Z6` على السيرفر (قراءة فقط، لا يمسّ الإنتاج).
2. `scp` تنزيل ملف `.dump` إلى `C:\SadaraBackups\db\`.
3. حذف الملف المؤقت من السيرفر.
4. استعادة في قاعدة `sadara_db_mirror_staging` ثم **تبديل ذرّي** إلى `sadara_db_mirror`
   (لو فشلت الاستعادة يبقى الـ mirror القديم سليماً).
5. الاحتفاظ بآخر **28 نسخة** (= 7 أيام × 4 نسخ/يوم) وحذف الأقدم.

### خطوات التشغيل (مرّة واحدة)

```powershell
# 1) إعداد كلمة مرور postgres المحلي (تُدخَل مخفية، لا تُخزَّن في المحادثة)
powershell -ExecutionPolicy Bypass -File scripts\setup_db_mirror_pgpass.ps1

# 2) أول مزامنة يدوية للتأكد
powershell -ExecutionPolicy Bypass -File scripts\db_mirror_sync.ps1

# 3) الجدولة التلقائية كل 6 ساعات (يُفضّل PowerShell كـ Administrator)
powershell -ExecutionPolicy Bypass -File scripts\register_db_mirror_task.ps1
```

### القراءة من النسخة المحلية

```powershell
& "C:\Program Files\PostgreSQL\16\bin\psql.exe" -h 127.0.0.1 -U postgres -d sadara_db_mirror
```

### الاستعادة الكاملة لو انمسح الإنتاج

كل ملف `.dump` في `C:\SadaraBackups\db\` نسخة كاملة مستقلّة. لاستعادتها إلى أي
PostgreSQL (محلي أو سيرفر جديد):

```bash
createdb sadara_db
pg_restore --no-owner --no-privileges -d sadara_db  sadara_db_YYYY-MM-DD_HH-mm.dump
```

### إدارة المهمة

```powershell
schtasks /Run    /TN SadaraDbMirrorSync            # تشغيل فوري
schtasks /Query  /TN SadaraDbMirrorSync /V /FO LIST # الحالة
schtasks /Delete /TN SadaraDbMirrorSync /F          # إلغاء
```

السجلّات: `C:\SadaraBackups\logs\db_mirror_*.log`

---

## المرحلة 2 — Logical Replication (نسخة حيّة) — ⏸ تحتاج موافقة

> **تنبيه القواعد الذهبية:** هذه المرحلة **تغيّر إعدادات الإنتاج وتُعيد تشغيل
> PostgreSQL** (توقّف قصير لـ `sadara-api`)، **وتفتح المنفذ 5432 في الجدار الناري**.
> لا تُنفَّذ إلا بـ:
> - موافقة بشرية صريحة (القاعدة #8/#10/#11).
> - مراجعة `database-postgres-agent` (القاعدة #15).
> - مراجعة `security-auditor-agent` لفتح المنفذ (القاعدة #14).
> - نافذة صيانة (إعادة التشغيل تقطع الـ API لثوانٍ).

### قيود يجب فهمها قبل الموافقة

- **لا يحمي من المسح** (يُكرّر الحذف) — لهذا المرحلة 1 تبقى الأساس.
- **لا يُكرّر تغييرات الـ schema (DDL/migrations).** مع كل EF migration على الإنتاج
  يجب تطبيق نفس التغيير يدوياً على النسخة الحيّة وإلا تتعطّل المزامنة.
- **IP المنزل ديناميكي غالباً** → أي تغيير للـ IP يكسر `pg_hba` والجدار الناري
  ويوقف المزامنة حتى التحديث.
- كل جدول يحتاج مفتاحاً أساسياً (PK) أو `REPLICA IDENTITY` لتُنسخ عمليات UPDATE/DELETE.

### الخطوات المخطّطة (لا تُنفَّذ بعد)

**أ) على الإنتاج — تغيير الإعداد + إعادة التشغيل (يحتاج موافقة):**
```bash
# /etc/postgresql/16/main/postgresql.conf
wal_level = logical
# ثم:
systemctl restart postgresql     # ← توقّف قصير — نافذة صيانة
```

**ب) على الإنتاج — دور المزامنة + النشر:**
```sql
CREATE ROLE repl_mirror WITH REPLICATION LOGIN PASSWORD '<سر قوي>';
GRANT USAGE ON SCHEMA public TO repl_mirror;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO repl_mirror;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO repl_mirror;
CREATE PUBLICATION mirror_pub FOR ALL TABLES;
```

**ج) على الإنتاج — السماح باتصال المشترك (pg_hba.conf + firewall):**
```
# pg_hba.conf  (قيّده بـ IP المنزل فقط)
host  sadara_db  repl_mirror  <HOME_IP>/32  scram-sha-256
```
```bash
# افتح 5432 لـ IP المنزل فقط (Hostinger firewall + ufw)
ufw allow from <HOME_IP> to any port 5432 proto tcp
```

**د) محلياً — تجهيز قاعدة حيّة من الـ schema ثم الاشتراك:**
```powershell
# أنشئ قاعدة حيّة منفصلة عن الـ mirror المجمّد
createdb -h 127.0.0.1 -U postgres sadara_db_live
# انسخ الـ schema فقط من الإنتاج إلى القاعدة الحيّة
# (ssh: pg_dump -s) ثم:
psql -h 127.0.0.1 -U postgres -d sadara_db_live -c "
  CREATE SUBSCRIPTION mirror_sub
    CONNECTION 'host=72.61.183.61 port=5432 dbname=sadara_db user=repl_mirror password=<سر>'
    PUBLICATION mirror_pub WITH (copy_data = true);
"
```

**هـ) صيانة مستمرة:** مع كل migration على الإنتاج، طبّق نفس DDL على `sadara_db_live`.

---

## التوصية

- **فعّل المرحلة 1 الآن** — تحقّق هدفك بالكامل (حماية من المسح + نسخة قابلة للقراءة).
- **أجّل المرحلة 2** حتى تقرّر أن القراءة الحيّة تستحق التكلفة (تغيير إنتاج + فتح منفذ
  + صيانة مع كل migration + هشاشة IP الديناميكي). إن قرّرت المضيّ، تُنفَّذ عبر
  `database-postgres-agent` و`security-auditor-agent` وبموافقتك في نافذة صيانة.
