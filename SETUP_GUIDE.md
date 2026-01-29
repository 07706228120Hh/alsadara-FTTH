# 📚 دليل إعداد منصة الصدارة (Sadara Platform)

## 🚨 الخطوات الأساسية قبل التشغيل

### 1. تحديث كلمات المرور في ملف `.env`

```powershell
# افتح الملف .env في أي محرر نصوص
code .env
```

قم بتغيير جميع القيم التي تحتوي على `CHANGE_THIS` أو `your_secure_password_here`:

```env
# Database
POSTGRES_PASSWORD=your_secure_password_here  # ❗ تغيير

# JWT Security
JWT_SECRET_KEY=YourSuperSecretKeyThatIsAtLeast32CharactersLong!  # ❗ تغيير

# VPS
VPS_PASSWORD=CHANGE_VPS_PASSWORD  # ❗ تغيير

# Encryption
ENCRYPTION_KEY=ChangeThisToASecure32CharacterKey!  # ❗ تغيير
ENCRYPTION_IV=ChangeThisTo16Characters!  # ❗ تغيير
```

### 2. إنشاء ملفات الخدمات (Google Sheets + Firebase)

#### A. Google Sheets API - service_account.json

1. اذهب إلى [Google Cloud Console](https://console.cloud.google.com/)
2. انشئ مشروع جديد اسمه `Sadara Platform`
3. اذهب إلى **API & Services** → **Enable APIs & Services**
4. ابحث عن "Google Sheets API" وافتحها
5. اضغط على "Enable"
6. اذهب إلى **Credentials** → **Create Credentials** → **Service Account**
7. أدخل اسم الخدمة مثلاً `sheets-access`
8. لاحقاً (نمرّ 3): اضغط على "Done" لا تضغط على anything else now

للحصول على ملف JSON:
1. في صفحة الخدمات → اضغط على الخدمة التي أنشأتها
2. اضغط على **Keys** → **Add Key** → **Create New Key**
3. اختر "JSON" → اضغط على "Create"
4. سيتم تحميل ملف JSON تلقائياً
5. قم بتسميته `service_account.json`
6. ضع الملف في هذا المسار:
   ```
   src/Apps/CompanyDesktop/alsadara-ftth/assets/service_account.json
   ```

#### B. Firebase Service Account - firebase-service-account.json

1. اذهب إلى [Firebase Console](https://console.firebase.google.com/)
2. انشئ مشروع جديد بنفس الاسم
3. اضغط على **Settings** (⚙️) → **Project Settings** → **Service Accounts**
4. اضغط على **Generate New Private Key**
5. اضغط على "Generate Key" → سيتم تحميل ملف JSON
6. قم بتسميته `firebase-service-account.json`
7. ضع الملف في هذا المسار:
   ```
   src/Backend/API/Sadara.API/secrets/firebase-service-account.json
   ```

**إليك قالب للمحتوى:**
```json
{
  "type": "service_account",
  "project_id": "YOUR_PROJECT_ID",
  "private_key_id": "YOUR_PRIVATE_KEY_ID",
  "private_key": "-----BEGIN PRIVATE KEY-----\nYOUR_PRIVATE_KEY\n-----END PRIVATE KEY-----\n",
  "client_email": "YOUR_CLIENT_EMAIL",
  "client_id": "YOUR_CLIENT_ID",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/YOUR_CLIENT_EMAIL"
}
```

### 3. تكوين ملف config.json للـ Flutter

```powershell
# افتح الملف التالي
code src/Apps/CompanyDesktop/alsadara-ftth/assets/config.json
```

قم بتحديث بهذه البيانات:
```json
{
  "apiUrl": "http://localhost:5000",
  "sheetId": "YOUR_GOOGLE_SHEET_ID",
  "maxUploadSize": 5
}
```

### 4. تشغيل PostgreSQL

#### إذا لم يكن مثبتاً:
1. حمل من [PostgreSQL Official Site](https://www.postgresql.org/download/windows/)
2. التثبيت: اتبع التعليمات (تأكد من تشغيل Stack Builder)
3. حدد كلمة مرور متينة (سيتم استخدامها في ملف .env)

#### تشغيل خدمة PostgreSQL:
```powershell
# تحقق من حالتها
Get-Service -Name postgresql*
```

إذا كانت موقوفة:
```powershell
Start-Service -Name postgresql-x64-15
```

### 5. تشغيل migrations لقاعدة البيانات

```powershell
cd scripts
.\setup-database.ps1 -Environment Development -Clean $true
```

## 🚀 تشغيل المشروع

### 1. تشغيل API
```powershell
cd src\Backend\API\Sadara.API
dotnet run --urls "http://localhost:5000"
```

### 2. تشغيل Flutter (في نافذة جديدة)
```powershell
cd src\Apps\CompanyDesktop\alsadara-ftth
flutter pub get
flutter run -d windows
```

### 3. التحقق من الاتصال
- **API**: http://localhost:5000
- **Swagger UI**: http://localhost:5000/swagger
- **Super Admin**: Email `admin@sadara.com`, Password `Admin@123`

## 📁 هياكل الملفات

```
C:\SadaraPlatform\
├── src\
│   ├── Apps\CompanyDesktop\alsadara-ftth\
│   │   └── assets\
│   │       ├── config.json          ← يحتوي على API URL
│   │       └── service_account.json ← مفتاح Google Sheets
│   └── Backend\API\Sadara.API\
│       ├── secrets\
│       │   └── firebase-service-account.json ← مفتاح Firebase
│       ├── appsettings.Development.json
│       └── Program.cs
├── .env                             ← متغيرات البيئة
├── docker\
│   ├── docker-compose.yaml
│   └── Dockerfile
└── scripts\
    ├── setup-database.ps1
    └── run-without-docker.ps1
```

## 🔒 الأمان

- **لا ترفع ملفات .env أو secrets إلى GitHub**
- **تغيير كلمة مرور Super Admin فورياً**:
  ```powershell
  # بعد تشغيل API:
  Invoke-RestMethod -Uri "http://localhost:5000/api/auth/change-password" -Method POST -Body @{
      PhoneNumber = "+9647801234567"
      OldPassword = "Admin@123"
      NewPassword = "YourNewSecurePassword!2025"
  } -ContentType "application/json"
  ```

## ❓ مساعدة إضافية

إذا كنت تواجه أي مشاكل:
1. تحقق من أنك وصلت إلى Internet
2. تأكد من تشغيل PostgreSQL
3. فحص ملف `.env` للتأكد من كلمات المرور
4. فحص ملف config.json للتأكد من API URL

## 📱 ملفات مطلوبة إضافية (لو لزم الأمر)

### assets/users_fallback.json

```json
[
  {
    "id": "1",
    "name": "مستخدم تجريبي",
    "phone": "07701234567",
    "email": "test@example.com"
  }
]
```

### secrets/vps_ssh_key.pem

إذا كنت تستخدم VPS، يمكنك إضافة مفتاح SSH.

## ✅ قائمة التحقق قبل الإطلاق

- [ ] تحديث كلمات المرور في .env
- [ ] تحميل service_account.json إلى assets/
- [ ] تحميل firebase-service-account.json إلى secrets/
- [ ] تكوين config.json
- [ ] تشغيل setup-database.ps1
- [ ] تشغيل API بنجاح
- [ ] تشغيل Flutter بنجاح
- [ ] تسجيل الدخول إلى Super Admin
