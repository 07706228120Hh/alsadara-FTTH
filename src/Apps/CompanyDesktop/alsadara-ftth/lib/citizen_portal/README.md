# 🏛️ مجلد بوابة المواطن (Citizen Portal)

هذا المجلد مخصص بالكامل لإدارة **نظام المواطن** داخل تطبيق الشركة.

## 📁 البنية

```
citizen_portal/
├── models/               # نماذج البيانات
│   ├── company_model.dart      # نموذج الشركة من API
│   └── citizen_model.dart      # نموذج المواطن من API
│
├── services/            # خدمات الاتصال بالـ API
│   └── company_api_service.dart # خدمة API الشركات
│
├── pages/               # الشاشات الرئيسية
│   ├── companies_management_page.dart        # شاشة إدارة الشركات (مدير النظام)
│   └── citizen_portal_dashboard_page.dart    # شاشة بوابة المواطن (الشركة المرتبطة)
│
├── widgets/             # مكونات مشتركة (سيتم إضافتها)
│
└── citizen_portal.dart  # ملف التصدير الرئيسي
```

## 🎯 الغرض

### 1. شاشة إدارة الشركات (CompaniesManagementPage)
**لمن؟** مدير النظام (SuperAdmin) فقط

**الوظائف:**
- ✅ عرض جميع الشركات
- ✅ إضافة/تعديل/حذف شركات
- ✅ تعليق/تفعيل شركات
- ✅ **اختيار الشركة المرتبطة بنظام المواطن** (شركة واحدة فقط)
- ✅ إلغاء الربط من أي شركة

**كيفية الوصول:**
```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => CompaniesManagementPage()),
);
```

---

### 2. شاشة بوابة المواطن (CitizenPortalDashboardPage)
**لمن؟** مدير وموظفي **الشركة المرتبطة فقط**

**الوظائف:**
- 👥 إدارة المواطنين (عرض/تعديل/حظر)
- 📋 طلبات الاشتراكات (موافقة/رفض)
- 💰 الاشتراكات الفعالة
- 🎫 الدعم الفني (التذاكر)
- 🛒 طلبات المتجر
- 📊 التقارير والإحصائيات

**شرط الظهور:**
- الشركة الحالية يجب أن تكون هي المرتبطة بنظام المواطن
- إذا لم تكن مرتبطة، ستظهر رسالة "غير متاحة"

**كيفية الوصول:**
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => CitizenPortalDashboardPage(
      companyId: currentCompanyId,
    ),
  ),
);
```

---

## 🔗 الاتصال بالـ Backend

يتصل بـ **.NET API** على الرابط:
```
https://72.61.183.61/api/Companies
```

### API Endpoints المستخدمة:

1. `GET /api/Companies` - جميع الشركات
2. `GET /api/Companies/linked-to-citizen-portal` - الشركة المرتبطة
3. `POST /api/Companies` - إنشاء شركة
4. `POST /api/Companies/link-to-citizen-portal` - ربط شركة
5. `POST /api/Companies/unlink-from-citizen-portal` - إلغاء الربط
6. `POST /api/Companies/{id}/toggle-status` - تعليق/تفعيل
7. `DELETE /api/Companies/{id}` - حذف شركة

---

## 🚀 التوسعات المستقبلية

### الصفحات المطلوب إضافتها:

1. **Citizens Management** - إدارة المواطنين
   - `lib/citizen_portal/pages/citizens_list_page.dart`
   - `lib/citizen_portal/pages/citizen_details_page.dart`

2. **Subscription Requests** - طلبات الاشتراك
   - `lib/citizen_portal/pages/subscription_requests_page.dart`

3. **Active Subscriptions** - الاشتراكات الفعالة
   - `lib/citizen_portal/pages/subscriptions_page.dart`

4. **Support Tickets** - تذاكر الدعم
   - `lib/citizen_portal/pages/tickets_page.dart`
   - `lib/citizen_portal/pages/ticket_details_page.dart`

5. **Store Orders** - طلبات المتجر
   - `lib/citizen_portal/pages/store_orders_page.dart`

6. **Reports** - التقارير
   - `lib/citizen_portal/pages/reports_page.dart`

---

## 💡 ملاحظات مهمة

1. **عزل تام:** كل بيانات نظام المواطن معزولة في هذا المجلد
2. **سهولة الصيانة:** يمكن تطوير وصيانة نظام المواطن بشكل مستقل
3. **قابلية التوسع:** إضافة صفحات جديدة سهلة وواضحة
4. **الأمان:** التحقق من الشركة المرتبطة في كل عملية

---

## 🔐 الأمان والصلاحيات

- ✅ **مدير النظام:** الوصول الكامل لإدارة الشركات واختيار المرتبطة
- ✅ **الشركة المرتبطة:** الوصول الكامل لبوابة المواطن
- ❌ **الشركات الأخرى:** لا يمكنها رؤية أو الوصول لبوابة المواطن

---

## 📝 مثال الاستخدام

### في HomePage الرئيسية:

```dart
// إضافة في قائمة الشاشات (فقط لمدير النظام)
if (isSuperAdmin) {
  ListTile(
    leading: Icon(Icons.business),
    title: Text('إدارة الشركات'),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CompaniesManagementPage()),
    ),
  ),
}

// إضافة في قائمة الشاشات (فقط للشركة المرتبطة)
if (isLinkedToCitizenPortal) {
  ListTile(
    leading: Icon(Icons.people),
    title: Text('بوابة المواطن'),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CitizenPortalDashboardPage(
          companyId: currentCompanyId,
        ),
      ),
    ),
  ),
}
```

---

تم التطوير بواسطة GitHub Copilot ✨
