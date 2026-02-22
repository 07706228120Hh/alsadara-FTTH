/// صفحة شاشتي - لوحة الموظف الشخصية
/// تحتوي على: البصمة + المعاملات المالية + الراتب + الخصومات والمكافآت
library;

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/attendance_api_service.dart';
import '../services/vps_auth_service.dart';
import '../services/api/api_client.dart';
import 'attendance_page.dart';

class MyDashboardPage extends StatefulWidget {
  final String username;
  final String permissions;
  final String center;

  const MyDashboardPage({
    super.key,
    required this.username,
    required this.permissions,
    required this.center,
  });

  @override
  State<MyDashboardPage> createState() => _MyDashboardPageState();
}

class _MyDashboardPageState extends State<MyDashboardPage>
    with TickerProviderStateMixin {
  // ── ألوان ──
  static const _bgPage = Color(0xFFF5F6FA);
  static const _bgCard = Colors.white;
  static const _bgToolbar = Color(0xFF1A2332);
  static const _textDark = Color(0xFF2C3E50);
  static const _textGray = Color(0xFF95A5A6);
  static const _textSubtle = Color(0xFF7F8C8D);
  static const _shadowColor = Color(0x14000000);
  static const _accentBlue = Color(0xFF3498DB);
  static const _accentGreen = Color(0xFF27AE60);
  static const _accentRed = Color(0xFFE74C3C);
  static const _accentOrange = Color(0xFFF39C12);
  static const _accentTeal = Color(0xFF00BCD4);

  final AttendanceApiService _attendanceApi = AttendanceApiService.instance;
  final _client = ApiClient.instance;


  int _attendanceCount = 0;
  int _lateDays = 0;
  int _totalLateMinutes = 0;
  int _totalOvertimeMinutes = 0;
  int _totalWorkedMinutes = 0;
  String? _userId;

  // ── حالة المعاملات ──
  bool _isLoadingTx = true;
  List<dynamic> _transactions = [];
  Map<String, dynamic> _txSummary = {};
  int _txPage = 1;
  int _txTotalPages = 1;
  int _txTotal = 0;

  // ── حالة تقرير الموظف (راتب + إجازات) ──
  bool _isLoadingReport = true;
  Map<String, dynamic>? _salaryData;
  Map<String, dynamic>? _attendanceReport;
  List<dynamic>? _dailyRecords;
  Map<String, dynamic>? _leavesData;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    await Future.wait([
      _fetchAttendanceCount(),
      _loadTransactions(),
      _loadEmployeeReport(),
    ]);
  }

  Future<void> _fetchAttendanceCount() async {
    try {
      final authUser = VpsAuthService.instance.currentUser;
      final realUserId = authUser?.id ?? _userId ?? widget.username;
      final data = await _attendanceApi.getMonthlyAttendance(
        userId: realUserId,
      );
      if (!mounted) return;
      setState(() {
        _attendanceCount = data['totalDays'] ?? data['TotalDays'] ?? 0;
        _lateDays = data['lateDays'] ?? data['LateDays'] ?? 0;
        _totalLateMinutes =
            data['totalLateMinutes'] ?? data['TotalLateMinutes'] ?? 0;
        _totalOvertimeMinutes =
            data['totalOvertimeMinutes'] ?? data['TotalOvertimeMinutes'] ?? 0;
        _totalWorkedMinutes =
            data['totalWorkedMinutes'] ?? data['TotalWorkedMinutes'] ?? 0;
      });
    } catch (e) {
      debugPrint('Error fetching attendance count: $e');
    }
  }

  Future<void> _loadTransactions({int page = 1}) async {
    try {
      final response = await _client.get(
        '/techniciantransactions/my-transactions?page=$page&pageSize=20',
        (json) => json,
      );
      if (!mounted) return;
      if (response.success && response.data != null) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          setState(() {
            _transactions = data['transactions'] as List<dynamic>? ?? [];
            _txSummary = data['summary'] as Map<String, dynamic>? ?? {};
            _txPage = data['page'] ?? 1;
            _txTotalPages = data['totalPages'] ?? 1;
            _txTotal = data['total'] ?? 0;
            _isLoadingTx = false;
          });
        } else {
          setState(() {
            _transactions = [];
            _isLoadingTx = false;
          });
        }
      } else {
        setState(() => _isLoadingTx = false);
      }
    } catch (e) {
      debugPrint('Error loading transactions: $e');
      if (mounted) setState(() => _isLoadingTx = false);
    }
  }

  Future<void> _loadEmployeeReport() async {
    try {
      final now = DateTime.now();
      // استخدام my-report الذي لا يحتاج Admin
      final data = await _attendanceApi.getMyReport(
        month: now.month,
        year: now.year,
      );
      if (!mounted) return;
      // data might be {Employee:..., Attendance:..., Salary:..., Leaves:...}
      // or it might be wrapped in data key
      final reportData = data['data'] ?? data;
      final attData = reportData['Attendance'] as Map<String, dynamic>?;
      setState(() {
        _salaryData = reportData['Salary'] as Map<String, dynamic>?;
        _attendanceReport = attData;
        _dailyRecords = attData?['DailyRecords'] as List<dynamic>?;
        _leavesData = reportData['Leaves'] as Map<String, dynamic>?;
        _isLoadingReport = false;
      });
    } catch (e) {
      debugPrint('Error loading employee report: $e');
      if (mounted) setState(() => _isLoadingReport = false);
    }
  }



  String _formatAmount(dynamic amount) {
    if (amount == null) return '0';
    final num val =
        amount is num ? amount : num.tryParse(amount.toString()) ?? 0;
    return NumberFormat('#,##0', 'ar').format(val);
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('yyyy/MM/dd - HH:mm', 'ar').format(date.toLocal());
    } catch (_) {
      return dateStr;
    }
  }

  // ═══════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bgPage,
        body: Column(
          children: [
            _buildToolbar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchAll,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ═══ 1. زر البصمة ═══
                      _buildAttendanceButton(),
                      const SizedBox(height: 20),
                      // ═══ 2. ملخص مالي ═══
                      _buildFinancialSummary(),
                      const SizedBox(height: 20),
                      // ═══ 3. الراتب والخصومات ═══
                      _buildSalarySection(),
                      const SizedBox(height: 20),
                      // ═══ 4. سجل الحضور اليومي ═══
                      _buildDailyAttendanceSection(),
                      const SizedBox(height: 20),
                      // ═══ 5. المعاملات ═══
                      _buildTransactionsSection(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  TOOLBAR
  // ═══════════════════════════════════════════════════════
  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2332), Color(0xFF2C3E50)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'رجوع',
            style: IconButton.styleFrom(foregroundColor: Colors.white70),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_accentBlue, _accentTeal],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.dashboard_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('شاشتي',
                    style: GoogleFonts.cairo(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                Text(widget.username,
                    style:
                        GoogleFonts.cairo(fontSize: 12, color: Colors.white54)),
              ],
            ),
          ),
          // ساعة حية
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _accentBlue.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _accentBlue.withOpacity(0.3)),
            ),
            child: StreamBuilder(
              stream: Stream.periodic(const Duration(seconds: 1)),
              builder: (context, snapshot) {
                final now = DateTime.now();
                return Text(
                  '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
                  style: GoogleFonts.cairo(
                    color: _accentTeal,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: () {
              _fetchAll();
            },
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(foregroundColor: Colors.white70),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  1. زر فتح شاشة البصمة
  // ═══════════════════════════════════════════════════════
  Widget _buildAttendanceButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AttendancePage(
                username: widget.username,
                center: widget.center,
                permissions: widget.permissions,
              ),
            ),
          ).then((_) {
            // تحديث البيانات عند العودة
            _fetchAll();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF667eea).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.fingerprint_rounded,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('البصمة',
                        style: GoogleFonts.cairo(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    Text('تسجيل الحضور والانصراف',
                        style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.8))),
                  ],
                ),
              ),
              Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white.withOpacity(0.7), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  2. ملخص مالي (من المعاملات)
  // ═══════════════════════════════════════════════════════
  Widget _buildFinancialSummary() {
    if (_isLoadingTx) {
      return _sectionCard(
        title: 'الملخص المالي',
        icon: Icons.account_balance_wallet_rounded,
        iconGradient: const [_accentBlue, Color(0xFF2980B9)],
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final totalCharges = _txSummary['totalCharges'] ?? 0;
    final totalPayments = _txSummary['totalPayments'] ?? 0;
    final netBalance = _txSummary['netBalance'] ?? 0;
    final isNegative = (netBalance is num) && netBalance < 0;

    return _sectionCard(
      title: 'الملخص المالي',
      icon: Icons.account_balance_wallet_rounded,
      iconGradient: const [_accentBlue, Color(0xFF2980B9)],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cols = constraints.maxWidth > 600 ? 3 : 2;
          final spacing = 12.0;
          final cardW = (constraints.maxWidth - spacing * (cols - 1)) / cols;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              SizedBox(
                width: cardW,
                child: _clickableMiniStatCard(
                  'إجمالي الأجور',
                  '${_formatAmount(totalCharges)} د.ع',
                  Icons.trending_down,
                  _accentRed,
                  onTap: () => _showFilteredTransactions('Charge', 'الأجور'),
                ),
              ),
              SizedBox(
                width: cardW,
                child: _clickableMiniStatCard(
                  'إجمالي التسديدات',
                  '${_formatAmount(totalPayments)} د.ع',
                  Icons.trending_up,
                  _accentGreen,
                  onTap: () =>
                      _showFilteredTransactions('Payment', 'التسديدات'),
                ),
              ),
              SizedBox(
                width: cardW,
                child: _miniStatCard(
                  'الرصيد الصافي',
                  '${_formatAmount((netBalance is num ? netBalance : 0).abs())} د.ع',
                  isNegative ? Icons.warning_amber_rounded : Icons.check_circle,
                  isNegative ? _accentRed : _accentGreen,
                  subtitle: isNegative ? 'مدين' : 'لا يوجد مستحقات',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  3. الراتب والخصومات والمكافآت
  // ═══════════════════════════════════════════════════════
  Widget _buildSalarySection() {
    if (_isLoadingReport) {
      return _sectionCard(
        title: 'الراتب والاستحقاقات',
        icon: Icons.payments_rounded,
        iconGradient: const [_accentGreen, Color(0xFF1ABC9C)],
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final now = DateTime.now();
    final monthName = _arabicMonth(now.month);

    return _sectionCard(
      title: 'الراتب والاستحقاقات - $monthName ${now.year}',
      icon: Icons.payments_rounded,
      iconGradient: const [_accentGreen, Color(0xFF1ABC9C)],
      child: Column(
        children: [
          if (_salaryData != null) ...[
            // بطاقات الراتب
            _buildSalaryCards(),
            const SizedBox(height: 12),
            // تفاصيل الخصومات
            _buildDeductionsDetail(),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: const Color(0xFFF8F9FA),
              ),
              child: Column(
                children: [
                  Icon(Icons.info_outline,
                      color: _textGray.withOpacity(0.5), size: 40),
                  const SizedBox(height: 8),
                  Text(
                    'لم يتم إصدار كشف الراتب لهذا الشهر بعد',
                    style: GoogleFonts.cairo(color: _textGray, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  if (_attendanceReport != null) ...[
                    const SizedBox(height: 12),
                    _buildAttendanceOnlyInfo(),
                  ],
                ],
              ),
            ),
          ],
          if (_leavesData != null &&
              (_leavesData!['TotalRequests'] ?? 0) > 0) ...[
            const SizedBox(height: 12),
            _buildLeavesInfo(),
          ],
        ],
      ),
    );
  }

  Widget _buildSalaryCards() {
    final s = _salaryData!;
    final baseSalary = s['BaseSalary'] ?? 0;
    final allowances = s['Allowances'] ?? 0;
    final deductions = s['Deductions'] ?? 0;
    final bonuses = s['Bonuses'] ?? 0;
    final netSalary = s['NetSalary'] ?? 0;
    final status = s['Status'] ?? '';

    String statusText;
    Color statusColor;
    switch (status) {
      case 'Paid':
        statusText = 'مدفوع ✓';
        statusColor = _accentGreen;
        break;
      case 'Pending':
        statusText = 'قيد الانتظار';
        statusColor = _accentOrange;
        break;
      default:
        statusText = 'مسودة';
        statusColor = _textGray;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 700 ? 5 : 3;
        final spacing = 10.0;
        final cardW = (constraints.maxWidth - spacing * (cols - 1)) / cols;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: cardW,
              child: _salaryStatCard(
                'الراتب الأساسي',
                baseSalary,
                Icons.account_balance_wallet,
                _accentBlue,
              ),
            ),
            SizedBox(
              width: cardW,
              child: _salaryStatCard(
                'البدلات',
                allowances,
                Icons.workspace_premium,
                _accentTeal,
                onTap: () => _showAdjustmentsDialog(
                  title: 'البدلات',
                  type: 2, // Allowance
                  color: _accentTeal,
                  icon: Icons.workspace_premium,
                  attendanceItems: [],
                ),
              ),
            ),
            SizedBox(
              width: cardW,
              child: _salaryStatCard(
                'المكافآت',
                bonuses,
                Icons.star_rounded,
                _accentGreen,
                onTap: () => _showAdjustmentsDialog(
                  title: 'المكافآت',
                  type: 1, // Bonus
                  color: _accentGreen,
                  icon: Icons.star_rounded,
                  attendanceItems: [
                    if ((s['OvertimeBonus'] ?? 0) > 0)
                      _DeductionItem('مكافأة وقت إضافي',
                          s['OvertimeBonus'] ?? 0, _accentGreen),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: cardW,
              child: _salaryStatCard(
                'الخصومات',
                deductions,
                Icons.remove_circle_outline,
                _accentRed,
                onTap: () => _showAdjustmentsDialog(
                  title: 'الخصومات',
                  type: 0, // Deduction
                  color: _accentRed,
                  icon: Icons.remove_circle_outline,
                  attendanceItems: [
                    if ((s['LateDeduction'] ?? 0) > 0)
                      _DeductionItem(
                          'خصم التأخير', s['LateDeduction'] ?? 0, _accentRed),
                    if ((s['AbsentDeduction'] ?? 0) > 0)
                      _DeductionItem(
                          'خصم الغياب', s['AbsentDeduction'] ?? 0, _accentRed),
                    if ((s['EarlyDepartureDeduction'] ?? 0) > 0)
                      _DeductionItem('خصم الخروج المبكر',
                          s['EarlyDepartureDeduction'] ?? 0, _accentOrange),
                    if ((s['UnpaidLeaveDeduction'] ?? 0) > 0)
                      _DeductionItem('خصم إجازة بدون راتب',
                          s['UnpaidLeaveDeduction'] ?? 0, _accentOrange),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: cardW,
              child: _salaryStatCard(
                'صافي الراتب',
                netSalary,
                Icons.payments_rounded,
                const Color(0xFF2C3E50),
                badge: statusText,
                badgeColor: statusColor,
              ),
            ),
          ],
        );
      },
    );
  }

  /// بطاقة راتب موحدة التصميم (تطابق _miniStatCard)
  Widget _salaryStatCard(
    String label,
    dynamic amount,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
    String? badge,
    Color? badgeColor,
  }) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    '${_formatAmount(amount)} د.ع',
                    style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                Text(label,
                    style: GoogleFonts.cairo(fontSize: 11, color: _textGray)),
                if (badge != null)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: (badgeColor ?? color).withOpacity(0.12),
                    ),
                    child: Text(
                      badge,
                      style: GoogleFonts.cairo(
                        color: badgeColor ?? color,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.touch_app_rounded,
                size: 14, color: color.withOpacity(0.35)),
        ],
      ),
    );

    if (onTap != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: card),
      );
    }
    return card;
  }

  // _salaryItem و _netSalaryItem تم استبدالهما بـ _salaryStatCard الموحد أعلاه

  Widget _buildDeductionsDetail() {
    final s = _salaryData!;
    final items = <_DeductionItem>[
      _DeductionItem('خصم التأخير', s['LateDeduction'] ?? 0, _accentRed),
      _DeductionItem('خصم الغياب', s['AbsentDeduction'] ?? 0, _accentRed),
      _DeductionItem('خصم الخروج المبكر', s['EarlyDepartureDeduction'] ?? 0,
          _accentOrange),
      _DeductionItem(
          'خصم إجازة بدون راتب', s['UnpaidLeaveDeduction'] ?? 0, _accentOrange),
      _DeductionItem('مكافأة وقت إضافي', s['OvertimeBonus'] ?? 0, _accentGreen),
    ];

    // لا تعرض إذا كل القيم 0
    final hasValues = items.any((i) {
      final v = i.amount;
      return (v is num && v != 0);
    });
    if (!hasValues) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFF8F9FA),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تفاصيل الخصومات والمكافآت',
              style: GoogleFonts.cairo(
                  color: _textDark, fontSize: 13, fontWeight: FontWeight.bold)),
          const Divider(height: 16),
          ...items.where((i) {
            final v = i.amount;
            return (v is num && v != 0);
          }).map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: item.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item.label,
                          style: GoogleFonts.cairo(
                              color: _textSubtle, fontSize: 12)),
                    ),
                    Text(
                      '${_formatAmount(item.amount)} د.ع',
                      style: GoogleFonts.cairo(
                        color: item.color,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildAttendanceOnlyInfo() {
    final a = _attendanceReport!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: _accentBlue.withOpacity(0.05),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          _infoChip('أيام حضور', '${a['PresentDays'] ?? 0}', _accentGreen),
          _infoChip('تأخير', '${a['LateDays'] ?? 0}', _accentOrange),
          _infoChip('غياب', '${a['AbsentDays'] ?? 0}', _accentRed),
          _infoChip(
              'ساعات عمل',
              ((a['TotalWorkedMinutes'] ?? 0) / 60).toStringAsFixed(1),
              _accentBlue),
        ],
      ),
    );
  }

  Widget _buildLeavesInfo() {
    final l = _leavesData!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFFFF3E0),
        border: Border.all(color: _accentOrange.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.beach_access_rounded, color: _accentOrange, size: 20),
          const SizedBox(width: 10),
          Text('الإجازات: ',
              style: GoogleFonts.cairo(
                  color: _textDark, fontSize: 12, fontWeight: FontWeight.bold)),
          Text('${l['TotalRequests'] ?? 0} طلب',
              style: GoogleFonts.cairo(color: _textSubtle, fontSize: 12)),
          const SizedBox(width: 16),
          Text('أيام موافق عليها: ${l['ApprovedDays'] ?? 0}',
              style: GoogleFonts.cairo(
                  color: _accentGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  4. المعاملات
  // ═══════════════════════════════════════════════════════
  Widget _buildTransactionsSection() {
    return _sectionCard(
      title: 'المعاملات المالية ($_txTotal)',
      icon: Icons.receipt_long_rounded,
      iconGradient: const [_accentOrange, Color(0xFFE67E22)],
      child: _isLoadingTx
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _transactions.isEmpty
              ? _buildEmptyTx()
              : Column(
                  children: [
                    ..._transactions.map(_buildTxCard),
                    if (_txTotalPages > 1) _buildTxPagination(),
                  ],
                ),
    );
  }

  Widget _buildEmptyTx() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.receipt_long, size: 60, color: _textGray.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text('لا توجد معاملات مالية حالياً',
              style: GoogleFonts.cairo(color: _textGray, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildTxCard(dynamic tx) {
    final type = tx['type']?.toString();
    final category = tx['category']?.toString();
    final amount = tx['amount'];
    final createdAt = tx['createdAt']?.toString();
    final typeColor = _getTypeColor(type);
    final customerName = tx['customerName']?.toString();

    String title = _getCategoryName(category);
    final taskType = tx['taskType']?.toString();
    if (taskType != null && taskType.isNotEmpty) title = taskType;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFECF0F1)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: typeColor,
              shape: BoxShape.circle,
            ),
            child: Icon(_getTypeIcon(type), color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: typeColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_getTypeName(type),
                          style: GoogleFonts.cairo(
                              color: typeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(title,
                          style: GoogleFonts.cairo(
                              color: _textDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  children: [
                    if (customerName != null && customerName.isNotEmpty)
                      _txInfo(Icons.person_outline, customerName),
                    _txInfo(Icons.access_time, _formatDate(createdAt)),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '${type == 'Charge' ? '-' : '+'}${_formatAmount(amount)}',
            style: GoogleFonts.cairo(
              color: typeColor,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _txInfo(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: _textGray),
        const SizedBox(width: 3),
        Text(text,
            style: GoogleFonts.cairo(color: _textSubtle, fontSize: 11),
            overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _buildTxPagination() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_txPage > 1)
            TextButton(
              onPressed: () => _loadTransactions(page: _txPage - 1),
              child:
                  Text('السابق', style: GoogleFonts.cairo(color: _accentBlue)),
            ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFECF0F1)),
            ),
            child: Text('$_txPage / $_txTotalPages',
                style: GoogleFonts.cairo(color: _textDark, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          if (_txPage < _txTotalPages)
            TextButton(
              onPressed: () => _loadTransactions(page: _txPage + 1),
              child:
                  Text('التالي', style: GoogleFonts.cairo(color: _accentBlue)),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════
  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Color> iconGradient,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: _shadowColor, blurRadius: 12, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: iconGradient),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.cairo(
                    color: _textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _miniStatCard(String title, String value, IconData icon, Color color,
      {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    style: GoogleFonts.cairo(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                ),
                Text(title,
                    style: GoogleFonts.cairo(fontSize: 11, color: _textGray)),
                if (subtitle != null)
                  Text(subtitle,
                      style: GoogleFonts.cairo(
                          fontSize: 10,
                          color: color,
                          fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text('$label: ',
            style: GoogleFonts.cairo(color: _textSubtle, fontSize: 12)),
        Text(value,
            style: GoogleFonts.cairo(
                color: _textDark, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _getCategoryName(String? category) {
    switch (category) {
      case 'Maintenance':
        return 'صيانة';
      case 'Installation':
        return 'تركيب';
      case 'Collection':
        return 'تحصيل';
      case 'CashPayment':
        return 'تسديد نقدي';
      case 'Subscription':
        return 'شراء اشتراك';
      case 'Other':
        return 'أخرى';
      default:
        return category ?? '-';
    }
  }

  String _getTypeName(String? type) {
    switch (type) {
      case 'Charge':
        return 'أجور';
      case 'Payment':
        return 'تسديد';
      case 'Discount':
        return 'خصم';
      case 'Adjustment':
        return 'تعديل';
      default:
        return type ?? '-';
    }
  }

  Color _getTypeColor(String? type) {
    switch (type) {
      case 'Charge':
        return _accentRed;
      case 'Payment':
        return _accentGreen;
      case 'Discount':
        return _accentOrange;
      case 'Adjustment':
        return _accentBlue;
      default:
        return _textGray;
    }
  }

  IconData _getTypeIcon(String? type) {
    switch (type) {
      case 'Charge':
        return Icons.arrow_downward;
      case 'Payment':
        return Icons.arrow_upward;
      case 'Discount':
        return Icons.discount;
      case 'Adjustment':
        return Icons.tune;
      default:
        return Icons.receipt;
    }
  }

  String _arabicMonth(int month) {
    const months = [
      '',
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return months[month.clamp(1, 12)];
  }

  String _arabicDay(int weekday) {
    const days = [
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد'
    ];
    return days[(weekday - 1).clamp(0, 6)];
  }

  String _statusArabic(String? status) {
    switch (status) {
      case 'Present':
        return 'حاضر';
      case 'Late':
        return 'متأخر';
      case 'Absent':
        return 'غائب';
      case 'HalfDay':
        return 'نصف يوم';
      case 'EarlyDeparture':
        return 'خروج مبكر';
      case 'Leave':
        return 'إجازة';
      case 'Weekend':
        return 'عطلة';
      default:
        return status ?? '-';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'Present':
        return _accentGreen;
      case 'Late':
        return _accentOrange;
      case 'Absent':
        return _accentRed;
      case 'HalfDay':
        return const Color(0xFF9B59B6);
      case 'EarlyDeparture':
        return _accentOrange;
      case 'Leave':
        return _accentTeal;
      case 'Weekend':
        return _textGray;
      default:
        return _textGray;
    }
  }

  // ───── بطاقة إحصائية قابلة للنقر ─────
  Widget _clickableMiniStatCard(
      String title, String value, IconData icon, Color color,
      {required VoidCallback onTap}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            _miniStatCard(title, value, icon, color),
            Positioned(
              top: 6,
              left: 6,
              child: Icon(Icons.touch_app_rounded,
                  size: 14, color: color.withOpacity(0.4)),
            ),
          ],
        ),
      ),
    );
  }

  // ───── عرض المعاملات المفلترة ─────
  void _showFilteredTransactions(String typeFilter, String title) {
    final filtered = _transactions.where((tx) {
      return tx['type']?.toString() == typeFilter;
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: _bgPage,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // header
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _getTypeColor(typeFilter).withOpacity(0.1),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      Icon(_getTypeIcon(typeFilter),
                          color: _getTypeColor(typeFilter), size: 22),
                      const SizedBox(width: 10),
                      Text('$title (${filtered.length})',
                          style: GoogleFonts.cairo(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _textDark)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // body
                Flexible(
                  child: filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_rounded,
                                  size: 48, color: _textGray.withOpacity(0.3)),
                              const SizedBox(height: 8),
                              Text('لا توجد عمليات',
                                  style: GoogleFonts.cairo(
                                      color: _textGray, fontSize: 14)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 8, thickness: 0.5),
                          itemBuilder: (_, i) {
                            final tx = filtered[i];
                            final amount = tx['amount'];
                            final category = tx['category']?.toString();
                            final createdAt = tx['createdAt']?.toString();
                            final customer = tx['customerName']?.toString();
                            final notes = tx['notes']?.toString();
                            String dateStr = '';
                            if (createdAt != null) {
                              try {
                                final d = DateTime.parse(createdAt);
                                dateStr = '${d.year}/${d.month}/${d.day}';
                              } catch (_) {}
                            }
                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: _bgCard,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: _getTypeColor(typeFilter)
                                          .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(_getTypeIcon(typeFilter),
                                        color: _getTypeColor(typeFilter),
                                        size: 18),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(_getCategoryName(category),
                                            style: GoogleFonts.cairo(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: _textDark)),
                                        if (customer != null &&
                                            customer.isNotEmpty)
                                          Text(customer,
                                              style: GoogleFonts.cairo(
                                                  fontSize: 11,
                                                  color: _textSubtle)),
                                        if (notes != null && notes.isNotEmpty)
                                          Text(notes,
                                              style: GoogleFonts.cairo(
                                                  fontSize: 10,
                                                  color: _textGray),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${_formatAmount(amount)} د.ع',
                                        style: GoogleFonts.cairo(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: _getTypeColor(typeFilter)),
                                      ),
                                      Text(dateStr,
                                          style: GoogleFonts.cairo(
                                              fontSize: 10, color: _textGray)),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ───── عرض تفاصيل بند الراتب مع جلب العمليات الفعلية من الخادم ─────
  void _showAdjustmentsDialog({
    required String title,
    required int type, // 0=Deduction, 1=Bonus, 2=Allowance
    required Color color,
    required IconData icon,
    List<_DeductionItem> attendanceItems = const [],
  }) {
    final now = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: _bgPage,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 550),
            child: _AdjustmentsDialogContent(
              title: title,
              type: type,
              color: color,
              icon: icon,
              attendanceItems: attendanceItems,
              month: now.month,
              year: now.year,
              attendanceApi: _attendanceApi,
              formatAmount: _formatAmount,
              arabicMonth: _arabicMonth,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  سجل الحضور اليومي
  // ═══════════════════════════════════════════════════════
  Widget _buildDailyAttendanceSection() {
    return _sectionCard(
      title: 'سجل الحضور والانصراف',
      icon: Icons.calendar_month_rounded,
      iconGradient: const [Color(0xFF8E44AD), Color(0xFF9B59B6)],
      child: _isLoadingReport
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : (_dailyRecords == null || _dailyRecords!.isEmpty)
              ? Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    children: [
                      Icon(Icons.event_busy,
                          size: 48, color: _textGray.withOpacity(0.3)),
                      const SizedBox(height: 8),
                      Text('لا توجد سجلات حضور لهذا الشهر',
                          style: GoogleFonts.cairo(
                              color: _textGray, fontSize: 13)),
                    ],
                  ),
                )
              : _buildDailyRecordsTable(),
    );
  }

  Widget _buildDailyRecordsTable() {
    final records = _dailyRecords!;
    return Column(
      children: [
        // header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF2C3E50).withOpacity(0.06),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              _headerCell('التاريخ', flex: 2),
              _headerCell('اليوم', flex: 2),
              _headerCell('الحالة', flex: 2),
              _headerCell('الدخول', flex: 2),
              _headerCell('الخروج', flex: 2),
              _headerCell('ساعات العمل', flex: 2),
              _headerCell('تأخير', flex: 1),
              _headerCell('إضافي', flex: 1),
            ],
          ),
        ),
        const Divider(height: 1),
        // data rows
        ...records.asMap().entries.map((entry) {
          final i = entry.key;
          final r = entry.value as Map<String, dynamic>;
          final dateStr = r['Date']?.toString() ?? '';
          final checkIn = r['CheckIn']?.toString() ?? '-';
          final checkOut = r['CheckOut']?.toString() ?? '-';
          final status = r['Status']?.toString();
          final lateMins = r['LateMinutes'] ?? 0;
          final overtimeMins = r['OvertimeMinutes'] ?? 0;
          final workedMins = r['WorkedMinutes'] ?? 0;

          DateTime? date;
          String dayName = '';
          String formattedDate = dateStr;
          try {
            date = DateTime.parse(dateStr);
            dayName = _arabicDay(date.weekday);
            formattedDate = '${date.month}/${date.day}';
          } catch (_) {}

          final isFriday = date?.weekday == 5;
          final isWeekend = status == 'Weekend' || isFriday;
          final rowColor = isWeekend
              ? const Color(0xFFF0F0F0)
              : i.isEven
                  ? Colors.white
                  : const Color(0xFFFAFAFA);

          final workedHours = workedMins is num
              ? '${(workedMins / 60).floor()}:${(workedMins % 60).toString().padLeft(2, '0')}'
              : '-';

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: rowColor,
              border: Border(
                  bottom: BorderSide(color: Colors.grey.withOpacity(0.1))),
            ),
            child: Row(
              children: [
                _dataCell(formattedDate, flex: 2),
                _dataCell(dayName,
                    flex: 2, color: isFriday ? _accentRed : null),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _statusArabic(status),
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _statusColor(status),
                        ),
                      ),
                    ),
                  ),
                ),
                _dataCell(checkIn == 'null' || checkIn.isEmpty ? '-' : checkIn,
                    flex: 2, color: _accentGreen),
                _dataCell(
                    checkOut == 'null' || checkOut.isEmpty ? '-' : checkOut,
                    flex: 2,
                    color: _accentRed),
                _dataCell(workedHours, flex: 2),
                _dataCell(
                  lateMins is num && lateMins > 0 ? '$lateMins د' : '-',
                  flex: 1,
                  color: lateMins is num && lateMins > 0 ? _accentOrange : null,
                ),
                _dataCell(
                  overtimeMins is num && overtimeMins > 0
                      ? '$overtimeMins د'
                      : '-',
                  flex: 1,
                  color: overtimeMins is num && overtimeMins > 0
                      ? _accentGreen
                      : null,
                ),
              ],
            ),
          );
        }),
        // summary row
        if (_attendanceReport != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: _accentBlue.withOpacity(0.06),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      _summaryChip(
                          'حضور',
                          '${_attendanceReport!['PresentDays'] ?? 0}',
                          _accentGreen),
                      _summaryChip(
                          'تأخير',
                          '${_attendanceReport!['LateDays'] ?? 0}',
                          _accentOrange),
                      _summaryChip(
                          'غياب',
                          '${_attendanceReport!['AbsentDays'] ?? 0}',
                          _accentRed),
                      _summaryChip(
                        'إجمالي ساعات',
                        '${((_attendanceReport!['TotalWorkedMinutes'] ?? 0) / 60).toStringAsFixed(1)}',
                        _accentBlue,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _headerCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Center(
        child: Text(
          text,
          style: GoogleFonts.cairo(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: _textDark,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _dataCell(String text, {int flex = 1, Color? color}) {
    return Expanded(
      flex: flex,
      child: Center(
        child: Text(
          text,
          style: GoogleFonts.cairo(
            fontSize: 11,
            color: color ?? _textSubtle,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _summaryChip(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text('$label: ',
            style: GoogleFonts.cairo(fontSize: 11, color: _textSubtle)),
        Text(value,
            style: GoogleFonts.cairo(
                fontSize: 11, color: _textDark, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════
//  نموذج بيانات إحصائية
// ═══════════════════════════════════════════════════════
class _StatData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatData(this.label, this.value, this.icon, this.color);
}

class _DeductionItem {
  final String label;
  final dynamic amount;
  final Color color;
  const _DeductionItem(this.label, this.amount, this.color);
}

// ═══════════════════════════════════════════════════════
//  محتوى حوار الخصومات/المكافآت/البدلات (يجلب من الخادم)
// ═══════════════════════════════════════════════════════
class _AdjustmentsDialogContent extends StatefulWidget {
  final String title;
  final int type;
  final Color color;
  final IconData icon;
  final List<_DeductionItem> attendanceItems;
  final int month;
  final int year;
  final AttendanceApiService attendanceApi;
  final String Function(dynamic) formatAmount;
  final String Function(int) arabicMonth;

  const _AdjustmentsDialogContent({
    required this.title,
    required this.type,
    required this.color,
    required this.icon,
    required this.attendanceItems,
    required this.month,
    required this.year,
    required this.attendanceApi,
    required this.formatAmount,
    required this.arabicMonth,
  });

  @override
  State<_AdjustmentsDialogContent> createState() =>
      _AdjustmentsDialogContentState();
}

class _AdjustmentsDialogContentState extends State<_AdjustmentsDialogContent> {
  static const _textDark = Color(0xFF2C3E50);
  static const _textGray = Color(0xFF95A5A6);

  bool _isLoading = true;
  List<Map<String, dynamic>> _records = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAdjustments();
  }

  Future<void> _fetchAdjustments() async {
    try {
      final authUser = VpsAuthService.instance.currentUser;
      final userId = authUser?.id;
      final companyId = VpsAuthService.instance.currentCompanyId;

      if (userId == null) {
        setState(() {
          _error = 'لا يمكن تحديد المستخدم';
          _isLoading = false;
        });
        return;
      }

      final data = await widget.attendanceApi.getEmployeeAdjustments(
        companyId: companyId,
        userId: userId,
        month: widget.month,
        year: widget.year,
        type: widget.type,
      );

      if (!mounted) return;

      final List<dynamic> rawRecords = data['data'] ?? [];
      setState(() {
        _records = rawRecords
            .map((r) => r as Map<String, dynamic>)
            .where((r) => r['IsApplied'] == true || r['isApplied'] == true)
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching adjustments: $e');
      if (mounted) {
        setState(() {
          _error = 'تعذّر جلب البيانات';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // حساب الإجمالي (عناصر الحضور + العمليات اليدوية)
    double attendanceTotal = widget.attendanceItems.fold<double>(0.0, (sum, i) {
      final v = i.amount;
      return sum + (v is num ? v.toDouble() : 0);
    });
    double manualTotal = _records.fold<double>(0.0, (sum, r) {
      final v = r['Amount'] ?? r['amount'] ?? 0;
      return sum + (v is num ? v.toDouble() : 0);
    });
    double grandTotal = attendanceTotal + manualTotal;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── العنوان ──
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, color: widget.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: GoogleFonts.cairo(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: _textDark)),
                    Text(
                      '${widget.arabicMonth(widget.month)} ${widget.year}',
                      style: GoogleFonts.cairo(fontSize: 11, color: _textGray),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── المحتوى القابل للتمرير ──
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── عناصر مبنية على الحضور (تأخير، غياب..) ──
                  if (widget.attendanceItems.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('حسب الحضور',
                            style: GoogleFonts.cairo(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _textGray)),
                      ),
                    ),
                    ...widget.attendanceItems.map((item) => _buildItemRow(
                          item.label,
                          item.amount,
                          item.color,
                        )),
                  ],

                  // ── العمليات اليدوية من الخادم ──
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(_error!,
                          style: GoogleFonts.cairo(
                              fontSize: 13, color: _textGray)),
                    )
                  else if (_records.isNotEmpty) ...[
                    if (widget.attendanceItems.isNotEmpty)
                      const Divider(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('عمليات يدوية',
                            style: GoogleFonts.cairo(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _textGray)),
                      ),
                    ),
                    ..._records.map((r) => _buildDetailedCard(r)),
                  ] else if (widget.attendanceItems.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        children: [
                          Icon(Icons.info_outline,
                              size: 36, color: _textGray.withOpacity(0.4)),
                          const SizedBox(height: 8),
                          Text('لا توجد عمليات لهذا الشهر',
                              style: GoogleFonts.cairo(
                                  fontSize: 13, color: _textGray)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const Divider(height: 20),
          // ── الإجمالي ──
          Row(
            children: [
              Text('الإجمالي',
                  style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _textDark)),
              const Spacer(),
              Text(
                '${widget.formatAmount(grandTotal)} د.ع',
                style: GoogleFonts.cairo(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: widget.color),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(String label, dynamic amount, Color color,
      {String? subtitle}) {
    final v = amount;
    final isZero = v is num && v == 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isZero ? const Color(0xFFF5F5F5) : color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isZero ? const Color(0xFFE0E0E0) : color.withOpacity(0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isZero ? _textGray.withOpacity(0.3) : color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.cairo(
                        fontSize: 13, color: isZero ? _textGray : _textDark)),
                if (subtitle != null)
                  Text(subtitle,
                      style: GoogleFonts.cairo(fontSize: 11, color: _textGray)),
              ],
            ),
          ),
          Text(
            '${widget.formatAmount(v)} د.ع',
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isZero ? _textGray : color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedCard(Map<String, dynamic> r) {
    final amount = r['Amount'] ?? r['amount'] ?? 0;
    final category = '${r['Category'] ?? r['category'] ?? ''}'.trim();
    final description = '${r['Description'] ?? r['description'] ?? ''}'.trim();
    final notes = '${r['Notes'] ?? r['notes'] ?? ''}'.trim();
    final createdByName =
        '${r['CreatedByName'] ?? r['createdByName'] ?? ''}'.trim();
    final isRecurring = r['IsRecurring'] == true || r['isRecurring'] == true;
    final createdAtRaw = r['CreatedAt'] ?? r['createdAt'] ?? '';
    String createdAtFormatted = '';
    if (createdAtRaw is String && createdAtRaw.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAtRaw).toLocal();
        createdAtFormatted =
            '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── السطر الأول: التصنيف + المبلغ ──
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.isNotEmpty ? category : widget.title,
                  style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _textDark),
                ),
              ),
              Text(
                '${widget.formatAmount(amount)} د.ع',
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: widget.color,
                ),
              ),
            ],
          ),
          // ── الوصف ──
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            _detailRow(Icons.description_outlined, 'الوصف', description),
          ],
          // ── الملاحظات ──
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            _detailRow(Icons.sticky_note_2_outlined, 'ملاحظات', notes),
          ],
          const SizedBox(height: 8),
          // ── السطر السفلي: من أنشأها + التاريخ + متكرر ──
          Row(
            children: [
              if (createdByName.isNotEmpty) ...[
                Icon(Icons.person_outline,
                    size: 14, color: _textGray.withOpacity(0.7)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    createdByName,
                    style: GoogleFonts.cairo(fontSize: 11, color: _textGray),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (createdAtFormatted.isNotEmpty) ...[
                Icon(Icons.calendar_today,
                    size: 13, color: _textGray.withOpacity(0.7)),
                const SizedBox(width: 4),
                Text(
                  createdAtFormatted,
                  style: GoogleFonts.cairo(fontSize: 11, color: _textGray),
                ),
                const SizedBox(width: 12),
              ],
              if (isRecurring)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF39C12).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.repeat,
                          size: 12, color: Color(0xFFF39C12)),
                      const SizedBox(width: 4),
                      Text('متكرر',
                          style: GoogleFonts.cairo(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFF39C12))),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 14, color: _textGray.withOpacity(0.7)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.cairo(fontSize: 12, color: _textGray),
              children: [
                TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


