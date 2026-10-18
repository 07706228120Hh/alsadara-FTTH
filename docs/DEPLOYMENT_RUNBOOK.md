# دليل النشر — منصة الصدارة (Deployment Runbook)

> مرجع عملي لنشر الباكند (.NET) ورفع إصدار التطبيق (Flutter) ونشره على GitHub وتحديثه تلقائياً.
> **كل نشر إنتاج يحتاج موافقة بشرية صريحة** (القواعد الذهبية في `CLAUDE.md`).

آخر تحديث: 2026-10-18.

---

## 0) تحذيرات حرجة

- **رفع tag `v*` أو إنشاء GitHub Release جديد = إصدار إنتاج حقيقي يصل كل الأجهزة تلقائياً** عبر التحديث التلقائي → موافقة صريحة فقط.
- **لا تحذف/تستبدل `.dpkeys/`** على الخادم — فقدها يكسر فكّ تشفير كلمات مرور حسابات الساس/FTTH.
- خادم النشر الوحيد: **`72.61.183.61`**. الخادم الخارجي `185.239.19.3` (api.ftth.iq) للقراءة فقط وليس ملكنا.
- الباكند والتطبيق **منفصلان**: انشر الباكند أولاً عند أي تغيير خادمي، ثم أصدر التطبيق.
- لا مزامنة آلية لرقم الإصدار — تأكّد يدوياً من تطابق `pubspec.yaml` + `installer.iss` + الـtag.

---

## 1) نشر الباكند (.NET) على VPS

المسار الرسمي الوحيد (يدوي — لا CI للباكند). يُشغَّل من **جذر المستودع** `C:\SadaraPlatform` داخل **Git Bash**:

```bash
bash deploy/deploy-backend.sh
# لتجاوز الخادم (اختياري): SADARA_SERVER=root@72.61.183.61 bash deploy/deploy-backend.sh
```

**ما يفعله تلقائياً** (`set -euo pipefail` = يتوقف عند أي خطأ):
1. يغلق أي `Sadara.API.exe` محلي (تحرير قفل البناء).
2. `dotnet publish -c Release` إلى مجلد مؤقت؛ يفشل إن غاب `Sadara.API.dll`.
3. يولّد سكربت هجرات **idempotent** (`dotnet ef migrations script --idempotent`) — يطبّق الهجرات الناقصة فقط؛ يرفض التنفيذ إن وجد `DROP TABLE`.
4. **نسخة احتياطية على الخادم أولاً**: نسخ كل الـDLLs الحالية إلى `/root/backups/dll_<TS>/` + `pg_dump sadara_db | gzip > /root/backups/db_<TS>.sql.gz`.
5. **يطبّق الهجرات قبل الـDLLs** (`psql -v ON_ERROR_STOP=1`).
6. ينشر **كل** الـDLLs إلى `/var/www/sadara-api/` (يمنع `MissingMethodException`).
7. `systemctl restart sadara-api` + انتظار ~32ث + تحقّق صارم: `active` **و** `/health`=200 **و** 0 أخطاء في السجل. وإلا يطبع أمر التراجع ويخرج برمز 1.

**ثوابت الخادم:** `root@72.61.183.61` · `/var/www/sadara-api` · قاعدة `sadara_db` · خدمة systemd `sadara-api` (على `http://localhost:5000`).

**لا يُلمَس على الخادم:** `appsettings.Production.json` · `.env` · `.dpkeys/`.

**التراجع (rollback):**
```bash
# DLLs:
cp /root/backups/dll_<TS>/*.dll /var/www/sadara-api/ && systemctl restart sadara-api
# القاعدة:
gunzip -c /root/backups/db_<TS>.sql.gz | sudo -u postgres psql -d sadara_db
```
ملاحظة: إرجاع الـDLLs لا يُرجع الهجرات (تُطبَّق قبلها). الهجرات الإضافية (`CreateTable`) آمنة ويتعايش معها الكود القديم.

---

## 2) رفع الإصدار وبناء المُنصِّب والنشر على GitHub

المستودع: **`07706228120Hh/alsadara-FTTH`**. التطبيق: `src/Apps/CompanyDesktop/alsadara-ftth`.

### 2.1 رفع الرقم (مكانان يدوياً — يجب أن يتطابقا)
- `pubspec.yaml` (السطر 5): `version: X.Y.Z+B`
- `installer.iss`: `AppVersion=X.Y.Z` و `OutputBaseFilename=Alsadara-Setup-vX.Y.Z`
- تأكّد أن `lib/services/auto_update_service.dart` يشير إلى `07706228120Hh/alsadara-FTTH` (مضبوط — لا تغيّره).

### 2.2 بناء التطبيق
```powershell
cd src\Apps\CompanyDesktop\alsadara-ftth
D:\flutter\flutter\bin\flutter.bat pub get
D:\flutter\flutter\bin\flutter.bat analyze
D:\flutter\flutter\bin\flutter.bat build windows --release
# الناتج: build\windows\x64\runner\Release\Alsadara.exe
```

### 2.3 بناء المُنصِّب (Inno Setup)
```powershell
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss
# الناتج: build\installer\Alsadara-Setup-vX.Y.Z.exe
# يضمّن مخرجات البناء + شهادة Let's Encrypt + خادم واتساب Node المحمول (whatsapp-server)
```

### 2.4 النشر على GitHub
- **الحالي (CI مقفل بالفوترة) = يدوي:**
```powershell
gh release create vX.Y.Z build\installer\Alsadara-Setup-vX.Y.Z.exe --latest --title "الإصدار X.Y.Z" --notes "..."
```
- **بديل (لو عادت الفوترة):** دفع tag `vX.Y.Z` يشغّل `.github/workflows/build-windows.yml` تلقائياً (بناء + Release).
- شرط: الـRelease معلّم **latest** وأصله يطابق `*setup*.exe`.

### 2.5 التحديث التلقائي (كيف يصل المستخدمين)
- بعد تسجيل الدخول (Windows، بعد ~3ث) يسأل كل جهاز `releases/latest`.
- يقارن `major.minor.patch` مع إصداره؛ إن أحدث يُنزّل أول asset يحوي `setup` وينتهي بـ`.exe`.
- يثبّت **صامتاً**: `/SILENT /FORCECLOSEAPPLICATIONS /RESTARTAPPLICATIONS /NOCANCEL /SP- /DIR=<مجلد الحالي>` ثم يعيد التشغيل.
- Snooze: بعد محاولة تثبيت لا يُعاد العرض لنفس الإصدار ساعتين؛ التخطي اليدوي 24 ساعة.

---

## 3) نشر ميزة «الحسابات المرتبطة المتعددة» تحديداً (القائمة بالترتيب)

1. **موافقة صريحة** + نسخة احتياطية (السكربت يأخذها).
2. **انشر الباكند**: `bash deploy/deploy-backend.sh` → يطبّق الهجرتين تلقائياً:
   - `20261017205159_AddFtthAccountsMultiLink` (جدول `FtthAccounts`)
   - `20261017214638_AddCredentialRevealAudit` (جدول `CredentialRevealAudits`)
3. **رخّص صلاحية `linked_accounts`** للشركات عبر `PUT /api/internal/companies/{id}/permissions-v2` — **إلزامي** (البذر محروس بـ`AnyAsync` لا يطال قواعد الإنتاج القائمة؛ بدونه يُحجب الأدمن، وSuperAdmin فقط يتجاوز).
4. (اختياري) أدرِج صفوف كتالوج `linked_accounts` الأربعة على الإنتاج لتظهر في واجهة إدارة الصلاحيات.
5. **شغّل `backfill-from-legacy`** لكل شركة (POST، أدمن) لترحيل روابط FTTH القديمة من `User.FtthUsername` إلى `FtthAccounts`.
6. **قرار العلَم** `Sas:AllowCredentialReveal` في `appsettings.Production.json` (OFF افتراضياً — فعّله فقط إن أردت كشف كلمات مرور الساس).
7. **ارفع الإصدار + ابنِ + انشر المُنصِّب** (القسم 2) — الواجهة الجديدة تحتاج كود العميل الجديد.
8. **تحقّق بعد النشر**: افتح نسخة أقدم، سجّل دخول، انتظر ~3ث → يجب أن يظهر حوار التحديث ويثبّت صامتاً؛ ثم افتح موظفاً → تبويب «الحسابات المرتبطة».

---

## 4) ملفات مرجعية

- `deploy/deploy-backend.sh` · `deploy/backup.sh` (نسخ احتياطي أشمل)
- `src/Apps/CompanyDesktop/alsadara-ftth/pubspec.yaml` · `installer.iss`
- `.github/workflows/build-windows.yml` (tag `v*` → build+release) · `release.yml` · `build.yml`
- `lib/services/auto_update_service.dart` · `lib/widgets/update_dialog.dart` · `lib/pages/login/premium_login_page.dart` (الفحص بعد الدخول)
- `CLAUDE.md` (Commands/النشر/الإصدار) · `.claude/agents/release-manager-agent.md`
- `docs/adr/ADR-0001-unified-multi-account-linking.md` (تصميم الميزة)
