# 🔗 كيفية إضافة بوابة المواطن في HomePage

## ✅ تم إنجازه:
- ✅ CitizenPortalDashboardPage - صفحة لوحة التحكم
- ✅ CompaniesManagementPage - صفحة إدارة الشركات (مدير النظام)
- ✅ CitizenPortalHelper - خدمة مساعدة للتحقق من الشركة المرتبطة

---

## 📝 الخطوات المطلوبة في HomePage:

### 1️⃣ استيراد الملفات المطلوبة

في أعلى ملف `home_page.dart`:

```dart
import 'package:alsadara/citizen_portal/citizen_portal.dart';
import 'package:alsadara/citizen_portal/services/citizen_portal_helper.dart';
```

---

### 2️⃣ إضافة متغير لحالة الشركة المرتبطة

في `_HomePageState`:

```dart
class _HomePageState extends State<HomePage> {
  bool isLinkedToCitizenPortal = false;
  bool isCheckingLink = true;
  
  @override
  void initState() {
    super.initState();
    _checkIfLinkedToCitizenPortal();
  }
  
  Future<void> _checkIfLinkedToCitizenPortal() async {
    if (widget.tenantId != null) {
      final isLinked = await CitizenPortalHelper.isLinkedCompany(widget.tenantId!);
      setState(() {
        isLinkedToCitizenPortal = isLinked;
        isCheckingLink = false;
      });
    } else {
      setState(() {
        isCheckingLink = false;
      });
    }
  }
  
  // ... باقي الكود
}
```

---

### 3️⃣ إضافة رابط بوابة المواطن في Drawer/Menu

**للشركات فقط (ليس لمدير النظام):**

```dart
// في Drawer أو قائمة الشاشات
if (!isSuperAdmin && isLinkedToCitizenPortal) {
  ListTile(
    leading: const Icon(Icons.people, color: Colors.teal),
    title: const Text('بوابة المواطن'),
    subtitle: const Text('إدارة نظام المواطن'),
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CitizenPortalDashboardPage(
            companyId: widget.tenantId!,
          ),
        ),
      );
    },
  ),
}
```

---

### 4️⃣ إضافة رابط إدارة الشركات لمدير النظام

**لمدير النظام فقط:**

```dart
// في Drawer أو قائمة الشاشات
if (isSuperAdmin) {
  ListTile(
    leading: const Icon(Icons.business, color: Colors.indigo),
    title: const Text('إدارة الشركات'),
    subtitle: const Text('ربط الشركات بنظام المواطن'),
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const CompaniesManagementPage(),
        ),
      );
    },
  ),
}
```

---

## 🎨 مثال كامل للـ Drawer:

```dart
Drawer(
  child: ListView(
    children: [
      UserAccountsDrawerHeader(
        accountName: Text(userName),
        accountEmail: Text(companyName),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.indigo, Colors.indigo.shade700],
          ),
        ),
      ),
      
      // === لمدير النظام فقط ===
      if (isSuperAdmin) ...[
        ListTile(
          leading: const Icon(Icons.business),
          title: const Text('إدارة الشركات'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CompaniesManagementPage()),
          ),
        ),
        const Divider(),
      ],
      
      // === للشركة المرتبطة فقط ===
      if (!isSuperAdmin && isLinkedToCitizenPortal) ...[
        ListTile(
          leading: const Icon(Icons.people, color: Colors.teal),
          title: const Text('بوابة المواطن'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'مرتبطة',
              style: TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CitizenPortalDashboardPage(
                companyId: widget.tenantId!,
              ),
            ),
          ),
        ),
        const Divider(),
      ],
      
      // === الشاشات العادية ===
      ListTile(
        leading: const Icon(Icons.dashboard),
        title: const Text('لوحة التحكم'),
        onTap: () => Navigator.pop(context),
      ),
      
      // ... باقي الشاشات
    ],
  ),
)
```

---

## 🔐 القواعد المهمة:

### ✅ يجب أن يظهر:
- **مدير النظام:** يرى رابط "إدارة الشركات" دائماً
- **الشركة المرتبطة:** ترى رابط "بوابة المواطن"

### ❌ لا يجب أن يظهر:
- **الشركات الأخرى:** لا ترى رابط "بوابة المواطن" **أبداً**
- **مدير النظام:** لا يرى "بوابة المواطن" (هو يدير من شاشة إدارة الشركات)

---

## 🚀 اختبار التنفيذ:

### السيناريو 1: مدير النظام
1. يسجل دخول كمدير نظام
2. يرى رابط "إدارة الشركات"
3. يفتح الصفحة → يرى جميع الشركات
4. يختار شركة ويربطها بنظام المواطن

### السيناريو 2: الشركة المرتبطة
1. يسجل دخول من الشركة المرتبطة
2. يرى رابط "بوابة المواطن" في القائمة ✅
3. يفتح الصفحة → يرى لوحة التحكم الكاملة
4. يمكنه إدارة المواطنين والطلبات

### السيناريو 3: شركة غير مرتبطة
1. يسجل دخول من شركة أخرى
2. **لا يرى رابط "بوابة المواطن"** ❌
3. إذا حاول الدخول يدوياً (عبر URL) → رسالة "غير مصرح"

---

## 🔄 تحديث الحالة:

عند تغيير الشركة المرتبطة (من صفحة إدارة الشركات):

```dart
// بعد ربط/إلغاء ربط شركة
CitizenPortalHelper.clearCache();

// إعادة التحقق في HomePage
await _checkIfLinkedToCitizenPortal();
```

---

## 📊 مخطط التدفق:

```
المستخدم يسجل دخول
         ↓
     مدير نظام؟
    ╱         ╲
  نعم          لا
   ↓           ↓
يرى "إدارة    التحقق: شركته مرتبطة؟
الشركات"      ╱              ╲
             نعم              لا
              ↓               ↓
        يرى "بوابة       لا يرى شيئاً
         المواطن"        (إخفاء تام)
```

---

## ✨ المزايا:

1. ✅ **أمان كامل:** الشركات الأخرى لا ترى الرابط أبداً
2. ✅ **تحقق مزدوج:** التحقق في القائمة + التحقق في الصفحة
3. ✅ **Cache ذكي:** تقليل استدعاءات API (Cache لمدة 5 دقائق)
4. ✅ **تحديث تلقائي:** مسح Cache عند تغيير الربط

---

تم التوثيق بنجاح! 🎉
