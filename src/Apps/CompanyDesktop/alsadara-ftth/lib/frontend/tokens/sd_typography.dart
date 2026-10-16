/// أنماط النص الموحّدة (Cairo) — نظام تصميم الصدارة.
///
/// أصغر حجم مسموح للنص المقروء 11.5 (القديم فيه مواضع 9–10).
library;

import 'package:flutter/material.dart';

import 'sd_colors.dart';

class SdText {
  SdText._();

  static const String family = 'Cairo';

  static const TextStyle display = TextStyle(
      fontFamily: family, fontSize: 28, fontWeight: FontWeight.w900, height: 1.25, color: SdColors.ink);
  static const TextStyle title = TextStyle(
      fontFamily: family, fontSize: 20, fontWeight: FontWeight.w900, height: 1.3, color: SdColors.ink);
  static const TextStyle titleSm = TextStyle(
      fontFamily: family, fontSize: 16, fontWeight: FontWeight.w900, height: 1.35, color: SdColors.ink);
  static const TextStyle label = TextStyle(
      fontFamily: family, fontSize: 14, fontWeight: FontWeight.w800, height: 1.35, color: SdColors.ink);
  static const TextStyle body = TextStyle(
      fontFamily: family, fontSize: 14, fontWeight: FontWeight.w600, height: 1.6, color: SdColors.ink);
  static const TextStyle bodySm = TextStyle(
      fontFamily: family, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.5, color: SdColors.muted);
  static const TextStyle caption = TextStyle(
      fontFamily: family, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.4, color: SdColors.muted);

  /// أرقام كبيرة (عدّادات/مؤشرات).
  static const TextStyle number = TextStyle(
      fontFamily: family, fontSize: 36, fontWeight: FontWeight.w900, height: 1.1, color: SdColors.ink);
  static const TextStyle numberSm = TextStyle(
      fontFamily: family, fontSize: 22, fontWeight: FontWeight.w900, height: 1.15, color: SdColors.ink);

  /// نص أحادي للقيم التقنية (IP، MAC، أرقام هواتف).
  static const TextStyle mono = TextStyle(
      fontFamily: 'monospace', fontSize: 12.5, fontWeight: FontWeight.w600, color: SdColors.muted);
}
