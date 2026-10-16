/// نقطة تشغيل مستقلة لمعرض نظام التصميم — لا تمسّ main.dart ولا أي جزء من التطبيق.
///
/// التشغيل (ويندوز):
///   D:\flutter\flutter\bin\flutter.bat run -d windows -t lib/frontend/preview/gallery_main.dart
/// ثم صغّر/كبّر النافذة لرؤية تخطيط الهاتف (< 600) والآيباد (< 1024) وسطح المكتب.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../frontend.dart';
import 'sd_gallery_page.dart';

void main() {
  runApp(const _GalleryApp());
}

class _GalleryApp extends StatelessWidget {
  const _GalleryApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'معرض نظام تصميم الصدارة',
      debugShowCheckedModeBanner: false,
      theme: SdTheme.light(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SdGalleryPage(),
    );
  }
}
