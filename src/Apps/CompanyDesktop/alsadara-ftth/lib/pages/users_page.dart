/// اسم الصفحة: المستخدمين
/// وصف الصفحة: صفحة إدارة المستخدمين والموظفين
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // لاستدعاء rootBundle
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart'; // استخدام clientViaServiceAccount

class UsersPage extends StatefulWidget {
  final String permissions; // إضافة معامل الصلاحيات

  const UsersPage({super.key, required this.permissions});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  sheets.SheetsApi? _sheetsApi;
  AuthClient? _client;
  final String spreadsheetId = '1MGY8UhtHaUiRaUKbohEi3a74jgEh7NeOuTEHBQ83KZc';
  List<Map<String, String>> users = [];
  List<Map<String, String>> filteredUsers = [];
  bool isLoading = true;
  String? errorMessage;
  TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeSheetsAPI();
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
      fetchUsers();

      debugPrint('Google Sheets API initialized successfully!');
    } catch (e) {
      debugPrint('Error initializing Sheets API: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء تهيئة Google Sheets API: $e')),
        );
      }
    }
  }

  Future<void> fetchUsers() async {
    try {
      final range = 'المستخدمين!A2:G'; // جلب الأعمدة من A إلى G
      final response =
          await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);

      final rows = response.values ?? [];
      List<Map<String, String>> fetchedUsers = rows.map((row) {
        return {
          'اسم المستخدم': row.isNotEmpty ? row[0]?.toString() ?? '' : '',
          'رقم الهاتف': row.length > 1 ? row[1]?.toString() ?? '' : '',
          'الصلاحيات': row.length > 2 ? row[2]?.toString() ?? '' : '',
          'القسم': row.length > 3 ? row[3]?.toString() ?? '' : '',
          'المركز': row.length > 4 ? row[4]?.toString() ?? '' : '',
          'الراتب': row.length > 5 ? row[5]?.toString() ?? '' : '',
          'الكود': row.length > 6 ? row[6]?.toString() ?? '' : '',
        };
      }).toList();

      setState(() {
        users = fetchedUsers;
        filteredUsers = fetchedUsers;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ أثناء جلب المستخدمين: $e';
        isLoading = false;
      });
    }
  }

  Future<void> updateUser(int index, Map<String, String> updatedUser) async {
    try {
      final rowIndex = index + 2; // لأن الصفوف تبدأ من 2 في النطاق.
      final range =
          'المستخدمين!A$rowIndex:G$rowIndex'; // تعديل النطاق ليشمل الأعمدة A إلى G
      final values = [
        [
          updatedUser['اسم المستخدم'],
          updatedUser['رقم الهاتف'],
          updatedUser['الصلاحيات'],
          updatedUser['القسم'],
          updatedUser['المركز'],
          updatedUser['الراتب'],
          updatedUser['الكود'],
        ]
      ];
      final valueRange = sheets.ValueRange(values: values);

      await _sheetsApi!.spreadsheets.values.update(
        valueRange,
        spreadsheetId,
        range,
        valueInputOption: 'USER_ENTERED',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث المستخدم بنجاح!')),
        );
      }

      fetchUsers(); // جلب البيانات لتحديث الجدول.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء تحديث المستخدم: $e')),
        );
      }
    }
  }

  Future<void> deleteUser(int index) async {
    try {
      final rowIndex = index + 2; // الصف الذي سيتم حذفه
      final range = 'المستخدمين!A$rowIndex:G$rowIndex';

      // حذف المحتوى بإرسال قيم فارغة
      final emptyValues = sheets.ValueRange(values: [[]]);
      await _sheetsApi!.spreadsheets.values.update(
        emptyValues,
        spreadsheetId,
        range,
        valueInputOption: 'USER_ENTERED',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف المستخدم بنجاح!')),
        );
      }

      fetchUsers(); // تحديث القائمة بعد الحذف
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء حذف المستخدم: $e')),
        );
      }
    }
  }

  void _showEditUserDialog(BuildContext context, int index) {
    final user = users[index];
    final controllers = {
      'اسم المستخدم': TextEditingController(text: user['اسم المستخدم']),
      'رقم الهاتف': TextEditingController(text: user['رقم الهاتف']),
      'الصلاحيات': TextEditingController(text: user['الصلاحيات']),
      'القسم': TextEditingController(text: user['القسم']),
      'المركز': TextEditingController(text: user['المركز']),
      'الراتب': TextEditingController(text: user['الراتب']),
      'الكود': TextEditingController(text: user['الكود']),
    };

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تعديل بيانات المستخدم'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (String column in controllers.keys)
                TextField(
                  controller: controllers[column],
                  decoration: InputDecoration(labelText: column),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                final updatedUser = {
                  for (String column in controllers.keys)
                    column: controllers[column]!.text,
                };
                updateUser(index, updatedUser);
                Navigator.pop(context);
              },
              child: const Text('تحديث'),
            ),
          ],
        );
      },
    );
  }

  void filterUsers(String query) {
    final results = users.where((user) {
      final username = user['اسم المستخدم']!.toLowerCase();
      return username.contains(query.toLowerCase());
    }).toList();

    setState(() {
      filteredUsers = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.blue[900]!,
                Colors.blue[700]!,
                Colors.blue[500]!,
              ],
            ),
          ),
        ),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
              size: 20,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.people,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'إدارة المستخدمين',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 16),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          labelText: 'ابحث عن المستخدم',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          prefixIcon: const Icon(Icons.search),
                        ),
                        onChanged: filterUsers,
                      ),
                    ),
                    Expanded(
                      child: _ResponsiveBodyShim(
                        child: ListView.builder(
                          itemCount: filteredUsers.length,
                          itemBuilder: (context, index) {
                            final user = filteredUsers[index];
                            return Card(
                              child: ExpansionTile(
                                title: Text(user['اسم المستخدم']!),
                                children: [
                                  for (var entry in user.entries)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4.0, horizontal: 16.0),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            entry.key,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ),
                                          Text(entry.value),
                                        ],
                                      ),
                                    ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed: () =>
                                            _showEditUserDialog(context, index),
                                        child: const Text(
                                          'تعديل',
                                          style: TextStyle(color: Colors.blue),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => deleteUser(index),
                                        child: const Text(
                                          'حذف',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  @override
  void dispose() {
    _client?.close();
    searchController.dispose();
    super.dispose();
  }
}

class _ResponsiveBodyShim extends StatelessWidget {
  final Widget child;
  const _ResponsiveBodyShim({required this.child});
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    double maxWidth;
    if (width > 1440) {
      maxWidth = 1200;
    } else if (width > 1024) {
      maxWidth = 1000;
    } else if (width > 600) {
      maxWidth = 800;
    } else {
      maxWidth = double.infinity;
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: child,
        ),
      ),
    );
  }
}
