import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_state_views.dart';

/// مستكشف الساس المتقدّم — أداة اكتشاف شاملة لواجهة SAS4 API.
///
/// متصفّح مدمج (WebView2) يفتح لوحة الساس؛ يتنقّل المستخدم ويسجّل دخوله بنفسه
/// (لا يُحقن أي اعتماد)، بينما يلتقط حقنُ JS كلَّ طلب `fetch`/`XHR` (المسار
/// · الطريقة · الحمولة المشفّرة · الاستجابة). ثم:
/// - «فكّ الكل»: يرسل الحمولات/الاستجابات المشفّرة إلى بوّابة الصدارة لفكّها
///   (الفكّ خادمي بمفتاح SAS4 الثابت — بلا اعتماد في الواجهة).
/// - كتالوج API تلقائي: نقطة فريدة لكل (method+path منظّف من المعرّفات) مع
///   التكرار وعيّنات الحمولة/الاستجابة والحقول المستنتَجة، مُصنّفة حسب المجال.
/// - تحليل بنية وأمان دفاعي + تصدير JSON و Markdown.
///
/// على غير ويندوز: يُتاح فتح اللوحة في المتصفّح النظامي (بلا التقاط).
class SasExplorerPage extends StatefulWidget {
  final SasAccount account;
  const SasExplorerPage({super.key, required this.account});

  @override
  State<SasExplorerPage> createState() => _SasExplorerPageState();
}

// JS يُحقَن قبل كل صفحة: يرقّع fetch و XMLHttpRequest ويرسل كل طلب إلى Dart.
const String _injectJs = r'''
(function(){
  if (window.__capInstalled) return; window.__capInstalled = true;
  function post(o){ try { window.chrome.webview.postMessage(JSON.stringify(o)); } catch(e){} }
  var of = window.fetch;
  if (of) window.fetch = function(input, init){
    var url = (typeof input === 'string') ? input : (input && input.url);
    var method = (init && init.method) || (typeof input==='object' && input.method) || 'GET';
    var body = (init && init.body) ? String(init.body) : '';
    return of.apply(this, arguments).then(function(res){
      try { res.clone().text().then(function(t){
        post({ts:Date.now(),type:'fetch',method:method,url:url,req:body,status:res.status,res:(t||'').slice(0,40000)});
      }); } catch(e){ post({ts:Date.now(),type:'fetch',method:method,url:url,req:body,status:res.status}); }
      return res;
    });
  };
  var oOpen = XMLHttpRequest.prototype.open, oSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(m,u){ this.__m=m; this.__u=u; return oOpen.apply(this, arguments); };
  XMLHttpRequest.prototype.send = function(b){
    var x=this;
    x.addEventListener('loadend', function(){
      post({ts:Date.now(),type:'xhr',method:x.__m,url:x.__u,req:b?String(b):'',status:x.status,res:(x.responseText||'').slice(0,40000)});
    });
    return oSend.apply(this, arguments);
  };
})();
''';

// ============================================================
//  نماذج داخلية للالتقاط والكتالوج
// ============================================================

/// طلب ملتقَط واحد.
class _Cap {
  final int ts;
  final String type; // fetch | xhr
  final String method;
  final String url;
  final String req; // الحمولة الخام (قد تكون مشفّرة)
  final int status;
  final String res; // الاستجابة الخام (قد تكون مشفّرة)

  // نصوص مفكوكة (تُملأ عند «فكّ الكل»)
  String? reqDecrypted;
  String? resDecrypted;

  _Cap({
    required this.ts,
    required this.type,
    required this.method,
    required this.url,
    required this.req,
    required this.status,
    required this.res,
  });

  factory _Cap.fromMap(Map m) => _Cap(
        ts: (m['ts'] is num) ? (m['ts'] as num).toInt() : 0,
        type: (m['type'] ?? '').toString(),
        method: (m['method'] ?? 'GET').toString().toUpperCase(),
        url: (m['url'] ?? '').toString(),
        req: (m['req'] ?? '').toString(),
        status: (m['status'] is num) ? (m['status'] as num).toInt() : 0,
        res: (m['res'] ?? '').toString(),
      );

  /// المسار فقط (بلا المضيف ولا الـ query).
  String get path {
    try {
      final u = Uri.parse(url);
      return u.path;
    } catch (_) {
      final q = url.indexOf('?');
      return q >= 0 ? url.substring(0, q) : url;
    }
  }

  Map<String, dynamic> toExportJson() => {
        'ts': ts,
        'type': type,
        'method': method,
        'url': url,
        'status': status,
        'req': req,
        if (reqDecrypted != null) 'reqDecrypted': reqDecrypted,
        'res': res,
        if (resDecrypted != null) 'resDecrypted': resDecrypted,
      };
}

/// نقطة API مُهيكلة في الكتالوج (مجمّعة حسب method + path منظّف).
class _Endpoint {
  final String method;
  final String normPath; // المسار بعد تنظيف المعرّفات: /user/{id}
  final String domain; // المجال المستنتَج
  int count = 0;
  _Cap? sample; // آخر عيّنة
  final Set<String> reqFields = {};
  final Set<String> resFields = {};
  final Set<int> statuses = {};

  _Endpoint({
    required this.method,
    required this.normPath,
    required this.domain,
  });

  String get key => '$method $normPath';
}

class _SasExplorerPageState extends State<SasExplorerPage> {
  final WebviewController _controller = WebviewController();
  final TextEditingController _addr = TextEditingController();
  final TextEditingController _searchCtl = TextEditingController();

  final List<_Cap> _caps = [];
  StreamSubscription? _msgSub;

  bool _ready = false;
  bool _isLoading = false;
  String? _initError;

  // فلاتر
  bool _onlyApi = true;
  String _search = '';
  String _domainFilter = ''; // '' = الكل

  // تبويبات العرض: 0 طلبات · 1 كتالوج · 2 بنية/أمان
  int _tab = 0;

  bool _decrypting = false;

  /// عنوان اللوحة الابتدائي: عنوان خادم الحساب كما هو (بلا سرّ) مع بروتوكول.
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
    if (Platform.isWindows) _init();
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    if (_ready) _controller.dispose();
    _addr.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final url = _panelUrl;
    _addr.text = url.isEmpty ? 'https://' : url;
    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.white);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.allow);
      await _controller.addScriptToExecuteOnDocumentCreated(_injectJs);
      _msgSub = _controller.webMessage.listen(_onMessage);
      _controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() => _isLoading = state == LoadingState.loading);
      });
      if (_addr.text != 'https://') await _controller.loadUrl(_addr.text);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = e.toString().replaceFirst('Exception: ', '').trim();
        });
      }
    }
  }

  // ------------------------------------------------------------
  //  الالتقاط
  // ------------------------------------------------------------

  void _onMessage(dynamic raw) {
    try {
      final m = raw is String ? jsonDecode(raw) : raw;
      if (m is Map) {
        final url = (m['url'] ?? '').toString();
        if (_onlyApi && !_looksApi(url)) return;
        if (!mounted) return;
        setState(() => _caps.add(_Cap.fromMap(m)));
      }
    } catch (_) {}
  }

  // طلبات البيانات الحقيقية فقط — نستبعد الترجمة/الموارد والأصول الساكنة.
  static const _noise = [
    'resources/language', 'resources/forms', 'resources/menu',
    'resources/login', 'maps.google', 'gen_204', 'firebase', '.js', '.css',
    '.png', '.jpg', '.jpeg', '.svg', '.woff', '.ico', '/assets/',
  ];
  bool _looksApi(String url) {
    if (!url.contains('/api/')) return false;
    final u = url.toLowerCase();
    for (final n in _noise) {
      if (u.contains(n)) return false;
    }
    return true;
  }

  Future<void> _go() async {
    var u = _addr.text.trim();
    if (u.isEmpty) return;
    if (!u.startsWith('http')) u = 'https://$u';
    await _controller.loadUrl(u);
  }

  // ------------------------------------------------------------
  //  فكّ التشفير (خادمي — دفعات)
  // ------------------------------------------------------------

  /// هل النص يبدو حمولة ساس مشفّرة؟ (payload= أو base64 يبدأ بـ U2FsdGVk).
  static bool _looksEncrypted(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    if (t.contains('payload=')) return true;
    if (t.startsWith('U2FsdGVk')) return true; // "Salted__" base64
    // أحياناً يأتي مغلّفاً JSON {"d":"U2FsdGVk..."} — تحقّق سريع:
    if (t.contains('U2FsdGVk')) return true;
    return false;
  }

  /// استخراج الحمولة المشفّرة الخام من نص قد يكون `payload=....` أو JSON أو خام.
  static String _extractPayload(String s) {
    var t = s.trim();
    final idx = t.indexOf('payload=');
    if (idx >= 0) {
      t = t.substring(idx + 'payload='.length);
      final amp = t.indexOf('&');
      if (amp >= 0) t = t.substring(0, amp);
      try {
        t = Uri.decodeComponent(t);
      } catch (_) {}
      return t.trim();
    }
    // نص خام مشفّر (استجابة غالباً)
    final u = t.indexOf('U2FsdGVk');
    if (u >= 0) {
      var tail = t.substring(u);
      // قطع أي محارف تغليف (علامات اقتباس/فواصل) من النهاية.
      final m = RegExp(r'^[A-Za-z0-9+/=]+').firstMatch(tail);
      if (m != null) tail = m.group(0)!;
      return tail;
    }
    return t;
  }

  Future<void> _decryptAll() async {
    if (_decrypting) return;
    // اجمع (الفهرس، نوع الحقل، الحمولة) لكل ما يبدو مشفّراً وغير مفكوك.
    final tasks = <_DecTask>[];
    for (var i = 0; i < _caps.length; i++) {
      final c = _caps[i];
      if (c.reqDecrypted == null && _looksEncrypted(c.req)) {
        tasks.add(_DecTask(i, true, _extractPayload(c.req)));
      }
      if (c.resDecrypted == null && _looksEncrypted(c.res)) {
        tasks.add(_DecTask(i, false, _extractPayload(c.res)));
      }
    }
    if (tasks.isEmpty) {
      _snack('لا توجد حمولات مشفّرة لفكّها');
      return;
    }
    setState(() => _decrypting = true);
    try {
      var done = 0;
      const batch = 500;
      for (var start = 0; start < tasks.length; start += batch) {
        final slice = tasks.sublist(
            start, (start + batch).clamp(0, tasks.length));
        final items = slice.map((t) => t.payload).toList();
        final results =
            await SasAgentApiService.instance.decryptPayloads(items);
        for (var j = 0; j < slice.length; j++) {
          final t = slice[j];
          final r = j < results.length ? results[j] : null;
          final ok = r != null && (r['ok'] == true);
          final text = ok
              ? (r['text'] ?? '').toString()
              : '⚠️ ${(r?['error'] ?? 'تعذّر الفكّ').toString()}';
          if (t.isReq) {
            _caps[t.index].reqDecrypted = text;
          } else {
            _caps[t.index].resDecrypted = text;
          }
        }
        done += slice.length;
        if (mounted) setState(() {});
      }
      if (mounted) _snack('فُكّ $done عنصراً مشفّراً');
    } catch (e) {
      if (mounted) _snack('تعذّر فكّ التشفير: ${_clean(e)}', error: true);
    } finally {
      if (mounted) setState(() => _decrypting = false);
    }
  }

  // ------------------------------------------------------------
  //  الكتالوج + البنية + الأمان (مُستنتَج من الملتقَط)
  // ------------------------------------------------------------

  /// تنظيف المسار: المقاطع الرقمية/UUID تتحوّل إلى {id}.
  static String _normalize(String path) {
    final parts = path.split('/');
    final out = parts.map((p) {
      if (p.isEmpty) return p;
      if (RegExp(r'^\d+$').hasMatch(p)) return '{id}';
      if (RegExp(r'^[0-9a-fA-F]{8}-').hasMatch(p)) return '{uuid}';
      if (p.length >= 16 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(p)) {
        return '{hash}';
      }
      return p;
    });
    return out.join('/');
  }

  /// استنتاج المجال من المسار (user/manager/report/index/billing/auth…).
  static String _domainOf(String normPath) {
    final p = normPath.toLowerCase();
    bool has(String s) => p.contains('/$s') || p.contains('$s/');
    if (has('login') || has('auth') || has('logout') || has('session')) {
      return 'auth';
    }
    if (has('report')) return 'report';
    if (has('index')) return 'index';
    if (has('billing') || has('invoice') || has('payment') || has('receipt') ||
        has('transaction')) {
      return 'billing';
    }
    if (has('manager') || has('reseller') || has('admin')) return 'manager';
    if (has('user') || has('subscriber') || has('customer')) return 'user';
    if (has('profile') || has('package') || has('plan')) return 'package';
    return 'other';
  }

  /// استخراج مفاتيح من نص JSON مفكوك (سطح أول) — للحقول المستنتَجة.
  static Set<String> _topKeys(String? text) {
    if (text == null || text.isEmpty) return const {};
    try {
      final d = jsonDecode(text);
      if (d is Map) return d.keys.map((e) => e.toString()).toSet();
      if (d is List && d.isNotEmpty && d.first is Map) {
        return (d.first as Map).keys.map((e) => e.toString()).toSet();
      }
    } catch (_) {}
    return const {};
  }

  /// بناء الكتالوج من الطلبات الملتقطة (طلبات API فقط).
  Map<String, _Endpoint> _buildCatalog() {
    final map = <String, _Endpoint>{};
    for (final c in _caps) {
      if (!_looksApi(c.url)) continue;
      final norm = _normalize(c.path);
      final domain = _domainOf(norm);
      final ep = map.putIfAbsent(
        '${c.method} $norm',
        () => _Endpoint(method: c.method, normPath: norm, domain: domain),
      );
      ep.count++;
      ep.sample = c;
      ep.statuses.add(c.status);
      ep.reqFields.addAll(_topKeys(c.reqDecrypted ?? c.req));
      ep.resFields.addAll(_topKeys(c.resDecrypted ?? c.res));
    }
    return map;
  }

  /// المجالات المتاحة (للفلترة) مرتّبة.
  List<String> _availableDomains() {
    final set = <String>{};
    for (final c in _caps) {
      if (!_looksApi(c.url)) continue;
      set.add(_domainOf(_normalize(c.path)));
    }
    final list = set.toList()..sort();
    return list;
  }

  /// حقول حسّاسة ظاهرة في الاستجابات المفكوكة (تحليل أمني دفاعي).
  static const _sensitiveKeys = [
    'password', 'passwd', 'pass', 'token', 'secret', 'api_key', 'apikey',
    'national_id', 'nationalid', 'ssn', 'card', 'cvv', 'pin', 'otp',
    'private_key', 'authorization',
  ];
  Set<String> _detectSensitive() {
    final found = <String>{};
    for (final c in _caps) {
      final hay = (c.resDecrypted ?? c.res).toLowerCase();
      for (final k in _sensitiveKeys) {
        if (hay.contains('"$k"') || hay.contains("'$k'")) found.add(k);
      }
    }
    return found;
  }

  _SecuritySummary _security() {
    final hasBearer = _caps.any((c) =>
        c.req.toLowerCase().contains('bearer') ||
        c.url.toLowerCase().contains('token'));
    final hasAesEnc = _caps.any((c) =>
        _looksEncrypted(c.req) || _looksEncrypted(c.res));
    final anyHttp = _caps.any((c) => c.url.startsWith('http://'));
    final anyHttps = _caps.any((c) => c.url.startsWith('https://'));
    return _SecuritySummary(
      authMechanism: hasBearer ? 'Bearer / token' : 'جلسة/كوكيز (غير ظاهر)',
      encryption: hasAesEnc ? 'AES (Salted__ / payload=)' : 'بلا تشفير ظاهر',
      protocol: anyHttp
          ? (anyHttps ? 'http + https (⚠️ طلبات غير مشفّرة موجودة)' : 'http (⚠️ غير آمن)')
          : (anyHttps ? 'https' : 'غير معروف'),
      sensitive: _detectSensitive(),
    );
  }

  // ------------------------------------------------------------
  //  التصدير (JSON + Markdown)
  // ------------------------------------------------------------

  String _exportJson() {
    final catalog = _buildCatalog();
    return const JsonEncoder.withIndent('  ').convert({
      'account': widget.account.displayName,
      'captured_count': _caps.length,
      'endpoint_count': catalog.length,
      'endpoints': catalog.values
          .map((e) => {
                'method': e.method,
                'path': e.normPath,
                'domain': e.domain,
                'count': e.count,
                'statuses': e.statuses.toList(),
                'reqFields': e.reqFields.toList(),
                'resFields': e.resFields.toList(),
                'sampleReq': e.sample?.reqDecrypted ?? e.sample?.req,
                'sampleRes': e.sample?.resDecrypted ?? e.sample?.res,
              })
          .toList(),
      'requests': _caps.map((c) => c.toExportJson()).toList(),
    });
  }

  String _exportMarkdown() {
    final catalog = _buildCatalog();
    final sec = _security();
    final byDomain = <String, List<_Endpoint>>{};
    for (final e in catalog.values) {
      byDomain.putIfAbsent(e.domain, () => []).add(e);
    }
    final b = StringBuffer();
    b.writeln('# خريطة SAS4 API — ${widget.account.displayName}');
    b.writeln();
    b.writeln('- تاريخ التوليد: ${DateTime.now().toIso8601String()}');
    b.writeln('- الطلبات الملتقطة: ${_caps.length}');
    b.writeln('- النقاط الفريدة: ${catalog.length}');
    b.writeln();
    b.writeln('## ملاحظات الأمان');
    b.writeln('- آلية المصادقة: ${sec.authMechanism}');
    b.writeln('- التشفير: ${sec.encryption}');
    b.writeln('- البروتوكول: ${sec.protocol}');
    b.writeln('- حقول حسّاسة ظاهرة: '
        '${sec.sensitive.isEmpty ? 'لا شيء' : sec.sensitive.join('، ')}');
    b.writeln();
    b.writeln('## البنية حسب المجال');
    final domains = byDomain.keys.toList()..sort();
    for (final d in domains) {
      final eps = byDomain[d]!..sort((a, z) => a.normPath.compareTo(z.normPath));
      b.writeln();
      b.writeln('### $d (${eps.length})');
      b.writeln();
      b.writeln('| الطريقة | المسار | التكرار | الحالات | حقول الطلب | حقول الرد |');
      b.writeln('|---|---|---|---|---|---|');
      for (final e in eps) {
        b.writeln('| ${e.method} | `${e.normPath}` | ${e.count} | '
            '${e.statuses.join(", ")} | '
            '${e.reqFields.take(8).join(", ")} | '
            '${e.resFields.take(8).join(", ")} |');
      }
    }
    return b.toString();
  }

  Future<void> _export() async {
    if (_caps.isEmpty) {
      _snack('لا توجد طلبات ملتقطة للتصدير', error: true);
      return;
    }
    try {
      final dir = await _exportDir();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final base = 'sas_explorer_$stamp';
      final jsonPath = '${dir.path}${Platform.pathSeparator}$base.json';
      final mdPath = '${dir.path}${Platform.pathSeparator}$base.md';
      await File(jsonPath).writeAsString(_exportJson());
      await File(mdPath).writeAsString(_exportMarkdown());
      if (mounted) _snack('حُفظ التقرير في:\n$jsonPath');
    } catch (e) {
      if (mounted) _snack('تعذّر الحفظ: ${_clean(e)}', error: true);
    }
  }

  Future<Directory> _exportDir() async {
    // مجلد المستندات (مُفضّل)، وإلا سطح المكتب على ويندوز، وإلا المؤقّت.
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {}
    if (Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) {
        final d = Directory('$profile${Platform.pathSeparator}Desktop');
        if (await d.exists()) return d;
      }
    }
    return Directory.systemTemp;
  }

  Future<void> _copyJson() async {
    if (_caps.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _exportJson()));
    if (mounted) _snack('نُسخ ${_caps.length} طلباً (JSON) إلى الحافظة');
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

  // ------------------------------------------------------------
  //  أدوات
  // ------------------------------------------------------------

  String _clean(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.cairo()),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  List<_Cap> get _filteredCaps {
    final q = _search.trim().toLowerCase();
    return _caps.where((c) {
      if (_onlyApi && !_looksApi(c.url)) return false;
      if (_domainFilter.isNotEmpty &&
          _domainOf(_normalize(c.path)) != _domainFilter) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay =
            '${c.url} ${c.method} ${c.reqDecrypted ?? c.req} ${c.resDecrypted ?? c.res}'
                .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  // ============================================================
  //  البناء
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: _appBar(),
        body: _body(),
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    final encryptedCount = _caps
        .where((c) => _looksEncrypted(c.req) || _looksEncrypted(c.res))
        .length;
    return AppBar(
      elevation: 0,
      toolbarHeight: 56,
      backgroundColor: AppTheme.primaryColor,
      iconTheme: const IconThemeData(color: Colors.white),
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
          Text('مستكشف الساس المتقدّم',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Colors.white)),
          Text(
              '${widget.account.displayName} · التُقط ${_caps.length}'
              '${encryptedCount > 0 ? ' · مشفّر $encryptedCount' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.cairo(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.80))),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'فتح في المتصفّح',
          onPressed: _openInBrowser,
          icon: const Icon(Icons.open_in_new_rounded, size: 20),
        ),
        if (Platform.isWindows) ...[
          IconButton(
            tooltip: 'نسخ JSON',
            onPressed: _caps.isEmpty ? null : _copyJson,
            icon: const Icon(Icons.copy_rounded, size: 20),
          ),
          IconButton(
            tooltip: 'مسح السجلّ',
            onPressed:
                _caps.isEmpty ? null : () => setState(_caps.clear),
            icon: const Icon(Icons.delete_sweep_rounded, size: 20),
          ),
        ],
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _body() {
    if (!Platform.isWindows) {
      return SasEmptyView(
        message:
            'مستكشف الساس المدمج متاح على سطح مكتب ويندوز.\nيمكنك فتح اللوحة في المتصفّح.',
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
      return SasErrorView(
          message:
              'تعذّر تشغيل المتصفّح المدمج (WebView2):\n$_initError\n\nيتطلّب «WebView2 Runtime» (مثبّت افتراضياً على ويندوز 11).',
          onRetry: _init);
    }
    if (!_ready) {
      return const SasLoadingView(message: 'جاري تهيئة المتصفّح المدمج…');
    }

    // تخطيط أفقي على الشاشات العريضة: المتصفّح يمين · لوحة الفحص يسار.
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 1000;
      final browser = _browserPane();
      final inspector = _inspectorPane();
      if (wide) {
        return Row(
          children: [
            Expanded(flex: 5, child: browser),
            const VerticalDivider(width: 1),
            Expanded(flex: 4, child: inspector),
          ],
        );
      }
      return Column(
        children: [
          Expanded(flex: 3, child: browser),
          const Divider(height: 1),
          Expanded(flex: 4, child: inspector),
        ],
      );
    });
  }

  // لوحة المتصفّح + شريط العنوان + أدوات التنقّل.
  Widget _browserPane() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(children: [
            _navBtn(Icons.arrow_forward_rounded, 'رجوع',
                () => _controller.goBack()),
            _navBtn(Icons.arrow_back_rounded, 'أمام',
                () => _controller.goForward()),
            _navBtn(Icons.refresh_rounded, 'تحديث',
                () => _controller.reload()),
            _navBtn(Icons.home_rounded, 'الرئيسية', () {
              _addr.text = _panelUrl;
              _go();
            }),
            const SizedBox(width: 6),
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _addr,
                  textDirection: TextDirection.ltr,
                  style: GoogleFonts.robotoMono(fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    prefixIcon: const Icon(Icons.public_rounded, size: 18),
                    hintText: 'رابط لوحة الساس',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onTap: () => _addr.selection = TextSelection(
                      baseOffset: 0, extentOffset: _addr.text.length),
                  onSubmitted: (_) => _go(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: _go,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text('اذهب',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        if (_isLoading)
          const LinearProgressIndicator(
              color: AppTheme.primaryColor, minHeight: 2),
        Expanded(child: Webview(_controller)),
      ],
    );
  }

  Widget _navBtn(IconData icon, String tip, VoidCallback onTap) {
    return IconButton(
      tooltip: tip,
      onPressed: onTap,
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: AppTheme.primaryColor),
    );
  }

  // لوحة الفحص (تبويبات + شريط أدوات + بحث/تصفية + المحتوى).
  Widget _inspectorPane() {
    return Column(
      children: [
        _toolbar(),
        _tabBar(),
        _filterBar(),
        Expanded(child: _tabContent()),
      ],
    );
  }

  Widget _toolbar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        Icon(Icons.sensors_rounded,
            size: 18, color: AppTheme.successColor),
        const SizedBox(width: 6),
        Text('${_filteredCaps.length} / ${_caps.length}',
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.w700, fontSize: 12.5)),
        const SizedBox(width: 10),
        Tooltip(
          message: 'طلبات API فقط',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(
              value: _onlyApi,
              activeThumbColor: AppTheme.primaryColor,
              onChanged: (v) => setState(() => _onlyApi = v),
            ),
            Text('API',
                style: GoogleFonts.cairo(
                    fontSize: 11.5, fontWeight: FontWeight.w600)),
          ]),
        ),
        const Spacer(),
        _toolBtn(
          icon: _decrypting
              ? Icons.hourglass_top_rounded
              : Icons.lock_open_rounded,
          label: _decrypting ? 'جارٍ…' : 'فكّ الكل',
          color: AppTheme.warningColor,
          onTap: _decrypting ? null : _decryptAll,
        ),
        const SizedBox(width: 6),
        _toolBtn(
          icon: Icons.save_alt_rounded,
          label: 'تصدير',
          color: AppTheme.primaryColor,
          onTap: _caps.isEmpty ? null : _export,
        ),
      ]),
    );
  }

  Widget _toolBtn({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icon, size: 16),
      label: Text(label,
          style: GoogleFonts.cairo(
              fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }

  Widget _tabBar() {
    const labels = ['الطلبات المباشرة', 'الكتالوج', 'البنية / الأمان'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Row(
        children: List.generate(labels.length, (i) {
          final sel = _tab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: sel
                      ? AppTheme.primaryColor
                      : AppTheme.primaryColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : AppTheme.primaryColor,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _filterBar() {
    final domains = _availableDomains();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: [
          SizedBox(
            height: 38,
            child: TextField(
              controller: _searchCtl,
              style: GoogleFonts.cairo(fontSize: 12.5),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _searchCtl.clear();
                          setState(() => _search = '');
                        },
                      ),
                hintText: 'بحث في المسار/الحمولة/الاستجابة…',
                hintStyle: GoogleFonts.cairo(fontSize: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          if (domains.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _domainChip('الكل', ''),
                  ...domains.map((d) => _domainChip(d, d)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _domainChip(String label, String value) {
    final sel = _domainFilter == value;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ChoiceChip(
        label: Text(label,
            style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: sel ? Colors.white : AppTheme.primaryColor)),
        selected: sel,
        showCheckmark: false,
        selectedColor: AppTheme.primaryColor,
        backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.06),
        side: BorderSide(
            color: AppTheme.primaryColor.withValues(alpha: 0.18)),
        onSelected: (_) => setState(() => _domainFilter = value),
      ),
    );
  }

  Widget _tabContent() {
    switch (_tab) {
      case 1:
        return _catalogView();
      case 2:
        return _structureView();
      default:
        return _requestsView();
    }
  }

  // ---------- تبويب 0: الطلبات المباشرة ----------
  Widget _requestsView() {
    final list = _filteredCaps.reversed.toList(); // الأحدث أولاً
    if (list.isEmpty) {
      return const SasEmptyView(
        message:
            'لا طلبات بعد.\nتصفّح لوحة الساس وسجّل دخولك؛ ستظهر الطلبات هنا تلقائياً.',
        icon: Icons.travel_explore_rounded,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _RequestCard(cap: list[i]),
    );
  }

  // ---------- تبويب 1: الكتالوج ----------
  Widget _catalogView() {
    final catalog = _buildCatalog().values.toList()
      ..sort((a, b) {
        final d = a.domain.compareTo(b.domain);
        return d != 0 ? d : a.normPath.compareTo(b.normPath);
      });
    final filtered = catalog.where((e) {
      if (_domainFilter.isNotEmpty && e.domain != _domainFilter) return false;
      final q = _search.trim().toLowerCase();
      if (q.isNotEmpty && !e.key.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
    if (filtered.isEmpty) {
      return const SasEmptyView(
        message: 'لا نقاط في الكتالوج بعد.\nالتقط طلبات ثم عد هنا.',
        icon: Icons.account_tree_rounded,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _EndpointCard(ep: filtered[i]),
    );
  }

  // ---------- تبويب 2: البنية / الأمان ----------
  Widget _structureView() {
    if (_caps.isEmpty) {
      return const SasEmptyView(
        message: 'لا بيانات للتحليل بعد.',
        icon: Icons.security_rounded,
      );
    }
    final catalog = _buildCatalog();
    final byDomain = <String, List<_Endpoint>>{};
    for (final e in catalog.values) {
      byDomain.putIfAbsent(e.domain, () => []).add(e);
    }
    final domains = byDomain.keys.toList()..sort();
    final sec = _security();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _securityCard(sec),
        const SizedBox(height: 12),
        SasSectionHeader(
          title: 'شجرة المجالات',
          icon: Icons.account_tree_rounded,
          trailingText: '${catalog.length} نقطة',
        ),
        const SizedBox(height: 10),
        ...domains.map((d) {
          final eps = byDomain[d]!
            ..sort((a, z) => a.normPath.compareTo(z.normPath));
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: SasUi.card(),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              shape: const Border(),
              leading: SasUi.gradientBadge(
                icon: _domainIcon(d),
                colors: AppTheme.blueGradient,
                size: 32,
                iconSize: 16,
              ),
              title: Text(d,
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w800, fontSize: 13.5)),
              subtitle: Text('${eps.length} نقطة',
                  style: GoogleFonts.cairo(
                      fontSize: 11, color: Colors.grey[600])),
              childrenPadding:
                  const EdgeInsets.fromLTRB(14, 0, 14, 10),
              children: eps
                  .map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          _methodPill(e.method),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(e.normPath,
                                style: GoogleFonts.robotoMono(fontSize: 11.5)),
                          ),
                          Text('×${e.count}',
                              style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey[600])),
                        ]),
                      ))
                  .toList(),
            ),
          );
        }),
      ],
    );
  }

  Widget _securityCard(_SecuritySummary sec) {
    final warn = sec.protocol.contains('⚠️') || sec.sensitive.isNotEmpty;
    final c = warn ? AppTheme.warningColor : AppTheme.successColor;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: SasUi.card(borderColor: c.withValues(alpha: 0.3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SasUi.gradientBadge(
              icon: warn
                  ? Icons.gpp_maybe_rounded
                  : Icons.verified_user_rounded,
              colors: [c, c.withValues(alpha: 0.7)],
              size: 34,
              iconSize: 18,
            ),
            const SizedBox(width: 10),
            Text('ملخّص أمني دفاعي',
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w800, fontSize: 14)),
          ]),
          const SizedBox(height: 12),
          _secRow(Icons.key_rounded, 'آلية المصادقة', sec.authMechanism),
          _secRow(Icons.lock_rounded, 'التشفير', sec.encryption),
          _secRow(
              sec.protocol.contains('⚠️')
                  ? Icons.warning_amber_rounded
                  : Icons.https_rounded,
              'البروتوكول',
              sec.protocol),
          _secRow(
              Icons.privacy_tip_rounded,
              'حقول حسّاسة ظاهرة',
              sec.sensitive.isEmpty
                  ? 'لا شيء مكتشَف'
                  : sec.sensitive.join('، ')),
        ],
      ),
    );
  }

  Widget _secRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: Text(label,
              style: GoogleFonts.cairo(
                  fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Text(value,
              style: GoogleFonts.cairo(
                  fontSize: 12, color: Colors.grey[800])),
        ),
      ]),
    );
  }

  Widget _methodPill(String method) => _pill(method);

  /// pill للطريقة — مشترك بين لوحة البنية والبطاقات.
  static Widget _pill(String method) {
    final color = _methodColor(method);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(method,
          style: GoogleFonts.robotoMono(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  static Color _methodColor(String m) {
    switch (m.toUpperCase()) {
      case 'GET':
        return AppTheme.infoColor;
      case 'POST':
        return AppTheme.successColor;
      case 'PUT':
      case 'PATCH':
        return AppTheme.warningColor;
      case 'DELETE':
        return AppTheme.errorColor;
      default:
        return AppTheme.secondaryColor;
    }
  }

  static IconData _domainIcon(String d) {
    switch (d) {
      case 'auth':
        return Icons.vpn_key_rounded;
      case 'report':
        return Icons.assessment_rounded;
      case 'index':
        return Icons.list_alt_rounded;
      case 'billing':
        return Icons.receipt_long_rounded;
      case 'manager':
        return Icons.admin_panel_settings_rounded;
      case 'user':
        return Icons.person_rounded;
      case 'package':
        return Icons.inventory_2_rounded;
      default:
        return Icons.api_rounded;
    }
  }
}

/// مهمّة فكّ واحدة (مرجع للطلب + الحقل + الحمولة).
class _DecTask {
  final int index;
  final bool isReq;
  final String payload;
  _DecTask(this.index, this.isReq, this.payload);
}

/// ملخّص أمني دفاعي مُستنتَج.
class _SecuritySummary {
  final String authMechanism;
  final String encryption;
  final String protocol;
  final Set<String> sensitive;
  _SecuritySummary({
    required this.authMechanism,
    required this.encryption,
    required this.protocol,
    required this.sensitive,
  });
}

// ============================================================
//  بطاقة طلب مباشر (قابلة للطيّ: خام ↔ مفكوك)
// ============================================================
class _RequestCard extends StatefulWidget {
  final _Cap cap;
  const _RequestCard({required this.cap});
  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _expanded = false;

  Color get _statusColor {
    final s = widget.cap.status;
    if (s >= 200 && s < 300) return AppTheme.successColor;
    if (s >= 400) return AppTheme.errorColor;
    if (s >= 300) return AppTheme.warningColor;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cap;
    return Container(
      decoration: SasUi.card(),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(SasUi.radius),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              _SasExplorerPageState._pill(c.method),
              const SizedBox(width: 8),
              Expanded(
                child: Text(c.path,
                    maxLines: _expanded ? 3 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.robotoMono(fontSize: 11.5)),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${c.status}',
                    style: GoogleFonts.robotoMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _statusColor)),
              ),
              Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: Colors.grey),
            ]),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 8),
                _block('الحمولة (req)', c.req, c.reqDecrypted),
                const SizedBox(height: 8),
                _block('الاستجابة (res)', c.res, c.resDecrypted),
              ],
            ),
          ),
      ]),
    );
  }

  Widget _block(String title, String raw, String? decrypted) {
    final hasDec = decrypted != null && decrypted.isNotEmpty;
    final shown = hasDec ? decrypted : raw;
    if (shown.trim().isEmpty) {
      return Text('$title: —',
          style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(title,
              style: GoogleFonts.cairo(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryColor)),
          const SizedBox(width: 6),
          if (hasDec)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('مفكوك',
                  style: GoogleFonts.cairo(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.successColor)),
            )
          else if (_SasExplorerPageState._looksEncrypted(raw))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('مشفّر',
                  style: GoogleFonts.cairo(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.warningColor)),
            ),
        ]),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
          ),
          child: SelectableText(
            _pretty(shown),
            textDirection: TextDirection.ltr,
            style: GoogleFonts.robotoMono(fontSize: 10.5, height: 1.4),
          ),
        ),
      ],
    );
  }

  String _pretty(String s) {
    final t = s.trim();
    try {
      final d = jsonDecode(t);
      return const JsonEncoder.withIndent('  ').convert(d);
    } catch (_) {
      return t.length > 4000 ? '${t.substring(0, 4000)}…' : t;
    }
  }
}

// ============================================================
//  بطاقة نقطة كتالوج
// ============================================================
class _EndpointCard extends StatelessWidget {
  final _Endpoint ep;
  const _EndpointCard({required this.ep});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: SasUi.card(),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: const Border(),
        title: Row(children: [
          _SasExplorerPageState._pill(ep.method),
          const SizedBox(width: 8),
          Expanded(
            child: Text(ep.normPath,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.robotoMono(fontSize: 11.5)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('×${ep.count}',
                style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryColor)),
          ),
        ]),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Text('المجال: ${ep.domain}',
                style: GoogleFonts.cairo(
                    fontSize: 10.5, color: Colors.grey[600])),
            const SizedBox(width: 10),
            Text('الحالات: ${ep.statuses.join(", ")}',
                style: GoogleFonts.cairo(
                    fontSize: 10.5, color: Colors.grey[600])),
          ]),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          if (ep.reqFields.isNotEmpty)
            _fields('حقول الطلب', ep.reqFields, AppTheme.infoColor),
          if (ep.resFields.isNotEmpty)
            _fields('حقول الرد', ep.resFields, AppTheme.successColor),
          if (ep.sample != null) ...[
            const SizedBox(height: 8),
            _sample('عيّنة حمولة',
                ep.sample!.reqDecrypted ?? ep.sample!.req),
            const SizedBox(height: 6),
            _sample('عيّنة استجابة',
                ep.sample!.resDecrypted ?? ep.sample!.res),
          ],
        ],
      ),
    );
  }

  Widget _fields(String title, Set<String> fields, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.cairo(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: fields
                .map((f) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(5),
                        border:
                            Border.all(color: color.withValues(alpha: 0.25)),
                      ),
                      child: Text(f,
                          style: GoogleFonts.robotoMono(
                              fontSize: 10, color: color)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _sample(String title, String text) {
    final t = text.trim();
    if (t.isEmpty) return const SizedBox.shrink();
    String pretty;
    try {
      pretty = const JsonEncoder.withIndent('  ').convert(jsonDecode(t));
    } catch (_) {
      pretty = t.length > 1500 ? '${t.substring(0, 1500)}…' : t;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.cairo(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.grey[700])),
        const SizedBox(height: 3),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FC),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.16)),
          ),
          child: SelectableText(
            pretty,
            textDirection: TextDirection.ltr,
            style: GoogleFonts.robotoMono(fontSize: 10, height: 1.4),
          ),
        ),
      ],
    );
  }
}
