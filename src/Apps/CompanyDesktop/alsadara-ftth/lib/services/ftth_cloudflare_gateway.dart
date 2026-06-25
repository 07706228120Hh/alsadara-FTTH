/// بوابة Cloudflare لـ FTTH
///
/// المشكلة: وضع المزوّد تحدّي Cloudflare (`Cf-Mitigated: challenge`) على كامل
/// نطاق `admin.ftth.iq/api` — فتُحجب كل طلبات مكتبة `http` بـ 403.
///
/// الحل (إنسان-في-الحلقة): WebView واحد دائم (WebView2 على Windows). يحلّ
/// المشغّل تحدّي «أنت لست روبوت» مرة واحدة → يُصدر Cloudflare كوكي `cf_clearance`
/// (HttpOnly) داخل المتصفح. بعدها تُنفَّذ كل طلبات FTTH كـ `fetch` **داخل نفس
/// المتصفح** فيُرفق الكوكي تلقائياً، وتُعاد النتيجة لـ Flutter عبر `webMessage`.
///
/// `webview_windows` لا يكشف API لقراءة الكوكيز (HttpOnly)، لذلك لا يمكن استخراج
/// `cf_clearance` وإرفاقه بـ `http` — تنفيذ الـ fetch داخل المتصفح يتجاوز هذا القيد.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:webview_windows/webview_windows.dart';

/// استجابة مبسطة من البوابة
class GatewayResponse {
  final int statusCode;
  final String body;
  const GatewayResponse(this.statusCode, this.body);
}

class FtthCloudflareGateway {
  FtthCloudflareGateway._();
  static final FtthCloudflareGateway instance = FtthCloudflareGateway._();

  /// مفتاح تشغيل البوابة. معطّل حالياً: نهج WebView الدائم يتعارض مع WebViews
  /// الأخرى في التطبيق ويُسبّب انهيار native. يُعاد تفعيله بعد اعتماد معمارية
  /// لا تُبقي متحكمين أحياء معاً (انظر cloudflare_gateway.md).
  static bool enabled = false;

  static const String origin = 'https://admin.ftth.iq';

  /// User-Agent ثابت — يُربط به كوكي cf_clearance؛ ثباته يضمن عدم إبطال الجلسة.
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  WebviewController? _controller;
  WebviewController? get controller => _controller;

  bool _initializing = false;
  bool _ready = false; // تمت تهيئة المتحكم وتحميل الصفحة
  bool _cleared = false; // تم اجتياز تحدّي Cloudflare

  bool get isReady => _ready;
  bool get isCleared => _cleared;

  /// البوابة مدعومة على Windows فقط (webview_windows / WebView2)
  bool get isSupported => Platform.isWindows;

  // طلبات fetch المعلّقة بانتظار رد عبر webMessage
  final Map<int, Completer<GatewayResponse>> _pending = {};
  int _reqSeq = 0;

  // إعلام الواجهة بأن التحدّي يحتاج حلاً يدوياً من المشغّل
  final StreamController<bool> _needsSolveCtrl =
      StreamController<bool>.broadcast();
  Stream<bool> get needsSolveStream => _needsSolveCtrl.stream;

  bool _needsSolve = false;
  bool get needsSolve => _needsSolve;

  void _flagNeedsSolve() {
    _cleared = false;
    if (!_needsSolve) {
      _needsSolve = true;
      if (!_needsSolveCtrl.isClosed) _needsSolveCtrl.add(true);
    }
  }

  /// تهيئة المتحكم وتحميل النطاق (مرة واحدة)
  Future<void> initialize() async {
    if (!isSupported) return;
    if (_ready) return;
    // انتظر تهيئة جارية إن وُجدت
    while (_initializing) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_ready) return;
    }
    _initializing = true;
    try {
      final c = WebviewController();
      await c.initialize();
      await c.setUserAgent(_userAgent);
      await c.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      c.webMessage.listen(_onWebMessage);
      // تحميل النطاق حتى تكون نداءات fetch من نفس الـ origin
      await c.loadUrl('$origin/auth/login');
      _controller = c;
      _ready = true;
      debugPrint('🛡️ [Gateway] تمت التهيئة');
    } catch (e) {
      debugPrint('❌ [Gateway] فشل التهيئة: $e');
    } finally {
      _initializing = false;
    }
  }

  void _onWebMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message.toString());
      if (decoded is Map && decoded['__ftthGw'] == true) {
        final id = decoded['id'] as int;
        final completer = _pending.remove(id);
        if (completer == null || completer.isCompleted) return;
        if (decoded['ok'] == true) {
          completer.complete(GatewayResponse(
            (decoded['status'] as num).toInt(),
            decoded['body'] as String? ?? '',
          ));
        } else {
          completer.completeError(
              Exception('Gateway fetch error: ${decoded['error']}'));
        }
      }
    } catch (_) {
      // رسائل أخرى (interceptors قديمة...) — تجاهل
    }
  }

  /// تنفيذ طلب HTTP عبر fetch داخل المتصفح (يتجاوز Cloudflare بكوكي الجلسة)
  Future<GatewayResponse> request(
    String method,
    String url, {
    Map<String, String>? headers,
    String? body,
  }) async {
    if (!isSupported) {
      throw StateError('FtthCloudflareGateway مدعوم على Windows فقط');
    }
    await initialize();
    if (_controller == null) {
      throw StateError('تعذّر تهيئة بوابة Cloudflare');
    }

    final id = ++_reqSeq;
    final completer = Completer<GatewayResponse>();
    _pending[id] = completer;

    final optsJson = jsonEncode({
      'method': method.toUpperCase(),
      'headers': headers ?? const <String, String>{},
      'body': body,
    });
    final urlJson = jsonEncode(url);

    final js = '''
      (function(){
        try {
          var o = $optsJson;
          var init = { method: o.method, headers: o.headers, credentials: 'include' };
          if (o.body != null && o.method !== 'GET' && o.method !== 'HEAD') { init.body = o.body; }
          fetch($urlJson, init).then(function(r){
            return r.text().then(function(t){
              window.chrome.webview.postMessage(JSON.stringify({__ftthGw:true, id:$id, ok:true, status:r.status, body:t}));
            });
          }).catch(function(e){
            window.chrome.webview.postMessage(JSON.stringify({__ftthGw:true, id:$id, ok:false, error:String(e)}));
          });
        } catch(e) {
          window.chrome.webview.postMessage(JSON.stringify({__ftthGw:true, id:$id, ok:false, error:String(e)}));
        }
        return 'dispatched';
      })();
    ''';

    try {
      await _controller!.executeScript(js);
    } catch (e) {
      _pending.remove(id);
      rethrow;
    }

    GatewayResponse resp;
    try {
      resp = await completer.future.timeout(const Duration(seconds: 45));
    } on TimeoutException {
      _pending.remove(id);
      rethrow;
    }

    // كشف تحدّي Cloudflare في الرد
    if (resp.statusCode == 403 && _looksLikeChallenge(resp.body)) {
      _flagNeedsSolve();
    } else if (resp.statusCode != 403) {
      // وصلنا للخادم فعلياً ⇒ الجلسة مُجازة
      _cleared = true;
      _needsSolve = false;
    }
    return resp;
  }

  bool _looksLikeChallenge(String body) {
    final b = body.toLowerCase();
    return b.contains('challenge-platform') ||
        b.contains('cf-chl') ||
        b.contains('cf_chl') ||
        b.contains('just a moment') ||
        b.contains('turnstile') ||
        b.contains('إجراء التحقق من الأمان');
  }

  /// فحص ما إذا كان التحدّي مُجتازاً حالياً (عبر مسبار خفيف على الـ API)
  Future<bool> probeCleared() async {
    if (!isSupported) return true;
    try {
      // GET على نقطة المصادقة: 401/400/405 ⇒ وصلنا للخادم (مُجاز)؛ 403+challenge ⇒ لا
      final r = await request('GET', '$origin/api/auth/Contractor/refresh');
      if (r.statusCode == 403 && _looksLikeChallenge(r.body)) {
        _flagNeedsSolve();
        return false;
      }
      _cleared = true;
      _needsSolve = false;
      return true;
    } catch (e) {
      debugPrint('⚠️ [Gateway] فشل المسبار: $e');
      return false;
    }
  }

  /// إعادة تحميل صفحة الدخول (لإظهار تحدّي Cloudflare للمشغّل)
  Future<void> reloadChallenge() async {
    if (_controller == null) return;
    try {
      await _controller!.loadUrl('$origin/auth/login');
    } catch (_) {}
  }

  void dispose() {
    _controller?.dispose();
    _controller = null;
    _ready = false;
    if (!_needsSolveCtrl.isClosed) _needsSolveCtrl.close();
  }
}
