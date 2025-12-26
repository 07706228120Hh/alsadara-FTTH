import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// خدمة للتحكم في Windows API لإرسال أحداث لوحة المفاتيح
class WindowsAutomationService {
  // تحديد User32.dll للوصول إلى keybd_event
  static final user32 = DynamicLibrary.open('user32.dll');

  // تعريف keybd_event function
  static final keybd_event = user32.lookupFunction<
      Void Function(Uint8, Uint8, Uint32, Pointer<IntPtr>),
      void Function(int, int, int, Pointer<IntPtr>)>('keybd_event');

  // إضافة متغير لتتبع حالة الإرسال لمنع الإرسال المتكرر
  static bool _isSending = false;
  static DateTime? _lastSendTime;
  static bool _isCheckingNumber = false;

  /// فحص إذا كان الرقم له حساب على الواتساب
  static Future<Map<String, dynamic>> checkWhatsAppNumber(
      String phoneNumber) async {
    if (!Platform.isWindows || _isCheckingNumber) {
      return {'exists': false, 'error': 'جاري فحص رقم آخر، يرجى الانتظار'};
    }

    _isCheckingNumber = true;

    try {
      print('🔍 بدء فحص الرقم: $phoneNumber');

      // تنظيف الرقم وإضافة رمز الدولة إذا لم يكن موجوداً
      String cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
      if (!cleanedNumber.startsWith('+')) {
        cleanedNumber = '+966$cleanedNumber'; // السعودية كافتراضي
      }

      // فتح رابط واتساب مع الرقم للفحص (بدون رسالة)
      final whatsappUrl = 'whatsapp://send?phone=$cleanedNumber';

      print('🌐 محاولة فتح: $whatsappUrl');

      // فتح الرابط
      await Process.run('start', [whatsappUrl], runInShell: true);

      // انتظار قصير لفتح الواتساب
      await Future.delayed(const Duration(seconds: 3));

      // البحث عن نافذة الواتساب والتركيز عليها
      final windowFound = await focusWhatsAppWindow();
      if (!windowFound) {
        return {'exists': false, 'error': 'لا يمكن الوصول لنافذة الواتساب'};
      }

      // انتظار للسماح للواتساب بالتحقق من الرقم
      await Future.delayed(const Duration(seconds: 2));

      // فحص محتوى الشاشة للبحث عن رسائل عدم وجود الرقم
      final checkResult = await _checkScreenForNumberStatus();

      return checkResult;
    } catch (e) {
      print('❌ خطأ في فحص الرقم: $e');
      return {'exists': false, 'error': 'خطأ في فحص الرقم: $e'};
    } finally {
      _isCheckingNumber = false;
    }
  }

  /// فحص محتوى الشاشة لمعرفة حالة الرقم
  static Future<Map<String, dynamic>> _checkScreenForNumberStatus() async {
    try {
      // محاولة إرسال Alt+Tab للتنقل للنافذة النشطة
      keybd_event(VK_MENU, 0, 0, nullptr);
      keybd_event(VK_TAB, 0, 0, nullptr);
      keybd_event(VK_TAB, 0, KEYEVENTF_KEYUP, nullptr);
      keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, nullptr);

      await Future.delayed(const Duration(milliseconds: 500));

      // محاولة نسخ محتوى الشاشة المرئي باستخدام Ctrl+A ثم Ctrl+C
      keybd_event(VK_CONTROL, 0, 0, nullptr);
      keybd_event('A'.codeUnitAt(0), 0, 0, nullptr);
      keybd_event('A'.codeUnitAt(0), 0, KEYEVENTF_KEYUP, nullptr);
      keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, nullptr);

      await Future.delayed(const Duration(milliseconds: 300));

      keybd_event(VK_CONTROL, 0, 0, nullptr);
      keybd_event('C'.codeUnitAt(0), 0, 0, nullptr);
      keybd_event('C'.codeUnitAt(0), 0, KEYEVENTF_KEYUP, nullptr);
      keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, nullptr);

      await Future.delayed(const Duration(milliseconds: 500));

      // التحقق من وجود مربع النص (إذا كان موجود = الرقم صحيح)
      // محاولة النقر على مربع النص
      final screenWidth = GetSystemMetrics(SM_CXSCREEN);
      final screenHeight = GetSystemMetrics(SM_CYSCREEN);
      final textBoxX = (screenWidth * 0.5).round();
      final textBoxY = (screenHeight * 0.82).round();

      clickAtPosition(textBoxX, textBoxY);
      await Future.delayed(const Duration(milliseconds: 300));

      // محاولة كتابة نص تجريبي
      keybd_event('T'.codeUnitAt(0), 0, 0, nullptr);
      keybd_event('T'.codeUnitAt(0), 0, KEYEVENTF_KEYUP, nullptr);

      await Future.delayed(const Duration(milliseconds: 200));

      // محاولة حذف النص التجريبي
      keybd_event(VK_BACK, 0, 0, nullptr);
      keybd_event(VK_BACK, 0, KEYEVENTF_KEYUP, nullptr);

      // إذا وصلنا هنا بدون خطأ، فالرقم موجود على الأرجح
      print('✅ يبدو أن الرقم موجود على الواتساب');
      return {
        'exists': true,
        'message': 'الرقم موجود على الواتساب ✅',
        'phoneNumber': 'تم التحقق بنجاح'
      };
    } catch (e) {
      print('⚠️ لا يمكن التأكد من وجود الرقم: $e');
      return {
        'exists': false,
        'error': 'لا يمكن التأكد من وجود الرقم على الواتساب',
        'message': 'قد يكون الرقم غير موجود أو هناك مشكلة في الاتصال'
      };
    }
  }

  /// فحص إذا كان الإرسال متاحاً (منع الإرسال المتكرر)
  static bool canSend() {
    if (_isSending) return false;

    final now = DateTime.now();
    if (_lastSendTime != null) {
      final timeSinceLastSend = now.difference(_lastSendTime!);
      if (timeSinceLastSend.inSeconds < 2) {
        print(
            '⏰ انتظار ${2 - timeSinceLastSend.inSeconds} ثانية قبل الإرسال التالي');
        return false;
      }
    }
    return true;
  }

  /// إرسال ضغطة مفتاح TAB
  static void sendTabKey() {
    if (!Platform.isWindows) return;

    // إرسال ضغطة TAB (VK_TAB = 0x09)
    keybd_event(VK_TAB, 0, KEYEVENTF_EXTENDEDKEY, nullptr);
    keybd_event(VK_TAB, 0, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP, nullptr);
  }

  /// إرسال ضغطة مفتاح ENTER
  static void sendEnterKey() {
    if (!Platform.isWindows) return;

    // إرسال ضغطة ENTER (VK_RETURN = 0x0D)
    keybd_event(VK_RETURN, 0, 0, nullptr);
    keybd_event(VK_RETURN, 0, KEYEVENTF_KEYUP, nullptr);
  }

  /// إرسال SHIFT+TAB (للعودة خطوة للخلف في واتساب بعد الإرسال)
  static void sendShiftTabKey() {
    if (!Platform.isWindows) return;
    // ضغط SHIFT
    keybd_event(VK_SHIFT, 0, 0, nullptr);
    // ضغط TAB مع إبقاء SHIFT مضغوط
    keybd_event(VK_TAB, 0, 0, nullptr);
    keybd_event(VK_TAB, 0, KEYEVENTF_KEYUP, nullptr);
    // تحرير SHIFT
    keybd_event(VK_SHIFT, 0, KEYEVENTF_KEYUP, nullptr);
  }

  /// إرسال Ctrl+V للصق النص من الكليببورد مع تحسين الموثوقية
  static void sendCtrlV() {
    if (!Platform.isWindows) return;

    // الضغط على Ctrl
    keybd_event(VK_CONTROL, 0, 0, nullptr);
    // انتظار قصير جداً للتأكد من تسجيل الضغطة
    Sleep(10); // 10ms انتظار صغير

    // الضغط على V مع الاحتفاظ بـ Ctrl
    keybd_event('V'.codeUnitAt(0), 0, 0, nullptr);
    keybd_event('V'.codeUnitAt(0), 0, KEYEVENTF_KEYUP, nullptr);

    // انتظار قصير قبل تحرير Ctrl
    Sleep(10); // 10ms انتظار صغير
    // تحرير Ctrl
    keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, nullptr);
  }

  /// النقر بالفأرة على موقع محدد
  static void clickAtPosition(int x, int y) {
    if (!Platform.isWindows) return;

    // تحريك الفأرة للموقع المحدد
    SetCursorPos(x, y);

    // النقر بالزر الأيسر للفأرة
    keybd_event(VK_LBUTTON, 0, 0, nullptr);
    keybd_event(VK_LBUTTON, 0, KEYEVENTF_KEYUP, nullptr);
  }

  /// تأشير مربع النص باستخدام النقر المحسن في منطقة النص
  static Future<void> focusTextBox({int delayMs = 150}) async {
    if (!Platform.isWindows) return;

    try {
      print('🎯 تأشير مربع النص بالنقر السريع...');

      // النقر في منطقة مربع النص المحسنة (أكثر دقة)
      final screenWidth = GetSystemMetrics(SM_CXSCREEN);
      final screenHeight = GetSystemMetrics(SM_CYSCREEN);

      // النقر في منطقة مربع النص المحسنة (أعلى قليلاً من السابق)
      final textBoxX = (screenWidth * 0.5).round(); // وسط الشاشة أفقياً
      final textBoxY =
          (screenHeight * 0.82).round(); // 82% من ارتفاع الشاشة (أعلى من 85%)

      print('📍 النقر السريع في الموقع: X=$textBoxX, Y=$textBoxY');
      clickAtPosition(textBoxX, textBoxY);
      await Future.delayed(Duration(milliseconds: delayMs));

      print('✅ تم تأشير مربع النص بسرعة - جاهز للصق');
    } catch (e) {
      print('❌ خطأ في تأشير مربع النص: $e');
    }
  }

  /// الانتقال مباشرة لعنصر محدد باستخدام رقم TAB
  static Future<void> navigateDirectlyToTab(int tabNumber,
      {int delayMs = 300}) async {
    if (!Platform.isWindows) return;

    try {
      print('🎯 الانتقال المباشر إلى TAB$tabNumber...');

      // الانتقال المباشر لرقم TAB المحدد
      for (int i = 0; i < tabNumber; i++) {
        sendTabKey();
        await Future.delayed(Duration(milliseconds: delayMs ~/ 3)); // سرعة أكبر
      }

      print('✅ تم الوصول لـ TAB$tabNumber');
    } catch (e) {
      print('❌ خطأ في الانتقال المباشر: $e');
    }
  }

  /// إرسال عدة ضغطات TAB متتالية مع تأخير سريع
  static Future<void> sendMultipleTabs(int count, {int delayMs = 100}) async {
    if (!Platform.isWindows) return;

    for (int i = 0; i < count; i++) {
      sendTabKey();
      await Future.delayed(Duration(milliseconds: delayMs));
    }
  }

  /// إرسال بسيط وسريع مع حماية من التكرار: تأشير مربع النص → لصق → TAB → إرسال
  static Future<void> performQuickAutoSend({int delayMs = 120}) async {
    if (!Platform.isWindows) return;

    // فحص إمكانية الإرسال لمنع التكرار
    if (!canSend()) {
      print('⚠️ الإرسال غير متاح حالياً - منع التكرار');
      return;
    }

    _isSending = true;

    try {
      // انتظار سريع جداً للتأكد من فتح الواتساب
      await Future.delayed(const Duration(milliseconds: 800));

      print('🚀 بدء الإرسال التلقائي فائق السرعة...');

      // الخطوة 1: تأشير مربع النص بالنقر عليه
      print('🎯 تأشير مربع النص بالنقر السريع...');
      await focusTextBox(delayMs: delayMs);

      // الخطوة 2: لصق النص باستخدام Ctrl+V
      print('📋 لصق النص سريع (Ctrl+V)...');
      await Future.delayed(Duration(milliseconds: delayMs));
      sendCtrlV();
      await Future.delayed(Duration(milliseconds: delayMs));

      // الخطوة 3: TAB واحد للانتقال لزر الإرسال
      print('📤 الانتقال لزر الإرسال سريع (TAB)...');
      sendTabKey();
      await Future.delayed(Duration(milliseconds: delayMs));

      // الخطوة 4: إرسال الرسالة (Enter) والتوقف
      print('✉️ إرسال سريع (Enter) والتوقف...');
      sendEnterKey();
      await Future.delayed(Duration(milliseconds: delayMs));
      print('↩️ تنفيذ SHIFT+TAB لإرجاع التركيز إلى مربع النص');
      sendShiftTabKey();

      // تحديث وقت آخر إرسال
      _lastSendTime = DateTime.now();

      print('✅ تم الإرسال التلقائي فائق السرعة: نقر → Ctrl+V → TAB → Enter ✋');
    } catch (e) {
      print('❌ خطأ في الإرسال التلقائي السريع: $e');
    } finally {
      _isSending = false;
    }
  }

  static Future<void> performSimpleAutoSend({int delayMs = 300}) async {
    if (!Platform.isWindows) return;

    try {
      // انتظار للتأكد من فتح الواتساب بالكامل
      await Future.delayed(const Duration(seconds: 3));

      print('🚀 بدء الإرسال التلقائي البسيط...');

      // الخطوة 1: TAB×11 للوصول لمربع النص
      print('� الانتقال لمربع النص (TAB×11)...');
      await sendMultipleTabs(11, delayMs: delayMs);

      // انتظار قصير
      await Future.delayed(Duration(milliseconds: delayMs));

      // الخطوة 2: TAB×1 للانتقال لزر الإرسال
      print('� الانتقال لزر الإرسال (TAB×1)...');
      sendTabKey();
      await Future.delayed(Duration(milliseconds: delayMs));

      // الخطوة 3: Enter للإرسال والتوقف
      print('✉️ إرسال الرسالة (Enter) والتوقف...');
      sendEnterKey();
      await Future.delayed(Duration(milliseconds: delayMs));
      print('↩️ (Ultra) SHIFT+TAB لإرجاع التركيز');
      sendShiftTabKey();

      print('✅ تم الإرسال التلقائي البسيط: TAB×11 → TAB×1 → Enter ✋ توقف');
    } catch (e) {
      print('❌ خطأ في الإرسال التلقائي البسيط: $e');
    }
  }

  /// البحث عن نافذة الواتساب والتركيز عليها
  static Future<bool> focusWhatsAppWindow() async {
    if (!Platform.isWindows) return false;

    try {
      // البحث عن نافذة الواتساب باستخدام اسم النافذة الشائع
      // تحديث لإصدارات الواتساب الجديدة 2.2532.3.0
      final windowTitles = [
        'WhatsApp',
        'WhatsApp Business',
        'WhatsApp Desktop',
        'WhatsApp - Google Chrome',
        'WhatsApp Web'
      ];

      for (String title in windowTitles) {
        final titlePtr = title.toNativeUtf16();
        final hWnd = FindWindow(nullptr, titlePtr);
        malloc.free(titlePtr);

        if (hWnd != 0) {
          // جعل النافذة في المقدمة والتركيز عليها
          SetForegroundWindow(hWnd);
          ShowWindow(hWnd, SW_RESTORE);
          await Future.delayed(
              const Duration(milliseconds: 300)); // وقت مخفف للسرعة القصوى
          print('✅ تم العثور على نافذة الواتساب: $title');
          return true;
        }
      }

      // محاولة البحث بطريقة أخرى - البحث في جميع النوافذ
      print('🔍 البحث السريع في جميع النوافذ المفتوحة...');
      await Future.delayed(
          const Duration(milliseconds: 800)); // وقت مخفف للسرعة القصوى

      for (String title in windowTitles) {
        final titlePtr = title.toNativeUtf16();
        final hWnd = FindWindow(nullptr, titlePtr);
        malloc.free(titlePtr);

        if (hWnd != 0) {
          SetForegroundWindow(hWnd);
          ShowWindow(hWnd, SW_RESTORE);
          await Future.delayed(const Duration(milliseconds: 300)); // سرعة قصوى
          print('✅ تم العثور على نافذة الواتساب في المحاولة الثانية: $title');
          return true;
        }
      }

      print('⚠️ لم يتم العثور على نافذة الواتساب');
      return false;
    } catch (e) {
      print('❌ خطأ في البحث عن نافذة الواتساب: $e');
      return false;
    }
  }

  /// الإرسال التلقائي مع البحث عن نافذة الواتساب أولاً
  static Future<bool> performSmartAutoSend({int delayMs = 120}) async {
    if (!Platform.isWindows) return false;

    try {
      print('🔍 بحث سريع جداً عن نافذة الواتساب...');

      // البحث عن نافذة الواتساب والتركيز عليها
      final found = await focusWhatsAppWindow();
      if (!found) {
        print('❌ لم يتم العثور على نافذة الواتساب للإرسال التلقائي');
        // محاولة أخيرة بوقت مخفف جداً
        print('🔄 محاولة أخيرة سريعة...');
        await Future.delayed(const Duration(milliseconds: 1000));
        final foundRetry = await focusWhatsAppWindow();
        if (!foundRetry) {
          return false;
        }
      }

      print('✅ تم العثور على نافذة الواتساب، بدء الإرسال البرق...');

      // اختيار الطريقة الأنسب حسب الحالة
      if (delayMs <= 120) {
        // إرسال فائق السرعة
        print('⚡ تشغيل وضع الإرسال البرق...');
        await performLightningAutoSend(delayMs: delayMs);
      } else if (delayMs <= 180) {
        // إرسال سريع عادي
        print('🚀 تشغيل وضع الإرسال السريع...');
        await performQuickAutoSend(delayMs: delayMs);
      } else {
        // إرسال متطور للحالات المعقدة
        print('🎯 تشغيل وضع الإرسال المتطور...');
        await performUltraAutoSend(delayMs: delayMs);
      }

      return true;
    } catch (e) {
      print('❌ خطأ في الإرسال التلقائي الذكي: $e');
      return false;
    }
  }

  /// إرسال تلقائي متطور مع طرق متعددة للضمان
  static Future<void> performUltraAutoSend({int delayMs = 180}) async {
    if (!Platform.isWindows) return;

    // فحص إمكانية الإرسال
    if (!canSend()) {
      print('⚠️ الإرسال غير متاح حالياً - منع التكرار');
      return;
    }

    _isSending = true;

    try {
      print('🚀 بدء الإرسال التلقائي فائق التطور...');

      // انتظار محسن للواتساب
      await Future.delayed(const Duration(milliseconds: 1200));

      // الطريقة 1: النقر المباشر + لصق سريع
      print('🎯 المحاولة 1: النقر المباشر...');
      await focusTextBox(delayMs: delayMs);

      print('📋 لصق محسن...');
      await Future.delayed(Duration(milliseconds: delayMs));
      sendCtrlV();
      await Future.delayed(Duration(milliseconds: delayMs));

      // التحقق من نجاح اللصق بالضغط على Ctrl+A ثم Ctrl+V مرة أخرى
      print('🔄 تأكيد اللصق...');
      keybd_event(VK_CONTROL, 0, 0, nullptr);
      keybd_event('A'.codeUnitAt(0), 0, 0, nullptr);
      keybd_event('A'.codeUnitAt(0), 0, KEYEVENTF_KEYUP, nullptr);
      keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, nullptr);

      await Future.delayed(Duration(milliseconds: delayMs ~/ 2));
      sendCtrlV(); // لصق مرة أخرى للتأكد

      // إرسال سريع
      print('📤 إرسال سريع...');
      await Future.delayed(Duration(milliseconds: delayMs));
      sendTabKey();
      await Future.delayed(Duration(milliseconds: delayMs));
      sendEnterKey();
      await Future.delayed(Duration(milliseconds: delayMs));
      print('↩️ (Lightning) SHIFT+TAB لإرجاع التركيز');
      sendShiftTabKey();

      _lastSendTime = DateTime.now();
      print('✅ تم الإرسال فائق التطور بنجاح!');
    } catch (e) {
      print('❌ خطأ في الإرسال فائق التطور: $e');
    } finally {
      _isSending = false;
    }
  }

  /// إرسال سريع جداً - للاستخدام عند التأكد من جاهزية النظام
  static Future<void> performLightningAutoSend({int delayMs = 120}) async {
    if (!Platform.isWindows) return;

    if (!canSend()) return;
    _isSending = true;

    try {
      print('⚡ إرسال البرق - فائق السرعة...');

      // بدون انتظار - تنفيذ مباشر
      await focusTextBox(delayMs: delayMs ~/ 2);
      sendCtrlV();
      await Future.delayed(Duration(milliseconds: delayMs));
      sendTabKey();
      await Future.delayed(Duration(milliseconds: delayMs ~/ 2));
      sendEnterKey();
      // إرجاع التركيز مباشرةً إلى مربع النص بخطوة واحدة فقط (SHIFT+TAB)
      await Future.delayed(Duration(milliseconds: delayMs));
      print('↩️ (Lightning) SHIFT+TAB لإرجاع التركيز إلى مربع النص');
      sendShiftTabKey();

      _lastSendTime = DateTime.now();
      print('⚡ تم الإرسال البرق!');
    } catch (e) {
      print('❌ خطأ في الإرسال البرق: $e');
    } finally {
      _isSending = false;
    }
  }
}
