# Firebase Setup Guide for Sadara Platform

## المتطلبات
- Node.js 18+
- Firebase CLI (`npm install -g firebase-tools`)
- حساب Firebase

## الخطوات

### 1. تسجيل الدخول لـ Firebase
```bash
firebase login
```

### 2. إنشاء مشروع Firebase جديد
```bash
firebase projects:create sadara-platform
```

### 3. تهيئة المشروع
```bash
firebase init
```
اختر:
- Firestore
- Storage
- Authentication
- Hosting (اختياري)

### 4. نشر القواعد
```bash
firebase deploy --only firestore:rules
firebase deploy --only storage:rules
```

## إعداد Authentication

### تفعيل Phone Authentication
1. اذهب لـ Firebase Console
2. Authentication > Sign-in method
3. فعّل Phone
4. أضف أرقام اختبار:
   - `+9647700000001` → `123456`

### تفعيل Email Authentication (اختياري)
1. Authentication > Sign-in method
2. فعّل Email/Password

## إعداد Flutter App

### 1. تثبيت FlutterFire CLI
```bash
dart pub global activate flutterfire_cli
```

### 2. تكوين Firebase للتطبيق
```bash
flutterfire configure --project=sadara-platform
```

### 3. إضافة الحزم
```yaml
# pubspec.yaml
dependencies:
  firebase_core: ^2.24.0
  firebase_auth: ^4.16.0
  cloud_firestore: ^4.14.0
  firebase_storage: ^11.6.0
  firebase_messaging: ^14.7.0
```

## المتغيرات البيئية

### Android (android/app/google-services.json)
يتم إنشاؤه تلقائياً بواسطة `flutterfire configure`

### iOS (ios/Runner/GoogleService-Info.plist)
يتم إنشاؤه تلقائياً بواسطة `flutterfire configure`

### Web (web/index.html)
```html
<script src="https://www.gstatic.com/firebasejs/9.0.0/firebase-app-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/9.0.0/firebase-auth-compat.js"></script>
```

## اختبار الاتصال

```dart
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Test connection
  print('Firebase initialized: ${Firebase.apps.isNotEmpty}');
  
  runApp(MyApp());
}
```

## الأمان

⚠️ **مهم:**
- لا تشارك `google-services.json` أو `GoogleService-Info.plist` علنياً
- استخدم App Check لحماية إضافية
- راجع القواعد قبل النشر للإنتاج

## الدعم

للمساعدة:
- [Firebase Documentation](https://firebase.google.com/docs)
- [FlutterFire Documentation](https://firebase.flutter.dev/)
