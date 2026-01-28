/// اسم الصفحة: الحضور والانصراف
/// وصف الصفحة: صفحة تسجيل حضور وانصراف الموظفين مع تتبع الموقع
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // لاستدعاء rootBundle
import 'package:shared_preferences/shared_preferences.dart'; // لتخزين البيانات محليًا
import 'package:geolocator/geolocator.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart'; // استخدام clientViaServiceAccount
import '../widgets/responsive_body.dart';

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
  // لون الخلفية الموحد للصفحة بالكامل
  Color get _bgColor => Colors.blue[400]!;
  sheets.SheetsApi? _sheetsApi;
  AuthClient? _client;
  int _attendanceCount = 0;
  final String spreadsheetId = '1MGY8UhtHaUiRaUKbohEi3a74jgEh7NeOuTEHBQ83KZc';
  final TextEditingController _codeController = TextEditingController();
  String? _savedCode;

  @override
  void initState() {
    super.initState();
    _initializeSheetsAPI();
    _fetchAttendanceCount();
    _loadSavedCode();
    // Ensure system bars blend with our gradient (fix black nav bar)
    WidgetsBinding.instance.addPostFrameCallback((_) => _applySystemUi());
  }

  void _applySystemUi() {
    // Edge-to-edge and transparent nav bar with no forced contrast
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: _bgColor,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ));
  }

  Future<void> _initializeSheetsAPI() async {
    try {
      final jsonString =
          await rootBundle.loadString('assets/service_account.json');
      final accountCredentials =
          ServiceAccountCredentials.fromJson(jsonDecode(jsonString));
      final scopes = [sheets.SheetsApi.spreadsheetsScope];
      _client = await clientViaServiceAccount(accountCredentials, scopes);
      _sheetsApi = sheets.SheetsApi(_client!);

      debugPrint('Google Sheets API initialized successfully!');
    } catch (e) {
      debugPrint('Error initializing Sheets API: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء تهيئة Google Sheets API: $e')),
      );
    }
  }

  Future<void> _fetchAttendanceCount() async {
    try {
      final range = 'الحضور!A1:Z';
      final response =
          await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);

      final rows = response.values ?? [];
      int userRowIndex = rows.indexWhere((row) =>
          row.length > 2 &&
          row[1] == widget.username &&
          row[2] == widget.center);

      if (userRowIndex != -1) {
        final userRow = rows[userRowIndex];
        int count = userRow.skip(4).where((value) => value != "").length ~/ 2;
        setState(() {
          _attendanceCount = count;
        });
      }
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
      if (_sheetsApi == null || _client == null) {
        throw Exception('Google Sheets API غير مهيأ.');
      }

      // تحقق من موقع المركز
      final centerLocation = await _getCenterLocation(widget.center);
      if (centerLocation == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم العثور على موقع المركز')),
        );
        return;
      }

      // تحقق المسافة (اختياري): فعّل هذا الشرط إذا أردت فرض التواجد ضمن نطاق المركز
      // نجعل الشرط غير ثابت عند التحليل لتجنب تحذير "dead code"
      final bool enableDistanceCheck = widget.permissions == '_';
      if (enableDistanceCheck) {
        final userPosition = await Geolocator.getCurrentPosition();
        if (!_isWithinAllowedDistance(
          userPosition.latitude,
          userPosition.longitude,
          centerLocation,
        )) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('أنت خارج نطاق المركز المسموح')),
          );
          return;
        }
      }

      // قراءة الصفوف للعثور على المستخدم
      final range = 'الحضور!A1:Z';
      final response =
          await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);
      final rows = response.values ?? [];
      int userRowIndex = rows.indexWhere((row) =>
          row.length > 2 &&
          row[1] == widget.username &&
          row[2] == widget.center);

      if (userRowIndex == -1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الموظف غير موجود')),
        );
        return;
      }

      final userRow = rows[userRowIndex];
      String? columnDCode = userRow.length > 3 && userRow[3] != null
          ? userRow[3].toString()
          : null;

      if (columnDCode == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد كود مخزن لهذا المستخدم.')),
        );
        return;
      }
      if (columnDCode != _savedCode) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الكود المدخل غير مطابق للكود المخزن')),
        );
        return;
      }

      final now = TimeOfDay.now();
      final timeString = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
      final column = _columnLetter(4 +
          (DateTime.now().day - 1) * 2 +
          (attendanceType == 'خروج' ? 1 : 0));
      final updateRange = 'الحضور!$column${userRowIndex + 1}';
      final valueRange = sheets.ValueRange(values: [
        [timeString]
      ]);

      await _sheetsApi!.spreadsheets.values.update(
        valueRange,
        spreadsheetId,
        updateRange,
        valueInputOption: 'USER_ENTERED',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تسجيل $attendanceType بنجاح!')),
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
      final range = 'المراكز!A2:B';
      final response =
          await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);

      final rows = response.values ?? [];
      final centerRow =
          rows.firstWhere((row) => row[0] == centerId, orElse: () => []);
      if (centerRow.isEmpty || centerRow.length < 2) return null;
      final location = centerRow[1].toString().split(',');
      return [double.parse(location[0]), double.parse(location[1])];
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

  String _columnLetter(int column) {
    int temp = column;
    String letter = '';
    while (temp > 0) {
      int remainder = (temp - 1) % 26;
      letter = String.fromCharCode(65 + remainder) + letter;
      temp = (temp - 1) ~/ 26;
    }
    return letter;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: _bgColor,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        extendBody: false,
        backgroundColor: _bgColor,
        body: Stack(
          children: [
            // Full-screen gradient background
            Positioned.fill(
              child: Container(
                color: _bgColor,
              ),
            ),

            // Bottom safe-area filler to ensure color shows behind nav bar on all devices
            if (bottomPadding > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: bottomPadding,
                child: Container(color: _bgColor),
              ),

            // Foreground content
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ResponsiveBody(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Column(
                    children: [
                      // Header with app bar
                      _buildHeader(),
                      const SizedBox(height: 20),

                      // Welcome Card
                      _buildWelcomeCard(),
                      const SizedBox(height: 12),

                      // Attendance Days Card
                      _buildAttendanceStatsCard(),
                      const SizedBox(height: 16),

                      // Code Section
                      _buildCodeSection(),
                      const SizedBox(height: 20),
                      // Attendance Buttons
                      _buildAttendanceButtons(),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.fingerprint,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'نظام البصمة',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                Text(
                  'إدارة الحضور والانصراف',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.security,
                  color: Colors.orange[600],
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'كود الأمان',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.permissions == 'مدير') ...[
            TextField(
              controller: _codeController,
              decoration: InputDecoration(
                labelText: 'أدخل الكود الحالي أو عدله',
                labelStyle: const TextStyle(fontSize: 16),
                prefixIcon: Icon(Icons.edit, color: Colors.blue[600], size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.blue[600]!, width: 1),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              style: const TextStyle(fontSize: 18),
              onSubmitted: (value) {
                _saveCode(value);
              },
            ),
            const SizedBox(height: 8),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.grey[100]!, Colors.grey[50]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.grey[300]!,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Text(
                  widget.permissions == 'مدير'
                      ? 'الكود الحالي'
                      : 'الكود المخزن',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _savedCode ?? 'لا يوجد كود',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceButtons() {
    return Column(
      children: [
        _fancyButton(
          label: 'تسجيل الدخول',
          icon: Icons.fingerprint_rounded,
          gradient: [
            Colors.green.shade600,
            Colors.green.shade400,
          ],
          onTap: () => _submitAttendance('دخول'),
        ),
        const SizedBox(height: 12),
        _fancyButton(
          label: 'تسجيل الخروج',
          icon: Icons.logout_rounded,
          gradient: [
            Colors.red.shade500,
            Colors.orange.shade400,
          ],
          onTap: () => _submitAttendance('خروج'),
        ),
      ],
    );
  }

  Widget _fancyButton({
    required String label,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            splashColor: Colors.white.withValues(alpha: 0.12),
            highlightColor: Colors.white.withValues(alpha: 0.06),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: Icon(icon, size: 22, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
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

  Widget _buildWelcomeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.grey[50]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue[600]!, Colors.blue[400]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'مرحباً بك',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.username,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.blue[700],
              letterSpacing: 0.1,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue[200]!, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on_rounded,
                        color: Colors.blue[600], size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'المركز: ${widget.center}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[800],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.purple[200]!, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user_rounded,
                        color: Colors.purple[600], size: 14),
                    const SizedBox(width: 4),
                    Text(
                      widget.permissions,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.purple[800],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceStatsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green[500]!, Colors.green[300]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
            ),
            child: const Icon(
              Icons.calendar_today_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'أيام الحضور',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            '$_attendanceCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(
                  color: Colors.black26,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
          Text(
            'يوم',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Restore default system UI to avoid side effects when leaving the page
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    ));
    _client?.close();
    _codeController.dispose();
    super.dispose();
  }
}
