# دليل التشغيل السريع - نظام Firebase Multi-Tenant

## ✅ ما تم إنجازه

### 1. خدمات Firebase الأساسية
- ✅ `firebase_auth_service.dart` - مصادقة مخصصة (username + password)
- ✅ `organizations_service.dart` - إدارة الشركات
- ✅ `firestore_tasks_service.dart` - خدمة المهام
- ✅ `firestore_permissions_service.dart` - نظام الصلاحيات

### 2. واجهات المستخدم
- ✅ `firebase_login_page_new.dart` - صفحة تسجيل الدخول (محدّثة للـ username)
- ✅ `organizations_management_page.dart` - لوحة تحكم Super Admin

### 3. التكامل
- ✅ `main.dart` - استعادة الجلسة عند بدء التطبيق
- ✅ `pubspec.yaml` - حزمة crypto مثبتة

---

## 🚀 خطوات التشغيل

### الخطوة 1: إنشاء Super Admin الأول

انتقل إلى [Firebase Console](https://console.firebase.google.com/):

1. افتح مشروع: **ramz-alsadara2025**
2. اذهب إلى: **Firestore Database**
3. أنشئ Collection: **`users`**
4. أضف Document جديد:

```javascript
{
  "username": "superadmin",
  "password": "5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8",
  "displayName": "المدير العام",
  "organizationId": null,
  "role": "super_admin",
  "isActive": true,
  "createdAt": FieldValue.serverTimestamp(),
  "lastLogin": null
}
```

**ملاحظة:** كلمة المرور `password` مشفرة بـ SHA-256

---

### الخطوة 2: تشغيل التطبيق

```powershell
cd "d:\flutter\app\ramz1 top\old_project"
flutter run -d windows
```

---

### الخطوة 3: تسجيل الدخول

1. افتح التطبيق
2. استخدم بيانات Super Admin:
   - **اسم المستخدم:** `superadmin`
   - **كلمة المرور:** `password`

3. ستُفتح صفحة **إدارة الشركات والمؤسسات**

---

## 📊 استخدام لوحة التحكم

### إدارة الشركات (تبويب 1)

#### إضافة شركة جديدة:
1. اضغط زر "إضافة شركة" (FAB)
2. أدخل:
   - اسم الشركة (مثال: شركة النور للاتصالات)
   - الوصف (اختياري)
3. اضغط "إضافة"

#### تعديل شركة:
1. اضغط على القائمة المنسدلة (⋮) بجانب الشركة
2. اختر "تعديل"
3. عدّل البيانات
4. اضغط "حفظ"

#### تفعيل/تعطيل شركة:
1. اضغط على القائمة المنسدلة (⋮)
2. اختر "تفعيل" أو "تعطيل"

#### عرض إحصائيات الشركة:
- اضغط على السهم لتوسيع بطاقة الشركة
- ستظهر: عدد المستخدمين، المهام، الاشتراكات

---

### إدارة المستخدمين (تبويب 2)

#### إضافة مستخدم لشركة:
1. اختر الشركة من التبويب الأول
2. اذهب لتبويب "المستخدمين"
3. اضغط زر "إضافة مستخدم" (FAB)
4. أدخل:
   - اسم المستخدم (مثال: ahmed123)
   - كلمة المرور (6 أحرف على الأقل)
   - الاسم الكامل (مثال: أحمد محمد)
   - الدور: مدير أو مستخدم
5. اضغط "إضافة"

#### إدارة صلاحيات المستخدم:
1. اضغط على أيقونة 🔒 بجانب المستخدم
2. ستظهر قائمة الصلاحيات مقسمة إلى:
   - **إدارة النظام**: users, accounts, zones, export
   - **العمليات**: subscriptions, tasks, agents, technicians
   - **المالية**: wallet_balance, transactions, plans_bundles
   - **التقارير**: quick_search, expiring_soon, notifications, audit_logs
   - **WhatsApp**: whatsapp, whatsapp_business_api, whatsapp_bulk_sender
3. حدد الصلاحيات المطلوبة
4. اضغط "حفظ الصلاحيات"

---

## 🔐 نظام الأدوار

### 1. Super Admin (المدير الأعلى)
- **الصلاحيات:**
  - إدارة جميع الشركات
  - إنشاء/تعديل/حذف الشركات
  - إدارة مستخدمي جميع الشركات
  - تعيين الصلاحيات
  - عرض جميع البيانات
- **organizationId:** `null` (لا ينتمي لشركة محددة)

### 2. Admin (مدير شركة)
- **الصلاحيات:**
  - إدارة بيانات شركته فقط
  - عرض/تعديل المستخدمين في شركته
  - إدارة المهام والاشتراكات
  - (حسب الصلاحيات المعينة من Super Admin)
- **organizationId:** `{orgId}` (ينتمي لشركة محددة)

### 3. User (مستخدم عادي)
- **الصلاحيات:**
  - عرض البيانات فقط
  - تنفيذ المهام المعينة له
  - (حسب الصلاحيات المعينة من Admin)
- **organizationId:** `{orgId}` (ينتمي لشركة محددة)

---

## 📁 هيكل Firestore

```
ramz-alsadara2025/
├── users/                          # المستخدمون
│   ├── {userId}/
│   │   ├── username: "ahmed123"
│   │   ├── password: "sha256_hash"
│   │   ├── displayName: "أحمد محمد"
│   │   ├── organizationId: "{orgId}" | null
│   │   ├── role: "super_admin" | "admin" | "user"
│   │   ├── isActive: true
│   │   ├── createdAt: Timestamp
│   │   └── lastLogin: Timestamp
│
├── organizations/                   # الشركات
│   ├── {orgId}/
│   │   ├── name: "شركة النور"
│   │   ├── description: "شركة اتصالات"
│   │   ├── isActive: true
│   │   ├── createdAt: Timestamp
│   │   ├── updatedAt: Timestamp
│   │   └── stats:
│   │       ├── usersCount: 5
│   │       ├── tasksCount: 120
│   │       └── subscriptionsCount: 350
│
├── tasks/                           # المهام
│   ├── {taskId}/
│   │   ├── organizationId: "{orgId}"    # ← عزل البيانات
│   │   ├── title: "تركيب خط جديد"
│   │   ├── description: "..."
│   │   ├── status: "pending"
│   │   ├── assignedTo: "ahmed123"
│   │   └── createdAt: Timestamp
│
├── subscriptions/                   # الاشتراكات (مستقبلاً)
│   ├── {subId}/
│   │   ├── organizationId: "{orgId}"    # ← عزل البيانات
│   │   ├── customerName: "علي أحمد"
│   │   └── ...
│
└── permissions/                     # الصلاحيات
    ├── {orgId}/
    │   ├── {userId}/
    │   │   ├── users: true
    │   │   ├── subscriptions: true
    │   │   ├── tasks: false
    │   │   └── ...
```

---

## 🔄 تدفق المصادقة (Authentication Flow)

```
1. المستخدم يدخل username + password
   ↓
2. FirebaseAuthService.signInWithUsername()
   ↓
3. البحث في Firestore: users collection
   ↓
4. مقارنة password (SHA-256)
   ↓
5. التحقق من isActive
   ↓
6. حفظ الجلسة (SharedPreferences)
   ↓
7. إرجاع userData مع organizationId و role
   ↓
8. التوجيه حسب الدور:
   - super_admin → OrganizationsManagementPage
   - admin/user → LoginPage (FTTH مع عزل البيانات)
```

---

## 🛡️ الصلاحيات المتاحة

### إدارة النظام
- `users` - إدارة المستخدمين
- `accounts` - إدارة الحسابات
- `zones` - إدارة المناطق
- `export` - تصدير البيانات

### العمليات
- `subscriptions` - الاشتراكات
- `tasks` - المهام
- `agents` - الوكلاء
- `technicians` - فني التوصيل

### المالية
- `wallet_balance` - رصيد المحفظة
- `transactions` - التحويلات
- `plans_bundles` - الباقات

### التقارير
- `quick_search` - البحث السريع
- `expiring_soon` - المنتهية قريباً
- `notifications` - الإشعارات
- `audit_logs` - سجل التدقيق

### WhatsApp
- `whatsapp` - رسائل WhatsApp
- `whatsapp_business_api` - WhatsApp Business API
- `whatsapp_bulk_sender` - الإرسال الجماعي
- `whatsapp_conversations_fab` - زر المحادثات

### التخزين
- `local_storage` - التخزين المحلي
- `local_storage_import` - استيراد البيانات

---

## 🔧 خطوات إضافية (اختيارية)

### 1. إزالة Google Sheets (لاحقاً)

```powershell
# حذف الملف
Remove-Item "lib\services\google_sheets_service.dart"

# تحديث pubspec.yaml (إزالة)
# gsheets: ^0.5.0
# googleapis: any
# googleapis_auth: any

# تشغيل
flutter pub get
flutter clean
```

### 2. اختبار الصلاحيات في الصفحات

في أي صفحة تريد حماية:

```dart
import '../../services/firestore_permissions_service.dart';

// في initState أو build
final hasPermission = await FirestorePermissionsService()
    .hasPermission(organizationId, userId, 'subscriptions');

if (!hasPermission) {
  // عرض رسالة خطأ أو إخفاء المحتوى
}
```

### 3. عزل البيانات في الاستعلامات

```dart
// في أي خدمة تتعامل مع Firestore
final userData = await FirebaseAuthService.getUserData(userId);
final orgId = userData['organizationId'];

// استعلام مع عزل البيانات
final query = FirebaseFirestore.instance
    .collection('tasks')
    .where('organizationId', isEqualTo: orgId) // ← عزل
    .where('status', isEqualTo: 'pending');
```

---

## 📝 ملاحظات مهمة

1. **كلمات المرور مشفرة**: يستخدم SHA-256، لا يمكن استرجاعها
2. **organizationId = null**: للـ super_admin فقط
3. **عزل البيانات**: كل استعلام يجب أن يحتوي على `organizationId`
4. **الصلاحيات الافتراضية**: جميعها `false` عند إنشاء مستخدم جديد
5. **isActive**: يجب أن يكون `true` لتسجيل الدخول

---

## 🆘 استكشاف الأخطاء

### خطأ: "ليس لديك صلاحية الوصول"
**الحل:** تأكد من `role = 'super_admin'` في Firestore

### خطأ: "اسم المستخدم أو كلمة المرور غير صحيحة"
**الحل:** 
- تحقق من `username` (حساس لحالة الأحرف)
- تأكد من تشفير كلمة المرور بـ SHA-256

### لا تظهر البيانات للمستخدم
**الحل:**
- تحقق من `organizationId` في كل من users و البيانات المطلوبة
- تأكد من `isActive = true`
- تحقق من الصلاحيات في `permissions/{orgId}/{userId}`

### خطأ: "crypto package not found"
**الحل:**
```powershell
cd "d:\flutter\app\ramz1 top\old_project"
flutter pub get
```

---

## 🎯 الخطوات القادمة

1. ✅ تسجيل الدخول كـ Super Admin
2. ✅ إنشاء شركة تجريبية
3. ✅ إضافة مستخدم تجريبي للشركة
4. ✅ تعيين صلاحيات المستخدم
5. ⏳ تسجيل الدخول كمستخدم الشركة واختبار العزل
6. ⏳ ربط صفحات FTTH مع نظام الصلاحيات
7. ⏳ إزالة Google Sheets بالكامل

---

تم التوثيق بتاريخ: 25 ديسمبر 2025
