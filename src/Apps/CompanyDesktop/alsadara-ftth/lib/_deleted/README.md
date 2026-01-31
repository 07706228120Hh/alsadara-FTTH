# 🗑️ الملفات المحذوفة (للمراجعة)

> هذا المجلد يحتوي على ملفات تم نقلها من المشروع لأنها **غير مستخدمة حالياً**.
> يمكن مراجعتها واستعادتها إذا احتجنا إليها في المستقبل.

---

## 📅 تاريخ النقل: 31 يناير 2026

---

## 📂 الملفات المنقولة (6 ملفات)

### pages/

| الملف | السبب | المصدر الأصلي |
|-------|-------|---------------|
| `firebase_login_page.dart` | التطبيق يستخدم VPS API وليس Firebase | `lib/pages/` |
| `firebase_login_page_new.dart` | نسخة محدثة غير مستخدمة | `lib/pages/` |
| `login_page.dart` | **نظام قديم يستخدم Google Sheets** - تم استبداله بـ VpsTenantLoginPage | `lib/pages/` |
| `tenant_login_page.dart` | نسخة Firebase - تم استبدالها بـ VpsTenantLoginPage | `lib/pages/` |
| `super_admin_login_page.dart` | نسخة Firebase - يُستخدم `vps_super_admin_login_page.dart` بدلاً منها | `lib/pages/super_admin/` |
| `super_admin_pages.dart` | ملف export غير مستخدم | `lib/pages/super_admin/` |

---

## ✅ الملفات المستخدمة حالياً لتسجيل الدخول

| الملف | الاستخدام |
|-------|-----------|
| `vps_tenant_login_page.dart` | ✅ صفحة الدخول الرئيسية (VPS API) |
| `vps_super_admin_login_page.dart` | ✅ دخول مدير النظام (VPS API) |
| `ftth/auth/login_page.dart` | ✅ دخول نظام FTTH من الواجهة الرئيسية |

---

## 🔄 التغييرات التي تمت

تم تحديث الملفات التالية لاستخدام `VpsTenantLoginPage`:

1. ✅ `main.dart` - نقطة الدخول الرئيسية
2. ✅ `widgets/auth_guard.dart` - حارس المصادقة
3. ✅ `widgets/permissions_gate.dart` - بوابة الصلاحيات
4. ✅ `services/app_initialization_service.dart` - خدمة التهيئة
5. ✅ `pages/home_page.dart` - زر تسجيل الخروج
6. ✅ `pages/enhanced_home_page.dart` - الصفحة المحسنة
7. ✅ `pages/super_admin/super_admin_dashboard.dart` - لوحة تحكم مدير النظام
8. ✅ `pages/admin/organizations_management_page.dart` - إدارة الشركات

---

## ⚠️ ملاحظات

1. **لا تحذف هذا المجلد** - قد نحتاج الملفات للمراجعة
2. **إذا أردت استعادة ملف** - انقله إلى موقعه الأصلي وأعد المراجع
3. **إعدادات البيانات الحالية**: `DataSourceConfig.currentSource = DataSource.vpsApi`

---

## 🔄 كيفية استعادة ملف

```powershell
# مثال: استعادة tenant_login_page.dart
Move-Item "lib/_deleted/pages/tenant_login_page.dart" "lib/pages/"
```

ثم أعد import في الملفات التي تحتاجه.
