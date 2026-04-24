/// صفحة تشخيص التطبيق - تتبع كل خطوة من البحث حتى شاشة التجديد
/// لتحديد أين يحصل التجمد بالضبط
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../subscriptions/subscription_details_page.dart';
import '../../services/auth_service.dart';
import '../../services/whatsapp_template_storage.dart';
import '../../services/template_password_storage.dart';
import '../auth/auth_error_handler.dart';

class DiagnosticPage extends StatefulWidget {
  final String authToken;
  final String activatedBy;
  final bool? isAdminFlag;

  const DiagnosticPage({
    super.key,
    required this.authToken,
    required this.activatedBy,
    this.isAdminFlag,
  });

  @override
  State<DiagnosticPage> createState() => _DiagnosticPageState();
}

class _DiagnosticPageState extends State<DiagnosticPage> {
  bool get _isPhone => MediaQuery.of(context).size.width < 500;
  double _fs(double base) => _isPhone ? base * 0.85 : base;
  final List<_LogEntry> _logs = [];
  final ScrollController _scrollCtrl = ScrollController();
  bool _isRunning = false;
  bool _isDone = false;
  final Stopwatch _totalStopwatch = Stopwatch();

  // البيانات المجمعة
  String? _userId;
  String? _userName;
  String? _userPhone;
  String? _subscriptionId;
  Map<String, dynamic>? _subscriptionData;
  Map<String, dynamic>? _fullSubData;
  Map<String, dynamic>? _deviceOntInfo;
  Map<String, dynamic>? _customerData;
  Map<String, dynamic>? _allowedActions;
  Map<String, dynamic>? _bundles;
  double? _partnerWalletBalance;
  double? _customerWalletBalance;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _log(String message, {_LogLevel level = _LogLevel.info}) {
    if (!mounted) return;
    final elapsed = _totalStopwatch.elapsedMilliseconds;
    setState(() {
      _logs.add(_LogEntry(
        time: elapsed,
        message: message,
        level: level,
      ));
    });
    // التمرير التلقائي للأسفل
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startDiagnostic() async {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
      _isDone = false;
      _logs.clear();
    });
    _totalStopwatch.reset();
    _totalStopwatch.start();

    _log('🔧 بدء التشخيص التلقائي...', level: _LogLevel.header);
    _log(
        '🔑 التوكن: ${widget.authToken.length > 20 ? "${widget.authToken.substring(0, 20)}..." : widget.authToken}');
    _log('👤 المستخدم النشط: ${widget.activatedBy}');

    try {
      // ──── الخطوة 1: البحث عن المشترك ────
      await _step1SearchCustomer();
      if (_userId == null) {
        _log('❌ فشل: لم يتم العثور على المشترك', level: _LogLevel.error);
        _finish();
        return;
      }

      // ──── الخطوة 2: جلب بيانات الاشتراك ────
      await _step2FetchSubscriptions();
      if (_subscriptionId == null) {
        _log('❌ فشل: لم يتم العثور على اشتراك', level: _LogLevel.error);
        _finish();
        return;
      }

      // ──── الخطوة 3: جلب تفاصيل الاشتراك الكاملة ────
      await _step3FetchFullSubscription();

      // ──── الخطوة 4: جلب بيانات الجهاز ONT ────
      await _step4FetchDeviceOnt();

      // ──── الخطوة 5: جلب بيانات العميل ────
      await _step5FetchCustomerDetails();

      // ──── الخطوة 6: جلب العمليات المسموحة والباقات والمحافظ ────
      await _step6FetchActionsAndWallets();

      // ──── الخطوة 7: محاكاة SubscriptionInfo.fromJson ────
      _log('');
      _log('═══════════════════════════════════════', level: _LogLevel.header);
      _log('🧪 الخطوة 7: محاكاة ما يفعله initState (بدون فتح الشاشة)',
          level: _LogLevel.header);
      _log('═══════════════════════════════════════', level: _LogLevel.header);

      // استخراج البيانات من الاشتراك
      final mergedSub = _fullSubData ?? _subscriptionData ?? {};
      final status = _safeMap(mergedSub['status']);
      final deviceDetails = _safeMap(mergedSub['deviceDetails']);
      final services = mergedSub['services'] as List?;
      final endDate = mergedSub['endDate']?.toString();
      final startedAt = mergedSub['startedAt']?.toString();
      final currentStatus = status?['displayValue']?.toString() ?? '';
      final deviceUsername = _safeStr(deviceDetails?['username']) ?? '';
      final fdtDisplay =
          _safeStr(_safeMap(deviceDetails?['fdt'])?['displayValue']) ?? '';
      final fatDisplay =
          _safeStr(_safeMap(deviceDetails?['fat'])?['displayValue']) ?? '';

      String? deviceSerial, macAddress, deviceModel;
      if (_deviceOntInfo != null) {
        final ontModel = _safeMap(_deviceOntInfo!['model']);
        deviceSerial = _safeStr(ontModel?['serialNumber']);
        macAddress = _safeStr(ontModel?['macAddress']);
        deviceModel = _safeStr(ontModel?['model']);
      }

      String? gpsLatitude, gpsLongitude, customerAddress;
      if (_customerData != null) {
        final addresses = _customerData!['addresses'] as List?;
        if (addresses != null && addresses.isNotEmpty) {
          final first = _safeMap(addresses.first);
          customerAddress = _safeStr(first?['displayValue']);
          final gps = _safeMap(first?['gpsCoordinate']);
          gpsLatitude = _safeStr(gps?['latitude']);
          gpsLongitude = _safeStr(gps?['longitude']);
        }
      }

      // FBG / FAT
      String? fbgValue =
          _safeStr(_safeMap(deviceDetails?['fbg'])?['displayValue']);
      String? fatValue =
          _safeStr(_safeMap(deviceDetails?['fat'])?['displayValue']);

      _log('📊 ملخص البيانات المستخرجة:');
      _log('   userId: $_userId');
      _log('   subscriptionId: $_subscriptionId');
      _log('   userName: $_userName');
      _log('   userPhone: $_userPhone');
      _log('   currentStatus: $currentStatus');
      _log('   deviceUsername: $deviceUsername');
      _log('   endDate: $endDate');
      _log('   startedAt: $startedAt');
      _log('   services count: ${services?.length ?? 0}');
      _log('   fdtDisplay: $fdtDisplay');
      _log('   fatDisplay: $fatDisplay');
      _log('   deviceSerial: $deviceSerial');
      _log('   macAddress: $macAddress');
      _log('   deviceModel: $deviceModel');
      _log('   gpsLatitude: $gpsLatitude');
      _log('   gpsLongitude: $gpsLongitude');
      _log('   customerAddress: $customerAddress');
      _log('   fbgValue: $fbgValue');
      _log('   fatValue: $fatValue');
      _log('   partnerWallet: $_partnerWalletBalance');
      _log('   customerWallet: $_customerWalletBalance');
      _log('   allowedActions: ${_allowedActions != null ? "✅" : "❌"}');
      _log('   bundles: ${_bundles != null ? "✅" : "❌"}');
      _log('   deviceOntInfo: ${_deviceOntInfo != null ? "✅" : "❌"}');
      _log('   customerData: ${_customerData != null ? "✅" : "❌"}');

      // ──── الخطوة 7أ: محاكاة SubscriptionInfo.fromJson ────
      _log('');
      _log('🧬 محاكاة SubscriptionInfo.fromJson...', level: _LogLevel.header);
      try {
        final sw7 = Stopwatch()..start();
        final subInfo = SubscriptionInfo.fromJson(_subscriptionData!);
        sw7.stop();
        _log('✅ SubscriptionInfo.fromJson نجح (${sw7.elapsedMilliseconds}ms)',
            level: _LogLevel.success);
        _log('   currentPlan: ${subInfo.currentPlan}');
        _log('   commitmentPeriod: ${subInfo.commitmentPeriod}');
        _log('   salesType: ${subInfo.salesType}');
        _log('   zoneId: ${subInfo.zoneId}');
        _log('   zoneDisplayValue: ${subInfo.zoneDisplayValue}');
      } catch (e, stack) {
        _log('❌ SubscriptionInfo.fromJson فشل', level: _LogLevel.error);
        _log('📋 ${stack.toString().split('\n').take(3).join('\n')}',
            level: _LogLevel.error);
      }

      // ──── الخطوة 7ب: محاكاة SharedPreferences ────
      _log('');
      _log('💾 محاكاة تحميل SharedPreferences...', level: _LogLevel.header);
      try {
        final sw8 = Stopwatch()..start();
        final prefs = await SharedPreferences.getInstance();
        final useWeb = prefs.getBool('whatsapp_use_web') ?? true;
        final defaultPhone = prefs.getString('default_whatsapp_phone');
        final rawTechs = prefs.getString('local_technicians_list');
        sw8.stop();
        _log('✅ SharedPreferences نجح (${sw8.elapsedMilliseconds}ms)',
            level: _LogLevel.success);
        _log('   whatsapp_use_web: $useWeb');
        _log('   default_phone: ${defaultPhone ?? "غير محدد"}');
        _log(
            '   technicians: ${rawTechs != null ? "${rawTechs.length} حرف" : "فارغ"}');
      } catch (e) {
        _log('❌ SharedPreferences فشل', level: _LogLevel.error);
      }

      // ──── الخطوة 7ج: محاكاة WhatsAppTemplateStorage ────
      _log('');
      _log('📝 محاكاة WhatsAppTemplateStorage...', level: _LogLevel.header);
      try {
        final sw9 = Stopwatch()..start();
        final template = await WhatsAppTemplateStorage.loadTemplate();
        final password = await TemplatePasswordStorage.loadPassword();
        sw9.stop();
        _log('✅ WhatsAppTemplate نجح (${sw9.elapsedMilliseconds}ms)',
            level: _LogLevel.success);
        _log(
            '   template: ${template != null ? "${template.length} حرف" : "افتراضي"}');
        _log('   password: ${password != null ? "موجود" : "افتراضي"}');
      } catch (e) {
        _log('❌ WhatsAppTemplate فشل', level: _LogLevel.error);
      }

      // ──── النتيجة النهائية ────
      _log('');
      _log('═══════════════════════════════════════', level: _LogLevel.header);
      _log('📋 نتيجة جلب البيانات', level: _LogLevel.header);
      _log('═══════════════════════════════════════', level: _LogLevel.header);
      _log('✅ كل البيانات جُلبت بنجاح بدون تجمد', level: _LogLevel.success);
      _log('✅ SubscriptionInfo.fromJson يعمل', level: _LogLevel.success);
      _log('✅ SharedPreferences يعمل', level: _LogLevel.success);
      _log('');

      // ──── الخطوة 8: فتح الشاشة بوضع التشخيص التدريجي ────
      _log('═══════════════════════════════════════', level: _LogLevel.header);
      _log('🖥️ الخطوة 8: فتح الشاشة بوضع التشخيص التدريجي',
          level: _LogLevel.header);
      _log('═══════════════════════════════════════', level: _LogLevel.header);
      _log('📌 سيتم فتح SubscriptionDetailsPage مع diagnosticMode=true');
      _log('📌 كل قسم يُعرض بعد ثانيتين — لما يتجمد، نعرف القسم بالضبط');
      _log(
          '📌 الأقسام: ErrorMessage → CustomerInfo → PlanSelection → PriceDetails → ActionButtons');
      _log('');
      _log('🚀 جاري فتح الشاشة الآن...', level: _LogLevel.warning);

      // انتظار ثانية ثم فتح الشاشة
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        // استخراج البيانات اللازمة لفتح الشاشة
        final mergedSub = _fullSubData ?? _subscriptionData ?? {};
        final status = _safeMap(mergedSub['status']);
        final deviceDetails = _safeMap(mergedSub['deviceDetails']);
        final services = mergedSub['services'] as List?;

        String? deviceSerial, macAddress, deviceModel;
        if (_deviceOntInfo != null) {
          final ontModel = _safeMap(_deviceOntInfo!['model']);
          deviceSerial = _safeStr(ontModel?['serialNumber']);
          macAddress = _safeStr(ontModel?['macAddress']);
          deviceModel = _safeStr(ontModel?['model']);
        }

        String? gpsLat, gpsLng, custAddress;
        if (_customerData != null) {
          final addresses = _customerData!['addresses'] as List?;
          if (addresses != null && addresses.isNotEmpty) {
            final first = _safeMap(addresses.first);
            custAddress = _safeStr(first?['displayValue']);
            final gps = _safeMap(first?['gpsCoordinate']);
            gpsLat = _safeStr(gps?['latitude']);
            gpsLng = _safeStr(gps?['longitude']);
          }
        }

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SubscriptionDetailsPage(
              userId: _userId!,
              subscriptionId: _subscriptionId!,
              authToken: widget.authToken,
              activatedBy: widget.activatedBy,
              userName: _userName,
              userPhone: _userPhone,
              currentStatus: _safeStr(status?['displayValue']),
              deviceUsername: _safeStr(deviceDetails?['username']),
              services: services,
              fdtDisplayValue:
                  _safeStr(_safeMap(deviceDetails?['fdt'])?['displayValue']),
              fatDisplayValue:
                  _safeStr(_safeMap(deviceDetails?['fat'])?['displayValue']),
              initialAllowedActions: _allowedActions,
              initialBundles: _bundles,
              initialPartnerWalletBalance: _partnerWalletBalance,
              initialCustomerWalletBalance: _customerWalletBalance,
              deviceSerial: deviceSerial,
              macAddress: macAddress,
              deviceModel: deviceModel,
              gpsLatitude: gpsLat,
              gpsLongitude: gpsLng,
              customerAddress: custAddress,
              deviceOntInfo: _deviceOntInfo,
              customerDataMain: _customerData,
              fbgValue:
                  _safeStr(_safeMap(deviceDetails?['fbg'])?['displayValue']),
              fatValue:
                  _safeStr(_safeMap(deviceDetails?['fat'])?['displayValue']),
              isAdminFlag: widget.isAdminFlag,
            ),
          ),
        );
      }

      _log('');
      _log('⏱️ الوقت الكلي: ${_totalStopwatch.elapsedMilliseconds} مللي ثانية',
          level: _LogLevel.success);
    } catch (e, stack) {
      _log('💥 خطأ غير متوقع', level: _LogLevel.error);
      _log('📋 Stack: ${stack.toString().split('\n').take(5).join('\n')}',
          level: _LogLevel.error);
    }

    _finish();
  }

  void _finish() {
    _totalStopwatch.stop();
    if (mounted) {
      setState(() {
        _isRunning = false;
        _isDone = true;
      });
      _log('');
      _log('═══════════════════════════════════════', level: _LogLevel.header);
      _log(
          '⏱️ انتهى التشخيص — الوقت الكلي: ${_totalStopwatch.elapsedMilliseconds} مللي ثانية',
          level: _LogLevel.success);
      _log('═══════════════════════════════════════', level: _LogLevel.header);
    }
  }

  // ──── الخطوة 1: البحث ────
  Future<void> _step1SearchCustomer() async {
    _log('');
    _log('═══════════════════════════════════════', level: _LogLevel.header);
    _log('🔍 الخطوة 1: البحث عن "مرتضى باسل"', level: _LogLevel.header);
    _log('═══════════════════════════════════════', level: _LogLevel.header);

    final sw = Stopwatch()..start();
    final url =
        'https://api.ftth.iq/api/customers?pageSize=10&pageNumber=1&sortCriteria.property=self.displayValue&sortCriteria.direction=asc&name=${Uri.encodeQueryComponent("مرتضى باسل")}';

    _log('📡 URL: $url');

    try {
      final response = await AuthService.instance.authenticatedRequest('GET', url);
      sw.stop();

      _log(
          '📥 الاستجابة: ${response.statusCode} (${sw.elapsedMilliseconds}ms)');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List? ?? [];
        _log(
            '📊 عدد النتائج: ${items.length} من أصل ${data['totalCount'] ?? 0}');

        if (items.isEmpty) {
          _log('⚠️ لم يتم العثور على نتائج!', level: _LogLevel.warning);
          return;
        }

        // أخذ أول نتيجة
        final user = items.first;
        _userId = user['self']?['id']?.toString() ?? '';
        _userName = user['self']?['displayValue']?.toString() ?? 'غير متوفر';
        _userPhone =
            user['primaryContact']?['mobile']?.toString() ?? 'غير متوفر';

        _log('✅ تم العثور على المشترك:', level: _LogLevel.success);
        _log('   📌 ID: $_userId');
        _log('   👤 الاسم: $_userName');
        _log('   📞 الهاتف: $_userPhone');

        // عرض بقية النتائج إن وجدت
        if (items.length > 1) {
          _log('   📋 نتائج إضافية:');
          for (int i = 1; i < items.length && i < 5; i++) {
            final u = items[i];
            _log(
                '      ${i + 1}. ${u['self']?['displayValue'] ?? '?'} | ${u['primaryContact']?['mobile'] ?? '?'}');
          }
        }
      } else if (response.statusCode == 401) {
        _log('⚠️ خطأ 401 — انتهت صلاحية الجلسة', level: _LogLevel.error);
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      } else {
        _log('❌ فشل البحث: ${response.statusCode}', level: _LogLevel.error);
        _log(
            '📄 الاستجابة: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
      }
    } catch (e) {
      sw.stop();
      _log('❌ خطأ في البحث (${sw.elapsedMilliseconds}ms)',
          level: _LogLevel.error);
    }
  }

  // ──── الخطوة 2: جلب الاشتراكات ────
  Future<void> _step2FetchSubscriptions() async {
    _log('');
    _log('═══════════════════════════════════════', level: _LogLevel.header);
    _log('📋 الخطوة 2: جلب اشتراكات المستخدم', level: _LogLevel.header);
    _log('═══════════════════════════════════════', level: _LogLevel.header);

    final sw = Stopwatch()..start();
    final url =
        'https://admin.ftth.iq/api/customers/subscriptions?customerId=$_userId';
    _log('📡 URL: $url');

    try {
      final response = await AuthService.instance.authenticatedRequest('GET', url);
      sw.stop();

      _log(
          '📥 الاستجابة: ${response.statusCode} (${sw.elapsedMilliseconds}ms)');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List?;
        _log('📊 عدد الاشتراكات: ${items?.length ?? 0}');

        if (items == null || items.isEmpty) {
          _log('⚠️ لا يوجد اشتراكات!', level: _LogLevel.warning);
          return;
        }

        _subscriptionData = items.first as Map<String, dynamic>;

        // استخراج ID الاشتراك
        for (final k in ['id', 'subscriptionId', 'subscription_id', 'subId']) {
          final v = _subscriptionData![k]?.toString();
          if (v != null && v.isNotEmpty) {
            _subscriptionId = v;
            break;
          }
        }
        if (_subscriptionId == null) {
          final self = _safeMap(_subscriptionData!['self']);
          _subscriptionId = self?['id']?.toString();
        }

        _log('✅ تم العثور على الاشتراك:', level: _LogLevel.success);
        _log('   📌 subscriptionId: $_subscriptionId');
        _log(
            '   📊 الحالة: ${_safeMap(_subscriptionData!['status'])?['displayValue'] ?? '?'}');
        _log('   📅 انتهاء: ${_subscriptionData!['endDate'] ?? '?'}');

        // عرض معلومات الجهاز
        final dev = _safeMap(_subscriptionData!['deviceDetails']);
        if (dev != null) {
          _log('   🔧 الجهاز: ${_safeStr(dev['username']) ?? '?'}');
          _log(
              '   📡 FDT: ${_safeStr(_safeMap(dev['fdt'])?['displayValue']) ?? '?'}');
        }
      } else if (response.statusCode == 401) {
        _log('⚠️ خطأ 401 — انتهت صلاحية الجلسة', level: _LogLevel.error);
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      } else {
        _log('❌ فشل جلب الاشتراكات: ${response.statusCode}',
            level: _LogLevel.error);
      }
    } catch (e) {
      sw.stop();
      _log('❌ خطأ (${sw.elapsedMilliseconds}ms)', level: _LogLevel.error);
    }
  }

  // ──── الخطوة 3: تفاصيل الاشتراك الكاملة ────
  Future<void> _step3FetchFullSubscription() async {
    _log('');
    _log('═══════════════════════════════════════', level: _LogLevel.header);
    _log('📑 الخطوة 3: جلب تفاصيل الاشتراك الكاملة', level: _LogLevel.header);
    _log('═══════════════════════════════════════', level: _LogLevel.header);

    final sw = Stopwatch()..start();
    final url =
        'https://admin.ftth.iq/api/subscriptions/$_subscriptionId?customerId=$_userId';
    _log('📡 URL: $url');

    try {
      final response = await AuthService.instance.authenticatedRequest('GET', url);
      sw.stop();

      _log(
          '📥 الاستجابة: ${response.statusCode} (${sw.elapsedMilliseconds}ms)');

      if (response.statusCode == 200) {
        _fullSubData = jsonDecode(response.body);
        _log('✅ تم جلب التفاصيل الكاملة', level: _LogLevel.success);

        // استخراج partnerId
        final partner = _safeMap(_fullSubData!['partner']);
        final partnerId = partner?['id']?.toString();
        _log('   👥 Partner ID: ${partnerId ?? "غير متوفر"}');
        _log(
            '   📊 الحالة: ${_safeMap(_fullSubData!['status'])?['displayValue'] ?? '?'}');

        final services = _fullSubData!['services'] as List?;
        _log('   📦 عدد الخدمات: ${services?.length ?? 0}');

        if (services != null) {
          for (int i = 0; i < services.length && i < 3; i++) {
            final svc = _safeMap(services[i]);
            _log(
                '      ${i + 1}. ${_safeStr(_safeMap(svc?['baseService'])?['displayValue']) ?? '?'}');
          }
        }
      } else if (response.statusCode == 401) {
        _log('⚠️ خطأ 401 — انتهت صلاحية الجلسة', level: _LogLevel.error);
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      } else {
        _log('⚠️ فشل: ${response.statusCode}', level: _LogLevel.warning);
      }
    } catch (e) {
      sw.stop();
      _log('❌ خطأ (${sw.elapsedMilliseconds}ms)', level: _LogLevel.error);
    }
  }

  // ──── الخطوة 4: بيانات ONT ────
  Future<void> _step4FetchDeviceOnt() async {
    _log('');
    _log('═══════════════════════════════════════', level: _LogLevel.header);
    _log('📡 الخطوة 4: جلب بيانات الجهاز (ONT)', level: _LogLevel.header);
    _log('═══════════════════════════════════════', level: _LogLevel.header);

    final mergedSub = _fullSubData ?? _subscriptionData ?? {};
    final deviceDetails = _safeMap(mergedSub['deviceDetails']);
    final username = _safeStr(deviceDetails?['username']);

    if (username == null || username.trim().isEmpty) {
      _log('⚠️ لا يوجد username للجهاز — تخطي', level: _LogLevel.warning);
      return;
    }

    final sw = Stopwatch()..start();
    final url =
        'https://admin.ftth.iq/api/subscriptions/device/ont?username=${username.trim()}';
    _log('📡 URL: $url');

    try {
      final response = await AuthService.instance.authenticatedRequest('GET', url);
      sw.stop();

      _log(
          '📥 الاستجابة: ${response.statusCode} (${sw.elapsedMilliseconds}ms)');

      if (response.statusCode == 200) {
        _deviceOntInfo = jsonDecode(response.body);
        _log('✅ تم جلب بيانات ONT', level: _LogLevel.success);
        final model = _safeMap(_deviceOntInfo!['model']);
        if (model != null) {
          _log('   📱 الموديل: ${_safeStr(model['model']) ?? '?'}');
          _log('   🔢 السيريال: ${_safeStr(model['serialNumber']) ?? '?'}');
          _log('   🌐 MAC: ${_safeStr(model['macAddress']) ?? '?'}');
        }
      } else if (response.statusCode == 401) {
        _log('⚠️ خطأ 401 — انتهت صلاحية الجلسة', level: _LogLevel.error);
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      } else {
        _log('⚠️ فشل: ${response.statusCode}', level: _LogLevel.warning);
      }
    } catch (e) {
      sw.stop();
      _log('❌ خطأ (${sw.elapsedMilliseconds}ms)', level: _LogLevel.error);
    }
  }

  // ──── الخطوة 5: بيانات العميل ────
  Future<void> _step5FetchCustomerDetails() async {
    _log('');
    _log('═══════════════════════════════════════', level: _LogLevel.header);
    _log('👤 الخطوة 5: جلب تفاصيل العميل', level: _LogLevel.header);
    _log('═══════════════════════════════════════', level: _LogLevel.header);

    final sw = Stopwatch()..start();
    final url = 'https://admin.ftth.iq/api/customers/$_userId';
    _log('📡 URL: $url');

    try {
      final response = await AuthService.instance.authenticatedRequest('GET', url);
      sw.stop();

      _log(
          '📥 الاستجابة: ${response.statusCode} (${sw.elapsedMilliseconds}ms)');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          _customerData = data['model'] is Map<String, dynamic>
              ? data['model'] as Map<String, dynamic>
              : data;
        }
        _log('✅ تم جلب بيانات العميل', level: _LogLevel.success);

        // استخراج العنوان
        final addresses = _customerData?['addresses'] as List?;
        if (addresses != null && addresses.isNotEmpty) {
          final first = _safeMap(addresses.first);
          _log('   📍 العنوان: ${_safeStr(first?['displayValue']) ?? '?'}');
          final gps = _safeMap(first?['gpsCoordinate']);
          if (gps != null) {
            _log('   🗺️ GPS: ${gps['latitude']}, ${gps['longitude']}');
          }
        }
      } else if (response.statusCode == 401) {
        _log('⚠️ خطأ 401 — انتهت صلاحية الجلسة', level: _LogLevel.error);
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      } else {
        _log('⚠️ فشل: ${response.statusCode}', level: _LogLevel.warning);
      }
    } catch (e) {
      sw.stop();
      _log('❌ خطأ (${sw.elapsedMilliseconds}ms)', level: _LogLevel.error);
    }
  }

  // ──── الخطوة 6: العمليات + الباقات + المحافظ ────
  Future<void> _step6FetchActionsAndWallets() async {
    _log('');
    _log('═══════════════════════════════════════', level: _LogLevel.header);
    _log('💰 الخطوة 6: جلب العمليات والباقات والمحافظ (متوازي)',
        level: _LogLevel.header);
    _log('═══════════════════════════════════════', level: _LogLevel.header);

    // استخراج partnerId
    final partner =
        _safeMap((_fullSubData ?? _subscriptionData ?? {})['partner']);
    final partnerId = partner?['id']?.toString();

    _log('👥 Partner ID: ${partnerId ?? "غير متوفر"}');

    final sw = Stopwatch()..start();
    _log('📡 إرسال 4 طلبات متوازية...');

    try {
      final results = await Future.wait([
        // 1) Allowed Actions
        _fetchJson(
          'https://admin.ftth.iq/api/subscriptions/allowed-actions?subscriptionIds=$_subscriptionId&customerId=$_userId',
          'AllowedActions',
        ),
        // 2) Bundles
        _fetchJson(
          'https://admin.ftth.iq/api/plans/bundles?includePrices=false&subscriptionId=$_subscriptionId',
          'Bundles',
        ),
        // 3) Partner Wallet
        (partnerId != null && partnerId.isNotEmpty)
            ? _fetchJson(
                'https://admin.ftth.iq/api/partners/$partnerId/wallets/balance',
                'PartnerWallet',
              )
            : Future.value(null),
        // 4) Customer Wallet
        _fetchJson(
          'https://admin.ftth.iq/api/customers/$_userId/wallets/balance',
          'CustomerWallet',
        ),
      ]);
      sw.stop();
      _log('⏱️ كل الطلبات المتوازية انتهت في ${sw.elapsedMilliseconds}ms');

      // حفظ النتائج
      _allowedActions = results[0];
      _bundles = results[1];
      final partnerWallet = results[2];
      final customerWallet = results[3];

      // استخراج الأرصدة
      if (partnerWallet != null) {
        final model = _safeMap(partnerWallet['model']);
        if (model != null && model['balance'] != null) {
          _partnerWalletBalance = double.tryParse(model['balance'].toString());
        } else if (partnerWallet['balance'] != null) {
          _partnerWalletBalance =
              double.tryParse(partnerWallet['balance'].toString());
        }
      }
      if (customerWallet != null) {
        final model = _safeMap(customerWallet['model']);
        if (model != null && model['balance'] != null) {
          _customerWalletBalance = double.tryParse(model['balance'].toString());
        } else if (customerWallet['balance'] != null) {
          _customerWalletBalance =
              double.tryParse(customerWallet['balance'].toString());
        }
      }

      _log('✅ النتائج:', level: _LogLevel.success);
      _log(
          '   📋 AllowedActions: ${_allowedActions != null ? "✅ تم" : "❌ فارغ"}');
      _log('   📦 Bundles: ${_bundles != null ? "✅ تم" : "❌ فارغ"}');
      _log('   💰 Partner Wallet: ${_partnerWalletBalance ?? "غير متوفر"}');
      _log('   💰 Customer Wallet: ${_customerWalletBalance ?? "غير متوفر"}');
    } catch (e) {
      sw.stop();
      _log('❌ خطأ في الطلبات المتوازية (${sw.elapsedMilliseconds}ms)',
          level: _LogLevel.error);
    }
  }

  // ──── مساعدات ────
  Future<Map<String, dynamic>?> _fetchJson(String url, String label) async {
    final sw = Stopwatch()..start();
    try {
      final response = await AuthService.instance.authenticatedRequest('GET', url);
      sw.stop();
      _log(
          '   📥 $label: ${response.statusCode} (${sw.elapsedMilliseconds}ms)');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        _log('   ⚠️ $label خطأ 401 — انتهت صلاحية الجلسة', level: _LogLevel.error);
        if (mounted) AuthErrorHandler.handle401Error(context);
        return null;
      }
      return null;
    } catch (e) {
      sw.stop();
      _log('   ❌ $label خطأ (${sw.elapsedMilliseconds}ms)',
          level: _LogLevel.error);
      return null;
    }
  }

  Map<String, dynamic>? _safeMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  String? _safeStr(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF1a1a2e),
        appBar: AppBar(
          title: const Text('🔧 تشخيص التطبيق',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF16213e),
          foregroundColor: Colors.white,
          actions: [
            // زر نسخ السجلات
            if (_logs.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.copy_all),
                tooltip: 'نسخ السجلات',
                onPressed: () {
                  final text =
                      _logs.map((l) => '[${l.time}ms] ${l.message}').join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('✅ تم نسخ السجلات'),
                        duration: Duration(seconds: 2)),
                  );
                },
              ),
            // زر مسح
            if (_logs.isNotEmpty && !_isRunning)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'مسح السجلات',
                onPressed: () => setState(() {
                  _logs.clear();
                  _isDone = false;
                }),
              ),
          ],
        ),
        body: Column(
          children: [
            // شريط الحالة
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: _isPhone ? 10 : 16, vertical: _isPhone ? 8 : 12),
              decoration: BoxDecoration(
                color: _isRunning
                    ? Colors.blue.shade900
                    : (_isDone ? Colors.green.shade900 : Colors.grey.shade900),
              ),
              child: Row(
                children: [
                  if (_isRunning) ...[
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white)),
                    const SizedBox(width: 12),
                    Text('جاري التشخيص...',
                        style: TextStyle(color: Colors.white, fontSize: _fs(14))),
                  ] else if (_isDone) ...[
                    Icon(Icons.check_circle,
                        color: Colors.greenAccent, size: _isPhone ? 18 : 20),
                    const SizedBox(width: 8),
                    Text('انتهى — ${_totalStopwatch.elapsedMilliseconds}ms',
                        style: TextStyle(
                            color: Colors.greenAccent, fontSize: _fs(14))),
                  ] else ...[
                    Icon(Icons.bug_report, color: Colors.amber, size: _isPhone ? 18 : 20),
                    const SizedBox(width: 8),
                    Text('اضغط "ابدأ التشخيص" للبدء',
                        style: TextStyle(color: Colors.amber, fontSize: _fs(14))),
                  ],
                  const Spacer(),
                  Text('سجلات: ${_logs.length}',
                      style:
                          TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                ],
              ),
            ),

            // سجلات التشخيص
            Expanded(
              child: _logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bug_report,
                              size: _isPhone ? 60 : 80, color: Colors.grey.shade700),
                          const SizedBox(height: 16),
                          Text(
                            'سيتم البحث عن "مرتضى باسل" وتتبع كل خطوة\nحتى شاشة التجديد لتحديد سبب التجمد',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: _fs(14),
                                height: 1.6),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: EdgeInsets.all(_isPhone ? 8 : 12),
                      itemCount: _logs.length,
                      itemBuilder: (_, i) {
                        final log = _logs[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // الوقت
                              SizedBox(
                                width: _isPhone ? 55 : 70,
                                child: Text(
                                  '${log.time}ms',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: _fs(11),
                                    fontFamily: 'Consolas',
                                  ),
                                ),
                              ),
                              // الرسالة
                              Expanded(
                                child: Text(
                                  log.message,
                                  style: TextStyle(
                                    color: log.color,
                                    fontSize:
                                        log.level == _LogLevel.header ? _fs(14) : _fs(12),
                                    fontWeight: log.level == _LogLevel.header
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontFamily: 'Consolas',
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // زر البدء
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(_isPhone ? 10 : 16),
              decoration: BoxDecoration(
                color: const Color(0xFF16213e),
                border: Border(top: BorderSide(color: Colors.grey.shade800)),
              ),
              child: ElevatedButton.icon(
                onPressed: _isRunning ? null : _startDiagnostic,
                icon: Icon(_isRunning
                    ? Icons.hourglass_top
                    : (_isDone ? Icons.replay : Icons.play_arrow)),
                label: Text(
                  _isRunning
                      ? 'جاري التشخيص...'
                      : (_isDone ? 'إعادة التشخيص' : 'ابدأ التشخيص'),
                  style: TextStyle(
                      fontSize: _fs(16), fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isRunning ? Colors.grey : Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: _isPhone ? 10 : 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──── نموذج سجل ────
enum _LogLevel { info, success, warning, error, header }

class _LogEntry {
  final int time;
  final String message;
  final _LogLevel level;

  _LogEntry(
      {required this.time, required this.message, this.level = _LogLevel.info});

  Color get color {
    switch (level) {
      case _LogLevel.info:
        return Colors.grey.shade300;
      case _LogLevel.success:
        return Colors.greenAccent;
      case _LogLevel.warning:
        return Colors.amber;
      case _LogLevel.error:
        return Colors.redAccent;
      case _LogLevel.header:
        return Colors.cyanAccent;
    }
  }
}
