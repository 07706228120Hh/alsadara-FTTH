/// حقن كوكي cf_clearance + User-Agent في كل طلبات admin.ftth.iq
///
/// بعد أن يحلّ المشغّل تحدّي Cloudflare في WebView، نقرأ كوكي cf_clearance
/// (HttpOnly) عبر getCookies (تعديل native)، ثم نثبّت HttpOverrides عالمي يحقن
/// الكوكي + نفس الـ User-Agent في كل طلبات النطاق — شفّاف لكل نداءات http
/// في التطبيق دون لمس أي شاشة.
///
/// cf_clearance مرتبط بـ (IP + User-Agent): التطبيق يعمل من نفس جهاز المشغّل
/// (نفس IP)، ونستخدم نفس الـ UA الذي حلّ به التحدّي.
library;

import 'dart:io';

class FtthCfClearance {
  FtthCfClearance._();
  static final FtthCfClearance instance = FtthCfClearance._();

  static const String origin = 'https://admin.ftth.iq';
  static const String host = 'admin.ftth.iq';

  /// هل المضيف ضمن نطاق ftth.iq (admin/api/dashboard...)؟
  static bool isFtthHost(String h) =>
      h == 'ftth.iq' || h.endsWith('.ftth.iq');

  /// User-Agent ثابت — يجب أن يطابق ما يرسله WebView عند حلّ التحدّي
  static const String userAgentString =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  String? _cookieHeader; // "cf_clearance=...; cf_bm=..."
  bool _installed = false;

  String? get cookieHeader => _cookieHeader;
  String get userAgent => userAgentString;
  bool get hasClearance => _cookieHeader != null && _cookieHeader!.isNotEmpty;

  /// تحديث الكوكي وتثبيت HttpOverrides (مرة واحدة)
  void update(String cookieHeader) {
    _cookieHeader = cookieHeader;
    if (!_installed) {
      HttpOverrides.global = _FtthHttpOverrides();
      _installed = true;
    }
  }

  void clear() => _cookieHeader = null;
}

class _FtthHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final inner = super.createHttpClient(context);
    inner.userAgent = FtthCfClearance.userAgentString;
    return _FtthHttpClient(inner);
  }
}

/// عميل HTTP مفوِّض: يمرّر كل شيء للعميل الداخلي، ويحقن Cookie + UA لطلبات
/// admin.ftth.iq فقط.
class _FtthHttpClient implements HttpClient {
  final HttpClient _i;
  _FtthHttpClient(this._i);

  /// api.ftth.iq نطاق Cloudflare منفصل يُسقط اتصال Dart؛ نعيد توجيهه إلى
  /// admin.ftth.iq (نفس backend البوابة، ونملك تصريح cf_clearance له).
  static Uri _rewrite(Uri url) {
    if (url.host == 'api.ftth.iq') {
      return url.replace(host: 'admin.ftth.iq');
    }
    return url;
  }

  Future<HttpClientRequest> _inject(
      Future<HttpClientRequest> future, Uri url) async {
    final req = await future;
    if (FtthCfClearance.isFtthHost(url.host)) {
      final cf = FtthCfClearance.instance;
      final cookie = cf.cookieHeader;
      if (cookie != null && cookie.isNotEmpty) {
        req.headers.set(HttpHeaders.cookieHeader, cookie);
      }
      req.headers.set(HttpHeaders.userAgentHeader, cf.userAgent);
    }
    return req;
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    final u = _rewrite(url);
    return _inject(_i.openUrl(method, u), u);
  }

  @override
  Future<HttpClientRequest> open(
      String method, String host, int port, String path) {
    final u = _rewrite(Uri(scheme: 'https', host: host, port: port, path: path));
    return _inject(_i.openUrl(method, u), u);
  }

  // دوال مختصرة → عبر openUrl/open لضمان الحقن
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('get', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('post', url);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('put', url);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('delete', url);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('patch', url);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('head', url);
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      open('get', host, port, path);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      open('post', host, port, path);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      open('put', host, port, path);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      open('delete', host, port, path);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      open('patch', host, port, path);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      open('head', host, port, path);

  // خصائص مفوَّضة
  @override
  bool get autoUncompress => _i.autoUncompress;
  @override
  set autoUncompress(bool v) => _i.autoUncompress = v;
  @override
  Duration get idleTimeout => _i.idleTimeout;
  @override
  set idleTimeout(Duration v) => _i.idleTimeout = v;
  @override
  Duration? get connectionTimeout => _i.connectionTimeout;
  @override
  set connectionTimeout(Duration? v) => _i.connectionTimeout = v;
  @override
  int? get maxConnectionsPerHost => _i.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? v) => _i.maxConnectionsPerHost = v;
  @override
  String? get userAgent => _i.userAgent;
  @override
  set userAgent(String? v) => _i.userAgent = v;

  // ردود نداء مفوَّضة
  @override
  set authenticate(
          Future<bool> Function(Uri url, String scheme, String? realm)? f) =>
      _i.authenticate = f;
  @override
  set authenticateProxy(
          Future<bool> Function(
                  String host, int port, String scheme, String? realm)?
              f) =>
      _i.authenticateProxy = f;
  @override
  set findProxy(String Function(Uri url)? f) => _i.findProxy = f;
  @override
  set badCertificateCallback(
          bool Function(X509Certificate cert, String host, int port)? cb) =>
      _i.badCertificateCallback = cb;
  @override
  set connectionFactory(
          Future<ConnectionTask<Socket>> Function(
                  Uri url, String? proxyHost, int? proxyPort)?
              f) =>
      _i.connectionFactory = f;
  @override
  set keyLog(Function(String line)? cb) => _i.keyLog = cb;

  @override
  void addCredentials(
          Uri url, String realm, HttpClientCredentials credentials) =>
      _i.addCredentials(url, realm, credentials);
  @override
  void addProxyCredentials(
          String host, int port, String realm, HttpClientCredentials creds) =>
      _i.addProxyCredentials(host, port, realm, creds);
  @override
  void close({bool force = false}) => _i.close(force: force);
}
