# 📚 الدرس #6: تطبيق Flutter Desktop

## 🎯 ما هو تطبيق Flutter؟

**Flutter** هو framework لبناء تطبيقات متعددة المنصات:
- ✅ Windows Desktop
- ✅ Android
- ✅ iOS
- ✅ Web

**في هذا المشروع:** نستخدم Flutter لتطبيق سطح المكتب (Windows).

---

## 📁 هيكل المجلد

```
src/Apps/CompanyDesktop/alsadara-ftth/lib/
├── main.dart               ← نقطة البداية
├── firebase_options.dart   ← إعدادات Firebase
│
├── config/                 ← الإعدادات
│   └── data_source_config.dart
│
├── models/                 ← نماذج البيانات
│   ├── user_model.dart
│   └── ...
│
├── pages/                  ← الصفحات (UI)
│   ├── login_page.dart
│   ├── home_page.dart
│   ├── admin/
│   └── super_admin/
│
├── services/               ← الخدمات (منطق العمل)
│   ├── api_service.dart
│   ├── auth_service.dart
│   └── ...
│
├── widgets/                ← مكونات مشتركة
│   ├── permissions_gate.dart
│   └── ...
│
├── theme/                  ← السمة (ألوان، خطوط)
│   └── app_theme.dart
│
└── utils/                  ← أدوات مساعدة
```

---

## 🚀 main.dart - نقطة البداية

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 📊 تهيئة Error Reporter
  await ErrorReporterService.instance.initialize();

  // إعداد نافذة Windows
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      center: true,
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.maximize();
    });
  }

  // تحميل Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // تشغيل التطبيق
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'منصة الصدارة',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      theme: AppTheme.lightTheme,
      home: _buildHomePage(),
    );
  }
}
```

---

## ⚙️ مصادر البيانات

### الملف: `config/data_source_config.dart`

```dart
enum DataSource {
  firebase,   // Firebase Firestore
  vpsApi,     // VPS API (.NET)
}

class DataSourceConfig {
  // المصدر الحالي
  static const DataSource currentSource = DataSource.vpsApi;
  
  // رابط API
  static const String apiBaseUrl = 'https://api.ftth.iq/api';
}
```

**💡 ملاحظة:** التطبيق يدعم مصدرين للبيانات:
1. **Firebase:** للشركات الصغيرة
2. **VPS API:** للشركات الكبيرة (المُستخدم حالياً)

---

## 🔧 Services - الخدمات

### نمط Singleton

```dart
class ApiService {
  // Singleton instance
  static ApiService? _instance;
  static ApiService get instance => _instance ??= ApiService._internal();
  
  // Private constructor
  ApiService._internal();

  // Methods
  Future<Map<String, dynamic>> get(String endpoint) async {
    final response = await http.get(Uri.parse('$baseUrl$endpoint'));
    return json.decode(response.body);
  }
}
```

**الاستخدام:**
```dart
// من أي مكان في التطبيق
final data = await ApiService.instance.get('/users');
```

### قائمة الخدمات الرئيسية

| الخدمة | الملف | الوظيفة |
|--------|-------|---------|
| `ApiService` | api_service.dart | HTTP requests للـ API |
| `AuthService` | auth_service.dart | المصادقة (تسجيل/دخول) |
| `VpsAuthService` | vps_auth_service.dart | مصادقة مع VPS API |
| `FirebaseAuthService` | firebase_auth_service.dart | مصادقة Firebase |
| `PermissionsService` | permissions_service.dart | إدارة الصلاحيات |
| `NotificationService` | notification_service.dart | الإشعارات |
| `SyncService` | sync_service.dart | مزامنة البيانات |

---

## 📄 Pages - الصفحات

### هيكل الصفحات

```
pages/
├── login_page.dart              ← تسجيل الدخول
├── home_page.dart               ← الصفحة الرئيسية
├── dashboard_page.dart          ← لوحة القيادة
├── users_page.dart              ← إدارة المستخدمين
│
├── admin/                       ← صفحات مدير الشركة
│   ├── permissions_page.dart    ← إدارة الصلاحيات
│   └── employees_page.dart      ← إدارة الموظفين
│
├── super_admin/                 ← صفحات مدير النظام
│   ├── companies_page.dart      ← إدارة الشركات
│   └── system_settings.dart     ← إعدادات النظام
│
└── citizen_portal/              ← بوابة المواطن
    ├── citizen_home_page.dart
    └── citizen_services_page.dart
```

### مثال على صفحة

```dart
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<User> users = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => isLoading = true);
    
    try {
      final response = await ApiService.instance.get('/users');
      if (response['success']) {
        users = (response['data'] as List)
            .map((json) => User.fromJson(json))
            .toList();
      }
    } catch (e) {
      // Handle error
    }
    
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return ListTile(
          title: Text(user.fullName),
          subtitle: Text(user.phoneNumber),
        );
      },
    );
  }
}
```

---

## 🔐 نظام الصلاحيات في Flutter

### PermissionsGate Widget

```dart
class PermissionsGate extends StatelessWidget {
  final String permission;
  final String? action;
  final Widget child;
  final Widget? fallback;

  const PermissionsGate({
    required this.permission,
    required this.child,
    this.action,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final hasPermission = PermissionsService.instance
        .hasPermission(permission, action: action);

    if (hasPermission) {
      return child;
    }
    
    return fallback ?? const SizedBox.shrink();
  }
}
```

**الاستخدام:**
```dart
// إظهار زر فقط إذا كان لديه صلاحية
PermissionsGate(
  permission: 'users',
  action: 'delete',
  child: ElevatedButton(
    onPressed: _deleteUser,
    child: const Text('حذف المستخدم'),
  ),
  fallback: const Text('لا تملك صلاحية الحذف'),
)
```

---

## 🎨 Widgets - المكونات المشتركة

### قائمة المكونات

| Widget | الوظيفة |
|--------|---------|
| `PermissionsGate` | حماية العناصر بالصلاحيات |
| `LoadingOverlay` | شاشة تحميل |
| `ErrorWidget` | عرض الأخطاء |
| `AppDrawer` | القائمة الجانبية |
| `DataTable` | جدول البيانات |

### مثال: LoadingOverlay

```dart
class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;

  const LoadingOverlay({
    required this.isLoading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }
}
```

---

## 📊 Models - نماذج البيانات

### مثال: User Model

```dart
class User {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String? email;
  final String role;
  final bool isActive;

  User({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    this.email,
    required this.role,
    required this.isActive,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      fullName: json['fullName'],
      phoneNumber: json['phoneNumber'],
      email: json['email'],
      role: json['role'],
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'email': email,
      'role': role,
      'isActive': isActive,
    };
  }
}
```

---

## 🔄 تدفق البيانات

```
┌─────────────────────────────────────────────────────┐
│                    Page (UI)                        │
│              عرض البيانات للمستخدم                  │
└────────────────────────┬────────────────────────────┘
                         │ يطلب البيانات
                         ▼
┌─────────────────────────────────────────────────────┐
│                   Service                           │
│              منطق العمل والتحقق                     │
└────────────────────────┬────────────────────────────┘
                         │ HTTP Request
                         ▼
┌─────────────────────────────────────────────────────┐
│                  ApiService                         │
│              إرسال/استقبال HTTP                     │
└────────────────────────┬────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│                  .NET API                           │
│              الخادم (Backend)                       │
└─────────────────────────────────────────────────────┘
```

---

## 🚀 تشغيل التطبيق

```powershell
# الانتقال للمجلد
cd C:\SadaraPlatform\src\Apps\CompanyDesktop\alsadara-ftth

# تحميل الحزم
flutter pub get

# تشغيل على Windows
flutter run -d windows

# بناء للإنتاج
flutter build windows
```

---

## ➕ كيف تضيف صفحة جديدة؟

### الخطوة 1: أنشئ الملف

```dart
// pages/invoices_page.dart
class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الفواتير')),
      body: const Center(child: Text('صفحة الفواتير')),
    );
  }
}
```

### الخطوة 2: أضف للـ Navigation

```dart
// في home_page.dart أو drawer
ListTile(
  title: const Text('الفواتير'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InvoicesPage()),
    );
  },
)
```

### الخطوة 3: أضف الصلاحية (اختياري)

```dart
PermissionsGate(
  permission: 'invoices',
  action: 'view',
  child: ListTile(
    title: const Text('الفواتير'),
    onTap: () => Navigator.push(...),
  ),
)
```

---

## 📝 تمارين

1. **افتح `main.dart`** - كيف يتم تحديد مصدر البيانات؟
2. **افتح `api_service.dart`** - ما هو baseUrl؟
3. **ابحث عن `PermissionsGate`** - كيف يتحقق من الصلاحية؟

---

## 🔗 الدرس التالي

[07_Database_and_Migrations.md](./07_Database_and_Migrations.md) - قاعدة البيانات والـ Migrations
