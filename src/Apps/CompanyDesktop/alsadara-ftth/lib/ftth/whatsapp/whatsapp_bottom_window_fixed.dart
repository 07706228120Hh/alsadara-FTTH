import 'dart:async';
import 'dart:io';
// (تمت إزالة استيراد dart:convert لعدم الحاجة حالياً)
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as wvwin;
import 'package:url_launcher/url_launcher.dart';
import '../../pages/whatsapp_conversations_page.dart' as conv_page;
import '../../services/whatsapp_conversation_service.dart';

/// نافذة واتساب كاملة الحجم
class WhatsAppBottomWindow {
  static OverlayEntry? _overlayEntry;
  static OverlayEntry? _fabEntry;
  static OverlayEntry? _conversationsFabEntry; // زر عائم للمحادثات
  static bool _isShowing = false;
  static bool _isHidden = false;
  static Timer? _fabGuardTimer; // مراقبة لضمان بقاء زر الواتساب
  static OverlayState? _rootOverlay; // overlay الجذرية لتثبيت العناصر عالمياً
  static bool _initialized = false; // تم التهيئة الجذرية
  // _isHidden == true يعني أننا في حالة تصغير (Minimized) لكن ما زال الـ WebView موجود في الذاكرة
  static _WhatsAppBottomWindowState? _instance;
  static BuildContext? _savedContext;
  static Widget? _savedWindowContent; // حفظ محتوى النافذة لإعادة الاستخدام
  static final GlobalKey<_WhatsAppBottomWindowState> _windowKey =
      GlobalKey<_WhatsAppBottomWindowState>(); // مفتاح للحفاظ على الحالة
  static bool _isAdminUser = false; // حالة المدير

  /// التحقق من وجود نافذة مخفية
  static bool get hasHiddenWindow =>
      _isShowing && _isHidden && _savedWindowContent != null;

  /// إظهار نافذة واتساب بحجم كامل
  static void showBottomWindow(
      BuildContext context, String phone, String message) {
    // تأكد من التهيئة الجذرية
    ensureGlobal(context);
    _savedContext = context;

    debugPrint(
        '🔍 showBottomWindow called: _isShowing=$_isShowing, _isHidden=$_isHidden');

    // إذا كانت النافذة مخفية، أظهرها مع المحتوى المحفوظ
    if (_isShowing && _isHidden && _savedWindowContent != null) {
      // استرجاع سريع دون إعادة تحميل كامل
      _restoreMinimizedWindow();
      if (phone.isNotEmpty && message.isNotEmpty) {
        // استخدم المسار الذكي (سيراعي نفس المحادثة)
        sendMessageToBottomWindow(phone, message);
      }
      return;
    }

    if (_isShowing && !_isHidden) {
      if (phone.isNotEmpty && message.isNotEmpty) {
        sendMessageToBottomWindow(phone, message);
      }
      return;
    }

    // إنشاء نافذة جديدة فقط إذا لم تكن موجودة
    _savedWindowContent ??= WhatsAppBottomWindowContent(
      key: _windowKey,
      phone: phone,
      message: message,
      onClose: _closeWindow, // إغلاق نهائي
      onMinimize: _minimizeWindow, // تصغير فقط
    );

    _overlayEntry = OverlayEntry(
        builder: (context) => IgnorePointer(
              ignoring:
                  _isHidden, // السماح بالنقر على العناصر أسفل النافذة عند التصغير
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isHidden ? 0.0 : 1.0,
                child: Material(
                  child: Container(
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                    color: Colors.white,
                    child: _savedWindowContent!,
                  ),
                ),
              ),
            ));

    final overlay = _rootOverlay ?? Overlay.of(context, rootOverlay: true);
    overlay.insert(_overlayEntry!);
    _isShowing = true;
    _isHidden = false;

    // تأكد من وجود زر الواتساب دائماً (حتى أثناء فتح النافذة)
    // إظهار الزر العائم (عالمي) إن لم يكن موجوداً
    if (_fabEntry == null) {
      showFloatingButton(context);
    }
  }

  /// إخفاء النافذة
  static void hideBottomWindow({bool clearContent = false}) {
    try {
      if (_overlayEntry != null) {
        _overlayEntry!.remove();
        _overlayEntry = null;
      }
    } catch (e) {
      debugPrint('⚠️ Error removing main overlay: $e');
      _overlayEntry = null;
    }

    try {
      if (_fabEntry != null) {
        _fabEntry!.remove();
        _fabEntry = null;
      }
    } catch (e) {
      debugPrint('⚠️ Error removing FAB overlay: $e');
      _fabEntry = null;
    }

    // إعادة تعيين جميع الحالات
    _isShowing = false;
    _isHidden = false;

    // مسح المحتوى فقط عند الإغلاق النهائي (clearContent = true)
    if (clearContent) {
      _instance = null;
      _savedContext = null;
      _savedWindowContent = null;
      _stopFabGuard();
    }
  }

  /// تصغير النافذة وإظهار الزر العائم
  static void _minimizeWindow() {
    if (!_isShowing) return;
    if (_isHidden) return; // بالفعل مصغرة
    _isHidden = true;
    // تحديث الـ overlay بدون إزالة الـ WebView للحفاظ على الجلسة
    _overlayEntry?.markNeedsBuild();

    // إظهار الزر العائم
    if (_savedContext != null) {
      try {
        if (_savedContext!.mounted) {
          showFloatingButton(_savedContext!);
        } else {
          debugPrint('⚠️ Saved context is not mounted, cannot show FAB');
        }
      } catch (e) {
        debugPrint('⚠️ Error showing FAB after minimize: $e');
      }
    }
  }

  /// إرجاع النافذة المصغرة بدون إعادة تحميل أو فقدان الحالة
  static void _restoreMinimizedWindow() {
    if (!_isShowing || !_isHidden) return;
    _isHidden = false;
    _overlayEntry?.markNeedsBuild();
    // لا نقوم بإزالة زر الواتساب لإبقائه دائماً
    if (_fabEntry == null && _savedContext != null) {
      try {
        if (_savedContext!.mounted) {
          showFloatingButton(_savedContext!);
        }
      } catch (_) {}
    }
  }

  /// إغلاق نهائي مع تنظيف الحالة بالكامل
  static void _closeWindow() {
    hideBottomWindow(clearContent: true);
  }

  /// ضمان وجود زر الواتساب بعد الانتقال بين أنظمة / صفحات مختلفة
  /// استدعها من الشاشة الرئيسية لكل نظام (في build أو بعد الانتقال) لضمان إعادة إظهار الزر إذا فُقد الـ Overlay القديم.
  static void ensureFloatingButton(BuildContext context) {
    ensureGlobal(context);
    _savedContext = context;
    // إذا كان لدينا زر مفقود (null) أو تم التخلص من الـ overlay السابق (يحصل بعد تغيير Navigator)
    bool needsRecreate = false;
    if (_fabEntry == null) {
      needsRecreate = true;
    } else {
      // محاولة تحفيز إعادة بناء؛ لو حصل خطأ نعيد إنشاؤه
      try {
        _fabEntry!.markNeedsBuild();
      } catch (e) {
        debugPrint('⚠️ FAB overlay seems detached, recreating: $e');
        try {
          _fabEntry!.remove();
        } catch (_) {}
        _fabEntry = null;
        needsRecreate = true;
      }
    }
    if (needsRecreate) {
      showFloatingButton(context);
    }
  }

  /// إظهار النافذة المخفية مع المحتوى المحفوظ
  // (تم إلغاء الدالة القديمة _showExistingWindow لعدم الحاجة)

  /// إظهار الزر العائم
  static void showFloatingButton(BuildContext context) {
    // تهيئة جذرية إذا لم تتم
    ensureGlobal(context);
    // إذا كان موجوداً ومثبتاً (mounted) لا نعيد إنشاءه، فقط نضمن الحارس
    if (_fabEntry != null && _fabEntry!.mounted) {
      _startFabGuard();
      return;
    }
    // إن كان غير مثبت أو null نحذفه وننشئ واحد جديد
    if (_fabEntry != null && !_fabEntry!.mounted) {
      try {
        _fabEntry!.remove();
      } catch (_) {}
      _fabEntry = null;
    }

    // التحقق من أن الـ context ما زال صالحاً
    try {
      if (!context.mounted) {
        debugPrint('⚠️ Context is not mounted, cannot show FAB');
        return;
      }
    } catch (e) {
      debugPrint('⚠️ Context error: $e');
      return;
    }

    _fabEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 80,
        right: 20,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(28),
          child: FloatingActionButton(
            onPressed: () {
              try {
                debugPrint('🔘 ضغط زر واتساب العائم');
                if (_isShowing && _isHidden) {
                  // فقط استرجاع بدون تحميل جديد
                  _restoreMinimizedWindow();
                  debugPrint('✅ تم استرجاع النافذة المصغرة');
                } else {
                  showBottomWindow(context, '', '');
                  debugPrint('✅ تم فتح/إظهار نافذة الواتساب');
                }
              } catch (e) {
                debugPrint('❌ خطأ في التعامل مع زر الواتساب العائم: $e');
              }
            },
            backgroundColor: const Color(0xFF25D366),
            heroTag: "whatsapp_fab",
            tooltip: 'فتح واتساب ويب',
            child: Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17.5),
                color: Colors.white,
              ),
              child: const Icon(
                Icons.chat,
                color: Color(0xFF25D366),
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final overlay = _rootOverlay ?? Overlay.of(context, rootOverlay: true);
      overlay.insert(_fabEntry!);
    } catch (e) {
      debugPrint('⚠️ Failed to insert FAB overlay: $e');
      _fabEntry = null;
    }

    _startFabGuard();
  }

  /// إظهار زر عائم للمحادثات (على الجهة اليسرى)
  static void showConversationsFloatingButton(BuildContext context,
      {bool isAdmin = false}) {
    _isAdminUser = isAdmin; // حفظ حالة المدير
    debugPrint('👤 showConversationsFloatingButton - isAdmin: $isAdmin');
    if (_conversationsFabEntry != null) {
      _conversationsFabEntry?.remove();
      _conversationsFabEntry = null;
    }

    // التحقق من أن الـ context ما زال صالحاً
    try {
      if (!context.mounted) {
        debugPrint('⚠️ Context is not mounted, cannot show Conversations FAB');
        return;
      }
    } catch (e) {
      debugPrint('⚠️ Context error: $e');
      return;
    }

    _conversationsFabEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 80,
        left: 20, // على الجهة اليسرى
        child: StreamBuilder<int>(
          stream: WhatsAppConversationService.getUnreadCount(),
          builder: (context, snapshot) {
            final unreadCount = snapshot.data ?? 0;

            return Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  FloatingActionButton(
                    onPressed: () {
                      try {
                        debugPrint('🔘 ضغط زر المحادثات العائم');
                        // فتح صفحة المحادثات
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                conv_page.WhatsAppConversationsPage(
                                    isAdmin: _isAdminUser),
                          ),
                        );
                      } catch (e) {
                        debugPrint('❌ خطأ في فتح صفحة المحادثات: $e');
                      }
                    },
                    backgroundColor: const Color(0xFF128C7E),
                    heroTag: "whatsapp_conversations_fab",
                    tooltip: 'محادثات الواتساب',
                    child: Container(
                      width: 35,
                      height: 35,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(17.5),
                        color: Colors.white,
                      ),
                      child: const Icon(
                        Icons.chat_bubble,
                        color: Color(0xFF128C7E),
                        size: 24,
                      ),
                    ),
                  ),
                  // Badge للرسائل غير المقروءة
                  if (unreadCount > 0)
                    Positioned(
                      top: -5,
                      right: -5,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );

    try {
      final overlay = _rootOverlay ?? Overlay.of(context, rootOverlay: true);
      overlay.insert(_conversationsFabEntry!);
    } catch (e) {
      debugPrint('⚠️ Failed to insert Conversations FAB overlay: $e');
      _conversationsFabEntry = null;
    }
  }

  /// إخفاء زر المحادثات العائم
  static void hideConversationsFloatingButton() {
    _conversationsFabEntry?.remove();
    _conversationsFabEntry = null;
  }

  /// فحص إذا كانت النافذة مفتوحة
  static bool isBottomWindowShowing() {
    return _isShowing && _instance != null;
  }

  /// إرسال رسالة للنافذة المفتوحة
  static bool sendMessageToBottomWindow(String phone, String message) {
    if (_isShowing && _instance != null) {
      try {
        // إذا كنا في نفس المحادثة الحالية (نفس الرقم) نحاول حقن رسالة بدون إعادة تحميل كامل
        if (_instance!._currentPhone.isNotEmpty &&
            phone == _instance!._currentPhone) {
          debugPrint('💬 إرسال رسالة إضافية في نفس المحادثة بدون إعادة تحميل');
          _instance!.sendAnotherMessageSameChat(message);
          return true;
        }
        // خلاف ذلك: فتح محادثة جديدة (قد يؤدي لتحميل واجهة المحادثة فقط)
        _instance!.sendNewMessage(phone, message);
        return true;
      } catch (e) {
        debugPrint('⚠️ فشل إرسال رسالة إلى النافذة المفتوحة: $e');
        try {
          _instance!.sendNewMessage(phone, message);
          return true;
        } catch (_) {}
      }
    }
    return false;
  }

  // ================== حارس الزر (FAB Guard) ==================
  static void _startFabGuard() {
    if (_fabGuardTimer?.isActive ?? false) return;
    _fabGuardTimer = Timer.periodic(const Duration(seconds: 2), (t) {
      // إذا اختفى أو أصبح غير مثبت (unmounted) بسبب إعادة بناء / تسجيل خروج / تبديل نظام
      if ((_fabEntry == null || !_fabEntry!.mounted) && _savedContext != null) {
        debugPrint('🔄 FAB guard: recreating missing/unmounted WhatsApp FAB');
        try {
          if (_savedContext!.mounted) {
            showFloatingButton(_savedContext!);
          }
        } catch (e) {
          debugPrint('⚠️ FAB guard recreate error: $e');
        }
      }
    });
  }

  static void _stopFabGuard() {
    try {
      _fabGuardTimer?.cancel();
    } catch (_) {}
    _fabGuardTimer = null;
  }

  /// تهيئة جذرية لمرة واحدة لتثبيت الـ rootOverlay
  static void ensureGlobal(BuildContext context) {
    if (!_initialized) {
      try {
        _rootOverlay = Overlay.of(context, rootOverlay: true);
        _initialized = _rootOverlay != null;
        debugPrint('✅ WhatsApp global overlay initialized: $_initialized');

        // إظهار زر المحادثات العائم
        if (_initialized && _conversationsFabEntry == null) {
          showConversationsFloatingButton(context, isAdmin: _isAdminUser);
        }
      } catch (e) {
        debugPrint('⚠️ Failed to init global overlay: $e');
      }
    }
  }
}

class WhatsAppBottomWindowContent extends StatefulWidget {
  final String phone;
  final String message;
  final VoidCallback onClose;
  final VoidCallback onMinimize;

  const WhatsAppBottomWindowContent({
    super.key,
    required this.phone,
    required this.message,
    required this.onClose,
    required this.onMinimize,
  });

  @override
  State<WhatsAppBottomWindowContent> createState() =>
      _WhatsAppBottomWindowState();
}

class _WhatsAppBottomWindowState extends State<WhatsAppBottomWindowContent> {
  bool _isLoading = true;
  bool _isLoggedIn = false;
  bool _messageSent = false;
  String? _error;
  WebViewController? _controller;
  wvwin.WebviewController? _winController;
  Timer? _statusMonitor;

  String _currentPhone = '';
  String _currentMessage = '';

  @override
  void initState() {
    super.initState();
    WhatsAppBottomWindow._instance = this;
    _currentPhone = widget.phone;
    _currentMessage = widget.message;

    _checkSavedLoginState();
    _initializeWebView();
  }

  @override
  void dispose() {
    try {
      _statusMonitor?.cancel();
    } catch (e) {
      debugPrint('⚠️ Error canceling status monitor: $e');
    }

    // تنظيف آمن للـ instance reference
    if (WhatsAppBottomWindow._instance == this) {
      WhatsAppBottomWindow._instance = null;
    }

    super.dispose();
  }

  Future<void> _checkSavedLoginState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLogin = prefs.getBool('wa_web_logged_in') ?? false;
      if (savedLogin) {
        debugPrint('✅ جلسة واتساب ويب محفوظة مسبقاً');
        setState(() => _isLoggedIn = true);
      }
    } catch (e) {
      debugPrint('❌ خطأ في فحص حالة تسجيل الدخول: $e');
    }
  }

  Future<void> _initializeWebView() async {
    try {
      if (Platform.isWindows) {
        await _initializeWindowsWebView();
      } else {
        await _initializeFlutterWebView();
      }
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة WebView: $e');
      setState(() {
        _error = 'خطأ في تحميل واتساب: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeWindowsWebView() async {
    try {
      _winController = wvwin.WebviewController();

      await _winController!.initialize();
      await _winController!.setBackgroundColor(Colors.white);
      await _winController!
          .setPopupWindowPolicy(wvwin.WebviewPopupWindowPolicy.deny);

      _winController!.url.listen((url) {
        debugPrint('🌐 URL تغيّر إلى: $url');
        _handleUrlChange(url);
      });

      _winController!.loadingState.listen((state) {
        if (state == wvwin.LoadingState.navigationCompleted) {
          setState(() => _isLoading = false);
          _startStatusMonitoring();
        }
      });

      // تحميل واتساب ويب
      final encodedMessage = Uri.encodeComponent(_currentMessage);
      final webUrl =
          'https://web.whatsapp.com/send?phone=$_currentPhone&text=$encodedMessage';
      await _winController!.loadUrl(webUrl);
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة Windows WebView: $e');
      setState(() {
        if (e.toString().toLowerCase().contains('webview2') ||
            e.toString().toLowerCase().contains('edge') ||
            e.toString().toLowerCase().contains('runtime')) {
          _error =
              'يتطلب Microsoft Edge WebView2 Runtime لعمل الواتساب.\n\nيرجى تحميله وتثبيته من موقع مايكروسوفت الرسمي ثم إعادة تشغيل التطبيق.';
        } else {
          _error = 'خطأ في تحميل واتساب ويب: ${e.toString()}';
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeFlutterWebView() async {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            debugPrint('🔄 تقدم التحميل: $progress%');
          },
          onPageStarted: (String url) {
            debugPrint('🌐 بدء تحميل: $url');
            _handleUrlChange(url);
          },
          onPageFinished: (String url) {
            debugPrint('✅ انتهى تحميل: $url');
            setState(() => _isLoading = false);
            _startStatusMonitoring();
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('❌ خطأ ويب: ${error.description}');
            setState(() {
              _error = 'خطأ في التحميل: ${error.description}';
              _isLoading = false;
            });
          },
        ),
      );

    // تحميل واتساب ويب
    final encodedMessage = Uri.encodeComponent(_currentMessage);
    final webUrl =
        'https://web.whatsapp.com/send?phone=$_currentPhone&text=$encodedMessage';
    await _controller!.loadRequest(Uri.parse(webUrl));
  }

  void _handleUrlChange(String url) {
    if (url.contains('web.whatsapp.com') && !url.contains('/auth')) {
      if (!_isLoggedIn) {
        setState(() => _isLoggedIn = true);
        _saveLoginState();
      }
    }
  }

  Future<void> _saveLoginState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('wa_web_logged_in', true);
      debugPrint('💾 تم حفظ حالة تسجيل الدخول');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ حالة الدخول: $e');
    }
  }

  void _startStatusMonitoring() {
    _statusMonitor?.cancel();
    _statusMonitor = Timer.periodic(const Duration(seconds: 2), (timer) {
      _checkMessageSent();
    });
  }

  Future<void> _checkMessageSent() async {
    try {
      if (Platform.isWindows && _winController != null) {
        try {
          await _winController!.executeScript(
              'document.querySelector("[data-icon=\'msg-check\']") !== null');
          if (!_messageSent) {
            setState(() => _messageSent = true);
            _statusMonitor?.cancel();
            // _showSuccessMessage(); // تم تعطيل إشعار النجاح
          }
        } catch (e) {
          // تجاهل الخطأ واستمر في المحاولة
        }
      } else if (_controller != null) {
        final result = await _controller!.runJavaScriptReturningResult(
            'document.querySelector("[data-icon=\'msg-check\']") !== null');

        if (result.toString() == 'true' && !_messageSent) {
          setState(() => _messageSent = true);
          _statusMonitor?.cancel();
          // _showSuccessMessage(); // تم تعطيل إشعار النجاح
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في فحص حالة الإرسال: $e');
    }
  }

  /// دالة لإرسال رسالة جديدة
  void sendNewMessage(String phone, String message) {
    if (!mounted) return;

    debugPrint('📨 إرسال رسالة جديدة: $phone');
    // حالة نفس المحادثة: حقن فقط
    if (phone == _currentPhone && _currentPhone.isNotEmpty) {
      debugPrint('♻️ نفس المحادثة الحالية -> حقن رسالة فقط');
      sendAnotherMessageSameChat(message);
      return;
    }

    // محاولة التحويل السريع أولاً (بدون إعادة تحميل كامل)
    if (_isLoggedIn && !_isLoading) {
      debugPrint('🔄 محاولة التحويل السريع للرقم الجديد...');
      bool quickSwitchSuccess = tryQuickSwitchChat(phone, message);

      if (quickSwitchSuccess) {
        debugPrint('✅ نجح التحويل السريع');
        setState(() {
          _currentPhone = phone;
          _currentMessage = message;
          _messageSent = false;
        });

        // مراقبة حالة الإرسال
        _startStatusMonitoring();
        return;
      }

      debugPrint('⚠️ فشل التحويل السريع، الانتقال لإعادة التحميل الكامل');
    }

    // إذا فشل التحويل السريع أو لم نكن مسجلين دخول، نعيد التحميل الكامل
    debugPrint('🔄 فتح محادثة جديدة برقم مختلف (إعادة تحميل كاملة)');

    setState(() {
      _currentPhone = phone;
      _currentMessage = message;
      _messageSent = false;
      _isLoading = true;
    });

    final encodedMessage = Uri.encodeComponent(message);
    final webUrl =
        'https://web.whatsapp.com/send?phone=$phone&text=$encodedMessage';
    if (Platform.isWindows && _winController != null) {
      _winController!.loadUrl(webUrl);
    } else if (!Platform.isWindows && _controller != null) {
      _controller!.loadRequest(Uri.parse(webUrl));
    }
    _startStatusMonitoring();
  }

  /// إرسال رسالة إضافية في نفس المحادثة المفتوحة بدون إعادة تحميل كامل
  void sendAnotherMessageSameChat(String message) {
    if (!mounted) return;
    // إن لم نكن في محادثة جاهزة نتراجع إلى sendNewMessage
    if (_currentPhone.isEmpty) {
      debugPrint(
          'ℹ️ لا توجد محادثة حالية، سيتم تجاهل sendAnotherMessageSameChat');
      return;
    }
    _currentMessage = message; // تحديث آخر رسالة (اختياري)
    debugPrint('💬 حقن رسالة جديدة في نفس المحادثة الحالية');
    final escaped = message
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r"\n");

    final js = """
      (function(){
        try {
          const boxes = document.querySelectorAll('[contenteditable="true"]');
          if (!boxes || boxes.length === 0) return false;
          const box = boxes[boxes.length-1];
          box.focus();
          const dataTransfer = new DataTransfer();
          dataTransfer.setData('text', '$escaped');
          const evt = new ClipboardEvent('paste', { clipboardData: dataTransfer });
          box.dispatchEvent(evt);
          // محاكاة ضغط Enter
          const enterEvent = new KeyboardEvent('keydown', {key: 'Enter', code: 'Enter', which:13, keyCode:13, bubbles:true});
          box.dispatchEvent(enterEvent);
          return true;
        } catch(e){ return false; }
      })();
    """;

    try {
      if (Platform.isWindows && _winController != null) {
        _winController!.executeScript(js);
      } else if (_controller != null) {
        _controller!.runJavaScript(js);
      }
    } catch (e) {
      debugPrint('⚠️ فشل حقن الرسالة في نفس المحادثة: $e');
    }
  }

  /// محاولة فتح محادثة جديدة (رقم جديد) بدون إعادة تحميل كامل للصفحة
  /// تعود true إذا نجح الحقن، false إذا لم تتوفر البيئة الداخلية (Store) أو فشل التنفيذ
  bool tryQuickSwitchChat(String phone, String message) {
    if (!mounted) return false;
    // لا نحاول إن لم نكن مسجلين دخول أو الـ WebView ما زال في حالة تحميل
    if (_isLoading) return false;

    // التأكد من أن WhatsApp Store متاح (يتم توفيره بعد اكتمال تهيئة واجهة واتساب)
    final js = _buildQuickSwitchScript(phone, message);
    try {
      if (Platform.isWindows && _winController != null) {
        _winController!.executeScript(js);
        _currentPhone = phone; // تحديث مبكر لتقليل إعادة التحميل لاحقاً
        return true; // تفادي تحميل كامل
      } else if (!Platform.isWindows && _controller != null) {
        _controller!.runJavaScript(js);
        _currentPhone = phone;
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ فشل quickSwitchChat: $e');
    }
    return false;
  }

  String _buildQuickSwitchScript(String phone, String message) {
    final escapedMsg = message
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('"', r'\"')
        .replaceAll('\n', r"\n")
        .replaceAll('\r', r"\r");
    final escapedPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');

    // سكريپت محسّن للبحث والتحويل للمحادثة الصحيحة
    return """
      (function(){
        console.log('🔍 بدء التحويل السريع للرقم: $escapedPhone');
        
        try {
          // التحقق من توفر Store
          if (!window.Store || !window.Store.Chat) {
            console.log('❌ Store أو Store.Chat غير متاح');
            return false;
          }
          
          const targetPhone = '$escapedPhone@c.us';
          console.log('📞 البحث عن رقم: ' + targetPhone);
          
          // محاولة البحث المباشر أولاً
          const existingChat = window.Store.Chat.get(targetPhone);
          if (existingChat) {
            console.log('✅ وُجدت محادثة موجودة مسبقاً');
            try {
              window.Store.Cmd.openChatAt(existingChat.id);
              setTimeout(() => injectMessage('$escapedMsg'), 500);
              return true;
            } catch(e) {
              console.log('⚠️ فشل فتح المحادثة الموجودة: ' + e);
            }
          }
          
          // البحث في جميع المحادثات المتاحة
          const allChats = window.Store.Chat.getModelsArray();
          console.log('🔍 البحث في ' + allChats.length + ' محادثة متاحة');
          
          const foundChat = allChats.find(chat => {
            if (!chat || !chat.id || !chat.id.user) return false;
            return chat.id.user === '$escapedPhone' || 
                   chat.id._serialized === targetPhone ||
                   (chat.contact && chat.contact.id && chat.contact.id.user === '$escapedPhone');
          });
          
          if (foundChat) {
            console.log('✅ وُجدت المحادثة: ' + foundChat.id._serialized);
            try {
              window.Store.Cmd.openChatAt(foundChat.id);
              setTimeout(() => injectMessage('$escapedMsg'), 800);
              return true;
            } catch(e) {
              console.log('⚠️ فشل فتح المحادثة المعثور عليها: ' + e);
            }
          }
          
          // إذا لم توجد المحادثة، محاولة إنشاء جديدة عبر الانتقال المباشر
          console.log('🆕 محاولة فتح محادثة جديدة');
          const newChatUrl = 'https://web.whatsapp.com/send?phone=$escapedPhone&text=' + 
                            encodeURIComponent('$escapedMsg');
          
          window.location.href = newChatUrl;
          return true;
          
        } catch(e) { 
          console.log('❌ خطأ عام في التحويل السريع: ' + e);
          return false; 
        }
        
        // دالة حقن الرسالة
        function injectMessage(msg) {
          console.log('💬 بدء حقن الرسالة: ' + msg.substring(0, 50) + '...');
          
          try {
            // البحث عن صندوق النص النشط
            const textBoxes = document.querySelectorAll('[contenteditable="true"]');
            if (!textBoxes || textBoxes.length === 0) {
              console.log('❌ لم يتم العثور على صندوق النص');
              return false;
            }
            
            const activeBox = textBoxes[textBoxes.length - 1];
            activeBox.focus();
            
            // تجربة طرق متعددة لحقن النص
            
            // الطريقة الأولى: استخدام clipboard simulation
            try {
              const dataTransfer = new DataTransfer();
              dataTransfer.setData('text/plain', msg);
              const pasteEvent = new ClipboardEvent('paste', {
                clipboardData: dataTransfer,
                bubbles: true,
                cancelable: true
              });
              activeBox.dispatchEvent(pasteEvent);
            } catch(e) {
              console.log('⚠️ فشل الطريقة الأولى، جاري التجربة الثانية');
            }
            
            // الطريقة الثانية: تعديل المحتوى مباشرة
            try {
              activeBox.textContent = msg;
              activeBox.dispatchEvent(new InputEvent('input', {
                data: msg,
                bubbles: true,
                cancelable: true
              }));
            } catch(e) {
              console.log('⚠️ فشل الطريقة الثانية');
            }
            
            // محاكاة ضغط Enter لإرسال الرسالة
            setTimeout(() => {
              const enterEvent = new KeyboardEvent('keydown', {
                key: 'Enter',
                code: 'Enter',
                which: 13,
                keyCode: 13,
                bubbles: true
              });
              activeBox.dispatchEvent(enterEvent);
              console.log('✅ تم إرسال الرسالة الجديدة');
            }, 300);
            
            return true;
            
          } catch(e) {
            console.log('❌ خطأ في حقن الرسالة: ' + e);
            return false;
          }
        }
      })();
    """;
  }

  /// فتح صفحة تحميل WebView2 Runtime
  void _launchWebView2Download() async {
    const url =
        'https://developer.microsoft.com/en-us/microsoft-edge/webview2/';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'تعذر فتح رابط التحميل. يرجى البحث عن "Microsoft Edge WebView2 Runtime" وتحميله من موقع مايكروسوفت الرسمي.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في فتح رابط التحميل: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'تعذر فتح رابط التحميل. يرجى البحث عن "Microsoft Edge WebView2 Runtime" وتحميله من موقع مايكروسوفت الرسمي.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// الانتقال لواجهة الواتساب الرئيسية (بدون محادثة محددة)
  void navigateToHome() {
    if (!mounted) return;

    debugPrint('🏠 الانتقال لواجهة الواتساب الرئيسية');

    setState(() {
      _currentPhone = '';
      _currentMessage = '';
      _messageSent = false;
      _isLoading = true;
    });

    const webUrl = 'https://web.whatsapp.com/';

    // تحميل واجهة الواتساب الرئيسية
    if (Platform.isWindows && _winController != null) {
      _winController!.loadUrl(webUrl);
    } else if (!Platform.isWindows && _controller != null) {
      _controller!.loadRequest(Uri.parse(webUrl));
    }

    _startStatusMonitoring();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // شريط العنوان
        Container(
          height: 60,
          decoration: const BoxDecoration(
            color: Color(0xFF25D366),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.chat, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Text(
                'واتساب ويب',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const Spacer(),
              // زر تصغير
              Container(
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon:
                      const Icon(Icons.minimize, color: Colors.white, size: 20),
                  onPressed: () {
                    widget.onMinimize();
                  },
                  tooltip: 'تصغير',
                ),
              ),
              // زر إغلاق
              Container(
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  onPressed: widget.onClose,
                  tooltip: 'إغلاق نهائي',
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        // محتوى الواجهة
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _error = null);
                      _initializeWebView();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                  if (Platform.isWindows && _error!.contains('WebView2')) ...[
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _launchWebView2Download,
                      icon: const Icon(Icons.download),
                      label: const Text('تحميل WebView2'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        // WebView
        if (Platform.isWindows && _winController != null)
          wvwin.Webview(_winController!)
        else if (!Platform.isWindows && _controller != null)
          WebViewWidget(controller: _controller!),

        // مؤشر التحميل
        if (_isLoading)
          Container(
            color: Colors.white.withValues(alpha: 0.9),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF25D366)),
                  SizedBox(height: 16),
                  Text('جاري تحميل واتساب ويب...'),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
