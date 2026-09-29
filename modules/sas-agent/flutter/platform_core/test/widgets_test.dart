import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_core/platform_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget home, {AppBrand brand = AppBrand.agents, Size size = const Size(1280, 800)}) => MediaQuery(
      data: MediaQueryData(size: size),
      child: PlatformApp(brand: brand, home: home, themes: ThemeController(ThemeMode.light)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('AuthScaffold: يعرض هوية التطبيق وشارة البيئة والنموذج', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_app(
      const AuthScaffold(brand: AppBrand.agents, hint: 'تلميح', form: Text('FORM')),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('FORM'), findsOneWidget);
    expect(find.text('تلميح'), findsOneWidget);
    // عنوان التطبيق يظهر في لوحة الهوية (عريض)
    expect(find.text(AppBrand.agents.title), findsWidgets);
    // عنوان الباكند الافتراضي محلي ⇒ شارة «بيئة تطوير»
    expect(find.text('بيئة تطوير'), findsOneWidget);
    expect(find.byType(ThemeToggleButton), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // إيقاف مؤقّت فحص الخادم
  });

  testWidgets('AuthScaffold: عمود واحد على الموبايل', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_app(
      const AuthScaffold(brand: AppBrand.subscribers, hint: 'x', form: Text('FORM')),
      size: const Size(400, 800),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(BrandPanel), findsNothing);
    expect(find.byType(BrandMark), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  List<ShellTab> tabs() => [
        ShellTab(label: 'أ', icon: Icons.home, selectedIcon: Icons.home, builder: () => const Text('PAGE-A'), group: 'ع'),
        ShellTab(label: 'ب', icon: Icons.list, selectedIcon: Icons.list, builder: () => const Text('PAGE-B'), group: 'ع'),
        ShellTab(label: 'ج', icon: Icons.info, selectedIcon: Icons.info, builder: () => const Text('PAGE-C'), group: 'ن'),
        ShellTab(label: 'د', icon: Icons.settings, selectedIcon: Icons.settings, builder: () => const Text('PAGE-D')),
        ShellTab(label: 'هـ', icon: Icons.star, selectedIcon: Icons.star, builder: () => const Text('PAGE-E')),
        ShellTab(label: 'و', icon: Icons.mail, selectedIcon: Icons.mail, builder: () => const Text('PAGE-F')),
      ];

  testWidgets('AppShell: Rail على العريض وشريط سفلي + «المزيد» على الموبايل', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_app(AppShell(brand: AppBrand.companies, tabs: tabs())));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('PAGE-A'), findsOneWidget);
    await tester.tap(find.text('ج'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE-C'), findsOneWidget);

    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpWidget(_app(AppShell(brand: AppBrand.companies, tabs: tabs()), size: const Size(400, 800)));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('المزيد'), findsOneWidget);
  });

  testWidgets('PinField: يُكمل عند 6 أرقام ويحوّل الأرقام العربية', (tester) async {
    String? done;
    await tester.pumpWidget(_app(Scaffold(body: Center(child: PinField(onCompleted: (v) => done = v)))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '١٢٣٤٥٦');
    await tester.pump();
    expect(done, '123456');
  });

  testWidgets('PBanner.error يعرض النص', (tester) async {
    await tester.pumpWidget(_app(const Scaffold(body: PBanner.error('خطأ ما'))));
    await tester.pumpAndSettle();
    expect(find.text('خطأ ما'), findsOneWidget);
  });

  testWidgets('PTable: جدول على العريض وبطاقات على الموبايل', (tester) async {
    final cols = [
      PColumn<int>(label: 'الاسم', value: (r) => 'صف $r'),
      PColumn<int>(label: 'العدد', value: (r) => '$r', numeric: true, sortKey: (r) => r),
    ];
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_app(Scaffold(body: PTable<int>(columns: cols, rows: const [3, 1, 2]))));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);

    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpWidget(_app(Scaffold(body: PTable<int>(columns: cols, rows: const [3, 1, 2])), size: const Size(400, 800)));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('صف 3'), findsOneWidget);
  });
}
