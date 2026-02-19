import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // للـ Clipboard
import 'package:webview_windows/webview_windows.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../services/ftth_data_service.dart';
import '../../services/agents_auth_service.dart';
import '../server_data_page.dart'; // للوصول لـ FtthServerDataService.dashboardPath

/// صفحة جلب بيانات الموقع من الداشبورد
/// تفتح متصفح WebView وتسجل كل الطلبات والاستجابات
class FetchServerDataPage extends StatefulWidget {
  const FetchServerDataPage({super.key});

  @override
  State<FetchServerDataPage> createState() => _FetchServerDataPageState();
}

class _FetchServerDataPageState extends State<FetchServerDataPage> {
  final WebviewController _controller = WebviewController();
  bool _isLoading = true;
  bool _isInitialized = false;

  // قوائم تسجيل البيانات
  final List<Map<String, dynamic>> _capturedCharts = [];

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

  // رابط تسجيل الدخول
  static const String _loginUrl = 'https://admin.ftth.iq/auth/login';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      await _controller.initialize();

      // الاستماع لتغيير الرابط
      _controller.url.listen((url) {
        setState(() {
          _currentUrl = url;
          _requestCount++;
        });
      });

      // الاستماع لحالة التحميل
      _controller.loadingState.listen((state) {
        setState(() {
          _isLoading = state == LoadingState.loading;
          if (state == LoadingState.navigationCompleted) {
            _responseCount++;
            _statusMessage = 'تم تحميل الصفحة - انتظر اكتمال البيانات...';
            // حقن المعترض فقط - الاستخراج يدوي بعد اكتمال التحميل
            Future.delayed(const Duration(seconds: 1), () async {
              await _injectInterceptor();
              // لا نستخرج تلقائياً - ننتظر المستخدم يضغط زر الاستخراج
              // أو ننتظر وقت أطول للتأكد من اكتمال AJAX
              if (_currentUrl.contains('dashboard') ||
                  _currentUrl.contains('data')) {
                setState(() {
                  _statusMessage =
                      '📋 الصفحة جاهزة - اضغط ⬇️ للاستخراج عندما تظهر البيانات';
                });
              }
            });
          }
        });
      });

      // الاستماع للرسائل من JavaScript
      _controller.webMessage.listen(_handleWebMessage);

      // تحميل صفحة تسجيل الدخول
      await _controller.loadUrl(_loginUrl);

      setState(() {
        _isInitialized = true;
        _statusMessage = 'سجّل الدخول ثم انتقل للداشبورد';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'خطأ في تهيئة المتصفح: $e';
      });
    }
  }

  /// حقن JavaScript interceptor
  Future<void> _injectInterceptor() async {
    try {
      await _controller.executeScript(r'''
        (function() {
          if (window.__sdInterceptor) return;
          window.__sdInterceptor = true;
          window.__sdCharts = [];
          
          // Override fetch
          const origFetch = window.fetch;
          window.fetch = async function(url, opts) {
            const resp = await origFetch.apply(this, arguments);
            if (url && url.toString().includes('/chart/data')) {
              const clone = resp.clone();
              clone.json().then(d => {
                window.__sdCharts.push({u: url.toString(), d: d, t: Date.now()});
                try { window.chrome.webview.postMessage('CHART:' + window.__sdCharts.length); } catch(e) {}
              }).catch(() => {});
            }
            return resp;
          };
          
          // Override XHR
          const origOpen = XMLHttpRequest.prototype.open;
          const origSend = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function(m, u) {
            this.__url = u;
            return origOpen.apply(this, arguments);
          };
          XMLHttpRequest.prototype.send = function() {
            this.addEventListener('load', function() {
              if (this.__url && this.__url.includes('/chart/data')) {
                try {
                  const d = JSON.parse(this.responseText);
                  window.__sdCharts.push({u: this.__url, d: d, t: Date.now()});
                  try { window.chrome.webview.postMessage('CHART:' + window.__sdCharts.length); } catch(e) {}
                } catch(e) {}
              }
            });
            return origSend.apply(this, arguments);
          };
        })();
      ''');
    } catch (e) {
      debugPrint('Inject error: $e');
    }
  }

  /// معالجة الرسائل من JavaScript
  void _handleWebMessage(dynamic message) {
    final msg = message.toString();
    if (msg.startsWith('CHART:')) {
      final count = int.tryParse(msg.substring(6)) ?? 0;
      setState(() {
        _chartCount = count;
        _statusMessage = '✅ تم التقاط $count chart';
      });
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
          setState(() {
            _chartCount = _capturedCharts.length;
            _statusMessage = '✅ تم استخراج $_chartCount chart';
          });
        } else {
          // محاولة استخراج من DOM
          await _extractFromDOM();
        }
      }
    } catch (e) {
      debugPrint('Extract error: $e');
      // محاولة استخراج من DOM كبديل
      await _extractFromDOM();
    }

    setState(() => _isExtracting = false);
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

        setState(() {
          _chartCount = _capturedCharts.length;
          _statusMessage = itemCount > 0
              ? '✅ تم استخراج $itemCount عنصر في $_chartCount مجموعة'
              : '❌ لم يتم العثور على بيانات - تأكد من تحميل الصفحة';
        });
      }
    } catch (e) {
      debugPrint('DOM extract error: $e');
      setState(() {
        _statusMessage = '❌ خطأ في الاستخراج: $e';
      });
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
      _log('❌ خطأ في استخراج token: $e');
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
      // أولاً: محاولة استخراج token من WebView (إذا سجّل المستخدم الدخول)
      if (_extractedAuthToken == null && _isInitialized) {
        _log('🔍 محاولة استخراج token من WebView أولاً...');
        await _extractAuthTokenFromWebView();
      }

      // ثانياً: محاولة جلب Guest Token مع الـ auth token المستخرج
      _log('📡 محاولة AgentsAuthService.fetchGuestToken()...');
      var token = await AgentsAuthService.fetchGuestToken(
          authToken: _extractedAuthToken);
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

      setState(() => _guestToken = token);
      _log(token != null
          ? '✅ Guest Token جاهز (${token.substring(0, 20)}...)'
          : '❌ فشل الحصول على Guest Token - تأكد من تسجيل الدخول في المتصفح');
    } catch (e, stackTrace) {
      _log('❌ استثناء في _fetchGuestToken: $e');
      _log(
          '📋 Stack trace: ${stackTrace.toString().split('\n').take(5).join('\n')}');
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
      setState(() {
        _statusMessage = '🔑 جلب رمز المصادقة...';
        _isFetchingFromApi = true;
      });
      await _fetchGuestToken();
    } else {
      _log('✅ Guest Token موجود مسبقاً: ${_guestToken!.substring(0, 20)}...');
    }

    if (_guestToken == null) {
      _log('❌ فشل نهائي في الحصول على Guest Token');
      setState(() {
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

        setState(() {
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
          _log('❌ استثناء في جلب $chartName: $e');
          _log(
              '📋 Stack: ${stackTrace.toString().split('\n').take(3).join('\n')}');
        }
      }

      _log('═══════════════════════════════════════════');
      _log('📊 ملخص الجلب: $successCount نجاح، $totalRows سجل إجمالي');
      _log('═══════════════════════════════════════════');

      setState(() {
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
      _log('❌ استثناء عام: $e');
      _log('📋 Stack: ${stackTrace.toString().split('\n').take(5).join('\n')}');
      setState(() {
        _isFetchingFromApi = false;
        _statusMessage = '❌ خطأ: $e';
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

    if (confirmed != true) return;

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

      setState(() {
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
      setState(() {
        _isFetchingAllZones = false;
        _statusMessage = '❌ خطأ: $e';
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
          SnackBar(content: Text('❌ خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// مسح البيانات
  void _clearData() {
    setState(() {
      _capturedCharts.clear();
      _chartCount = 0;
      _statusMessage = 'تم مسح البيانات';
    });
  }

  /// تحديث الصفحة
  Future<void> _refresh() async {
    await _controller.reload();
  }

  @override
  void dispose() {
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
                ? Webview(_controller)
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
