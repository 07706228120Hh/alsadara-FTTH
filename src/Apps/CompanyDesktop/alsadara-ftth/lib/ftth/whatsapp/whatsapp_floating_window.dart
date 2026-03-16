import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as wvwin;
import 'package:window_manager/window_manager.dart';

/// نافذة واتساب العائمة المستقلة
class WhatsAppFloatingWindow extends StatefulWidget {
  final String initialPhone;
  final String initialMessage;

  const WhatsAppFloatingWindow({
    super.key,
    required this.initialPhone,
    required this.initialMessage,
  });

  /// إنشاء نافذة عائمة جديدة
  static Future<void> createFloatingWindow({
    required String phone,
    required String message,
  }) async {
    try {
      debugPrint('🪟 إنشاء نافذة واتساب عائمة: $phone');

      // إنشاء نافذة جديدة
      await WindowManager.instance.setAlwaysOnTop(false);
      await WindowManager.instance.setSkipTaskbar(false);

      // تشغيل التطبيق في نافذة منفصلة
      runApp(
        MaterialApp(
          title: 'واتساب ويب',
          theme: ThemeData(
            primarySwatch: Colors.green,
            fontFamily: 'Arial',
          ),
          home: WhatsAppFloatingWindow(
            initialPhone: phone,
            initialMessage: message,
          ),
          debugShowCheckedModeBanner: false,
        ),
      );
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء النافذة العائمة');
      rethrow;
    }
  }

  @override
  State<WhatsAppFloatingWindow> createState() => _WhatsAppFloatingWindowState();
}

class _WhatsAppFloatingWindowState extends State<WhatsAppFloatingWindow>
    with WindowListener {
  static _WhatsAppFloatingWindowState? _instance;

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
    _instance = this;
    _currentPhone = widget.initialPhone;
    _currentMessage = widget.initialMessage;

    // إعداد النافذة
    _setupWindow();
    _checkSavedLoginState();
    _initializeWebView();

    windowManager.addListener(this);
  }

  @override
  void dispose() {
    _statusMonitor?.cancel();
    windowManager.removeListener(this);
    _instance = null;
    super.dispose();
  }

  Future<void> _setupWindow() async {
    try {
      await windowManager.ensureInitialized();

      WindowOptions windowOptions = const WindowOptions(
        size: Size(400, 600),
        minimumSize: Size(350, 500),
        center: false,
        backgroundColor: Colors.white,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
        title: 'واتساب ويب',
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
        // وضع النافذة في الزاوية اليمنى السفلى
        await windowManager.setPosition(const Offset(50, 50));
        await windowManager.setAlwaysOnTop(true);
      });
    } catch (e) {
      debugPrint('❌ خطأ في إعداد النافذة');
    }
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
      debugPrint('❌ خطأ في فحص حالة تسجيل الدخول');
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
      debugPrint('❌ خطأ في تهيئة WebView');
      setState(() {
        _error = 'خطأ في تحميل واتساب';
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeWindowsWebView() async {
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
      debugPrint('❌ خطأ في حفظ حالة الدخول');
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
        // فحص للـ Windows WebView - استخدام طريقة أبسط
        try {
          await _winController!.executeScript(
              'document.querySelector("[data-icon=\'msg-check\']") !== null');
          if (!_messageSent) {
            setState(() => _messageSent = true);
            _statusMonitor?.cancel();
            _showSuccessMessage();
          }
        } catch (e) {
          // تجاهل الخطأ واستمر في المحاولة
        }
      } else if (_controller != null) {
        // فحص للـ Flutter WebView
        final result = await _controller!.runJavaScriptReturningResult(
            'document.querySelector("[data-icon=\'msg-check\']") !== null');

        if (result.toString() == 'true' && !_messageSent) {
          setState(() => _messageSent = true);
          _statusMonitor?.cancel();
          _showSuccessMessage();
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في فحص حالة الإرسال');
    }
  }

  void _showSuccessMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ تم إرسال الرسالة بنجاح'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// دالة لإرسال رسالة جديدة من النافذة الرئيسية
  static bool sendNewMessage(String phone, String message) {
    if (_instance != null) {
      _instance!._sendNewMessageInternal(phone, message);
      return true;
    }
    return false;
  }

  /// فحص إذا كانت النافذة مفتوحة
  static bool isFloatingWindowOpen() {
    return _instance != null;
  }

  void _sendNewMessageInternal(String phone, String message) {
    if (!mounted) return;

    debugPrint('📨 إرسال رسالة جديدة: $phone');

    setState(() {
      _currentPhone = phone;
      _currentMessage = message;
      _messageSent = false;
      _isLoading = true;
    });

    final encodedMessage = Uri.encodeComponent(message);
    final webUrl =
        'https://web.whatsapp.com/send?phone=$phone&text=$encodedMessage';

    // إعادة تحميل الصفحة برسالة جديدة
    if (Platform.isWindows && _winController != null) {
      _winController!.loadUrl(webUrl);
    } else if (!Platform.isWindows && _controller != null) {
      _controller!.loadRequest(Uri.parse(webUrl));
    }

    _startStatusMonitoring();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('واتساب ويب', style: TextStyle(fontSize: 16)),
        backgroundColor: const Color(0xFF25D366),
        foregroundColor: Colors.white,
        elevation: 1,
        toolbarHeight: 40,
        actions: [
          // زر تصغير النافذة
          IconButton(
            icon: const Icon(Icons.minimize, size: 16),
            onPressed: () => windowManager.minimize(),
            tooltip: 'تصغير',
          ),
          // زر إغلاق النافذة
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => windowManager.close(),
            tooltip: 'إغلاق',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() => _error = null);
                _initializeWebView();
              },
              child: const Text('إعادة المحاولة'),
            ),
          ],
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
            color: Colors.white,
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

        // شريط حالة الرسالة
        if (_messageSent)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.green.withValues(alpha: 0.9),
              child: const Text(
                '✅ تم إرسال الرسالة بنجاح',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}
