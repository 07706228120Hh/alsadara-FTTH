# 🚀 البدء السريع - نظام Multi-Tenant

## الخطوات الأساسية

### 1️⃣ إنشاء Super Admin
```powershell
.\create_superadmin_tenant.ps1
```

اتبع التعليمات ثم أضف البيانات في Firebase Console.

### 2️⃣ تشغيل التطبيق
```powershell
flutter run -d windows
```

### 3️⃣ تسجيل الدخول
- افتح صفحة **Super Admin Login**
- أدخل اسم المستخدم وكلمة المرور
- ستظهر لك لوحة التحكم

### 4️⃣ إضافة شركة
من لوحة التحكم:
1. اضغط على "إدارة الشركات"
2. اضغط على زر "+"
3. املأ بيانات الشركة والمدير الأول
4. اضغط "إنشاء"

---

## 📚 التوثيق الكامل
اقرأ [MULTI_TENANT_SYSTEM_GUIDE.md](MULTI_TENANT_SYSTEM_GUIDE.md) للدليل الشامل.

## 🔑 الميزات
✅ Super Admin Dashboard  
✅ إدارة الشركات  
✅ نظام الاشتراكات  
✅ حالات الاشتراك (نشط، تحذير، حرج، منتهي، معلق)  
✅ إدارة المستخدمين  
✅ نظام الصلاحيات المتقدم (نظامين)  
✅ عزل كامل للبيانات  

## 📂 الملفات المهمة
- `lib/multi_tenant.dart` - تصدير موحد
- `lib/models/` - النماذج (Tenant, TenantUser, SuperAdmin)
- `lib/services/` - الخدمات (CustomAuthService, TenantService)
- `lib/pages/super_admin/` - واجهات Super Admin

---

**الحالة**: ✅ جاهز للاستخدام  
**التاريخ**: 25 ديسمبر 2025
