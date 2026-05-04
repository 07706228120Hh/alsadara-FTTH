import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/vps_auth_service.dart';
import '../../services/auth_service.dart';
import '../../services/accounting_service.dart';
import '../../services/task_api_service.dart';
import '../../services/plan_pricing_service.dart';
import '../../theme/accounting_theme.dart';
import '../../permissions/permission_manager.dart';
import '../../theme/accounting_responsive.dart';
import 'client_accounts_page.dart';
import 'ftth_operator_account_page.dart';
import 'ftth_operator_linking_page.dart';
import 'ftth_operator_transactions_page.dart';

/// لوحة تحكم مشغلي FTTH — 3 تبويبات
/// 1) خادمنا: بيانات SubscriptionLogs من سيرفرنا
/// 2) خادم FTTH: معاملات من admin.ftth.iq/api/transactions
/// 3) المقارنة: مقارنة بين النظامين
class FtthOperatorsDashboardPage extends StatefulWidget {
  final String? companyId;

  const FtthOperatorsDashboardPage({super.key, this.companyId});

  @override
  State<FtthOperatorsDashboardPage> createState() =>
      _FtthOperatorsDashboardPageState();
}

class _FtthOperatorsDashboardPageState extends State<FtthOperatorsDashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── بيانات مشتركة ──
  DateTime? _fromDate;
  DateTime? _toDate;
  String _dateLabel = 'اليوم';
  bool _showDateFilter = false;

  String get _companyId =>
      widget.companyId ?? VpsAuthService.instance.currentCompanyId ?? '';

  final _currencyFormat = NumberFormat('#,###', 'ar');

  // ── TAB 1: خادمنا ──
  bool _isLoadingOurs = true;
  String? _errorOurs;
  List<dynamic> _oursOperators = [];
  int _oursTabIndex = 0; // 0 = المشغلون, 1 = الفنيون
  String _oursSortKey = 'totalAmount'; // مفتاح الترتيب
  bool _oursSortAsc = false; // false = تنازلي
  String _oursSearchQuery = '';
  final _oursSearchController = TextEditingController();
  Map<String, dynamic>? _oursSummary;
  Map<String, dynamic>? _oursDistributions;

  // ── TAB 2: خادم FTTH ──
  bool _isLoadingFtth = false;
  String? _errorFtth;
  bool _ftthAuthenticated = false;
  Map<String, _FtthOperatorData> _ftthOperators = {};
  double _ftthTotalNegative = 0;
  double _ftthTotalPositive = 0;
  int _ftthTotalCount = 0;

  // ── تقدم نسب "بدون منشئ" ──
  bool _isResolvingOrphans = false;
  int _orphanTotal = 0;
  int _orphanResolved = 0;

  // ── متغيرات التصفية المتقدمة ──
  List<String> _selectedWalletTypes = [];
  List<String> _selectedWalletOwnerTypes = ['partner']; // شريك افتراضياً
  List<String> _selectedSalesTypes = [];
  List<String> _selectedChangeTypes = [];
  List<String> _selectedPaymentMethods = [];
  List<String> _selectedZones = []; // فارغ = كل المناطق
  List<String> _selectedTransactionTypes = [];
  List<String> _selectedServiceNames = [];
  String? _transactionUser;
  bool _showTransactionsWithoutUser = false;
  bool _showTeamRefill = false; // إظهار مشغلي تعبئة رصيد الفريق

  // قوائم المناطق
  List<String> _availableZones = [];
  bool _isLoadingZones = false;

  // قوائم أسماء المستخدمين
  List<String> _availableUsernames = [];
  bool _isLoadingUsernames = false;

  // قوائم الخيارات
  final List<Map<String, String>> _walletTypes = [
    {'value': 'Main', 'label': 'المحفظة الرئيسية'},
    {'value': 'Secondary', 'label': 'المحفظة الثانوية'},
  ];
  final List<Map<String, String>> _walletOwnerTypes = [
    {'value': 'partner', 'label': 'شريك'},
    {'value': 'customer', 'label': 'عميل'},
  ];
  final List<Map<String, String>> _salesTypes = [
    {'value': '0', 'label': 'دفعة واحدة'},
    {'value': '1', 'label': 'دفعات شهرية'},
  ];
  final List<Map<String, String>> _changeTypes = [
    {'value': '0', 'label': 'مجدول'},
    {'value': '1', 'label': 'فوري'},
  ];
  final List<Map<String, String>> _paymentMethods = [
    {'value': '0', 'label': 'نقدي'},
    {'value': '1', 'label': 'بطاقة ائتمان'},
    {'value': '2', 'label': 'تحويل بنكي'},
    {'value': '3', 'label': 'محفظة إلكترونية'},
    {'value': '4', 'label': 'فاست بي'},
  ];
  final List<Map<String, String>> _transactionTypesList = [
    {'value': 'BAL_CARD_SELL', 'label': 'بيع بطاقة رصيد'},
    {'value': 'CASHBACK_COMMISSION', 'label': 'عمولة استرداد نقدي'},
    {'value': 'CASHOUT', 'label': 'سحب نقدي'},
    {'value': 'HARDWARE_SELL', 'label': 'بيع أجهزة'},
    {'value': 'MAINTENANCE_COMMISSION', 'label': 'عمولة صيانة'},
    {'value': 'PLAN_CHANGE', 'label': 'تغيير الباقة'},
    {'value': 'PLAN_PURCHASE', 'label': 'شراء باقة'},
    {'value': 'PLAN_RENEW', 'label': 'تجديد الباقة'},
    {'value': 'PURCHASE_COMMISSION', 'label': 'عمولة شراء'},
    {'value': 'SCHEDULE_CANCEL', 'label': 'إلغاء جدولة'},
    {'value': 'SCHEDULE_CHANGE', 'label': 'تغيير جدولة'},
    {'value': 'TERMINATE', 'label': 'إنهاء'},
    {'value': 'TRIAL_PERIOD', 'label': 'فترة تجريبية'},
    {'value': 'WALLET_REFUND', 'label': 'استرداد محفظة'},
    {'value': 'WALLET_TOPUP', 'label': 'شحن محفظة'},
    {'value': 'WALLET_TRANSFER', 'label': 'تحويل محفظة'},
    {'value': 'PLAN_SCHEDULE', 'label': 'جدولة باقة'},
    {'value': 'PURCH_COMM_REVERSAL', 'label': 'عكس عمولة شراء'},
    {'value': 'AUTO_RENEW', 'label': 'تجديد تلقائي'},
    {'value': 'TERMINATE_SUBSCRIPTION', 'label': 'إنهاء اشتراك'},
    {'value': 'PURCHASE_REVERSAL', 'label': 'عكس شراء'},
    {'value': 'HIER_COMM_REVERSAL', 'label': 'عكس عمولة هرمية'},
    {'value': 'HIERACHY_COMMISSION', 'label': 'عمولة هرمية'},
    {'value': 'WALLET_TRANSFER_COMMISSION', 'label': 'عمولة تحويل محفظة'},
    {'value': 'COMMISSION_TRANSFER', 'label': 'تحويل عمولة'},
    {'value': 'RENEW_REVERSAL', 'label': 'عكس تجديد'},
    {'value': 'MAINT_COMM_REVERSAL', 'label': 'عكس عمولة صيانة'},
    {'value': 'WALLET_REVERSAL', 'label': 'عكس محفظة'},
    {'value': 'WALLET_TRANSFER_FEE', 'label': 'رسوم تحويل محفظة'},
    {'value': 'PLAN_EMI_RENEW', 'label': 'تجديد قسط باقة'},
    {'value': 'PLAN_SUSPEND', 'label': 'تعليق باقة'},
    {'value': 'PLAN_REACTIVATE', 'label': 'إعادة تفعيل باقة'},
    {'value': 'REFILL_TEAM_MEMBER_BALANCE', 'label': 'تعبئة رصيد عضو فريق'},
    {
      'value': 'PurchaseSubscriptionFromTrial',
      'label': 'شراء اشتراك من التجربة'
    },
  ];
  final List<Map<String, String>> _serviceNames = [
    {'value': 'FIBER 35', 'label': 'FIBER 35'},
    {'value': 'FIBER 50', 'label': 'FIBER 50'},
    {'value': 'FIBER 75', 'label': 'FIBER 75'},
    {'value': 'FIBER 150', 'label': 'FIBER 150'},
    {'value': 'IPTV', 'label': 'IPTV'},
    {'value': 'Parental Control', 'label': 'الرقابة الأبوية'},
    {'value': 'VOIP', 'label': 'VOIP'},
    {'value': 'VOD', 'label': 'VOD'},
    {'value': 'Learning Platform', 'label': 'منصة التعلم'},
    {'value': 'Hardware Plan ONT', 'label': 'باقة جهاز ONT'},
    {'value': 'Hardware Plan Router', 'label': 'باقة راوتر'},
    {'value': 'Grace Plan', 'label': 'باقة السماح'},
  ];

  // تصنيف أنواع العمليات — 5 فئات
  static const _subscriptionTypeSet = {
    'PLAN_PURCHASE',
    'PLAN_RENEW',
    'PLAN_CHANGE',
    'PLAN_SUBSCRIBE',
    'AUTO_RENEW',
    'PLAN_SCHEDULE',
    'SCHEDULE_CHANGE',
    'PurchaseSubscriptionFromTrial',
    'PLAN_EMI_RENEW',
  };
  static const _commissionTypeSet = {
    'PURCHASE_COMMISSION',
    'CASHBACK_COMMISSION',
    'MAINTENANCE_COMMISSION',
    'HIERACHY_COMMISSION',
    'WALLET_TRANSFER_COMMISSION',
    'COMMISSION_TRANSFER',
  };
  static const _reversalTypeSet = {
    'PURCHASE_REVERSAL',
    'PURCH_COMM_REVERSAL',
    'RENEW_REVERSAL',
    'HIER_COMM_REVERSAL',
    'MAINT_COMM_REVERSAL',
    'WALLET_REVERSAL',
  };
  static const _walletTypeSet = {
    'WALLET_TOPUP',
    'WALLET_REFUND',
    'WALLET_TRANSFER',
    'WALLET_TRANSFER_FEE',
  };

  static String _categorizeType(String type) {
    if (_subscriptionTypeSet.contains(type)) return 'subscription';
    if (_commissionTypeSet.contains(type)) return 'commission';
    if (_reversalTypeSet.contains(type)) return 'reversal';
    if (_walletTypeSet.contains(type)) return 'wallet';
    return 'other';
  }

  static String _translateType(String type) {
    const map = {
      'PLAN_PURCHASE': 'شراء باقة',
      'PLAN_RENEW': 'تجديد',
      'PLAN_CHANGE': 'تغيير باقة',
      'PLAN_SUBSCRIBE': 'اشتراك',
      'AUTO_RENEW': 'تجديد تلقائي',
      'PLAN_SCHEDULE': 'جدولة',
      'SCHEDULE_CHANGE': 'تغيير جدولة',
      'PLAN_EMI_RENEW': 'تجديد قسط',
      'PURCHASE_COMMISSION': 'عمولة شراء',
      'CASHBACK_COMMISSION': 'عمولة استرداد',
      'MAINTENANCE_COMMISSION': 'عمولة صيانة',
      'HIERACHY_COMMISSION': 'عمولة هرمية',
      'WALLET_TRANSFER_COMMISSION': 'عمولة تحويل',
      'COMMISSION_TRANSFER': 'تحويل عمولة',
      'PURCHASE_REVERSAL': 'عكس شراء',
      'PURCH_COMM_REVERSAL': 'عكس عمولة شراء',
      'RENEW_REVERSAL': 'عكس تجديد',
      'HIER_COMM_REVERSAL': 'عكس عمولة هرمية',
      'MAINT_COMM_REVERSAL': 'عكس عمولة صيانة',
      'WALLET_REVERSAL': 'عكس محفظة',
      'WALLET_TOPUP': 'شحن محفظة',
      'WALLET_REFUND': 'استرداد محفظة',
      'WALLET_TRANSFER': 'تحويل محفظة',
      'WALLET_TRANSFER_FEE': 'رسوم تحويل',
      'BAL_CARD_SELL': 'بيع بطاقة',
      'CASHOUT': 'سحب نقدي',
      'HARDWARE_SELL': 'بيع أجهزة',
      'TERMINATE': 'إنهاء',
      'TERMINATE_SUBSCRIPTION': 'إنهاء اشتراك',
      'SCHEDULE_CANCEL': 'إلغاء جدولة',
      'TRIAL_PERIOD': 'فترة تجريبية',
      'PLAN_SUSPEND': 'تعليق',
      'PLAN_REACTIVATE': 'إعادة تفعيل',
      'REFILL_TEAM_MEMBER_BALANCE': 'تعبئة رصيد فريق',
      'PurchaseSubscriptionFromTrial': 'شراء من تجربة',
    };
    return map[type] ?? type;
  }

  // ── TAB 3: المقارنة ──
  bool _isLoadingCompare = false;
  List<_ComparisonRow> _comparisonRows = [];
  int _totalMatched = 0;
  int _totalOursOnly = 0;
  int _totalFtthOnly = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    // الافتراضي: اليوم
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, now.day);
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _dateLabel = 'اليوم';
    _loadOursData();
    _checkFtthAuth();
    _loadAvailableZones();
    _loadAvailableUsernames();
    PlanPricingService.instance.load();
  }

  void _setTodayAndYesterday() {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    _fromDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _dateLabel = 'اليوم + أمس';
  }

  void _setYesterday() {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    _fromDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
    _toDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
    _dateLabel = 'أمس';
  }

  void _setCurrentMonth() {
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _dateLabel = 'هذا الشهر';
  }

  String? _mapPaymentMode(String paymentMode) {
    final mode = paymentMode.toLowerCase().trim();
    if (mode.contains('cash')) return 'cash';
    if (mode.contains('credit')) return 'credit';
    if (mode.contains('master')) return 'master';
    if (mode.contains('agent')) return 'agent';
    if (mode.contains('tech')) return 'technician';
    return null;
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    switch (_tabController.index) {
      case 0:
        if (_oursOperators.isEmpty && !_isLoadingOurs) _loadOursData();
        break;
      case 1:
        if (_ftthOperators.isEmpty && !_isLoadingFtth && _ftthAuthenticated) {
          _loadFtthData();
        }
        break;
      case 2:
        if (_comparisonRows.isEmpty && !_isLoadingCompare) _buildComparison();
        break;
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  FTTH AUTH
  // ════════════════════════════════════════════════════════════════

  Future<void> _checkFtthAuth() async {
    final token = await AuthService.instance.getAccessToken();
    if (mounted) {
      setState(() => _ftthAuthenticated = token != null && token.isNotEmpty);
    }
    if (_ftthAuthenticated) {
      _loadFtthData();
    }
  }

  Future<void> _showFtthLoginDialog() async {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    bool isLoading = false;
    String? errorMsg;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(context.accR.radiusL)),
            title: Row(
              children: [
                Icon(Icons.wifi_tethering, color: Colors.teal.shade700),
                SizedBox(width: context.accR.spaceS),
                Text('تسجيل دخول FTTH',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.headingSmall,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            content: SizedBox(
              width: context.accR.isMobile
                  ? MediaQuery.of(context).size.width * 0.9
                  : 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(context.accR.spaceM),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: context.accR.iconM,
                            color: Colors.blue.shade700),
                        SizedBox(width: context.accR.spaceS),
                        Expanded(
                          child: Text(
                            'أدخل بيانات حساب FTTH لجلب بيانات المعاملات من خادم admin.ftth.iq',
                            style: TextStyle(
                                fontSize: context.accR.small,
                                color: Colors.blue.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: context.accR.spaceXL),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextField(
                      controller: usernameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(context.accR.cardRadius)),
                      ),
                    ),
                  ),
                  SizedBox(height: context.accR.spaceM),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextField(
                      controller: passwordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(context.accR.cardRadius)),
                      ),
                    ),
                  ),
                  if (errorMsg != null) ...[
                    SizedBox(height: context.accR.spaceM),
                    Container(
                      padding: EdgeInsets.all(context.accR.spaceS),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(errorMsg!,
                          style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: context.accR.small)),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (usernameCtrl.text.trim().isEmpty ||
                            passwordCtrl.text.isEmpty) {
                          setDlgState(() => errorMsg =
                              'يرجى إدخال اسم المستخدم وكلمة المرور');
                          return;
                        }
                        setDlgState(() {
                          isLoading = true;
                          errorMsg = null;
                        });
                        try {
                          final loginResult = await AuthService.instance.login(
                            usernameCtrl.text.trim(),
                            passwordCtrl.text,
                          );
                          if (loginResult['success'] == true) {
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } else {
                            setDlgState(() {
                              isLoading = false;
                              errorMsg =
                                  loginResult['message'] ?? 'فشل تسجيل الدخول';
                            });
                          }
                        } catch (e) {
                          setDlgState(() {
                            isLoading = false;
                            errorMsg = 'خطأ';
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text('تسجيل الدخول',
                        style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true) {
      setState(() => _ftthAuthenticated = true);
      _loadFtthData();
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  TAB 1: جلب بيانات خادمنا
  // ════════════════════════════════════════════════════════════════

  Future<void> _loadOursData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingOurs = true;
      _errorOurs = null;
    });
    try {
      var url =
          'https://api.ramzalsadara.tech/api/ftth-accounting/operators-dashboard?companyId=$_companyId';
      if (_fromDate != null) {
        url += '&from=${_fromDate!.toIso8601String().split('T')[0]}';
      }
      if (_toDate != null) {
        url += '&to=${_toDate!.toIso8601String().split('T')[0]}';
      }

      final token = VpsAuthService.instance.accessToken;
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'X-Api-Key': 'sadara-internal-2024-secure-key',
        },
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          _oursOperators = (result['data'] as List?) ?? [];
          _oursSummary = result['summary'] as Map<String, dynamic>?;
          _oursDistributions = result['distributions'] as Map<String, dynamic>?;
        } else {
          _errorOurs = result['message'] ?? 'خطأ';
        }
      } else {
        _errorOurs = 'خطأ في الاتصال: ${response.statusCode}';
      }
    } catch (e) {
      _errorOurs = 'خطأ';
    }
    if (mounted) setState(() => _isLoadingOurs = false);
  }

  // ════════════════════════════════════════════════════════════════
  //  TAB 2: جلب بيانات خادم FTTH
  // ════════════════════════════════════════════════════════════════

  Future<void> _loadFtthData() async {
    if (!_ftthAuthenticated || !mounted) return;
    setState(() {
      _isLoadingFtth = true;
      _errorFtth = null;
    });

    try {
      // بناء نطاق التاريخ
      DateTime from;
      DateTime to;
      if (_fromDate != null && _toDate != null) {
        from = _fromDate!;
        to = _toDate!;
      } else {
        // افتراضي: اليوم + أمس
        final now = DateTime.now();
        final yesterday = now.subtract(const Duration(days: 1));
        from =
            DateTime(yesterday.year, yesterday.month, yesterday.day, 0, 0, 0);
        to = DateTime(now.year, now.month, now.day, 23, 59, 59);
      }

      final utcFrom = from.toUtc();
      final utcTo = to.toUtc();
      final fromStr =
          '${DateFormat('yyyy-MM-ddTHH:mm:ss.SSS').format(utcFrom)}Z';
      final toStr = '${DateFormat('yyyy-MM-ddTHH:mm:ss.SSS').format(utcTo)}Z';

      // لا نفلتر بنوع العملية — نجلب الكل لعرض تفصيلي
      Map<String, _FtthOperatorData> operators = {};
      final Set<String> seenTxIds = {}; // منع تكرار نفس العملية
      double totalNeg = 0, totalPos = 0;
      int totalCnt = 0;
      int page = 1;
      const pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        // بناء URL مع الفلاتر المتقدمة
        final baseParams = <String>[
          'pageSize=$pageSize',
          'pageNumber=$page',
          'sortCriteria.property=occuredAt',
          'sortCriteria.direction=desc',
          'occuredAt.from=$fromStr',
          'occuredAt.to=$toStr',
          'createdAt.from=$fromStr',
          'createdAt.to=$toStr',
        ];
        // إضافة فلاتر متقدمة
        final advancedParams = _buildFtthFilterParams();
        // إذا لم يحدد المستخدم walletOwnerType في الفلاتر المتقدمة، نضيف partner كافتراضي
        if (!advancedParams.any((p) => p.startsWith('walletOwnerType='))) {
          baseParams.add('walletOwnerType=partner');
        }
        baseParams.addAll(advancedParams);
        final url =
            'https://admin.ftth.iq/api/transactions?${baseParams.join('&')}';

        final response =
            await AuthService.instance.authenticatedRequest('GET', url);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final items = List<Map<String, dynamic>>.from(data['items'] ?? []);

          for (final tx in items) {
            // فحص 3 حقول لمعرفة المنشئ
            final createdBy = (tx['createdBy'] ?? '').toString().trim();
            final transactionUser =
                (tx['transactionUser'] ?? '').toString().trim();
            final username = (tx['username'] ?? '').toString().trim();
            final operatorName = createdBy.isNotEmpty
                ? createdBy
                : transactionUser.isNotEmpty
                    ? transactionUser
                    : username.isNotEmpty
                        ? username
                        : 'بدون منشئ';

            final amtVal = tx['transactionAmount']?['value'] ?? 0.0;
            final num amtNum = (amtVal is num)
                ? amtVal
                : double.tryParse(amtVal.toString()) ?? 0.0;
            final double amount = amtNum.toDouble();

            final type = tx['type']?.toString() ?? '';
            final subscriptionId = tx['subscription']?['id']?.toString() ?? '';
            final customerName =
                tx['customer']?['displayValue']?.toString() ?? '';
            final customerId = tx['customer']?['id']?.toString() ?? '';
            final planName =
                tx['subscription']?['displayValue']?.toString() ?? '';
            final occuredAt = tx['occuredAt']?.toString() ?? '';
            final txId = tx['id']?.toString() ?? '';
            // تخطي العمليات المكررة (نفس المعرّف)
            if (txId.isNotEmpty && !seenTxIds.add(txId)) continue;
            // تخطي الخدمات الإضافية (فقط FIBER = إنترنت)
            if (!planName.toUpperCase().contains('FIBER')) continue;
            final zoneId = tx['zoneId']?.toString() ?? '';
            final deviceUsername = tx['deviceUsername']?.toString() ?? '';
            final planDuration = (tx['planDurationInDays'] ??
                    tx['durationInDays'] ??
                    tx['duration'] ??
                    0) as int? ??
                0;

            // حقول إضافية
            final remBalVal = tx['remainingBalance']?['value'] ?? 0.0;
            final double remainingBalance = (remBalVal is num)
                ? remBalVal.toDouble()
                : double.tryParse(remBalVal.toString()) ?? 0.0;
            final paymentMode = tx['paymentMode']?.toString() ?? '';
            final paymentMethod =
                tx['paymentMethod']?['displayValue']?.toString() ?? '';
            final startsAt = tx['subscription']?['startsAt']?.toString() ?? '';
            final endsAt = tx['subscription']?['endsAt']?.toString() ?? '';

            if (!operators.containsKey(operatorName)) {
              operators[operatorName] = _FtthOperatorData(name: operatorName);
            }

            final op = operators[operatorName]!;
            op.totalCount++;
            op.totalAmount += amount;
            if (amount < 0) {
              op.negativeAmount += amount;
              totalNeg += amount;
            } else {
              op.positiveAmount += amount;
              totalPos += amount;
            }
            totalCnt++;

            // تصنيف نوع العملية
            final category = _categorizeType(type);
            op.typeCounts[type] = (op.typeCounts[type] ?? 0) + 1;

            switch (category) {
              case 'subscription':
                op.subscriptionOps++;
                // تفصيل الاشتراكات
                if (const {
                  'PLAN_PURCHASE',
                  'PurchaseSubscriptionFromTrial',
                  'PLAN_SUBSCRIBE'
                }.contains(type)) {
                  op.purchaseOps++;
                } else if (const {'PLAN_RENEW', 'AUTO_RENEW', 'PLAN_EMI_RENEW'}
                    .contains(type)) {
                  op.renewOps++;
                } else if (const {'PLAN_CHANGE', 'SCHEDULE_CHANGE'}
                    .contains(type)) {
                  op.changeOps++;
                } else if (type == 'PLAN_SCHEDULE') {
                  op.scheduleOps++;
                }
                break;
              case 'commission':
                op.commissionOps++;
                break;
              case 'reversal':
                op.reversalOps++;
                break;
              case 'wallet':
                op.walletOps++;
                break;
              default:
                op.otherOps++;
            }

            // حفظ جميع المعاملات
            op.transactions.add(_FtthTransaction(
              id: txId,
              type: type,
              amount: amount,
              subscriptionId: subscriptionId,
              customerName: customerName,
              customerId: customerId,
              planName: planName,
              occuredAt: occuredAt,
              createdBy: operatorName,
              zoneId: zoneId,
              deviceUsername: deviceUsername,
              planDuration: planDuration,
              remainingBalance: remainingBalance,
              paymentMode: paymentMode,
              paymentMethod: paymentMethod,
              startsAt: startsAt,
              endsAt: endsAt,
            ));
          }

          final serverTotal = data['totalCount'] ?? 0;
          if (page * pageSize >= serverTotal || items.isEmpty) {
            hasMore = false;
          } else {
            page++;
          }
        } else if (response.statusCode == 401) {
          if (mounted) {
            setState(() {
              _ftthAuthenticated = false;
              _errorFtth = 'انتهت جلسة FTTH — يرجى تسجيل الدخول مرة أخرى';
            });
          }
          return;
        } else {
          _errorFtth = 'خطأ من خادم FTTH: ${response.statusCode}';
          hasMore = false;
        }
      }

      // ═══ المرحلة 1: عرض البيانات فوراً (مع "بدون منشئ" كمشغل مؤقت) ═══
      _ftthOperators = operators;
      _ftthTotalNegative = totalNeg;
      _ftthTotalPositive = totalPos;
      _ftthTotalCount = totalCnt;
      if (mounted) setState(() => _isLoadingFtth = false);

      // ═══ المرحلة 2: نسب "بدون منشئ" عبر audit-logs (في الخلفية مع عداد) ═══
      _resolveOrphansInBackground();
    } catch (e) {
      _errorFtth = 'خطأ في جلب بيانات FTTH';
      if (mounted) setState(() => _isLoadingFtth = false);
    }
  }

  /// المرحلة 2: نسب عمليات "بدون منشئ" في الخلفية مع تحديث العداد
  Future<void> _resolveOrphansInBackground() async {
    // جمع معاملات "بدون منشئ" + "Agent" (كلاهما يحتاج إعادة نسب)
    final List<_FtthTransaction> orphanTxs = [];
    final noCreator = _ftthOperators.remove('بدون منشئ');
    if (noCreator != null && noCreator.transactions.isNotEmpty) {
      orphanTxs.addAll(noCreator.transactions);
    }
    final agentOp = _ftthOperators.remove('Agent');
    if (agentOp != null && agentOp.transactions.isNotEmpty) {
      orphanTxs.addAll(agentOp.transactions);
    }
    if (orphanTxs.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    // جمع customerIds الفريدة
    final Set<String> uniqueCustomerIds = {};
    for (final tx in orphanTxs) {
      if (tx.customerId.isNotEmpty) {
        uniqueCustomerIds.add(tx.customerId);
      }
    }

    if (mounted) {
      setState(() {
        _isResolvingOrphans = true;
        _orphanTotal = uniqueCustomerIds.length;
        _orphanResolved = 0;
      });
    }

    // جلب actor.username من audit-logs لكل عميل فريد
    final Map<String, String> customerAuditCreator = {};
    int processed = 0;
    for (final custId in uniqueCustomerIds) {
      if (!mounted) return;
      try {
        final auditUrl =
            'https://admin.ftth.iq/api/audit-logs?pageSize=10&pageNumber=1'
            '&sortCriteria.property=CreatedAt&sortCriteria.direction=%20desc'
            '&customerId=$custId';
        final auditResp =
            await AuthService.instance.authenticatedRequest('GET', auditUrl);
        if (auditResp.statusCode == 200) {
          final auditData = jsonDecode(auditResp.body);
          final auditItems = auditData['items'] as List? ?? [];
          for (final item in auditItems) {
            final actor = item['actor'];
            if (actor != null && actor['username'] != null) {
              final actorUsername = actor['username'].toString().trim();
              if (actorUsername.isNotEmpty) {
                customerAuditCreator[custId] = actorUsername;
                break;
              }
            }
          }
        }
      } catch (_) {}
      processed++;
      if (mounted && processed % 3 == 0) {
        setState(() => _orphanResolved = processed);
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // نسب العمليات للمشغلين (مع منع التكرار بالمعرّف)
    final Set<String> assignedIds = {};
    final List<_FtthTransaction> finalOrphan = [];
    for (final tx in orphanTxs) {
      // تخطي إذا تم نسب هذه العملية مسبقاً
      if (tx.id.isNotEmpty && !assignedIds.add(tx.id)) continue;
      // تخطي الخدمات الإضافية (فقط FIBER = إنترنت)
      if (!tx.planName.toUpperCase().contains('FIBER')) continue;

      final auditCreator =
          tx.customerId.isNotEmpty ? customerAuditCreator[tx.customerId] : null;

      if (auditCreator != null) {
        tx.auditCreator = auditCreator;
        if (!_ftthOperators.containsKey(auditCreator)) {
          _ftthOperators[auditCreator] = _FtthOperatorData(name: auditCreator);
        }
        final target = _ftthOperators[auditCreator]!;
        // تحقق أن المشغل لا يحتوي على هذه العملية أصلاً
        if (target.transactions.any((t) => t.id == tx.id)) continue;
        target.totalCount++;
        target.totalAmount += tx.amount;
        target.attributedOps++;
        if (tx.amount < 0) {
          target.negativeAmount += tx.amount;
        } else {
          target.positiveAmount += tx.amount;
        }
        final category = _categorizeType(tx.type);
        target.typeCounts[tx.type] = (target.typeCounts[tx.type] ?? 0) + 1;
        switch (category) {
          case 'subscription':
            target.subscriptionOps++;
            if (const {
              'PLAN_PURCHASE',
              'PurchaseSubscriptionFromTrial',
              'PLAN_SUBSCRIBE'
            }.contains(tx.type)) {
              target.purchaseOps++;
            } else if (const {'PLAN_RENEW', 'AUTO_RENEW', 'PLAN_EMI_RENEW'}
                .contains(tx.type)) {
              target.renewOps++;
            } else if (const {'PLAN_CHANGE', 'SCHEDULE_CHANGE'}
                .contains(tx.type)) {
              target.changeOps++;
            } else if (tx.type == 'PLAN_SCHEDULE') {
              target.scheduleOps++;
            }
            break;
          case 'commission':
            target.commissionOps++;
            break;
          case 'reversal':
            target.reversalOps++;
            break;
          case 'wallet':
            target.walletOps++;
            break;
          default:
            target.otherOps++;
        }
        target.transactions.add(_FtthTransaction(
          id: tx.id,
          type: tx.type,
          amount: tx.amount,
          subscriptionId: tx.subscriptionId,
          customerName: tx.customerName,
          customerId: tx.customerId,
          planName: tx.planName,
          occuredAt: tx.occuredAt,
          createdBy: '⇐ ${target.name}',
          zoneId: tx.zoneId,
          deviceUsername: tx.deviceUsername,
          auditCreator: auditCreator,
        ));
      } else {
        finalOrphan.add(tx);
      }
    }

    // إبقاء العمليات التي لم نستطع نسبها
    if (finalOrphan.isNotEmpty) {
      final orphanOp = _FtthOperatorData(name: 'بدون منشئ');
      for (final tx in finalOrphan) {
        orphanOp.totalCount++;
        orphanOp.totalAmount += tx.amount;
        if (tx.amount < 0) {
          orphanOp.negativeAmount += tx.amount;
        } else {
          orphanOp.positiveAmount += tx.amount;
        }
        final category = _categorizeType(tx.type);
        orphanOp.typeCounts[tx.type] = (orphanOp.typeCounts[tx.type] ?? 0) + 1;
        switch (category) {
          case 'subscription':
            orphanOp.subscriptionOps++;
            if (const {
              'PLAN_PURCHASE',
              'PurchaseSubscriptionFromTrial',
              'PLAN_SUBSCRIBE'
            }.contains(tx.type))
              orphanOp.purchaseOps++;
            else if (const {'PLAN_RENEW', 'AUTO_RENEW', 'PLAN_EMI_RENEW'}
                .contains(tx.type))
              orphanOp.renewOps++;
            else if (const {'PLAN_CHANGE', 'SCHEDULE_CHANGE'}.contains(tx.type))
              orphanOp.changeOps++;
            else if (tx.type == 'PLAN_SCHEDULE') orphanOp.scheduleOps++;
            break;
          case 'commission':
            orphanOp.commissionOps++;
            break;
          case 'reversal':
            orphanOp.reversalOps++;
            break;
          case 'wallet':
            orphanOp.walletOps++;
            break;
          default:
            orphanOp.otherOps++;
        }
        orphanOp.transactions.add(tx);
      }
      _ftthOperators['بدون منشئ'] = orphanOp;
    }

    if (mounted) {
      setState(() {
        _isResolvingOrphans = false;
        _orphanResolved = _orphanTotal;
      });
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  مزامنة عمليات FTTH → خادمنا
  // ════════════════════════════════════════════════════════════════

  Future<void> _syncFtthToOurServer() async {
    if (_ftthOperators.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا توجد بيانات FTTH لمزامنتها — جلب البيانات أولاً'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // تأكيد المزامنة
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.sync, color: Colors.teal.shade700),
            SizedBox(width: context.accR.spaceS),
            Text('مزامنة FTTH → خادمنا',
                style: GoogleFonts.cairo(
                    fontSize: context.accR.headingSmall,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سيتم إرسال جميع عمليات FTTH المحملة إلى خادمنا.\n'
              'العمليات المحفوظة مسبقاً (بناءً على FtthTransactionId) ستُتجاهل تلقائياً.',
              style: GoogleFonts.cairo(fontSize: context.accR.financialSmall),
            ),
            SizedBox(height: context.accR.spaceS),
            Text(
              'عدد العمليات: ${_ftthOperators.values.fold<int>(0, (s, op) => s + op.transactions.length)}',
              style: GoogleFonts.cairo(
                  fontSize: context.accR.financialSmall,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: Icon(Icons.sync, size: context.accR.iconM),
            label: const Text('مزامنة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // بناء خريطة ftthUsername → userId من بيانات المشغلين
    final ftthToUserId = <String, String>{};
    for (final op in _oursOperators) {
      final uid = op['userId']?.toString();
      final ftthUser = (op['ftthUsername'] ?? '').toString().toLowerCase().trim();
      final username = (op['username'] ?? '').toString().toLowerCase().trim();
      final opName = (op['operatorName'] ?? '').toString().toLowerCase().trim();
      if (uid != null && uid.isNotEmpty) {
        if (ftthUser.isNotEmpty) ftthToUserId[ftthUser] = uid;
        if (username.isNotEmpty) ftthToUserId[username] = uid;
        if (opName.isNotEmpty) ftthToUserId[opName] = uid;
      }
    }

    // إضافة ربط من _comparisonRows (يشمل المشغلين الذين ليس لهم عمليات عندنا)
    for (final row in _comparisonRows) {
      if (row.operatorUserId != null && row.operatorUserId!.isNotEmpty) {
        ftthToUserId[row.operatorName.toLowerCase().trim()] = row.operatorUserId!;
      }
    }

    // تحويل العمليات مع ربط كل عملية بالمشغل
    final List<Map<String, dynamic>> txList = [];
    for (final opEntry in _ftthOperators.entries) {
      // البحث عن userId المشغل
      final opKey = opEntry.key.toLowerCase().trim();
      final matchedUserId = ftthToUserId[opKey];

      for (final tx in opEntry.value.transactions) {
        final txMap = <String, dynamic>{
          'ftthTransactionId': tx.id,
          'customerId': tx.customerId,
          'customerName': tx.customerName,
          'subscriptionId': tx.subscriptionId,
          'planName': tx.planName,
          'amount': tx.amount,
          'operationType': tx.type,
          'createdBy': tx.auditCreator,
          'occuredAt': tx.occuredAt,
          'zoneId': tx.zoneId,
          'deviceUsername': tx.deviceUsername,
          'collectionType': _mapPaymentMode(tx.paymentMode),
          'paymentMethod': tx.paymentMethod,
          'remainingBalance': tx.remainingBalance,
          'createAccounting': true,
        };
        if (tx.startsAt.isNotEmpty) {
          final parsed = DateTime.tryParse(tx.startsAt);
          if (parsed != null) txMap['startDate'] = parsed.toIso8601String();
        }
        if (tx.endsAt.isNotEmpty) {
          final parsed = DateTime.tryParse(tx.endsAt);
          if (parsed != null) txMap['endDate'] = parsed.toIso8601String();
        }
        if (tx.planDuration > 0) txMap['commitmentPeriod'] = tx.planDuration;
        if (matchedUserId != null) txMap['operatorUserId'] = matchedUserId;
        txList.add(txMap);
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('جاري مزامنة ${txList.length} عملية...'),
          backgroundColor: Colors.teal,
          duration: const Duration(seconds: 10),
        ),
      );
    }

    try {
      final result = await AccountingService.instance.syncFtthTransactions(
        companyId: _companyId,
        transactions: txList,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        final success = result['success'] == true;
        final data = result['data'];
        final saved = data is Map
            ? data['saved'] ?? result['saved'] ?? 0
            : result['saved'] ?? 0;
        final skipped = data is Map
            ? data['skipped'] ?? result['skipped'] ?? 0
            : result['skipped'] ?? 0;
        final failed = data is Map
            ? data['failed'] ?? result['failed'] ?? 0
            : result['failed'] ?? 0;
        final updated = data is Map
            ? data['updated'] ?? result['updated'] ?? 0
            : result['updated'] ?? 0;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'تمت المزامنة: $saved محفوظ، ${updated > 0 ? '$updated محدّث، ' : ''}$skipped موجود مسبقاً، $failed فشل'
                  : result['message'] ?? 'خطأ في المزامنة',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );

        // إعادة تحميل بيانات خادمنا
        if (success) _loadOursData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  TAB 3: بناء المقارنة
  // ════════════════════════════════════════════════════════════════

  Future<void> _buildComparison() async {
    if (!mounted) return;
    setState(() => _isLoadingCompare = true);

    // 1. تحميل بيانات خادمنا إذا لم تُحمَّل
    if (_oursOperators.isEmpty && !_isLoadingOurs) await _loadOursData();
    // انتظار انتهاء تحميل بياناتنا
    while (_isLoadingOurs && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // 2. تحميل بيانات FTTH إذا لم تُحمَّل
    if (_ftthOperators.isEmpty && _ftthAuthenticated) {
      await _loadFtthData();
    }
    // انتظار انتهاء تحميل FTTH
    while (_isLoadingFtth && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    // انتظار انتهاء نسب العمليات اليتيمة (مهم للحصول على أسماء المشغلين الصحيحة)
    while (_isResolvingOrphans && mounted) {
      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (!mounted) return;

    try {
      // 2.5 جلب بصمات العمليات المحفوظة عندنا لتحديد العمليات الناقصة
      Set<String> existingFtthIds = {};
      Set<String> existingKeys = {};
      try {
        final result = await AccountingService.instance.getExistingFtthFingerprints(
          companyId: _companyId,
          from: _fromDate,
          to: _toDate,
        );
        existingFtthIds = (result['ids'] ?? []).toSet();
        existingKeys = (result['keys'] ?? []).toSet();
        debugPrint('📊 بصمات محفوظة: ${existingFtthIds.length} IDs، ${existingKeys.length} keys');
      } catch (e) {
        debugPrint('⚠️ فشل جلب بصمات العمليات المحفوظة: $e');
      }

      // بناء خريطة (customerId|تاريخ → مبلغ) لكشف المبالغ الخاطئة
      final Map<String, int> cidDateAmounts = {};
      for (final key in existingKeys) {
        final parts = key.split('|');
        if (parts.length == 3) {
          final cidDate = '${parts[0]}|${parts[2]}';
          cidDateAmounts[cidDate] = int.tryParse(parts[1]) ?? 0;
        }
      }

      // 3. بناء خريطة مشغلينا مع عدة مفاتيح للمطابقة
      // كل مشغل يمكن مطابقته بـ ftthUsername أو username أو operatorName
      final Map<String, Map<String, dynamic>> oursMap = {};
      // خريطة عكسية: مفتاح المطابقة → اسم العرض
      final Map<String, List<String>> oursAllKeys = {};

      for (final op in _oursOperators) {
        final m = op as Map<String, dynamic>;
        // استبعاد الفنيين — المقارنة للمشغلين فقط
        if (m['isTechnician'] == true) continue;
        final ftthUser = (m['ftthUsername'] ?? '').toString().trim();
        final username = (m['username'] ?? '').toString().trim();
        final opName = (m['operatorName'] ?? '').toString().trim();

        // المفتاح الأساسي للمطابقة (أولوية: ftthUsername > username > operatorName)
        final primaryKey = ftthUser.isNotEmpty
            ? ftthUser.toLowerCase()
            : username.isNotEmpty
                ? username.toLowerCase()
                : opName.toLowerCase();

        if (primaryKey.isEmpty) continue;
        oursMap[primaryKey] = m;

        // تجميع كل المفاتيح الممكنة لهذا المشغل
        final keys = <String>[];
        if (ftthUser.isNotEmpty) keys.add(ftthUser.toLowerCase());
        if (username.isNotEmpty) keys.add(username.toLowerCase());
        if (opName.isNotEmpty) keys.add(opName.toLowerCase());
        oursAllKeys[primaryKey] = keys;
      }

      debugPrint('📊 مقارنة: ${oursMap.length} مشغل عندنا، ${_ftthOperators.length} مشغل FTTH');
      for (final k in oursMap.keys) {
        debugPrint('  ours key: "$k" (allKeys: ${oursAllKeys[k]})');
      }
      for (final k in _ftthOperators.keys) {
        debugPrint('  ftth key: "$k" (subs: ${_ftthOperators[k]!.subscriptionOps})');
      }

      final List<_ComparisonRow> rows = [];
      final Set<String> processedFtth = {};
      int matched = 0, oursOnly = 0, ftthOnly = 0;

      // 4. مرور على مشغلي خادمنا والبحث عن نظير في FTTH
      for (final entry in oursMap.entries) {
        final primaryKey = entry.key;
        final oursOp = entry.value;
        final oursCount = (oursOp['totalCount'] ?? 0) as int;
        final oursAmount = (oursOp['pageDeduction'] ?? oursOp['totalAmount'] ?? 0).toDouble();
        final oursName = oursOp['operatorName'] ?? primaryKey;

        // البحث بكل المفاتيح الممكنة
        _FtthOperatorData? ftthOp;
        final allKeys = oursAllKeys[primaryKey] ?? [primaryKey];
        for (final key in allKeys) {
          for (final fEntry in _ftthOperators.entries) {
            if (fEntry.key.toLowerCase() == key) {
              ftthOp = fEntry.value;
              break;
            }
          }
          if (ftthOp != null) break;
        }

        if (ftthOp != null) {
          processedFtth.add(ftthOp.name.toLowerCase());

          final ftthSubOps = ftthOp.subscriptionOps;

          // تصنيف عمليات FTTH: ناقصة أو خاطئة
          final List<_FtthTransaction> missingTxs = [];
          final List<_WrongTransaction> wrongTxs = [];
          for (final tx in ftthOp.transactions) {
            if (!_subscriptionTypeSet.contains(tx.type)) continue;
            if (existingFtthIds.contains(tx.id)) continue;
            final dateStr = tx.occuredAt.length >= 10 ? tx.occuredAt.substring(0, 10) : tx.occuredAt;
            final amt = tx.amount.abs().toInt();
            final cid = tx.customerId.trim();
            // مطابقة بمعرّف العميل
            final cidKey = '$cid|$amt|$dateStr';
            if (existingKeys.contains(cidKey)) continue;
            // تحقق: هل معرّف العميل موجود بنفس التاريخ لكن بمبلغ مختلف؟
            final cidDate = '$cid|$dateStr';
            if (cid.isNotEmpty && cidDateAmounts.containsKey(cidDate)) {
              wrongTxs.add(_WrongTransaction(
                ftthTx: tx,
                oursAmount: cidDateAmounts[cidDate]!,
                ftthAmount: amt,
              ));
            } else {
              missingTxs.add(tx);
            }
          }

          // حساب دقيق
          final realFtthOnly = missingTxs.length;
          final realMatched = ftthSubOps - realFtthOnly - wrongTxs.length;
          final realOursOnly = oursCount > realMatched ? oursCount - realMatched : 0;

          matched += realMatched > 0 ? realMatched : 0;
          oursOnly += realOursOnly;
          ftthOnly += realFtthOnly;

          rows.add(_ComparisonRow(
            operatorName: oursName.toString(),
            operatorUserId: oursOp['userId']?.toString(),
            oursCount: oursCount,
            oursAmount: oursAmount,
            ftthCount: ftthSubOps,
            ftthAmount: ftthOp.negativeAmount.abs(),
            matchedCount: realMatched > 0 ? realMatched : 0,
            oursOnlyCount: realOursOnly,
            ftthOnlyCount: realFtthOnly,
            ftthTransactions: missingTxs,
            wrongTransactions: wrongTxs,
          ));
        } else {
          oursOnly += oursCount;
          rows.add(_ComparisonRow(
            operatorName: oursName.toString(),
            operatorUserId: oursOp['userId']?.toString(),
            oursCount: oursCount,
            oursAmount: oursAmount,
            ftthCount: 0,
            ftthAmount: 0,
            matchedCount: 0,
            oursOnlyCount: oursCount,
            ftthOnlyCount: 0,
          ));
        }
      }

      // 5. مشغلون في FTTH ليسوا عندنا
      for (final entry in _ftthOperators.entries) {
        if (processedFtth.contains(entry.key.toLowerCase())) continue;
        if (entry.key == 'بدون منشئ') continue;

        // محاولة أخيرة: البحث في مفاتيحنا عن تطابق جزئي
        bool found = false;
        for (final oursEntry in oursMap.entries) {
          final allKeys = oursAllKeys[oursEntry.key] ?? [];
          if (allKeys.any((k) => k == entry.key.toLowerCase())) {
            found = true;
            break;
          }
        }
        if (found) continue;

        final ftthOp = entry.value;
        if (ftthOp.subscriptionOps == 0) continue;
        ftthOnly += ftthOp.subscriptionOps;

        final List<_FtthTransaction> missingTxs = [];
        final List<_WrongTransaction> wrongTxs = [];
        for (final tx in ftthOp.transactions) {
          if (!_subscriptionTypeSet.contains(tx.type)) continue;
          if (existingFtthIds.contains(tx.id)) continue;
          final dateStr = tx.occuredAt.length >= 10 ? tx.occuredAt.substring(0, 10) : tx.occuredAt;
          final amt = tx.amount.abs().toInt();
          final cid = tx.customerId.trim();
          final cidKey = '$cid|$amt|$dateStr';
          if (existingKeys.contains(cidKey)) continue;
          final cidDate = '$cid|$dateStr';
          if (cid.isNotEmpty && cidDateAmounts.containsKey(cidDate)) {
            wrongTxs.add(_WrongTransaction(
              ftthTx: tx,
              oursAmount: cidDateAmounts[cidDate]!,
              ftthAmount: amt,
            ));
          } else {
            missingTxs.add(tx);
          }
        }

        // محاولة ربط المشغل بـ userId من كل المستخدمين (بحث بـ ftthUsername أو username أو fullName)
        String? unmatchedUserId;
        final ftthKey = entry.key.toLowerCase().trim();
        for (final op in _oursOperators) {
          final fUser = (op['ftthUsername'] ?? '').toString().toLowerCase().trim();
          final uName = (op['username'] ?? '').toString().toLowerCase().trim();
          final oName = (op['operatorName'] ?? '').toString().toLowerCase().trim();
          if (ftthKey == fUser || ftthKey == uName || ftthKey == oName) {
            unmatchedUserId = op['userId']?.toString();
            break;
          }
        }

        rows.add(_ComparisonRow(
          operatorName: ftthOp.name,
          operatorUserId: unmatchedUserId,
          oursCount: 0,
          oursAmount: 0,
          ftthCount: ftthOp.subscriptionOps,
          ftthAmount: ftthOp.negativeAmount.abs(),
          matchedCount: 0,
          oursOnlyCount: 0,
          ftthOnlyCount: missingTxs.length,
          ftthTransactions: missingTxs,
          wrongTransactions: wrongTxs,
        ));
      }

      // ترتيب: الأكثر عمليات أولاً
      rows.sort((a, b) => (b.oursCount + b.ftthCount)
          .compareTo(a.oursCount + a.ftthCount));

      _comparisonRows = rows;
      _totalMatched = matched;
      _totalOursOnly = oursOnly;
      _totalFtthOnly = ftthOnly;
    } catch (e) {
      debugPrint('خطأ في بناء المقارنة: $e');
    }

    if (mounted) setState(() => _isLoadingCompare = false);
  }

  // ════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isMobile = context.accR.isMobile;

    // حماية الصفحة بصلاحية
    if (!PermissionManager.instance.canView('accounting.ftth_operators') &&
        !PermissionManager.instance.canView('accounting')) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('غير مصرح')),
          body: const Center(child: Text('لا تملك صلاحية الوصول لهذه الصفحة')),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        appBar: AppBar(
          backgroundColor: AccountingTheme.bgSidebar,
          iconTheme: const IconThemeData(color: Colors.white),
          toolbarHeight: 44,
          titleSpacing: 0,
          title: Row(
            children: [
              // قائمة التاريخ المنسدلة
              PopupMenuButton<String>(
                tooltip: 'فلتر التاريخ',
                offset: const Offset(0, 44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                onSelected: (value) {
                  if (value == 'مخصص') {
                    _showCustomDatePicker();
                  } else {
                    _applyDateFilter(value);
                  }
                },
                itemBuilder: (ctx) => [
                  for (final label in ['اليوم', 'أمس', 'اليوم + أمس', 'آخر 7 أيام', 'هذا الشهر', 'الكل'])
                    PopupMenuItem<String>(
                      value: label,
                      child: Row(
                        children: [
                          if (_dateLabel == label)
                            Icon(Icons.check, size: 16, color: AccountingTheme.neonBlue)
                          else
                            const SizedBox(width: 16),
                          const SizedBox(width: 8),
                          Text(label, style: GoogleFonts.cairo(
                              fontSize: context.accR.small,
                              fontWeight: _dateLabel == label ? FontWeight.w700 : FontWeight.w500)),
                        ],
                      ),
                    ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'مخصص',
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month, size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 8),
                        Text('مخصص', style: GoogleFonts.cairo(fontSize: context.accR.small)),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: context.accR.spaceS,
                      vertical: context.accR.spaceXS),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.date_range,
                          size: context.accR.iconS, color: Colors.white70),
                      if (!isMobile) ...[
                        SizedBox(width: context.accR.spaceXS),
                        Text(
                          _dateLabel,
                          style: GoogleFonts.cairo(
                            fontSize: context.accR.small,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_fromDate != null && _toDate != null) ...[
                          SizedBox(width: context.accR.spaceXS),
                          Text(
                            '${DateFormat('MM/dd').format(_fromDate!)} - ${DateFormat('MM/dd').format(_toDate!)}',
                            style: TextStyle(
                                fontSize: context.accR.caption,
                                color: Colors.white54),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              if (!isMobile) ...[
                const Spacer(),
                // التبويبات في الوسط
                _tabButton(0, Icons.storage, 'خادمنا'),
                _tabButton(1, Icons.wifi_tethering, 'FTTH'),
                _tabButton(2, Icons.compare_arrows, 'المقارنة'),
                const Spacer(),
              ] else
                const Spacer(),
            ],
          ),
          actions: [
            if (isMobile) ...[
              // Mobile: only refresh + overflow menu
              IconButton(
                icon: Icon(Icons.refresh,
                    color: Colors.white70, size: context.accR.iconM),
                onPressed: _refreshAll,
                tooltip: 'تحديث الكل',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert,
                    color: Colors.white70, size: context.accR.iconM),
                onSelected: (v) {
                  switch (v) {
                    case 'ftthLogin':
                      _showFtthLoginDialog();
                      break;
                    case 'receiveCash':
                      _showReceiveCashDialog();
                      break;
                    case 'planPricing':
                      _showPlanPricingDialog();
                      break;
                    case 'advancedFilter':
                      _showAdvancedFilterDialog();
                      break;
                    case 'team':
                      _showTeamDialog();
                      break;
                    case 'linking':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              FtthOperatorLinkingPage(companyId: _companyId),
                        ),
                      );
                      break;
                    case 'sync':
                      _syncFtthToOurServer();
                      break;
                    case 'resolveOrphans':
                      _resolveOrphansInBackground();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  if (!_ftthAuthenticated)
                    const PopupMenuItem(
                        value: 'ftthLogin',
                        child: ListTile(
                            leading:
                                Icon(Icons.login, color: Colors.orangeAccent),
                            title: Text('تسجيل دخول FTTH'),
                            dense: true,
                            contentPadding: EdgeInsets.zero)),
                  const PopupMenuItem(
                      value: 'receiveCash',
                      child: ListTile(
                          leading: Icon(Icons.move_to_inbox,
                              color: Colors.greenAccent),
                          title: Text('استلام نقد من مشغل'),
                          dense: true,
                          contentPadding: EdgeInsets.zero)),
                  const PopupMenuItem(
                      value: 'planPricing',
                      child: ListTile(
                          leading: Icon(Icons.price_change_outlined,
                              color: Colors.amberAccent),
                          title: Text('أسعار الباقات'),
                          dense: true,
                          contentPadding: EdgeInsets.zero)),
                  PopupMenuItem(
                      value: 'advancedFilter',
                      child: ListTile(
                          leading: Icon(Icons.tune,
                              color: _hasActiveAdvancedFilters()
                                  ? Colors.orangeAccent
                                  : Colors.grey),
                          title: const Text('تصفية متقدمة'),
                          dense: true,
                          contentPadding: EdgeInsets.zero)),
                  if (_ftthAuthenticated) ...[
                    const PopupMenuItem(
                        value: 'team',
                        child: ListTile(
                            leading:
                                Icon(Icons.group, color: Colors.cyanAccent),
                            title: Text('الفريق'),
                            dense: true,
                            contentPadding: EdgeInsets.zero)),
                    const PopupMenuItem(
                        value: 'linking',
                        child: ListTile(
                            leading: Icon(Icons.link, color: Colors.limeAccent),
                            title: Text('ربط المشغلين'),
                            dense: true,
                            contentPadding: EdgeInsets.zero)),
                    const PopupMenuItem(
                        value: 'sync',
                        child: ListTile(
                            leading: Icon(Icons.sync,
                                color: Colors.lightGreenAccent),
                            title: Text('مزامنة FTTH → خادمنا'),
                            dense: true,
                            contentPadding: EdgeInsets.zero)),
                    if (!_isResolvingOrphans && _ftthOperators.isNotEmpty)
                      const PopupMenuItem(
                          value: 'resolveOrphans',
                          child: ListTile(
                              leading: Icon(Icons.person_search,
                                  color: Colors.orangeAccent),
                              title: Text('إعادة نسب المعاملات'),
                              dense: true,
                              contentPadding: EdgeInsets.zero)),
                  ],
                ],
              ),
              if (_ftthAuthenticated)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(Icons.check_circle,
                      color: Colors.greenAccent, size: 14),
                ),
              if (_isResolvingOrphans)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.orangeAccent),
                    ),
                  ),
                ),
              SizedBox(width: context.accR.spaceXS),
            ] else ...[
              // Desktop: all buttons visible
              if (!_ftthAuthenticated)
                IconButton(
                  icon: const Icon(Icons.login, color: Colors.orangeAccent),
                  onPressed: _showFtthLoginDialog,
                  tooltip: 'تسجيل دخول FTTH',
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36),
                ),
              IconButton(
                icon: Icon(Icons.refresh,
                    color: Colors.white70, size: context.accR.iconM),
                onPressed: _refreshAll,
                tooltip: 'تحديث الكل',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36),
              ),
              IconButton(
                icon: Stack(
                  children: [
                    Icon(Icons.tune,
                        color: Colors.white70, size: context.accR.iconM),
                    if (_hasActiveAdvancedFilters())
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.orangeAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: _showAdvancedFilterDialog,
                tooltip: 'تصفية متقدمة',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert,
                    color: Colors.white70, size: context.accR.iconM),
                tooltip: 'المزيد',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36),
                onSelected: (v) {
                  if (v == 'team') _showTeamDialog();
                  if (v == 'pricing') _showPlanPricingDialog();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'pricing',
                    child: ListTile(
                      leading: Icon(Icons.price_change_outlined, color: Colors.amber),
                      title: Text('أسعار الباقات'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (_ftthAuthenticated)
                    const PopupMenuItem(
                      value: 'team',
                      child: ListTile(
                        leading: Icon(Icons.group, color: Colors.cyan),
                        title: Text('الفريق'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),
              SizedBox(width: context.accR.spaceXS),
            ],
          ],
        ),
        body: Column(
          children: [
            // ═══ تبويبات الموبايل ═══
            if (isMobile)
              Container(
                color: AccountingTheme.bgSidebar,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: _tabButton(0, Icons.storage, 'خادمنا')),
                    const SizedBox(width: 4),
                    Expanded(
                        child: _tabButton(1, Icons.wifi_tethering, 'FTTH')),
                    const SizedBox(width: 4),
                    Expanded(
                        child: _tabButton(2, Icons.compare_arrows, 'المقارنة')),
                  ],
                ),
              ),
            // (فلتر التاريخ أصبح في القائمة المنسدلة)
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOursTab(),
                  _buildFtthTab(),
                  _buildCompareTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(int index, IconData icon, String label) {
    final isSelected = _tabController.index == index;
    final isMobile = context.accR.isMobile;
    return Padding(
      padding: EdgeInsets.only(left: 2),
      child: InkWell(
        onTap: () {
          _tabController.animateTo(index);
          setState(() {});
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 8 : context.accR.spaceM,
              vertical: context.accR.spaceXS),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.white54,
              width: isSelected ? 1.5 : 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: isMobile ? 14 : context.accR.iconS,
                  color: isSelected
                      ? Colors.teal.shade800
                      : Colors.white.withOpacity(0.85)),
              SizedBox(width: isMobile ? 3 : 5),
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 11 : 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.teal.shade800
                      : Colors.white.withOpacity(0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _refreshAll() {
    _loadOursData();
    if (_ftthAuthenticated) _loadFtthData();
    _comparisonRows.clear();
  }

  /// تصحيح السجلات القديمة التي لا تحتوي على CompanyId
  Future<void> _fixOrphanRecords() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تصحيح السجلات القديمة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
          content: Text(
            'سيتم إسناد الشركة تلقائياً للسجلات التي لا تحتوي على شركة.\n'
            'هذا الإجراء آمن ولا يمكن التراجع عنه.',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              child: Text('تصحيح', style: GoogleFonts.cairo(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final token = VpsAuthService.instance.accessToken;
      final response = await http.post(
        Uri.parse(
            'https://api.ramzalsadara.tech/api/ftth-accounting/fix-orphan-records'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'X-Api-Key': 'sadara-internal-2024-secure-key',
        },
      );
      if (!mounted) return;
      String message;
      if (response.statusCode == 403 || response.statusCode == 401) {
        message = 'هذه العملية تحتاج صلاحية مدير الشركة أو سوبر أدمن';
      } else {
        try {
          final body = jsonDecode(response.body);
          message = body['message'] ?? (response.statusCode == 200 ? 'تم بنجاح' : 'فشل');
        } catch (_) {
          message = response.statusCode == 200 ? 'تم بنجاح' : 'فشل (${response.statusCode})';
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.cairo()),
          backgroundColor:
              response.statusCode == 200 ? Colors.teal : Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      if (response.statusCode == 200) _loadOursData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ', style: GoogleFonts.cairo()),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// تصحيح السجلات التي لا تحتوي على UserId أو CollectionType
  Future<void> _fixMissingUserIds() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تصحيح بيانات المشغلين',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
          content: Text(
            'سيتم:\n'
            '• ربط السجلات بالمشغل الصحيح عبر مستخدم FTTH\n'
            '• تصنيف السجلات غير المصنّفة كـ "نقد" افتراضياً\n\n'
            'هذا الإجراء آمن ولا يؤثر على المبالغ.',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
              child:
                  Text('تصحيح', style: GoogleFonts.cairo(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final token = VpsAuthService.instance.accessToken;
      final companyId = _companyId.isNotEmpty ? '?companyId=$_companyId' : '';
      final response = await http.post(
        Uri.parse(
            'https://api.ramzalsadara.tech/api/ftth-accounting/fix-missing-userids$companyId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'X-Api-Key': 'sadara-internal-2024-secure-key',
        },
      );
      if (!mounted) return;
      String message;
      try {
        final body = jsonDecode(response.body);
        message = body['message'] ?? (response.statusCode == 200 ? 'تم بنجاح' : 'فشل');
      } catch (_) {
        message = response.statusCode == 200 ? 'تم بنجاح' : 'فشل (${response.statusCode})';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.cairo()),
          backgroundColor: response.statusCode == 200 ? Colors.indigo : Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      if (response.statusCode == 200) _loadOursData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ', style: GoogleFonts.cairo()),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// تعيين السجلات المجهولة (UserId=null) يدوياً لمستخدم محدد
  Future<void> _assignUnknownRecords() async {
    // جلب قائمة المستخدمين من الباكيند
    final vpsToken = VpsAuthService.instance.accessToken;
    List<Map<String, dynamic>> users = [];
    try {
      final url = _companyId.isNotEmpty
          ? 'https://api.ramzalsadara.tech/api/ftth-accounting/operators-linking?companyId=$_companyId'
          : 'https://api.ramzalsadara.tech/api/ftth-accounting/operators-linking';
      final res = await http.get(Uri.parse(url), headers: {
        if (vpsToken != null) 'Authorization': 'Bearer $vpsToken',
        'X-Api-Key': 'sadara-internal-2024-secure-key',
      });
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        users = List<Map<String, dynamic>>.from(body['data'] ?? []);
      }
    } catch (_) {}

    if (!mounted) return;
    if (users.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('لم يتم جلب المستخدمين', style: GoogleFonts.cairo()),
        backgroundColor: Colors.red,
      ));
      return;
    }

    String? selectedUserId;
    String? selectedUserName;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('تعيين المشغل للسجلات المجهولة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('اختر المشغل الذي نفّذ السجلات المجهولة:',
                    style: GoogleFonts.cairo()),
                SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'المشغل',
                    labelStyle: GoogleFonts.cairo(),
                  ),
                  items: users.map((u) {
                    final id = u['id']?.toString() ?? '';
                    final name = u['fullName']?.toString() ?? u['username']?.toString() ?? id;
                    return DropdownMenuItem(value: id, child: Text(name, style: GoogleFonts.cairo()));
                  }).toList(),
                  onChanged: (val) {
                    setDlgState(() {
                      selectedUserId = val;
                      selectedUserName = users.firstWhere((u) => u['id']?.toString() == val, orElse: () => {})['fullName']?.toString();
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('إلغاء', style: GoogleFonts.cairo()),
              ),
              ElevatedButton(
                onPressed: selectedUserId == null ? null : () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                child: Text('تعيين', style: GoogleFonts.cairo(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true || selectedUserId == null || !mounted) return;

    try {
      final companyParam = _companyId.isNotEmpty ? '&companyId=$_companyId' : '';
      final response = await http.post(
        Uri.parse('https://api.ramzalsadara.tech/api/ftth-accounting/assign-unknown-records?targetUserId=$selectedUserId$companyParam'),
        headers: {
          'Content-Type': 'application/json',
          if (vpsToken != null) 'Authorization': 'Bearer $vpsToken',
          'X-Api-Key': 'sadara-internal-2024-secure-key',
        },
      );
      if (!mounted) return;
      String message;
      try {
        final body = jsonDecode(response.body);
        message = body['message'] ?? (response.statusCode == 200 ? 'تم بنجاح' : 'فشل');
      } catch (_) {
        message = response.statusCode == 200 ? 'تم بنجاح' : 'فشل (${response.statusCode})';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message, style: GoogleFonts.cairo()),
        backgroundColor: response.statusCode == 200 ? Colors.teal : Colors.red,
        duration: const Duration(seconds: 5),
      ));
      if (response.statusCode == 200) _loadOursData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('خطأ', style: GoogleFonts.cairo()),
        backgroundColor: Colors.red,
      ));
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  عرض بيانات الفريق من admin.ftth.iq/api/teams/members
  // ════════════════════════════════════════════════════════════════
  Future<void> _showTeamDialog() async {
    if (!_ftthAuthenticated) return;

    // الانتقال لصفحة الفريق مباشرة (تجلب البيانات داخلياً)
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _FtthTeamPage()),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  تحميل المناطق والمستخدمين
  // ════════════════════════════════════════════════════════════════

  Future<void> _loadAvailableZones() async {
    if (!mounted || _isLoadingZones) return;
    setState(() => _isLoadingZones = true);
    try {
      final token = await AuthService.instance.getAccessToken();
      if (token == null) return;
      final response = await http.get(
        Uri.parse('https://admin.ftth.iq/api/locations/zones'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> rawZones = data['items'] ?? [];
        final List<String> fetched = [];
        for (final zone in rawZones) {
          if (zone is Map<String, dynamic>) {
            String? name;
            if (zone['self'] is Map<String, dynamic>) {
              final self = zone['self'] as Map<String, dynamic>;
              name = self['displayValue']?.toString() ?? self['id']?.toString();
            } else {
              name = zone['displayValue']?.toString() ??
                  zone['name']?.toString() ??
                  zone['id']?.toString();
            }
            if (name != null && name.isNotEmpty) fetched.add(name);
          }
        }
        fetched.sort((a, b) {
          final reg = RegExp(r'^(.*?)(\d+)(.*)');
          final ma = reg.firstMatch(a.toLowerCase());
          final mb = reg.firstMatch(b.toLowerCase());
          if (ma != null && mb != null && ma.group(1) == mb.group(1)) {
            return int.parse(ma.group(2)!).compareTo(int.parse(mb.group(2)!));
          }
          return a.toLowerCase().compareTo(b.toLowerCase());
        });
        if (mounted) setState(() => _availableZones = fetched);
      }
    } catch (e) {
      debugPrint('خطأ تحميل المناطق');
    } finally {
      if (mounted) setState(() => _isLoadingZones = false);
    }
  }

  Future<void> _loadAvailableUsernames() async {
    if (!mounted || _isLoadingUsernames) return;
    setState(() => _isLoadingUsernames = true);
    try {
      final token = await AuthService.instance.getAccessToken();
      if (token == null) return;
      final response = await http.get(
        Uri.parse('https://admin.ftth.iq/api/users?pageSize=1000'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List? ?? [];
        final Set<String> names = {};
        for (final u in items) {
          final uname = u['username']?.toString() ?? '';
          if (uname.isNotEmpty) names.add(uname);
        }
        final sorted = names.toList()..sort();
        if (mounted) setState(() => _availableUsernames = sorted);
      }
    } catch (e) {
      debugPrint('خطأ تحميل المستخدمين');
    } finally {
      if (mounted) setState(() => _isLoadingUsernames = false);
    }
  }

  bool _hasActiveAdvancedFilters() {
    return _selectedWalletTypes.isNotEmpty ||
        _selectedWalletOwnerTypes.length != 1 ||
        !_selectedWalletOwnerTypes.contains('partner') ||
        _selectedSalesTypes.isNotEmpty ||
        _selectedChangeTypes.isNotEmpty ||
        _selectedPaymentMethods.isNotEmpty ||
        _selectedZones.isNotEmpty ||
        _selectedTransactionTypes.isNotEmpty ||
        _selectedServiceNames.isNotEmpty ||
        (_transactionUser != null && _transactionUser!.isNotEmpty) ||
        _showTransactionsWithoutUser;
  }

  // ════════════════════════════════════════════════════════════════
  //  حوار إدارة أسعار الباقات
  // ════════════════════════════════════════════════════════════════

  void _showPlanPricingDialog() async {
    await PlanPricingService.instance.load();
    final pricing = PlanPricingService.instance;

    // الباقات المتاحة مع أسعار افتراضية
    final allPlans = <String, double>{
      'FIBER 35': 35000,
      'FIBER 50': 50000,
      'FIBER 75': 75000,
      'FIBER 150': 150000,
      'IPTV': 0,
      'Parental Control': 0,
      'VOIP': 0,
      'VOD': 0,
      'Learning Platform': 0,
      'Hardware Plan ONT': 0,
      'Hardware Plan Router': 0,
      'Grace Plan': 0,
    };

    // إنشاء controllers لكل باقة
    final controllers = <String, TextEditingController>{};
    for (final plan in allPlans.keys) {
      final savedPrice = pricing.getPrice(plan);
      final defaultPrice = allPlans[plan] ?? 0;
      controllers[plan] = TextEditingController(
        text: (savedPrice ?? (defaultPrice > 0 ? defaultPrice : null))
                ?.toStringAsFixed(0) ??
            '',
      );
    }

    // controller لإضافة باقة مخصصة
    final customNameController = TextEditingController();
    final customPriceController = TextEditingController();

    // أسعار مخصصة أضافها المستخدم سابقاً
    final customPlans = <String, TextEditingController>{};
    for (final entry in pricing.allPrices.entries) {
      if (!allPlans.containsKey(entry.key)) {
        customPlans[entry.key] = TextEditingController(
          text: entry.value.toStringAsFixed(0),
        );
      }
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(context.accR.radiusL)),
                title: Row(
                  children: [
                    Icon(Icons.price_change,
                        color: Colors.amber.shade700, size: context.accR.iconM),
                    SizedBox(width: context.accR.spaceS),
                    Expanded(
                      child: Text('أسعار الباقات الحقيقية',
                          style: GoogleFonts.cairo(
                              fontSize: context.accR.body,
                              fontWeight: FontWeight.w700)),
                    ),
                    // زر تعيين الأسعار الافتراضية
                    TextButton.icon(
                      onPressed: () {
                        setDialogState(() {
                          for (final entry
                              in PlanPricingService.defaultPrices.entries) {
                            controllers[entry.key]?.text =
                                entry.value.toStringAsFixed(0);
                          }
                        });
                      },
                      icon: Icon(Icons.restore, size: context.accR.iconS),
                      label: Text('افتراضي',
                          style:
                              GoogleFonts.cairo(fontSize: context.accR.small)),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: context.accR.dialogMediumW,
                  height: 500,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // شرح
                        Container(
                          padding: EdgeInsets.all(context.accR.spaceM),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.amber.shade700,
                                  size: context.accR.iconM),
                              SizedBox(width: context.accR.spaceS),
                              Expanded(
                                child: Text(
                                  'أدخل السعر الحقيقي لكل باقة (بدون خصم).\n'
                                  'سيتم مقارنته بالمبلغ الفعلي في المعاملات لإظهار الخصم.',
                                  style: GoogleFonts.cairo(
                                      fontSize: context.accR.small,
                                      color: Colors.amber.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: context.accR.spaceM),

                        // باقات Fiber الرئيسية
                        Text('باقات الإنترنت',
                            style: GoogleFonts.cairo(
                                fontSize: context.accR.financialSmall,
                                fontWeight: FontWeight.w700,
                                color: Colors.teal.shade700)),
                        SizedBox(height: context.accR.spaceXS),
                        ..._buildPricingFields(
                          controllers,
                          ['FIBER 35', 'FIBER 50', 'FIBER 75', 'FIBER 150'],
                        ),

                        const Divider(height: 20),

                        // باقات إضافية
                        Text('خدمات إضافية',
                            style: GoogleFonts.cairo(
                                fontSize: context.accR.financialSmall,
                                fontWeight: FontWeight.w700,
                                color: Colors.teal.shade700)),
                        SizedBox(height: context.accR.spaceXS),
                        ..._buildPricingFields(
                          controllers,
                          [
                            'IPTV',
                            'Parental Control',
                            'VOIP',
                            'VOD',
                            'Learning Platform',
                            'Hardware Plan ONT',
                            'Hardware Plan Router',
                            'Grace Plan',
                          ],
                        ),

                        // باقات مخصصة
                        if (customPlans.isNotEmpty) ...[
                          Divider(height: 20),
                          Text('باقات مخصصة',
                              style: GoogleFonts.cairo(
                                  fontSize: context.accR.financialSmall,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.purple.shade700)),
                          SizedBox(height: context.accR.spaceXS),
                          ...customPlans.entries.map((entry) {
                            return Padding(
                              padding: EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(entry.key,
                                        style: GoogleFonts.cairo(
                                            fontSize: context.accR.small,
                                            fontWeight: FontWeight.w500)),
                                  ),
                                  SizedBox(width: context.accR.spaceS),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: entry.value,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.cairo(
                                          fontSize: context.accR.small),
                                      decoration: InputDecoration(
                                        hintText: 'السعر',
                                        suffixText: 'د.ع',
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 8),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline,
                                        color: Colors.red.shade400,
                                        size: context.accR.iconM),
                                    onPressed: () {
                                      setDialogState(() {
                                        customPlans.remove(entry.key);
                                      });
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints:
                                        const BoxConstraints(minWidth: 30),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],

                        // إضافة باقة مخصصة
                        Divider(height: 20),
                        Text('إضافة باقة جديدة',
                            style: GoogleFonts.cairo(
                                fontSize: context.accR.financialSmall,
                                fontWeight: FontWeight.w700,
                                color: Colors.blue.shade700)),
                        SizedBox(height: context.accR.spaceXS),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: customNameController,
                                style: GoogleFonts.cairo(
                                    fontSize: context.accR.small),
                                decoration: InputDecoration(
                                  hintText: 'اسم الباقة',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: context.accR.spaceS),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: customPriceController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cairo(
                                    fontSize: context.accR.small),
                                decoration: InputDecoration(
                                  hintText: 'السعر',
                                  suffixText: 'د.ع',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.add_circle,
                                  color: Colors.green.shade600,
                                  size: context.accR.iconM),
                              onPressed: () {
                                final name = customNameController.text.trim();
                                final price = double.tryParse(
                                    customPriceController.text.trim());
                                if (name.isNotEmpty && price != null) {
                                  setDialogState(() {
                                    customPlans[name] = TextEditingController(
                                        text: price.toStringAsFixed(0));
                                    customNameController.clear();
                                    customPriceController.clear();
                                  });
                                }
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 30),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('إلغاء',
                        style: GoogleFonts.cairo(color: Colors.grey)),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      // حفظ جميع الأسعار
                      final Map<String, double> prices = {};

                      // الباقات المعروفة
                      for (final entry in controllers.entries) {
                        final val = double.tryParse(entry.value.text.trim());
                        if (val != null && val > 0) {
                          prices[entry.key] = val;
                        }
                      }

                      // الباقات المخصصة
                      for (final entry in customPlans.entries) {
                        final val = double.tryParse(entry.value.text.trim());
                        if (val != null && val > 0) {
                          prices[entry.key] = val;
                        }
                      }

                      // حفظ
                      final pricingService = PlanPricingService.instance;
                      // مسح القديم وإعادة التعيين
                      for (final key
                          in pricingService.allPrices.keys.toList()) {
                        await pricingService.removePrice(key);
                      }
                      await pricingService.setPrices(prices);

                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'تم حفظ أسعار ${prices.length} باقة',
                              style: GoogleFonts.cairo(),
                              textDirection: TextDirection.rtl,
                            ),
                            backgroundColor: Colors.teal,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                        setState(() {}); // تحديث الواجهة
                      }
                    },
                    icon: Icon(Icons.save, size: context.accR.iconM),
                    label: Text('حفظ الأسعار',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // تنظيف controllers
    for (final c in controllers.values) {
      c.dispose();
    }
    for (final c in customPlans.values) {
      c.dispose();
    }
    customNameController.dispose();
    customPriceController.dispose();
  }

  /// بناء حقول إدخال الأسعار
  List<Widget> _buildPricingFields(
    Map<String, TextEditingController> controllers,
    List<String> planNames,
  ) {
    return planNames.map((name) {
      return Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(name,
                  style: GoogleFonts.cairo(
                      fontSize: context.accR.small,
                      fontWeight: FontWeight.w500)),
            ),
            SizedBox(width: context.accR.spaceS),
            Expanded(
              flex: 2,
              child: TextField(
                controller: controllers[name],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(fontSize: context.accR.small),
                decoration: InputDecoration(
                  hintText: 'السعر',
                  suffixText: 'د.ع',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: context.accR.spaceS,
                      vertical: context.accR.spaceS),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // ════════════════════════════════════════════════════════════════
  //  حوار التصفية المتقدمة
  // ════════════════════════════════════════════════════════════════

  void _showAdvancedFilterDialog() {
    // نسخ مؤقتة للتعديل داخل الحوار
    List<String> tmpWalletTypes = List.from(_selectedWalletTypes);
    List<String> tmpWalletOwnerTypes = List.from(_selectedWalletOwnerTypes);
    List<String> tmpSalesTypes = List.from(_selectedSalesTypes);
    List<String> tmpChangeTypes = List.from(_selectedChangeTypes);
    List<String> tmpPaymentMethods = List.from(_selectedPaymentMethods);
    List<String> tmpZones = List.from(_selectedZones);
    List<String> tmpTransactionTypes = List.from(_selectedTransactionTypes);
    List<String> tmpServiceNames = List.from(_selectedServiceNames);
    String? tmpUser = _transactionUser;
    bool tmpWithoutUser = _showTransactionsWithoutUser;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            Widget section(String title, IconData icon, Widget content) {
              return Container(
                margin: EdgeInsets.only(bottom: context.accR.spaceM),
                padding: EdgeInsets.all(context.accR.spaceM),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(context.accR.cardRadius),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon,
                            size: context.accR.iconM, color: Color(0xFF1A237E)),
                        SizedBox(width: context.accR.spaceS),
                        Text(title,
                            style: GoogleFonts.cairo(
                              fontSize: context.accR.body,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1A237E),
                            )),
                      ],
                    ),
                    SizedBox(height: context.accR.spaceS),
                    content,
                  ],
                ),
              );
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(context.accR.radiusL)),
                title: Row(
                  children: [
                    Icon(Icons.tune,
                        color: Color(0xFF1A237E), size: context.accR.iconM),
                    SizedBox(width: context.accR.spaceM),
                    Text('تصفية متقدمة',
                        style: GoogleFonts.cairo(
                          fontSize: context.accR.headingSmall,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A237E),
                        )),
                    Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        setDlg(() {
                          tmpWalletTypes.clear();
                          tmpWalletOwnerTypes = ['partner'];
                          tmpSalesTypes.clear();
                          tmpChangeTypes.clear();
                          tmpPaymentMethods.clear();
                          tmpZones.clear();
                          tmpTransactionTypes.clear();
                          tmpServiceNames.clear();
                          tmpUser = null;
                          tmpWithoutUser = false;
                        });
                      },
                      icon: Icon(Icons.restart_alt,
                          size: context.accR.iconS, color: Colors.red.shade400),
                      label: Text('إعادة تعيين',
                          style: TextStyle(
                            fontSize: context.accR.small,
                            color: Colors.red.shade400,
                          )),
                    ),
                  ],
                ),
                content: Container(
                  width: context.accR.dialogMediumW,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.75,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // اسم المستخدم
                        section(
                            'اسم المستخدم',
                            Icons.person,
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_isLoadingUsernames)
                                  Row(children: [
                                    const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                    SizedBox(width: context.accR.spaceS),
                                    Text('جارٍ تحميل الاقتراحات...',
                                        style: TextStyle(
                                            fontSize: context.accR.small,
                                            color: Colors.grey.shade600)),
                                  ]),
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    hintText: 'اختر اسم المستخدم',
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    isDense: true,
                                  ),
                                  value: (tmpUser != null &&
                                          _availableUsernames.contains(tmpUser))
                                      ? tmpUser
                                      : null,
                                  items: _availableUsernames
                                      .map((u) => DropdownMenuItem(
                                          value: u,
                                          child: Text(u,
                                              style: TextStyle(
                                                  fontSize: context
                                                      .accR.financialSmall))))
                                      .toList(),
                                  onChanged: (v) => setDlg(() => tmpUser = v),
                                ),
                                SizedBox(height: context.accR.spaceXS),
                                Row(children: [
                                  TextButton.icon(
                                    onPressed: () =>
                                        setDlg(() => tmpUser = null),
                                    icon: Icon(Icons.clear,
                                        size: context.accR.iconXS),
                                    label: Text('مسح',
                                        style: TextStyle(
                                            fontSize: context.accR.small)),
                                    style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(0, 30)),
                                  ),
                                ]),
                                CheckboxListTile(
                                  title: Text('العمليات بدون مستخدم',
                                      style: TextStyle(
                                          fontSize:
                                              context.accR.financialSmall)),
                                  value: tmpWithoutUser,
                                  onChanged: (v) => setDlg(() {
                                    tmpWithoutUser = v ?? false;
                                    if (tmpWithoutUser) tmpUser = null;
                                  }),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                ),
                              ],
                            )),

                        // مالك المحفظة
                        section(
                            'مالك المحفظة',
                            Icons.account_balance_wallet,
                            Wrap(
                              spacing: 8,
                              children: _walletOwnerTypes.map((t) {
                                final selected =
                                    tmpWalletOwnerTypes.contains(t['value']);
                                return FilterChip(
                                  label: Text(t['label']!,
                                      style: TextStyle(
                                        fontSize: context.accR.small,
                                        color: selected
                                            ? Colors.white
                                            : Colors.grey.shade700,
                                      )),
                                  selected: selected,
                                  selectedColor: const Color(0xFF1A237E),
                                  checkmarkColor: Colors.white,
                                  onSelected: (v) => setDlg(() {
                                    if (v) {
                                      tmpWalletOwnerTypes.add(t['value']!);
                                    } else {
                                      tmpWalletOwnerTypes.remove(t['value']!);
                                    }
                                  }),
                                );
                              }).toList(),
                            )),

                        // نوع المحفظة
                        section(
                            'نوع المحفظة',
                            Icons.wallet,
                            Wrap(
                              spacing: 8,
                              children: _walletTypes.map((t) {
                                final selected =
                                    tmpWalletTypes.contains(t['value']);
                                return FilterChip(
                                  label: Text(t['label']!,
                                      style: TextStyle(
                                        fontSize: context.accR.small,
                                        color: selected
                                            ? Colors.white
                                            : Colors.grey.shade700,
                                      )),
                                  selected: selected,
                                  selectedColor: const Color(0xFF1A237E),
                                  checkmarkColor: Colors.white,
                                  onSelected: (v) => setDlg(() {
                                    if (v)
                                      tmpWalletTypes.add(t['value']!);
                                    else
                                      tmpWalletTypes.remove(t['value']!);
                                  }),
                                );
                              }).toList(),
                            )),

                        // المناطق
                        section(
                            'المنطقة (Zone)',
                            Icons.location_on,
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_isLoadingZones)
                                  Row(children: [
                                    const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                    SizedBox(width: context.accR.spaceS),
                                    Text('جارٍ تحميل المناطق...',
                                        style: TextStyle(
                                            fontSize: context.accR.small,
                                            color: Colors.grey.shade600)),
                                  ])
                                else if (_availableZones.isEmpty)
                                  Text('لا توجد مناطق',
                                      style: TextStyle(
                                          fontSize: context.accR.small,
                                          color: Colors.grey.shade500))
                                else
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tmpZones.isEmpty
                                            ? 'كل المناطق (افتراضي)'
                                            : 'محدد: ${tmpZones.length} منطقة',
                                        style: TextStyle(
                                            fontSize: context.accR.small,
                                            color: Colors.grey.shade600),
                                      ),
                                      SizedBox(height: context.accR.spaceXS),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: _availableZones.map((z) {
                                          final selected = tmpZones.contains(z);
                                          return FilterChip(
                                            label: Text(z,
                                                style: TextStyle(
                                                  fontSize: context.accR.small,
                                                  color: selected
                                                      ? Colors.white
                                                      : Colors.grey.shade700,
                                                )),
                                            selected: selected,
                                            selectedColor: Colors.teal.shade600,
                                            checkmarkColor: Colors.white,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            visualDensity:
                                                VisualDensity.compact,
                                            onSelected: (v) => setDlg(() {
                                              if (v)
                                                tmpZones.add(z);
                                              else
                                                tmpZones.remove(z);
                                            }),
                                          );
                                        }).toList(),
                                      ),
                                      if (tmpZones.isNotEmpty) ...[
                                        SizedBox(height: context.accR.spaceXS),
                                        TextButton.icon(
                                          onPressed: () =>
                                              setDlg(() => tmpZones.clear()),
                                          icon: Icon(Icons.clear_all,
                                              size: context.accR.iconXS),
                                          label: Text('مسح الكل',
                                              style: TextStyle(
                                                  fontSize:
                                                      context.accR.small)),
                                          style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              minimumSize: const Size(0, 24)),
                                        ),
                                      ],
                                    ],
                                  ),
                              ],
                            )),

                        // أنواع المبيعات
                        section(
                            'أنواع المبيعات',
                            Icons.sell,
                            Wrap(
                              spacing: 8,
                              children: _salesTypes.map((t) {
                                final selected =
                                    tmpSalesTypes.contains(t['value']);
                                return FilterChip(
                                  label: Text(t['label']!,
                                      style: TextStyle(
                                        fontSize: context.accR.small,
                                        color: selected
                                            ? Colors.white
                                            : Colors.grey.shade700,
                                      )),
                                  selected: selected,
                                  selectedColor: const Color(0xFF1A237E),
                                  checkmarkColor: Colors.white,
                                  onSelected: (v) => setDlg(() {
                                    if (v)
                                      tmpSalesTypes.add(t['value']!);
                                    else
                                      tmpSalesTypes.remove(t['value']!);
                                  }),
                                );
                              }).toList(),
                            )),

                        // أنواع التغيير
                        section(
                            'أنواع التغيير',
                            Icons.swap_horiz,
                            Wrap(
                              spacing: 8,
                              children: _changeTypes.map((t) {
                                final selected =
                                    tmpChangeTypes.contains(t['value']);
                                return FilterChip(
                                  label: Text(t['label']!,
                                      style: TextStyle(
                                        fontSize: context.accR.small,
                                        color: selected
                                            ? Colors.white
                                            : Colors.grey.shade700,
                                      )),
                                  selected: selected,
                                  selectedColor: const Color(0xFF1A237E),
                                  checkmarkColor: Colors.white,
                                  onSelected: (v) => setDlg(() {
                                    if (v)
                                      tmpChangeTypes.add(t['value']!);
                                    else
                                      tmpChangeTypes.remove(t['value']!);
                                  }),
                                );
                              }).toList(),
                            )),

                        // طرق الدفع
                        section(
                            'طرق الدفع',
                            Icons.payment,
                            Wrap(
                              spacing: 8,
                              children: _paymentMethods.map((t) {
                                final selected =
                                    tmpPaymentMethods.contains(t['value']);
                                return FilterChip(
                                  label: Text(t['label']!,
                                      style: TextStyle(
                                        fontSize: context.accR.small,
                                        color: selected
                                            ? Colors.white
                                            : Colors.grey.shade700,
                                      )),
                                  selected: selected,
                                  selectedColor: const Color(0xFF1A237E),
                                  checkmarkColor: Colors.white,
                                  onSelected: (v) => setDlg(() {
                                    if (v)
                                      tmpPaymentMethods.add(t['value']!);
                                    else
                                      tmpPaymentMethods.remove(t['value']!);
                                  }),
                                );
                              }).toList(),
                            )),

                        // أنواع المعاملات
                        section(
                            'أنواع المعاملات',
                            Icons.receipt_long,
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: _transactionTypesList.map((t) {
                                final selected =
                                    tmpTransactionTypes.contains(t['value']);
                                return FilterChip(
                                  label: Text(t['label']!,
                                      style: TextStyle(
                                        fontSize: context.accR.small,
                                        color: selected
                                            ? Colors.white
                                            : Colors.grey.shade700,
                                      )),
                                  selected: selected,
                                  selectedColor: Colors.indigo.shade600,
                                  checkmarkColor: Colors.white,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (v) => setDlg(() {
                                    if (v)
                                      tmpTransactionTypes.add(t['value']!);
                                    else
                                      tmpTransactionTypes.remove(t['value']!);
                                  }),
                                );
                              }).toList(),
                            )),

                        // أسماء الخدمات
                        section(
                            'أسماء الخدمات',
                            Icons.router,
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: _serviceNames.map((t) {
                                final selected =
                                    tmpServiceNames.contains(t['value']);
                                return FilterChip(
                                  label: Text(t['label']!,
                                      style: TextStyle(
                                        fontSize: context.accR.small,
                                        color: selected
                                            ? Colors.white
                                            : Colors.grey.shade700,
                                      )),
                                  selected: selected,
                                  selectedColor: Colors.purple.shade600,
                                  checkmarkColor: Colors.white,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (v) => setDlg(() {
                                    if (v)
                                      tmpServiceNames.add(t['value']!);
                                    else
                                      tmpServiceNames.remove(t['value']!);
                                  }),
                                );
                              }).toList(),
                            )),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('إلغاء',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedWalletTypes = tmpWalletTypes;
                        _selectedWalletOwnerTypes = tmpWalletOwnerTypes;
                        _selectedSalesTypes = tmpSalesTypes;
                        _selectedChangeTypes = tmpChangeTypes;
                        _selectedPaymentMethods = tmpPaymentMethods;
                        _selectedZones = tmpZones;
                        _selectedTransactionTypes = tmpTransactionTypes;
                        _selectedServiceNames = tmpServiceNames;
                        _transactionUser = tmpUser;
                        _showTransactionsWithoutUser = tmpWithoutUser;
                      });
                      Navigator.pop(ctx);
                      _comparisonRows.clear();
                      _refreshAll();
                    },
                    icon: Icon(Icons.check, size: context.accR.iconM),
                    label: Text('تطبيق',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A237E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// بناء معاملات التصفية للـ URL
  List<String> _buildFtthFilterParams() {
    final params = <String>[];
    for (final v in _selectedWalletTypes) {
      params.add('walletType=$v');
    }
    for (final v in _selectedWalletOwnerTypes) {
      params.add('walletOwnerType=$v');
    }
    for (final v in _selectedSalesTypes) {
      params.add('salesTypes=$v');
    }
    for (final v in _selectedChangeTypes) {
      params.add('changeTypes=$v');
    }
    for (final v in _selectedPaymentMethods) {
      params.add('paymentMethods=$v');
    }
    for (final v in _selectedZones) {
      params.add('zones=$v');
    }
    if (_selectedTransactionTypes.isNotEmpty) {
      for (final v in _selectedTransactionTypes) {
        params.add('transactionTypes=$v');
      }
    }
    for (final v in _selectedServiceNames) {
      params.add('subscriptionServiceNames=${Uri.encodeComponent(v)}');
    }
    if (_transactionUser != null && _transactionUser!.isNotEmpty) {
      params.add('transactionUser=${Uri.encodeComponent(_transactionUser!)}');
      params.add('createdBy=${Uri.encodeComponent(_transactionUser!)}');
      params.add('username=${Uri.encodeComponent(_transactionUser!)}');
    }
    return params;
  }

  // ════════════════════════════════════════════════════════════════
  //  TAB 1: خادمنا
  // ════════════════════════════════════════════════════════════════

  Widget _buildOursTab() {
    if (_isLoadingOurs) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorOurs != null) {
      return _buildErrorWidget(_errorOurs!, _loadOursData);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(
          context.accR.isMobile ? context.accR.spaceM : context.accR.spaceXL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ═══ بطاقات الملخص الرئيسية ═══
          _buildOursSummary(),
          SizedBox(height: context.accR.spaceM),
          // ═══ جدول المشغلين ═══
          _buildOursTable(),
        ],
      ),
    );
  }

  Widget _buildOursSummary() {
    if (_oursSummary == null) return const SizedBox();
    final isMobile = context.accR.isMobile;

    // الصف الأول: المستقطع + الإيرادات + المصاريف + الإجمالي + نقد
    final row1 = <Widget>[
      _summaryCard('المستقطع', (_oursSummary!['totalPageDeduction'] ?? 0).toDouble(), '',
          Colors.indigo.shade600,
          icon: Icons.account_balance),
      _summaryCard('الإيرادات', (_oursSummary!['totalRevenue'] ?? 0).toDouble(), '',
          Colors.green.shade700,
          icon: Icons.trending_up),
      _summaryCard('المصاريف', (_oursSummary!['totalExpense'] ?? 0).toDouble(), '',
          Colors.red.shade600,
          icon: Icons.trending_down),
      _summaryCard(
          'إجمالي العمليات',
          (_oursSummary!['totalAmount'] ?? 0).toDouble(),
          '${_oursSummary!['totalActivations'] ?? 0} عملية بواسطة ${_oursSummary!['totalOperators'] ?? 0} مشغل',
          AccountingTheme.neonBlue,
          icon: Icons.analytics_outlined),
      _summaryCard('نقد', (_oursSummary!['totalCash'] ?? 0).toDouble(), '',
          Colors.green.shade600,
          icon: Icons.attach_money),
    ];

    // الصف الثاني: تحصيل + مستحق
    final row2 = <Widget>[
      _summaryCard('آجل', (_oursSummary!['totalCredit'] ?? 0).toDouble(), '',
          Colors.orange.shade600,
          icon: Icons.schedule),
      _summaryCard('ماستر', (_oursSummary!['totalMaster'] ?? 0).toDouble(), '',
          Colors.purple.shade600,
          icon: Icons.credit_card),
      _summaryCard('وكيل', (_oursSummary!['totalAgent'] ?? 0).toDouble(), '',
          Colors.blue.shade600,
          icon: Icons.store),
      _summaryCard('فني', (_oursSummary!['totalTechnician'] ?? 0).toDouble(),
          '', Colors.teal.shade600,
          icon: Icons.engineering),
      _summaryCard('المستحق', (_oursSummary!['totalNetOwed'] ?? 0).toDouble(),
          'نقد + آجل بعد خصم التسليمات', Colors.red.shade600,
          icon: Icons.warning_amber_rounded),
      if ((_oursSummary!['totalUnclassified'] ?? 0).toDouble() > 0)
        _summaryCard(
            'غير مصنّفة',
            (_oursSummary!['totalUnclassified'] ?? 0).toDouble(),
            '${_oursSummary!['totalUnclassifiedCount'] ?? 0} عملية',
            Colors.grey.shade600,
            icon: Icons.help_outline),
    ];

    if (isMobile) {
      final screenW = MediaQuery.of(context).size.width;
      final cardW = (screenW - 32 - 12) / 3;
      return Column(
        children: [
          Wrap(
            spacing: 6, runSpacing: 6,
            children: row1.map((c) => SizedBox(width: cardW, child: c)).toList(),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: row2.map((c) => SizedBox(width: cardW, child: c)).toList(),
          ),
        ],
      );
    }

    Widget buildRow(List<Widget> cards) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: cards
            .map((c) => Expanded(
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: c)))
            .toList(),
      ),
    );

    return Column(
      children: [
        buildRow(row1),
        const SizedBox(height: 8),
        buildRow(row2),
      ],
    );
  }

  /// بطاقات أنواع العمليات (شراء / تجديد / تغيير / جدولة)
  Widget _buildOursOperationTypeSummary() {
    if (_oursSummary == null) return const SizedBox();
    final purchaseAmt = (_oursSummary!['totalPurchase'] ?? 0).toDouble();
    final purchaseCnt = (_oursSummary!['totalPurchaseCount'] ?? 0);
    final renewalAmt = (_oursSummary!['totalRenewal'] ?? 0).toDouble();
    final renewalCnt = (_oursSummary!['totalRenewalCount'] ?? 0);
    final changeAmt = (_oursSummary!['totalChange'] ?? 0).toDouble();
    final changeCnt = (_oursSummary!['totalChangeCount'] ?? 0);
    final scheduleAmt = (_oursSummary!['totalSchedule'] ?? 0).toDouble();
    final scheduleCnt = (_oursSummary!['totalScheduleCount'] ?? 0);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        side: BorderSide(color: Colors.teal.shade200, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(context.accR.spaceM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.category,
                    size: context.accR.iconS, color: Colors.teal.shade700),
                SizedBox(width: context.accR.spaceXS),
                Text('تفصيل أنواع العمليات',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.financialSmall,
                        fontWeight: FontWeight.w700,
                        color: Colors.teal.shade700)),
              ],
            ),
            SizedBox(height: context.accR.spaceM),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _opTypeChip('شراء', purchaseCnt, purchaseAmt,
                    Colors.green.shade700, Icons.shopping_cart),
                _opTypeChip('تجديد', renewalCnt, renewalAmt,
                    Colors.blue.shade700, Icons.autorenew),
                _opTypeChip('تغيير', changeCnt, changeAmt,
                    Colors.orange.shade700, Icons.swap_horiz),
                _opTypeChip('جدولة', scheduleCnt, scheduleAmt,
                    Colors.purple.shade700, Icons.schedule_send),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _opTypeChip(
      String label, dynamic count, double amount, Color color, IconData icon) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.spaceL, vertical: context.accR.spaceS),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: context.accR.iconS, color: color),
          SizedBox(width: context.accR.spaceXS),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$label ($count)',
                  style: TextStyle(
                      fontSize: context.accR.small,
                      fontWeight: FontWeight.w700,
                      color: color)),
              Text(_currencyFormat.format(amount),
                  style: TextStyle(
                      fontSize: context.accR.small,
                      fontWeight: FontWeight.w500,
                      color: color.withOpacity(0.8))),
            ],
          ),
        ],
      ),
    );
  }

  /// بطاقة حالة المطابقة
  Widget _buildOursReconciliationCard() {
    if (_oursSummary == null) return const SizedBox();
    final total = (_oursSummary!['totalActivations'] ?? 0);
    final reconciled = (_oursSummary!['reconciledCount'] ?? 0);
    final pct = (_oursSummary!['reconciledPercentage'] ?? 0).toDouble();
    final unreconciled = total - reconciled;
    final isMobile = context.accR.isMobile;

    final statusColor = pct >= 80
        ? Colors.green
        : pct >= 50
            ? Colors.orange
            : Colors.red;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        side: BorderSide(color: statusColor.shade200, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 10 : context.accR.paddingH,
            vertical: context.accR.spaceM),
        child: isMobile
            ? Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(Icons.verified,
                      size: context.accR.iconM, color: statusColor.shade700),
                  Text('المطابقة مع FTTH: ',
                      style: GoogleFonts.cairo(
                          fontSize: context.accR.small,
                          fontWeight: FontWeight.w600)),
                  Text('$reconciled / $total',
                      style: TextStyle(
                          fontSize: context.accR.financialSmall,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade700)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${pct.toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: context.accR.small,
                            fontWeight: FontWeight.bold,
                            color: statusColor.shade800)),
                  ),
                  if (unreconciled > 0)
                    Text('($unreconciled غير مطابقة)',
                        style: TextStyle(
                            fontSize: context.accR.small,
                            color: Colors.red.shade400)),
                ],
              )
            : Row(
                children: [
                  Icon(Icons.verified,
                      size: context.accR.iconM, color: statusColor.shade700),
                  SizedBox(width: context.accR.spaceS),
                  Text('المطابقة مع FTTH: ',
                      style: GoogleFonts.cairo(
                          fontSize: context.accR.small,
                          fontWeight: FontWeight.w600)),
                  Text('$reconciled / $total',
                      style: TextStyle(
                          fontSize: context.accR.financialSmall,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade700)),
                  SizedBox(width: context.accR.spaceS),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${pct.toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: context.accR.small,
                            fontWeight: FontWeight.bold,
                            color: statusColor.shade800)),
                  ),
                  if (unreconciled > 0) ...[
                    SizedBox(width: context.accR.spaceM),
                    Text('($unreconciled غير مطابقة)',
                        style: TextStyle(
                            fontSize: context.accR.small,
                            color: Colors.red.shade400)),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildOursTable() {
    if (_oursOperators.isEmpty) {
      return _emptyCard('لا يوجد مشغلون');
    }

    // إظهار تحذير إذا كانت هناك سجلات بدون userId أو collectionType
    final hasUnknownOperators = _oursOperators.any((op) =>
        op['operatorName'] == 'غير معروف' || op['userId'] == null);
    final hasUnclassified = _oursOperators.any((op) =>
        (op['unclassifiedAmount'] ?? 0) > 0);

    return Column(
      children: [
        Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        side: const BorderSide(color: Colors.black, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: context.accR.spaceL, vertical: context.accR.spaceM),
            child: Row(
              children: [
                // تبويب: المشغلون
                _TabButton(
                  label: 'المشغلون (${_oursOperators.where((o) => o['isTechnician'] != true).length})',
                  selected: _oursTabIndex == 0,
                  icon: Icons.people,
                  onTap: () => setState(() => _oursTabIndex = 0),
                ),
                SizedBox(width: context.accR.spaceXS),
                // تبويب: الفنيون
                _TabButton(
                  label: 'الفنيون (${_oursOperators.where((o) => o['isTechnician'] == true).length})',
                  selected: _oursTabIndex == 1,
                  icon: Icons.engineering,
                  color: Colors.teal,
                  onTap: () => setState(() => _oursTabIndex = 1),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 180,
                  height: 34,
                  child: TextField(
                    controller: _oursSearchController,
                    onChanged: (v) => setState(() => _oursSearchQuery = v.trim().toLowerCase()),
                    style: GoogleFonts.cairo(fontSize: 12),
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      hintText: _oursTabIndex == 0 ? 'بحث عن مشغل...' : 'بحث عن فني...',
                      hintStyle: GoogleFonts.cairo(fontSize: 12, color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, size: 16, color: Colors.grey),
                      suffixIcon: _oursSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 14),
                              onPressed: () {
                                _oursSearchController.clear();
                                setState(() => _oursSearchQuery = '');
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.black, width: 1.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.black, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.blue, width: 2),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _AllOperationsPage(
                          companyId: _companyId,
                          fromDate: _fromDate,
                          toDate: _toDate,
                          operators: _ftthOperators.keys
                              .where((k) => k.isNotEmpty)
                              .toList()
                            ..sort()),
                    ),
                  ),
                  icon: const Icon(Icons.table_rows, size: 14),
                  label: Text('كل العمليات', style: GoogleFonts.cairo()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                        horizontal: context.accR.spaceM,
                        vertical: context.accR.spaceXS),
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                  ),
                  child: DataTable(
                    border: TableBorder.all(color: Colors.black, width: 1.5),
                    dividerThickness: 0,
                    headingRowColor:
                        WidgetStateProperty.all(Colors.grey.shade100),
                    dataRowMinHeight: 28,
                    dataRowMaxHeight: 44,
                    headingRowHeight: 32,
                    columnSpacing: 0,
                    horizontalMargin: 8,
                    headingTextStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: context.accR.small,
                        color: Colors.black87),
                    columns: [
                      const DataColumn(label: Expanded(child: Center(child: Text('#')))),
                      DataColumn(label: _sortableHeader('المشغل', 'operatorName')),
                      DataColumn(label: _sortableHeader('العمليات', 'totalCount')),
                      DataColumn(label: _sortableHeader('المستقطع', 'pageDeduction', color: Colors.indigo.shade800)),
                      DataColumn(label: _sortableHeader('الإيرادات', 'revenue', color: Colors.green.shade800)),
                      DataColumn(label: _sortableHeader('المصاريف', 'expense', color: Colors.red.shade800)),
                      DataColumn(label: _sortableHeader('الإجمالي', 'totalAmount', color: Colors.blue.shade800)),
                      DataColumn(label: _sortableHeader('شراء', 'purchaseCount')),
                      DataColumn(label: _sortableHeader('تجديد', 'renewalCount')),
                      DataColumn(label: _sortableHeader('تغيير', 'changeCount')),
                      DataColumn(label: _sortableHeader('نقد', 'cashAmount')),
                      DataColumn(label: _sortableHeader('آجل', 'creditAmount')),
                      DataColumn(label: _sortableHeader('ماستر', 'masterAmount')),
                      DataColumn(label: _sortableHeader('وكيل', 'agentAmount')),
                      DataColumn(label: _sortableHeader('فني', 'technicianAmount')),
                      DataColumn(label: _sortableHeader('المسلّم', 'deliveredCash')),
                      DataColumn(label: _sortableHeader('المستحق', 'netOwed')),
                      if (_oursTabIndex == 0)
                        DataColumn(label: _sortableHeader('ذمم فني', 'techDebt', color: Colors.deepOrange)),
                      const DataColumn(label: Expanded(child: Center(child: Text('مطابقة')))),
                      DataColumn(label: Expanded(child: Center(child: Text('إجراءات')))),
                    ],
                    rows: (() {
                      var filtered = _oursTabIndex == 0
                          ? _oursOperators.where((o) => o['isTechnician'] != true).toList()
                          : _oursOperators.where((o) => o['isTechnician'] == true).toList();
                      if (_oursSearchQuery.isNotEmpty) {
                        filtered = filtered.where((o) {
                          final name = (o['operatorName'] ?? '').toString().toLowerCase();
                          final username = (o['username'] ?? '').toString().toLowerCase();
                          final ftthUser = (o['ftthUsername'] ?? '').toString().toLowerCase();
                          return name.contains(_oursSearchQuery) || username.contains(_oursSearchQuery) || ftthUser.contains(_oursSearchQuery);
                        }).toList();
                      }
                      filtered = _sortOperators(filtered);
                      return filtered.asMap().entries.map((entry) {
                      final i = entry.key;
                      final op = entry.value as Map<String, dynamic>;
                      final netOwed = (op['netOwed'] ?? 0).toDouble();
                      final reconciledCnt = (op['reconciledCount'] ?? 0);
                      final totalCnt = (op['totalCount'] ?? 0);
                      final purchaseCnt = (op['purchaseCount'] ?? 0);
                      final renewalCnt = (op['renewalCount'] ?? 0);
                      final changeCnt = (op['changeCount'] ?? 0);
                      final isTech = op['isTechnician'] == true;

                      return DataRow(
                        color: isTech
                            ? WidgetStateProperty.all(Colors.teal.withOpacity(0.07))
                            : null,
                        cells: [
                        DataCell(Center(
                            child: Text('${i + 1}',
                                style: TextStyle(
                                    fontSize: context.accR.small,
                                    fontWeight: FontWeight.w600)))),
                        DataCell(
                            Center(
                                child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isTech) ...[
                                      Icon(Icons.engineering, size: 13, color: Colors.teal),
                                      SizedBox(width: 3),
                                    ],
                                    Text(op['operatorName'] ?? '-',
                                        style: TextStyle(
                                            fontSize: context.accR.small,
                                            fontWeight: FontWeight.w700,
                                            color: isTech ? Colors.teal.shade700 : null,
                                            decoration: TextDecoration.underline,
                                            decorationColor: isTech ? Colors.teal.shade300 : Colors.grey.shade400)),
                                  ],
                                ),
                                if (!isTech && op['ftthUsername'] != null)
                                  Text(op['ftthUsername'],
                                      style: TextStyle(
                                          fontSize: context.accR.caption,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey.shade600)),
                                if (isTech)
                                  Text('فني',
                                      style: TextStyle(
                                          fontSize: context.accR.caption,
                                          color: Colors.teal.shade400)),
                              ],
                            )),
                            onTap: () => _openAccountStatement(op)),
                        DataCell(Center(
                            child: Text('$totalCnt',
                                style: TextStyle(
                                    fontSize: context.accR.small,
                                    fontWeight: FontWeight.w600)))),
                        // المستقطع من الصفحة
                        DataCell(Center(child: Text(
                          _currencyFormat.format((op['pageDeduction'] ?? 0).toDouble()),
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w700),
                        ))),
                        // الإيرادات
                        DataCell(Center(child: Text(
                          _currencyFormat.format((op['revenue'] ?? 0).toDouble()),
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w600,
                              color: (op['revenue'] ?? 0).toDouble() > 0 ? Colors.green.shade700 : Colors.grey.shade400),
                        ))),
                        // المصاريف
                        DataCell(Center(child: Text(
                          _currencyFormat.format((op['expense'] ?? 0).toDouble()),
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w600,
                              color: (op['expense'] ?? 0).toDouble() > 0 ? Colors.red.shade700 : Colors.grey.shade400),
                        ))),
                        // الإجمالي
                        DataCell(Center(child: Text(
                          _currencyFormat.format((op['totalAmount'] ?? 0).toDouble()),
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w700,
                              color: AccountingTheme.neonBlue),
                        ))),
                        // شراء
                        DataCell(Center(
                            child: Text(
                          '$purchaseCnt',
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w600,
                              color: purchaseCnt > 0
                                  ? Colors.green.shade700
                                  : Colors.grey.shade400),
                        ))),
                        // تجديد
                        DataCell(Center(
                            child: Text(
                          '$renewalCnt',
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w600,
                              color: renewalCnt > 0
                                  ? Colors.blue.shade700
                                  : Colors.grey.shade400),
                        ))),
                        // تغيير
                        DataCell(Center(
                            child: Text(
                          '$changeCnt',
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w600,
                              color: changeCnt > 0
                                  ? Colors.orange.shade700
                                  : Colors.grey.shade400),
                        ))),
                        // نقد
                        DataCell(Center(
                            child: Text(
                          _currencyFormat
                              .format((op['cashAmount'] ?? 0).toDouble()),
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700),
                        ))),
                        // آجل
                        DataCell(Center(
                            child: Text(
                          _currencyFormat
                              .format((op['creditAmount'] ?? 0).toDouble()),
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade700),
                        ))),
                        // ماستر
                        DataCell(Center(
                            child: Text(
                          _currencyFormat
                              .format((op['masterAmount'] ?? 0).toDouble()),
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w600,
                              color: Colors.purple.shade700),
                        ))),
                        // وكيل
                        DataCell(Center(
                            child: Text(
                          _currencyFormat
                              .format((op['agentAmount'] ?? 0).toDouble()),
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700),
                        ))),
                        // فني
                        DataCell(Center(
                            child: Text(
                          _currencyFormat
                              .format((op['technicianAmount'] ?? 0).toDouble()),
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w600,
                              color: Colors.teal.shade700),
                        ))),
                        // المسلّم
                        DataCell(Center(
                            child: Text(
                          _currencyFormat.format(
                              ((op['deliveredCash'] ?? 0).toDouble()) +
                                  ((op['collectedCredit'] ?? 0).toDouble())),
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700),
                        ))),
                        // المستحق
                        DataCell(Center(
                            child: Text(
                          _currencyFormat.format(netOwed),
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.bold,
                              color: netOwed > 0
                                  ? Colors.red.shade700
                                  : Colors.green.shade700),
                        ))),
                        // ذمم فني (فقط في تبويب المشغلون)
                        if (_oursTabIndex == 0)
                          DataCell(Center(
                              child: () {
                            final techDebt = (op['techDebt'] ?? 0).toDouble();
                            if (techDebt == 0) {
                              return Text('-', style: TextStyle(fontSize: context.accR.small, color: Colors.grey));
                            }
                            return Text(
                              _currencyFormat.format(techDebt),
                              style: TextStyle(
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.bold,
                                  color: techDebt > 0 ? Colors.deepOrange : Colors.green.shade700),
                            );
                          }())),
                        // مطابقة
                        DataCell(Center(
                            child: Text(
                          '$reconciledCnt/$totalCnt',
                          style: TextStyle(
                              fontSize: context.accR.caption,
                              fontWeight: FontWeight.w600,
                              color: reconciledCnt == totalCnt && totalCnt > 0
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700),
                        ))),
                        DataCell(Center(
                            child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                              icon: Icon(Icons.open_in_new,
                                  size: context.accR.iconS,
                                  color: AccountingTheme.neonBlue),
                              onPressed: () => _openOperatorAccount(op),
                              tooltip: 'كشف الحساب',
                            ),
                            if (op['userId'] != null) ...[
                              SizedBox(width: context.accR.spaceXS),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                                icon: Icon(Icons.payments,
                                    size: context.accR.iconS,
                                    color: Colors.green.shade700),
                                onPressed: () => op['isTechnician'] == true
                                    ? _showTechnicianPaymentDialog(op)
                                    : _showQuickDeliverDialog(op),
                                tooltip: op['isTechnician'] == true ? 'تسديد فني' : 'تسليم نقد',
                              ),
                              if (op['isTechnician'] != true) ...[
                                SizedBox(width: context.accR.spaceXS),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(),
                                  icon: Icon(Icons.request_quote,
                                      size: context.accR.iconS,
                                      color: Colors.orange.shade700),
                                  onPressed: () => _showQuickCollectDialog(op),
                                  tooltip: 'تحصيل آجل',
                                ),
                              ],
                            ],
                          ],
                        ))),
                      ]);
                    }).toList()
                    ..add(DataRow(
                      color: WidgetStateProperty.all(Colors.grey.shade200),
                      cells: [
                        DataCell(Center(child: Text('', style: TextStyle(fontSize: context.accR.small)))),
                        DataCell(Center(child: Text('المجموع', style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w900)))),
                        DataCell(Center(child: Text('${filtered.fold<int>(0, (s, o) => s + ((o['totalCount'] ?? 0) as int))}', style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w900)))),
                        DataCell(Center(child: Text(_currencyFormat.format(filtered.fold<double>(0, (s, o) => s + ((o['pageDeduction'] ?? 0) as num).toDouble())), style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w900, color: Colors.indigo.shade800)))),
                        DataCell(Center(child: Text(_currencyFormat.format(filtered.fold<double>(0, (s, o) => s + ((o['revenue'] ?? 0) as num).toDouble())), style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w900, color: Colors.green.shade800)))),
                        DataCell(Center(child: Text(_currencyFormat.format(filtered.fold<double>(0, (s, o) => s + ((o['expense'] ?? 0) as num).toDouble())), style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w900, color: Colors.red.shade800)))),
                        DataCell(Center(child: Text(_currencyFormat.format(filtered.fold<double>(0, (s, o) => s + ((o['totalAmount'] ?? 0) as num).toDouble())), style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w900, color: Colors.blue.shade800)))),
                        DataCell(Center(child: Text('${filtered.fold<int>(0, (s, o) => s + ((o['purchaseCount'] ?? 0) as int))}', style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w700)))),
                        DataCell(Center(child: Text('${filtered.fold<int>(0, (s, o) => s + ((o['renewalCount'] ?? 0) as int))}', style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w700)))),
                        DataCell(Center(child: Text('${filtered.fold<int>(0, (s, o) => s + ((o['changeCount'] ?? 0) as int))}', style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w700)))),
                        DataCell(Center(child: Text(_currencyFormat.format(filtered.fold<double>(0, (s, o) => s + ((o['cashAmount'] ?? 0) as num).toDouble())), style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w700)))),
                        DataCell(Center(child: Text(_currencyFormat.format(filtered.fold<double>(0, (s, o) => s + ((o['creditAmount'] ?? 0) as num).toDouble())), style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w700)))),
                        DataCell(Center(child: Text(_currencyFormat.format(filtered.fold<double>(0, (s, o) => s + ((o['masterAmount'] ?? 0) as num).toDouble())), style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w700)))),
                        DataCell(Center(child: Text(_currencyFormat.format(filtered.fold<double>(0, (s, o) => s + ((o['agentAmount'] ?? 0) as num).toDouble())), style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w700)))),
                        DataCell(Center(child: Text(_currencyFormat.format(filtered.fold<double>(0, (s, o) => s + ((o['technicianAmount'] ?? 0) as num).toDouble())), style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w700)))),
                        DataCell(Center(child: Text(_currencyFormat.format(filtered.fold<double>(0, (s, o) => s + ((o['deliveredCash'] ?? 0) as num).toDouble())), style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w700)))),
                        DataCell(Center(child: Text(_currencyFormat.format(filtered.fold<double>(0, (s, o) => s + ((o['netOwed'] ?? 0) as num).toDouble())), style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w900, color: Colors.red.shade700)))),
                        if (_oursTabIndex == 0)
                          DataCell(Center(child: Text(_currencyFormat.format(filtered.fold<double>(0, (s, o) => s + ((o['techDebt'] ?? 0) as num).toDouble())), style: TextStyle(fontSize: context.accR.small, fontWeight: FontWeight.w900, color: Colors.deepOrange)))),
                        DataCell(Center(child: Text('', style: TextStyle(fontSize: context.accR.small)))),
                        DataCell(Center(child: Text(''))),
                      ],
                    ));
                    })(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
        ),
      ],
    );
  }

  /// ═══ التوزيعات (مناطق، باقات، فنيين، يومي) ═══
  Widget _buildOursDistributions() {
    if (_oursDistributions == null) return const SizedBox();
    final isMobile = context.accR.isMobile;

    final zones = (_oursDistributions!['zones'] as List?) ?? [];
    final plans = (_oursDistributions!['plans'] as List?) ?? [];
    final technicians = (_oursDistributions!['technicians'] as List?) ?? [];
    final daily = (_oursDistributions!['daily'] as List?) ?? [];
    final opTypes = (_oursDistributions!['operationTypes'] as List?) ?? [];

    final opTypesTable = opTypes.isNotEmpty
        ? _buildDistTable('أنواع العمليات', Icons.category, Colors.teal,
            columns: ['النوع', 'العدد', 'المبلغ'],
            rows: opTypes.map((e) {
              final m = e as Map<String, dynamic>;
              return [
                m['type']?.toString() ?? '-',
                '${m['count'] ?? 0}',
                _currencyFormat.format((m['amount'] ?? 0).toDouble()),
              ];
            }).toList())
        : null;

    final dailyTable = daily.isNotEmpty
        ? _buildDistTable('التوزيع اليومي', Icons.calendar_today, Colors.indigo,
            columns: ['التاريخ', 'العدد', 'المبلغ'],
            rows: daily.map((e) {
              final m = e as Map<String, dynamic>;
              return [
                m['date']?.toString() ?? '-',
                '${m['count'] ?? 0}',
                _currencyFormat.format((m['amount'] ?? 0).toDouble()),
              ];
            }).toList())
        : null;

    final zonesTable = zones.isNotEmpty
        ? _buildDistTable('توزيع المناطق', Icons.location_on, Colors.deepOrange,
            columns: ['المنطقة', 'العدد', 'المبلغ'],
            rows: zones.map((e) {
              final m = e as Map<String, dynamic>;
              return [
                m['zone']?.toString() ?? '-',
                '${m['count'] ?? 0}',
                _currencyFormat.format((m['amount'] ?? 0).toDouble()),
              ];
            }).toList())
        : null;

    final plansTable = plans.isNotEmpty
        ? _buildDistTable('توزيع الباقات', Icons.wifi, Colors.blue,
            columns: ['الباقة', 'العدد', 'المبلغ'],
            rows: plans.map((e) {
              final m = e as Map<String, dynamic>;
              return [
                m['plan']?.toString() ?? '-',
                '${m['count'] ?? 0}',
                _currencyFormat.format((m['amount'] ?? 0).toDouble()),
              ];
            }).toList())
        : null;

    final techTable = technicians.isNotEmpty
        ? _buildDistTable('توزيع الفنيين', Icons.engineering, Colors.brown,
            columns: ['الفني', 'العدد', 'المبلغ'],
            rows: technicians.map((e) {
              final m = e as Map<String, dynamic>;
              return [
                m['technician']?.toString() ?? '-',
                '${m['count'] ?? 0}',
                _currencyFormat.format((m['amount'] ?? 0).toDouble()),
              ];
            }).toList())
        : null;

    if (isMobile) {
      // Mobile: stack all tables vertically
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (opTypesTable != null) opTypesTable,
          if (opTypesTable != null) SizedBox(height: context.accR.spaceM),
          if (dailyTable != null) dailyTable,
          if (dailyTable != null) SizedBox(height: context.accR.spaceM),
          if (zonesTable != null) zonesTable,
          if (zonesTable != null) SizedBox(height: context.accR.spaceM),
          if (plansTable != null) plansTable,
          if (plansTable != null) SizedBox(height: context.accR.spaceM),
          if (techTable != null) techTable,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ═══ صف 1: أنواع العمليات + التوزيع اليومي ═══
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (opTypesTable != null) Expanded(child: opTypesTable),
            if (opTypesTable != null && dailyTable != null)
              SizedBox(width: context.accR.spaceM),
            if (dailyTable != null) Expanded(child: dailyTable),
          ],
        ),
        SizedBox(height: context.accR.spaceM),
        // ═══ صف 2: المناطق + الباقات ═══
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (zonesTable != null) Expanded(child: zonesTable),
            if (zonesTable != null && plansTable != null)
              SizedBox(width: context.accR.spaceM),
            if (plansTable != null) Expanded(child: plansTable),
          ],
        ),
        SizedBox(height: context.accR.spaceM),
        // ═══ صف 3: الفنيين ═══
        if (techTable != null) techTable,
      ],
    );
  }

  /// جدول توزيع عام قابل لإعادة الاستخدام
  Widget _buildDistTable(String title, IconData icon, Color color,
      {required List<String> columns, required List<List<String>> rows}) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        side: BorderSide(color: Colors.black, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Icon(icon, size: context.accR.iconS, color: color),
                SizedBox(width: context.accR.spaceXS),
                Text('$title (${rows.length})',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.small,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: 400),
                child: DataTable(
                  border: TableBorder.all(color: Colors.black, width: 1.5),
                  dividerThickness: 0,
                  headingRowColor:
                      WidgetStateProperty.all(color.withOpacity(0.06)),
                  dataRowMinHeight: 26,
                  dataRowMaxHeight: 32,
                  headingRowHeight: 30,
                  columnSpacing: 0,
                  horizontalMargin: 10,
                  headingTextStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: context.accR.small,
                      color: color),
                  columns: columns
                      .map((c) => DataColumn(
                          label: Expanded(child: Center(child: Text(c)))))
                      .toList(),
                  rows: rows.asMap().entries.map((entry) {
                    final row = entry.value;
                    return DataRow(
                      cells: row
                          .map((cell) => DataCell(Center(
                                child: Text(cell,
                                    style:
                                        TextStyle(fontSize: context.accR.small),
                                    overflow: TextOverflow.ellipsis),
                              )))
                          .toList(),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sortableHeader(String label, String key, {Color? color}) {
    final isActive = _oursSortKey == key;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          if (_oursSortKey == key) {
            _oursSortAsc = !_oursSortAsc;
          } else {
            _oursSortKey = key;
            _oursSortAsc = key == 'operatorName'; // الاسم تصاعدي افتراضياً، الأرقام تنازلي
          }
        }),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: isActive ? FontWeight.w900 : FontWeight.bold,
                        color: color ?? (isActive ? Colors.blue.shade800 : Colors.black87))),
              ),
              if (isActive)
                Icon(_oursSortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 12, color: color ?? Colors.blue.shade800),
            ],
          ),
        ),
      ),
    );
  }

  List<dynamic> _sortOperators(List<dynamic> list) {
    final sorted = List<dynamic>.from(list);
    sorted.sort((a, b) {
      final av = a[_oursSortKey];
      final bv = b[_oursSortKey];
      int cmp;
      if (av is String && bv is String) {
        cmp = av.compareTo(bv);
      } else {
        cmp = ((av as num?)?.toDouble() ?? 0).compareTo((bv as num?)?.toDouble() ?? 0);
      }
      return _oursSortAsc ? cmp : -cmp;
    });
    return sorted;
  }

  /// فتح كشف حساب الصندوق (للمشغل) أو الذمم (للفني)
  void _openAccountStatement(Map<String, dynamic> op) {
    final userId = op['userId']?.toString();
    if (userId == null || userId.isEmpty) return;
    final isTech = op['isTechnician'] == true;

    // البحث عن accountId المناسب من الحسابات المحملة
    // المشغل → صندوق (1110xx)، الفني → ذمة (1140xx)
    final prefix = isTech ? '1140' : '1110';
    AccountingService.instance.getAccounts(companyId: _companyId).then((result) {
      if (result['success'] != true || !mounted) return;
      final accounts = (result['data'] as List?) ?? [];
      final match = accounts.where((a) =>
          (a['Code']?.toString() ?? '').startsWith(prefix) &&
          a['Description']?.toString() == userId &&
          a['IsLeaf'] == true).firstOrNull;
      if (match != null) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ClientAccountsPage(
            companyId: _companyId,
            initialAccountId: match['Id']?.toString(),
          ),
        ));
      } else {
        // إذا لم يُوجد حساب، افتح صفحة عمليات المشغل
        _openOperatorAccount(op);
      }
    });
  }

  void _openOperatorAccount(Map<String, dynamic> op) {
    final userId = op['userId']?.toString();
    if (userId == null || userId.isEmpty) {
      _showUnassignedLogsInfo(op);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FtthOperatorAccountPage(
          userId: userId,
          operatorName: op['operatorName'] ?? 'مشغل',
          companyId: _companyId,
          initialFromDate: _fromDate,
          initialToDate: _toDate,
          initialDateLabel: _dateLabel,
          isTechnician: op['isTechnician'] == true,
        ),
      ),
    );
  }

  void _showUnassignedLogsInfo(Map<String, dynamic> op) {
    final total = op['totalCount'] ?? 0;
    final amount = op['totalAmount'] ?? 0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سجلات بدون مشغل محدد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('عدد العمليات: $total'),
            Text('الإجمالي: $amount د.ع'),
            const SizedBox(height: 12),
            const Text(
              'هذه السجلات ناتجة عن مزامنة FTTH ولم يُعرَّف مشغلها لأن نظام FTTH لم يُرسل اسم المنشئ.\n\n'
              'لتصحيحها: اذهب إلى تبويب FTTH وأعد الضغط على "مزامنة FTTH → خادمنا".',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  تسليم نقد سريع / تحصيل آجل سريع
  // ════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════
  //  استلام نقد من مشغل (حوار مركزي)
  // ════════════════════════════════════════════════════════════════

  Future<void> _showReceiveCashDialog() async {
    // جمع المشغلين الذين لديهم userId ورصيد نقد
    final operators = _oursOperators
        .where(
            (op) => op['userId'] != null && op['userId'].toString().isNotEmpty)
        .toList();

    if (operators.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يوجد مشغلون بصناديق نقد'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    Map<String, dynamic>? selectedOp;
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    bool isSubmitting = false;
    String? errorMsg;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(context.accR.radiusL)),
            title: Row(
              children: [
                Icon(Icons.move_to_inbox, color: Colors.green.shade700),
                SizedBox(width: context.accR.spaceS),
                Text('استلام نقد من مشغل',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.headingSmall,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            content: SizedBox(
              width: context.accR.isMobile
                  ? MediaQuery.of(context).size.width * 0.92
                  : 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // معلومة توضيحية
                  Container(
                    padding: EdgeInsets.all(context.accR.spaceM),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: context.accR.iconS,
                            color: Colors.blue.shade700),
                        SizedBox(width: context.accR.spaceS),
                        Expanded(
                          child: Text(
                            'تحويل النقد من صندوق المشغل إلى الصندوق الرئيسي',
                            style: TextStyle(
                                fontSize: context.accR.small,
                                color: Colors.blue.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: context.accR.spaceL),
                  // اختيار المشغل
                  Text('اختر المشغل:',
                      style: GoogleFonts.cairo(
                          fontSize: context.accR.financialSmall,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: context.accR.spaceXS),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: BoxConstraints(maxHeight: 200),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: operators.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: Colors.grey.shade200),
                      itemBuilder: (_, i) {
                        final op = operators[i] as Map<String, dynamic>;
                        final cashAmt = (op['cashAmount'] ?? 0).toDouble();
                        final isSelected = selectedOp != null &&
                            selectedOp!['userId'] == op['userId'];
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor: Colors.green.shade50,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: isSelected
                                ? Colors.green.shade700
                                : Colors.grey.shade300,
                            child: Text('${i + 1}',
                                style: TextStyle(
                                    fontSize: context.accR.small,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black54,
                                    fontWeight: FontWeight.w700)),
                          ),
                          title: Text(op['operatorName'] ?? '-',
                              style: GoogleFonts.cairo(
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.w600)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: cashAmt > 0
                                  ? Colors.green.shade50
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(
                                  context.accR.cardRadius),
                              border: Border.all(
                                  color: cashAmt > 0
                                      ? Colors.green.shade300
                                      : Colors.grey.shade300),
                            ),
                            child: Text(
                              _currencyFormat.format(cashAmt),
                              style: GoogleFonts.cairo(
                                fontSize: context.accR.small,
                                fontWeight: FontWeight.w700,
                                color: cashAmt > 0
                                    ? Colors.green.shade700
                                    : Colors.grey,
                              ),
                            ),
                          ),
                          onTap: () {
                            setDlgState(() {
                              selectedOp = op;
                              // تعبئة المبلغ الكامل تلقائياً
                              amountController.text =
                                  cashAmt > 0 ? cashAmt.toStringAsFixed(0) : '';
                              errorMsg = null;
                            });
                          },
                        );
                      },
                    ),
                  ),
                  if (selectedOp != null) ...[
                    SizedBox(height: context.accR.spaceL),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: 'المبلغ',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.attach_money),
                        ),
                      ),
                    ),
                    SizedBox(height: context.accR.spaceS),
                    TextField(
                      controller: notesController,
                      decoration: InputDecoration(
                        labelText: 'ملاحظات (اختياري)',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.note),
                      ),
                    ),
                  ],
                  if (errorMsg != null) ...[
                    SizedBox(height: context.accR.spaceM),
                    Container(
                      padding: EdgeInsets.all(context.accR.spaceS),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(errorMsg!,
                          style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: context.accR.small)),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    isSubmitting ? null : () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                onPressed: isSubmitting || selectedOp == null
                    ? null
                    : () async {
                        final amount = double.tryParse(amountController.text);
                        if (amount == null || amount <= 0) {
                          setDlgState(() => errorMsg = 'أدخل مبلغاً صحيحاً');
                          return;
                        }
                        setDlgState(() {
                          isSubmitting = true;
                          errorMsg = null;
                        });
                        try {
                          final res =
                              await AccountingService.instance.quickDeliver(
                            operatorUserId: selectedOp!['userId'].toString(),
                            amount: amount,
                            companyId: _companyId,
                            notes: notesController.text.isEmpty
                                ? null
                                : notesController.text,
                          );
                          if (ctx.mounted) {
                            if (res['success'] == true) {
                              Navigator.pop(ctx, true);
                            } else {
                              setDlgState(() {
                                isSubmitting = false;
                                errorMsg = res['message'] ?? 'فشلت العملية';
                              });
                            }
                          }
                        } catch (e) {
                          setDlgState(() {
                            isSubmitting = false;
                            errorMsg = 'خطأ';
                          });
                        }
                      },
                icon: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(Icons.check, size: context.accR.iconM),
                label: Text(isSubmitting ? 'جاري...' : 'استلام'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'تم استلام النقد من ${selectedOp?['operatorName'] ?? 'المشغل'} بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
      _loadOursData();
    }
  }

  Future<void> _showQuickDeliverDialog(Map<String, dynamic> op) async {
    final userId = op['userId']?.toString();
    if (userId == null || userId.isEmpty) return;
    final name = op['operatorName'] ?? 'مشغل';
    final cashAmount = (op['cashAmount'] ?? 0).toDouble();
    final amountController = TextEditingController();
    final notesController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.payments, color: Colors.green.shade700),
            SizedBox(width: context.accR.spaceS),
            Expanded(
              child: Text('تسليم نقد — $name',
                  style: GoogleFonts.cairo(
                      fontSize: context.accR.body,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: SizedBox(
          width: context.accR.isMobile
              ? MediaQuery.of(context).size.width * 0.9
              : 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('رصيد النقد الحالي: ${_currencyFormat.format(cashAmount)}',
                  style: GoogleFonts.cairo(
                      fontSize: context.accR.financialSmall,
                      color: Colors.grey.shade700)),
              SizedBox(height: context.accR.spaceM),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'المبلغ',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
              ),
              SizedBox(height: context.accR.spaceS),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: Icon(Icons.check, size: context.accR.iconM),
            label: const Text('تسليم'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
          ),
        ],
      ),
    );

    if (result != true) return;
    final amount = double.tryParse(amountController.text);
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('أدخل مبلغاً صحيحاً'),
              backgroundColor: Colors.orange),
        );
      }
      return;
    }

    try {
      final res = await AccountingService.instance.quickDeliver(
        operatorUserId: userId,
        amount: amount,
        companyId: _companyId,
        notes: notesController.text.isEmpty ? null : notesController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['success'] == true
                ? 'تم تسليم ${_currencyFormat.format(amount)} بنجاح'
                : res['message'] ?? 'خطأ'),
            backgroundColor: res['success'] == true ? Colors.green : Colors.red,
          ),
        );
        if (res['success'] == true) _loadOursData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showTechnicianPaymentDialog(Map<String, dynamic> op) async {
    final userId = op['userId']?.toString();
    if (userId == null || userId.isEmpty) return;
    final name = op['operatorName'] ?? 'فني';
    final totalAmount = (op['totalAmount'] ?? 0).toDouble();
    final delivered = (op['deliveredCash'] ?? 0).toDouble();
    final remaining = totalAmount - delivered;
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    DateTime selectedDate = _fromDate ?? DateTime.now();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.payments, color: Colors.green.shade700),
              SizedBox(width: context.accR.spaceS),
              Expanded(
                child: Text('تسديد فني — $name',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.body,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          content: SizedBox(
            width: context.accR.isMobile
                ? MediaQuery.of(context).size.width * 0.9
                : 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المستحق: ${_currencyFormat.format(remaining)}',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.financialSmall,
                        color: Colors.grey.shade700)),
                SizedBox(height: context.accR.spaceM),
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  onChanged: (v) {
                    final raw = v.replaceAll(',', '');
                    final num = int.tryParse(raw);
                    if (num != null) {
                      final formatted = _currencyFormat.format(num);
                      if (formatted != v) {
                        amountController.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(offset: formatted.length),
                        );
                      }
                    }
                  },
                ),
                SizedBox(height: context.accR.spaceS),
                // حقل التاريخ
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                      locale: const Locale('ar'),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: Colors.blue, size: 18),
                        const SizedBox(width: 8),
                        Text('التاريخ: ${selectedDate.year}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.day.toString().padLeft(2, '0')}'),
                        const Spacer(),
                        Icon(Icons.edit, color: Colors.grey, size: 16),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: context.accR.spaceS),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, {'confirmed': true, 'date': selectedDate}),
              icon: Icon(Icons.check, size: context.accR.iconM),
              label: const Text('تسديد'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );

    if (result == null || result['confirmed'] != true) return;
    final pickedDate = result['date'] as DateTime;
    final amount = double.tryParse(amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('أدخل مبلغاً صحيحاً'),
              backgroundColor: Colors.orange),
        );
      }
      return;
    }

    try {
      final res = await AccountingService.instance.recordTechnicianPayment(
        technicianId: userId,
        amount: amount,
        description: 'تسديد نقدي',
        notes: notesController.text.isEmpty ? null : notesController.text,
        transactionDate: pickedDate,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['success'] == true
                ? 'تم تسديد ${_currencyFormat.format(amount)} بنجاح'
                : res['message'] ?? 'خطأ'),
            backgroundColor: res['success'] == true ? Colors.green : Colors.red,
          ),
        );
        if (res['success'] == true) _loadOursData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showQuickCollectDialog(Map<String, dynamic> op) async {
    final userId = op['userId']?.toString();
    if (userId == null || userId.isEmpty) return;
    final name = op['operatorName'] ?? 'مشغل';
    final creditAmount = (op['creditAmount'] ?? 0).toDouble();
    final amountController = TextEditingController();
    final notesController = TextEditingController();

    // جلب عملاء الآجل غير المسددين
    List<Map<String, dynamic>> creditCustomers = [];
    Set<int> selectedLogIds = {};
    bool isLoadingCustomers = true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          // جلب البيانات عند أول بناء
          if (isLoadingCustomers) {
            AccountingService.instance
                .getCreditCustomers(
                    operatorUserId: userId, companyId: _companyId)
                .then((res) {
              if (res['success'] == true) {
                final rawData = res['data'];
                final List dataList = rawData is List
                    ? rawData
                    : (rawData is Map
                        ? (rawData['data'] ?? rawData['customers'] ?? [])
                        : []);
                final list = dataList
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                setDlgState(() {
                  creditCustomers = list;
                  isLoadingCustomers = false;
                });
              } else {
                setDlgState(() => isLoadingCustomers = false);
              }
            }).catchError((_) {
              setDlgState(() => isLoadingCustomers = false);
            });
            isLoadingCustomers = false; // لمنع الجلب المتكرر
          }

          // حساب المجموع المحدد
          double selectedTotal = 0;
          String selectedNames = '';
          if (selectedLogIds.isNotEmpty) {
            for (final c in creditCustomers) {
              if (selectedLogIds.contains((c['Id'] as num).toInt())) {
                selectedTotal += (c['Amount'] as num? ?? 0).toDouble();
              }
            }
            final names = creditCustomers
                .where((c) => selectedLogIds.contains((c['Id'] as num).toInt()))
                .map((c) => c['CustomerName']?.toString() ?? '-')
                .toSet()
                .toList();
            selectedNames = names.join('، ');
          }

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(context.accR.radiusL)),
              title: Row(
                children: [
                  Icon(Icons.request_quote, color: Colors.orange.shade700),
                  SizedBox(width: context.accR.spaceS),
                  Expanded(
                    child: Text('تحصيل آجل — $name',
                        style: GoogleFonts.cairo(
                            fontSize: context.accR.body,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              content: SizedBox(
                width: context.accR.dialogMediumW,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // معلومة الرصيد
                    Container(
                      padding: EdgeInsets.all(context.accR.spaceM),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: context.accR.iconS,
                              color: Colors.orange.shade700),
                          SizedBox(width: context.accR.spaceS),
                          Expanded(
                            child: Text(
                              'رصيد الآجل الحالي: ${_currencyFormat.format(creditAmount)}',
                              style: TextStyle(
                                  fontSize: context.accR.small,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: context.accR.spaceM),

                    // قائمة العملاء
                    Text('اختر العملاء المراد تحصيلهم:',
                        style: GoogleFonts.cairo(
                            fontSize: context.accR.financialSmall,
                            fontWeight: FontWeight.w600)),
                    SizedBox(height: context.accR.spaceXS),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: creditCustomers.isEmpty
                          ? Padding(
                              padding: EdgeInsets.all(context.accR.spaceXL),
                              child: Center(
                                child: Text(
                                  isLoadingCustomers
                                      ? 'جاري التحميل...'
                                      : 'لا يوجد عملاء آجل غير مسددين',
                                  style: TextStyle(
                                      fontSize: context.accR.small,
                                      color: Colors.grey.shade500),
                                ),
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // زر تحديد/إلغاء الكل
                                Container(
                                  color: Colors.grey.shade100,
                                  child: ListTile(
                                    dense: true,
                                    leading: Checkbox(
                                      value: selectedLogIds.length ==
                                          creditCustomers.length,
                                      tristate: true,
                                      onChanged: (_) {
                                        setDlgState(() {
                                          if (selectedLogIds.length ==
                                              creditCustomers.length) {
                                            selectedLogIds.clear();
                                            amountController.clear();
                                          } else {
                                            selectedLogIds = creditCustomers
                                                .map((c) =>
                                                    (c['Id'] as num).toInt())
                                                .toSet();
                                            double total = creditCustomers.fold(
                                                0.0,
                                                (s, c) =>
                                                    s +
                                                    (c['Amount'] as num? ?? 0)
                                                        .toDouble());
                                            amountController.text =
                                                total.toStringAsFixed(0);
                                          }
                                        });
                                      },
                                    ),
                                    title: Text('تحديد الكل',
                                        style: GoogleFonts.cairo(
                                            fontSize: context.accR.small,
                                            fontWeight: FontWeight.w600)),
                                    trailing: Text(
                                        '${creditCustomers.length} عميل',
                                        style: TextStyle(
                                            fontSize: context.accR.small,
                                            color: Colors.grey.shade600)),
                                  ),
                                ),
                                Divider(height: 1, color: Colors.grey.shade300),
                                Flexible(
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: creditCustomers.length,
                                    separatorBuilder: (_, __) => Divider(
                                        height: 1, color: Colors.grey.shade200),
                                    itemBuilder: (_, i) {
                                      final c = creditCustomers[i];
                                      final logId = (c['Id'] as num).toInt();
                                      final cName =
                                          c['CustomerName']?.toString() ?? '-';
                                      final cAmount =
                                          (c['Amount'] as num? ?? 0).toDouble();
                                      final planName =
                                          c['PlanName']?.toString() ?? '';
                                      final date =
                                          c['ActivationDate']?.toString();
                                      final dateStr = date != null
                                          ? date.substring(
                                              0,
                                              date.length >= 10
                                                  ? 10
                                                  : date.length)
                                          : '';
                                      final isSelected =
                                          selectedLogIds.contains(logId);

                                      // معلومات التكرار
                                      final cycleMonths =
                                          c['RenewalCycleMonths'] as int?;
                                      final paidMonths =
                                          (c['PaidMonths'] as num?)?.toInt() ??
                                              0;
                                      final collectionType =
                                          c['CollectionType']?.toString() ??
                                              'credit';
                                      final isCashWithCycle =
                                          collectionType == 'cash' &&
                                              cycleMonths != null &&
                                              cycleMonths > 1;
                                      final isRecurring = cycleMonths != null &&
                                          cycleMonths > 0;
                                      final remainingMonths = isRecurring
                                          ? cycleMonths - paidMonths
                                          : 1;
                                      final monthlyAmount = cAmount;
                                      final remainingAmount = isRecurring
                                          ? monthlyAmount * remainingMonths
                                          : cAmount;

                                      return ListTile(
                                        dense: true,
                                        selected: isSelected,
                                        selectedTileColor:
                                            Colors.orange.shade50,
                                        leading: Checkbox(
                                          value: isSelected,
                                          activeColor: Colors.orange.shade700,
                                          onChanged: (v) {
                                            setDlgState(() {
                                              if (v == true) {
                                                selectedLogIds.add(logId);
                                              } else {
                                                selectedLogIds.remove(logId);
                                              }
                                              // تحديث المبلغ تلقائياً — للمكرر يُحسب شهر واحد فقط
                                              double total = 0;
                                              for (final cc
                                                  in creditCustomers) {
                                                if (selectedLogIds.contains(
                                                    (cc['Id'] as num)
                                                        .toInt())) {
                                                  total +=
                                                      (cc['Amount'] as num? ??
                                                              0)
                                                          .toDouble();
                                                }
                                              }
                                              amountController.text =
                                                  total.toStringAsFixed(0);
                                            });
                                          },
                                        ),
                                        title: Row(
                                          children: [
                                            Expanded(
                                              child: Text(cName,
                                                  style: GoogleFonts.cairo(
                                                      fontSize:
                                                          context.accR.small,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ),
                                            if (isRecurring) ...[
                                              SizedBox(
                                                  width: context.accR.spaceXS),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1),
                                                decoration: BoxDecoration(
                                                  color:
                                                      Colors.deepPurple.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                      color: Colors
                                                          .deepPurple.shade300),
                                                ),
                                                child: Text(
                                                  '🔄 $paidMonths/$cycleMonths شهر',
                                                  style: TextStyle(
                                                    fontSize:
                                                        context.accR.caption,
                                                    color: Colors
                                                        .deepPurple.shade700,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (isCashWithCycle) ...[
                                              SizedBox(
                                                  width: context.accR.spaceXS),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: Colors.teal.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                      color:
                                                          Colors.teal.shade300),
                                                ),
                                                child: Text(
                                                  'نقد+آجل',
                                                  style: TextStyle(
                                                    fontSize: 8,
                                                    color: Colors.teal.shade700,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        subtitle: Wrap(
                                          spacing: context.accR.spaceXS,
                                          children: [
                                            Text('$planName  •  $dateStr',
                                                style: TextStyle(
                                                    fontSize:
                                                        context.accR.caption,
                                                    color:
                                                        Colors.grey.shade600)),
                                            if (isRecurring)
                                              Text(
                                                'متبقي: ${_currencyFormat.format(remainingAmount)}',
                                                style: TextStyle(
                                                  fontSize:
                                                      context.accR.caption,
                                                  color: Colors.red.shade600,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                          ],
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        context
                                                            .accR.cardRadius),
                                                border: Border.all(
                                                    color:
                                                        Colors.orange.shade300),
                                              ),
                                              child: Text(
                                                  _currencyFormat
                                                      .format(monthlyAmount),
                                                  style: GoogleFonts.cairo(
                                                      fontSize:
                                                          context.accR.small,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Colors
                                                          .orange.shade800)),
                                            ),
                                            if (isRecurring)
                                              Text('/شهر',
                                                  style: TextStyle(
                                                      fontSize: 8,
                                                      color: Colors
                                                          .grey.shade500)),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                    ),
                    if (selectedLogIds.isNotEmpty) ...[
                      SizedBox(height: context.accR.spaceS),
                      Container(
                        padding: EdgeInsets.all(context.accR.spaceS),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                size: context.accR.iconS,
                                color: Colors.green.shade700),
                            SizedBox(width: context.accR.spaceXS),
                            Expanded(
                              child: Text(
                                'المحدد: ${selectedLogIds.length} عميل — المجموع: ${_currencyFormat.format(selectedTotal)}',
                                style: TextStyle(
                                    fontSize: context.accR.small,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // زر تحديد التكرار للعميل المحدد (إذا محدد عميل واحد فقط)
                      if (selectedLogIds.length == 1) ...[
                        SizedBox(height: context.accR.spaceXS),
                        Builder(builder: (_) {
                          final selLog = creditCustomers.firstWhere(
                            (c) =>
                                (c['Id'] as num).toInt() ==
                                selectedLogIds.first,
                            orElse: () => <String, dynamic>{},
                          );
                          final currentCycle =
                              selLog['RenewalCycleMonths'] as int?;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: Colors.deepPurple.shade200),
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  Icon(Icons.repeat,
                                      size: context.accR.iconS,
                                      color: Colors.deepPurple.shade700),
                                  SizedBox(width: context.accR.spaceXS),
                                  Text('التكرار:',
                                      style: TextStyle(
                                          fontSize: context.accR.small,
                                          color: Colors.deepPurple.shade700,
                                          fontWeight: FontWeight.w600)),
                                  SizedBox(width: context.accR.spaceS),
                                  ...([0, 1, 2, 3]).map((months) {
                                    final isActive =
                                        (months == 0 && currentCycle == null) ||
                                            currentCycle == months;
                                    final label = months == 0
                                        ? 'بدون'
                                        : months == 1
                                            ? 'شهر'
                                            : '$months أشهر';
                                    return Padding(
                                      padding: EdgeInsets.only(left: 4),
                                      child: InkWell(
                                        onTap: () async {
                                          final logId = selectedLogIds.first;
                                          final res = await AccountingService
                                              .instance
                                              .setRenewalCycle(
                                            logId: logId,
                                            cycleMonths:
                                                months == 0 ? null : months,
                                          );
                                          if (res['success'] == true) {
                                            // تحديث البيانات محلياً
                                            final idx = creditCustomers
                                                .indexWhere((c) =>
                                                    (c['Id'] as num).toInt() ==
                                                    logId);
                                            if (idx >= 0) {
                                              setDlgState(() {
                                                creditCustomers[idx]
                                                        ['RenewalCycleMonths'] =
                                                    months == 0 ? null : months;
                                                // إذا العملية نقد، الشهر الأول مدفوع تلقائياً
                                                final paidFromServer =
                                                    res['paidMonths'] as int? ??
                                                        0;
                                                creditCustomers[idx]
                                                        ['PaidMonths'] =
                                                    paidFromServer;
                                              });
                                            }
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isActive
                                                ? Colors.deepPurple.shade700
                                                : Colors.white,
                                            borderRadius: BorderRadius.circular(
                                                context.accR.cardRadius),
                                            border: Border.all(
                                                color:
                                                    Colors.deepPurple.shade300),
                                          ),
                                          child: Text(label,
                                              style: TextStyle(
                                                fontSize: context.accR.caption,
                                                color: isActive
                                                    ? Colors.white
                                                    : Colors
                                                        .deepPurple.shade700,
                                                fontWeight: FontWeight.w600,
                                              )),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                    SizedBox(height: context.accR.spaceM),
                    TextField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'المبلغ',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                    ),
                    SizedBox(height: context.accR.spaceS),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات (اختياري)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.note),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: Icon(Icons.check, size: context.accR.iconM),
                  label: const Text('تحصيل'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (result != true) return;
    final amount = double.tryParse(amountController.text);
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('أدخل مبلغاً صحيحاً'),
              backgroundColor: Colors.orange),
        );
      }
      return;
    }

    // جمع أسماء العملاء المحددين
    String? customerName;
    if (selectedLogIds.isNotEmpty) {
      final names = creditCustomers
          .where((c) => selectedLogIds.contains((c['Id'] as num).toInt()))
          .map((c) => c['CustomerName']?.toString() ?? '-')
          .toSet()
          .toList();
      customerName = names.join('، ');
    }

    try {
      final res = await AccountingService.instance.quickCollect(
        operatorUserId: userId,
        amount: amount,
        companyId: _companyId,
        notes: notesController.text.isEmpty ? null : notesController.text,
        subscriptionLogIds:
            selectedLogIds.isNotEmpty ? selectedLogIds.toList() : null,
        customerName: customerName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['success'] == true
                ? 'تم تحصيل ${_currencyFormat.format(amount)} بنجاح'
                : res['message'] ?? 'خطأ'),
            backgroundColor: res['success'] == true ? Colors.green : Colors.red,
          ),
        );
        if (res['success'] == true) _loadOursData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  TAB 2: خادم FTTH
  // ════════════════════════════════════════════════════════════════

  Widget _buildFtthTab() {
    if (!_ftthAuthenticated) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: context.accR.iconEmpty, color: Colors.grey.shade400),
            SizedBox(height: context.accR.spaceXL),
            Text('يجب تسجيل الدخول لخادم FTTH',
                style: TextStyle(
                    fontSize: context.accR.headingSmall,
                    color: Colors.grey.shade600)),
            SizedBox(height: context.accR.spaceM),
            ElevatedButton.icon(
              onPressed: _showFtthLoginDialog,
              icon: const Icon(Icons.login),
              label: const Text('تسجيل الدخول'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoadingFtth) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: context.accR.spaceM),
            Text('جاري جلب بيانات خادم FTTH...'),
          ],
        ),
      );
    }

    if (_errorFtth != null) {
      return _buildErrorWidget(_errorFtth!, () {
        if (!_ftthAuthenticated) {
          _showFtthLoginDialog();
        } else {
          _loadFtthData();
        }
      });
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(
          context.accR.isMobile ? context.accR.spaceM : context.accR.spaceXL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFtthSummary(),
          SizedBox(height: context.accR.spaceXS),
          // شريط تقدم نسب "بدون منشئ"
          if (_isResolvingOrphans)
            Padding(
              padding: EdgeInsets.only(bottom: context.accR.spaceS),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: context.accR.spaceS),
                      Text(
                        'جاري نسب "بدون منشئ": $_orphanResolved / $_orphanTotal',
                        style: TextStyle(
                          fontSize: context.accR.small,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: context.accR.spaceXS),
                  LinearProgressIndicator(
                    value:
                        _orphanTotal > 0 ? _orphanResolved / _orphanTotal : 0,
                    backgroundColor: Colors.orange.shade100,
                    valueColor: AlwaysStoppedAnimation(Colors.orange.shade600),
                    minHeight: 4,
                  ),
                ],
              ),
            ),

          // أزرار الفلترة (تعبئة الفريق + مجدول)
          Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                FilterChip(
                  label: Text(
                    _showTeamRefill ? 'إخفاء تعبئة الفريق' : 'إظهار تعبئة الفريق',
                    style: TextStyle(fontSize: context.accR.small),
                  ),
                  avatar: Icon(
                    _showTeamRefill ? Icons.visibility_off : Icons.visibility,
                    size: context.accR.iconS,
                    color: _showTeamRefill ? Colors.teal : Colors.grey,
                  ),
                  selected: _showTeamRefill,
                  selectedColor: Colors.teal.shade50,
                  checkmarkColor: Colors.teal,
                  onSelected: (v) => setState(() => _showTeamRefill = v),
                ),
                SizedBox(width: context.accR.spaceS),
                ActionChip(
                  label: Text(
                    'مجدول',
                    style: TextStyle(fontSize: context.accR.small),
                  ),
                  avatar: Icon(
                    Icons.schedule_send,
                    size: context.accR.iconS,
                    color: Colors.purple.shade600,
                  ),
                  backgroundColor: Colors.purple.shade50,
                  onPressed: _showScheduledDialog,
                ),
                SizedBox(width: context.accR.spaceS),
                ActionChip(
                  label: Text(
                    'تحميل Excel',
                    style: TextStyle(fontSize: context.accR.small),
                  ),
                  avatar: Icon(
                    Icons.download,
                    size: context.accR.iconS,
                    color: Colors.green.shade700,
                  ),
                  backgroundColor: Colors.green.shade50,
                  onPressed: _exportToExcel,
                ),
                if (_ftthAuthenticated && _ftthOperators.isNotEmpty) ...[
                  SizedBox(width: context.accR.spaceS),
                  Builder(builder: (_) {
                    final orphanCount =
                        (_ftthOperators['بدون منشئ']?.transactions.length ?? 0) +
                            (_ftthOperators['Agent']?.transactions.length ?? 0);
                    return ActionChip(
                      label: Text(
                        'إعادة نسب المعاملات${orphanCount > 0 ? ' ($orphanCount)' : ''}',
                        style: TextStyle(fontSize: context.accR.small),
                      ),
                      avatar: _isResolvingOrphans
                          ? SizedBox(
                              width: context.accR.iconS,
                              height: context.accR.iconS,
                              child: const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.orange)),
                            )
                          : Icon(Icons.person_search, size: context.accR.iconS, color: Colors.orange.shade700),
                      backgroundColor: Colors.orange.shade50,
                      onPressed: _isResolvingOrphans ? null : _resolveOrphansInBackground,
                    );
                  }),
                ],
              ],
            ),
          ),
          _buildFtthTable(),
        ],
      ),
    );
  }

  Future<void> _exportToExcel() async {
    if (_ftthOperators.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا توجد بيانات للتصدير',
              style: GoogleFonts.cairo()),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // جمع كل المعاملات
    final List<_FtthTransaction> allTx = [];
    final Map<String, _FtthOperatorData> ops = _ftthOperators;
    for (final op in ops.values) {
      for (final tx in op.transactions) {
        allTx.add(tx);
      }
    }
    allTx.sort((a, b) => b.occuredAt.compareTo(a.occuredAt));

    final excel = xl.Excel.createExcel();

    // ── ورقة 1: المعاملات التفصيلية ──
    final sheet1Name = 'المعاملات';
    final sheet1 = excel[sheet1Name];
    excel.setDefaultSheet(sheet1Name);

    final headers = [
      'المشغل', 'العميل', 'رقم العميل', 'رقم الاشتراك',
      'الباقة', 'نوع العملية', 'المبلغ', 'التاريخ',
      'طريقة الدفع', 'تاريخ البداية', 'تاريخ الانتهاء',
    ];
    final headerStyle = xl.CellStyle(
      bold: true,
      backgroundColorHex: xl.ExcelColor.fromHexString('FF1E6F75'),
      fontColorHex: xl.ExcelColor.white,
    );
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet1.cell(
          xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = xl.TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    for (int i = 0; i < allTx.length; i++) {
      final tx = allTx[i];
      // إيجاد اسم المشغل
      String opName = '';
      for (final entry in ops.entries) {
        if (entry.value.transactions.contains(tx)) {
          opName = entry.key;
          break;
        }
      }
      final rowData = [
        opName,
        tx.customerName,
        tx.customerId,
        tx.subscriptionId,
        tx.planName,
        _translateType(tx.type),
        tx.amount.toStringAsFixed(0),
        tx.occuredAt.length >= 10 ? tx.occuredAt.substring(0, 10) : tx.occuredAt,
        tx.paymentMethod,
        tx.startsAt.length >= 10 ? tx.startsAt.substring(0, 10) : tx.startsAt,
        tx.endsAt.length >= 10 ? tx.endsAt.substring(0, 10) : tx.endsAt,
      ];
      final rowStyle = xl.CellStyle(
        backgroundColorHex: i.isEven
            ? xl.ExcelColor.fromHexString('FFF5FFFE')
            : xl.ExcelColor.white,
      );
      for (int j = 0; j < rowData.length; j++) {
        final cell = sheet1.cell(
            xl.CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 1));
        cell.value = xl.TextCellValue(rowData[j]);
        cell.cellStyle = rowStyle;
      }
    }

    // ── ورقة 2: ملخص المشغلين ──
    final sheet2 = excel['ملخص المشغلين'];
    final summaryHeaders = [
      'المشغل', 'إجمالي المعاملات', 'الموجب', 'السالب',
      'شراء', 'تجديد/تغيير', 'مجدول', 'الفرق', 'الصافي',
      'عدد الجدولة', 'عمولات',
    ];
    final summaryHeaderStyle = xl.CellStyle(
      bold: true,
      backgroundColorHex: xl.ExcelColor.fromHexString('FF4A148C'),
      fontColorHex: xl.ExcelColor.white,
    );
    for (int i = 0; i < summaryHeaders.length; i++) {
      final cell = sheet2.cell(
          xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = xl.TextCellValue(summaryHeaders[i]);
      cell.cellStyle = summaryHeaderStyle;
    }
    final sortedOps = ops.values.toList()
      ..sort((a, b) => b.totalCount.compareTo(a.totalCount));
    for (int i = 0; i < sortedOps.length; i++) {
      final op = sortedOps[i];
      final purchase = op.calcPurchaseAmount();
      final renewChange = op.calcRenewChangeAmount();
      final schedule = op.calcScheduleAmount();
      final disc = op.calcTotalDiscount();
      final net = purchase + renewChange + disc;
      final rowData = [
        op.name,
        op.totalCount.toString(),
        op.positiveAmount.toStringAsFixed(0),
        op.negativeAmount.abs().toStringAsFixed(0),
        purchase.toStringAsFixed(0),
        renewChange.toStringAsFixed(0),
        schedule.toStringAsFixed(0),
        disc.toStringAsFixed(0),
        net.toStringAsFixed(0),
        op.scheduleOps.toString(),
        op.commissionOps.toString(),
      ];
      final netStyle = xl.CellStyle(
        bold: true,
        backgroundColorHex: xl.ExcelColor.fromHexString('FFFFF9C4'),
      );
      final scheduleStyle = xl.CellStyle(
        backgroundColorHex: xl.ExcelColor.fromHexString('FFEDE7F6'),
      );
      for (int j = 0; j < rowData.length; j++) {
        final cell = sheet2.cell(
            xl.CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 1));
        cell.value = xl.TextCellValue(rowData[j]);
        if (j == 8) cell.cellStyle = netStyle;      // الصافي
        if (j == 6) cell.cellStyle = scheduleStyle; // مجدول
      }
    }

    // حذف الورقة الافتراضية الفارغة
    excel.delete('Sheet1');

    // حفظ الملف
    final bytes = excel.save();
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إنشاء الملف', style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final dir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final filePath = '${dir.path}/ftth_transactions_$timestamp.xlsx';
    File(filePath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم حفظ الملف: $filePath', style: GoogleFonts.cairo()),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'فتح',
          textColor: Colors.white,
          onPressed: () => OpenFilex.open(filePath),
        ),
      ),
    );
  }

  void _showScheduledDialog() {
    // جمع كل عمليات PLAN_SCHEDULE من جميع المشغلين
    final List<Map<String, dynamic>> rows = [];
    for (final op in _ftthOperators.values) {
      for (final tx in op.transactions) {
        if (tx.type == 'PLAN_SCHEDULE') {
          rows.add({
            'operator': op.name,
            'tx': tx,
          });
        }
      }
    }
    // ترتيب تنازلي حسب التاريخ
    rows.sort((a, b) {
      final ta = (a['tx'] as _FtthTransaction).occuredAt;
      final tb = (b['tx'] as _FtthTransaction).occuredAt;
      return tb.compareTo(ta);
    });

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.accR.radiusL)),
          insetPadding: EdgeInsets.symmetric(
              horizontal: context.accR.isMobile ? 8 : 32, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 860,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // عنوان
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: context.accR.spaceM,
                      vertical: context.accR.spaceS),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade600,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(context.accR.radiusL),
                      topRight: Radius.circular(context.accR.radiusL),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.schedule_send,
                          color: Colors.white, size: context.accR.iconM),
                      SizedBox(width: context.accR.spaceS),
                      Expanded(
                        child: Text(
                          'العمليات المجدولة  (${rows.length})',
                          style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontSize: context.accR.body,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(ctx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                // الجدول
                Flexible(
                  child: rows.isEmpty
                      ? Padding(
                          padding: EdgeInsets.all(context.accR.spaceXL),
                          child: Text(
                            'لا توجد عمليات مجدولة في هذا النطاق',
                            style: GoogleFonts.cairo(
                                fontSize: context.accR.body,
                                color: Colors.grey.shade600),
                          ),
                        )
                      : SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                                Colors.purple.shade50),
                            columnSpacing: 16,
                            dataRowMinHeight: 40,
                            dataRowMaxHeight: 52,
                            columns: [
                              DataColumn(
                                  label: Text('المشغل',
                                      style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.w700,
                                          fontSize: context.accR.small))),
                              DataColumn(
                                  label: Text('العميل',
                                      style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.w700,
                                          fontSize: context.accR.small))),
                              DataColumn(
                                  label: Text('الباقة',
                                      style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.w700,
                                          fontSize: context.accR.small))),
                              DataColumn(
                                  label: Text('المبلغ',
                                      style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.w700,
                                          fontSize: context.accR.small))),
                              DataColumn(
                                  label: Text('التاريخ',
                                      style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.w700,
                                          fontSize: context.accR.small))),
                            ],
                            rows: rows.map((r) {
                              final tx = r['tx'] as _FtthTransaction;
                              final dateStr = tx.occuredAt.length >= 10
                                  ? tx.occuredAt.substring(0, 10)
                                  : tx.occuredAt;
                              return DataRow(cells: [
                                DataCell(Text(r['operator'] as String,
                                    style: GoogleFonts.cairo(
                                        fontSize: context.accR.small,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.purple.shade700))),
                                DataCell(Text(tx.customerName,
                                    style: GoogleFonts.cairo(
                                        fontSize: context.accR.small))),
                                DataCell(Text(tx.planName,
                                    style: GoogleFonts.cairo(
                                        fontSize: context.accR.small))),
                                DataCell(Text(
                                    _currencyFormat.format(tx.amount),
                                    style: GoogleFonts.cairo(
                                        fontSize: context.accR.small,
                                        color: tx.amount >= 0
                                            ? Colors.green.shade700
                                            : Colors.red.shade700,
                                        fontWeight: FontWeight.w600))),
                                DataCell(Text(dateStr,
                                    style: GoogleFonts.cairo(
                                        fontSize: context.accR.small,
                                        color: Colors.grey.shade700))),
                              ]);
                            }).toList(),
                          ),
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

  Widget _buildFtthSummary() {
    // بناء قائمة المشغلين المرئية (نفس منطق _buildFtthTable)
    var visibleList = _ftthOperators.values.toList();
    if (!_showTeamRefill) {
      visibleList = visibleList
          .map((op) {
            final refillCount =
                op.typeCounts['REFILL_TEAM_MEMBER_BALANCE'] ?? 0;
            if (refillCount == 0) return op;
            double refillAmount = 0;
            for (final tx in op.transactions) {
              if (tx.type == 'REFILL_TEAM_MEMBER_BALANCE') {
                refillAmount += tx.amount;
              }
            }
            final filtered = _FtthOperatorData(name: op.name);
            filtered.totalCount = op.totalCount - refillCount;
            filtered.totalAmount = op.totalAmount - refillAmount;
            filtered.negativeAmount = op.negativeAmount;
            filtered.positiveAmount = op.positiveAmount;
            if (refillAmount > 0) {
              filtered.positiveAmount -= refillAmount;
            } else {
              filtered.negativeAmount -= refillAmount;
            }
            filtered.subscriptionOps = op.subscriptionOps;
            filtered.purchaseOps = op.purchaseOps;
            filtered.renewOps = op.renewOps;
            filtered.changeOps = op.changeOps;
            filtered.scheduleOps = op.scheduleOps;
            filtered.commissionOps = op.commissionOps;
            filtered.reversalOps = op.reversalOps;
            filtered.walletOps = op.walletOps;
            filtered.otherOps = op.otherOps - refillCount;
            filtered.attributedOps = op.attributedOps;
            filtered.totalDiscount = op.totalDiscount;
            filtered.typeCounts = Map.from(op.typeCounts)
              ..remove('REFILL_TEAM_MEMBER_BALANCE');
            filtered.transactions = op.transactions
                .where((tx) => tx.type != 'REFILL_TEAM_MEMBER_BALANCE')
                .toList();
            return filtered;
          })
          .where((op) => op.totalCount > 0)
          .toList();
    }

    // حساب إجماليات الفئات من القائمة المرئية
    int totalPur = 0, totalRen = 0, totalChg = 0, totalSch = 0;
    int totalComm = 0, totalRev = 0, totalWal = 0, totalOth = 0;
    int totalAttr = 0;
    double totalDiscount = 0;
    double visiblePositive = 0;
    double visibleNegative = 0;
    int visibleCount = 0;
    for (final op in visibleList) {
      totalPur += op.purchaseOps;
      totalRen += op.renewOps;
      totalChg += op.changeOps;
      totalSch += op.scheduleOps;
      totalComm += op.commissionOps;
      totalRev += op.reversalOps;
      totalWal += op.walletOps;
      totalOth += op.otherOps;
      totalAttr += op.attributedOps;
      totalDiscount += op.calcTotalDiscount();
      visiblePositive += op.positiveAmount;
      visibleNegative += op.negativeAmount;
      visibleCount += op.totalCount;
    }

    final isMobile = context.accR.isMobile;

    final card1 = _summaryCardMain(
        'إجمالي المعاملات',
        visibleCount.toDouble(),
        '${visibleList.length} مشغل',
        AccountingTheme.neonBlue,
        Icons.receipt_long,
        isCount: true);
    final card2 = _summaryCardMain('مجموع السالب', visibleNegative.abs(),
        'مبالغ مخصومة', Colors.red.shade600, Icons.arrow_circle_down);
    final card3 = _summaryCardMain('مجموع الموجب', visiblePositive,
        'عمولات ومرتجعات', Colors.green.shade600, Icons.arrow_circle_up);
    final card4 = _summaryCardMain('مجموع الفرق', totalDiscount,
        'خصومات التجديد والتغيير', Colors.orange.shade700, Icons.discount);

    if (isMobile) {
      final halfW = (MediaQuery.of(context).size.width - 32 - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [card1, card2, card3, card4]
            .map((c) => SizedBox(width: halfW, child: c))
            .toList(),
      );
    }

    return Column(
      children: [
        // الصف الأول: البطاقات الرئيسية (إجمالي + سالب + موجب + الفرق)
        Row(
          children: [
            Expanded(child: card1),
            SizedBox(width: context.accR.spaceS),
            Expanded(child: card2),
            SizedBox(width: context.accR.spaceS),
            Expanded(child: card3),
            SizedBox(width: context.accR.spaceS),
            Expanded(child: card4),
          ],
        ),
      ],
    );
  }

  Widget _buildFtthTable() {
    if (_ftthOperators.isEmpty) {
      return _emptyCard('لا توجد معاملات في هذا النطاق');
    }

    var list = _ftthOperators.values.toList();
    if (!_showTeamRefill) {
      // حساب عدد عمليات REFILL_TEAM_MEMBER_BALANCE لكل مشغل وطرحها
      list = list
          .map((op) {
            final refillCount =
                op.typeCounts['REFILL_TEAM_MEMBER_BALANCE'] ?? 0;
            if (refillCount == 0) return op;
            // حساب مبلغ عمليات التعبئة
            double refillAmount = 0;
            for (final tx in op.transactions) {
              if (tx.type == 'REFILL_TEAM_MEMBER_BALANCE') {
                refillAmount += tx.amount;
              }
            }
            // إنشاء نسخة معدلة بدون عمليات التعبئة
            final filtered = _FtthOperatorData(name: op.name);
            filtered.totalCount = op.totalCount - refillCount;
            filtered.totalAmount = op.totalAmount - refillAmount;
            filtered.negativeAmount = op.negativeAmount;
            filtered.positiveAmount = op.positiveAmount;
            if (refillAmount > 0) {
              filtered.positiveAmount -= refillAmount;
            } else {
              filtered.negativeAmount -= refillAmount;
            }
            filtered.subscriptionOps = op.subscriptionOps;
            filtered.purchaseOps = op.purchaseOps;
            filtered.renewOps = op.renewOps;
            filtered.changeOps = op.changeOps;
            filtered.scheduleOps = op.scheduleOps;
            filtered.commissionOps = op.commissionOps;
            filtered.reversalOps = op.reversalOps;
            filtered.walletOps = op.walletOps;
            filtered.otherOps = op.otherOps - refillCount;
            filtered.attributedOps = op.attributedOps;
            filtered.totalDiscount = op.totalDiscount;
            filtered.typeCounts = Map.from(op.typeCounts)
              ..remove('REFILL_TEAM_MEMBER_BALANCE');
            filtered.transactions = op.transactions
                .where((tx) => tx.type != 'REFILL_TEAM_MEMBER_BALANCE')
                .toList();
            return filtered;
          })
          .where((op) => op.totalCount > 0)
          .toList();
    }
    final sorted = list..sort((a, b) => b.totalCount.compareTo(a.totalCount));

    // موبايل: جدول بعمود مثبت + تمرير أفقي
    if (context.accR.isMobile) {
      return _buildFtthTableMobile(sorted);
    }

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        side: const BorderSide(color: Colors.black, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                  ),
                  child: DataTable(
                    border: TableBorder.all(color: Colors.black, width: 1.5),
                    dividerThickness: 0,
                    showCheckboxColumn: false,
                    headingRowColor:
                        WidgetStateProperty.all(Colors.teal.shade50),
                    dataRowMinHeight: 28,
                    dataRowMaxHeight: 36,
                    headingRowHeight: 32,
                    columnSpacing: 0,
                    horizontalMargin: 8,
                    headingTextStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: context.accR.financialSmall,
                        color: Colors.black87),
                    columns: [
                      DataColumn(
                          label: Expanded(child: Center(child: Text('#'))),
                          numeric: true),
                      DataColumn(
                          label:
                              Expanded(child: Center(child: Text('المشغل')))),
                      DataColumn(
                          label: Expanded(child: Center(child: Text('شراء')))),
                      DataColumn(
                          label: Expanded(child: Center(child: Text('تجديد')))),
                      DataColumn(
                          label: Expanded(child: Center(child: Text('تغيير')))),
                      DataColumn(
                          label: Expanded(child: Center(child: Text('جدولة')))),
                      DataColumn(
                          label:
                              Expanded(child: Center(child: Text('عمولات')))),
                      DataColumn(
                          label: Expanded(child: Center(child: Text('عكس')))),
                      DataColumn(
                          label: Expanded(child: Center(child: Text('محفظة')))),
                      DataColumn(
                          label: Expanded(child: Center(child: Text('أخرى')))),
                      DataColumn(
                          label:
                              Expanded(child: Center(child: Text('الإجمالي')))),
                      DataColumn(
                          label:
                              Expanded(child: Center(child: Text('الشراء')))),
                      DataColumn(
                          label: Expanded(
                              child: Center(
                                  child: Text('التجديد/التغيير',
                                      style: TextStyle(
                                          fontSize: context.accR.small))))),
                      DataColumn(
                          label: Expanded(child: Center(child: Text('الفرق')))),
                      DataColumn(
                          label:
                              Expanded(child: Center(child: Text('الصافي')))),
                      DataColumn(
                          label: Expanded(
                              child: Center(child: Text('التحويلات')))),
                      DataColumn(
                          label:
                              Expanded(child: Center(child: Text('التفاصيل')))),
                    ],
                    rows: sorted.asMap().entries.map((entry) {
                      final i = entry.key;
                      final op = entry.value;

                      return DataRow(
                          onSelectChanged: (_) => _openOperatorTransactions(op),
                          cells: [
                            DataCell(Text('${i + 1}',
                                style: TextStyle(
                                    fontSize: context.accR.small,
                                    fontWeight: FontWeight.w600))),
                            DataCell(Center(
                                child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                    op.name == 'بدون منشئ'
                                        ? 'بدون منسئ'
                                        : op.name,
                                    style: TextStyle(
                                        fontSize: context.accR.small,
                                        fontWeight: FontWeight.w700)),
                                if (op.attributedOps > 0)
                                  Text(
                                    '+${op.attributedOps} منسوبة',
                                    style: TextStyle(
                                        fontSize: context.accR.caption,
                                        color: Colors.blue.shade600),
                                  ),
                              ],
                            ))),
                            DataCell(Center(
                                child: Text('${op.purchaseOps}',
                                    style: TextStyle(
                                        fontSize: context.accR.small,
                                        fontWeight: FontWeight.w700,
                                        color: op.purchaseOps > 0
                                            ? Colors.teal.shade700
                                            : Colors.grey.shade400)))),
                            DataCell(Center(
                                child: Text('${op.renewOps}',
                                    style: TextStyle(
                                        fontSize: context.accR.small,
                                        fontWeight: FontWeight.w700,
                                        color: op.renewOps > 0
                                            ? Colors.teal.shade600
                                            : Colors.grey.shade400)))),
                            DataCell(Center(
                                child: Text('${op.changeOps}',
                                    style: TextStyle(
                                        fontSize: context.accR.small,
                                        fontWeight: FontWeight.w600,
                                        color: op.changeOps > 0
                                            ? Colors.teal.shade500
                                            : Colors.grey.shade400)))),
                            DataCell(Center(
                                child: Text('${op.scheduleOps}',
                                    style: TextStyle(
                                        fontSize: context.accR.small,
                                        fontWeight: FontWeight.w600,
                                        color: op.scheduleOps > 0
                                            ? Colors.teal.shade400
                                            : Colors.grey.shade400)))),
                            DataCell(Center(
                                child: Text('${op.commissionOps}',
                                    style: TextStyle(
                                        fontSize: context.accR.small,
                                        fontWeight: FontWeight.w600,
                                        color: op.commissionOps > 0
                                            ? Colors.purple.shade700
                                            : Colors.grey.shade400)))),
                            DataCell(Center(
                                child: Text('${op.reversalOps}',
                                    style: TextStyle(
                                        fontSize: context.accR.small,
                                        fontWeight: FontWeight.w600,
                                        color: op.reversalOps > 0
                                            ? Colors.orange.shade700
                                            : Colors.grey.shade400)))),
                            DataCell(Center(
                                child: Text('${op.walletOps}',
                                    style: TextStyle(
                                        fontSize: context.accR.small,
                                        fontWeight: FontWeight.w600,
                                        color: op.walletOps > 0
                                            ? Colors.blue.shade700
                                            : Colors.grey.shade400)))),
                            // أخرى: إظهار كل نوع بدل رقم واحد
                            DataCell(Center(child: _buildOtherTypesCell(op))),
                            DataCell(Center(
                                child: Text('${op.totalCount}',
                                    style: TextStyle(
                                        fontSize: context.accR.small,
                                        fontWeight: FontWeight.w700)))),
                            // عمود الشراء
                            DataCell(Center(child: () {
                              final purchase = op.calcPurchaseAmount();
                              return Text(
                                _currencyFormat.format(purchase),
                                style: TextStyle(
                                    fontSize: context.accR.small,
                                    fontWeight: FontWeight.w700,
                                    color: purchase > 0
                                        ? Colors.red.shade700
                                        : Colors.grey.shade400),
                              );
                            }())),
                            // عمود التجديد/التغيير
                            DataCell(Center(child: () {
                              final renewChange = op.calcRenewChangeAmount();
                              return Text(
                                _currencyFormat.format(renewChange),
                                style: TextStyle(
                                    fontSize: context.accR.small,
                                    fontWeight: FontWeight.w700,
                                    color: renewChange > 0
                                        ? Colors.red.shade600
                                        : Colors.grey.shade400),
                              );
                            }())),
                            // عمود الفرق (إجمالي الخصومات)
                            DataCell(Center(child: () {
                              final disc = op.calcTotalDiscount();
                              if (disc > 0) {
                                return Text(
                                  _currencyFormat.format(disc),
                                  style: TextStyle(
                                      fontSize: context.accR.small,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.orange.shade800),
                                );
                              }
                              return Text('0',
                                  style: TextStyle(
                                      fontSize: context.accR.small,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey.shade400));
                            }())),
                            // عمود الصافي (الشراء + التجديد/التغيير + الفرق)
                            DataCell(Container(
                              color: Colors.green.shade50,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              child: Center(child: () {
                                final net = op.calcPurchaseAmount() +
                                    op.calcRenewChangeAmount() +
                                    op.calcTotalDiscount();
                                return Text(
                                  _currencyFormat.format(net),
                                  style: TextStyle(
                                      fontSize: context.accR.small,
                                      fontWeight: FontWeight.w700,
                                      color: net > 0
                                          ? Colors.deepOrange.shade700
                                          : Colors.grey.shade400),
                                );
                              }()),
                            )),
                            DataCell(Center(
                                child: Text(
                              _currencyFormat.format(op.positiveAmount),
                              style: TextStyle(
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade700),
                            ))),
                            DataCell(
                              SizedBox(
                                width: 50,
                                child: Center(
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: BoxConstraints(),
                                    icon: Icon(Icons.info_outline,
                                        size: context.accR.iconS,
                                        color: Colors.teal.shade600),
                                    tooltip: 'عرض تفاصيل الأنواع',
                                    onPressed: () => _showTypeBreakdown(op),
                                  ),
                                ),
                              ),
                            ),
                          ]);
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// جدول FTTH للموبايل مع عمود مشغل مثبت + تمرير أفقي
  Widget _buildFtthTableMobile(List<_FtthOperatorData> sorted) {
    const double headerH = 38.0;
    const double rowH = 44.0;
    const double frozenW = 115.0;
    const double numW = 26.0;
    const double countCellW = 56.0;
    const double totalCellW = 60.0;
    const double amountCellW = 82.0;
    const double detailCellW = 46.0;

    final hStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: context.accR.caption,
      color: Colors.black87,
    );

    Widget hCell(String text, double w) => Container(
          width: w,
          height: headerH,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            border: Border(
              right: BorderSide(color: Colors.black, width: 1.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(text,
              style: hStyle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        );

    Widget dCell(Widget child, double w, [Color? bg]) => Container(
          width: w,
          height: rowH,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            border: const Border(
              right: BorderSide(color: Colors.black, width: 1.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: child,
        );

    TextStyle cStyle({FontWeight fw = FontWeight.w600, Color? color}) =>
        TextStyle(
          fontSize: context.accR.caption,
          fontWeight: fw,
          color: color ?? Colors.black87,
        );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        side: const BorderSide(color: Colors.black, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ──────── عمود مثبت: # + المشغل ────────
          Container(
            width: frozenW,
            decoration: BoxDecoration(
              color: Colors.white,
              border: const Border(
                  right: BorderSide(color: Colors.black, width: 1.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // رأس العمود المثبت
                Container(
                  height: headerH,
                  color: Colors.teal.shade50,
                  child: Row(
                    children: [
                      Container(
                        width: numW,
                        alignment: Alignment.center,
                        child: Text('#', style: hStyle),
                      ),
                      Container(width: 1.5, color: Colors.black),
                      Expanded(
                          child: Center(child: Text('المشغل', style: hStyle))),
                    ],
                  ),
                ),
                Container(height: 2.5, color: Colors.black),
                // صفوف البيانات المثبتة
                ...sorted.asMap().entries.map((entry) {
                  final i = entry.key;
                  final op = entry.value;
                  return InkWell(
                    onTap: () => _openOperatorTransactions(op),
                    child: Container(
                      height: rowH,
                      decoration: BoxDecoration(
                        color: i.isEven
                            ? Colors.teal.shade50
                            : Colors.teal.shade100,
                        border: const Border(
                            bottom:
                                BorderSide(color: Colors.black, width: 1.5)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: numW,
                            alignment: Alignment.center,
                            child: Text('${i + 1}',
                                style: cStyle(fw: FontWeight.w600)),
                          ),
                          Container(width: 1.5, color: Colors.black),
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    op.name == 'بدون منشئ'
                                        ? 'بدون منسئ'
                                        : op.name,
                                    style: cStyle(fw: FontWeight.w700),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  if (op.attributedOps > 0)
                                    Text(
                                      '+${op.attributedOps} منسوبة',
                                      style: TextStyle(
                                          fontSize: context.accR.caption - 1,
                                          color: Colors.blue.shade600),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),

          // ──────── أعمدة قابلة للتمرير ────────
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // رأس الأعمدة القابلة للتمرير
                  Container(
                    height: headerH,
                    color: Colors.teal.shade50,
                    child: Row(
                      children: [
                        hCell('شراء', countCellW),
                        hCell('تجديد', countCellW),
                        hCell('تغيير', countCellW),
                        hCell('جدولة', countCellW),
                        hCell('عمولات', countCellW),
                        hCell('عكس', countCellW),
                        hCell('محفظة', countCellW),
                        hCell('أخرى', countCellW),
                        hCell('الإجمالي', totalCellW),
                        hCell('الشراء', amountCellW),
                        hCell('التجديد/\nالتغيير', amountCellW),
                        hCell('الفرق', amountCellW),
                        hCell('الصافي', amountCellW),
                        hCell('التحويلات', amountCellW),
                        hCell('التفاصيل', detailCellW),
                      ],
                    ),
                  ),
                  Container(height: 2.5, color: Colors.black),
                  // صفوف البيانات القابلة للتمرير
                  ...sorted.asMap().entries.map((entry) {
                    final i = entry.key;
                    final op = entry.value;
                    final purchase = op.calcPurchaseAmount();
                    final renewChange = op.calcRenewChangeAmount();
                    final disc = op.calcTotalDiscount();
                    final net = purchase + renewChange + disc;

                    return InkWell(
                      onTap: () => _openOperatorTransactions(op),
                      child: Container(
                        height: rowH,
                        decoration: BoxDecoration(
                          color: i.isEven ? Colors.white : Colors.grey.shade50,
                          border: const Border(
                              bottom:
                                  BorderSide(color: Colors.black, width: 1.5)),
                        ),
                        child: Row(
                          children: [
                            // أعمدة الأعداد
                            dCell(
                                Text('${op.purchaseOps}',
                                    style: cStyle(
                                        fw: FontWeight.w700,
                                        color: op.purchaseOps > 0
                                            ? Colors.teal.shade700
                                            : Colors.grey.shade400)),
                                countCellW),
                            dCell(
                                Text('${op.renewOps}',
                                    style: cStyle(
                                        fw: FontWeight.w700,
                                        color: op.renewOps > 0
                                            ? Colors.teal.shade600
                                            : Colors.grey.shade400)),
                                countCellW),
                            dCell(
                                Text('${op.changeOps}',
                                    style: cStyle(
                                        color: op.changeOps > 0
                                            ? Colors.teal.shade500
                                            : Colors.grey.shade400)),
                                countCellW),
                            dCell(
                                Text('${op.scheduleOps}',
                                    style: cStyle(
                                        color: op.scheduleOps > 0
                                            ? Colors.teal.shade400
                                            : Colors.grey.shade400)),
                                countCellW),
                            dCell(
                                Text('${op.commissionOps}',
                                    style: cStyle(
                                        color: op.commissionOps > 0
                                            ? Colors.purple.shade700
                                            : Colors.grey.shade400)),
                                countCellW),
                            dCell(
                                Text('${op.reversalOps}',
                                    style: cStyle(
                                        color: op.reversalOps > 0
                                            ? Colors.orange.shade700
                                            : Colors.grey.shade400)),
                                countCellW),
                            dCell(
                                Text('${op.walletOps}',
                                    style: cStyle(
                                        color: op.walletOps > 0
                                            ? Colors.blue.shade700
                                            : Colors.grey.shade400)),
                                countCellW),
                            dCell(
                                FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: _buildOtherTypesCell(op)),
                                countCellW),
                            dCell(
                                Text('${op.totalCount}',
                                    style: cStyle(fw: FontWeight.w700)),
                                totalCellW),
                            // أعمدة المبالغ
                            dCell(
                                Text(_currencyFormat.format(purchase),
                                    style: cStyle(
                                        fw: FontWeight.w700,
                                        color: purchase > 0
                                            ? Colors.red.shade700
                                            : Colors.grey.shade400)),
                                amountCellW),
                            dCell(
                                Text(_currencyFormat.format(renewChange),
                                    style: cStyle(
                                        fw: FontWeight.w700,
                                        color: renewChange > 0
                                            ? Colors.red.shade600
                                            : Colors.grey.shade400)),
                                amountCellW),
                            dCell(
                                disc > 0
                                    ? Text(_currencyFormat.format(disc),
                                        style: cStyle(
                                            fw: FontWeight.w700,
                                            color: Colors.orange.shade800))
                                    : Text('0',
                                        style: cStyle(
                                            fw: FontWeight.w500,
                                            color: Colors.grey.shade400)),
                                amountCellW),
                            dCell(
                                Text(_currencyFormat.format(net),
                                    style: cStyle(
                                        fw: FontWeight.w700,
                                        color: net > 0
                                            ? Colors.deepOrange.shade700
                                            : Colors.grey.shade400)),
                                amountCellW,
                                Colors.green.shade50),
                            dCell(
                                Text(_currencyFormat.format(op.positiveAmount),
                                    style:
                                        cStyle(color: Colors.green.shade700)),
                                amountCellW),
                            // زر التفاصيل
                            Container(
                              width: detailCellW,
                              height: rowH,
                              alignment: Alignment.center,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: Icon(Icons.info_outline,
                                    size: context.accR.iconS,
                                    color: Colors.teal.shade600),
                                tooltip: 'عرض تفاصيل الأنواع',
                                onPressed: () => _showTypeBreakdown(op),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// فتح صفحة عمليات المشغل عند الضغط على الصف
  void _openOperatorTransactions(_FtthOperatorData op) {
    // تحويل المعاملات إلى قائمة من Map لتمريرها
    final txList = op.transactions
        .map((tx) => {
              'id': tx.id,
              'type': tx.type,
              'amount': tx.amount,
              'subscriptionId': tx.subscriptionId,
              'customerName': tx.customerName,
              'customerId': tx.customerId,
              'planName': tx.planName,
              'occuredAt': tx.occuredAt,
              'createdBy': tx.createdBy,
              'zoneId': tx.zoneId,
              'deviceUsername': tx.deviceUsername,
              'auditCreator': tx.auditCreator,
              'planDuration': tx.planDuration,
              'remainingBalance': tx.remainingBalance,
              'paymentMode': tx.paymentMode,
              'paymentMethod': tx.paymentMethod,
              'startsAt': tx.startsAt,
              'endsAt': tx.endsAt,
            })
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FtthOperatorTransactionsPage(
          operatorName: op.name,
          transactions: txList,
          attributedOps: op.attributedOps,
        ),
      ),
    );
  }

  /// عرض تفاصيل أنواع العمليات لمشغل معين
  void _showTypeBreakdown(_FtthOperatorData op) {
    final sorted = op.typeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.accR.radiusL)),
          title: Row(
            children: [
              Icon(Icons.list_alt,
                  color: Colors.teal.shade700, size: context.accR.iconM),
              SizedBox(width: context.accR.spaceS),
              Expanded(
                child: Text('تفاصيل عمليات: ${op.name}',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.body,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          content: SizedBox(
            width: context.accR.isMobile
                ? MediaQuery.of(context).size.width * 0.92
                : 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ملخص الفئات
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _typeBadge('شراء', op.purchaseOps, Colors.teal.shade700),
                    _typeBadge('تجديد', op.renewOps, Colors.teal.shade500),
                    _typeBadge('تغيير', op.changeOps, Colors.teal.shade400),
                    _typeBadge('جدولة', op.scheduleOps, Colors.teal.shade300),
                    _typeBadge('عمولات', op.commissionOps, Colors.purple),
                    _typeBadge('عكس', op.reversalOps, Colors.orange),
                    _typeBadge('محفظة', op.walletOps, Colors.blue),
                  ],
                ),
                const Divider(height: 20),
                // تفاصيل كل نوع
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: sorted.length,
                    itemBuilder: (_, i) {
                      final type = sorted[i].key;
                      final count = sorted[i].value;
                      final cat = _categorizeType(type);
                      final catColor = cat == 'subscription'
                          ? Colors.teal
                          : cat == 'commission'
                              ? Colors.purple
                              : cat == 'reversal'
                                  ? Colors.orange
                                  : cat == 'wallet'
                                      ? Colors.blue
                                      : Colors.grey;

                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: catColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: context.accR.spaceS),
                            Expanded(
                              child: Text(_translateType(type),
                                  style:
                                      TextStyle(fontSize: context.accR.small)),
                            ),
                            Text('$count',
                                style: TextStyle(
                                    fontSize: context.accR.small,
                                    fontWeight: FontWeight.bold,
                                    color: catColor.shade700)),
                            SizedBox(width: context.accR.spaceXS),
                            Text(type,
                                style: TextStyle(
                                    fontSize: context.accR.caption,
                                    color: Colors.grey.shade500)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Divider(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text('الإجمالي: ${op.totalCount}',
                        style: GoogleFonts.cairo(
                            fontSize: context.accR.small,
                            fontWeight: FontWeight.bold)),
                    Text(
                        'سالب: ${_currencyFormat.format(op.negativeAmount.abs())} | موجب: ${_currencyFormat.format(op.positiveAmount)}',
                        style: TextStyle(fontSize: context.accR.caption)),
                  ],
                ),
                // عرض تفاصيل المعاملات الفردية لعمليات "بدون منشئ" أو المنسوبة
                if (op.name == 'بدون منشئ' || op.attributedOps > 0) ...[
                  Divider(height: 16),
                  Text(
                    op.name == 'بدون منشئ'
                        ? '📋 تفاصيل العمليات (${op.transactions.length})'
                        : '📋 العمليات المنسوبة تلقائياً (${op.attributedOps})',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.small,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade700),
                  ),
                  SizedBox(height: context.accR.spaceXS),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: op.name == 'بدون منشئ'
                          ? op.transactions.length
                          : op.transactions
                              .where((t) => t.createdBy.startsWith('⇐'))
                              .length,
                      itemBuilder: (_, i) {
                        final tx = op.name == 'بدون منشئ'
                            ? op.transactions[i]
                            : op.transactions
                                .where((t) => t.createdBy.startsWith('⇐'))
                                .toList()[i];
                        return Container(
                          margin: EdgeInsets.only(bottom: 4),
                          padding: EdgeInsets.all(context.accR.spaceS),
                          decoration: BoxDecoration(
                            color: op.name == 'بدون منشئ'
                                ? Colors.orange.shade50
                                : Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: op.name == 'بدون منشئ'
                                  ? Colors.orange.shade200
                                  : Colors.indigo.shade200,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(_translateType(tx.type),
                                      style: TextStyle(
                                          fontSize: context.accR.small,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.teal.shade700)),
                                  Spacer(),
                                  Text(
                                      '${_currencyFormat.format(tx.amount.abs())} د.ع',
                                      style: TextStyle(
                                          fontSize: context.accR.small,
                                          fontWeight: FontWeight.bold,
                                          color: tx.amount < 0
                                              ? Colors.red.shade700
                                              : Colors.green.shade700)),
                                ],
                              ),
                              if (tx.customerName.isNotEmpty)
                                Text('👤 العميل: ${tx.customerName}',
                                    style: TextStyle(
                                        fontSize: context.accR.small,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue.shade800)),
                              if (tx.auditCreator.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color: Colors.green.shade300),
                                  ),
                                  child: Text(
                                      '🔍 المنشئ (audit): ${tx.auditCreator}',
                                      style: TextStyle(
                                          fontSize: context.accR.caption,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade800)),
                                ),
                              if (tx.customerId.isNotEmpty &&
                                  tx.auditCreator.isEmpty)
                                Text('🆔 معرف العميل: ${tx.customerId}',
                                    style: TextStyle(
                                        fontSize: context.accR.caption,
                                        color: Colors.grey.shade600)),
                              if (tx.planName.isNotEmpty)
                                Text('📦 ${tx.planName}',
                                    style: TextStyle(
                                        fontSize: context.accR.caption,
                                        color: Colors.grey.shade600)),
                              if (tx.zoneId.isNotEmpty)
                                Text('📍 زون: ${tx.zoneId}',
                                    style: TextStyle(
                                        fontSize: context.accR.caption,
                                        color: Colors.grey.shade600)),
                              if (tx.occuredAt.isNotEmpty)
                                Text('🕐 ${_formatTxDate(tx.occuredAt)}',
                                    style: TextStyle(
                                        fontSize: context.accR.caption,
                                        color: Colors.grey.shade500)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeBadge(String label, int count, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.spaceS, vertical: context.accR.spaceXS),
      decoration: BoxDecoration(
        color: count > 0 ? color.withOpacity(0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: count > 0 ? color.withOpacity(0.5) : Colors.grey.shade300,
        ),
      ),
      child: Text('$label: $count',
          style: TextStyle(
              fontSize: context.accR.small,
              fontWeight: FontWeight.w600,
              color: count > 0 ? color : Colors.grey.shade500)),
    );
  }

  /// خلية عمود "أخرى" - تعرض كل نوع باسمه العربي
  Widget _buildOtherTypesCell(_FtthOperatorData op) {
    if (op.otherOps == 0) {
      return Text('0',
          style: TextStyle(
              fontSize: context.accR.small, color: Colors.grey.shade400));
    }
    // جمع أنواع "أخرى" فقط
    final otherTypes = <String, int>{};
    for (final e in op.typeCounts.entries) {
      if (_categorizeType(e.key) == 'other') {
        otherTypes[e.key] = e.value;
      }
    }
    final sorted = otherTypes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: sorted.map((e) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 1),
          child: Text(
            '${_translateType(e.key)}: ${e.value}',
            style: TextStyle(
              fontSize: context.accR.caption,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatTxDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return DateFormat('MM/dd HH:mm').format(dt);
    } catch (_) {
      return isoDate;
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  TAB 3: المقارنة
  // ════════════════════════════════════════════════════════════════

  Widget _buildCompareTab() {
    if (!_ftthAuthenticated) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: context.accR.iconXL, color: Colors.grey.shade400),
            SizedBox(height: context.accR.spaceM),
            Text('يجب تسجيل الدخول لخادم FTTH أولاً لإجراء المقارنة',
                style: TextStyle(
                    fontSize: context.accR.body, color: Colors.grey.shade600)),
            SizedBox(height: context.accR.spaceM),
            ElevatedButton.icon(
              onPressed: _showFtthLoginDialog,
              icon: const Icon(Icons.login),
              label: const Text('تسجيل الدخول'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoadingCompare || _isLoadingOurs || _isLoadingFtth || _isResolvingOrphans) {
      final status = _isLoadingOurs
          ? 'جاري تحميل بيانات خادمنا...'
          : _isLoadingFtth
              ? 'جاري تحميل بيانات FTTH...'
              : _isResolvingOrphans
                  ? 'جاري نسب العمليات ($_orphanResolved/$_orphanTotal)...'
                  : 'جاري بناء المقارنة...';
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: context.accR.spaceM),
            Text(status),
          ],
        ),
      );
    }

    if (_comparisonRows.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isLoadingCompare) _buildComparison();
      });
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(
          context.accR.isMobile ? context.accR.spaceM : context.accR.spaceXL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCompareSummaryCards(),
          SizedBox(height: context.accR.spaceXS),
          _buildCompareTable(),
        ],
      ),
    );
  }

  Widget _buildCompareSummaryCards() {
    final total = _totalMatched + _totalOursOnly + _totalFtthOnly;
    final matchPercent = total > 0 ? (_totalMatched / total * 100) : 0;

    return Row(
      children: [
        Expanded(child: _summaryCard(
            'مطابقة',
            _totalMatched.toDouble(),
            '${matchPercent.toStringAsFixed(0)}% من الإجمالي',
            Colors.green.shade600,
            icon: Icons.check_circle,
            isCount: true)),
        const SizedBox(width: 8),
        Expanded(child: _summaryCard('في خادمنا فقط', _totalOursOnly.toDouble(),
            'غير موجودة في FTTH', Colors.blue.shade600,
            icon: Icons.info_outline, isCount: true)),
        const SizedBox(width: 8),
        Expanded(child: _summaryCard('في FTTH فقط', _totalFtthOnly.toDouble(),
            'غير موجودة عندنا', Colors.red.shade600,
            icon: Icons.error_outline, isCount: true)),
      ],
    );
  }

  void _showWrongTransactions(_ComparisonRow row) {
    final txs = row.wrongTransactions;
    if (txs.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange.shade700),
              SizedBox(width: context.accR.spaceS),
              Expanded(
                child: Text(
                  'عمليات خاطئة — ${row.operatorName} (${txs.length})',
                  style: GoogleFonts.cairo(
                      fontSize: context.accR.headingSmall,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width * 0.9 : 900,
            height: 500,
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                border: TableBorder.all(color: Colors.grey.shade300),
                dataRowMinHeight: 28,
                dataRowMaxHeight: 40,
                headingRowHeight: 32,
                columnSpacing: 12,
                horizontalMargin: 8,
                headingRowColor:
                    WidgetStateProperty.all(Colors.orange.shade50),
                headingTextStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: context.accR.financialSmall,
                    color: Colors.black87),
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('العميل')),
                  DataColumn(label: Text('الباقة')),
                  DataColumn(label: Text('مبلغنا')),
                  DataColumn(label: Text('مبلغ FTTH')),
                  DataColumn(label: Text('الفرق')),
                  DataColumn(label: Text('التاريخ')),
                ],
                rows: txs.asMap().entries.map((entry) {
                  final i = entry.key;
                  final w = entry.value;
                  final diff = w.ftthAmount - w.oursAmount;
                  final dateStr = _formatTxDate(w.ftthTx.occuredAt);
                  return DataRow(cells: [
                    DataCell(Text('${i + 1}',
                        style: TextStyle(fontSize: context.accR.small))),
                    DataCell(Text(w.ftthTx.customerName,
                        style: TextStyle(fontSize: context.accR.small))),
                    DataCell(Text(w.ftthTx.planName,
                        style: TextStyle(fontSize: context.accR.small))),
                    DataCell(Text(_currencyFormat.format(w.oursAmount),
                        style: TextStyle(
                            fontSize: context.accR.small,
                            fontWeight: FontWeight.w600))),
                    DataCell(Text(_currencyFormat.format(w.ftthAmount),
                        style: TextStyle(
                            fontSize: context.accR.small,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal.shade700))),
                    DataCell(Text(
                        (diff > 0 ? '+' : '') +
                            _currencyFormat.format(diff),
                        style: TextStyle(
                            fontSize: context.accR.small,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700))),
                    DataCell(Text(dateStr,
                        style: TextStyle(fontSize: context.accR.small))),
                  ]);
                }).toList(),
              ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  void _showCompareTransactions(_ComparisonRow row) {
    final txs = row.ftthTransactions;
    if (txs.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.compare_arrows, color: Colors.teal.shade700),
              SizedBox(width: context.accR.spaceS),
              Expanded(
                child: Text(
                  'عمليات ناقصة — ${row.operatorName} (${txs.length})',
                  style: GoogleFonts.cairo(
                      fontSize: context.accR.headingSmall,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width * 0.9 : 900,
            height: 500,
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                border: TableBorder.all(color: Colors.grey.shade300),
                dataRowMinHeight: 28,
                dataRowMaxHeight: 40,
                headingRowHeight: 32,
                columnSpacing: 12,
                horizontalMargin: 8,
                headingRowColor:
                    WidgetStateProperty.all(Colors.teal.shade50),
                headingTextStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: context.accR.financialSmall,
                    color: Colors.black87),
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('العميل')),
                  DataColumn(label: Text('الباقة')),
                  DataColumn(label: Text('النوع')),
                  DataColumn(label: Text('المبلغ')),
                  DataColumn(label: Text('التاريخ')),
                ],
                rows: txs.asMap().entries.map((entry) {
                  final i = entry.key;
                  final tx = entry.value;
                  final dateStr = _formatTxDate(tx.occuredAt);
                  return DataRow(cells: [
                    DataCell(Text('${i + 1}',
                        style:
                            TextStyle(fontSize: context.accR.small))),
                    DataCell(Text(tx.customerName,
                        style:
                            TextStyle(fontSize: context.accR.small))),
                    DataCell(Text(tx.planName,
                        style:
                            TextStyle(fontSize: context.accR.small))),
                    DataCell(Text(_translateType(tx.type),
                        style:
                            TextStyle(fontSize: context.accR.small))),
                    DataCell(Text(
                        _currencyFormat.format(tx.amount.abs()),
                        style: TextStyle(
                            fontSize: context.accR.small,
                            fontWeight: FontWeight.w600))),
                    DataCell(Text(dateStr,
                        style:
                            TextStyle(fontSize: context.accR.small))),
                  ]);
                }).toList(),
              ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _syncSpecificTransactions(txs, row.operatorName, row.operatorUserId);
              },
              icon: Icon(Icons.sync, size: context.accR.iconM),
              label: Text('مزامنة ${txs.length} عملية → خادمنا'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _syncSpecificTransactions(
      List<_FtthTransaction> txs, String operatorName, String? operatorUserId) async {
    final txList = txs
        .map((tx) => {
              'ftthTransactionId': tx.id,
              'customerId': tx.customerId,
              'customerName': tx.customerName,
              'subscriptionId': tx.subscriptionId,
              'planName': tx.planName,
              'amount': tx.amount,
              'operationType': tx.type,
              'createdBy': tx.auditCreator,
              'occuredAt': tx.occuredAt,
              'zoneId': tx.zoneId,
              'deviceUsername': tx.deviceUsername,
              'collectionType': _mapPaymentMode(tx.paymentMode),
              'paymentMethod': tx.paymentMethod,
              if (tx.startsAt.isNotEmpty && DateTime.tryParse(tx.startsAt) != null) 'startDate': DateTime.tryParse(tx.startsAt)!.toIso8601String(),
              if (tx.endsAt.isNotEmpty && DateTime.tryParse(tx.endsAt) != null) 'endDate': DateTime.tryParse(tx.endsAt)!.toIso8601String(),
              'remainingBalance': tx.remainingBalance,
              if (tx.planDuration > 0) 'commitmentPeriod': tx.planDuration,
              'createAccounting': true,
              if (operatorUserId != null) 'operatorUserId': operatorUserId,
            })
        .toList();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('جاري مزامنة ${txList.length} عملية لـ $operatorName...'),
          backgroundColor: Colors.teal,
          duration: const Duration(seconds: 10),
        ),
      );
    }

    try {
      final result = await AccountingService.instance.syncFtthTransactions(
        companyId: _companyId,
        transactions: txList,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        final success = result['success'] == true;
        final data = result['data'];
        final saved = data is Map
            ? data['saved'] ?? result['saved'] ?? 0
            : result['saved'] ?? 0;
        final skipped = data is Map
            ? data['skipped'] ?? result['skipped'] ?? 0
            : result['skipped'] ?? 0;
        final failed = data is Map
            ? data['failed'] ?? result['failed'] ?? 0
            : result['failed'] ?? 0;
        final updated = data is Map
            ? data['updated'] ?? result['updated'] ?? 0
            : result['updated'] ?? 0;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '$operatorName: $saved محفوظ، ${updated > 0 ? '$updated محدّث، ' : ''}$skipped موجود مسبقاً، $failed فشل'
                  : result['message'] ?? 'خطأ في المزامنة',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );

        if (success) {
          _loadOursData();
          _comparisonRows.clear();
          _buildComparison();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildCompareTable() {
    if (_comparisonRows.isEmpty) {
      return _emptyCard('لا توجد بيانات للمقارنة');
    }

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        side: const BorderSide(color: Colors.black, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(context.accR.spaceL),
            child: Row(
              children: [
                if (_ftthAuthenticated)
                  IconButton(
                    icon: Icon(Icons.cloud_download, size: context.accR.iconM, color: Colors.teal),
                    onPressed: _syncFtthToOurServer,
                    tooltip: 'مزامنة FTTH → خادمنا',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32),
                  ),
                Spacer(),
                Text('مقارنة المشغلين (${_comparisonRows.length})',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.body,
                        fontWeight: FontWeight.w600)),
                Spacer(),
                IconButton(
                  icon: Icon(Icons.refresh, size: context.accR.iconM),
                  onPressed: () {
                    _comparisonRows.clear();
                    _buildComparison();
                  },
                  tooltip: 'إعادة بناء المقارنة',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                  ),
                  child: DataTable(
                    border: TableBorder.all(color: Colors.black, width: 1.5),
                    dividerThickness: 0,
                    headingRowColor:
                        WidgetStateProperty.all(Colors.indigo.shade50),
                    dataRowMinHeight: 28,
                    dataRowMaxHeight: 36,
                    headingRowHeight: 32,
                    columnSpacing: 0,
                    horizontalMargin: 8,
                    headingTextStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: context.accR.financialSmall,
                        color: Colors.black87),
                    columns: [
                      DataColumn(
                          label: Expanded(child: Center(child: Text('#'))),
                          numeric: true),
                      DataColumn(
                          label:
                              Expanded(child: Center(child: Text('المشغل')))),
                      DataColumn(
                          label:
                              Expanded(child: Center(child: Text('عملياتنا')))),
                      DataColumn(
                          label:
                              Expanded(child: Center(child: Text('المستقطع')))),
                      DataColumn(
                          label: Expanded(
                              child: Center(child: Text('عمليات FTTH')))),
                      DataColumn(
                          label: Expanded(
                              child: Center(child: Text('مبالغ FTTH')))),
                      DataColumn(
                          label: Expanded(
                              child: Center(child: Text('ناقصة')))),
                      DataColumn(
                          label: Expanded(
                              child: Center(child: Text('خاطئة')))),
                      DataColumn(
                          label: Expanded(
                              child: Center(child: Text('فرق المبالغ')))),
                      DataColumn(
                          label:
                              Expanded(child: Center(child: Text('مطابقة')))),
                      DataColumn(
                          label: Expanded(
                              child: Center(child: Text('عندنا فقط')))),
                      DataColumn(
                          label:
                              Expanded(child: Center(child: Text('FTTH فقط')))),
                      DataColumn(
                          label:
                              Expanded(child: Center(child: Text('النسبة')))),
                    ],
                    rows: _comparisonRows.asMap().entries.map((entry) {
                      final i = entry.key;
                      final row = entry.value;
                      final total = row.matchedCount +
                          row.oursOnlyCount +
                          row.ftthOnlyCount;
                      final percent = total > 0
                          ? (row.matchedCount / total * 100).toStringAsFixed(0)
                          : '0';

                      final rowColor =
                          row.oursOnlyCount == 0 && row.ftthOnlyCount == 0
                              ? Colors.green.shade50
                              : (row.matchedCount == 0
                                  ? Colors.red.shade50
                                  : Colors.orange.shade50);

                      return DataRow(
                        color: WidgetStateProperty.all(rowColor),
                        cells: [
                          DataCell(Center(
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      fontSize: context.accR.small,
                                      fontWeight: FontWeight.w600)))),
                          DataCell(Center(
                              child: Text(row.operatorName,
                                  style: TextStyle(
                                      fontSize: context.accR.small,
                                      fontWeight: FontWeight.w700)))),
                          DataCell(Center(
                              child: Text('${row.oursCount}',
                                  style: TextStyle(
                                      fontSize: context.accR.small,
                                      fontWeight: FontWeight.w600)))),
                          DataCell(Center(
                              child: Text(
                            _currencyFormat.format(row.oursAmount),
                            style: TextStyle(
                                fontSize: context.accR.small,
                                fontWeight: FontWeight.w600),
                          ))),
                          DataCell(Center(
                              child: Text('${row.ftthCount}',
                                  style: TextStyle(
                                      fontSize: context.accR.small,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.teal.shade700)))),
                          DataCell(Center(
                              child: Text(
                            _currencyFormat.format(row.ftthAmount),
                            style: TextStyle(
                                fontSize: context.accR.small,
                                fontWeight: FontWeight.w600,
                                color: Colors.teal.shade700),
                          ))),
                          DataCell(
                              Center(
                                  child: Text(
                                row.ftthTransactions.isEmpty
                                    ? '0'
                                    : '${row.ftthTransactions.length}',
                                style: TextStyle(
                                    fontSize: context.accR.small,
                                    fontWeight: FontWeight.bold,
                                    color: row.ftthTransactions.isEmpty
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
                                    decoration: row.ftthTransactions.isNotEmpty
                                        ? TextDecoration.underline
                                        : null),
                              )),
                              onTap: row.ftthTransactions.isNotEmpty
                                  ? () => _showCompareTransactions(row)
                                  : null),
                          // خاطئة
                          DataCell(
                              Center(
                                  child: Text(
                                row.wrongTransactions.isEmpty
                                    ? '0'
                                    : '${row.wrongTransactions.length}',
                                style: TextStyle(
                                    fontSize: context.accR.small,
                                    fontWeight: FontWeight.bold,
                                    color: row.wrongTransactions.isEmpty
                                        ? Colors.green.shade700
                                        : Colors.orange.shade700,
                                    decoration:
                                        row.wrongTransactions.isNotEmpty
                                            ? TextDecoration.underline
                                            : null),
                              )),
                              onTap: row.wrongTransactions.isNotEmpty
                                  ? () => _showWrongTransactions(row)
                                  : null),
                          // فرق المبالغ (ناقصة + زيادة عندنا)
                          DataCell(Center(
                              child: () {
                            final missingAmount = row.ftthTransactions.fold<double>(
                                0, (s, tx) => s + tx.amount.abs());
                            final amountDiff = row.oursAmount - row.ftthAmount;
                            // إذا عندنا زيادة في المبالغ (أزرق)، أو FTTH عنده زيادة (أحمر)
                            if (missingAmount > 0) {
                              // FTTH عنده معاملات ناقصة عندنا
                              return Text(
                                '-${_currencyFormat.format(missingAmount)}',
                                style: TextStyle(
                                    fontSize: context.accR.small,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700),
                              );
                            } else if (amountDiff > 0) {
                              // عندنا زيادة في المبالغ
                              return Text(
                                '+${_currencyFormat.format(amountDiff)}',
                                style: TextStyle(
                                    fontSize: context.accR.small,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700),
                              );
                            } else if (amountDiff < 0) {
                              return Text(
                                _currencyFormat.format(amountDiff),
                                style: TextStyle(
                                    fontSize: context.accR.small,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700),
                              );
                            }
                            return Text(
                              '0',
                              style: TextStyle(
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700),
                            );
                          }())),
                          DataCell(Center(
                              child: Text('${row.matchedCount}',
                                  style: TextStyle(
                                      fontSize: context.accR.small,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700)))),
                          DataCell(Center(
                              child: Text(
                            '${row.oursOnlyCount}',
                            style: TextStyle(
                                fontSize: context.accR.small,
                                fontWeight: row.oursOnlyCount > 0
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: row.oursOnlyCount > 0
                                    ? Colors.blue.shade700
                                    : Colors.grey),
                          ))),
                          DataCell(Center(
                              child: Text(
                            '${row.ftthOnlyCount}',
                            style: TextStyle(
                                fontSize: context.accR.small,
                                fontWeight: row.ftthOnlyCount > 0
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: row.ftthOnlyCount > 0
                                    ? Colors.red.shade700
                                    : Colors.grey),
                          ))),
                          DataCell(Center(child: _buildMatchBadge(percent))),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMatchBadge(String percent) {
    final p = int.tryParse(percent) ?? 0;
    Color bg, fg;
    if (p == 100) {
      bg = Colors.green.shade100;
      fg = Colors.green.shade800;
    } else if (p >= 70) {
      bg = Colors.orange.shade100;
      fg = Colors.orange.shade800;
    } else {
      bg = Colors.red.shade100;
      fg = Colors.red.shade800;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
      ),
      child: Text('$percent%',
          style: TextStyle(
              fontSize: context.accR.small,
              fontWeight: FontWeight.bold,
              color: fg)),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  SHARED WIDGETS
  // ════════════════════════════════════════════════════════════════

  /// بطاقة رئيسية (إجمالي / سالب / موجب)
  Widget _summaryCardMain(
      String title, double value, String subtitle, Color color, IconData icon,
      {bool isCount = false}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        side: const BorderSide(color: Colors.black, width: 2),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: context.accR.spaceM, vertical: context.accR.spaceM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: context.accR.iconS, color: color),
                SizedBox(width: context.accR.spaceXS),
                Flexible(
                  child: Text(title,
                      style: GoogleFonts.cairo(
                          fontSize: context.accR.small,
                          fontWeight: FontWeight.w600,
                          color: color),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            SizedBox(height: context.accR.spaceXS),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                isCount
                    ? '${value.toInt()}'
                    : '${_currencyFormat.format(value)} د.ع',
                style: GoogleFonts.cairo(
                    fontSize: context.accR.headingSmall,
                    fontWeight: FontWeight.bold,
                    color: color),
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(subtitle,
                  style: TextStyle(
                      fontSize: context.accR.caption,
                      color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  /// بطاقة صغيرة (شراء، تجديد، إلخ)
  Widget _miniCard(String label, int count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: context.accR.iconS, color: color),
            SizedBox(height: 2),
            Text('$count',
                style: TextStyle(
                    fontSize: context.accR.body,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                style: TextStyle(fontSize: context.accR.caption, color: color),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  /// بطاقة ملخص عامة (تُستخدم في تاب خادمنا)
  Widget _summaryCard(String title, double value, String subtitle, Color color,
      {IconData? icon, bool isCount = false}) {
    final isMobile = context.accR.isMobile;
    final pad = isMobile ? 6.0 : context.accR.spaceL;
    final iconSz = isMobile ? 16.0 : context.accR.iconM;
    final titleFs = isMobile ? 10.0 : context.accR.small;
    final valueFs = isMobile ? 13.0 : context.accR.headingSmall;
    final subFs = isMobile ? 8.0 : context.accR.caption;
    return Card(
      elevation: isMobile ? 1 : 2,
      margin: isMobile ? const EdgeInsets.all(0) : null,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(isMobile ? 8 : context.accR.cardRadius),
        side: const BorderSide(color: Colors.black, width: 2),
      ),
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: iconSz, color: color),
                  SizedBox(width: isMobile ? 3 : context.accR.spaceXS),
                ],
                Text(title,
                    style: GoogleFonts.cairo(
                        fontSize: titleFs,
                        fontWeight: FontWeight.w600,
                        color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
            SizedBox(height: isMobile ? 2 : context.accR.spaceS),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                isCount
                    ? '${value.toInt()}'
                    : '${_currencyFormat.format(value)} د.ع',
                style: GoogleFonts.cairo(
                    fontSize: valueFs,
                    fontWeight: FontWeight.bold,
                    color: color),
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              SizedBox(height: isMobile ? 1 : context.accR.spaceXS),
              Text(subtitle,
                  style:
                      TextStyle(fontSize: subFs, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(String text) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(context.accR.spaceXXL),
        child: Center(
          child: Text(text, style: TextStyle(color: Colors.grey.shade500)),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(String error, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: context.accR.iconXL, color: Colors.red.shade300),
          SizedBox(height: context.accR.spaceM),
          Text(error, style: TextStyle(color: Colors.red.shade700)),
          SizedBox(height: context.accR.spaceM),
          ElevatedButton(
              onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  DATE FILTER — شريط فلتر سريع
  // ════════════════════════════════════════════════════════════════

  Widget _buildQuickDateFilter() {
    final isMobile = context.accR.isMobile;
    final isCustomDate = _dateLabel.contains('/') || _dateLabel.contains('-');

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : context.accR.spaceM,
          vertical: context.accR.spaceS),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Icon(Icons.filter_alt,
                size: context.accR.iconS, color: Colors.grey.shade600),
            SizedBox(width: context.accR.spaceS),
            _filterChip('اليوم', 'اليوم'),
            SizedBox(width: context.accR.spaceXS),
            _filterChip('أمس', 'أمس'),
            SizedBox(width: context.accR.spaceXS),
            _filterChip('اليوم + أمس', 'اليوم + أمس'),
            SizedBox(width: context.accR.spaceXS),
            _filterChip('آخر 7 أيام', 'آخر 7 أيام'),
            SizedBox(width: context.accR.spaceXS),
            _filterChip('هذا الشهر', 'هذا الشهر'),
            SizedBox(width: context.accR.spaceXS),
            _filterChip('الكل', 'الكل'),
            SizedBox(width: context.accR.spaceM),
            // زر اختيار مخصص
            InkWell(
              onTap: _showCustomDatePicker,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 8 : context.accR.spaceM,
                    vertical: context.accR.spaceXS),
                decoration: BoxDecoration(
                  color: isCustomDate
                      ? AccountingTheme.neonBlue
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCustomDate
                        ? AccountingTheme.neonBlue
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_month,
                        size: context.accR.iconS,
                        color:
                            isCustomDate ? Colors.white : Colors.grey.shade600),
                    SizedBox(width: context.accR.spaceXS),
                    Text(
                      isCustomDate ? _dateLabel : 'مخصص',
                      style: TextStyle(
                        fontSize: context.accR.small,
                        fontWeight: FontWeight.w600,
                        color:
                            isCustomDate ? Colors.white : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!isMobile) ...[
              SizedBox(width: context.accR.spaceM),
              // عرض النطاق الحالي
              if (_fromDate != null && _toDate != null)
                Text(
                  '${DateFormat('MM/dd').format(_fromDate!)} - ${DateFormat('MM/dd').format(_toDate!)}',
                  style: TextStyle(
                      fontSize: context.accR.caption,
                      color: Colors.grey.shade500),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String filterKey) {
    final isSelected = _dateLabel == filterKey;
    return InkWell(
      onTap: () => _applyDateFilter(filterKey),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: context.accR.spaceM, vertical: context.accR.spaceXS),
        decoration: BoxDecoration(
          color: isSelected ? AccountingTheme.neonBlue : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AccountingTheme.neonBlue : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: context.accR.small,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  void _applyDateFilter(String filterKey) {
    final now = DateTime.now();
    setState(() {
      switch (filterKey) {
        case 'اليوم':
          _fromDate = DateTime(now.year, now.month, now.day);
          _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          _dateLabel = 'اليوم';
          break;
        case 'أمس':
          final yesterday = now.subtract(const Duration(days: 1));
          _fromDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
          _toDate = DateTime(
              yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
          _dateLabel = 'أمس';
          break;
        case 'اليوم + أمس':
          final yesterday = now.subtract(const Duration(days: 1));
          _fromDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
          _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          _dateLabel = 'اليوم + أمس';
          break;
        case 'آخر 7 أيام':
          _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          _fromDate = _toDate!.subtract(const Duration(days: 7));
          _dateLabel = 'آخر 7 أيام';
          break;
        case 'هذا الشهر':
          _fromDate = DateTime(now.year, now.month, 1);
          _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          _dateLabel = 'هذا الشهر';
          break;
        case 'الكل':
          _fromDate = null;
          _toDate = null;
          _dateLabel = 'الكل';
          break;
      }
    });
    _comparisonRows.clear();
    _refreshAll();
  }

  Future<void> _showCustomDatePicker() async {
    final now = DateTime.now();
    final initialRange = (_fromDate != null && _toDate != null)
        ? DateTimeRange(start: _fromDate!, end: _toDate!)
        : DateTimeRange(
            start: now.subtract(const Duration(days: 1)),
            end: now,
          );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: initialRange,
      locale: const Locale('ar'),
    );

    if (picked != null && mounted) {
      setState(() {
        _fromDate = picked.start;
        _toDate = DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
        _dateLabel =
            '${DateFormat('MM/dd').format(picked.start)} - ${DateFormat('MM/dd').format(picked.end)}';
      });
      _comparisonRows.clear();
      _refreshAll();
    }
  }
}

// ════════════════════════════════════════════════════════════════
//  DATA MODELS
// ════════════════════════════════════════════════════════════════

/// زر تبويب بسيط للجداول
class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? Colors.indigo.shade700;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? activeColor : Colors.grey.shade400,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? Colors.white : activeColor),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : activeColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════

/// بيانات مشغل مجمعة من خادم FTTH
class _FtthOperatorData {
  final String name;
  int totalCount = 0;
  double totalAmount = 0;
  double negativeAmount = 0;
  double positiveAmount = 0;
  int subscriptionOps = 0;
  int purchaseOps = 0;
  int renewOps = 0;
  int changeOps = 0;
  int scheduleOps = 0;
  int commissionOps = 0;
  int reversalOps = 0;
  int walletOps = 0;
  int otherOps = 0;
  int attributedOps = 0; // عمليات منسوبة تلقائياً من "بدون منشئ"
  double totalDiscount =
      0; // إجمالي الخصومات (الفرق بين السعر الحقيقي والمبلغ الفعلي)
  Map<String, int> typeCounts = {};
  List<_FtthTransaction> transactions = [];

  _FtthOperatorData({required this.name});

  /// أنواع التجديد والتغيير فقط (بدون الشراء - له أسعار مختلفة)
  static const _renewChangeTypes = {
    'PLAN_RENEW',
    'AUTO_RENEW',
    'PLAN_EMI_RENEW',
    'PLAN_CHANGE',
    'SCHEDULE_CHANGE',
    'PLAN_SCHEDULE',
  };

  /// Purchase types
  static const _purchaseTypes = {
    'PLAN_PURCHASE',
    'PurchaseSubscriptionFromTrial',
    'PLAN_SUBSCRIBE',
  };

  /// حساب مبلغ الشراء (المبالغ السالبة لعمليات الشراء فقط)
  double calcPurchaseAmount() {
    double total = 0;
    for (final tx in transactions) {
      if (_purchaseTypes.contains(tx.type) && tx.amount < 0) {
        total += tx.amount.abs();
      }
    }
    return total;
  }

  /// حساب مبلغ التجديد والتغيير (المبالغ السالبة لعمليات التجديد والتغيير)
  double calcRenewChangeAmount() {
    double total = 0;
    for (final tx in transactions) {
      if (_renewChangeTypes.contains(tx.type) && tx.amount < 0) {
        total += tx.amount.abs();
      }
    }
    return total;
  }

  /// حساب مبلغ عمليات الجدولة (PLAN_SCHEDULE فقط)
  double calcScheduleAmount() {
    double total = 0;
    for (final tx in transactions) {
      if (tx.type == 'PLAN_SCHEDULE' && tx.amount < 0) {
        total += tx.amount.abs();
      }
    }
    return total;
  }

  /// حساب إجمالي الخصومات من أسعار الباقات
  double calcTotalDiscount() {
    double disc = 0;
    final pricing = PlanPricingService.instance;
    for (final tx in transactions) {
      if (tx.planName.isEmpty) continue;
      // فقط عمليات التجديد والتغيير (الشراء له أسعار مختلفة)
      if (!_renewChangeTypes.contains(tx.type)) continue;
      final d = pricing.getDiscount(tx.planName, tx.amount);
      if (d != null) disc += d;
    }
    return disc;
  }

  static String _categorizeTxType(String type) {
    const sub = {
      'PLAN_PURCHASE',
      'PurchaseSubscriptionFromTrial',
      'PLAN_SUBSCRIBE',
      'PLAN_RENEW',
      'AUTO_RENEW',
      'PLAN_EMI_RENEW',
      'PLAN_CHANGE',
      'SCHEDULE_CHANGE',
      'PLAN_SCHEDULE'
    };
    const comm = {
      'PARTNER_COMMISSION',
      'CommissionAdjustment',
      'PLAN_COMMISSION',
      'COMMISSION_DEDUCTION',
      'REFILL_TEAM_MEMBER_BALANCE',
      'ADD_BALANCE'
    };
    const rev = {'RENEW_REVERSE', 'REVERSE_COMMISSION'};
    const wal = {
      'WALLET_RECHARGE',
      'REFUND_BALANCE',
      'DEDUCT_BALANCE',
      'ADJUST_BALANCE',
      'REFILL_BALANCE',
      'WALLET_TRANSFER'
    };
    if (sub.contains(type)) return 'subscription';
    if (comm.contains(type)) return 'commission';
    if (rev.contains(type)) return 'reversal';
    if (wal.contains(type)) return 'wallet';
    return 'other';
  }
}

/// معاملة FTTH مفردة
class _FtthTransaction {
  final String id;
  final String type;
  final double amount;
  final String subscriptionId;
  final String customerName;
  final String customerId;
  final String planName;
  final String occuredAt;
  final String createdBy;
  final String zoneId;
  final String deviceUsername;
  String auditCreator; // المنشئ المستخرج من audit-logs
  final int planDuration; // مدة الاشتراك بالأيام
  final double remainingBalance; // الرصيد المتبقي بعد العملية
  final String paymentMode; // طريقة الدفع
  final String paymentMethod; // نوع الدفع
  final String startsAt; // بداية الاشتراك
  final String endsAt; // نهاية الاشتراك

  _FtthTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.subscriptionId,
    required this.customerName,
    required this.customerId,
    required this.planName,
    required this.occuredAt,
    required this.createdBy,
    this.zoneId = '',
    this.deviceUsername = '',
    this.auditCreator = '',
    this.planDuration = 0,
    this.remainingBalance = 0.0,
    this.paymentMode = '',
    this.paymentMethod = '',
    this.startsAt = '',
    this.endsAt = '',
  });
}

/// عملية بمبلغ خاطئ (موجودة عندنا لكن المبلغ مختلف)
class _WrongTransaction {
  final _FtthTransaction ftthTx;
  final int oursAmount;
  final int ftthAmount;

  _WrongTransaction({
    required this.ftthTx,
    required this.oursAmount,
    required this.ftthAmount,
  });
}

/// صف مقارنة بين النظامين
class _ComparisonRow {
  final String operatorName;
  final String? operatorUserId;
  final int oursCount;
  final double oursAmount;
  final int ftthCount;
  final double ftthAmount;
  final int matchedCount;
  final int oursOnlyCount;
  final int ftthOnlyCount;
  final List<_FtthTransaction> ftthTransactions;
  final List<_WrongTransaction> wrongTransactions;

  _ComparisonRow({
    required this.operatorName,
    this.operatorUserId,
    required this.oursCount,
    required this.oursAmount,
    required this.ftthCount,
    required this.ftthAmount,
    required this.matchedCount,
    required this.oursOnlyCount,
    required this.ftthOnlyCount,
    this.ftthTransactions = const [],
    this.wrongTransactions = const [],
  });
}

// ══════════════════════════════════════════════════════════════════
//  صفحة الفريق - شاشة كاملة
// ══════════════════════════════════════════════════════════════════
class _FtthTeamPage extends StatefulWidget {
  const _FtthTeamPage();

  @override
  State<_FtthTeamPage> createState() => _FtthTeamPageState();
}

class _FtthTeamPageState extends State<_FtthTeamPage> {
  final _currencyFormat = NumberFormat('#,##0', 'en_US');
  List<Map<String, dynamic>> _teamList = [];
  bool _isLoading = true;
  String? _error;
  int _totalCount = 0;
  String _filterRole = 'الكل';

  @override
  void initState() {
    super.initState();
    _loadTeam();
  }

  Future<void> _loadTeam() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await AuthService.instance.authenticatedRequest(
          'GET', 'https://admin.ftth.iq/api/teams/members');
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _teamList = List<Map<String, dynamic>>.from(data['items'] ?? []);
          _totalCount = data['totalCount'] ?? _teamList.length;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'خطأ ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'حدث خطأ';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredList {
    if (_filterRole == 'الكل') return _teamList;
    return _teamList.where((m) {
      final role = (m['role'] as Map?)?['displayValue']?.toString() ?? '';
      return role == _filterRole;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // حساب الملخصات
    double totalBalance = 0;
    int withWallet = 0;
    final roleCounts = <String, int>{};
    for (final m in _teamList) {
      final wallet = m['walletSetup'] as Map<String, dynamic>?;
      if (wallet != null) {
        totalBalance += (wallet['balance'] as num?)?.toDouble() ?? 0;
        if (wallet['hasWallet'] == true) withWallet++;
      }
      final role =
          (m['role'] as Map?)?['displayValue']?.toString() ?? 'غير محدد';
      roleCounts[role] = (roleCounts[role] ?? 0) + 1;
    }

    final filtered = _filteredList;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('الفريق ($_totalCount عضو)',
              style: TextStyle(
                  fontSize: context.accR.headingSmall,
                  fontWeight: FontWeight.bold)),
          backgroundColor: Colors.teal.shade700,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: Icon(Icons.refresh, size: context.accR.iconM),
              onPressed: _loadTeam,
              tooltip: 'تحديث',
            ),
            SizedBox(width: context.accR.spaceS),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: context.accR.iconXL,
                            color: Colors.red.shade300),
                        SizedBox(height: context.accR.spaceM),
                        Text(_error!,
                            style: TextStyle(color: Colors.red.shade700)),
                        SizedBox(height: context.accR.spaceM),
                        ElevatedButton.icon(
                          onPressed: _loadTeam,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // بطاقات الملخص
                      Padding(
                        padding: EdgeInsets.all(context.accR.spaceM),
                        child: context.accR.isMobile
                            ? Column(
                                children: [
                                  Row(
                                    children: [
                                      _summaryCard(
                                          'إجمالي الأعضاء',
                                          '$_totalCount',
                                          Icons.people,
                                          Colors.teal),
                                      SizedBox(width: context.accR.spaceS),
                                      _summaryCard(
                                          'لديهم محفظة',
                                          '$withWallet',
                                          Icons.account_balance_wallet,
                                          Colors.blue),
                                    ],
                                  ),
                                  SizedBox(height: context.accR.spaceS),
                                  Row(
                                    children: [
                                      _summaryCard(
                                          'إجمالي الأرصدة',
                                          _currencyFormat.format(totalBalance),
                                          Icons.monetization_on,
                                          totalBalance >= 0
                                              ? Colors.green
                                              : Colors.red),
                                    ],
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  _summaryCard('إجمالي الأعضاء', '$_totalCount',
                                      Icons.people, Colors.teal),
                                  SizedBox(width: context.accR.spaceS),
                                  _summaryCard(
                                      'لديهم محفظة',
                                      '$withWallet',
                                      Icons.account_balance_wallet,
                                      Colors.blue),
                                  SizedBox(width: context.accR.spaceS),
                                  _summaryCard(
                                      'إجمالي الأرصدة',
                                      _currencyFormat.format(totalBalance),
                                      Icons.monetization_on,
                                      totalBalance >= 0
                                          ? Colors.green
                                          : Colors.red),
                                ],
                              ),
                      ),
                      // فلتر الأدوار
                      Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: context.accR.spaceM),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _roleChip('الكل', _teamList.length),
                              ...roleCounts.entries
                                  .map((e) => _roleChip(e.key, e.value)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: context.accR.spaceS),
                      // الجدول
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: context.accR.spaceM),
                          child: SingleChildScrollView(
                            child: _buildTable(filtered),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _roleChip(String label, int count) {
    final isSelected = _filterRole == label;
    return Padding(
      padding: EdgeInsets.only(left: 6),
      child: FilterChip(
        label: Text('$label ($count)',
            style: TextStyle(
                fontSize: context.accR.small,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.teal.shade800)),
        selected: isSelected,
        selectedColor: Colors.teal.shade600,
        backgroundColor: Colors.teal.shade50,
        onSelected: (_) => setState(() => _filterRole = label),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: context.accR.spaceM, vertical: context.accR.spaceM),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(context.accR.cardRadius),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: context.accR.iconM),
            SizedBox(width: context.accR.spaceM),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: context.accR.small,
                        color: Colors.grey.shade600)),
                Text(value,
                    style: TextStyle(
                        fontSize: context.accR.body,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> list) {
    if (list.isEmpty) return const Center(child: Text('لا توجد بيانات'));

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: 600),
          child: DataTable(
            border: TableBorder.all(color: Colors.black, width: 1.5),
            dividerThickness: 0,
            columnSpacing: 0,
            horizontalMargin: 8,
            headingRowHeight: 42,
            dataRowMinHeight: 38,
            dataRowMaxHeight: 54,
            headingRowColor: WidgetStateProperty.all(Colors.teal.shade50),
            columns: [
              DataColumn(
                  label: Expanded(
                      child: Center(
                          child: Text('#',
                              style: TextStyle(
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.bold))))),
              DataColumn(
                  label: Expanded(
                      child: Center(
                          child: Text('المستخدم',
                              style: TextStyle(
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.bold))))),
              DataColumn(
                  label: Expanded(
                      child: Center(
                          child: Text('الاسم',
                              style: TextStyle(
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.bold))))),
              DataColumn(
                  label: Expanded(
                      child: Center(
                          child: Text('الهاتف',
                              style: TextStyle(
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.bold))))),
              DataColumn(
                  label: Expanded(
                      child: Center(
                          child: Text('الدور',
                              style: TextStyle(
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.bold))))),
              DataColumn(
                  label: Expanded(
                      child: Center(
                          child: Text('رئيسي',
                              style: TextStyle(
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.bold))))),
              DataColumn(
                  label: Expanded(
                      child: Center(
                          child: Text('المناطق',
                              style: TextStyle(
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.bold))))),
              DataColumn(
                  label: Expanded(
                      child: Center(
                          child: Text('محفظة',
                              style: TextStyle(
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.bold))))),
              DataColumn(
                  label: Expanded(
                      child: Center(
                          child: Text('الرصيد',
                              style: TextStyle(
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.bold))))),
            ],
            rows: list.asMap().entries.map((entry) {
              final i = entry.key;
              final m = entry.value;
              final role =
                  (m['role'] as Map?)?['displayValue']?.toString() ?? '-';
              final firstName = m['firstName']?.toString() ?? '';
              final lastName = m['lastName']?.toString() ?? '';
              final fullName = '$firstName $lastName'.trim();
              final phone = m['phoneNumber']?.toString() ?? '-';
              final username = m['username']?.toString() ?? '-';
              final isMain = m['isMainPartner'] == true;
              final zones = (m['zoneIds'] as List?)?.length ?? 0;
              final wallet = m['walletSetup'] as Map<String, dynamic>?;
              final hasWallet = wallet?['hasWallet'] == true;
              final balance = (wallet?['balance'] as num?)?.toDouble() ?? 0;

              Color roleColor;
              switch (role) {
                case 'Super Admin Member':
                  roleColor = Colors.red.shade700;
                  break;
                case 'Zone Admin':
                  roleColor = Colors.blue.shade700;
                  break;
                case 'Field Worker':
                  roleColor = Colors.green.shade700;
                  break;
                case 'Contractor':
                  roleColor = Colors.purple.shade700;
                  break;
                default:
                  roleColor = Colors.grey.shade700;
              }

              return DataRow(cells: [
                DataCell(Center(
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontSize: context.accR.small,
                            fontWeight: FontWeight.w600)))),
                DataCell(Center(
                    child: Text(username,
                        style: TextStyle(
                            fontSize: context.accR.small,
                            fontWeight: FontWeight.w700)))),
                DataCell(Center(
                    child: Text(fullName.isNotEmpty ? fullName : '-',
                        style: TextStyle(fontSize: context.accR.small)))),
                DataCell(Center(
                    child: Text(phone,
                        style: TextStyle(fontSize: context.accR.small)))),
                DataCell(Center(
                    child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(role,
                      style: TextStyle(
                          fontSize: context.accR.small,
                          fontWeight: FontWeight.w600,
                          color: roleColor)),
                ))),
                DataCell(Center(
                    child: Text(isMain ? '✅' : '',
                        style: TextStyle(fontSize: context.accR.small)))),
                DataCell(Center(
                    child: Text('$zones',
                        style: TextStyle(
                            fontSize: context.accR.small,
                            fontWeight: FontWeight.w600,
                            color: zones > 0
                                ? Colors.teal.shade700
                                : Colors.grey.shade400)))),
                DataCell(Center(
                    child: Text(hasWallet ? '✅' : '❌',
                        style: TextStyle(fontSize: context.accR.small)))),
                DataCell(Center(
                    child: Text(
                  _currencyFormat.format(balance),
                  style: TextStyle(
                      fontSize: context.accR.small,
                      fontWeight: FontWeight.w600,
                      color: balance > 0
                          ? Colors.green.shade700
                          : balance < 0
                              ? Colors.red.shade700
                              : Colors.grey.shade400),
                ))),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  صفحة كل العمليات — تعرض جميع سجلات SubscriptionLogs
// ═══════════════════════════════════════════════════════
class _AllOperationsPage extends StatefulWidget {
  final String companyId;
  final DateTime? fromDate;
  final DateTime? toDate;
  final List<String> operators;

  const _AllOperationsPage({
    required this.companyId,
    this.fromDate,
    this.toDate,
    this.operators = const [],
  });

  @override
  State<_AllOperationsPage> createState() => _AllOperationsPageState();
}

class _AllOperationsPageState extends State<_AllOperationsPage> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchCtrl = TextEditingController();
  final _fmt = NumberFormat('#,###', 'ar');
  final _dateFmt = DateFormat('yyyy/MM/dd');

  // ── Inline edit ──
  String? _editingId;
  final _editOperatorCtrl = TextEditingController();
  final _editPriceCtrl = TextEditingController();
  final _editTechnicianCtrl = TextEditingController();
  final _editAgentCtrl = TextEditingController();
  String _editCollType = 'cash';
  String _editPaymentMethod = '';
  bool _isSaving = false;

  // ── Linking ──
  Map<String, String> _linkingMap = {};
  Map<String, String> _reverseMap = {};

  // ── قوائم الموظفين للتعديل ──
  List<String> _staffTechnicians = [];
  List<String> _staffAgents = [];
  Map<String, String> _staffTechIdMap = {}; // name → id
  Map<String, String> _staffAgentIdMap = {}; // name → id
  bool _staffLoaded = false;

  // ── Sort ──
  String? _sortKey;
  bool _sortAsc = true;

  // ── Column filters: dataKey → Set of selected values (multi-select) ──
  final Map<String, Set<String>> _colFilters = {};

  // ── Multi-select rows ──
  final Set<String> _selectedIds = {};
  bool _isDeletingSelected = false;

  // ── Column visibility (saved locally) ──
  Set<String> _hiddenCols = {};
  static const _prefKey = 'allops_hidden_cols_v2';

  static const _baseUrl =
      'https://api.ramzalsadara.tech/api/internal/subscriptionlogs';
  static const _apiKey = 'sadara-internal-2024-secure-key';

  /// [label, dataKey, flex]  — flex يُستخدم لـ Expanded ويملأ الشاشة تلقائياً
  static const List<List<dynamic>> _cols = [
    ['☐',           '_check',           1],
    ['#',            '_idx',             1],
    ['التاريخ',     'تاريخ التفعيل',     3],
    ['المشغل',      'المُفعِّل',          4],
    ['العميل',      'اسم العميل',        5],
    ['الباقة',      'اسم الباقة',        3],
    ['المبلغ',      'سعر الباقة',        3],
    ['نوع العملية', 'نوع العملية',       3],
    ['التحصيل',     'نوع التحصيل',       3],
    ['الفني',       'الفني',             3],
    ['الوكيل',      'الوكيل',            3],
    ['المنطقة',     'اسم المنطقة',       2],
    ['الهاتف',      'رقم الهاتف',        3],
    ['بداية',       'تاريخ البدء',       3],
    ['نهاية',       'تاريخ الانتهاء',    3],
    ['ر.قبل',       'الرصيد قبل',        2],
    ['ر.بعد',       'الرصيد بعد',        2],
    ['FBG',         'fbg',               2],
    ['FAT',         'fat',               2],
    ['FDT',         'fdt',               2],
    ['ملاحظات',     'ملاحظات',           4],
    ['الحالة',      'الحالة الحالية',     2],
    ['✓',           '_icons',            2],
  ];

  List<List<dynamic>> get _visibleCols =>
      _cols.where((c) => !_hiddenCols.contains(c[1] as String)).toList();

  @override
  void initState() {
    super.initState();
    _loadColVisibility().then((_) {
      _load();
      _loadLinking();
    });
    _searchCtrl.addListener(_applyFilters);
  }

  Future<void> _loadColVisibility() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefKey);
      if (mounted && raw != null) setState(() => _hiddenCols = raw.toSet());
    } catch (_) {}
  }

  Future<void> _saveColVisibility() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKey, _hiddenCols.toList());
    } catch (_) {}
  }

  /// يفتح dialog لاختيار الأعمدة المرئية
  void _showColPickerDialog() {
    // نسخة مؤقتة للتعديل
    final tempHidden = Set<String>.from(_hiddenCols);

    showDialog(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setDlg) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            title: Row(children: [
              Icon(Icons.view_column, size: 20, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text('اختيار الأعمدة',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              TextButton(
                onPressed: () => setDlg(() => tempHidden.clear()),
                child: Text('إظهار الكل',
                    style: GoogleFonts.cairo(
                        color: Colors.teal.shade700, fontSize: 11)),
              ),
            ]),
            content: SizedBox(
              width: min(320, MediaQuery.of(context).size.width * 0.85),
              height: (_cols.length * 42.0).clamp(200, 500),
              child: ListView(
                children: _cols.map((col) {
                  final key   = col[1] as String;
                  final label = col[0] as String;
                  final isVisible = !tempHidden.contains(key);
                  // الأعمدة الأساسية لا يمكن إخفاؤها
                  final isCore = key == '_check' || key == '_idx' || key == '_icons';
                  return InkWell(
                    onTap: isCore ? null : () => setDlg(() {
                      if (isVisible) tempHidden.add(key);
                      else tempHidden.remove(key);
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 3, horizontal: 4),
                      child: Row(children: [
                        Checkbox(
                          value: isVisible,
                          onChanged: isCore ? null : (c) => setDlg(() {
                            if (c == true) tempHidden.remove(key);
                            else tempHidden.add(key);
                          }),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          activeColor: Colors.teal.shade700,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            label,
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              color: isCore
                                  ? Colors.grey.shade400
                                  : (isVisible
                                      ? Colors.black87
                                      : Colors.grey.shade500),
                              fontWeight: isVisible
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isCore)
                          Text('ثابت',
                              style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  color: Colors.grey.shade400)),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: Text('إلغاء', style: GoogleFonts.cairo()),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white),
                icon: const Icon(Icons.save, size: 16),
                onPressed: () {
                  Navigator.pop(dctx);
                  setState(() => _hiddenCols = tempHidden);
                  _saveColVisibility();
                },
                label: Text('حفظ', style: GoogleFonts.cairo()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadLinking() async {
    try {
      final result = await AccountingService.instance
          .getOperatorsLinking(companyId: widget.companyId);
      if (result['success'] != true) return;
      final raw = result['data'];
      List items = raw is List
          ? raw
          : (raw is Map && raw['data'] is List ? raw['data'] : []);
      final map = <String, String>{};
      final rev = <String, String>{};
      for (final e in items) {
        final ftth = (e['FtthUsername']?.toString() ?? '').toLowerCase();
        final name = e['FullName']?.toString() ?? '';
        if (ftth.isNotEmpty && name.isNotEmpty) {
          map[ftth] = name;
          rev[name] = ftth;
        }
      }
      if (mounted) setState(() { _linkingMap = map; _reverseMap = rev; });
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _editOperatorCtrl.dispose();
    _editPriceCtrl.dispose();
    super.dispose();
  }

  /// تحويل تاريخ UTC إلى التوقيت المحلي (العراق +3)
  static String _toLocalDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  /// استخراج اسم الفني/الوكيل من الاستجابة (يجرب عدة أسماء للحقل)
  static String _extractTechName(dynamic item) {
    // أسماء محتملة للحقل في الـ JSON
    for (final key in [
      'TechnicianName', 'LinkedTechnicianName', 'technicianName',
    ]) {
      final v = item[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    // navigation property موسّع
    if (item['LinkedTechnician'] is Map) {
      final m = item['LinkedTechnician'] as Map;
      final v = (m['FullName'] ?? m['fullName'] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    if (item['LinkedAgent'] is Map) {
      final m = item['LinkedAgent'] as Map;
      final v = (m['FullName'] ?? m['fullName'] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    // fallback: اسم الوكيل
    for (final key in ['AgentName', 'LinkedAgentName', 'agentName']) {
      final v = item[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      String url = '$_baseUrl?pageSize=2000';
      if (widget.companyId.isNotEmpty) url += '&companyId=${widget.companyId}';
      if (widget.fromDate != null) url += '&fromDate=${widget.fromDate!.toIso8601String().split('T')[0]}';
      if (widget.toDate != null) url += '&toDate=${widget.toDate!.toIso8601String().split('T')[0]}';

      final response = await http.get(Uri.parse(url), headers: {'X-Api-Key': _apiKey});
      if (response.statusCode != 200) {
        throw Exception('خطأ ${response.statusCode}: ${response.body}');
      }

      final body = jsonDecode(response.body);
      final List<dynamic> items = body is List
          ? body
          : ((body['data'] ?? body['items'] ?? []) as List<dynamic>);

      final result = items.map<Map<String, dynamic>>((item) {
        return {
          'id':               item['Id']?.toString() ?? '',
          'تاريخ التفعيل':   _toLocalDate(item['ActivationDate']?.toString()),
          'المُفعِّل':        item['ActivatedBy']?.toString() ?? '',
          'اسم العميل':      item['CustomerName']?.toString() ?? '',
          'اسم الباقة':      item['PlanName']?.toString() ?? '',
          'سعر الباقة':      item['PlanPrice']?.toString() ?? '',
          'نوع العملية':     _mapOperationType(item['OperationType']?.toString() ?? ''),
          'طريقة الدفع':     item['PaymentMethod']?.toString() ?? '',
          'الحالة الحالية':  item['CurrentStatus']?.toString() ?? '',
          'رقم الهاتف':      item['PhoneNumber']?.toString() ?? '',
          'اسم المنطقة':     item['ZoneName']?.toString() ?? '',
          'نوع التحصيل':     _mapCollectionType(item['CollectionType']?.toString() ?? ''),
          'نوع التحصيل_raw': item['CollectionType']?.toString() ?? '',
          'الرصيد قبل':      item['WalletBalanceBefore']?.toString() ?? '',
          'الرصيد بعد':      item['WalletBalanceAfter']?.toString() ?? '',
          'مطبوع':           item['IsPrinted'] == true,
          'واتساب':          item['IsWhatsAppSent'] == true,
          'اسم الجهاز':      item['DeviceUsername']?.toString() ?? '',
          'ملاحظات':         item['SubscriptionNotes']?.toString() ?? '',
          'تاريخ البدء':     _toLocalDate(item['StartDate']?.toString()),
          'تاريخ الانتهاء':  _toLocalDate(item['EndDate']?.toString()),
          'fbg':             item['FbgInfo']?.toString() ?? '',
          'fat':             item['FatInfo']?.toString() ?? '',
          'fdt':             item['FdtInfo']?.toString() ?? '',
          'الفني':           (item['CollectionType']?.toString() == 'technician')
              ? _extractTechName(item) : '',
          'الوكيل':          (item['CollectionType']?.toString() == 'agent')
              ? _extractTechName(item) : '',
          'linkedTechnicianId': item['LinkedTechnicianId']?.toString() ?? '',
          'linkedAgentId':      item['LinkedAgentId']?.toString() ?? '',
        };
      }).toList();

      if (mounted) {
        setState(() {
          _records = result;
          _selectedIds.clear();
          _isLoading = false;
        });
        _applyFiltersFromRecords(result);
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'حدث خطأ'; _isLoading = false; });
    }
  }

  void _applyFiltersFromRecords(List<Map<String, dynamic>> source) {
    final q = _searchCtrl.text.trim().toLowerCase();
    var result = source.where((r) {
      // بحث نصي عام
      if (q.isNotEmpty &&
          !r.values.any((v) => v.toString().toLowerCase().contains(q))) {
        return false;
      }
      // فلاتر الأعمدة (multi-select)
      for (final entry in _colFilters.entries) {
        final allowedVals = entry.value;
        if (allowedVals.isEmpty) continue;
        final rv = r[entry.key]?.toString() ?? '';
        if (!allowedVals.contains(rv)) return false;
      }
      return true;
    }).toList();

    if (_sortKey != null) {
      result.sort((a, b) {
        final av = a[_sortKey]?.toString() ?? '';
        final bv = b[_sortKey]?.toString() ?? '';
        final an = double.tryParse(av);
        final bn = double.tryParse(bv);
        final cmp = (an != null && bn != null)
            ? an.compareTo(bn)
            : av.compareTo(bv);
        return _sortAsc ? cmp : -cmp;
      });
    }
    setState(() => _filtered = result);
  }

  void _applyFilters() => _applyFiltersFromRecords(_records);

  void _onSortCol(String key) {
    if (_sortKey == key) {
      if (_sortAsc) {
        _sortAsc = false;
      } else {
        _sortKey = null;
        _sortAsc = true;
      }
    } else {
      _sortKey = key;
      _sortAsc = true;
    }
    _applyFiltersFromRecords(_records);
  }

  /// يفتح dialog تحديد متعدد للفلترة على عمود معين
  void _showFilterDialog(String key, String label) {
    final values = _records
        .map((r) => r[key]?.toString() ?? '')
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    if (values.isEmpty) return;

    // للمشغل: ترتيب القائمة حسب الاسم الحقيقي
    if (key == 'المُفعِّل') {
      values.sort((a, b) {
        final na = _linkingMap[a.toLowerCase()] ?? a;
        final nb = _linkingMap[b.toLowerCase()] ?? b;
        return na.compareTo(nb);
      });
    }

    final selected = Set<String>.from(_colFilters[key] ?? {});

    showDialog(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setDlg) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            title: Row(children: [
              Icon(Icons.filter_alt, size: 18, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text('فلتر: $label',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              TextButton(
                onPressed: () => setDlg(() => selected.clear()),
                child: Text('مسح الكل',
                    style: GoogleFonts.cairo(
                        color: Colors.red.shade600, fontSize: 11)),
              ),
            ]),
            content: SizedBox(
              width: min(300, MediaQuery.of(context).size.width * 0.85),
              height: (values.length * 44.0).clamp(100, 380),
              child: ListView(
                children: values.map((v) {
                  final isSelected = selected.contains(v);
                  // للمشغل: أظهر الاسم الحقيقي من _linkingMap
                  final displayText = key == 'المُفعِّل'
                      ? (_linkingMap[v.toLowerCase()] ?? v)
                      : v;
                  return InkWell(
                    onTap: () => setDlg(() {
                      if (isSelected) selected.remove(v);
                      else selected.add(v);
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Row(children: [
                        Checkbox(
                          value: isSelected,
                          onChanged: (c) => setDlg(() {
                            if (c == true) selected.add(v);
                            else selected.remove(v);
                          }),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          activeColor: Colors.teal.shade700,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(displayText,
                                  style: GoogleFonts.cairo(
                                      fontSize: 12,
                                      color: isSelected
                                          ? Colors.teal.shade800
                                          : Colors.black87,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal),
                                  overflow: TextOverflow.ellipsis),
                              // إظهار اسم المستخدم الأصلي كـ hint صغير إذا كان مختلفاً
                              if (key == 'المُفعِّل' && displayText != v)
                                Text(v,
                                    style: GoogleFonts.cairo(
                                        fontSize: 9,
                                        color: Colors.grey.shade500),
                                    overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: Text('إلغاء', style: GoogleFonts.cairo()),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.pop(dctx);
                  setState(() {
                    if (selected.isEmpty) {
                      _colFilters.remove(key);
                    } else {
                      _colFilters[key] = Set.from(selected);
                    }
                  });
                  _applyFiltersFromRecords(_records);
                },
                child: Text(
                    selected.isEmpty
                        ? 'إزالة الفلتر'
                        : 'تطبيق (${selected.length})',
                    style: GoogleFonts.cairo()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── حقل بحث وتصفية (Autocomplete) ──
  Widget _buildSearchableField({
    required TextEditingController controller,
    required List<String> options,
    required String hint,
  }) {
    return Autocomplete<String>(
      optionsBuilder: (textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty) return options;
        return options.where((o) => o.toLowerCase().contains(q));
      },
      initialValue: TextEditingValue(text: controller.text),
      onSelected: (v) {
        controller.text = v;
        setState(() {});
      },
      fieldViewBuilder: (ctx, fieldCtrl, focusNode, onSubmit) {
        return TextField(
          controller: fieldCtrl,
          focusNode: focusNode,
          style: GoogleFonts.cairo(fontSize: 10),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: GoogleFonts.cairo(fontSize: 9, color: Colors.grey),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.teal.shade600),
            ),
            suffixIcon: const Icon(Icons.search, size: 14),
            suffixIconConstraints: const BoxConstraints(maxWidth: 20, maxHeight: 20),
          ),
          onChanged: (v) => controller.text = v,
          onSubmitted: (_) { onSubmit(); _saveEditing(); },
        );
      },
      optionsViewBuilder: (ctx, onSelected, opts) {
        return Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180, maxWidth: 200),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: opts.length,
                itemBuilder: (_, i) {
                  final o = opts.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(o),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Text(o, style: GoogleFonts.cairo(fontSize: 11)),
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

  // ── ترجمة الحقول ──
  static String _mapCollectionType(String v) => switch (v) {
    'cash' => 'نقد', 'credit' => 'آجل', 'agent' => 'وكيل',
    'master' => 'ماستر', 'technician' => 'فني', _ => v,
  };
  static String _mapCollectionTypeReverse(String v) => switch (v) {
    'نقد' => 'cash', 'آجل' => 'credit', 'وكيل' => 'agent',
    'ماستر' => 'master', 'فني' => 'technician', _ => v,
  };
  static String _mapOperationType(String v) => switch (v) {
    'renewal' => 'تجديد', 'change' => 'تغيير', 'new' => 'جديد',
    'upgrade' => 'ترقية', 'downgrade' => 'تخفيض', 'cancel' => 'إلغاء',
    'suspend' => 'تعليق', 'resume' => 'استئناف', _ => v,
  };

  // ── Inline edit ──
  Future<void> _loadStaffForEditing() async {
    if (_staffLoaded) return;
    try {
      final result = await TaskApiService.instance.getTaskStaff();
      if (result['success'] == true && result['data'] != null) {
        final data = result['data'];
        final techs = <String>[];
        final agents = <String>[];
        final techIdMap = <String, String>{};
        final agentIdMap = <String, String>{};
        for (final t in (data['technicians'] as List? ?? [])) {
          final name = (t['Name'] ?? t['name'])?.toString() ?? '';
          final id = (t['Id'] ?? t['id'])?.toString() ?? '';
          if (name.isNotEmpty) {
            techs.add(name);
            if (id.isNotEmpty) techIdMap[name] = id;
          }
        }
        for (final l in (data['leaders'] as List? ?? [])) {
          final name = (l['Name'] ?? l['name'])?.toString() ?? '';
          final id = (l['Id'] ?? l['id'])?.toString() ?? '';
          if (name.isNotEmpty && !techs.contains(name)) {
            techs.add(name);
            if (id.isNotEmpty) techIdMap[name] = id;
          }
        }
        // الوكلاء: است��راج أسماء فريدة من العمود "ا��وكيل" في البيانات المحمّلة
        for (final r in _records) {
          final agent = r['الوكيل']?.toString().trim() ?? '';
          final agentId = r['linkedAgentId']?.toString() ?? '';
          if (agent.isNotEmpty && agent != '-' && !agents.contains(agent)) {
            agents.add(agent);
            if (agentId.isNotEmpty) agentIdMap[agent] = agentId;
          }
        }
        techs.sort();
        agents.sort();
        if (mounted) setState(() {
          _staffTechnicians = techs;
          _staffAgents = agents;
          _staffTechIdMap = techIdMap;
          _staffAgentIdMap = agentIdMap;
          _staffLoaded = true;
        });
      }
    } catch (_) {}
  }

  void _startEditing(Map<String, dynamic> r) {
    _loadStaffForEditing();
    final collTypeRaw = r['نوع التحصيل_raw']?.toString() ?? _mapCollectionTypeReverse(r['نوع التحصيل']?.toString() ?? 'cash');
    final payMethod = r['طريقة الدفع']?.toString() ?? '';
    setState(() {
      _editingId = r['id']?.toString();
      _editOperatorCtrl.text = r['المُفعِّل']?.toString() ?? '';
      _editPriceCtrl.text = r['سعر الباقة']?.toString() ?? '';
      _editTechnicianCtrl.text = r['الفني']?.toString() ?? '';
      _editAgentCtrl.text = r['الوكيل']?.toString() ?? '';
      _editCollType = ['cash', 'credit', 'agent', 'master', 'technician']
              .contains(collTypeRaw)
          ? collTypeRaw
          : 'cash';
      _editPaymentMethod = payMethod;
    });
  }

  void _cancelEditing() => setState(() => _editingId = null);

  Future<void> _saveEditing() async {
    final id = _editingId;
    if (id == null || id.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final techName = _editTechnicianCtrl.text.trim();
      final agentName = _editAgentCtrl.text.trim();
      final bodyMap = <String, dynamic>{
        'ActivatedBy': _editOperatorCtrl.text.trim(),
        'PlanPrice': double.tryParse(_editPriceCtrl.text.trim()) ?? 0,
        'CollectionType': _editCollType,
        'TechnicianName': techName,
        'AgentName': agentName,
        'PaymentMethod': _editPaymentMethod,
      };
      // إرسال LinkedTechnicianId إذا تغيّر الفني
      if (techName.isNotEmpty && _staffTechIdMap.containsKey(techName)) {
        bodyMap['LinkedTechnicianId'] = _staffTechIdMap[techName];
      }
      // إرسال LinkedAgentId إذا تغيّر الوكيل
      if (agentName.isNotEmpty && _staffAgentIdMap.containsKey(agentName)) {
        bodyMap['LinkedAgentId'] = _staffAgentIdMap[agentName];
      }
      final body = jsonEncode(bodyMap);
      final res = await http.put(
        Uri.parse('$_baseUrl/$id'),
        headers: {'X-Api-Key': _apiKey, 'Content-Type': 'application/json'},
        body: body,
      );
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 204) {
        final updated = {
          'المُفعِّل': _editOperatorCtrl.text.trim(),
          'سعر الباقة': _editPriceCtrl.text.trim(),
          'نوع التحصيل': _mapCollectionType(_editCollType),
          'نوع التحصيل_raw': _editCollType,
          'الفني': _editTechnicianCtrl.text.trim(),
          'الوكيل': _editAgentCtrl.text.trim(),
          'طريقة الدفع': _editPaymentMethod,
        };
        setState(() {
          final idx = _records.indexWhere((r) => r['id'] == id);
          if (idx != -1) _records[idx] = {..._records[idx], ...updated};
          final fidx = _filtered.indexWhere((r) => r['id'] == id);
          if (fidx != -1) _filtered[fidx] = {..._filtered[fidx], ...updated};
          _editingId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم الحفظ', style: GoogleFonts.cairo()),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل الحفظ: ${res.statusCode}', style: GoogleFonts.cairo()),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('خطأ', style: GoogleFonts.cairo()),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteRecord(Map<String, dynamic> record) async {
    final id = record['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تأكيد الحذف',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Text(
            'حذف "${record['اسم العميل']}" - ${record['اسم الباقة']}؟\nلا يمكن التراجع.',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('إلغاء', style: GoogleFonts.cairo())),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('حذف',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      final res = await http.delete(Uri.parse('$_baseUrl/$id'),
          headers: {'X-Api-Key': _apiKey});
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 204) {
        setState(() {
          _records.removeWhere((r) => r['id'] == id);
          _filtered.removeWhere((r) => r['id'] == id);
          _selectedIds.remove(id);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم الحذف', style: GoogleFonts.cairo()),
          backgroundColor: Colors.green.shade700,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل: ${res.statusCode}', style: GoogleFonts.cairo()),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('خطأ', style: GoogleFonts.cairo()),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تأكيد الحذف الجماعي',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Text('حذف $count عملية؟ لا يمكن التراجع.',
              style: GoogleFonts.cairo()),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('إلغاء', style: GoogleFonts.cairo())),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('حذف الكل',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() => _isDeletingSelected = true);
    final ids = _selectedIds.toList();
    int deleted = 0;
    for (final id in ids) {
      try {
        final res = await http.delete(Uri.parse('$_baseUrl/$id'),
            headers: {'X-Api-Key': _apiKey});
        if (res.statusCode == 200 || res.statusCode == 204) deleted++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _records.removeWhere((r) => ids.contains(r['id']));
      _selectedIds.clear();
      _isDeletingSelected = false;
    });
    _applyFiltersFromRecords(_records);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('تم حذف $deleted من $count', style: GoogleFonts.cairo()),
      backgroundColor:
          deleted == count ? Colors.green.shade700 : Colors.orange.shade700,
    ));
  }

  void _showRowMenu(BuildContext ctx, Offset globalPos,
      Map<String, dynamic> record) {
    final overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox;
    final pos = RelativeRect.fromRect(
      Rect.fromLTWH(globalPos.dx, globalPos.dy, 1, 1),
      Offset.zero & overlay.size,
    );
    showMenu<String>(
      context: ctx,
      position: pos,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 16, color: Colors.teal.shade700),
            const SizedBox(width: 8),
            Text('تعديل', style: GoogleFonts.cairo()),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 16, color: Colors.red.shade600),
            const SizedBox(width: 8),
            Text('حذف', style: GoogleFonts.cairo(color: Colors.red.shade600)),
          ]),
        ),
      ],
    ).then((value) {
      if (value == 'edit') _startEditing(record);
      if (value == 'delete') _deleteRecord(record);
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeFiltersCount = _colFilters.values
        .where((s) => s.isNotEmpty)
        .length;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'كل العمليات (${_filtered.length})'
            '${_selectedIds.isNotEmpty ? ' — محدد: ${_selectedIds.length}' : ''}',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.teal.shade700,
          foregroundColor: Colors.white,
          actions: [
            // حذف المحددة
            if (_selectedIds.isNotEmpty)
              _isDeletingSelected
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2)),
                    )
                  : TextButton.icon(
                      onPressed: _deleteSelected,
                      icon: Icon(Icons.delete_sweep,
                          color: Colors.red.shade300, size: 18),
                      label: Text('حذف (${_selectedIds.length})',
                          style: GoogleFonts.cairo(
                              color: Colors.red.shade300,
                              fontWeight: FontWeight.w600)),
                    ),
            // عدد الفلاتر النشطة
            if (activeFiltersCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Tooltip(
                  message: 'إزالة كل الفلاتر',
                  child: ActionChip(
                    label: Text('$activeFiltersCount فلتر نشط',
                        style: GoogleFonts.cairo(fontSize: 11, color: Colors.white)),
                    avatar: const Icon(Icons.filter_alt, size: 14, color: Colors.white),
                    backgroundColor: Colors.orange.shade700,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _colFilters.clear();
                      _applyFiltersFromRecords(_records);
                    }),
                  ),
                ),
              ),
            // الترتيب النشط
            if (_sortKey != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Chip(
                  label: Text(
                    '${_cols.firstWhere((c) => c[1] == _sortKey, orElse: () => [_sortKey!, _sortKey!, 0])[0]}'
                    ' ${_sortAsc ? '↑' : '↓'}',
                    style: GoogleFonts.cairo(fontSize: 11, color: Colors.white),
                  ),
                  deleteIcon:
                      const Icon(Icons.close, size: 14, color: Colors.white70),
                  onDeleted: () => setState(() {
                    _sortKey = null;
                    _applyFiltersFromRecords(_records);
                  }),
                  backgroundColor: Colors.teal.shade600,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            // زر اختيار الأعمدة
            Tooltip(
              message: 'اختيار الأعمدة',
              child: IconButton(
                icon: Badge(
                  isLabelVisible: _hiddenCols.isNotEmpty,
                  label: Text('${_hiddenCols.length}',
                      style: const TextStyle(fontSize: 9)),
                  backgroundColor: Colors.orange.shade600,
                  child: const Icon(Icons.view_column),
                ),
                onPressed: _showColPickerDialog,
              ),
            ),
            IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _load,
                tooltip: 'تحديث'),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                controller: _searchCtrl,
                style: GoogleFonts.cairo(color: Colors.black87),
                decoration: InputDecoration(
                  hintText: 'بحث في كل الحقول...',
                  hintStyle: GoogleFonts.cairo(color: Colors.grey.shade500),
                  prefixIcon: Icon(Icons.search, color: Colors.teal.shade400),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: Colors.grey.shade500),
                          onPressed: () => _searchCtrl.clear())
                      : null,
                  filled: true,
                  fillColor: Colors.teal.shade50,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.teal.shade200)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.teal.shade200)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.teal.shade400)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, style: GoogleFonts.cairo(color: Colors.red)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                        onPressed: _load,
                        child: Text('إعادة المحاولة', style: GoogleFonts.cairo())),
                  ]))
                : _filtered.isEmpty
                    ? Center(
                        child: Text('لا توجد سجلات',
                            style: GoogleFonts.cairo(fontSize: 16)))
                    : _buildTable(),
      ),
    );
  }

  // ── بناء خلية رأس العمود (تُعيد Expanded) ──
  Widget _buildHeaderCell(List<dynamic> col) {
    final label = col[0] as String;
    final key   = col[1] as String;
    final flex  = col[2] as int;

    final baseDeco = BoxDecoration(
      border: Border(
        bottom: BorderSide(color: Colors.black54, width: 1.5),
        left: BorderSide(color: Colors.black26),
      ),
    );

    // عمود التحديد الكلي
    if (key == '_check') {
      final allSel = _filtered.isNotEmpty &&
          _filtered.every(
              (r) => _selectedIds.contains(r['id']?.toString() ?? ''));
      final someSel = _selectedIds.isNotEmpty && !allSel;
      return Expanded(
        flex: flex,
        child: Container(
          decoration: baseDeco,
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Center(
            child: Checkbox(
              value: allSel ? true : (someSel ? null : false),
              tristate: true,
              onChanged: (_) => setState(() {
                if (allSel) {
                  _selectedIds.removeAll(
                      _filtered.map((r) => r['id']?.toString() ?? ''));
                } else {
                  _selectedIds.addAll(
                      _filtered.map((r) => r['id']?.toString() ?? ''));
                }
              }),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: Colors.teal.shade700),
              activeColor: Colors.teal.shade700,
            ),
          ),
        ),
      );
    }

    // # و ✓ — بدون فرز/فلتر
    if (key == '_idx' || key == '_icons') {
      return Expanded(
        flex: flex,
        child: Container(
          decoration: baseDeco,
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Center(
            child: Text(label,
                style: GoogleFonts.cairo(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.teal.shade900)),
          ),
        ),
      );
    }

    final isSorted = _sortKey == key;
    final hasFilter =
        _colFilters.containsKey(key) && _colFilters[key]!.isNotEmpty;
    final filterCount = _colFilters[key]?.length ?? 0;

    return Expanded(
      flex: flex,
      child: Container(
        decoration: baseDeco,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // منطقة الفرز (الضغط على النص)
            Expanded(
              child: InkWell(
                onTap: () => _onSortCol(key),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: hasFilter
                                ? Colors.orange.shade800
                                : Colors.teal.shade900,
                          ),
                        ),
                      ),
                      if (isSorted) ...[
                        const SizedBox(width: 1),
                        Icon(
                          _sortAsc
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 9,
                          color: Colors.teal.shade700,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // زر الفلتر
            InkWell(
              onTap: () => _showFilterDialog(key, label),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      hasFilter ? Icons.filter_alt : Icons.filter_list,
                      size: 13,
                      color: hasFilter
                          ? Colors.orange.shade600
                          : Colors.grey.shade500,
                    ),
                    if (filterCount > 1)
                      Positioned(
                        top: -4,
                        left: -4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade700,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$filterCount',
                            style: const TextStyle(
                                fontSize: 7,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildTable() {
    return Column(
      children: [
        // رأس الجدول
        Container(
          color: Colors.teal.shade50,
          child: Row(children: _visibleCols.map(_buildHeaderCell).toList()),
        ),
        // الصفوف
        Expanded(
          child: ListView.builder(
            itemCount: _filtered.length,
            itemBuilder: (ctx, i) => _buildRow(ctx, _filtered[i], i),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext ctx, Map<String, dynamic> r, int i) {
    final id         = r['id']?.toString() ?? '';
    final isEditing  = _editingId == id;
    final isSelected = _selectedIds.contains(id);

    String fmtDate(String? raw) {
      if (raw == null || raw.isEmpty) return '';
      final d = DateTime.tryParse(raw);
      return d != null ? _dateFmt.format(d) : raw;
    }

    final displayDate  = fmtDate(r['تاريخ التفعيل']?.toString());
    final displayStart = fmtDate(r['تاريخ البدء']?.toString());
    final displayEnd   = fmtDate(r['تاريخ الانتهاء']?.toString());
    final price        = double.tryParse(r['سعر الباقة']?.toString() ?? '') ?? 0;
    final operator0    = r['المُفعِّل']?.toString() ?? '';
    final isUnknown    = operator0.isEmpty;
    final collType     = r['نوع التحصيل']?.toString() ?? '';
    final isPrinted    = r['مطبوع'] == true;
    final isWa         = r['واتساب'] == true;

    Color collColor = Colors.grey.shade600;
    if (collType == 'cash')           collColor = Colors.green.shade700;
    else if (collType == 'credit')    collColor = Colors.orange.shade700;
    else if (collType == 'agent')     collColor = Colors.purple.shade700;
    else if (collType == 'master')    collColor = Colors.blue.shade700;
    else if (collType == 'technician') collColor = Colors.teal.shade700;

    final bgColor = isSelected
        ? Colors.blue.shade50
        : isEditing
            ? Colors.teal.shade50
            : isUnknown
                ? Colors.orange.shade50
                : i.isEven ? Colors.white : Colors.grey.shade50;

    final rowH = isEditing ? 52.0 : 34.0;

    // helper: خلية flex
    Widget cell(int flex, Widget child, {bool start = false}) {
      return Expanded(
        flex: flex,
        child: ClipRect(
          child: Container(
            height: rowH,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: Colors.black26)),
            ),
            alignment: start
                ? AlignmentDirectional.centerStart
                : Alignment.center,
            child: child,
          ),
        ),
      );
    }

    // helper: نص بسيط
    Widget txt(int flex, String text,
        {Color? color, bool bold = false, bool start = false}) {
      return cell(
        flex,
        Text(
          text.isEmpty ? '-' : text,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.cairo(
            fontSize: 10,
            color: text.isEmpty ? Colors.grey.shade400 : color,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        start: start,
      );
    }

    // helper: حقل تعديل
    Widget editField(TextEditingController ctrl,
        {TextInputType keyboard = TextInputType.text}) {
      return TextField(
        controller: ctrl,
        keyboardType: keyboard,
        style: GoogleFonts.cairo(fontSize: 10),
        onSubmitted: (_) => _saveEditing(),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: Colors.teal.shade600),
          ),
        ),
      );
    }

    return Builder(builder: (rowCtx) => GestureDetector(
      onSecondaryTapUp: (d) => _showRowMenu(rowCtx, d.globalPosition, r),
      onLongPress: () {
        final obj = rowCtx.findRenderObject();
        final pos = (obj is RenderBox)
            ? obj.localToGlobal(const Offset(50, 17))
            : Offset.zero;
        _showRowMenu(rowCtx, pos, r);
      },
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(bottom: BorderSide(color: Colors.black26)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ☐  flex=1  (لا يُخفى)
            cell(1, Checkbox(
              value: isSelected,
              onChanged: (_) => setState(() {
                if (isSelected) _selectedIds.remove(id);
                else _selectedIds.add(id);
              }),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: Colors.grey.shade400),
              activeColor: Colors.teal.shade700,
            )),
            // #  flex=1  (لا يُخفى)
            cell(1, Text('${i + 1}',
                style: GoogleFonts.cairo(fontSize: 9, color: Colors.grey.shade500))),
            // التاريخ
            if (!_hiddenCols.contains('تاريخ التفعيل')) txt(3, displayDate),
            // المشغل
            if (!_hiddenCols.contains('المُفعِّل'))
              cell(4,
                isEditing
                    ? StatefulBuilder(builder: (_, sl) {
                        final cur = _editOperatorCtrl.text.trim();
                        final linked = _reverseMap.values.toSet();
                        final items = <MapEntry<String, String>>[
                          for (final e in _reverseMap.entries) MapEntry(e.key, e.value),
                          for (final f in widget.operators)
                            if (!linked.contains(f.toLowerCase())) MapEntry(f, f),
                        ]..sort((a, b) => a.key.compareTo(b.key));
                        final sel = items
                            .where((e) => e.value.toLowerCase() == cur.toLowerCase())
                            .firstOrNull;
                        return DropdownButton<String>(
                          value: sel?.value,
                          isDense: true,
                          isExpanded: true,
                          hint: Text('اختر', style: GoogleFonts.cairo(fontSize: 10)),
                          underline: Container(height: 1, color: Colors.teal.shade400),
                          style: GoogleFonts.cairo(fontSize: 10, color: Colors.black87),
                          items: items.map((e) => DropdownMenuItem(
                                value: e.value,
                                child: Text(e.key, style: GoogleFonts.cairo(fontSize: 10)),
                              )).toList(),
                          onChanged: (v) {
                            if (v != null) {
                              _editOperatorCtrl.text = v;
                              sl(() {});
                              setState(() {});
                            }
                          },
                        );
                      })
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _linkingMap[operator0.toLowerCase()] ??
                                (isUnknown ? '⚠️ غير معروف' : operator0),
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              color: isUnknown
                                  ? Colors.orange.shade800
                                  : Colors.teal.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!isUnknown &&
                              _linkingMap.containsKey(operator0.toLowerCase()))
                            Text(operator0,
                                style: GoogleFonts.cairo(
                                    fontSize: 8, color: Colors.grey.shade500)),
                        ],
                      ),
                start: true,
              ),
            // العميل
            if (!_hiddenCols.contains('اسم العميل'))
              txt(5, r['اسم العميل']?.toString() ?? '', start: true),
            // الباقة
            if (!_hiddenCols.contains('اسم الباقة'))
              txt(3, r['اسم الباقة']?.toString() ?? ''),
            // المبلغ
            if (!_hiddenCols.contains('سعر الباقة'))
              cell(3,
                isEditing
                    ? editField(_editPriceCtrl, keyboard: TextInputType.number)
                    : Text(
                        price > 0 ? '${_fmt.format(price)} د.ع' : '-',
                        style: GoogleFonts.cairo(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade800),
                      ),
              ),
            // نوع العملية
            if (!_hiddenCols.contains('نوع العملية'))
              txt(3, r['نوع العملية']?.toString() ?? ''),
            // التحصيل (مدمج مع طريقة الدفع)
            if (!_hiddenCols.contains('نوع التحصيل'))
              cell(3,
                isEditing
                    ? StatefulBuilder(
                        builder: (_, sl) {
                          // تأكد أن القيمة موجودة في القائمة
                          const validValues = ['cash', 'credit', 'agent', 'master', 'technician'];
                          final safeValue = validValues.contains(_editCollType)
                              ? _editCollType
                              : 'cash';
                          if (safeValue != _editCollType) _editCollType = safeValue;
                          return DropdownButton<String>(
                            value: safeValue,
                            isDense: true,
                            isExpanded: true,
                            underline: Container(height: 1, color: Colors.teal.shade400),
                            style: GoogleFonts.cairo(fontSize: 10, color: Colors.black87),
                            items: const [
                              DropdownMenuItem(value: 'cash', child: Text('نقد')),
                              DropdownMenuItem(value: 'credit', child: Text('آجل')),
                              DropdownMenuItem(value: 'agent', child: Text('وكيل')),
                              DropdownMenuItem(value: 'master', child: Text('ماستر')),
                              DropdownMenuItem(value: 'technician', child: Text('فني')),
                            ],
                            onChanged: (v) =>
                                setState(() => _editCollType = v ?? _editCollType),
                          );
                        },
                      )
                    : Text(
                        collType.isNotEmpty ? collType : '-',
                        style: GoogleFonts.cairo(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: collColor),
                      ),
              ),
            if (!_hiddenCols.contains('الفني'))
              cell(3,
                isEditing
                    ? _buildSearchableField(
                        controller: _editTechnicianCtrl,
                        options: _staffTechnicians,
                        hint: 'ابحث عن فني',
                      )
                    : Text(
                        (r['الفني']?.toString() ?? '').isEmpty ? '-' : r['الفني'].toString(),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(fontSize: 10),
                      ),
                start: true,
              ),
            if (!_hiddenCols.contains('الوكيل'))
              cell(3,
                isEditing
                    ? _buildSearchableField(
                        controller: _editAgentCtrl,
                        options: _staffAgents,
                        hint: 'ابحث عن وكيل',
                      )
                    : Text(
                        (r['الوكيل']?.toString() ?? '').isEmpty ? '-' : r['الوكيل'].toString(),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(fontSize: 10),
                      ),
                start: true,
              ),
            // طريقة الدفع — مدمجة في عمود التحصيل
            if (!_hiddenCols.contains('اسم المنطقة'))
              txt(2, r['اسم المنطقة']?.toString() ?? ''),
            if (!_hiddenCols.contains('رقم الهاتف'))
              txt(3, r['رقم الهاتف']?.toString() ?? ''),
            if (!_hiddenCols.contains('تاريخ البدء'))
              txt(3, displayStart),
            if (!_hiddenCols.contains('تاريخ الانتهاء'))
              txt(3, displayEnd),
            if (!_hiddenCols.contains('الرصيد قبل'))
              txt(2, r['الرصيد قبل']?.toString() ?? ''),
            if (!_hiddenCols.contains('الرصيد بعد'))
              txt(2, r['الرصيد بعد']?.toString() ?? ''),
            if (!_hiddenCols.contains('fbg'))
              txt(2, r['fbg']?.toString() ?? ''),
            if (!_hiddenCols.contains('fat'))
              txt(2, r['fat']?.toString() ?? ''),
            if (!_hiddenCols.contains('fdt'))
              txt(2, r['fdt']?.toString() ?? ''),
            if (!_hiddenCols.contains('ملاحظات'))
              txt(4, r['ملاحظات']?.toString() ?? '',
                  color: Colors.grey.shade700, start: true),
            if (!_hiddenCols.contains('الحالة الحالية'))
              txt(2, r['الحالة الحالية']?.toString() ?? ''),
            // ✓  (لا يُخفى)
            cell(2,
              isEditing
                  ? _isSaving
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: _saveEditing,
                              child: Icon(Icons.check_circle,
                                  size: 18, color: Colors.green.shade700),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: _cancelEditing,
                              child: Icon(Icons.cancel,
                                  size: 18, color: Colors.red.shade400),
                            ),
                          ],
                        )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.print,
                            size: 13,
                            color: isPrinted
                                ? Colors.green.shade600
                                : Colors.grey.shade300),
                        const SizedBox(width: 4),
                        Icon(Icons.message,
                            size: 13,
                            color: isWa
                                ? Colors.green.shade600
                                : Colors.grey.shade300),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ));
  }
}
