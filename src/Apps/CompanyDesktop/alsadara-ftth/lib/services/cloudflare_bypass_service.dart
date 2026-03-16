/// خدمة تجاوز حماية Cloudflare
/// تستخدم WebView لجلب الـ cookies اللازمة لتجاوز تحدي Cloudflare
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart' as wvwin;
import 'package:shared_preferences/shared_preferences.dart';

class CloudflareBypassService {
  static final CloudflareBypassService _instance =
      CloudflareBypassService._internal();
  factory CloudflareBypassService() => _instance;
  CloudflareBypassService._internal();

  static CloudflareBypassService get instance => _instance;

  // حالة التجاوز
  final bool _isInitialized = false;
  bool _isBypassing = false;
  String? _cfClearance;
  String? _cfBm;
  Map<String, String> _cookies = {};
  DateTime? _lastBypassTime;

  // مدة صلاحية الـ cookies (30 دقيقة)
  static const Duration _cookieValidity = Duration(minutes: 30);

  /// التحقق مما إذا كانت الـ cookies صالحة
  bool get hasValidCookies {
    if (_cfClearance == null || _lastBypassTime == null) return false;
    return DateTime.now().difference(_lastBypassTime!) < _cookieValidity;
  }

  /// الحصول على الـ cookies المخزنة
  Map<String, String> get cookies => Map.from(_cookies);

  /// الحصول على cookie string للاستخدام في الـ headers
  String get cookieString {
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// تحميل الـ cookies المحفوظة
  Future<void> loadSavedCookies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCookies = prefs.getString('cf_bypass_cookies');
      final savedTime = prefs.getInt('cf_bypass_time');

      if (savedCookies != null && savedTime != null) {
        final savedDateTime = DateTime.fromMillisecondsSinceEpoch(savedTime);
        if (DateTime.now().difference(savedDateTime) < _cookieValidity) {
          // الـ cookies لا تزال صالحة
          _parseCookieString(savedCookies);
          _lastBypassTime = savedDateTime;
          debugPrint('✅ تم تحميل cookies محفوظة صالحة');
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل cookies');
    }
  }

  /// حفظ الـ cookies
  Future<void> _saveCookies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cf_bypass_cookies', cookieString);
      await prefs.setInt(
          'cf_bypass_time', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('❌ خطأ في حفظ cookies');
    }
  }

  void _parseCookieString(String cookieStr) {
    _cookies.clear();
    final parts = cookieStr.split('; ');
    for (var part in parts) {
      final eqIdx = part.indexOf('=');
      if (eqIdx > 0) {
        final key = part.substring(0, eqIdx);
        final value = part.substring(eqIdx + 1);
        _cookies[key] = value;
        if (key == 'cf_clearance') _cfClearance = value;
        if (key == '__cf_bm') _cfBm = value;
      }
    }
  }

  /// تجاوز Cloudflare باستخدام WebView (Windows فقط حالياً)
  Future<bool> bypassCloudflare(BuildContext context, String targetUrl) async {
    if (!Platform.isWindows) {
      debugPrint('⚠️ تجاوز Cloudflare متاح فقط على Windows حالياً');
      return false;
    }

    if (_isBypassing) {
      debugPrint('⏳ عملية تجاوز جارية بالفعل...');
      return false;
    }

    // التحقق من الـ cookies المحفوظة أولاً
    await loadSavedCookies();
    if (hasValidCookies) {
      debugPrint('✅ استخدام cookies محفوظة صالحة');
      return true;
    }

    _isBypassing = true;

    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _CloudflareBypassDialog(
          targetUrl: targetUrl,
          onCookiesObtained: (cookies) {
            _cookies = cookies;
            _cfClearance = cookies['cf_clearance'];
            _cfBm = cookies['__cf_bm'];
            _lastBypassTime = DateTime.now();
            _saveCookies();
          },
        ),
      );

      return result ?? false;
    } finally {
      _isBypassing = false;
    }
  }

  /// مسح الـ cookies
  Future<void> clearCookies() async {
    _cookies.clear();
    _cfClearance = null;
    _cfBm = null;
    _lastBypassTime = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cf_bypass_cookies');
      await prefs.remove('cf_bypass_time');
    } catch (_) {}
  }
}

/// Dialog لعرض WebView وتجاوز Cloudflare
class _CloudflareBypassDialog extends StatefulWidget {
  final String targetUrl;
  final Function(Map<String, String>) onCookiesObtained;

  const _CloudflareBypassDialog({
    required this.targetUrl,
    required this.onCookiesObtained,
  });

  @override
  State<_CloudflareBypassDialog> createState() =>
      _CloudflareBypassDialogState();
}

class _CloudflareBypassDialogState extends State<_CloudflareBypassDialog> {
  wvwin.WebviewController? _controller;
  bool _isLoading = true;
  bool _isSuccess = false;
  String _status = 'جاري تحميل الصفحة...';
  Timer? _checkTimer;
  int _checkCount = 0;
  static const int _maxChecks = 30; // 30 ثانية كحد أقصى

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      final controller = wvwin.WebviewController();
      await controller.initialize();
      await controller.setBackgroundColor(Colors.white);

      // تحميل صفحة Dashboard
      await controller.loadUrl(widget.targetUrl);

      if (mounted) {
        setState(() {
          _controller = controller;
          _isLoading = false;
        });
      }

      // بدء فحص دوري للتحقق من تجاوز Cloudflare
      _startCheckTimer();
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة WebView');
      if (mounted) {
        setState(() {
          _status = 'فشل في تحميل الصفحة';
          _isLoading = false;
        });
      }
    }
  }

  void _startCheckTimer() {
    _checkTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _checkCount++;

      if (_checkCount > _maxChecks) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _status = 'انتهت مهلة التحقق. حاول مرة أخرى.';
          });
        }
        return;
      }

      await _checkBypassStatus();
    });
  }

  Future<void> _checkBypassStatus() async {
    if (_controller == null || _isSuccess) return;

    try {
      // الحصول على الـ cookies من WebView
      final cookiesJs = '''
        (function() {
          return document.cookie;
        })();
      ''';

      final result = await _controller!.executeScript(cookiesJs);
      final cookieStr = result?.toString() ?? '';

      debugPrint('🍪 Cookies: $cookieStr');

      // التحقق من وجود cf_clearance
      if (cookieStr.contains('cf_clearance')) {
        // نجح التجاوز!
        final cookies = _parseCookies(cookieStr);

        if (mounted) {
          setState(() {
            _isSuccess = true;
            _status = '✅ تم تجاوز Cloudflare بنجاح!';
          });
        }

        widget.onCookiesObtained(cookies);

        _checkTimer?.cancel();

        // إغلاق الـ dialog بعد ثانية
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        // التحقق من حالة الصفحة
        final titleJs = 'document.title';
        final title = await _controller!.executeScript(titleJs);

        if (title != null && !title.toString().contains('moment')) {
          // الصفحة تحملت لكن بدون cf_clearance
          if (mounted) {
            setState(() {
              _status = 'جاري التحقق... (${_checkCount}s)';
            });
          }
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في فحص الحالة');
    }
  }

  Map<String, String> _parseCookies(String cookieStr) {
    final cookies = <String, String>{};
    final parts = cookieStr.split('; ');
    for (var part in parts) {
      final eqIdx = part.indexOf('=');
      if (eqIdx > 0) {
        final key = part.substring(0, eqIdx);
        final value = part.substring(eqIdx + 1);
        cookies[key] = value;
      }
    }
    return cookies;
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isSuccess ? Icons.check_circle : Icons.security,
            color: _isSuccess ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          const Text('تجاوز حماية Cloudflare'),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            // شريط الحالة
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isSuccess ? Colors.green[50] : Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (!_isSuccess && _isLoading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      _isSuccess ? Icons.check : Icons.info_outline,
                      color: _isSuccess ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _status,
                      style: TextStyle(
                        color:
                            _isSuccess ? Colors.green[800] : Colors.orange[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // WebView
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: _controller != null
                    ? wvwin.Webview(_controller!)
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
            const SizedBox(height: 12),
            // تعليمات
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'إذا ظهر تحدي Cloudflare، انتظر حتى يتم التحقق تلقائياً.\n'
                'أو قم بحل التحدي يدوياً إذا طُلب منك.',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        if (_isSuccess)
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('متابعة'),
          ),
      ],
    );
  }
}
