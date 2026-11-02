/// اختبارات تخطيط (widget) لميزة «ربط المهام بحساب مصدر ومنطقة».
///
/// الهدف: كشف أخطاء التخطيط وقت التشغيل (overflow / infinite-height) التي
/// لا يكشفها `flutter analyze`. نرسم الودجت فعلياً بأحجام شاشة واقعية ونلتقط
/// أي استثناء تخطيط عبر [WidgetTester.takeException].
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alsadara/models/task.dart';
import 'package:alsadara/models/task_source_pool.dart';
import 'package:alsadara/task/task_card.dart';
import 'package:alsadara/task/widgets/task_source_region_section.dart';

/// مجمّع تجريبي يحوي حسابات FTTH/ساس + شركاء + مناطق ساس (بأسماء طويلة
/// عمداً لاختبار القصّ/الالتفاف).
TaskSourcePool _buildPool() {
  return const TaskSourcePool(
    ftthAccounts: [
      SourceAccountOption(
        id: 'ftth-1',
        label: 'حساب FTTH الرئيسي لمدينة الصدر القطاع الأول',
        username: 'ftth_user_sadr_01',
        serverUrl: 'https://admin.ftth.iq',
      ),
      SourceAccountOption(
        id: 'ftth-2',
        label: 'حساب FTTH الثانوي',
        username: 'ftth_user_02',
      ),
    ],
    sasAccounts: [
      SourceAccountOption(
        id: 'sas-1',
        label: 'حساب الساز الرئيسي للمزوّد الخارجي رقم واحد',
        username: 'sas_admin',
        serverUrl: 'https://sas.example.com',
        accountType: 1,
      ),
    ],
    partners: [
      PartnerOption(
          partnerId: '2261175',
          partnerName: 'الشريك الرئيسي مدينة الصدر المحدودة للاتصالات'),
      PartnerOption(partnerId: '3171968', partnerName: 'مكتب 11'),
    ],
    sasRegions: [
      SasRegionOption(
          id: 'region-1',
          name: 'منطقة الحبيبية القطاع الصناعي الكبير',
          code: 'HBB-01'),
      SasRegionOption(id: 'region-2', name: 'منطقة أخرى', code: ''),
    ],
  );
}

/// يلفّ قسم النموذج (TaskSourceRegionSection) في بيئة RTL بعرض حوار محدّد.
/// هذا القسم لا يقرأ MediaQuery، فتحديد العرض آمن وواقعي (كعرض حوار).
Widget _wrap(Widget child, {double width = 400}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

/// يلفّ TaskCard بحيث يملأ عرض الشاشة كاملاً (بلا SizedBox/padding أفقي)،
/// فيتطابق عرض التخطيط مع عرض MediaQuery تماماً كما في الإنتاج — لأن البطاقة
/// تتّخذ قراراتها التجاوبية من MediaQuery.of(context).size.width.
Widget _wrapCard(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    ),
  );
}

Task _task({
  int sourceAccountType = 0,
  String sourceAccountLabel = '',
  String partnerName = '',
  String regionName = '',
}) {
  return Task(
    id: '12345',
    guid: 'guid-12345',
    title: 'تجديد اشتراك',
    status: 'مفتوحة',
    department: 'الصيانة',
    leader: 'ليدر تجريبي',
    technician: 'فني تجريبي',
    username: 'مشترك تجريبي باسم طويل جداً لاختبار القصّ',
    phone: '07701234567',
    fbg: 'FBG-01',
    fat: 'FAT-02',
    location: 'مدينة الصدر قطاع 55',
    notes: '',
    createdAt: DateTime(2026, 1, 1, 10, 0),
    summary: '',
    priority: 'متوسط',
    agents: const [],
    statusHistory: const [],
    createdBy: 'منشئ تجريبي',
    sourceAccountType: sourceAccountType,
    sourceAccountLabel: sourceAccountLabel,
    partnerName: partnerName,
    regionName: regionName,
  );
}

void main() {
  // أحجام شاشة واقعية (ديسكتوب وموبايل) — نضبطها لكل اختبار ونعيدها بعده.
  void setSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('TaskSourceRegionSection', () {
    testWidgets('يُرسَم بلا استثناء/overflow (type=None)', (tester) async {
      setSurface(tester, const Size(1280, 800));
      await tester.pumpWidget(_wrap(TaskSourceRegionSection(
        initial: const TaskSourceSelection(),
        onChanged: (_) {},
        pool: _buildPool(),
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // منسدلة نوع الحساب ظاهرة، ولا منسدلات تابعة.
      expect(find.text('حساب المصدر'), findsOneWidget);
      expect(find.text('الحساب'), findsNothing);
      expect(find.text('الشريك الرئيسي'), findsNothing);
      expect(find.text('المنطقة (ساس)'), findsNothing);
      expect(find.text('المنطقة (يدوية)'), findsNothing);
    });

    testWidgets('التبديل None→FTTH يُظهر الحساب + الشريك + منطقة يدوية',
        (tester) async {
      setSurface(tester, const Size(420, 840)); // موبايل ضيّق
      TaskSourceSelection? last;
      await tester.pumpWidget(_wrap(
        TaskSourceRegionSection(
          initial: const TaskSourceSelection(),
          onChanged: (s) => last = s,
          pool: _buildPool(),
        ),
        width: 380,
      ));
      await tester.pumpAndSettle();

      // افتح منسدلة النوع واختر FTTH.
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('FTTH').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(last?.type, 1);
      // منسدلات FTTH: الحساب + الشريك + منطقة يدوية (نصّية). لا منسدلة ساس.
      expect(find.text('الحساب'), findsOneWidget);
      expect(find.text('الشريك الرئيسي'), findsOneWidget);
      expect(find.text('المنطقة (يدوية)'), findsOneWidget);
      expect(find.text('المنطقة (ساس)'), findsNothing);
    });

    testWidgets('التبديل None→ساس يُظهر الحساب + منسدلة مناطق ساس',
        (tester) async {
      setSurface(tester, const Size(420, 840));
      await tester.pumpWidget(_wrap(
        TaskSourceRegionSection(
          initial: const TaskSourceSelection(),
          onChanged: (_) {},
          pool: _buildPool(),
        ),
        width: 380,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ساس').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('الحساب'), findsOneWidget);
      expect(find.text('المنطقة (ساس)'), findsOneWidget);
      // لا عناصر FTTH.
      expect(find.text('الشريك الرئيسي'), findsNothing);
      expect(find.text('المنطقة (يدوية)'), findsNothing);
    });

    testWidgets('FTTH→ساس→None يبدّل المنسدلات بلا تعطّل', (tester) async {
      setSurface(tester, const Size(500, 840));
      await tester.pumpWidget(_wrap(TaskSourceRegionSection(
        initial: const TaskSourceSelection(),
        onChanged: (_) {},
        pool: _buildPool(),
      )));
      await tester.pumpAndSettle();

      // → FTTH
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('FTTH').last);
      await tester.pumpAndSettle();
      expect(find.text('الشريك الرئيسي'), findsOneWidget);

      // → ساس
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ساس').last);
      await tester.pumpAndSettle();
      expect(find.text('المنطقة (ساس)'), findsOneWidget);
      expect(find.text('الشريك الرئيسي'), findsNothing);

      // → لا شيء
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('لا شيء').last);
      await tester.pumpAndSettle();
      expect(find.text('الحساب'), findsNothing);
      expect(find.text('المنطقة (ساس)'), findsNothing);

      expect(tester.takeException(), isNull);
    });
  });

  group('TaskCard — شارات المصدر', () {
    testWidgets('بطاقة بالقيم الثلاث تُرسَم بلا overflow (ديسكتوب)',
        (tester) async {
      setSurface(tester, const Size(1280, 900));
      await tester.pumpWidget(_wrapCard(
        TaskCard(
          task: _task(
            sourceAccountType: 1,
            sourceAccountLabel: 'حساب FTTH الرئيسي لمدينة الصدر القطاع الأول',
            partnerName: 'الشريك الرئيسي مدينة الصدر المحدودة للاتصالات',
            regionName: 'منطقة الحبيبية القطاع الصناعي الكبير',
          ),
          currentUserRole: 'مدير',
          currentUserName: 'مدير النظام',
          onStatusChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // الشارات الثلاث ظاهرة.
      expect(
          find.text('حساب FTTH الرئيسي لمدينة الصدر القطاع الأول'),
          findsOneWidget);
      expect(find.text('الشريك الرئيسي مدينة الصدر المحدودة للاتصالات'),
          findsOneWidget);
      expect(find.text('منطقة الحبيبية القطاع الصناعي الكبير'), findsOneWidget);
    });

    testWidgets('بطاقة بالقيم الثلاث تُرسَم بلا overflow (موبايل ضيّق)',
        (tester) async {
      setSurface(tester, const Size(360, 780));
      // دور «فني» (مطابق لفني المهمة) يعزل ميزة الشارات عن شريط الإجراءات —
      // فلا يظهر زر «المزيد» المنبثق الذي يحمل انحداراً سابقاً في overflow
      // عند 360px (task_card.dart:1402، نصّ غير مرن). انظر تقرير الاختبار.
      await tester.pumpWidget(_wrapCard(
        TaskCard(
          task: _task(
            sourceAccountType: 2,
            sourceAccountLabel: 'حساب الساز الرئيسي للمزوّد الخارجي رقم واحد',
            partnerName: 'مكتب 11',
            regionName: 'منطقة الحبيبية القطاع الصناعي الكبير',
          ),
          currentUserRole: 'فني',
          currentUserName: 'فني تجريبي',
          onStatusChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('حساب الساز الرئيسي للمزوّد الخارجي رقم واحد'),
          findsOneWidget);
    });

    testWidgets('بطاقة لدور «مدير» بعرض ضيّق (360px) بلا overflow — زر «المزيد»',
        (tester) async {
      // دور «مدير» يُظهر شريط الإجراءات على الموبايل مع زر «المزيد» المنبثق
      // (task_card.dart). كان نصّ «المزيد» غير مرن داخل Row ⇒ overflow ~15px
      // عند 360px. هذا الاختبار يثبت زوال الانحدار بعد لفّ النصّ بـ Flexible.
      setSurface(tester, const Size(360, 780));
      await tester.pumpWidget(_wrapCard(
        TaskCard(
          task: _task(
            sourceAccountType: 1,
            sourceAccountLabel: 'حساب FTTH الرئيسي لمدينة الصدر القطاع الأول',
            partnerName: 'الشريك الرئيسي مدينة الصدر المحدودة للاتصالات',
            regionName: 'منطقة الحبيبية القطاع الصناعي الكبير',
          ),
          currentUserRole: 'مدير',
          currentUserName: 'مدير النظام',
          onStatusChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // زر «المزيد» المنبثق ظاهر في شريط إجراءات الموبايل.
      expect(find.text('المزيد'), findsOneWidget);
    });

    testWidgets('بطاقة بقيم مصدر فارغة لا تُظهر شارات', (tester) async {
      setSurface(tester, const Size(1280, 900));
      await tester.pumpWidget(_wrapCard(
        TaskCard(
          task: _task(), // كل قيم المصدر فارغة
          currentUserRole: 'مدير',
          currentUserName: 'مدير النظام',
          onStatusChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // لا أسماء شريك/منطقة.
      expect(find.text('مكتب 11'), findsNothing);
      expect(find.text('منطقة الحبيبية القطاع الصناعي الكبير'), findsNothing);
    });
  });
}
