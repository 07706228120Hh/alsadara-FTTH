# 📝 دليل تحديث البيانات التجريبية إلى بيانات حقيقية

في هذا الدليل سوف نتحدث عن كيفية تحديث جميع البيانات التجريبية إلى بيانات حقيقية في منصة الصدارة.

## 📋 جدول الملفات التي تحتاج للتحديث

| الملف | الوصف | الحالة |
|------|-------|--------|
| `deployment/firebase/.secrets.json` | بيانات Firebase | ✅ ملف موجود، تحتاج لتحديث |
| `deployment/vps/.secrets.json` | بيانات VPS | ✅ ملف موجود، تحتاج لتحديث |
| `src/Backend/API/Sadara.API/secrets/firebase-service-account.json` | مفتاح Firebase Service Account | ✅ ملف موجود، تحتاج لتحديث |
| `src/Apps/CompanyDesktop/alsadara-ftth/assets/service_account.json` | مفتاح Google Sheets | ✅ ملف موجود، تحتاج لتحديث |
| `src/Apps/CompanyDesktop/alsadara-ftth/assets/config.json` | إعدادات API و Sheet ID | ✅ ملف موجود، تحتاج لتحديث |
| `.env` | متغيرات البيئة | ✅ ملف موجود، تحتاج لتحديث |

---

## 🔑 الخطوة 1: تحديث Firebase

### 1.1 الحصول على ملف Service Account من Firebase Console
1. اذهب إلى [Firebase Console](https://console.firebase.google.com/)
2. اختر مشروعك
3. اضغط على **⚙️ Project Settings** → **Service Accounts**
4. اضغط على **Generate New Private Key**
5. اضغط على **Generate Key** → سيتم تحميل ملف JSON
6. قم بتسميته `firebase-service-account.json`
7. احفظه في المسار:
   ```
   src/Backend/API/Sadara.API/secrets/firebase-service-account.json
   ```

### 1.2 تحديث ملف `.secrets.json` لـ Firebase
افتح الملف `deployment/firebase/.secrets.json` وقم بتحديث هذه القيم من Firebase Console:

```json
{
  "project": {
    "projectId": "YOUR_PROJECT_ID",        // من Project Settings
    "projectNumber": "YOUR_PROJECT_NUMBER",  // من Project Settings
    "webApiKey": "YOUR_WEB_API_KEY"         // من Project Settings > General
  },
  "serviceAccount": {
    "type": "service_account",
    "project_id": "YOUR_PROJECT_ID",        // من الملف المحمل
    "private_key_id": "YOUR_PRIVATE_KEY_ID",  // من الملف المحمل
    "private_key": "-----BEGIN PRIVATE KEY-----\nYOUR_PRIVATE_KEY\n-----END PRIVATE KEY-----\n", // من الملف
    "client_email": "YOUR_CLIENT_EMAIL",    // من الملف
    "client_id": "YOUR_CLIENT_ID",          // من الملف
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token"
  },
  "cloudMessaging": {
    "serverKey": "YOUR_FCM_SERVER_KEY",    // من Cloud Messaging
    "vapidKey": "YOUR_VAPID_KEY"           // من Cloud Messaging
  }
}
```

---

## 📊 الخطوة 2: تحديث Google Sheets

### 2.1 الحصول على ملف Service Account من Google Cloud Console
1. اذهب إلى [Google Cloud Console](https://console.cloud.google.com/)
2. اختر مشروع Firebase الخاص بك
3. اذهب إلى **APIs & Services** → **Credentials**
4. اضغط على **Create Credentials** → **Service Account**
5. أدخل اسم الخدمة (مثال: `sheets-access`)
6. اضغط على **Create and Continue**
7. للدور، اختر **Project > Owner** → **Continue**
8. اضغط على **Done**
9. في صفحة الخدمة → اضغط على **Keys** → **Add Key** → **Create New Key**
10. اختر **JSON** → اضغط على **Create**
11. سيتم تحميل ملف JSON، قم بتسميته `service_account.json`
12. احفظه في المسار:
    ```
    src/Apps/CompanyDesktop/alsadara-ftth/assets/service_account.json
    ```

### 2.2 تحديث config.json
افتح `src/Apps/CompanyDesktop/alsadara-ftth/assets/config.json` وثبّت Sheet ID:

```json
{
  "apiUrl": "http://localhost:5000",
  "sheetId": "YOUR_GOOGLE_SHEET_ID",  // ✅ هذا الحقل يتغير
  "maxUploadSize": 5
}
```

لحصول على Sheet ID:
1. اذهب إلى Google Sheets
2. أنشئ جدولاً جديداً أو افتح جدول موجود
3. انسخ الـ ID من الرابط: `https://docs.google.com/spreadsheets/d/[SHEET_ID]/edit#gid=0`

---

## 🌐 الخطوة 3: تحديث VPS

### 3.1 تحديث ملف `.secrets.json` لـ VPS
افتح `deployment/vps/.secrets.json` وثبّت بيانات VPS الحقيقية:

```json
{
  "ssh": {
    "host": "YOUR_SERVER_IP",            // مثلاً: 72.61.183.61
    "port": 22,
    "user": "root",
    "password": "YOUR_SSH_PASSWORD",     // كلمة مرور VPS
    "privateKeyPath": ""
  },
  "database": {
    "host": "localhost",
    "port": 5432,
    "name": "sadara_db",
    "user": "sadara_user",
    "password": "YOUR_DB_PASSWORD",      // كلمة مرور PostgreSQL
    "connectionString": "Host=localhost;Port=5432;Database=sadara_db;Username=sadara_user;Password=YOUR_DB_PASSWORD"
  },
  "api": {
    "jwtSecret": "YOUR_JWT_SECRET_AT_LEAST_64_CHARACTERS_LONG",
    "jwtIssuer": "SadaraPlatform",
    "jwtAudience": "SadaraClients"
  },
  "superAdmin": {
    "phone": "YOUR_ADMIN_PHONE",         // رقم هاتف المدير
    "password": "YOUR_ADMIN_PASSWORD",   // كلمة مرور المدير
    "email": "admin@yourdomain.com"
  },
  "ssl": {
    "certificatePath": "/etc/ssl/certs/your-cert.crt",
    "keyPath": "/etc/ssl/private/your-key.key",
    "letsEncryptEmail": "your@email.com"
  }
}
```

---

## 🔧 الخطوة 4: تحديث .env (متغيرات البيئة)

افتح الملف `.env` وثبّت القيم الحقيقية:

```env
# Database Configuration
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=SadaraDB
POSTGRES_USER=postgres
POSTGRES_PASSWORD=YOUR_DB_PASSWORD  # ✅ تحديث

# JWT Configuration
JWT_SECRET_KEY=YOUR_JWT_SECRET_KEY  # ✅ تحديث (32 حرف)
JWT_EXPIRY_DAYS=7
JWT_ISSUER=SadaraPlatform
JWT_AUDIENCE=SadaraUsers

# Firebase Configuration
FIREBASE_PROJECT_ID=YOUR_PROJECT_ID  # ✅ تحديث
FIREBASE_API_KEY=YOUR_WEB_API_KEY   # ✅ تحديث
FIREBASE_AUTH_DOMAIN=YOUR_PROJECT.firebaseapp.com
FIREBASE_DATABASE_URL=https://YOUR_PROJECT.firebaseio.com
FIREBASE_STORAGE_BUCKET=YOUR_PROJECT.appspot.com
FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID  # ✅ تحديث
FIREBASE_APP_ID=YOUR_APP_ID         # ✅ تحديث

# VPS Configuration
VPS_HOST=YOUR_SERVER_IP             # ✅ تحديث (مثل: 72.61.183.61)
VPS_PORT=22
VPS_USER=root
VPS_PASSWORD=YOUR_SSH_PASSWORD      # ✅ تحديث

# API Configuration
API_URL=http://localhost:5000
API_KEY=YOUR_API_KEY                # ✅ تحديث
```

---

## 🚀 الخطوة 5: إعادة تشغيل المشروع

### 5.1 إيقاف الخدمات الحالية
```powershell
# في Terminal 1: اضغط Ctrl+C لإيقاف API
# في Terminal 2: اضغط Ctrl+C لإيقاف Flutter
```

### 5.2 تشغيل API مرة أخرى
```powershell
cd src\Backend\API\Sadara.API
dotnet run --urls "http://localhost:5000"
```

### 5.3 تشغيل Flutter مرة أخرى
```powershell
cd src\Apps\CompanyDesktop\alsadara-ftth
flutter run -d windows
```

---

## ✅ خطوات التحقق من الصحة

### 5.1 فحص API
1. افتح المتصفح واذهب إلى: http://localhost:5000/swagger
2. حاول الاتصال برقم الهاتف: +9647701234567 و كلمة المرور: Admin@123
3. إذا نجح التسجيل → API يعمل بشكل صحيح

### 5.2 فحص Flutter
1. عند فتح التطبيق، قم بتسجيل الدخول بنفس الحساب
2. إذا وجدت أن **لوحة التحكم** تحمل البيانات → Flutter يعمل

### 5.3 فحص Google Sheets
1. اذهب إلى Google Sheets
2. انسخ الـ Sheet ID إلى `config.json`
3. أضف بيانات من خلال التطبيق
4. تأكد من ظهور البيانات في Google Sheets

---

## 🔍 المشاكل الشائعة

### مشكلة 1: Firebase Auth Failed
**الأسباب**:
- ملف `firebase-service-account.json` غير صحيح
- API Key غير صحيح في `.env`

**الحل**:
- تحقق من صحة الملفات المحملة من Firebase Console
- تأكد من تطابق البيانات في `.env` مع Project Settings

### مشكلة 2: Google Sheets لا يظهر البيانات
**الأسباب**:
- `service_account.json` غير صحيح
- `sheetId` غير صحيح في `config.json`
- الخدمة `Google Sheets API` غير مفعلة في Google Cloud Console

**الحل**:
- تحقق من ملف `service_account.json`
- تأكد من تفعيل Google Sheets API
- احصل على Sheet ID صحيح من الرابط

### مشكلة 3: لا يمكن الاتصال بالـ API من Flutter
**الأسباب**:
- API URL غير صحيح في `config.json`
- فايروال معطل
- API لا يعمل

**الحل**:
- تأكد من تشغيل API على http://localhost:5000
- تحقق من API URL في `config.json`
- قم بإيقاف Windows Defender Firewall مؤقتاً للاختبار

---

## 📝 ملاحظات مهمة

1. **لا تنسوا**: جميع ملفات `.secrets.json` و `service_account.json` **لا يجب رفعها إلى GitHub**
2. **الرجوع**: يمكنك استخدام نسخة من `.env.example` لاستعادة القيم الافتراضية
3. **النسخ الاحتياطي**: قبل أي تحديث، قم بنسخ احتياطي من الملفات المُتغيرة

باستكمال هذه الخطوات، سيكون مشروعك جاهزاً للاستخدام مع بيانات حقيقية!
