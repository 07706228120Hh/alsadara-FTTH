# 📋 الخطة التنفيذية لتوحيد البنية التحتية لمنصة صدارة
## Unified Infrastructure Implementation Plan

---

## 📅 تاريخ الإنشاء: 29 يناير 2026
## 🎯 الهدف: توحيد مصدر البيانات (VPS PostgreSQL)

---

## 📑 فهرس المحتويات
1. [الهدف العام](#الهدف-العام)
2. [تحليل الوضع الحالي](#تحليل-الوضع-الحالي)
3. [الهيكلية المقترحة](#الهيكلية-المقترحة)
4. [هيكلية المجلدات الجديدة](#هيكلية-المجلدات)
5. [خطوات التنفيذ التفصيلية](#خطوات-التنفيذ)
6. [الجدول الزمني](#الجدول-الزمني)
7. [استراتيجية الترحيل الآمن](#استراتيجية-الترحيل)
8. [قائمة الملفات المطلوب تعديلها](#قائمة-الملفات)
9. [خطة ترحيل البيانات](#ترحيل-البيانات)
10. [قائمة التحقق النهائية](#قائمة-التحقق)

---

## 🎯 الهدف العام {#الهدف-العام}

توحيد مصدر البيانات في منصة صدارة بحيث يكون **VPS PostgreSQL** هو المصدر الوحيد للبيانات، مع الإبقاء على **Firebase** للخدمات المساندة فقط (الإشعارات، التحليلات، توزيع التطبيق).

### الفوائد المتوقعة
| الفائدة | التفاصيل |
|---------|----------|
| 🔄 **تزامن البيانات** | مصدر واحد = لا مشاكل تزامن |
| 💰 **تقليل التكلفة** | Firebase Firestore مكلف مع النمو |
| 🔐 **أمان أفضل** | تحكم كامل في البيانات |
| 🚀 **أداء أفضل** | PostgreSQL أسرع للاستعلامات المعقدة |
| 🛠️ **صيانة أسهل** | نظام واحد للمراقبة والصيانة |

---

## 📊 تحليل الوضع الحالي {#تحليل-الوضع-الحالي}

### المشكلة الرئيسية
```
┌─────────────────────────────────────────────────────────────────┐
│                    ⚠️ مصادر بيانات متعددة                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   CompanyDesktop                    CitizenWeb                  │
│   ┌──────────────┐                  ┌──────────────┐           │
│   │ Flutter Win  │                  │ Flutter Web  │           │
│   └──────┬───────┘                  └──────┬───────┘           │
│          │                                  │                   │
│    ┌─────┴─────┐                           │                   │
│    ▼           ▼                           ▼                   │
│ ┌────────┐ ┌────────┐               ┌────────────┐            │
│ │Firebase│ │VPS API │               │  VPS API   │            │
│ │Firestore│ │        │               │            │            │
│ └────────┘ └────────┘               └────────────┘            │
│     ❌         ✅                        ✅                    │
│                                                                 │
│ ⚠️ مشكلة: بيانات مكررة وغير متزامنة                            │
└─────────────────────────────────────────────────────────────────┘
```

### البيانات المخزنة حالياً في Firebase Firestore
| Collection | الوصف | الحالة | الإجراء المطلوب |
|------------|-------|--------|-----------------|
| `super_admins` | مدراء النظام | ❌ خاطئ | نقل للـ VPS |
| `tenants` | الشركات | ❌ خاطئ | نقل للـ VPS |
| `tenants/{id}/users` | موظفي الشركات | ❌ خاطئ | نقل للـ VPS |
| `system_settings` | إعدادات النظام | ❌ خاطئ | نقل للـ VPS |
| `app_config` | إعدادات التطبيق | ❌ خاطئ | نقل للـ VPS |

### البيانات المخزنة في VPS PostgreSQL
| Table | الوصف | الحالة | ملاحظات |
|-------|-------|--------|---------|
| `Citizens` | المواطنين | ✅ صحيح | يعمل بشكل جيد |
| `Companies` | الشركات | ⚠️ موجود | غير مستخدم من CompanyDesktop |
| `Users` | المستخدمين | ⚠️ موجود | غير مستخدم من CompanyDesktop |
| `Plans` | الباقات | ✅ صحيح | يعمل بشكل جيد |
| `Subscriptions` | الاشتراكات | ✅ صحيح | يعمل بشكل جيد |

---

## 🏗️ الهيكلية المقترحة (Hybrid Architecture) {#الهيكلية-المقترحة}

```
┌─────────────────────────────────────────────────────────────────┐
│                  ✅ الهيكلية الموحدة الجديدة                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   CompanyDesktop                    CitizenWeb                  │
│   ┌──────────────┐                  ┌──────────────┐           │
│   │ Flutter Win  │                  │ Flutter Web  │           │
│   └──────┬───────┘                  └──────┬───────┘           │
│          │                                  │                   │
│          │         ┌────────────┐          │                   │
│          └────────►│  VPS API   │◄─────────┘                   │
│                    │ (ASP.NET)  │                               │
│                    └─────┬──────┘                               │
│                          │                                      │
│                    ┌─────▼──────┐                               │
│                    │ PostgreSQL │  ◄── مصدر البيانات الوحيد     │
│                    │ sadara_db  │                               │
│                    └────────────┘                               │
│                                                                 │
│   ╔═══════════════════════════════════════════════════════╗    │
│   ║        Firebase (خدمات مساندة فقط)                    ║    │
│   ╠═══════════════════════════════════════════════════════╣    │
│   ║ • FCM - الإشعارات (Push Notifications)               ║    │
│   ║ • Analytics - التحليلات وتتبع الاستخدام              ║    │
│   ║ • Crashlytics - تتبع الأخطاء والانهيارات             ║    │
│   ║ • App Distribution - توزيع التطبيق للاختبار          ║    │
│   ╚═══════════════════════════════════════════════════════╝    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### الرابط الوحيد بين Firebase و PostgreSQL
```
PostgreSQL                          Firebase
┌─────────────────┐                ┌─────────────────┐
│     Users       │                │      FCM        │
│ ────────────────│                │                 │
│ • Id            │                │                 │
│ • Name          │                │                 │
│ • Email         │                │                 │
│ • FcmToken ─────┼───────────────►│ Send Push       │
│                 │                │ Notification    │
└─────────────────┘                └─────────────────┘

فقط FcmToken يربط بين النظامين
```

---

## 📁 هيكلية المجلدات الجديدة للـ Flutter {#هيكلية-المجلدات}

### CompanyDesktop - lib/services/api/
```
lib/
└── services/
    └── api/
        ├── api_client.dart           # HTTP Client الأساسي مع التوثيق
        ├── api_config.dart           # إعدادات API (URLs, Keys)
        ├── api_response.dart         # نموذج الاستجابة الموحد
        ├── api_exceptions.dart       # معالجة الأخطاء المخصصة
        │
        ├── auth/
        │   ├── auth_api.dart         # تسجيل الدخول للموظفين
        │   └── super_admin_api.dart  # تسجيل دخول مدير النظام
        │
        ├── companies/
        │   ├── companies_api.dart    # CRUD للشركات
        │   └── company_users_api.dart # موظفي الشركة
        │
        ├── citizens/
        │   └── citizens_api.dart     # إدارة المواطنين
        │
        ├── subscriptions/
        │   ├── plans_api.dart        # الباقات
        │   └── subscriptions_api.dart # الاشتراكات
        │
        └── system/
            ├── settings_api.dart     # إعدادات النظام
            └── reports_api.dart      # التقارير
```

### CitizenWeb - lib/services/api/
```
lib/
└── services/
    └── api/
        ├── api_client.dart           # HTTP Client الأساسي
        ├── api_config.dart           # إعدادات API
        ├── api_response.dart         # نموذج الاستجابة الموحد
        │
        ├── auth/
        │   └── citizen_auth_api.dart # تسجيل دخول المواطن
        │
        ├── plans/
        │   └── plans_api.dart        # عرض الباقات
        │
        ├── subscriptions/
        │   └── subscriptions_api.dart # إدارة الاشتراكات
        │
        └── profile/
            └── profile_api.dart      # الملف الشخصي
```

---

## 🔧 خطوات التنفيذ التفصيلية {#خطوات-التنفيذ}

### المرحلة 1: تحديث الـ Backend (30-45 دقيقة)

#### 1.1 إنشاء كيان SuperAdmin
**الملف:** `src/Backend/Core/Sadara.Domain/Entities/SuperAdmin.cs`

```csharp
using System;
using System.ComponentModel.DataAnnotations;

namespace Sadara.Domain.Entities
{
    public class SuperAdmin
    {
        [Key]
        public int Id { get; set; }
        
        [Required]
        [StringLength(50)]
        public string Username { get; set; } = string.Empty;
        
        [Required]
        public string PasswordHash { get; set; } = string.Empty;
        
        [EmailAddress]
        [StringLength(100)]
        public string? Email { get; set; }
        
        [StringLength(100)]
        public string? FullName { get; set; }
        
        public bool IsActive { get; set; } = true;
        
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        
        public DateTime? LastLoginAt { get; set; }
    }
}
```

#### 1.2 تحديث DbContext
**الملف:** `src/Backend/Core/Sadara.Infrastructure/Data/ApplicationDbContext.cs`

```csharp
// إضافة في DbSet
public DbSet<SuperAdmin> SuperAdmins { get; set; }

// إضافة في OnModelCreating
modelBuilder.Entity<SuperAdmin>(entity =>
{
    entity.HasIndex(e => e.Username).IsUnique();
    entity.Property(e => e.CreatedAt).HasDefaultValueSql("CURRENT_TIMESTAMP");
});
```

#### 1.3 إنشاء Migration
```powershell
cd C:\SadaraPlatform\src\Backend\Core\Sadara.Infrastructure
dotnet ef migrations add AddSuperAdminEntity --startup-project ../API/Sadara.API
```

#### 1.4 إنشاء SuperAdminController
**الملف:** `src/Backend/API/Sadara.API/Controllers/SuperAdminController.cs`

| Endpoint | Method | الوصف | Parameters |
|----------|--------|-------|------------|
| `/api/superadmin/login` | POST | تسجيل دخول مدير النظام | `{ username, password }` |
| `/api/superadmin/companies` | GET | قائمة جميع الشركات | - |
| `/api/superadmin/companies` | POST | إنشاء شركة جديدة | `CompanyCreateDto` |
| `/api/superadmin/companies/{id}` | GET | تفاصيل شركة | `id` |
| `/api/superadmin/companies/{id}` | PUT | تحديث بيانات شركة | `id, CompanyUpdateDto` |
| `/api/superadmin/companies/{id}/suspend` | POST | تعليق شركة | `id` |
| `/api/superadmin/companies/{id}/activate` | POST | تفعيل شركة | `id` |
| `/api/superadmin/companies/{id}/users` | GET | موظفي شركة | `id` |
| `/api/superadmin/dashboard` | GET | إحصائيات لوحة التحكم | - |

#### 1.5 إنشاء DTOs
**الملف:** `src/Backend/Core/Sadara.Application/DTOs/SuperAdminDtos.cs`

```csharp
public class SuperAdminLoginDto
{
    public string Username { get; set; }
    public string Password { get; set; }
}

public class SuperAdminLoginResponseDto
{
    public int Id { get; set; }
    public string Username { get; set; }
    public string FullName { get; set; }
    public string Token { get; set; }
}

public class DashboardStatsDto
{
    public int TotalCompanies { get; set; }
    public int ActiveCompanies { get; set; }
    public int TotalCitizens { get; set; }
    public int TotalSubscriptions { get; set; }
    public decimal TotalRevenue { get; set; }
}
```

#### 1.6 تحديث CompanyController
| Endpoint | Method | الوصف | Parameters |
|----------|--------|-------|------------|
| `/api/company/login` | POST | تسجيل دخول موظف | `{ companyCode, username, password }` |
| `/api/company/users` | GET | قائمة موظفي الشركة | - |
| `/api/company/users` | POST | إنشاء موظف جديد | `UserCreateDto` |
| `/api/company/users/{id}` | PUT | تحديث بيانات موظف | `UserUpdateDto` |
| `/api/company/profile` | GET | ملف الشركة | - |

---

### المرحلة 2: إنشاء طبقة API في Flutter (45 دقيقة)

#### 2.1 API Client الأساسي
**الملف:** `lib/services/api/api_client.dart`

```dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'api_response.dart';
import 'api_exceptions.dart';

class ApiClient {
  final http.Client _client;
  String? _authToken;
  
  ApiClient({http.Client? client}) : _client = client ?? http.Client();
  
  void setAuthToken(String token) => _authToken = token;
  void clearAuthToken() => _authToken = null;
  
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };
  
  Future<ApiResponse<T>> get<T>(
    String endpoint, 
    T Function(dynamic) parser,
  ) async {
    try {
      final response = await _client.get(
        Uri.parse('${ApiConfig.baseUrl}$endpoint'),
        headers: _headers,
      );
      return _handleResponse(response, parser);
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }
  
  Future<ApiResponse<T>> post<T>(
    String endpoint,
    dynamic body,
    T Function(dynamic) parser,
  ) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiConfig.baseUrl}$endpoint'),
        headers: _headers,
        body: jsonEncode(body),
      );
      return _handleResponse(response, parser);
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }
  
  Future<ApiResponse<T>> put<T>(
    String endpoint,
    dynamic body,
    T Function(dynamic) parser,
  ) async {
    try {
      final response = await _client.put(
        Uri.parse('${ApiConfig.baseUrl}$endpoint'),
        headers: _headers,
        body: jsonEncode(body),
      );
      return _handleResponse(response, parser);
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }
  
  Future<ApiResponse<T>> delete<T>(
    String endpoint,
    T Function(dynamic) parser,
  ) async {
    try {
      final response = await _client.delete(
        Uri.parse('${ApiConfig.baseUrl}$endpoint'),
        headers: _headers,
      );
      return _handleResponse(response, parser);
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }
  
  ApiResponse<T> _handleResponse<T>(
    http.Response response,
    T Function(dynamic) parser,
  ) {
    final body = jsonDecode(response.body);
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return ApiResponse.success(parser(body), response.statusCode);
    } else {
      return ApiResponse.error(
        body['message'] ?? 'Unknown error',
        statusCode: response.statusCode,
        errors: body['errors'] != null 
          ? List<String>.from(body['errors']) 
          : null,
      );
    }
  }
}
```

#### 2.2 API Config
**الملف:** `lib/services/api/api_config.dart`

```dart
class ApiConfig {
  // Production
  static const String baseUrl = 'https://72.61.183.61/api';
  
  // Development (local)
  // static const String baseUrl = 'http://localhost:5000/api';
  
  // Endpoints
  static const String superAdminLogin = '/superadmin/login';
  static const String superAdminCompanies = '/superadmin/companies';
  static const String superAdminDashboard = '/superadmin/dashboard';
  
  static const String companyLogin = '/company/login';
  static const String companyUsers = '/company/users';
  static const String companyProfile = '/company/profile';
  
  static const String citizenLogin = '/citizen/login';
  static const String citizenRegister = '/citizen/register';
  static const String citizenPlans = '/citizen/plans';
  static const String citizenSubscriptions = '/citizen/subscriptions';
}
```

#### 2.3 API Response Model
**الملف:** `lib/services/api/api_response.dart`

```dart
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final int statusCode;
  final List<String>? errors;
  
  ApiResponse._({
    required this.success,
    this.data,
    this.message,
    required this.statusCode,
    this.errors,
  });
  
  factory ApiResponse.success(T data, int statusCode) {
    return ApiResponse._(
      success: true,
      data: data,
      statusCode: statusCode,
    );
  }
  
  factory ApiResponse.error(
    String message, {
    int statusCode = 500,
    List<String>? errors,
  }) {
    return ApiResponse._(
      success: false,
      message: message,
      statusCode: statusCode,
      errors: errors,
    );
  }
  
  bool get isSuccess => success;
  bool get isError => !success;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
}
```

#### 2.4 Super Admin API
**الملف:** `lib/services/api/auth/super_admin_api.dart`

```dart
import '../api_client.dart';
import '../api_config.dart';
import '../api_response.dart';
import '../../../models/super_admin.dart';
import '../../../models/company.dart';
import '../../../models/dashboard_stats.dart';

class SuperAdminApi {
  final ApiClient _client;
  
  SuperAdminApi(this._client);
  
  Future<ApiResponse<SuperAdminLoginResponse>> login(
    String username, 
    String password,
  ) async {
    return _client.post(
      ApiConfig.superAdminLogin,
      {'username': username, 'password': password},
      (json) => SuperAdminLoginResponse.fromJson(json),
    );
  }
  
  Future<ApiResponse<List<Company>>> getCompanies() async {
    return _client.get(
      ApiConfig.superAdminCompanies,
      (json) => (json as List).map((e) => Company.fromJson(e)).toList(),
    );
  }
  
  Future<ApiResponse<Company>> createCompany(CompanyCreateDto dto) async {
    return _client.post(
      ApiConfig.superAdminCompanies,
      dto.toJson(),
      (json) => Company.fromJson(json),
    );
  }
  
  Future<ApiResponse<Company>> updateCompany(int id, CompanyUpdateDto dto) async {
    return _client.put(
      '${ApiConfig.superAdminCompanies}/$id',
      dto.toJson(),
      (json) => Company.fromJson(json),
    );
  }
  
  Future<ApiResponse<bool>> suspendCompany(int id) async {
    return _client.post(
      '${ApiConfig.superAdminCompanies}/$id/suspend',
      {},
      (json) => true,
    );
  }
  
  Future<ApiResponse<bool>> activateCompany(int id) async {
    return _client.post(
      '${ApiConfig.superAdminCompanies}/$id/activate',
      {},
      (json) => true,
    );
  }
  
  Future<ApiResponse<DashboardStats>> getDashboardStats() async {
    return _client.get(
      ApiConfig.superAdminDashboard,
      (json) => DashboardStats.fromJson(json),
    );
  }
}
```

#### 2.5 Company Auth API
**الملف:** `lib/services/api/auth/auth_api.dart`

```dart
import '../api_client.dart';
import '../api_config.dart';
import '../api_response.dart';
import '../../../models/user.dart';

class AuthApi {
  final ApiClient _client;
  
  AuthApi(this._client);
  
  Future<ApiResponse<UserLoginResponse>> loginEmployee(
    String companyCode,
    String username,
    String password,
  ) async {
    return _client.post(
      ApiConfig.companyLogin,
      {
        'companyCode': companyCode,
        'username': username,
        'password': password,
      },
      (json) => UserLoginResponse.fromJson(json),
    );
  }
  
  Future<ApiResponse<bool>> logout() async {
    return _client.post(
      '/company/logout',
      {},
      (json) => true,
    );
  }
}
```

---

### المرحلة 3: تعديل الصفحات (60 دقيقة)

#### 3.1 صفحة تسجيل دخول مدير النظام
**الملف:** `lib/pages/super_admin_login_page.dart`

| قبل (Firebase) | بعد (VPS API) |
|----------------|---------------|
| `FirebaseFirestore.instance.collection('super_admins').where('username', isEqualTo: username).get()` | `await _superAdminApi.login(username, password)` |

**التعديلات المطلوبة:**
```dart
// قبل
final querySnapshot = await FirebaseFirestore.instance
    .collection('super_admins')
    .where('username', isEqualTo: _usernameController.text)
    .get();

if (querySnapshot.docs.isEmpty) {
  // خطأ: اسم المستخدم غير صحيح
}

// بعد
final response = await _superAdminApi.login(
  _usernameController.text,
  _passwordController.text,
);

if (response.isError) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(response.message ?? 'خطأ في تسجيل الدخول')),
  );
  return;
}

// حفظ التوكن والانتقال للوحة التحكم
_apiClient.setAuthToken(response.data!.token);
```

#### 3.2 صفحة قائمة الشركات
**الملف:** `lib/pages/super_admin/companies_list_page.dart`

| قبل (Firebase) | بعد (VPS API) |
|----------------|---------------|
| `StreamBuilder<List<Tenant>>` من Firebase | `FutureBuilder<ApiResponse<List<Company>>>` |

**التعديلات المطلوبة:**
```dart
// قبل
StreamBuilder<List<Tenant>>(
  stream: _authService.getAllTenants(),
  builder: (context, snapshot) {
    if (snapshot.hasError) return Text('Error: ${snapshot.error}');
    if (!snapshot.hasData) return CircularProgressIndicator();
    final tenants = snapshot.data!;
    // ...
  },
)

// بعد
FutureBuilder<ApiResponse<List<Company>>>(
  future: _superAdminApi.getCompanies(),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return Center(child: CircularProgressIndicator());
    }
    
    if (!snapshot.hasData || snapshot.data!.isError) {
      return Center(child: Text('خطأ في جلب البيانات'));
    }
    
    final companies = snapshot.data!.data!;
    return ListView.builder(
      itemCount: companies.length,
      itemBuilder: (context, index) {
        final company = companies[index];
        return CompanyListTile(company: company);
      },
    );
  },
)
```

#### 3.3 صفحة إضافة شركة
**الملف:** `lib/pages/super_admin/add_company_page.dart`

| قبل (Firebase) | بعد (VPS API) |
|----------------|---------------|
| `_firestore.collection('tenants').add(...)` | `await _superAdminApi.createCompany(dto)` |

**التعديلات المطلوبة:**
```dart
// قبل
await _firestore.collection('tenants').add({
  'companyName': _companyNameController.text,
  'companyCode': _companyCodeController.text,
  'adminEmail': _adminEmailController.text,
  'isActive': true,
  'createdAt': FieldValue.serverTimestamp(),
});

// بعد
final response = await _superAdminApi.createCompany(
  CompanyCreateDto(
    name: _companyNameController.text,
    code: _companyCodeController.text,
    adminEmail: _adminEmailController.text,
  ),
);

if (response.isSuccess) {
  Navigator.pop(context, response.data);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('تم إنشاء الشركة بنجاح')),
  );
} else {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(response.message ?? 'خطأ في إنشاء الشركة')),
  );
}
```

#### 3.4 صفحة تسجيل دخول الشركة
**الملف:** `lib/pages/tenant_login_page.dart`

| قبل (Firebase) | بعد (VPS API) |
|----------------|---------------|
| Firebase Auth + Firestore query | `await _authApi.loginEmployee(companyCode, username, password)` |

---

### المرحلة 4: الاختبار (30 دقيقة)

#### 4.1 اختبارات الـ Backend
```bash
# اختبار تسجيل دخول مدير النظام
curl -X POST https://72.61.183.61/api/superadmin/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"Admin@123"}' \
  -k

# اختبار جلب الشركات
curl https://72.61.183.61/api/superadmin/companies \
  -H "Authorization: Bearer {token}" \
  -k

# اختبار إنشاء شركة
curl -X POST https://72.61.183.61/api/superadmin/companies \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {token}" \
  -d '{"name":"شركة اختبار","code":"TEST001","adminEmail":"admin@test.com"}' \
  -k

# اختبار تسجيل دخول موظف
curl -X POST https://72.61.183.61/api/company/login \
  -H "Content-Type: application/json" \
  -d '{"companyCode":"SADARA001","username":"employee1","password":"pass123"}' \
  -k
```

#### 4.2 قائمة اختبارات التطبيق
| # | الوظيفة | النتيجة المتوقعة |
|---|---------|-----------------|
| 1 | تسجيل دخول مدير النظام | دخول للوحة التحكم |
| 2 | عرض قائمة الشركات | قائمة بجميع الشركات |
| 3 | إضافة شركة جديدة | الشركة تظهر في القائمة |
| 4 | تعديل بيانات شركة | البيانات تتحدث |
| 5 | تعليق شركة | الحالة تتغير لمعلق |
| 6 | تفعيل شركة | الحالة تتغير لنشط |
| 7 | تسجيل دخول موظف شركة | دخول للوحة الشركة |
| 8 | عرض لوحة تحكم الشركة | الإحصائيات صحيحة |

---

## ⏱️ الجدول الزمني {#الجدول-الزمني}

```
┌─────────────────────────────────────────────────────────────────┐
│                     الجدول الزمني التفصيلي                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  المرحلة 1: Backend                                             │
│  ├── إنشاء SuperAdmin Entity ................ 10 دقائق         │
│  ├── تحديث DbContext ........................ 5 دقائق          │
│  ├── إنشاء Migration ....................... 5 دقائق           │
│  ├── إنشاء SuperAdminController ............ 15 دقائق          │
│  └── إنشاء DTOs ............................ 10 دقائق          │
│      ─────────────────────────────────────                     │
│      المجموع: 45 دقيقة                                          │
│                                                                 │
│  المرحلة 2: Flutter API Layer                                   │
│  ├── إنشاء api_client.dart .................. 15 دقيقة         │
│  ├── إنشاء api_config.dart .................. 5 دقائق          │
│  ├── إنشاء api_response.dart ................ 5 دقائق          │
│  ├── إنشاء super_admin_api.dart ............ 10 دقائق          │
│  └── إنشاء auth_api.dart ................... 10 دقائق          │
│      ─────────────────────────────────────                     │
│      المجموع: 45 دقيقة                                          │
│                                                                 │
│  المرحلة 3: تعديل الصفحات                                       │
│  ├── super_admin_login_page.dart ............ 15 دقيقة         │
│  ├── companies_list_page.dart ............... 15 دقيقة         │
│  ├── add_company_page.dart .................. 15 دقيقة         │
│  └── tenant_login_page.dart ................. 15 دقيقة         │
│      ─────────────────────────────────────                     │
│      المجموع: 60 دقيقة                                          │
│                                                                 │
│  المرحلة 4: الاختبار                                            │
│  ├── اختبار Backend APIs ................... 15 دقيقة          │
│  └── اختبار Flutter App .................... 15 دقيقة          │
│      ─────────────────────────────────────                     │
│      المجموع: 30 دقيقة                                          │
│                                                                 │
│  ══════════════════════════════════════════════════════════    │
│  الإجمالي الكلي: 2.5 - 3 ساعات                                  │
│  ══════════════════════════════════════════════════════════    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🛡️ استراتيجية الترحيل الآمن {#استراتيجية-الترحيل}

### المبادئ الأساسية
| المبدأ | التفاصيل |
|--------|----------|
| 🔒 **لا كسر للكود** | الكود القديم يبقى كـ fallback |
| 📈 **ترحيل تدريجي** | صفحة بصفحة |
| 🧪 **اختبار مستمر** | كل تغيير يتم اختباره فوراً |
| ↩️ **إمكانية التراجع** | يمكن الرجوع في أي وقت |

### خطوات الترحيل الآمن
```
┌─────────────────────────────────────────────────────────────┐
│                    خطوات الترحيل الآمن                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1️⃣ إنشاء API endpoints جديدة (لا تؤثر على القديم)          │
│     ↓                                                       │
│  2️⃣ إنشاء API services في Flutter (ملفات جديدة)            │
│     ↓                                                       │
│  3️⃣ تعديل صفحة واحدة واختبارها                              │
│     ↓                                                       │
│  4️⃣ إذا نجح → الانتقال للصفحة التالية                       │
│     إذا فشل → التراجع والإصلاح                              │
│     ↓                                                       │
│  5️⃣ بعد نجاح جميع الصفحات → حذف كود Firebase القديم         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### التعامل مع الأخطاء
```dart
// استراتيجية Fallback (اختياري)
Future<List<Company>> getCompanies() async {
  try {
    // محاولة VPS API أولاً
    final response = await _superAdminApi.getCompanies();
    if (response.isSuccess) {
      return response.data!;
    }
    throw Exception(response.message);
  } catch (e) {
    // Fallback للـ Firebase (مؤقت)
    print('VPS failed, falling back to Firebase: $e');
    final snapshot = await FirebaseFirestore.instance
        .collection('tenants')
        .get();
    return snapshot.docs.map((doc) => Company.fromFirestore(doc)).toList();
  }
}
```

---

## 📝 قائمة الملفات المطلوب تعديلها {#قائمة-الملفات}

### Backend (Sadara.API)
| # | الملف | العملية | الأولوية | الحالة |
|---|-------|---------|----------|--------|
| 1 | `Domain/Entities/SuperAdmin.cs` | إنشاء جديد | 🔴 عالية | ⬜ |
| 2 | `Infrastructure/Data/ApplicationDbContext.cs` | تعديل | 🔴 عالية | ⬜ |
| 3 | `API/Controllers/SuperAdminController.cs` | إنشاء جديد | 🔴 عالية | ⬜ |
| 4 | `API/Controllers/CompanyController.cs` | تعديل | 🔴 عالية | ⬜ |
| 5 | `Application/DTOs/SuperAdminDtos.cs` | إنشاء جديد | 🔴 عالية | ⬜ |
| 6 | `Application/DTOs/CompanyDtos.cs` | تعديل | 🟡 متوسطة | ⬜ |

### CompanyDesktop (Flutter)
| # | الملف | العملية | الأولوية | الحالة |
|---|-------|---------|----------|--------|
| 1 | `lib/services/api/api_client.dart` | إنشاء جديد | 🔴 عالية | ⬜ |
| 2 | `lib/services/api/api_config.dart` | إنشاء جديد | 🔴 عالية | ⬜ |
| 3 | `lib/services/api/api_response.dart` | إنشاء جديد | 🔴 عالية | ⬜ |
| 4 | `lib/services/api/api_exceptions.dart` | إنشاء جديد | 🟡 متوسطة | ⬜ |
| 5 | `lib/services/api/auth/super_admin_api.dart` | إنشاء جديد | 🔴 عالية | ⬜ |
| 6 | `lib/services/api/auth/auth_api.dart` | إنشاء جديد | 🔴 عالية | ⬜ |
| 7 | `lib/services/api/companies/companies_api.dart` | إنشاء جديد | 🔴 عالية | ⬜ |
| 8 | `lib/pages/super_admin_login_page.dart` | تعديل | 🔴 عالية | ⬜ |
| 9 | `lib/pages/super_admin/companies_list_page.dart` | تعديل | 🔴 عالية | ⬜ |
| 10 | `lib/pages/super_admin/add_company_page.dart` | تعديل | 🔴 عالية | ⬜ |
| 11 | `lib/pages/tenant_login_page.dart` | تعديل | 🔴 عالية | ⬜ |
| 12 | `lib/services/tenant_service.dart` | حذف/إهمال | 🟢 منخفضة | ⬜ |

### CitizenWeb (Flutter) - تحسينات فقط
| # | الملف | العملية | الأولوية | الحالة |
|---|-------|---------|----------|--------|
| 1 | `lib/services/api_service.dart` | إعادة هيكلة | 🟡 متوسطة | ⬜ |
| 2 | إنشاء مجلد `services/api/` | تنظيم | 🟢 منخفضة | ⬜ |

---

## 🔄 خطة ترحيل البيانات {#ترحيل-البيانات}

### 1. إنشاء جدول SuperAdmins
```sql
-- إنشاء جدول SuperAdmins إذا لم يكن موجوداً
CREATE TABLE IF NOT EXISTS "SuperAdmins" (
    "Id" SERIAL PRIMARY KEY,
    "Username" VARCHAR(50) NOT NULL UNIQUE,
    "PasswordHash" TEXT NOT NULL,
    "Email" VARCHAR(100),
    "FullName" VARCHAR(100),
    "IsActive" BOOLEAN DEFAULT TRUE,
    "CreatedAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "LastLoginAt" TIMESTAMP
);

-- إضافة فهرس للبحث السريع
CREATE INDEX IF NOT EXISTS "IX_SuperAdmins_Username" ON "SuperAdmins" ("Username");
```

### 2. إضافة مدير نظام افتراضي
```sql
-- إضافة مدير نظام افتراضي (كلمة المرور: Admin@123)
INSERT INTO "SuperAdmins" ("Username", "PasswordHash", "Email", "FullName", "IsActive")
VALUES (
    'admin', 
    '$2a$11$rBNQCqhR.8OvLz8sBQkKeeqJkGWvpHyX.xqZBkM8YK6AICQKP0pXO', -- BCrypt hash
    'admin@sadara.com', 
    'مدير النظام', 
    TRUE
)
ON CONFLICT ("Username") DO NOTHING;
```

### 3. نقل بيانات الشركات من Firebase
```
خطوات النقل:
1. تصدير بيانات tenants من Firebase Console (Export)
2. تحويل JSON لـ SQL INSERT statements
3. تنفيذ INSERT في PostgreSQL

Firebase Collection: tenants
↓
PostgreSQL Table: Companies

الحقول المطلوب نقلها:
┌────────────────────┬────────────────────┐
│ Firebase Field     │ PostgreSQL Column  │
├────────────────────┼────────────────────┤
│ companyName        │ Name               │
│ companyCode        │ Code               │
│ adminEmail         │ AdminEmail         │
│ isActive           │ IsActive           │
│ createdAt          │ CreatedAt          │
│ subscriptionPlan   │ SubscriptionPlanId │
│ address            │ Address            │
│ phone              │ Phone              │
└────────────────────┴────────────────────┘
```

### 4. نقل بيانات المستخدمين
```
Firebase Collection: tenants/{tenantId}/users
↓
PostgreSQL Table: Users

الحقول:
┌────────────────────┬────────────────────┐
│ Firebase Field     │ PostgreSQL Column  │
├────────────────────┼────────────────────┤
│ username           │ Username           │
│ email              │ Email              │
│ fullName           │ FullName           │
│ role               │ Role               │
│ isActive           │ IsActive           │
│ createdAt          │ CreatedAt          │
│ tenantId (parent)  │ CompanyId          │
└────────────────────┴────────────────────┘
```

---

## ✅ قائمة التحقق النهائية {#قائمة-التحقق}

### قبل البدء
- [ ] نسخ احتياطي لقاعدة البيانات PostgreSQL
- [ ] نسخ احتياطي لـ Firebase Firestore (export)
- [ ] التأكد من اتصال الـ API بالـ VPS
- [ ] التأكد من صحة الـ Connection String
- [ ] التأكد من توفر Flutter SDK
- [ ] التأكد من توفر .NET SDK

### المرحلة 1: Backend
- [ ] إنشاء SuperAdmin Entity
- [ ] تحديث ApplicationDbContext
- [ ] إنشاء Migration
- [ ] تطبيق Migration على قاعدة البيانات
- [ ] إنشاء SuperAdminDtos
- [ ] إنشاء SuperAdminController
- [ ] تحديث CompanyController
- [ ] اختبار جميع الـ Endpoints

### المرحلة 2: Flutter API Layer
- [ ] إنشاء مجلد `services/api/`
- [ ] إنشاء `api_client.dart`
- [ ] إنشاء `api_config.dart`
- [ ] إنشاء `api_response.dart`
- [ ] إنشاء `auth/super_admin_api.dart`
- [ ] إنشاء `auth/auth_api.dart`
- [ ] إنشاء `companies/companies_api.dart`

### المرحلة 3: تعديل الصفحات
- [ ] تعديل `super_admin_login_page.dart`
- [ ] اختبار تسجيل دخول مدير النظام
- [ ] تعديل `companies_list_page.dart`
- [ ] اختبار قائمة الشركات
- [ ] تعديل `add_company_page.dart`
- [ ] اختبار إضافة شركة
- [ ] تعديل `tenant_login_page.dart`
- [ ] اختبار تسجيل دخول موظف

### المرحلة 4: الاختبار النهائي
- [ ] اختبار شامل لجميع الوظائف
- [ ] التأكد من عدم وجود أخطاء في Console
- [ ] اختبار على بيئة الإنتاج
- [ ] توثيق أي تغييرات إضافية

### بعد الانتهاء
- [ ] حذف الكود القديم (Firebase) - اختياري
- [ ] تحديث الوثائق
- [ ] إعلام الفريق بالتغييرات

---

## 🚀 البدء في التنفيذ

للبدء في التنفيذ، استخدم الأمر:
```
"ابدأ تنفيذ المرحلة 1 - تحديث Backend"
```

أو للبدء من مرحلة محددة:
```
"ابدأ تنفيذ المرحلة 2 - Flutter API Layer"
```

---

## 📞 ملاحظات مهمة

> ⚠️ **تحذير**: لا تحذف كود Firebase فوراً - ابقِه كـ fallback حتى التأكد من نجاح الترحيل

> 🧪 **نصيحة**: اختبر كل خطوة - لا تنتقل للخطوة التالية قبل التأكد من نجاح الحالية

> 💾 **تذكير**: احتفظ بنسخ احتياطية - قبل أي تعديل كبير

> ⏸️ **مرونة**: الترحيل تدريجي - يمكن التوقف في أي وقت والاستمرار لاحقاً

---

## 📚 المراجع

- [INFRASTRUCTURE_DESIGN.md](./INFRASTRUCTURE_DESIGN.md) - وثيقة تصميم البنية التحتية
- [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) - خطة التنفيذ العامة
- [API Documentation](https://72.61.183.61/swagger) - توثيق الـ API

---

*آخر تحديث: 29 يناير 2026*
*الإصدار: 1.0*
