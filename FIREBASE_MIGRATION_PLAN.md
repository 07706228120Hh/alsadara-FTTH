# خطة نقل البيانات من Google Sheets إلى Firebase Firestore

## 🎯 الهدف
إزالة الاعتماد على Google Sheets بالكامل واستخدام Firebase Firestore لكل شيء

---

## 📊 البيانات المخزنة حالياً في Google Sheets

### 1. **المهام (Tasks)**
- الموقع: `tasks!A2:T`
- البيانات: (20 عمود)
  - معلومات المهمة
  - الحالة
  - الفني المسؤول
  - رقم الهاتف
  - التواريخ
  - إلخ...

### 2. **المستخدمين (Users)** ❓
- من `assets/users_fallback.json`

### 3. **البيانات الأخرى** ❓
- يحتاج فحص `google_sheets_service.dart`

---

## 🔄 بنية Firestore المقترحة

```
organizations/
  {orgId}/
    name: "اسم المنظمة"
    createdAt: timestamp
    isActive: true
    users: {
      {userId}: {
        displayName: "الاسم"
        email: "email@example.com"
        role: "user" | "admin" | "technician"
        permissions: {
          first_system_attendance: true,
          second_system_users: true,
          ...
        }
      }
    }

users/
  {userId}/
    email: "user@example.com"
    displayName: "أحمد محمد"
    photoURL: "..."
    role: "user" | "admin" | "technician"
    organizationId: "{orgId}"
    isActive: true
    createdAt: timestamp
    lastLogin: timestamp
    metadata: {
      phone: "+9647XXXXXXXX"
      address: "..."
    }

tasks/
  {taskId}/
    organizationId: "{orgId}"
    title: "عنوان المهمة"
    description: "الوصف"
    status: "pending" | "in_progress" | "completed" | "cancelled"
    priority: "low" | "medium" | "high"
    assignedTo: {
      userId: "{userId}"
      displayName: "الفني"
      phone: "+9647XXXXXXXX"
    }
    location: {
      address: "العنوان"
      coordinates: GeoPoint(lat, lng)
    }
    dates: {
      createdAt: timestamp
      updatedAt: timestamp
      dueDate: timestamp
      completedAt: timestamp?
    }
    metadata: {
      // أي بيانات إضافية من الأعمدة
    }

subscriptions/
  {subscriptionId}/
    organizationId: "{orgId}"
    customerId: "{userId}"
    customerName: "اسم المشترك"
    customerPhone: "+9647XXXXXXXX"
    plan: {
      name: "اسم الباقة"
      speed: "100 Mbps"
      price: 50000
    }
    status: "active" | "expired" | "suspended"
    dates: {
      startDate: timestamp
      endDate: timestamp
      createdAt: timestamp
    }
    location: {
      address: "العنوان"
      zone: "Zone A"
    }

zones/
  {zoneId}/
    organizationId: "{orgId}"
    name: "Zone A"
    technicians: [
      {userId}: true
    ]
    subscribersCount: 100
    activeSubscriptionsCount: 85

agents/
  {agentId}/
    organizationId: "{orgId}"
    name: "اسم الوكيل"
    phone: "+9647XXXXXXXX"
    email: "agent@example.com"
    commission: 10 // نسبة العمولة
    totalSales: 1000000
    isActive: true

accounts/
  {accountId}/
    organizationId: "{orgId}"
    type: "income" | "expense"
    amount: 50000
    description: "الوصف"
    category: "subscription" | "maintenance" | "salary" | ...
    date: timestamp
    createdBy: "{userId}"
    createdAt: timestamp

notifications/
  {notificationId}/
    organizationId: "{orgId}"
    userId: "{userId}" // null = للجميع
    title: "العنوان"
    body: "المحتوى"
    type: "info" | "warning" | "success" | "error"
    isRead: false
    createdAt: timestamp

activity_logs/
  {logId}/
    organizationId: "{orgId}"
    userId: "{userId}"
    action: "login" | "create_task" | "update_subscription" | ...
    details: "..."
    timestamp: timestamp
```

---

## 🛠️ خطوات التنفيذ

### المرحلة 1: إنشاء خدمات Firestore (✅ جاهزة للبدء)
- ✅ `firebase_auth_service.dart` - موجود
- ✅ `firestore_permissions_service.dart` - موجود
- 🔲 `firestore_tasks_service.dart` - جديد
- 🔲 `firestore_users_service.dart` - جديد
- 🔲 `firestore_subscriptions_service.dart` - جديد
- 🔲 `firestore_zones_service.dart` - جديد
- 🔲 `firestore_agents_service.dart` - جديد
- 🔲 `firestore_accounts_service.dart` - جديد

### المرحلة 2: استبدال استدعاءات Google Sheets
- 🔲 فحص جميع الصفحات التي تستخدم `GoogleSheetsService`
- 🔲 استبدالها بـ `FirestoreXxxService`
- 🔲 اختبار كل صفحة

### المرحلة 3: نقل البيانات
- 🔲 تصدير البيانات من Google Sheets (يدوي أو سكربت)
- 🔲 إنشاء سكربت لاستيراد البيانات إلى Firestore
- 🔲 التحقق من البيانات

### المرحلة 4: التنظيف
- 🔲 إزالة `google_sheets_service.dart`
- 🔲 إزالة `gsheets` و `googleapis` من pubspec.yaml
- 🔲 إزالة `assets/service_account.json` (Google Sheets)
- 🔲 تحديث الوثائق

---

## ⚡ المزايا بعد النقل

1. **أسرع**: Firestore أسرع من Google Sheets API
2. **Real-time**: تحديثات فورية بدون polling
3. **Offline**: دعم offline caching تلقائي
4. **أمان**: قواعد Firestore Security Rules
5. **Scalable**: يتحمل آلاف المستخدمين
6. **مجاني**: حتى 50k reads/day مجانية

---

## 📝 ملاحظات مهمة

1. **Firestore له حدود:**
   - Document size: max 1MB
   - Batch writes: max 500 operations
   - Array fields: max 20,000 items

2. **يجب إعداد Security Rules:**
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // المستخدمون المصادقون فقط
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
    
    // الصلاحيات حسب Organization
    match /organizations/{orgId} {
      allow read: if request.auth != null && 
                     request.auth.token.organizationId == orgId;
      allow write: if request.auth != null && 
                      request.auth.token.role == 'admin';
    }
  }
}
```

3. **يجب إنشاء Indexes للبحث السريع**

---

## 🚀 هل تريد البدء؟

أخبرني إذا كنت تريد:
1. ✅ إنشاء خدمات Firestore الجديدة
2. ✅ سكربت لنقل البيانات من Google Sheets
3. ✅ استبدال الكود القديم
