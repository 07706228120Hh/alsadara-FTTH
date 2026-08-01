# Release Runbook — تطبيق alsadara-ftth (Windows)

دليل إصدار دقيق وقابل للتنفيذ يدوياً لتطبيق الصدارة (Flutter Windows). كل حقيقة هنا مؤكَّدة من ملفات المستودع الفعلية مع الأسطر. أي بند غير مؤكَّد مُعلَّم صراحةً بـ **[غير مؤكَّد]**.

> نطاق هذا الدليل: **تحقيق وتوثيق فقط**. لا ينفّذ هذا المستند أي نشر/رفع/push. الخطوات المعلَّمة بـ **(تتطلب موافقة بشرية)** لا تُنفَّذ إلا بموافقة صريحة حسب `CLAUDE.md` / `PROJECT_CONTEXT.md`.

- تاريخ التحرير: 2026-08-01
- الإصدار الحالي المؤكَّد: `2.2.25+304` — من `src/Apps/CompanyDesktop/alsadara-ftth/pubspec.yaml:5`
- مجلد التطبيق: `src/Apps/CompanyDesktop/alsadara-ftth/`
- المستودع (origin) لهذا الريبو = مستودع الإصدارات نفسه: `https://github.com/07706228120Hh/alsadara-FTTH.git` — من `.git/config:12-14`

---

## 0. حقيقة أساسية: هذا الريبو هو مستودع الإصدارات نفسه

`origin` لهذا المستودع المحلي هو `07706228120Hh/alsadara-FTTH` (`.git/config:13`). وهذا هو نفس المستودع الذي:
- تقرأ منه خدمة التحديث آخر إصدار: `AutoUpdateService.githubApiUrl` = `https://api.github.com/repos/07706228120Hh/alsadara-FTTH/releases/latest` (`lib/services/auto_update_service.dart:99-102`).
- يبني وينشر تلقائياً عند رفع tag بنمط `v*` عبر GitHub Actions (`.github/workflows/build-windows.yml:6-9`).

النتيجة العملية: **رفع tag `v*` إلى origin = إطلاق إصدار حقيقي يصل تلقائياً لأجهزة المستخدمين.** لذلك `git push` لأي tag `v*` هو عملية إنتاج تتطلب موافقة بشرية (Golden Rule #9 و#8).

---

## 1. رقم الإصدار: مكانه ومكوّناته وأماكن استهلاكه

### 1.1 المصدر الأساسي (Source of Truth)
- `pubspec.yaml:5` → `version: 2.2.25+304`
  - الصيغة: `<major>.<minor>.<patch>+<build>` = `2.2.25` + build `304`.
  - عند البناء، Flutter يحقن هذا في `package_info_plus`؛ التطبيق يقرأه عبر `PackageInfo.fromPlatform()` → `packageInfo.version` (يُعيد `2.2.25` بدون جزء الـ build) في:
    - `lib/services/auto_update_service.dart:170-171, 375-378`
    - `lib/pages/login/premium_login_page.dart:172` (عرض `v$_appVersion`)

### 1.2 أماكن أخرى يُحقن/يُستهلك فيها الرقم (يجب مزامنتها يدوياً)
| المكان | السطر | القيمة الحالية | ملاحظة |
|--------|-------|----------------|--------|
| `pubspec.yaml` | 5 | `2.2.25+304` | المصدر الأساسي |
| `installer.iss` `AppVersion` | 4 | `2.2.25` | مكتوب يدوياً — **لا يقرأ من pubspec** |
| `installer.iss` `OutputBaseFilename` | 9 | `Alsadara-Setup-v2.2.25` | مكتوب يدوياً — **لا يقرأ من pubspec** |

### 1.3 لا يوجد ملف latest/appcast/version.json
- **مؤكَّد**: لا يوجد ملف `version.json` / `appcast` / `latest.yml` في التطبيق. آلية «آخر إصدار» تعتمد كلياً على **GitHub Releases API** (`releases/latest`)، وليس على ملف ثابت.
- يوجد استخدام قديم `dotenv.env['APP_VERSION']` في `lib/services/config_manager.dart:80, 253` — لكنه لأغراض telemetry/config فقط (يُكتب في config.json المحلي) و**ليس** له علاقة بمنطق التحديث. لا يؤثر على الإصدار المعروض ولا على المقارنة.

---

## 2. آلية التحقق من التحديث داخل التطبيق

الملف: `lib/services/auto_update_service.dart` + واجهة `lib/widgets/update_dialog.dart`.

### 2.1 من أين يقرأ آخر إصدار
- ثابتة الرابط: `githubApiUrl = https://api.github.com/repos/07706228120Hh/alsadara-FTTH/releases/latest` (`auto_update_service.dart:99-102`).
- `checkForUpdate()` (`:158-187`) يرسل `GET` مع header `Accept: application/vnd.github.v3+json`، ويأخذ الـ Release الموسوم **latest** فقط.
- رقم الإصدار عن بُعد يؤخذ من `json['tag_name']` بعد إزالة الحرف `v` (`:87` → `replaceAll('v', '')`). أي أن الـ **tag** هو مصدر الإصدار عن بُعد — مثل `v2.2.26` ← `2.2.26`.

### 2.2 كيف يقارن الإصدارات
- `_isNewerVersion()` (`:190-207`): يقسم الرقم على `.` ويقارن `major.minor.patch` فقط (3 أجزاء).
- **مهم**: المقارنة **تتجاهل جزء الـ build (`+304`)** تماماً. الترقية لا تحدث إلا إذا تغيّر أحد `major/minor/patch`.
- **[خطر]** أي `split('.').map(int.parse)` سيفشل إن احتوى الـ tag على لاحقة غير رقمية (مثل `2.2.26-beta`) → تُلتقط الاستثناء وتُعيد `false` (لا تحديث). استخدم tags نظيفة `vX.Y.Z` فقط.

### 2.3 كيف ينزّل ويُثبّت وأي asset يتوقعه
اختيار الـ asset في `UpdateInfo.fromGitHubRelease()` (`:32-93`) حسب المنصة:

- **Windows** (`:48-84`) — يبحث بالترتيب:
  1. أول asset اسمه (lowercase) **يحتوي `setup` وينتهي بـ `.exe`** ← الأولوية. (`:52-59`)
  2. وإلا: أي asset ينتهي بـ `.exe`. (`:62-71`)
  3. وإلا: أي `.zip`. (`:74-83`)
  - اسم الملف الذي ينتجه `installer.iss` هو `Alsadara-Setup-v2.2.25.exe` (`installer.iss:9`) — يحتوي `setup` وينتهي بـ `.exe` ✅ فيُلتقط في المرحلة 1.
- **Android** (`:38-47`): أول asset ينتهي بـ `.apk`. (workflow الحالي لا يبني APK — انظر §4.5).

- التنزيل `downloadUpdate()` (`:210-274`): يحفظ في مجلد temporary باسم مأخوذ من آخر جزء من الـ URL (`:227`)، يتحقق من الحجم لتفادي إعادة التنزيل، ثم يبثّ التقدّم.
- التثبيت (Windows) `installUpdate()` (`:307-344`):
  - يستخرج الإصدار من اسم الملف عبر regex `v(\d+\.\d+\.\d+)` (`:310-311`) لتسجيل «محاولة» ومنع حلقة تحديث.
  - `Unblock-File` لإزالة حظر SmartScreen (`:318-323`).
  - يشغّل المثبّت صامتاً بالأعلام:
    `/SILENT /FORCECLOSEAPPLICATIONS /RESTARTAPPLICATIONS /NOCANCEL /SP- /DIR=<مجلد exe الحالي> /TASKS=desktopicon` (`:333-341`)، ثم `exit(0)`.

### 2.4 متى يُشغَّل الفحص
- بعد 5 ثوانٍ من فتح الصفحة الرئيسية: `lib/pages/home_page.dart:270-273`.
- وأيضاً عند شاشة الدخول: `lib/pages/login/premium_login_page.dart:518`.
- ينفّذ فقط على Windows/Android: `UpdateManager.checkAndShowUpdateDialog` (`update_dialog.dart:446-448`).
- آلية snooze: ساعتان بين محاولات نفس الإصدار، و24 ساعة عند التخطي اليدوي (`auto_update_service.dart:110-155`).

---

## 3. ملف Inno Setup (`installer.iss`)

المسار: `src/Apps/CompanyDesktop/alsadara-ftth/installer.iss`.

| بند | القيمة | السطر |
|-----|--------|-------|
| `AppVersion` | `2.2.25` | 4 |
| `OutputDir` | `build\installer` | 8 |
| `OutputBaseFilename` | `Alsadara-Setup-v2.2.25` → الناتج `Alsadara-Setup-v2.2.25.exe` | 9 |
| مجلد المصدر (Files) | `build\windows\x64\runner\Release\*` | 30 |
| استثناءات | `*.lib,*.exp,*.pdb` | 30 |
| اسم exe المُثبَّت | `{app}\Alsadara.exe` | 17, 33-35 |
| Mutex/إغلاق | `AppMutex=AlsadaraFTTHMutex`, `CloseApplicationsFilter=Alsadara.exe` | 20-21 |

- **مؤكَّد**: مصدر الملفات يشير فعلاً إلى `build\windows\x64\runner\Release` (مخرجات `flutter build windows --release`)، ويطابق مسار الـ build الذي أُنتج للتو (`build\windows\x64\runner\Release\Alsadara.exe`).
- اسم الـ exe = `Alsadara.exe` مؤكَّد من `windows/CMakeLists.txt:7` (`set(BINARY_NAME "Alsadara")`).
- **[خطر مزامنة]** `AppVersion` و`OutputBaseFilename` مكتوبان **يدوياً** ولا يُشتقّان من `pubspec.yaml`. عند تغيير الإصدار يجب تعديل السطرين 4 و9 يدوياً وإلا سيظل اسم/إصدار المثبّت قديماً.

---

## 4. مستودع الإصدارات على GitHub وآلية النشر

### 4.1 الطريقة الرسمية: GitHub Actions (مؤتمتة عند tag)
الملف: `.github/workflows/build-windows.yml`.
- المُشغِّل (`:6-10`): `push` على tags بنمط `v*`، أو `workflow_dispatch` يدوي.
- الخطوات (`:26-81`):
  1. checkout + Setup Flutter نسخة `3.38.4` (`:13, 30-35`).
  2. ينشئ `.env` فارغاً (`:37-39`) — **[خطر]** أي متغيّرات بيئة حقيقية لن تكون موجودة في بناء الـ CI.
  3. `flutter pub get` ثم `flutter build windows --release` (`:41-45`).
  4. ينشئ `Alsadara-Windows-<tag>.zip` من مجلد Release (`:47-50`).
  5. يثبّت Inno Setup عبر choco ويشغّل `iscc installer.iss` (`:52-56`).
  6. ينشئ GitHub Release ويرفع assets (`:58-79`):
     - `Alsadara-Windows-<tag>.zip`
     - `src/Apps/CompanyDesktop/alsadara-ftth/build/installer/Alsadara-Setup-<tag>.exe`

### 4.2 تعارض أسماء حرج (asset mismatch) — يجب الانتباه
- الـ workflow يرفع الملف بالاسم **`Alsadara-Setup-${{ github.ref_name }}.exe`** أي `Alsadara-Setup-v2.2.25.exe` عندما يكون الـ tag = `v2.2.25` (`:77`).
- بينما `installer.iss` ينتج فعلياً `Alsadara-Setup-v2.2.25.exe` (لأن `OutputBaseFilename` مثبّت على `v2.2.25`).
- **إذن يتطابقان فقط إذا كان الـ tag = `v2.2.25` بالضبط.** لو رفعت tag مختلف (مثل `v2.2.26`) دون تعديل `OutputBaseFilename` في `installer.iss:9`، فإن Inno سيُنتج `Alsadara-Setup-v2.2.25.exe` بينما الـ workflow يبحث عن `Alsadara-Setup-v2.2.26.exe` → **خطوة الرفع تفشل / الأصل مفقود**. (`softprops/action-gh-release` قد يفشل عند غياب ملف مُحدَّد في `files`.)
- **القاعدة الإلزامية**: حدّث `installer.iss:9` (`OutputBaseFilename`) و`:4` (`AppVersion`) لتطابق الـ tag قبل أي إصدار.

### 4.3 هل الأصل يطابق ما تتوقعه خدمة التحديث؟
- خدمة التحديث تبحث عن أي `.exe` يحتوي `setup` (§2.3). كلا الاسمين المحتملين يبدآن بـ `Alsadara-Setup-` ← يحتويان `setup` ← يُلتقطان. لذا **حتى لو اختلف رقم الإصدار في اسم الملف، خدمة التحديث ستلتقط أول setup.exe**. المخاطرة الفعلية هي فشل **رفع** الـ asset في الـ workflow (§4.2)، لا التقاطه في العميل.

### 4.4 الطريقة اليدوية عبر السكربت (قديمة/غير موثوقة)
- `scripts/build/create_release.ps1`: يحدّث `pubspec.yaml`، ينشئ tag، ويعمل **`git push origin main`** و`git push origin v$Version` (`:63-64`). كما أنه يطبع placeholders قديمة (`YOUR_GITHUB_USERNAME`, repo `alsadara`) في `:47-49, 73`.
  - **[خطر]** يعمل push إلى `main` تلقائياً — يخالف Golden Rule #9. **لا تستخدمه بلا موافقة صريحة.**
  - **[خطر]** يشتق الـ build number بمعادلة `major*100+minor*10+patch` (`:40`) وهي **لا تطابق** نمط الـ build الحالي `304`؛ ستكسر تسلسل أرقام الـ build. الأفضل تعديل `pubspec.yaml` يدوياً.

### 4.5 سكربتات بناء قديمة (لا تعمل كما هي — للأرشيف فقط)
جميعها في `scripts/build/`، وتشير إلى مسار مشروع قديم غير موجود `d:\flutter\app\ramz1 top\filter_page` وأرقام إصدارات قديمة وأسماء iss قديمة:
- `MAKE_INSTALLER.bat` (v1.2.6، iss قديم `alsadara_installer_v1.2.6.iss`).
- `build_complete.ps1` (v1.2.5).
- `build_v1.2.8.ps1` (v1.2.8).
- `create_release.ps1` (انظر §4.4).
- **الخلاصة**: هذه السكربتات **مهجورة** ولا تطابق البنية الحالية. لا تعتمد عليها. المسار الرسمي هو GitHub Actions أو الخطوات اليدوية في §6.

---

## 5. السكربتات المساعدة الموجودة (جرد)

| السكربت | الحالة | ملاحظة |
|---------|--------|--------|
| `scripts/build/create_release.ps1` | مهجور/خطِر | يعمل push تلقائي + placeholders قديمة |
| `scripts/build/build_complete.ps1` | مهجور | مسار مشروع قديم، v1.2.5 |
| `scripts/build/build_v1.2.8.ps1` | مهجور | مسار مشروع قديم، v1.2.8 |
| `scripts/build/MAKE_INSTALLER.bat` | مهجور | iss قديم، مسار قديم |
| `.github/workflows/build-windows.yml` | فعّال ورسمي | المسار المعتمد للبناء والنشر |

لا يوجد سكربت بناء/إصدار حديث يطابق `installer.iss` الحالي؛ المسار الموثوق الوحيد المؤتمت هو الـ workflow.

---

## 6. خطوات الإصدار اليدوية بالترتيب الدقيق

> افتراض: نُصدر إصدار جديد `X.Y.Z` (مثال `2.2.26`). بدّل القيم أدناه. أي خطوة نشر/push معلَّمة **(موافقة بشرية)**.

### المرحلة أ — تحديث الأرقام (تعديل ملفات فقط)
1. `pubspec.yaml:5` → `version: 2.2.26+305` (ارفع الـ build يدوياً بمقدار 1؛ لا تستخدم معادلة `create_release.ps1`).
2. `installer.iss:4` → `AppVersion=2.2.26`.
3. `installer.iss:9` → `OutputBaseFilename=Alsadara-Setup-v2.2.26`.
4. حدّث `src/Apps/CompanyDesktop/alsadara-ftth/CHANGELOG.md` (أضف قسم الإصدار الجديد أعلى الملف).
5. تحقّق: لا يوجد أي مرجع آخر لرقم إصدار ثابت يحتاج تحديثاً (خدمة التحديث تقرأ من pubspec تلقائياً — لا حاجة لتعديلها).

### المرحلة ب — البناء المحلي (اختياري إن استُخدم الـ CI)
6. `"D:\flutter\flutter\bin\flutter.bat" pub get` داخل مجلد التطبيق.
7. `"D:\flutter\flutter\bin\flutter.bat" build windows --release`
   - المخرجات: `build\windows\x64\runner\Release\Alsadara.exe` (مؤكَّد أنه بُني للتو).
8. تجميع المثبّت:
   `"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss`
   - المخرجات: `build\installer\Alsadara-Setup-v2.2.26.exe` (`installer.iss:8-9`).
9. تحقّق يدوياً من الملف الناتج (اسمه، حجمه، تشغيله على جهاز اختبار).

### المرحلة ج — إنشاء الإصدار على GitHub

اختر **أحد** المسارين:

**المسار 1 — عبر GitHub Actions (المعتمد):**
10. commit تعديلات الأرقام (`pubspec.yaml`, `installer.iss`, `CHANGELOG.md`).
11. **(موافقة بشرية — Golden Rule #9)** أنشئ وادفع الـ tag:
    - `git tag -a v2.2.26 -m "release v2.2.26"`
    - `git push origin v2.2.26`
    - هذا يشغّل الـ workflow الذي يبني وينشر تلقائياً (§4.1). **لا حاجة لرفع أصل يدوياً.**
12. تابع Actions حتى ينشئ Release بأصلين: `Alsadara-Windows-v2.2.26.zip` + `Alsadara-Setup-v2.2.26.exe`.

**المسار 2 — رفع يدوي للأصل (بدون الاعتماد على بناء الـ CI):**
10'. **(موافقة بشرية)** أنشئ Release في `07706228120Hh/alsadara-FTTH` موسوماً `v2.2.26`، وعيّنه **latest**.
11'. **(موافقة بشرية)** ارفع الأصل `build\installer\Alsadara-Setup-v2.2.26.exe` باسمه كما هو (يجب أن يحتوي `setup` وينتهي بـ `.exe`).
> ملاحظة: حتى في المسار اليدوي، إن كان الـ tag يبدأ بـ `v*` وتمّ push، سيُشغَّل الـ workflow أيضاً وقد يتعارض مع رفعك اليدوي. نسّق مع `devops-agent` لتفادي ازدواج البناء.

### المرحلة د — كيف يلتقطه المستخدمون
13. عند فتح أي عميل التطبيق (بعد 5 ثوانٍ من الصفحة الرئيسية أو عند الدخول)، يستدعي `releases/latest`، يقارن `2.2.26 > 2.2.25`، يلتقط أول `setup.exe`، ينزّله ويثبّته صامتاً ويعيد التشغيل (§2). الوصول تدريجي مع snooze ساعتين.

---

## 7. الفجوات والمخاطر (خلاصة)

1. **النشر مؤتمت جزئياً لكن الإطلاق يدوي**: البناء والنشر يتمّان تلقائياً عبر GitHub Actions، لكن **الإطلاق يبدأ بـ push tag يدوي** = عملية إنتاج تتطلب موافقة.
2. **origin = مستودع الإصدارات نفسه**: أي `git push` لـ tag `v*` يصل للمستخدمين مباشرة. خطر إطلاق غير مقصود عالٍ.
3. **إصدار المثبّت غير مشتق من pubspec**: `installer.iss:4,9` يدويان؛ نسيان تحديثهما يُنتج مثبّتاً باسم/إصدار خاطئ.
4. **asset-name mismatch محتمل**: الـ workflow يرفع `Alsadara-Setup-<tag>.exe` بينما iss قد يُنتج اسماً بإصدار مختلف إن لم يُحدَّث → **فشل رفع الأصل** (§4.2). أوقف الإصدار حتى تتطابق أسماء iss مع الـ tag.
5. **مقارنة الإصدار تتجاهل الـ build**: زيادة `+build` فقط دون تغيير `major/minor/patch` **لن تُطلق تحديثاً** لدى المستخدمين.
6. **tags يجب أن تكون `vX.Y.Z` نظيفة**: أي لاحقة (`-beta`) تكسر `int.parse` في المقارنة → لا تحديث.
7. **الـ CI ينشئ `.env` فارغاً** (`workflow:37-39`): أي متغيرات بيئة مطلوبة وقت التشغيل غير موجودة في بناء الـ CI — تحقّق أن التطبيق لا يعتمد على `.env` وقت البناء.
8. **سكربتات البناء القديمة خطِرة/مهجورة**: `create_release.ps1` يعمل `git push origin main` تلقائياً — لا يُستخدم بلا موافقة.
9. **[غير مؤكَّد] بوابات الجودة قبل الإصدار**: لا يوجد ضمن الـ workflow أي خطوة اختبارات/فحص أمني آلي قبل النشر؛ لا CHANGELOG-gate. الجاهزية (اختبارات/أمن/توثيق) يجب تأكيدها يدوياً مع `testing-qa-agent` و`security-auditor-agent`.
10. **لا rollback مؤتمت لـ GitHub Release**: انظر §8.
11. **[غير مؤكَّد]** لا يوجد توقيع كود (code signing) للمثبّت؛ الاعتماد على `Unblock-File` لتجاوز SmartScreen (`auto_update_service.dart:318-323`) قد لا يكفي على كل الأجهزة.

---

## 8. خطة Rollback

بما أن خدمة التحديث تقرأ حصراً **Release الموسوم latest**، فإن التراجع يتم بإعادة تعريف الـ latest:

1. **تراجع فوري (الأسرع)**: في صفحة Releases على `07706228120Hh/alsadara-FTTH`:
   - علّم إصدار v2.2.26 المعطوب كـ **pre-release** أو احذفه، و
   - أعد تعيين الإصدار السابق المستقر (`v2.2.25`) كـ **latest**.
   - النتيجة: العملاء الجدد الذين يستعلمون `releases/latest` سيرون `2.2.25` ولن يُحدَّثوا للنسخة المعطوبة. (العملاء الذين حدّثوا فعلاً لن يعودوا تلقائياً — التطبيق لا ينزّل نسخة أقدم لأن `_isNewerVersion` يرفض ذلك.)
2. **للأجهزة التي ثبّتت النسخة المعطوبة**: أصدر إصدار إصلاح أعلى (`v2.2.27`) بأسرع وقت؛ هو المسار الوحيد لدفع إصلاح تلقائياً لأن التطبيق لا يرجع لنسخة أقدم.
3. **حذف الأصل المعطوب**: أزل `Alsadara-Setup-v2.2.26.exe` من الـ Release لمنع أي تنزيل يدوي جديد.
4. **الـ Backend/DB (إن مسّه الإصدار)**: راجع توافق أي migration مع الإنتاج عبر `database-postgres-agent` قبل الإطلاق؛ لا تُطلق إصداراً يعتمد على migration لم يُطبَّق على الإنتاج (`72.61.183.61`). Rollback الـ backend خارج نطاق هذا التطبيق (SCP + `systemctl restart sadara-api`).

> ملاحظة مخاطر: لأن التطبيق لا يدعم downgrade، فإن أقوى ضمان قبل النشر هو **الاختبار على جهاز نظيف** بالمثبّت الناتج فعلياً قبل رفعه.

---

## 9. بنود تتطلب موافقة بشرية صريحة (حسب CLAUDE.md)

- `git push` لأي tag `v*` إلى origin (= إطلاق إنتاج) — Golden Rules #8, #9.
- إنشاء/تعديل GitHub Release أو رفع أصوله.
- أي تشغيل لـ `create_release.ps1` (يحوي push تلقائي).
- أي إصدار يعتمد على migration قاعدة بيانات (تنسيق مع `database-postgres-agent` + موافقة).

---

## 10. مراجع الملفات (مطلقة)

- `c:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth\pubspec.yaml` (سطر 5)
- `c:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth\installer.iss` (أسطر 4, 8, 9, 17, 30)
- `c:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth\lib\services\auto_update_service.dart` (أسطر 32-93, 99-102, 158-207, 210-274, 307-344)
- `c:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth\lib\widgets\update_dialog.dart` (أسطر 446-462)
- `c:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth\lib\pages\home_page.dart` (سطر 270-273)
- `c:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth\lib\pages\login\premium_login_page.dart` (سطر 518)
- `c:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth\windows\CMakeLists.txt` (سطر 7)
- `c:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth\CHANGELOG.md`
- `c:\SadaraPlatform\.github\workflows\build-windows.yml` (أسطر 6-10, 37-79)
- `c:\SadaraPlatform\.git\config` (سطر 12-14)
- سكربتات مهجورة: `c:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth\scripts\build\{create_release.ps1, build_complete.ps1, build_v1.2.8.ps1, MAKE_INSTALLER.bat}`
