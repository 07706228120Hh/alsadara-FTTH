# ✅ ملخص التنفيذ: ربط نظام المواطن بالشركات

## 🎯 ما تم إنجازه

تم تنفيذ نظام متكامل يربط **نظام المواطن** بشركة واحدة من الشركات الموجودة في النظام، مع إمكانية مدير النظام باختيار أي شركة وتغييرها في أي وقت.

---

## 📦 المكونات المنفذة

### 1. **Backend (.NET API)** ✅

#### Entity (Domain Layer)
- ✅ `Company.cs` - تم تحديثه بإضافة:
  - `IsLinkedToCitizenPortal` (bool)
  - `LinkedToCitizenPortalAt` (DateTime?)
  - `LinkedById` (Guid?)

#### DTOs (API Layer)
- ✅ `CompanyDto.cs` - عرض بيانات الشركة
- ✅ `UpsertCompanyDto.cs` - إنشاء/تحديث شركة
- ✅ `LinkToCitizenPortalDto.cs` - ربط/إلغاء ربط بنظام المواطن

#### Controllers
- ✅ `CompaniesController.cs` موجود مسبقاً ويحتوي على:
  - `GET /api/Companies` - جميع الشركات
  - `GET /api/Companies/linked-to-citizen-portal` - الشركة المرتبطة
  - `POST /api/Companies` - إنشاء شركة
  - `POST /api/Companies/link-to-citizen-portal` - ربط شركة ⭐
  - `POST /api/Companies/unlink-from-citizen-portal` - إلغاء الربط
  - `POST /api/Companies/{id}/toggle-status` - تعليق/تفعيل
  - `DELETE /api/Companies/{id}` - حذف شركة

---

### 2. **Frontend (Flutter - alsadara-ftth)** ✅

#### البنية الجديدة
تم إنشاء مجلد `citizen_portal/` كامل ومنظم:

```
lib/citizen_portal/
├── models/
│   ├── company_model.dart        ✅
│   └── citizen_model.dart        ✅
├── services/
│   └── company_api_service.dart  ✅
├── pages/
│   ├── companies_management_page.dart       ✅ (مدير النظام)
│   └── citizen_portal_dashboard_page.dart   ✅ (الشركة المرتبطة)
├── widgets/
│   └── (جاهز للإضافة)
├── citizen_portal.dart           ✅ (ملف التصدير)
└── README.md                     ✅ (التوثيق)
```

#### الشاشات المنفذة

**1. CompaniesManagementPage** (لمدير النظام)
- عرض جميع الشركات في Cards
- عرض حالة كل شركة (نشط/معلق)
- عرض معلومات الاشتراك والأيام المتبقية
- زر "ربط بنظام المواطن" لكل شركة نشطة
- زر "إلغاء الربط" للشركة المرتبطة حالياً
- تأكيد قبل الربط/الإلغاء
- تحديث تلقائي بعد كل عملية

**2. CitizenPortalDashboardPage** (للشركة المرتبطة)
- **تحقق تلقائي:** تتحقق الشاشة من أن الشركة الحالية هي المرتبطة
- **منع الوصول:** إذا لم تكن الشركة مرتبطة، تظهر رسالة "غير متاحة"
- **لوحة التحكم:**
  - إحصائيات (المواطنين، الطلبات، الاشتراكات، التذاكر)
  - إجراءات سريعة:
    - إدارة المواطنين
    - طلبات الاشتراك
    - الاشتراكات الفعالة
    - الدعم الفني
    - طلبات المتجر
    - التقارير

---

## 🔄 سير العمل (Workflow)

### مدير النظام:
1. يفتح **شاشة إدارة الشركات**
2. يرى جميع الشركات مع حالاتها
3. يختار الشركة المطلوب ربطها بنظام المواطن
4. يضغط "ربط بنظام المواطن"
5. يظهر تأكيد: "سيتم إلغاء ربط أي شركة أخرى"
6. بعد الموافقة:
   - يتم إلغاء ربط الشركة القديمة (إن وجدت)
   - يتم ربط الشركة الجديدة
   - تحديث القائمة تلقائياً

### مدير/موظف الشركة:
1. إذا كانت شركته **مرتبطة**:
   - يرى قائمة "بوابة المواطن" في الشاشة الرئيسية
   - يفتح الشاشة ويرى لوحة التحكم الكاملة
   - يستطيع إدارة جميع بيانات المواطنين

2. إذا كانت شركته **غير مرتبطة**:
   - لا يرى قائمة "بوابة المواطن" (أو معطلة)
   - إذا حاول الدخول يدوياً، تظهر رسالة "غير متاحة"

---

## 📊 قاعدة البيانات

### جدول Companies
تم إضافة الحقول التالية:

| الحقل | النوع | الوصف |
|------|------|-------|
| `IsLinkedToCitizenPortal` | `bool` | هل الشركة مرتبطة؟ (واحدة فقط = true) |
| `LinkedToCitizenPortalAt` | `DateTime?` | تاريخ الربط |
| `LinkedById` | `Guid?` | من قام بالربط (مدير النظام) |

### جدول Citizens
يحتوي على:
- `CompanyId` (Guid) - معرف الشركة المرتبطة
- كل مواطن يسجل يُربط تلقائياً بالشركة المختارة

---

## 🔐 الأمان والصلاحيات

### القواعد المطبقة:

1. **شركة واحدة فقط:**
   - عند ربط شركة جديدة → إلغاء ربط القديمة تلقائياً

2. **عدم ربط شركة معلقة:**
   - لا يمكن ربط شركة غير نشطة بنظام المواطن
   - عند تعليق شركة مرتبطة → إلغاء الربط تلقائياً

3. **عزل البيانات:**
   - كل شركة ترى بياناتها فقط
   - الشركة المرتبطة ترى المواطنين التابعين لها فقط

4. **التحقق المستمر:**
   - `CitizenPortalDashboardPage` تتحقق من الربط عند كل فتح
   - إذا تغير الربط → تظهر رسالة "غير متاحة"

---

## 🚀 الخطوات التالية (Next Steps)

### ✅ تم إنجازه:
- [x] إنشاء Entity & DTOs & Controller في Backend
- [x] إنشاء Models & Services في Flutter
- [x] إضافة شاشة إدارة الشركات (مدير النظام)
- [x] إضافة شاشة بوابة المواطن (الشركة المرتبطة)
- [x] إنشاء مجلد منظم citizen_portal/
- [x] توثيق كامل (README.md)

### ⏳ المطلوب لاحقاً:

1. **إضافة في HomePage الرئيسية:**
   ```dart
   // في قائمة الشاشات
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

2. **إنشاء صفحات فرعية:**
   - إدارة المواطنين (عرض/تعديل/حظر)
   - طلبات الاشتراك (موافقة/رفض)
   - الاشتراكات الفعالة
   - تذاكر الدعم
   - طلبات المتجر
   - التقارير

3. **تشغيل Migration:**
   ```bash
   cd C:\Sadara.API
   dotnet ef migrations add AddCitizenPortalLink
   dotnet ef database update
   ```

4. **تحديث CitizenWeb:**
   - عند التسجيل: جلب الشركة المرتبطة
   - تعيين `CompanyId` تلقائياً للمواطن الجديد

---

## 📝 أمثلة الاستخدام

### Backend API

```csharp
// ربط شركة بنظام المواطن
POST /api/Companies/link-to-citizen-portal
{
  "companyId": "guid-here"
}

// الحصول على الشركة المرتبطة
GET /api/Companies/linked-to-citizen-portal
```

### Flutter

```dart
// جلب الشركة المرتبطة
final linkedCompany = await CompanyApiService.getLinkedCompany();

// ربط شركة
await CompanyApiService.linkToCitizenPortal(companyId);

// إلغاء الربط
await CompanyApiService.unlinkFromCitizenPortal(companyId);
```

---

## 🎉 النتيجة النهائية

✅ **نظام متكامل** يربط نظام المواطن بشركة واحدة مختارة  
✅ **مدير النظام** يستطيع التحكم الكامل في الربط  
✅ **الشركة المرتبطة** تدير جميع بيانات المواطنين  
✅ **باقي الشركات** لا ترى نظام المواطن أبداً  
✅ **بنية منظمة** في مجلد `citizen_portal/` سهلة الصيانة والتوسع  

---

تم التطوير بنجاح! 🚀
