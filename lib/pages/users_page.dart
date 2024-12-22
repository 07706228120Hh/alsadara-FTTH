import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key, required String permissions});

  @override
  _UsersPageState createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final String apiKey = 'AIzaSyDdwZK0D8uRoPSKS0axA5dQjwMCQJtF1BU';
  final String spreadsheetId = '1MGY8UhtHaUiRaUKbohEi3a74jgEh7NeOuTEHBQ83KZc';
  final String range = 'المستخدمين!A2:D';

  bool isLoading = true;
  String? errorMessage;
  List<Map<String, String>> users = [];
  List<Map<String, String>> filteredUsers = [];
  TextEditingController searchController = TextEditingController();

  Future<void> fetchUsers() async {
    final url =
        'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/$range?key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['values'] != null) {
          List<Map<String, String>> fetchedUsers = [];
          for (var row in data['values']) {
            if (row.length >= 4) {
              fetchedUsers.add({
                'username': row[0],
                'phone': row[1],
                'permissions': row[2],
                'department': row[3],
              });
            }
          }

          setState(() {
            users = fetchedUsers;
            filteredUsers = fetchedUsers;
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage = 'لا توجد بيانات.';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'خطأ: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ: $e';
        isLoading = false;
      });
    }
  }

  Future<void> addUser(Map<String, String> user) async {
    final url =
        'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/$range:append?valueInputOption=USER_ENTERED&key=$apiKey';
    final body = jsonEncode({
      "values": [
        [
          user['username'],
          user['phone'],
          user['permissions'],
          user['department']
        ]
      ]
    });

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        fetchUsers(); // تحديث البيانات
      } else {
        throw 'خطأ في الإضافة: ${response.statusCode}';
      }
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ أثناء الإضافة: $e';
      });
    }
  }

  Future<void> deleteUser(int index) async {
    setState(() {
      users.removeAt(index);
      filteredUsers = users;
    });
  }

  void filterUsers(String query) {
    final results = users.where((user) {
      final username = user['username']!.toLowerCase();
      return username.contains(query.toLowerCase());
    }).toList();

    setState(() {
      filteredUsers = results;
    });
  }

  @override
  void initState() {
    super.initState();
    fetchUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'المستخدمين',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 28, 169, 125),
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
                    ElevatedButton(
                      onPressed: () => _showAddUserDialog(context),
                      child: const Text('إضافة مستخدم'),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 20,
                          border: TableBorder.all(color: Colors.grey),
                          headingRowColor:
                              MaterialStateProperty.all(Colors.blue[100]),
                          columns: const [
                            DataColumn(
                              label: CenteredText(
                                text: 'اسم المستخدم',
                                fontSize: 14,
                              ),
                            ),
                            DataColumn(
                              label: CenteredText(
                                text: 'رقم الهاتف',
                                fontSize: 14,
                              ),
                            ),
                            DataColumn(
                              label: CenteredText(
                                text: 'الصلاحيات',
                                fontSize: 14,
                              ),
                            ),
                            DataColumn(
                              label: CenteredText(
                                text: 'القسم',
                                fontSize: 14,
                              ),
                            ),
                            DataColumn(
                              label: CenteredText(
                                text: 'إجراءات',
                                fontSize: 14,
                              ),
                            ),
                          ],
                          rows: filteredUsers.asMap().entries.map((entry) {
                            int index = entry.key;
                            Map<String, String> user = entry.value;
                            return DataRow(
                              cells: [
                                DataCell(CenteredText(
                                    text: user['username']!, fontSize: 12)),
                                DataCell(CenteredText(
                                    text: user['phone']!, fontSize: 12)),
                                DataCell(CenteredText(
                                    text: user['permissions']!, fontSize: 12)),
                                DataCell(CenteredText(
                                    text: user['department']!, fontSize: 12)),
                                DataCell(
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.delete,
                                            color: Colors.red),
                                        onPressed: () => deleteUser(index),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  void _showAddUserDialog(BuildContext context) {
    final usernameController = TextEditingController();
    final phoneController = TextEditingController();
    final permissionsController = TextEditingController();
    final departmentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('إضافة مستخدم جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: 'اسم المستخدم'),
              ),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
              ),
              TextField(
                controller: permissionsController,
                decoration: const InputDecoration(labelText: 'الصلاحيات'),
              ),
              TextField(
                controller: departmentController,
                decoration: const InputDecoration(labelText: 'القسم'),
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
                final user = {
                  'username': usernameController.text,
                  'phone': phoneController.text,
                  'permissions': permissionsController.text,
                  'department': departmentController.text,
                };
                addUser(user);
                Navigator.pop(context);
              },
              child: const Text('إضافة'),
            ),
          ],
        );
      },
    );
  }
}

class CenteredText extends StatelessWidget {
  final String text;
  final double fontSize;

  const CenteredText({super.key, required this.text, this.fontSize = 14});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.normal,
          color: Colors.black,
        ),
      ),
    );
  }
}
