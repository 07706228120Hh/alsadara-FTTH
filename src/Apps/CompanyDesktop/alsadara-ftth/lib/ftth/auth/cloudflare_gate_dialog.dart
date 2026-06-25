/// واجهة حلّ تحدّي Cloudflare (إنسان-في-الحلقة)
///
/// تظهر عند فتح صفحة الوكيل قبل الدخول التلقائي. تعرض WebView واحداً (يُتلف بعد
/// الحل، فلا يبقى أي متحكم حيّ → لا تعارض مع WebViews الأخرى). يضغط المشغّل على
/// مربع «التحقق من أنك إنسان»؛ بعدها نقرأ كوكي cf_clearance عبر getCookies ونثبّت
/// الحقن في كل طلبات admin.ftth.iq، ثم تُغلق النافذة ويُكمل الدخول التلقائي.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_windows/webview_windows.dart';
import '../../services/ftth_cf_clearance.dart';

class CloudflareGateDialog extends StatefulWidget {
  const CloudflareGateDialog({super.key});

  /// يضمن وجود cf_clearance صالح. يعيد true عند الجاهزية.
  /// إن كانت الجلسة مُجازة مسبقاً يعود فوراً دون إظهار نافذة.
  static Future<bool> ensure(BuildContext context) async {
    if (!Platform.isWindows) return true; // البوابة لـ Windows فقط حالياً
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
          .get(Uri.parse('${FtthCfClearance.origin}/api/auth/Contractor/refresh'))
          .timeout(const Duration(seconds: 12));
      // 403 = تحدّي Cloudflare؛ أي شيء آخر (400/401/405...) = وصلنا للخادم
      return r.statusCode != 403;
    } catch (_) {
      return false;
    }
  }

  @override
  State<CloudflareGateDialog> createState() => _CloudflareGateDialogState();
}

class _CloudflareGateDialogState extends State<CloudflareGateDialog> {
  WebviewController? _controller;
  bool _initialized = false;
  Timer? _poll;
  bool _checking = false;
  bool _done = false;
  String _status = 'جاري تحميل صفحة التحقق...';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    if (!Platform.isWindows) return;
    try {
      final c = WebviewController();
      await c.initialize();
      await c.setUserAgent(FtthCfClearance.userAgentString);
      await c.setBackgroundColor(Colors.white);
      await c.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await c.loadUrl('${FtthCfClearance.origin}/auth/login');
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _initialized = true;
        _status = 'اضغط على مربع «التحقق من أنك إنسان» وانتظر';
      });
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    } catch (e) {
      if (mounted) setState(() => _status = 'تعذّر تحميل صفحة التحقق: $e');
    }
  }

  Future<void> _check() async {
    if (_checking || _done || !mounted || _controller == null) return;
    _checking = true;
    try {
      final raw = await _controller!.getCookies();
      final cookieHeader = _extractCfCookies(raw);
      if (cookieHeader != null) {
        // ثبّت الحقن ثم تأكد عبر مسبار حقيقي
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
    } catch (_) {
      // تجاهل — أعد المحاولة
    } finally {
      _checking = false;
    }
  }

  /// يستخرج كوكيز Cloudflare (cf_clearance وما شابه) لنطاق ftth.iq كترويسة Cookie
  String? _extractCfCookies(String rawJson) {
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
        if (!domain.contains('ftth.iq')) continue;
        final isCf = name == 'cf_clearance' ||
            name.startsWith('cf_') ||
            name.startsWith('__cf');
        if (!isCf) continue;
        if (name == 'cf_clearance' && value.isNotEmpty) hasClearance = true;
        parts.add('$name=$value');
      }
      if (!hasClearance) return null; // لم يُحلّ التحدّي بعد
      return parts.join('; ');
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _controller?.dispose();
    super.dispose();
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
            Expanded(
              child: (_initialized &&
                      _controller != null &&
                      _controller!.value.isInitialized)
                  ? Webview(
                      _controller!,
                      permissionRequested: (url, kind, isUserInitiated) =>
                          WebviewPermissionDecision.allow,
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(_status, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
            ),
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
