/// صفحة الشركة - عرض لوحة تحكم admin.ftth.iq في WebView
/// تسجيل الدخول التلقائي باستخدام بيانات المستخدم الميداني
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import '../../services/company_settings_service.dart';
import '../../services/custom_auth_service.dart';
import '../../services/vps_auth_service.dart';
import '../../task/add_task_api_dialog.dart';

class FtthCompanyPage extends StatefulWidget {
  const FtthCompanyPage({super.key});

  @override
  State<FtthCompanyPage> createState() => _FtthCompanyPageState();
}

class _FtthCompanyPageState extends State<FtthCompanyPage> {
  final WebviewController _controller = WebviewController();
  bool _isInitialized = false;
  bool _isLoading = true;
  bool _autoLoginDone = false;
  String _currentUrl = '';

  static const String _loginUrl = 'https://admin.ftth.iq/auth/login';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _initWebView() async {
    if (!Platform.isWindows) return;

    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.white);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      // متابعة الرابط الحالي
      _controller.url.listen((url) {
        if (!mounted) return;
        _currentUrl = url;
      });

      // عند اكتمال تحميل الصفحة → محاولة الدخول التلقائي
      _controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() => _isLoading = state == LoadingState.loading);

        if (state == LoadingState.navigationCompleted &&
            !_autoLoginDone &&
            _currentUrl.contains('/auth/login')) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !_autoLoginDone) _tryAutoLogin();
          });
        }
      });

      // استماع لرسائل من الـ WebView
      _controller.webMessage.listen((message) {
        if (!mounted) return;
        final msg = message.toString();
        if (msg.startsWith('AUTO_LOGIN:SUCCESS')) {
          debugPrint('🏢 صفحة الشركة: تسجيل دخول تلقائي ناجح');
          _autoLoginDone = true;
        } else if (msg.startsWith('AUTO_LOGIN:FAIL')) {
          debugPrint('🏢 صفحة الشركة: فشل الدخول التلقائي - $msg');
          _autoLoginDone = true;
        } else if (msg.startsWith('TASK_DATA:')) {
          try {
            final jsonStr = msg.substring('TASK_DATA:'.length);
            final data = Map<String, dynamic>.from(
              const JsonDecoder().convert(jsonStr) as Map,
            );
            debugPrint('🏢 بيانات المشترك: $data');
            _openTaskDialog(data);
          } catch (e) {
            debugPrint('❌ خطأ في تحليل بيانات المشترك: $e');
          }
        }
      });

      await _controller.loadUrl(_loginUrl);

      if (mounted) setState(() => _isInitialized = true);
    } catch (_) {}
  }

  /// محاولة تسجيل دخول تلقائي ببيانات المستخدم الميداني
  Future<void> _tryAutoLogin() async {
    try {
      final tenantId = VpsAuthService.instance.currentCompanyId ??
          CustomAuthService().currentTenantId;
      debugPrint('🏢 صفحة الشركة: tenantId=$tenantId');

      if (tenantId == null) return;

      final fieldUser =
          await CompanySettingsService.getFieldUser(tenantId: tenantId);
      if (fieldUser == null) {
        debugPrint('🏢 صفحة الشركة: لا يوجد مستخدم ميداني - دخول يدوي');
        return;
      }

      debugPrint('🏢 صفحة الشركة: بدء دخول تلقائي بـ ${fieldUser.username}');
      _autoLoginDone = true;

      final jsCode = '''
        (async function() {
          try {
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
              body: 'username=${_escapeJs(fieldUser.username)}&password=${_escapeJs(fieldUser.password)}&grant_type=password'
            });
            const data = await resp.json();
            if (data && data.access_token) {
              localStorage.setItem('access_token', data.access_token);
              localStorage.setItem('refresh_token', data.refresh_token || '');
              localStorage.setItem('token', JSON.stringify(data));
              localStorage.setItem('currentUser', JSON.stringify(data));
              window.chrome.webview.postMessage('AUTO_LOGIN:SUCCESS');
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
      debugPrint('🏢 صفحة الشركة: خطأ في الدخول التلقائي: $e');
    }
  }

  /// فتح صفحة الشركة في نافذة مستقلة (Edge --app mode)
  Future<void> _openInSeparateWindow() async {
    final url = _currentUrl.isNotEmpty ? _currentUrl : 'https://admin.ftth.iq/';
    try {
      final browsers = [
        'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
        'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
        'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
        'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
      ];
      String? browserPath;
      for (final path in browsers) {
        if (await File(path).exists()) { browserPath = path; break; }
      }
      if (browserPath != null) {
        await Process.start(browserPath, ['--app=$url', '--window-size=1200,800']);
        if (mounted) Navigator.of(context).pop();
      } else {
        await Process.start('cmd', ['/c', 'start', url]);
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('❌ فشل فتح نافذة مستقلة: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل فتح نافذة مستقلة')));
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
            // فصل في نافذة مستقلة (Windows فقط)
            if (Platform.isWindows)
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 20),
                tooltip: 'فتح في نافذة مستقلة',
                onPressed: _openInSeparateWindow,
              ),
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
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _extractAndCreateTask,
          backgroundColor: const Color(0xFF1A237E),
          icon: const Icon(Icons.add_task, color: Colors.white),
          label: const Text('إنشاء مهمة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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

  /// استخراج بيانات المشترك من WebView وفتح نموذج إنشاء مهمة
  Future<void> _extractAndCreateTask() async {
    if (!_isInitialized) return;

    try {
      // JavaScript لاستخراج البيانات من صفحة admin.ftth.iq
      // يبحث عن أزواج (تسمية: قيمة) في كل الصفحة ثم يستخرج الحقول المطلوبة
      final js = r'''
        (function() {
          var data = {name:'', phone:'', fbg:'', fat:'', serviceType:'', duration:'', subscriptionId:''};

          // جمع كل النصوص المرئية في الصفحة مع عناصرها
          var allText = document.body.innerText || '';

          // 1) الاسم — من breadcrumb "الحساب / الاسم / الاشتراكات" أو من العنوان بجانب السهم
          // طريقة 1: breadcrumb
          var breadcrumb = allText.match(/الحساب\s*\/\s*([^\/\n]+)\s*\//);
          if (breadcrumb) data.name = breadcrumb[1].trim();
          // طريقة 2: معلومات الاتصال — الاسم بجانب التسمية
          if (!data.name) {
            var contactMatch = allText.match(/معلومات الاتصال[:\s]*\n?\s*([\u0600-\u06FF][\u0600-\u06FF\s]+)/);
            if (contactMatch) data.name = contactMatch[1].trim();
          }
          // طريقة 3: أول سطر عربي طويل بعد سهم الرجوع
          if (!data.name) {
            var arrowMatch = allText.match(/[←→\u2192]\s*([\u0600-\u06FF][\u0600-\u06FF\s]{4,60})/);
            if (arrowMatch) data.name = arrowMatch[1].trim();
          }

          // 2) دالة بحث بالنمط في النص الكامل
          function findByPattern(pattern) {
            var match = allText.match(pattern);
            return match ? (match[1] || match[0]).trim() : '';
          }

          // 3) الهاتف — بحث عن رقم عراقي (07xx)
          var phoneMatch = allText.match(/(?:رقم الهاتف|الهاتف|Phone)[:\s]*\n?\s*(07\d{8,9})/);
          if (phoneMatch) data.phone = phoneMatch[1];
          if (!data.phone) {
            // بحث عن أي رقم 07 في الصفحة
            var anyPhone = allText.match(/(07[0-9]{8,9})/);
            if (anyPhone) data.phone = anyPhone[1];
          }

          // 4) FBG/FDT — بحث عن FBG/FDT + رقم
          var fdtMatch = allText.match(/(?:FDT|المنطقة)[:\s]*\n?\s*(FBG\d[\w-]*)/i);
          if (fdtMatch) data.fbg = fdtMatch[1];
          if (!data.fbg) {
            var fbgMatch = allText.match(/(FBG\d[\w-]*)/i);
            if (fbgMatch) data.fbg = fbgMatch[1];
          }

          // 5) FAT
          var fatMatch = allText.match(/FAT[:\s]*\n?\s*(FAT\d[\w-]*)/i);
          if (fatMatch) data.fat = fatMatch[1];
          if (!data.fat) {
            var fatAny = allText.match(/(FAT\d[\w-]*)/i);
            if (fatAny) data.fat = fatAny[1];
          }

          // 6) نوع الخدمة — FIBER XX
          var fiberMatch = allText.match(/FIBER\s*(\d+)/i);
          if (fiberMatch) data.serviceType = fiberMatch[1];

          // 7) مدة الالتزام — بحث في كل النص عن أي "رقم شهر/سنة" قريب من "لتزام"
          // أولاً: طباعة كل سطر فيه "لتزام" للتشخيص
          var lines = allText.split('\n');
          for (var li = 0; li < lines.length; li++) {
            if (/لتزام/.test(lines[li])) {
              // جمع 5 أسطر بعده
              var block = '';
              for (var k = li; k < Math.min(li + 6, lines.length); k++) {
                block += lines[k] + ' ';
              }
              var m = block.match(/(\d+)\s*(شهر|سنة|أشهر|شهور|سنوات)/);
              if (m) { data.duration = m[1] + ' ' + m[2]; break; }
            }
          }

          // 8) بطاقة التعريف
          var idMatch = allText.match(/بطاقة تعري[فة][:\s]*\n?\s*(\d+)/);
          if (idMatch) data.subscriptionId = idMatch[1];

          window.chrome.webview.postMessage('TASK_DATA:' + JSON.stringify(data));
        })();
      ''';

      await _controller.executeScript(js);

      // الاستماع للنتيجة عبر webMessage (نستخدم listener مؤقت)
      // بما أن الـ listener الرئيسي موجود، نضيف معالجة في _controller.webMessage
    } catch (e) {
      debugPrint('❌ خطأ في استخراج البيانات: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل استخراج البيانات من الصفحة'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// فتح نموذج إنشاء مهمة مع البيانات المستخرجة
  void _openTaskDialog(Map<String, dynamic> data) {
    final user = VpsAuthService.instance.currentUser;
    final username = user?.fullName ?? '';
    final role = user?.role ?? 'فني';
    final dept = '';

    showDialog(
      context: context,
      builder: (_) => AddTaskApiDialog(
        currentUsername: username,
        currentUserRole: role,
        currentUserDepartment: dept,
        initialCustomerName: data['name']?.toString(),
        initialCustomerPhone: data['phone']?.toString(),
        initialFBG: data['fbg']?.toString(),
        initialFAT: data['fat']?.toString(),
        initialServiceType: data['serviceType']?.toString(),
        initialSubscriptionDuration: data['duration']?.toString(),
        initialTaskType: 'شراء اشتراك',
        initialNotes: 'من صفحة الشركة — ${data['subscriptionId'] ?? ''}',
      ),
    );
  }
}
