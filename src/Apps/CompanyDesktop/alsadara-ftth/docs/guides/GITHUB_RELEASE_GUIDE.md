# 🚀 دليل إنشاء GitHub Release

## الطريقة 1: من واجهة GitHub (الأسهل)

### الخطوات:

1. **افتح صفحة الإصدارات:**
   - اذهب إلى: https://github.com/07706228120Hh/alsadara-FTTH/releases

2. **انقر "Create a new release"** أو "Draft a new release"

3. **اختر Tag:**
   - اختر `v1.3.0` من القائمة (تم إنشاؤه مسبقاً)

4. **أضف عنوان Release:**
   ```
   Alsadara v1.3.0 - Auto-Update & Company Permissions
   ```

5. **أضف وصف Release:**
   ```markdown
   ## ✨ ما الجديد في هذا الإصدار
   
   ### ميزات جديدة
   - 🔄 **نظام التحديث التلقائي**: التطبيق يفحص التحديثات تلقائياً
   - 🔐 **صلاحيات الشركة**: تطبيق صلاحيات من مستوى الشركة
   
   ### تحسينات
   - إزالة أزرار الصلاحيات المحلية
   - تحسين واجهة التحديث
   
   ### إصلاحات
   - ✅ إصلاح عدم تطبيق صلاحيات المدراء
   
   ## 📥 التحميل
   - `Alsadara_v1.3.0.zip` - النسخة المحمولة (Portable)
   
   ## 📋 متطلبات النظام
   - Windows 10 أو أحدث (64-bit)
   - اتصال بالإنترنت لـ Firebase
   ```

6. **ارفع ملف التوزيع:**
   - انقر "Attach binaries by dropping them here"
   - اختر: `Distribution_v1.3.0/Alsadara_v1.3.0.zip`

7. **انقر "Publish release"**

---

## الطريقة 2: تثبيت GitHub CLI

```powershell
# تثبيت GitHub CLI
winget install GitHub.cli

# تسجيل الدخول
gh auth login

# إنشاء Release
gh release create v1.3.0 "Distribution_v1.3.0/Alsadara_v1.3.0.zip" --title "Alsadara v1.3.0" --notes-file RELEASE_NOTES.md
```

---

## 📍 الروابط المهمة

- **صفحة Repository:** https://github.com/07706228120Hh/alsadara-FTTH
- **صفحة Releases:** https://github.com/07706228120Hh/alsadara-FTTH/releases
- **صفحة Tags:** https://github.com/07706228120Hh/alsadara-FTTH/tags

---

## 🔄 كيف يعمل التحديث التلقائي

1. عند تشغيل التطبيق، يفحص آخر Release من GitHub
2. يقارن الإصدار الحالي مع آخر إصدار
3. إذا وجد إصدار جديد، يعرض حوار للمستخدم
4. المستخدم يختار التحميل أو التأجيل
5. التحميل يتم مباشرة من GitHub

### رابط API للتحقق من التحديثات:
```
https://api.github.com/repos/07706228120Hh/alsadara-FTTH/releases/latest
```

---

## 📦 ملفات التوزيع الجاهزة

```
Distribution_v1.3.0/
├── Alsadara_v1.3.0.zip    ← ملف للرفع على GitHub
└── Portable/              ← مجلد التطبيق المستخرج
    ├── Alsadara.exe
    ├── flutter_windows.dll
    └── ... (باقي الملفات)
```

## ✅ الإصدار v1.3.0 جاهز للتوزيع!

الملف: `d:\flutter\app\ramz1 top\filter_page\Distribution_v1.3.0\Alsadara_v1.3.0.zip`
الحجم: ~25 MB
