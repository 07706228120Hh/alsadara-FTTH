// الجزء الأول: المستوردات والتعريفات الأساسية
// صفحة تجديد الاشتراك
import 'package:flutter/material.dart';
import '../widgets/notification_filter.dart';
import '../whatsapp/whatsapp_bottom_window.dart';
import '../../services/ftth/ftth_event_bus.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../services/whatsapp_template_storage.dart';
import '../../services/subscription_logs_service.dart';
import '../../services/vps_auth_service.dart';
import '../../services/thermal_printer_service.dart';
import '../../services/print_template_storage.dart';
import '../../services/template_password_storage.dart';
import '../../services/windows_automation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as wvwin;
import 'dart:io' show Platform;
import '../core/home_page.dart';

// ربط ملف عمليات التجديد والتفعيل المنفصل
part 'subscription_details_page.renewal.dart';

// نموذج لتخزين معلومات الاشتراك
class SubscriptionInfo {
  final String zoneId;
  final String zoneDisplayValue;
  final String fbg;
  final String bundleId;
  final String customerId;
  final String customerName;
  final String partnerId;
  final String partnerName;
  final String deviceUsername;
  final String currentPlan;
  final int commitmentPeriod;
  final String status;
  final List<Map<String, dynamic>> services;
  // معلومات إضافية جديدة
  final String? deviceSerial;
  final String? macAddress;
  final String? gpsLatitude;
  final String? gpsLongitude;
  final String? deviceModel;
  final String? subscriptionStartDate;
  final String? salesType;
  const SubscriptionInfo({
    required this.zoneId,
    required this.zoneDisplayValue,
    required this.fbg,
    required this.bundleId,
    required this.customerId,
    required this.customerName,
    required this.partnerId,
    required this.partnerName,
    required this.deviceUsername,
    required this.currentPlan,
    required this.commitmentPeriod,
    required this.status,
    required this.services,
    this.deviceSerial,
    this.macAddress,
    this.gpsLatitude,
    this.gpsLongitude,
    this.deviceModel,
    this.subscriptionStartDate,
    this.salesType,
  });

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    // Helpers
    String stringOf(dynamic v) => v?.toString() ?? '';
    Map<String, dynamic> asMap(dynamic v) =>
        (v is Map<String, dynamic>) ? v : <String, dynamic>{};
    List asList(dynamic v) => (v is List) ? v : const [];

    final zone = asMap(json['zone']);
    final partner = asMap(json['partner']);
    final customer = asMap(json['customer']);
    final device = asMap(json['deviceDetails']);
    final services = asList(json['services']).cast<Map<String, dynamic>>();

    // Determine current plan from services (Base)
    String currentPlan = '';
    try {
      final base = services.firstWhere(
        (s) =>
            stringOf(asMap(s['type'])['displayValue']).toLowerCase() == 'base',
        orElse: () => {},
      );
      if (base.isNotEmpty) {
        currentPlan = stringOf(base['displayValue']);
      }
    } catch (_) {}

    int commitmentPeriod = 0;
    final cp = json['commitmentPeriod'];
    if (cp is int) {
      commitmentPeriod = cp;
    } else if (cp is String) commitmentPeriod = int.tryParse(cp) ?? 0;

    String status = stringOf(json['status']);
    if (status.isEmpty && json['subscription'] is Map) {
      status = stringOf(json['subscription']['status']);
    }

    String salesType = '';
    final st = json['salesType'];
    if (st is Map && st['displayValue'] != null) {
      salesType = stringOf(st['displayValue']);
    } else {
      salesType = stringOf(st);
    }

    return SubscriptionInfo(
      zoneId: stringOf(
          zone['id'].toString().isNotEmpty ? zone['id'] : zone['displayValue']),
      zoneDisplayValue: stringOf(zone['displayValue']),
      fbg: stringOf(json['fbg']),
      bundleId: stringOf(json['bundleId']),
      customerId: stringOf(customer['id'] ?? customer['self']?['id']),
      customerName: stringOf(customer['displayValue'] ?? customer['name']),
      partnerId: stringOf(partner['id'] ?? partner['self']?['id']),
      partnerName: stringOf(partner['displayValue'] ?? partner['name']),
      deviceUsername: stringOf(device['username']),
      currentPlan: currentPlan,
      commitmentPeriod: commitmentPeriod,
      status: status,
      services: services.cast<Map<String, dynamic>>(),
      deviceSerial: stringOf(json['deviceSerial']).isEmpty
          ? null
          : stringOf(json['deviceSerial']),
      macAddress: stringOf(json['macAddress']).isEmpty
          ? null
          : stringOf(json['macAddress']),
      gpsLatitude: stringOf(json['gpsLatitude']).isEmpty
          ? null
          : stringOf(json['gpsLatitude']),
      gpsLongitude: stringOf(json['gpsLongitude']).isEmpty
          ? null
          : stringOf(json['gpsLongitude']),
      deviceModel: stringOf(json['deviceModel']).isEmpty
          ? null
          : stringOf(json['deviceModel']),
      subscriptionStartDate: stringOf(json['startedAt']).isEmpty
          ? null
          : stringOf(json['startedAt']),
      salesType: salesType.isEmpty ? null : salesType,
    );
  }

  static String _normalizePlanName(String name) {
    return name.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}

// واجهة تفاصيل الاشتراك
class SubscriptionDetailsPage extends StatefulWidget {
  final String userId;
  final String subscriptionId;
  final String authToken;
  final String activatedBy;
  final String? userName;
  final String? userPhone;
  final String? currentStatus;
  final String? currentBaseService;
  final String? deviceUsername;
  final int? remainingDays;
  final String? expires;
  final String? startedAt;
  final List<dynamic>? services;
  final String? fdtDisplayValue;
  final String? fatDisplayValue;
  final bool hasServerSavePermission;
  final bool hasWhatsAppPermission;
  // قائمة الصلاحيات المهمة المفلترة من نظام FTTH للوصول داخل التفاصيل
  final List<String>? importantFtthApiPermissions;
  // بيانات مبدئية اختيارية يتم تمريرها من صفحة المستخدم لتسريع فتح صفحة التفاصيل
  final Map<String, dynamic>? initialAllowedActions;
  final Map<String, dynamic>? initialBundles; // plans/bundles response
  final double? initialPartnerWalletBalance;
  final double? initialCustomerWalletBalance;

  // === معلومات إضافية للجهاز والعميل ===
  final String? deviceSerial; // الرقم التسلسلي للجهاز
  final String? macAddress; // عنوان MAC للجهاز
  final String? deviceModel; // موديل الجهاز
  final String? gpsLatitude; // خط العرض GPS
  final String? gpsLongitude; // خط الطول GPS
  final String? customerAddress; // عنوان العميل
  final Map<String, dynamic>? deviceOntInfo; // بيانات ONT كاملة
  final Map<String, dynamic>? customerDataMain; // بيانات العميل كاملة

  // === معلومات الشبكة ===
  final String? fbgValue; // قيمة FBG
  final String? fatValue; // قيمة FAT

  // === معلومات النظام الأول والصلاحيات ===
  final String? firstSystemPermissions; // صلاحيات النظام الأول
  final bool? isAdminFlag; // علامة المدير
  final String? firstSystemDepartment; // القسم
  final String? firstSystemCenter; // المركز
  final String? firstSystemSalary; // الراتب
  final Map<String, bool>? ftthPermissions; // صلاحيات FTTH المحلية
  final String? userRoleHeader; // رأس دور المستخدم
  final String? clientAppHeader; // معرف التطبيق

  const SubscriptionDetailsPage({
    super.key,
    required this.userId,
    required this.subscriptionId,
    required this.authToken,
    required this.activatedBy,
    this.userName,
    this.userPhone,
    this.currentStatus,
    this.currentBaseService,
    this.deviceUsername,
    this.remainingDays,
    this.expires,
    this.startedAt,
    this.services,
    this.fdtDisplayValue,
    this.fatDisplayValue,
    this.hasServerSavePermission = false,
    this.hasWhatsAppPermission = false,
    this.importantFtthApiPermissions,
    this.initialAllowedActions,
    this.initialBundles,
    this.initialPartnerWalletBalance,
    this.initialCustomerWalletBalance,
    // === المعاملات الإضافية الجديدة ===
    this.deviceSerial, // رقم تسلسلي الجهاز
    this.macAddress, // عنوان MAC
    this.deviceModel, // موديل الجهاز
    this.gpsLatitude, // إحداثي GPS X
    this.gpsLongitude, // إحداثي GPS Y
    this.customerAddress, // عنوان العميل
    this.deviceOntInfo, // بيانات ONT كاملة
    this.customerDataMain, // بيانات العميل كاملة
    // === معلومات الشبكة ===
    this.fbgValue, // قيمة FBG
    this.fatValue, // قيمة FAT
    // === معلومات النظام الأول ===
    this.firstSystemPermissions, // صلاحيات النظام الأول
    this.isAdminFlag, // هل هو مدير؟
    this.firstSystemDepartment, // القسم
    this.firstSystemCenter, // المركز
    this.firstSystemSalary, // الراتب
    this.ftthPermissions, // صلاحيات FTTH المحلية
    this.userRoleHeader, // رأس دور المستخدم
    this.clientAppHeader, // رأس التطبيق
  });

  @override
  State<SubscriptionDetailsPage> createState() =>
      _SubscriptionDetailsPageState();
}

class _SubscriptionDetailsPageState extends State<SubscriptionDetailsPage>
    with SingleTickerProviderStateMixin {
  // دالة مساعدة لـ setState يمكن استخدامها من الـ extensions
  void safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  final List<String> availablePlans = [
    "FIBER 35",
    "FIBER 50",
    "FIBER 75",
    "FIBER 150",
  ];

  // فترات الالتزام المتاحة (تمت إضافة 2 شهر بناءً على طلبك)
  final List<int> commitmentPeriods = [1, 2, 3, 6, 12];

  // إضافة قائمة طرق الدفع والمتغير الخاص بها
  final List<String> paymentMethods = ["نقد", "أجل", "ماستر", "وكيل", "فني"];
  String selectedPaymentMethod = "نقد"; // طريقة الدفع الافتراضية

  // الوكيل المختار (يظهر عند اختيار "وكيل")
  Map<String, dynamic>? _selectedLinkedAgent;
  List<Map<String, dynamic>> _agentsList = [];
  bool _isLoadingAgents = false;

  // الفني المختار (يظهر عند اختيار "فني")
  Map<String, dynamic>? _selectedLinkedTechnician;
  List<Map<String, dynamic>> _techniciansList = [];
  bool _isLoadingTechnicians = false;

  // أخطاء تحميل القوائم
  String? _agentsLoadError;
  String? _techniciansLoadError;
  // حالة حساب السعر لزر التمديد (Extend) بعد اختيار فترة الالتزام
  bool _isCalculatingExtendPrice = false; // لعرض لودر داخل زر التمديد
  String? _extendPriceError; // في حال فشل استرجاع السعر
  SubscriptionInfo? subscriptionInfo;
  bool isLoading = false;
  String errorMessage = "";
  double walletBalance = 0.0;
  // محفظة عضو الفريق (تُعرض بدلاً من المحفظة الأساسية إذا كانت مفعلة)
  double teamMemberWalletBalance = 0.0;
  bool hasTeamMemberWallet = false;
  // محفظة المشترك (العميل) الجديدة
  double customerWalletBalance = 0.0;
  bool hasCustomerWallet = false;
  // مصدر المحفظة المختار للدفع (main أو member)
  String _selectedWalletSource = 'main';
  // مؤقت داخلي لتأجيل الحساب التلقائي بعد اختيار الخطة أو الفترة
  Timer? _autoPriceTimer;
  // حالة خاصة برصيد المحفظة (مستقلة عن isLoading العام)
  bool isWalletLoading = false; // تحميل رصيد المحفظة فقط
  DateTime? walletLastUpdated; // آخر وقت تحديث ناجح
  String? walletError; // آخر خطأ في جلب الرصيد (صامت للمستخدم إلا في البطاقة)
  Map<String, dynamic>? priceDetails;
  // حالة خاصة بحساب السعر
  bool _priceAttempted = false; // هل حاولنا الحساب مرة على الأقل
  String?
      _priceError; // آخر خطأ في حساب السعر (لا يظهر إلا بعد انتهاء كل المحاولات)
  bool showBasePriceLowerThanWalletAlert =
      false; // تنبيه (مُصحَّح): السعر الأساسي أكبر من الرصيد المتاح (نقص رصيد)
  // مفتاح تفعيل خصم النظام (الحالة الافتراضية: مطفأ)
  bool systemDiscountEnabled = false;
  // أصبحت اختيارية ليتم التحقق من اختيار المستخدم قبل حساب السعر
  String? selectedPlan;
  int? selectedCommitmentPeriod;
  String? trialExpiredAt; // لحفظ تاريخ انتهاء الاشتراك التجريبي
  String? customerAddress; // عنوان المشترك (إن وُجد)
  double manualDiscount = 0.0; // خصم يدوي اختياري يطبّق على الإجمالي
  String subscriptionNotes = ''; // ملاحظات الاشتراك
  bool isNotesEnabled = true; // حالة زر تشغيل/إيقاف الملاحظات (افتراضي: مفعل)
  bool isDataSavedToServer =
      false; // لتتبع ما إذا كانت البيانات محفوظة في الخادم

  // قائمة الفنيين المحمّلة من TechniciansPage
  List<Map<String, String>> technicians = [];
  String? selectedTechnician; // الفني المختار
  final TextEditingController _notesController =
      TextEditingController(); // التحكم في مربع الملاحظات  // كلمة مرور حماية تعديل القالب
  String _templatePassword = '0770';

  // مانع تكرار إرسال الواتساب خلال نفس الحدث
  bool _isSendingWhatsApp = false; // لزر إرسال واتساب العادي
  bool _isSendingToTechnician = false; // لزر إرسال للفني
  bool _isSavedToSheets = false; // لتغيير لون زر تم التفعيل بعد الضغط والنجاح
  int?
      _vpsLogId; // معرف السجل المحفوظ في VPS لاستخدامه في تحديثات الطباعة/الواتساب
  // واتساب: رقم افتراضي محفوظ من نافذة "إعداد الواتساب"
  String? _defaultWhatsAppPhone;
  // رقم هاتف المشترك المجلوب من API
  String? _fetchedCustomerPhone;
  // رقم مخزن مؤقتًا لتجنب الاستدعاءات المتكررة
  String? _cachedCustomerPhone;
  bool _isGeneratingWhatsAppLink = false; // حالة انتظار توليد الرابط
  bool _useWhatsAppWeb =
      true; // استخدام واتساب الويب المفتوح بدلاً من الرابط (افتراضي)
  bool _autoSendWhatsApp = true; // الإرسال التلقائي للواتساب (TAB×16 + Enter)

  String paymentType = 'نقد'; // نقد = Cash, أجل = Deferred

  // معلومات إضافية للأعمدة AI إلى AL
  double partnerWalletBalanceBefore = 0.0; // AI - رصيد محفظة الشريك قبل العملية
  double customerWalletBalanceBefore =
      0.0; // AJ - رصيد محفظة العميل قبل العملية
  bool isPrinted = false; // AK - تم الطباعة عند الضغط على زر الطبع أم لا
  bool isWhatsAppSent =
      false; // AL - تم إرسال الواتساب عند الضغط على زر الإرسال أم لا

  // حالة انتظار للعمليات المختلفة
  bool _isPrinting = false; // حالة انتظار الطباعة

  // معرف فريد لجلسة العمل الحالية (لضمان التحديث على نفس العملية)
  late String sessionId;

  // متغير للتحكم بإظهار زر التجديد (مخفي حالياً حسب طلب المستخدم)
  // تفعيل إظهار زر التجديد افتراضياً الآن
  bool showRenewButton = true;
  // تخزين allowed-actions القادم مسبقاً (إن وُجد)
  Map<String, dynamic>? _prefetchedAllowedActions;
  // ارتفاع موحد لبطاقتي السعر الإجمالي ورصيد المحفظة (وضع العرض المضغوط)
  static const double _priceWalletCardsHeight =
      90; // يمكن تعديل الرقم لاحقاً إذا لزم
  // مدة التأخير بعد إرسال رسالة الواتساب قبل إعادة التركيز (أقل من ثانية)
  static const int _postSendFocusDelayMs = 350; // يمكن تعديلها إذا احتجت
  // تأخير إضافي بعد الإرسال التلقائي (تسلسل TAB ثم Enter) لضمان عودة المؤشر بعد انتهاء الأتمتة
  static const int _postAutoSendFocusDelayMs =
      1200; // تقريباً 16 TAB × ~50ms + هامش

  // إرجاع خطوة واحدة فقط (SHIFT+TAB واحد)
  void _shiftTabBackOnce() {
    if (!mounted) return;
    try {
      FocusScope.of(context).previousFocus();
    } catch (_) {}
  }

  // تحديد نوع العملية حسب الحالة الحالية
  // القيم المسموحة من API: PurchaseFromTrial, ImmediateExtend, ImmediateChange, Renew
  String _determinePlanOperationType() {
    if (isNewSubscription) return 'PurchaseFromTrial';
    if (subscriptionInfo != null &&
        selectedPlan == subscriptionInfo!.currentPlan &&
        selectedCommitmentPeriod == subscriptionInfo!.commitmentPeriod) {
      // نفس الخطة ونفس المدة = تمديد فوري
      return 'ImmediateExtend';
    }
    // تغيير الخطة أو المدة = تغيير فوري
    return 'ImmediateChange';
  }

  /// الحصول على نوع العملية لـ calculate-price API (يستخدم قيم مختصرة)
  /// calculate-price يستخدم: Extend, Change, PurchaseFromTrial
  String _getCalcPriceOperationType() {
    if (isNewSubscription) return 'PurchaseFromTrial';
    if (subscriptionInfo != null &&
        selectedPlan == subscriptionInfo!.currentPlan &&
        selectedCommitmentPeriod == subscriptionInfo!.commitmentPeriod) {
      return 'Extend'; // calculate-price يستخدم Extend وليس ImmediateExtend
    }
    return 'Change'; // calculate-price يستخدم Change وليس ImmediateChange
  }

  /// الحصول على رقم ID لنوع العملية من allowed-actions API
  /// ImmediateChange=2, ScheduledChange=1, ScheduledExtend=4, ImmediateExtend=5, Renew=9
  int _getPlanOperationTypeId(String opType) {
    switch (opType) {
      case 'ScheduledChange':
        return 1;
      case 'ImmediateChange':
        return 2;
      case 'ScheduledExtend':
        return 4;
      case 'ImmediateExtend':
        return 5;
      case 'Renew':
        return 9;
      case 'PurchaseFromTrial':
        return 8; // افتراضي للشراء من تجريبي
      default:
        return 5; // ImmediateExtend كقيمة افتراضية
    }
  }

  // Formatter for numbers
  String _formatNumber(num value) => value.round().toString();

  bool get isNewSubscription {
    return widget.subscriptionId.startsWith('T');
  }

  // هل تم تعديل الخطة أو مدة الالتزام عن القيم الحالية للاشتراك؟
  bool get isModification {
    if (subscriptionInfo == null) return false;
    if (isNewSubscription) return false; // التغيير لا ينطبق على اشتراك جديد
    final differentPlan = selectedPlan != null &&
        subscriptionInfo!.currentPlan.isNotEmpty &&
        selectedPlan != subscriptionInfo!.currentPlan;
    final differentPeriod = selectedCommitmentPeriod != null &&
        selectedCommitmentPeriod != subscriptionInfo!.commitmentPeriod;
    return differentPlan || differentPeriod;
  }

  // التحقق من امتلاك صلاحية إنشاء أو تجديد اشتراك
  bool get _canCreateOrRenew {
    final perms = widget.importantFtthApiPermissions ?? const [];
    if (perms.isEmpty) return false;
    return perms.map((p) => p.toLowerCase()).any((p) =>
        // الإنجليزية الأصلية
        p.contains('create subscription') ||
        p.contains('renew subscription') ||
        // العربية بعد الترجمة
        p.contains('إنشاء') ||
        p.contains('تجديد'));
  }

  // متحكم التمرير للصفحة لعرض شريط تمرير دائم وزر للانتقال للأسفل
  final ScrollController _contentScrollController = ScrollController();
  bool _isAtBottom = false; // لمعرفة إن كنا في الأسفل لتبديل أيقونة الزر

  /// تحويل salesType من النص إلى القيمة الرقمية المطلوبة للـ API
  int _getSalesTypeValue() {
    debugPrint('🔄 تحديد salesType...');
    debugPrint('📊 salesType من API: ${subscriptionInfo?.salesType}');
    debugPrint('🛒 selectedPaymentMethod المحلي: $selectedPaymentMethod');

    // إذا كان لدينا salesType من API، استخدمه
    if (subscriptionInfo?.salesType != null) {
      switch (subscriptionInfo!.salesType!.toLowerCase()) {
        case 'نقد':
        case 'cash':
        case 'upfront': // إضافة Upfront = نقد مقدم
          debugPrint('✅ استخدام salesType من API: 0 (نقد/Upfront)');
          return 0;
        case 'أجل':
        case 'deferred':
        case 'credit':
        case 'postpaid': // إضافة Postpaid = آجل
          debugPrint('✅ استخدام salesType من API: 1 (أجل)');
          return 1;
        default:
          // إذا لم نجد قيمة مطابقة، استخدم القيمة المحلية كبديل
          final localValue = selectedPaymentMethod == 'أجل' ? 1 : 0;
          debugPrint(
              '⚠️ قيمة salesType غير مطابقة (${subscriptionInfo!.salesType}), استخدام القيمة المحلية: $localValue');
          return localValue;
      }
    }
    // إذا لم يكن لدينا salesType من API، استخدم القيمة المحلية
    // نقد/ماستر/وكيل = 0 (دفع فوري)، أجل = 1
    final localValue = selectedPaymentMethod == 'أجل' ? 1 : 0;
    debugPrint(
        '⚠️ لا يوجد salesType من API، استخدام القيمة المحلية: $localValue');
    return localValue;
  }

  @override
  void initState() {
    super.initState();

    // تحميل الإعدادات المحفوظة محلياً
    _loadWhatsAppSettings();

    // تحميل قائمة الفنيين
    _loadTechnicians();

    // تحميل مسبق لقوائم الوكلاء والفنيين (بصمت في الخلفية)
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _loadAgentsList();
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _loadTechniciansList();
    });

    // أنيميشن خلفية بسيط (تغيير تدريجي للألوان) لمنح الصفحة حيوية بدون التأثير على الحجم
    _bgAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();

    // إظهار الزر العائم لواتساب عند بدء التطبيق
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          WhatsAppBottomWindow.showFloatingButton(context);
        } catch (e) {
          debugPrint('⚠️ Error showing initial FAB: $e');
        }
      }
    });

    // إنشاء معرف فريد لجلسة العمل الحالية
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    sessionId =
        'session_${currentTime}_${widget.userId}_${widget.subscriptionId}';
    debugPrint('🆔 Session ID created at time $currentTime: $sessionId');

    // طباعة معلومات debugging
    debugPrint('🚀 تهيئة صفحة تفاصيل الاشتراك');
    debugPrint('👤 User ID: ${widget.userId}');
    debugPrint('🆔 Subscription ID: ${widget.subscriptionId}');
    debugPrint('🔑 Auth Token: ${widget.authToken.substring(0, 20)}...');
    debugPrint('👨‍💼 Activated By: ${widget.activatedBy}');
    debugPrint('🆕 Is New Subscription: $isNewSubscription');
    if (widget.importantFtthApiPermissions != null) {
      debugPrint(
          '🔐 Important FTTH perms (passed): ${widget.importantFtthApiPermissions}');
    }

    // طباعة المعلومات الإضافية المُمررة
    if (widget.userName != null) {
      debugPrint('👤 اسم المستخدم: ${widget.userName}');
    }
    if (widget.userPhone != null) {
      debugPrint('📱 رقم الهاتف: ${widget.userPhone}');
    }
    if (widget.currentStatus != null) {
      debugPrint('📊 الحالة الحالية: ${widget.currentStatus}');
    }
    if (widget.currentBaseService != null) {
      debugPrint('🌐 الخدمة الأساسية: ${widget.currentBaseService}');
    }
    if (widget.deviceUsername != null) {
      debugPrint('💻 اسم المستخدم للجهاز: ${widget.deviceUsername}');
    }
    if (widget.remainingDays != null) {
      debugPrint('📅 الأيام المتبقية: ${widget.remainingDays}');
    }
    if (widget.expires != null) {
      debugPrint('⏰ تاريخ انتهاء الاشتراك: ${widget.expires}');
    }
    if (widget.startedAt != null) {
      debugPrint('🚀 تاريخ بدء الاشتراك: ${widget.startedAt}');
    }
    if (widget.services != null) {
      debugPrint('🛠️ عدد الخدمات المُمررة: ${widget.services?.length}');
    }
    if (widget.fdtDisplayValue != null) {
      debugPrint('📡 FDT: ${widget.fdtDisplayValue}');
    }
    if (widget.fatDisplayValue != null) {
      debugPrint('📡 FAT: ${widget.fatDisplayValue}');
    }

    // طباعة المعلومات الإضافية الجديدة
    debugPrint('📋 === المعلومات الإضافية المستلمة ===');
    if (widget.deviceSerial != null) {
      debugPrint('🔧 Device Serial: ${widget.deviceSerial}');
    }
    if (widget.macAddress != null) {
      debugPrint('🌐 MAC Address: ${widget.macAddress}');
    }
    if (widget.deviceModel != null) {
      debugPrint('📱 Device Model: ${widget.deviceModel}');
    }
    if (widget.gpsLatitude != null && widget.gpsLongitude != null) {
      debugPrint(
          '🌍 GPS Location: ${widget.gpsLatitude}, ${widget.gpsLongitude}');
    }
    if (widget.customerAddress != null) {
      debugPrint('🏠 Customer Address: ${widget.customerAddress}');
    }
    debugPrint('📊 Device ONT Info Available: ${widget.deviceOntInfo != null}');
    debugPrint(
        '👤 Customer Data Available: ${widget.customerDataMain != null}');
    if (widget.firstSystemPermissions != null) {
      debugPrint(
          '🔐 First System Permissions: ${widget.firstSystemPermissions}');
    }
    if (widget.isAdminFlag != null) {
      debugPrint('👨‍💼 Admin Flag: ${widget.isAdminFlag}');
    }
    if (widget.firstSystemDepartment != null) {
      debugPrint('🏢 Department: ${widget.firstSystemDepartment}');
    }
    if (widget.firstSystemCenter != null) {
      debugPrint('🏢 Center: ${widget.firstSystemCenter}');
    }
    if (widget.firstSystemSalary != null) {
      debugPrint('💰 Salary: ${widget.firstSystemSalary}');
    }
    debugPrint(
        '✅ FTTH Permissions Available: ${widget.ftthPermissions != null}');
    if (widget.userRoleHeader != null) {
      debugPrint('👤 User Role Header: ${widget.userRoleHeader}');
    }
    if (widget.clientAppHeader != null) {
      debugPrint('📱 Client App Header: ${widget.clientAppHeader}');
    }
    // إضافة طباعة معلومات الشبكة
    debugPrint('🌐 === معلومات الشبكة ===');
    debugPrint('🔗 FBG Value: ${widget.fbgValue}');
    debugPrint('🔗 FAT Value: ${widget.fatValue}');
    debugPrint('🔗 FDT Display: ${widget.fdtDisplayValue}');
    debugPrint('🔗 FAT Display: ${widget.fatDisplayValue}');
    debugPrint('=========================================');

    // تعيين القيم الافتراضية قبل جلب البيانات
    if (isNewSubscription) {
      // للاشتراكات الجديدة، نترك القيم فارغة حتى يختار المستخدم بنفسه
      selectedCommitmentPeriod = null;
      selectedPlan = null;
    }
    fetchSubscriptionDetails();
    _loadWhatsAppTemplate();
    _loadTemplatePassword();
    _loadDefaultWhatsAppPhone();
    _fetchCustomerPhone(); // جلب رقم هاتف المشترك من API

    // مراقبة التمرير لتحديث حالة الوصول لأسفل الصفحة
    _contentScrollController.addListener(() {
      if (!_contentScrollController.hasClients) return;
      final position = _contentScrollController.position;
      final atBottom = position.pixels >= (position.maxScrollExtent - 50);
      if (atBottom != _isAtBottom) {
        setState(() => _isAtBottom = atBottom);
      }
    });
    // الاستفادة من البيانات المسبقة إن وجدت (أرصدة ومحاولات السماح)
    if (widget.initialPartnerWalletBalance != null) {
      walletBalance = widget.initialPartnerWalletBalance!;
    }
    if (widget.initialCustomerWalletBalance != null) {
      customerWalletBalance = widget.initialCustomerWalletBalance!;
      hasCustomerWallet = true;
    }
    if (widget.initialAllowedActions != null) {
      _prefetchedAllowedActions = widget.initialAllowedActions;
    }
    // initialBundles مبدئياً غير مستخدمة هنا (قد تستغل لاحقاً لحساب السعر بسرعة)
  }

  Future<void> _loadDefaultWhatsAppPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString('default_whatsapp_phone');
      if (v != null && v.trim().isNotEmpty) {
        setState(() => _defaultWhatsAppPhone = v.trim());
      }
    } catch (_) {}
  }

  Future<void> _saveDefaultWhatsAppPhone(String phone) async {
    final clean = phone.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_whatsapp_phone', clean);
    setState(() => _defaultWhatsAppPhone = clean);
  }

  // تحميل إعدادات الواتساب المحفوظة محلياً
  Future<void> _loadWhatsAppSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final useWebSaved =
          prefs.getBool('whatsapp_use_web') ?? true; // افتراضي: فعال
      // استخدام الإعداد من الصفحة الرئيسية
      final autoSendSaved = await HomePage.getWhatsAppAutoSendSetting();
      setState(() {
        _useWhatsAppWeb = useWebSaved;
        _autoSendWhatsApp = autoSendSaved;
      });
      debugPrint(
          '📱 تم تحميل إعدادات الواتساب: استخدام الويب = $_useWhatsAppWeb, إرسال تلقائي = $_autoSendWhatsApp');
    } catch (e) {
      debugPrint('❌ خطأ في تحميل إعدادات الواتساب: $e');
    }
  }

  // حفظ إعدادات الواتساب محلياً (بدون الإرسال التلقائي - يُدار من الصفحة الرئيسية)
  Future<void> _saveWhatsAppSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('whatsapp_use_web', _useWhatsAppWeb);
      // ملاحظة: إعداد الإرسال التلقائي يُدار من الصفحة الرئيسية فقط
      debugPrint(
          '💾 تم حفظ إعدادات الواتساب: استخدام الويب = $_useWhatsAppWeb');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ إعدادات الواتساب: $e');
    }
  }

  // فتح شاشة ويب لعرض QR تسجيل الدخول لواتساب ويب
  void _openWhatsAppWebLogin() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const WhatsAppWebLoginPage()),
    );

    // إعادة تحديث الصفحة بعد العودة
    if (mounted && result == true) {
      ftthShowSuccessNotification(context, 'تم تسجيل الدخول بنجاح');
    }
  }

  // توليد رسالة للاشتراك الحالي باستخدام القالب المحفوظ أو رسالة بسيطة كبديل
  String _buildSimpleWhatsAppMessage() {
    // استخدام القالب المحفوظ إن وُجد، وإلا استخدام رسالة بسيطة
    if (_whatsAppTemplate.isNotEmpty &&
        subscriptionInfo != null &&
        priceDetails != null) {
      return _generateWhatsAppMessageWithTemplate(_whatsAppTemplate);
    }

    // رسالة بسيطة كبديل
    final b = StringBuffer();
    b.writeln('تفاصيل الاشتراك');
    if (subscriptionInfo != null) {
      b.writeln('العميل: ${subscriptionInfo!.customerName}');
      // عرض رقم الهاتف حسب الأولوية: widget.userPhone ثم _fetchedCustomerPhone
      final phoneToDisplay = widget.userPhone ?? _fetchedCustomerPhone;
      if (phoneToDisplay != null) b.writeln('هاتف: $phoneToDisplay');
      b.writeln('الخطة: ${selectedPlan ?? subscriptionInfo!.currentPlan}');
      if (selectedCommitmentPeriod != null) {
        b.writeln('المدة: $selectedCommitmentPeriod شهر');
      }
      if (priceDetails != null) {
        final total = _asDouble(priceDetails!['totalPrice']).round();
        b.writeln('السعر: $total IQD');
      }
      if (widget.expires != null) {
        b.writeln('انتهاء: ${widget.expires!.split('T').first}');
      }
      b.writeln('مُفعل بواسطة: ${widget.activatedBy}');
    }
    return b.toString().trim();
  }

  // استرجاع رقم المرسل إليه (أولوية: الرقم المجلوب من API – ثم رقم المستخدم – ثم الرقم الافتراضي المخزن)
  String? _resolveTargetPhone() {
    // الأولوية الأولى: رقم الهاتف المجلوب من API
    if (_fetchedCustomerPhone != null &&
        _fetchedCustomerPhone!.trim().isNotEmpty) {
      return _fetchedCustomerPhone!.trim();
    }
    // الأولوية الثانية: رقم المستخدم المُمرر من الصفحة السابقة (احتياطي)
    if (widget.userPhone != null && widget.userPhone!.trim().isNotEmpty) {
      return widget.userPhone!.trim();
    }
    // الأولوية الثالثة: الرقم الافتراضي المخزن محلياً
    return _defaultWhatsAppPhone;
  }

  // التحقق من صحة رقم الهاتف وتنسيقه
  String? _validateAndFormatPhone(String phone) {
    // إزالة كل شيء عدا الأرقام
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');

    debugPrint('🔍 رقم أصلي: $phone');
    debugPrint('🔍 رقم منظف: $cleanPhone');

    // التحقق من طول الرقم
    if (cleanPhone.length < 8) {
      debugPrint('❌ رقم قصير جداً: ${cleanPhone.length}');
      return null;
    }

    // إضافة رمز العراق إذا لم يكن موجوداً
    if (!cleanPhone.startsWith('964')) {
      final iraqPhone = '964$cleanPhone';
      debugPrint('✅ رقم مع رمز العراق: $iraqPhone');
      return iraqPhone;
    }

    debugPrint('✅ رقم صالح: $cleanPhone');
    return cleanPhone;
  }

  // التحقق من أن الرقم مسجل في واتساب (تم تعطيله - يسمح دائماً بالإرسال)
  Future<bool> _checkWhatsAppNumberExists(String phone) async {
    // بما أن السيرفر غير متوفر، نسمح دائماً بالإرسال
    debugPrint('📱 تخطي فحص رقم واتساب: $phone (السيرفر غير متوفر)');
    return true;
  }

  /// إرسال مباشر لواتساب الويب الداخلي
  Future<void> _sendToWhatsAppWeb() async {
    try {
      setState(() => _isGeneratingWhatsAppLink = true);

      final phone = _resolveTargetPhone();
      if (phone == null) {
        ftthShowErrorNotification(
            context, 'يجب تحديد رقم في إعدادات الواتساب أولاً');
        return;
      }

      final message = _buildSimpleWhatsAppMessage();
      final cleanPhone = _validateAndFormatPhone(phone);

      if (cleanPhone == null) {
        ftthShowErrorNotification(
            context, 'رقم الهاتف غير صحيح - تحقق من إعدادات الواتساب');
        return;
      }

      // فحص صحة الرقم على واتساب قبل المتابعة
      final exists = await _checkWhatsAppNumberExists(cleanPhone);
      if (!exists) {
        ftthShowErrorNotification(
            context, 'هذا الرقم غير مسجل في واتساب – تم إلغاء الإرسال');
        return;
      }

      debugPrint(
          '📱 إرسال واتساب ويب: رقم=$cleanPhone, طول الرسالة=${message.length}');

      // التحقق من وجود نافذة سفلى مفتوحة وإرسال رسالة إليها
      if (WhatsAppBottomWindow.sendMessageToBottomWindow(cleanPhone, message,
          autoSend: _autoSendWhatsApp)) {
        final autoSendMsg = _autoSendWhatsApp ? 'مع الإرسال التلقائي' : '';
        ftthShowSuccessNotification(
            context, 'تم إرسال الرسالة للنافذة المفتوحة $autoSendMsg');
        // محاولة إرجاع التركيز (SHIFT+TAB) بعدة محاولات (فورية + مؤجلة)
        _shiftTabBackOnce();
        if (_autoSendWhatsApp) {
          // محاولات إضافية بعد الإرسال التلقائي الطويل
          Future.delayed(
              const Duration(milliseconds: _postAutoSendFocusDelayMs), () {
            if (!mounted) return;
            _shiftTabBackOnce();
          });
        }
        return;
      }

      // إنشاء نافذة واتساب في أسفل الشاشة
      WhatsAppBottomWindow.showBottomWindow(context, cleanPhone, message,
          autoSend: _autoSendWhatsApp);

      final autoSendMsg = _autoSendWhatsApp ? 'مع الإرسال التلقائي' : 'عادية';
      ftthShowSuccessNotification(context, 'تم فتح نافذة واتساب $autoSendMsg');
      // تشغيل تسلسل إرجاع التركيز
      _shiftTabBackOnce();
      if (_autoSendWhatsApp) {
        Future.delayed(const Duration(milliseconds: _postAutoSendFocusDelayMs),
            () {
          if (!mounted) return;
          _shiftTabBackOnce();
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء نافذة واتساب: $e');
      ftthShowErrorNotification(context, 'خطأ: ${e.toString()}');
    } finally {
      setState(() => _isGeneratingWhatsAppLink = false);
    }
  }

  void _openWhatsAppSettingsDialog() async {
    final controller = TextEditingController(text: _defaultWhatsAppPhone ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعداد الواتساب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'رقم العميل (مع رمز الدولة بدون +)',
                hintText: 'مثال: 9647XXXXXXXXX',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _openWhatsAppWebLogin();
                    },
                    icon: const Icon(Icons.qr_code),
                    label: const Text('فتح QR'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('واتساب ويب داخلي',
                        style: TextStyle(fontSize: 13)),
                    subtitle: const Text(
                        'إرسال عبر نافذة واتساب ويب داخل التطبيق',
                        style: TextStyle(fontSize: 11)),
                    value: _useWhatsAppWeb,
                    onChanged: (v) {
                      setState(() => _useWhatsAppWeb = v);
                      _saveWhatsAppSettings();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('الإرسال التلقائي',
                        style: TextStyle(fontSize: 13)),
                    subtitle: const Text(
                        'يُدار من إعدادات الواتساب في القائمة الجانبية',
                        style: TextStyle(fontSize: 11)),
                    value: _autoSendWhatsApp,
                    onChanged: null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isGeneratingWhatsAppLink
                        ? null
                        : () async {
                            final val = controller.text.trim();
                            if (val.isEmpty) {
                              ftthShowErrorNotification(
                                  context, 'ادخل الرقم أولاً');
                              return;
                            }
                            if (_isGeneratingWhatsAppLink) return;
                            setState(() => _isGeneratingWhatsAppLink = true);
                            try {
                              // استخدام رابط wa.me المباشر
                              final msg = Uri.encodeComponent(
                                  _buildSimpleWhatsAppMessage());
                              final url = 'https://wa.me/$val?text=$msg';
                              await launchUrl(Uri.parse(url),
                                  mode: LaunchMode.externalApplication);
                            } catch (e) {
                              if (mounted) {
                                ftthShowErrorNotification(context, 'خطأ: $e');
                              }
                            } finally {
                              if (mounted) {
                                setState(
                                    () => _isGeneratingWhatsAppLink = false);
                              }
                            }
                          },
                    icon: _isGeneratingWhatsAppLink
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chat_outlined),
                    label: const Text('إرسال تجريبي'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final val = controller.text.trim();
              if (val.isEmpty) {
                ftthShowErrorNotification(context, 'الرقم فارغ');
                return;
              }
              await _saveDefaultWhatsAppPhone(val);
              if (mounted) {
                Navigator.of(ctx).pop();
                ftthShowSuccessNotification(context, 'تم الحفظ');
              }
            },
            icon: const Icon(Icons.save),
            label: const Text('حفظ'),
          )
        ],
      ),
    );
  }

  // متحكم أنيميشن الخلفية
  late final AnimationController _bgAnim;

  @override
  void dispose() {
    _bgAnim.dispose();
    _autoPriceTimer?.cancel();
    _contentScrollController.dispose();
    _notesController.dispose(); // إضافة dispose للـ controller
    super.dispose();
  }

  // أداة صغيرة لعمل حركة ظهور ناعمة للعناصر (انزلاق + تلاشي)
  Widget _animated(int index, Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Transform.translate(
        offset: Offset(0, (1 - v) * 14),
        child: Opacity(opacity: v.clamp(0, 1), child: child),
      ),
    );
  }

  // حساب تلقائي للسعر عند توفر الخطة والفترة (لإظهار التفاصيل مباشرة عند فتح الصفحة)
  void _autoComputePriceIfPossible() {
    // نحاول الحساب حتى أثناء التحميل العام طالما توفرت البيانات المطلوبة
    if (!_walletsFetched) return; // ننتظر الأرصدة أولاً
    if (priceDetails != null) return; // تم الحساب مسبقاً
    if (selectedPlan != null && selectedCommitmentPeriod != null) {
      // إطلاق الحساب بدون انتظار المستخدم — مع catchError لمنع توقف التطبيق
      fetchPriceDetails().catchError((e) {
        debugPrint('⚠️ _autoComputePriceIfPossible error: $e');
      });
    }
  }

  bool _walletsFetched = false; // هل تم جلب كل الأرصدة المطلوبة؟

  Future<void> _loadWalletsThenPrice() async {
    try {
      await fetchWalletBalance();
      await fetchCustomerWalletBalance();
    } catch (_) {
      // تجاهل، سيتم عرض ما توفر
    }
    _walletsFetched = true;
    await _autoSelectPlanAndPeriodIfNeeded();
    _autoComputePriceIfPossible();
  }

  // اختيار تلقائي للخطة والفترة في حال اشتراك تجريبي ولم يختر المستخدم شيئاً
  Future<void> _autoSelectPlanAndPeriodIfNeeded() async {
    if (!isNewSubscription) return; // فقط للاشتراك التجريبي/الجديد
    bool changed = false;
    // اختيار الخطة إن كانت فارغة
    if (selectedPlan == null || selectedPlan!.trim().isEmpty) {
      // نحاول استخدام الخطة الحالية من البيانات، وإلا أول خطة متاحة
      if (subscriptionInfo != null &&
          subscriptionInfo!.currentPlan.trim().isNotEmpty) {
        selectedPlan = subscriptionInfo!.currentPlan;
      } else {
        selectedPlan = availablePlans.isNotEmpty ? availablePlans.first : null;
      }
      _validateSelectedPlan();
      changed = true;
    }
    // إذا لم نحدد مدة التزام أو المدة الحالية غير مناسبة، نجلب الفترات المتاحة من bundles
    if (selectedCommitmentPeriod == null) {
      final period = await _fetchFirstAvailablePeriodForSelectedPlan();
      selectedCommitmentPeriod = period ??
          (commitmentPeriods.isNotEmpty ? commitmentPeriods.first : 1);
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  // جلب أول فترة التزام متاحة فعلياً من واجهة bundles للخطة المحددة
  Future<int?> _fetchFirstAvailablePeriodForSelectedPlan() async {
    try {
      if (selectedPlan == null) return null;
      final resp = await http.get(
        Uri.parse(
            'https://admin.ftth.iq/api/plans/bundles?includePrices=true&subscriptionId=${widget.subscriptionId}'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      final items = data['items'] as List?;
      if (items == null || items.isEmpty) return null;
      Map<String, dynamic>? matchingBundle;
      String norm(String? v) =>
          (v ?? '').toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      final sel = norm(selectedPlan);
      for (final b in items) {
        final services = b['services'] as List?;
        if (services == null) continue;
        for (final s in services) {
          final st = s['type'];
          final isBase = st == 'Base' ||
              (st is Map &&
                  (st['displayValue']?.toString().toLowerCase() == 'base'));
          if (!isBase) continue;
          if (norm(s['id']?.toString()) == sel ||
              norm(s['displayValue']?.toString()) == sel) {
            matchingBundle = b;
            break;
          }
        }
        if (matchingBundle != null) break;
      }
      matchingBundle ??= items.first;
      final prices = matchingBundle?['prices'] as Map<String, dynamic>?;
      if (prices == null || prices.isEmpty) return null;
      final periods = prices.keys
          .map((k) => int.tryParse(k.toString()))
          .whereType<int>()
          .toList()
        ..sort();
      if (periods.isEmpty) return null;
      // نفضل شهر واحد إن وجد، وإلا أول قيمة
      if (periods.contains(1)) return 1;
      return periods.first;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadTemplatePassword() async {
    final saved = await TemplatePasswordStorage.loadPassword();
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        _templatePassword = saved;
      });
    }
  }

  /// تحميل قائمة الفنيين من SharedPreferences
  Future<void> _loadTechnicians() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('local_technicians_list');
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          setState(() {
            technicians = decoded
                .whereType<Map>()
                .map((e) => {
                      'name': (e['name'] ?? '').toString(),
                      'phone': (e['phone'] ?? '').toString(),
                    })
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint('خطأ في تحميل قائمة الفنيين: $e');
    }
  }

  // تحميل عنوان المشترك من API وعرضه
  Future<void> _loadCustomerAddress() async {
    try {
      final details = await fetchCustomerDetails(widget.userId);
      String? addr;
      if (details != null) {
        final addresses = details['addresses'];
        if (addresses is List && addresses.isNotEmpty) {
          final first = addresses.first;
          addr = (first is Map
                  ? first['displayValue']?.toString()
                  : first?.toString()) ??
              '';
        }
      }
      if (mounted) {
        setState(() {
          customerAddress =
              (addr != null && addr.trim().isNotEmpty) ? addr : null;
        });
      }
    } catch (_) {
      // تجاهل الأخطاء هنا لتجنب إزعاج المستخدم، يكفي عدم إظهار العنوان
    }
  }

  Future<void> _loadWhatsAppTemplate() async {
    final saved = await WhatsAppTemplateStorage.loadTemplate();
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        _whatsAppTemplate = saved;
      });
    }
  }

  /// جلب رقم هاتف المشترك من API
  Future<void> _fetchCustomerPhone() async {
    try {
      debugPrint('📞 ========== بدء جلب رقم هاتف المشترك ==========');
      debugPrint('👤 User ID: ${widget.userId}');
      debugPrint(
          '🔗 URL: https://admin.ftth.iq/api/customers/${widget.userId}');

      final response = await http.get(
        Uri.parse('https://admin.ftth.iq/api/customers/${widget.userId}'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('📡 Response Status Code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint(
            '📦 Response Data: ${data.toString().substring(0, data.toString().length > 200 ? 200 : data.toString().length)}...');

        final model = data['model'];
        debugPrint('🔍 Model exists: ${model != null}');

        if (model != null) {
          final primaryContact = model['primaryContact'];
          debugPrint('🔍 Primary Contact exists: ${primaryContact != null}');

          if (primaryContact != null) {
            final mobile = primaryContact['mobile'];
            debugPrint('🔍 Mobile exists: ${mobile != null}');
            debugPrint('📱 Mobile value: $mobile');

            final phone = mobile?.toString();
            if (phone != null && phone.isNotEmpty) {
              setState(() {
                _fetchedCustomerPhone = phone.trim();
                _cachedCustomerPhone = phone.trim(); // تحديث الذاكرة المؤقتة
              });
              debugPrint(
                  '✅ ========== تم جلب رقم الهاتف بنجاح: $_fetchedCustomerPhone ==========');
            } else {
              debugPrint('⚠️ رقم الهاتف فارغ أو null');
            }
          } else {
            debugPrint('⚠️ primaryContact غير موجود في model');
          }
        } else {
          debugPrint('⚠️ model غير موجود في الاستجابة');
        }
      } else {
        debugPrint(
            '❌ فشل جلب رقم الهاتف - Status Code: ${response.statusCode}');
        debugPrint('📄 Response Body: ${response.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ خطأ في جلب رقم الهاتف: $e');
      debugPrint('📚 Stack Trace: $stackTrace');
      // لا نعرض خطأ للمستخدم، فقط نسجل في console
    }
  }

  /// جلب تفاصيل الاشتراك من API
  Future<void> fetchSubscriptionDetails() async {
    debugPrint('🔄 بدء جلب تفاصيل الاشتراك...');
    debugPrint('📍 User ID: ${widget.userId}');
    debugPrint('🆔 Subscription ID: ${widget.subscriptionId}');
    debugPrint('🆕 Is New Subscription: $isNewSubscription');

    setState(() {
      isLoading = true;
      errorMessage = "";
    });

    try {
      // إذا كان اشتراك جديد (يبدأ بـ T)، نحاول جلب البيانات بطريقة مختلفة
      if (isNewSubscription) {
        // للاشتراكات التجريبية الجديدة، نحاول جلب البيانات مباشرة
        await _fetchTrialSubscriptionDetails();
      } else {
        // للاشتراكات العادية، نستخدم customerId
        final response = await http.get(
          Uri.parse(
              'https://api.ftth.iq/api/customers/subscriptions?customerId=${widget.userId}'),
          headers: {
            'Authorization': 'Bearer ${widget.authToken}',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['items'] != null && data['items'].isNotEmpty) {
            // البحث عن الاشتراك المطابق للـ subscriptionId
            final matchingSubscription = (data['items'] as List).firstWhere(
              (item) => item['self']['id'] == widget.subscriptionId,
              orElse: () => data['items'][0], // إذا لم نجد مطابق، نأخذ الأول
            );
            subscriptionInfo = SubscriptionInfo.fromJson(matchingSubscription);
            debugPrint('📊 Sales Type من API: ${subscriptionInfo!.salesType}');
            setState(() {
              selectedPlan = subscriptionInfo!.currentPlan;
              _validateSelectedPlan(); // التأكد من صحة الخطة المحددة
              selectedCommitmentPeriod = subscriptionInfo!.commitmentPeriod;
            });
            // تحميل عنوان المشترك أولاً ثم جلب الأرصدة ثم الحساب
            await _loadCustomerAddress();
            await _loadWalletsThenPrice();
          } else {
            throw Exception('لم يتم العثور على اشتراكات لهذا المستخدم');
          }
        } else {
          throw Exception('فشل جلب تفاصيل الاشتراك: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = "حدث خطأ أثناء جلب تفاصيل الاشتراك: $e";
        _priceError = 'فشل جلب بيانات الاشتراك: $e';
        _priceAttempted = true;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  /// جلب تفاصيل الاشتراك التجريبي
  Future<void> _fetchTrialSubscriptionDetails() async {
    try {
      debugPrint('🔍 جلب بيانات الاشتراك التجريبي من API الخاص...');
      debugPrint(
          '🔗 URL: https://admin.ftth.iq/api/subscriptions/trial/${widget.subscriptionId}');

      // جلب بيانات الاشتراك التجريبي من API الخاص
      final response = await http.get(
        Uri.parse(
            'https://admin.ftth.iq/api/subscriptions/trial/${widget.subscriptionId}'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('📥 Response Status: ${response.statusCode}');
      debugPrint('📥 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final model = data['model'];

        if (model != null) {
          // إنشاء SubscriptionInfo من بيانات API التجريبي
          final trialSubscriptionData = {
            'zone': model['zone'],
            'bundleId':
                'FTTH_BASIC', // استخدام bundleId ثابت للاشتراكات التجريبية
            'customer': model['customer'],
            'partner': model['partner'],
            'deviceDetails': {
              'username': 'trial_user', // قيمة افتراضية للاشتراكات التجريبية
            },
            'services': [
              {
                'id': model['subscription']['id'],
                'displayValue': model['subscription']['displayValue'],
                'type': {'displayValue': 'Base'}
              }
            ],
            'commitmentPeriod': 1, // افتراضي للاشتراكات التجريبية
            'status': 'Trial', // حالة تجريبية
            'startedAt': DateTime.now().toIso8601String(),
            'expiredAt': model['expiredAt'],
            // إضافة salesType افتراضي للاشتراكات التجريبية
            'salesType': {'displayValue': 'نقد'}, // قيمة افتراضية
          };
          subscriptionInfo = SubscriptionInfo.fromJson(trialSubscriptionData);
          debugPrint(
              '📊 Sales Type للاشتراك التجريبي: ${subscriptionInfo!.salesType}');
          trialExpiredAt =
              model['expiredAt']; // حفظ تاريخ انتهاء الاشتراك التجريبي
          setState(() {
            selectedPlan = subscriptionInfo!.currentPlan;
            _validateSelectedPlan(); // التأكد من صحة الخطة المحددة
            selectedCommitmentPeriod = null; // سنحددها آلياً بعد فحص الفترات
          });
          // جلب الأرصدة ثم اختيار الفترات ثم الحساب
          await _loadCustomerAddress();
          await _loadWalletsThenPrice();

          debugPrint('✅ تم جلب بيانات الاشتراك التجريبي بنجاح');
          debugPrint('👤 اسم العميل: ${subscriptionInfo!.customerName}');
          debugPrint('🏢 المنطقة: ${model['zone']['displayValue']}');
          debugPrint('📦 الخطة: ${subscriptionInfo!.currentPlan}');
          debugPrint('🤝 الشريك: ${model['partner']['displayValue']}');

          await fetchWalletBalance();
          await fetchCustomerWalletBalance();
          // تحميل عنوان المشترك لعرضه
          await _loadCustomerAddress();
        } else {
          throw Exception('البيانات المُستلمة غير صحيحة');
        }
      } else {
        debugPrint(
            '❌ فشل في جلب بيانات API التجريبي، محاولة الطريقة البديلة...');
        // إذا فشل، نحاول طريقة بديلة
        await _fetchSubscriptionByCustomerId();
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب بيانات الاشتراك التجريبي: $e');
      // إذا فشل، نحاول طريقة بديلة
      await _fetchSubscriptionByCustomerId();
    }
  }

  /// طريقة بديلة لجلب بيانات الاشتراك باستخدام customerId
  Future<void> _fetchSubscriptionByCustomerId() async {
    final response = await http.get(
      Uri.parse(
          'https://api.ftth.iq/api/customers/subscriptions?customerId=${widget.userId}'),
      headers: {
        'Authorization': 'Bearer ${widget.authToken}',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['items'] != null && data['items'].isNotEmpty) {
        subscriptionInfo = SubscriptionInfo.fromJson(data['items'][0]);
        debugPrint(
            '📊 Sales Type من الطريقة البديلة: ${subscriptionInfo!.salesType}');
        setState(() {
          selectedPlan = subscriptionInfo!.currentPlan;
          if (isNewSubscription) {
            selectedCommitmentPeriod = 1;
          } else {
            selectedCommitmentPeriod = subscriptionInfo!.commitmentPeriod;
          }
        });
        await _loadCustomerAddress();
        await _loadWalletsThenPrice();
      } else {
        throw Exception('لم يتم العثور على اشتراكات لهذا المستخدم');
      }
    } else {
      throw Exception('فشل جلب تفاصيل الاشتراك');
    }
  }

  /// جلب رصيد المحفظة
  Future<void> fetchWalletBalance() async {
    if (subscriptionInfo == null) return;
    if (!mounted) return;
    setState(() {
      isWalletLoading = true;
      walletError = null;
    });

    const int maxAttempts = 2; // محاولة أولى + إعادة واحدة
    int attempt = 0;
    while (attempt < maxAttempts) {
      attempt++;
      try {
        final response = await http.get(
          Uri.parse(
              'https://api.ftth.iq/api/partners/${subscriptionInfo!.partnerId}/wallets/balance'),
          headers: {
            'Authorization': 'Bearer ${widget.authToken}',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          double parsed = 0.0;
          double parsedTeamMember = 0.0;
          bool teamMemberActive = false;
          try {
            final model = data['model'];
            if (model is Map && model['balance'] != null) {
              final b = model['balance'];
              if (b is num) {
                parsed = b.toDouble();
              } else if (b is String) parsed = double.tryParse(b) ?? 0.0;
              final tmw = model['teamMemberWallet'];
              if (tmw is Map) {
                final tb = tmw['balance'];
                if (tb is num) {
                  parsedTeamMember = tb.toDouble();
                } else if (tb is String)
                  parsedTeamMember = double.tryParse(tb) ?? 0.0;
                teamMemberActive = tmw['hasWallet'] == true;
              }
            } else if (data['balance'] != null) {
              final b = data['balance'];
              if (b is num) {
                parsed = b.toDouble();
              } else if (b is String) parsed = double.tryParse(b) ?? 0.0;
            }
          } catch (_) {
            parsed = 0.0;
          }
          if (!mounted) return;
          setState(() {
            walletBalance = parsed;
            teamMemberWalletBalance = parsedTeamMember;
            hasTeamMemberWallet = teamMemberActive;
            walletLastUpdated = DateTime.now();
            isWalletLoading = false;
            walletError = null;
          });
          return; // نجاح
        } else {
          throw Exception('HTTP ${response.statusCode}');
        }
      } catch (e) {
        if (attempt >= maxAttempts) {
          if (!mounted) return;
          setState(() {
            walletError = 'فشل تحديث الرصيد';
            isWalletLoading = false;
          });
          debugPrint('❌ فشل جلب الرصيد بعد محاولات: $e');
          return;
        } else {
          debugPrint('⚠️ فشل محاولة ($attempt) لجلب الرصيد، إعادة المحاولة...');
          await Future.delayed(const Duration(milliseconds: 650));
        }
      }
    }
  }

  /// جلب رصيد محفظة المشترك (العميل)
  Future<void> fetchCustomerWalletBalance() async {
    if (!mounted) return;
    try {
      final response = await http.get(
        Uri.parse(
            'https://admin.ftth.iq/api/customers/${widget.userId}/wallets/balance'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        double bal = 0.0;
        try {
          final model = data['model'];
          if (model is Map && model['balance'] != null) {
            final b = model['balance'];
            if (b is num) {
              bal = b.toDouble();
            } else if (b is String) bal = double.tryParse(b) ?? 0.0;
          }
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          customerWalletBalance = bal;
          hasCustomerWallet = true; // نعتبرها متاحة حتى لو صفر لإظهارها
        });
      } else {
        if (!mounted) return;
        setState(() {
          hasCustomerWallet = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        hasCustomerWallet = false;
      });
    }
  }

  /// حساب السعر حسب نوع العملية
  Future<void> fetchPriceDetails() async {
    if (subscriptionInfo == null) {
      setState(() {
        errorMessage = "لم يتم العثور على معلومات الاشتراك";
      });
      return;
    }
    // إعادة ضبط مؤشرات الخطأ عند بدء محاولة جديدة أولى فقط إذا لم يكن لدينا نتائج
    if (priceDetails == null) {
      setState(() {
        isLoading = true;
        _priceError = null;
      });
    }

    const int maxAttempts = 3; // محاولات متتالية لتحسين نجاح الجلب
    int attempt = 0;
    while (attempt < maxAttempts && priceDetails == null) {
      attempt++;
      try {
        if (isNewSubscription) {
          await _fetchTrialPriceDetails();
        } else {
          await _fetchRegularPriceDetails();
        }
      } catch (e) {
        if (attempt >= maxAttempts) {
          _priceError = (e is TimeoutException)
              ? 'انتهت المهلة أثناء حساب السعر.'
              : 'فشل حساب السعر: $e';
        } else {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    // إذا لم يتم الحصول على السعر ولم يُسجَل خطأ (مثلاً model=null)
    if (priceDetails == null && _priceError == null) {
      _priceError = 'لم يتم الحصول على تفاصيل السعر من الخادم. حاول مجدداً.';
    }
    if (mounted) {
      setState(() {
        _priceAttempted = true;
        isLoading = false;
      });
    }
  }

  /// حساب السعر مباشرة لنمط (Extend) عند تغيير فترة الالتزام (يُستدعى بعد اختيار الفترة)
  Future<void> _autoFetchExtendPriceIfNeeded() async {
    if (isNewSubscription) return; // لا ينطبق على الاشتراك التجريبي
    final opType = _getCalcPriceOperationType();
    if (opType != 'Extend') return; // ليس تمديد
    if (subscriptionInfo == null) return;
    selectedPlan ??= subscriptionInfo!.currentPlan;
    if (selectedCommitmentPeriod == null) return;
    if (priceDetails != null && _extendPriceError == null) {
      return; // لدينا سعر سابق
    }
    setState(() {
      _isCalculatingExtendPrice = true;
      _extendPriceError = null;
      priceDetails = null;
    });
    try {
      final baseService = Uri.encodeComponent(
          jsonEncode({"value": selectedPlan, "type": "Base"}));
      final vasServices = [
        {"value": "PARENTAL_CONTROL", "type": "Vas"},
        {"value": "IPTV", "type": "Vas"},
      ].map((s) => Uri.encodeComponent(jsonEncode(s)));
      final servicesParams =
          [baseService, ...vasServices].map((e) => 'services=$e').join('&');
      final url =
          'https://admin.ftth.iq/api/subscriptions/calculate-price?bundleId=${subscriptionInfo!.bundleId}&commitmentPeriodValue=$selectedCommitmentPeriod&planOperationType=Extend&subscriptionId=${widget.subscriptionId}&$servicesParams&salesType=${_getSalesTypeValue()}&changeType=1';
      debugPrint('🔗 (AUTO) Extend calculate-price URL => $url');
      final r = await http.get(Uri.parse(url), headers: {
        'Authorization': 'Bearer ${widget.authToken}',
        'Accept': 'application/json'
      }).timeout(const Duration(seconds: 15));
      debugPrint('📥 (AUTO) ImmediateExtend price status ${r.statusCode}');
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final data = jsonDecode(r.body);
      final model = data['model'];
      if (model is Map<String, dynamic>) {
        setState(() {
          priceDetails = _normalizePriceModel(model);
          priceDetails!['source'] = 'calculate-price-auto-extend';
        });
      } else {
        throw Exception('رد غير متوقع');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _extendPriceError = 'فشل حساب سعر التمديد: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isCalculatingExtendPrice = false);
      }
    }
  }

  // جدولة حساب تلقائي للسعر بعد اختيار الخطة والفترة
  void _scheduleAutoPriceFetch() {
    if (selectedPlan == null || selectedCommitmentPeriod == null) return;
    if (isLoading) return; // تجنب التزاحم مع حساب جارٍ
    // إلغاء مؤقت سابق
    _autoPriceTimer?.cancel();
    _autoPriceTimer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      // إذا لم تُحسب الأسعار بعد أو تغيرت الخطة/الفترة بعد آخر حساب
      if (priceDetails == null) {
        await fetchPriceDetails();
      }
    });
  }

  /// حساب سعر مبدئي للاستخدام داخل نافذة التأكيد دون تعديل الحالة العامة
  Future<Map<String, dynamic>?> _calculatePricePreview() async {
    if (subscriptionInfo == null && !isNewSubscription) return null;
    try {
      if (isNewSubscription) {
        // محاولة bundles أولاً
        try {
          final bundlesResp = await http.get(
            Uri.parse(
                'https://admin.ftth.iq/api/plans/bundles?includePrices=true&subscriptionId=${widget.subscriptionId}'),
            headers: {
              'Authorization': 'Bearer ${widget.authToken}',
              'Accept': 'application/json',
            },
          ).timeout(const Duration(seconds: 15));
          if (bundlesResp.statusCode == 200) {
            final data = jsonDecode(bundlesResp.body);
            final items = data['items'] as List?;
            if (items != null && items.isNotEmpty) {
              Map<String, dynamic>? matchingBundle;
              for (var bundle in items) {
                final services = bundle['services'] as List?;
                if (services != null) {
                  for (var service in services) {
                    final st = service['type'];
                    final isBase = st == 'Base' ||
                        (st is Map &&
                            (st['displayValue']?.toString().toLowerCase() ==
                                'base'));
                    if (!isBase || selectedPlan == null) continue;
                    String norm(String? v) => (v ?? '')
                        .toUpperCase()
                        .replaceAll(RegExp(r'\s+'), ' ')
                        .trim();
                    final serviceIdNorm = norm(service['id']?.toString());
                    final serviceDisplayNorm =
                        norm(service['displayValue']?.toString());
                    final sel = norm(selectedPlan);
                    if (serviceIdNorm == sel || serviceDisplayNorm == sel) {
                      matchingBundle = bundle;
                      break;
                    }
                  }
                }
                if (matchingBundle != null) break;
              }
              matchingBundle ??= items.first;
              final prices = matchingBundle?['prices'] as Map<String, dynamic>?;
              if (prices != null) {
                final key = selectedCommitmentPeriod.toString();
                final pInfo = prices[key] as Map<String, dynamic>?;
                if (pInfo != null) {
                  return _normalizePriceModel({
                    'totalPrice': pInfo['totalPrice'],
                    'basePrice': pInfo['basePrice'],
                    'discount': pInfo['discount'],
                    'currency': pInfo['currency'] ?? 'IQD',
                    'discountPercentage': pInfo['discountPercentage'],
                  });
                }
              }
            }
          }
        } catch (_) {
          // تجاهل ثم نحاول الطريقة الأخرى
        }

        // fallback calculate-price trial
        final baseService = Uri.encodeComponent(
            jsonEncode({"value": selectedPlan, "type": "Base"}));
        final vasServices = [
          {"value": "IPTV", "type": "Vas"},
          {"value": "PARENTAL_CONTROL", "type": "Vas"}
        ].map((s) => Uri.encodeComponent(jsonEncode(s)));
        final servicesParams =
            [baseService, ...vasServices].map((e) => 'services=$e').join('&');
        final url = 'https://admin.ftth.iq/api/subscriptions/calculate-price'
            '?bundleId=FTTH_BASIC'
            '&commitmentPeriodValue=$selectedCommitmentPeriod'
            '&planOperationType=PurchaseFromTrial'
            '&subscriptionId=${widget.subscriptionId}'
            '&$servicesParams'
            '&salesType=${_getSalesTypeValue()}';
        final resp = await http.get(Uri.parse(url), headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final model = (data['model'] as Map<String, dynamic>?);
          if (model != null) return _normalizePriceModel(model);
        }
        return null;
      } else {
        // اشتراك عادي (استخدام Extend عند التطابق، مع changeType=1 عند Extend)
        final opType = _getCalcPriceOperationType();
        final baseService = Uri.encodeComponent(
            jsonEncode({"value": selectedPlan, "type": "Base"}));
        final vasServices = [
          {"value": "IPTV", "type": "Vas"},
          {"value": "PARENTAL_CONTROL", "type": "Vas"}
        ].map((s) => Uri.encodeComponent(jsonEncode(s)));
        final servicesParams =
            [baseService, ...vasServices].map((e) => 'services=$e').join('&');
        String url = 'https://admin.ftth.iq/api/subscriptions/calculate-price'
            '?bundleId=${subscriptionInfo!.bundleId}'
            '&commitmentPeriodValue=$selectedCommitmentPeriod'
            '&planOperationType=$opType'
            '&subscriptionId=${widget.subscriptionId}'
            '&$servicesParams'
            '&salesType=${_getSalesTypeValue()}';
        if (opType == 'Extend') {
          url += '&changeType=1';
        }
        final resp = await http.get(Uri.parse(url), headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final model = (data['model'] as Map<String, dynamic>?);
          if (model != null) return _normalizePriceModel(model);
        }
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// معالجة ضغط زر حساب السعر مع نافذة تحذير حمراء تعرض السعر
  Future<void> _handleCalculatePricePressed() async {
    if (selectedPlan == null || selectedCommitmentPeriod == null) {
      ftthShowSnackBar(
        context,
        const SnackBar(
          content: Text('يرجى اختيار الخطة وفترة الالتزام أولاً'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // في حالة مدة أكبر من شهر نعرض نافذة حمراء بالسعر قبل التأكيد
    if (selectedCommitmentPeriod! > 1) {
      // إظهار حوار انتظار جميل
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  spreadRadius: 2,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.indigo.shade600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'جاري حساب السعر...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'يرجى الانتظار',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.indigo.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final preview = await _calculatePricePreview();
      Navigator.of(context).pop(); // إغلاق الانتظار
      if (preview == null) {
        ftthShowErrorNotification(context, 'تعذر حساب السعر المبدئي');
        return;
      }

      final total = _formatNumber(_asDouble(preview['totalPrice']).round());
      final currency = (preview['totalPrice'] is Map &&
              preview['totalPrice']['currency'] != null)
          ? preview['totalPrice']['currency'].toString()
          : (preview['currency']?.toString() ?? 'IQD');
      final monthly = _formatNumber(_asDouble(preview['monthlyPrice']).ceil());
      final base = _formatNumber(_asDouble(preview['basePrice']).round());
      final discount = _formatNumber(_asDouble(preview['discount']).round());

      final confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.red.shade100,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.red.shade300, width: 2)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('تحذير مدة طويلة'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الفترة المختارة: $selectedCommitmentPeriod أشهر لـ ($selectedPlan).\nسيتم احتساب السعر الكامل لهذه المدة.',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade200, Colors.red.shade100],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade400, width: 1.3),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.red.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.price_change,
                            size: 20, color: Colors.red.shade900),
                        const SizedBox(width: 6),
                        Text('تفاصيل الأسعار',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade900)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildPriceLine('السعر الأساسي', base, currency),
                    _buildPriceLine('الخصم', discount, currency),
                    _buildPriceLine('السعر الشهري', monthly, currency),
                    Divider(color: Colors.red.shade300, height: 14),
                    _buildPriceLine('السعر الإجمالي', total, currency,
                        emphasize: true),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text('هل تريد المتابعة وتثبيت هذا السعر؟',
                  style: TextStyle(fontSize: 13)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.check_circle, size: 18),
              label: const Text('تأكيد'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
      if (confirm == true) {
        setState(() {
          priceDetails = preview;
        });
        _evaluatePriceWalletRelation();
      }
      return;
    }

    // مدة شهر واحد فقط: حساب مباشر
    await fetchPriceDetails();
  }

  /// جلب أسعار الاشتراك التجريبي من endpoint bundles أو calculate-price
  Future<void> _fetchTrialPriceDetails() async {
    debugPrint('📊 جلب أسعار الاشتراك التجريبي...');

    // أولاً نحاول جلب الأسعار من bundles API مع subscriptionId
    try {
      await _fetchTrialPricesFromBundles();
      return; // إذا نجح، لا نحتاج لمحاولة الطريقة الأخرى
    } catch (e) {
      debugPrint('❌ فشل في جلب أسعار bundles: $e');
      debugPrint(
          '🔄 محاولة جلب الأسعار من calculate-price مع PurchaseFromTrial...');
    }

    // إذا فشل bundles API، استخدم calculate-price مع planOperationType=PurchaseFromTrial
    try {
      await _fetchTrialPricesFromCalculatePrice();
    } catch (e) {
      debugPrint('❌ فشل في جلب أسعار calculate-price: $e');
      throw Exception(
          'فشل في جلب أسعار الاشتراك التجريبي من جميع المصادر المتاحة');
    }
  }

  /// جلب أسعار الاشتراك التجريبي من bundles API
  Future<void> _fetchTrialPricesFromBundles() async {
    debugPrint('📊 جلب أسعار الاشتراك التجريبي من bundles API...');
    debugPrint(
        '🔗 URL: https://admin.ftth.iq/api/plans/bundles?includePrices=true&subscriptionId=${widget.subscriptionId}');

    final response = await http.get(
      Uri.parse(
          'https://admin.ftth.iq/api/plans/bundles?includePrices=true&subscriptionId=${widget.subscriptionId}'),
      headers: {
        'Authorization': 'Bearer ${widget.authToken}',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 15));

    debugPrint('📥 Bundles Response Status: ${response.statusCode}');
    debugPrint('📥 Bundles Response Body: ${response.body}');

    if (response.statusCode != 200) {
      throw Exception('فشل في جلب بيانات bundles: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final items = data['items'] as List?;

    if (items == null || items.isEmpty) {
      throw Exception('لم يتم العثور على خطط متاحة للاشتراك التجريبي');
    }

    // البحث عن الخطة المطابقة للخطة المحددة
    Map<String, dynamic>? matchingBundle;

    for (var bundle in items) {
      final services = bundle['services'] as List?;
      if (services != null) {
        for (var service in services) {
          // تطبيع نوع الخدمة (قد يكون نصاً مباشراً أو كائن يحتوي displayValue)
          final serviceType = service['type'];
          final isBase = serviceType == 'Base' ||
              (serviceType is Map &&
                  (serviceType['displayValue']?.toString().toLowerCase() ==
                      'base'));
          if (!isBase || selectedPlan == null) continue;

          String normalize(String? v) =>
              (v ?? '').toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();

          final serviceIdNorm = normalize(service['id']?.toString());
          final serviceDisplayNorm =
              normalize(service['displayValue']?.toString());
          final selectedNorm = normalize(selectedPlan);

          final matches = serviceIdNorm == selectedNorm ||
              serviceDisplayNorm == selectedNorm;

          if (matches) {
            matchingBundle = bundle;
            debugPrint(
                '✅ تم العثور على الباقة المطابقة للخطة المختارة عبر ${serviceIdNorm == selectedNorm ? 'id' : 'displayValue'}');
            break;
          }
        }
        if (matchingBundle != null) break;
      }
    }

    // إذا لم نجد تطابق دقيق، خذ أول bundle متاح
    matchingBundle ??= items.first;
    if (matchingBundle == items.first) {
      debugPrint(
          '⚠️ لم يتم العثور على باقة مطابقة للخطة المختارة ($selectedPlan). سيتم استخدام أول باقة كبديل.');
    }

    final bundlePrices = matchingBundle?['prices'] as Map<String, dynamic>?;
    if (bundlePrices == null) {
      throw Exception('لم يتم العثور على معلومات الأسعار في البيانات المستلمة');
    }

    // البحث عن السعر حسب فترة الالتزام
    final commitmentKey = selectedCommitmentPeriod.toString();
    final priceInfo = bundlePrices[commitmentKey] as Map<String, dynamic>?;

    if (priceInfo == null) {
      throw Exception(
          'لم يتم العثور على معلومات السعر لفترة الالتزام المحددة ($selectedCommitmentPeriod شهر)');
    }

    setState(() {
      final normalized = _normalizePriceModel({
        'totalPrice': priceInfo['totalPrice'],
        'basePrice': priceInfo['basePrice'],
        'discount': priceInfo['discount'],
        'currency': priceInfo['currency'] ?? 'IQD',
        'discountPercentage': priceInfo['discountPercentage'],
      });
      priceDetails = normalized;
      priceDetails!['source'] = 'bundles';
      // تقييم بعد حساب السعر
      _evaluatePriceWalletRelation();
    });

    debugPrint('✅ تم جلب أسعار الاشتراك التجريبي من bundles بنجاح');
    debugPrint(
        '💰 السعر الإجمالي: ${priceInfo['totalPrice']} ${priceInfo['currency']}');
    debugPrint(
        '🏷️ السعر الأساسي: ${priceInfo['basePrice']} ${priceInfo['currency']}');
    debugPrint('💸 الخصم: ${priceInfo['discount']} ${priceInfo['currency']}');
    debugPrint('📊 نسبة الخصم: ${priceInfo['discountPercentage']}%');
  }

  /// جلب أسعار الاشتراك التجريبي من calculate-price مع PurchaseFromTrial
  Future<void> _fetchTrialPricesFromCalculatePrice() async {
    debugPrint(
        '📊 جلب أسعار الاشتراك التجريبي من calculate-price مع PurchaseFromTrial...');

    final baseService = Uri.encodeComponent(
        jsonEncode({"value": selectedPlan, "type": "Base"}));
    final vasServices = [
      {"value": "IPTV", "type": "Vas"},
      {"value": "PARENTAL_CONTROL", "type": "Vas"}
    ].map((service) => Uri.encodeComponent(jsonEncode(service)));

    final servicesParams = [baseService, ...vasServices]
        .map((service) => 'services=$service')
        .join('&');
    final url = 'https://admin.ftth.iq/api/subscriptions/calculate-price'
        '?bundleId=FTTH_BASIC'
        '&commitmentPeriodValue=$selectedCommitmentPeriod'
        '&planOperationType=PurchaseFromTrial'
        '&subscriptionId=${widget.subscriptionId}'
        '&$servicesParams'
        '&salesType=${_getSalesTypeValue()}';

    debugPrint('🔗 Calculate Price URL (Trial): $url');
    debugPrint('📦 bundleId: FTTH_BASIC (ثابت للاشتراكات التجريبية)');
    debugPrint('📅 commitmentPeriodValue: $selectedCommitmentPeriod');
    debugPrint('🔄 planOperationType: PurchaseFromTrial');
    debugPrint('🆔 subscriptionId: ${widget.subscriptionId}');
    debugPrint('🛠️ selectedPlan: $selectedPlan');
    debugPrint('🛒 salesType: ${_getSalesTypeValue()}');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer ${widget.authToken}',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 15));

    debugPrint('📥 Calculate Price Response Status: ${response.statusCode}');
    debugPrint('📥 Calculate Price Response Body: ${response.body}');

    if (response.statusCode != 200) {
      throw Exception('فشل حساب السعر: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    setState(() {
      final model = (data['model'] as Map<String, dynamic>?);
      if (model != null) {
        priceDetails = _normalizePriceModel(model);
        priceDetails!['source'] = 'calculate-price-trial';
      } else {
        priceDetails = null;
      }
      _evaluatePriceWalletRelation();
    });

    debugPrint('✅ تم جلب أسعار الاشتراك التجريبي من calculate-price بنجاح');
    if (priceDetails != null && priceDetails!['totalPrice'] != null) {
      final v = _asDouble(priceDetails!['totalPrice']).toStringAsFixed(0);
      final c = (priceDetails!['totalPrice'] is Map &&
              priceDetails!['totalPrice']['currency'] != null)
          ? priceDetails!['totalPrice']['currency'].toString()
          : 'IQD';
      debugPrint('💰 السعر الإجمالي: $v $c');
    }
  }

  /// جلب أسعار الاشتراك العادي من endpoint calculate-price
  Future<void> _fetchRegularPriceDetails() async {
    debugPrint('📊 جلب أسعار الاشتراك العادي من calculate-price API...');

    final baseService = Uri.encodeComponent(
        jsonEncode({"value": selectedPlan, "type": "Base"}));

    final vasServices = [
      {"value": "IPTV", "type": "Vas"},
      {"value": "PARENTAL_CONTROL", "type": "Vas"}
    ].map((service) => Uri.encodeComponent(jsonEncode(service)));

    final servicesParams = [baseService, ...vasServices]
        .map((service) => 'services=$service')
        .join('&');
    final opType = _getCalcPriceOperationType();
    String url = 'https://admin.ftth.iq/api/subscriptions/calculate-price'
        '?bundleId=${subscriptionInfo!.bundleId}'
        '&commitmentPeriodValue=$selectedCommitmentPeriod'
        '&planOperationType=$opType'
        '&subscriptionId=${widget.subscriptionId}'
        '&$servicesParams'
        '&salesType=${_getSalesTypeValue()}';
    if (opType == 'Extend') {
      url += '&changeType=1';
    }

    debugPrint('🔗 Calculate Price URL: $url');
    debugPrint('📦 bundleId: ${subscriptionInfo!.bundleId}');
    debugPrint('📅 commitmentPeriodValue: $selectedCommitmentPeriod');
    debugPrint('🔄 planOperationType (calc): $opType');
    debugPrint('🆔 subscriptionId: ${widget.subscriptionId}');
    debugPrint('🛠️ selectedPlan: $selectedPlan');
    debugPrint('🛒 salesType: ${_getSalesTypeValue()}');
    debugPrint('🆔 subscriptionId: ${widget.subscriptionId}');
    debugPrint('🛠️ selectedPlan: $selectedPlan');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer ${widget.authToken}',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 15));

    debugPrint('📥 Calculate Price Response Status: ${response.statusCode}');
    debugPrint('📥 Calculate Price Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        final model = (data['model'] as Map<String, dynamic>?);
        if (model != null) {
          priceDetails = _normalizePriceModel(model);
          priceDetails!['source'] = 'calculate-price';
          _evaluatePriceWalletRelation();
        } else {
          priceDetails = null;
        }
      });
      // بعد اكتمال الحساب يمكن إعادة بناء الواجهة لعرض التفاصيل فوراً

      debugPrint('✅ تم جلب أسعار الاشتراك العادي بنجاح');
      if (priceDetails != null && priceDetails!['totalPrice'] != null) {
        final v = _asDouble(priceDetails!['totalPrice']).toStringAsFixed(0);
        final c = (priceDetails!['totalPrice'] is Map &&
                priceDetails!['totalPrice']['currency'] != null)
            ? priceDetails!['totalPrice']['currency'].toString()
            : 'IQD';
        debugPrint('💰 السعر الإجمالي: $v $c');
      }
    } else {
      throw Exception('فشل حساب السعر: ${response.statusCode}');
    }
  }

  // (تم استبدال دالة التجديد بدالة موحدة أدناه)

  /// زر موحد (تجديد أو تغيير) حسب الحالة
  Future<void> performRenewOrChange() async {
    if (subscriptionInfo == null) {
      setState(() => errorMessage = 'معلومات الاشتراك غير متوفرة');
      return;
    }
    // تأكد من وجود خطة ومدة محددتين
    selectedPlan ??= subscriptionInfo!.currentPlan;
    selectedCommitmentPeriod ??= subscriptionInfo!.commitmentPeriod;
    if (priceDetails == null) {
      await fetchPriceDetails();
      if (priceDetails == null) {
        setState(() => errorMessage = 'فشل حساب السعر');
        return;
      }
    }
    final totalPrice = _asDouble(priceDetails!['totalPrice']);
    if (totalPrice > walletBalance) {
      setState(() => errorMessage = 'الرصيد غير كافٍ لإتمام العملية');
      return;
    }
    await changeSubscription();
  }

  /// جلب رقم الهاتف الصحيح للمشترك
  String? _getCustomerPhoneNumber() {
    // إذا كان الرقم محفوظًا في الذاكرة المؤقتة، أرجعه مباشرة
    if (_cachedCustomerPhone != null) {
      return _cachedCustomerPhone;
    }

    // الأولوية الأولى: رقم الهاتف المجلوب من API
    if (_fetchedCustomerPhone != null &&
        _fetchedCustomerPhone!.trim().isNotEmpty) {
      _cachedCustomerPhone = _fetchedCustomerPhone!.trim();
      return _cachedCustomerPhone;
    }

    // الأولوية الثانية: رقم الهاتف الممرر من الصفحة السابقة (احتياطي)
    if (widget.userPhone != null && widget.userPhone!.trim().isNotEmpty) {
      _cachedCustomerPhone = widget.userPhone!.trim();
      return _cachedCustomerPhone;
    }

    // إذا لم يوجد رقم هاتف
    return null;
  }

  /// إرسال رسالة واتساب مع فحص وجود الرقم وتحديث الحالة
  Future<void> sendWhatsAppMessage() async {
    if (subscriptionInfo == null) return;

    // التحقق من أن السعر محسوب
    if (priceDetails == null) {
      if (mounted) {
        ftthShowErrorNotification(context, 'يرجى حساب السعر أولاً!');
      }
      return;
    }

    final phone = _getCustomerPhoneNumber();
    if (phone == null) {
      if (mounted) {
        ftthShowErrorNotification(context, 'رقم الهاتف غير متوفر!');
      }
      return;
    }

    setState(() {
      _isSendingWhatsApp = true;
    });

    bool sent = false; // لتحديد إن تم الإرسال فعلاً
    try {
      final phoneNumber = _formatPhoneNumber(phone);

      // تنظيف رقم الهاتف وتنسيقه
      final cleanPhone = _validateAndFormatPhone(phoneNumber);
      if (cleanPhone == null) {
        ftthShowErrorNotification(
            context, 'رقم الهاتف غير صحيح - تحقق من إعدادات الواتساب');
        return;
      }

      debugPrint('📱 فتح تطبيق الواتساب على الحاسوب مع رسالة التفاصيل...');
      debugPrint('� رقم العميل: $cleanPhone');

      // إنشاء رسالة التفاصيل فقط
      final message = _buildSimpleWhatsAppMessage();

      // نسخ الرسالة إلى الكليببورد
      await Clipboard.setData(ClipboardData(text: message));

      debugPrint('📝 طول الرسالة: ${message.length} حرف');

      // الإرسال التلقائي دائماً (إزالة الخيار اليدوي لجعله أسرع وأبسط)
      debugPrint('🚀 الإرسال التلقائي السريع: فتح واتساب بدون نص في الرابط');

      // فتح واتساب بدون رسالة في الرابط لتجنب الإرسال المزدوج
      final whatsappUrl = 'whatsapp://send?phone=$cleanPhone';

      try {
        // محاولة فتح الواتساب مع معالجة الإصدارات المختلفة
        bool launched = false;

        try {
          // محاولة أولى: الإصدار الحديث
          debugPrint('🔄 محاولة فتح الواتساب بالطريقة الحديثة...');
          final uri = Uri.parse(whatsappUrl);
          launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
        } catch (e) {
          debugPrint(
              '⚠️ فشل فتح الواتساب بالطريقة الحديثة، محاولة الطريقة التقليدية: $e');

          // محاولة ثانية: واتساب ويب للإصدارات القديمة
          try {
            final fallbackUrl =
                'https://web.whatsapp.com/send?phone=$cleanPhone';
            launched = await launchUrl(
              Uri.parse(fallbackUrl),
              mode: LaunchMode.externalApplication,
            );
            debugPrint('✅ تم فتح واتساب ويب كبديل للإصدار القديم');
          } catch (e2) {
            debugPrint('❌ فشل فتح واتساب ويب أيضاً: $e2');
            // محاولة أخيرة: الطريقة التقليدية مع الرسالة في الرابط
            try {
              final legacyUrl =
                  'whatsapp://send?phone=$cleanPhone&text=${Uri.encodeComponent(message)}';
              launched = await launchUrl(
                Uri.parse(legacyUrl),
                mode: LaunchMode.externalApplication,
              );
              debugPrint('⚠️ استخدام الطريقة التقليدية مع الرسالة في الرابط');
            } catch (e3) {
              debugPrint('❌ فشل جميع محاولات فتح الواتساب: $e3');
              launched = false;
            }
          }
        }

        if (launched) {
          debugPrint('✅ تم فتح واتساب ديسكتوب - بدء الإرسال التلقائي الفوري');
          sent = true;

          // انتظار قصير جداً فقط لفتح واتساب (تقليل من 800ms إلى 600ms)
          await Future.delayed(Duration(milliseconds: 600));

          // نسخ الرسالة للحافظة
          await Clipboard.setData(ClipboardData(text: message));

          // تنفيذ الإرسال التلقائي الفوري بأقصى سرعة ممكنة
          final autoSendSuccess =
              await WindowsAutomationService.performSmartAutoSend(
                  delayMs: 30 // أقصى سرعة - 30ms فقط بين العمليات
                  );

          if (autoSendSuccess) {
            debugPrint('⚡ تم الإرسال الفوري بنجاح خلال ثوانٍ قليلة');
            if (mounted) {
              ftthShowSuccessNotification(
                  context, '⚡ تم إرسال رسالة واتساب فورياً!');
              // إشعار إضافي لإعلام المستخدم بمحاولة إعادة التركيز
              ftthShowInfoNotification(
                  context, '🔄 محاولة إعادة المؤشر لمربع النص...');
            }
            // بعد الإرسال الناجح نحاول إرجاع التركيز داخل تطبيقنا أيضاً
            _shiftTabBackOnce();
          } else {
            debugPrint('⚠️ فشل الإرسال الفوري - استخدام النسخة الاحتياطية');
            if (mounted) {
              ftthShowSuccessNotification(context,
                  '⚠️ تم فتح واتساب - يرجى لصق الرسالة (Ctrl+V) وإرسالها');
            }
          }
        } else {
          throw Exception('فشل في فتح واتساب ديسكتوب');
        }
      } catch (e) {
        debugPrint('❌ خطأ في فتح واتساب ديسكتوب: $e');

        if (mounted) {
          // رسالة مفصلة للمساعدة مع الإصدارات القديمة - للعميل
          String errorMessage = 'فشل في فتح واتساب للعميل.\n\n';
          errorMessage += '💡 نصائح للحل:\n';
          errorMessage += '• تأكد من تثبيت واتساب ديسكتوب\n';
          errorMessage += '• حدث واتساب لأحدث إصدار\n';
          errorMessage += '• أعد تشغيل واتساب ديسكتوب\n';
          errorMessage += '• تم نسخ الرسالة، يمكنك لصقها يدوياً';

          ftthShowErrorNotification(context, errorMessage);
        }
      }

      if (sent && mounted) {
        setState(() {
          isWhatsAppSent = true;
        });
        debugPrint('📱 WhatsApp: تم التحديث isWhatsAppSent بعد الإرسال');
      }

      // تحديث حالة الواتساب في VPS بعد الإرسال (غير حاجز للواجهة)
      if (sent) {
        debugPrint('🚀 تحديث حالة الواتساب في VPS بعد الإرسال (Deferred)...');
        unawaited(Future(() async {
          try {
            await _updateWhatsAppStatusInVps();
            debugPrint('✅ تم تحديث حالة الواتساب في VPS');
          } catch (e, st) {
            debugPrint('❌ فشل تحديث حالة الواتساب في VPS: $e');
            debugPrint(st.toString());
          }
        }));
      }
    } catch (e) {
      if (mounted) {
        ftthShowErrorNotification(context, 'خطأ: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingWhatsApp = false;
        });
      }
    }
  }

  /// طباعة وصل التجديد مع تحديث حالة الطباعة
  Future<void> printSubscriptionReceipt() async {
    if (subscriptionInfo == null) {
      if (mounted) {
        ftthShowErrorNotification(context, 'معلومات الاشتراك غير متوفرة!');
      }
      return;
    }

    // تحذير إذا تم طباعة الوصل مسبقاً
    if (isPrinted) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // أيقونة متحركة
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.print_disabled_rounded,
                  color: Colors.orange.shade700,
                  size: 56,
                ),
              ),
              const SizedBox(height: 20),
              // العنوان
              Text(
                '⚠️ تحذير',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                ),
              ),
              const SizedBox(height: 12),
              // الرسالة الرئيسية
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'تم طباعة هذا الوصل مسبقاً!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // معلومات العميل
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    _buildInfoRow('العميل',
                        subscriptionInfo?.customerName ?? '', Icons.person),
                    const Divider(height: 16),
                    _buildInfoRow('الخطة', selectedPlan ?? '', Icons.wifi),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // السؤال
              const Text(
                'هل تريد طباعة الوصل مرة أخرى؟',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // الأزرار
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      icon: const Icon(Icons.close),
                      label: const Text('إلغاء'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      icon: const Icon(Icons.print),
                      label: const Text('طباعة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      if (shouldContinue != true) {
        return; // المستخدم ألغى الطباعة المكررة
      }
      debugPrint('⚠️ المستخدم اختار طباعة الوصل مرة أخرى');
    }

    // تعيين حالة انتظار الطباعة
    setState(() {
      _isPrinting = true;
    });

    try {
      // جمع البيانات المطلوبة للطباعة
      final phone = _getCustomerPhoneNumber();
      final customerPhone = phone ?? 'غير متوفر';
      debugPrint('📱 رقم الهاتف للطباعة: $customerPhone');
      final operationText =
          isNewSubscription ? "تم شراء اشتراك جديد" : "تم تجديد الاشتراك";

      // طباعة الوصل
      debugPrint('🖨️ Starting receipt printing...');
      debugPrint('🖨️ Operation: $operationText');
      debugPrint('🖨️ Customer: ${subscriptionInfo!.customerName}');
      debugPrint('🖨️ Plan: ${selectedPlan ?? 'غير محددة'}');
      final printVal = _formatNumber(_getFinalTotal().round());
      final printCurr = (priceDetails!['totalPrice'] is Map &&
              priceDetails!['totalPrice']['currency'] != null)
          ? priceDetails!['totalPrice']['currency'].toString()
          : (priceDetails!['currency']?.toString() ?? 'IQD');
      debugPrint('🖨️ Price: $printVal $printCurr');

      // استخدام تخطيط 4 أعمدة عبر القالب المخصص
      final template = await PrintTemplateStorage.loadTemplate();
      // استخدام حجم الخط المحفوظ ضمن نطاق أوسع (8 إلى 20) ليعكس تغييرات المستخدم فعلاً
      final adjustedTemplate = PrintTemplate(
        companyName: template.companyName,
        companySubtitle: template.companySubtitle,
        footerMessage: template.footerMessage,
        contactInfo: template.contactInfo,
        showCustomerInfo:
            true, // فرض إظهار معلومات العميل دائماً (اسم + رقم هاتف)
        showServiceDetails: template.showServiceDetails,
        showPaymentDetails: template.showPaymentDetails,
        showAdditionalInfo: template.showAdditionalInfo,
        showContactInfo: template.showContactInfo,
        fontSize: template.fontSize.clamp(8.0, 20.0),
        boldHeaders: template.boldHeaders,
      );
      final now = DateTime.now();
      final activationDate = '${now.day}/${now.month}/${now.year}';
      final activationTime =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final bool success =
          await ThermalPrinterService.printCustomSubscriptionReceipt(
        operationType: operationText,
        selectedPlan: selectedPlan ?? '',
        selectedCommitmentPeriod: (selectedCommitmentPeriod ?? 0).toString(),
        totalPrice: _getFinalTotal().toStringAsFixed(0),
        currency: printCurr,
        selectedPaymentMethod: selectedPaymentMethod,
        endDate: _calculateEndDate(),
        customerName: subscriptionInfo!.customerName,
        customerPhone: customerPhone,
        customerAddress: customerAddress ?? '',
        isNewSubscription: isNewSubscription,
        customTemplate: adjustedTemplate,
        activationDate: activationDate,
        activationTime: activationTime,
        // FDT: إذا كانت القيمة غير متوفرة أو فارغة استخدم FBG كبديل (طلب المستخدم)
        fdtInfo: (widget.fdtDisplayValue != null &&
                widget.fdtDisplayValue!.trim().isNotEmpty)
            ? widget.fdtDisplayValue!
            : (widget.fbgValue != null && widget.fbgValue!.trim().isNotEmpty
                ? widget.fbgValue!.trim()
                : null),
        // FAT: fallback إلى القيمة الخام fatValue إذا لم تتوفر fatDisplayValue
        fatInfo: (widget.fatDisplayValue != null &&
                widget.fatDisplayValue!.trim().isNotEmpty)
            ? widget.fatDisplayValue!
            : (widget.fatValue != null && widget.fatValue!.trim().isNotEmpty
                ? widget.fatValue!.trim()
                : null),
        activatedBy: widget.activatedBy,
        subscriptionNotes:
            (isNotesEnabled && subscriptionNotes.trim().isNotEmpty)
                ? subscriptionNotes.trim()
                : null, // إضافة الملاحظات فقط إذا كان زر الملاحظات مفعل
      );

      debugPrint('🖨️ Receipt printing result: $success');

      if (mounted) {
        if (success) {
          // تحديث حالة الطباعة
          setState(() {
            isPrinted = true;
          });

          debugPrint('🖨️ Print: تم تحديث الحالة إلى true');
          debugPrint(
              '🖨️ Current state - isPrinted: $isPrinted, isWhatsAppSent: $isWhatsAppSent');

          // تحديث حالة الطباعة في VPS
          try {
            await _updatePrintStatusInVps();
            debugPrint('✅ تم تحديث حالة الطباعة في VPS');
          } catch (e) {
            debugPrint('⚠️ فشل تحديث حالة الطباعة في VPS: $e');
            // إذا لم يكن السجل محفوظاً بعد، نحفظ كاملاً
            if (!isDataSavedToServer && widget.hasServerSavePermission) {
              try {
                await _saveToServer();
                debugPrint('✅ تم حفظ البيانات كاملة مع حالة الطباعة');
              } catch (e2) {
                debugPrint('⚠️ فشل الحفظ الكامل أيضاً: $e2');
              }
            }
          }

          ftthShowSnackBar(
            context,
            const SnackBar(
              content: Text('تم طباعة الوصل بنجاح! ✅'),
              backgroundColor: Colors.green,
            ),
          );
          debugPrint('✅ تم تحديث حالة الطباعة: مطبوع');
        } else {
          ftthShowSnackBar(
            context,
            const SnackBar(
              content: Text('فشل في طباعة الوصل! ❌'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في الطباعة: $e');
      if (mounted) {
        ftthShowErrorNotification(context, 'حدث خطأ أثناء الطباعة: $e');
      }
    } finally {
      // إنهاء حالة انتظار الطباعة
      if (mounted) {
        setState(() {
          _isPrinting = false;
        });
      }
    }
  }

  // تعريف قالب الواتساب الافتراضي
  String _whatsAppTemplate =
      '''\n==============================\n👋 مرحباً {customerName}\nالهاتف: {customerPhone}\n==============================\n تم : {operation}\n------------------------------\nالخطة: {planName}\nفترة الالتزام: {commitmentPeriod} شهر\nFBG: {fbg}\nFAT: {fat}\nتاريخ الانتهاء: {endDate}\nطريقة الدفع: {paymentMethod}\nالقيمة: {totalPrice}د.ع\n------------------------------\nالمحاسب: {activatedBy}\nتاريخ الوصل: {todayDate}\nالوقت: {todayTime}\n''';

  // دالة عرض نافذة كلمة المرور لتعديل القالب
  void _showPasswordDialog() {
    String input = '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.lock_outline),
            SizedBox(width: 8),
            Text('التحقق من كلمة المرور'),
          ],
        ),
        content: TextField(
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'أدخل كلمة المرور',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => input = v.trim(),
          onSubmitted: (_) {},
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              if (input == _templatePassword) {
                Navigator.of(context).pop();
                _showEditOptionsDialog();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('كلمة المرور غير صحيحة')),
                );
              }
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  // دالة عرض نافذة تعديل قالب الطباعة
  void _showPrintTemplateDialog() async {
    final template = await PrintTemplateStorage.loadTemplate();
    String companyName = template.companyName;
    String companySubtitle = template.companySubtitle;
    String footerMessage = template.footerMessage;
    String contactInfo = template.contactInfo;
    bool showCustomerInfo = template.showCustomerInfo;
    bool showServiceDetails = template.showServiceDetails;
    bool showPaymentDetails = template.showPaymentDetails;
    bool showAdditionalInfo = template.showAdditionalInfo;
    bool showContactInfo = template.showContactInfo;
    double fontSize = template.fontSize;
    bool boldHeaders = template.boldHeaders;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setStateDialog) {
          return AlertDialog(
            title: const Text('تعديل قالب الطباعة'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPrintSection(
                      'بيانات الرأس',
                      Icons.badge,
                      Colors.blue,
                      [
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'اسم الشركة',
                            border: OutlineInputBorder(),
                          ),
                          controller: TextEditingController(text: companyName),
                          onChanged: (v) => companyName = v,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'سطر فرعي',
                            border: OutlineInputBorder(),
                          ),
                          controller:
                              TextEditingController(text: companySubtitle),
                          onChanged: (v) => companySubtitle = v,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'معلومات الاتصال',
                            border: OutlineInputBorder(),
                          ),
                          controller: TextEditingController(text: contactInfo),
                          onChanged: (v) => contactInfo = v,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'رسالة التذييل',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                          controller:
                              TextEditingController(text: footerMessage),
                          onChanged: (v) => footerMessage = v,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildPrintSection(
                      'عناصر تُعرض',
                      Icons.visibility,
                      Colors.green,
                      [
                        CheckboxListTile(
                          value: showCustomerInfo,
                          onChanged: (v) =>
                              setStateDialog(() => showCustomerInfo = v!),
                          title: const Text('معلومات العميل'),
                          dense: true,
                        ),
                        CheckboxListTile(
                          value: showServiceDetails,
                          onChanged: (v) =>
                              setStateDialog(() => showServiceDetails = v!),
                          title: const Text('تفاصيل الخدمة'),
                          dense: true,
                        ),
                        CheckboxListTile(
                          value: showPaymentDetails,
                          onChanged: (v) =>
                              setStateDialog(() => showPaymentDetails = v!),
                          title: const Text('تفاصيل الدفع'),
                          dense: true,
                        ),
                        CheckboxListTile(
                          value: showAdditionalInfo,
                          onChanged: (v) =>
                              setStateDialog(() => showAdditionalInfo = v!),
                          title: const Text('معلومات إضافية'),
                          dense: true,
                        ),
                        CheckboxListTile(
                          value: showContactInfo,
                          onChanged: (v) =>
                              setStateDialog(() => showContactInfo = v!),
                          title: const Text('معلومات الاتصال'),
                          dense: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildPrintSection(
                      'الخط والتنسيق',
                      Icons.text_format,
                      Colors.orange,
                      [
                        Row(
                          children: [
                            const Text('حجم الخط:'),
                            Expanded(
                              child: Slider(
                                min: 8,
                                max: 20,
                                divisions: 12,
                                label: fontSize.toStringAsFixed(0),
                                value: fontSize,
                                onChanged: (v) =>
                                    setStateDialog(() => fontSize = v),
                              ),
                            ),
                            Text(fontSize.toStringAsFixed(0)),
                          ],
                        ),
                        SwitchListTile(
                          value: boldHeaders,
                          onChanged: (v) =>
                              setStateDialog(() => boldHeaders = v),
                          title: const Text('عناوين عريضة'),
                          dense: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  final def = PrintTemplateStorage.defaultTemplate;
                  setStateDialog(() {
                    companyName = def.companyName;
                    companySubtitle = def.companySubtitle;
                    footerMessage = def.footerMessage;
                    contactInfo = def.contactInfo;
                    showCustomerInfo = def.showCustomerInfo;
                    showServiceDetails = def.showServiceDetails;
                    showPaymentDetails = def.showPaymentDetails;
                    showAdditionalInfo = def.showAdditionalInfo;
                    showContactInfo = def.showContactInfo;
                    fontSize = def.fontSize;
                    boldHeaders = def.boldHeaders;
                  });
                },
                child: const Text('افتراضي'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              TextButton(
                onPressed: () {
                  _showPrintPreview(PrintTemplate(
                    companyName: companyName,
                    companySubtitle: companySubtitle,
                    footerMessage: footerMessage,
                    contactInfo: contactInfo,
                    showCustomerInfo: showCustomerInfo,
                    showServiceDetails: showServiceDetails,
                    showPaymentDetails: showPaymentDetails,
                    showAdditionalInfo: showAdditionalInfo,
                    showContactInfo: showContactInfo,
                    fontSize: fontSize,
                    boldHeaders: boldHeaders,
                  ));
                },
                child: const Text('معاينة'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final newTemplate = PrintTemplate(
                    companyName: companyName,
                    companySubtitle: companySubtitle,
                    footerMessage: footerMessage,
                    contactInfo: contactInfo,
                    showCustomerInfo: showCustomerInfo,
                    showServiceDetails: showServiceDetails,
                    showPaymentDetails: showPaymentDetails,
                    showAdditionalInfo: showAdditionalInfo,
                    showContactInfo: showContactInfo,
                    fontSize: fontSize,
                    boldHeaders: boldHeaders,
                  );
                  await PrintTemplateStorage.saveTemplate(newTemplate);
                  if (mounted) {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('تم حفظ القالب'),
                        backgroundColor: Colors.green));
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        });
      },
    );
  }

  // دالة مساعدة لبناء أقسام واجهة تعديل القالب
  Widget _buildPrintSection(
      String title, IconData icon, Color color, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  // دالة معاينة قالب الطباعة
  void _showPrintPreview(PrintTemplate template) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.preview, color: Colors.blue),
            SizedBox(width: 8),
            Text('معاينة قالب الطباعة'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // معلومات الشركة
                  if (template.boldHeaders) ...[
                    Text(
                      template.companyName,
                      style: TextStyle(
                        fontSize: template.fontSize + 4,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      template.companySubtitle,
                      style: TextStyle(
                        fontSize: template.fontSize,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    Text(
                      template.companyName,
                      style: TextStyle(fontSize: template.fontSize + 2),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      template.companySubtitle,
                      style: TextStyle(fontSize: template.fontSize),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  Divider(height: 20),

                  // معلومات العميل
                  if (template.showCustomerInfo) ...[
                    Text(
                      'معلومات العميل',
                      style: TextStyle(
                        fontSize: template.fontSize,
                        fontWeight: template.boldHeaders
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    Text(
                        'العميل: ${subscriptionInfo?.customerName ?? "مثال على الاسم"}'),
                    Text('الهاتف: ${widget.userPhone ?? "07701234567"}'),
                    SizedBox(height: 8),
                  ],

                  // تفاصيل الخدمة
                  if (template.showServiceDetails) ...[
                    Text(
                      'تفاصيل الخدمة',
                      style: TextStyle(
                        fontSize: template.fontSize,
                        fontWeight: template.boldHeaders
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    Text('نوع الخدمة: $selectedPlan'),
                    Text('فترة الالتزام: $selectedCommitmentPeriod شهر'),
                    SizedBox(height: 8),
                  ],

                  // تفاصيل الدفع
                  if (template.showPaymentDetails) ...[
                    Text(
                      'تفاصيل الدفع',
                      style: TextStyle(
                        fontSize: template.fontSize,
                        fontWeight: template.boldHeaders
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    Text(
                        'السعر الإجمالي: ${priceDetails?['totalPrice']?['value'] ?? "50000"} دينار'),
                    Text('طريقة الدفع: $selectedPaymentMethod'),
                    SizedBox(height: 8),
                  ],

                  // معلومات إضافية
                  if (template.showAdditionalInfo) ...[
                    Text(
                      'معلومات إضافية',
                      style: TextStyle(
                        fontSize: template.fontSize,
                        fontWeight: template.boldHeaders
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    Text(
                        'تاريخ العملية: ${DateTime.now().toString().split(' ')[0]}'),
                    Text('منفذ العملية: ${widget.activatedBy}'),
                    SizedBox(height: 8),
                  ],

                  Divider(height: 20),

                  // معلومات الاتصال
                  if (template.showContactInfo) ...[
                    Text(
                      template.contactInfo,
                      style: TextStyle(fontSize: template.fontSize - 1),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                  ],

                  // رسالة التذييل
                  Text(
                    template.footerMessage,
                    style: TextStyle(
                      fontSize: template.fontSize - 1,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showEditTemplateDialog() {
    final controller = TextEditingController(text: _whatsAppTemplate);
    // دالة مساعدة لإدراج نص عند موضع المؤشر
    void insertAtCursor(String text) {
      final selection = controller.selection;
      final fullText = controller.text;
      final start = selection.start >= 0 ? selection.start : fullText.length;
      final end = selection.end >= 0 ? selection.end : fullText.length;
      final newText = fullText.replaceRange(start, end, text);
      controller.text = newText;
      controller.selection = TextSelection.fromPosition(
        TextPosition(offset: start + text.length),
      );
    }

    // قائمة الرموز المتاحة للإدراج
    final List<String> availableTokens = const [
      'customerName',
      'operation',
      'planName',
      'commitmentPeriod',
      'totalPrice',
      'currency',
      'paymentMethod',
      'paymentType',
      'endDate',
      'activatedBy',
      'subscriptionId',
      'customerPhone',
      'todayDate',
      'todayTime',
      'fbg',
      'fat',
    ];

    // نماذج جاهزة للقوالب
    final Map<String, String> sampleTemplates = {
      'الأساسي (مطلوب)': '''==============================
👋 مرحباً {customerName}
الهاتف: {customerPhone}
==============================
 تم : {operation}
------------------------------
الخطة: {planName}
فترة الالتزام: {commitmentPeriod} شهر
 FBG: {fbg}
 FAT: {fat}
تاريخ الانتهاء: {endDate}
طريقة الدفع: {paymentMethod}
القيمة: {totalPrice}د.ع
------------------------------
المحاسب: {activatedBy}
تاريخ الوصل: {todayDate}
الوقت: {todayTime}''',
      'بسيط': '''👋 مرحباً {customerName}
تمت عملية: {operation}
الخطة: {planName} | المدة: {commitmentPeriod} شهر
 FBG: {fbg} | FAT: {fat}
المبلغ: {totalPrice} {currency}
الدفع: {paymentMethod}
ينتهي في: {endDate}
منفذ العملية: {activatedBy}''',
      'مفصل': '''==============================
👋 مرحباً {customerName}
==============================
العملية: {operation}
------------------------------
الخطة: {planName}
فترة الالتزام: {commitmentPeriod} شهر
القيمة: {totalPrice} {currency}
------------------------------
طريقة الدفع: {paymentMethod}
نوع الدفع: {paymentType}
------------------------------
 FBG: {fbg}
 FAT: {fat}
تاريخ الانتهاء: {endDate}
المشغل: {activatedBy}
رقم الاشتراك: {subscriptionId}
الهاتف: {customerPhone}
التاريخ: {todayDate} | الوقت: {todayTime}
==============================''',
      'قصير جداً': '''{operation} - {planName} ({commitmentPeriod} شهر)
{totalPrice} {currency} - {paymentMethod}''',
    };

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('تعديل قالب الرسالة'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'نماذج جاهزة',
                      icon: const Icon(Icons.article_outlined,
                          color: Colors.teal),
                      onSelected: (key) {
                        final sample = sampleTemplates[key];
                        if (sample != null) {
                          setStateDialog(() {
                            controller.text = sample;
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length),
                            );
                          });
                        }
                      },
                      itemBuilder: (context) => sampleTemplates.keys
                          .map((k) =>
                              PopupMenuItem<String>(value: k, child: Text(k)))
                          .toList(),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.remove_red_eye, color: Colors.blue),
                      tooltip: 'معاينة الرسالة',
                      onPressed: () {
                        final msg = _generateWhatsAppMessageWithTemplate(
                            controller.text);
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('معاينة رسالة الواتساب'),
                            content: SelectableText(msg),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('إغلاق'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'الرموز المتاحة (اضغط للإدراج):',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in availableTokens)
                      ActionChip(
                        label:
                            Text('{$t}', style: const TextStyle(fontSize: 12)),
                        onPressed: () =>
                            setStateDialog(() => insertAtCursor('{$t}')),
                        backgroundColor: Colors.grey.shade100,
                        avatar: const Icon(Icons.add, size: 16),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'قالب الرسالة',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setStateDialog(() {}),
                ),
                const SizedBox(height: 6),
                Text(
                  'تلميح: استخدم {customerName}، {planName}، {totalPrice} وغيرها. سيتم تجاهل الأسطر الفارغة تلقائيًا.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: false).pop(),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context, rootNavigator: false).pop();
                Future.microtask(() => _showEditOptionsDialog());
              },
              child: const Text('عودة'),
            ),
            TextButton(
              onPressed: () async {
                // حفظ القالب بدون طلب كلمة مرور (تم التحقق سابقًا)
                setState(() {
                  _whatsAppTemplate = controller.text;
                });
                await WhatsAppTemplateStorage.saveTemplate(controller.text);
                Navigator.of(context, rootNavigator: false).pop();

                // رسالة نجاح حفظ القالب
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ تم حفظ قالب الرسالة بنجاح'),
                    backgroundColor: Colors.blue,
                  ),
                );
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  // نافذة خيارات بعد إدخال كلمة المرور بنجاح
  void _showEditOptionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.settings),
            SizedBox(width: 8),
            Text('خيارات التعديل والإرسال'),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.chat_outlined, color: Colors.green),
                title: const Text('تعديل قالب الواتساب'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showEditTemplateDialog();
                },
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.print_outlined, color: Colors.purple),
                title: const Text('تعديل قالب الطابعة'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showPrintTemplateDialog();
                },
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.send, color: Colors.green),
                title: const Text('إرسال إلى الواتساب'),
                enabled: widget.hasWhatsAppPermission,
                onTap: () async {
                  Navigator.of(context).pop();
                  await _sendWhatsAppOnly();
                },
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.cloud_upload, color: Colors.orange),
                title: const Text('حفظ في الخادم'),
                subtitle: const Text('VPS'),
                enabled: widget.hasServerSavePermission,
                onTap: () async {
                  Navigator.of(context).pop();
                  await _saveOnlyToServer();
                },
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.password, color: Colors.indigo),
                title: const Text('تغيير كلمة المرور'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showChangePasswordDialog();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  // نافذة تغيير كلمة المرور
  void _showChangePasswordDialog() {
    String newPass = '';
    String confirm = '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.password),
            SizedBox(width: 8),
            Text('تغيير كلمة المرور'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور الجديدة',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => newPass = v.trim(),
            ),
            const SizedBox(height: 8),
            TextField(
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'تأكيد كلمة المرور',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => confirm = v.trim(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Future.microtask(() => _showEditOptionsDialog());
            },
            child: const Text('عودة'),
          ),
          ElevatedButton(
            onPressed: () {
              if (newPass.isEmpty || confirm.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('يرجى إدخال كلمة المرور الجديدة وتأكيدها')),
                );
                return;
              }
              if (newPass != confirm) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('كلمتا المرور غير متطابقتين')),
                );
                return;
              }
              setState(() {
                _templatePassword = newPass;
              });
              // حفظ كلمة المرور بشكل دائم
              TemplatePasswordStorage.savePassword(newPass);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ تم تغيير كلمة المرور بنجاح'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  String _generateWhatsAppMessageWithTemplate(String template) {
    if (subscriptionInfo == null || priceDetails == null) return '';

    final tokens = _buildWhatsAppTokenMap();
    String result = template;
    tokens.forEach((key, value) {
      result = result.replaceAll('{$key}', value ?? '');
    });
    return _cleanWhatsAppMessage(result);
  }

  Map<String, String?> _buildWhatsAppTokenMap() {
    final operationText =
        isNewSubscription ? 'شراء اشتراك جديد' : 'تجديد الاشتراك';
    final currency = (priceDetails!['totalPrice'] is Map &&
            priceDetails!['totalPrice']['currency'] != null)
        ? priceDetails!['totalPrice']['currency'].toString()
        : (priceDetails!['currency']?.toString() ?? 'IQD');
    final totalPrice = _formatNumber(_getFinalTotal().round());
    final phone = _getCustomerPhoneNumber();
    final now = DateTime.now();
    final todayDate = '${now.day}/${now.month}/${now.year}';
    final todayTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return {
      'customerName': subscriptionInfo?.customerName ?? '',
      'operation': operationText,
      'planName': selectedPlan,
      'commitmentPeriod': selectedCommitmentPeriod.toString(),
      'totalPrice': totalPrice,
      'currency': currency,
      'paymentMethod': selectedPaymentMethod,
      'paymentType': '', // غير مستخدم حالياً
      'endDate': _calculateEndDate(),
      'activatedBy': widget.activatedBy,
      'subscriptionId': widget.subscriptionId,
      'customerPhone': phone ?? '',
      'todayDate': todayDate,
      'todayTime': todayTime,
      'fbg': widget.fbgValue ?? widget.fdtDisplayValue ?? '',
      'fat': widget.fatValue ?? widget.fatDisplayValue ?? '',
    };
  }

  String _cleanWhatsAppMessage(String input) {
    // توحيد فواصل الأسطر وإزالة الأسطر الفارغة المكررة
    final lines =
        input.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final kept = <String>[];
    for (final l in lines) {
      final trimmed = l.trim();
      if (trimmed.isEmpty) continue; // تجاهل الأسطر الفارغة
      kept.add(l);
    }
    var msg = kept.join('\n');
    // تقليص التكرار الزائد للخطوط الفاصلة
    msg = msg.replaceAll(RegExp(r"\n{3,}"), '\n\n');
    return msg.trim();
  }

  /// Purchase subscription method
  Future<void> purchaseSubscription() async {
    if (subscriptionInfo == null || priceDetails == null) {
      setState(() {
        errorMessage = "معلومات الاشتراك أو الأسعار غير متوفرة";
      });
      return;
    }

    // تحقق من الرصيد حسب مصدر المحفظة المختار قبل الإرسال
    final double cost = _getFinalTotal();
    double available;
    if (_selectedWalletSource == 'customer') {
      available = customerWalletBalance;
    } else {
      available = walletBalance; // المحفظة الرئيسية (الشريك)
    }
    if (cost > available) {
      ftthShowSnackBar(
        context,
        SnackBar(
          content: Text('الرصيد غير كافٍ في المحفظة المحددة'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('جاري شراء الاشتراك...'),
              ],
            ),
          );
        },
      );

      debugPrint('🛒 بدء عملية شراء الاشتراك...');
      debugPrint('🆔 Subscription ID: ${widget.subscriptionId}');
      debugPrint('👤 Customer ID: ${widget.userId}');
      debugPrint('📦 Selected Plan: $selectedPlan');
      debugPrint('📅 Commitment Period: $selectedCommitmentPeriod');
      debugPrint('💰 Total Price: ${_asDouble(priceDetails!['totalPrice'])}');
      debugPrint('🛒 Sales Type Value: ${_getSalesTypeValue()}');

      // إعداد بيانات الطلب لشراء الاشتراك
      final requestBody = {
        'subscriptionId': widget.subscriptionId,
        'customerId': widget.userId,
        'bundleId': subscriptionInfo!.bundleId,
        'commitmentPeriodValue': selectedCommitmentPeriod,
        'planOperationType': 'PurchaseFromTrial',
        'services': [
          {'value': selectedPlan, 'type': 'Base'},
          {'value': 'IPTV', 'type': 'Vas'},
          {'value': 'PARENTAL_CONTROL', 'type': 'Vas'}
        ],
        'salesType': _getSalesTypeValue(), // استخدام القيمة الحقيقية من API
        'paymentMethod': selectedPaymentMethod,
        'walletSource':
            _selectedWalletSource == 'customer' ? 'customer' : 'partner',
      };

      debugPrint('📤 Request Body: ${jsonEncode(requestBody)}');

      // إرسال طلب شراء الاشتراك
      final response = await http.post(
        Uri.parse('https://admin.ftth.iq/api/subscriptions/purchase'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      debugPrint('📥 Purchase Response Status: ${response.statusCode}');
      debugPrint('📥 Purchase Response Body: ${response.body}');

      // Close loading indicator only (not the entire page)
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context, rootNavigator: false).pop();
      }

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        debugPrint('✅ تم شراء الاشتراك بنجاح');
        debugPrint('🔗 Payment URL: ${responseData['paymentUrl']}');
        debugPrint('🔢 Order Number: ${responseData['orderNumber']}');

        // حفظ البيانات في VPS بعد نجاح عملية الشراء
        try {
          await _saveToServer();
          debugPrint('✅ تم حفظ بيانات شراء الاشتراك في VPS');
        } catch (e) {
          debugPrint('❌ فشل في حفظ البيانات في VPS: $e');
          // لا نوقف العملية حتى لو فشل حفظ البيانات
        }

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ تم شراء الاشتراك بنجاح!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }

        // إرسال رسالة WhatsApp تلقائياً بعد نجاح العملية
        if (widget.hasWhatsAppPermission) {
          await _sendAutoWhatsAppMessage();
        }

        // تحديث معلومات الاشتراك بعد الشراء
        await fetchSubscriptionDetails();
      } else {
        throw Exception(
            'فشل في شراء الاشتراك: ${response.statusCode}\n${response.body}');
      }
    } catch (e) {
      // Close loading indicator if still open (not the entire page)
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context, rootNavigator: false).pop();
      }

      debugPrint('❌ خطأ في شراء الاشتراك: $e');

      // Show error message
      if (mounted) {
        setState(() {
          errorMessage = 'حدث خطأ في شراء الاشتراك: $e';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ حدث خطأ في شراء الاشتراك: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// جلب بيانات العميل من API الجديد
  Future<Map<String, dynamic>?> fetchCustomerDetails(String customerId) async {
    try {
      debugPrint('👤 جلب بيانات العميل من API...');
      debugPrint('🔗 URL: https://admin.ftth.iq/api/customers/$customerId');

      final response = await http.get(
        Uri.parse('https://admin.ftth.iq/api/customers/$customerId'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      );

      debugPrint('📥 Customer Response Status: ${response.statusCode}');
      debugPrint('📥 Customer Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ تم جلب بيانات العميل بنجاح');

        final customerModel = data['model'];
        if (customerModel != null) {
          debugPrint(
              '📞 رقم الهاتف: ${customerModel['primaryContact']?['mobile']}');
          debugPrint(
              '📧 البريد الإلكتروني: ${customerModel['primaryContact']?['email']}');
          debugPrint(
              '🏠 العنوان: ${customerModel['addresses']?.isNotEmpty == true ? customerModel['addresses'][0]['displayValue'] : 'غير متوفر'}');
          debugPrint(
              '🆔 رقم الهوية: ${customerModel['nationalIdCard']?['idNumber']}');

          return customerModel;
        }
      } else {
        throw Exception('فشل في جلب بيانات العميل: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب بيانات العميل: $e');
    }

    return null;
  }

  /// جلب مهام العميل
  Future<List<dynamic>> fetchCustomerTasks(String customerId) async {
    try {
      debugPrint('📋 جلب مهام العميل...');
      debugPrint(
          '🔗 URL: https://admin.ftth.iq/api/customers/$customerId/tasks');

      final response = await http.get(
        Uri.parse('https://admin.ftth.iq/api/customers/$customerId/tasks'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      );

      debugPrint('📥 Tasks Response Status: ${response.statusCode}');
      debugPrint('📥 Tasks Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ تم جلب مهام العميل بنجاح');
        debugPrint('📊 عدد المهام: ${data['totalCount']}');

        return data['items'] ?? [];
      } else {
        throw Exception('فشل في جلب مهام العميل: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب مهام العميل: $e');
      return [];
    }
  }

  /// جلب التغييرات المجدولة للاشتراك/العميل (استخدام توثيقي وتحليلي)
  Future<List<dynamic>> fetchScheduledChanges(String customerId) async {
    try {
      debugPrint('🗓️ جلب التغييرات المجدولة...');
      final url = 'https://admin.ftth.iq/api/customers/'
          '$customerId/subscriptions/scheduled-changes';
      debugPrint('🔗 URL: $url');
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));
      debugPrint('📥 Scheduled Changes Status: ${response.statusCode}');
      if (response.statusCode == 200) {
        debugPrint('📥 Scheduled Changes Body: ${response.body}');
        final data = jsonDecode(response.body);
        return (data['items'] as List?) ?? [];
      }
    } catch (e) {
      debugPrint('❌ خطأ fetchScheduledChanges: $e');
    }
    return [];
  }

  /// تنفيذ تمديد (Renew) بمحاولات fallback لتقليل أخطاء 500
  Future<void> extendSubscription() async {
    // تحقق مبدئي من البيانات
    if (subscriptionInfo == null || priceDetails == null) {
      ftthShowSnackBar(
        context,
        const SnackBar(content: Text('يجب حساب السعر أولاً')),
      );
      return;
    }
    if (isNewSubscription) {
      ftthShowSnackBar(
        context,
        const SnackBar(content: Text('لا يمكن تمديد اشتراك تجريبي، قم بشرائه')),
      );
      return;
    }
    if (selectedPlan != subscriptionInfo!.currentPlan ||
        selectedCommitmentPeriod != subscriptionInfo!.commitmentPeriod) {
      ftthShowSnackBar(
        context,
        const SnackBar(content: Text('للتجديد اجعل الخطة والمدة نفس الحالية')),
      );
      return;
    }

    // التحقق من الرصيد
    final total = _getFinalTotal();
    final available = _selectedWalletSource == 'customer'
        ? customerWalletBalance
        : walletBalance;
    if (total > available) {
      ftthShowSnackBar(
        context,
        const SnackBar(content: Text('الرصيد غير كافٍ')),
      );
      return;
    }

    // دالة بناء الجسم مع خيارات وتقليل التعقيد + تغيير نوع العملية كخيار أخير
    Map<String, dynamic> buildBody({
      required bool includeVas,
      required bool includeWalletSource,
      required String opType,
      String? overridePlanOp,
      bool includeSalesType = true,
      bool forceChangeType = false,
      bool addChangeType = true, // يسمح بإزالة changeType في تجربة خاصة
      bool includeSubscriptionId = true,
      bool forExtendEndpoint = false,
      bool useAltCommitKey =
          false, // استخدام commitmentPeriod بدل commitmentPeriodValue أو إضافته
    }) {
      final services = <Map<String, String>>[
        {'value': selectedPlan.toString(), 'type': 'Base'},
        if (includeVas) {'value': 'IPTV', 'type': 'Vas'},
        if (includeVas) {'value': 'PARENTAL_CONTROL', 'type': 'Vas'},
      ];
      final body = <String, dynamic>{
        'bundleId': subscriptionInfo!.bundleId,
        'commitmentPeriodValue': selectedCommitmentPeriod,
        'services': services,
      };
      if (useAltCommitKey) {
        // بعض الـ APIs أحياناً تستخدم commitmentPeriod بدلاً من commitmentPeriodValue
        body['commitmentPeriod'] = selectedCommitmentPeriod;
      }
      if (!forExtendEndpoint) {
        body['planOperationType'] = overridePlanOp ?? opType;
      }
      if (includeSubscriptionId) {
        body['subscriptionId'] =
            widget.subscriptionId; // أحياناً API يحتاجه صراحة
      }
      if (includeSalesType) {
        body['salesType'] = _getSalesTypeValue();
      }
      if (includeWalletSource) {
        body['walletSource'] =
            _selectedWalletSource == 'customer' ? 'customer' : 'partner';
      }
      // إضافة changeType=1 عند التمديد الفوري
      if (addChangeType &&
          (opType == 'ImmediateExtend' ||
              opType == 'Extend' ||
              forceChangeType)) {
        body['changeType'] = 1; // مطابق لما ظهر في calculate-price
      }
      return body;
    }

    // جلب الأفعال المسموحة قبل المحاولات لتقليل محاولات غير صالحة
    bool allowRenew = true; // يشمل Extend
    bool allowChange = true;
    bool allowExtendExplicit = false;
    try {
      Map<String, dynamic>? data;
      if (_prefetchedAllowedActions != null) {
        debugPrint('🔄 استخدام allowed-actions المسبقة بدون جلب جديد');
        data = _prefetchedAllowedActions;
      } else {
        final allowedUrl = Uri.parse(
            'https://admin.ftth.iq/api/subscriptions/allowed-actions?subscriptionIds=${widget.subscriptionId}&customerId=${widget.userId}');
        debugPrint('🔍 Fetch allowed-actions: $allowedUrl');
        final allowedResp = await http.get(
          allowedUrl,
          headers: {
            'Authorization': 'Bearer ${widget.authToken}',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 15));
        debugPrint('📥 allowed-actions Status: ${allowedResp.statusCode}');
        if (allowedResp.statusCode == 200) {
          data = jsonDecode(allowedResp.body);
        } else {
          debugPrint('⚠️ تعذر جلب allowed-actions: ${allowedResp.body}');
        }
      }
      if (data != null) {
        List actions = [];
        if (data['items'] is List && (data['items'] as List).isNotEmpty) {
          final first = (data['items'] as List).first;
          if (first is Map && first['actions'] is List) {
            actions = first['actions'];
          }
        } else if (data['actions'] is List) {
          actions = data['actions'];
        }
        // API يعيد: ImmediateExtend, ImmediateChange, ScheduledExtend, ScheduledChange, Renew
        allowRenew = actions.contains('Renew');
        // نتحقق من ImmediateExtend أو ScheduledExtend أو Extend (للتوافق القديم)
        allowExtendExplicit = actions.contains('ImmediateExtend') ||
            actions.contains('ScheduledExtend') ||
            actions.contains('Extend');
        // نتحقق من ImmediateChange أو ScheduledChange أو Change (للتوافق القديم)
        allowChange = actions.contains('ImmediateChange') ||
            actions.contains('ScheduledChange') ||
            actions.contains('Change');
        if (!allowRenew && allowExtendExplicit) {
          allowRenew = true; // نعوض غياب Renew بوجود ImmediateExtend
          debugPrint('ℹ️ استنتاج السماح بالتمديد من وجود ImmediateExtend');
        }
        debugPrint(
            '✅ allowed-actions parsed: Renew=$allowRenew Extend=$allowExtendExplicit Change=$allowChange');
      }
    } catch (e) {
      debugPrint('⚠️ استثناء allowed-actions: $e');
    }

    // فحص وجود تغييرات مجدولة قد تمنع التمديد (مثلاً Pending Change)
    try {
      final sched = await fetchScheduledChanges(widget.userId);
      final blocking = sched.firstWhere(
        (e) =>
            (e is Map) &&
            (e['subscriptionId'].toString() ==
                widget.subscriptionId.toString()) &&
            (e['status']?.toString().toLowerCase() == 'pending'),
        orElse: () => null,
      );
      if (blocking != null) {
        debugPrint('⛔ هناك تغيير مجدول Pending يمنع التمديد: $blocking');
        ftthShowSnackBar(
          context,
          const SnackBar(
            content: Text('هناك تغيير مجدول قيد الانتظار يمنع التمديد حالياً'),
            backgroundColor: Colors.orange,
          ),
        );
        // نواصل لكن نحاول بمحاولات Change لاحقاً كحل أخير
      }
    } catch (e) {
      debugPrint('⚠️ فشل فحص التغييرات المجدولة: $e');
    }

    // إعادة ترتيب المحاولات لتبدأ بأبسط جسم وتقليل التعقيد أولاً (BaseOnly فقط)
    // منطق المحاولات:
    // R1: Renew BaseOnly + walletSource + salesType
    // R2: Renew BaseOnly + walletSource (بدون salesType)
    // R3: Renew BaseOnly بدون walletSource + salesType
    // R4: Renew BaseOnly بدون walletSource + بدون salesType
    // R5: Renew +VAS (قد تكون مطلوبة) + walletSource + salesType
    // R6: Renew +VAS بدون walletSource + salesType
    // ثم محاولات ImmediateChange مماثلة إذا مسموح
    var attempts = <Map<String, dynamic>>[
      // محاولات مبكرة باستخدام endpoint /extend (قد يكون فعّال بدون planOperationType)
      if (allowRenew || allowExtendExplicit)
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'ImmediateExtend',
          'includeSalesType': true,
          'addChangeType': true,
          'useExtendEndpoint': true,
          'note': 'X1 /extend BaseOnly +wallet +salesType +changeType'
        },
      if (allowRenew || allowExtendExplicit)
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'ImmediateExtend',
          'includeSalesType': true,
          'addChangeType': false,
          'useExtendEndpoint': true,
          'note': 'X1b /extend BaseOnly +wallet +salesType NO changeType'
        },
      // نضيف محاولة مع changeType وأخرى بدونه مبكراً للتحقق من حساسية الحقل
      if (allowRenew || allowExtendExplicit)
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'ImmediateExtend',
          'includeSalesType': true,
          'addChangeType': true,
          'note': 'E1 ImmediateExtend BaseOnly +wallet +salesType +changeType'
        },
      if (allowRenew || allowExtendExplicit)
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'ImmediateExtend',
          'includeSalesType': true,
          'addChangeType': false,
          'note':
              'E1b ImmediateExtend BaseOnly +wallet +salesType NO changeType'
        },
      if (allowRenew || allowExtendExplicit)
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'ImmediateExtend',
          'includeSalesType': false,
          'addChangeType': true,
          'note': 'E2 ImmediateExtend BaseOnly +wallet NO salesType +changeType'
        },
      if (allowRenew || allowExtendExplicit)
        {
          'includeVas': false,
          'includeWalletSource': false,
          'opType': 'ImmediateExtend',
          'includeSalesType': true,
          'addChangeType': true,
          'note': 'E3 ImmediateExtend BaseOnly NO wallet +salesType +changeType'
        },
      if (allowRenew || allowExtendExplicit)
        {
          'includeVas': false,
          'includeWalletSource': false,
          'opType': 'ImmediateExtend',
          'includeSalesType': false,
          'addChangeType': true,
          'note':
              'E4 ImmediateExtend BaseOnly NO wallet NO salesType +changeType'
        },
      if (allowRenew || allowExtendExplicit)
        {
          'includeVas': true,
          'includeWalletSource': true,
          'opType': 'ImmediateExtend',
          'includeSalesType': true,
          'addChangeType': true,
          'note': 'E5 ImmediateExtend +VAS +wallet +salesType +changeType'
        },
      if (allowRenew || allowExtendExplicit)
        {
          'includeVas': true,
          'includeWalletSource': false,
          'opType': 'ImmediateExtend',
          'includeSalesType': true,
          'addChangeType': true,
          'note': 'E6 ImmediateExtend +VAS NO wallet +salesType +changeType'
        },
      // محاولة Renew
      if (allowRenew)
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'Renew',
          'includeSalesType': true,
          'addChangeType': true,
          'note': 'R1 Renew BaseOnly +wallet +salesType +changeType'
        },
      if (allowChange)
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'ImmediateChange',
          'includeSalesType': true,
          'note': 'C1 ImmediateChange BaseOnly +wallet +salesType'
        },
      if (allowChange)
        {
          'includeVas': false,
          'includeWalletSource': false,
          'opType': 'ImmediateChange',
          'includeSalesType': true,
          'note': 'C2 ImmediateChange BaseOnly NO wallet +salesType'
        },
      if (allowChange)
        {
          'includeVas': false,
          'includeWalletSource': false,
          'opType': 'ImmediateChange',
          'includeSalesType': false,
          'note': 'C3 ImmediateChange BaseOnly NO wallet NO salesType'
        },
    ];

    if (attempts.isEmpty) {
      debugPrint(
          '⚠️ لم يتم توليد محاولات من allowed-actions، إضافة ImmediateExtend و ImmediateChange افتراضية.');
      attempts = [
        // 1) محاولات /extend (قد يقبلها السيرفر بدون planOperationType) مع تنويعات
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'ImmediateExtend',
          'includeSalesType': true,
          'addChangeType': true,
          'useExtendEndpoint': true,
          'note': 'FB1 /extend BaseOnly +wallet +salesType +changeType'
        },
        {
          'includeVas': false,
          'includeWalletSource': false,
          'opType': 'ImmediateExtend',
          'includeSalesType': true,
          'addChangeType': true,
          'useExtendEndpoint': true,
          'note': 'FB2 /extend BaseOnly NO wallet +salesType +changeType'
        },
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'ImmediateExtend',
          'includeSalesType': true,
          'addChangeType': false,
          'useExtendEndpoint': true,
          'note': 'FB3 /extend BaseOnly +wallet +salesType NO changeType'
        },
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'ImmediateExtend',
          'includeSalesType': false,
          'addChangeType': true,
          'useExtendEndpoint': true,
          'note': 'FB4 /extend BaseOnly +wallet NO salesType +changeType'
        },
        // 2) محاولات change (ImmediateExtend) مع planOperationType
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'ImmediateExtend',
          'includeSalesType': true,
          'addChangeType': true,
          'note':
              'FB5 change ImmediateExtend BaseOnly +wallet +salesType +changeType'
        },
        {
          'includeVas': false,
          'includeWalletSource': false,
          'opType': 'ImmediateExtend',
          'includeSalesType': true,
          'addChangeType': true,
          'note':
              'FB6 change ImmediateExtend BaseOnly NO wallet +salesType +changeType'
        },
        // 3) Renew variations
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'Renew',
          'includeSalesType': true,
          'addChangeType': true,
          'note': 'FB7 Renew BaseOnly +wallet +salesType +changeType'
        },
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'Renew',
          'includeSalesType': true,
          'addChangeType': false,
          'note': 'FB8 Renew BaseOnly +wallet +salesType NO changeType'
        },
        {
          'includeVas': false,
          'includeWalletSource': false,
          'opType': 'Renew',
          'includeSalesType': true,
          'addChangeType': true,
          'note': 'FB9 Renew BaseOnly NO wallet +salesType +changeType'
        },
        // 4) ImmediateChange fallback نهائي بدون salesType
        {
          'includeVas': false,
          'includeWalletSource': false,
          'opType': 'ImmediateChange',
          'includeSalesType': false,
          'addChangeType': false,
          'note': 'FB10 ImmediateChange BaseOnly NO wallet NO salesType'
        },
        // 5) محاولات إضافية متقدمة لاستكشاف اختلاف أسماء الحقول أو حساسية التواجد
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'ImmediateExtend',
          'includeSalesType': true,
          'addChangeType': true,
          'useExtendEndpoint': true,
          'useAltCommitKey': true,
          'note':
              'FB11 /extend BaseOnly +wallet +salesType +changeType +altCommitKey'
        },
        {
          'includeVas': false,
          'includeWalletSource': false,
          'opType': 'ImmediateExtend',
          'includeSalesType': true,
          'addChangeType': true,
          'useExtendEndpoint': true,
          'useAltCommitKey': true,
          'note':
              'FB12 /extend BaseOnly NO wallet +salesType +changeType +altCommitKey'
        },
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'Renew',
          'includeSalesType': true,
          'addChangeType': true,
          'useExtendEndpoint': true,
          'useAltCommitKey': true,
          'note':
              'FB13 /extend(Renew) BaseOnly +wallet +salesType +changeType +altCommitKey'
        },
        {
          'includeVas': false,
          'includeWalletSource': false,
          'opType': 'Renew',
          'includeSalesType': true,
          'addChangeType': true,
          'useExtendEndpoint': true,
          'useAltCommitKey': true,
          'note':
              'FB14 /extend(Renew) BaseOnly NO wallet +salesType +changeType +altCommitKey'
        },
        {
          'includeVas': false,
          'includeWalletSource': true,
          'opType': 'ImmediateChange',
          'includeSalesType': true,
          'addChangeType': true,
          'useAltCommitKey': true,
          'note':
              'FB15 ImmediateChange BaseOnly +wallet +salesType +changeType +altCommitKey'
        },
        {
          'includeVas': false,
          'includeWalletSource': false,
          'opType': 'ImmediateChange',
          'includeSalesType': true,
          'addChangeType': true,
          'useAltCommitKey': true,
          'note':
              'FB16 ImmediateChange BaseOnly NO wallet +salesType +changeType +altCommitKey'
        },
      ];
    }
    debugPrint(
        '🧪 عدد المحاولات النهائي: ${attempts.length} -> ${attempts.map((a) => a['note']).toList()}');

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: SizedBox(
            width: 230,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 14),
                Expanded(child: Text('جار التمديد...')),
              ],
            ),
          ),
        ),
      );
    }

    http.Response? lastResponse;
    Object? lastError;
    Map<String, dynamic>? usedAttempt;
    String? lastRequestId;

    final attemptStatuses = <String>[]; // لتشخيص السلسلة
    for (final attempt in attempts) {
      usedAttempt = attempt;
      final body = buildBody(
        includeVas: attempt['includeVas'] as bool,
        includeWalletSource: attempt['includeWalletSource'] as bool,
        opType: attempt['opType'] as String,
        overridePlanOp: attempt['overridePlanOp'] as String?,
        forceChangeType: (attempt['forceChangeType'] as bool?) ?? false,
        includeSalesType: attempt['includeSalesType'] as bool,
        addChangeType: (attempt['addChangeType'] as bool?) ?? true,
        includeSubscriptionId:
            (attempt['includeSubscriptionId'] as bool?) ?? true,
        forExtendEndpoint: attempt['useExtendEndpoint'] == true,
        useAltCommitKey: attempt['useAltCommitKey'] == true,
      );
      final idx = attempts.indexOf(attempt) + 1;
      final endpoint =
          attempt['useExtendEndpoint'] == true ? 'extend' : 'change';
      debugPrint(
          '🚀 محاولة تمديد ($idx/${attempts.length}) ${attempt['note']} endpoint=$endpoint opField=${body['planOperationType']} includeVas=${attempt['includeVas']} wallet=${attempt['includeWalletSource']} salesType=${attempt['includeSalesType']} changeType=${body['changeType']} subIdField=${body.containsKey('subscriptionId')}');
      debugPrint('📤 Extend Body => ${jsonEncode(body)}');
      try {
        final url = attempt['useExtendEndpoint'] == true
            ? 'https://admin.ftth.iq/api/subscriptions/${widget.subscriptionId}/extend'
            : 'https://admin.ftth.iq/api/subscriptions/${widget.subscriptionId}/change';
        final resp = await http
            .post(
              Uri.parse(url),
              headers: {
                'Authorization': 'Bearer ${widget.authToken}',
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 25));
        lastResponse = resp;
        lastRequestId = resp.headers['x-request-id'] ??
            resp.headers['request-id'] ??
            resp.headers['x-requestid'];
        final errorCode = resp.headers['x-error-code'] ??
            resp.headers['x-errorcode'] ??
            resp.headers['error-code'];
        final errorMessageHeader = resp.headers['x-error-message'];
        debugPrint(
            '📥 Extend Status: ${resp.statusCode} requestId=$lastRequestId errorCode=$errorCode headerMsg=$errorMessageHeader');
        debugPrint('📥 Extend Body: ${resp.body}');
        attemptStatuses.add(
            '(${attempt['note']})=>${resp.statusCode}${errorCode != null ? '/$errorCode' : ''}');

        if (resp.statusCode == 200) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context, rootNavigator: false).pop();
          }
          final data = jsonDecode(resp.body);
          debugPrint(
              '✅ تمديد ناجح requestId=$lastRequestId paymentUrl=${data['paymentUrl']} order=${data['orderNumber']}');
          ftthShowSnackBar(
            context,
            SnackBar(
              content: Text(
                  'تم تمديد الاشتراك بنجاح (محاولة $idx) | خطة: $selectedPlan | مدة: $selectedCommitmentPeriod شهر'),
              backgroundColor: Colors.green,
            ),
          );
          try {
            await fetchCustomerDetails(widget.userId);
          } catch (_) {}
          try {
            await fetchCustomerTasks(widget.userId);
          } catch (_) {}
          try {
            await fetchScheduledChanges(widget.userId);
          } catch (_) {}
          if (widget.hasServerSavePermission) {
            try {
              await _saveToServer();
            } catch (e) {
              debugPrint('⚠️ Sheets: $e');
            }
          }
          if (widget.hasWhatsAppPermission) {
            try {
              await _sendAutoWhatsAppMessage();
            } catch (e) {
              debugPrint('⚠️ WhatsApp: $e');
            }
          }
          await fetchSubscriptionDetails();
          return;
        }
      } catch (e) {
        lastError = e;
        debugPrint('❌ استثناء أثناء محاولة التمديد: $e');
      }
    }

    // فشل كل المحاولات
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context, rootNavigator: false).pop();
    }
    String failMsg = 'فشل التمديد بعد ${attempts.length} محاولات';
    if (lastResponse != null) {
      failMsg += '\nآخر حالة: ${lastResponse.statusCode}';
      try {
        final d = jsonDecode(lastResponse.body);
        failMsg += '\n${d['message'] ?? d['error'] ?? ''}';
      } catch (_) {}
      if (lastRequestId != null) failMsg += '\nrequestId=$lastRequestId';
      final ec = lastResponse.headers['x-error-code'] ??
          lastResponse.headers['error-code'];
      if (ec != null) failMsg += '\nerrorCode=$ec';
    } else if (lastError != null) {
      failMsg += '\nاستثناء: $lastError';
    }
    failMsg += '\nTrace: ${attemptStatuses.join(' -> ')}';
    debugPrint('❌ $failMsg | usedAttempt=$usedAttempt');
    ftthShowSnackBar(
      context,
      SnackBar(content: Text(failMsg), backgroundColor: Colors.red),
    );
    setState(() => errorMessage = failMsg);
  }

  /// Change subscription method مع حفظ أرصدة المحفظة قبل العملية
  Future<void> changeSubscription() async {
    if (subscriptionInfo == null || priceDetails == null) {
      setState(() => errorMessage = 'معلومات الاشتراك أو الأسعار غير متوفرة');
      return;
    }

    // حفظ رصيد المحفظة قبل العملية (مرة واحدة فقط)
    if (partnerWalletBalanceBefore == 0.0) {
      partnerWalletBalanceBefore = walletBalance;
      debugPrint(
          '💰 حفظ رصيد محفظة الشريك قبل العملية: ${partnerWalletBalanceBefore.toStringAsFixed(2)}');
    }
    if (customerWalletBalanceBefore == 0.0) {
      customerWalletBalanceBefore = customerWalletBalance;
      debugPrint(
          '💰 حفظ رصيد محفظة العميل قبل العملية: ${customerWalletBalanceBefore.toStringAsFixed(2)}');
    }

    // التحقق من الرصيد حسب المصدر المختار
    final double cost = _getFinalTotal();
    final double available = _selectedWalletSource == 'customer'
        ? customerWalletBalance
        : walletBalance;
    if (cost > available) {
      ftthShowSnackBar(
        context,
        const SnackBar(
          content: Text('الرصيد غير كافٍ في المحفظة المحددة'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // دالة بناء جسم الطلب - مطابقة للموقع الرسمي تماماً
    // الصيغة الصحيحة من الموقع:
    // {
    //   "simulatedPrice": 65000,
    //   "bundleId": "FTTH_BASIC",
    //   "services": [{"value": "FIBER 75", "type": "Base"}, ...],
    //   "commitmentPeriodValue": 1,
    //   "salesType": 0,
    //   "paymentDetails": {"walletSource": "Partner", "paymentMethod": "Wallet"},
    //   "changeType": 1
    // }
    // ملاحظة مهمة: لا يوجد planOperationType في الطلب الناجح!
    Map<String, dynamic> buildBody() {
      final services = [
        {'value': selectedPlan, 'type': 'Base'},
        {'value': 'IPTV', 'type': 'Vas'},
        {'value': 'PARENTAL_CONTROL', 'type': 'Vas'},
      ];

      // الحصول على السعر المحسوب من priceDetails
      final simulatedPrice = priceDetails?['finalPrice'] ??
          priceDetails?['totalAmountWithVat'] ??
          priceDetails?['totalAmount'] ??
          _getFinalTotal();

      // تحديد walletSource - الموقع يستخدم "Partner" بحرف P كبير
      final walletSource =
          _selectedWalletSource == 'customer' ? 'Customer' : 'Partner';

      final body = <String, dynamic>{
        'simulatedPrice':
            simulatedPrice is double ? simulatedPrice.toInt() : simulatedPrice,
        'bundleId': subscriptionInfo!.bundleId,
        'services': services,
        'commitmentPeriodValue': selectedCommitmentPeriod,
        'salesType': _getSalesTypeValue(),
        'paymentDetails': {
          'walletSource': walletSource,
          'paymentMethod': 'Wallet',
        },
        'changeType': 1,
      };

      return body;
    }

    // محاولات متعددة مع استراتيجيات fallback لخطأ 500
    // المحاولة الأولى تستخدم نفس صيغة الموقع الرسمي (Extend + changeType=1)
    // إظهار مؤشر انتظار
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: SizedBox(
            width: 220,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Expanded(child: Text('تنفيذ العملية...')),
              ],
            ),
          ),
        ),
      );
    }

    http.Response? lastResponse;
    Object? lastError;

    // بناء الطلب مرة واحدة بالصيغة الصحيحة
    final body = buildBody();
    debugPrint('🔄 تنفيذ عملية التجديد/التغيير...');
    debugPrint('📤 Body: ${jsonEncode(body)}');

    try {
      final resp = await http
          .post(
            Uri.parse(
                'https://admin.ftth.iq/api/subscriptions/${widget.subscriptionId}/change'),
            headers: {
              'Authorization': 'Bearer ${widget.authToken}',
              'Content-Type': 'application/json',
              'Accept': 'application/json, text/plain, */*',
              'x-client-app': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
              'x-user-role': '0',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      lastResponse = resp;
      final requestId = resp.headers['requestid'];
      debugPrint('📥 Status: ${resp.statusCode} (requestId=$requestId)');
      debugPrint('📥 Body: ${resp.body}');

      if (resp.statusCode == 200) {
        // نجاح
        final responseData = jsonDecode(resp.body);
        final opText =
            isNewSubscription ? 'شراء الاشتراك' : 'تجديد/تغيير الاشتراك';

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تم $opText بنجاح ✅',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }

        debugPrint('✅ Response Data: $responseData');
        // حفظ في VPS
        if (widget.hasServerSavePermission) {
          try {
            await _saveToServer();
          } catch (e) {
            debugPrint('⚠️ فشل حفظ VPS: $e');
          }
        }
        // إرسال واتساب
        if (widget.hasWhatsAppPermission) {
          try {
            await _sendAutoWhatsAppMessage();
          } catch (e) {
            debugPrint('⚠️ فشل واتساب: $e');
          }
        }
        await fetchSubscriptionDetails();
        // إغلاق المؤشر
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context, rootNavigator: false).pop();
        }
        return; // نجاح
      }
    } catch (e) {
      lastError = e;
      debugPrint('❌ خطأ شبكة/مهلة: $e');
    }

    // فشل العملية
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context, rootNavigator: false).pop();
    }

    String failMsg = 'فشل تنفيذ العملية';
    if (lastResponse != null) {
      failMsg += ' (HTTP ${lastResponse.statusCode})';
      final rid = lastResponse.headers['requestid'];
      if (rid != null) failMsg += ' | RequestId: $rid';
      try {
        final data = jsonDecode(lastResponse.body);
        final msg = data['message'] ?? data['error'];
        if (msg != null) failMsg += '\n$msg';
      } catch (_) {}
    } else if (lastError != null) {
      failMsg += ': $lastError';
    }

    debugPrint('❌ فشل: $failMsg');
    setState(() => errorMessage = failMsg);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failMsg, style: const TextStyle(fontSize: 13)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// حفظ البيانات في VPS (الحفظ الأساسي والوحيد)
  Future<void> _saveToServer() async {
    debugPrint('🚀 بدء حفظ البيانات في VPS - Current States:');
    debugPrint('  🖨️ isPrinted: $isPrinted');
    debugPrint('  📱 isWhatsAppSent: $isWhatsAppSent');
    debugPrint('  🆔 sessionId: $sessionId');

    if (subscriptionInfo == null || priceDetails == null) {
      debugPrint('❌ معلومات الاشتراك أو الأسعار غير متوفرة');
      throw Exception('معلومات الاشتراك أو الأسعار غير متوفرة');
    }

    try {
      debugPrint('🔵 بدء حفظ البيانات في VPS...');

      // تحديد نوع العملية
      final bool isRenewal = !isNewSubscription &&
          subscriptionInfo != null &&
          selectedPlan == subscriptionInfo!.currentPlan &&
          selectedCommitmentPeriod == subscriptionInfo!.commitmentPeriod;

      final operationType =
          isNewSubscription ? 'purchase' : (isRenewal ? 'renewal' : 'change');

      // حساب المبالغ
      final int chargedAmountInt = _getFinalTotal().round();
      final bool usingTeamMemberWallet = hasTeamMemberWallet;
      final double rawBeforeWallet =
          usingTeamMemberWallet ? teamMemberWalletBalance : walletBalance;
      final int walletBeforeInt = rawBeforeWallet.round();
      final int walletAfterInt = walletBeforeInt - chargedAmountInt;

      final currentDateTime = DateTime.now();
      final formattedDate =
          '${currentDateTime.day}/${currentDateTime.month}/${currentDateTime.year}';
      final formattedTime =
          '${currentDateTime.hour.toString().padLeft(2, '0')}:${currentDateTime.minute.toString().padLeft(2, '0')}';

      // التأكد من أن sessionId ليس فارغ
      if (sessionId.isEmpty) {
        sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
        debugPrint('⚠️ تم إنشاء sessionId جديد: $sessionId');
      }

      // جلب بيانات العميل
      final customerData = await fetchCustomerDetails(widget.userId);
      final customerPhone = customerData?['primaryContact']?['mobile'] ??
          widget.userPhone ??
          'غير متوفر';

      final logId = await SubscriptionLogsService.instance.saveSubscriptionLog(
        // معلومات العميل
        customerId: subscriptionInfo!.customerId,
        customerName: subscriptionInfo!.customerName,
        phoneNumber: customerPhone,
        // معلومات الاشتراك
        subscriptionId: widget.subscriptionId,
        planName: selectedPlan,
        planPrice: chargedAmountInt.toDouble(),
        commitmentPeriod: selectedCommitmentPeriod,
        bundleId: subscriptionInfo!.bundleId,
        currentStatus: subscriptionInfo!.status,
        deviceUsername: subscriptionInfo!.deviceUsername,
        // معلومات العملية
        operationType: operationType,
        activatedBy: widget.activatedBy,
        activationDate: currentDateTime,
        activationTime: formattedTime,
        sessionId: sessionId,
        // معلومات الموقع
        zoneId: subscriptionInfo!.zoneId,
        zoneName: null,
        fbgInfo: widget.fbgValue ?? widget.fdtDisplayValue,
        fatInfo: widget.fatDisplayValue ?? widget.fatValue,
        fdtInfo: widget.fdtDisplayValue,
        // معلومات المحفظة
        walletBalanceBefore: walletBeforeInt.toDouble(),
        walletBalanceAfter: walletAfterInt.toDouble(),
        partnerWalletBalanceBefore: partnerWalletBalanceBefore,
        customerWalletBalanceBefore: customerWalletBalanceBefore,
        currency: (priceDetails!['totalPrice'] is Map &&
                priceDetails!['totalPrice']['currency'] != null)
            ? priceDetails!['totalPrice']['currency'].toString()
            : (priceDetails!['currency']?.toString() ?? 'IQD'),
        paymentMethod: selectedPaymentMethod,
        // معلومات الشريك
        partnerName: subscriptionInfo!.partnerName,
        partnerId: subscriptionInfo!.partnerId,
        // حالة العملية
        isPrinted: isPrinted,
        isWhatsAppSent: isWhatsAppSent,
        subscriptionNotes: subscriptionNotes,
        // معلومات إضافية
        startDate: formattedDate,
        endDate: _calculateEndDate(),
        // معلومات المستخدم والشركة (مطلوبة للوحة المشغلين)
        userId: VpsAuthService.instance.currentUser?.id ??
            VpsAuthService.instance.currentSuperAdmin?.id,
        companyId: VpsAuthService.instance.currentCompanyId,
        // حقول تكامل المحاسبة
        collectionType: _getCollectionTypeCode(selectedPaymentMethod),
        linkedAgentId: _selectedLinkedAgent?['Id']?.toString(),
        linkedTechnicianId: _selectedLinkedTechnician?['Id']?.toString(),
        technicianName: _selectedLinkedTechnician?['Name']?.toString() ??
            _selectedLinkedAgent?['Name']?.toString(),
      );

      if (logId != null) {
        _vpsLogId = logId;
        debugPrint('✅ تم حفظ البيانات في VPS بنجاح - logId: $logId');
        debugPrint('💾 الحالات المحفوظة:');
        debugPrint('  🖨️ isPrinted: $isPrinted');
        debugPrint('  📱 isWhatsAppSent: $isWhatsAppSent');

        // تحديث حالة الحفظ
        setState(() {
          isDataSavedToServer = true;
        });

        // ملاحظة: المحاسبة (JE + AgentTransaction/TechnicianTransaction + تحديث الرصيد)
        // يتم تلقائياً من السيرفر عبر CreateAccountingEntryForLog
        // لذلك لا نستدعي _recordChargeToLinkedPerson هنا لتجنب الازدواجية
      } else {
        throw Exception('فشل حفظ البيانات في VPS - لم يتم إرجاع logId');
      }
    } catch (e) {
      debugPrint('❌ خطأ في حفظ البيانات في VPS: $e');
      throw Exception('فشل في حفظ البيانات في الخادم: $e');
    }
  }

  /// تحديث حالة الطباعة في VPS
  Future<void> _updatePrintStatusInVps() async {
    final logId = await _getOrFindVpsLogId();
    if (logId == null) {
      debugPrint('⚠️ لا يوجد logId لتحديث حالة الطباعة');
      return;
    }
    await SubscriptionLogsService.instance.updateLogStatus(
      logId: logId,
      isPrinted: true,
    );
    debugPrint('✅ تم تحديث حالة الطباعة في VPS (logId: $logId)');
  }

  /// تحديث حالة الواتساب في VPS
  Future<void> _updateWhatsAppStatusInVps() async {
    final logId = await _getOrFindVpsLogId();
    if (logId == null) {
      debugPrint('⚠️ لا يوجد logId لتحديث حالة الواتساب');
      return;
    }
    await SubscriptionLogsService.instance.updateLogStatus(
      logId: logId,
      isWhatsAppSent: true,
    );
    debugPrint('✅ تم تحديث حالة الواتساب في VPS (logId: $logId)');
  }

  /// الحصول على logId المحفوظ أو البحث عنه بواسطة sessionId
  Future<int?> _getOrFindVpsLogId() async {
    if (_vpsLogId != null && _vpsLogId! > 0) return _vpsLogId;
    if (sessionId.isNotEmpty) {
      _vpsLogId =
          await SubscriptionLogsService.instance.findLogBySessionId(sessionId);
    }
    return _vpsLogId;
  }

  /// تحديث الملاحظات في VPS (بعد الحفظ المسبق)
  Future<void> _updateNotesOnServer() async {
    if (!isDataSavedToServer) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'يجب حفظ البيانات أولاً عن طريق أحد الأزرار (تم التفعيل، طباعة، أو واتساب)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      debugPrint('🔄 جاري تحديث الملاحظات في VPS...');

      final logId = await _getOrFindVpsLogId();
      if (logId == null) {
        throw Exception('لم يتم العثور على السجل في VPS');
      }

      await SubscriptionLogsService.instance.updateLogStatus(
        logId: logId,
        notes: subscriptionNotes,
      );

      debugPrint('✅ تم تحديث الملاحظات في VPS بنجاح');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تم تحديث الملاحظات بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('❌ فشل في تحديث الملاحظات: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ فشل في تحديث الملاحظات: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// إرسال رسالة واتساب تلقائياً بعد العمليات الناجحة
  Future<void> _sendAutoWhatsAppMessage() async {
    if (subscriptionInfo == null) return;

    // منع فتح واتساب مرتين عن طريق الخطأ لنفس الحدث
    if (_isSendingWhatsApp) return;
    _isSendingWhatsApp = true;

    final phone = _getCustomerPhoneNumber();
    if (phone == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('رقم الهاتف غير متوفر لإرسال رسالة WhatsApp!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final phoneNumber = _formatPhoneNumber(phone);

    // استخدام قالب الرسالة إذا كان متوفراً، وإلا استخدام الرسالة الافتراضية
    String message;
    if (_whatsAppTemplate.isNotEmpty) {
      message = _generateWhatsAppMessageWithTemplate(_whatsAppTemplate);
    } else {
      final operationText =
          isNewSubscription ? "تم شراء اشتراك جديد" : "تم تجديد الاشتراك";
      final tVal = _formatNumber(_getFinalTotal().round());
      final tCurr = (priceDetails!['totalPrice'] is Map &&
              priceDetails!['totalPrice']['currency'] != null)
          ? priceDetails!['totalPrice']['currency'].toString()
          : (priceDetails!['currency']?.toString() ?? 'IQD');
      message = '''$operationText بنجاح!
- العميل: ${subscriptionInfo!.customerName}
- نوع الخدمة: $selectedPlan
- فترة الالتزام: $selectedCommitmentPeriod شهر
- السعر الإجمالي: $tVal $tCurr
- طريقة الدفع: $selectedPaymentMethod
- تاريخ الانتهاء: ${_calculateEndDate()}
- منفذ العملية: ${widget.activatedBy}
${isNewSubscription ? "- تم تحويل الاشتراك من تجريبي إلى مدفوع" : ""}''';
    }

    // نسخ الرسالة للحافظة أولاً
    await Clipboard.setData(ClipboardData(text: message));

    // محاولة فتح تطبيق واتساب مع الرسالة
    final whatsappUrl =
        'whatsapp://send?phone=$phoneNumber&text=${Uri.encodeComponent(message)}';

    try {
      final whatsappUri = Uri.parse(whatsappUrl);
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri);

        // تحديث حالة الإرسال
        setState(() {
          isWhatsAppSent = true;
        });

        // إظهار رسالة نجاح
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.chat, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        '✅ تم فتح WhatsApp بنجاح! الرسالة جاهزة للإرسال للمشترك.'),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
        debugPrint('✅ تم تحديث حالة إرسال الواتساب: مُرسل');
      } else {
        // إذا لم يكن WhatsApp مثبتاً، اعرض رسالة مع نسخ النص
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.content_copy, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('واتساب غير مثبت! تم نسخ نص الرسالة للحافظة.'),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      // في حالة حدوث خطأ، على الأقل النص منسوخ
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في فتح WhatsApp: $e\nتم نسخ النص للحافظة.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      _isSendingWhatsApp = false;
    }
  }

  // دالة تنسيق رقم الهاتف للواتساب
  String _formatPhoneNumber(String phone) {
    String cleanPhone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '+964${cleanPhone.substring(1)}';
    } else if (!cleanPhone.startsWith('+')) {
      cleanPhone = '+964$cleanPhone';
    }
    return cleanPhone;
  }

  // تمت إزالة الدالة المجمعة السابقة (_saveAndSendWhatsAppAndSheets) بعد فصل الأزرار.

  /// زر حفظ فقط في VPS (بدون واتساب)
  Future<void> _saveOnlyToServer() async {
    if (subscriptionInfo == null || priceDetails == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى حساب السعر أولاً')),
        );
      }
      return;
    }
    if (!widget.hasServerSavePermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا تملك صلاحية الحفظ في الخادم')),
        );
      }
      return;
    }

    // حفظ رصيد المحفظة قبل العملية إذا لم يكن محفوظاً
    if (partnerWalletBalanceBefore == 0.0) {
      partnerWalletBalanceBefore = walletBalance;
      debugPrint(
          '💰 حفظ رصيد محفظة الشريك قبل العملية: ${partnerWalletBalanceBefore.toStringAsFixed(2)}');
    }
    if (customerWalletBalanceBefore == 0.0) {
      customerWalletBalanceBefore = customerWalletBalance;
      debugPrint(
          '💰 حفظ رصيد محفظة العميل قبل العملية: ${customerWalletBalanceBefore.toStringAsFixed(2)}');
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 12),
              Text('جاري الحفظ...'),
            ],
          ),
        ),
      );
      await _saveToServer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم الحفظ في الخادم'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _isSavedToSheets = true;
          // خصم المبلغ محلياً من المحفظة المعروضة (محلية فقط – لا تستبدل طلب API)
          final double cost = _getFinalTotal();
          if (hasTeamMemberWallet) {
            teamMemberWalletBalance = (teamMemberWalletBalance - cost);
            if (teamMemberWalletBalance < 0) teamMemberWalletBalance = 0;
          } else {
            walletBalance = (walletBalance - cost);
            if (walletBalance < 0) walletBalance = 0;
          }
        });
        // إعادة تقييم العلاقة بين السعر والرصيد بعد الخصم المحلي
        _evaluatePriceWalletRelation();
        // محاولة جلب الرصيد الحقيقي مرة أخرى من المصدر لتأكيد التحديث (قد يعتمد على أن العملية الأصلية سبق أن خصمت من الخادم)
        try {
          await fetchWalletBalance();
        } catch (e) {
          debugPrint('⚠️ فشل تحديث الرصيد من المصدر بعد التفعيل: $e');
        }
        // بث حدث تحديث فوري للواجهة الرئيسية (محفظة + لوحة)
        try {
          // الاستيراد المتأخر لتفادي الاعتمادية الدائرية إن وُجدت
          // (وإلا يمكن وضع الاستيراد أعلى الملف مباشرة)
          // ignore: avoid_web_libraries_in_flutter
        } catch (_) {}
        // استخدام event bus مباشرة (نضيف الاستيراد أعلى الملف فعلياً)
        FtthEventBus.instance.emit(FtthEvents.forceRefresh);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSavedToSheets = false;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل الحفظ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context, rootNavigator: false).pop();
      }
    }
  }

  /// إرسال واتساب فقط (بدون حفظ)
  Future<void> _sendWhatsAppOnly() async {
    if (subscriptionInfo == null || priceDetails == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى حساب السعر أولاً')),
        );
      }
      return;
    }
    if (!widget.hasWhatsAppPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا تملك صلاحية إرسال WhatsApp')),
        );
      }
      return;
    }
    // استدعاء الدالة الصحيحة التي تحفظ في الخادم
    await sendWhatsAppMessage();
  }

  /// إرسال رسالة للفني المحدد مباشرة
  Future<void> _sendSelectedTechnicianMessage() async {
    if (selectedTechnician == null) {
      ftthShowErrorNotification(context, 'يرجى اختيار فني أولاً');
      return;
    }

    if (subscriptionInfo == null || priceDetails == null) {
      ftthShowErrorNotification(context, 'يرجى حساب السعر أولاً');
      return;
    }

    if (!widget.hasWhatsAppPermission) {
      ftthShowErrorNotification(context, 'لا تملك صلاحية إرسال WhatsApp');
      return;
    }

    // البحث عن رقم الفني المحدد
    final selectedTech = technicians.firstWhere(
      (tech) => tech['name'] == selectedTechnician,
      orElse: () => {},
    );

    if (selectedTech.isEmpty || selectedTech['phone'] == null) {
      ftthShowErrorNotification(
          context, 'لم يتم العثور على رقم هاتف الفني المحدد');
      return;
    }

    // إرسال رسالة للفني
    await _sendTechnicianMessage(selectedTech['phone']!, selectedTech['name']!);
  }

  /// إرسال تفاصيل المشترك إلى فني التوصيل
  Future<void> _sendToTechnician() async {
    if (subscriptionInfo == null || priceDetails == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى حساب السعر أولاً')),
        );
      }
      return;
    }
    if (!widget.hasWhatsAppPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا تملك صلاحية إرسال WhatsApp')),
        );
      }
      return;
    }

    // إظهار نافذة اختيار الفني
    await _showTechnicianSelectionDialog();
  }

  /// نافذة اختيار الفني وإرسال التفاصيل
  Future<void> _showTechnicianSelectionDialog() async {
    String? selectedTechPhone;
    String? selectedTechName;

    // التحقق من وجود فنيين
    if (technicians.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'لا توجد قائمة فنيين محفوظة. يرجى إضافة الفنيين من الإعدادات'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.engineering, color: Colors.orange.shade600),
              SizedBox(width: 8),
              Text('اختيار فني التوصيل'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'اختر الفني الذي سيستلم معلومات المشترك',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 16),
                Container(
                  constraints: BoxConstraints(maxHeight: 300),
                  child: SingleChildScrollView(
                    child: Column(
                      children: technicians.map((tech) {
                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.shade100,
                              child: Icon(Icons.person,
                                  color: Colors.orange.shade700),
                            ),
                            title: Text(tech['name'] ?? 'غير محدد'),
                            subtitle: Text(tech['phone'] ?? 'غير محدد'),
                            onTap: () {
                              Navigator.of(context).pop({
                                'name': tech['name'] ?? '',
                                'phone': tech['phone'] ?? '',
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('إلغاء'),
            ),
          ],
        );
      },
    );

    if (result != null &&
        result['phone'] != null &&
        result['phone']!.isNotEmpty) {
      selectedTechPhone = result['phone'];
      selectedTechName = result['name'];

      // إرسال رسالة للفني
      await _sendTechnicianMessage(selectedTechPhone!, selectedTechName!);
    }
  }

  /// إرسال رسالة واتساب للفني مع تفاصيل المشترك - فتح تطبيق الواتساب على الحاسوب
  Future<void> _sendTechnicianMessage(String techPhone, String techName) async {
    setState(() {
      _isSendingToTechnician = true;
    });

    try {
      // تنسيق رقم الفني
      final cleanTechPhone = _validateAndFormatPhone(techPhone);
      if (cleanTechPhone == null) {
        if (mounted) {
          ftthShowErrorNotification(context, 'رقم هاتف الفني غير صحيح');
        }
        return;
      }

      // إنشاء رسالة خاصة بالفني
      final message = _buildTechnicianMessage(techName);

      debugPrint('📱 فتح تطبيق الواتساب على الحاسوب للفني: $techName');
      debugPrint('📱 رقم الفني: $cleanTechPhone');
      debugPrint('📱 طول الرسالة: ${message.length}');

      // نسخ الرسالة إلى الكليببورد
      await Clipboard.setData(ClipboardData(text: message));

      // الإرسال التلقائي دائماً (نفس آلية زر العميل)
      debugPrint(
          '🚀 الإرسال التلقائي السريع للفني: فتح واتساب بدون نص في الرابط');

      // فتح واتساب بدون رسالة في الرابط لتجنب الإرسال المزدوج
      final whatsappUrl = 'whatsapp://send?phone=$cleanTechPhone';

      try {
        // محاولة فتح الواتساب مع معالجة الإصدارات المختلفة
        final uri = Uri.parse(whatsappUrl);
        bool launched = false;

        try {
          // محاولة أولى: الإصدار الحديث
          debugPrint('🔄 محاولة فتح الواتساب بالطريقة الحديثة...');
          launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
        } catch (e) {
          debugPrint(
              '⚠️ فشل فتح الواتساب بالطريقة الحديثة، محاولة الطريقة التقليدية: $e');

          // محاولة ثانية: الإصدار التقليدي للإصدارات القديمة
          try {
            final fallbackUrl =
                'https://web.whatsapp.com/send?phone=$cleanTechPhone';
            launched = await launchUrl(
              Uri.parse(fallbackUrl),
              mode: LaunchMode.externalApplication,
            );
            debugPrint('✅ تم فتح واتساب ويب كبديل للإصدار القديم');
          } catch (e2) {
            debugPrint('❌ فشل فتح واتساب ويب أيضاً: $e2');
            // محاولة أخيرة: فتح الواتساب مع الرسالة في الرابط للإصدارات القديمة جداً
            try {
              final legacyUrl =
                  'whatsapp://send?phone=$cleanTechPhone&text=${Uri.encodeComponent(message)}';
              launched = await launchUrl(
                Uri.parse(legacyUrl),
                mode: LaunchMode.externalApplication,
              );
              debugPrint('⚠️ استخدام الطريقة التقليدية مع الرسالة في الرابط');
            } catch (e3) {
              debugPrint('❌ فشل جميع محاولات فتح الواتساب: $e3');
              launched = false;
            }
          }
        }

        if (launched) {
          debugPrint(
              '✅ تم فتح واتساب ديسكتوب للفني - بدء الإرسال التلقائي الفوري');

          // انتظار قصير جداً فقط لفتح واتساب (تقليل من 800ms إلى 600ms)
          await Future.delayed(Duration(milliseconds: 600));

          // نسخ الرسالة للحافظة مرة أخرى للتأكد
          await Clipboard.setData(ClipboardData(text: message));

          // تنفيذ الإرسال التلقائي الفوري بأقصى سرعة ممكنة
          final autoSendSuccess =
              await WindowsAutomationService.performSmartAutoSend(
                  delayMs: 30 // أقصى سرعة - 30ms فقط بين العمليات
                  );

          if (autoSendSuccess) {
            debugPrint('⚡ تم إرسال رسالة الفني فورياً بنجاح خلال ثوانٍ قليلة');
            if (mounted) {
              ftthShowSuccessNotification(
                  context, '⚡ تم إرسال رسالة للفني $techName فورياً!');
              ftthShowInfoNotification(
                  context, '🔄 محاولة إعادة المؤشر لمربع النص...');
            }
            _shiftTabBackOnce();
          } else {
            debugPrint(
                '⚠️ فشل الإرسال الفوري للفني - استخدام النسخة الاحتياطية');
            if (mounted) {
              ftthShowSuccessNotification(context,
                  '⚠️ تم فتح واتساب للفني $techName - يرجى لصق الرسالة (Ctrl+V) وإرسالها');
            }
          }
        } else {
          throw Exception('فشل في فتح واتساب ديسكتوب');
        }
      } catch (e) {
        debugPrint('❌ خطأ في فتح واتساب ديسكتوب: $e');

        if (mounted) {
          // رسالة مفصلة للمساعدة مع الإصدارات القديمة - للفني
          String errorMessage = 'فشل في فتح واتساب للفني $techName.\n\n';
          errorMessage += '💡 نصائح للحل:\n';
          errorMessage += '• تأكد من تثبيت واتساب ديسكتوب\n';
          errorMessage += '• حدث واتساب لأحدث إصدار\n';
          errorMessage += '• أعد تشغيل واتساب ديسكتوب\n';
          errorMessage += '• تم نسخ الرسالة، يمكنك لصقها يدوياً';

          ftthShowErrorNotification(context, errorMessage);
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في إرسال رسالة للفني: $e');
      if (mounted) {
        ftthShowErrorNotification(
            context, 'خطأ في إرسال الرسالة للفني: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingToTechnician = false);
      }
    }
  }

  /// بناء رسالة خاصة بالفني
  String _buildTechnicianMessage(String techName) {
    if (subscriptionInfo == null || priceDetails == null) return '';

    final phone = _getCustomerPhoneNumber() ?? 'غير محدد';

    // بناء رابط خرائط جوجل للموقع
    String googleMapsUrl = 'غير محدد';
    if (widget.gpsLatitude != null &&
        widget.gpsLongitude != null &&
        widget.gpsLatitude!.trim().isNotEmpty &&
        widget.gpsLongitude!.trim().isNotEmpty) {
      googleMapsUrl =
          'https://maps.google.com/?q=${widget.gpsLatitude},${widget.gpsLongitude}';
    }

    final totalPrice = _formatNumber(_getFinalTotal().round());
    final currency = (priceDetails!['totalPrice'] is Map &&
            priceDetails!['totalPrice']['currency'] != null)
        ? priceDetails!['totalPrice']['currency'].toString()
        : (priceDetails!['currency']?.toString() ?? 'IQD');

    final now = DateTime.now();
    final todayDate = '${now.day}/${now.month}/${now.year}';
    final todayTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return '''
🔧 مهمة تفعيل جديدة - $techName
═════════════════════
• الاسم: ${subscriptionInfo!.customerName}
• الهاتف: $phone
📍 الخريطة: $googleMapsUrl
---------------------
• الخطة: ${selectedPlan ?? 'غير محددة'}
• المدة: ${selectedCommitmentPeriod ?? 0} شهر
• FBG: ${widget.fbgValue ?? widget.fdtDisplayValue ?? 'غير محدد'}
• FAT: ${widget.fatValue ?? widget.fatDisplayValue ?? 'غير محدد'}
---------------------
• القيمة: $totalPrice $currency
• طريقة الدفع: $selectedPaymentMethod
---------------------
• المحاسب: ${widget.activatedBy}
• التاريخ: $todayDate
• الوقت: $todayTime
═════════════════════
⚠️ تنبيه مهم
يجب تحصيل المبلغ المذكور أعلاه من المشترك قبل التفعيل
شكراً لك أخي $techName 🙏
''';
  } // دالة حساب تاريخ الانتهاء

  String _calculateEndDate() {
    try {
      final now = DateTime.now();
      final endDate = now.add(Duration(days: 30));
      return '${endDate.day}/${endDate.month}/${endDate.year}';
    } catch (e) {
      return 'غير محدد';
    }
  }

  // نافذة التفعيل المباشر
  void _showDirectActivationDialog() {
    final operationType = isNewSubscription
        ? 'شراء الاشتراك'
        : (subscriptionInfo != null &&
                selectedPlan == subscriptionInfo!.currentPlan &&
                selectedCommitmentPeriod == subscriptionInfo!.commitmentPeriod)
            ? 'تجديد الاشتراك'
            : 'تغيير الاشتراك';

    final bool canExecute = priceDetails != null &&
        selectedPlan != null &&
        selectedCommitmentPeriod != null;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (BuildContext ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            padding: const EdgeInsets.all(0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // الهيدر
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade600, Colors.teal.shade700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.flash_on,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'التفعيل المباشر',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'تنفيذ العملية على API مباشرة',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                // المحتوى
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // معلومات العملية
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            _buildActivationInfoRow(
                              'نوع العملية:',
                              operationType,
                              icon: Icons.sync,
                              color: Colors.blue,
                            ),
                            const Divider(height: 16),
                            _buildActivationInfoRow(
                              'العميل:',
                              subscriptionInfo?.customerName ?? 'غير محدد',
                              icon: Icons.person,
                              color: Colors.indigo,
                            ),
                            const Divider(height: 16),
                            _buildActivationInfoRow(
                              'الباقة:',
                              selectedPlan ?? 'غير محدد',
                              icon: Icons.wifi,
                              color: Colors.purple,
                            ),
                            const Divider(height: 16),
                            _buildActivationInfoRow(
                              'المدة:',
                              '${selectedCommitmentPeriod ?? 0} شهر',
                              icon: Icons.calendar_month,
                              color: Colors.orange,
                            ),
                            const Divider(height: 16),
                            _buildActivationInfoRow(
                              'السعر:',
                              priceDetails != null
                                  ? '${_formatNumber(_getFinalTotal().round())} IQD'
                                  : 'لم يُحسب بعد',
                              icon: Icons.payments,
                              color: Colors.green,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // تحذير
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.amber.shade700, size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                canExecute
                                    ? 'سيتم خصم المبلغ من المحفظة وتفعيل الاشتراك فوراً'
                                    : 'يرجى اختيار الباقة والمدة وحساب السعر أولاً',
                                style: TextStyle(
                                  color: Colors.amber.shade800,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // الأزرار
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(color: Colors.grey.shade300),
                                ),
                              ),
                              child: const Text(
                                'إلغاء',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: canExecute
                                  ? () {
                                      Navigator.of(ctx).pop();
                                      executeRenewalOrPurchase();
                                    }
                                  : null,
                              icon: Icon(
                                isNewSubscription
                                    ? Icons.shopping_cart
                                    : Icons.refresh,
                                size: 20,
                              ),
                              label: Text(
                                operationType,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: canExecute
                                    ? Colors.green.shade600
                                    : Colors.grey.shade400,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: canExecute ? 4 : 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // صف معلومات في شاشة التفعيل المباشر
  Widget _buildActivationInfoRow(
    String label,
    String value, {
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 13,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  // نافذة عرض البيانات المنقولة
  void _showPassedDataDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Colors.blue.shade50,
                  Colors.indigo.shade50,
                  Colors.purple.shade50,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: 0.3),
                  spreadRadius: 5,
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(
                color: Colors.blue.shade200,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // عنوان محسن مع خلفية متدرجة
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.blue.shade600,
                        Colors.indigo.shade700,
                        Colors.purple.shade600,
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.info_outline,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'المعلومات المُمررة',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    offset: const Offset(0, 1),
                                    blurRadius: 3,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'جميع البيانات من الصفحات السابقة',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // المحتوى
                Flexible(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 1. معلومات الاشتراك الأساسية (مطلوبة)
                          _buildInfoSection('📋 معلومات الاشتراك الأساسية', [
                            _buildInfoRow(
                                'معرف المستخدم', widget.userId, Icons.person),
                            _buildInfoRow('معرف الاشتراك',
                                widget.subscriptionId, Icons.article),
                            _buildInfoRow('منشط بواسطة', widget.activatedBy,
                                Icons.person_pin),
                            _buildInfoRow(
                                'نوع الاشتراك',
                                isNewSubscription ? 'جديد (تجريبي)' : 'موجود',
                                Icons.subscriptions),
                          ]),

                          // 2. معلومات المستخدم (اختيارية)
                          if (widget.userName != null ||
                              widget.userPhone != null) ...[
                            SizedBox(height: 16),
                            _buildInfoSection('👤 معلومات المستخدم', [
                              if (widget.userName != null)
                                _buildInfoRow('اسم المستخدم', widget.userName!,
                                    Icons.account_circle),
                              if (widget.userPhone != null)
                                _buildInfoRow('رقم الهاتف', widget.userPhone!,
                                    Icons.phone),
                            ]),
                          ],

                          // 3. معلومات الحالة والجهاز (اختيارية)
                          if (widget.currentStatus != null ||
                              widget.deviceUsername != null) ...[
                            SizedBox(height: 16),
                            _buildInfoSection('🌐 معلومات الحالة والجهاز', [
                              if (widget.currentStatus != null)
                                _buildInfoRow(
                                    'الحالة الحالية',
                                    widget.currentStatus!,
                                    Icons.signal_wifi_4_bar),
                              if (widget.deviceUsername != null)
                                _buildInfoRow('اسم المستخدم للجهاز',
                                    widget.deviceUsername!, Icons.router),
                            ]),
                          ],

                          // 4. معلومات الخدمات (اختيارية)
                          if (widget.currentBaseService != null ||
                              widget.services != null) ...[
                            SizedBox(height: 16),
                            _buildInfoSection('🛜 معلومات الخدمات', [
                              if (widget.currentBaseService != null)
                                _buildInfoRow('الخدمة الأساسية الحالية',
                                    widget.currentBaseService!, Icons.wifi),
                              if (widget.services != null) ...[
                                _buildInfoRow(
                                    'عدد الخدمات',
                                    '${widget.services!.length} خدمة',
                                    Icons.list),
                                if (widget.services!.isNotEmpty)
                                  for (int i = 0;
                                      i < widget.services!.length;
                                      i++)
                                    _buildInfoRow(
                                        'خدمة ${i + 1}',
                                        widget.services![i].toString(),
                                        Icons.miscellaneous_services),
                              ],
                            ]),
                          ],

                          // 5. معلومات التواريخ والمدة (اختيارية)
                          if (widget.expires != null ||
                              widget.startedAt != null ||
                              widget.remainingDays != null) ...[
                            SizedBox(height: 16),
                            _buildInfoSection('📅 معلومات التواريخ والمدة', [
                              if (widget.startedAt != null)
                                _buildInfoRow(
                                    'تاريخ البدء',
                                    widget.startedAt!.split('T')[0],
                                    Icons.play_arrow),
                              if (widget.expires != null)
                                _buildInfoRow('تاريخ الانتهاء',
                                    widget.expires!.split('T')[0], Icons.stop),
                              if (widget.remainingDays != null)
                                _buildInfoRow(
                                    'الأيام المتبقية',
                                    '${widget.remainingDays} يوم',
                                    Icons.schedule),
                            ]),
                          ],

                          // 6. معلومات الشبكة والبنية التحتية (محسنة)
                          Builder(builder: (context) {
                            final networkInfo = <Widget>[];

                            // FDT و FAT - أهم معلومات البنية التحتية
                            if (widget.fdtDisplayValue != null &&
                                widget.fdtDisplayValue!.isNotEmpty) {
                              networkInfo.add(_buildInfoRow(
                                'FDT (موزع الألياف البصرية)',
                                widget.fdtDisplayValue!,
                                Icons.device_hub,
                              ));
                            } else {
                              networkInfo.add(_buildInfoRow(
                                'FDT (موزع الألياف البصرية)',
                                'غير محدد - قد يتطلب تحديث البيانات',
                                Icons.device_hub,
                              ));
                            }

                            // عرض FBG إذا تم تمريره من الصفحة السابقة
                            if (widget.fbgValue != null &&
                                widget.fbgValue!.trim().isNotEmpty) {
                              networkInfo.add(_buildInfoRow(
                                'FBG (صندوق التقسيم الرئيسي)',
                                widget.fbgValue!,
                                Icons.account_tree,
                              ));
                            } else {
                              networkInfo.add(_buildInfoRow(
                                'FBG (صندوق التقسيم الرئيسي)',
                                'غير متوفر',
                                Icons.account_tree,
                              ));
                            }

                            if (widget.fatDisplayValue != null &&
                                widget.fatDisplayValue!.isNotEmpty) {
                              networkInfo.add(_buildInfoRow(
                                'FAT (نهاية الألياف البصرية)',
                                widget.fatDisplayValue!,
                                Icons.router_outlined,
                              ));
                            } else {
                              networkInfo.add(_buildInfoRow(
                                'FAT (نهاية الألياف البصرية)',
                                'غير محدد - قد يتطلب تحديث البيانات',
                                Icons.router_outlined,
                              ));
                            }

                            // في بعض الحالات يتم تمرير fatValue (القيمة الخام) وتختلف عن fatDisplayValue
                            if (widget.fatValue != null &&
                                widget.fatValue!.trim().isNotEmpty &&
                                widget.fatValue != widget.fatDisplayValue) {
                              networkInfo.add(_buildInfoRow(
                                'FAT (القيمة الأصلية)',
                                widget.fatValue!,
                                Icons.hub,
                              ));
                            }

                            // معلومات شبكة إضافية من بيانات العميل الشاملة
                            if (widget.customerDataMain != null) {
                              final data = widget.customerDataMain!;

                              if (data.containsKey('network_type')) {
                                networkInfo.add(_buildInfoRow(
                                  'نوع الشبكة',
                                  data['network_type'].toString(),
                                  Icons.network_wifi,
                                ));
                              }

                              if (data.containsKey('connection_status')) {
                                networkInfo.add(_buildInfoRow(
                                  'حالة الاتصال',
                                  data['connection_status'].toString(),
                                  Icons.signal_cellular_alt,
                                ));
                              }

                              if (data.containsKey('speed')) {
                                networkInfo.add(_buildInfoRow(
                                  'السرعة المحددة',
                                  data['speed'].toString(),
                                  Icons.speed,
                                ));
                              }

                              if (data.containsKey('bandwidth')) {
                                networkInfo.add(_buildInfoRow(
                                  'عرض النطاق الترددي',
                                  data['bandwidth'].toString(),
                                  Icons.network_check,
                                ));
                              }
                            }

                            // معلومات إضافية من بيانات ONT
                            if (widget.deviceOntInfo != null) {
                              final ontData = widget.deviceOntInfo!;

                              if (ontData.containsKey('optical_power')) {
                                networkInfo.add(_buildInfoRow(
                                  'القوة البصرية',
                                  '${ontData['optical_power']} dBm',
                                  Icons.lightbulb_outline,
                                ));
                              }

                              if (ontData.containsKey('fiber_status')) {
                                networkInfo.add(_buildInfoRow(
                                  'حالة الألياف البصرية',
                                  ontData['fiber_status'].toString(),
                                  Icons.cable,
                                ));
                              }

                              if (ontData.containsKey('upstream_rate')) {
                                networkInfo.add(_buildInfoRow(
                                  'معدل الرفع (Upstream)',
                                  ontData['upstream_rate'].toString(),
                                  Icons.upload,
                                ));
                              }

                              if (ontData.containsKey('downstream_rate')) {
                                networkInfo.add(_buildInfoRow(
                                  'معدل التحميل (Downstream)',
                                  ontData['downstream_rate'].toString(),
                                  Icons.download,
                                ));
                              }
                            }

                            // إضافة معلومات عامة للشبكة
                            networkInfo.add(_buildInfoRow(
                              'نوع التقنية',
                              'FTTH (Fiber To The Home)',
                              Icons.wifi,
                            ));

                            networkInfo.add(_buildInfoRow(
                              'حالة الاتصال العامة',
                              'متصل ونشط',
                              Icons.signal_wifi_4_bar,
                            ));

                            return Column(
                              children: [
                                SizedBox(height: 16),
                                _buildInfoSection(
                                    '🌐 معلومات الشبكة والبنية التحتية',
                                    networkInfo),
                              ],
                            );
                          }),

                          // 6.1. معلومات الجهاز التقنية الإضافية
                          if (widget.deviceSerial != null ||
                              widget.macAddress != null ||
                              widget.deviceModel != null ||
                              (subscriptionInfo != null &&
                                  subscriptionInfo!
                                      .deviceUsername.isNotEmpty)) ...[
                            SizedBox(height: 16),
                            _buildInfoSection('🔧 معلومات الجهاز التقنية', [
                              if (subscriptionInfo != null &&
                                  subscriptionInfo!.deviceUsername.isNotEmpty)
                                _buildInfoRow(
                                    'اسم مستخدم الجهاز',
                                    subscriptionInfo!.deviceUsername,
                                    Icons.router),
                              if (widget.deviceSerial != null)
                                _buildInfoRow('الرقم التسلسلي للجهاز',
                                    widget.deviceSerial!, Icons.qr_code_2),
                              if (widget.macAddress != null)
                                _buildInfoRow('عنوان MAC', widget.macAddress!,
                                    Icons.network_check),
                              if (widget.deviceModel != null)
                                _buildInfoRow('موديل الجهاز',
                                    widget.deviceModel!, Icons.device_unknown),
                              if (subscriptionInfo != null) ...[
                                if (subscriptionInfo!.deviceSerial != null)
                                  _buildInfoRow(
                                      'رقم تسلسلي من API',
                                      subscriptionInfo!.deviceSerial!,
                                      Icons.qr_code),
                                if (subscriptionInfo!.macAddress != null)
                                  _buildInfoRow(
                                      'MAC من API',
                                      subscriptionInfo!.macAddress!,
                                      Icons.wifi),
                                if (subscriptionInfo!.deviceModel != null)
                                  _buildInfoRow(
                                      'موديل من API',
                                      subscriptionInfo!.deviceModel!,
                                      Icons.memory),
                              ],
                            ]),
                          ],

                          // 6.2. معلومات الموقع والعنوان
                          if (widget.gpsLatitude != null ||
                              widget.gpsLongitude != null ||
                              widget.customerAddress != null ||
                              (subscriptionInfo != null &&
                                  subscriptionInfo!.gpsLatitude != null)) ...[
                            SizedBox(height: 16),
                            _buildInfoSection('🌍 معلومات الموقع والعنوان', [
                              if (widget.gpsLatitude != null &&
                                  widget.gpsLongitude != null)
                                _buildInfoRow(
                                    'إحداثيات GPS',
                                    'خط العرض: ${widget.gpsLatitude}\nخط الطول: ${widget.gpsLongitude}',
                                    Icons.location_on),
                              if (subscriptionInfo != null) ...[
                                if (subscriptionInfo!.gpsLatitude != null &&
                                    subscriptionInfo!.gpsLongitude != null)
                                  _buildInfoRow(
                                      'GPS من API',
                                      'العرض: ${subscriptionInfo!.gpsLatitude}, الطول: ${subscriptionInfo!.gpsLongitude}',
                                      Icons.gps_fixed),
                              ],
                              if (widget.customerAddress != null)
                                _buildInfoRow(
                                    'عنوان العميل',
                                    widget.customerAddress!,
                                    Icons.home_outlined),
                              if (customerAddress != null)
                                _buildInfoRow('العنوان المحمل',
                                    customerAddress!, Icons.location_city),
                            ]),
                          ],

                          // 7. معلومات الصلاحيات والأذونات (اختيارية)
                          if (widget.importantFtthApiPermissions != null &&
                              widget
                                  .importantFtthApiPermissions!.isNotEmpty) ...[
                            SizedBox(height: 16),
                            _buildInfoSection('🔐 الصلاحيات والأذونات', [
                              _buildInfoRow(
                                  'عدد الصلاحيات',
                                  '${widget.importantFtthApiPermissions!.length} صلاحية',
                                  Icons.security),
                              for (String permission
                                  in widget.importantFtthApiPermissions!)
                                _buildInfoRow('صلاحية', permission,
                                    Icons.check_circle_outline),
                            ]),
                          ],

                          // 8. معلومات الأذونات المحلية
                          SizedBox(height: 16),
                          _buildInfoSection('✅ أذونات التطبيق', [
                            _buildInfoRow(
                                'إذن حفظ الخادم',
                                widget.hasServerSavePermission
                                    ? 'مفعل'
                                    : 'غير مفعل',
                                widget.hasServerSavePermission
                                    ? Icons.check_circle
                                    : Icons.cancel),
                            _buildInfoRow(
                                'إذن الواتساب',
                                widget.hasWhatsAppPermission
                                    ? 'مفعل'
                                    : 'غير مفعل',
                                widget.hasWhatsAppPermission
                                    ? Icons.check_circle
                                    : Icons.cancel),
                          ]),

                          // 9. البيانات المبدئية (اختيارية)
                          if (widget.initialAllowedActions != null &&
                              widget.initialAllowedActions!.isNotEmpty) ...[
                            SizedBox(height: 16),
                            _buildInfoSection(
                                '🎬 الإجراءات المسموحة المبدئية', [
                              _buildInfoRow(
                                  'عدد الإجراءات',
                                  '${widget.initialAllowedActions!.keys.length} إجراء',
                                  Icons.settings),
                              for (String action
                                  in widget.initialAllowedActions!.keys)
                                _buildInfoRow(
                                    'إجراء',
                                    '$action: ${widget.initialAllowedActions![action]}',
                                    Icons.play_circle_outline),
                            ]),
                          ],

                          // 10. معلومات الخطط والحزم (اختيارية)
                          if (widget.initialBundles != null &&
                              widget.initialBundles!.isNotEmpty) ...[
                            SizedBox(height: 16),
                            _buildInfoSection('📦 الخطط والحزم المبدئية', [
                              _buildInfoRow(
                                  'عدد العناصر',
                                  '${widget.initialBundles!.keys.length} عنصر',
                                  Icons.inventory),
                              for (String key in widget.initialBundles!.keys
                                  .take(5)) // عرض أول 5 فقط لتوفير المساحة
                                _buildInfoRow(
                                    'عنصر',
                                    '$key: ${widget.initialBundles![key].toString().substring(0, widget.initialBundles![key].toString().length > 50 ? 50 : widget.initialBundles![key].toString().length)}${widget.initialBundles![key].toString().length > 50 ? '...' : ''}',
                                    Icons.inventory_2),
                              if (widget.initialBundles!.keys.length > 5)
                                _buildInfoRow(
                                    'المزيد',
                                    'و ${widget.initialBundles!.keys.length - 5} عنصر إضافي',
                                    Icons.more_horiz),
                            ]),
                          ],

                          // 11. معلومات المحافظ المالية (اختيارية)
                          if (widget.initialPartnerWalletBalance != null ||
                              widget.initialCustomerWalletBalance != null) ...[
                            SizedBox(height: 16),
                            _buildInfoSection('💰 أرصدة المحافظ المبدئية', [
                              if (widget.initialPartnerWalletBalance != null)
                                _buildInfoRow(
                                    'رصيد محفظة الشريك',
                                    '${widget.initialPartnerWalletBalance!.toStringAsFixed(0)} دينار',
                                    Icons.account_balance_wallet),
                              if (widget.initialCustomerWalletBalance != null)
                                _buildInfoRow(
                                    'رصيد محفظة العميل',
                                    '${widget.initialCustomerWalletBalance!.toStringAsFixed(0)} دينار',
                                    Icons.wallet),
                            ]),
                          ],

                          // 12. معلومات الاشتراك التجريبي المفصلة
                          if (isNewSubscription &&
                              subscriptionInfo != null) ...[
                            SizedBox(height: 16),
                            _buildInfoSection('🆕 تفاصيل الاشتراك التجريبي', [
                              _buildInfoRow('اسم العميل',
                                  subscriptionInfo!.customerName, Icons.person),
                              _buildInfoRow(
                                  'رقم الهاتف',
                                  _getCustomerPhoneNumber() ?? 'غير متوفر',
                                  Icons.phone),
                              _buildInfoRow('المنطقة', subscriptionInfo!.zoneId,
                                  Icons.location_on),
                              _buildInfoRow(
                                  'الشريك',
                                  subscriptionInfo!.partnerName,
                                  Icons.business),
                              _buildInfoRow(
                                  'معرف الشريك',
                                  subscriptionInfo!.partnerId,
                                  Icons.business_center),
                              if (trialExpiredAt != null)
                                _buildInfoRow(
                                    'تاريخ انتهاء التجربة',
                                    trialExpiredAt!.split('T')[0],
                                    Icons.access_time_outlined),
                            ]),
                          ],

                          // 13. معلومات الحالة الحالية للصفحة
                          SizedBox(height: 16),
                          _buildInfoSection('📊 حالة الصفحة الحالية', [
                            _buildInfoRow(
                                'الخطة المختارة',
                                selectedPlan ?? 'غير محددة',
                                Icons.fiber_manual_record),
                            _buildInfoRow(
                                'فترة الالتزام',
                                selectedCommitmentPeriod != null
                                    ? '$selectedCommitmentPeriod شهر'
                                    : 'غير محددة',
                                Icons.access_time),
                            _buildInfoRow('طريقة الدفع', selectedPaymentMethod,
                                Icons.payment),
                            _buildInfoRow(
                                'حالة حساب السعر',
                                priceDetails != null
                                    ? 'تم الحساب'
                                    : 'لم يتم الحساب',
                                Icons.calculate),
                            if (priceDetails != null)
                              _buildInfoRow(
                                  'السعر المحسوب',
                                  '${_asDouble(priceDetails!['totalPrice']).toStringAsFixed(0)} دينار',
                                  Icons.price_check),
                          ]),

                          // 14. معلومات الجلسة والأمان
                          SizedBox(height: 16),
                          _buildInfoSection('🔒 معلومات الجلسة والأمان', [
                            _buildInfoRow(
                                'رمز المصادقة (Token)',
                                '${widget.authToken.substring(0, 30)}...',
                                Icons.security),
                            _buildInfoRow(
                                'وقت تحميل الصفحة',
                                DateTime.now().toString().split('.')[0],
                                Icons.access_time),
                            _buildInfoRow(
                                'حالة التحميل',
                                isLoading ? 'جاري التحميل' : 'مكتمل',
                                isLoading
                                    ? Icons.hourglass_empty
                                    : Icons.check_circle),
                            if (errorMessage.isNotEmpty)
                              _buildInfoRow(
                                  'آخر خطأ', errorMessage, Icons.error_outline),
                          ]),

                          // 15. معلومات إضافية مختصرة (إزالة التكرار)
                          if (widget.deviceSerial != null ||
                              widget.macAddress != null ||
                              widget.deviceModel != null ||
                              widget.gpsLatitude != null ||
                              widget.gpsLongitude != null ||
                              widget.customerAddress != null ||
                              widget.deviceOntInfo != null ||
                              widget.customerDataMain != null) ...[
                            SizedBox(height: 16),
                            _buildInfoSection('🔧 معلومات إضافية مختصرة', [
                              if (widget.deviceSerial != null)
                                _buildInfoRow('الرقم التسلسلي',
                                    widget.deviceSerial!, Icons.qr_code_2),
                              if (widget.macAddress != null)
                                _buildInfoRow('MAC', widget.macAddress!,
                                    Icons.network_check),
                              if (widget.deviceModel != null)
                                _buildInfoRow('موديل', widget.deviceModel!,
                                    Icons.devices_other),
                              if (widget.gpsLatitude != null &&
                                  widget.gpsLongitude != null)
                                _buildInfoRow(
                                    'GPS',
                                    '${widget.gpsLatitude}, ${widget.gpsLongitude}',
                                    Icons.gps_fixed),
                              if (widget.customerAddress != null)
                                _buildInfoRow(
                                    'عنوان العميل (مُمرر)',
                                    widget.customerAddress!,
                                    Icons.home_outlined),
                              if (customerAddress != null &&
                                  widget.customerAddress == null)
                                _buildInfoRow('عنوان العميل', customerAddress!,
                                    Icons.home_outlined),
                              if (widget.deviceOntInfo != null)
                                _buildInfoRow(
                                    'عدد عناصر ONT',
                                    widget.deviceOntInfo!.keys.length
                                        .toString(),
                                    Icons.router),
                              if (widget.customerDataMain != null)
                                _buildInfoRow(
                                    'عدد عناصر بيانات العميل',
                                    widget.customerDataMain!.keys.length
                                        .toString(),
                                    Icons.person_search),
                            ]),
                          ],

                          // 16. معلومات النظام الأول والصلاحيات
                          if (widget.firstSystemPermissions != null ||
                              widget.isAdminFlag != null ||
                              widget.firstSystemDepartment != null ||
                              widget.firstSystemCenter != null ||
                              widget.firstSystemSalary != null ||
                              widget.ftthPermissions != null ||
                              widget.userRoleHeader != null ||
                              widget.clientAppHeader != null) ...[
                            SizedBox(height: 16),
                            _buildInfoSection(
                                '🏢 معلومات النظام الأول والصلاحيات', [
                              if (widget.firstSystemPermissions != null)
                                _buildInfoRow(
                                    'صلاحيات النظام الأول',
                                    widget.firstSystemPermissions!,
                                    Icons.security),
                              if (widget.isAdminFlag != null)
                                _buildInfoRow(
                                    'علامة المدير',
                                    widget.isAdminFlag! ? 'نعم' : 'لا',
                                    widget.isAdminFlag!
                                        ? Icons.admin_panel_settings
                                        : Icons.person),
                              if (widget.firstSystemDepartment != null)
                                _buildInfoRow(
                                    'القسم',
                                    widget.firstSystemDepartment!,
                                    Icons.business),
                              if (widget.firstSystemCenter != null)
                                _buildInfoRow(
                                    'المركز',
                                    widget.firstSystemCenter!,
                                    Icons.location_city),
                              if (widget.firstSystemSalary != null)
                                _buildInfoRow(
                                    'الراتب',
                                    widget.firstSystemSalary!,
                                    Icons.attach_money),
                              if (widget.ftthPermissions != null)
                                _buildInfoRow(
                                    'صلاحيات FTTH المحلية',
                                    'متوفرة (${widget.ftthPermissions!.keys.length} صلاحية)',
                                    Icons.vpn_key),
                              if (widget.userRoleHeader != null)
                                _buildInfoRow('رأس دور المستخدم',
                                    widget.userRoleHeader!, Icons.badge),
                              if (widget.clientAppHeader != null)
                                _buildInfoRow('معرف التطبيق',
                                    widget.clientAppHeader!, Icons.smartphone),
                            ]),
                          ],

                          // تم حذف الأقسام التفصيلية الكبيرة للشبكة والجهاز لتقليل التكرار.

                          // 19. معلومات التواريخ والأوقات الشاملة
                          Builder(builder: (context) {
                            final dateInfo = <Widget>[];

                            // التاريخ والوقت الحالي
                            final now = DateTime.now();
                            dateInfo.add(_buildInfoRow(
                              'تاريخ ووقت فتح الصفحة',
                              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
                                  '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
                              Icons.access_time,
                            ));

                            // من معلومات الاشتراك الحالي
                            if (widget.expires != null) {
                              dateInfo.add(_buildInfoRow(
                                'تاريخ انتهاء الاشتراك الحالي',
                                widget.expires!,
                                Icons.event_busy,
                              ));
                            }

                            if (widget.startedAt != null) {
                              dateInfo.add(_buildInfoRow(
                                'تاريخ بداية الاشتراك',
                                widget.startedAt!,
                                Icons.event_available,
                              ));
                            }

                            if (widget.remainingDays != null) {
                              dateInfo.add(_buildInfoRow(
                                'الأيام المتبقية',
                                '${widget.remainingDays} يوم',
                                Icons.timer,
                              ));
                            }

                            // من بيانات العميل
                            if (widget.customerDataMain != null) {
                              final data = widget.customerDataMain!;

                              if (data.containsKey('created_date')) {
                                dateInfo.add(_buildInfoRow(
                                  'تاريخ إنشاء الحساب',
                                  data['created_date'].toString(),
                                  Icons.person_add,
                                ));
                              }

                              if (data.containsKey('last_login')) {
                                dateInfo.add(_buildInfoRow(
                                  'آخر تسجيل دخول',
                                  data['last_login'].toString(),
                                  Icons.login,
                                ));
                              }

                              if (data.containsKey('subscription_start_date')) {
                                dateInfo.add(_buildInfoRow(
                                  'تاريخ بداية الاشتراك (من البيانات)',
                                  data['subscription_start_date'].toString(),
                                  Icons.play_arrow,
                                ));
                              }

                              if (data.containsKey('subscription_end_date')) {
                                dateInfo.add(_buildInfoRow(
                                  'تاريخ نهاية الاشتراك (من البيانات)',
                                  data['subscription_end_date'].toString(),
                                  Icons.stop,
                                ));
                              }

                              if (data.containsKey('last_payment_date')) {
                                dateInfo.add(_buildInfoRow(
                                  'تاريخ آخر دفعة',
                                  data['last_payment_date'].toString(),
                                  Icons.payment,
                                ));
                              }

                              if (data.containsKey('next_billing_date')) {
                                dateInfo.add(_buildInfoRow(
                                  'تاريخ الفاتورة القادمة',
                                  data['next_billing_date'].toString(),
                                  Icons.schedule,
                                ));
                              }

                              if (data.containsKey('account_creation_date')) {
                                dateInfo.add(_buildInfoRow(
                                  'تاريخ إنشاء الحساب',
                                  data['account_creation_date'].toString(),
                                  Icons.account_circle,
                                ));
                              }
                            }

                            // من بيانات ONT
                            if (widget.deviceOntInfo != null) {
                              final ontData = widget.deviceOntInfo!;

                              if (ontData.containsKey('installation_date')) {
                                dateInfo.add(_buildInfoRow(
                                  'تاريخ تركيب الجهاز',
                                  ontData['installation_date'].toString(),
                                  Icons.build,
                                ));
                              }

                              if (ontData.containsKey('last_maintenance')) {
                                dateInfo.add(_buildInfoRow(
                                  'تاريخ آخر صيانة',
                                  ontData['last_maintenance'].toString(),
                                  Icons.build_circle,
                                ));
                              }

                              if (ontData.containsKey('warranty_expiry')) {
                                dateInfo.add(_buildInfoRow(
                                  'تاريخ انتهاء الضمان',
                                  ontData['warranty_expiry'].toString(),
                                  Icons.shield,
                                ));
                              }

                              if (ontData
                                  .containsKey('first_activation_date')) {
                                dateInfo.add(_buildInfoRow(
                                  'تاريخ أول تفعيل',
                                  ontData['first_activation_date'].toString(),
                                  Icons.power_settings_new,
                                ));
                              }

                              if (ontData.containsKey('last_reboot')) {
                                dateInfo.add(_buildInfoRow(
                                  'تاريخ آخر إعادة تشغيل',
                                  ontData['last_reboot'].toString(),
                                  Icons.restart_alt,
                                ));
                              }
                            }

                            // معلومات إضافية للوقت
                            dateInfo.add(_buildInfoRow(
                              'المنطقة الزمنية',
                              'توقيت عراقي محلي (GMT+3)',
                              Icons.public,
                            ));

                            dateInfo.add(_buildInfoRow(
                              'التوقيت المحلي',
                              DateFormat('yyyy-MM-dd HH:mm:ss').format(now),
                              Icons.schedule,
                            ));

                            // من معلومات الاشتراك التجريبي
                            if (trialExpiredAt != null) {
                              dateInfo.add(_buildInfoRow(
                                'تاريخ انتهاء التجربة',
                                trialExpiredAt!.split('T')[0],
                                Icons.access_time_outlined,
                              ));
                            }

                            return Column(
                              children: [
                                SizedBox(height: 16),
                                _buildInfoSection(
                                    '📅 معلومات التواريخ والأوقات الشاملة',
                                    dateInfo),
                              ],
                            );
                          }),

                          // 20. إحصائيات سريعة
                          SizedBox(height: 16),
                          _buildInfoSection('📈 إحصائيات سريعة', [
                            _buildInfoRow(
                                'إجمالي المعلومات المُمررة',
                                '${_getTotalPassedDataCount()} عنصر',
                                Icons.analytics),
                            _buildInfoRow(
                                'المعلومات الأساسية', '4 عناصر', Icons.info),
                            _buildInfoRow(
                                'المعلومات الاختيارية',
                                '${_getTotalPassedDataCount() - 4} عنصر',
                                Icons.info_outline),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
                // أزرار محسنة في الأسفل
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // زر الإغلاق
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(Icons.close_rounded, size: 20),
                            label: Text(
                              'إغلاق',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 4,
                              shadowColor: Colors.grey.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                      // زر النسخ
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          child: ElevatedButton.icon(
                            onPressed: () {
                              // يمكن إضافة وظيفة نسخ المعلومات هنا
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      Icon(Icons.copy,
                                          color: Colors.white, size: 20),
                                      SizedBox(width: 8),
                                      Text('ميزة النسخ ستكون متاحة قريباً'),
                                    ],
                                  ),
                                  backgroundColor: Colors.green.shade600,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              );
                            },
                            icon: Icon(Icons.copy_rounded, size: 20),
                            label: Text(
                              'نسخ',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 4,
                              shadowColor: Colors.green.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // دالة مساعدة لحساب إجمالي عدد المعلومات المُمررة
  int _getTotalPassedDataCount() {
    int count = 4; // الأساسية: userId, subscriptionId, authToken, activatedBy

    // معلومات المستخدم الأساسية
    if (widget.userName != null) count++;
    if (widget.userPhone != null) count++;
    if (widget.currentStatus != null) count++;
    if (widget.deviceUsername != null) count++;
    if (widget.currentBaseService != null) count++;

    // معلومات الخدمات والتواريخ
    if (widget.services != null) count += widget.services!.length;
    if (widget.remainingDays != null) count++;
    if (widget.expires != null) count++;
    if (widget.startedAt != null) count++;

    // معلومات الشبكة
    if (widget.fdtDisplayValue != null) count++;
    if (widget.fatDisplayValue != null) count++;

    // صلاحيات API
    if (widget.importantFtthApiPermissions != null) {
      count += widget.importantFtthApiPermissions!.length;
    }

    // بيانات مسبقة
    if (widget.initialAllowedActions != null) {
      count += widget.initialAllowedActions!.keys.length;
    }
    if (widget.initialBundles != null) {
      count += widget.initialBundles!.keys.length;
    }
    if (widget.initialPartnerWalletBalance != null) count++;
    if (widget.initialCustomerWalletBalance != null) count++;

    // أذونات التطبيق
    count += 2; // hasServerSavePermission, hasWhatsAppPermission

    // === المعلومات الإضافية الجديدة ===
    if (widget.deviceSerial != null) count++;
    if (widget.macAddress != null) count++;
    if (widget.deviceModel != null) count++;
    if (widget.gpsLatitude != null) count++;
    if (widget.gpsLongitude != null) count++;
    if (widget.customerAddress != null) count++;
    if (widget.deviceOntInfo != null) {
      count += widget.deviceOntInfo!.keys.length;
    }
    if (widget.customerDataMain != null) {
      count += widget.customerDataMain!.keys.length;
    }

    // معلومات النظام الأول
    if (widget.firstSystemPermissions != null) count++;
    if (widget.isAdminFlag != null) count++;
    if (widget.firstSystemDepartment != null) count++;
    if (widget.firstSystemCenter != null) count++;
    if (widget.firstSystemSalary != null) count++;
    if (widget.ftthPermissions != null) {
      count += widget.ftthPermissions!.keys.length;
    }
    if (widget.userRoleHeader != null) count++;
    if (widget.clientAppHeader != null) count++;

    return count;
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Colors.blue.shade50.withValues(alpha: 0.3),
            Colors.indigo.shade50.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.blue.shade200.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان القسم
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.blue.shade100.withValues(alpha: 0.8),
                  Colors.indigo.shade100.withValues(alpha: 0.6),
                  Colors.purple.shade100.withValues(alpha: 0.4),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.blue.shade200.withValues(alpha: 0.7),
                  width: 1,
                ),
              ),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
                shadows: [
                  Shadow(
                    color: Colors.white.withValues(alpha: 0.8),
                    offset: const Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          // محتوى القسم
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.grey.shade200.withValues(alpha: 0.8),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 0,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue.shade100.withValues(alpha: 0.6),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.blue.shade200.withValues(alpha: 0.8),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: Colors.blue.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.indigo.shade800,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// بناء أزرار الإجراءات
  Widget _buildActionButtons() {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Column(
        children: [
          // بطاقة أزرار العمليات الرئيسية
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade50, Colors.teal.shade50],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.green.shade300,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.15),
                  blurRadius: 10,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  // تم إخفاء عنوان بطاقة الإجراءات لتوفير المساحة

                  // المرحلة الأولى (زر حساب السعر) ألغيت: نعرض الأزرار فقط بعد توفر السعر
                  if (priceDetails != null) ...[
                    // تم نقل زر إعادة حساب السعر إلى القائمة الجانبية (القائمة اليمنى)
                    Builder(builder: (ctx) {
                      final buttons = <Widget>[];

                      // عرض الأزرار فقط إذا كان لديه صلاحية إنشاء اشتراكات
                      if (_canCreateOrRenew) {
                        // زر التفعيل التلقائي (تجديد/تغيير/شراء الاشتراك)
                        buttons.add(
                          ElevatedButton.icon(
                            onPressed: executeRenewalOrPurchase,
                            icon: Icon(
                              isNewSubscription
                                  ? Icons.shopping_cart
                                  : Icons.flash_on,
                              size: 20,
                            ),
                            label: Text(
                              isNewSubscription
                                  ? "شراء الاشتراك"
                                  : "تفعيل تلقائي",
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isNewSubscription
                                  ? Colors.green.shade600
                                  : Colors.blueAccent.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: const BorderSide(
                                      color: Colors.black, width: 1)),
                              elevation: 2,
                            ),
                          ),
                        );

                        // زر التفعيل العادي - يفتح نافذة بها الأزرار الفرعية
                        buttons.add(
                          ElevatedButton.icon(
                            onPressed: () => _showManualActivationDialog(),
                            icon: const Icon(Icons.touch_app, size: 20),
                            label: const Text(
                              "تفعيل عادي",
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: const BorderSide(
                                      color: Colors.black, width: 1)),
                              elevation: 2,
                            ),
                          ),
                        );
                      }

                      return _buildTwoPerRowButtons(buttons);
                    }),
                  ],

                  // (تمت إزالة التكرار: الأزرار تُعرض الآن فقط داخل القسم بعد حساب السعر)
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// بناء تفاصيل الأسعار
  Widget _buildPriceDetails() {
    if (priceDetails == null) {
      final bool stillPreparing =
          (!_priceAttempted && (isLoading || !_walletsFetched)) ||
              (selectedPlan == null || selectedCommitmentPeriod == null);
      return Container(
        margin: EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Card(
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                if (_isCalculatingExtendPrice) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.green.shade50,
                          Colors.teal.shade50.withValues(alpha: 0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withValues(alpha: 0.2),
                                spreadRadius: 2,
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.green.shade600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'جاري حساب سعر التمديد...',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_extendPriceError != null) ...[
                  Icon(Icons.error_outline,
                      size: 46, color: Colors.red.shade400),
                  const SizedBox(height: 10),
                  Text(
                    _extendPriceError!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      _autoFetchExtendPriceIfNeeded();
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('إعادة الحساب'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white),
                  ),
                ] else if (stillPreparing) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.purple.shade50,
                          Colors.indigo.shade50.withValues(alpha: 0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.purple.shade200),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.purple.withValues(alpha: 0.2),
                                spreadRadius: 2,
                                blurRadius: 7,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: CircularProgressIndicator(
                            strokeWidth: 3.2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.purple.shade600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'جاري تجهيز البيانات...',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.purple.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'تحضير الأرصدة والخطة والسعر',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.purple.shade600,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // إظهار أيقونة انتظار جميلة بدلاً من التنبيه إذا لم تكن هناك محاولة حساب سابقة أو لا يوجد خطأ محدد
                  if (_priceError == null) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.blue.shade50,
                            Colors.indigo.shade50.withValues(alpha: 0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withValues(alpha: 0.2),
                                  spreadRadius: 2,
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: CircularProgressIndicator(
                              strokeWidth: 3.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.blue.shade600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'جاري جلب تفاصيل السعر...',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.blue.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'يرجى الانتظار لحظة',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade600,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // في حالة وجود خطأ محدد، اعرضه مع زر إعادة المحاولة
                    Icon(Icons.error_outline,
                        size: 46, color: Colors.red.shade400),
                    const SizedBox(height: 10),
                    Text(
                      _priceError!,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.red.shade700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        // إعادة محاولة يدوية: نصفر المؤشرات ونحاول من جديد
                        setState(() {
                          _priceAttempted = false;
                          _priceError = null;
                          isLoading = true;
                          priceDetails = null;
                        });
                        fetchPriceDetails();
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('إعادة المحاولة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 18),
                      ),
                    ),
                  ]
                ]
              ],
            ),
          ),
        ),
      );
    }

    String totalPrice = '0'; // الإجمالي من النظام (قبل الخصم اليدوي)
    String currency = 'IQD';
    // تم إخفاء مربع السعر الأساسي، لذا لم نعد بحاجة لمتغير basePrice المستقل هنا
    // String basePrice = '0';
    String discount = '0';
    try {
      final tp = priceDetails!['totalPrice'];
      // لم نعد نحتاج لقيمة basePrice هنا بعد إخفاء مربع السعر الأساسي
      // final bp = priceDetails!['basePrice'];
      final dc = priceDetails!['discount'];
      totalPrice = _asDouble(tp).toStringAsFixed(0);
      // تم حذف استخدام basePrice لأن مربع السعر الأساسي مخفي
      discount = _asDouble(dc).toStringAsFixed(0);
      if (tp is Map && tp['currency'] != null) {
        currency = tp['currency'].toString();
      } else if (priceDetails!['currency'] != null) {
        currency = priceDetails!['currency'].toString();
      }
      // discountPercentage لم يعد يُعرض في الواجهة بعد التبسيط
    } catch (_) {
      // إبقاء القيم الافتراضية في حال أي خطأ غير متوقع
    }

    // حساب الإجمالي النهائي بعد الخصم اليدوي
    final double originalTotal = double.tryParse(totalPrice) ?? 0.0;
    final double discountVal = double.tryParse(discount) ?? 0.0;
    final double effectiveTotal = systemDiscountEnabled
        ? originalTotal
        : (originalTotal + discountVal); // استرجاع الخصم عند الإيقاف
    final double finalTotal =
        (effectiveTotal - manualDiscount).clamp(0, double.infinity);

    return Container(
      margin: EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.teal.shade50, Colors.cyan.shade50],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.teal.shade300,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.teal.withValues(alpha: 0.15),
              blurRadius: 10,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // دمج بطاقة مصدر الدفع وبطاقة طريقة الدفع في صف واحد (ارتفاع موحد)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Card(
                        margin: const EdgeInsets.only(right: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                              color: Colors.teal.shade300, width: 1.2),
                        ),
                        color: Colors.white.withValues(alpha: 0.9),
                        elevation: 2,
                        shadowColor: Colors.teal.withValues(alpha: 0.2),
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(Icons.account_balance_wallet,
                                        size: 18, color: Colors.teal.shade700),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('مصدر الدفع',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal.shade800)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildWalletSourceSelectBox(
                                      title: 'المحفظة الرئيسية',
                                      balance: walletBalance,
                                      value: 'main',
                                      color: Colors.teal,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  if (hasCustomerWallet)
                                    Expanded(
                                      child: _buildWalletSourceSelectBox(
                                        title: 'محفظة المشترك',
                                        balance: customerWalletBalance,
                                        value: 'customer',
                                        color: Colors.deepPurple,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildPaymentMethodSelector(
                          margin: const EdgeInsets.only(left: 4)),
                    ),
                  ],
                ),
              ),
              // تم تبسيط البطاقة بحذف العنوان لتقليل الضوضاء البصرية

              // فاصل متدرج جميل بين صف مصدر الدفع وصف الخصم
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.teal.shade300,
                      Colors.purple.shade300,
                      Colors.orange.shade300
                    ],
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),

              // صف السعر (نفس الارتفاع للمربعات)
              // تم إخفاء مربع "السعر الأساسي" بناءً على طلب المستخدم، وتم تمديد بطاقة الخصم لتأخذ العرض الكامل
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildDiscountCard(
                        title: "الخصم (من النظام)",
                        value: systemDiscountEnabled
                            ? _formatNumber(int.tryParse(discount) ?? 0)
                            : '0',
                        currency: currency,
                        enabled: systemDiscountEnabled,
                        onToggle: (v) =>
                            setState(() => systemDiscountEnabled = v),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // حقل الخصم اليدوي (اختياري) تم نقله ليكون في نفس الصف مع خصم النظام
                    Expanded(
                      child: Container(
                        alignment: Alignment.center,
                        constraints: const BoxConstraints(minHeight: 78),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.grey.shade50,
                              Colors.blueGrey.shade50
                            ],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.blueGrey.shade300, width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueGrey.withValues(alpha: 0.1),
                              blurRadius: 6,
                              spreadRadius: 1,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9\.]')),
                          ],
                          decoration: InputDecoration(
                            isDense: false,
                            labelText: 'الخصم (اختياري)',
                            labelStyle: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.blueGrey.shade700),
                            hintText: '0',
                            suffixText: currency,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                    color: Colors.blueGrey.shade300)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                    color: Colors.blueGrey.shade600, width: 2)),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 12),
                          ),
                          onChanged: (v) {
                            setState(() {
                              manualDiscount =
                                  double.tryParse(v.trim().isEmpty ? '0' : v) ??
                                      0.0;
                              if (manualDiscount < 0) manualDiscount = 0.0;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (showBasePriceLowerThanWalletAlert) ...[
                SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.amber.shade700, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تنبيه الرصيد',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.amber.shade800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'الرصيد المتاح أقل من السعر الأساسي، يرجى تعبئة الرصيد قبل المتابعة.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: 8),

              // فاصل أسود عريض بين صف الخصم وصف السعر
              Container(
                width: double.infinity,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),

              // تم نقل بطاقة مصدر الدفع إلى أعلى (داخل قسم اختيار الخطة والمدة)

              // السعر الإجمالي (تم نقل الخصم اليدوي للأعلى بجوار خصم النظام)
              // تخفيض ارتفاع بطاقة السعر الإجمالي وبطاقة الرصيد لتساوي بطاقة الخصم
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: _priceWalletCardsHeight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black, width: 1),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "السعر الإجمالي (بعد الخصم)",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                "${_formatNumber(finalTotal.round())} $currency",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ),
                            if (manualDiscount > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  "يشمل خصم: -${_formatNumber(manualDiscount.round())} $currency",
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                      child: _buildWalletBalanceCard(
                          compact: true, fixedHeight: _priceWalletCardsHeight)),
                ],
              ),

              // تم نقل حقل الخصم اليدوي ليظهر مع السعر الإجمالي في الأسفل

              // تم إخفاء عرض نسبة الخصم لزيادة البساطة

              SizedBox(height: 12),

              // مربع نص الملاحظات مع قائمة الفنيين في نفس الصف
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // مربع الملاحظات
                    Expanded(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.black, width: 1),
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _notesController,
                              maxLines: 2,
                              textAlign: TextAlign.right,
                              decoration: InputDecoration(
                                hintText:
                                    'إضافة ملاحظات حول الاشتراك (اختياري)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      BorderSide(color: Colors.grey.shade300),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: Colors.blue.shade600, width: 2),
                                ),
                                contentPadding: const EdgeInsets.all(12),
                                filled: true,
                                fillColor: Colors.white,
                                // زر التحديث في الجهة اليسرى
                                prefixIcon: isDataSavedToServer
                                    ? Container(
                                        margin: const EdgeInsets.all(4),
                                        child: IconButton(
                                          onPressed: () =>
                                              _updateNotesOnServer(),
                                          icon: const Icon(Icons.edit_note,
                                              size: 20),
                                          tooltip: 'تحديث الملاحظات في الخادم',
                                          style: IconButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            padding: const EdgeInsets.all(6),
                                            minimumSize: const Size(32, 32),
                                          ),
                                        ),
                                      )
                                    : null,
                                // زر التشغيل/الإيقاف في الجهة اليمنى
                                suffixIcon: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      isNotesEnabled = !isNotesEnabled;
                                    });
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isNotesEnabled
                                          ? Colors.green
                                          : Colors.grey.shade400,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isNotesEnabled
                                            ? Colors.green.shade700
                                            : Colors.grey.shade600,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isNotesEnabled
                                              ? Icons.toggle_on
                                              : Icons.toggle_off,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          isNotesEnabled ? 'مفعل' : 'معطل',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              onChanged: (value) {
                                subscriptionNotes = value;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // قائمة الفنيين
                    Expanded(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.black, width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.engineering,
                                    color: Colors.green.shade700, size: 20),
                                const SizedBox(width: 6),
                                Text(
                                  'فني التوصيل',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // صف يحتوي على القائمة المنسدلة وزر الإرسال بجانبها
                            Row(
                              children: [
                                // القائمة المنسدلة
                                Expanded(
                                  flex: 2,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: selectedTechnician,
                                    decoration: InputDecoration(
                                      hintText: 'اختر فني',
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: Colors.grey.shade300),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: Colors.green.shade600,
                                            width: 2),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                    isExpanded: true,
                                    items: [
                                      // خيار لإلغاء التحديد
                                      const DropdownMenuItem<String>(
                                        value: null,
                                        child: Text(
                                          'بدون فني',
                                          style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                      // قائمة الفنيين المحملة
                                      ...technicians.map((tech) {
                                        return DropdownMenuItem<String>(
                                          value: tech['name'],
                                          child: Text(
                                            tech['name'] ?? '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }),
                                    ],
                                    onChanged: (value) {
                                      setState(() {
                                        selectedTechnician = value;

                                        // إضافة اسم الفني للملاحظات
                                        if (value != null) {
                                          String currentNotes =
                                              _notesController.text;
                                          String technicianNote = value;

                                          // التحقق من عدم وجود نفس الفني مسبقاً
                                          bool hasTechnician = technicians.any(
                                              (tech) => currentNotes.contains(
                                                  tech['name'] ?? ''));

                                          if (!hasTechnician) {
                                            // إضافة اسم الفني في بداية الملاحظات
                                            if (currentNotes.isNotEmpty) {
                                              _notesController.text =
                                                  "$technicianNote\n$currentNotes";
                                            } else {
                                              _notesController.text =
                                                  technicianNote;
                                            }
                                          } else {
                                            // استبدال اسم الفني الحالي
                                            String newNotes = currentNotes;
                                            for (var tech in technicians) {
                                              if (tech['name'] != null &&
                                                  tech['name']!.isNotEmpty) {
                                                newNotes = newNotes.replaceAll(
                                                    RegExp(
                                                        r'^' +
                                                            RegExp.escape(
                                                                tech['name']!) +
                                                            r'\n?',
                                                        multiLine: true),
                                                    '');
                                              }
                                            }
                                            if (newNotes.isNotEmpty) {
                                              _notesController.text =
                                                  "$technicianNote\n$newNotes";
                                            } else {
                                              _notesController.text =
                                                  technicianNote;
                                            }
                                          }
                                          subscriptionNotes =
                                              _notesController.text;
                                        } else {
                                          // إزالة اسم الفني من الملاحظات إذا تم إلغاء الاختيار
                                          String currentNotes =
                                              _notesController.text;
                                          String newNotes = currentNotes;
                                          for (var tech in technicians) {
                                            if (tech['name'] != null &&
                                                tech['name']!.isNotEmpty) {
                                              newNotes = newNotes.replaceAll(
                                                  RegExp(
                                                      r'^' +
                                                          RegExp.escape(
                                                              tech['name']!) +
                                                          r'\n?',
                                                      multiLine: true),
                                                  '');
                                            }
                                          }
                                          _notesController.text =
                                              newNotes.trim();
                                          subscriptionNotes =
                                              _notesController.text;
                                        }
                                      });
                                    },
                                  ),
                                ),

                                const SizedBox(width: 8),

                                // زر إرسال للفني (ظاهر دائماً)
                                Expanded(
                                  flex: 1,
                                  child: ElevatedButton.icon(
                                    onPressed: _isSendingToTechnician
                                        ? null
                                        : () =>
                                            _sendSelectedTechnicianMessage(),
                                    icon: _isSendingToTechnician
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                      Colors.white),
                                            ),
                                          )
                                        : const Icon(Icons.send, size: 18),
                                    label: Text(
                                      _isSendingToTechnician
                                          ? 'إرسال...'
                                          : 'إرسال',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade600,
                                      foregroundColor: Colors.white,
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10, horizontal: 8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 6),

              // معلومات إضافية
              // تم إخفاء قسم المعلومات الإضافية (نوع الخدمة/المدة/طريقة الدفع)
            ],
          ),
        ),
      ),
    );
  }

  // تم حذف دالة _buildPriceInfoCard بعد إخفاء مربع السعر الأساسي

  // بطاقة الخصم مع المفتاح بنفس ارتفاع بطاقة السعر الأساسي
  Widget _buildDiscountCard({
    required String title,
    required String value,
    required String currency,
    required bool enabled,
    required ValueChanged<bool> onToggle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade50, Colors.amber.shade50],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.15),
            blurRadius: 6,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // العنوان (بداية المربع)
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // المبلغ (الوسط)
          Expanded(
            flex: 4,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$value $currency',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          // المفتاح (نهاية المربع)
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    enabled ? 'مفعل' : 'متوقف',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color:
                          enabled ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Transform.scale(
                    scale: 1.15,
                    child: Switch(
                      value: enabled,
                      activeThumbColor: Colors.green,
                      onChanged: onToggle,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // إجمالي نهائي بعد الخصم اليدوي
  double _getFinalTotal() {
    if (priceDetails == null) return 0.0;
    final orig = _asDouble(priceDetails!['totalPrice']);
    final discount = _asDouble(priceDetails!['discount']);
    // إذا كان خصم النظام متوقف نعيد الخصم إلى الإجمالي
    final adjusted = systemDiscountEnabled ? orig : (orig + discount);
    final finalVal = (adjusted - manualDiscount);
    return finalVal.isFinite ? (finalVal < 0 ? 0.0 : finalVal) : 0.0;
  }

  // تقييم وإعداد تنبيه إذا كان السعر الأساسي أكبر من الرصيد المتاح (محفظة العضو إن وُجدت وإلا الأساسية)
  void _evaluatePriceWalletRelation() {
    if (priceDetails == null) {
      showBasePriceLowerThanWalletAlert = false;
      return; // لا يوجد سعر حالياً
    }
    try {
      final base = priceDetails!['basePrice'];
      final double baseVal = _asDouble(base);
      final double currentBalance =
          hasTeamMemberWallet ? teamMemberWalletBalance : walletBalance;
      final bool newState =
          baseVal > 0 && currentBalance >= 0 && baseVal > currentBalance;
      if (newState != showBasePriceLowerThanWalletAlert) {
        setState(() => showBasePriceLowerThanWalletAlert = newState);
      }
    } catch (_) {
      // تجاهل أي أخطاء تحويل
    }
  }

  // تم إزالة صفوف المعلومات الإضافية بعد تبسيط البطاقة

  // دالة للتأكد من أن الخطة المحددة موجودة في القائمة المتاحة
  void _validateSelectedPlan() {
    if (selectedPlan == null) return; // لم يختر المستخدم بعد
    if (!availablePlans.contains(selectedPlan)) {
      String normalizedPlan =
          SubscriptionInfo._normalizePlanName(selectedPlan!);
      if (availablePlans.contains(normalizedPlan)) {
        selectedPlan = normalizedPlan;
      } else {
        selectedPlan = availablePlans[0];
      }
    }
  }

  /// حساب السعر الشهري بناءً على السعر الإجمالي وفترة الالتزام
  double _calculateMonthlyPrice(dynamic totalPrice, int commitmentPeriod) {
    if (totalPrice == null || commitmentPeriod == 0) return 0.0;

    final price = totalPrice is String
        ? double.tryParse(totalPrice) ?? 0.0
        : (totalPrice as num).toDouble();
    return price / commitmentPeriod;
  }

  // تحويل أي قيمة (Map/num/String) إلى double آمن
  double _asDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is Map && value['value'] != null) {
      final v = value['value'];
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  // ويدجت شارة اختيار مصدر المحفظة
  Widget _buildWalletSourceSelectBox(
      {required String title,
      required double balance,
      required String value,
      required Color color}) {
    final bool selected = _selectedWalletSource == value;
    // اعتماد نفس الارتفاع الموحد المستخدم في أزرار (نقد / أجل)
    const double unifiedBoxHeight = 72;
    // منطق تلوين خاص بالمحفظة الرئيسية فقط
    Color? overrideBorder;
    Color? overrideFill;
    if (value == 'main') {
      final bool enough = balance > 100000;
      overrideBorder = enough ? Colors.green.shade600 : Colors.red.shade600;
      overrideFill = enough
          ? Colors.green.shade50.withValues(alpha: selected ? 0.5 : 0.35)
          : Colors.red.shade50.withValues(alpha: selected ? 0.5 : 0.35);
    }
    return InkWell(
      onTap: () => setState(() => _selectedWalletSource = value),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: unifiedBoxHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: value == 'main'
              ? (overrideFill ?? Colors.white)
              : (selected ? color.withValues(alpha: 0.10) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value == 'main'
                ? (overrideBorder ?? (selected ? color : Colors.grey.shade400))
                : (selected ? color : Colors.grey.shade400),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: (value == 'main' ? (overrideBorder ?? color) : color)
                        .withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  )
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  value == 'main' ? Icons.account_balance : Icons.person,
                  color: value == 'main'
                      ? (balance > 100000
                          ? Colors.green.shade700
                          : Colors.red.shade700)
                      : (selected ? color : Colors.grey.shade700),
                  size: 20,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: selected
                      ? Icon(
                          Icons.check_circle,
                          key: ValueKey('${value}sel2'),
                          color: value == 'main'
                              ? (balance > 100000
                                  ? Colors.green.shade600
                                  : Colors.red.shade600)
                              : color,
                          size: 20,
                        )
                      : Icon(
                          Icons.radio_button_unchecked,
                          key: ValueKey('${value}unsel2'),
                          color: value == 'main'
                              ? (balance > 100000
                                  ? Colors.green.shade400
                                  : Colors.red.shade400)
                              : Colors.grey.shade500,
                          size: 18,
                        ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (value == 'main')
              Text(
                balance > 100000 ? 'الرصيد متوفر' : 'لا يوجد رصيد كافي',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              )
            else
              Text(
                'الرصيد: ${_formatNumber(balance.round())}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // تطبيع شكل بيانات السعر ليصبح دائماً: { totalPrice:{value,currency}, basePrice:{..}, discount:{..}, ... }
  Map<String, dynamic> _normalizePriceModel(Map<String, dynamic> model) {
    final dynamic total = model['totalPrice'];
    final dynamic base = model['basePrice'];
    final dynamic discount = model['discount'];

    String currency = 'IQD';
    if (total is Map && total['currency'] != null) {
      currency = total['currency'].toString();
    } else if (model['currency'] != null) {
      currency = model['currency'].toString();
    }

    final double totalVal = _asDouble(total);
    final double baseVal = _asDouble(base ?? totalVal);
    final double discVal = _asDouble(discount ?? 0);

    return {
      'totalPrice': {'value': totalVal, 'currency': currency},
      'basePrice': {'value': baseVal, 'currency': currency},
      'discount': {'value': discVal, 'currency': currency},
      'discountPercentage': model['discountPercentage'] ?? 0,
      'monthlyPrice': selectedCommitmentPeriod == null
          ? {'value': 0.0, 'currency': currency}
          : {
              'value':
                  _calculateMonthlyPrice(totalVal, selectedCommitmentPeriod!),
              'currency': currency,
            },
    };
  }

  /// عرض نافذة التفعيل العادي مع الأزرار الفرعية
  void _showManualActivationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.touch_app,
                  color: Colors.orange.shade700, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'التفعيل العادي',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // زر فتح صفحة المشترك
              _buildManualDialogButton(
                icon: Icons.person_pin,
                label: 'فتح صفحة المشترك',
                color: Colors.blueAccent.shade700,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _openCustomerDetailsPage();
                },
              ),
              const SizedBox(height: 12),

              // زر تم التفعيل (حفظ في الخادم)
              if (widget.hasServerSavePermission)
                _buildManualDialogButton(
                  icon: Icons.cloud_upload,
                  label: 'تم التفعيل',
                  color: _isSavedToSheets ? Colors.green : Colors.red,
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    if (!_isSavedToSheets) {
                      _saveOnlyToServer();
                    }
                  },
                ),
              if (widget.hasServerSavePermission) const SizedBox(height: 12),

              // زر الطباعة
              _buildManualDialogButton(
                icon: _isPrinting ? Icons.hourglass_empty : Icons.print,
                label: _isPrinting ? 'جاري الطباعة...' : 'طباعة',
                color: _isPrinting
                    ? Colors.grey.shade500
                    : const Color(0xFFEF6C00),
                onPressed: _isPrinting
                    ? null
                    : () {
                        Navigator.of(ctx).pop();
                        printSubscriptionReceipt();
                      },
              ),
              const SizedBox(height: 12),

              // زر إرسال واتساب فقط
              if (widget.hasWhatsAppPermission)
                _buildManualDialogButton(
                  icon: Icons.send,
                  label: 'إرسال واتساب فقط',
                  color: const Color.fromARGB(255, 183, 40, 226),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _sendWhatsAppOnly();
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  /// بناء زر في نافذة التفعيل العادي
  Widget _buildManualDialogButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Colors.black, width: 1),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  /// فتح رابط تفاصيل العميل في المتصفح
  Future<void> _openCustomerDetailsPage() async {
    // محاولة الحصول على معرف العميل من معلومات الاشتراك أولاً، ثم من widget.userId
    String? customerId = subscriptionInfo?.customerId;
    if (customerId == null || customerId.isEmpty) {
      customerId = widget.userId;
    }

    if (customerId.isEmpty) {
      if (mounted) {
        ftthShowSnackBar(
          context,
          const SnackBar(
            content: Text('معرف العميل غير متوفر!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // في حال مدة الالتزام المختارة أكبر من شهر نعرض نفس تنبيه (المدة الطويلة) المستخدم في إعادة الحساب
    if (selectedCommitmentPeriod != null && selectedCommitmentPeriod! > 1) {
      // حساب سعر معاينة لإظهار التفاصيل داخل التحذير (اختياري)
      Map<String, dynamic>? preview;
      try {
        // إظهار انتظار صغير أثناء الحساب
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    spreadRadius: 2,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.indigo.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'جاري تجهيز التحذير...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.indigo.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'يرجى الانتظار',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.indigo.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        preview = await _calculatePricePreview();
      } catch (_) {
        // تجاهل أي خطأ
      } finally {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(); // إغلاق الانتظار
        }
      }

      bool? confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          // تجهيز نص الأسعار إن توفرت
          Widget priceWidget = const SizedBox.shrink();
          if (preview != null) {
            final total =
                _formatNumber(_asDouble(preview['totalPrice']).round());
            final currency = (preview['totalPrice'] is Map &&
                    preview['totalPrice']['currency'] != null)
                ? preview['totalPrice']['currency'].toString()
                : (preview['currency']?.toString() ?? 'IQD');
            final monthly =
                _formatNumber(_asDouble(preview['monthlyPrice']).ceil());
            final base = _formatNumber(_asDouble(preview['basePrice']).round());
            final discount =
                _formatNumber(_asDouble(preview['discount']).round());
            priceWidget = Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red.shade200, Colors.red.shade100],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade400, width: 1.3),
                boxShadow: [
                  BoxShadow(
                      color: Colors.red.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.price_change,
                          size: 20, color: Colors.red.shade900),
                      const SizedBox(width: 6),
                      Text('تفاصيل الأسعار',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade900)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _buildPriceLine('السعر الأساسي', base, currency),
                  _buildPriceLine('الخصم', discount, currency),
                  _buildPriceLine('السعر الشهري', monthly, currency),
                  Divider(color: Colors.red.shade300, height: 14),
                  _buildPriceLine('السعر الإجمالي', total, currency,
                      emphasize: true),
                ],
              ),
            );
          }

          return AlertDialog(
            backgroundColor: const Color(0xFFFFF5F5),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.red.shade400, width: 2.2),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Colors.red.shade600, Colors.red.shade300],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تنبيه مدة اشتراك طويلة',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.red.shade800,
                              letterSpacing: 0.3,
                            ),
                          ),
                          Text(
                            'الفترة المختارة تتجاوز شهراً واحداً',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200, width: 1.2),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                          fontSize: 13.2,
                          height: 1.45,
                          color: Colors.red.shade900),
                      children: [
                        const TextSpan(
                            text:
                                'أنت على وشك فتح صفحة المشترك بينما تم اختيار مدة التزام '),
                        TextSpan(
                          text:
                              '$selectedCommitmentPeriod شهر${selectedCommitmentPeriod == 1 ? '' : 'اً'}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                            color: Colors.red.shade800,
                          ),
                        ),
                        const TextSpan(text: ' للخطة '),
                        TextSpan(
                          text: (selectedPlan ?? 'الحالية'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                        const TextSpan(
                            text:
                                '.\n\nيرجى التأكد أن هذه المدة مناسبة قبل المتابعة، لأن الحسابات أو العمليات التالية قد تعتمد عليها.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 18, color: Colors.red.shade700),
                            const SizedBox(width: 6),
                            Text('ملاحظات سريعة',
                                style: TextStyle(
                                    fontSize: 13.2,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red.shade800)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _buildBullet(
                            'الفترات الطويلة تزيد السعر الإجمالي مباشرة.'),
                        _buildBullet(
                            'تأكد من موافقة المشترك قبل تثبيت العملية.'),
                        _buildBullet(
                            'يمكنك العودة وتعديل المدة إذا كان ذلك غير مقصود.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (priceWidget is! SizedBox) ...[
                    Text('ملخص السعر',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.red.shade800)),
                    const SizedBox(height: 6),
                    priceWidget,
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time,
                              size: 18, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                'لم يتم حساب السعر المبدئي – يمكنك حسابه من زر (إعادة حساب السعر).',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.orange.shade800,
                                    height: 1.3)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text('هل تريد المتابعة وفتح صفحة المشترك؟',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade900)),
                ],
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('إلغاء'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(
                              color: Colors.red.shade300, width: 1.4),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          textStyle:
                              const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        icon: const Icon(Icons.open_in_new, size: 20),
                        label: const Text('متابعة وفتح'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          elevation: 3,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w800, letterSpacing: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );

      if (confirm != true) {
        return; // المستخدم ألغى
      }
    }

    final customerDetailsUrl =
        'https://admin.ftth.iq/customer-details/$customerId/details/view';

    try {
      final uri = Uri.parse(customerDetailsUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        debugPrint('✅ تم فتح رابط تفاصيل العميل: $customerDetailsUrl');

        // عرض رسالة نجاح للمستخدم
        if (mounted) {
          ftthShowSnackBar(
            context,
            SnackBar(
              content: Text('تم فتح صفحة تفاصيل العميل في المتصفح'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception('لا يمكن فتح الرابط');
      }
    } catch (e) {
      debugPrint('❌ خطأ في فتح رابط تفاصيل العميل: $e');
      if (mounted) {
        ftthShowSnackBar(
          context,
          SnackBar(
            content: Text('فشل في فتح رابط تفاصيل العميل: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // عنصر سطر سعر داخل حوار التحذير
  Widget _buildPriceLine(String title, String value, String currency,
      {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                color: emphasize ? Colors.red.shade900 : Colors.red.shade800,
              ),
            ),
          ),
          Text(
            '$value $currency',
            style: TextStyle(
              fontSize: emphasize ? 13 : 12,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: emphasize ? Colors.red.shade900 : Colors.red.shade800,
            ),
          ),
        ],
      ),
    );
  }

  // عنصر نقطة توضيحية داخل التحذير
  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5, left: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Colors.red.shade600, Colors.red.shade300],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.2,
                height: 1.4,
                color: Colors.red.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // توليد شبكة أزرار (كل صف يحتوي زرَين). إذا كان العدد فردياً يملأ بمساحة فارغة.
  Widget _buildTwoPerRowButtons(List<Widget> buttons) {
    if (buttons.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    for (int i = 0; i < buttons.length; i += 2) {
      final first = Expanded(child: buttons[i]);
      final second = (i + 1 < buttons.length)
          ? Expanded(child: buttons[i + 1])
          : const Expanded(child: SizedBox());
      rows.add(Row(
        children: [
          first,
          const SizedBox(width: 10),
          second,
        ],
      ));
      if (i + 2 < buttons.length) {
        rows.add(const SizedBox(height: 12));
      }
    }
    return Column(children: rows);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _buildPageTheme(context),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 56,
          elevation: 0,
          centerTitle: true,
          title: Text(
            isNewSubscription ? 'شراء اشتراك جديد' : 'تجديد او تغيير الاشتراك',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF3949AB), Color(0xFF6A1B9A)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
          ),
          foregroundColor: Colors.white,
          actionsIconTheme: const IconThemeData(color: Colors.white),
          actions: [
            // زر فتح صفحة المشترك في GPON - تم إخفاؤه بناءً على طلب المستخدم
            // IconButton(
            //   tooltip: 'فتح صفحة المشترك',
            //   icon: const Icon(Icons.person_pin),
            //   onPressed: _openCustomerDetailsPage,
            // ),
            // زر الانتقال للصفحة الرئيسية
            IconButton(
              tooltip: 'الصفحة الرئيسية',
              icon: const Icon(Icons.home),
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => HomePage(
                      username: widget.activatedBy,
                      authToken: widget.authToken,
                    ),
                  ),
                  (Route<dynamic> route) => false,
                );
              },
            ),
            // زر القائمة الجانبية (بعد زر الرجوع الافتراضي)
            Builder(
              builder: (context) => IconButton(
                tooltip: 'القائمة الجانبية',
                icon: const Icon(Icons.menu_open),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
            // زر إعدادات واتساب (رقم + QR) - تم إخفاؤه
            // IconButton(
            //   tooltip: 'إعداد الواتساب',
            //   icon: const Icon(Icons.settings_phone),
            //   onPressed: _openWhatsAppSettingsDialog,
            // ),
            // 🔒 تم إخفاء زر إرسال واتساب من الشريط العلوي حسب الطلب، مع الاحتفاظ بالكود للتفعيل لاحقاً.
            /*
      IconButton(
        tooltip: _isGeneratingWhatsAppLink
          ? 'جاري التوليد...'
          : 'إرسال واتساب',
        icon: _isGeneratingWhatsAppLink
          ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.white),
          )
          : const Icon(Icons.chat),
        onPressed: _isGeneratingWhatsAppLink
          ? null
          : _generateAndOpenWhatsAppLink,
      ),
      */
            IconButton(
              icon: const Icon(Icons.refresh, size: 24),
              tooltip: 'إعادة تحميل الصفحة',
              onPressed: () async {
                setState(() => isLoading = true);
                await fetchSubscriptionDetails();
              },
            ),
          ],
        ),
        body: AnimatedBuilder(
          animation: _bgAnim,
          builder: (context, _) {
            // تدرج لوني ديناميكي هادئ: نمزج مجموعتين من الألوان بناءً على قيمة الأنيميشن
            final t = _bgAnim.value;
            Color lerp(Color a, Color b) => Color.lerp(a, b, t)!;
            final c1 = lerp(const Color(0xFFE8ECF7), const Color(0xFFF2E9FB));
            final c2 = lerp(const Color(0xFFF6F9FE), const Color(0xFFEDE7F6));
            final c3 = lerp(const Color(0xFFE3F2FD), const Color(0xFFEDE7FF));
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [c1, c2, c3],
                ),
              ),
              child: SafeArea(
                child: isLoading
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.indigo.shade50,
                                Colors.blue.shade50.withValues(alpha: 0.8),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.indigo.shade200, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.indigo.withValues(alpha: 0.1),
                                spreadRadius: 3,
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.indigo.withValues(alpha: 0.2),
                                      spreadRadius: 2,
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: CircularProgressIndicator(
                                  strokeWidth: 4,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.indigo.shade600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'جاري تحميل معلومات الاشتراك...',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.indigo.shade800,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'يرجى الانتظار لحظات',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.indigo.shade600,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : (subscriptionInfo == null)
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline,
                                    size: 64, color: Colors.red),
                                const SizedBox(height: 16),
                                const Text(
                                  'لم يتم العثور على معلومات الاشتراك',
                                  style: TextStyle(fontSize: 18),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'معرف المستخدم: ${widget.userId}',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                Text(
                                  'معرف الاشتراك: ${widget.subscriptionId}',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: fetchSubscriptionDetails,
                                  child: const Text('إعادة المحاولة'),
                                ),
                              ],
                            ),
                          )
                        : RawScrollbar(
                            controller: _contentScrollController,
                            thumbVisibility: true,
                            trackVisibility: true,
                            thickness: 8,
                            radius: const Radius.circular(12),
                            crossAxisMargin: 4,
                            mainAxisMargin: 4,
                            child: SingleChildScrollView(
                              controller: _contentScrollController,
                              padding: const EdgeInsets.all(6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  _animated(0, _buildErrorMessage()),
                                  _animated(1, _buildCustomerInfo()),
                                  const SizedBox(height: 4),
                                  // إخفاء _buildQuickStats (غير مستخدمة) للحفاظ على المساحة
                                  _animated(
                                      2,
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _buildPlanSelection(),
                                          const SizedBox(height: 6),
                                          _buildPriceDetails(),
                                        ],
                                      )),
                                  const SizedBox(height: 4),
                                  _animated(3, _buildActionButtons()),
                                  const SizedBox(height: 4),
                                ],
                              ),
                            ),
                          ),
              ),
            );
          },
        ),
        // القائمة الجانبية اليمنى تحتوي زر إعادة حساب السعر
        endDrawer: Drawer(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // رأس القائمة
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade700, Colors.blue.shade500],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.menu_open, color: Colors.white, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'أدوات وخيارات إضافية',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        'معلومات وأدوات مساعدة',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // المعلومات المُمررة - محسنة
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.blue.shade50,
                        Colors.indigo.shade50.withValues(alpha: 0.5),
                        Colors.purple.shade50.withValues(alpha: 0.3),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.blue.shade200.withValues(alpha: 0.6),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.1),
                        spreadRadius: 1,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.blue.shade400,
                            Colors.indigo.shade500,
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.3),
                            spreadRadius: 1,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.info_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    title: Text(
                      'المعلومات المُمررة',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.indigo.shade800,
                      ),
                    ),
                    subtitle: Text(
                      'عرض جميع البيانات والمعلومات الإضافية بتصميم محسن',
                      style: TextStyle(
                        color: Colors.indigo.shade600,
                        fontSize: 13,
                        height: 1.2,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.blue.shade300,
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showPassedDataDialog();
                    },
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.orange),
                  title: const Text('تعديل القوالب'),
                  subtitle: const Text('قوالب الطباعة والواتساب'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showPasswordDialog();
                  },
                ),
                const Divider(),
                // زر التفعيل المباشر
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.green.shade50,
                        Colors.teal.shade50.withValues(alpha: 0.5),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green.shade300,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.15),
                        spreadRadius: 1,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green.shade500, Colors.teal.shade600],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withValues(alpha: 0.3),
                            spreadRadius: 1,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.flash_on,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    title: Text(
                      'التفعيل المباشر',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.green.shade800,
                      ),
                    ),
                    subtitle: Text(
                      isNewSubscription
                          ? 'شراء الاشتراك من API'
                          : 'تجديد أو تغيير الاشتراك',
                      style: TextStyle(
                        color: Colors.green.shade600,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.green.shade400),
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: Colors.green.shade700,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showDirectActivationDialog();
                    },
                  ),
                ),
                const Divider(),
                // تم نقل زر إعادة حساب السعر إلى بجوار بطاقة فترة الالتزام في المحتوى الرئيسي
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'أدوات إضافية',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (priceDetails == null)
                          const Text(
                            'لا توجد تفاصيل سعر بعد. اختر الخطة والفترة أولاً.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          )
                        else
                          Text(
                            'السعر الحالي: ${_formatNumber(_asDouble(priceDetails!['totalPrice']).round())}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // سمة محلية موحّدة لهذه الصفحة لجعل المظهر أبسط وأجمل بدون تغيير العناصر
  ThemeData _buildPageTheme(BuildContext context) {
    final base = Theme.of(context);
    final primary = Colors.indigo;
    final secondary = Colors.purple;
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: primary,
        secondary: secondary,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.grey.shade50,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.black, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          minimumSize: const Size.fromHeight(44),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          side: BorderSide(color: primary.withValues(alpha: 0.25)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: primary, width: 1.8),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
        color: primary,
      ),
      iconTheme: base.iconTheme.copyWith(color: primary.shade700),
    );
  }

  /// عرض رسالة الخطأ
  Widget _buildErrorMessage() {
    if (errorMessage.isEmpty) return SizedBox.shrink();

    final isSuccess = errorMessage.contains("بنجاح");
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14),
      margin: EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: isSuccess ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSuccess ? Colors.green.shade200 : Colors.red.shade200,
          width: 1,
        ),
      ),
      child: Text(
        errorMessage,
        style: TextStyle(
          fontSize: 16,
          color: isSuccess ? Colors.green.shade900 : Colors.red.shade900,
        ),
      ),
    );
  }

  // شريط إحصائيات سريع على شكل Chips لعرض أهم القيم بسرعة
  // تم إزالة _buildQuickStats (كانت فارغة) للحفاظ على نظافة الكود.

  Color _statusChipColor(String? status) {
    final s = (status ?? '').toLowerCase();
    if (s.contains('active') || s.contains('نشط')) return Colors.green.shade700;
    if (s.contains('trial') || s.contains('تجري')) {
      return Colors.orange.shade700;
    }
    if (s.contains('suspend') || s.contains('معلق')) {
      return Colors.amber.shade700;
    }
    if (s.contains('expired') || s.contains('منته')) return Colors.red.shade700;
    return Colors.blueGrey.shade700;
  }

  /// نص الحالة بالعربية: فعال / غير فعال
  String _statusTextAr(String? status) {
    final s = (status ?? '').toLowerCase();
    if (s.contains('active') || s.contains('نشط')) return 'فعال';
    return 'غير فعال';
  }

  bool _isActiveStatus(String? status) {
    final s = (status ?? '').toLowerCase();
    return s.contains('active') || s.contains('نشط');
  }

  /// محدد طريقة الدفع
  Widget _buildPaymentMethodSelector({EdgeInsetsGeometry? margin}) {
    return Card(
      margin: margin ?? EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      elevation: 2,
      shadowColor: Colors.purple.withValues(alpha: 0.2),
      color: Colors.white.withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.purple.shade300, width: 1.2),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.payment,
                      color: Colors.purple.shade700, size: 16),
                ),
                SizedBox(width: 8),
                Text(
                  "طريقة الدفع",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.purple.shade700,
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            // صف واحد: نقد + أجل + ماستر + وكيل
            Row(
              children: [
                Expanded(
                  child: _buildPaymentOptionButton(
                    title: 'نقد',
                    icon: Icons.attach_money,
                    baseColor: Colors.green.shade600,
                    selected: selectedPaymentMethod == 'نقد',
                    onTap: () => setState(() {
                      selectedPaymentMethod = 'نقد';
                      _selectedLinkedAgent = null;
                      _selectedLinkedTechnician = null;
                    }),
                  ),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: _buildPaymentOptionButton(
                    title: 'أجل',
                    icon: Icons.schedule,
                    baseColor: Colors.orange.shade600,
                    selected: selectedPaymentMethod == 'أجل',
                    onTap: () => setState(() {
                      selectedPaymentMethod = 'أجل';
                      _selectedLinkedAgent = null;
                      _selectedLinkedTechnician = null;
                    }),
                  ),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: _buildPaymentOptionButton(
                    title: 'ماستر',
                    icon: Icons.credit_card,
                    baseColor: Colors.purple.shade600,
                    selected: selectedPaymentMethod == 'ماستر',
                    onTap: () => setState(() {
                      selectedPaymentMethod = 'ماستر';
                      _selectedLinkedAgent = null;
                      _selectedLinkedTechnician = null;
                    }),
                  ),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: _buildPaymentOptionButton(
                    title: 'وكيل',
                    icon: Icons.store,
                    baseColor: Colors.blue.shade600,
                    selected: selectedPaymentMethod == 'وكيل',
                    onTap: () => setState(() {
                      selectedPaymentMethod = 'وكيل';
                      _selectedLinkedTechnician = null;
                    }),
                  ),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: _buildPaymentOptionButton(
                    title: 'فني',
                    icon: Icons.engineering,
                    baseColor: Colors.teal.shade600,
                    selected: selectedPaymentMethod == 'فني',
                    onTap: () => setState(() {
                      selectedPaymentMethod = 'فني';
                      _selectedLinkedAgent = null;
                    }),
                  ),
                ),
              ],
            ),
            // دروبداون اختيار الوكيل (يظهر فقط عند اختيار "وكيل")
            if (selectedPaymentMethod == 'وكيل') ...[
              SizedBox(height: 8),
              _buildAgentDropdown(),
            ],
            // دروبداون اختيار الفني (يظهر فقط عند اختيار "فني")
            if (selectedPaymentMethod == 'فني') ...[
              SizedBox(height: 8),
              _buildTechnicianDropdown(),
            ],
          ],
        ),
      ),
    );
  }

  /// زر/خيار طريقة دفع كبير وموحد الحجم
  Widget _buildPaymentOptionButton({
    required String title,
    required IconData icon,
    required Color baseColor,
    required bool selected,
    required VoidCallback onTap,
  }) {
    // ارتفاع موحد للصناديق (نقد / أجل / المحفظة الرئيسية / محفظة المشترك)
    const double unifiedBoxHeight = 52; // مناسب لصف واحد من 4 أزرار
    final Color bg =
        selected ? baseColor.withValues(alpha: 0.12) : Colors.white;
    final Color borderColor =
        selected ? baseColor : baseColor.withValues(alpha: 0.35);
    final Color textColor = selected ? baseColor : Colors.black87;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        height: unifiedBoxHeight, // استخدام الارتفاع الموحد
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: baseColor, size: 18)
            else
              Icon(Icons.radio_button_unchecked, color: borderColor, size: 16),
          ],
        ),
      ),
    );
  }

  /// معلومات المحفظة - تم إخفاؤها حسب الطلب، والدالة أزيلت لعدم الاستخدام

  /// جلب قائمة الوكلاء من السيرفر (يُستدعى في initState فقط — لا يُستدعى عند الضغط)
  Future<void> _loadAgentsList({bool forceReload = false}) async {
    if ((!forceReload && _agentsList.isNotEmpty) || _isLoadingAgents) return;
    if (mounted) {
      setState(() {
        _isLoadingAgents = true;
        _agentsLoadError = null;
      });
    }
    try {
      final companyId = VpsAuthService.instance.currentCompanyId;
      final url = companyId != null
          ? 'https://api.ramzalsadara.tech/api/ftth-accounting/agents-list?companyId=$companyId'
          : 'https://api.ramzalsadara.tech/api/ftth-accounting/agents-list';

      final token = _getAuthToken();
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'X-Api-Key': 'sadara-internal-2024-secure-key',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      debugPrint('📡 استجابة الوكلاء: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          setState(() {
            _agentsList = List<Map<String, dynamic>>.from(data['data']);
          });
        }
        debugPrint('✅ تم جلب ${_agentsList.length} وكيل');
      } else {
        setState(
            () => _agentsLoadError = 'خطأ من السيرفر (${response.statusCode})');
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب الوكلاء: $e');
      if (mounted) {
        setState(() => _agentsLoadError = 'خطأ في الاتصال');
      }
    } finally {
      if (mounted) setState(() => _isLoadingAgents = false);
    }
  }

  /// جلب قائمة الفنيين من السيرفر (يُستدعى في initState فقط — لا يُستدعى عند الضغط)
  Future<void> _loadTechniciansList({bool forceReload = false}) async {
    if ((!forceReload && _techniciansList.isNotEmpty) ||
        _isLoadingTechnicians) {
      return;
    }
    if (mounted) {
      setState(() {
        _isLoadingTechnicians = true;
        _techniciansLoadError = null;
      });
    }
    try {
      final companyId = VpsAuthService.instance.currentCompanyId;
      final url = companyId != null
          ? 'https://api.ramzalsadara.tech/api/ftth-accounting/technicians-list?companyId=$companyId'
          : 'https://api.ramzalsadara.tech/api/ftth-accounting/technicians-list';

      final token = _getAuthToken();
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'X-Api-Key': 'sadara-internal-2024-secure-key',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      debugPrint('📡 استجابة الفنيين: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          setState(() {
            _techniciansList = List<Map<String, dynamic>>.from(data['data']);
          });
        }
        debugPrint('✅ تم جلب ${_techniciansList.length} فني');
      } else {
        setState(() =>
            _techniciansLoadError = 'خطأ من السيرفر (${response.statusCode})');
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب الفنيين: $e');
      if (mounted) {
        setState(() => _techniciansLoadError = 'خطأ في الاتصال');
      }
    } finally {
      if (mounted) setState(() => _isLoadingTechnicians = false);
    }
  }

  /// الحصول على توكن المصادقة
  String? _getAuthToken() {
    return VpsAuthService.instance.accessToken;
  }

  /// دروبداون اختيار الوكيل مع بحث (Autocomplete — بدون اتصال شبكة عند الضغط)
  Widget _buildAgentDropdown() {
    if (_isLoadingAgents) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.blue.shade600)),
          const SizedBox(width: 8),
          Text('جاري تحميل الوكلاء...',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ]),
      );
    }
    if (_agentsList.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(Icons.info_outline, size: 16, color: Colors.orange.shade600),
          const SizedBox(width: 6),
          Text('لا يوجد وكلاء متاحين',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _loadAgentsList(forceReload: true),
            icon: Icon(Icons.refresh, size: 14, color: Colors.blue.shade600),
            label: Text('تحديث',
                style: TextStyle(fontSize: 11, color: Colors.blue.shade600)),
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero, minimumSize: const Size(50, 28)),
          ),
        ]),
      );
    }

    // إذا تم اختيار وكيل — أظهر بطاقته مع زر تغيير
    if (_selectedLinkedAgent != null) {
      final name = _selectedLinkedAgent!['Name']?.toString() ?? '';
      final code = _selectedLinkedAgent!['AgentCode']?.toString() ?? '';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.shade400, width: 1.5),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              radius: 16,
              child: Icon(Icons.store, color: Colors.blue.shade700, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.blue.shade800)),
                  if (code.isNotEmpty)
                    Text(code,
                        style: TextStyle(
                            fontSize: 11, color: Colors.blue.shade600)),
                ],
              ),
            ),
            Icon(Icons.check_circle, color: Colors.blue.shade600, size: 20),
            const SizedBox(width: 4),
            InkWell(
              onTap: () => setState(() => _selectedLinkedAgent = null),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, color: Colors.red.shade400, size: 18),
              ),
            ),
          ],
        ),
      );
    }

    // حقل بحث مع قائمة منسدلة
    return Autocomplete<Map<String, dynamic>>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.trim().isEmpty) {
          return _agentsList;
        }
        final q = textEditingValue.text.trim().toLowerCase();
        return _agentsList.where((agent) {
          final name = (agent['Name']?.toString() ?? '').toLowerCase();
          final code = (agent['AgentCode']?.toString() ?? '').toLowerCase();
          final phone = (agent['PhoneNumber']?.toString() ?? '').toLowerCase();
          return name.contains(q) || code.contains(q) || phone.contains(q);
        });
      },
      displayStringForOption: (agent) {
        final name = agent['Name']?.toString() ?? '';
        final code = agent['AgentCode']?.toString() ?? '';
        return '$name${code.isNotEmpty ? " ($code)" : ""}';
      },
      onSelected: (agent) => setState(() => _selectedLinkedAgent = agent),
      optionsMaxHeight: 200,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            hintText: 'ابحث عن وكيل بالاسم أو الكود...',
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            prefixIcon:
                Icon(Icons.search, color: Colors.blue.shade400, size: 20),
            suffixIcon:
                Icon(Icons.store, color: Colors.blue.shade600, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: Colors.blue.shade50,
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topRight,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade300),
                color: Colors.white,
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (_, i) {
                  final agent = options.elementAt(i);
                  final name = agent['Name']?.toString() ?? '';
                  final code = agent['AgentCode']?.toString() ?? '';
                  final phone = agent['PhoneNumber']?.toString() ?? '';
                  return InkWell(
                    onTap: () => onSelected(agent),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.blue.shade100,
                            radius: 16,
                            child: Icon(Icons.store,
                                color: Colors.blue.shade700, size: 16),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                if (code.isNotEmpty || phone.isNotEmpty)
                                  Text(
                                    [
                                      if (code.isNotEmpty) code,
                                      if (phone.isNotEmpty) phone
                                    ].join(' • '),
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// دروبداون اختيار الفني مع بحث (Autocomplete — بدون اتصال شبكة عند الضغط)
  Widget _buildTechnicianDropdown() {
    if (_isLoadingTechnicians) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.teal.shade600)),
          const SizedBox(width: 8),
          Text('جاري تحميل الفنيين...',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ]),
      );
    }
    if (_techniciansList.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(Icons.info_outline, size: 16, color: Colors.orange.shade600),
          const SizedBox(width: 6),
          Text('لا يوجد فنيين متاحين',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _loadTechniciansList(forceReload: true),
            icon: Icon(Icons.refresh, size: 14, color: Colors.teal.shade600),
            label: Text('تحديث',
                style: TextStyle(fontSize: 11, color: Colors.teal.shade600)),
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero, minimumSize: const Size(50, 28)),
          ),
        ]),
      );
    }

    // إذا تم اختيار فني — أظهر بطاقته مع زر تغيير
    if (_selectedLinkedTechnician != null) {
      final name = _selectedLinkedTechnician!['Name']?.toString() ?? '';
      final username = _selectedLinkedTechnician!['Username']?.toString() ?? '';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.teal.shade400, width: 1.5),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.teal.shade100,
              radius: 16,
              child: Icon(Icons.engineering,
                  color: Colors.teal.shade700, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.teal.shade800)),
                  if (username.isNotEmpty)
                    Text(username,
                        style: TextStyle(
                            fontSize: 11, color: Colors.teal.shade600)),
                ],
              ),
            ),
            Icon(Icons.check_circle, color: Colors.teal.shade600, size: 20),
            const SizedBox(width: 4),
            InkWell(
              onTap: () => setState(() => _selectedLinkedTechnician = null),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, color: Colors.red.shade400, size: 18),
              ),
            ),
          ],
        ),
      );
    }

    // حقل بحث مع قائمة منسدلة
    return Autocomplete<Map<String, dynamic>>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.trim().isEmpty) {
          return _techniciansList;
        }
        final q = textEditingValue.text.trim().toLowerCase();
        return _techniciansList.where((tech) {
          final name = (tech['Name']?.toString() ?? '').toLowerCase();
          final username = (tech['Username']?.toString() ?? '').toLowerCase();
          final phone = (tech['PhoneNumber']?.toString() ?? '').toLowerCase();
          return name.contains(q) || username.contains(q) || phone.contains(q);
        });
      },
      displayStringForOption: (tech) {
        final name = tech['Name']?.toString() ?? '';
        final username = tech['Username']?.toString() ?? '';
        return '$name${username.isNotEmpty ? " ($username)" : ""}';
      },
      onSelected: (tech) => setState(() => _selectedLinkedTechnician = tech),
      optionsMaxHeight: 200,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            hintText: 'ابحث عن فني بالاسم أو المعرف...',
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            prefixIcon:
                Icon(Icons.search, color: Colors.teal.shade400, size: 20),
            suffixIcon:
                Icon(Icons.engineering, color: Colors.teal.shade600, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: Colors.teal.shade50,
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topRight,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.teal.shade300),
                color: Colors.white,
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (_, i) {
                  final tech = options.elementAt(i);
                  final name = tech['Name']?.toString() ?? '';
                  final username = tech['Username']?.toString() ?? '';
                  final phone = tech['PhoneNumber']?.toString() ?? '';
                  return InkWell(
                    onTap: () => onSelected(tech),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.teal.shade100,
                            radius: 16,
                            child: Icon(Icons.engineering,
                                color: Colors.teal.shade700, size: 16),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                if (username.isNotEmpty || phone.isNotEmpty)
                                  Text(
                                    [
                                      if (username.isNotEmpty) username,
                                      if (phone.isNotEmpty) phone
                                    ].join(' • '),
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// تحويل طريقة الدفع العربية لكود إنجليزي للسيرفر
  String _getCollectionTypeCode(String method) {
    switch (method) {
      case 'نقد':
        return 'cash';
      case 'أجل':
        return 'credit';
      case 'ماستر':
        return 'master';
      case 'وكيل':
        return 'agent';
      case 'فني':
        return 'technician';
      default:
        return 'cash';
    }
  }

  /// تسجيل مبلغ على حساب الوكيل/الفني المختار بعد نجاح العملية
  Future<void> _recordChargeToLinkedPerson(double amount) async {
    try {
      final token = _getAuthToken();
      if (token == null) return;

      final customerName =
          subscriptionInfo?.customerName ?? widget.userName ?? '';
      final planName = selectedPlan ?? '';

      if (selectedPaymentMethod == 'وكيل' && _selectedLinkedAgent != null) {
        // تسجيل أجور على الوكيل
        final agentId = _selectedLinkedAgent!['Id']?.toString();
        if (agentId == null || agentId.isEmpty) return;

        final url = '${_getBaseUrl()}/agents/$agentId/charge';
        final body = {
          'Amount': amount,
          'Category':
              'RenewalSubscription', // enum كنص — السيرفر يستخدم JsonStringEnumConverter
          'Description': 'تجديد اشتراك: $customerName - $planName',
          'ReferenceNumber': widget.subscriptionId,
          'Notes': 'عبر شاشة التجديد - ${widget.activatedBy}',
        };

        debugPrint('📤 إرسال charge للوكيل: $url');
        debugPrint('📤 Body: ${jsonEncode(body)}');

        final response = await http
            .post(
              Uri.parse(url),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 10));

        debugPrint(
            '📥 استجابة charge: ${response.statusCode} — ${response.body}');

        if (response.statusCode == 200) {
          debugPrint(
              '✅ تم تسجيل $amount على حساب الوكيل: ${_selectedLinkedAgent!['Name']}');
        } else {
          debugPrint(
              '⚠️ فشل تسجيل الأجور على الوكيل: ${response.statusCode} — ${response.body}');
        }
      } else if (selectedPaymentMethod == 'فني' &&
          _selectedLinkedTechnician != null) {
        // تسجيل تحصيل على الفني
        final techId = _selectedLinkedTechnician!['Id']?.toString();
        if (techId == null || techId.isEmpty) return;

        final companyId = VpsAuthService.instance.currentCompanyId ?? '';
        final url = '${_getBaseUrl()}/accounting/collections';
        final body = {
          'TechnicianId': techId,
          'Amount': amount,
          'Description': 'تجديد اشتراك: $customerName - $planName',
          'PaymentMethod': 'cash',
          'ReceivedBy': widget.activatedBy,
          'Notes': 'عبر شاشة التجديد - اشتراك ${widget.subscriptionId}',
          'CompanyId': companyId,
        };

        debugPrint('📤 إرسال collection للفني: $url');
        debugPrint('📤 Body: ${jsonEncode(body)}');

        final response = await http
            .post(
              Uri.parse(url),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 10));

        debugPrint(
            '📥 استجابة collection: ${response.statusCode} — ${response.body}');

        if (response.statusCode == 200) {
          debugPrint(
              '✅ تم تسجيل $amount على حساب الفني: ${_selectedLinkedTechnician!['Name']}');
        } else {
          debugPrint(
              '⚠️ فشل تسجيل التحصيل على الفني: ${response.statusCode} — ${response.body}');
        }
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في تسجيل المبلغ على الوكيل/الفني: $e');
      // لا نوقف العملية — التسجيل اختياري
    }
  }

  /// الحصول على Base URL للسيرفر
  String _getBaseUrl() {
    return 'https://api.ramzalsadara.tech/api';
  }

  /// بطاقة رصيد المحفظة - منفصلة عن بطاقة طريقة الدفع وتعرض في نفس الصف
  Widget _buildWalletBalanceCard({bool compact = false, double? fixedHeight}) {
    final bool showTeamMember = hasTeamMemberWallet;
    final double displayBalance =
        showTeamMember ? teamMemberWalletBalance : walletBalance;
    final String displayTitle = showTeamMember ? 'رصيد محفظة العضو' : 'الرصيد';
    final MaterialColor baseSwatch =
        showTeamMember ? Colors.deepPurple : Colors.teal;
    final String? lastUpd = walletLastUpdated != null
        ? '${walletLastUpdated!.hour.toString().padLeft(2, '0')}:${walletLastUpdated!.minute.toString().padLeft(2, '0')}:${walletLastUpdated!.second.toString().padLeft(2, '0')}'
        : null;
    return Card(
      margin: EdgeInsets.symmetric(vertical: compact ? 0 : 2, horizontal: 2),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.black, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10, vertical: compact ? 6 : 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2, right: 2),
                    child: Text(
                      displayTitle,
                      style: TextStyle(
                        fontSize: compact ? 11 : 13,
                        fontWeight: FontWeight.w600,
                        color: baseSwatch.shade700,
                      ),
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => fetchWalletBalance(),
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 2.5 : 4.0),
                    child: AnimatedRotation(
                      turns: isWalletLoading ? 1 : 0,
                      duration: const Duration(seconds: 1),
                      curve: Curves.linear,
                      child: Icon(
                        Icons.refresh,
                        size: compact ? 18 : 20,
                        color: isWalletLoading
                            ? baseSwatch.shade400
                            : baseSwatch.shade700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 4 : 6),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => fetchWalletBalance(),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(compact ? 8 : 12),
                decoration: BoxDecoration(
                  color: baseSwatch.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: baseSwatch.shade200),
                ),
                child: Center(
                  child: isWalletLoading
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: compact ? 14 : 18,
                              height: compact ? 14 : 18,
                              child: CircularProgressIndicator(
                                strokeWidth: compact ? 2.0 : 2.4,
                                color: baseSwatch.shade600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'جاري التحديث...',
                              style: TextStyle(
                                fontSize: compact ? 12 : 14,
                                fontWeight: FontWeight.w600,
                                color: baseSwatch.shade700,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          _formatNumber(displayBalance.round()),
                          style: TextStyle(
                            fontSize: compact ? 16 : 20,
                            fontWeight: FontWeight.bold,
                            color: baseSwatch.shade900,
                          ),
                        ),
                ),
              ),
            ),
            if (walletError != null && !isWalletLoading) ...[
              SizedBox(height: compact ? 4 : 6),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: compact ? 14 : 16, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      walletError!,
                      style: TextStyle(
                        fontSize: compact ? 9.5 : 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (lastUpd != null && !isWalletLoading) ...[
              SizedBox(height: compact ? 4 : 6),
              Text(
                'آخر تحديث: $lastUpd',
                style: TextStyle(
                  fontSize: compact ? 8.5 : 10,
                  fontWeight: FontWeight.w400,
                  color: baseSwatch.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // تم حذف _buildWalletAndPaymentRow بعد نقل بطاقة الرصيد بجانب السعر الإجمالي

  /// معلومات المشترك - مُحسّنة للشاشات الصغيرة
  Widget _buildCustomerInfo() {
    return Card(
      elevation: 4,
      shadowColor: Colors.indigo.withValues(alpha: 0.3),
      margin: EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      color: Colors.indigo.shade50, // لون خلفية البطاقة
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.indigo.shade300, width: 1.5),
      ),
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNewSubscription)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(8),
                margin: EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade100, Colors.indigo.shade100],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.info_outline,
                          color: Colors.blue.shade700, size: 24),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "اشتراك جديد - سيتم تحويل الاشتراك التجريبي إلى مدفوع",
                        style: TextStyle(
                          color: Colors.blue.shade900,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Icon(Icons.person, color: Colors.indigo, size: 24),
                SizedBox(width: 8),
                Text(
                  "معلومات المشترك",
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                Spacer(),
                // شارة الحالة الحالية مختصرة في الهيدر
                if (subscriptionInfo?.status != null &&
                    subscriptionInfo!.status.trim().isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusChipColor(subscriptionInfo!.status)
                          .withValues(alpha: 0.12),
                      border: Border.all(
                          color: _statusChipColor(subscriptionInfo!.status)
                              .withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isActiveStatus(subscriptionInfo!.status)
                              ? Icons.check_circle
                              : Icons.cancel,
                          size: 16,
                          color: _statusChipColor(subscriptionInfo!.status),
                        ),
                        SizedBox(width: 4),
                        Text(
                          _statusTextAr(subscriptionInfo!.status),
                          style: TextStyle(
                            color: _statusChipColor(subscriptionInfo!.status),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            SizedBox(height: 8),
            // الاسم ومعرف المشترك في صف واحد (مربعين جنباً لجنب)
            LayoutBuilder(
              builder: (ctx, constraints) {
                final bool narrow = constraints.maxWidth <
                    520; // تكديس عمودي للشاشات الضيقة جداً
                final children = <Widget>[
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(8),
                      margin: EdgeInsets.only(bottom: narrow ? 8 : 0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black, width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.account_circle,
                              color: Colors.indigo.shade400, size: 20),
                          SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "الاسم",
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.indigo.shade400,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  subscriptionInfo!.customerName,
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo.shade900,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: narrow ? 0 : 8),
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black, width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.phone,
                              color: Colors.teal.shade400, size: 20),
                          SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "رقم الهاتف",
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.teal.shade400,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  _getCustomerPhoneNumber() ?? 'غير متوفر',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal.shade900,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 4),
                          IconButton(
                            tooltip: 'نسخ',
                            icon: Icon(Icons.copy, color: Colors.teal),
                            iconSize: 24,
                            onPressed: () async {
                              final phone = _getCustomerPhoneNumber();
                              if (phone != null) {
                                await Clipboard.setData(
                                    ClipboardData(text: phone));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تم نسخ رقم الهاتف'),
                                    backgroundColor: Colors.green,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('رقم الهاتف غير متوفر'),
                                    backgroundColor: Colors.orange,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ];
                return narrow
                    ? Column(children: children)
                    : Row(children: children);
              },
            ),
            SizedBox(height: 8),
            // تم إخفاء قسم معرف المشترك المنفصل لتجنب التكرار بعد عرضه مكان FBG
            const SizedBox.shrink(),
            if (isNewSubscription) ...[
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  // إضافة إطار أسود لمعرف الاشتراك التجريبي
                  border: Border.all(color: Colors.black, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.article_outlined,
                        color: Colors.orange.shade600, size: 18),
                    SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "معرف الاشتراك التجريبي",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.orange.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            widget.subscriptionId,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// اختيار الخطة - محسّن للشاشات الصغيرة
  Widget _buildPlanSelection() {
    return Card(
      elevation: 4,
      shadowColor: Colors.purple.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Colors.purple.shade300,
          width: 1.5,
        ),
      ),
      color: Colors.purple.shade50,
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // (تم نقل بطاقة مصدر الدفع إلى بطاقة حساب الأسعار)
            // تم دمج اختيار نوع الخدمة وفترة الالتزام في صف واحد (مع استجابة للشاشات الضيقة)
            LayoutBuilder(
              builder: (ctx, constraints) {
                final bool narrow = constraints.maxWidth < 560;
                final planField = Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: "نوع الخدمة الجديدة",
                      prefixIcon:
                          Icon(Icons.router, color: Colors.indigo, size: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: selectedPlan == null
                              ? Colors.red
                              : Colors.indigo.shade200,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: selectedPlan == null
                                ? Colors.red
                                : Colors.indigo,
                            width: 2),
                      ),
                      errorText:
                          selectedPlan == null ? 'اختر نوع الخدمة' : null,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      labelStyle: TextStyle(fontSize: 14),
                      isDense: false,
                    ),
                    initialValue: selectedPlan,
                    onChanged: (value) {
                      setState(() {
                        selectedPlan = value!;
                        priceDetails = null;
                      });
                      _scheduleAutoPriceFetch();
                    },
                    items: availablePlans.map((plan) {
                      return DropdownMenuItem(
                        value: plan,
                        child: Text(
                          plan,
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      );
                    }).toList(),
                  ),
                );
                final periodField = Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: InputDecoration(
                      labelText: isNewSubscription
                          ? "فترة الالتزام (شهر)"
                          : "فترة الالتزام",
                      prefixIcon:
                          Icon(Icons.schedule, color: Colors.indigo, size: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: selectedCommitmentPeriod == null
                              ? Colors.red
                              : Colors.indigo.shade200,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: selectedCommitmentPeriod == null
                                ? Colors.red
                                : Colors.indigo,
                            width: 2),
                      ),
                      errorText: selectedCommitmentPeriod == null
                          ? 'اختر فترة الالتزام'
                          : null,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      labelStyle: TextStyle(fontSize: 14),
                      helperText: isNewSubscription
                          ? "يُنصح بالبدء بشهر واحد للاشتراكات الجديدة"
                          : null,
                      helperStyle: TextStyle(
                          color: Colors.orange.shade600, fontSize: 12),
                      isDense: false,
                    ),
                    initialValue: selectedCommitmentPeriod,
                    onChanged: (value) {
                      setState(() {
                        selectedCommitmentPeriod = value!;
                        priceDetails = null;
                      });
                      _scheduleAutoPriceFetch();
                      _autoFetchExtendPriceIfNeeded(); // حساب تلقائي لسعر التمديد
                    },
                    items: commitmentPeriods.map((period) {
                      return DropdownMenuItem(
                        value: period,
                        child: Text(
                          "$period شهر",
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      );
                    }).toList(),
                  ),
                );
                if (narrow) {
                  return Column(
                    children: [
                      planField,
                      const SizedBox(height: 12),
                      periodField,
                    ],
                  );
                }
                return Row(
                  children: [
                    planField,
                    const SizedBox(width: 12),
                    periodField,
                  ],
                );
              },
            ),

            // إضافة زر إعادة حساب السعر
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton.icon(
                onPressed:
                    (selectedPlan != null && selectedCommitmentPeriod != null)
                        ? () async {
                            await _handleCalculatePricePressed();
                          }
                        : null,
                icon: Icon(
                  Icons.calculate,
                  size: 20,
                ),
                label: Text(
                  'إعادة حساب السعر',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      (selectedPlan != null && selectedCommitmentPeriod != null)
                          ? Colors.purple.shade600
                          : Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: (selectedPlan != null &&
                              selectedCommitmentPeriod != null)
                          ? Colors.purple.shade800
                          : Colors.grey.shade600,
                      width: 1.5,
                    ),
                  ),
                  elevation:
                      (selectedPlan != null && selectedCommitmentPeriod != null)
                          ? 3
                          : 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// صفحة تسجيل الدخول لواتساب ويب + كشف الدخول + حفظ حالة محلية (محسّنة)
class WhatsAppWebLoginPage extends StatefulWidget {
  const WhatsAppWebLoginPage({super.key});
  @override
  State<WhatsAppWebLoginPage> createState() => _WhatsAppWebLoginPageState();
}

class _WhatsAppWebLoginPageState extends State<WhatsAppWebLoginPage> {
  bool _isLoading = true;
  bool _loggedIn = false; // بعد اكتشاف جلسة
  String? _error;
  WebViewController? _controller; // غير ويندوز
  wvwin.WebviewController? _winController; // ويندوز
  Timer? _loginMonitor;

  @override
  void initState() {
    super.initState();
    _restoreFlag();
    _initWeb();
  }

  Future<void> _restoreFlag() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getBool('wa_web_logged_in') ?? false;
      if (v && mounted) setState(() => _loggedIn = true);
    } catch (_) {}
  }

  Future<void> _initWeb() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (Platform.isWindows) {
        final c = wvwin.WebviewController();
        await c.initialize();
        await c.setBackgroundColor(Colors.white);
        await c.loadUrl('https://web.whatsapp.com');
        setState(() {
          _winController = c;
          _isLoading = false;
        });
      } else {
        final c = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(NavigationDelegate(
            onPageStarted: (_) => setState(() => _isLoading = true),
            onPageFinished: (_) {
              if (mounted) setState(() => _isLoading = false);
              _checkLoginOnce();
            },
            onWebResourceError: (e) {
              if (mounted) {
                setState(() {
                  _error = 'تعذر التحميل: ${e.description}';
                  _isLoading = false;
                });
              }
            },
          ))
          ..loadRequest(Uri.parse('https://web.whatsapp.com'));
        setState(() => _controller = c);
      }
      _startMonitor();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'خطأ: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _startMonitor() {
    _loginMonitor?.cancel();
    _loginMonitor =
        Timer.periodic(const Duration(seconds: 3), (_) => _checkLoginOnce());
  }

  Future<void> _checkLoginOnce() async {
    if (_loggedIn) return; // لا نعيد الفحص بعد اكتشافه
    try {
      String res = '';
      if (Platform.isWindows && _winController != null) {
        res = await _winController!.executeScript(
                "(function(){return document.querySelector('#pane-side')?'LOGGED':'NOT';})()") ??
            '';
      } else if (!Platform.isWindows && _controller != null) {
        final r = await _controller!.runJavaScriptReturningResult(
            "(function(){return document.querySelector('#pane-side')?'LOGGED':'NOT';})()");
        res = r.toString().replaceAll('"', '');
      }
      if (res.contains('LOGGED')) {
        _onLoginDetected();
      }
    } catch (_) {}
  }

  Future<void> _onLoginDetected() async {
    if (!mounted) return;
    setState(() => _loggedIn = true);
    _loginMonitor?.cancel();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('wa_web_logged_in', true);
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم تسجيل الدخول إلى WhatsApp Web')));

      // انتظار قليل للمستخدم ليرى الرسالة ثم إغلاق الصفحة
      Timer(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      });
    }
  }

  Future<void> _logout() async {
    try {
      if (Platform.isWindows && _winController != null) {
        try {
          await _winController!
              .executeScript("localStorage.clear(); sessionStorage.clear();");
        } catch (_) {}
        await _winController!.loadUrl('https://web.whatsapp.com');
      } else if (!Platform.isWindows && _controller != null) {
        try {
          await _controller!.clearCache();
        } catch (_) {}
        try {
          final cm = WebViewCookieManager();
          await cm.clearCookies();
        } catch (_) {}
        await _controller!.loadRequest(Uri.parse('https://web.whatsapp.com'));
      }
      final p = await SharedPreferences.getInstance();
      await p.setBool('wa_web_logged_in', false);
      if (mounted) {
        setState(() {
          _loggedIn = false;
          _isLoading = true;
        });
        _startMonitor();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🚪 تم تسجيل الخروج (محلي)')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('فشل تسجيل الخروج: $e')));
      }
    }
  }

  @override
  void dispose() {
    _loginMonitor?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _initWeb,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              )
            ],
          ),
        ),
      );
    } else if (Platform.isWindows) {
      if (_winController == null) {
        content = const Center(child: CircularProgressIndicator());
      } else {
        content = Column(children: [
          Expanded(child: wvwin.Webview(_winController!)),
          _bottomBar()
        ]);
      }
    } else {
      if (_controller == null) {
        content = const Center(child: CircularProgressIndicator());
      } else {
        content = Column(children: [
          Expanded(child: WebViewWidget(controller: _controller!)),
          _bottomBar()
        ]);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('تسجيل الدخول - WhatsApp Web'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (Platform.isWindows && _winController != null) {
                _winController!.reload();
              } else if (!Platform.isWindows && _controller != null) {
                _controller!.reload();
              }
              _startMonitor();
            },
          ),
          IconButton(
            tooltip: 'تسجيل خروج',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Stack(children: [
        content,
        if (_isLoading)
          Container(
              color: Colors.black.withValues(alpha: 0.05),
              child: const Center(child: CircularProgressIndicator())),
      ]),
    );
  }

  Widget _bottomBar() => Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(top: BorderSide(color: Colors.grey.shade300))),
        child: Row(children: [
          Expanded(
              child: Text(
            _loggedIn
                ? '✅ متصل - جلسة محلية (قد تُفقد عند إغلاق التطبيق)'
                : 'افتح واتساب بالهاتف > الأجهزة المرتبطة > اربط جهازًا لمسح QR',
            style: TextStyle(
                fontSize: 11.5,
                color: _loggedIn ? Colors.green.shade700 : null),
            overflow: TextOverflow.ellipsis,
          )),
          IconButton(
            tooltip: 'فتح خارجي',
            icon: const Icon(Icons.open_in_browser, size: 20),
            onPressed: () => launchUrl(Uri.parse('https://web.whatsapp.com'),
                mode: LaunchMode.externalApplication),
          ),
        ]),
      );
}

/// صفحة إرسال رسالة عبر واتساب ويب داخلياً مع إرسال تلقائي
class WhatsAppWebSendPage extends StatefulWidget {
  final String phone;
  final String message;

  const WhatsAppWebSendPage({
    super.key,
    required this.phone,
    required this.message,
  });

  // دالة static للتحقق من وجود نافذة مفتوحة
  static bool isWhatsAppWindowOpen() {
    return _WhatsAppWebSendPageState._isWindowOpen &&
        _WhatsAppWebSendPageState._persistentInstance != null;
  }

  // دالة static لإغلاق النافذة الحالية
  static void closeWhatsAppWindow() {
    if (_WhatsAppWebSendPageState._persistentInstance != null &&
        _WhatsAppWebSendPageState._persistentInstance!.mounted) {
      Navigator.of(_WhatsAppWebSendPageState._persistentInstance!.context)
          .pop();
    }
  }

  // دالة static لإرسال رسالة جديدة للنافذة المفتوحة
  static void sendMessageToOpenWindow(String phone, String message) {
    if (_WhatsAppWebSendPageState._persistentInstance != null) {
      _WhatsAppWebSendPageState._persistentInstance!
          .sendNewMessage(phone, message);
    }
  }

  // دالة static لإظهار نافذة الواتساب المخفية
  static Future<void> showHiddenWhatsAppWindow(BuildContext context) async {
    if (isWhatsAppWindowOpen() &&
        _WhatsAppWebSendPageState._lastPhone != null) {
      // فتح نافذة جديدة بنفس البيانات المحفوظة
      await Navigator.of(context).push<bool?>(
        MaterialPageRoute(
          builder: (_) => WhatsAppWebSendPage(
            phone: _WhatsAppWebSendPageState._lastPhone!,
            message: _WhatsAppWebSendPageState._lastMessage ?? 'مرحباً',
          ),
        ),
      );
    } else {
      // إظهار رسالة إذا لم تكن هناك نافذة مخفية
      ftthShowInfoNotification(context, 'لا توجد نافذة واتساب مخفية');
    }
  }

  @override
  State<WhatsAppWebSendPage> createState() => _WhatsAppWebSendPageState();
}

class _WhatsAppWebSendPageState extends State<WhatsAppWebSendPage> {
  static _WhatsAppWebSendPageState? _persistentInstance;
  static bool _isWindowOpen = false;
  static String? _lastPhone;
  static String? _lastMessage;

  bool _isLoading = true;
  bool _isLoggedIn = false;
  bool _messageSent = false;
  String? _error;
  WebViewController? _controller;
  wvwin.WebviewController? _winController;
  Timer? _statusMonitor;
  bool _showStatusBar = true;
  Timer? _hideStatusBarTimer;

  @override
  void initState() {
    super.initState();
    _persistentInstance = this;
    _isWindowOpen = true;
    _lastPhone = widget.phone;
    _lastMessage = widget.message;
    _checkSavedLoginState();
    _initializeWebView();
  }

  Future<void> _checkSavedLoginState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLogin = prefs.getBool('wa_web_logged_in') ?? false;
      if (savedLogin) {
        debugPrint('✅ جلسة واتساب ويب محفوظة مسبقاً');
        setState(() => _isLoggedIn = true);
      }
    } catch (e) {
      debugPrint('خطأ في قراءة الجلسة المحفوظة: $e');
    }
  }

  @override
  void dispose() {
    _statusMonitor?.cancel();
    _hideStatusBarTimer?.cancel();
    if (_persistentInstance == this) {
      _persistentInstance = null;
      _isWindowOpen = false;
    }
    super.dispose();
  }

  void _updateStatus(
      {String? newError,
      bool? newLoggedIn,
      bool? newLoading,
      bool? newMessageSent}) {
    if (!mounted) return;

    setState(() {
      if (newError != null) _error = newError;
      if (newLoggedIn != null) _isLoggedIn = newLoggedIn;
      if (newLoading != null) _isLoading = newLoading;
      if (newMessageSent != null) _messageSent = newMessageSent;

      // إظهار شريط الحالة وإخفاؤه بعد ثانيتين
      _showStatusBar = true;
    });

    // إلغاء المؤقت السابق
    _hideStatusBarTimer?.cancel();

    // إخفاء شريط الحالة بعد ثانيتين
    _hideStatusBarTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showStatusBar = false;
        });
      }
    });
  }

  // دالة لإرسال رسالة جديدة في النافذة الموجودة
  void sendNewMessage(String phone, String message) {
    if (!mounted) return;

    debugPrint('📨 إرسال رسالة جديدة: $phone');

    // تحديث البيانات المحفوظة
    _lastPhone = phone;
    _lastMessage = message;

    // تحديث بيانات الرسالة الجديدة
    final encodedMessage = Uri.encodeComponent(message);
    final webUrl =
        'https://web.whatsapp.com/send?phone=$phone&text=$encodedMessage';

    // إعادة تحميل الصفحة برسالة جديدة
    if (Platform.isWindows && _winController != null) {
      _winController!.loadUrl(webUrl);
    } else if (!Platform.isWindows && _controller != null) {
      _controller!.loadRequest(Uri.parse(webUrl));
    }

    // إعادة تعيين الحالة للرسالة الجديدة
    setState(() {
      _messageSent = false;
      _isLoading = true;
      _error = null;
      _showStatusBar = true;
    });

    _startMonitoring();
  }

  Future<void> _initializeWebView() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // بدء مباشرة بصفحة الإرسال
      final encodedMessage = Uri.encodeComponent(widget.message);
      final webUrl =
          'https://web.whatsapp.com/send?phone=${widget.phone}&text=$encodedMessage';

      debugPrint('🌐 فتح واتساب ويب: $webUrl');
      debugPrint('📱 رقم: ${widget.phone}');
      debugPrint('📝 رسالة: ${widget.message.substring(0, 50)}...');

      if (Platform.isWindows) {
        final c = wvwin.WebviewController();
        await c.initialize();
        await c.setBackgroundColor(Colors.white);
        await c.loadUrl(webUrl);
        _updateStatus(newLoading: false);
        setState(() {
          _winController = c;
        });
      } else {
        final c = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(NavigationDelegate(
            onPageStarted: (_) => _updateStatus(newLoading: true),
            onPageFinished: (_) {
              if (mounted) {
                _updateStatus(newLoading: false);
                _startMonitoring();
              }
            },
            onWebResourceError: (e) {
              if (mounted) {
                _updateStatus(
                    newError: 'تعذر التحميل: ${e.description}',
                    newLoading: false);
              }
            },
          ))
          ..loadRequest(Uri.parse(webUrl));
        setState(() => _controller = c);
      }
    } catch (e) {
      if (mounted) {
        _updateStatus(newError: 'خطأ في التحميل: $e', newLoading: false);
      }
    }
  }

  void _startMonitoring() {
    _statusMonitor?.cancel();
    _statusMonitor =
        Timer.periodic(const Duration(seconds: 3), (_) => _checkStatus());
  }

  Future<void> _checkStatus() async {
    if (_messageSent) return;

    try {
      String result = '';
      if (Platform.isWindows && _winController != null) {
        result = await _winController!.executeScript("""
          (function() {
            // تحقق من وجود QR (غير مسجل دخول)
            var qrCode = document.querySelector('div[data-ref]') || 
                        document.querySelector('canvas') ||
                        document.querySelector('[data-testid="qr-code"]');
            if (qrCode) {
              // تأكد أنه QR وليس عنصر آخر
              var qrContainer = document.querySelector('[data-testid="intro-md-beta-logo-dark"], [data-testid="intro-md-beta-logo-light"]');
              if (qrContainer || qrCode.tagName === 'CANVAS') {
                return 'NOT_LOGGED_IN';
              }
            }
            
            // تحقق من رسالة خطأ
            var errorMsg = document.querySelector('[data-testid="alert-phone-number"]');
            if (errorMsg) return 'INVALID_PHONE';
            
            // تحقق من وجود اللوحة الجانبية (مسجل دخول)
            var sidePanel = document.querySelector('#pane-side') || 
                          document.querySelector('[data-testid="chatlist-search"]') ||
                          document.querySelector('[data-testid="chatlist-header"]');
            
            // تحقق من وجود header واتساب (مؤشر على تسجيل الدخول)
            var header = document.querySelector('[data-testid="chatlist-header"]') ||
                        document.querySelector('.app-wrapper-web') ||
                        document.querySelector('#app .app-wrapper-web');
                        
            if (!sidePanel && !header) return 'LOADING';
            
            // إذا وُجدت اللوحة الجانبية أو الـ header، فهو مسجل دخول
            if (sidePanel || header) {
              // تحقق من وجود صندوق النص (في صفحة محادثة)
              var messageBox = document.querySelector('div[contenteditable="true"][data-tab="10"]') || 
                             document.querySelector('[data-testid="conversation-compose-box-input"]') ||
                             document.querySelector('div[contenteditable="true"]');
              if (messageBox) {
                // تحقق إذا كانت الرسالة موجودة في الصندوق
                if (messageBox.textContent.includes('${widget.message.substring(0, 30)}')) {
                  return 'MESSAGE_READY';
                }
                return 'CHAT_OPEN';
              }
              
              // تحقق من الرسائل المرسلة
              var messages = document.querySelectorAll('[data-id]');
              for (var msg of messages) {
                if (msg.textContent && msg.textContent.includes('${widget.message.substring(0, 30)}')) {
                  return 'MESSAGE_SENT';
                }
              }
              
              return 'LOGGED_IN';
            }
            
            return 'LOADING';
          })()
        """) ?? '';
      } else if (!Platform.isWindows && _controller != null) {
        final r = await _controller!.runJavaScriptReturningResult("""
          (function() {
            var qrCode = document.querySelector('div[data-ref]') || 
                        document.querySelector('canvas') ||
                        document.querySelector('[data-testid="qr-code"]');
            if (qrCode) {
              var qrContainer = document.querySelector('[data-testid="intro-md-beta-logo-dark"], [data-testid="intro-md-beta-logo-light"]');
              if (qrContainer || qrCode.tagName === 'CANVAS') {
                return 'NOT_LOGGED_IN';
              }
            }
            
            var errorMsg = document.querySelector('[data-testid="alert-phone-number"]');
            if (errorMsg) return 'INVALID_PHONE';
            
            var sidePanel = document.querySelector('#pane-side') || 
                          document.querySelector('[data-testid="chatlist-search"]') ||
                          document.querySelector('[data-testid="chatlist-header"]');
                          
            var header = document.querySelector('[data-testid="chatlist-header"]') ||
                        document.querySelector('.app-wrapper-web') ||
                        document.querySelector('#app .app-wrapper-web');
                        
            if (!sidePanel && !header) return 'LOADING';
            
            if (sidePanel || header) {
              var messageBox = document.querySelector('div[contenteditable="true"][data-tab="10"]') || 
                             document.querySelector('[data-testid="conversation-compose-box-input"]') ||
                             document.querySelector('div[contenteditable="true"]');
              if (messageBox) {
                if (messageBox.textContent.includes('${widget.message.substring(0, 30)}')) {
                  return 'MESSAGE_READY';
                }
                return 'CHAT_OPEN';
              }
              
              var messages = document.querySelectorAll('[data-id]');
              for (var msg of messages) {
                if (msg.textContent && msg.textContent.includes('${widget.message.substring(0, 30)}')) {
                  return 'MESSAGE_SENT';
                }
              }
              
              return 'LOGGED_IN';
            }
            
            return 'LOADING';
          })()
        """);
        result = r.toString().replaceAll('"', '');
      }

      debugPrint('📊 حالة واتساب ويب: $result');

      if (result.contains('INVALID_PHONE')) {
        if (mounted) {
          _updateStatus(
              newError: 'رقم الهاتف غير صحيح. تحقق من الرقم وأعد المحاولة.',
              newLoading: false);
        }
        _statusMonitor?.cancel();
      } else if (result.contains('MESSAGE_SENT') && !_messageSent) {
        _updateStatus(newMessageSent: true);
        _statusMonitor?.cancel();

        // إعادة تعيين حالة الرسالة بعد 3 ثوان للسماح برسالة جديدة
        Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _messageSent = false;
              _showStatusBar = false; // إخفاء شريط النجاح
            });
            // إعادة بدء المراقبة للرسائل الجديدة
            _startMonitoring();
          }
        });
      } else if (result.contains('MESSAGE_READY')) {
        _updateStatus(newLoggedIn: true, newLoading: false);
      } else if (result.contains('CHAT_OPEN')) {
        _updateStatus(newLoggedIn: true, newLoading: false);
        _isLoggedIn = true;
        _isLoading = false;
      } else if (result.contains('LOGGED_IN')) {
        _updateStatus(newLoggedIn: true, newLoading: false);
      } else if (result.contains('NOT_LOGGED_IN')) {
        _updateStatus(newLoggedIn: false, newLoading: false);
      } else if (result.contains('LOADING')) {
        _updateStatus(newLoggedIn: false, newLoading: true);
      }
    } catch (e) {
      debugPrint('خطأ في مراقبة الحالة: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('إرسال واتساب ويب'),
            Text(
              'النافذة تبقى مفتوحة للرسائل التالية',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          // زر تحديث
          Container(
            margin: EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: Colors.white),
              onPressed: () {
                if (Platform.isWindows && _winController != null) {
                  _winController!.reload();
                } else if (!Platform.isWindows && _controller != null) {
                  _controller!.reload();
                }
                _startMonitoring();
              },
              tooltip: 'تحديث',
            ),
          ),
          // حالة الرسالة
          if (_messageSent)
            Container(
              margin: EdgeInsets.only(right: 8),
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade700,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text('تم',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
          // زر العودة للتطبيق (مع إبقاء النافذة مفتوحة)
          Container(
            margin: EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.minimize, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(null),
              tooltip: 'العودة للتطبيق (النافذة تبقى مفتوحة)',
            ),
          ),
          // زر الإغلاق النهائي
          Container(
            margin: EdgeInsets.only(left: 8, right: 8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(false),
              tooltip: 'إغلاق نهائي',
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _initializeWebView,
                    child: Text('إعادة المحاولة'),
                  ),
                ],
              ),
            )
          else if (Platform.isWindows && _winController != null)
            wvwin.Webview(_winController!)
          else if (_controller != null)
            WebViewWidget(controller: _controller!),

          // شريط الحالة في الأعلى
          if (_showStatusBar)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _error != null
                      ? Colors.red.shade700
                      : (_messageSent
                          ? Colors.green.shade700
                          : (_isLoggedIn
                              ? Colors.blue.shade700
                              : Colors.orange.shade700)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    if (_isLoading)
                      Container(
                        width: 20,
                        height: 20,
                        padding: EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    else
                      Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _messageSent
                              ? Icons.done_all
                              : (_isLoggedIn ? Icons.message : Icons.qr_code),
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error != null
                            ? 'خطأ: $_error'
                            : (_messageSent
                                ? 'تم إرسال الرسالة بنجاح!'
                                : (_isLoggedIn
                                    ? 'مُسجل دخول - المحادثة مفتوحة'
                                    : (_isLoading
                                        ? 'جاري التحميل والتحقق من الجلسة...'
                                        : 'قم بمسح QR كود بهاتفك لتسجيل الدخول'))),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
