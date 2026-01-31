# 🚀 نظام التحديث التلقائي - دليل الإعداد

## 📋 المتطلبات

1. حساب GitHub
2. مستودع GitHub للمشروع
3. Flutter مثبت على جهازك

---

## 🔧 خطوات الإعداد

### الخطوة 1: إنشاء مستودع GitHub

```bash
# 1. أنشئ مستودع جديد على GitHub
# اذهب إلى: https://github.com/new

# 2. اربط المشروع بالمستودع
cd "d:\flutter\app\ramz1 top\filter_page"
git init
git remote add origin https://github.com/YOUR_USERNAME/alsadara.git
git add .
git commit -m "Initial commit"
git push -u origin main
```

### الخطوة 2: تحديث إعدادات التحديث التلقائي

افتح الملف `lib/services/auto_update_service.dart` وعدّل:

```dart
// ⚠️ غيّر هذه القيم لتتوافق مع مستودعك
static const String githubOwner = 'YOUR_GITHUB_USERNAME';  // ← اسم المستخدم
static const String githubRepo = 'alsadara';               // ← اسم المستودع
```

### الخطوة 3: إعداد GitHub Secrets (اختياري)

إذا كان لديك متغيرات بيئة سرية:

1. اذهب إلى إعدادات المستودع → Secrets and variables → Actions
2. أضف:
   - `FTTH_API_BASE_URL` - رابط API

---

## 📦 إنشاء إصدار جديد

### الطريقة 1: باستخدام السكربت (مُوصى)

```powershell
# افتح PowerShell في مجلد المشروع
.\create_release.ps1 -Version "1.2.9" -Message "تحسينات وإصلاحات"
```

### الطريقة 2: يدوياً

```bash
# 1. تحديث الإصدار في pubspec.yaml
# version: 1.2.9+15

# 2. حفظ التغييرات
git add .
git commit -m "إصدار v1.2.9"

# 3. إنشاء tag
git tag -a v1.2.9 -m "إصدار جديد"

# 4. رفع التغييرات
git push origin main
git push origin v1.2.9
```

---

## ⚙️ كيف يعمل النظام؟

```
┌─────────────────────────────────────────────────────────────────┐
│                        GitHub Repository                         │
├─────────────────────────────────────────────────────────────────┤
│  1. المطور يرفع tag جديد (v1.2.9)                                │
│           ↓                                                      │
│  2. GitHub Actions يبدأ تلقائياً                                 │
│           ↓                                                      │
│  3. يبني التطبيق للـ Windows                                     │
│           ↓                                                      │
│  4. يُنشئ Release مع ملف ZIP                                      │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                     تطبيق المستخدم                               │
├─────────────────────────────────────────────────────────────────┤
│  1. المستخدم يفتح التطبيق                                        │
│           ↓                                                      │
│  2. التطبيق يتحقق من GitHub API                                  │
│           ↓                                                      │
│  3. إذا وُجد إصدار جديد → يعرض نافذة التحديث                     │
│           ↓                                                      │
│  4. المستخدم يضغط "تحديث الآن"                                   │
│           ↓                                                      │
│  5. يُحمّل ويُثبّت التحديث تلقائياً                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📁 الملفات المُنشأة

| الملف | الوصف |
|-------|-------|
| `lib/services/auto_update_service.dart` | خدمة التحقق من التحديثات |
| `lib/widgets/update_dialog.dart` | نافذة عرض التحديث |
| `.github/workflows/build-windows.yml` | سير عمل GitHub Actions |
| `create_release.ps1` | سكربت إنشاء إصدار جديد |

---

## 🔍 اختبار النظام

### 1. اختبار محلي

```dart
// في أي مكان في التطبيق:
import 'package:alsadara/services/auto_update_service.dart';

// التحقق من التحديثات يدوياً
final update = await AutoUpdateService.instance.checkForUpdate();
if (update != null) {
  print('تحديث متاح: ${update.version}');
}
```

### 2. اختبار كامل

1. ارفع إصدار جديد (مثلاً v1.2.9)
2. انتظر GitHub Actions (5-10 دقائق)
3. افتح التطبيق بإصدار أقدم
4. يجب أن تظهر نافذة التحديث

---

## ❓ الأسئلة الشائعة

### لا تظهر نافذة التحديث؟

1. تأكد من تحديث `githubOwner` و `githubRepo`
2. تأكد من وجود Release على GitHub
3. تأكد من أن الـ Release يحتوي على ملف `.exe` أو `.zip`

### GitHub Actions فشل؟

1. تحقق من الـ logs في صفحة Actions
2. تأكد من صحة إصدار Flutter
3. تأكد من وجود ملف `.env` (أو أنشئه فارغاً)

### كيف أضيف ملاحظات الإصدار؟

عند إنشاء Release على GitHub، أضف الملاحظات في حقل "Release notes"

---

## 🎯 نصائح

- ✅ استخدم [Semantic Versioning](https://semver.org/) (مثال: 1.2.9)
- ✅ أضف ملاحظات واضحة لكل إصدار
- ✅ اختبر البناء محلياً قبل الرفع
- ✅ راقب GitHub Actions للتأكد من نجاح البناء

---

## 📞 الدعم

إذا واجهت مشاكل، افتح Issue على GitHub أو تواصل مع فريق التطوير.
