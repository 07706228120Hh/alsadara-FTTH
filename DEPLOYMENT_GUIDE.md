# دليل نشر وتوزيع تطبيق الصدارة
**الإصدار:** 1.4.2  
**تاريخ البناء:** 24 فبراير 2026

---

## 📦 ملفات التوزيع الجاهزة

### Windows Desktop
- **الملف:** `Alsadara-Windows-v1.4.2.zip`
- **الحجم:** 28 MB (مضغوط)
- **الموقع:** `C:\SadaraPlatform\Alsadara-Windows-v1.4.2.zip`

### Android (الهواتف)
- **الملف:** `Alsadara-Android-v1.4.2.apk`
- **الحجم:** 103 MB
- **الموقع:** `C:\SadaraPlatform\Alsadara-Android-v1.4.2.apk`

---

## 🖥️ التوزيع على حواسب Windows

### الطريقة 1: التثبيت اليدوي
1. انسخ ملف `Alsadara-Windows-v1.4.2.zip` إلى الحاسوب المستهدف
2. فك ضغط الملف في مجلد (مثلاً: `C:\Program Files\Alsadara`)
3. شغّل `Alsadara.exe` مباشرة (لا يحتاج تثبيت)

### الطريقة 2: تثبيت عبر الشبكة (Network Share)
```powershell
# على السيرفر
$sharePath = "\\ServerName\Alsadara"
New-Item -Path $sharePath -ItemType Directory -Force
Copy-Item "C:\SadaraPlatform\Alsadara-Windows-v1.4.2.zip" -Destination $sharePath

# على كل حاسوب
Expand-Archive -Path "\\ServerName\Alsadara\Alsadara-Windows-v1.4.2.zip" -DestinationPath "C:\Program Files\Alsadara" -Force
```

### الطريقة 3: إنشاء اختصار على سطح المكتب
```powershell
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\الصدارة.lnk")
$Shortcut.TargetPath = "C:\Program Files\Alsadara\Alsadara.exe"
$Shortcut.WorkingDirectory = "C:\Program Files\Alsadara"
$Shortcut.Save()
```

### متطلبات النظام
- Windows 10 (64-bit) أو أحدث
- 4 GB RAM
- اتصال بالإنترنت
- .NET Desktop Runtime (يُثبّت تلقائياً إذا لزم)

---

## 📱 التوزيع على الهواتف (Android)

### الطريقة 1: التثبيت المباشر (Direct Install)
1. انسخ `Alsadara-Android-v1.4.2.apk` إلى الهاتف عبر USB أو البريد أو WhatsApp
2. افتح الملف من مدير الملفات
3. السماح بالتثبيت من "مصادر غير معروفة" (إذا طُلب)
4. اضغط "تثبيت"

### الطريقة 2: التنزيل من رابط
1. ارفع `Alsadara-Android-v1.4.2.apk` على سيرفرك:
```bash
scp C:\SadaraPlatform\Alsadara-Android-v1.4.2.apk root@72.61.183.61:/var/www/downloads/
```

2. اجعله متاحاً عبر Nginx:
```nginx
# في /etc/nginx/sites-available/sadara-downloads
server {
    listen 80;
    server_name download.yourcompany.iq;
    
    root /var/www/downloads;
    
    location /alsadara.apk {
        alias /var/www/downloads/Alsadara-Android-v1.4.2.apk;
        add_header Content-Type application/vnd.android.package-archive;
        add_header Content-Disposition 'attachment; filename="Alsadara.apk"';
    }
}
```

3. شارك الرابط: `http://download.yourcompany.iq/alsadara.apk`

### الطريقة 3: توزيع داخلي عبر Google Drive أو Dropbox
1. ارفع APK على Drive/Dropbox
2. اصنع رابط مشاركة
3. شاركه مع الموظفين/العملاء

### متطلبات النظام
- Android 7.0 (API 24) أو أحدث
- 200 MB مساحة فارغة
- اتصال بالإنترنت
- أذونات: الموقع، التخزين، الكاميرا (للمسح الضوئي)

---

## 🔄 تحديث التطبيق

### على Windows
- استبدل المجلد القديم بالجديد
- أو فك ضغط النسخة الجديدة فوق القديمة

### على Android
- ثبّت APK الجديد فوق القديم (سيحل محله تلقائياً)
- البيانات المحفوظة تبقى كما هي

---

## ⚙️ إعدادات مهمة بعد التثبيت

### اتصال بالـ API
التطبيق يتصل بـ API على: `https://api.ftth.iq/api`

إذا تريد تغيير API base URL:
```dart
// في: lib/services/api_service.dart
static const String _vpsBaseUrl = 'https://api.ftth.iq/api';
```

### قاعدة البيانات المحلية
التطبيق يستخدم SQLite للتخزين المحلي - لا يحتاج إعداد.

---

## 🐛 حل المشاكل الشائعة

### Windows: "الملف غير موثوق"
- **السبب:** التطبيق غير موقّع رقمياً
- **الحل:** اضغط "مزيد من المعلومات" ← "تشغيل على أي حال"

### Android: "التطبيق ممنوع"
- **السبب:** مصدر غير معروف
- **الحل:** الإعدادات → الأمان → السماح بالتثبيت من مصادر غير معروفة

### خطأ في الاتصال بالـ API
- تأكد من الاتصال بالإنترنت
- تأكد من أن API يعمل: `curl https://api.ftth.iq/api/health`
- تحقق من الـ Firewall

### الأداء بطيء
- أغلق تطبيقات أخرى تعمل بالخلفية
- تأكد من سرعة الإنترنت
- امسح ذاكرة التخزين المؤقت (على Android)

---

## 📊 معلومات البناء التقنية

| المنصة | أداة البناء | الإصدار | Target |
|--------|-------------|---------|--------|
| Windows | Flutter 3.x | Release | x64 |
| Android | Flutter 3.x | Release | Multi-ABI (arm64-v8a, armeabi-v7a, x86_64) |

**تم حل المشاكل:**
✅ إصلاح خطأ "Expected to find ')'" في `fixed_expenses_page.dart`  
✅ ترتيب خصائص `child` في جميع الـ widgets للتوافق مع Lint  
✅ إزالة null-aware operators الزائدة  
✅ تنظيف شامل لـ build cache لتجاوز مشاكل Gradle/Kotlin daemon  

---

## 📞 الدعم الفني

للمشاكل أو الأسئلة:
- **مطوّر البرنامج:** فريق منصة الصدارة
- **السيرفر الرئيسي:** `72.61.183.61`
- **API Endpoint:** `https://api.ftth.iq/api`

---

**آخر تحديث:** 24 فبراير 2026  
**رقم البناء:** 18  
**حالة الفحص:** ✅ جميع الاختبارات ناجحة - جاهز للنشر
