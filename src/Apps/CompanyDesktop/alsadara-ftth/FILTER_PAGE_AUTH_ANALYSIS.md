# تحليل شامل لنظام المصادقة والصلاحيات في filter_page

## 📋 نظرة عامة

تطبيق filter_page يستخدم **نظام مصادقة ثنائي** (Dual Authentication System):
1. **النظام الأول**: Google Sheets (للموظفين والمستخدمين العاديين)
2. **النظام الثاني**: FTTH API (لمستخدمي نظام FTTH)

---

## 🔐 1. آلية تسجيل الدخول (Login Flow)

### 1.1 صفحة تسجيل الدخول
**الملف:** `lib/pages/login_page.dart`

#### البيانات المطلوبة:
```dart
- username: اسم المستخدم (TextFormField)
- phone: رقم الهاتف (TextFormField) 
- rememberMe: تذكرني (Checkbox)
```

#### خطوات تسجيل الدخول:

```dart
Future<void> login() async {
  // 1️⃣ محاولة النظام الموحد أولاً
  final result = await UnifiedAuthManager.instance.login(
    usernameController.text.trim(),
    phoneController.text.trim(),
    rememberMe: rememberMe,
  );
  
  if (result.isSuccess) {
    // ✅ تسجيل دخول ناجح
    await _saveCredentials(); // حفظ البيانات محلياً
    
    Navigator.pushReplacement(context, 
      MaterialPageRoute(builder: (context) => HomePage(
        username: result.userSession!.username,
        permissions: 'USER',
        department: 'عام',
        salary: '',
        center: 'المركز الرئيسي',
        pageAccess: {...}, // صلاحيات النظام الأول
        secondSystemPageAccess: {...}, // صلاحيات النظام الثاني
        tenantId: 'DEMO',
        userId: result.userSession!.username,
      )),
    );
  } else {
    // ❌ فشل النظام الموحد - استخدام Google Sheets
    await _fallbackToTraditionalLogin();
  }
}
```

### 1.2 النظام التقليدي (Google Sheets Fallback)

```dart
Future<void> _fallbackToTraditionalLogin() async {
  // 1️⃣ قراءة بيانات من Google Sheets
  final url = 'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/$range?key=$apiKey';
  final response = await http.get(Uri.parse(url));
  
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    final rows = data['values'] as List;
    
    // 2️⃣ البحث عن المستخدم في الصفوف
    for (var row in rows) {
      if (row[0].trim().toLowerCase() == username.toLowerCase() &&
          row[1].trim() == phone) {
        // ✅ مستخدم موجود
        userName = row[0].trim();
        userPermissions = row[2].trim();
        userDepartment = row[3].trim();
        userCenter = row[4].trim();
        userSalary = row[5].trim();
        
        // 3️⃣ جلب صلاحيات الوصول للصفحات
        pageAccess = {
          'home': row[6] == 'TRUE',
          'home_page1': row[7] == 'TRUE',
          'home_page_tasks': row[8] == 'TRUE',
          'home_page2': row[9] == 'TRUE',
        };
        break;
      }
    }
    
    // 4️⃣ الانتقال للصفحة الرئيسية
    Navigator.pushReplacement(context, 
      MaterialPageRoute(builder: (context) => HomePage(...))
    );
  }
}
```

#### هيكل بيانات Google Sheets:

| العمود | الحقل | الوصف |
|--------|-------|-------|
| A | username | اسم المستخدم |
| B | phone | رقم الهاتف |
| C | permissions | الصلاحيات (مدير/موظف) |
| D | department | القسم |
| E | center | المركز |
| F | salary | الراتب |
| G | home | صلاحية الصفحة الرئيسية (TRUE/FALSE) |
| H | home_page1 | صلاحية صفحة 1 (TRUE/FALSE) |
| I | home_page_tasks | صلاحية المهام (TRUE/FALSE) |
| J | home_page2 | صلاحية صفحة 2 (TRUE/FALSE) |

---

## 🔑 2. نظام FTTH API Authentication

### 2.1 خدمة المصادقة
**الملف:** `lib/services/auth_service.dart`

#### تسجيل الدخول عبر API:

```dart
Future<Map<String, dynamic>> login(String username, String password) async {
  // 1️⃣ تحضير البيانات
  final encodedBody = 'username=${Uri.encodeQueryComponent(username)}'
                      '&password=${Uri.encodeQueryComponent(password)}'
                      '&grant_type=password'
                      '&scope=openid%20profile';
  
  // 2️⃣ إرسال الطلب
  final response = await http.post(
    Uri.parse('https://admin.ftth.iq/api/auth/Contractor/token'),
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
      'x-client-app': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
    },
    body: encodedBody,
  );
  
  // 3️⃣ حفظ التوكنات
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    await _saveTokens(data); // حفظ access_token و refresh_token
    _startTokenRefreshTimer(); // بدء مؤقت تجديد التوكن
    
    return {
      'success': true,
      'message': 'تم تسجيل الدخول بنجاح',
      'data': data,
    };
  }
  
  return {
    'success': false,
    'message': 'بيانات الدخول غير صحيحة',
  };
}
```

#### هيكل التوكنات:

```dart
// SharedPreferences Keys
static const String _accessTokenKey = 'access_token';
static const String _refreshTokenKey = 'refresh_token';
static const String _tokenExpiryKey = 'token_expiry';
static const String _refreshExpiryKey = 'refresh_expiry';

// مثال على البيانات المحفوظة:
{
  "access_token": "eyJhbGc....", 
  "refresh_token": "8f3a2b...",
  "expires_in": 3600,           // ساعة واحدة
  "refresh_expires_in": 691200  // 8 أيام
}
```

### 2.2 تجديد التوكن التلقائي

```dart
Future<bool> _refreshAccessToken() async {
  final refreshToken = prefs.getString(_refreshTokenKey);
  
  final response = await http.post(
    Uri.parse('https://admin.ftth.iq/api/auth/Contractor/refresh'),
    body: 'refresh_token=$refreshToken&grant_type=refresh_token',
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    await _saveTokens(data);
    return true;
  }
  return false;
}

// مؤقت تجديد التوكن كل 30 دقيقة
void _startTokenRefreshTimer() {
  _tokenRefreshTimer = Timer.periodic(Duration(minutes: 30), (timer) async {
    final refreshed = await _refreshAccessToken();
    if (!refreshed) {
      await _tryAutoRelogin(); // إعادة تسجيل الدخول تلقائياً
    }
  });
}
```

### 2.3 إعادة تسجيل الدخول التلقائي

```dart
Future<bool> _tryAutoRelogin() async {
  final prefs = await SharedPreferences.getInstance();
  final savedUsername = prefs.getString('savedUsername');
  final savedPassword = prefs.getString('savedPassword');
  final rememberCredentials = prefs.getBool('rememberMe') ?? false;
  
  if (rememberCredentials && savedUsername != null && savedPassword != null) {
    final result = await login(savedUsername, savedPassword);
    return result['success'] == true;
  }
  return false;
}
```

---

## 🛡️ 3. نظام الصلاحيات (Permissions System)

### 3.1 النظام الأول (First System)
**الملف:** `lib/services/permissions_service.dart`

#### الصلاحيات المتاحة:

```dart
static const List<String> firstSystemPermissions = [
  'attendance',  // صفحة الحضور والغياب
  'agent',       // صفحة الوكلاء
  'tasks',       // إدارة المهام
  'zones',       // إدارة الزونات
  'ai_search',   // البحث بالذكاء الاصطناعي
];
```

#### الصلاحيات الافتراضية:

```dart
static const Map<String, bool> firstSystemDefaults = {
  'attendance': false,  // ❌ مغلق افتراضياً
  'agent': false,       // ❌ مغلق افتراضياً
  'tasks': false,       // ❌ مغلق افتراضياً
  'zones': false,       // ❌ مغلق افتراضياً
  'ai_search': false,   // ❌ مغلق افتراضياً
};
```

#### حفظ واسترجاع الصلاحيات:

```dart
// حفظ الصلاحيات
static Future<void> saveFirstSystemPermissions(
    Map<String, bool> permissions) async {
  final prefs = await SharedPreferences.getInstance();
  
  for (String key in firstSystemPermissions) {
    await prefs.setBool('first_system_permission_$key', 
                        permissions[key] ?? false);
  }
  
  await prefs.setBool('first_system_configured', true);
  await prefs.setString('first_system_last_update', 
                        DateTime.now().toIso8601String());
}

// جلب الصلاحيات
static Future<Map<String, bool>> getFirstSystemPermissions() async {
  final prefs = await SharedPreferences.getInstance();
  bool isConfigured = prefs.getBool('first_system_configured') ?? false;
  
  Map<String, bool> permissions = {};
  for (String key in firstSystemPermissions) {
    if (isConfigured) {
      permissions[key] = prefs.getBool('first_system_permission_$key') 
                         ?? firstSystemDefaults[key]!;
    } else {
      permissions[key] = firstSystemDefaults[key]!;
    }
  }
  return permissions;
}
```

### 3.2 النظام الثاني (Second System - FTTH)

#### الصلاحيات المتاحة:

```dart
static const List<String> secondSystemPermissions = [
  // 👥 إدارة المستخدمين والحسابات
  'users',                      // إدارة المستخدمين
  'accounts',                   // إدارة الحسابات
  'account_records',            // سجلات الحسابات
  
  // 📶 الاشتراكات والمناطق
  'subscriptions',              // إدارة الاشتراكات
  'zones',                      // إدارة الزونات
  'expiring_soon',              // الاشتراكات المنتهية قريباً
  
  // 🔧 المهام والوكلاء
  'tasks',                      // إدارة المهام
  'agents',                     // إدارة الوكلاء
  'technicians',                // فني التوصيل (محلي)
  
  // 💰 المالية
  'wallet_balance',             // رصيد المحفظة
  'transactions',               // التحويلات
  'plans_bundles',              // الباقات والعروض
  
  // 📤 التصدير والتكامل
  'export',                     // تصدير البيانات
  'google_sheets',              // Google Sheets
  
  // 💬 الواتساب
  'whatsapp',                   // رسائل WhatsApp
  'whatsapp_link',              // ربط الواتساب (QR)
  'whatsapp_settings',          // إعدادات الواتساب
  'whatsapp_business_api',      // WhatsApp Business API
  'whatsapp_bulk_sender',       // إرسال رسائل جماعية
  'whatsapp_conversations_fab', // زر محادثات الواتساب
  
  // 🔔 الإشعارات والسجلات
  'notifications',              // الإشعارات
  'audit_logs',                 // سجل التدقيق
  
  // 🔍 البحث والتخزين
  'quick_search',               // البحث السريع
  'local_storage',              // التخزين المحلي
  'local_storage_import',       // استيراد بيانات التخزين المحلي
];
```

#### الصلاحيات الافتراضية (افتراضياً مغلقة):

```dart
static const Map<String, bool> secondSystemDefaults = {
  // ✅ مفتوح للجميع
  'users': false,               // عرض المستخدمين
  'subscriptions': false,       // عرض الاشتراكات
  'tasks': false,               // عرض المهام
  'agents': false,              // عرض الوكلاء
  'wallet_balance': false,      // رصيد المحفظة
  'expiring_soon': false,       // الاشتراكات المنتهية
  
  // 🔒 للمديرين فقط (مغلق افتراضياً)
  'zones': false,               // إدارة المناطق
  'accounts': false,            // إدارة الحسابات
  'export': false,              // تصدير البيانات
  'google_sheets': false,       // Google Sheets
  'whatsapp': false,            // رسائل WhatsApp
  
  // جميع الصلاحيات الأخرى مغلقة افتراضياً...
};
```

### 3.3 كلمة المرور الافتراضية للنظام الثاني

```dart
// حفظ كلمة المرور الافتراضية
static Future<void> saveSecondSystemDefaultPassword(String password) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('second_system_default_password', password);
}

// جلب كلمة المرور الافتراضية
static Future<String?> getSecondSystemDefaultPassword() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('second_system_default_password');
}
```

---

## 👨‍💼 4. نظام الأدوار (User Roles)

### 4.1 أدوار النظام الأول
**الملف:** `lib/services/user_permissions_service.dart`

```dart
static const String MANAGER = 'مدير';      // 👑 مدير
static const String LEADER = 'ليدر';       // 🎯 ليدر
static const String TECHNICIAN = 'فني';    // 🔧 فني
```

#### صلاحيات كل دور:

| الدور | التعديل | الحذف | إدارة الوكلاء | رؤية كل المهام |
|-------|--------|--------|---------------|-----------------|
| **مدير** | ✅ | ✅ | ✅ | ✅ |
| **ليدر** | ✅ | ❌ | ✅ | ✅ |
| **فني** | ❌ | ❌ | ❌ | ❌ (مهامه فقط) |

#### التحقق من الصلاحيات:

```dart
// التحقق من صلاحية التعديل
static Future<bool> canEditTask() async {
  final role = await getCurrentUserRole();
  return role == MANAGER || role == LEADER;
}

// التحقق من صلاحية الحذف
static Future<bool> canDeleteTask() async {
  final role = await getCurrentUserRole();
  return role == MANAGER;  // المدير فقط
}

// التحقق من رؤية المهمة
static Future<bool> canViewTask(String taskTechnician) async {
  final role = await getCurrentUserRole();
  final userName = await getCurrentUserName();
  
  if (role == MANAGER || role == LEADER) {
    return true;  // يرون جميع المهام
  }
  
  // الفني يرى مهامه فقط
  return taskTechnician.trim() == userName.trim();
}
```

### 4.2 أدوار النظام الثاني (FTTH)

النظام الثاني يستخدم نظام صلاحيات مختلف:
- **super_admin**: مدير النظام الأعلى
- **admin**: مدير شركة
- **user**: مستخدم عادي

---

## 🔐 5. تخزين البيانات المحلية

### 5.1 Flutter Secure Storage (للبيانات الحساسة)

```dart
static const _secureStorage = FlutterSecureStorage();

// حفظ البيانات
await _secureStorage.write(key: 'username', value: username);
await _secureStorage.write(key: 'phone', value: phone);
await _secureStorage.write(key: 'rememberMe', value: 'true');

// قراءة البيانات
final savedUsername = await _secureStorage.read(key: 'username');
final savedPhone = await _secureStorage.read(key: 'phone');

// حذف البيانات
await _secureStorage.delete(key: 'username');
await _secureStorage.delete(key: 'phone');
```

### 5.2 SharedPreferences (للصلاحيات والتوكنات)

```dart
final prefs = await SharedPreferences.getInstance();

// حفظ
await prefs.setString('access_token', token);
await prefs.setBool('first_system_permission_tasks', true);
await prefs.setString('token_expiry', DateTime.now().toIso8601String());

// قراءة
final token = prefs.getString('access_token');
final canViewTasks = prefs.getBool('first_system_permission_tasks') ?? false;

// حذف
await prefs.remove('access_token');
```

---

## 🔄 6. نظام المصادقة الموحد (Unified Auth Manager)

### الملف المفترض: `lib/services/unified_auth_manager.dart`

```dart
class UnifiedAuthManager {
  static final instance = UnifiedAuthManager._internal();
  
  Future<AuthResult> login(
    String username, 
    String phone, 
    {bool rememberMe = false}
  ) async {
    // 1️⃣ محاولة FTTH API
    final ftthResult = await _tryFtthLogin(username, phone);
    if (ftthResult.isSuccess) return ftthResult;
    
    // 2️⃣ محاولة Google Sheets
    final sheetsResult = await _tryGoogleSheetsLogin(username, phone);
    if (sheetsResult.isSuccess) return sheetsResult;
    
    // ❌ فشل جميع المحاولات
    return AuthResult.failure('فشل تسجيل الدخول');
  }
}
```

---

## 📊 7. مقارنة بين النظامين

| الميزة | النظام الأول (Google Sheets) | النظام الثاني (FTTH API) |
|--------|------------------------------|--------------------------|
| **مصدر البيانات** | Google Sheets | FTTH API (admin.ftth.iq) |
| **المصادقة** | username + phone | username + password |
| **التوكنات** | ❌ لا يوجد | ✅ access_token + refresh_token |
| **تجديد التوكن** | ❌ لا يوجد | ✅ كل 30 دقيقة |
| **إعادة الدخول التلقائي** | ✅ نعم | ✅ نعم |
| **التخزين المحلي** | FlutterSecureStorage | SharedPreferences |
| **الصلاحيات** | 5 صلاحيات | 25+ صلاحية |
| **الأدوار** | مدير / ليدر / فني | super_admin / admin / user |
| **Multi-Tenant** | ❌ لا | ✅ نعم (organizationId) |

---

## 🎯 8. التطبيق على old_project

### ما تم تطبيقه بالفعل:

✅ **خدمة المصادقة المخصصة (Firestore)**
- ملف: `lib/services/firebase_auth_service.dart`
- المصادقة: username + password (SHA-256)
- التخزين: SharedPreferences للجلسة

✅ **خدمة إدارة الشركات (Organizations)**
- ملف: `lib/services/organizations_service.dart`
- Multi-tenant بالكامل

✅ **خدمة المهام (Firestore)**
- ملف: `lib/services/firestore_tasks_service.dart`
- عزل البيانات حسب organizationId

✅ **خدمة الصلاحيات (Firestore)**
- ملف: `lib/services/firestore_permissions_service.dart`
- صلاحيات حسب الدور لكل شركة

### ما يحتاج التطبيق:

🔲 **صفحة تسجيل الدخول المحدّثة**
- تم التحديث لاستخدام username بدلاً من email ✅
- تحتاج اختبار

🔲 **صفحة إدارة الشركات (Admin Panel)**
- لم يتم إنشاؤها بعد
- مطلوبة للـ super_admin

🔲 **إزالة Google Sheets**
- حذف ملف `google_sheets_service.dart`
- إزالة الحزم من pubspec.yaml

🔲 **إنشاء مستخدم Super Admin الأول**
- يدوياً في Firestore Console

---

## 📝 9. الخلاصة والتوصيات

### النقاط الرئيسية:

1. **المصادقة الثنائية**: filter_page يستخدم نظامين (Google Sheets + FTTH API)
2. **الصلاحيات المنفصلة**: كل نظام له صلاحياته الخاصة
3. **تجديد التوكن التلقائي**: يحافظ على الجلسة نشطة
4. **إعادة الدخول التلقائي**: عند انتهاء التوكنات
5. **Multi-Tenant**: النظام الثاني يدعم تعدد الشركات

### التوصيات لـ old_project:

✅ **استخدام نفس البنية**:
- نظام موحد للمصادقة
- فصل الصلاحيات بين النظامين
- تخزين آمن للبيانات

✅ **تحسينات إضافية**:
- استخدام Firestore بدلاً من Google Sheets (أسرع وأكثر أماناً)
- نظام Multi-Tenant كامل
- صلاحيات ديناميكية من Firestore

✅ **الخطوات التالية**:
1. إنشاء super_admin الأول في Firestore
2. إنشاء صفحة إدارة الشركات
3. اختبار نظام المصادقة الكامل
4. إزالة Google Sheets تماماً

---

## 🔗 الملفات المرجعية

### filter_page:
- `lib/pages/login_page.dart` - صفحة تسجيل الدخول
- `lib/services/auth_service.dart` - FTTH API Authentication
- `lib/services/permissions_service.dart` - نظام الصلاحيات الثنائي
- `lib/services/user_permissions_service.dart` - أدوار النظام الأول
- `lib/services/unified_auth_manager.dart` - النظام الموحد

### old_project:
- `lib/services/firebase_auth_service.dart` - المصادقة المخصصة
- `lib/services/organizations_service.dart` - إدارة الشركات
- `lib/services/firestore_tasks_service.dart` - خدمة المهام
- `lib/services/firestore_permissions_service.dart` - الصلاحيات
- `lib/pages/firebase_login_page_new.dart` - صفحة الدخول (تحتاج تحديث)

---

تم التحليل بتاريخ: 25 ديسمبر 2025
