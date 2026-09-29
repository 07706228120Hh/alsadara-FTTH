import 'package:flutter/material.dart';
import 'brand.dart';
import 'tokens.dart';
import 'typography.dart';

/// بانِي الثيم الموحّد: لون أساسي واحد للمنصّة + لكنة التطبيق + كل ثيمات المكوّنات.
/// التطبيقات لا تملك ThemeData خاصاً — تستدعي `PlatformTheme.build(brand, brightness)` فقط.
abstract class PlatformTheme {
  static ThemeData build(AppBrand brand, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = dark ? PlatformPalette.dark : PlatformPalette.light;
    final pal = base.copyWith(accent: brand.accentFor(brightness));

    final primary = dark ? PlatformPalette.primaryDark : PlatformPalette.primaryLight;
    const onPrimary = PlatformPalette.onPrimaryInk;
    final primaryContainer = dark ? PlatformPalette.primaryContainerDark : PlatformPalette.primaryContainerLight;
    final onPrimaryContainer = dark ? const Color(0xFFFDE68A) : const Color(0xFF78350F);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: pal.accent,
      onSecondary: dark ? const Color(0xFF0B1220) : Colors.white,
      secondaryContainer: pal.accent.withValues(alpha: dark ? 0.22 : 0.14),
      onSecondaryContainer: pal.text,
      tertiary: pal.info,
      onTertiary: Colors.white,
      error: pal.danger,
      onError: Colors.white,
      errorContainer: pal.danger.withValues(alpha: dark ? 0.22 : 0.12),
      onErrorContainer: pal.danger,
      surface: pal.surface,
      onSurface: pal.text,
      surfaceContainerLowest: pal.surfaceCard,
      surfaceContainerLow: pal.surfaceCard,
      surfaceContainer: pal.surfaceCard,
      surfaceContainerHigh: pal.surfaceVariant,
      surfaceContainerHighest: pal.surfaceVariant,
      onSurfaceVariant: pal.textMuted,
      outline: pal.outline,
      outlineVariant: pal.outline.withValues(alpha: 0.6),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: dark ? pal.text : const Color(0xFF15202E),
      onInverseSurface: dark ? const Color(0xFF0B1220) : Colors.white,
      inversePrimary: dark ? PlatformPalette.primaryLight : PlatformPalette.primaryDark,
      surfaceTint: Colors.transparent,
    );

    final baseTheme = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme);
    final text = PlatformType.textTheme(baseTheme.textTheme, pal.text, pal.textMuted);

    OutlineInputBorder border(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: Radii.rMd, borderSide: BorderSide(color: c, width: w));

    final buttonShape = RoundedRectangleBorder(borderRadius: Radii.rMd);
    final buttonText = text.labelLarge?.copyWith(fontWeight: FontWeight.w700);

    return baseTheme.copyWith(
      extensions: [pal],
      textTheme: text,
      primaryTextTheme: text,
      scaffoldBackgroundColor: pal.surface,
      canvasColor: pal.surfaceCard,
      cardColor: pal.surfaceCard,
      dividerColor: pal.outline,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: pal.surface,
        foregroundColor: pal.text,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: pal.text, size: 22),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: pal.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.rLg,
          side: BorderSide(color: pal.outline),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: pal.surfaceVariant,
        border: border(pal.outline),
        enabledBorder: border(pal.outline),
        focusedBorder: border(primary, 1.6),
        errorBorder: border(pal.danger),
        focusedErrorBorder: border(pal.danger, 1.6),
        disabledBorder: border(pal.outline.withValues(alpha: 0.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: text.bodyMedium?.copyWith(color: pal.textMuted),
        hintStyle: text.bodyMedium?.copyWith(color: pal.textMuted.withValues(alpha: 0.7)),
        helperStyle: text.bodySmall,
        errorStyle: text.bodySmall?.copyWith(color: pal.danger, fontWeight: FontWeight.w600),
        prefixIconColor: pal.textMuted,
        suffixIconColor: pal.textMuted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(64, 48),
          shape: buttonShape,
          textStyle: buttonText,
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: buttonShape,
          textStyle: buttonText,
          elevation: 0,
          backgroundColor: primary,
          foregroundColor: onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 46),
          shape: buttonShape,
          textStyle: buttonText,
          side: BorderSide(color: pal.outline),
          foregroundColor: pal.text,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 40),
          shape: RoundedRectangleBorder(borderRadius: Radii.rSm),
          textStyle: buttonText,
          foregroundColor: pal.accent,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: pal.textMuted,
          shape: RoundedRectangleBorder(borderRadius: Radii.rSm),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: Radii.rLg),
        extendedTextStyle: buttonText,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: pal.surfaceVariant,
        selectedColor: primary.withValues(alpha: dark ? 0.16 : 0.14),
        side: BorderSide(color: pal.outline),
        shape: RoundedRectangleBorder(borderRadius: Radii.rPill),
        labelStyle: text.labelMedium?.copyWith(color: pal.textMuted),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: pal.accent),
        checkmarkColor: primary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        elevation: 0,
        backgroundColor: pal.surfaceCard,
        surfaceTintColor: Colors.transparent,
        indicatorColor: pal.accent.withValues(alpha: dark ? 0.25 : 0.15),
        indicatorShape: RoundedRectangleBorder(borderRadius: Radii.rMd),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: s.contains(WidgetState.selected) ? pal.text : pal.textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? pal.accent : pal.textMuted, size: 22),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: pal.surfaceCard,
        elevation: 0,
        indicatorColor: pal.accent.withValues(alpha: dark ? 0.25 : 0.15),
        indicatorShape: RoundedRectangleBorder(borderRadius: Radii.rMd),
        selectedIconTheme: IconThemeData(color: pal.accent, size: 22),
        unselectedIconTheme: IconThemeData(color: pal.textMuted, size: 22),
        selectedLabelTextStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: pal.text),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(color: pal.textMuted),
        useIndicator: true,
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: pal.surfaceCard,
        indicatorColor: pal.accent.withValues(alpha: dark ? 0.25 : 0.15),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: pal.accent,
        unselectedLabelColor: pal.textMuted,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
        indicatorColor: primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: pal.outline,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(pal.surfaceVariant),
        headingTextStyle: text.labelMedium?.copyWith(color: pal.textMuted, fontWeight: FontWeight.w700),
        dataTextStyle: text.bodyMedium,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 56,
        headingRowHeight: 44,
        dividerThickness: 1,
        horizontalMargin: 16,
        columnSpacing: 20,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: pal.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Radii.rXl),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: pal.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
        showDragHandle: true,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: pal.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Radii.rMd, side: BorderSide(color: pal.outline)),
        textStyle: text.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFF131D2B) : const Color(0xFF0F172A),
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: dark ? pal.accent : PlatformPalette.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: Radii.rMd),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? pal.surfaceVariant : const Color(0xFF15202E),
          borderRadius: Radii.rSm,
          border: Border.all(color: pal.outline),
        ),
        textStyle: text.bodySmall?.copyWith(color: Colors.white),
        waitDuration: const Duration(milliseconds: 400),
      ),
      dividerTheme: DividerThemeData(color: pal.outline, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: pal.textMuted,
        textColor: pal.text,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodySmall,
        shape: RoundedRectangleBorder(borderRadius: Radii.rMd),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : pal.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : pal.surfaceVariant,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : pal.outline,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: pal.outline, width: 1.5),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: pal.surfaceVariant,
        circularTrackColor: pal.surfaceVariant,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: 0.30),
        selectionHandleColor: primary,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: text.bodyMedium,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(pal.surfaceCard),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: Radii.rMd)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: primary.withValues(alpha: dark ? 0.28 : 0.14),
          selectedForegroundColor: primary,
          side: BorderSide(color: pal.outline),
          textStyle: text.labelMedium,
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: pal.danger,
        textColor: Colors.white,
        textStyle: text.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }
}
