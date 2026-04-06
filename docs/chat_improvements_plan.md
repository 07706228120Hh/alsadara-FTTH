# خطة تحسينات نظام المحادثة الداخلي — Sadara Chat

> تاريخ الإنشاء: 2026-04-04
> الإصدار الأساسي: v1.7.0 (نظام المحادثة)

---

## المرحلة 1 — تحسينات أساسية (أولوية عالية)

### 1.1 إشعارات ذكية — فتح المحادثة مباشرة
- عند الضغط على إشعار رسالة → يفتح المحادثة المعنية مباشرة
- ربط `NotificationService._handleNotificationNavigation` مع `Navigator` عبر `GlobalKey`
- دعم نوعين: `chat_message` (يفتح الغرفة) و `chat_mention` (يفتح الغرفة + يمرر للرسالة)
- **الملفات**: `notification_service.dart`, `main.dart`, `chat_conversation_page.dart`

### 1.2 ضغط الصور قبل الرفع
- تصغير الصور تلقائياً قبل الإرسال (max 1024px عرض، جودة 75%)
- توفير بيانات الموظفين وتسريع التحميل
- استخدام `flutter_image_compress` أو ضغط يدوي عبر `image` package
- **الملفات**: `chat_conversation_page.dart` (دالة `_sendImage`)

### 1.3 تسجيل صوتي مباشر
- استبدال اختيار الملفات بتسجيل مباشر من الميكروفون
- استخدام `flutter_sound` بدلاً من `record` (أكثر استقراراً)
- واجهة: ضغط مطوّل على الميكروفون → شريط تسجيل أحمر → رفع الإصبع = إرسال
- **الملفات**: `pubspec.yaml`, `chat_conversation_page.dart`

### 1.4 كاش الرسائل المحلي
- تخزين آخر 100 رسالة لكل غرفة في SQLite محلي
- عرض الرسائل المخزنة فوراً ثم مزامنة مع السيرفر
- يسمح بقراءة المحادثات بدون إنترنت
- **الملفات**: جديد `chat_cache_service.dart`, `chat_service.dart`, `chat_conversation_page.dart`

---

## المرحلة 2 — تحسينات تجربة المستخدم (أولوية متوسطة)

### 2.1 ردود سريعة (Reactions)
- إضافة إيموجي على الرسائل بضغطة مزدوجة أو ضغط مطوّل
- إيموجيات: 👍 ❤️ 😂 😮 😢 🙏
- جدول جديد `ChatMessageReactions` في الـ Backend
- بث Reaction عبر SignalR فوراً
- **الملفات**: Backend entity + migration, ChatHub, ChatController, chat_conversation_page.dart

### 2.2 رسائل مثبّتة (Pin)
- تثبيت رسالة مهمة في أعلى المحادثة
- فقط مدير الغرفة يمكنه التثبيت
- حقل `IsPinned` في `ChatMessage` + عرض شريط أعلى المحادثة
- **الملفات**: Chat.cs, migration, ChatController, chat_conversation_page.dart

### 2.3 معاينة الروابط (Link Preview)
- عند إرسال رابط → جلب عنوان الصفحة + وصف + صورة
- استخدام `any_link_preview` أو جلب OpenGraph من Backend
- عرض بطاقة مصغرة تحت الرسالة
- **الملفات**: chat_conversation_page.dart, ChatController (endpoint جديد)

### 2.4 وضع الظلام (Dark Mode)
- دعم Dark Mode كامل في صفحات المحادثة
- ألوان الفقاعات: مرسلة (أزرق داكن)، مستقبلة (رمادي غامق)
- خلفية داكنة + نصوص فاتحة
- **الملفات**: chat_rooms_page.dart, chat_conversation_page.dart, employee_profile_card.dart

### 2.5 رسائل صوتية بشريط موجي (Waveform)
- عرض شكل الموجة الصوتية بدلاً من شريط مستقيم
- استخدام `audio_waveforms` package
- **الملفات**: pubspec.yaml, chat_conversation_page.dart

### 2.6 حالة المستخدم (Status/Story)
- نشر حالة (نص/صورة) تختفي بعد 24 ساعة
- عرض حالات الزملاء في أعلى صفحة المحادثات (حلقات دائرية)
- **الملفات**: جداول جديدة + صفحة جديدة + ChatController endpoints

### 2.7 قوالب رسائل جاهزة
- ردود سريعة محفوظة (مثل "شكراً"، "تم الاستلام"، "سأتواصل لاحقاً")
- المستخدم يضيف قوالبه الخاصة
- زر اختصار في شريط الإدخال
- **الملفات**: SharedPreferences محلي + chat_conversation_page.dart

---

## المرحلة 3 — تحسينات إدارية (أولوية متوسطة)

### 3.1 إحصائيات المحادثة (Dashboard)
- لوحة تحكم: عدد الرسائل/اليوم، أنشط المستخدمين، أوقات الذروة
- رسوم بيانية (fl_chart)
- فلتر بالتاريخ والقسم
- **الملفات**: صفحة جديدة `chat_analytics_page.dart` + ChatController endpoints

### 3.2 أرشفة المحادثات
- إخفاء محادثات قديمة بدون حذفها
- قسم "المؤرشفة" في أسفل قائمة المحادثات
- حقل `IsArchived` في `ChatRoomMember`
- **الملفات**: migration, ChatController, chat_rooms_page.dart

### 3.3 رسائل مجدولة
- إرسال رسالة في وقت محدد (مثلاً: إرسال تذكير الساعة 8 صباحاً)
- جدول `ScheduledMessage` + Background Service
- **الملفات**: Backend entity + Hangfire/Timer job + ChatController

### 3.4 تصدير المحادثة
- تصدير سجل محادثة كاملة كـ PDF أو Excel
- يشمل: الرسائل + المرسلين + التواريخ + المرفقات (روابط)
- صلاحية `chat.export` موجودة مسبقاً
- **الملفات**: ChatController endpoint جديد + chat_conversation_page.dart (زر تصدير)

---

## المرحلة 4 — تحسينات أمنية (أولوية عالية)

### 4.1 تشفير End-to-End (E2EE)
- تشفير الرسائل بمفاتيح عامة/خاصة (RSA + AES)
- السيرفر لا يستطيع قراءة المحتوى
- تبادل المفاتيح عند إنشاء المحادثة
- **تعقيد**: عالي — يتطلب إعادة هيكلة التخزين

### 4.2 رسائل ذاتية الحذف
- رسائل تختفي بعد وقت محدد (5 دقائق، ساعة، يوم)
- حقل `ExpiresAt` في `ChatMessage` + Background cleanup
- **الملفات**: Chat.cs, migration, ChatHub, ChatController, chat_conversation_page.dart

### 4.3 سجل تدقيق (Audit Log)
- تسجيل كل عملية: إرسال، حذف، تعديل، إضافة/إزالة أعضاء
- جدول `ChatAuditLog` مع userId + action + timestamp + metadata
- متاح فقط لمدير الشركة
- **الملفات**: Backend entity + migration + ChatController + صفحة جديدة

---

## ملاحظات
- كل مرحلة مستقلة ويمكن تنفيذها بدون الأخرى
- المرحلة 1 هي الأهم وتؤثر مباشرة على تجربة المستخدم
- المرحلة 4 (الأمان) مهمة للشركات الكبيرة لكن يمكن تأجيلها
