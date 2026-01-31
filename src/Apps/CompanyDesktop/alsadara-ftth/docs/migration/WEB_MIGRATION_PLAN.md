# 🌐 خطة تحويل مشروع الصدارة من Windows Desktop إلى Web Multi-Tenant
## رفع على Hostinger

---

## 📋 ملخص تنفيذي

### الوضع الحالي
- **المنصة:** Windows Desktop (Flutter)
- **المصادقة:** نظامين منفصلين (Google Sheets + FTTH JWT API)
- **التخزين:** SharedPreferences + FlutterSecureStorage (محلي)
- **الإشعارات:** Firebase Messaging + Local Notifications
- **WebView:** webview_windows (خاص بـ Windows)

### الهدف
- **المنصة:** Web Application (Flutter Web)
- **البنية:** Multi-Tenant (حسابات متعددة معزولة)
- **الاستضافة:** Hostinger
- **التخزين:** Cloud (Firebase/Supabase) + Web Storage

---

## 🔴 التحديات الرئيسية والحلول

### 1. المكتبات غير المتوافقة مع الويب

| المكتبة | المشكلة | الحل |
|---------|---------|------|
| `window_manager` | خاص بـ Desktop | إزالة/تعطيل على الويب |
| `webview_windows` | خاص بـ Windows | استخدام `iframe` أو `url_launcher` |
| `flutter_secure_storage` | يستخدم نظام الملفات | استخدام `shared_preferences_web` + تشفير |
| `win32` / `ffi` | Windows APIs | إزالة/تعطيل على الويب |
| `local_auth` | البصمة/Face ID | إزالة على الويب |
| `geolocator` | GPS | استخدام `html.window.navigator.geolocation` |
| `printing` | طباعة محلية | استخدام `window.print()` |
| `path_provider` | نظام الملفات | استخدام IndexedDB/Web Storage |
| `windows_taskbar` | Taskbar Windows | إزالة على الويب |

### 2. هيكل الملفات المتأثرة

```
lib/
├── main.dart                              ⚠️ يحتاج تعديل (Platform checks)
├── services/
│   ├── windows_automation_service.dart    ❌ Windows فقط
│   ├── escpos_cutter.dart                 ❌ طابعة محلية
│   ├── ticket_updates_service.dart        ⚠️ Platform.isWindows
│   ├── export_service.dart                ⚠️ نظام الملفات
│   ├── local_database_service.dart        ⚠️ نظام الملفات
│   ├── local_cache_service.dart           ⚠️ نظام الملفات
│   └── badge_service.dart                 ⚠️ windows_taskbar
├── widgets/
│   ├── window_close_handler.dart          ❌ window_manager
│   ├── window_close_handler_fixed.dart    ❌ window_manager
│   └── platform_webview.dart              ⚠️ webview_windows
└── ftth/whatsapp/
    ├── whatsapp_bottom_window.dart        ⚠️ webview_windows
    └── whatsapp_floating_window.dart      ⚠️ webview_windows
```

---

## 🏗️ خطة التنفيذ المفصلة

### المرحلة 1: تجهيز البنية التحتية (1-2 أيام)

#### 1.1 إنشاء خدمة كشف المنصة
```dart
// lib/utils/platform_detector.dart
import 'package:flutter/foundation.dart' show kIsWeb;

class PlatformDetector {
  static bool get isWeb => kIsWeb;
  static bool get isDesktop => !kIsWeb;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get supportsPrinting => !kIsWeb;
  static bool get supportsLocalAuth => !kIsWeb;
  static bool get supportsWebView => true; // iframe على الويب
}
```

#### 1.2 إنشاء Wrapper للتخزين المشترك
```dart
// lib/services/storage/storage_service.dart
abstract class StorageService {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

// lib/services/storage/web_storage_service.dart
class WebStorageService implements StorageService {
  // استخدام localStorage مع تشفير AES
}

// lib/services/storage/desktop_storage_service.dart
class DesktopStorageService implements StorageService {
  // استخدام flutter_secure_storage
}
```

#### 1.3 تحديث pubspec.yaml
```yaml
dependencies:
  # إضافة
  universal_html: ^2.2.4
  
  # تعديل الشروط
  flutter_secure_storage: ^9.2.2  # سيُستخدم على Desktop فقط
  
  # حزم الويب
  url_launcher_web: ^2.0.0
```

---

### المرحلة 2: تعديل نقطة البداية (1 يوم)

#### 2.1 تعديل main.dart
```dart
import 'package:flutter/foundation.dart' show kIsWeb;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // إعداد مدير النوافذ للديسكتوب فقط
  if (!kIsWeb) {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.ensureInitialized();
      // ... إعدادات النافذة
    }
  }

  // Firebase (يعمل على الويب والـ Desktop)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // الإشعارات
  if (!kIsWeb) {
    await NotificationService.initialize();
    TicketUpdatesService.instance.start();
  } else {
    // Web Push Notifications (اختياري)
    await WebNotificationService.initialize();
  }

  runApp(
    kIsWeb 
      ? const MyApp() 
      : WindowCloseHandlerFixed(child: const SessionBootstrap(child: MyApp())),
  );
}
```

---

### المرحلة 3: نظام Multi-Tenant (2-3 أيام)

#### 3.1 هيكل قاعدة البيانات (Firebase Firestore)

```
firestore/
├── tenants/                          # الشركات/المؤسسات
│   └── {tenantId}/
│       ├── name: string
│       ├── domain: string
│       ├── createdAt: timestamp
│       ├── settings: map
│       └── subscription: map
│
├── users/                            # المستخدمين
│   └── {tenantId}/
│       └── {userId}/
│           ├── username: string
│           ├── email: string
│           ├── phone: string
│           ├── role: string
│           ├── permissions: map
│           ├── ftthCredentials: map (مشفرة)
│           └── lastLogin: timestamp
│
├── sessions/                         # الجلسات النشطة
│   └── {tenantId}/
│       └── {sessionId}/
│           ├── userId: string
│           ├── token: string
│           ├── device: string
│           ├── createdAt: timestamp
│           └── expiresAt: timestamp
│
└── audit_logs/                       # سجل العمليات
    └── {tenantId}/
        └── {logId}/
            ├── userId: string
            ├── action: string
            ├── details: map
            └── timestamp: timestamp
```

#### 3.2 نموذج Tenant
```dart
// lib/models/tenant.dart
class Tenant {
  final String id;
  final String name;
  final String domain;
  final Map<String, dynamic> settings;
  final TenantSubscription subscription;
  
  // إعدادات FTTH API الخاصة بالمؤسسة
  final String? ftthApiUrl;
  final String? ftthClientId;
  
  // إعدادات Google Sheets الخاصة
  final String? sheetsSpreadsheetId;
  final String? sheetsApiKey;
}

class TenantSubscription {
  final String plan; // free, basic, premium
  final int maxUsers;
  final DateTime expiresAt;
  final List<String> features;
}
```

#### 3.3 نموذج المستخدم المحسّن
```dart
// lib/models/tenant_user.dart
class TenantUser {
  final String id;
  final String tenantId;
  final String username;
  final String? email;
  final String? phone;
  final UserRole role;
  final Map<String, bool> permissions;
  
  // بيانات النظام الأول (Google Sheets)
  final String? department;
  final String? center;
  final String? salary;
  final Map<String, bool> pageAccess;
  
  // بيانات FTTH (مشفرة)
  final String? ftthUsername;
  final String? encryptedFtthPassword;
  final String? ftthToken;
  final DateTime? ftthTokenExpiry;
}

enum UserRole { superAdmin, tenantAdmin, manager, user, viewer }
```

#### 3.4 خدمة إدارة المستأجرين
```dart
// lib/services/tenant/tenant_service.dart
class TenantService {
  static TenantService? _instance;
  static TenantService get instance => _instance ??= TenantService._();
  TenantService._();
  
  Tenant? _currentTenant;
  TenantUser? _currentUser;
  
  Tenant? get currentTenant => _currentTenant;
  TenantUser? get currentUser => _currentUser;
  
  // تحديد المستأجر من الـ URL أو Subdomain
  Future<void> detectTenant() async {
    if (kIsWeb) {
      final uri = Uri.base;
      final subdomain = uri.host.split('.').first;
      // البحث عن المستأجر
      _currentTenant = await _fetchTenantByDomain(subdomain);
    }
  }
  
  // تسجيل دخول المستخدم
  Future<AuthResult> login(String username, String password) async {
    // 1. البحث عن المستخدم في المستأجر الحالي
    // 2. التحقق من كلمة المرور
    // 3. إنشاء جلسة
    // 4. تحميل الصلاحيات
  }
  
  // إنشاء مستأجر جديد (Super Admin فقط)
  Future<Tenant> createTenant(TenantCreateRequest request);
  
  // إضافة مستخدم للمستأجر (Tenant Admin فقط)
  Future<TenantUser> addUser(UserCreateRequest request);
}
```

---

### المرحلة 4: تعديل صفحات تسجيل الدخول (1-2 أيام)

#### 4.1 صفحة اختيار المستأجر/الشركة (جديدة)
```dart
// lib/pages/tenant_selection_page.dart
class TenantSelectionPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          children: [
            // شعار النظام
            Logo(),
            
            // حقل إدخال كود الشركة أو اختيار من قائمة
            TextField(
              decoration: InputDecoration(
                labelText: 'كود الشركة',
                hintText: 'مثال: alsadara',
              ),
            ),
            
            // أو اختيار من القائمة
            DropdownButton<Tenant>(...),
            
            // زر المتابعة
            ElevatedButton(
              onPressed: () => _selectTenant(),
              child: Text('متابعة'),
            ),
          ],
        ),
      ),
    );
  }
}
```

#### 4.2 تعديل صفحة تسجيل الدخول الرئيسية
```dart
// تعديل lib/pages/login_page.dart
class LoginPage extends StatefulWidget {
  final Tenant tenant; // المستأجر المحدد
  
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  Future<void> login() async {
    final result = await TenantService.instance.login(
      usernameController.text,
      passwordController.text,
      tenantId: widget.tenant.id,
    );
    
    if (result.isSuccess) {
      // حفظ بيانات الجلسة في Cloud
      await SessionService.saveSession(result.session);
      
      // الانتقال للصفحة الرئيسية
      Navigator.pushReplacement(...);
    }
  }
}
```

---

### المرحلة 5: تعديل الخدمات للويب (2-3 أيام)

#### 5.1 خدمة WebView للويب
```dart
// lib/widgets/web_safe_webview.dart
import 'package:flutter/foundation.dart' show kIsWeb;

class WebSafeWebView extends StatelessWidget {
  final String url;
  
  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // استخدام iframe أو فتح في تبويب جديد
      return HtmlElementView(
        viewType: 'iframe-$url',
        onPlatformViewCreated: (id) {
          // تهيئة iframe
        },
      );
    } else {
      // استخدام webview_windows على Desktop
      return WindowsWebView(url: url);
    }
  }
}
```

#### 5.2 خدمة الإشعارات للويب
```dart
// lib/services/web_notification_service.dart
import 'dart:html' as html;

class WebNotificationService {
  static Future<void> initialize() async {
    final permission = await html.Notification.requestPermission();
    if (permission == 'granted') {
      // الاشتراك في Firebase Cloud Messaging للويب
    }
  }
  
  static Future<void> show(String title, String body) async {
    html.Notification(title, body: body);
  }
}
```

#### 5.3 خدمة التصدير للويب
```dart
// lib/services/web_export_service.dart
import 'dart:html' as html;

class WebExportService {
  static Future<void> downloadExcel(List<int> bytes, String filename) async {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
  
  static Future<void> printPage() async {
    html.window.print();
  }
}
```

---

### المرحلة 6: لوحة إدارة المستأجرين (2 أيام)

#### 6.1 صفحة إدارة الشركات (Super Admin)
```dart
// lib/admin/tenants_management_page.dart
class TenantsManagementPage extends StatelessWidget {
  // قائمة جميع الشركات
  // إضافة شركة جديدة
  // تعديل إعدادات الشركة
  // إدارة الاشتراكات
}
```

#### 6.2 صفحة إدارة المستخدمين (Tenant Admin)
```dart
// lib/admin/users_management_page.dart
class UsersManagementPage extends StatelessWidget {
  // قائمة مستخدمي الشركة
  // إضافة مستخدم جديد
  // تعديل صلاحيات المستخدم
  // تعطيل/تفعيل المستخدم
  // إعادة تعيين كلمة المرور
}
```

---

### المرحلة 7: الأمان والتشفير (1-2 أيام)

#### 7.1 تشفير البيانات الحساسة
```dart
// lib/services/encryption_service.dart
import 'package:encrypt/encrypt.dart';

class EncryptionService {
  static final _key = Key.fromSecureRandom(32);
  static final _iv = IV.fromSecureRandom(16);
  static final _encrypter = Encrypter(AES(_key));
  
  static String encrypt(String plainText) {
    return _encrypter.encrypt(plainText, iv: _iv).base64;
  }
  
  static String decrypt(String encryptedText) {
    return _encrypter.decrypt64(encryptedText, iv: _iv);
  }
}
```

#### 7.2 حماية API Keys
```dart
// استخدام Firebase Functions لإخفاء المفاتيح
// lib/services/secure_api_service.dart
class SecureApiService {
  static Future<String> getGoogleSheetsData(String range) async {
    // استدعاء Firebase Function بدلاً من استخدام API Key مباشرة
    final result = await FirebaseFunctions.instance
        .httpsCallable('getGoogleSheetsData')
        .call({'range': range});
    return result.data;
  }
}
```

---

### المرحلة 8: البناء والنشر على Hostinger (1 يوم)

#### 8.1 بناء إصدار الويب
```bash
# بناء للإنتاج
flutter build web --release --web-renderer html

# أو مع canvaskit للأداء الأفضل
flutter build web --release --web-renderer canvaskit
```

#### 8.2 تكوين Hostinger

##### إعداد الاستضافة:
1. **اختيار خطة:** Business Web Hosting أو أعلى
2. **إضافة Domain:** alsadara.com أو subdomain
3. **SSL Certificate:** تفعيل Let's Encrypt
4. **PHP Version:** غير مطلوب (static files)

##### رفع الملفات:
```bash
# هيكل الملفات على الخادم
public_html/
├── index.html
├── main.dart.js
├── flutter.js
├── manifest.json
├── favicon.png
├── icons/
├── assets/
│   ├── fonts/
│   ├── images/
│   └── AssetManifest.json
└── canvaskit/ (إذا استخدمت canvaskit renderer)
```

##### ملف .htaccess للـ SPA:
```apache
<IfModule mod_rewrite.c>
  RewriteEngine On
  RewriteBase /
  RewriteRule ^index\.html$ - [L]
  RewriteCond %{REQUEST_FILENAME} !-f
  RewriteCond %{REQUEST_FILENAME} !-d
  RewriteRule . /index.html [L]
</IfModule>

# تمكين الضغط
<IfModule mod_deflate.c>
  AddOutputFilterByType DEFLATE text/html text/plain text/css application/javascript application/json
</IfModule>

# كاش للملفات الثابتة
<IfModule mod_expires.c>
  ExpiresActive on
  ExpiresByType text/css "access plus 1 year"
  ExpiresByType application/javascript "access plus 1 year"
  ExpiresByType image/png "access plus 1 year"
  ExpiresByType font/woff2 "access plus 1 year"
</IfModule>
```

#### 8.3 إعداد Firebase للويب
```javascript
// web/index.html - إضافة Firebase config
<script src="https://www.gstatic.com/firebasejs/9.x.x/firebase-app-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/9.x.x/firebase-firestore-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/9.x.x/firebase-messaging-compat.js"></script>
<script>
  firebase.initializeApp({
    apiKey: "YOUR_API_KEY",
    authDomain: "YOUR_PROJECT.firebaseapp.com",
    projectId: "YOUR_PROJECT",
    storageBucket: "YOUR_PROJECT.appspot.com",
    messagingSenderId: "YOUR_SENDER_ID",
    appId: "YOUR_APP_ID"
  });
</script>
```

---

## 📊 جدول المقارنة: قبل وبعد

| الميزة | Windows Desktop | Web Multi-Tenant |
|--------|-----------------|------------------|
| التخزين | محلي (SharedPreferences) | Cloud (Firestore) |
| المصادقة | Google Sheets + JWT | Firebase Auth + JWT |
| الجلسات | جلسة واحدة | جلسات متعددة معزولة |
| الإشعارات | Local + FCM | Web Push + FCM |
| WebView | webview_windows | iframe / popup |
| الطباعة | printing package | window.print() |
| الملفات | نظام الملفات | Download API |
| البصمة | local_auth | غير متاح |

---

## ⏱️ الجدول الزمني المقترح

| المرحلة | المدة | الأولوية |
|---------|-------|----------|
| 1. تجهيز البنية التحتية | 1-2 أيام | 🔴 عالية |
| 2. تعديل main.dart | 1 يوم | 🔴 عالية |
| 3. نظام Multi-Tenant | 2-3 أيام | 🔴 عالية |
| 4. صفحات تسجيل الدخول | 1-2 أيام | 🔴 عالية |
| 5. تعديل الخدمات | 2-3 أيام | 🟡 متوسطة |
| 6. لوحة الإدارة | 2 أيام | 🟡 متوسطة |
| 7. الأمان والتشفير | 1-2 أيام | 🔴 عالية |
| 8. البناء والنشر | 1 يوم | 🟡 متوسطة |

**المجموع:** 11-16 يوم عمل

---

## ⚠️ ملاحظات هامة

### 1. الحفاظ على التوافقية
- المشروع سيبقى يعمل على Windows Desktop
- استخدام `kIsWeb` للفصل بين المنصات
- عدم حذف أي كود Windows، فقط إضافة بدائل للويب

### 2. الاختبار
- اختبار على Chrome, Firefox, Safari, Edge
- اختبار الأداء مع بيانات كبيرة
- اختبار الأمان (XSS, CSRF)

### 3. قيود الويب
- لا يمكن الوصول لنظام الملفات مباشرة
- البصمة/Face ID غير متاحة
- WebSocket للـ Real-time بدلاً من polling

### 4. CORS
- تكوين Firebase Functions للسماح بالطلبات من domain الخاص
- تكوين FTTH API للسماح بالطلبات من domain الخاص

---

## 🎯 الخطوة التالية

**هل تريد البدء بالتنفيذ؟**

أنصح بالبدء بـ:
1. إنشاء `platform_detector.dart`
2. تعديل `main.dart` لدعم الويب
3. إنشاء هيكل Firestore للـ Multi-Tenant
4. تجربة `flutter build web` للتأكد من عمل البناء الأساسي

---

*تم إنشاء هذه الخطة في: ديسمبر 2025*
