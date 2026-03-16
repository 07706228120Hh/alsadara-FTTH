import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // للـ Clipboard
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../services/ftth_data_service.dart';
import '../../services/agents_auth_service.dart';
import '../server_data_page.dart'; // للوصول لـ FtthServerDataService.dashboardPath

/// صفحة جلب بيانات الموقع من الداشبورد
/// تفتح متصفح WebView وتسجل كل الطلبات والاستجابات
class FetchServerDataPage extends StatefulWidget {
  final String authToken;
  const FetchServerDataPage({super.key, this.authToken = ''});

  @override
  State<FetchServerDataPage> createState() => _FetchServerDataPageState();
}

class _FetchServerDataPageState extends State<FetchServerDataPage> {
  final WebviewController _controller = WebviewController();
  bool _isLoading = true;
  bool _isInitialized = false;

  // قوائم تسجيل البيانات
  final List<Map<String, dynamic>> _capturedCharts = [];
  // جميع طلبات API الملتقطة
  final List<Map<String, dynamic>> _capturedApiCalls = [];

  // إحصائيات
  int _requestCount = 0;
  int _responseCount = 0;
  int _chartCount = 0;

  String _currentUrl = '';
  String _statusMessage = 'جاري التحميل...';
  bool _isExtracting = false;
  bool _isFetchingFromApi = false; // جلب من Dashboard API
  bool _isFetchingAllZones = false; // جلب جميع المناطق (613)
  String? _guestToken; // Guest Token للـ Dashboard API
  bool _isFetchingSupersetDirect = false;
  String? _pendingGuestTokenForEmbed;
  bool _supersetAutoSaveDone = false;
  String? _supersetScriptId; // لتنظيف السكربت المحقون بعد الانتهاء

  // رابط تسجيل الدخول
  static const String _loginUrl = 'https://admin.ftth.iq/auth/login';
  // هل تم تسجيل الدخول تلقائياً؟
  bool _autoLoginAttempted = false;
  bool _autoLoginDone = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  /// حقن JavaScript لتسجيل الدخول تلقائياً بعد تحميل صفحة admin.ftth.iq
  Future<void> _injectAutoLogin() async {
    if (_autoLoginDone) return;

    try {
      // قراءة بيانات الدخول المخزنة
      final prefs = await SharedPreferences.getInstance();
      final savedUser = prefs.getString('savedUsername') ?? '';
      final savedPass = prefs.getString('savedPassword') ?? '';

      if (savedUser.isEmpty || savedPass.isEmpty) {
        debugPrint('⚠️ لا توجد بيانات دخول مخزنة — تسجيل يدوي');
        if (mounted) {
          setState(() => _statusMessage = 'سجّل الدخول ثم انتقل للداشبورد');
        }
        return;
      }

      _autoLoginDone = true;
      debugPrint('🔑 حقن تسجيل دخول تلقائي...');

      if (mounted) {
        setState(() => _statusMessage = '🔑 جاري تسجيل الدخول تلقائياً...');
      }

      // حقن JS لتسجيل الدخول من داخل الـ WebView (نفس الـ origin)
      final jsCode = '''
        (async function() {
          try {
            // مسح بيانات الجلسة القديمة لمنع استخدام جلسة مستخدم سابق
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
              body: 'username=${_escapeJs(savedUser)}&password=${_escapeJs(savedPass)}&grant_type=password'
            });
            const data = await resp.json();
            if (data && data.access_token) {
              // تخزين التوكن كما يفعل تطبيق Angular
              localStorage.setItem('access_token', data.access_token);
              localStorage.setItem('refresh_token', data.refresh_token || '');
              localStorage.setItem('token', JSON.stringify(data));
              localStorage.setItem('currentUser', JSON.stringify(data));
              window.chrome.webview.postMessage('AUTO_LOGIN:SUCCESS');
              // الانتقال للصفحة الرئيسية
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
      debugPrint('⚠️ خطأ في حقن تسجيل الدخول');
      if (mounted) {
        setState(() => _statusMessage = 'سجّل الدخول يدوياً');
      }
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

  Future<void> _initWebView() async {
    try {
      await _controller.initialize();

      // إعدادات WebView
      await _controller.setBackgroundColor(Colors.white);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      // الاستماع لتغيير الرابط
      _controller.url.listen((url) {
        if (!mounted) return;
        setState(() {
          _currentUrl = url;
          _requestCount++;
        });
      });

      // الاستماع لحالة التحميل
      _controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() {
          _isLoading = state == LoadingState.loading;
          if (state == LoadingState.navigationCompleted) {
            _responseCount++;
            _statusMessage = 'تم تحميل الصفحة - انتظر اكتمال البيانات...';

            Future.delayed(const Duration(seconds: 1), () async {
              if (!mounted) return;
              await _injectInterceptor();

              // Superset يحمّل طبيعي — الـ interceptor محقون عبر addScriptToExecuteOnDocumentCreated
              if (_pendingGuestTokenForEmbed != null &&
                  _currentUrl.contains('dashboard.ftth.iq')) {
                if (mounted) {
                  setState(() => _statusMessage = '📊 Superset يحمّل — انتظار البيانات...');
                }
                _log('📊 Superset loaded — interceptor active, waiting for chart data...');
                // لا نستدعي fetch يدوي — Superset سيجلب البيانات طبيعياً
                // والـ interceptor المحقون مسبقاً سيلتقط الاستجابات
                return; // تخطي منطق تسجيل الدخول التلقائي
              }

              // تسجيل دخول تلقائي إذا كنا على صفحة تسجيل الدخول
              if (_currentUrl.contains('/auth/login') && !_autoLoginDone) {
                await _injectAutoLogin();
              } else if (!_autoLoginDone && !_autoLoginAttempted) {
                // الموقع حوّل للداشبورد بجلسة قديمة — نمسح ونعيد تسجيل الدخول
                _autoLoginAttempted = true;
                debugPrint('🔄 [FetchServer] جلسة قديمة — مسح وإعادة تسجيل الدخول');
                await _controller.executeScript(
                    'localStorage.clear(); sessionStorage.clear(); window.location.href = "/auth/login";');
              } else if (_autoLoginDone) {
                if (_currentUrl.contains('dashboard') ||
                    _currentUrl.contains('data') ||
                    _currentUrl.contains('embedded') ||
                    _currentUrl == 'https://admin.ftth.iq/' ||
                    _currentUrl == 'https://admin.ftth.iq') {
                  if (mounted) {
                    setState(() {
                      _statusMessage =
                          '📋 الصفحة جاهزة - اضغط ⬇️ للاستخراج عندما تظهر البيانات';
                    });
                  }
                }
              }
            });
          }
        });
      });

      // الاستماع للرسائل من JavaScript
      _controller.webMessage.listen((message) {
        if (!mounted) return;
        final msg = message.toString();
        if (msg.startsWith('AUTO_LOGIN:SUCCESS')) {
          debugPrint('✅ تم تسجيل الدخول التلقائي بنجاح');
          if (mounted) {
            setState(() => _statusMessage = '✅ تم تسجيل الدخول — جاري تحميل الداشبورد...');
          }
        } else if (msg.startsWith('AUTO_LOGIN:FAIL:')) {
          final reason = msg.substring('AUTO_LOGIN:FAIL:'.length);
          debugPrint('❌ فشل تسجيل الدخول التلقائي: $reason');
          if (mounted) {
            setState(() => _statusMessage = 'فشل تسجيل الدخول التلقائي — سجّل يدوياً');
            _autoLoginDone = false; // السماح بإعادة المحاولة
          }
        } else {
          _handleWebMessage(message);
        }
      });

      // مسح بيانات التصفح القديمة لمنع استخدام جلسة مستخدم سابق
      try {
        await _controller.clearCache();
      } catch (_) {}

      // تحميل صفحة تسجيل الدخول — الـ auto-login يحدث بعد التحميل
      await _controller.loadUrl(_loginUrl);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _statusMessage = 'جاري تسجيل الدخول تلقائياً...';
        });
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'خطأ في تهيئة المتصفح';
        });
      }
    }
  }

  /// حقن JavaScript interceptor — يلتقط كل شيء مثل DevTools
  Future<void> _injectInterceptor() async {
    try {
      await _controller.executeScript(r'''
        (function() {
          if (window.__sdInterceptor) return;
          window.__sdInterceptor = true;
          window.__sdCharts = [];
          window.__sdApiCalls = [];

          function truncate(s, max) {
            if (!s) return s;
            if (typeof s !== 'string') s = JSON.stringify(s);
            return s.length > max ? s.substring(0, max) + '...[TRUNCATED]' : s;
          }

          const ignoredHosts = ['clarity.ms', 'google-analytics.com', 'googletagmanager.com', 'facebook.net', 'doubleclick.net', 'analytics.', 'hotjar.com'];
          function isIgnored(url) {
            if (!url) return true;
            const u = url.toString().toLowerCase();
            return ignoredHosts.some(h => u.includes(h));
          }

          function sendApi(entry) {
            window.__sdApiCalls.push(entry);
            try {
              window.chrome.webview.postMessage('API:' + JSON.stringify(entry));
            } catch(e) {}
          }

          // ═══════════════════════════════════════════
          // 1. Console — التقاط كل مخرجات الكونسول
          // ═══════════════════════════════════════════
          ['log','warn','error','info','debug'].forEach(level => {
            const orig = console[level];
            console[level] = function() {
              const args = Array.from(arguments).map(a => {
                try { return typeof a === 'object' ? JSON.stringify(a) : String(a); }
                catch(e) { return String(a); }
              });
              sendApi({
                type: 'console',
                method: level.toUpperCase(),
                url: 'console.' + level,
                status: level === 'error' ? 500 : (level === 'warn' ? 300 : 200),
                respBody: truncate(args.join(' '), 5000),
                time: 0,
                timestamp: new Date().toISOString()
              });
              return orig.apply(this, arguments);
            };
          });

          // ═══════════════════════════════════════════
          // 2. JS Errors — أخطاء JavaScript غير ملتقطة
          // ═══════════════════════════════════════════
          window.addEventListener('error', function(e) {
            sendApi({
              type: 'js-error',
              method: 'ERROR',
              url: (e.filename || 'unknown') + ':' + (e.lineno || 0) + ':' + (e.colno || 0),
              status: 500,
              respBody: truncate(e.message || e.toString(), 3000),
              time: 0,
              timestamp: new Date().toISOString()
            });
          });

          window.addEventListener('unhandledrejection', function(e) {
            let reason = '';
            try { reason = e.reason ? (e.reason.message || e.reason.toString()) : 'Unknown'; }
            catch(err) { reason = 'Unknown rejection'; }
            sendApi({
              type: 'js-error',
              method: 'PROMISE',
              url: 'unhandledrejection',
              status: 500,
              respBody: truncate(reason, 3000),
              time: 0,
              timestamp: new Date().toISOString()
            });
          });

          // ═══════════════════════════════════════════
          // 3. WebSocket — التقاط رسائل الويب سوكت
          // ═══════════════════════════════════════════
          const OrigWS = window.WebSocket;
          window.WebSocket = function(url, protocols) {
            const ws = protocols ? new OrigWS(url, protocols) : new OrigWS(url);
            sendApi({
              type: 'websocket',
              method: 'CONNECT',
              url: url,
              status: 101,
              respBody: 'WebSocket opened',
              time: 0,
              timestamp: new Date().toISOString()
            });

            ws.addEventListener('message', function(e) {
              sendApi({
                type: 'websocket',
                method: 'MSG-IN',
                url: url,
                status: 200,
                respBody: truncate(typeof e.data === 'string' ? e.data : '[binary]', 3000),
                time: 0,
                timestamp: new Date().toISOString()
              });
            });

            ws.addEventListener('close', function(e) {
              sendApi({
                type: 'websocket',
                method: 'CLOSE',
                url: url,
                status: e.code || 1000,
                respBody: e.reason || 'Connection closed',
                time: 0,
                timestamp: new Date().toISOString()
              });
            });

            ws.addEventListener('error', function() {
              sendApi({
                type: 'websocket',
                method: 'WS-ERR',
                url: url,
                status: 500,
                respBody: 'WebSocket error',
                time: 0,
                timestamp: new Date().toISOString()
              });
            });

            const origSendWs = ws.send.bind(ws);
            ws.send = function(data) {
              sendApi({
                type: 'websocket',
                method: 'MSG-OUT',
                url: url,
                status: 200,
                reqBody: truncate(typeof data === 'string' ? data : '[binary]', 3000),
                respBody: null,
                time: 0,
                timestamp: new Date().toISOString()
              });
              return origSendWs(data);
            };

            return ws;
          };
          window.WebSocket.prototype = OrigWS.prototype;
          window.WebSocket.CONNECTING = OrigWS.CONNECTING;
          window.WebSocket.OPEN = OrigWS.OPEN;
          window.WebSocket.CLOSING = OrigWS.CLOSING;
          window.WebSocket.CLOSED = OrigWS.CLOSED;

          // ═══════════════════════════════════════════
          // 4. Performance — تسجيل أداء الصفحة
          // ═══════════════════════════════════════════
          if (window.PerformanceObserver) {
            try {
              const perfObs = new PerformanceObserver(list => {
                for (const entry of list.getEntries()) {
                  if (entry.entryType === 'resource') {
                    if (isIgnored(entry.name)) continue;
                    // فقط الموارد البطيئة (> 500ms)
                    if (entry.duration > 500) {
                      sendApi({
                        type: 'perf',
                        method: entry.initiatorType ? entry.initiatorType.toUpperCase() : 'RES',
                        url: entry.name,
                        status: 200,
                        respBody: 'size: ' + (entry.transferSize || 0) + 'B, duration: ' + Math.round(entry.duration) + 'ms',
                        time: Math.round(entry.duration),
                        timestamp: new Date().toISOString()
                      });
                    }
                  }
                }
              });
              perfObs.observe({entryTypes: ['resource']});
            } catch(e) {}
          }

          // ═══════════════════════════════════════════
          // 5. Navigation — تغييرات الصفحة
          // ═══════════════════════════════════════════
          let lastUrl = location.href;
          const navCheck = setInterval(() => {
            if (location.href !== lastUrl) {
              sendApi({
                type: 'navigation',
                method: 'NAV',
                url: location.href,
                status: 200,
                respBody: 'from: ' + lastUrl,
                time: 0,
                timestamp: new Date().toISOString()
              });
              lastUrl = location.href;
            }
          }, 500);

          // ═══════════════════════════════════════════
          // 6. Cookies — تتبع تغييرات الكوكيز
          // ═══════════════════════════════════════════
          let lastCookies = document.cookie;
          setInterval(() => {
            if (document.cookie !== lastCookies) {
              sendApi({
                type: 'cookie',
                method: 'COOKIE',
                url: location.href,
                status: 200,
                reqBody: truncate(lastCookies, 2000),
                respBody: truncate(document.cookie, 2000),
                time: 0,
                timestamp: new Date().toISOString()
              });
              lastCookies = document.cookie;
            }
          }, 1000);

          // ═══════════════════════════════════════════
          // 7. Storage — localStorage & sessionStorage
          // ═══════════════════════════════════════════
          ['localStorage', 'sessionStorage'].forEach(storageName => {
            const storage = window[storageName];
            if (!storage) return;
            const origSet = storage.setItem.bind(storage);
            const origRemove = storage.removeItem.bind(storage);

            storage.setItem = function(key, value) {
              sendApi({
                type: 'storage',
                method: 'SET',
                url: storageName + '.' + key,
                status: 200,
                respBody: truncate(value, 2000),
                time: 0,
                timestamp: new Date().toISOString()
              });
              return origSet(key, value);
            };

            storage.removeItem = function(key) {
              sendApi({
                type: 'storage',
                method: 'DEL',
                url: storageName + '.' + key,
                status: 200,
                respBody: null,
                time: 0,
                timestamp: new Date().toISOString()
              });
              return origRemove(key);
            };
          });

          // ═══════════════════════════════════════════
          // 8. Fetch & XHR (كما كان سابقاً)
          // ═══════════════════════════════════════════
          const origFetch = window.fetch;
          window.fetch = async function(url, opts) {
            const urlStr = (url && url.url) ? url.url : (url ? url.toString() : '');
            if (isIgnored(urlStr)) return origFetch.apply(this, arguments);
            const method = (opts && opts.method) ? opts.method : (url && url.method ? url.method : 'GET');
            let reqBody = null;
            if (opts && opts.body) {
              try { reqBody = typeof opts.body === 'string' ? opts.body : JSON.stringify(opts.body); } catch(e) { reqBody = '[binary]'; }
            }
            let reqHeaders = {};
            if (opts && opts.headers) {
              try {
                if (opts.headers instanceof Headers) {
                  opts.headers.forEach((v, k) => { reqHeaders[k] = v; });
                } else {
                  reqHeaders = Object.assign({}, opts.headers);
                }
              } catch(e) {}
            }

            const startTime = Date.now();
            try {
              const resp = await origFetch.apply(this, arguments);
              const clone = resp.clone();

              if (urlStr.includes('/chart/data')) {
                clone.clone().json().then(d => {
                  window.__sdCharts.push({u: urlStr, d: d, t: Date.now()});
                  try { window.chrome.webview.postMessage('CHART:' + window.__sdCharts.length); } catch(e) {}
                }).catch(() => {});
              }

              clone.text().then(text => {
                let respBody = truncate(text, 5000);
                try { JSON.parse(text); respBody = truncate(text, 5000); } catch(e) {}

                sendApi({
                  type: 'fetch',
                  method: method.toUpperCase(),
                  url: urlStr,
                  reqHeaders: reqHeaders,
                  reqBody: truncate(reqBody, 3000),
                  status: resp.status,
                  statusText: resp.statusText,
                  respBody: respBody,
                  respHeaders: Object.fromEntries([...resp.headers.entries()]),
                  time: Date.now() - startTime,
                  timestamp: new Date().toISOString()
                });
              }).catch(() => {
                sendApi({
                  type: 'fetch',
                  method: method.toUpperCase(),
                  url: urlStr,
                  reqHeaders: reqHeaders,
                  reqBody: truncate(reqBody, 3000),
                  status: resp.status,
                  statusText: resp.statusText,
                  respBody: '[unreadable]',
                  time: Date.now() - startTime,
                  timestamp: new Date().toISOString()
                });
              });

              return resp;
            } catch(err) {
              sendApi({
                type: 'fetch',
                method: method.toUpperCase(),
                url: urlStr,
                reqHeaders: reqHeaders,
                reqBody: truncate(reqBody, 3000),
                status: 0,
                statusText: 'NETWORK_ERROR',
                respBody: err.message || err.toString(),
                time: Date.now() - startTime,
                timestamp: new Date().toISOString()
              });
              throw err;
            }
          };

          const origOpen = XMLHttpRequest.prototype.open;
          const origSend = XMLHttpRequest.prototype.send;
          const origSetHeader = XMLHttpRequest.prototype.setRequestHeader;

          XMLHttpRequest.prototype.open = function(m, u) {
            this.__method = m;
            this.__url = u;
            this.__reqHeaders = {};
            this.__startTime = Date.now();
            return origOpen.apply(this, arguments);
          };

          XMLHttpRequest.prototype.setRequestHeader = function(k, v) {
            if (this.__reqHeaders) this.__reqHeaders[k] = v;
            return origSetHeader.apply(this, arguments);
          };

          XMLHttpRequest.prototype.send = function(body) {
            const self = this;
            if (isIgnored(self.__url)) return origSend.apply(this, arguments);
            const reqBody = body ? truncate(typeof body === 'string' ? body : JSON.stringify(body), 3000) : null;

            this.addEventListener('load', function() {
              if (self.__url && self.__url.includes('/chart/data')) {
                try {
                  const d = JSON.parse(self.responseText);
                  window.__sdCharts.push({u: self.__url, d: d, t: Date.now()});
                  try { window.chrome.webview.postMessage('CHART:' + window.__sdCharts.length); } catch(e) {}
                } catch(e) {}
              }

              // جمع response headers
              let respHeaders = {};
              try {
                const allH = self.getAllResponseHeaders().trim().split(/[\r\n]+/);
                allH.forEach(h => { const p = h.split(': '); if(p.length>=2) respHeaders[p[0]] = p.slice(1).join(': '); });
              } catch(e) {}

              sendApi({
                type: 'xhr',
                method: (self.__method || 'GET').toUpperCase(),
                url: self.__url || '',
                reqHeaders: self.__reqHeaders || {},
                reqBody: reqBody,
                status: self.status,
                statusText: self.statusText,
                respBody: truncate(self.responseText, 5000),
                respHeaders: respHeaders,
                time: Date.now() - (self.__startTime || Date.now()),
                timestamp: new Date().toISOString()
              });
            });

            this.addEventListener('error', function() {
              sendApi({
                type: 'xhr',
                method: (self.__method || 'GET').toUpperCase(),
                url: self.__url || '',
                reqHeaders: self.__reqHeaders || {},
                reqBody: reqBody,
                status: 0,
                statusText: 'XHR_ERROR',
                respBody: null,
                time: Date.now() - (self.__startTime || Date.now()),
                timestamp: new Date().toISOString()
              });
            });

            return origSend.apply(this, arguments);
          };

          // رسالة تأكيد
          sendApi({
            type: 'system',
            method: 'INIT',
            url: location.href,
            status: 200,
            respBody: 'DevTools interceptor active — capturing: fetch, XHR, console, errors, WebSocket, cookies, storage, navigation, performance',
            time: 0,
            timestamp: new Date().toISOString()
          });
        })();
      ''');
    } catch (e) {
      debugPrint('Inject error');
    }
  }

  /// معالجة الرسائل من JavaScript
  void _handleWebMessage(dynamic message) {
    if (!mounted) return;
    final msg = message.toString();
    if (msg.startsWith('CHART:')) {
      final count = int.tryParse(msg.substring(6)) ?? 0;
      setState(() {
        _chartCount = count;
        _statusMessage = _isFetchingSupersetDirect
            ? '⏳ تم التقاط $count chart - انتظار المزيد...'
            : '✅ تم التقاط $count chart';
      });
      // حفظ تلقائي عند التقاط عدد كافٍ من الشارتات
      if (_isFetchingSupersetDirect && count >= 5 && !_supersetAutoSaveDone) {
        _supersetAutoSaveDone = true;
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) _autoSaveSupersetCharts();
        });
      }
    } else if (msg.startsWith('API:')) {
      try {
        final data = jsonDecode(msg.substring(4)) as Map<String, dynamic>;
        setState(() {
          _capturedApiCalls.add(data);
          _requestCount = _capturedApiCalls.length;
          final method = data['method'] ?? '';
          final url = data['url'] ?? '';
          final status = data['status'] ?? 0;
          // عرض آخر API call في شريط الحالة
          final shortUrl = url.toString().length > 60
              ? '...${url.toString().substring(url.toString().length - 57)}'
              : url.toString();
          _statusMessage = '$method $status  $shortUrl';
        });
        _log('API: ${data['method']} ${data['status']} ${data['url']}');
      } catch (e) {
        debugPrint('API parse error');
      }
    }
  }

  /// التحقق من اكتمال تحميل البيانات في الصفحة
  Future<bool> _waitForDataToLoad() async {
    for (int i = 0; i < 5; i++) {
      // انتظار حتى 5 ثواني فقط
      final result = await _controller.executeScript(r'''
        (function() {
          // البحث عن أي محتوى يحتوي على FBG (دليل على وجود بيانات)
          const pageText = document.body?.innerText || '';
          if (pageText.includes('FBG')) return 'ready';
          
          // البحث عن جداول
          const tables = document.querySelectorAll('table, [role="grid"], [class*="table"]');
          if (tables.length > 0) {
            for (const t of tables) {
              if (t.querySelectorAll('tr, [role="row"]').length > 1) return 'ready';
            }
          }
          
          // التحقق من وجود مؤشر تحميل
          const loaders = document.querySelectorAll('[class*="loading"], [class*="spinner"], .ant-spin');
          if (loaders.length > 0) return 'loading';
          
          return 'waiting';
        })();
      ''');

      final status = result.toString().replaceAll('"', '');
      debugPrint('Data status: $status (attempt ${i + 1})');

      if (status == 'ready') return true;

      await Future.delayed(const Duration(seconds: 1));
    }
    // بعد 5 ثواني نسمح بالاستمرار على أي حال
    return true;
  }

  /// استخراج البيانات من الصفحة
  Future<void> _extractData() async {
    if (!mounted) return;
    setState(() {
      _isExtracting = true;
      _statusMessage = 'جاري استخراج البيانات...';
    });

    // انتظار قصير لاكتمال تحميل البيانات
    await _waitForDataToLoad();

    try {
      // محاولة استخراج البيانات المخزنة
      final result = await _controller.executeScript(r'''
        (function() {
          if (window.__sdCharts && window.__sdCharts.length > 0) {
            return JSON.stringify(window.__sdCharts);
          }
          return "[]";
        })();
      ''');

      if (result != null) {
        String jsonStr = result.toString();
        // إزالة علامات الاقتباس الخارجية إن وجدت
        if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
          jsonStr = jsonStr.substring(1, jsonStr.length - 1);
          jsonStr = jsonStr.replaceAll(r'\"', '"');
        }

        final List<dynamic> charts = jsonDecode(jsonStr);
        if (charts.isNotEmpty) {
          _capturedCharts.clear();
          for (var chart in charts) {
            _capturedCharts.add({
              'url': chart['u'],
              'data': chart['d'],
              'timestamp': chart['t'],
            });
          }
          if (mounted) setState(() {
            _chartCount = _capturedCharts.length;
            _statusMessage = '✅ تم استخراج $_chartCount chart';
          });
        } else {
          // محاولة استخراج من DOM
          await _extractFromDOM();
        }
      }
    } catch (e) {
      debugPrint('Extract error');
      // محاولة استخراج من DOM كبديل
      await _extractFromDOM();
    }

    if (mounted) setState(() => _isExtracting = false);
  }

  /// استخراج البيانات من DOM مباشرة
  Future<void> _extractFromDOM() async {
    try {
      // استخراج كل البيانات المرئية من الصفحة
      final result = await _controller.executeScript(r'''
        (function() {
          const data = {
            tables: [],
            cards: [],
            stats: [],
            zones: [],
            relatedZones: []
          };
          
          console.log('=== Starting Sadara Extraction ===');
          
          // === طريقة 1: البحث المباشر عن جداول HTML ===
          const allTables = document.querySelectorAll('table');
          console.log('Found', allTables.length, 'tables');
          
          allTables.forEach((table, tableIdx) => {
            console.log('Processing table', tableIdx);
            
            // جمع كل الصفوف
            const allTr = table.querySelectorAll('tr');
            console.log('Table has', allTr.length, 'rows');
            
            if (allTr.length < 2) return;
            
            // استخراج العناوين من أول صف
            let headers = [];
            const firstRow = allTr[0];
            firstRow.querySelectorAll('th, td').forEach((cell) => {
              let text = (cell.innerText || cell.textContent || '').trim();
              text = text.replace(/[↕↑↓▲▼⬍♦◊]/g, '').trim();
              headers.push(text || 'col' + headers.length);
            });
            
            console.log('Headers:', headers.join(', '));
            
            // استخراج البيانات من باقي الصفوف
            const rows = [];
            for (let i = 1; i < allTr.length; i++) {
              const tr = allTr[i];
              const cells = tr.querySelectorAll('td');
              if (cells.length < 2) continue;
              
              const rowData = {};
              let hasValue = false;
              cells.forEach((td, j) => {
                const key = headers[j] || ('col' + j);
                const val = (td.innerText || td.textContent || '').trim();
                rowData[key] = val;
                if (val && val.length > 0) hasValue = true;
              });
              
              if (hasValue) {
                rows.push(rowData);
              }
            }
            
            console.log('Extracted', rows.length, 'rows');
            
            if (rows.length > 0) {
              // التحقق إذا كان جدول Zones
              const headerStr = headers.join(' ').toLowerCase();
              const isZones = headerStr.includes('zone') || headerStr.includes('contractor');
              
              if (isZones) {
                data.relatedZones = data.relatedZones.concat(rows);
                console.log('Added to relatedZones');
              } else {
                data.tables.push({headers: headers, rows: rows, count: rows.length});
                console.log('Added to tables');
              }
            }
          });
          
          // === طريقة 2: استخراج FBG من نص الصفحة ===
          const bodyText = document.body?.innerText || '';
          const fbgMatches = bodyText.match(/FBG\d{3,5}(-\d+)?/g) || [];
          const uniqueFbg = [...new Set(fbgMatches)];
          data.zones = uniqueFbg;
          console.log('Found FBG codes:', uniqueFbg.length);
          
          // === طريقة 3: إذا لم نجد جداول، نبحث عن div بنية ===
          if (data.relatedZones.length === 0 && data.zones.length > 0) {
            console.log('No tables found, creating from FBG list');
            data.zones.forEach(fbg => {
              data.relatedZones.push({
                Zone: fbg,
                ZoneType: fbg.includes('-') ? 'Virtual' : 'Main',
                ZoneContractor: '',
                MainZoneContractor: ''
              });
            });
          }
          
          console.log('=== Extraction Complete ===');
          console.log('relatedZones:', data.relatedZones.length);
          console.log('zones:', data.zones.length);
          console.log('tables:', data.tables.length);
          
          return JSON.stringify(data);
        })();
      ''');

      if (result != null) {
        String jsonStr = result.toString();
        if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
          jsonStr = jsonStr.substring(1, jsonStr.length - 1);
          jsonStr = jsonStr.replaceAll(r'\"', '"').replaceAll(r'\\n', '\n');
        }

        final Map<String, dynamic> extractedData = jsonDecode(jsonStr);

        _capturedCharts.clear();
        int itemCount = 0;

        // إضافة الجداول
        final tables = extractedData['tables'] as List? ?? [];
        for (var table in tables) {
          _capturedCharts.add({
            'type': 'table',
            'url': _currentUrl,
            'data': {
              'result': [
                {'data': table['rows']}
              ]
            },
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
          itemCount += (table['count'] as int? ?? 0);
        }

        // إضافة الإحصائيات
        final stats = extractedData['stats'] as List? ?? [];
        if (stats.isNotEmpty) {
          _capturedCharts.add({
            'type': 'stats',
            'url': _currentUrl,
            'data': {
              'result': [
                {'data': stats}
              ]
            },
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
          itemCount += stats.length;
        }

        // إضافة Related Zones
        final relatedZones = extractedData['relatedZones'] as List? ?? [];
        if (relatedZones.isNotEmpty) {
          _capturedCharts.add({
            'type': 'zones',
            'url': _currentUrl,
            'data': {
              'result': [
                {'data': relatedZones}
              ]
            },
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
          itemCount += relatedZones.length;
        }

        // إضافة قائمة الـ zones
        final zones = extractedData['zones'] as List? ?? [];
        if (zones.isNotEmpty) {
          _capturedCharts.add({
            'type': 'zone_list',
            'url': _currentUrl,
            'data': {
              'result': [
                {
                  'data': zones.map((z) => {'Zone': z}).toList()
                }
              ]
            },
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
          itemCount += zones.length;
        }

        if (mounted) setState(() {
          _chartCount = _capturedCharts.length;
          _statusMessage = itemCount > 0
              ? '✅ تم استخراج $itemCount عنصر في $_chartCount مجموعة'
              : '❌ لم يتم العثور على بيانات - تأكد من تحميل الصفحة';
        });
      }
    } catch (e) {
      debugPrint('DOM extract error');
      if (mounted) setState(() {
        _statusMessage = '❌ خطأ في الاستخراج';
      });
    }
  }

  /// عرض جميع طلبات API الملتقطة
  String _trafficFilter = 'الكل';

  void _showApiTraffic() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          // فلترة حسب النوع
          final typeFilters = {
            'الكل': null,
            'HTTP': ['fetch', 'xhr'],
            'Console': ['console'],
            'Errors': ['js-error'],
            'WS': ['websocket'],
            'Storage': ['storage', 'cookie'],
            'Nav': ['navigation', 'system'],
          };

          final filteredCalls = _trafficFilter == 'الكل'
              ? _capturedApiCalls
              : _capturedApiCalls.where((c) {
                  final types = typeFilters[_trafficFilter];
                  return types != null && types.contains(c['type']);
                }).toList();

          return AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
              children: [
                const Icon(Icons.http, color: Colors.deepPurple),
                const SizedBox(width: 8),
                Text('DevTools (${filteredCalls.length}/${_capturedApiCalls.length})',
                    style: const TextStyle(fontSize: 16)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy_all, size: 20),
                  tooltip: 'نسخ الكل JSON',
                  onPressed: () {
                    final json = const JsonEncoder.withIndent('  ')
                        .convert(_capturedApiCalls);
                    Clipboard.setData(ClipboardData(text: json));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم نسخ جميع الطلبات'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.save_alt, size: 20),
                  tooltip: 'حفظ كملف JSON',
                  onPressed: () => _saveApiTrafficToFile(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: typeFilters.keys.map((label) {
                final isSelected = _trafficFilter == label;
                // عدد العناصر لكل فلتر
                final count = label == 'الكل'
                    ? _capturedApiCalls.length
                    : _capturedApiCalls.where((c) {
                        final types = typeFilters[label];
                        return types != null && types.contains(c['type']);
                      }).length;
                return FilterChip(
                  label: Text('$label ($count)', style: const TextStyle(fontSize: 11)),
                  selected: isSelected,
                  onSelected: (_) => setDialogState(() => _trafficFilter = label),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                );
              }).toList(),
            ),
          ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.height * 0.75,
              child: filteredCalls.isEmpty
                  ? const Center(
                      child: Text(
                        'لا توجد طلبات ملتقطة بعد.\nتصفح الصفحات في المتصفح لالتقاط الطلبات.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredCalls.length,
                      itemBuilder: (context, index) {
                        final call = filteredCalls[
                            filteredCalls.length - 1 - index];
                        final method = call['method'] ?? 'GET';
                        final url = call['url'] ?? '';
                        final status = call['status'] ?? 0;
                        final time = call['time'] ?? 0;
                        final type = call['type'] ?? 'fetch';

                        // لون الحالة
                        Color statusColor;
                        if (status >= 200 && status < 300) {
                          statusColor = Colors.green;
                        } else if (status >= 400) {
                          statusColor = Colors.red;
                        } else if (status == 0) {
                          statusColor = Colors.grey;
                        } else {
                          statusColor = Colors.orange;
                        }

                        // أيقونة ولون حسب النوع
                        IconData typeIcon;
                        Color methodColor;
                        Color? bgColor;
                        switch (type) {
                          case 'console':
                            typeIcon = method == 'ERROR' ? Icons.error : (method == 'WARN' ? Icons.warning : Icons.terminal);
                            methodColor = method == 'ERROR' ? Colors.red : (method == 'WARN' ? Colors.orange : Colors.blueGrey);
                            bgColor = method == 'ERROR' ? Colors.red.shade50 : (method == 'WARN' ? Colors.orange.shade50 : null);
                            break;
                          case 'js-error':
                            typeIcon = Icons.bug_report;
                            methodColor = Colors.red.shade800;
                            bgColor = Colors.red.shade50;
                            break;
                          case 'websocket':
                            typeIcon = Icons.cable;
                            methodColor = Colors.purple;
                            break;
                          case 'cookie':
                            typeIcon = Icons.cookie;
                            methodColor = Colors.brown;
                            break;
                          case 'storage':
                            typeIcon = Icons.storage;
                            methodColor = Colors.teal;
                            break;
                          case 'navigation':
                            typeIcon = Icons.open_in_browser;
                            methodColor = Colors.indigo;
                            bgColor = Colors.indigo.shade50;
                            break;
                          case 'perf':
                            typeIcon = Icons.speed;
                            methodColor = Colors.deepOrange;
                            break;
                          case 'system':
                            typeIcon = Icons.settings;
                            methodColor = Colors.grey;
                            bgColor = Colors.grey.shade100;
                            break;
                          default: // fetch, xhr
                            typeIcon = type == 'xhr' ? Icons.swap_horiz : Icons.cloud_download;
                            switch (method) {
                              case 'GET': methodColor = Colors.blue; break;
                              case 'POST': methodColor = Colors.green.shade700; break;
                              case 'PUT': methodColor = Colors.orange; break;
                              case 'DELETE': methodColor = Colors.red; break;
                              default: methodColor = Colors.grey;
                            }
                        }

                        // اختصار الـ URL
                        String shortUrl = url.toString();
                        if (type == 'fetch' || type == 'xhr') {
                          try {
                            final uri = Uri.parse(shortUrl);
                            shortUrl = uri.path +
                                (uri.query.isNotEmpty ? '?${uri.query}' : '');
                          } catch (_) {}
                        }

                        // للـ console نعرض المحتوى بدل الـ URL
                        final displayText = (type == 'console' || type == 'js-error')
                            ? (call['respBody'] ?? '').toString()
                            : shortUrl;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 1),
                          color: bgColor,
                          elevation: 0.5,
                          child: InkWell(
                            onTap: () => _showApiCallDetails(call),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Row(
                                children: [
                                  // Type icon
                                  Icon(typeIcon, size: 14, color: methodColor),
                                  const SizedBox(width: 6),
                                  // Method badge
                                  Container(
                                    width: 56,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: methodColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                      border:
                                          Border.all(color: methodColor, width: 0.5),
                                    ),
                                    child: Text(
                                      method.length > 7 ? method.substring(0, 7) : method,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: methodColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Status
                                  if (type == 'fetch' || type == 'xhr')
                                    SizedBox(
                                      width: 30,
                                      child: Text(
                                        '$status',
                                        style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  // Content
                                  Expanded(
                                    child: Text(
                                      displayText,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        color: (type == 'js-error' || method == 'ERROR')
                                            ? Colors.red.shade700 : null,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Time
                                  if (time > 0)
                                    Text(
                                      '${time}ms',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: time > 1000 ? Colors.red : Colors.grey.shade600,
                                        fontWeight: time > 1000 ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() => _capturedApiCalls.clear());
                  Navigator.pop(ctx);
                },
                child: const Text('مسح الكل'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// عرض تفاصيل طلب API واحد
  void _showApiCallDetails(Map<String, dynamic> call) {
    final method = call['method'] ?? '';
    final url = call['url'] ?? '';
    final status = call['status'] ?? 0;
    final reqHeaders = call['reqHeaders'];
    final reqBody = call['reqBody'];
    final respBody = call['respBody'];
    final time = call['time'] ?? 0;
    final timestamp = call['timestamp'] ?? '';

    String formatJson(dynamic data) {
      if (data == null) return 'null';
      if (data is String) {
        try {
          final parsed = jsonDecode(data);
          return const JsonEncoder.withIndent('  ').convert(parsed);
        } catch (_) {
          return data;
        }
      }
      return const JsonEncoder.withIndent('  ').convert(data);
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(
              method,
              style: TextStyle(
                color: method == 'POST'
                    ? Colors.green.shade700
                    : method == 'DELETE'
                        ? Colors.red
                        : Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Text('$status',
                style: TextStyle(
                  color: status >= 200 && status < 300
                      ? Colors.green
                      : Colors.red,
                )),
            const SizedBox(width: 8),
            Text('${time}ms',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'نسخ الكل',
              onPressed: () {
                final full = const JsonEncoder.withIndent('  ').convert(call);
                Clipboard.setData(ClipboardData(text: full));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم النسخ'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.7,
          child: DefaultTabController(
            length: 4,
            child: Column(
              children: [
                // URL bar
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    url,
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 4),
                Text(timestamp,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                const SizedBox(height: 8),
                const TabBar(
                  labelColor: Colors.deepPurple,
                  tabs: [
                    Tab(text: 'Headers'),
                    Tab(text: 'Request Body'),
                    Tab(text: 'Response'),
                    Tab(text: 'cURL'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      // Headers tab
                      SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: SelectableText(
                            formatJson(reqHeaders),
                            style: const TextStyle(
                                fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                      // Request Body tab
                      SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: SelectableText(
                            reqBody != null ? formatJson(reqBody) : '(no body)',
                            style: const TextStyle(
                                fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                      // Response tab
                      SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: SelectableText(
                            respBody != null
                                ? formatJson(respBody)
                                : '(no response)',
                            style: const TextStyle(
                                fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                      // cURL tab
                      SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: SelectableText(
                            _buildCurl(call),
                            style: const TextStyle(
                                fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  /// بناء أمر cURL من بيانات الطلب
  String _buildCurl(Map<String, dynamic> call) {
    final method = call['method'] ?? 'GET';
    final url = call['url'] ?? '';
    final headers = call['reqHeaders'] as Map<String, dynamic>? ?? {};
    final body = call['reqBody'];

    final sb = StringBuffer("curl -X $method \\\n  '$url'");

    headers.forEach((k, v) {
      sb.write(" \\\n  -H '$k: $v'");
    });

    if (body != null && body.toString().isNotEmpty) {
      final escapedBody = body.toString().replaceAll("'", "'\\''");
      sb.write(" \\\n  -d '$escapedBody'");
    }

    return sb.toString();
  }

  /// حفظ API traffic كملف JSON
  Future<void> _saveApiTrafficToFile() async {
    if (_capturedApiCalls.isEmpty) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File('${dir.path}/api_traffic_$timestamp.json');
      final json =
          const JsonEncoder.withIndent('  ').convert(_capturedApiCalls);
      await file.writeAsString(json);
      _log('تم حفظ ${_capturedApiCalls.length} طلب في: ${file.path}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم الحفظ: ${file.path}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      _log('خطأ في الحفظ');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 📊 جلب بيانات الوكلاء والمناطق من Dashboard API مباشرة
  // ═══════════════════════════════════════════════════════════════════

  // قائمة سجلات العمليات للتتبع
  final List<String> _logs = [];
  String? _extractedAuthToken; // token مستخرج من WebView

  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final logEntry = '[$timestamp] $message';
    _logs.add(logEntry);
    debugPrint(logEntry);
  }

  /// استخراج Auth Token من WebView (localStorage)
  Future<String?> _extractAuthTokenFromWebView() async {
    if (!_isInitialized) {
      _log('⚠️ WebView غير مهيأ');
      return null;
    }

    try {
      _log('🔍 محاولة استخراج token من localStorage...');

      // محاولة استخراج token من localStorage
      final result = await _controller.executeScript(r'''
        (function() {
          // البحث في localStorage عن أي token
          const keys = ['access_token', 'accessToken', 'token', 'auth_token', 'jwt'];
          for (const key of keys) {
            const val = localStorage.getItem(key);
            if (val) return val;
          }
          
          // البحث في localStorage عن أي مفتاح يحتوي token
          for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            if (key && key.toLowerCase().includes('token')) {
              const val = localStorage.getItem(key);
              if (val && val.length > 50) return val;
            }
          }
          
          // محاولة من sessionStorage
          for (const key of keys) {
            const val = sessionStorage.getItem(key);
            if (val) return val;
          }
          
          return null;
        })();
      ''');

      if (result != null &&
          result.toString() != 'null' &&
          result.toString().length > 50) {
        String token = result.toString();
        // إزالة علامات الاقتباس
        if (token.startsWith('"') && token.endsWith('"')) {
          token = token.substring(1, token.length - 1);
        }
        _log('✅ تم استخراج token من WebView (${token.length} حرف)');
        _extractedAuthToken = token;
        return token;
      }

      _log('⚠️ لم يتم العثور على token في localStorage');
      return null;
    } catch (e) {
      _log('❌ خطأ في استخراج token');
      return null;
    }
  }

  /// عرض سجل العمليات
  void _showLogs() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.article, color: Colors.blue),
            SizedBox(width: 8),
            Text('سجل العمليات'),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.6,
          child: _logs.isEmpty
              ? const Center(child: Text('لا توجد سجلات'))
              : ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[_logs.length - 1 - index]; // الأحدث أولاً
                    Color color = Colors.black;
                    if (log.contains('✅')) color = Colors.green;
                    if (log.contains('❌')) color = Colors.red;
                    if (log.contains('⚠️')) color = Colors.orange;
                    if (log.contains('🔄') || log.contains('📊'))
                      color = Colors.blue;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        log,
                        style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: color),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          // زر نسخ السجلات
          TextButton.icon(
            onPressed: () {
              if (_logs.isNotEmpty) {
                final allLogs = _logs.join('\n');
                Clipboard.setData(ClipboardData(text: allLogs));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ تم نسخ السجلات إلى الحافظة'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('نسخ'),
          ),
          TextButton(
            onPressed: () {
              setState(() => _logs.clear());
              Navigator.pop(ctx);
            },
            child: const Text('مسح السجلات'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  /// جلب Guest Token للـ Dashboard API
  Future<void> _fetchGuestToken() async {
    _log('🔄 بدء جلب Guest Token...');
    try {
      // أولاً: محاولة باستخدام authToken الممرر من الصفحة الرئيسية
      String? effectiveAuthToken = widget.authToken.isNotEmpty ? widget.authToken : null;

      // ثانياً: محاولة استخراج token من WebView
      if (effectiveAuthToken == null && _extractedAuthToken == null && _isInitialized) {
        _log('🔍 محاولة استخراج token من WebView أولاً...');
        await _extractAuthTokenFromWebView();
      }

      effectiveAuthToken ??= _extractedAuthToken;

      // ثالثاً: محاولة جلب Guest Token
      _log('📡 محاولة AgentsAuthService.fetchGuestToken()...');
      var token = await AgentsAuthService.fetchGuestToken(
          authToken: effectiveAuthToken);
      _log(
          '📋 نتيجة fetchGuestToken: ${token != null ? "تم الحصول على token" : "null"}');

      if (token == null) {
        _log('⚠️ Guest Token فارغ - محاولة تسجيل دخول viewer...');
        final loginResult = await AgentsAuthService.login('viewer', 'viewer');
        _log(
            '📋 نتيجة login: isSuccess=${loginResult.isSuccess}, error=${loginResult.errorMessage ?? "none"}');

        if (loginResult.isSuccess) {
          _log('✅ تسجيل الدخول ناجح - جلب Guest Token مرة أخرى...');
          token = await AgentsAuthService.fetchGuestToken();
          _log('📋 Guest Token بعد login: ${token != null ? "تم" : "فشل"}');
        } else {
          _log('❌ فشل تسجيل الدخول: ${loginResult.errorMessage}');

          // محاولة أخيرة: استخدام Guest Token المخزن مسبقاً
          _log('🔄 محاولة الحصول على Guest Token المخزن...');
          token = await AgentsAuthService.getStoredGuestToken();
          _log(
              '📋 Guest Token المخزن: ${token != null ? "موجود" : "غير موجود"}');
        }
      }

      if (mounted) setState(() => _guestToken = token);
      _log(token != null
          ? '✅ Guest Token جاهز (${token.substring(0, 20)}...)'
          : '❌ فشل الحصول على Guest Token - تأكد من تسجيل الدخول في المتصفح');
    } catch (e, stackTrace) {
      _log('❌ استثناء في _fetchGuestToken');
      _log(
          '📋 Stack trace: ${stackTrace.toString().split('\n').take(5).join('\n')}');
    }
  }

  /// حقن Guest Token في صفحة Superset المدمجة عبر postMessage
  Future<void> _injectGuestTokenForEmbedded(String guestToken) async {
    _log('🔑 حقن Guest Token للـ Superset المدمج...');
    try {
      final escapedToken = _escapeJs(guestToken);
      await _controller.executeScript('''
        (function() {
          const TOKEN = '$escapedToken';

          // الاستماع لرسالة 'ready' من صفحة Superset المدمجة
          window.addEventListener('message', function handler(e) {
            if (e.data && e.data.type === 'ready') {
              console.log('[Sadara] Embedded page ready - sending guestToken');
              window.postMessage({type: 'guestToken', guestToken: TOKEN}, '*');
            }
          });

          // إرسال فوري في حالة كانت الصفحة جاهزة مسبقاً
          setTimeout(function() {
            console.log('[Sadara] Sending guestToken (initial)');
            window.postMessage({type: 'guestToken', guestToken: TOKEN}, '*');
          }, 500);

          // إرسال احتياطي بعد ثانيتين
          setTimeout(function() {
            console.log('[Sadara] Sending guestToken (backup 2s)');
            window.postMessage({type: 'guestToken', guestToken: TOKEN}, '*');
          }, 2000);

          // إرسال احتياطي بعد 5 ثواني
          setTimeout(function() {
            console.log('[Sadara] Sending guestToken (backup 5s)');
            window.postMessage({type: 'guestToken', guestToken: TOKEN}, '*');
          }, 5000);

          console.log('[Sadara] Guest token injector installed');
        })();
      ''');
      _log('✅ تم حقن Guest Token');
    } catch (e) {
      _log('❌ خطأ في حقن Guest Token: $e');
    }
  }

  /// جلب بيانات الشارتات مباشرة من API وهو على نفس الـ origin (dashboard.ftth.iq)
  Future<void> _directFetchSupersetSlices() async {
    if (_guestToken == null) {
      _log('❌ لا يوجد Guest Token للجلب المباشر');
      return;
    }

    _log('📊 بدء جلب الشارتات مباشرة من dashboard.ftth.iq...');
    final escapedToken = _escapeJs(_guestToken!);

    await _controller.executeScript('''
      (async function() {
        const GUEST_TOKEN = '$escapedToken';
        const SLICES = [34, 35, 36, 37, 38, 46, 48, 51, 52];
        window.__sdCharts = window.__sdCharts || [];

        console.log('[Sadara] Direct fetch: ' + SLICES.length + ' slices via /chart/{id}/data/');
        console.log('[Sadara] GuestToken: ' + GUEST_TOKEN.substring(0, 30) + '...');

        for (const sliceId of SLICES) {
          try {
            // استخدام endpoint الصحيح: /api/v1/chart/{id}/data/
            // هذا الـ endpoint يجلب بيانات الشارت مباشرة بالـ ID بدون الحاجة لـ query context
            const url = '/api/v1/chart/' + sliceId + '/data/?dashboard_id=7&force=false';

            console.log('[Sadara] Fetching slice ' + sliceId + ': ' + url);

            const resp = await fetch(url, {
              headers: {
                'Authorization': 'Bearer ' + GUEST_TOKEN,
                'X-GuestToken': GUEST_TOKEN,
                'Accept': 'application/json'
              }
            });

            const text = await resp.text();
            console.log('[Sadara] Slice ' + sliceId + ' HTTP ' + resp.status + ' len=' + text.length);

            let data;
            try { data = JSON.parse(text); } catch(e) {
              console.error('[Sadara] Slice ' + sliceId + ' JSON parse error: ' + text.substring(0, 200));
              // حتى لو فشل الـ parse، نسجل الاستجابة للتشخيص
              window.__sdCharts.push({
                u: 'chart/' + sliceId + '/data',
                d: {error: 'JSON parse error', raw: text.substring(0, 500), status: resp.status},
                t: Date.now()
              });
              try { window.chrome.webview.postMessage('CHART:' + window.__sdCharts.length); } catch(e2) {}
              continue;
            }

            if (resp.ok) {
              // تسجيل بنية الاستجابة للتشخيص
              const keys = Object.keys(data);
              console.log('[Sadara] Slice ' + sliceId + ' keys: ' + keys.join(', '));

              if (data.result && Array.isArray(data.result)) {
                const rowcount = data.result[0]?.rowcount ?? data.result[0]?.data?.length ?? 0;
                console.log('[Sadara] Slice ' + sliceId + ' ✅ rows=' + rowcount);
              }
            } else {
              console.error('[Sadara] Slice ' + sliceId + ' ❌ HTTP ' + resp.status);
              // تسجيل تفاصيل الخطأ
              if (data.errors) {
                data.errors.forEach(function(err) {
                  console.error('[Sadara]   error_type: ' + err.error_type + ' msg: ' + (err.message || ''));
                });
              }
            }

            // تسجيل الاستجابة (نجاح أو فشل) للتشخيص
            window.__sdCharts.push({
              u: 'chart/' + sliceId + '/data',
              d: data,
              t: Date.now(),
              status: resp.status
            });
            try {
              window.chrome.webview.postMessage('CHART:' + window.__sdCharts.length);
            } catch(e2) {}

          } catch(e) {
            console.error('[Sadara] Slice ' + sliceId + ' exception: ' + e.message);
            window.__sdCharts.push({
              u: 'chart/' + sliceId + '/data',
              d: {error: e.message},
              t: Date.now(),
              status: 0
            });
            try { window.chrome.webview.postMessage('CHART:' + window.__sdCharts.length); } catch(e2) {}
          }
        }

        console.log('[Sadara] Direct fetch complete. Total: ' + window.__sdCharts.length);
      })();
    ''');

    _log('✅ تم حقن سكربت الجلب المباشر');
  }

  /// جلب بيانات Superset مباشرة عبر فتح الداشبورد المدمج في WebView
  Future<void> _fetchSupersetDirect() async {
    _log('═══════════════════════════════════════════');
    _log('🚀 بدء جلب Superset مباشر');
    _log('═══════════════════════════════════════════');

    if (!mounted) return;
    setState(() {
      _isFetchingSupersetDirect = true;
      _supersetAutoSaveDone = false;
      _statusMessage = '🔄 تحضير جلب Superset...';
      _capturedCharts.clear();
      _chartCount = 0;
    });

    // 1. استخراج Auth Token من WebView
    if (_extractedAuthToken == null && _isInitialized) {
      _log('🔍 استخراج Auth Token...');
      await _extractAuthTokenFromWebView();
    }

    if (_extractedAuthToken == null) {
      _log('❌ لا يوجد Auth Token — سجّل الدخول أولاً');
      if (mounted) setState(() {
        _isFetchingSupersetDirect = false;
        _statusMessage = '❌ سجّل الدخول أولاً ثم اضغط الزر';
      });
      return;
    }

    // 2. جلب Guest Token
    _log('🔑 جلب Guest Token...');
    if (mounted) setState(() => _statusMessage = '🔑 جلب رمز المصادقة...');
    await _fetchGuestToken();

    if (_guestToken == null) {
      _log('❌ فشل في الحصول على Guest Token');
      if (mounted) setState(() {
        _isFetchingSupersetDirect = false;
        _statusMessage = '❌ فشل في المصادقة';
      });
      return;
    }

    // 3. تخزين Guest Token للحقن بعد التحميل
    _pendingGuestTokenForEmbed = _guestToken;

    // 4. حقن سكربت يعمل قبل أي JS في الصفحة (addScriptToExecuteOnDocumentCreated)
    //    لخداع Superset بأن الصفحة مفتوحة داخل iframe + تقديم guest token
    _log('🔧 حقن سكربت خداع iframe...');
    if (mounted) setState(() => _statusMessage = '🔧 تحضير بيئة Superset...');

    // تنظيف السكربت السابق إن وجد
    if (_supersetScriptId != null) {
      try {
        await _controller
            .removeScriptToExecuteOnDocumentCreated(_supersetScriptId!);
      } catch (_) {}
      _supersetScriptId = null;
    }

    final escapedToken = _escapeJs(_guestToken!);
    final scriptId =
        await _controller.addScriptToExecuteOnDocumentCreated('''
      (function() {
        // فقط على صفحات dashboard.ftth.iq
        if (!location.href.includes('dashboard.ftth.iq')) return;
        if (window.__sdSupersetInjected) return;
        window.__sdSupersetInjected = true;

        const GUEST_TOKEN = '$escapedToken';
        console.log('[Sadara] === Superset Injector Starting ===');

        // ═══════════════════════════════════════════
        // 1. FETCH INTERCEPTOR — يجب أن يعمل قبل أي JS من Superset
        //    لأن Superset يحفظ reference للـ fetch الأصلي عند التهيئة
        // ═══════════════════════════════════════════
        window.__sdCharts = [];
        var chartCount = 0;

        var origFetch = window.fetch;
        window.fetch = function(url, opts) {
          var urlStr = (url && url.url) ? url.url : (url ? url.toString() : '');
          var method = (opts && opts.method) ? opts.method : (url && url.method ? url.method : 'GET');

          return origFetch.apply(this, arguments).then(function(resp) {
            // التقاط استجابات chart/data
            if (urlStr.includes('/chart/data') || urlStr.includes('/chart/')) {
              var clone = resp.clone();
              clone.json().then(function(d) {
                // استخراج slice_id من الطلب
                var sliceId = null;
                try {
                  if (opts && opts.body) {
                    var body = typeof opts.body === 'string' ? JSON.parse(opts.body) : opts.body;
                    sliceId = body.form_data && body.form_data.slice_id;
                  }
                } catch(e) {}
                if (!sliceId) {
                  try { var m = urlStr.match(/slice_id[^0-9]*([0-9]+)/); if(m) sliceId = parseInt(m[1]); } catch(e){}
                }

                // تجاهل الاستجابات الفاشلة
                if (d && d.result && Array.isArray(d.result) && d.result.length > 0) {
                  var rowcount = d.result[0].rowcount || (d.result[0].data ? d.result[0].data.length : 0);
                  console.log('[Sadara] ✅ Chart captured: ' + method + ' ' + urlStr.substring(0, 80) + ' rows=' + rowcount + ' slice=' + sliceId);
                  window.__sdCharts.push({u: urlStr, d: d, t: Date.now(), slice_id: sliceId, status: resp.status});
                  chartCount++;
                  try { window.chrome.webview.postMessage('CHART:' + chartCount); } catch(e) {}
                } else if (d && !d.errors) {
                  console.log('[Sadara] 📊 Chart response (no result array): ' + urlStr.substring(0, 80));
                  window.__sdCharts.push({u: urlStr, d: d, t: Date.now(), slice_id: sliceId, status: resp.status});
                  chartCount++;
                  try { window.chrome.webview.postMessage('CHART:' + chartCount); } catch(e) {}
                } else {
                  console.warn('[Sadara] ❌ Chart error: ' + urlStr.substring(0, 80) + ' status=' + resp.status);
                }
              }).catch(function(e) {
                console.warn('[Sadara] Chart JSON parse failed: ' + urlStr.substring(0, 80));
              });
            }
            return resp;
          });
        };
        console.log('[Sadara] ✅ Fetch interceptor installed (before Superset JS)');

        // ═══════════════════════════════════════════
        // 2. IFRAME TRICK — خداع Superset بأن الصفحة داخل iframe
        // ═══════════════════════════════════════════
        try {
          var fakeParent = {
            postMessage: function(msg, origin) {
              console.log('[Sadara] parent.postMessage received:', JSON.stringify(msg));
              // عندما ترسل Superset رسالة 'ready' نرد بـ guestToken
              if (msg && msg.type === 'ready') {
                console.log('[Sadara] 🔑 Superset sent ready! Sending guestToken...');
                // إرسال عبر postMessage
                setTimeout(function() {
                  window.postMessage({type: 'guestToken', guestToken: GUEST_TOKEN}, '*');
                }, 50);
                // إرسال احتياطي عبر dispatchEvent (يعمل حتى لو postMessage لا يصل)
                setTimeout(function() {
                  try {
                    window.dispatchEvent(new MessageEvent('message', {
                      data: {type: 'guestToken', guestToken: GUEST_TOKEN},
                      origin: window.location.origin
                    }));
                    console.log('[Sadara] 🔑 Sent guestToken via dispatchEvent');
                  } catch(e) { console.warn('[Sadara] dispatchEvent failed:', e); }
                }, 100);
              }
            }
          };
          Object.defineProperty(window, 'parent', {
            get: function() { return fakeParent; },
            configurable: true
          });
          console.log('[Sadara] ✅ window.parent overridden');
        } catch(e) {
          console.warn('[Sadara] Failed to override parent:', e);
        }

        // أيضاً خداع frameElement check
        try {
          Object.defineProperty(window, 'frameElement', {
            get: function() { return document.createElement('iframe'); },
            configurable: true
          });
        } catch(e) {}

        // ═══════════════════════════════════════════
        // 3. GUEST TOKEN — إرسال متعدد المحاولات
        // ═══════════════════════════════════════════
        // استماع لرسائل 'ready' التي قد تصل عبر addEventListener
        window.addEventListener('message', function(e) {
          if (e.data && e.data.type === 'ready') {
            console.log('[Sadara] 🔄 Received ready via addEventListener, sending guestToken');
            window.postMessage({type: 'guestToken', guestToken: GUEST_TOKEN}, '*');
          }
        });

        // إرسال احتياطي مكثف بعد تأخيرات مختلفة
        [300, 1000, 2000, 3000, 5000, 8000, 12000, 20000].forEach(function(delay) {
          setTimeout(function() {
            console.log('[Sadara] 🔑 Backup guestToken send at ' + delay + 'ms (charts so far: ' + chartCount + ')');
            window.postMessage({type: 'guestToken', guestToken: GUEST_TOKEN}, '*');
            // أيضاً عبر dispatchEvent
            try {
              window.dispatchEvent(new MessageEvent('message', {
                data: {type: 'guestToken', guestToken: GUEST_TOKEN},
                origin: window.location.origin
              }));
            } catch(e) {}
          }, delay);
        });

        console.log('[Sadara] === Superset Injector Ready ===');
      })();
    ''');
    _supersetScriptId = scriptId;
    _log('✅ تم حقن سكربت خداع iframe (id: $scriptId)');

    // 5. بناء رابط embedded مع Authorization لتجاوز APISIX
    const dashboardUuid = '2a63cc44-01f4-4c59-a620-7d280c01411d';
    final embedUrl =
        'https://dashboard.ftth.iq/embedded/$dashboardUuid?uiConfig=11&Authorization=Bearer%20$_extractedAuthToken';

    _log('🌐 فتح Superset Dashboard...');
    if (mounted) setState(() => _statusMessage = '🌐 فتح Superset Dashboard...');

    await _controller.loadUrl(embedUrl);
    // الباقي يتم في callback الـ navigationCompleted:
    // - حقن interceptor تلقائي (يلتقط chart/data requests)
    // - حقن guest token احتياطي عبر postMessage
    // - حفظ تلقائي بعد التقاط 5+ شارت
  }

  /// حفظ تلقائي لبيانات Superset المُلتقطة من الشارتات
  Future<void> _autoSaveSupersetCharts() async {
    if (!_isFetchingSupersetDirect || !mounted) return;

    _log('💾 حفظ تلقائي لبيانات Superset...');

    try {
      // استخراج بيانات الشارتات من WebView
      final result = await _controller.executeScript(r'''
        (function() {
          if (window.__sdCharts && window.__sdCharts.length > 0) {
            return JSON.stringify(window.__sdCharts);
          }
          return "[]";
        })();
      ''');

      if (result == null) {
        _log('⚠️ لا توجد بيانات شارت');
        return;
      }

      String jsonStr = result.toString();
      if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
        jsonStr = jsonStr.substring(1, jsonStr.length - 1);
        jsonStr = jsonStr.replaceAll(r'\"', '"');
      }

      final List<dynamic> charts = jsonDecode(jsonStr);
      if (charts.isEmpty) {
        _log('⚠️ قائمة الشارتات فارغة');
        return;
      }

      _log('📊 تم التقاط ${charts.length} شارت');

      // تحويل البيانات لصيغة متوافقة مع server_data_page
      _capturedCharts.clear();
      for (var chart in charts) {
        final url = chart['u']?.toString() ?? '';
        // استخراج slice_id من الـ URL
        int? sliceId;
        final sliceMatch = RegExp(r'slice_id["\s:]+(\d+)').firstMatch(url);
        if (sliceMatch != null) {
          sliceId = int.tryParse(sliceMatch.group(1) ?? '');
        }

        _capturedCharts.add({
          'url': url,
          'data': chart['d'],
          'timestamp': chart['t'],
          'slice_id': sliceId,
        });
        _log('   📈 Slice ${sliceId ?? "?"}: ${_getRowCount(chart['d'])} صف');
      }

      // حفظ كملف
      await _saveData();

      if (mounted) setState(() {
        _isFetchingSupersetDirect = false;
        _chartCount = _capturedCharts.length;
        _statusMessage = '✅ تم حفظ ${_capturedCharts.length} شارت من Superset!';
      });

      _log('✅ تم حفظ بيانات Superset بنجاح');
      _log('═══════════════════════════════════════════');

      // تنظيف السكربت المحقون
      if (_supersetScriptId != null) {
        try {
          await _controller
              .removeScriptToExecuteOnDocumentCreated(_supersetScriptId!);
          _supersetScriptId = null;
          _log('🧹 تم تنظيف سكربت خداع iframe');
        } catch (_) {}
      }
    } catch (e) {
      _log('❌ خطأ في حفظ بيانات Superset: $e');
      if (mounted) setState(() {
        _isFetchingSupersetDirect = false;
        _statusMessage = '❌ خطأ في الحفظ';
      });
    }
  }

  /// جلب كل البيانات من Dashboard API (الوكلاء والمناطق)
  Future<void> _fetchFromDashboardApi() async {
    _log('═══════════════════════════════════════════');
    _log('🚀 بدء جلب بيانات Dashboard API');
    _log('═══════════════════════════════════════════');

    // أولاً: محاولة استخراج auth token من WebView إذا لم يكن موجوداً
    if (_extractedAuthToken == null && _isInitialized) {
      _log('🔍 محاولة استخراج Auth Token من WebView...');
      await _extractAuthTokenFromWebView();
      _log(_extractedAuthToken != null
          ? '✅ تم استخراج Auth Token: ${_extractedAuthToken!.substring(0, 30)}...'
          : '⚠️ لم يتم استخراج Auth Token');
    }

    // جلب Guest Token إذا لم يكن موجوداً
    if (_guestToken == null) {
      _log('⚠️ Guest Token غير موجود - جلب جديد...');
      if (mounted) setState(() {
        _statusMessage = '🔑 جلب رمز المصادقة...';
        _isFetchingFromApi = true;
      });
      await _fetchGuestToken();
    } else {
      _log('✅ Guest Token موجود مسبقاً: ${_guestToken!.substring(0, 20)}...');
    }

    if (_guestToken == null) {
      _log('❌ فشل نهائي في الحصول على Guest Token');
      if (mounted) setState(() {
        _isFetchingFromApi = false;
        _statusMessage = '❌ فشل في المصادقة - سجّل الدخول أولاً';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('فشل في المصادقة - اضغط 📋 لعرض السجلات'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
                label: '📋', onPressed: _showLogs, textColor: Colors.white),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isFetchingFromApi = true;
      _statusMessage = '📊 جاري جلب بيانات الوكلاء والمناطق...';
    });

    try {
      // قائمة الشارتات المطلوب جلبها (نفس صفحة مشروع داشبورد)
      final chartsToFetch = [
        {
          'slice_id': 52,
          'name': 'zones_detailed',
          'desc': 'تفاصيل المناطق والمقاولين'
        },
        {
          'slice_id': 48,
          'name': 'timeseries_weekly',
          'desc': 'السلسلة الأسبوعية'
        },
        {
          'slice_id': 51,
          'name': 'timeseries_monthly',
          'desc': 'السلسلة الشهرية'
        },
        {'slice_id': 46, 'name': 'timeseries_46', 'desc': 'سلسلة زمنية'},
        {'slice_id': 34, 'name': 'users_34', 'desc': 'إحصائيات المستخدمين'},
        {'slice_id': 35, 'name': 'users_35', 'desc': 'إحصائيات المستخدمين 2'},
      ];

      _log('📋 عدد الشارتات المطلوبة: ${chartsToFetch.length}');

      int successCount = 0;
      int totalRows = 0;

      for (var i = 0; i < chartsToFetch.length; i++) {
        final chart = chartsToFetch[i];
        if (!mounted) {
          _log('⚠️ Widget unmounted - إيقاف');
          break;
        }

        final sliceId = chart['slice_id'];
        final chartName = chart['name'];
        _log(
            '🔄 [${i + 1}/${chartsToFetch.length}] جلب $chartName (slice_id: $sliceId)...');

        if (mounted) setState(() {
          _statusMessage =
              '📊 جلب ${chart['desc']} (${i + 1}/${chartsToFetch.length})...';
        });

        try {
          _log('📤 إرسال طلب GET مباشر...');
          _log('   - slice_id: $sliceId');
          _log('   - dashboard_id: 7');
          _log('   - guestToken: ${_guestToken!.substring(0, 20)}...');
          _log(
              '   - authToken: ${_extractedAuthToken != null ? "موجود" : "غير موجود"}');

          // استخدام HTTP GET مباشرة مع logging كامل
          final formData = Uri.encodeComponent('{"slice_id":$sliceId}');
          final url = Uri.parse(
              'https://dashboard.ftth.iq/api/v1/chart/data?form_data=$formData&dashboard_id=7');

          _log('   - URL: $url');

          // بناء headers مع Authorization للـ API Gateway
          final headers = <String, String>{
            'x-guesttoken': _guestToken!,
            'Accept': 'application/json',
            'origin': 'https://dashboard.ftth.iq',
            'referer': 'https://dashboard.ftth.iq/embedded/7',
          };

          // إضافة Authorization header للـ API Gateway (APISIX)
          if (_extractedAuthToken != null && _extractedAuthToken!.isNotEmpty) {
            headers['Authorization'] = 'Bearer $_extractedAuthToken';
            _log('   - إضافة Authorization header');
          }

          final response = await http
              .get(
                url,
                headers: headers,
              )
              .timeout(const Duration(seconds: 30));

          _log('   - Status: ${response.statusCode}');
          _log(
              '   - Response: ${response.body.length > 200 ? "${response.body.substring(0, 200)}..." : response.body}');

          if (response.statusCode == 200) {
            final jsonBody = json.decode(response.body);

            if (jsonBody['error_msg'] != null) {
              _log('❌ خطأ API: ${jsonBody['error_msg']}');
            } else {
              final resultList = jsonBody['result'] as List?;
              if (resultList != null && resultList.isNotEmpty) {
                final chartData = resultList[0] as Map<String, dynamic>;
                final dataList = chartData['data'] as List? ?? [];
                final colnames = chartData['colnames'];
                _log('✅ $chartName: ${dataList.length} سجل');
                _log('   - الأعمدة: ${colnames?.toString() ?? "غير محدد"}');

                _capturedCharts.add({
                  'type': chartName,
                  'url': 'dashboard_api_slice_$sliceId',
                  'data': {
                    'result': [
                      {'data': dataList}
                    ]
                  },
                  'colnames': colnames,
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                });
                successCount++;
                totalRows += dataList.length;
              } else {
                _log('❌ $chartName: result فارغ');
              }
            }
          } else {
            _log('❌ $chartName: HTTP ${response.statusCode}');
          }
        } catch (e, stackTrace) {
          _log('❌ استثناء في جلب $chartName');
          _log(
              '📋 Stack: ${stackTrace.toString().split('\n').take(3).join('\n')}');
        }
      }

      _log('═══════════════════════════════════════════');
      _log('📊 ملخص الجلب: $successCount نجاح، $totalRows سجل إجمالي');
      _log('═══════════════════════════════════════════');

      if (mounted) setState(() {
        _isFetchingFromApi = false;
        _chartCount = _capturedCharts.length;
        _statusMessage = successCount > 0
            ? '✅ تم جلب $successCount شارت ($totalRows سجل)'
            : '❌ فشل في جلب البيانات - اضغط ❓ للسجلات';
      });

      if (successCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ تم جلب $successCount شارت ($totalRows سجل) - اضغط حفظ 💾'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('❌ فشل - اضغط 📋 لعرض السجلات'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
                label: '📋', onPressed: _showLogs, textColor: Colors.white),
          ),
        );
      }
    } catch (e, stackTrace) {
      _log('❌ استثناء عام');
      _log('📋 Stack: ${stackTrace.toString().split('\n').take(5).join('\n')}');
      if (mounted) setState(() {
        _isFetchingFromApi = false;
        _statusMessage = '❌ خطأ';
      });
    }
  }

  /// جلب جميع المناطق (613) باستخدام Python script
  Future<void> _fetchAllZones() async {
    final scriptsPath = '${FtthServerDataService.dashboardPath}\\scripts';
    final scriptFile = File('$scriptsPath\\fetch_all_zones_no_filter.py');

    if (!await scriptFile.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'سكربت Python غير موجود!\n$scriptsPath\\fetch_all_zones_no_filter.py'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // تأكيد قبل البدء
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.public, color: Colors.green),
            SizedBox(width: 8),
            Text('جلب كل المناطق (613)'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('سيتم جلب بيانات جميع الـ 613 منطقة'),
            SizedBox(height: 12),
            Text('ملاحظات:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('• سيفتح متصفح للتعامل مع Cloudflare'),
            Text('• قد يستغرق وقتاً أطول (5-10 دقائق)'),
            Text('• تأكد من تثبيت playwright'),
            Text('• لا تغلق نافذة المتصفح!',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.play_arrow),
            label: const Text('بدء الجلب'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isFetchingAllZones = true;
      _statusMessage = '🌍 جاري جلب 613 منطقة...';
    });

    try {
      final process = await Process.start(
        'python',
        ['-u', scriptFile.path],
        workingDirectory: scriptsPath,
        runInShell: true,
        environment: {
          'PYTHONIOENCODING': 'utf-8',
          'PYTHONLEGACYWINDOWSSTDIO': '0',
        },
      );

      // قراءة الخرج
      process.stdout.transform(utf8.decoder).listen((data) {
        if (mounted) {
          setState(() => _statusMessage = data.trim());
        }
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('Python Error: $data');
      });

      // انتظار انتهاء العملية
      final exitCode = await process.exitCode;

      if (mounted) setState(() {
        _isFetchingAllZones = false;
        _statusMessage = exitCode == 0
            ? '✅ تم جلب جميع المناطق (613) بنجاح!'
            : '❌ فشل مع كود: $exitCode';
      });

      if (exitCode == 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم جلب جميع المناطق! تحقق من مجلد البيانات'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() {
        _isFetchingAllZones = false;
        _statusMessage = '❌ خطأ';
      });
    }
  }

  /// حفظ البيانات
  Future<void> _saveData() async {
    if (_capturedCharts.isEmpty) {
      // محاولة استخراج أولاً
      await _extractData();
      if (_capturedCharts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'لا توجد بيانات لحفظها - حاول الضغط على زر الاستخراج أولاً'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');

      final file = File('${dir.path}/ftth_data_$timestamp.json');
      final dataToSave = {
        'timestamp': timestamp,
        'url': _currentUrl,
        'charts_count': _chartCount,
        'charts': _capturedCharts,
      };

      await file.writeAsString(jsonEncode(dataToSave));

      // تحميل في الخدمة
      final success = await FtthDataService.instance.loadFromFile(file.path);
      final stats = FtthDataService.instance.getStatistics();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '✅ تم الحفظ\n📍 ${stats.totalZones} منطقة'
                  : '✅ تم حفظ الملف:\n${file.path}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// مسح البيانات
  void _clearData() {
    setState(() {
      _capturedCharts.clear();
      _capturedApiCalls.clear();
      _chartCount = 0;
      _requestCount = 0;
      _statusMessage = 'تم مسح البيانات';
    });
  }

  /// تحديث الصفحة
  Future<void> _refresh() async {
    await _controller.reload();
  }

  @override
  void dispose() {
    // تنظيف السكربت المحقون إن وجد
    if (_supersetScriptId != null) {
      _controller
          .removeScriptToExecuteOnDocumentCreated(_supersetScriptId!)
          .catchError((_) {});
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('جلب بيانات الموقع'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          // 📊 زر جلب Superset مباشرة (يفتح الداشبورد في WebView)
          IconButton(
            icon: _isFetchingSupersetDirect
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.cyan),
                  )
                : const Icon(Icons.auto_graph, color: Colors.cyan),
            onPressed: _isFetchingSupersetDirect ? null : _fetchSupersetDirect,
            tooltip: '📊 جلب Superset مباشرة',
          ),
          // 🔷 زر جلب بيانات الوكلاء من Dashboard API
          IconButton(
            icon: _isFetchingFromApi
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.amber),
                  )
                : const Icon(Icons.people, color: Colors.amber),
            onPressed: _isFetchingFromApi ? null : _fetchFromDashboardApi,
            tooltip: '📊 جلب الوكلاء والمناطق من API',
          ),
          // 🌍 زر جلب جميع المناطق (613)
          IconButton(
            icon: _isFetchingAllZones
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.lightGreen),
                  )
                : const Icon(Icons.public, color: Colors.lightGreen),
            onPressed: _isFetchingAllZones ? null : _fetchAllZones,
            tooltip: '🌍 جلب كل المناطق (613)',
          ),
          const VerticalDivider(color: Colors.white54, width: 16),
          // زر التحديث
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'تحديث',
          ),
          // زر الاستخراج
          IconButton(
            icon: _isExtracting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download),
            onPressed: _isExtracting ? null : _extractData,
            tooltip: 'استخراج البيانات من الصفحة',
          ),
          // زر المسح
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearData,
            tooltip: 'مسح',
          ),
          // زر الحفظ
          IconButton(
            icon: Badge(
              label: Text('$_chartCount'),
              isLabelVisible: _chartCount > 0,
              child: const Icon(Icons.save),
            ),
            onPressed: _saveData,
            tooltip: 'حفظ',
          ),
          // 📋 زر عرض السجلات
          IconButton(
            icon: Badge(
              label: Text('${_logs.length}'),
              isLabelVisible: _logs.isNotEmpty,
              backgroundColor: Colors.orange,
              child: const Icon(Icons.article_outlined),
            ),
            onPressed: _showLogs,
            tooltip: '📋 عرض سجل العمليات',
          ),
          // 🌐 زر عرض API Traffic
          IconButton(
            icon: Badge(
              label: Text('${_capturedApiCalls.length}'),
              isLabelVisible: _capturedApiCalls.isNotEmpty,
              backgroundColor: Colors.deepPurple,
              child: const Icon(Icons.http),
            ),
            onPressed: _showApiTraffic,
            tooltip: 'API Traffic',
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط الحالة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.teal.shade50,
            child: Row(
              children: [
                Icon(
                  _isLoading ? Icons.sync : Icons.check_circle,
                  color: _isLoading ? Colors.orange : Colors.green,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: Colors.teal.shade800,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
                // إحصائيات
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.upload, size: 14, color: Colors.blue.shade700),
                      Text(' $_requestCount ',
                          style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                      const SizedBox(width: 8),
                      Icon(Icons.download,
                          size: 14, color: Colors.green.shade700),
                      Text(' $_responseCount ',
                          style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                      const SizedBox(width: 8),
                      Icon(Icons.bar_chart,
                          size: 14, color: Colors.purple.shade700),
                      Text(' $_chartCount',
                          style: TextStyle(
                              color: Colors.purple.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // شريط العنوان
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                const Icon(Icons.link, size: 14, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentUrl.isEmpty ? _loginUrl : _currentUrl,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // المتصفح
          Expanded(
            child: _isInitialized
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      return Webview(
                        _controller,
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                      );
                    },
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('جاري تهيئة المتصفح...'),
                      ],
                    ),
                  ),
          ),

          // شريط البيانات
          if (_capturedCharts.isNotEmpty)
            Container(
              height: 80,
              padding: const EdgeInsets.all(8),
              color: Colors.grey.shade200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'البيانات المسجلة ($_chartCount)',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _capturedCharts.length,
                      itemBuilder: (context, index) {
                        final chart = _capturedCharts[index];
                        final rowCount = _getRowCount(chart['data']);
                        return Card(
                          margin: const EdgeInsets.only(right: 6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.table_chart,
                                    color: Colors.teal, size: 18),
                                const SizedBox(width: 4),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('${index + 1}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11)),
                                    Text('$rowCount صف',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.grey.shade600)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),

      // زر التعليمات
      floatingActionButton: FloatingActionButton(
        onPressed: _showInstructions,
        backgroundColor: Colors.teal,
        mini: true,
        child: const Icon(Icons.help_outline, color: Colors.white),
      ),
    );
  }

  int _getRowCount(dynamic data) {
    try {
      if (data is Map && data['result'] != null) {
        final result = data['result'];
        if (result is List && result.isNotEmpty) {
          final firstResult = result[0];
          if (firstResult is Map && firstResult['data'] != null) {
            return (firstResult['data'] as List).length;
          }
        }
      }
    } catch (_) {}
    return 0;
  }

  void _showInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.teal),
            SizedBox(width: 8),
            Text('تعليمات الاستخدام'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📋 استخراج من الصفحة:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('1. سجّل الدخول في صفحة admin.ftth.iq'),
              Text('2. انتقل إلى الداشبورد المطلوب'),
              Text('3. انتظر تحميل البيانات'),
              Text('4. اضغط زر الاستخراج ⬇️ لجلب البيانات'),
              Text('5. اضغط زر الحفظ 💾'),
              SizedBox(height: 12),
              Divider(),
              SizedBox(height: 12),
              Text('📊 جلب الوكلاء والمناطق (زر 👥 الأصفر):',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('• يجلب بيانات الوكلاء والمناطق من Dashboard API مباشرة'),
              Text('• لا يحتاج تصفح - يعمل تلقائياً'),
              SizedBox(height: 12),
              Text('🌍 جلب كل المناطق 613 (زر 🌍 الأخضر):',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('• يشغّل سكربت Python'),
              Text('• يفتح متصفح للتعامل مع Cloudflare'),
              Text('• قد يستغرق 5-10 دقائق'),
              SizedBox(height: 12),
              Text(
                '💡 إذا لم تظهر بيانات، جرب الانتقال لصفحة أخرى ثم العودة',
                style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                    fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('فهمت'),
          ),
        ],
      ),
    );
  }
}
