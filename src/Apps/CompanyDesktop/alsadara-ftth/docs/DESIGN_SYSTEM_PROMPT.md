# 🎨 نظام تصميم Al-Sadara Platform - Design System Prompt

## استخدم هذا الملف كـ Prompt عند تحسين أي شاشة في التطبيق

---

## 📋 نظرة عامة على التصميم

هذا التصميم مستوحى من واجهات المستخدم الحديثة للوحات التحكم (Admin Dashboards) مع طابع احترافي وداكن.

**الاسم**: Al-Sadara Platform Theme
**النمط**: Dark Navy Professional
**اللغة**: عربي (RTL) + إنجليزي للعناوين

---

## 🎨 لوحة الألوان (Color Palette)

### الألوان الأساسية - محسّنة لراحة العين
```dart
// الخلفية الرئيسية - Navy أفتح لراحة العين
static const Color bgDark = Color(0xFF1A2332);        // الخلفية الأساسية
static const Color bgDarkLight = Color(0xFF243447);   // خلفية أفتح قليلاً
static const Color bgCard = Color(0xFF1E2D3D);        // خلفية البطاقات
static const Color bgSurface = Color(0xFF2A4158);     // الأسطح والعناصر المحددة

// اللون الأساسي - Blue
static const Color primary = Color(0xFF3B82F6);       // أزرق رئيسي
static const Color primaryLight = Color(0xFF60A5FA);  // أزرق فاتح
static const Color primaryDark = Color(0xFF2563EB);   // أزرق داكن

// اللون الثانوي - Gold/Amber (للأزرار الرئيسية)
static const Color accent = Color(0xFFD4A574);        // ذهبي
static const Color accentLight = Color(0xFFE8C49A);   // ذهبي فاتح
static const Color accentDark = Color(0xFFB8864E);    // ذهبي داكن
```

### ألوان الحالة
```dart
static const Color success = Color(0xFF22C55E);   // أخضر - نجاح
static const Color warning = Color(0xFFF59E0B);   // برتقالي - تحذير
static const Color danger = Color(0xFFEF4444);    // أحمر - خطأ
static const Color info = Color(0xFF3B82F6);      // أزرق - معلومات
```

### ألوان النصوص - محسّنة للوضوح
```dart
static const Color textWhite = Color(0xFFFFFFFF);     // أبيض - العناوين الرئيسية
static const Color textLight = Color(0xFFCBD5E1);     // رمادي فاتح - النصوص العادية
static const Color textMuted = Color(0xFF94A3B8);     // رمادي - النصوص الثانوية
static const Color textDark = Color(0xFF64748B);      // رمادي داكن - التلميحات
```

### ألوان الحدود
```dart
static const Color border = Color(0xFF3B5068);        // حدود عادية
static const Color borderLight = Color(0xFF4B6080);   // حدود فاتحة
static const Color borderFocus = Color(0xFF3B82F6);   // حدود عند التركيز
```

---

## 🌈 التدرجات (Gradients)

### التدرج الذهبي (للأزرار الرئيسية)
```dart
static const LinearGradient goldGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [
    Color(0xFFD4A574),  // ذهبي
    Color(0xFFF59E0B),  // برتقالي
    Color(0xFFD97706),  // برتقالي داكن
  ],
);
```

### تدرج الخلفية
```dart
static const LinearGradient backgroundGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF0D1B2A), Color(0xFF152238)],
);
```

---

## 📐 المقاسات والمسافات

### الحشو (Padding)
- **صغير**: 8px
- **متوسط**: 12px
- **عادي**: 16px
- **كبير**: 24px
- **كبير جداً**: 32px

### الزوايا (Border Radius)
- **صغير**: 8px (الأزرار الصغيرة، الحقول)
- **متوسط**: 12px (البطاقات الصغيرة)
- **كبير**: 16px (البطاقات الكبيرة)
- **دائري**: 24px (البطاقات الرئيسية)
- **كامل**: 30px (التبويبات)

### أحجام الخطوط
- **عنوان كبير**: 28px - Bold
- **عنوان**: 20px - SemiBold
- **عنوان فرعي**: 16px - Medium
- **نص عادي**: 14px - Regular
- **نص صغير**: 12px - Regular
- **تسمية**: 10px - Medium

---

## 🧩 مكونات التصميم

### 1. صفحة تسجيل الدخول

```
┌─────────────────────────────────────────────┐
│           [خلفية: #0D1B2A]                  │
│                                             │
│              ◇ شعار الماسة                  │
│            (80x80, حدود #1E3A5F)            │
│                                             │
│     ┌─────────────────────────────┐         │
│     │   خلفية البطاقة: #152238    │         │
│     │   حدود: #1E3A5F             │         │
│     │                             │         │
│     │      Welcome Back           │         │
│     │   (أبيض، 28px، Bold)        │         │
│     │                             │         │
│     │  [Tenant/Agent] [Super Admin]│        │
│     │   (تبويبات، خلفية #0D1B2A)  │         │
│     │                             │         │
│     │  ┌─────────────────────┐    │         │
│     │  │ Email or Username   │    │         │
│     │  │ خلفية: #0D1B2A      │    │         │
│     │  │ حدود: #1E3A5F       │    │         │
│     │  └─────────────────────┘    │         │
│     │                             │         │
│     │  ┌─────────────────────┐    │         │
│     │  │ Password            │    │         │
│     │  └─────────────────────┘    │         │
│     │                             │         │
│     │  ╔═══════════════════════╗  │         │
│     │  ║      Log In          ║  │         │
│     │  ║  (تدرج ذهبي + ظل)    ║  │         │
│     │  ╚═══════════════════════╝  │         │
│     │                             │         │
│     │     🔐 Use Biometric        │         │
│     │     Forgot Password?        │         │
│     └─────────────────────────────┘         │
│                                             │
└─────────────────────────────────────────────┘
```

### 2. القائمة الجانبية (Sidebar)

```
┌──────────────────┐
│  عرض: 200px      │
│  خلفية: #0D1B2A  │
│  حدود يمين:      │
│   #1E3A5F        │
├──────────────────┤
│                  │
│ 🏠 Command Center│  ← العنصر المحدد:
│    (محدد)        │     خلفية #1E3A5F
│                  │     نص أبيض
│ 👥 User Mgmt     │  ← العنصر العادي:
│                  │     نص #94A3B8
│ 🔗 Network Map   │
│                  │
│ ☁️ Firebase Data │
│                  │
│ 🖥️ VPS Data     │
│                  │
│ 💾 Database      │
│                  │
├──────────────────┤
│ ⚙️ Settings      │
│                  │
│ 🚪 Logout        │  ← لون أحمر #EF4444
│                  │
│ [◀ طي القائمة]   │
└──────────────────┘
```

### 3. الشريط العلوي (Top Bar)

```
┌────────────────────────────────────────────────────────┐
│  ◇ Al-Sadara Platform              [صورة المستخدم] 🟢 │
│  (#64748B)                          (40x40, حدود خضراء)│
│  خلفية: #0D1B2A                                        │
│  حدود سفلية: #1E3A5F                                   │
└────────────────────────────────────────────────────────┘
```

### 4. الشريط السفلي (Footer)

```
┌────────────────────────────────────────────────────────┐
│        © 2026 Al-Sadara Platform. All rights reserved. │
│        خلفية: #152238 | نص: #64748B | 12px             │
└────────────────────────────────────────────────────────┘
```

### 5. البطاقات (Cards)

```dart
// بطاقة عادية
Container(
  decoration: BoxDecoration(
    color: Color(0xFF152238),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Color(0xFF1E3A5F)),
  ),
)

// بطاقة مع ظل
Container(
  decoration: BoxDecoration(
    color: Color(0xFF152238),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Color(0xFF1E3A5F)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.2),
        blurRadius: 10,
        offset: Offset(0, 4),
      ),
    ],
  ),
)
```

### 6. حقول الإدخال (Text Fields)

```dart
TextFormField(
  style: TextStyle(color: Colors.white, fontSize: 15),
  decoration: InputDecoration(
    hintText: 'التلميح',
    hintStyle: TextStyle(color: Color(0xFF475569)),
    filled: true,
    fillColor: Color(0xFF0D1B2A),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Color(0xFF1E3A5F)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Color(0xFF1E3A5F)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Color(0xFF3B82F6), width: 2),
    ),
    prefixIcon: Icon(Icons.email, color: Color(0xFF64748B)),
  ),
)
```

### 7. الأزرار

#### زر رئيسي (بتدرج ذهبي)
```dart
Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFFD4A574), Color(0xFFF59E0B), Color(0xFFD97706)],
    ),
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: Color(0xFFF59E0B).withOpacity(0.3),
        blurRadius: 12,
        offset: Offset(0, 4),
      ),
    ],
  ),
  child: ElevatedButton(
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
    ),
    child: Text('Log In', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
  ),
)
```

#### زر ثانوي
```dart
ElevatedButton(
  style: ElevatedButton.styleFrom(
    backgroundColor: Color(0xFF1E3A5F),
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
)
```

### 8. التبويبات (Tabs)

```dart
// الحاوية
Container(
  padding: EdgeInsets.all(4),
  decoration: BoxDecoration(
    color: Color(0xFF0D1B2A),
    borderRadius: BorderRadius.circular(30),
  ),
)

// التبويب المحدد
Container(
  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
  decoration: BoxDecoration(
    color: Color(0xFF1E3A5F),
    borderRadius: BorderRadius.circular(25),
  ),
  child: Text('Tab', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
)

// التبويب العادي
Container(
  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
  decoration: BoxDecoration(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(25),
  ),
  child: Text('Tab', style: TextStyle(color: Color(0xFF64748B))),
)
```

### 9. الشارات (Badges)

```dart
// شارة الحالة - نشط
Container(
  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(
    color: Color(0xFF22C55E).withOpacity(0.2),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Text('Active', style: TextStyle(color: Color(0xFF22C55E), fontSize: 12)),
)

// شارة المستوى
Container(
  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(
    color: Color(0xFFF59E0B).withOpacity(0.2),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Color(0xFFF59E0B).withOpacity(0.3)),
  ),
  child: Text('Gold Tier', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
)
```

---

## 🖼️ الأيقونات

استخدم أيقونات Material Icons مع الأنماط التالية:

```dart
// أيقونة في الشريط الجانبي
Icon(Icons.home_rounded, size: 20, color: Color(0xFF64748B))

// أيقونة محددة
Icon(Icons.home_rounded, size: 20, color: Colors.white)

// أيقونة في حقل إدخال
Icon(Icons.email_outlined, size: 20, color: Color(0xFF64748B))

// أيقونة الشعار
Icon(Icons.diamond_outlined, size: 40, color: Color(0xFF3B82F6))
```

---

## 📱 التصميم المتجاوب

### نقاط الانكسار
- **موبايل**: < 600px
- **تابلت**: 600px - 1024px
- **سطح المكتب**: > 1024px

### القائمة الجانبية
- **سطح المكتب**: 200px عرض ثابت
- **تابلت**: قابلة للطي (80px مطوية)
- **موبايل**: Drawer منزلق

---

## 🔤 الخطوط

```dart
// للنصوص الإنجليزية
GoogleFonts.poppins()

// للنصوص العربية
GoogleFonts.cairo()

// أو استخدم
fontFamily: 'Poppins'  // للإنجليزية
fontFamily: 'Cairo'    // للعربية
```

---

## 💡 قواعد التصميم العامة

1. **التباين**: استخدم دائماً تباين قوي بين النص والخلفية
2. **المسافات**: اترك مسافات كافية بين العناصر (minimum 8px)
3. **الاتساق**: استخدم نفس الألوان والمقاسات في جميع الشاشات
4. **الحدود**: استخدم حدود خفيفة (#1E3A5F) لفصل العناصر
5. **الظلال**: استخدم الظلال باعتدال للعناصر المهمة فقط
6. **الرسوم المتحركة**: استخدم انتقالات سلسة (200-300ms)

---

## 📝 مثال Prompt لتحسين شاشة

```
أريد تحسين شاشة [اسم الشاشة] لتتوافق مع نظام تصميم Al-Sadara Platform:

1. الخلفية: Navy داكن (#0D1B2A)
2. البطاقات: خلفية #152238 مع حدود #1E3A5F
3. الأزرار الرئيسية: تدرج ذهبي
4. النصوص: أبيض للعناوين، رمادي (#94A3B8) للنص العادي
5. الأيقونات: Material Icons مع لون #64748B
6. الحقول: خلفية #0D1B2A مع حدود #1E3A5F

المطلوب:
- [وصف التحسين المطلوب]
```

---

## 📱 قواعد التصميم المتجاوب (Responsive)

### حساب الأبعاد ديناميكياً
```dart
// الحصول على حجم الشاشة
final screenSize = MediaQuery.of(context).size;
final screenWidth = screenSize.width;
final screenHeight = screenSize.height;
final isSmallScreen = screenWidth < 600;

// تحديد المسافات بناءً على الشاشة
final padding = isSmallScreen ? 16.0 : 24.0;
final cardPadding = isSmallScreen ? 20.0 : 32.0;
final logoSize = isSmallScreen ? 60.0 : 80.0;
final fontSize = isSmallScreen ? 12.0 : 14.0;

// تحديد عرض القائمة الجانبية
final sidebarWidth = isSidebarCollapsed ? 70.0 : (screenWidth < 800 ? 180.0 : 200.0);
```

### نقاط الانكسار
- **شاشة صغيرة**: `width < 600px`
- **شاشة متوسطة**: `600px - 800px`
- **شاشة كبيرة**: `> 800px`

### ConstrainedBox لمنع التمدد الزائد
```dart
ConstrainedBox(
  constraints: BoxConstraints(
    maxWidth: screenWidth > 500 ? 420.0 : screenWidth - 32,
    maxHeight: screenHeight - 48,
  ),
  child: YourWidget(),
)
```

---

## 🈸 نصوص الواجهة بالعربي

### صفحة تسجيل الدخول
| العنصر | النص العربي |
|--------|------------|
| العنوان | مرحباً بك |
| تبويب الشركة | شركة / وكيل |
| تبويب المدير | مدير النظام |
| حقل المستخدم | البريد الإلكتروني أو اسم المستخدم |
| حقل كلمة المرور | كلمة المرور |
| زر الدخول | تسجيل الدخول |
| البصمة | تسجيل الدخول بالبصمة |
| نسيت كلمة المرور | نسيت كلمة المرور؟ |

### القائمة الجانبية
| العنصر | النص العربي |
|--------|------------|
| الرئيسية | لوحة التحكم |
| المستخدمين | إدارة المستخدمين |
| الشبكة | خريطة الشبكة |
| Firebase | بيانات Firebase |
| VPS | بيانات VPS |
| قاعدة البيانات | قاعدة البيانات |
| الإعدادات | الإعدادات |
| الخروج | تسجيل الخروج |

### الشريط العلوي والسفلي
| العنصر | النص العربي |
|--------|------------|
| اسم المنصة | منصة الصدارة |
| حقوق النشر | © 2026 منصة الصدارة. جميع الحقوق محفوظة. |

---

**تم إنشاء هذا الملف**: يناير 2026
**الإصدار**: 1.1 - مع دعم التصميم المتجاوب والنصوص العربية
