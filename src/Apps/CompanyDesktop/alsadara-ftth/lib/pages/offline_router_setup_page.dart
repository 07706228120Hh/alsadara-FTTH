/// أداة إعداد الراوتر أوفلاين — Wizard خطوة بخطوة
/// تعمل بدون إنترنت — فقط اتصال محلي بالراوتر
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:webview_windows/webview_windows.dart' as wvwin;
import '../services/router_adapter_service.dart';
import '../services/pending_subscribers_service.dart';

// ═══════ ثوابت ACS ═══════
const String _acsUrl = 'http://187.124.177.236:7547';

// ═══════ الحقول المطلوبة في إعدادات TR-069 ═══════
const _acsFields = <Map<String, String>>[
  {'label': 'ACS URL', 'value': _acsUrl},
  {'label': 'Periodic Inform', 'value': 'Enabled'},
  {'label': 'Inform Interval', 'value': '300'},
  {'label': 'ACS Username', 'value': '(فارغ)'},
  {'label': 'ACS Password', 'value': '(فارغ)'},
];

// ═══════ قاعدة بيانات الراوترات (أوفلاين) ═══════
class RouterProfile {
  final String brand;
  final String icon;
  final bool supportsTr069;
  final String defaultIp;
  final String defaultUser;
  final String defaultPass;
  final String tr069Path;
  final List<String> altUsers;
  final List<String> altPasswords;
  final List<String> keywords;
  const RouterProfile({
    required this.brand, required this.icon, this.supportsTr069 = true,
    required this.defaultIp, required this.defaultUser, required this.defaultPass,
    required this.tr069Path, this.altUsers = const [], this.altPasswords = const [],
    required this.keywords,
  });
}

const _routerProfiles = <RouterProfile>[
  RouterProfile(brand: 'Huawei ONU/ONT', icon: '📡', defaultIp: '192.168.100.1', defaultUser: 'telecomadmin', defaultPass: 'admintelecom',
    altUsers: ['root', 'admin'], altPasswords: ['adminHW', 'admin', 'NWTF5x%RaijrgnaS#', 'NWTF5x%'],
    tr069Path: 'WAN → WAN Configuration → TR-069', keywords: ['huawei', 'hg8', 'hg6', 'echolife', 'smartax', 'gpon']),
  RouterProfile(brand: 'ZTE ONU/ONT', icon: '📡', defaultIp: '192.168.1.1', defaultUser: 'admin', defaultPass: 'admin',
    altUsers: ['user', 'zte'], altPasswords: ['user', 'zte', 'Zte521'],
    tr069Path: 'Administration → TR-069 Client', keywords: ['zte', 'zxhn', 'zxa10', 'f6', 'f670']),
  RouterProfile(brand: 'TP-Link', icon: '🌐', defaultIp: '192.168.0.1', defaultUser: 'admin', defaultPass: 'admin',
    altPasswords: ['password', ''], tr069Path: 'Advanced → System Tools → CWMP (TR-069)',
    keywords: ['tp-link', 'tplinkwifi', 'tplink', 'archer', 'tl-wr', 'tl-mr']),
  RouterProfile(brand: 'Tenda', icon: '🌐', defaultIp: '192.168.0.1', defaultUser: 'admin', defaultPass: 'admin',
    altPasswords: ['password', ''], tr069Path: 'Administration → TR-069', keywords: ['tenda', 'tendawifi']),
  RouterProfile(brand: 'D-Link', icon: '🌐', defaultIp: '192.168.0.1', defaultUser: 'admin', defaultPass: 'admin',
    altPasswords: ['password', ''], tr069Path: 'Management → TR-069 Client', keywords: ['d-link', 'dlink', 'dir-']),
  RouterProfile(brand: 'Netis', icon: '🌐', defaultIp: '192.168.1.1', defaultUser: 'admin', defaultPass: 'admin',
    altUsers: ['guest'], altPasswords: ['password', ''], tr069Path: 'System → CWMP Settings', keywords: ['netis', 'netiswifi']),
  RouterProfile(brand: 'MikroTik', icon: '⚙️', defaultIp: '192.168.88.1', defaultUser: 'admin', defaultPass: '',
    altPasswords: ['admin'], tr069Path: 'System → TR-069 (يحتاج تفعيل الحزمة)', keywords: ['mikrotik', 'routeros', 'routerboard']),
  RouterProfile(brand: 'Xiaomi / Redmi', icon: '📱', supportsTr069: false, defaultIp: '192.168.31.1', defaultUser: 'admin', defaultPass: '',
    tr069Path: 'غير مدعوم', keywords: ['xiaomi', 'miwifi', 'redmi', 'mi router']),
  RouterProfile(brand: 'Mercusys', icon: '📱', supportsTr069: false, defaultIp: '192.168.1.1', defaultUser: 'admin', defaultPass: '',
    tr069Path: 'غير مدعوم', keywords: ['mercusys', 'mwifi']),
  RouterProfile(brand: 'Nokia/Alcatel ONT', icon: '📡', defaultIp: '192.168.1.1', defaultUser: 'admin', defaultPass: '1234',
    altUsers: ['AdminGPON'], altPasswords: ['ALC#FGU', 'admin'], tr069Path: 'WAN Settings → TR-069', keywords: ['nokia', 'alcatel', 'g-240']),
];

class _ScanResult {
  String ip = '';
  bool reachable = false;
  int statusCode = 0;
  String pageTitle = '';
  String rawBody = '';
  RouterProfile? matchedProfile;
  String error = '';
}

const _indigo = Color(0xFF1a237e);

// ════════════════════════════════════════════════════════════
// الصفحة الرئيسية — Wizard إعداد الراوتر
// ════════════════════════════════════════════════════════════
class OfflineRouterSetupPage extends StatefulWidget {
  const OfflineRouterSetupPage({super.key});
  @override
  State<OfflineRouterSetupPage> createState() => _OfflineRouterSetupPageState();
}

class _OfflineRouterSetupPageState extends State<OfflineRouterSetupPage> {
  // ═══ Responsive helpers ═══
  bool get _isMobile => MediaQuery.of(context).size.width < 600;
  double get _fs => _isMobile ? 0.85 : 1.0; // font scale
  double get _pad => _isMobile ? 10 : 16;
  double get _iconSz => _isMobile ? 18 : 22;

  // ═══ Wizard state ═══
  int _step = 0; // 0=scan, 1=webview, 2=test
  bool _scanning = false;
  final List<_ScanResult> _results = [];
  _ScanResult? _selectedDevice;
  String _scanStatus = '';
  final _customIpCtrl = TextEditingController();

  // ═══ PPPoE ═══
  final _pppoeUserCtrl = TextEditingController();
  final _pppoePassCtrl = TextEditingController();

  // ═══ WiFi ═══
  final _wifiSsidCtrl = TextEditingController();
  final _wifiPassCtrl = TextEditingController();

  // ═══ Test ═══
  bool _testingInternet = false;
  String _internetResult = '';
  bool _testingGenieacs = false;
  String _genieacsResult = '';

  // ═══ سجل الإعدادات ═══
  final List<String> _setupLog = [];

  // ═══ إعداد تلقائي ═══
  bool _autoRunning = false;
  RouterAdapter? _adapter;
  bool _loggedIn = false;
  bool _loggingIn = false;
  String _loginStatus = '';

  // ═══ المشتركين المعلّقين ═══
  List<PendingSubscriber> _pendingSubs = [];
  PendingSubscriber? _selectedSub;
  final _phoneSearchCtrl = TextEditingController();

  // ═══ WebView ═══
  final wvwin.WebviewController _webCtrl = wvwin.WebviewController();
  bool _webInitialized = false;
  bool _webLoading = true;

  // ═══ العناوين الشائعة ═══
  static const _commonIps = ['192.168.1.1', '192.168.0.1', '192.168.100.1', '192.168.31.1', '192.168.88.1', '10.0.0.1', '192.168.2.1', '192.168.10.1'];

  final _steps = const ['كشف الراوتر', 'واجهة الراوتر', 'اختبار'];

  @override
  void initState() {
    super.initState();
    _loadPendingSubs();
  }

  Future<void> _loadPendingSubs() async {
    final subs = await PendingSubscribersService.getAll();
    if (mounted) setState(() => _pendingSubs = subs);
  }

  void _selectSubscriber(PendingSubscriber sub) {
    setState(() {
      _selectedSub = sub;
      _pppoeUserCtrl.text = sub.pppoeUser;
      _pppoePassCtrl.text = sub.pppoePass;
      if (sub.name.isNotEmpty) _wifiSsidCtrl.text = sub.name;
    });
  }

  @override
  void dispose() {
    _customIpCtrl.dispose();
    _phoneSearchCtrl.dispose();
    _pppoeUserCtrl.dispose();
    _pppoePassCtrl.dispose();
    _wifiSsidCtrl.dispose();
    _wifiPassCtrl.dispose();
    if (_webInitialized) _webCtrl.dispose();
    super.dispose();
  }

  // ═══════ فحص الشبكة ═══════
  Future<String?> _detectGateway() async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run('ipconfig', [], stdoutEncoding: utf8);
        for (final line in r.stdout.toString().split('\n')) {
          if (line.contains('Default Gateway') && !line.trim().endsWith(':')) {
            final m = RegExp(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})').firstMatch(line);
            if (m != null) return m.group(1);
          }
        }
      } else {
        final r = await Process.run('ip', ['route', 'show', 'default']);
        final m = RegExp(r'via\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})').firstMatch(r.stdout.toString());
        if (m != null) return m.group(1);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _scanNetwork() async {
    setState(() { _scanning = true; _results.clear(); _scanStatus = 'جاري كشف الشبكة...'; });
    final gateway = await _detectGateway();
    final ips = <String>{..._commonIps};
    if (gateway != null && gateway.isNotEmpty) {
      ips.add(gateway);
      final p = gateway.split('.');
      if (p.length == 4) ips.add('${p[0]}.${p[1]}.${p[2]}.1');
    }
    setState(() { _scanStatus = 'جاري فحص ${ips.length} عنوان${gateway != null ? " (Gateway: $gateway)" : ""}...'; });
    final results = await Future.wait(ips.map(_probeIp));
    if (!mounted) return;
    setState(() {
      _results.addAll(results.where((r) => r.reachable));
      _scanning = false;
      _scanStatus = _results.isEmpty ? 'لم يتم العثور على أي جهاز — تأكد أنك متصل بشبكة الراوتر' : 'تم العثور على ${_results.length} جهاز';
      if (_results.length == 1) _selectedDevice = _results.first;
    });
  }

  Future<void> _scanCustomIp() async {
    final ip = _customIpCtrl.text.trim();
    if (ip.isEmpty) return;
    setState(() { _scanning = true; _scanStatus = 'جاري فحص $ip...'; });
    final result = await _probeIp(ip);
    if (!mounted) return;
    setState(() {
      _scanning = false;
      if (result.reachable) {
        _results.removeWhere((r) => r.ip == ip);
        _results.insert(0, result);
        _selectedDevice = result;
        _scanStatus = 'تم العثور على جهاز في $ip';
      } else {
        _scanStatus = 'لا يوجد جهاز في $ip';
      }
    });
  }

  Future<_ScanResult> _probeIp(String ip) async {
    final result = _ScanResult()..ip = ip;
    try {
      final r = await http.get(Uri.parse('http://$ip/')).timeout(const Duration(seconds: 4));
      result.reachable = true;
      result.statusCode = r.statusCode;
      result.rawBody = r.body;
      final combined = '${r.body.toLowerCase()} ${r.headers.toString().toLowerCase()}';
      final t = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false).firstMatch(r.body);
      if (t != null) result.pageTitle = t.group(1)?.trim() ?? '';
      for (final p in _routerProfiles) {
        if (p.keywords.any((k) => combined.contains(k))) { result.matchedProfile = p; break; }
      }
    } catch (e) {
      result.error = e.toString().contains('Timeout') ? 'انتهت المهلة' : 'غير قابل للوصول';
    }
    return result;
  }

  // ═══════ WebView ═══════
  Future<void> _initWebView(String ip) async {
    if (_webInitialized) {
      await _webCtrl.loadUrl('http://$ip/');
      return;
    }
    try {
      await _webCtrl.initialize();
      _webCtrl.loadingState.listen((s) {
        if (mounted) setState(() => _webLoading = s == wvwin.LoadingState.loading);
      });
      await _webCtrl.setBackgroundColor(Colors.white);
      await _webCtrl.loadUrl('http://$ip/');
      if (mounted) setState(() => _webInitialized = true);
    } catch (e) {
      debugPrint('[WebView] init error: $e');
    }
  }

  // ═══════ اختبار الاتصال ═══════
  Future<void> _testInternet() async {
    setState(() { _testingInternet = true; _internetResult = ''; });
    try {
      final r = await http.get(Uri.parse('http://connectivitycheck.gstatic.com/generate_204')).timeout(const Duration(seconds: 5));
      if (mounted) setState(() {
        _testingInternet = false;
        _internetResult = r.statusCode == 204 ? 'متصل بالإنترنت' : 'رمز الاستجابة: ${r.statusCode}';
      });
    } catch (e) {
      if (mounted) setState(() { _testingInternet = false; _internetResult = 'لا يوجد اتصال بالإنترنت'; });
    }
  }

  Future<void> _testGenieacs() async {
    setState(() { _testingGenieacs = true; _genieacsResult = ''; });
    try {
      final r = await http.get(Uri.parse('http://187.124.177.236:7557/devices?limit=1&projection=_id')).timeout(const Duration(seconds: 8));
      if (mounted) setState(() {
        _testingGenieacs = false;
        _genieacsResult = r.statusCode == 200 ? 'GenieACS متصل — الراوتر سيظهر خلال دقائق' : 'خطأ: ${r.statusCode}';
      });
    } catch (e) {
      if (mounted) setState(() { _testingGenieacs = false; _genieacsResult = 'لا يمكن الوصول لـ GenieACS (يحتاج إنترنت)'; });
    }
  }

  // ═══════ الإعداد التلقائي عبر Router Adapter ═══════
  RouterAdapter? _getAdapter() {
    if (_selectedDevice?.matchedProfile == null) return null;
    return RouterAdapterFactory.getAdapter(_selectedDevice!.matchedProfile!.brand);
  }

  Future<void> _autoLogin() async {
    if (_loggedIn || _loggingIn) return;
    if (_selectedDevice == null) return;
    final p = _selectedDevice!.matchedProfile;
    if (p == null) return;
    _adapter = _getAdapter();
    if (_adapter == null) {
      setState(() => _loginStatus = 'لا يوجد دعم تلقائي لـ ${p.brand}');
      return;
    }

    setState(() { _loggingIn = true; _loginStatus = 'جاري تسجيل الدخول...'; });
    _log('تسجيل الدخول تلقائياً لـ ${p.brand}...');

    final users = [p.defaultUser, ...p.altUsers];
    final passes = [p.defaultPass, ...p.altPasswords];

    bool ok = false;
    String successUser = '';
    for (final u in users) {
      for (final pw in passes) {
        ok = await _adapter!.login(_selectedDevice!.ip, u, pw);
        if (ok) { successUser = u; break; }
      }
      if (ok) break;
    }

    if (mounted) setState(() {
      _loggingIn = false;
      _loggedIn = ok;
      _loginStatus = ok ? 'تم تسجيل الدخول بـ $successUser' : 'فشل — سيتم تسجيل الدخول عبر واجهة الراوتر';
    });
    _log(ok ? '✓ تم تسجيل الدخول بـ $successUser' : '✗ فشل تسجيل الدخول عبر API');

    // إذا فشل API → جرب WebView مع JS injection
    if (!ok && _selectedDevice != null) {
      _log('جاري تسجيل الدخول عبر WebView...');
      await _loginViaWebView();
    }

    // قراءة الإعدادات الحالية
    if (_loggedIn && _adapter != null && _selectedDevice != null) {
      try {
        final settings = await _adapter!.readSettings(_selectedDevice!.ip);
        if (mounted) setState(() {
          if (_pppoeUserCtrl.text.isEmpty && settings.pppoeUser.isNotEmpty) _pppoeUserCtrl.text = settings.pppoeUser;
          if (_pppoePassCtrl.text.isEmpty && settings.pppoePass.isNotEmpty) _pppoePassCtrl.text = settings.pppoePass;
          if (_wifiSsidCtrl.text.isEmpty && settings.wifiSsid.isNotEmpty) _wifiSsidCtrl.text = settings.wifiSsid;
          if (_wifiPassCtrl.text.isEmpty && settings.wifiPass.isNotEmpty) _wifiPassCtrl.text = settings.wifiPass;
        });
        if (settings.pppoeUser.isNotEmpty || settings.wifiSsid.isNotEmpty) {
          _log('✓ تم قراءة الإعدادات الحالية');
        }
      } catch (e) {
        debugPrint('[AutoSetup] readSettings error: $e');
      }
    }

    // إذا فشل كل شيء — نقرأ البيانات من WebView
    if (_loggedIn && _webInitialized) {
      _readSettingsFromWebView();
    }
  }

  Future<void> _autoPppoe() async {
    if (_adapter == null || _selectedDevice == null) return;
    final user = _pppoeUserCtrl.text.trim();
    final pass = _pppoePassCtrl.text.trim();
    if (user.isEmpty) return;

    setState(() => _autoRunning = true);
    _log('إعداد PPPoE تلقائي: $user...');
    final r = await _adapter!.setPppoe(_selectedDevice!.ip, user, pass);
    _setupLog.addAll(r.log);
    _log(r.success ? '✓ تم إعداد PPPoE' : '✗ فشل — جرّب يدوياً من WebView');
    if (mounted) setState(() => _autoRunning = false);
  }

  Future<void> _autoWifi() async {
    if (_adapter == null || _selectedDevice == null) return;
    final ssid = _wifiSsidCtrl.text.trim();
    final pass = _wifiPassCtrl.text.trim();
    if (ssid.isEmpty) return;

    setState(() => _autoRunning = true);
    _log('إعداد WiFi تلقائي: $ssid...');
    final r = await _adapter!.setWifi(_selectedDevice!.ip, ssid, pass);
    _setupLog.addAll(r.log);
    _log(r.success ? '✓ تم إعداد WiFi' : '✗ فشل — جرّب يدوياً من WebView');
    if (mounted) setState(() => _autoRunning = false);
  }

  Future<void> _autoTr069() async {
    if (_adapter == null || _selectedDevice == null) return;
    setState(() => _autoRunning = true);
    _log('إعداد TR-069 تلقائي...');
    final r = await _adapter!.setTr069(_selectedDevice!.ip, _acsUrl);
    _setupLog.addAll(r.log);
    _log(r.success ? '✓ تم إعداد TR-069' : '✗ فشل — جرّب يدوياً من WebView');
    if (mounted) setState(() => _autoRunning = false);
  }

  Future<void> _autoSetupAll() async {
    if (_selectedDevice == null) return;
    final p = _selectedDevice!.matchedProfile;
    if (p == null) return;
    _adapter = _getAdapter();
    if (_adapter == null) {
      _log('لا يوجد adapter لـ ${p.brand}');
      return;
    }
    setState(() => _autoRunning = true);
    final r = await _adapter!.setupAll(
      _selectedDevice!.ip, p.defaultUser, p.defaultPass,
      pppoeUser: _pppoeUserCtrl.text.trim().isNotEmpty ? _pppoeUserCtrl.text.trim() : null,
      pppoePass: _pppoePassCtrl.text.trim().isNotEmpty ? _pppoePassCtrl.text.trim() : null,
      wifiSsid: _wifiSsidCtrl.text.trim().isNotEmpty ? _wifiSsidCtrl.text.trim() : null,
      wifiPass: _wifiPassCtrl.text.trim().isNotEmpty ? _wifiPassCtrl.text.trim() : null,
      acsUrl: _acsUrl,
    );
    _setupLog.addAll(r.log);
    _log(r.success ? '✓ الإعداد الشامل تم بنجاح' : '✗ بعض الإعدادات قد فشلت');
    if (mounted) setState(() { _autoRunning = false; _step = 2; }); // انتقل للاختبار
  }

  bool get _hasAdapter => _selectedDevice?.matchedProfile != null && RouterAdapterFactory.getAdapter(_selectedDevice!.matchedProfile!.brand) != null;

  Widget _autoButton(String label, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      icon: _autoRunning
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      onPressed: _autoRunning ? null : onPressed,
    );
  }

  // ═══════ تسجيل دخول عبر WebView + JS ═══════
  Future<void> _loginViaWebView() async {
    if (_selectedDevice == null) return;
    final ip = _selectedDevice!.ip;
    final p = _selectedDevice!.matchedProfile;
    if (p == null) return;

    // تهيئة WebView إذا لم يكن جاهزاً
    if (!_webInitialized) await _initWebView(ip);
    if (!_webInitialized) return;

    // تحميل صفحة الراوتر
    await _webCtrl.loadUrl('http://$ip/');
    await Future.delayed(const Duration(seconds: 3));

    // حقن JS لتسجيل الدخول
    final users = [p.defaultUser, ...p.altUsers];
    final passes = [p.defaultPass, ...p.altPasswords];

    for (final user in users) {
      for (final pass in passes) {
        try {
          _log('  WebView: جاري تجربة $user...');

          // ملء الحقول + استدعاء SubmitForm الأصلية
          await _webCtrl.executeScript('''
            (function() {
              var u = document.getElementById('txt_Username');
              var p = document.getElementById('txt_Password');
              if (!u) u = document.querySelector('input[name*="user" i]') || document.querySelector('input[type="text"]');
              if (!p) p = document.querySelector('input[name*="pass" i]') || document.querySelector('input[type="password"]');
              if (u) { u.value = '$user'; u.disabled = false; }
              if (p) { p.value = '$pass'; p.disabled = false; }
            })()
          ''');

          await Future.delayed(const Duration(milliseconds: 500));

          // استدعاء SubmitForm الأصلية — هي تتكفل بالتشفير والـ token
          await _webCtrl.executeScript('''
            (function() {
              if (typeof SubmitForm === 'function') { SubmitForm(); return; }
              var btn = document.getElementById('tripletbtn') || document.getElementById('button') || document.querySelector('button.submit') || document.querySelector('button');
              if (btn) btn.click();
            })()
          ''');

          await Future.delayed(const Duration(seconds: 4));

          // تحقق — هل الصفحة تغيرت؟
          final result = await _webCtrl.executeScript('''
            (function() {
              var body = document.body ? document.body.innerHTML : '';
              if (body.indexOf('Incorrect') > -1 || body.indexOf('Login failure') > -1) return 'failed';
              if (body.indexOf('frameset') > -1 || body.indexOf('menu') > -1 || body.indexOf('status') > -1 || body.indexOf('WAN') > -1 || body.indexOf('content') > -1) return 'success';
              var url = window.location.href || '';
              if (url.indexOf('login') === -1 && url.indexOf('index') > -1) return 'success';
              return document.title || 'unknown';
            })()
          ''');
          final res = result?.toString() ?? '';

          if (res.contains('success')) {
            if (mounted) setState(() { _loggedIn = true; _loginStatus = 'تم تسجيل الدخول عبر WebView بـ $user'; });
            _log('✓ WebView: نجح الدخول بـ $user');
            return;
          }
          if (res.contains('failed')) {
            _log('  ✗ $user — باسورد خاطئ');
            // إعادة تحميل صفحة login للمحاولة التالية
            await _webCtrl.loadUrl('http://$ip/');
            await Future.delayed(const Duration(seconds: 2));
          }
        } catch (e) {
          debugPrint('[WebView Login] error: $e');
        }
      }
    }
    _log('✗ فشل تسجيل الدخول — تأكد من بيانات الدخول');
  }

  // ═══════ قراءة إعدادات من WebView — XHR داخلي ═══════
  Future<void> _readSettingsFromWebView() async {
    if (!_webInitialized || _selectedDevice == null) return;
    _log('جاري قراءة إعدادات الراوتر...');

    // ننتظر قليلاً حتى يكتمل تحميل الصفحة الرئيسية بعد الدخول
    await Future.delayed(const Duration(seconds: 2));

    // نحاول عدة مجموعات من المسارات — تختلف حسب موديل Huawei
    try {
      final result = await _webCtrl.executeScript(r"""
        (function() {
          var R = {};
          function get(url) {
            try {
              var x = new XMLHttpRequest();
              x.open('GET', url, false);
              x.send();
              return x.status === 200 ? x.responseText : '';
            } catch(e) { return ''; }
          }
          function find(text, patterns) {
            for (var i = 0; i < patterns.length; i++) {
              var m = text.match(patterns[i]);
              if (m && m[1] && m[1].length > 1 && m[1] !== 'undefined') return m[1];
            }
            return '';
          }

          // صفحات محتملة لكل نوع بيانات
          var devUrls = ['/html/status/deviceinformation_t.asp', '/asp/status/deviceinformation_t.asp', '/status.asp'];
          var wanUrls = ['/html/network/wan_t.asp', '/html/status/wan/wan_ether_info_t.asp', '/asp/network/wan_t.asp', '/wan.asp'];
          var wlanUrls = ['/html/ssmp/wlan/wlan_basic_t.asp', '/asp/ssmp/wlan/wlan_basic_t.asp', '/wlan.asp', '/html/network/wlan_basic_t.asp'];
          var trUrls = ['/html/amp/tr069_t.asp', '/asp/amp/tr069_t.asp', '/tr069.asp'];

          // 1. Device info
          for (var i = 0; i < devUrls.length; i++) {
            var p = get(devUrls[i]);
            if (p.length > 100) {
              R.model = find(p, [/ModelName\W+(\w[\w\-]+)/i, /DeviceName\W+(\w[\w\-]+)/i, /ProductClass\W+(\w[\w\-]+)/i]);
              R.firmware = find(p, [/SoftwareVersion\W+([\w\.]+)/i, /FirmwareVersion\W+([\w\.]+)/i]);
              R.mac = find(p, [/MACAddress\W+((?:[0-9A-Fa-f]{2}[:\-]){5}[0-9A-Fa-f]{2})/i]);
              if (R.model) break;
            }
          }

          // 2. WAN / PPPoE
          for (var i = 0; i < wanUrls.length; i++) {
            var p = get(wanUrls[i]);
            if (p.length > 100) {
              R.pppoeUser = find(p, [/Username\W{1,5}(\S{3,})/i, /PPPoEUser\W{1,5}(\S{3,})/i]);
              R.wanIp = find(p, [/ExternalIPAddress\W{1,5}(\d+\.\d+\.\d+\.\d+)/i, /WanIP\W{1,5}(\d+\.\d+\.\d+\.\d+)/i, /IPAddress\W{1,5}(\d+\.\d+\.\d+\.\d+)/i]);
              if (R.pppoeUser) break;
            }
          }

          // 3. WiFi
          for (var i = 0; i < wlanUrls.length; i++) {
            var p = get(wlanUrls[i]);
            if (p.length > 100) {
              R.ssid = find(p, [/WlanSSID\W{1,5}([^\s'"<]{2,32})/i, /\bSSID\W{1,5}([^\s'"<]{2,32})/i]);
              R.ssidPass = find(p, [/WpaPreSharedKey\W{1,5}([^\s'"<]+)/i, /KeyPassphrase\W{1,5}([^\s'"<]+)/i, /WlanKey\W{1,5}([^\s'"<]+)/i]);
              if (R.ssid) break;
            }
          }

          // 4. TR-069
          for (var i = 0; i < trUrls.length; i++) {
            var p = get(trUrls[i]);
            if (p.length > 100) {
              R.tr069 = find(p, [/\bURL\W{1,5}(http\S+)/i, /AcsUrl\W{1,5}(http\S+)/i]);
              if (R.tr069) break;
            }
          }

          // 5. أيضاً نحاول من الصفحة الحالية (بعد الدخول قد تكون status)
          var body = document.body ? document.body.innerHTML : '';
          if (!R.model) R.model = find(body, [/ModelName\W+(\w[\w\-]+)/i, /ProductName\W+(\w[\w\-]+)/i]);

          return JSON.stringify(R);
        })()
      """);

      _applyWebViewResult(result);
    } catch (e) {
      debugPrint('[WebView Read] error: $e');
      _log('⚠️ خطأ في قراءة الإعدادات');
    }
  }

  void _applyWebViewResult(Object? raw) {
    if (raw == null) return;
    try {
      var str = raw.toString();
      // تنظيف — إزالة علامات اقتباس خارجية إذا موجودة
      if (str.startsWith('"') && str.endsWith('"')) str = str.substring(1, str.length - 1);
      str = str.replaceAll(r'\"', '"');
      if (str.isEmpty || str == '{}' || str == 'null') { _log('⚠️ لم يتم العثور على بيانات'); return; }

      final j = jsonDecode(str);
      if (j is! Map) return;

      if (mounted) setState(() {
        if (_pppoeUserCtrl.text.isEmpty && j['pppoeUser']?.toString().isNotEmpty == true)
          _pppoeUserCtrl.text = j['pppoeUser'].toString();
        if (_pppoePassCtrl.text.isEmpty && j['pppoePass']?.toString().isNotEmpty == true)
          _pppoePassCtrl.text = j['pppoePass'].toString();
        if (_wifiSsidCtrl.text.isEmpty && j['ssid']?.toString().isNotEmpty == true)
          _wifiSsidCtrl.text = j['ssid'].toString();
        if (_wifiPassCtrl.text.isEmpty && j['ssidPass']?.toString().isNotEmpty == true)
          _wifiPassCtrl.text = j['ssidPass'].toString();
      });

      final fields = {'PPPoE': j['pppoeUser'], 'WAN IP': j['wanIp'], 'WiFi': j['ssid'], 'Model': j['model'], 'Firmware': j['firmware'], 'MAC': j['mac'], 'TR-069': j['tr069']};
      for (final e in fields.entries) {
        if (e.value?.toString().isNotEmpty == true) _log('✓ ${e.key}: ${e.value}');
      }
      if (j['ssidPass']?.toString().isNotEmpty == true) _log('✓ WiFi Pass: ***');

      final hasData = fields.values.any((v) => v?.toString().isNotEmpty == true);
      if (!hasData) _log('⚠️ لم يتم العثور على بيانات — جرّب من "فتح واجهة الراوتر"');
    } catch (e) {
      debugPrint('[Parse] error: $e — raw: $raw');
      _log('⚠️ خطأ في تحليل البيانات');
    }
  }

  void _log(String msg) => _setupLog.add('[${TimeOfDay.now().format(context)}] $msg');

  // ═══════ القائمة المنسدلة — المشتركين المعلّقين ═══════
  Widget _buildSubsDropdown() {
    return PopupMenuButton<String>(
      icon: Badge(
        isLabelVisible: _pendingSubs.isNotEmpty,
        label: Text('${_pendingSubs.length}', style: const TextStyle(fontSize: 9)),
        child: const Icon(Icons.people, color: Colors.white),
      ),
      tooltip: 'المشتركين',
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      constraints: const BoxConstraints(maxWidth: 400),
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, height: 36,
          child: Row(children: [
            Icon(Icons.people, size: 16, color: _indigo),
            const SizedBox(width: 6),
            Text('المشتركين (${_pendingSubs.length})', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _indigo)),
            const Spacer(),
            InkWell(
              onTap: () { Navigator.pop(context); _showAddSubscriberDialog(); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.green.shade700, borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, size: 14, color: Colors.white),
                  SizedBox(width: 2),
                  Text('إضافة', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ])),
        const PopupMenuDivider(),
        if (_pendingSubs.isEmpty)
          const PopupMenuItem(enabled: false, height: 50,
            child: Center(child: Text('لا يوجد مشتركين — أضف من المهام أو يدوياً', style: TextStyle(fontSize: 11, color: Colors.grey)))),
        ..._pendingSubs.map((s) => PopupMenuItem<String>(
          value: s.phone,
          height: 60,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: _selectedSub?.phone == s.phone ? _indigo.withOpacity(0.08) : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              CircleAvatar(radius: 16, backgroundColor: _indigo.withOpacity(0.1),
                child: Text(s.name.isNotEmpty ? s.name[0] : '?', style: TextStyle(fontWeight: FontWeight.w800, color: _indigo, fontSize: 14))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                Row(children: [
                  Text(s.phone, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFamily: 'monospace')),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () { Clipboard.setData(ClipboardData(text: s.phone)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الهاتف'), duration: Duration(seconds: 1))); },
                    child: Icon(Icons.copy, size: 12, color: Colors.grey.shade400),
                  ),
                ]),
                if (s.pppoeUser.isNotEmpty) Row(children: [
                  Text('PPPoE: ${s.pppoeUser}', style: TextStyle(fontSize: 10, color: Colors.teal.shade700)),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () { Clipboard.setData(ClipboardData(text: s.pppoeUser)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ PPPoE'), duration: Duration(seconds: 1))); },
                    child: Icon(Icons.copy, size: 12, color: Colors.grey.shade400),
                  ),
                ]),
              ])),
              if (_selectedSub?.phone == s.phone)
                Icon(Icons.check_circle, size: 18, color: _indigo),
            ]),
          ),
        )),
      ],
      onSelected: (phone) {
        final sub = _pendingSubs.firstWhere((s) => s.phone == phone, orElse: () => _pendingSubs.first);
        _selectSubscriber(sub);
      },
    );
  }

  void _showAddSubscriberDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final pppoeCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(children: [
            Icon(Icons.person_add, color: _indigo),
            const SizedBox(width: 8),
            const Text('إضافة مشترك', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: _inputDeco('اسم المشترك', Icons.person)),
            const SizedBox(height: 10),
            TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: _inputDeco('رقم الهاتف', Icons.phone)),
            const SizedBox(height: 10),
            TextField(controller: pppoeCtrl, decoration: _inputDeco('PPPoE Username', Icons.language)),
            const SizedBox(height: 10),
            TextField(controller: passCtrl, decoration: _inputDeco('PPPoE Password', Icons.lock)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _indigo, foregroundColor: Colors.white),
              onPressed: () async {
                if (phoneCtrl.text.trim().isEmpty) return;
                await PendingSubscribersService.add(PendingSubscriber(
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  pppoeUser: pppoeCtrl.text.trim(),
                  pppoePass: passCtrl.text.trim(),
                ));
                await _loadPendingSubs();
                if (ctx.mounted) Navigator.pop(ctx);
                // اختر المشترك الجديد تلقائياً
                if (_pendingSubs.isNotEmpty) _selectSubscriber(_pendingSubs.first);
              },
              child: const Text('حفظ', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════ القائمة المنسدلة — إعدادات GenieACS ═══════
  Widget _buildAcsDropdown() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.list_alt, color: Colors.white),
      tooltip: 'إعدادات TR-069 للنسخ',
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, height: 32,
          child: Text('إعدادات TR-069', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _indigo))),
        const PopupMenuDivider(),
        ..._acsFields.map((f) => PopupMenuItem<String>(
          value: f['value'],
          height: 44,
          child: Row(
            children: [
              SizedBox(width: 100, child: Text(f['label']!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
              Expanded(child: Text(f['value']!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'monospace'))),
              const Icon(Icons.copy, size: 14, color: Colors.grey),
            ],
          ),
        )),
        const PopupMenuDivider(),
        // بيانات الدخول إذا موجود profile
        if (_selectedDevice?.matchedProfile != null) ...[
          PopupMenuItem(enabled: false, height: 32,
            child: Text('بيانات دخول ${_selectedDevice!.matchedProfile!.brand}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.teal.shade700))),
          PopupMenuItem<String>(value: _selectedDevice!.matchedProfile!.defaultUser, height: 40,
            child: Row(children: [
              const SizedBox(width: 100, child: Text('User', style: TextStyle(fontSize: 11, color: Colors.grey))),
              Text(_selectedDevice!.matchedProfile!.defaultUser, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const Spacer(), const Icon(Icons.copy, size: 14, color: Colors.grey),
            ])),
          PopupMenuItem<String>(value: _selectedDevice!.matchedProfile!.defaultPass, height: 40,
            child: Row(children: [
              const SizedBox(width: 100, child: Text('Password', style: TextStyle(fontSize: 11, color: Colors.grey))),
              Text(_selectedDevice!.matchedProfile!.defaultPass.isEmpty ? '(فارغ)' : _selectedDevice!.matchedProfile!.defaultPass,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const Spacer(), const Icon(Icons.copy, size: 14, color: Colors.grey),
            ])),
          PopupMenuItem<String>(value: _selectedDevice!.matchedProfile!.tr069Path, height: 40,
            child: Row(children: [
              const SizedBox(width: 100, child: Text('مسار TR-069', style: TextStyle(fontSize: 11, color: Colors.grey))),
              Expanded(child: Text(_selectedDevice!.matchedProfile!.tr069Path, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
              const Icon(Icons.copy, size: 14, color: Colors.grey),
            ])),
        ],
        // PPPoE إذا تم إدخاله
        if (_pppoeUserCtrl.text.trim().isNotEmpty) ...[
          const PopupMenuDivider(),
          PopupMenuItem(enabled: false, height: 32,
            child: Text('بيانات PPPoE', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.orange.shade700))),
          PopupMenuItem<String>(value: _pppoeUserCtrl.text.trim(), height: 40,
            child: Row(children: [
              const SizedBox(width: 100, child: Text('PPPoE User', style: TextStyle(fontSize: 11, color: Colors.grey))),
              Text(_pppoeUserCtrl.text.trim(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
              const Spacer(), const Icon(Icons.copy, size: 14, color: Colors.grey),
            ])),
          if (_pppoePassCtrl.text.trim().isNotEmpty)
            PopupMenuItem<String>(value: _pppoePassCtrl.text.trim(), height: 40,
              child: Row(children: [
                const SizedBox(width: 100, child: Text('PPPoE Pass', style: TextStyle(fontSize: 11, color: Colors.grey))),
                Text(_pppoePassCtrl.text.trim(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                const Spacer(), const Icon(Icons.copy, size: 14, color: Colors.grey),
              ])),
        ],
        // WiFi إذا تم إدخاله
        if (_wifiSsidCtrl.text.trim().isNotEmpty) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(value: _wifiSsidCtrl.text.trim(), height: 40,
            child: Row(children: [
              const SizedBox(width: 100, child: Text('WiFi SSID', style: TextStyle(fontSize: 11, color: Colors.grey))),
              Text(_wifiSsidCtrl.text.trim(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const Spacer(), const Icon(Icons.copy, size: 14, color: Colors.grey),
            ])),
          if (_wifiPassCtrl.text.trim().isNotEmpty)
            PopupMenuItem<String>(value: _wifiPassCtrl.text.trim(), height: 40,
              child: Row(children: [
                const SizedBox(width: 100, child: Text('WiFi Pass', style: TextStyle(fontSize: 11, color: Colors.grey))),
                Text(_wifiPassCtrl.text.trim(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const Spacer(), const Icon(Icons.copy, size: 14, color: Colors.grey),
              ])),
        ],
      ],
      onSelected: (val) {
        Clipboard.setData(ClipboardData(text: val));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم النسخ: $val'), duration: const Duration(seconds: 1)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: Text(
            _step == 1 ? 'واجهة الراوتر' : 'إعداد الراوتر',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: _isMobile ? 14 : 16),
          ),
          backgroundColor: _indigo,
          foregroundColor: Colors.white,
          elevation: 0,
          toolbarHeight: _isMobile ? 44 : 56,
          actions: [
            _buildSubsDropdown(),
            _buildAcsDropdown(),
            if (!_isMobile) IconButton(icon: const Icon(Icons.menu_book, size: 22), tooltip: 'دليل الراوترات', onPressed: _showRouterGuide),
            if (_isMobile) PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'guide', child: Row(children: [Icon(Icons.menu_book, size: 18), SizedBox(width: 8), Text('دليل الراوترات')])),
                if (_step == 1) ...[
                  const PopupMenuItem(value: 'refresh', child: Row(children: [Icon(Icons.refresh, size: 18), SizedBox(width: 8), Text('تحديث')])),
                  const PopupMenuItem(value: 'back', child: Row(children: [Icon(Icons.arrow_back, size: 18), SizedBox(width: 8), Text('رجوع')])),
                ],
              ],
              onSelected: (v) {
                if (v == 'guide') _showRouterGuide();
                if (v == 'refresh') _webCtrl.reload();
                if (v == 'back') _webCtrl.goBack();
              },
            ),
            if (!_isMobile && _step == 1) ...[
              if (_webLoading) const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
              IconButton(icon: const Icon(Icons.refresh), tooltip: 'تحديث', onPressed: () => _webCtrl.reload()),
              IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'رجوع', onPressed: () => _webCtrl.goBack()),
            ],
            if (_scanning) const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
          ],
        ),
        body: Column(
          children: [
            // ═══ شريط الخطوات العصري ═══
            Container(
              padding: EdgeInsets.symmetric(vertical: _isMobile ? 8 : 12, horizontal: _isMobile ? 8 : 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: List.generate(_steps.length * 2 - 1, (i) {
                  if (i.isOdd) {
                    // الخط بين الخطوات
                    final done = (i ~/ 2) < _step;
                    return Expanded(child: Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: done ? const Color(0xFF00C853) : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(2),
                      )));
                  }
                  final idx = i ~/ 2;
                  final active = idx == _step;
                  final done = idx < _step;
                  return GestureDetector(
                    onTap: () { if (done || idx == _step) setState(() => _step = idx); },
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: active ? (_isMobile ? 30 : 36) : (_isMobile ? 24 : 30),
                        height: active ? (_isMobile ? 30 : 36) : (_isMobile ? 24 : 30),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: active ? const LinearGradient(colors: [Color(0xFF1a237e), Color(0xFF3949ab)]) : null,
                          color: active ? null : (done ? const Color(0xFF00C853) : Colors.grey.shade200),
                          boxShadow: active ? [BoxShadow(color: _indigo.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : null,
                        ),
                        child: Center(
                          child: done
                              ? Icon(Icons.check_rounded, size: _isMobile ? 13 : 16, color: Colors.white)
                              : Text('${idx + 1}', style: TextStyle(fontSize: _isMobile ? 10 : 12, fontWeight: FontWeight.w800, color: active ? Colors.white : Colors.grey.shade500)),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(_steps[idx], style: TextStyle(fontSize: _isMobile ? 8 : 10, fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                          color: active ? _indigo : (done ? const Color(0xFF00C853) : Colors.grey.shade500)),
                        overflow: TextOverflow.ellipsis),
                    ]),
                  );
                }),
              ),
            ),
            // ═══ محتوى الخطوة ═══
            Expanded(child: _buildStep()),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _stepScan();
      case 1: return _stepWebView();
      case 2: return _stepTest();
      default: return _stepScan();
    }
  }

  // ════════════════════════════════════════
  // الخطوة 1: فحص الشبكة + اختيار الراوتر
  // ════════════════════════════════════════
  Widget _stepScan() {
    final w = MediaQuery.of(context).size.width;
    final center = w > 700;
    final mob = _isMobile;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: center ? w * 0.12 : (mob ? 10 : 16), vertical: mob ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ═══ Hero section ═══
          if (_results.isEmpty && !_scanning) ...[
            SizedBox(height: mob ? 10 : 20),
            Icon(Icons.router_outlined, size: mob ? 44 : 64, color: _indigo.withOpacity(0.15)),
            SizedBox(height: mob ? 8 : 12),
            Text('كشف الراوتر وإعداده', textAlign: TextAlign.center,
                style: TextStyle(fontSize: mob ? 18 : 22, fontWeight: FontWeight.w900, color: _indigo)),
            const SizedBox(height: 6),
            Text('وصّل جهازك بشبكة WiFi الراوتر أو عبر كيبل LAN', textAlign: TextAlign.center,
                style: TextStyle(fontSize: mob ? 11 : 13, color: Colors.grey.shade600)),
            SizedBox(height: mob ? 14 : 24),
          ],

          // ═══ بحث المشترك ═══
          if (_pendingSubs.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
              ),
              child: Column(children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: _indigo.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.person_search, size: 20, color: _indigo),
                  ),
                  const SizedBox(width: 10),
                  Text('اختيار المشترك', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _indigo)),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneSearchCtrl,
                  decoration: InputDecoration(
                    hintText: 'بحث برقم الهاتف...',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    filled: true, fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _indigo, width: 2)),
                    prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey.shade500),
                    suffixIcon: _selectedSub != null ? IconButton(icon: Icon(Icons.clear, size: 18, color: Colors.grey.shade400),
                      onPressed: () => setState(() { _selectedSub = null; _phoneSearchCtrl.clear(); _pppoeUserCtrl.clear(); _pppoePassCtrl.clear(); })) : null,
                  ),
                  keyboardType: TextInputType.phone,
                  onChanged: (val) {
                    final clean = val.replaceAll(RegExp(r'\D'), '');
                    if (clean.length >= 4) {
                      for (final s in _pendingSubs) {
                        if (s.phone.contains(clean)) { _selectSubscriber(s); break; }
                      }
                    }
                  },
                ),
                if (_selectedSub != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [const Color(0xFF00C853).withOpacity(0.08), const Color(0xFF00C853).withOpacity(0.03)]),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF00C853).withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      CircleAvatar(radius: 18, backgroundColor: const Color(0xFF00C853).withOpacity(0.15),
                        child: Text(_selectedSub!.name.isNotEmpty ? _selectedSub!.name[0] : '?', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF00C853), fontSize: 16))),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_selectedSub!.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF1B5E20))),
                        Text('${_selectedSub!.phone}${_selectedSub!.pppoeUser.isNotEmpty ? "  •  ${_selectedSub!.pppoeUser}" : ""}',
                            style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontFamily: 'monospace')),
                      ])),
                      const Icon(Icons.check_circle_rounded, size: 22, color: Color(0xFF00C853)),
                    ]),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 16),
          ],

          // ═══ فحص الشبكة ═══
          Container(
            padding: EdgeInsets.all(mob ? 10 : 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: Column(children: [
              SizedBox(
                height: mob ? 42 : 48,
                child: ElevatedButton.icon(
                  icon: _scanning
                      ? SizedBox(width: mob ? 16 : 18, height: mob ? 16 : 18, child: const CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Icon(Icons.radar_rounded, size: mob ? 18 : 22),
                  label: Text(_scanning ? 'جاري الفحص...' : 'فحص الشبكة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: mob ? 13 : 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _indigo, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  onPressed: _scanning ? null : _scanNetwork,
                ),
              ),
              SizedBox(height: mob ? 8 : 10),
              SizedBox(
                height: mob ? 40 : 44,
                child: TextField(
                  controller: _customIpCtrl,
                  decoration: InputDecoration(
                    hintText: 'أو أدخل IP يدوياً',
                    hintStyle: TextStyle(fontSize: mob ? 11 : 12, color: Colors.grey.shade400),
                    filled: true, fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _indigo, width: 2)),
                    suffixIcon: IconButton(icon: Icon(Icons.arrow_circle_left_outlined, size: mob ? 20 : 22, color: _indigo), onPressed: _scanning ? null : _scanCustomIp),
                  ),
                  keyboardType: TextInputType.number, onSubmitted: (_) => _scanCustomIp(),
                ),
              ),
              if (_scanStatus.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_scanStatus, style: TextStyle(fontSize: mob ? 10 : 12, color: Colors.grey.shade600), textAlign: TextAlign.center),
              ),
            ]),
          ),

          const SizedBox(height: 16),

          // ═══ نتائج الفحص ═══
          ..._results.map((r) => _deviceTile(r)),

          // ═══ معلومات الجهاز المختار ═══
          if (_selectedDevice != null) ...[
            const SizedBox(height: 12),
            if (_hasAdapter)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [const Color(0xFF00C853).withOpacity(0.08), const Color(0xFF00C853).withOpacity(0.02)]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00C853).withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.auto_fix_high, size: 18, color: Color(0xFF00C853)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${_selectedDevice!.matchedProfile!.brand} — يدعم الإعداد التلقائي',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1B5E20)))),
                ]),
              )
            else if (_selectedDevice!.matchedProfile != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${_selectedDevice!.matchedProfile!.brand} — إعداد يدوي عبر WebView',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange.shade800))),
                ]),
              ),
            const SizedBox(height: 16),
            SizedBox(height: 50, child: _nextButton()),
          ],
        ],
      ),
    );
  }

  Widget _deviceTile(_ScanResult r) {
    final selected = _selectedDevice?.ip == r.ip;
    final p = r.matchedProfile;
    return GestureDetector(
      onTap: () => setState(() => _selectedDevice = r),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? _indigo.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? _indigo : Colors.grey.shade200, width: selected ? 2 : 1),
          boxShadow: [
            if (selected) BoxShadow(color: _indigo.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, 3))
            else BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: selected ? _indigo.withOpacity(0.1) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(p?.icon ?? '❓', style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p?.brand ?? 'غير معروف', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: selected ? _indigo : Colors.black87)),
            const SizedBox(height: 2),
            Row(children: [
              Text(r.ip, style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey.shade600)),
              if (r.pageTitle.isNotEmpty) ...[
                Text('  •  ', style: TextStyle(color: Colors.grey.shade400)),
                Flexible(child: Text(r.pageTitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500), overflow: TextOverflow.ellipsis)),
              ],
            ]),
          ])),
          if (p != null && !p.supportsTr069)
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.orange.shade600, borderRadius: BorderRadius.circular(20)),
              child: const Text('لا يدعم', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
          if (selected)
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _indigo),
              child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
            ),
        ]),
      ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(fontSize: _isMobile ? 12 : 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: _isMobile ? 10 : 12),
    prefixIcon: Icon(icon, size: _isMobile ? 16 : 18),
  );

  // ════════════════════════════════════════
  // الخطوة 2: WebView — واجهة الراوتر
  // ════════════════════════════════════════
  Widget _stepWebView() {
    if (_selectedDevice == null) return const Center(child: Text('لم يتم اختيار جهاز'));
    if (!_webInitialized) {
      _initWebView(_selectedDevice!.ip);
      // تسجيل الدخول تلقائي بعد تحميل الصفحة
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _webInitialized && !_loggedIn) _loginViaWebView();
      });
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('جاري تحميل واجهة الراوتر...')]));
    }
    final p = _selectedDevice!.matchedProfile;
    final mob = _isMobile;
    return Column(children: [
      // شريط معلومات + تسجيل دخول
      Container(
        padding: EdgeInsets.symmetric(horizontal: mob ? 8 : 12, vertical: 6),
        decoration: BoxDecoration(
          color: _loggedIn ? const Color(0xFF00C853).withOpacity(0.08) : Colors.amber.shade50,
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(children: [
          Icon(_loggedIn ? Icons.lock_open : Icons.info_outline, size: 14, color: _loggedIn ? const Color(0xFF00C853) : Colors.orange),
          const SizedBox(width: 6),
          Expanded(child: Text(
            _loggedIn
                ? 'متصل — ${p?.tr069Path ?? "انسخ الإعدادات من القائمة أعلاه"}'
                : (p != null ? 'سجّل الدخول: ${p.defaultUser} / ${p.defaultPass.isEmpty ? "(فارغ)" : p.defaultPass}' : 'سجّل الدخول يدوياً'),
            style: TextStyle(fontSize: mob ? 10 : 11, fontWeight: FontWeight.w600),
          )),
          if (!_loggedIn && !_loggingIn)
            SizedBox(
              height: 28,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.login, size: 13),
                label: Text('دخول تلقائي', style: TextStyle(fontSize: mob ? 9 : 10, fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(backgroundColor: _indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                onPressed: _loginViaWebView,
              ),
            ),
          if (_loggingIn) SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _indigo)),
        ]),
      ),
      // أزرار التنقل
      Padding(
        padding: EdgeInsets.symmetric(horizontal: mob ? 6 : 12, vertical: 3),
        child: Row(children: [
          _backButton(compact: true),
          const SizedBox(width: 6),
          Expanded(child: _nextButton(label: 'اختبار الاتصال')),
        ]),
      ),
      Expanded(child: wvwin.Webview(_webCtrl)),
    ]);
  }

  // ════════════════════════════════════════
  // الخطوة 5: اختبار
  // ════════════════════════════════════════
  Widget _stepTest() {
    final mob = _isMobile;
    final w = MediaQuery.of(context).size.width;
    final centerPad = w > 700 ? w * 0.12 : (mob ? 10.0 : 16.0);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: centerPad, vertical: mob ? 10 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _stepTitle('اختبار الاتصال بعد الإعداد'),
        const SizedBox(height: 16),
        // اختبار الإنترنت
        _testCard('اختبار الإنترنت', 'Ping → Google', Icons.language, Colors.blue,
          _testingInternet, _internetResult, _testInternet),
        const SizedBox(height: 10),
        // اختبار GenieACS
        _testCard('اختبار GenieACS', 'هل الراوتر سيظهر في النظام؟', Icons.settings_remote, Colors.teal,
          _testingGenieacs, _genieacsResult, _testGenieacs),
        const SizedBox(height: 10),
        // Ping للراوتر
        _testCard('اختبار الراوتر', 'Ping → ${_selectedDevice?.ip ?? "الراوتر"}', Icons.router, Colors.indigo,
          false, '', () async {
            try {
              final r = await http.get(Uri.parse('http://${_selectedDevice?.ip ?? "192.168.1.1"}/')).timeout(const Duration(seconds: 3));
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('الراوتر يستجيب — HTTP ${r.statusCode}'), backgroundColor: Colors.green));
            } catch (_) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الراوتر لا يستجيب'), backgroundColor: Colors.red));
            }
          }),
        const SizedBox(height: 20),
        // سجل الإعدادات
        if (_setupLog.isNotEmpty) ...[
          Text('سجل الإعدادات:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.grey.shade800)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _setupLog.map((l) => Text(l, style: const TextStyle(fontSize: 10, fontFamily: 'monospace'))).toList()),
          ),
        ],
        const SizedBox(height: 20),
        Row(children: [
          _backButton(),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton.icon(
            icon: const Icon(Icons.check_circle, size: 20),
            label: const Text('إنهاء', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              _log('تم إنهاء الإعداد — ${_selectedDevice?.matchedProfile?.brand ?? "راوتر"} (${_selectedDevice?.ip})');
              Navigator.pop(context);
            },
          )),
        ]),
      ]),
    );
  }

  Widget _testCard(String title, String subtitle, IconData icon, Color color, bool loading, String result, VoidCallback onTest) {
    final mob = _isMobile;
    return Container(
      padding: EdgeInsets.all(mob ? 10 : 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))]),
      child: Row(children: [
        Icon(icon, size: mob ? 22 : 28, color: color),
        SizedBox(width: mob ? 8 : 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: mob ? 12 : 13, color: color)),
          Text(subtitle, style: TextStyle(fontSize: mob ? 9 : 10, color: Colors.grey.shade600)),
          if (result.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(result, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: result.contains('متصل') ? Colors.green.shade700 : Colors.orange.shade800))),
        ])),
        loading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : IconButton(icon: Icon(Icons.play_arrow, color: color), onPressed: onTest),
      ]),
    );
  }

  // ═══════ مشتركات ═══════
  Widget _stepTitle(String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: _indigo.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: _indigo.withOpacity(0.12))),
    child: Row(children: [
      Icon(Icons.info_outline, size: 18, color: _indigo),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade800))),
    ]),
  );

  Widget _nextButton({String? label}) => ElevatedButton(
    style: ElevatedButton.styleFrom(
      backgroundColor: _indigo, foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
    ),
    onPressed: () {
      if (_step == 0 && _selectedDevice != null) {
        _log('تم اختيار ${_selectedDevice!.matchedProfile?.brand ?? "راوتر"} (${_selectedDevice!.ip})');
        // تسجيل دخول تلقائي عند الانتقال للإعدادات
        if (_hasAdapter && !_loggedIn) _autoLogin();
      }
      if (_step == 1 && _pppoeUserCtrl.text.trim().isNotEmpty) _log('PPPoE: ${_pppoeUserCtrl.text.trim()}');
      setState(() => _step = (_step + 1).clamp(0, 2));
    },
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(label ?? 'التالي', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      const SizedBox(width: 8),
      const Icon(Icons.arrow_back_ios_rounded, size: 16),
    ]),
  );

  Widget _backButton({bool compact = false}) => compact
      ? IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
          ),
          onPressed: () => setState(() => _step = (_step - 1).clamp(0, 2)),
        )
      : OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          onPressed: () => setState(() => _step = (_step - 1).clamp(0, 2)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            const SizedBox(width: 6),
            Text('السابق', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
          ]),
        );

  // ═══════ دليل الراوترات ═══════
  void _showRouterGuide() {
    final mob = _isMobile;
    final dw = mob ? MediaQuery.of(context).size.width * 0.95 : 600.0;
    final dh = mob ? MediaQuery.of(context).size.height * 0.8 : 500.0;
    showDialog(context: context, builder: (_) => Directionality(textDirection: TextDirection.rtl, child: Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.all(mob ? 8 : 40),
      child: SizedBox(width: dw, height: dh, child: Column(children: [
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: _indigo, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
          child: Row(children: [
            const Icon(Icons.menu_book, color: Colors.white, size: 22), const SizedBox(width: 8),
            const Expanded(child: Text('دليل الراوترات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
          ])),
        Expanded(child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: _routerProfiles.length, itemBuilder: (_, i) {
          final p = _routerProfiles[i];
          return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.supportsTr069 ? Colors.grey.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.supportsTr069 ? Colors.grey.shade200 : Colors.orange.shade200)),
            child: Row(children: [
              Text(p.icon, style: const TextStyle(fontSize: 22)), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Text(p.brand, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)), const SizedBox(width: 6),
                  if (!p.supportsTr069) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.orange.shade700, borderRadius: BorderRadius.circular(8)), child: const Text('لا يدعم TR-069', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)))]),
                const SizedBox(height: 4),
                Text('IP: ${p.defaultIp}  |  User: ${p.defaultUser}  |  Pass: ${p.defaultPass.isEmpty ? "(فارغ)" : p.defaultPass}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontFamily: 'monospace')),
                if (p.altUsers.isNotEmpty || p.altPasswords.isNotEmpty) Text('بديل: ${[...p.altUsers, ...p.altPasswords.map((x) => x.isEmpty ? "(فارغ)" : x)].join(" / ")}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                if (p.supportsTr069) Text('TR-069: ${p.tr069Path}', style: TextStyle(fontSize: 11, color: Colors.indigo.shade700, fontWeight: FontWeight.w600)),
              ])),
            ]),
          );
        })),
      ])),
    )));
  }
}
