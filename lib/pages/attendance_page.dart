import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // لاستدعاء rootBundle
import 'package:shared_preferences/shared_preferences.dart'; // لتخزين البيانات محليًا
import 'package:geolocator/geolocator.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart'; // استخدام clientViaServiceAccount

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
  _AttendancePageState createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  sheets.SheetsApi? _sheetsApi;
  AuthClient? _client;
  int _attendanceCount = 0;
  final String spreadsheetId = '1MGY8UhtHaUiRaUKbohEi3a74jgEh7NeOuTEHBQ83KZc';
  TextEditingController _codeController = TextEditingController();
  String? _savedCode;

  @override
  void initState() {
    super.initState();
    _initializeSheetsAPI();
    _fetchAttendanceCount();
    _loadSavedCode();
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

      print('Google Sheets API initialized successfully!');
    } catch (e) {
      print('Error initializing Sheets API: $e');
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
      print('Error fetching attendance count: $e');
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ الكود بنجاح!')),
    );
  }

  Future<void> _submitAttendance(String attendanceType) async {
    try {
      if (_sheetsApi == null || _client == null) {
        throw Exception('Google Sheets API غير مهيأ.');
      }

      final centerLocation = await _getCenterLocation(widget.center);
      if (centerLocation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يمكن العثور على موقع المركز.')),
        );
        return;
      }

      final userPosition = await Geolocator.getCurrentPosition();
      if (!_isWithinAllowedDistance(
          userPosition.latitude, userPosition.longitude, centerLocation)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أنت خارج النطاق المسموح به.')),
        );
        return;
      }

      final range = 'الحضور!A1:Z';
      final response =
          await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);

      final rows = response.values ?? [];
      int userRowIndex = rows.indexWhere((row) =>
          row.length > 2 &&
          row[1] == widget.username &&
          row[2] == widget.center);

      if (userRowIndex == -1) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد كود مخزن لهذا المستخدم.')),
        );
        return;
      }

      if (columnDCode != _savedCode) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('المنكد تريد تبصم من غير تليفون')),
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تسجيل $attendanceType بنجاح!')),
      );

      _fetchAttendanceCount();
    } catch (error) {
      print('Error submitting attendance: $error');
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
      print('Error fetching center location: $e');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('تسجيل الحضور'),
        backgroundColor: Colors.blueAccent,
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Card(
                elevation: 5,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        'مرحبًا، ${widget.username}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'المركز: ${widget.center}',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'عدد أيام الحضور: $_attendanceCount',
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (widget.permissions == 'مدير')
                Column(
                  children: [
                    TextField(
                      controller: _codeController,
                      decoration: InputDecoration(
                        labelText: 'أدخل الكود الحالي أو عدله',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        _saveCode(value);
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'الكود الحالي: $_savedCode',
                      style: const TextStyle(fontSize: 18, color: Colors.blue),
                    ),
                  ],
                )
              else
                Text(
                  'الكود المخزن: $_savedCode',
                  style: const TextStyle(fontSize: 18),
                ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _submitAttendance('دخول'),
                icon: const Icon(Icons.login),
                label: const Text(
                  'تسجيل الدخول',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () => _submitAttendance('خروج'),
                icon: const Icon(Icons.logout),
                label: const Text(
                  'تسجيل الخروج',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 237, 108, 108),
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _client?.close();
    _codeController.dispose();
    super.dispose();
  }
}
