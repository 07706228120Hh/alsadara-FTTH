/// اسم الصفحة: المستخدمين
/// وصف الصفحة: صفحة إدارة المستخدمين والموظفين
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import '../services/api_service.dart';

class UsersPage extends StatefulWidget {
  final String permissions; // إضافة معامل الصلاحيات

  const UsersPage({super.key, required this.permissions});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final ApiService _api = ApiService.instance;
  List<Map<String, String>> users = [];
  List<Map<String, String>> filteredUsers = [];
  List<Map<String, dynamic>> _rawUsers = []; // بيانات API الخام
  bool isLoading = true;
  String? errorMessage;
  TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchUsers();
  }

  Future<void> fetchUsers() async {
    try {
      setState(() => isLoading = true);
      final response = await _api.get('/internal/data/users');
      final data = response['data'];
      final List<dynamic> rawList = data is List ? data : [];

      _rawUsers = rawList.cast<Map<String, dynamic>>();
      List<Map<String, String>> fetchedUsers = _rawUsers.map((user) {
        return {
          'اسم المستخدم':
              (user['FullName'] ?? user['fullName'] ?? '').toString(),
          'رقم الهاتف':
              (user['PhoneNumber'] ?? user['phoneNumber'] ?? '').toString(),
          'الصلاحيات': (user['FirstSystemPermissions'] ??
                  user['firstSystemPermissions'] ??
                  '')
              .toString(),
          'القسم': (user['Department'] ?? user['department'] ?? '').toString(),
          'المركز': (user['Center'] ?? user['center'] ?? '').toString(),
          'الراتب': (user['Salary'] ?? user['salary'] ?? '').toString(),
          'الكود':
              (user['EmployeeCode'] ?? user['employeeCode'] ?? '').toString(),
          '_id': (user['Id'] ?? user['id'] ?? '').toString(),
        };
      }).toList();

      setState(() {
        users = fetchedUsers;
        filteredUsers = fetchedUsers;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ أثناء جلب المستخدمين';
        isLoading = false;
      });
    }
  }

  Future<void> updateUser(int index, Map<String, String> updatedUser) async {
    try {
      final userId = users[index]['_id'] ?? '';
      if (userId.isEmpty) {
        throw 'معرف المستخدم غير موجود';
      }

      await _api.put('/users/$userId', body: {
        'FullName': updatedUser['اسم المستخدم'],
        'PhoneNumber': updatedUser['رقم الهاتف'],
        'FirstSystemPermissions': updatedUser['الصلاحيات'],
        'Department': updatedUser['القسم'],
        'Center': updatedUser['المركز'],
        'Salary': updatedUser['الراتب'],
        'EmployeeCode': updatedUser['الكود'],
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث المستخدم بنجاح!')),
        );
      }

      fetchUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء تحديث المستخدم')),
        );
      }
    }
  }

  Future<void> deleteUser(int index) async {
    try {
      final userId = users[index]['_id'] ?? '';
      if (userId.isEmpty) {
        throw 'معرف المستخدم غير موجود';
      }

      await _api.delete('/users/$userId');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف المستخدم بنجاح!')),
        );
      }

      fetchUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء حذف المستخدم')),
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
          content: SizedBox(
            width: MediaQuery.of(context).size.width > 600
                ? 400
                : MediaQuery.of(context).size.width * 0.85,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (String column in controllers.keys)
                    TextField(
                      controller: controllers[column],
                      decoration: InputDecoration(labelText: column),
                    ),
                ],
              ),
            ),
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
