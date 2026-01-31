# 🏢 نظام Multi-Tenant كامل - دليل الاستخدام

## 📋 نظرة عامة

تم نسخ نظام Multi-Tenant الكامل من **filter_page** إلى **old_project** بنجاح!

### ✨ الميزات الرئيسية

#### 1. **Super Admin Dashboard** 
لوحة تحكم المدير الرئيسي للنظام بالكامل

#### 2. **نظام الشركات المستأجرة (Tenants)**
- إضافة شركات جديدة
- تعديل بيانات الشركات
- تعليق/إلغاء تعليق الشركات
- حذف الشركات

#### 3. **نظام الاشتراكات**
كل شركة لها:
- تاريخ بداية الاشتراك
- تاريخ انتهاء الاشتراك
- نوع الخطة (شهري/سنوي)
- حد أقصى للمستخدمين

#### 4. **حالات الاشتراك التلقائية**
- 🟢 **نشط (Active)**: أكثر من 30 يوم متبقي
- 🟠 **تحذير (Warning)**: 30-7 أيام متبقية
- 🟠 **حرج (Critical)**: أقل من 7 أيام
- 🔴 **منتهي (Expired)**: انتهى الاشتراك
- ⚫ **معلق (Suspended)**: تم التعليق يدوياً

#### 5. **إدارة المستخدمين لكل شركة**
- إضافة مستخدمين جدد
- تعديل بيانات المستخدمين
- تفعيل/تعطيل المستخدمين
- تغيير كلمات المرور
- إدارة الأدوار والصلاحيات

#### 6. **نظام الصلاحيات المتقدم**
##### النظام الأول (First System Permissions):
- الحضور والغياب
- الوكلاء
- المهام
- الزونات
- البحث الذكي

##### النظام الثاني (Second System Permissions):
- إدارة المستخدمين
- الاشتراكات
- المهام
- الزونات
- الحسابات
- سجلات الحسابات
- التصدير
- الوكلاء
- Google Sheets
- WhatsApp
- رصيد المحفظة
- الاشتراكات المنتهية قريباً
- البحث السريع
- الفنيين
- المعاملات
- الإشعارات
- سجلات التدقيق
- رابط WhatsApp
- إعدادات WhatsApp
- الخطط والباقات
- WhatsApp Business API
- مرسل WhatsApp الجماعي
- محادثات WhatsApp
- التخزين المحلي
- استيراد التخزين المحلي

---

## 📁 الملفات المنسوخة

### Models (النماذج)
```
lib/models/
├── tenant.dart              # نموذج الشركة
├── tenant_user.dart         # نموذج مستخدم الشركة
└── super_admin.dart         # نموذج المدير الرئيسي
```

### Services (الخدمات)
```
lib/services/
├── custom_auth_service.dart # خدمة المصادقة
└── tenant_service.dart      # خدمة إدارة الشركات
```

### Pages (الصفحات)
```
lib/pages/super_admin/
├── super_admin_dashboard.dart     # لوحة التحكم الرئيسية
├── super_admin_login_page.dart    # صفحة تسجيل دخول Super Admin
├── companies_list_page.dart       # قائمة الشركات
├── company_details_page.dart      # تفاصيل الشركة
├── add_company_page.dart          # إضافة شركة جديدة
└── super_admin_pages.dart         # تصدير الصفحات
```

### Library Exports
```
lib/multi_tenant.dart         # تصدير موحد لجميع المكونات
```

---

## 🔧 هيكل Firestore

### Collection: `super_admins`
```json
{
  "username": "superadmin",
  "passwordHash": "sha256_hash",
  "name": "المدير العام",
  "email": "admin@example.com",
  "phone": "1234567890",
  "createdAt": "timestamp",
  "lastLogin": "timestamp"
}
```

### Collection: `tenants` (الشركات)
```json
{
  "name": "شركة النور",
  "code": "NOOR2025",
  "email": "info@noor.com",
  "phone": "966501234567",
  "address": "الرياض، السعودية",
  "logo": "url_to_logo",
  "isActive": true,
  "suspensionReason": null,
  "suspendedAt": null,
  "suspendedBy": null,
  "subscriptionStart": "timestamp",
  "subscriptionEnd": "timestamp",
  "subscriptionPlan": "yearly",
  "maxUsers": 50,
  "createdAt": "timestamp",
  "createdBy": "super_admin_id"
}
```

### Subcollection: `tenants/{tenantId}/users`
```json
{
  "username": "ahmed123",
  "passwordHash": "sha256_hash",
  "fullName": "أحمد محمد",
  "email": "ahmed@noor.com",
  "phone": "966501234567",
  "role": "admin",
  "department": "تقني",
  "center": "المركز الرئيسي",
  "salary": "5000",
  "isActive": true,
  "firstSystemPermissions": {
    "attendance": true,
    "agent": true,
    "tasks": true,
    "zones": true,
    "ai_search": false
  },
  "secondSystemPermissions": {
    "users": true,
    "subscriptions": true,
    "tasks": true,
    ...
  },
  "createdAt": "timestamp",
  "createdBy": "user_id_or_admin_id",
  "lastLogin": "timestamp"
}
```

---

## 🚀 خطوات التفعيل

### 1. إنشاء Super Admin الأول

#### طريقة PowerShell:
```powershell
# استخدم السكريبت الموجود
.\create_superadmin.ps1
```

#### طريقة Firebase Console:
1. افتح Firebase Console
2. اذهب إلى Firestore Database
3. أنشئ Collection اسمها `super_admins`
4. أضف Document بالبيانات التالية:

```json
{
  "username": "superadmin",
  "passwordHash": "5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8",
  "name": "المدير العام",
  "email": "admin@example.com",
  "createdAt": [تاريخ الآن]
}
```

**ملاحظة**: `passwordHash` أعلاه يساوي "password" (للتجربة فقط - غيرها فوراً!)

### 2. تشغيل التطبيق

```powershell
cd "d:\flutter\app\ramz1 top\old_project"
flutter run -d windows
```

### 3. تسجيل الدخول كـ Super Admin

- الصفحة: `SuperAdminLoginPage`
- اسم المستخدم: `superadmin`
- كلمة المرور: `password`

### 4. إضافة شركة جديدة

من لوحة التحكم → "إدارة الشركات" → زر "+"

املأ البيانات:
- **معلومات الشركة**:
  - اسم الشركة
  - كود الشركة (فريد)
  - البريد الإلكتروني
  - رقم الهاتف
  - العنوان

- **معلومات المدير الأول**:
  - اسم المستخدم
  - كلمة المرور
  - الاسم الكامل
  - البريد الإلكتروني
  - رقم الهاتف

- **معلومات الاشتراك**:
  - تاريخ انتهاء الاشتراك
  - نوع الخطة (شهري/سنوي)
  - حد المستخدمين

### 5. إدارة الشركة

#### تعليق شركة:
```dart
await TenantService().suspendTenant(tenantId, "سبب التعليق");
```

#### تمديد اشتراك:
```dart
await TenantService().extendSubscription(
  tenantId,
  DateTime.now().add(Duration(days: 365)),
  'yearly'
);
```

#### إضافة مستخدم للشركة:
```dart
await CustomAuthService().createTenantUser(
  tenantId: tenantId,
  username: "user1",
  password: "password123",
  fullName: "اسم المستخدم",
  role: UserRole.employee,
  firstSystemPermissions: {
    'attendance': true,
    'tasks': true,
  },
  secondSystemPermissions: {
    'subscriptions': true,
    'quick_search': true,
  },
);
```

---

## 🔐 نظام الصلاحيات

### الأدوار المتاحة:
1. **admin** (مدير) - صلاحيات كاملة
2. **manager** (مشرف) - صلاحيات متقدمة
3. **technical_leader** (ليدر فني) - صلاحيات فنية
4. **technician** (فني) - صلاحيات محدودة
5. **employee** (موظف) - صلاحيات أساسية
6. **viewer** (مشاهد) - قراءة فقط

### تمرير الصلاحيات بين النظامين:

#### عند تسجيل دخول المستخدم:
```dart
final result = await CustomAuthService().loginTenantUser(
  tenantCode,
  username,
  password
);

if (result.success && result.tenantUser != null) {
  // الصلاحيات متاحة في:
  final firstPerms = result.tenantUser!.firstSystemPermissions;
  final secondPerms = result.tenantUser!.secondSystemPermissions;
  
  // فحص صلاحية معينة:
  if (firstPerms['attendance'] == true) {
    // السماح بالوصول لصفحة الحضور
  }
  
  if (secondPerms['users'] == true) {
    // السماح بإدارة المستخدمين
  }
}
```

#### في الصفحات:
```dart
// الحصول على المستخدم الحالي
final currentUser = CustomAuthService.currentUser;

// فحص الصلاحيات
if (currentUser?.firstSystemPermissions['tasks'] == true) {
  // عرض زر المهام
}

if (currentUser?.secondSystemPermissions['export'] == true) {
  // عرض زر التصدير
}

// فحص الدور
if (currentUser?.isAdmin == true) {
  // عرض خيارات الإدارة
}
```

---

## 📊 مثال كامل: دورة حياة الشركة

### 1. Super Admin ينشئ شركة
```dart
final result = await TenantService().createTenantWithAdmin(
  tenantName: "شركة الأمل",
  tenantCode: "HOPE2025",
  subscriptionEnd: DateTime.now().add(Duration(days: 365)),
  subscriptionPlan: "yearly",
  maxUsers: 100,
  adminUsername: "admin_hope",
  adminPassword: "SecurePass123!",
  adminFullName: "مدير شركة الأمل",
);

if (result.success) {
  print("تم إنشاء الشركة: ${result.tenantId}");
}
```

### 2. مدير الشركة يسجل دخول
```dart
final authResult = await CustomAuthService().loginTenantUser(
  "HOPE2025",  // كود الشركة
  "admin_hope",
  "SecurePass123!"
);

if (authResult.success) {
  // تم تسجيل الدخول بنجاح
  // الانتقال لصفحة FTTH
}
```

### 3. مدير الشركة يضيف موظفين
```dart
// إضافة فني
await CustomAuthService().createTenantUser(
  tenantId: CustomAuthService.currentTenant!.id,
  username: "tech1",
  password: "Tech123!",
  fullName: "علي الفني",
  role: UserRole.technician,
  department: "التقنية",
  firstSystemPermissions: {
    'tasks': true,
    'zones': true,
  },
  secondSystemPermissions: {
    'tasks': true,
    'quick_search': true,
  },
);

// إضافة محاسب
await CustomAuthService().createTenantUser(
  tenantId: CustomAuthService.currentTenant!.id,
  username: "accountant1",
  password: "Acc123!",
  fullName: "سارة المحاسبة",
  role: UserRole.employee,
  firstSystemPermissions: {},  // بدون صلاحيات النظام الأول
  secondSystemPermissions: {
    'wallet_balance': true,
    'transactions': true,
    'plans_bundles': true,
  },
);
```

### 4. مراقبة الاشتراك
```dart
final tenant = CustomAuthService.currentTenant!;

// فحص حالة الاشتراك
switch (tenant.status) {
  case SubscriptionStatus.active:
    print("الاشتراك نشط - ${tenant.daysRemaining} يوم متبقي");
    break;
  case SubscriptionStatus.warning:
    showWarningDialog("سينتهي الاشتراك خلال ${tenant.daysRemaining} يوم");
    break;
  case SubscriptionStatus.critical:
    showCriticalDialog("الاشتراك ينتهي قريباً!");
    break;
  case SubscriptionStatus.expired:
    navigateToSubscriptionPage();
    break;
  case SubscriptionStatus.suspended:
    showErrorDialog("الحساب معلق: ${tenant.suspensionReason}");
    break;
}
```

### 5. Super Admin يمدد الاشتراك
```dart
await TenantService().extendSubscription(
  tenantId,
  DateTime.now().add(Duration(days: 365)),
  'yearly'
);
```

---

## 🎨 واجهات المستخدم

### Super Admin Dashboard
- **النظرة العامة**: إحصائيات عامة لجميع الشركات
- **إدارة الشركات**: 
  - قائمة الشركات مع البحث والفلترة
  - حالات الاشتراك بألوان مختلفة
  - تعليق/تفعيل الشركات
  - تمديد الاشتراكات
- **زر إضافة شركة**: نموذج من 3 خطوات

### Company Details Page
- معلومات الشركة الأساسية
- حالة الاشتراك وتاريخ الانتهاء
- قائمة المستخدمين
- إضافة/تعديل/حذف مستخدمين
- تفعيل/تعطيل مستخدمين
- تعديل صلاحيات كل مستخدم

---

## ⚙️ التكامل مع old_project

### في main.dart:
```dart
import 'multi_tenant.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  runApp(MyApp());
}
```

### في FTTH Pages:
```dart
import '../../multi_tenant.dart';

// فحص الصلاحيات قبل عرض الميزة
if (CustomAuthService.currentUser?.secondSystemPermissions['users'] == true) {
  // عرض صفحة إدارة المستخدمين
}
```

### فلترة البيانات حسب الشركة:
```dart
// في جميع استعلامات Firestore، أضف:
query = query.where(
  'tenantId', 
  isEqualTo: CustomAuthService.currentTenantId
);
```

---

## 🔒 الأمان

### 1. تشفير كلمات المرور
- SHA-256 hash
- لا يتم حفظ كلمات المرور الأصلية أبداً

### 2. عزل البيانات
- كل شركة لها بياناتها الخاصة
- لا يمكن للشركة الوصول لبيانات شركة أخرى

### 3. التحقق من الصلاحيات
- فحص الصلاحيات في كل عملية
- فحص حالة الاشتراك قبل السماح بالدخول

### 4. تدقيق السجلات
- تسجيل جميع العمليات المهمة
- حفظ معلومات المنشئ/المعدل

---

## 📝 ملاحظات مهمة

1. **TenantId vs OrganizationId**:
   - النظام يستخدم `tenantId` بدلاً من `organizationId`
   - يمكن توحيدهما لاحقاً أو استخدام alias

2. **عزل البيانات**:
   - تأكد من إضافة `tenantId` لجميع Collections الجديدة
   - استخدم Firestore Security Rules للأمان الإضافي

3. **نظام الاشتراكات**:
   - يتم فحص انتهاء الاشتراك عند كل تسجيل دخول
   - يمكن إضافة Cron Job للتحقق الدوري

4. **الصلاحيات الافتراضية**:
   - المدير (admin) يحصل على جميع الصلاحيات
   - باقي الأدوار تبدأ بدون صلاحيات

---

## 🔄 خطوات التطوير المستقبلية

### 1. Dashboard محسن
- [ ] إحصائيات متقدمة
- [ ] رسوم بيانية
- [ ] تقارير شهرية

### 2. نظام الفواتير
- [ ] إنشاء فواتير تلقائية
- [ ] تذكير بالدفع
- [ ] سجل المدفوعات

### 3. نظام الإشعارات
- [ ] تنبيهات انتهاء الاشتراك
- [ ] إشعارات البريد الإلكتروني
- [ ] إشعارات SMS

### 4. تحسينات الأمان
- [ ] Two-Factor Authentication
- [ ] قيود IP
- [ ] سجل تسجيل الدخول

### 5. API للتكامل
- [ ] REST API للشركات
- [ ] Webhooks للأحداث
- [ ] GraphQL API

---

## 🆘 استكشاف الأخطاء

### مشكلة: لا يمكن تسجيل الدخول كـ Super Admin
**الحل**: تأكد من إنشاء Super Admin في Firestore أولاً

### مشكلة: الشركة غير موجودة
**الحل**: تأكد من صحة كود الشركة (case-sensitive)

### مشكلة: المستخدم لا يرى بياناته
**الحل**: تأكد من إضافة فلتر `tenantId` في جميع الاستعلامات

### مشكلة: الصلاحيات لا تعمل
**الحل**: تحقق من أن الصلاحيات محفوظة بشكل صحيح في Firestore

---

## 📞 الدعم

للمساعدة أو الاستفسارات:
- راجع هذا الملف
- تحقق من التعليقات في الكود
- راجع `FILTER_PAGE_AUTH_ANALYSIS.md` للمزيد من التفاصيل

---

**تم إنشاء هذا النظام في**: 25 ديسمبر 2025  
**الإصدار**: 1.0.0  
**الحالة**: ✅ جاهز للاستخدام
