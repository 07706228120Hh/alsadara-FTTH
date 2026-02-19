/// ملف اختبار لتشغيل TestWebViewPage مباشرة
library;

import 'package:flutter/material.dart';
import 'test_webview_standalone.dart';

void main() {
  runApp(const TestApp());
}

class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'اختبار WebView',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Cairo',
      ),
      locale: const Locale('ar'),
      home: const TestWebViewPage(),
    );
  }
}
