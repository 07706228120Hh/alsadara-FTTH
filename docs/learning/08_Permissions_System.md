# 📚 الدرس #8: نظام الصلاحيات بالتفصيل

## 🎯 ما هو نظام الصلاحيات؟

**نظام الصلاحيات** يتحكم في:
- **من** يستطيع الوصول
- **ماذا** يستطيع أن يرى
- **أي إجراءات** يستطيع تنفيذها

---

## 🏗️ هرم الصلاحيات

```
                    👑 SuperAdmin
                   /            \
                  /              \
         🏢 CompanyAdmin    🏢 CompanyAdmin
              /    \              /    \
             /      \            /      \
        👷 Manager  👷 Manager  ...     ...
           /   \
          /     \
     👨‍💼 Employee  👨‍💼 Employee
```

---

## 👥 أدوار المستخدمين (UserRole)

```csharp
public enum UserRole
{
    Citizen = 0,        // مواطن (عميل)
    Employee = 10,      // موظف
    Viewer = 11,        // مشاهد فقط
    Technician = 12,    // فني
    TechnicalLeader = 13, // ليدر فني
    Manager = 14,       // مشرف
    CompanyAdmin = 20,  // مدير شركة
    SuperAdmin = 99     // مدير النظام
}
```

### 💡 ملاحظة الأرقام

الأرقام مُرتبة بحيث:
```csharp
// يمكن المقارنة مباشرة
if (user.Role >= UserRole.Manager)
{
    // مشرف أو أعلى
}

if (user.Role >= UserRole.CompanyAdmin)
{
    // مدير شركة أو مدير نظام
}
```

---

## 📊 نظامان للصلاحيات

### النظام 1: صلاحيات بسيطة (Boolean)

```json
// User.FirstSystemPermissions
{
  "attendance": true,    // الحضور والانصراف
  "agent": false,        // الوكيل
  "dashboard": true,     // لوحة القيادة
  "settings": true       // الإعدادات
}
```

**السؤال:** هل يملك الصلاحية؟ ✅ نعم / ❌ لا

### النظام 2: صلاحيات مفصلة (Actions)

```json
// User.SecondSystemPermissionsV2
{
  "users": {
    "view": true,      // عرض
    "add": true,       // إضافة
    "edit": false,     // تعديل
    "delete": false,   // حذف
    "export": false    // تصدير
  },
  "orders": {
    "view": true,
    "add": true,
    "edit": true,
    "delete": false,
    "export": true
  },
  "subscriptions": {
    "view": true,
    "add": false,
    "edit": false,
    "delete": false
  }
}
```

**السؤال:** ماذا يستطيع أن يفعل في كل قسم؟

---

## 🔄 تدفق الصلاحيات

```
┌─────────────────────────────────────────────────────────────┐
│  SuperAdmin يُنشئ شركة                                      │
│  ويُحدد الميزات المُتاحة للشركة                             │
│  Company.EnabledSecondSystemFeaturesV2                      │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  CompanyAdmin يُنشئ موظفين                                  │
│  ويُحدد صلاحيات كل موظف (ضمن حدود الشركة)                  │
│  User.SecondSystemPermissionsV2                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  الموظف يستخدم التطبيق                                     │
│  ويرى فقط ما يملك صلاحية له                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 💾 كيف تُخزن الصلاحيات؟

### في جدول Users

```sql
SELECT 
    "FullName",
    "Role",
    "FirstSystemPermissions",    -- JSON
    "SecondSystemPermissionsV2"  -- JSON
FROM "Users"
WHERE "Id" = '...';
```

### مثال على البيانات

| FullName | Role | FirstSystemPermissions | SecondSystemPermissionsV2 |
|----------|------|------------------------|---------------------------|
| أحمد | Employee | `{"attendance":true}` | `{"users":{"view":true,"add":false}}` |
| محمد | Manager | `{"attendance":true,"agent":true}` | `{"users":{"view":true,"add":true,"edit":true}}` |

---

## 🔧 التحقق من الصلاحيات

### في Backend (C#)

```csharp
public class PermissionHelper
{
    public static bool HasPermission(User user, string permission, string? action = null)
    {
        // SuperAdmin يملك كل الصلاحيات
        if (user.Role == UserRole.SuperAdmin)
            return true;

        // تحقق من V2 (الأكثر تفصيلاً)
        if (!string.IsNullOrEmpty(user.SecondSystemPermissionsV2))
        {
            var permissions = JsonSerializer.Deserialize<Dictionary<string, Dictionary<string, bool>>>(
                user.SecondSystemPermissionsV2);
            
            if (permissions.TryGetValue(permission, out var actions))
            {
                if (action == null)
                    return actions.Values.Any(v => v);
                
                return actions.TryGetValue(action, out var hasAction) && hasAction;
            }
        }

        return false;
    }
}
```

### في Controller

```csharp
[HttpDelete("{id}")]
[Authorize]
public async Task<IActionResult> DeleteUser(Guid id)
{
    var currentUser = await GetCurrentUser();
    
    // تحقق من الصلاحية
    if (!PermissionHelper.HasPermission(currentUser, "users", "delete"))
    {
        return Forbid();  // 403
    }

    // تنفيذ الحذف...
}
```

---

## 📱 التحقق في Flutter

### PermissionsService

```dart
class PermissionsService {
  static PermissionsService? _instance;
  static PermissionsService get instance => 
      _instance ??= PermissionsService._internal();
  
  Map<String, dynamic> _permissions = {};

  void setPermissions(Map<String, dynamic> permissions) {
    _permissions = permissions;
  }

  bool hasPermission(String permission, {String? action}) {
    if (!_permissions.containsKey(permission)) return false;
    
    if (action == null) {
      // أي صلاحية في هذا القسم
      final actions = _permissions[permission] as Map<String, dynamic>;
      return actions.values.any((v) => v == true);
    }
    
    // صلاحية محددة
    return _permissions[permission]?[action] == true;
  }
}
```

### PermissionsGate Widget

```dart
class PermissionsGate extends StatelessWidget {
  final String permission;
  final String? action;
  final Widget child;
  final Widget? fallback;

  const PermissionsGate({
    required this.permission,
    required this.child,
    this.action,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    if (PermissionsService.instance.hasPermission(permission, action: action)) {
      return child;
    }
    return fallback ?? const SizedBox.shrink();
  }
}
```

### الاستخدام

```dart
// إخفاء زر إذا لم تكن هناك صلاحية
PermissionsGate(
  permission: 'users',
  action: 'delete',
  child: IconButton(
    icon: Icon(Icons.delete),
    onPressed: () => _deleteUser(user.id),
  ),
)

// إظهار بديل إذا لم تكن هناك صلاحية
PermissionsGate(
  permission: 'reports',
  action: 'export',
  child: ElevatedButton(
    onPressed: _exportReport,
    child: Text('تصدير'),
  ),
  fallback: Text('لا تملك صلاحية التصدير'),
)
```

---

## 🗂️ قائمة الصلاحيات المتاحة

### النظام الأول (FirstSystem)

| الصلاحية | الوصف |
|----------|-------|
| `attendance` | الحضور والانصراف |
| `agent` | الوكيل |
| `dashboard` | لوحة القيادة |
| `settings` | الإعدادات |

### النظام الثاني (SecondSystem)

| الصلاحية | الوصف | الإجراءات |
|----------|-------|-----------|
| `users` | المستخدمين | view, add, edit, delete |
| `subscriptions` | الاشتراكات | view, add, edit, delete |
| `orders` | الطلبات | view, add, edit, delete, export |
| `payments` | المدفوعات | view, add, edit, delete |
| `reports` | التقارير | view, export |
| `products` | المنتجات | view, add, edit, delete |
| `customers` | العملاء | view, add, edit, delete |
| `tickets` | تذاكر الدعم | view, add, edit, delete |

---

## 🔐 صلاحيات الشركة vs صلاحيات الموظف

### Company.EnabledSecondSystemFeaturesV2

```json
// ما هي الميزات المُتاحة لهذه الشركة؟
{
  "users": {"view": true, "add": true, "edit": true, "delete": true},
  "orders": {"view": true, "add": true, "edit": true, "delete": false},
  "reports": {"view": true, "export": false}  // لا يمكن التصدير
}
```

### User.SecondSystemPermissionsV2

```json
// ما صلاحيات هذا الموظف (ضمن حدود شركته)؟
{
  "users": {"view": true, "add": false, "edit": false, "delete": false},
  "orders": {"view": true, "add": true, "edit": true, "delete": false}
}
```

### 💡 القاعدة

```
صلاحية الموظف الفعلية = 
    صلاحية الموظف ∩ صلاحية الشركة
    (التقاطع)
```

حتى لو أعطيت الموظف صلاحية، إذا الشركة لا تملكها، فلن تعمل.

---

## 🛠️ إضافة صلاحية جديدة

### 1️⃣ في Backend (SeedData)

```csharp
// Data/SeedData.cs
var permissions = new List<Permission>
{
    // ... صلاحيات موجودة
    new() { Name = "invoices", NameAr = "الفواتير", SystemType = 2 },
};
```

### 2️⃣ في Flutter (PermissionsService)

```dart
// services/permissions_service.dart
static const List<String> secondSystemPermissions = [
  // ... موجود
  'invoices',
];
```

### 3️⃣ استخدام الصلاحية الجديدة

```dart
PermissionsGate(
  permission: 'invoices',
  action: 'view',
  child: InvoicesPage(),
)
```

---

## 📝 تمارين

1. **في Flutter:** أضف `PermissionsGate` لحماية زر الحذف في صفحة المستخدمين
2. **في Backend:** اكتب method للتحقق من صلاحية المستخدم الحالي
3. **فكر:** لماذا `SuperAdmin` لا يحتاج صلاحيات JSON؟

---

## 🔗 الدرس التالي

[09_JWT_Authentication.md](./09_JWT_Authentication.md) - JWT والمصادقة
