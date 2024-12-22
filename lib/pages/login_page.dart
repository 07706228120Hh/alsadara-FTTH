import 'package:flutter/material.dart';
import 'home_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final FocusNode usernameFocusNode = FocusNode();
  final FocusNode phoneFocusNode = FocusNode();

  bool isLoading = false;
  String? errorMessage;

  // Google Sheets details
  final String apiKey = 'AIzaSyDdwZK0D8uRoPSKS0axA5dQjwMCQJtF1BU';
  final String spreadsheetId = '1MGY8UhtHaUiRaUKbohEi3a74jgEh7NeOuTEHBQ83KZc';
  final String range =
      'المستخدمين!A2:E'; // A: اسم المستخدم, B: رقم الهاتف, C: الصلاحيات, D: القسم, E: المركز

  Future<void> login() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final url =
        'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/$range?key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['values'] != null) {
          final rows = data['values'] as List;

          String? userPermissions;
          String? userDepartment;
          String? userCenter;

          bool isUserValid = false;

          for (var row in rows) {
            if (row.length >= 2 &&
                row[0].toString().trim().toLowerCase() ==
                    usernameController.text.trim().toLowerCase() &&
                row[1].toString().trim() == phoneController.text.trim()) {
              isUserValid = true;
              userPermissions = row.length > 2 ? row[2].toString().trim() : '';
              userDepartment = row.length > 3 ? row[3].toString().trim() : '';
              userCenter = row.length > 4 ? row[4].toString().trim() : '';
              break;
            }
          }

          if (isUserValid) {
            // الانتقال إلى الصفحة الرئيسية مع تمرير البيانات
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => HomePage(
                  username: usernameController.text.trim(),
                  permissions: userPermissions ?? '',
                  department: userDepartment ?? '',
                  center: userCenter ?? '',
                ),
              ),
            );
          } else {
            setState(() {
              errorMessage = 'اسم المستخدم أو رقم الهاتف غير صحيح.';
            });
          }
        } else {
          setState(() {
            errorMessage = 'لا توجد بيانات مستخدمين في الجدول.';
          });
        }
      } else {
        setState(() {
          errorMessage = 'خطأ أثناء الاتصال: ${response.statusCode}';
        });
      }
    } on SocketException {
      setState(() {
        errorMessage = 'لا يوجد اتصال بالإنترنت.';
      });
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ أثناء الاتصال: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تسجيل الدخول'),
        backgroundColor: Colors.blue[800],
      ),
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: usernameController,
              focusNode: usernameFocusNode,
              decoration: InputDecoration(
                labelText: 'اسم المستخدم',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
              ),
              textInputAction: TextInputAction.next,
              onSubmitted: (_) {
                FocusScope.of(context).requestFocus(phoneFocusNode);
              },
            ),
            const SizedBox(height: 18),
            TextField(
              controller: phoneController,
              focusNode: phoneFocusNode,
              decoration: InputDecoration(
                labelText: 'رقم الهاتف',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
              ),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                login();
              },
            ),
            const SizedBox(height: 18),
            if (errorMessage != null)
              Text(
                errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 16),
            isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: login,
                    child: const Text(
                      'تسجيل الدخول',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800],
                      padding: const EdgeInsets.symmetric(
                          horizontal: 50, vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
