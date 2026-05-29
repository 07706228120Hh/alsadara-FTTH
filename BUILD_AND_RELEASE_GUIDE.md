# دليل البناء والنشر — منصة الصدارة (Sadara Platform)

## المعلومات الأساسية

| المعلومة | القيمة |
|----------|--------|
| مسار المشروع | `c:\SadaraPlatform` |
| مسار Flutter | `src/Apps/CompanyDesktop/alsadara-ftth/` |
| مسار Backend | `src/Backend/API/Sadara.API/` |
| Flutter SDK | `D:\flutter\flutter\bin\flutter.bat` |
| Inno Setup | `C:\Program Files (x86)\Inno Setup 6\ISCC.exe` |
| سيرفر VPS | `root@72.61.183.61` |
| مسار API على السيرفر | `/var/www/sadara-api/` |
| GitHub Repo | `07706228120Hh/alsadara-FTTH` |
| Branch | `master` |

---

## الخطوات الكاملة للبناء والنشر

### الخطوة 1: فحص التعديلات غير المنشورة

```bash
cd "c:\SadaraPlatform"
git status -s | grep -v "^?? tmp_" | grep -v "^?? node_modules" | grep -v "^?? backup_"
```

- إذا 0 ملفات ← تحقق من commits جديدة بعد آخر release:
  ```bash
  head -5 "src/Apps/CompanyDesktop/alsadara-ftth/pubspec.yaml"
  git log --oneline -5
  ```

### الخطوة 2: تحقق من البناء (Backend)

```bash
cd "c:\SadaraPlatform\src\Backend\API\Sadara.API"
dotnet build -c Release 2>&1 | grep -E "Error|succeeded"
```

- يجب أن يكون: `Build succeeded. 0 Error(s)`

### الخطوة 3: تحديث الإصدار

**ملف pubspec.yaml** — تحديث version:
```yaml
# المسار: src/Apps/CompanyDesktop/alsadara-ftth/pubspec.yaml
# السطر 5
version: X.Y.Z+NNN  →  version: X.Y.Z+1+NNN+1
```

**ملف installer.iss** — تحديث AppVersion و OutputBaseFilename:
```ini
# المسار: src/Apps/CompanyDesktop/alsadara-ftth/installer.iss
AppVersion=X.Y.Z+1
OutputBaseFilename=Alsadara-Setup-vX.Y.Z+1
```

### الخطوة 4: البناء (بالتوازي)

**Windows:**
```bash
cd "c:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth"
"D:\flutter\flutter\bin\flutter.bat" build windows --release
```

**Android (حجم صغير — split per ABI):**
```bash
cd "c:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth"
"D:\flutter\flutter\bin\flutter.bat" build apk --release --split-per-abi
```

**Backend (إذا في تعديلات backend):**
```bash
cd "c:\SadaraPlatform\src\Backend\API\Sadara.API"
dotnet publish -c Release -o ./publish_temp
```

### الخطوة 5: بناء Windows Installer (بعد اكتمال Windows build)

```bash
cd "c:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth"
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss
```

**الناتج:** `build/installer/Alsadara-Setup-vX.Y.Z.exe`

### الخطوة 6: نشر Backend على VPS (إذا في تعديلات backend)

**الطريقة السريعة (DLLs فقط):**
```bash
scp publish_temp/Sadara.API.dll publish_temp/Sadara.Domain.dll \
    publish_temp/Sadara.Infrastructure.dll publish_temp/Sadara.Application.dll \
    root@72.61.183.61:/var/www/sadara-api/

ssh root@72.61.183.61 "systemctl restart sadara-api"
```

**التحقق:**
```bash
ssh root@72.61.183.61 "systemctl status sadara-api --no-pager | head -5"
```

### الخطوة 7: Git Commit + Push

```bash
cd "c:\SadaraPlatform"
git add -A -- ':!tmp_ex*.json' ':!node_modules' ':!backup_*.csv'
git commit -m "$(cat <<'EOF'
feat: vX.Y.Z+NNN — وصف التغييرات

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin master
```

### الخطوة 8: إنشاء GitHub Release

```bash
cd "c:\SadaraPlatform"
gh release create vX.Y.Z \
  "src/Apps/CompanyDesktop/alsadara-ftth/build/installer/Alsadara-Setup-vX.Y.Z.exe#Alsadara-Setup-vX.Y.Z.exe" \
  "src/Apps/CompanyDesktop/alsadara-ftth/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk#alsadara-vX.Y.Z-arm64.apk" \
  "src/Apps/CompanyDesktop/alsadara-ftth/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk#alsadara-vX.Y.Z-armeabi.apk" \
  --title "وصف الإصدار — vX.Y.Z" \
  --notes "$(cat <<'EOF'
## vX.Y.Z+NNN

### التحسينات
- وصف التغيير 1
- وصف التغيير 2
EOF
)"
```

---

## مسارات الملفات الناتجة

| الملف | المسار |
|-------|--------|
| Windows Installer | `build/installer/Alsadara-Setup-vX.Y.Z.exe` |
| Android APK (حديث) | `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` |
| Android APK (قديم) | `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` |
| Backend DLLs | `publish_temp/*.dll` |

---

## ملاحظات مهمة

1. **`--split-per-abi`** يقلل حجم APK من ~120MB لـ ~46MB
2. **الملفات المستثناة** من git: `tmp_ex*.json`, `node_modules/`, `backup_*.csv`
3. **Backend deploy** فقط إذا في تعديلات على ملفات في `src/Backend/`
4. **Inno Setup** يبني installer بعد اكتمال Windows build
5. **الإصدارات**: `version: major.minor.patch+buildNumber` — patch يزيد 1 كل مرة، buildNumber يزيد 1
6. **GitHub Release**: يشمل 3 ملفات (Windows installer + 2 APKs)

---

## مثال كامل (نسخ ولصق)

```bash
# 1. فحص
cd "c:\SadaraPlatform"
git status -s | grep -v "^?? tmp_" | grep -v "^?? node_modules" | grep -v "^?? backup_"

# 2. تحقق backend
cd "c:\SadaraPlatform\src\Backend\API\Sadara.API" && dotnet build -c Release 2>&1 | grep -E "Error|succeeded"

# 3. تحديث الإصدار (يدوياً في pubspec.yaml و installer.iss)

# 4. بناء بالتوازي
cd "c:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth"
"D:\flutter\flutter\bin\flutter.bat" build windows --release &
"D:\flutter\flutter\bin\flutter.bat" build apk --release --split-per-abi &

# 5. Backend (إذا لزم)
cd "c:\SadaraPlatform\src\Backend\API\Sadara.API"
dotnet publish -c Release -o ./publish_temp
scp ./publish_temp/Sadara.API.dll ./publish_temp/Sadara.Domain.dll ./publish_temp/Sadara.Infrastructure.dll ./publish_temp/Sadara.Application.dll root@72.61.183.61:/var/www/sadara-api/
ssh root@72.61.183.61 "systemctl restart sadara-api"

# 6. Installer (بعد Windows build)
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss

# 7. Git
cd "c:\SadaraPlatform"
git add -A -- ':!tmp_ex*.json' ':!node_modules' ':!backup_*.csv'
git commit -m "feat: vX.Y.Z — الوصف"
git push origin master

# 8. Release
gh release create vX.Y.Z \
  "src/.../Alsadara-Setup-vX.Y.Z.exe#Alsadara-Setup-vX.Y.Z.exe" \
  "src/.../app-arm64-v8a-release.apk#alsadara-vX.Y.Z-arm64.apk" \
  "src/.../app-armeabi-v7a-release.apk#alsadara-vX.Y.Z-armeabi.apk" \
  --title "الوصف — vX.Y.Z" --notes "التفاصيل"
```

---

## للمحادثة الجديدة — انسخ هذا:

> تاكد بان كل التعديلات في المحادثات الاخرى قد تم نشرها ولا يوجد شي متبقي.
> قم بتحديث الاصدار وابني من جديد وارفعه على كيت.
> اتبع الخطوات في ملف `BUILD_AND_RELEASE_GUIDE.md` في جذر المشروع.
