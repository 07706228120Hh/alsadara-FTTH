/// صفحة شاشتي - لوحة الموظف الشخصية
/// تحتوي على: البصمة + المعاملات المالية + الراتب + الخصومات والمكافآت
library;

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../services/attendance_api_service.dart';
import '../services/vps_auth_service.dart';
import '../services/api/api_client.dart';

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

  // ── حالة البصمة ──
  bool _isCheckingIn = false;
  bool _isCheckingOut = false;
  int _attendanceCount = 0;
  int _lateDays = 0;
  int _totalLateMinutes = 0;
  int _totalOvertimeMinutes = 0;
  int _totalWorkedMinutes = 0;
  String? _savedCode;
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
    _loadSavedCode();
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

  Future<void> _loadSavedCode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedCode = prefs.getString('attendance_code') ?? '';
    });
  }

  Future<void> _submitAttendance(String attendanceType) async {
    try {
      final authUser = VpsAuthService.instance.currentUser;
      final realUserId = authUser?.id ?? _userId ?? widget.username;
      final centerName = widget.center;

      double? userLat;
      double? userLng;
      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.deniedForever) {
          if (!mounted) return;
          _showSnack(
              'يرجى تفعيل صلاحية الموقع من إعدادات النظام', Colors.orange);
          return;
        }
        final userPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
        userLat = userPosition.latitude;
        userLng = userPosition.longitude;
      } catch (e) {
        debugPrint('خطأ في الحصول على الموقع: $e');
      }

      Map<String, dynamic> result;
      if (attendanceType == 'خروج') {
        result = await _attendanceApi.checkOut(
          userId: realUserId,
          latitude: userLat,
          longitude: userLng,
        );
      } else {
        result = await _attendanceApi.checkIn(
          userId: realUserId,
          userName: widget.username,
          centerName: centerName,
          latitude: userLat,
          longitude: userLng,
          securityCode: _savedCode,
        );
      }

      if (!mounted) return;

      if (result['success'] == false) {
        final message = result['message'] ?? result['error'] ?? 'خطأ غير معروف';
        _showSnack(message, _accentRed);
        return;
      }

      // رسالة النجاح
      final record = result['record'] ?? result['Record'];
      String successMsg = 'تم تسجيل $attendanceType بنجاح!';
      Color successColor = _accentGreen;

      if (record is Map) {
        final status = '${record['Status'] ?? record['status'] ?? ''}';
        final lateMins = record['LateMinutes'] ?? record['lateMinutes'];
        final overtime = record['OvertimeMinutes'] ?? record['overtimeMinutes'];
        final workedMins = record['WorkedMinutes'] ?? record['workedMinutes'];

        if (status == 'Late' || status == '1') {
          successMsg += '\n⚠️ متأخر $lateMins دقيقة';
          successColor = _accentOrange;
        }
        if (overtime != null && overtime > 0) {
          successMsg += '\n⏰ وقت إضافي: $overtime دقيقة';
        }
        if (workedMins != null && workedMins > 0 && attendanceType == 'خروج') {
          final hours = (workedMins / 60).toStringAsFixed(1);
          successMsg += '\n⏱️ ساعات العمل: $hours ساعة';
        }
      }

      _showSnack(successMsg, successColor);
      _fetchAttendanceCount();
    } catch (error) {
      debugPrint('Error submitting attendance: $error');
      if (!mounted) return;
      _showSnack('خطأ: $error', _accentRed);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.cairo(color: Colors.white)),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
      ),
    );
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
                      // ═══ 1. قسم البصمة ═══
                      _buildAttendanceSection(),
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
  //  1. قسم البصمة
  // ═══════════════════════════════════════════════════════
  Widget _buildAttendanceSection() {
    return _sectionCard(
      title: 'البصمة',
      icon: Icons.fingerprint_rounded,
      iconGradient: const [Color(0xFF667eea), Color(0xFF764ba2)],
      child: Column(
        children: [
          // إحصائيات الحضور
          _buildAttendanceStats(),
          const SizedBox(height: 16),
          // أزرار تسجيل الدخول والخروج
          _buildAttendanceButtons(),
        ],
      ),
    );
  }

  Widget _buildAttendanceStats() {
    final stats = [
      _StatData('حضور', '$_attendanceCount', Icons.check_circle_outline,
          _accentGreen),
      _StatData('تأخير', '$_lateDays', Icons.schedule_rounded, _accentOrange),
      _StatData('د. تأخير', '$_totalLateMinutes', Icons.timer_off_outlined,
          _accentRed),
      _StatData('د. إضافي', '$_totalOvertimeMinutes', Icons.more_time_rounded,
          _accentBlue),
      _StatData('ساعات عمل', (_totalWorkedMinutes / 60).toStringAsFixed(1),
          Icons.work_history_outlined, const Color(0xFF9B59B6)),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFFF8F9FA),
        border: Border.all(color: const Color(0xFFECF0F1)),
      ),
      child: Row(
        children: stats
            .map((s) => Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(s.icon, color: s.color, size: 18),
                      const SizedBox(height: 6),
                      Text(
                        s.value,
                        style: GoogleFonts.cairo(
                          color: _textDark,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.label,
                        style:
                            GoogleFonts.cairo(color: _textGray, fontSize: 10),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildAttendanceButtons() {
    return Row(
      children: [
        // زر تسجيل الدخول
        Expanded(
          child: _AttendanceBtn(
            label: 'تسجيل الدخول',
            icon: Icons.login_rounded,
            gradient: const [Color(0xFF43A047), Color(0xFF66BB6A)],
            isLoading: _isCheckingIn,
            onTap: () async {
              setState(() => _isCheckingIn = true);
              await _submitAttendance('دخول');
              if (mounted) setState(() => _isCheckingIn = false);
            },
          ),
        ),
        const SizedBox(width: 14),
        // زر تسجيل الخروج
        Expanded(
          child: _AttendanceBtn(
            label: 'تسجيل الخروج',
            icon: Icons.logout_rounded,
            gradient: const [Color(0xFFE53935), Color(0xFFEF5350)],
            isLoading: _isCheckingOut,
            onTap: () async {
              setState(() => _isCheckingOut = true);
              await _submitAttendance('خروج');
              if (mounted) setState(() => _isCheckingOut = false);
            },
          ),
        ),
      ],
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
                onTap: () => _showFilteredTransactions('Adjustment', 'البدلات'),
              ),
            ),
            SizedBox(
              width: cardW,
              child: _salaryStatCard(
                'المكافآت',
                bonuses,
                Icons.star_rounded,
                _accentGreen,
                onTap: () =>
                    _showFilteredTransactions('Adjustment', 'المكافآت'),
              ),
            ),
            SizedBox(
              width: cardW,
              child: _salaryStatCard(
                'الخصومات',
                deductions,
                Icons.remove_circle_outline,
                _accentRed,
                onTap: () => _showFilteredTransactions('Discount', 'الخصومات'),
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
//  زر البصمة
// ═══════════════════════════════════════════════════════
class _AttendanceBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final bool isLoading;
  final VoidCallback onTap;

  const _AttendanceBtn({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_AttendanceBtn> createState() => _AttendanceBtnState();
}

class _AttendanceBtnState extends State<_AttendanceBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 70,
        transform: _hovered
            ? (Matrix4.identity()..translate(0.0, -2.0))
            : Matrix4.identity(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.isLoading ? null : widget.onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.gradient,
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(_hovered ? 0.3 : 0.1),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.gradient[0].withOpacity(_hovered ? 0.4 : 0.2),
                    blurRadius: _hovered ? 16 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: widget.isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(widget.icon, color: Colors.white, size: 24),
                        const SizedBox(width: 10),
                        Text(
                          widget.label,
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
