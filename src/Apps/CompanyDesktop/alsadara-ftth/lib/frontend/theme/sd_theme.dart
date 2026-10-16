/// الثيم الموحّد لتطبيق الصدارة — مبني بالكامل من رموز `tokens/`.
///
/// لا يُربط بـ main.dart تلقائياً (حتى لا يتأثر أي جزء من المشروع).
/// طريقتان للاعتماد:
///  1) لكل شاشة تُرحَّل: لفّها بـ `SdTheme.scope(child: ...)`.
///  2) لاحقاً، بعد ترحيل الشاشات الأساسية وبموافقة: `theme: SdTheme.light()` في main.dart.
library;

import 'package:flutter/material.dart';

import '../tokens/sd_colors.dart';
import '../tokens/sd_metrics.dart';
import '../tokens/sd_typography.dart';

class SdTheme {
  SdTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: SdColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: SdColors.primary,
      onPrimary: Colors.white,
      secondary: SdColors.accent,
      onSecondary: Colors.white,
      error: SdColors.danger,
      onError: Colors.white,
      surface: SdColors.surface,
      onSurface: SdColors.ink,
      outline: SdColors.edge,
      outlineVariant: SdColors.divider,
    );

    final input = OutlineInputBorder(
      borderRadius: SdRadius.all(SdRadius.md),
      borderSide: const BorderSide(color: SdColors.edge),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: SdText.family,
      scaffoldBackgroundColor: SdColors.ground,
      dividerColor: SdColors.divider,
      textTheme: const TextTheme(
        headlineMedium: SdText.display,
        titleLarge: SdText.title,
        titleMedium: SdText.titleSm,
        labelLarge: SdText.label,
        bodyLarge: SdText.body,
        bodyMedium: SdText.body,
        bodySmall: SdText.bodySm,
        labelSmall: SdText.caption,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: SdColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: SdText.family,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: SdColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: SdRadius.all(SdRadius.lg)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SdColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(SdSpace.touch, SdSpace.touch),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: SdText.label,
          shape: RoundedRectangleBorder(borderRadius: SdRadius.all(SdRadius.md)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SdColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(SdSpace.touch, SdSpace.touch),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: SdText.label,
          shape: RoundedRectangleBorder(borderRadius: SdRadius.all(SdRadius.md)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SdColors.primary,
          minimumSize: const Size(SdSpace.touch, SdSpace.touch),
          side: const BorderSide(color: SdColors.primaryTintEdge),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: SdText.label,
          shape: RoundedRectangleBorder(borderRadius: SdRadius.all(SdRadius.md)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SdColors.primary,
          minimumSize: const Size(SdSpace.touch, SdSpace.touch),
          textStyle: SdText.label,
          shape: RoundedRectangleBorder(borderRadius: SdRadius.all(SdRadius.sm)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SdColors.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: SdText.bodySm,
        hintStyle: SdText.bodySm.copyWith(color: SdColors.faint),
        border: input,
        enabledBorder: input,
        focusedBorder: input.copyWith(
          borderSide: const BorderSide(color: SdColors.primary, width: 1.8),
        ),
        errorBorder: input.copyWith(
          borderSide: const BorderSide(color: SdColors.danger),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: SdColors.surface,
        selectedColor: SdColors.primary,
        labelStyle: SdText.label,
        side: const BorderSide(color: SdColors.edge),
        shape: RoundedRectangleBorder(borderRadius: SdRadius.all(SdRadius.pill)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: SdColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: SdRadius.all(SdRadius.xl)),
        titleTextStyle: SdText.title,
        contentTextStyle: SdText.body,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: SdColors.ink,
        contentTextStyle: SdText.body.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: SdRadius.all(SdRadius.md)),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: SdColors.primary,
        titleTextStyle: SdText.label,
        subtitleTextStyle: SdText.bodySm,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SdColors.primary,
        linearTrackColor: SdColors.divider,
      ),
      dividerTheme: const DividerThemeData(color: SdColors.divider, space: 1),
      extensions: const [SdTokens()],
    );
  }

  /// يطبّق الثيم الموحّد واتجاه RTL على شاشة واحدة دون لمس main.dart.
  static Widget scope({required Widget child}) {
    return Theme(
      data: light(),
      child: Directionality(textDirection: TextDirection.rtl, child: child),
    );
  }
}

/// امتداد ثيم للوصول للرموز من السياق: `Theme.of(context).extension<SdTokens>()`.
@immutable
class SdTokens extends ThemeExtension<SdTokens> {
  const SdTokens({
    this.ground = SdColors.ground,
    this.surface = SdColors.surface,
    this.cardEdge = SdColors.cardEdge,
    this.ink = SdColors.ink,
    this.muted = SdColors.muted,
  });

  final Color ground;
  final Color surface;
  final Color cardEdge;
  final Color ink;
  final Color muted;

  @override
  SdTokens copyWith({Color? ground, Color? surface, Color? cardEdge, Color? ink, Color? muted}) {
    return SdTokens(
      ground: ground ?? this.ground,
      surface: surface ?? this.surface,
      cardEdge: cardEdge ?? this.cardEdge,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
    );
  }

  @override
  SdTokens lerp(ThemeExtension<SdTokens>? other, double t) {
    if (other is! SdTokens) return this;
    return SdTokens(
      ground: Color.lerp(ground, other.ground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      cardEdge: Color.lerp(cardEdge, other.cardEdge, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}
