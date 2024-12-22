import 'package:flutter/material.dart';
import 'pages/login_page.dart'; // تحديث الاستيراد للصفحة الجديدة

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: LoginPage(), // صفحة تسجيل الدخول هي البداية
  ));
}
