/// اسم الصفحة: الحضور والانصراف
/// وصف الصفحة: صفحة تسجيل حضور وانصراف الموظفين مع تتبع الموقع
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/responsive_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
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
  // ── الألوان ──
  static const Color _bgDark = Color(0xFF0B1120);
  static const Color _cardDark = Color(0xFF131C2E);
  static const Color _blue = Color(0xFF3B82F6);
  static const Color _cyan = Color(0xFF06B6D4);
  static const Color _green = Color(0xFF22C55E);
  static const Color _red = Color(0xFFEF4444);
  static const Color _orange = Color(0xFFF59E0B);
  static const Color _purple = Color(0xFF8B5CF6);
  static const Color _textMuted = Color(0xFF64748B);

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
      systemNavigationBarColor: _bgDark,
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
      debugPrint('Error fetching attendance count');
    }
  }

  Future<void> _loadSavedCode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedCode = prefs.getString('attendance_code') ?? '';
      _codeController.text = _savedCode ?? '';
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
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('تم حفظ الكود بنجاح!'),
            ],
          ),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _submitAttendance(String attendanceType) async {
    try {
      final authUser = VpsAuthService.instance.currentUser;
      final realUserId = authUser?.id ?? _userId ?? widget.username;
      final centerName = authUser?.id != null ? widget.center : widget.center;

      double? userLat;
      double? userLng;
      try {
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

        if (userPosition.isMocked) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('تم اكتشاف تطبيق تزييف الموقع! أوقفه وحاول مرة أخرى'),
                backgroundColor: _red,
                duration: const Duration(seconds: 5),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
              ),
            );
          }
          return;
        }
        if (userPosition.accuracy < 1.0 || userPosition.accuracy > 500) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('دقة الموقع غير طبيعية — تأكد من إيقاف تطبيقات الموقع الوهمي'),
                backgroundColor: _orange,
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.all(16),
              ),
            );
          }
          return;
        }

        userLat = userPosition.latitude;
        userLng = userPosition.longitude;
      } catch (e) {
        debugPrint('خطأ في الحصول على الموقع');
      }

      File? selfieFile;
      try {
        if (Platform.isAndroid || Platform.isIOS) {
          // فتح شاشة السيلفي بالكاميرا الأمامية مباشرة (مضمون 100%)
          final file = await Navigator.push<File?>(
            context,
            MaterialPageRoute(builder: (_) => const _FrontCameraCapture()),
          );
          if (file != null) selfieFile = file;
        }
      } catch (e) {
        debugPrint('خطأ في التقاط الصورة: $e');
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

      if (selfieFile != null && result['success'] != false) {
        try {
          final photoType = attendanceType == 'خروج' ? 'checkout' : 'checkin';
          await _attendanceApi.uploadAttendancePhoto(
            userId: realUserId,
            type: photoType,
            photoFile: selfieFile,
          );
        } catch (e) {
          debugPrint('خطأ في رفع صورة السيلفي: $e');
        }
      }

      if (!mounted) return;

      if (result['success'] == false) {
        final code = result['code'] ?? '';
        final message = result['message'] ?? result['error'] ?? 'خطأ غير معروف';

        IconData icon;
        Color color;
        if (code == 'DEVICE_MISMATCH') {
          icon = Icons.devices_other;
          color = _red;
        } else if (code == 'OUT_OF_RANGE') {
          icon = Icons.location_off;
          color = _orange;
        } else if (code == 'DEVICE_PENDING') {
          icon = Icons.hourglass_top;
          color = _blue;
        } else if (code == 'DEVICE_REJECTED') {
          icon = Icons.block;
          color = Colors.red.shade800;
        } else if (code == 'INVALID_SECURITY_CODE') {
          icon = Icons.lock_outline;
          color = _orange;
        } else if (code == 'RATE_LIMITED') {
          icon = Icons.timer_off;
          color = Colors.deepOrange;
        } else {
          icon = Icons.error_outline;
          color = _red;
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
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
        return;
      }

      final record = result['record'] ?? result['Record'];
      String successMsg = 'تم تسجيل $attendanceType بنجاح!';
      Color successColor = _green;

      if (record is Map) {
        final status = '${record['Status'] ?? record['status'] ?? ''}';
        final lateMins = record['LateMinutes'] ?? record['lateMinutes'];
        final overtime = record['OvertimeMinutes'] ?? record['overtimeMinutes'];
        final workedMins = record['WorkedMinutes'] ?? record['workedMinutes'];

        if (status == 'Late' || status == '1') {
          successMsg += '\n⚠️ متأخر $lateMins دقيقة';
          successColor = _orange;
        }
        if (overtime != null && overtime > 0) {
          successMsg += '\n⏰ وقت إضافي: $overtime دقيقة';
        }
        if (workedMins != null && workedMins > 0 && attendanceType == 'خروج') {
          final hours = (workedMins / 60).toStringAsFixed(1);
          successMsg += '\n⏱️ ساعات العمل: $hours ساعة';
        }
      }

      final vpnWarning = result['vpnWarning'] == true;
      if (vpnWarning) {
        successMsg += '\n⚠️ يُشتبه باستخدام VPN — تم تسجيل الملاحظة';
        successColor = _orange;
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
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );

      _fetchAttendanceCount();
    } catch (error) {
      debugPrint('Error submitting attendance');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ')),
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
      debugPrint('Error fetching center location');
      return null;
    }
  }

  bool _isWithinAllowedDistance(
      double userLat, double userLng, List<double> centerLocation) {
    final distance = Geolocator.distanceBetween(
        userLat, userLng, centerLocation[0], centerLocation[1]);
    return distance <= 150;
  }

  // ═══════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final mobile = MediaQuery.of(context).size.width < 500;
    final pad = mobile ? 16.0 : 28.0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bgDark,
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: SafeArea(
            child: Column(
              children: [
                // ── المحتوى القابل للتمرير ──
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: pad, vertical: mobile ? 12 : 20),
                    child: Column(
                      children: [
                        _buildHeader(mobile),
                        SizedBox(height: mobile ? 20 : 28),
                        _buildStatsGrid(mobile),
                        SizedBox(height: mobile ? 20 : 28),
                        _buildCodeCard(mobile),
                      ],
                    ),
                  ),
                ),
                // ── أزرار ثابتة في الأسفل ──
                _buildActionButtons(mobile),
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
  Widget _buildHeader(bool mobile) {
    return Container(
      padding: EdgeInsets.all(mobile ? 14 : 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [_blue.withOpacity(0.12), _cyan.withOpacity(0.06)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        border: Border.all(color: _blue.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          // زر رجوع
          _glassButton(
            icon: Icons.arrow_forward_ios_rounded,
            size: mobile ? 36 : 42,
            onTap: () => Navigator.pop(context),
          ),
          SizedBox(width: mobile ? 10 : 16),
          // أيقونة البصمة
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: mobile ? 40 : 48,
              height: mobile ? 40 : 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [_blue, _cyan],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _blue.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(Icons.fingerprint_rounded,
                  color: Colors.white, size: mobile ? 22 : 26),
            ),
          ),
          SizedBox(width: mobile ? 10 : 14),
          // العنوان + المركز
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'نظام البصمة',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: mobile ? 17 : 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.username,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: mobile ? 12 : 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // المركز + الساعة
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: mobile ? 8 : 12,
                  vertical: mobile ? 3 : 5,
                ),
                decoration: BoxDecoration(
                  color: _cyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _cyan.withOpacity(0.2)),
                ),
                child: Text(
                  widget.center,
                  style: TextStyle(
                    color: _cyan,
                    fontSize: mobile ? 10 : 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              StreamBuilder(
                stream: Stream.periodic(const Duration(seconds: 1)),
                builder: (context, snapshot) {
                  final now = DateTime.now();
                  return Text(
                    '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: _blue,
                      fontSize: mobile ? 14 : 18,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  //  شبكة الإحصائيات
  // ═══════════════════════════════════════
  Widget _buildStatsGrid(bool mobile) {
    final stats = [
      _StatData('حضور', '$_attendanceCount', Icons.check_circle_rounded, _green),
      _StatData('تأخير', '$_lateDays', Icons.schedule_rounded, _orange),
      _StatData('د. تأخير', '$_totalLateMinutes', Icons.timer_off_rounded, _red),
      _StatData('د. إضافي', '$_totalOvertimeMinutes', Icons.more_time_rounded, _blue),
      _StatData('ساعات العمل', (_totalWorkedMinutes / 60).toStringAsFixed(1),
          Icons.work_history_rounded, _purple),
    ];

    if (mobile) {
      // على الهاتف: صفين — 3 في الأعلى + 2 في الأسفل
      return Column(
        children: [
          Row(
            children: [
              for (int i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _buildStatCard(stats[i], mobile)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildStatCard(stats[3], mobile)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard(stats[4], mobile)),
            ],
          ),
        ],
      );
    }

    // على الشاشات الكبيرة: صف واحد
    return Row(
      children: stats
          .map((s) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildStatCard(s, mobile),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildStatCard(_StatData s, bool mobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: mobile ? 12 : 16,
        horizontal: mobile ? 6 : 12,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _cardDark,
        border: Border.all(color: s.color.withOpacity(0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: mobile ? 32 : 38,
            height: mobile ? 32 : 38,
            decoration: BoxDecoration(
              color: s.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(s.icon, color: s.color, size: mobile ? 16 : 20),
          ),
          SizedBox(height: mobile ? 8 : 10),
          Text(
            s.value,
            style: TextStyle(
              color: Colors.white,
              fontSize: mobile ? 18 : 24,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s.label,
            style: TextStyle(
              color: _textMuted,
              fontSize: mobile ? 10 : 12,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  //  بطاقة كود الأمان
  // ═══════════════════════════════════════
  Widget _buildCodeCard(bool mobile) {
    final hasCode = _savedCode?.isNotEmpty == true;
    final isManager = widget.permissions == 'مدير';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(mobile ? 16 : 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: _cardDark,
        border: Border.all(color: _cyan.withOpacity(0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // عنوان
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _cyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.shield_rounded,
                    color: _cyan, size: mobile ? 18 : 22),
              ),
              const SizedBox(width: 10),
              Text(
                'كود الأمان',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: mobile ? 14 : 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: mobile ? 14 : 20),

          // عرض الكود
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: mobile ? 14 : 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: hasCode
                  ? _cyan.withOpacity(0.06)
                  : Colors.white.withOpacity(0.02),
              border: Border.all(
                color: hasCode
                    ? _cyan.withOpacity(0.15)
                    : Colors.white.withOpacity(0.05),
              ),
            ),
            child: Column(
              children: [
                Text(
                  hasCode ? _savedCode! : '- - -',
                  style: TextStyle(
                    fontSize: mobile ? 26 : 34,
                    fontWeight: FontWeight.w900,
                    color: hasCode ? _cyan : Colors.white.withOpacity(0.15),
                    letterSpacing: 8,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  textAlign: TextAlign.center,
                ),
                if (hasCode) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: _green, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'الكود مُفعّل',
                        style: TextStyle(
                          color: _green.withOpacity(0.8),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // حقل الإدخال للمدير
          if (isManager) ...[
            SizedBox(height: mobile ? 14 : 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: mobile ? 14 : 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                    decoration: InputDecoration(
                      hintText: 'أدخل أو عدّل الكود...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.15),
                        fontSize: mobile ? 12 : 14,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.04),
                      prefixIcon: Icon(Icons.edit_rounded,
                          color: _blue.withOpacity(0.5), size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: _blue.withOpacity(0.4)),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: mobile ? 12 : 14,
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (v) => _saveCode(v),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _saveCode(_codeController.text),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: mobile ? 16 : 22,
                        vertical: mobile ? 12 : 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [_blue, _cyan],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _blue.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.save_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'حفظ',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: mobile ? 13 : 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  //  أزرار الحضور والانصراف
  // ═══════════════════════════════════════
  Widget _buildActionButtons(bool mobile) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        mobile ? 16 : 28,
        mobile ? 12 : 16,
        mobile ? 16 : 28,
        mobile ? 16 : 24,
      ),
      decoration: BoxDecoration(
        color: _cardDark,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        children: [
          // تسجيل الدخول
          Expanded(
            child: _ActionBtn(
              label: 'تسجيل الدخول',
              icon: Icons.login_rounded,
              colors: const [Color(0xFF16A34A), _green],
              isLoading: _isCheckingIn,
              mobile: mobile,
              onTap: () async {
                setState(() => _isCheckingIn = true);
                await _submitAttendance('دخول');
                if (mounted) setState(() => _isCheckingIn = false);
              },
            ),
          ),
          SizedBox(width: mobile ? 12 : 20),
          // تسجيل الخروج
          Expanded(
            child: _ActionBtn(
              label: 'تسجيل الخروج',
              icon: Icons.logout_rounded,
              colors: const [Color(0xFFDC2626), _red],
              isLoading: _isCheckingOut,
              mobile: mobile,
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

  Widget _glassButton({
    required IconData icon,
    required double size,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Icon(icon, color: Colors.white54, size: size * 0.45),
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
class _StatData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatData(this.label, this.value, this.icon, this.color);
}

// ═══════════════════════════════════════
//  زر الإجراء
// ═══════════════════════════════════════
class _ActionBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final bool isLoading;
  final bool mobile;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.colors,
    required this.isLoading,
    required this.mobile,
    required this.onTap,
  });

  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (!widget.isLoading) widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          height: widget.mobile ? 64 : 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.colors,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.colors[0].withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: widget.isLoading
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.icon,
                        color: Colors.white,
                        size: widget.mobile ? 22 : 28),
                    SizedBox(width: widget.mobile ? 8 : 12),
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: widget.mobile ? 15 : 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════
//  شاشة التقاط سيلفي بالكاميرا الأمامية
// ═══════════════════════════════════════
class _FrontCameraCapture extends StatefulWidget {
  const _FrontCameraCapture();

  @override
  State<_FrontCameraCapture> createState() => _FrontCameraCaptureState();
}

class _FrontCameraCaptureState extends State<_FrontCameraCapture> {
  CameraController? _controller;
  bool _isTaking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      // البحث عن الكاميرا الأمامية
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first, // fallback للخلفية إذا لم توجد أمامية
      );
      _controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر فتح الكاميرا');
    }
  }

  Future<void> _takePicture() async {
    if (_isTaking || _controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isTaking = true);
    try {
      final xFile = await _controller!.takePicture();
      // نقل الصورة لمجلد مؤقت
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/selfie_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = await File(xFile.path).copy(path);
      if (mounted) Navigator.pop(context, file);
    } catch (e) {
      debugPrint('خطأ في التقاط الصورة: $e');
      if (mounted) setState(() => _isTaking = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.camera_alt_outlined,
                          color: Colors.white38, size: 60),
                      const SizedBox(height: 16),
                      Text(_error!,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 16)),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('تخطي',
                            style: TextStyle(color: Colors.white54)),
                      ),
                    ],
                  ),
                )
              : _controller == null || !_controller!.value.isInitialized
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        // عرض الكاميرا
                        ClipRRect(
                          borderRadius: BorderRadius.circular(0),
                          child: CameraPreview(_controller!),
                        ),
                        // إطار الوجه
                        Center(
                          child: Container(
                            width: 220,
                            height: 280,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(120),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.4),
                                  width: 2),
                            ),
                          ),
                        ),
                        // النص العلوي
                        Positioned(
                          top: 20,
                          left: 0,
                          right: 0,
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'ضع وجهك داخل الإطار',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 15),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // أزرار الأسفل
                        Positioned(
                          bottom: 30,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // تخطي
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close,
                                    color: Colors.white54, size: 30),
                              ),
                              // زر التصوير
                              GestureDetector(
                                onTap: _takePicture,
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 4),
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _isTaking
                                          ? Colors.grey
                                          : Colors.white,
                                    ),
                                    child: _isTaking
                                        ? const Padding(
                                            padding: EdgeInsets.all(18),
                                            child:
                                                CircularProgressIndicator(
                                                    strokeWidth: 2),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                              // مكان فارغ للتوازن
                              const SizedBox(width: 30),
                            ],
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
