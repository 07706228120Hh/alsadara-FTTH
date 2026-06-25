/// واجهة حلّ تحدّي Cloudflare (إنسان-في-الحلقة) — Windows + Android/iOS
///
/// تظهر عند فتح صفحة الوكيل قبل الدخول التلقائي. يضغط المشغّل على مربع «التحقق
/// من أنك إنسان»؛ بعدها نقرأ كوكي cf_clearance (HttpOnly) ونثبّت الحقن في كل
/// طلبات admin.ftth.iq، ثم تُغلق النافذة ويُكمل الدخول التلقائي.
///
/// - Windows: webview_windows + getCookies (DevTools).
/// - Android/iOS: webview_flutter + webview_cookie_manager (CookieManager الأصلي).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_windows/webview_windows.dart' as wvwin;
import 'package:webview_flutter/webview_flutter.dart' as wvm;
import 'package:webview_cookie_manager/webview_cookie_manager.dart';
import '../../services/ftth_cf_clearance.dart';

class CloudflareGateDialog extends StatefulWidget {
  const CloudflareGateDialog({super.key});

  static bool get supported =>
      Platform.isWindows || Platform.isAndroid || Platform.isIOS;

  /// يضمن وجود cf_clearance صالح. يعيد true عند الجاهزية.
  static Future<bool> ensure(BuildContext context) async {
    if (!supported) return true;
    if (await _probeOk()) return true;
    if (!context.mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CloudflareGateDialog(),
    );
    return result ?? false;
  }

  /// فحص سريع: هل تمرّ طلبات admin.ftth.iq دون 403 (تحدّي)؟
  static Future<bool> _probeOk() async {
    try {
      final r = await http
          .get(Uri.parse(
              '${FtthCfClearance.origin}/api/auth/Contractor/refresh'))
          .timeout(const Duration(seconds: 12));
      return r.statusCode != 403;
    } catch (_) {
      return false;
    }
  }

  @override
  State<CloudflareGateDialog> createState() => _CloudflareGateDialogState();
}

class _CloudflareGateDialogState extends State<CloudflareGateDialog> {
  wvwin.WebviewController? _winController;
  wvm.WebViewController? _mobileController;
  bool _initialized = false;
  Timer? _poll;
  bool _checking = false;
  bool _done = false;
  String _status = 'جاري تحميل صفحة التحقق...';

  bool get _isWindows => Platform.isWindows;

  @override
  void initState() {
    super.initState();
    if (_isWindows) {
      _initWindows();
    } else {
      _initMobile();
    }
  }

  // ============ Windows ============
  Future<void> _initWindows() async {
    try {
      final c = wvwin.WebviewController();
      await c.initialize();
      await c.setUserAgent(FtthCfClearance.userAgentString);
      await c.setBackgroundColor(Colors.white);
      await c.setPopupWindowPolicy(wvwin.WebviewPopupWindowPolicy.deny);
      await c.loadUrl('${FtthCfClearance.origin}/auth/login');
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _winController = c;
        _initialized = true;
        _status = 'اضغط على مربع «التحقق من أنك إنسان» وانتظر';
      });
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _checkWindows());
    } catch (e) {
      if (mounted) setState(() => _status = 'تعذّر تحميل صفحة التحقق: $e');
    }
  }

  Future<void> _checkWindows() async {
    if (_checking || _done || !mounted || _winController == null) return;
    _checking = true;
    try {
      final raw = await _winController!.getCookies();
      await _applyIfCleared(_extractFromDevtoolsJson(raw));
    } catch (_) {
    } finally {
      _checking = false;
    }
  }

  // ============ Android / iOS ============
  Future<void> _initMobile() async {
    try {
      final c = wvm.WebViewController()
        ..setJavaScriptMode(wvm.JavaScriptMode.unrestricted)
        ..setUserAgent(FtthCfClearance.userAgentString)
        ..setBackgroundColor(Colors.white);
      await c.loadRequest(Uri.parse('${FtthCfClearance.origin}/auth/login'));
      if (!mounted) return;
      setState(() {
        _mobileController = c;
        _initialized = true;
        _status = 'اضغط على مربع «التحقق من أنك إنسان» وانتظر';
      });
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _checkMobile());
    } catch (e) {
      if (mounted) setState(() => _status = 'تعذّر تحميل صفحة التحقق: $e');
    }
  }

  Future<void> _checkMobile() async {
    if (_checking || _done || !mounted) return;
    _checking = true;
    try {
      final cookies =
          await WebviewCookieManager().getCookies(FtthCfClearance.origin);
      await _applyIfCleared(_extractFromIoCookies(cookies));
    } catch (_) {
    } finally {
      _checking = false;
    }
  }

  // ============ مشترك ============
  Future<void> _applyIfCleared(String? cookieHeader) async {
    if (cookieHeader == null) return;
    FtthCfClearance.instance.update(cookieHeader);
    final ok = await CloudflareGateDialog._probeOk();
    debugPrint(
        '🍪 [CF] cf_clearance captured (${cookieHeader.length} chars), probe=$ok');
    if (ok && mounted) {
      _done = true;
      _poll?.cancel();
      Navigator.of(context).pop(true);
    }
  }

  bool _isCfCookie(String name) =>
      name == 'cf_clearance' || name.startsWith('cf_') || name.startsWith('__cf');

  /// من DevTools Network.getAllCookies (Windows)
  String? _extractFromDevtoolsJson(String rawJson) {
    if (rawJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(rawJson);
      final list = (decoded is Map ? decoded['cookies'] : null);
      if (list is! List) return null;
      final parts = <String>[];
      bool hasClearance = false;
      for (final c in list) {
        if (c is! Map) continue;
        final name = (c['name'] ?? '').toString();
        final value = (c['value'] ?? '').toString();
        final domain = (c['domain'] ?? '').toString().toLowerCase();
        if (!domain.contains('ftth.iq') || !_isCfCookie(name)) continue;
        if (name == 'cf_clearance' && value.isNotEmpty) hasClearance = true;
        parts.add('$name=$value');
      }
      return hasClearance ? parts.join('; ') : null;
    } catch (_) {
      return null;
    }
  }

  /// من webview_cookie_manager (Android/iOS) — List<Cookie>
  String? _extractFromIoCookies(List<Cookie> cookies) {
    final parts = <String>[];
    bool hasClearance = false;
    for (final c in cookies) {
      final domain = (c.domain ?? '').toLowerCase();
      if (!domain.contains('ftth.iq') || !_isCfCookie(c.name)) continue;
      if (c.name == 'cf_clearance' && c.value.isNotEmpty) hasClearance = true;
      parts.add('${c.name}=${c.value}');
    }
    return hasClearance ? parts.join('; ') : null;
  }

  @override
  void dispose() {
    _poll?.cancel();
    _winController?.dispose();
    super.dispose();
  }

  Widget _buildWebView() {
    if (_isWindows) {
      if (_winController != null && _winController!.value.isInitialized) {
        return wvwin.Webview(
          _winController!,
          permissionRequested: (url, kind, isUserInitiated) =>
              wvwin.WebviewPermissionDecision.allow,
        );
      }
    } else if (_mobileController != null) {
      return wvm.WebViewWidget(controller: _mobileController!);
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(_status, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 560,
        height: 620,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.indigo,
              child: Row(
                children: [
                  const Icon(Icons.verified_user, color: Colors.white),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'التحقق الأمني — اضغط على مربع «التحقق من أنك إنسان»',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'إلغاء',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: Colors.amber[50],
              padding: const EdgeInsets.all(10),
              child: const Text(
                'بعد إتمام التحقق ستُغلق هذه النافذة تلقائياً ويُكمل التطبيق الدخول.',
                style: TextStyle(fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(child: _buildWebView()),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('بانتظار إتمام التحقق...'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
