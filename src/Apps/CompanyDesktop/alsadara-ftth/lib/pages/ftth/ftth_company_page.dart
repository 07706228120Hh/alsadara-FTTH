/// صفحة الشركة - عرض لوحة تحكم admin.ftth.iq في WebView
/// المستخدم يسجل الدخول يدوياً
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

class FtthCompanyPage extends StatefulWidget {
  const FtthCompanyPage({super.key});

  @override
  State<FtthCompanyPage> createState() => _FtthCompanyPageState();
}

class _FtthCompanyPageState extends State<FtthCompanyPage> {
  final WebviewController _controller = WebviewController();
  bool _isInitialized = false;
  bool _isLoading = true;

  static const String _loginUrl = 'https://admin.ftth.iq/auth/login';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initWebView() async {
    if (!Platform.isWindows) return;

    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.white);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      _controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() => _isLoading = state == LoadingState.loading);
      });

      await _controller.loadUrl(_loginUrl);

      if (mounted) setState(() => _isInitialized = true);
    } catch (_) {}
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
