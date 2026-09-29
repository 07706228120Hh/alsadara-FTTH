// اختبار دخان بسيط — يتحقّق أن بيئة الاختبار تعمل وأن الودجات تُبنى.
// (القالب الافتراضي «MyApp/العدّاد» أُزيل لأنه لا يخصّ هذا التطبيق.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('smoke: يبني ودجت بسيطاً', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Text('الوكلاء'))),
    ));
    expect(find.text('الوكلاء'), findsOneWidget);
  });
}
