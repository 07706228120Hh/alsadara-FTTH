/// اسم الصفحة: صفحة الويب
/// وصف الصفحة: صفحة عرض المحتوى من الإنترنت
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import '../widgets/platform_webview.dart';

class WebViewPage extends StatelessWidget {
  final String url;
  final String title;

  const WebViewPage({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return PlatformWebView(
      url: url,
      title: title,
    );
  }
}
