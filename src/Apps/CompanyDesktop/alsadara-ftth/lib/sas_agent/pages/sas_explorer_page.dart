import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../widgets/sas_state_views.dart';

/// مستكشف SAS — يعرض لوحة الساس المدمجة لعنوان خادم الحساب المحدّد داخل
/// التطبيق عبر `webview_windows` (النسخة المبسّطة: عرض اللوحة).
///
/// ملاحظة أمنية: لا يُحقن أي سرّ في الصفحة؛ يفتح لوحة الساس ليسجّل الوكيل
/// دخوله بنفسه (اعتماده لا يمرّ عبر الواجهة). على غير ويندوز يُتاح فتح
/// اللوحة في المتصفّح النظامي.
class SasExplorerPage extends StatefulWidget {
  final SasAccount account;
  const SasExplorerPage({super.key, required this.account});

  @override
  State<SasExplorerPage> createState() => _SasExplorerPageState();
}

class _SasExplorerPageState extends State<SasExplorerPage> {
  final WebviewController _controller = WebviewController();
  bool _isInitialized = false;
  bool _isLoading = true;
  String? _initError;

  /// عنوان اللوحة: عنوان خادم الحساب كما هو (بلا سرّ)، مع بروتوكول افتراضي.
  String get _panelUrl {
    var url = widget.account.serverUrl.trim();
    if (url.isEmpty) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    return url;
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) _initWebView();
  }

  @override
  void dispose() {
    if (_isInitialized) _controller.dispose();
    super.dispose();
  }

  Future<void> _initWebView() async {
    final url = _panelUrl;
    if (url.isEmpty) {
      setState(() {
        _initError = 'لا يوجد عنوان خادم لهذا الحساب';
        _isLoading = false;
      });
      return;
    }
    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.white);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      _controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() => _isLoading = state == LoadingState.loading);
      });

      await _controller.loadUrl(url);
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = e.toString().replaceFirst('Exception: ', '').trim();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openInBrowser() async {
    final url = _panelUrl;
    if (url.isEmpty) return;
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', url]);
      } else {
        await Process.start('xdg-open', [url]);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          elevation: 0,
          toolbarHeight: 56,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.blueGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('مستكشف الساس',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              Text(widget.account.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.78))),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'فتح في المتصفّح',
              onPressed: _openInBrowser,
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
            ),
            if (Platform.isWindows)
              IconButton(
                tooltip: 'تحديث',
                onPressed: () {
                  if (_isInitialized) _controller.reload();
                },
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (!Platform.isWindows) {
      return SasEmptyView(
        message:
            'عرض لوحة الساس المدمج متاح على سطح مكتب ويندوز.\nيمكنك فتحها في المتصفّح.',
        icon: Icons.desktop_windows_rounded,
        action: FilledButton.icon(
          onPressed: _openInBrowser,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          ),
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text('فتح لوحة الساس',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        ),
      );
    }
    if (_initError != null) {
      return SasErrorView(message: _initError!, onRetry: _initWebView);
    }
    return Column(
      children: [
        if (_isLoading)
          const LinearProgressIndicator(color: AppTheme.primaryColor),
        Expanded(
          child: _isInitialized
              ? Webview(_controller)
              : const SasLoadingView(message: 'جاري فتح لوحة الساس…'),
        ),
      ],
    );
  }
}
