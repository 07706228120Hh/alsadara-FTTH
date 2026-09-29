import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../theme/brand.dart';
import '../theme/platform_theme.dart';
import '../theme/theme_controller.dart';

/// MaterialApp الموحّد لكل تطبيقات المنصّة:
/// الثيم الفاتح/الداكن من نظام التصميم، وضع العرض المحفوظ، العربية،
/// و**المكان الوحيد** الذي يُفرض فيه RTL — لا تكرّره الشاشات.
class PlatformApp extends StatelessWidget {
  final AppBrand brand;
  final Widget home;
  final ThemeController? themes;
  final String? title;
  final Map<String, WidgetBuilder> routes;
  final GlobalKey<NavigatorState>? navigatorKey;
  /// غلاف اختياري داخل RTL (مثل ضبط مقياس الخط).
  final TransitionBuilder? builder;

  const PlatformApp({
    super.key,
    required this.brand,
    required this.home,
    this.themes,
    this.title,
    this.routes = const {},
    this.navigatorKey,
    this.builder,
  });

  /// مفوّضو الترجمة الموحّدون (للتطبيقات التي تبني MaterialApp خاصاً بها مثل الوزارة).
  static const List<LocalizationsDelegate<dynamic>> delegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  @override
  Widget build(BuildContext context) {
    final c = themes ?? ThemeController.instance;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: c,
      builder: (context, mode, _) => MaterialApp(
        title: title ?? brand.title,
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: PlatformTheme.build(brand, Brightness.light),
        darkTheme: PlatformTheme.build(brand, Brightness.dark),
        themeMode: mode,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: delegates,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: builder != null ? builder!(context, child) : (child ?? const SizedBox.shrink()),
        ),
        routes: routes,
        home: home,
      ),
    );
  }
}
