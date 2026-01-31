# 📚 الدرس #10: بوابة المواطن (Citizen Portal)

## 🎯 ما هي بوابة المواطن؟

**بوابة المواطن** = تطبيق ويب للمواطنين (العملاء):
- 🌐 يعمل في المتصفح (PWA)
- 📱 يمكن تثبيته على الهاتف
- 🔐 تسجيل دخول خاص للمواطنين

---

## 🏗️ التقنيات المستخدمة

| التقنية | الوظيفة |
|---------|---------|
| **Flutter Web** | بناء الواجهة |
| **PWA** | تثبيت على الجهاز |
| **Provider** | إدارة الحالة |
| **go_router** | التنقل بين الصفحات |

---

## 📁 هيكل المشروع

```
src/Apps/CitizenWeb/lib/
├── main.dart              ← نقطة البداية
│
├── config/                ← الإعدادات
│   ├── router.dart        ← التنقل
│   └── api_config.dart    ← رابط API
│
├── models/                ← نماذج البيانات
│   ├── citizen.dart
│   ├── subscription.dart
│   └── order.dart
│
├── pages/                 ← الصفحات
│   ├── home_page.dart
│   ├── login_page.dart
│   ├── services_page.dart
│   └── profile_page.dart
│
├── providers/             ← إدارة الحالة
│   └── auth_provider.dart
│
└── services/              ← الخدمات
    └── api_service.dart
```

---

## 🚀 main.dart

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider()..loadProfile(),
        ),
      ],
      child: MaterialApp.router(
        title: 'بوابة المواطن',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          fontFamily: 'Cairo',
        ),
        routerConfig: router,
      ),
    );
  }
}
```

---

## 🔄 Provider - إدارة الحالة

### ما هو Provider؟

**Provider** = طريقة لمشاركة البيانات بين الصفحات.

```dart
// providers/auth_provider.dart
class AuthProvider extends ChangeNotifier {
  Citizen? _citizen;
  bool _isLoading = false;

  Citizen? get citizen => _citizen;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _citizen != null;

  Future<void> loadProfile() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await SecureStorage.getToken();
      if (token != null) {
        _citizen = await ApiService.instance.getProfile();
      }
    } catch (e) {
      _citizen = null;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String phoneNumber, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await ApiService.instance.login(
        phoneNumber, 
        password,
      );
      
      if (response.success) {
        _citizen = response.citizen;
        await SecureStorage.saveToken(response.token);
        notifyListeners();
        return true;
      }
    } catch (e) {
      // Handle error
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    await SecureStorage.deleteToken();
    _citizen = null;
    notifyListeners();
  }
}
```

### استخدام Provider في الصفحات

```dart
// قراءة البيانات
final authProvider = context.watch<AuthProvider>();
final citizen = authProvider.citizen;

// استدعاء دالة
context.read<AuthProvider>().logout();
```

---

## 🛣️ go_router - التنقل

### config/router.dart

```dart
final router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final authProvider = context.read<AuthProvider>();
    final isLoggedIn = authProvider.isLoggedIn;
    final isOnLogin = state.matchedLocation == '/login';

    if (!isLoggedIn && !isOnLogin) {
      return '/login';
    }
    if (isLoggedIn && isOnLogin) {
      return '/';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomePage(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/services',
      builder: (context, state) => const ServicesPage(),
    ),
    GoRoute(
      path: '/subscriptions',
      builder: (context, state) => const SubscriptionsPage(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfilePage(),
    ),
  ],
);
```

### التنقل بين الصفحات

```dart
// انتقال عادي
context.go('/services');

// انتقال مع Push (يحافظ على التاريخ)
context.push('/subscription/123');

// رجوع
context.pop();
```

---

## 📱 الصفحات الرئيسية

### 1. صفحة تسجيل الدخول

```dart
class LoginPage extends StatefulWidget {
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  Future<void> _login() async {
    final success = await context.read<AuthProvider>().login(
      _phoneController.text,
      _passwordController.text,
    );

    if (success) {
      context.go('/');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل تسجيل الدخول')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthProvider>().isLoading;

    return Scaffold(
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('بوابة المواطن', style: TextStyle(fontSize: 24)),
                const SizedBox(height: 24),
                TextField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _login,
                    child: isLoading
                        ? const CircularProgressIndicator()
                        : const Text('تسجيل الدخول'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

### 2. الصفحة الرئيسية

```dart
class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final citizen = context.watch<AuthProvider>().citizen;

    return Scaffold(
      appBar: AppBar(
        title: const Text('بوابة المواطن'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<AuthProvider>().logout();
              context.go('/login');
            },
          ),
        ],
      ),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        children: [
          _ServiceCard(
            title: 'اشتراكاتي',
            icon: Icons.wifi,
            onTap: () => context.go('/subscriptions'),
          ),
          _ServiceCard(
            title: 'طلب خدمة',
            icon: Icons.add_circle,
            onTap: () => context.go('/services'),
          ),
          _ServiceCard(
            title: 'المدفوعات',
            icon: Icons.payment,
            onTap: () => context.go('/payments'),
          ),
          _ServiceCard(
            title: 'الدعم الفني',
            icon: Icons.support_agent,
            onTap: () => context.go('/support'),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(citizen?.fullName ?? ''),
              accountEmail: Text(citizen?.phoneNumber ?? ''),
            ),
            // Menu items...
          ],
        ),
      ),
    );
  }
}
```

---

## 🌐 PWA - Progressive Web App

### ما هو PWA؟

**PWA** = تطبيق ويب يمكن تثبيته على الجهاز:
- ✅ يعمل Offline
- ✅ يظهر في الشاشة الرئيسية
- ✅ يُرسل إشعارات

### إعداد PWA

```yaml
# web/manifest.json
{
  "name": "بوابة المواطن",
  "short_name": "المواطن",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#2196F3",
  "icons": [
    {
      "src": "icons/icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "icons/icon-512.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}
```

---

## 🔗 الربط مع API

### services/api_service.dart

```dart
class ApiService {
  static const String baseUrl = 'https://api.ftth.iq/api/citizen';
  
  static ApiService? _instance;
  static ApiService get instance => _instance ??= ApiService._internal();

  Future<List<Subscription>> getSubscriptions() async {
    final response = await _authenticatedGet('/subscriptions');
    return (response['data'] as List)
        .map((json) => Subscription.fromJson(json))
        .toList();
  }

  Future<void> requestService(ServiceRequest request) async {
    await _authenticatedPost('/service-requests', body: request.toJson());
  }

  Future<List<SupportTicket>> getTickets() async {
    final response = await _authenticatedGet('/tickets');
    return (response['data'] as List)
        .map((json) => SupportTicket.fromJson(json))
        .toList();
  }
}
```

---

## 🚀 بناء ونشر PWA

### البناء

```powershell
cd src/Apps/CitizenWeb

# بناء للويب
flutter build web --release

# الملفات تكون في build/web/
```

### النشر

```powershell
# نسخ الملفات للخادم
scp -r build/web/* user@server:/var/www/citizen-portal/

# أو مع API في نفس الخادم
# الملفات موجودة في src/Backend/API/Sadara.API/citizen_portal/
```

---

## 📊 الخدمات المتاحة للمواطن

| الخدمة | الوصف |
|--------|-------|
| 📋 **الاشتراكات** | عرض الاشتراكات الحالية |
| 💳 **المدفوعات** | دفع الفواتير |
| 🛒 **المتجر** | شراء المنتجات |
| 🎫 **الدعم الفني** | فتح تذاكر دعم |
| 👤 **الملف الشخصي** | تعديل البيانات |

---

## 🔐 مصادقة المواطن

### الفرق عن مصادقة الموظفين

| | موظفين | مواطنين |
|---|--------|---------|
| **Endpoint** | `/api/auth/login` | `/api/citizen/auth/login` |
| **Role** | Employee+ | Citizen |
| **الصلاحيات** | SecondSystemPermissions | صلاحيات المواطن فقط |

### Controller خاص

```csharp
[ApiController]
[Route("api/citizen/[controller]")]
public class CitizenAuthController : ControllerBase
{
    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] CitizenLoginRequest request)
    {
        // تحقق من أن المستخدم مواطن
        var user = await _unitOfWork.Users
            .FirstOrDefaultAsync(u => 
                u.PhoneNumber == request.PhoneNumber && 
                u.Role == UserRole.Citizen);

        if (user == null)
            return BadRequest(new { message = "رقم الهاتف غير مسجل" });

        // ... باقي المنطق
    }
}
```

---

## 📝 تمارين

1. **أضف صفحة** لعرض سجل المدفوعات
2. **أضف Provider** لإدارة الاشتراكات
3. **فكر:** كيف يمكن إضافة إشعارات Push؟

---

## 🔗 الدرس التالي

هذا آخر درس في السلسلة الأساسية! 🎉

للمزيد من التعلم:
- راجع الكود المصدري
- جرب إضافة ميزات جديدة
- اقرأ التوثيق في مجلد `docs/`
