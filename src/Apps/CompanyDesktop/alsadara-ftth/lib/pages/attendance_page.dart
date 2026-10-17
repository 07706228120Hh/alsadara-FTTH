/// اسم الصفحة: الحضور والانصراف
/// وصف الصفحة: صفحة تسجيل حضور وانصراف الموظفين مع تتبع الموقع
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import '../frontend/frontend.dart';
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

class _AttendancePageState extends State<AttendancePage> {
  final AttendanceApiService _attendanceApi = AttendanceApiService.instance;
  int _attendanceCount = 0;
  int _lateDays = 0;
  int _totalLateMinutes = 0;
  int _totalOvertimeMinutes = 0;
  int _totalWorkedMinutes = 0;
  final TextEditingController _codeController = TextEditingController();
  String? _savedCode;
  String? _userId;

  bool _isCheckingIn = false;
  bool _isCheckingOut = false;

  @override
  void initState() {
    super.initState();
    _fetchAttendanceCount();
    _loadSavedCode();
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
          backgroundColor: SdColors.success,
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
                backgroundColor: SdColors.danger,
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
                backgroundColor: SdColors.warning,
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
          color = SdColors.danger;
        } else if (code == 'OUT_OF_RANGE') {
          icon = Icons.location_off;
          color = SdColors.warning;
        } else if (code == 'DEVICE_PENDING') {
          icon = Icons.hourglass_top;
          color = SdColors.info;
        } else if (code == 'DEVICE_REJECTED') {
          icon = Icons.block;
          color = SdColors.dangerEdge;
        } else if (code == 'INVALID_SECURITY_CODE') {
          icon = Icons.lock_outline;
          color = SdColors.warning;
        } else if (code == 'RATE_LIMITED') {
          icon = Icons.timer_off;
          color = SdColors.warningEdge;
        } else {
          icon = Icons.error_outline;
          color = SdColors.danger;
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
      Color successColor = SdColors.success;

      if (record is Map) {
        final status = '${record['Status'] ?? record['status'] ?? ''}';
        final lateMins = record['LateMinutes'] ?? record['lateMinutes'];
        final overtime = record['OvertimeMinutes'] ?? record['overtimeMinutes'];
        final workedMins = record['WorkedMinutes'] ?? record['workedMinutes'];

        if (status == 'Late' || status == '1') {
          successMsg += '\n⚠️ متأخر $lateMins دقيقة';
          successColor = SdColors.warning;
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
        successColor = SdColors.warning;
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
    return SdPage(
      maxWidth: SdSpace.formMax,
      appBar: SdAppBar(title: 'نظام البصمة', subtitle: widget.username),
      bottomBar: _buildActionButtons(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          SizedBox(height: context.sd.sectionGap),
          _buildStatsGrid(),
          SizedBox(height: context.sd.sectionGap),
          _buildCodeCard(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  //  الهيدر (المستخدم + المركز + الساعة الحيّة)
  // ═══════════════════════════════════════
  Widget _buildHeader() {
    final t = SdGroup.admin.tone;
    return SdCard(
      child: Row(
        children: [
          SdIconCube(icon: Icons.fingerprint_rounded, group: SdGroup.admin, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.username,
                    style: SdText.titleSm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                SdStatusChip(widget.center,
                    status: SdStatus.info, icon: Icons.business_rounded),
              ],
            ),
          ),
          StreamBuilder(
            stream: Stream.periodic(const Duration(seconds: 1)),
            builder: (context, snapshot) {
              final now = DateTime.now();
              return Text(
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
                style: SdText.numberSm.copyWith(
                  color: t.edge,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  //  شبكة الإحصائيات
  // ═══════════════════════════════════════
  Widget _buildStatsGrid() {
    return SdTileGrid(
      minTileWidth: 200,
      maxColumns: 3,
      children: [
        SdStatPedestal(
          value: _attendanceCount,
          label: 'أيام الحضور',
          tone: SdStatus.success.tone,
        ),
        SdStatPedestal(
          value: _lateDays,
          label: 'أيام التأخير',
          tone: SdStatus.warning.tone,
        ),
        SdStatPedestal(
          value: _totalLateMinutes,
          label: 'دقائق التأخير',
          tone: SdStatus.danger.tone,
        ),
        SdStatPedestal(
          value: _totalOvertimeMinutes,
          label: 'دقائق إضافية',
          tone: SdStatus.info.tone,
        ),
        SdStatPedestal(
          value: double.parse((_totalWorkedMinutes / 60).toStringAsFixed(1)),
          label: 'ساعات العمل',
          group: SdGroup.platform,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  //  بطاقة كود الأمان
  // ═══════════════════════════════════════
  Widget _buildCodeCard() {
    final hasCode = _savedCode?.isNotEmpty == true;
    final isManager = widget.permissions == 'مدير';
    final t = SdGroup.admin.tone;

    return SdCard(
      title: 'كود الأمان',
      icon: Icons.shield_rounded,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // عرض الكود
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SdRadius.md),
              color: hasCode ? t.tint : SdColors.surfaceAlt,
              boxShadow: [
                BoxShadow(
                    color: hasCode ? t.tintEdge : SdColors.edge,
                    offset: const Offset(0, SdDepth.chip)),
              ],
            ),
            child: Column(
              children: [
                Text(
                  hasCode ? _savedCode! : '- - -',
                  style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: hasCode ? t.text : SdColors.faint,
                    letterSpacing: 8,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  textAlign: TextAlign.center,
                ),
                if (hasCode) ...[
                  const SizedBox(height: 6),
                  SdStatusChip('الكود مُفعّل',
                      status: SdStatus.success,
                      icon: Icons.check_circle_rounded),
                ],
              ],
            ),
          ),

          // حقل الإدخال للمدير
          if (isManager) ...[
            const SizedBox(height: SdSpace.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    textAlign: TextAlign.center,
                    style: SdText.label.copyWith(letterSpacing: 2),
                    decoration: InputDecoration(
                      hintText: 'أدخل أو عدّل الكود...',
                      hintStyle: SdText.bodySm,
                      filled: true,
                      fillColor: SdColors.surfaceAlt,
                      prefixIcon: const Icon(Icons.edit_rounded,
                          color: SdColors.faint, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(SdRadius.sm),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(SdRadius.sm),
                        borderSide: const BorderSide(color: SdColors.primary),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      isDense: true,
                    ),
                    onSubmitted: (v) => _saveCode(v),
                  ),
                ),
                const SizedBox(width: 10),
                SdButton(
                  label: 'حفظ',
                  icon: Icons.save_rounded,
                  onPressed: () => _saveCode(_codeController.text),
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
  Widget _buildActionButtons() {
    final busy = _isCheckingIn || _isCheckingOut;
    return Row(
      children: [
        Expanded(
          child: SdButton(
            label: _isCheckingIn ? 'جاري التسجيل…' : 'تسجيل الدخول',
            icon: Icons.login_rounded,
            kind: SdButtonKind.primary,
            expand: true,
            onPressed: busy
                ? null
                : () async {
                    setState(() => _isCheckingIn = true);
                    await _submitAttendance('دخول');
                    if (mounted) setState(() => _isCheckingIn = false);
                  },
          ),
        ),
        const SizedBox(width: SdSpace.sm),
        Expanded(
          child: SdButton(
            label: _isCheckingOut ? 'جاري التسجيل…' : 'تسجيل الخروج',
            icon: Icons.logout_rounded,
            kind: SdButtonKind.danger,
            expand: true,
            onPressed: busy
                ? null
                : () async {
                    setState(() => _isCheckingOut = true);
                    await _submitAttendance('خروج');
                    if (mounted) setState(() => _isCheckingOut = false);
                  },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
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
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: SdCard(
                      padding: EdgeInsets.zero,
                      child: SdEmptyState(
                        icon: Icons.camera_alt_outlined,
                        status: SdStatus.danger,
                        title: _error!,
                        action: SdButton(
                          label: 'تخطي',
                          kind: SdButtonKind.secondary,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ),
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
                                  color: Colors.white.withValues(alpha: 0.4),
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
                                      fontFamily: SdText.family,
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700),
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
                                        color: SdColors.surface, width: 4),
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _isTaking
                                          ? SdColors.faint
                                          : SdColors.surface,
                                    ),
                                    child: _isTaking
                                        ? const Padding(
                                            padding: EdgeInsets.all(18),
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: SdColors.primary),
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
