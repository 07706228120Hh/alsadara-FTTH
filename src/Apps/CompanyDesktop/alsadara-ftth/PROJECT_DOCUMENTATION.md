# 📚 توثيق مشروع الصدارة (Alsadara)
## نظام إدارة شبكات FTTH المتكامل

---

## 📋 نظرة عامة

**اسم المشروع:** الصدارة (Alsadara)  
**الإصدار:** 1.2.8+14  
**المنصة الرئيسية:** Windows Desktop  
**إطار العمل:** Flutter 3.6.0+  
**اللغة:** Dart  

### وصف المشروع
تطبيق متكامل لإدارة شبكات الألياف البصرية (FTTH - Fiber To The Home) يتضمن:
- إدارة المشتركين والاشتراكات
- نظام التذاكر والدعم الفني
- المعاملات المالية والمحافظ
- تكامل WhatsApp Business API
- نظام إشعارات Firebase
- تقارير وتحليلات متقدمة

---

## 🏗️ هيكل المشروع

```
lib/
├── main.dart                    # نقطة البداية الرئيسية
├── firebase_options.dart        # إعدادات Firebase
├── ftth/                        # نظام FTTH الرئيسي
│   ├── auth/                    # المصادقة
│   ├── core/                    # الصفحات الأساسية
│   ├── subscriptions/           # إدارة الاشتراكات
│   ├── users/                   # إدارة المستخدمين
│   ├── tickets/                 # إدارة التذاكر
│   ├── transactions/            # المعاملات المالية
│   ├── reports/                 # التقارير
│   ├── whatsapp/                # تكامل WhatsApp
│   └── widgets/                 # مكونات مشتركة
├── pages/                       # صفحات النظام الأول
├── services/                    # الخدمات
├── models/                      # النماذج
├── widgets/                     # الويدجات العامة
├── utils/                       # الأدوات المساعدة
├── theme/                       # التصميم والثيمات
└── task/                        # نظام المهام
```

---

## 🔄 تدفق التطبيق (Application Flow)

### 1. نقطة البداية (main.dart)
```
main() 
  ↓
تهيئة Flutter
  ↓
إعداد مدير النوافذ (Windows)
  ↓
تهيئة Firebase
  ↓
تهيئة خدمة الإشعارات
  ↓
تشغيل التطبيق → MyApp
  ↓
صفحة تسجيل الدخول (LoginPage)
```

### 2. مسار تسجيل الدخول
```
LoginPage (pages/login_page.dart)
  ↓
التحقق من بيانات المستخدم
  ↓
[نجاح] → HomePage (pages/home_page.dart)
  ↓
[اختيار FTTH] → FTTH LoginPage (ftth/auth/login_page.dart)
  ↓
[نجاح] → FTTH HomePage (ftth/core/home_page.dart)
```

---

## 📱 الصفحات الرئيسية

### النظام الأول (pages/)

| الملف | الوصف | الارتباطات |
|-------|-------|------------|
| `login_page.dart` | صفحة تسجيل الدخول الرئيسية | → home_page.dart |
| `home_page.dart` | الصفحة الرئيسية والداشبورد | → جميع الصفحات |
| `attendance_page.dart` | نظام البصمة والحضور | مستقل |
| `users_page.dart` | إدارة المستخدمين | → user_details |
| `search_users_page.dart` | البحث عن المستخدمين | → user_details |
| `statistics_page.dart` | الإحصائيات والرسوم البيانية | مستقل |
| `aria_page.dart` | صفحة المساعد الذكي | مستقل |
| `local_storage_page.dart` | التخزين المحلي | مستقل |
| `whatsapp_conversations_page.dart` | محادثات WhatsApp | → whatsapp_chat |
| `whatsapp_bulk_sender_page.dart` | إرسال رسائل جماعية | مستقل |

### نظام FTTH (ftth/)

#### 🔐 المصادقة (auth/)
| الملف | الوصف |
|-------|-------|
| `login_page.dart` | تسجيل الدخول لنظام FTTH |
| `auth_error_handler.dart` | معالجة أخطاء المصادقة |

#### 🏠 الأساسية (core/)
| الملف | الوصف |
|-------|-------|
| `home_page.dart` | الصفحة الرئيسية FTTH (4729 سطر) |
| `permissions_page.dart` | إدارة الصلاحيات |

#### 📋 الاشتراكات (subscriptions/)
| الملف | الوصف |
|-------|-------|
| `subscriptions_page.dart` | قائمة الاشتراكات |
| `subscription_details_page.dart` | تفاصيل الاشتراك (11545 سطر) |
| `subscription_details_page.renewal.dart` | عمليات التجديد |
| `expiring_soon_page.dart` | الاشتراكات المنتهية قريباً |
| `connections_list_page.dart` | قائمة الوصولات |

#### 👥 المستخدمين (users/)
| الملف | الوصف |
|-------|-------|
| `users_page.dart` | قائمة المستخدمين |
| `user_details_page.dart` | تفاصيل المستخدم |
| `quick_search_users_page.dart` | البحث السريع |
| `user_records_page.dart` | سجلات المستخدم |
| `user_transactions_page.dart` | معاملات المستخدم |

#### 🎫 التذاكر (tickets/)
| الملف | الوصف |
|-------|-------|
| `tktats_page.dart` | قائمة التذاكر الرئيسية |
| `tktat_details_page.dart` | تفاصيل التذكرة |
| `customer_tickets_page.dart` | تذاكر العميل |
| `technicians_page.dart` | إدارة الفنيين |

#### 💰 المعاملات (transactions/)
| الملف | الوصف |
|-------|-------|
| `transactions_page.dart` | المعاملات المالية |
| `account_records_page.dart` | سجلات الحسابات |
| `account_stats_page.dart` | إحصائيات الحسابات |
| `caounter_details_page.dart` | تفاصيل العدادات |

#### 📊 التقارير (reports/)
| الملف | الوصف |
|-------|-------|
| `export_page.dart` | تصدير البيانات |
| `profits_page.dart` | تقرير الأرباح |
| `zones_page.dart` | إدارة المناطق |
| `data_page.dart` | صفحة البيانات الموحدة |
| `audit_log_page.dart` | سجل المراجعة |

---

## ⚙️ الخدمات (Services)

### خدمات المصادقة (auth/)
| الملف | الوصف |
|-------|-------|
| `session_manager.dart` | إدارة الجلسات |
| `session_provider.dart` | مزود الجلسات |
| `auth_context.dart` | سياق المصادقة |
| `auth_interceptor.dart` | اعتراض طلبات المصادقة |

### خدمات FTTH (ftth/)
| الملف | الوصف |
|-------|-------|
| `ftth_cache_service.dart` | خدمة التخزين المؤقت |
| `ftth_event_bus.dart` | ناقل الأحداث |

### الخدمات الرئيسية
| الملف | الوصف |
|-------|-------|
| `auth_service.dart` | خدمة المصادقة الرئيسية |
| `api_service.dart` | خدمة API |
| `notification_service.dart` | خدمة الإشعارات |
| `google_sheets_service.dart` | تكامل Google Sheets |
| `whatsapp_business_service.dart` | WhatsApp Business API |
| `sync_service.dart` | خدمة المزامنة |
| `badge_service.dart` | خدمة الشارات |
| `thermal_printer_service.dart` | خدمة الطباعة الحرارية |

---

## 🔗 الربط بين الصفحات

### خريطة التنقل الرئيسية

```
                    ┌─────────────────┐
                    │   LoginPage     │
                    │ (pages/login)   │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │    HomePage     │
                    │ (pages/home)    │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
┌───────▼───────┐   ┌────────▼────────┐   ┌───────▼───────┐
│  Attendance   │   │   FTTH System   │   │    Tasks      │
│    Page       │   │   (Login)       │   │    Page       │
└───────────────┘   └────────┬────────┘   └───────────────┘
                             │
                    ┌────────▼────────┐
                    │  FTTH HomePage  │
                    │ (ftth/core)     │
                    └────────┬────────┘
                             │
    ┌──────────┬─────────────┼─────────────┬──────────┐
    │          │             │             │          │
┌───▼───┐  ┌───▼───┐    ┌────▼────┐   ┌────▼────┐ ┌───▼───┐
│ Users │  │Tickets│    │Subscrip │   │Transact │ │Reports│
│ Page  │  │ Page  │    │  tions  │   │  ions   │ │ Page  │
└───┬───┘  └───┬───┘    └────┬────┘   └────┬────┘ └───┬───┘
    │          │             │             │          │
┌───▼───┐  ┌───▼───┐    ┌────▼────┐   ┌────▼────┐ ┌───▼───┐
│User   │  │Ticket │    │Subscrip │   │Account  │ │Export │
│Details│  │Details│    │ Details │   │Records  │ │ Page  │
└───────┘  └───────┘    └─────────┘   └─────────┘ └───────┘
```

### كود الانتقال بين الصفحات

#### من تسجيل الدخول إلى الرئيسية:
```dart
Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (context) => HomePage(
      username: result.userSession!.username,
      permissions: 'USER',
      department: 'عام',
      salary: '',
      center: 'المركز الرئيسي',
      pageAccess: {'home': true, ...},
    ),
  ),
);
```

#### من الرئيسية إلى FTTH:
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => ftth_login.LoginPage(
      firstSystemUsername: widget.username,
      firstSystemPermissions: widget.permissions,
      firstSystemDepartment: widget.department,
      firstSystemCenter: widget.center,
      firstSystemSalary: widget.salary,
      firstSystemPageAccess: widget.pageAccess,
    ),
  ),
);
```

#### من FTTH Login إلى FTTH Home:
```dart
Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (context) => HomePage(
      username: _username,
      authToken: _authToken,
      permissions: _permissions,
      firstSystemUsername: widget.firstSystemUsername,
      ...
    ),
  ),
);
```

---

## 🗃️ النماذج (Models)

| الملف | الوصف | الحقول الرئيسية |
|-------|-------|-----------------|
| `task.dart` | نموذج المهمة | id, title, description, status, priority |
| `filter_criteria.dart` | معايير التصفية | dateRange, status, user, zone |
| `whatsapp_conversation.dart` | محادثة واتساب | phone, messages, lastMessage |
| `maintenance_messages.dart` | رسائل الصيانة | id, message, type, date |

---

## 🎨 الثيمات والتصميم

### الألوان الرئيسية
```dart
// لون الألياف البصرية
final Color _fiberColor = const Color(0xFF00E5FF);

// لون الخلفية الداكنة
final Color _darkBackground = const Color(0xFF1A237E);

// ألوان الحالات
Colors.green   // نجاح/فعال
Colors.red     // خطأ/معطل
Colors.orange  // تحذير/انتظار
Colors.blue    // معلومات
```

### استخدام flutter_screenutil
```dart
// الحجم المتجاوب
width: 100.w   // عرض نسبي
height: 50.h   // ارتفاع نسبي
fontSize: 14.sp // حجم خط متجاوب
radius: 8.r    // نصف قطر متجاوب
```

---

## 🔐 نظام الصلاحيات

### صلاحيات النظام الأول
```dart
final Map<String, bool> _defaultPermissions = {
  'attendance': false,
  'agent': false,
  'tasks': false,
  'zones': false,
  'ai_search': false,
};
```

### صلاحيات نظام FTTH
```dart
final Map<String, bool> _defaultPermissions = {
  'users': false,
  'subscriptions': false,
  'tasks': false,
  'zones': false,
  'accounts': false,
  'export': false,
  'google_sheets': false,
  'whatsapp': false,
  'wallet_balance': false,
  'transactions': false,
  'notifications': false,
  'audit_logs': false,
  // ... المزيد
};
```

---

## 📡 التكاملات الخارجية

### 1. Firebase
- **Firebase Core:** التهيئة الأساسية
- **Firebase Messaging:** الإشعارات
- **Cloud Firestore:** قاعدة البيانات

### 2. Google Services
- **Google Sheets API:** جداول البيانات
- **Google Sign-In:** تسجيل الدخول
- **Google Maps:** الخرائط

### 3. WhatsApp Business API
- إرسال رسائل نصية
- إرسال رسائل جماعية
- إدارة المحادثات
- القوالب المعتمدة

---

## 🔧 الإعدادات والتكوين

### متغيرات البيئة (.env)
```env
GOOGLE_SHEETS_API_KEY=xxx
GOOGLE_SHEETS_SPREADSHEET_ID=xxx
FTTH_API_BASE_URL=xxx
WHATSAPP_API_TOKEN=xxx
```

### إعدادات التحليل (analysis_options.yaml)
```yaml
analyzer:
  errors:
    unused_element: ignore
    unused_field: ignore
    deprecated_member_use: ignore
```

---

## 📦 التبعيات الرئيسية

| الحزمة | الإصدار | الاستخدام |
|--------|---------|----------|
| flutter_screenutil | ^5.9.3 | التصميم المتجاوب |
| firebase_core | ^3.8.1 | Firebase |
| firebase_messaging | ^15.1.5 | الإشعارات |
| http | ^1.2.2 | طلبات HTTP |
| dio | ^5.7.0 | طلبات HTTP متقدمة |
| shared_preferences | ^2.3.3 | التخزين المحلي |
| gsheets | ^0.5.0 | Google Sheets |
| webview_windows | ^0.4.0 | عرض الويب |
| window_manager | ^0.5.1 | إدارة النوافذ |
| excel | ^4.0.6 | تصدير Excel |
| lottie | ^3.2.0 | الرسوم المتحركة |

---

## 🚀 البناء والتشغيل

### تشغيل في وضع التطوير
```bash
flutter run -d windows
```

### بناء للإنتاج
```bash
flutter build windows --release
```

### تحليل الكود
```bash
flutter analyze
```

---

## 📝 ملاحظات المطور

1. **الملفات الكبيرة:** 
   - `subscription_details_page.dart` (11,545 سطر)
   - `home_page.dart` FTTH (4,729 سطر)
   - يُنصح بتقسيمها مستقبلاً

2. **نظام الجلسات:**
   - JWT مع Refresh Tokens
   - إدارة تلقائية للتجديد

3. **التخزين المؤقت:**
   - `FtthCacheService` للبيانات
   - `SharedPreferences` للإعدادات

4. **الأداء:**
   - تحميل كسول للصفحات
   - تخزين مؤقت للبيانات

---

## 📅 سجل التحديثات

| الإصدار | التاريخ | التغييرات |
|---------|---------|----------|
| 1.2.8 | 2024 | إعادة هيكلة مجلد ftth |
| 1.2.7 | 2024 | تحسينات الأداء |
| 1.2.6 | 2024 | إضافة WhatsApp API |
| 1.2.5 | 2024 | نظام الإشعارات |

---

## 👨‍💻 فريق التطوير

**تطبيق الصدارة** - جميع الحقوق محفوظة © 2024

---

*آخر تحديث: ديسمبر 2025*
