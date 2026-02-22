/// اسم الصفحة: الحضور والانصراف
/// وصف الصفحة: صفحة تسجيل حضور وانصراف الموظفين مع تتبع الموقع
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../services/attendance_api_service.dart';
import '../services/vps_auth_service.dart';

class AttendancePage extends StatefulWidget {
  final String username;
  final String center;
  final String permissions;

  const AttendancePage({
    super.key,
    required this.username,
    required this.center,
    required this.permissions,
  });
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage>
    with TickerProviderStateMixin {
  static const Color _primaryDark = Color(0xFF0A1628);
  static const Color _primaryBlue = Color(0xFF1E88E5);
  static const Color _accentCyan = Color(0xFF00BCD4);

  final AttendanceApiService _attendanceApi = AttendanceApiService.instance;
  int _attendanceCount = 0;
  int _lateDays = 0;
  int _totalLateMinutes = 0;
  int _totalOvertimeMinutes = 0;
  int _totalWorkedMinutes = 0;
  final TextEditingController _codeController = TextEditingController();
  String? _savedCode;
  String? _userId;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _isCheckingIn = false;
  bool _isCheckingOut = false;

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
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fetchAttendanceCount();
    _loadSavedCode();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applySystemUi());
  }

  void _applySystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: _primaryDark,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ));
  }

  Future<void> _fetchAttendanceCount() async {
    try {
      final authUser = VpsAuthService.instance.currentUser;
      final realUserId = authUser?.id ?? _userId ?? widget.username;
      final data = await _attendanceApi.getMonthlyAttendance(
        userId: realUserId,
      );
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

  Future<void> _loadSavedCode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedCode = prefs.getString('attendance_code') ?? '';
      _codeController.text =
          _savedCode ?? ''; // إظهار الكود في مربع النص للمدير
    });
  }

  Future<void> _saveCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('attendance_code', code);
    setState(() {
      _savedCode = code;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الكود بنجاح!')),
      );
    }
  }

  Future<void> _submitAttendance(String attendanceType) async {
    try {
      // الحصول على UserId الحقيقي من VpsAuthService (Layer 3)
      final authUser = VpsAuthService.instance.currentUser;
      final realUserId = authUser?.id ?? _userId ?? widget.username;

      // الحصول على اسم المركز المعين للموظف
      final centerName = authUser?.id != null ? widget.center : widget.center;

      // الحصول على الموقع الحالي دائماً (Layer 2 - السيرفر يتحقق)
      double? userLat;
      double? userLng;
      try {
        // التحقق من صلاحيات الموقع
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.deniedForever) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('يرجى تفعيل صلاحية الموقع من إعدادات النظام')),
          );
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
        // السماح بالمتابعة بدون موقع - السيرفر سيقرر
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

      // التحقق من استجابة السيرفر
      if (result['success'] == false) {
        final code = result['code'] ?? '';
        final message = result['message'] ?? result['error'] ?? 'خطأ غير معروف';

        // رسائل مخصصة حسب نوع الرفض
        IconData icon;
        Color color;
        if (code == 'DEVICE_MISMATCH') {
          icon = Icons.devices_other;
          color = Colors.red;
        } else if (code == 'OUT_OF_RANGE') {
          icon = Icons.location_off;
          color = Colors.orange;
        } else {
          icon = Icons.error_outline;
          color = Colors.red;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: color,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      // بناء رسالة النجاح مع حالة التأخير/الوقت الإضافي
      final record = result['record'] ?? result['Record'];
      String successMsg = 'تم تسجيل $attendanceType بنجاح!';
      Color successColor = Colors.green;

      if (record is Map) {
        final status = '${record['Status'] ?? record['status'] ?? ''}';
        final lateMins = record['LateMinutes'] ?? record['lateMinutes'];
        final overtime = record['OvertimeMinutes'] ?? record['overtimeMinutes'];
        final workedMins = record['WorkedMinutes'] ?? record['workedMinutes'];

        if (status == 'Late' || status == '1') {
          successMsg += '\n⚠️ متأخر $lateMins دقيقة';
          successColor = Colors.orange;
        }
        if (overtime != null && overtime > 0) {
          successMsg += '\n⏰ وقت إضافي: $overtime دقيقة';
        }
        if (workedMins != null && workedMins > 0 && attendanceType == 'خروج') {
          final hours = (workedMins / 60).toStringAsFixed(1);
          successMsg += '\n⏱️ ساعات العمل: $hours ساعة';
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(successMsg)),
            ],
          ),
          backgroundColor: successColor,
          duration: const Duration(seconds: 5),
        ),
      );

      _fetchAttendanceCount();
    } catch (error) {
      debugPrint('Error submitting attendance: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $error')),
      );
    }
  }

  Future<List<double>?> _getCenterLocation(String centerId) async {
    try {
      final centers = await _attendanceApi.getCenters();
      final center = centers.firstWhere(
        (c) => (c['Name'] ?? c['name'] ?? '').toString() == centerId,
        orElse: () => {},
      );
      if (center.isEmpty) return null;
      final lat = double.tryParse(
          (center['Latitude'] ?? center['latitude'] ?? '').toString());
      final lng = double.tryParse(
          (center['Longitude'] ?? center['longitude'] ?? '').toString());
      if (lat != null && lng != null) return [lat, lng];
      return null;
    } catch (e) {
      debugPrint('Error fetching center location: $e');
      return null;
    }
  }

  bool _isWithinAllowedDistance(
      double userLat, double userLng, List<double> centerLocation) {
    final distance = Geolocator.distanceBetween(
        userLat, userLng, centerLocation[0], centerLocation[1]);
    return distance <= 150;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            child: Column(
              children: [
                // ── الهيدر ──
                _buildHeader(),
                const SizedBox(height: 24),
                // ── الإحصائيات ──
                _buildStatsRow(),
                const SizedBox(height: 24),
                // ── كود الأمان ──
                _buildCodeCard(),
                const Spacer(),
                const SizedBox(height: 16),
                // ── أزرار الحضور والانصراف ──
                _buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  //  الهيدر
  // ═══════════════════════════════════════
  Widget _buildHeader() {
    return Row(
      children: [
        // زر رجوع
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_forward_ios_rounded,
              color: Colors.white54, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.05),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(width: 14),
        // أيقونة نابضة
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                colors: [_primaryBlue, _accentCyan],
              ),
            ),
            child: const Icon(Icons.fingerprint_rounded,
                color: Colors.white, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        // العنوان
        const Expanded(
          child: Text(
            'نظام البصمة',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        // اسم المستخدم + المركز
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.username,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              widget.center,
              style: TextStyle(
                color: _accentCyan.withOpacity(0.7),
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        // الساعة
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _primaryBlue.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: StreamBuilder(
            stream: Stream.periodic(const Duration(seconds: 1)),
            builder: (context, snapshot) {
              final now = DateTime.now();
              return Text(
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: _accentCyan,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  //  صف الإحصائيات
  // ═══════════════════════════════════════
  Widget _buildStatsRow() {
    final stats = [
      _StatItem('حضور', '$_attendanceCount', Icons.check_circle_outline_rounded,
          const Color(0xFF4CAF50)),
      _StatItem('تأخير', '$_lateDays', Icons.schedule_rounded,
          const Color(0xFFFF9800)),
      _StatItem('د. تأخير', '$_totalLateMinutes', Icons.timer_off_outlined,
          const Color(0xFFf44336)),
      _StatItem('د. إضافي', '$_totalOvertimeMinutes', Icons.more_time_rounded,
          const Color(0xFF2196F3)),
      _StatItem('ساعات العمل', (_totalWorkedMinutes / 60).toStringAsFixed(1),
          Icons.work_history_outlined, const Color(0xFF9C27B0)),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: stats
            .map((s) => Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(s.icon, color: s.color, size: 20),
                      const SizedBox(height: 8),
                      Text(
                        s.value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.label,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 11,
                        ),
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

  // ═══════════════════════════════════════
  //  بطاقة كود الأمان
  // ═══════════════════════════════════════
  Widget _buildCodeCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // حقل الإدخال للمدير
          if (widget.permissions == 'مدير') ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'أدخل أو عدّل الكود...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.2),
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      prefixIcon: Icon(Icons.edit_outlined,
                          color: Colors.white.withOpacity(0.3), size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      isDense: true,
                    ),
                    onSubmitted: (v) => _saveCode(v),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _saveCode(_codeController.text),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('حفظ'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          // عرض الكود
          Icon(Icons.vpn_key_rounded,
              color: _accentCyan.withOpacity(0.3), size: 20),
          const SizedBox(height: 4),
          Text(
            _savedCode?.isNotEmpty == true ? _savedCode! : '---',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: _savedCode?.isNotEmpty == true
                  ? _accentCyan
                  : Colors.white.withOpacity(0.2),
              letterSpacing: 4,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'كود الأمان',
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  //  أزرار الحضور والانصراف
  // ═══════════════════════════════════════
  Widget _buildActionButtons() {
    return SizedBox(
      height: 100,
      child: Row(
        children: [
          // زر تسجيل الدخول
          Expanded(
            child: _ActionBtn(
              label: 'تسجيل الدخول',
              icon: Icons.login_rounded,
              colors: const [Color(0xFF43A047), Color(0xFF66BB6A)],
              isLoading: _isCheckingIn,
              onTap: () async {
                setState(() => _isCheckingIn = true);
                await _submitAttendance('دخول');
                if (mounted) setState(() => _isCheckingIn = false);
              },
            ),
          ),
          const SizedBox(width: 20),
          // زر تسجيل الخروج
          Expanded(
            child: _ActionBtn(
              label: 'تسجيل الخروج',
              icon: Icons.logout_rounded,
              colors: const [Color(0xFFE53935), Color(0xFFEF5350)],
              isLoading: _isCheckingOut,
              onTap: () async {
                setState(() => _isCheckingOut = true);
                await _submitAttendance('خروج');
                if (mounted) setState(() => _isCheckingOut = false);
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    ));
    _codeController.dispose();
    super.dispose();
  }
}

// ═══════════════════════════════════════
//  نموذج بيانات الإحصائية
// ═══════════════════════════════════════
class _StatItem {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatItem(this.label, this.value, this.icon, this.color);
}

// ═══════════════════════════════════════
//  زر الإجراء
// ═══════════════════════════════════════
class _ActionBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final bool isLoading;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.colors,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: _hovered
            ? (Matrix4.identity()..translate(0.0, -3.0))
            : Matrix4.identity(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.isLoading ? null : widget.onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.colors,
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(_hovered ? 0.25 : 0.1),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.colors[0].withOpacity(_hovered ? 0.5 : 0.25),
                    blurRadius: _hovered ? 24 : 12,
                    spreadRadius: _hovered ? 2 : 0,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: widget.isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 3),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(widget.icon, color: Colors.white, size: 30),
                        const SizedBox(height: 8),
                        Text(
                          widget.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
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
