/// فتح الروابط في المتصفح الافتراضي بمتانة — Network Quality
///
/// على ويندوز يُفتح عبر العملية مباشرةً (المسار الأساسي) لأن url_launcher قد
/// يُعيد true دون أن يفتح شيئاً فعلياً على بعض الإعدادات. على غير ويندوز يُستخدم
/// url_launcher كالمعتاد.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// يفتح [url] ويعيد true عند نجاح الفتح.
Future<bool> openUrlRobust(String url) async {
  if (Platform.isWindows) {
    // المسار الأساسي على ويندوز: فتح عبر العملية (لا نثق بـlaunchUrl هنا).
    // 1) rundll32 — الأكثر موثوقية.
    try {
      final r =
          await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      if (r.exitCode == 0) return true;
    } catch (_) {}
    // 2) cmd start.
    try {
      final r = await Process.run('cmd', ['/c', 'start', '', url]);
      if (r.exitCode == 0) return true;
    } catch (_) {}
    // 3) explorer (قد يُعيد رمزاً غير 0 رغم النجاح — آخر محاولة متسامحة).
    try {
      await Process.run('explorer.exe', [url]);
      return true;
    } catch (_) {}
    debugPrint('[UrlOpener] windows open failed (sanitized)');
    return false;
  }

  // غير ويندوز: url_launcher.
  try {
    return await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
  } catch (_) {
    debugPrint('[UrlOpener] launch failed (sanitized)');
    return false;
  }
}
