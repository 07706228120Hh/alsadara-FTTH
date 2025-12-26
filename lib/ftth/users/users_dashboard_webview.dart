/// اسم الصفحة: عرض داشبورد المستخدمين
/// وصف الصفحة: عرض Dashboard 7 (بيانات المستخدمين) في WebView
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart' as wvwin;
import 'package:url_launcher/url_launcher.dart';

class UsersDashboardWebView extends StatefulWidget {
  final String authToken;
  const UsersDashboardWebView({super.key, required this.authToken});

  @override
  State<UsersDashboardWebView> createState() => _UsersDashboardWebViewState();
}

class _UsersDashboardWebViewState extends State<UsersDashboardWebView> {
  wvwin.WebviewController? _controller;
  bool _isLoading = true;
  bool _isInitialized = false;
  String _currentUrl = ''; // ignore: unused_field
  String _pageTitle = 'جاري التحميل...';
  double _loadingProgress = 0; // ignore: unused_field

  // Dashboard URL
  static const String _dashboardBaseUrl = 'https://dashboard.ftth.iq';

  String get _dashboardUrl {
    // استخدام رابط الداشبورد من admin portal
    if (widget.authToken.isNotEmpty) {
      return 'https://admin.ftth.iq/dashboard?Authorization=${widget.authToken}';
    }
    return 'https://admin.ftth.iq/dashboard';
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      _initWebView();
    }
  }

  Future<void> _initWebView() async {
    try {
      debugPrint('🌐 بدء تهيئة WebView...');
      debugPrint('🔗 الرابط المستهدف: $_dashboardUrl');

      final controller = wvwin.WebviewController();
      await controller.initialize();

      // إعدادات WebView
      await controller.setBackgroundColor(Colors.white);
      await controller
          .setPopupWindowPolicy(wvwin.WebviewPopupWindowPolicy.deny);

      // الاستماع للأحداث
      controller.url.listen((url) {
        debugPrint('🔄 URL تغير إلى: $url');
        if (mounted) {
          setState(() {
            _currentUrl = url;
          });
          // طباعة معلومات الصفحة عند التغيير
          _logPageInfo();
        }
      });

      controller.loadingState.listen((state) {
        debugPrint('📊 حالة التحميل: $state');
        if (mounted) {
          setState(() {
            _isLoading = state == wvwin.LoadingState.loading;
            if (state == wvwin.LoadingState.navigationCompleted) {
              _loadingProgress = 1.0;
              _updatePageTitle();
              // طباعة معلومات مفصلة عند اكتمال التحميل
              _logPageDetails();
            }
          });
        }
      });

      // تحميل الداشبورد
      debugPrint('🚀 جاري تحميل: $_dashboardUrl');
      await controller.loadUrl(_dashboardUrl);

      if (mounted) {
        setState(() {
          _controller = controller;
          _isInitialized = true;
        });
        debugPrint('✅ تم تهيئة WebView بنجاح');
      }
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة WebView: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showError('فشل في تحميل الصفحة: $e');
      }
    }
  }

  /// طباعة معلومات الصفحة الأساسية
  Future<void> _logPageInfo() async {
    if (_controller == null) return;
    try {
      final url = await _controller!.executeScript('window.location.href');
      debugPrint('📍 URL الحالي: $url');
    } catch (e) {
      debugPrint('⚠️ خطأ في جلب URL: $e');
    }
  }

  /// طباعة تفاصيل الصفحة والـ cookies
  Future<void> _logPageDetails() async {
    if (_controller == null) return;

    try {
      // جلب العنوان
      final title = await _controller!.executeScript('document.title');
      debugPrint('📄 عنوان الصفحة: $title');

      // جلب الـ cookies
      final cookies = await _controller!.executeScript('document.cookie');
      debugPrint('🍪 Cookies: $cookies');

      // جلب الـ URL الكامل
      final fullUrl = await _controller!.executeScript('window.location.href');
      debugPrint('🔗 URL الكامل: $fullUrl');

      // محاولة جلب أي بيانات JSON في الصفحة
      final bodyText = await _controller!.executeScript('''
        (function() {
          try {
            var pre = document.querySelector('pre');
            if (pre) return pre.innerText.substring(0, 500);
            return document.body.innerText.substring(0, 500);
          } catch(e) { return 'Error: ' + e; }
        })()
      ''');
      debugPrint('📝 محتوى الصفحة (أول 500 حرف): $bodyText');

      // التحقق من وجود خطأ
      final hasError = await _controller!.executeScript('''
        document.body.innerText.includes('error') || 
        document.body.innerText.includes('Error') ||
        document.body.innerText.includes('404') ||
        document.body.innerText.includes('403')
      ''');
      debugPrint('⚠️ هل يوجد خطأ في الصفحة: $hasError');
    } catch (e) {
      debugPrint('⚠️ خطأ في جلب تفاصيل الصفحة: $e');
    }
  }

  Future<void> _updatePageTitle() async {
    if (_controller == null) return;
    try {
      final title = await _controller!.executeScript('document.title');
      if (title != null && mounted) {
        setState(() {
          _pageTitle = title.toString().replaceAll('"', '');
        });
      }
    } catch (_) {}
  }

  Future<void> _refresh() async {
    if (_controller != null) {
      await _controller!.reload();
    }
  }

  Future<void> _openInBrowser() async {
    final url = Uri.parse(_dashboardUrl);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _showError('فشل في فتح المتصفح: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // إذا لم يكن Windows، عرض رسالة
    if (!Platform.isWindows) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('بيانات المستخدمين'),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.computer, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'هذه الميزة متاحة فقط على Windows',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('فتح في المتصفح'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'بيانات المستخدمين',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (_pageTitle.isNotEmpty && !_pageTitle.contains('moment'))
              Text(
                _pageTitle,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          // زر تحديث
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: _refresh,
          ),
          // زر فتح في المتصفح
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'فتح في المتصفح',
            onPressed: _openInBrowser,
          ),
          // زر الرجوع للخلف
          if (_controller != null)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'رجوع',
              onPressed: () async {
                await _controller!.goBack();
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          // WebView
          if (_isInitialized && _controller != null)
            wvwin.Webview(
              _controller!,
              permissionRequested: (url, kind, isUserInitiated) =>
                  wvwin.WebviewPermissionDecision.allow,
            )
          else if (!_isInitialized)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('جاري تحميل الداشبورد...'),
                ],
              ),
            ),

          // شريط التحميل
          if (_isLoading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                backgroundColor: Colors.indigo.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigo),
              ),
            ),

          // رسالة Cloudflare
          if (_pageTitle.contains('moment'))
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.orange[100],
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.security, color: Colors.orange[800]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'جاري التحقق من Cloudflare... انتظر قليلاً',
                        style: TextStyle(color: Colors.orange[900]),
                      ),
                    ),
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
