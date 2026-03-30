/// صفحة الشركة - عرض لوحة تحكم admin.ftth.iq في WebView
/// تسجيل الدخول التلقائي باستخدام بيانات المستخدم الميداني
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import '../../services/company_settings_service.dart';
import '../../services/custom_auth_service.dart';
import '../../services/vps_auth_service.dart';

class FtthCompanyPage extends StatefulWidget {
  const FtthCompanyPage({super.key});

  @override
  State<FtthCompanyPage> createState() => _FtthCompanyPageState();
}

class _FtthCompanyPageState extends State<FtthCompanyPage> {
  final WebviewController _controller = WebviewController();
  bool _isInitialized = false;
  bool _isLoading = true;
  bool _autoLoginDone = false;
  String _currentUrl = '';

  static const String _loginUrl = 'https://admin.ftth.iq/auth/login';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _initWebView() async {
    if (!Platform.isWindows) return;

    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.white);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      // متابعة الرابط الحالي
      _controller.url.listen((url) {
        if (!mounted) return;
        _currentUrl = url;
      });

      // عند اكتمال تحميل الصفحة → محاولة الدخول التلقائي
      _controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() => _isLoading = state == LoadingState.loading);

        if (state == LoadingState.navigationCompleted &&
            !_autoLoginDone &&
            _currentUrl.contains('/auth/login')) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !_autoLoginDone) _tryAutoLogin();
          });
        }
      });

      // استماع لرسائل من الـ WebView
      _controller.webMessage.listen((message) {
        if (!mounted) return;
        final msg = message.toString();
        if (msg.startsWith('AUTO_LOGIN:SUCCESS')) {
          debugPrint('🏢 صفحة الشركة: تسجيل دخول تلقائي ناجح');
          _autoLoginDone = true;
        } else if (msg.startsWith('AUTO_LOGIN:FAIL')) {
          debugPrint('🏢 صفحة الشركة: فشل الدخول التلقائي - $msg');
          _autoLoginDone = true; // لا نعيد المحاولة
        }
      });

      await _controller.loadUrl(_loginUrl);

      if (mounted) setState(() => _isInitialized = true);
    } catch (_) {}
  }

  /// محاولة تسجيل دخول تلقائي ببيانات المستخدم الميداني
  Future<void> _tryAutoLogin() async {
    try {
      final tenantId = VpsAuthService.instance.currentCompanyId ??
          CustomAuthService().currentTenantId;
      debugPrint('🏢 صفحة الشركة: tenantId=$tenantId');

      if (tenantId == null) return;

      final fieldUser =
          await CompanySettingsService.getFieldUser(tenantId: tenantId);
      if (fieldUser == null) {
        debugPrint('🏢 صفحة الشركة: لا يوجد مستخدم ميداني - دخول يدوي');
        return;
      }

      debugPrint('🏢 صفحة الشركة: بدء دخول تلقائي بـ ${fieldUser.username}');
      _autoLoginDone = true;

      final jsCode = '''
        (async function() {
          try {
            localStorage.clear();
            sessionStorage.clear();
            const resp = await fetch('/api/auth/Contractor/token', {
              method: 'POST',
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json, text/plain, */*',
                'x-client-app': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
                'x-user-role': '0'
              },
              body: 'username=${_escapeJs(fieldUser.username)}&password=${_escapeJs(fieldUser.password)}&grant_type=password'
            });
            const data = await resp.json();
            if (data && data.access_token) {
              localStorage.setItem('access_token', data.access_token);
              localStorage.setItem('refresh_token', data.refresh_token || '');
              localStorage.setItem('token', JSON.stringify(data));
              localStorage.setItem('currentUser', JSON.stringify(data));
              window.chrome.webview.postMessage('AUTO_LOGIN:SUCCESS');
              window.location.href = '/';
            } else {
              window.chrome.webview.postMessage('AUTO_LOGIN:FAIL:' + (data.error_description || 'unknown'));
            }
          } catch(e) {
            window.chrome.webview.postMessage('AUTO_LOGIN:FAIL:' + e.message);
          }
        })();
      ''';

      await _controller.executeScript(jsCode);
    } catch (e) {
      debugPrint('🏢 صفحة الشركة: خطأ في الدخول التلقائي: $e');
    }
  }

  /// تنظيف النص لحقنه في JavaScript بأمان
  String _escapeJs(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          toolbarHeight: 44,
          titleSpacing: 0,
          title: const Text('صفحة الشركة',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'تحديث',
              onPressed: () {
                if (_isInitialized) _controller.reload();
              },
            ),
            IconButton(
              icon: const Icon(Icons.home, size: 20),
              tooltip: 'الصفحة الرئيسية',
              onPressed: () {
                if (_isInitialized) {
                  _controller.loadUrl('https://admin.ftth.iq/');
                }
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            if (_isLoading)
              const LinearProgressIndicator(color: Color(0xFF1A237E)),
            Expanded(
              child: _isInitialized
                  ? Webview(_controller)
                  : const Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
    );
  }
}
