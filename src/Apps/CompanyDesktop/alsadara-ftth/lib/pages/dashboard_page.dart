/// اسم الصفحة: لوحة التحكم
/// وصف الصفحة: صفحة عرض الإحصائيات والمعلومات الرئيسية
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import '../widgets/responsive_body.dart';

class DashboardPage extends StatelessWidget {
  final String username;
  final String permissions;
  final String department;

  const DashboardPage({
    super.key,
    required this.username,
    required this.permissions,
    required this.department,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('مرحبًا $username'),
        backgroundColor: Colors.blue[800],
      ),
      body: ResponsiveBody(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'الصلاحيات: $permissions',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                'القسم: $department',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('تسجيل خروج'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
