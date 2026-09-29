# نشر «تطبيق الوكلاء» (Aluklaa)

منتج مستقل بثلاثة أنماط نشر من **كود واحد**.

## 1) ويندوز — تثبيت محلي (الأسهل للوكيل الفرد)

الخادم مضمّن (`backend.exe`) وقاعدة البيانات SQLite محلية.

- **البناء والتحزيم** (على جهاز التطوير، مسار لاتيني):
  ```bat
  cd frontend && flutter build windows --release --dart-define=API_BASE=http://127.0.0.1:8000 --dart-define=APP_VERSION=1.0.0
  cd ..\backend && .venv\Scripts\pyinstaller backend.spec --noconfirm
  "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\aluklaa.iss
  ```
  الناتج: `installer\output\AluklaaSetup.exe` — ملف واحد يُوزَّع لأي جهاز ويندوز.
- **التثبيت**: تشغيل `AluklaaSetup.exe` (لكل مستخدم، بلا صلاحيات مدير) → اختصار سطح المكتب/قائمة ابدأ.
- قاعدة البيانات تُوضع في `%LOCALAPPDATA%\Aluklaa` (قابل للكتابة) عبر `ALUKLAA_DATA_DIR` في المشغّل.

## 2) سحابي — خادم مستضاف (يخدم الويب والهاتف)

Postgres + الباكند عبر Docker.

```bash
cp env.production.example .env      # املأ القيم الإلزامية
docker compose up -d --build
```
- عيّن في `.env`: `SECRET_KEY` (قوي) · `API_TOKEN` · `POSTGRES_PASSWORD` · `DEFAULT_ADMIN_PASSWORD` (قوية) · `CORS_ORIGINS`.
- ضع الباكند خلف عاكس (Nginx/Traefik) مع TLS، ولا تنشر منفذ Postgres.

## 3) الهاتف — أندرويد/iOS (يتصل بالخادم السحابي)

```bash
cd frontend
flutter build apk --release --dart-define=API_BASE=https://api.<your-domain>
flutter build ipa --release --dart-define=API_BASE=https://api.<your-domain>
```
- أيقونات الإطلاق مولّدة (`dart run flutter_launcher_icons`). الاسم المعروض: «تطبيق الوكلاء».
- الهاتف **لا يضمّن** خادماً — يجب أن يشير `API_BASE` إلى الخادم السحابي (النمط 2).

## جدول الأنماط

| النمط | الخادم | قاعدة البيانات | العميل | `API_BASE` |
|---|---|---|---|---|
| ويندوز محلي | `backend.exe` مضمّن | SQLite (`%LOCALAPPDATA%\Aluklaa`) | تطبيق ويندوز | `http://127.0.0.1:8000` |
| سحابي | Docker (مستضاف) | Postgres | ويب/هاتف | `https://api.<domain>` |
| هاتف | (سحابي) | (سحابي) | أندرويد/iOS | `https://api.<domain>` |

## الأمان في الإنتاج
الباكند **يرفض الإقلاع** بإعداد غير آمن عند `USE_MOCK_OLT=false`: `SECRET_KEY` قوي · `API_TOKEN` مضبوط · كلمة مرور مدير غير `admin` · `OTP_DEV_ECHO` مطفأ.
