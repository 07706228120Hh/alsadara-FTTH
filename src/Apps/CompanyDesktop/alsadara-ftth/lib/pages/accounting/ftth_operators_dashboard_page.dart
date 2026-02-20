import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/vps_auth_service.dart';
import '../../services/auth_service.dart';
import '../../theme/accounting_theme.dart';
import 'ftth_operator_account_page.dart';
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
  String _dateLabel = 'اليوم + أمس';

  String get _companyId =>
      widget.companyId ?? VpsAuthService.instance.currentCompanyId ?? '';

  final _currencyFormat = NumberFormat('#,###', 'ar');

  // ── TAB 1: خادمنا ──
  bool _isLoadingOurs = true;
  String? _errorOurs;
  List<dynamic> _oursOperators = [];
  Map<String, dynamic>? _oursSummary;

  // ── TAB 2: خادم FTTH ──
  bool _isLoadingFtth = false;
  String? _errorFtth;
  bool _ftthAuthenticated = false;
  Map<String, _FtthOperatorData> _ftthOperators = {};
  double _ftthTotalNegative = 0;
  double _ftthTotalPositive = 0;
  int _ftthTotalCount = 0;

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
    // الافتراضي: اليوم + أمس
    _setTodayAndYesterday();
    _loadOursData();
    _checkFtthAuth();
  }

  void _setTodayAndYesterday() {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    _fromDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _dateLabel = 'اليوم + أمس';
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.wifi_tethering, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                Text('تسجيل دخول FTTH',
                    style: GoogleFonts.cairo(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'أدخل بيانات حساب FTTH لجلب بيانات المعاملات من خادم admin.ftth.iq',
                            style: TextStyle(
                                fontSize: 12, color: Colors.blue.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextField(
                      controller: usernameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextField(
                      controller: passwordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(errorMsg!,
                          style: TextStyle(
                              color: Colors.red.shade700, fontSize: 12)),
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
                            errorMsg = 'خطأ: $e';
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
                    : const Text('تسجيل الدخول',
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
        } else {
          _errorOurs = result['message'] ?? 'خطأ';
        }
      } else {
        _errorOurs = 'خطأ في الاتصال: ${response.statusCode}';
      }
    } catch (e) {
      _errorOurs = 'خطأ: $e';
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
      double totalNeg = 0, totalPos = 0;
      int totalCnt = 0;
      int page = 1;
      const pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final url =
            'https://admin.ftth.iq/api/transactions?pageSize=$pageSize&pageNumber=$page'
            '&sortCriteria.property=occuredAt&sortCriteria.direction=desc'
            '&walletOwnerType=partner'
            '&occuredAt.from=$fromStr&occuredAt.to=$toStr'
            '&createdAt.from=$fromStr&createdAt.to=$toStr';

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
            final zoneId = tx['zoneId']?.toString() ?? '';
            final deviceUsername = tx['deviceUsername']?.toString() ?? '';

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

      // ════ نسب عمليات "بدون منشئ" تلقائياً ════
      final noCreator = operators.remove('بدون منشئ');
      if (noCreator != null && noCreator.transactions.isNotEmpty) {
        // 1) خريطة customerId → مشغل
        final Map<String, String> customerToOperator = {};
        // 2) خريطة subscriptionId → مشغل
        final Map<String, String> subToOperator = {};
        // 3) خريطة zoneId → عدّاد لكل مشغل (للأغلبية)
        final Map<String, Map<String, int>> zoneOperatorCounts = {};
        // 4) خريطة deviceUsername → مشغل
        final Map<String, String> deviceToOperator = {};

        for (final op in operators.values) {
          for (final tx in op.transactions) {
            if (tx.customerId.isNotEmpty) {
              customerToOperator[tx.customerId] = op.name;
            }
            if (tx.subscriptionId.isNotEmpty) {
              subToOperator[tx.subscriptionId] = op.name;
            }
            if (tx.zoneId.isNotEmpty) {
              zoneOperatorCounts
                  .putIfAbsent(tx.zoneId, () => {})
                  .update(op.name, (v) => v + 1, ifAbsent: () => 1);
            }
            if (tx.deviceUsername.isNotEmpty) {
              deviceToOperator[tx.deviceUsername] = op.name;
            }
          }
        }

        // حساب المشغل الأكثر نشاطاً لكل منطقة
        final Map<String, String> zoneDominant = {};
        for (final e in zoneOperatorCounts.entries) {
          String? best;
          int bestCount = 0;
          for (final oc in e.value.entries) {
            if (oc.value > bestCount) {
              bestCount = oc.value;
              best = oc.key;
            }
          }
          if (best != null) zoneDominant[e.key] = best;
        }

        // محاولة نسب كل عملية باستخدام 4 طرق
        final List<_FtthTransaction> stillOrphan = [];
        for (final tx in noCreator.transactions) {
          // ① customerId
          String? knownOp = tx.customerId.isNotEmpty
              ? customerToOperator[tx.customerId]
              : null;
          // ② subscriptionId
          knownOp ??= tx.subscriptionId.isNotEmpty
              ? subToOperator[tx.subscriptionId]
              : null;
          // ③ deviceUsername
          knownOp ??= tx.deviceUsername.isNotEmpty
              ? deviceToOperator[tx.deviceUsername]
              : null;
          // ④ zoneId (المشغل الأكثر نشاطاً في المنطقة)
          knownOp ??= tx.zoneId.isNotEmpty ? zoneDominant[tx.zoneId] : null;

          if (knownOp != null && operators.containsKey(knownOp)) {
            final target = operators[knownOp]!;
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
            ));
          } else {
            stillOrphan.add(tx);
          }
        }

        // ⑤ طريقة خامسة: audit-logs — جلب المنشئ الحقيقي عبر API
        if (stillOrphan.isNotEmpty) {
          final Set<String> uniqueCustomerIds = {};
          for (final tx in stillOrphan) {
            if (tx.customerId.isNotEmpty) {
              uniqueCustomerIds.add(tx.customerId);
            }
          }

          // جلب actor.username من audit-logs لكل عميل فريد
          final Map<String, String> customerAuditCreator = {};
          for (final custId in uniqueCustomerIds) {
            try {
              final auditUrl =
                  'https://admin.ftth.iq/api/audit-logs?pageSize=10&pageNumber=1'
                  '&sortCriteria.property=CreatedAt&sortCriteria.direction=%20desc'
                  '&customerId=$custId';
              final auditResp = await AuthService.instance
                  .authenticatedRequest('GET', auditUrl);
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
            } catch (_) {
              // تجاهل أخطاء audit-logs لعميل معين
            }
            // تأخير لتجنب إرهاق الخادم
            await Future.delayed(const Duration(milliseconds: 150));
          }

          // محاولة نسب المتبقيات بناءً على audit-logs
          final List<_FtthTransaction> finalOrphan = [];
          for (final tx in stillOrphan) {
            final auditCreator = tx.customerId.isNotEmpty
                ? customerAuditCreator[tx.customerId]
                : null;

            // حفظ اسم المنشئ المستخرج
            if (auditCreator != null) {
              tx.auditCreator = auditCreator;
            }

            // محاولة نسب للمشغل
            if (auditCreator != null && operators.containsKey(auditCreator)) {
              final target = operators[auditCreator]!;
              target.totalCount++;
              target.totalAmount += tx.amount;
              target.attributedOps++;
              if (tx.amount < 0) {
                target.negativeAmount += tx.amount;
              } else {
                target.positiveAmount += tx.amount;
              }
              final category = _categorizeType(tx.type);
              target.typeCounts[tx.type] =
                  (target.typeCounts[tx.type] ?? 0) + 1;
              switch (category) {
                case 'subscription':
                  target.subscriptionOps++;
                  if (const {
                    'PLAN_PURCHASE',
                    'PurchaseSubscriptionFromTrial',
                    'PLAN_SUBSCRIBE'
                  }.contains(tx.type)) {
                    target.purchaseOps++;
                  } else if (const {
                    'PLAN_RENEW',
                    'AUTO_RENEW',
                    'PLAN_EMI_RENEW'
                  }.contains(tx.type)) {
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

          stillOrphan
            ..clear()
            ..addAll(finalOrphan);
        }

        // إبقاء العمليات التي لم نستطع نسبها
        if (stillOrphan.isNotEmpty) {
          final orphanOp = _FtthOperatorData(name: 'بدون منشئ');
          for (final tx in stillOrphan) {
            orphanOp.totalCount++;
            orphanOp.totalAmount += tx.amount;
            if (tx.amount < 0) {
              orphanOp.negativeAmount += tx.amount;
            } else {
              orphanOp.positiveAmount += tx.amount;
            }
            final category = _categorizeType(tx.type);
            orphanOp.typeCounts[tx.type] =
                (orphanOp.typeCounts[tx.type] ?? 0) + 1;
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
                else if (const {'PLAN_CHANGE', 'SCHEDULE_CHANGE'}
                    .contains(tx.type))
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
          operators['بدون منشئ'] = orphanOp;
        }
      }

      _ftthOperators = operators;
      _ftthTotalNegative = totalNeg;
      _ftthTotalPositive = totalPos;
      _ftthTotalCount = totalCnt;
    } catch (e) {
      _errorFtth = 'خطأ في جلب بيانات FTTH: $e';
    }

    if (mounted) setState(() => _isLoadingFtth = false);
  }

  // ════════════════════════════════════════════════════════════════
  //  TAB 3: بناء المقارنة
  // ════════════════════════════════════════════════════════════════

  Future<void> _buildComparison() async {
    if (_oursOperators.isEmpty && !_isLoadingOurs) await _loadOursData();
    if (_ftthOperators.isEmpty && !_isLoadingFtth && _ftthAuthenticated) {
      await _loadFtthData();
    }

    if (!mounted) return;
    setState(() => _isLoadingCompare = true);

    try {
      // خريطة مشغلينا حسب ftthUsername أو operatorName
      final Map<String, Map<String, dynamic>> oursMap = {};
      for (final op in _oursOperators) {
        final m = op as Map<String, dynamic>;
        final ftthUser =
            (m['ftthUsername'] ?? m['operatorName'] ?? '').toString().trim();
        if (ftthUser.isNotEmpty) {
          oursMap[ftthUser.toLowerCase()] = m;
        }
      }

      final List<_ComparisonRow> rows = [];
      final Set<String> processedFtth = {};
      int matched = 0, oursOnly = 0, ftthOnly = 0;

      // مرور على مشغلي خادمنا
      for (final entry in oursMap.entries) {
        final oursKey = entry.key;
        final oursOp = entry.value;
        final oursCount = (oursOp['totalCount'] ?? 0) as int;
        final oursAmount = (oursOp['totalAmount'] ?? 0).toDouble();
        final oursName = oursOp['operatorName'] ?? oursKey;

        // البحث عن نظير في FTTH (case-insensitive)
        _FtthOperatorData? ftthOp;
        for (final fEntry in _ftthOperators.entries) {
          if (fEntry.key.toLowerCase() == oursKey) {
            ftthOp = fEntry.value;
            break;
          }
        }

        if (ftthOp != null) {
          processedFtth.add(ftthOp.name.toLowerCase());

          final ftthSubOps = ftthOp.subscriptionOps;
          final matchCount = oursCount < ftthSubOps ? oursCount : ftthSubOps;
          final oursOnlyCount = oursCount - matchCount;
          final ftthOnlyCount = ftthSubOps - matchCount;

          matched += matchCount;
          oursOnly += oursOnlyCount;
          ftthOnly += ftthOnlyCount;

          rows.add(_ComparisonRow(
            operatorName: oursName.toString(),
            oursCount: oursCount,
            oursAmount: oursAmount,
            ftthCount: ftthSubOps,
            ftthAmount: ftthOp.negativeAmount.abs(),
            matchedCount: matchCount,
            oursOnlyCount: oursOnlyCount,
            ftthOnlyCount: ftthOnlyCount,
          ));
        } else {
          oursOnly += oursCount;
          rows.add(_ComparisonRow(
            operatorName: oursName.toString(),
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

      // مشغلون في FTTH ليسوا عندنا
      for (final entry in _ftthOperators.entries) {
        if (processedFtth.contains(entry.key.toLowerCase())) continue;
        if (entry.key == 'بدون منشئ') continue;

        final ftthOp = entry.value;
        ftthOnly += ftthOp.subscriptionOps;

        rows.add(_ComparisonRow(
          operatorName: ftthOp.name,
          oursCount: 0,
          oursAmount: 0,
          ftthCount: ftthOp.subscriptionOps,
          ftthAmount: ftthOp.negativeAmount.abs(),
          matchedCount: 0,
          oursOnlyCount: 0,
          ftthOnlyCount: ftthOp.subscriptionOps,
        ));
      }

      // ترتيب: الأكثر فروقاً أولاً
      rows.sort((a, b) => (b.oursOnlyCount + b.ftthOnlyCount)
          .compareTo(a.oursOnlyCount + a.ftthOnlyCount));

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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        appBar: AppBar(
          backgroundColor: AccountingTheme.bgSidebar,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            'لوحة مشغلي FTTH',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            if (!_ftthAuthenticated)
              IconButton(
                icon: const Icon(Icons.login, color: Colors.orangeAccent),
                onPressed: _showFtthLoginDialog,
                tooltip: 'تسجيل دخول FTTH',
              ),
            if (_ftthAuthenticated)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.check_circle,
                    color: Colors.greenAccent, size: 18),
              ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70),
              onPressed: _refreshAll,
              tooltip: 'تحديث الكل',
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle:
                GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.cairo(fontSize: 12),
            tabs: const [
              Tab(icon: Icon(Icons.storage, size: 18), text: 'خادمنا'),
              Tab(
                  icon: Icon(Icons.wifi_tethering, size: 18),
                  text: 'خادم FTTH'),
              Tab(icon: Icon(Icons.compare_arrows, size: 18), text: 'المقارنة'),
            ],
          ),
        ),
        body: Column(
          children: [
            // ═══ شريط فلتر التاريخ السريع ═══
            _buildQuickDateFilter(),
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

  void _refreshAll() {
    _loadOursData();
    if (_ftthAuthenticated) _loadFtthData();
    _comparisonRows.clear();
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOursSummary(),
          const SizedBox(height: 16),
          _buildOursTable(),
        ],
      ),
    );
  }

  Widget _buildOursSummary() {
    if (_oursSummary == null) return const SizedBox();
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _summaryCard(
            'إجمالي العمليات',
            (_oursSummary!['totalAmount'] ?? 0).toDouble(),
            '${_oursSummary!['totalActivations'] ?? 0} عملية بواسطة ${_oursSummary!['totalOperators'] ?? 0} مشغل',
            AccountingTheme.neonBlue,
            icon: Icons.analytics_outlined),
        _summaryCard('نقد', (_oursSummary!['totalCash'] ?? 0).toDouble(), '',
            Colors.green.shade600,
            icon: Icons.attach_money),
        _summaryCard('آجل', (_oursSummary!['totalCredit'] ?? 0).toDouble(), '',
            Colors.orange.shade600,
            icon: Icons.schedule),
        _summaryCard('ماستر', (_oursSummary!['totalMaster'] ?? 0).toDouble(),
            '', Colors.purple.shade600,
            icon: Icons.credit_card),
        _summaryCard('وكيل', (_oursSummary!['totalAgent'] ?? 0).toDouble(), '',
            Colors.blue.shade600,
            icon: Icons.store),
        _summaryCard('المستحق', (_oursSummary!['totalNetOwed'] ?? 0).toDouble(),
            'نقد + آجل غير مسلّم', Colors.red.shade600,
            icon: Icons.warning_amber_rounded),
      ],
    );
  }

  Widget _buildOursTable() {
    if (_oursOperators.isEmpty) {
      return _emptyCard('لا يوجد مشغلون');
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text('المشغلون (${_oursOperators.length})',
                style: GoogleFonts.cairo(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('المشغل')),
                DataColumn(label: Text('العمليات')),
                DataColumn(label: Text('الإجمالي')),
                DataColumn(label: Text('نقد')),
                DataColumn(label: Text('آجل')),
                DataColumn(label: Text('ماستر')),
                DataColumn(label: Text('وكيل')),
                DataColumn(label: Text('المستحق')),
                DataColumn(label: Text('')),
              ],
              rows: _oursOperators.asMap().entries.map((entry) {
                final i = entry.key;
                final op = entry.value as Map<String, dynamic>;
                final netOwed = (op['netOwed'] ?? 0).toDouble();

                return DataRow(cells: [
                  DataCell(
                      Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                  DataCell(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(op['operatorName'] ?? '-',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      if (op['ftthUsername'] != null)
                        Text(op['ftthUsername'],
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600)),
                    ],
                  )),
                  DataCell(Text('${op['totalCount'] ?? 0}',
                      style: const TextStyle(fontSize: 12))),
                  DataCell(Text(
                    _currencyFormat.format((op['totalAmount'] ?? 0).toDouble()),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AccountingTheme.neonBlue),
                  )),
                  DataCell(Text(
                    _currencyFormat.format((op['cashAmount'] ?? 0).toDouble()),
                    style:
                        TextStyle(fontSize: 11, color: Colors.green.shade700),
                  )),
                  DataCell(Text(
                    _currencyFormat
                        .format((op['creditAmount'] ?? 0).toDouble()),
                    style:
                        TextStyle(fontSize: 11, color: Colors.orange.shade700),
                  )),
                  DataCell(Text(
                    _currencyFormat
                        .format((op['masterAmount'] ?? 0).toDouble()),
                    style:
                        TextStyle(fontSize: 11, color: Colors.purple.shade700),
                  )),
                  DataCell(Text(
                    _currencyFormat.format((op['agentAmount'] ?? 0).toDouble()),
                    style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                  )),
                  DataCell(Text(
                    _currencyFormat.format(netOwed),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: netOwed > 0
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                    ),
                  )),
                  DataCell(IconButton(
                    icon: Icon(Icons.open_in_new,
                        size: 18, color: AccountingTheme.neonBlue),
                    onPressed: () => _openOperatorAccount(op),
                    tooltip: 'فتح كشف الحساب',
                  )),
                ]);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _openOperatorAccount(Map<String, dynamic> op) {
    final userId = op['userId']?.toString();
    if (userId == null || userId.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FtthOperatorAccountPage(
          userId: userId,
          operatorName: op['operatorName'] ?? 'مشغل',
          companyId: _companyId,
        ),
      ),
    );
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
            Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('يجب تسجيل الدخول لخادم FTTH',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
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
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFtthSummary(),
          const SizedBox(height: 16),
          _buildFtthTable(),
        ],
      ),
    );
  }

  Widget _buildFtthSummary() {
    // حساب إجماليات الفئات
    int totalPur = 0, totalRen = 0, totalChg = 0, totalSch = 0;
    int totalComm = 0, totalRev = 0, totalWal = 0, totalOth = 0;
    int totalAttr = 0;
    for (final op in _ftthOperators.values) {
      totalPur += op.purchaseOps;
      totalRen += op.renewOps;
      totalChg += op.changeOps;
      totalSch += op.scheduleOps;
      totalComm += op.commissionOps;
      totalRev += op.reversalOps;
      totalWal += op.walletOps;
      totalOth += op.otherOps;
      totalAttr += op.attributedOps;
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _summaryCard('إجمالي المعاملات', _ftthTotalCount.toDouble(),
            '${_ftthOperators.length} مشغل', AccountingTheme.neonBlue,
            icon: Icons.receipt_long, isCount: true),
        _summaryCard('شراء', totalPur.toDouble(), 'شراء باقة جديدة',
            Colors.teal.shade700,
            icon: Icons.shopping_cart, isCount: true),
        _summaryCard('تجديد', totalRen.toDouble(), 'تجديد+تلقائي+قسط',
            Colors.teal.shade500,
            icon: Icons.autorenew, isCount: true),
        _summaryCard(
            'تغيير', totalChg.toDouble(), 'تغيير باقة', Colors.teal.shade400,
            icon: Icons.swap_horiz, isCount: true),
        _summaryCard('جدولة', totalSch.toDouble(), '', Colors.teal.shade300,
            icon: Icons.schedule, isCount: true),
        _summaryCard('عمولات', totalComm.toDouble(), '', Colors.purple.shade600,
            icon: Icons.percent, isCount: true),
        _summaryCard(
            'عكس/ارتجاع', totalRev.toDouble(), '', Colors.orange.shade600,
            icon: Icons.undo, isCount: true),
        if (totalAttr > 0)
          _summaryCard('منسوب تلقائياً', totalAttr.toDouble(),
              'عمليات نُسبت عبر العميل', Colors.indigo.shade500,
              icon: Icons.auto_fix_high, isCount: true),
        _summaryCard('مجموع السالب', _ftthTotalNegative.abs(), 'مبالغ مخصومة',
            Colors.red.shade600,
            icon: Icons.arrow_circle_down),
        _summaryCard('مجموع الموجب', _ftthTotalPositive, 'عمولات ومرتجعات',
            Colors.green.shade600,
            icon: Icons.arrow_circle_up),
      ],
    );
  }

  Widget _buildFtthTable() {
    if (_ftthOperators.isEmpty) {
      return _emptyCard('لا توجد معاملات في هذا النطاق');
    }

    final sorted = _ftthOperators.values.toList()
      ..sort((a, b) => b.totalCount.compareTo(a.totalCount));

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Text('المشغلون في FTTH (${sorted.length})',
                    style: GoogleFonts.cairo(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('admin.ftth.iq',
                      style:
                          TextStyle(fontSize: 10, color: Colors.teal.shade700)),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: MediaQuery.of(context).size.width,
              ),
              child: DataTable(
                showCheckboxColumn: false,
                headingRowColor: WidgetStateProperty.all(Colors.teal.shade50),
                columnSpacing: 14,
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('المشغل')),
                  DataColumn(label: Text('شراء')),
                  DataColumn(label: Text('تجديد')),
                  DataColumn(label: Text('تغيير')),
                  DataColumn(label: Text('جدولة')),
                  DataColumn(label: Text('عمولات')),
                  DataColumn(label: Text('عكس')),
                  DataColumn(label: Text('محفظة')),
                  DataColumn(label: Text('أخرى')),
                  DataColumn(label: Text('الإجمالي')),
                  DataColumn(label: Text('السالب')),
                  DataColumn(label: Text('الموجب')),
                  DataColumn(label: Text('التفاصيل')),
                ],
                rows: sorted.asMap().entries.map((entry) {
                  final i = entry.key;
                  final op = entry.value;

                  return DataRow(
                      onSelectChanged: (_) => _openOperatorTransactions(op),
                      cells: [
                        DataCell(Text('${i + 1}',
                            style: const TextStyle(fontSize: 12))),
                        DataCell(Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(op.name,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                            if (op.name == 'بدون منشئ')
                              Text('نظام أو إدارة',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.orange.shade700)),
                            if (op.attributedOps > 0)
                              Text('⇐ +${op.attributedOps} منسوب تلقائياً',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.indigo.shade600,
                                      fontWeight: FontWeight.w500)),
                          ],
                        )),
                        DataCell(Text('${op.purchaseOps}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: op.purchaseOps > 0
                                    ? Colors.teal.shade700
                                    : Colors.grey.shade400))),
                        DataCell(Text('${op.renewOps}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: op.renewOps > 0
                                    ? Colors.teal.shade600
                                    : Colors.grey.shade400))),
                        DataCell(Text('${op.changeOps}',
                            style: TextStyle(
                                fontSize: 12,
                                color: op.changeOps > 0
                                    ? Colors.teal.shade500
                                    : Colors.grey.shade400))),
                        DataCell(Text('${op.scheduleOps}',
                            style: TextStyle(
                                fontSize: 12,
                                color: op.scheduleOps > 0
                                    ? Colors.teal.shade400
                                    : Colors.grey.shade400))),
                        DataCell(Text('${op.commissionOps}',
                            style: TextStyle(
                                fontSize: 11,
                                color: op.commissionOps > 0
                                    ? Colors.purple.shade700
                                    : Colors.grey.shade400))),
                        DataCell(Text('${op.reversalOps}',
                            style: TextStyle(
                                fontSize: 11,
                                color: op.reversalOps > 0
                                    ? Colors.orange.shade700
                                    : Colors.grey.shade400))),
                        DataCell(Text('${op.walletOps}',
                            style: TextStyle(
                                fontSize: 11,
                                color: op.walletOps > 0
                                    ? Colors.blue.shade700
                                    : Colors.grey.shade400))),
                        // أخرى: إظهار كل نوع بدل رقم واحد
                        DataCell(_buildOtherTypesCell(op)),
                        DataCell(Text('${op.totalCount}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600))),
                        DataCell(Text(
                          _currencyFormat.format(op.negativeAmount.abs()),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade700),
                        )),
                        DataCell(Text(
                          _currencyFormat.format(op.positiveAmount),
                          style: TextStyle(
                              fontSize: 11, color: Colors.green.shade700),
                        )),
                        DataCell(IconButton(
                          icon: Icon(Icons.info_outline,
                              size: 16, color: Colors.teal.shade600),
                          tooltip: 'عرض تفاصيل الأنواع',
                          onPressed: () => _showTypeBreakdown(op),
                        )),
                      ]);
                }).toList(),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.list_alt, color: Colors.teal.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('تفاصيل عمليات: ${op.name}',
                    style: GoogleFonts.cairo(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
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
                  constraints: const BoxConstraints(maxHeight: 300),
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
                        padding: const EdgeInsets.symmetric(vertical: 3),
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
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_translateType(type),
                                  style: const TextStyle(fontSize: 12)),
                            ),
                            Text('$count',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: catColor.shade700)),
                            const SizedBox(width: 6),
                            Text(type,
                                style: TextStyle(
                                    fontSize: 9, color: Colors.grey.shade500)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الإجمالي: ${op.totalCount}',
                        style: GoogleFonts.cairo(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    Text(
                        'سالب: ${_currencyFormat.format(op.negativeAmount.abs())} | موجب: ${_currencyFormat.format(op.positiveAmount)}',
                        style: const TextStyle(fontSize: 10)),
                  ],
                ),
                // عرض تفاصيل المعاملات الفردية لعمليات "بدون منشئ" أو المنسوبة
                if (op.name == 'بدون منشئ' || op.attributedOps > 0) ...[
                  const Divider(height: 16),
                  Text(
                    op.name == 'بدون منشئ'
                        ? '📋 تفاصيل العمليات (${op.transactions.length})'
                        : '📋 العمليات المنسوبة تلقائياً (${op.attributedOps})',
                    style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade700),
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
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
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.all(8),
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
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.teal.shade700)),
                                  const Spacer(),
                                  Text(
                                      '${_currencyFormat.format(tx.amount.abs())} د.ع',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: tx.amount < 0
                                              ? Colors.red.shade700
                                              : Colors.green.shade700)),
                                ],
                              ),
                              if (tx.customerName.isNotEmpty)
                                Text('👤 العميل: ${tx.customerName}',
                                    style: TextStyle(
                                        fontSize: 11,
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
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade800)),
                                ),
                              if (tx.customerId.isNotEmpty &&
                                  tx.auditCreator.isEmpty)
                                Text('🆔 معرف العميل: ${tx.customerId}',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey.shade600)),
                              if (tx.planName.isNotEmpty)
                                Text('📦 ${tx.planName}',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade600)),
                              if (tx.zoneId.isNotEmpty)
                                Text('📍 زون: ${tx.zoneId}',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade600)),
                              if (tx.occuredAt.isNotEmpty)
                                Text('🕐 ${_formatTxDate(tx.occuredAt)}',
                                    style: TextStyle(
                                        fontSize: 9,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: count > 0 ? color.withOpacity(0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: count > 0 ? color.withOpacity(0.5) : Colors.grey.shade300,
        ),
      ),
      child: Text('$label: $count',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: count > 0 ? color : Colors.grey.shade500)),
    );
  }

  /// خلية عمود "أخرى" - تعرض كل نوع باسمه العربي
  Widget _buildOtherTypesCell(_FtthOperatorData op) {
    if (op.otherOps == 0) {
      return Text('0',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400));
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
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text(
            '${_translateType(e.key)}: ${e.value}',
            style: TextStyle(
              fontSize: 10,
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
            Icon(Icons.lock_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('يجب تسجيل الدخول لخادم FTTH أولاً لإجراء المقارنة',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
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

    if (_isLoadingCompare || _isLoadingOurs || _isLoadingFtth) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('جاري بناء المقارنة...'),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCompareSummaryCards(),
          const SizedBox(height: 16),
          _buildCompareTable(),
        ],
      ),
    );
  }

  Widget _buildCompareSummaryCards() {
    final total = _totalMatched + _totalOursOnly + _totalFtthOnly;
    final matchPercent = total > 0 ? (_totalMatched / total * 100) : 0;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _summaryCard(
            'مطابقة',
            _totalMatched.toDouble(),
            '${matchPercent.toStringAsFixed(0)}% من الإجمالي',
            Colors.green.shade600,
            icon: Icons.check_circle,
            isCount: true),
        _summaryCard('في خادمنا فقط', _totalOursOnly.toDouble(),
            'غير موجودة في FTTH', Colors.orange.shade600,
            icon: Icons.warning_amber, isCount: true),
        _summaryCard('في FTTH فقط', _totalFtthOnly.toDouble(),
            'غير موجودة عندنا', Colors.red.shade600,
            icon: Icons.error_outline, isCount: true),
      ],
    );
  }

  Widget _buildCompareTable() {
    if (_comparisonRows.isEmpty) {
      return _emptyCard('لا توجد بيانات للمقارنة');
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Text('مقارنة المشغلين (${_comparisonRows.length})',
                    style: GoogleFonts.cairo(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () {
                    _comparisonRows.clear();
                    _buildComparison();
                  },
                  tooltip: 'إعادة بناء المقارنة',
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.indigo.shade50),
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('المشغل')),
                DataColumn(label: Text('عملياتنا')),
                DataColumn(label: Text('مبالغنا')),
                DataColumn(label: Text('عمليات FTTH')),
                DataColumn(label: Text('مبالغ FTTH')),
                DataColumn(label: Text('مطابقة')),
                DataColumn(label: Text('عندنا فقط')),
                DataColumn(label: Text('FTTH فقط')),
                DataColumn(label: Text('النسبة')),
              ],
              rows: _comparisonRows.asMap().entries.map((entry) {
                final i = entry.key;
                final row = entry.value;
                final total =
                    row.matchedCount + row.oursOnlyCount + row.ftthOnlyCount;
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
                    DataCell(
                        Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                    DataCell(Text(row.operatorName,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600))),
                    DataCell(Text('${row.oursCount}',
                        style: const TextStyle(fontSize: 12))),
                    DataCell(Text(
                      _currencyFormat.format(row.oursAmount),
                      style: const TextStyle(fontSize: 11),
                    )),
                    DataCell(Text('${row.ftthCount}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.teal.shade700))),
                    DataCell(Text(
                      _currencyFormat.format(row.ftthAmount),
                      style:
                          TextStyle(fontSize: 11, color: Colors.teal.shade700),
                    )),
                    DataCell(Text('${row.matchedCount}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700))),
                    DataCell(Text(
                      '${row.oursOnlyCount}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              row.oursOnlyCount > 0 ? FontWeight.bold : null,
                          color: row.oursOnlyCount > 0
                              ? Colors.orange.shade700
                              : Colors.grey),
                    )),
                    DataCell(Text(
                      '${row.ftthOnlyCount}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              row.ftthOnlyCount > 0 ? FontWeight.bold : null,
                          color: row.ftthOnlyCount > 0
                              ? Colors.red.shade700
                              : Colors.grey),
                    )),
                    DataCell(_buildMatchBadge(percent)),
                  ],
                );
              }).toList(),
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$percent%',
          style:
              TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  SHARED WIDGETS
  // ════════════════════════════════════════════════════════════════

  Widget _summaryCard(String title, double value, String subtitle, Color color,
      {IconData? icon, bool isCount = false}) {
    return SizedBox(
      width: 200,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(title,
                        style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: color)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isCount
                    ? '${value.toInt()}'
                    : '${_currencyFormat.format(value)} د.ع',
                style: GoogleFonts.cairo(
                    fontSize: 16, fontWeight: FontWeight.bold, color: color),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle,
                    style:
                        TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyCard(String text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Text(error, style: TextStyle(color: Colors.red.shade700)),
          const SizedBox(height: 12),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
      child: Row(
        children: [
          Icon(Icons.filter_alt, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          _filterChip('اليوم', 'اليوم'),
          const SizedBox(width: 6),
          _filterChip('أمس', 'أمس'),
          const SizedBox(width: 6),
          _filterChip('اليوم + أمس', 'اليوم + أمس'),
          const SizedBox(width: 6),
          _filterChip('7 أيام', 'آخر 7 أيام'),
          const SizedBox(width: 6),
          _filterChip('الشهر', 'هذا الشهر'),
          const SizedBox(width: 6),
          _filterChip('الكل', 'الكل'),
          const SizedBox(width: 10),
          // زر اختيار مخصص
          InkWell(
            onTap: _showCustomDatePicker,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _dateLabel.contains('/') || _dateLabel.contains('-')
                    ? AccountingTheme.neonBlue
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _dateLabel.contains('/') || _dateLabel.contains('-')
                      ? AccountingTheme.neonBlue
                      : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_month,
                      size: 14,
                      color:
                          _dateLabel.contains('/') || _dateLabel.contains('-')
                              ? Colors.white
                              : Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    _dateLabel.contains('/') || _dateLabel.contains('-')
                        ? _dateLabel
                        : 'مخصص',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color:
                          _dateLabel.contains('/') || _dateLabel.contains('-')
                              ? Colors.white
                              : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // عرض النطاق الحالي
          if (_fromDate != null && _toDate != null)
            Text(
              '${DateFormat('MM/dd').format(_fromDate!)} - ${DateFormat('MM/dd').format(_toDate!)}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String filterKey) {
    final isSelected = _dateLabel == filterKey;
    return InkWell(
      onTap: () => _applyDateFilter(filterKey),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            fontSize: 11,
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
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar'),
    );
    if (picked != null) {
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
  Map<String, int> typeCounts = {};
  List<_FtthTransaction> transactions = [];

  _FtthOperatorData({required this.name});
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
  });
}

/// صف مقارنة بين النظامين
class _ComparisonRow {
  final String operatorName;
  final int oursCount;
  final double oursAmount;
  final int ftthCount;
  final double ftthAmount;
  final int matchedCount;
  final int oursOnlyCount;
  final int ftthOnlyCount;

  _ComparisonRow({
    required this.operatorName,
    required this.oursCount,
    required this.oursAmount,
    required this.ftthCount,
    required this.ftthAmount,
    required this.matchedCount,
    required this.oursOnlyCount,
    required this.ftthOnlyCount,
  });
}
