# دليل رفع التحديثات إلى منصة الصدارة

> مرجع عملي موحّد لكيفية نشر أي تحديث على منصة الصدارة. يغطّي الأجزاء الثلاثة:
> **بوابة الويب (المواطن)** · **الباكند (.NET API)** · **تطبيق سطح المكتب/الموبايل (Flutter)**.
> خادم النشر الوحيد لكل شيء: **`72.61.183.61`** (خادمنا). لا تنشر على أي خادم آخر.

---

## ⚠️ قبل أي نشر — بوّابات الموافقة (إلزامية)

نشر الإنتاج يحتاج **موافقة بشرية صريحة** في كل مرة (القاعدة الذهبية #8/#9). خصوصاً:
- رفع tag بصيغة `v*` = إصدار إنتاج حقيقي يصل **كل الأجهزة تلقائياً** عبر auto-update.
- أي هجرة قاعدة بيانات، تغيير أسرار/مصادقة/صلاحيات، force push.
- عند الشك: اكتب تقريراً واطلب موافقة بدل التنفيذ.

خطوات مشتركة قبل النشر: التزم التغييرات في git، وارفع رقم الإصدار، وخذ نسخة احتياطية.

---

## 1) بوابة الويب — تطبيق المواطن (CitizenWeb → ramzbot.com)

**ماهيتها**: تطبيق Flutter Web/PWA يُخدَم على `https://ramzbot.com` من خادمنا عبر **nginx** (ملفات ساكنة).
- جذر الموقع على الخادم: **`/var/www/ramzbot`**
- الدومينات: `ramzbot.com` + `www` + `app.ramzbot.com` (كلها نفس الجذر)؛ و`ramzalsadara.tech` يُحوّل 301 إليه.
- الـ API الذي يتصل به: `https://api.ramzalsadara.tech` (`lib/config/api_config.dart`).
- لا Cloudflare أمامه (DNS يشير للخادم مباشرة) ⇒ لا حاجة لإبطال كاش CF.

### الخطوات

```bash
cd src/Apps/CitizenWeb

# 1) ارفع رقم الإصدار في pubspec.yaml (version: X.Y.Z+N)

# 2) 🔴 إلزامي: نظّف قبل البناء (انظر «المصيدة» أدناه)
D:/flutter/flutter/bin/flutter.bat clean
D:/flutter/flutter/bin/flutter.bat pub get

# 3) ابنِ نسخة الويب
D:/flutter/flutter/bin/flutter.bat build web --release    # ينتج build/web/ ، base href=/

# 4) اضغط وارفع إلى الخادم
tar czf /tmp/web.tgz -C build/web .
scp /tmp/web.tgz root@72.61.183.61:/root/web.tgz

# 5) على الخادم: نسخة احتياطية + تبديل ذرّي (بلا توقّف)
ssh root@72.61.183.61 'set -e
  ts=$(date +%Y%m%d_%H%M%S)
  tar czf /root/backups/ramzbot_$ts.tar.gz -C /var/www ramzbot          # نسخة احتياطية
  rm -rf /var/www/ramzbot_new && mkdir /var/www/ramzbot_new
  tar xzf /root/web.tgz -C /var/www/ramzbot_new
  test -f /var/www/ramzbot_new/main.dart.js                              # تحقّق سلامة الفكّ
  rm -rf /var/www/ramzbot_old && mv /var/www/ramzbot /var/www/ramzbot_old
  mv /var/www/ramzbot_new /var/www/ramzbot
  chmod -R a+rX /var/www/ramzbot && rm -f /root/web.tgz
  cat /var/www/ramzbot/version.json'
```

nginx **لا يحتاج إعادة تشغيل** (ملفات ساكنة).

### التحقّق
```bash
curl -s "https://ramzbot.com/version.json"   # يجب أن يُظهر الإصدار الجديد
```
للتحقق من السلوك الفعلي عبر متصفح آلي (Playwright): امسح service worker والكاش أولاً
(`getRegistrations()→unregister()` + `caches.keys()→delete()`) ثم أعد التحميل، وإلا تفحص البناء القديم المخبوء.

### 🔴 مصيدتان مهمّتان
1. **`flutter clean` قبل كل `build web`**: وإلا قد يُعيد `build web` استخدام **مُسجِّل إضافات ويب مخبوء ناقص** (`.dart_tool/flutter_build/<hash>/web_plugin_registrant.dart`) لا يحوي إضافات مُضافة حديثاً (مثل `video_player_web`, `url_launcher_web`) ⇒ الإضافة لا تُسجَّل ⇒ `UnimplementedError: init() has not been implemented` وقت التشغيل. يعمل في `flutter run` ويفشل في البناء المنشور فقط، لذا يصعب اكتشافه بلا هذا التنبيه.
2. **كاش service worker**: بعد النشر، متصفحات المستخدمين تعرض النسخة القديمة وتُحدّث في الخلفية؛ قد يحتاجون تحديث الصفحة (Ctrl+F5) مرّة لرؤية الجديد فوراً.

### التراجع الفوري
```bash
ssh root@72.61.183.61 'mv /var/www/ramzbot /var/www/ramzbot_bad && mv /var/www/ramzbot_old /var/www/ramzbot'
```

---

## 2) الباكند — واجهة الـ API (.NET 9)

**ماهيته**: خدمة `sadara-api` (systemd) على `72.61.183.61` خلف nginx على `api.ramzalsadara.tech`، مع PostgreSQL `sadara_db`.

### الخطوة الوحيدة الصحيحة
```bash
bash deploy/deploy-backend.sh      # من جذر المستودع (Git Bash) — بموافقة صريحة فقط
```
السكربت idempotent ويطبّق كل الدروس المكتسبة تلقائياً:
1. يُغلق الباكند المحلي (يحرّر قفل البناء) ويبني Release كاملاً.
2. يولّد سكربت هجرات idempotent (يطبّق الناقص فقط).
3. **نسخة احتياطية** (قاعدة + كل DLLs الحالية) في `/root/backups/` قبل أي تغيير.
4. يطبّق **الهجرات قبل الـ DLLs** (وإلا أعمدة جديدة ⇒ 500).
5. ينشر **كل `*.dll`** (لا أربعة فقط) ⇒ يمنع `MissingMethodException`.
6. إعادة تشغيل + تحقّق صارم: `active` + `/health=200` + **صفر** أخطاء في السجل.

> ملاحظة: فحص الصحة قد يُرجع 000/يتعثّر عابراً أثناء إحماء EF أو تبديل DLLs (`BadImageFormat`)؛ تحقّق يدوياً بعدها: `curl -s -o /dev/null -w "%{http_code}" https://api.ramzalsadara.tech/health`.

### قواعد حرجة
- **لا تعدّل/تحذف أي migration موجودة** في `Sadara.Infrastructure/Data/Migrations` — أضف جديدة دائماً.
- migration جديدة:
  ```bash
  dotnet ef migrations add <Name> --project src/Backend/Core/Sadara.Infrastructure --startup-project src/Backend/API/Sadara.API
  ```
- أي تغيير أمني/قاعدة بيانات يمرّ على security-auditor-agent / database-postgres-agent.

### التراجع
الـ DLLs السابقة محفوظة في `/root/backups/dll_<TS>/` على الخادم:
```bash
ssh root@72.61.183.61 'cp /root/backups/dll_<TS>/*.dll /var/www/sadara-api/ && systemctl restart sadara-api'
```

---

## 3) تطبيق سطح المكتب/الموبايل (alsadara-ftth → GitHub Releases → auto-update)

**ماهيته**: تطبيق Flutter (Windows + Android + iOS) يُوزَّع عبر Inno Setup → GitHub Release
(`07706228120Hh/alsadara-FTTH`) → خدمة التحديث التلقائي في التطبيق.

### الخطوات (Windows)
```powershell
cd src/Apps/CompanyDesktop/alsadara-ftth

# 1) ارفع رقم الإصدار في الملفين معاً:
#    pubspec.yaml     →  version: X.Y.Z+BUILD
#    installer.iss    →  AppVersion=X.Y.Z  و  OutputBaseFilename=Alsadara-Setup-vX.Y.Z

# 2) ابنِ نسخة ويندوز
D:\flutter\flutter\bin\flutter.bat build windows --release

# 3) ابنِ المُنصِّب (Inno Setup)
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss
#    ينتج: Alsadara-Setup-vX.Y.Z.exe

# 4) ارفعه كـ GitHub Release (الأندرويد: ابنِ APK/AAB وأرفقه أيضاً)
#    gh release create vX.Y.Z Alsadara-Setup-vX.Y.Z.exe --title ... --notes ...
```

### 🔴 تحذير أعلى درجة
- **رفع tag `v*` = إصدار إنتاج حقيقي يصل كل الأجهزة تلقائياً** عبر auto-update — يحتاج موافقة صريحة.
- فرع العمل `release/v2.4.x`؛ و`main` = المُصدَر (يُزامَن FF بعد الإصدار).
- طبقة manifest التحديث على خادمنا: التطبيق يسأل `GET /api/appversions/manifest?platform=` أولاً، ثم GitHub.

### التراجع
```bash
gh release edit v<السابق> --latest     # يُرجع «الأحدث» لإصدار سابق فيتوقّف توزيع الجديد
```

---

## جدول مرجعي سريع

| الجزء | المصدر | الوجهة | الأمر | tag v*؟ | التراجع |
|------|--------|--------|------|---------|---------|
| بوابة الويب | `src/Apps/CitizenWeb` | `72.61.183.61:/var/www/ramzbot` (nginx) | `flutter clean && build web` + scp + تبديل ذرّي | لا | `mv ramzbot_old → ramzbot` |
| الباكند | `src/Backend` | `72.61.183.61` (systemd `sadara-api`) | `bash deploy/deploy-backend.sh` | لا | نسخ DLLs من `/root/backups/dll_<TS>` |
| التطبيق | `src/Apps/CompanyDesktop/alsadara-ftth` | GitHub Release → auto-update | `build windows` + `ISCC` + `gh release` | **نعم** | `gh release edit v<سابق> --latest` |

---

*آخر تحديث: 2026-10-29. أنشئ هذا الدليل بعد نشر بوابة الويب v1.1.1+3 (إصلاح صفحة الهبوط: الفيديو + Marquee + مُسجِّل الإضافات).*
