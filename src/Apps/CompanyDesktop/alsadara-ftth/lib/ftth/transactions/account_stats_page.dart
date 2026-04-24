/// اسم الصفحة: إحصائيات الحسابات
/// وصف الصفحة: صفحة إحصائيات وتحليلات الحسابات
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../subscriptions/connections_list_page.dart';
import '../users/user_records_page.dart'; // الصفحة الجديدة لسجلات المستخدم
import '../../models/filter_criteria.dart';

// صفحة إحصائيات السجلات (نسخة نظيفة وبسيطة)
class AccountStatsPage extends StatelessWidget {
  final int purchaseCount;
  final double purchaseTotal;
  final int renewalCount;
  final double renewalTotal;
  final int totalRecords;
  final double totalAmount;
  final int cashCount;
  final double cashTotal;
  final int creditCount;
  final double creditTotal;
  final List<UserAccountStat> userStats;
  final FilterCriteria?
      filterCriteria; // معايير التصفية المرسلة من الصفحة الرئيسية
  final List<Map<String, dynamic>>?
      filteredRecords; // العمليات المفلترة من account_records_page

  const AccountStatsPage({
    super.key,
    required this.purchaseCount,
    required this.purchaseTotal,
    required this.renewalCount,
    required this.renewalTotal,
    required this.totalRecords,
    required this.totalAmount,
    required this.cashCount,
    required this.cashTotal,
    required this.creditCount,
    required this.creditTotal,
    this.userStats = const [],
    this.filterCriteria, // معايير التصفية الاختيارية
    this.filteredRecords, // العمليات المفلترة الاختيارية
  });

  String _formatAmount(double amount) =>
      NumberFormat('#,###', 'ar').format(amount);

  bool _isPhone(BuildContext context) =>
      MediaQuery.of(context).size.width < 500;
  double _fs(BuildContext context, double base) =>
      _isPhone(context) ? base * 0.85 : base;

  /// التنقل إلى صفحة اسمية الوصولات لمستخدم محدد
  void _navigateToConnectionsList(BuildContext context, String userName) {
    print('🔍 AccountStatsPage - التنقل إلى ConnectionsListPage');
    print('   - اسم المستخدم: $userName');
    print('   - FilterCriteria موجود: ${filterCriteria != null}');
    if (filterCriteria != null) {
      print('   - له معايير نشطة: ${filterCriteria!.hasActiveFilters}');
      print('   - الوصف: ${filterCriteria!.activeFiltersDescription}');
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        // تمرير اسم المستخدم ومعايير التصفية لعرض وصولاته المفلترة فقط
        builder: (context) => ConnectionsListPage(
          specificUser: userName,
          filterCriteria: filterCriteria, // تمرير معايير التصفية
        ),
      ),
    );
  }

  /// التنقل إلى صفحة سجلات المستخدم (الجديدة - مثل account_records_page)
  void _navigateToUserRecords(BuildContext context, String userName) {
    print('🔍 AccountStatsPage - التنقل إلى UserRecordsPage');
    print('   - اسم المستخدم: $userName');
    print('   - FilterCriteria موجود: ${filterCriteria != null}');
    print('   - العمليات المفلترة موجودة: ${filteredRecords != null}');
    print('   - عدد العمليات المفلترة: ${filteredRecords?.length ?? 0}');
    if (filterCriteria != null) {
      print('   - له معايير نشطة: ${filterCriteria!.hasActiveFilters}');
      print('   - الوصف: ${filterCriteria!.activeFiltersDescription}');
    }

    // تصفية العمليات للمستخدم المحدد
    List<Map<String, dynamic>>? userSpecificRecords;
    if (filteredRecords != null) {
      userSpecificRecords = filteredRecords!.where((record) {
        // البحث في منفذ العملية أو المُفعِّل
        final executor = record['منفذ العملية']?.toString().trim() ?? '';
        final activator = record['المُفعِّل']?.toString().trim() ?? '';
        return executor == userName || activator == userName;
      }).toList();
      print('   - عدد عمليات المستخدم: ${userSpecificRecords.length}');
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UserRecordsPage(
          userName: userName,
          initialFilterCriteria: filterCriteria, // تمرير معايير التصفية الأولية
          userSpecificRecords:
              userSpecificRecords, // تمرير العمليات المفلترة للمستخدم
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('إحصائيات السجلات',
            style: TextStyle(fontSize: _fs(context, 18), fontWeight: FontWeight.w600)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          // زر لعرض جميع الوصولات (مع التصفية المطبقة)
          IconButton(
            icon: const Icon(Icons.list_alt),
            onPressed: () {
              print('🔍 AccountStatsPage - زر عرض جميع الوصولات');
              print('   - FilterCriteria موجود: ${filterCriteria != null}');
              if (filterCriteria != null) {
                print(
                    '   - له معايير نشطة: ${filterCriteria!.hasActiveFilters}');
              }

              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ConnectionsListPage(
                    filterCriteria: filterCriteria, // ⭐ تمرير معايير التصفية
                  ),
                ),
              );
            },
            tooltip: filterCriteria?.hasActiveFilters == true
                ? 'عرض الوصولات المفلترة'
                : 'عرض جميع الوصولات',
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(_isPhone(context) ? 10 : 16, 12, _isPhone(context) ? 10 : 16, 24),
        children: [
          Row(children: const [
            Icon(Icons.insights, color: Colors.deepPurple),
            SizedBox(width: 8),
            Expanded(
                child: Text('ملخص العمليات والمبالغ',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 12),
          _buildSummary(),
          const SizedBox(height: 16),
          const Divider(
            thickness: 1.5,
            color: Colors.black54,
            height: 0,
          ),
          const SizedBox(height: 12),
          Text('تفاصيل حسب المستخدم',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.deepPurple.shade700)),
          const SizedBox(height: 8),
          if (userStats.isEmpty)
            _emptyUsersBox()
          else
            ..._buildUserTiles(context),
          const SizedBox(height: 24),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text('حسب التصفية الحالية',
                style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          ),
        ],
      ),
    );
  }

  // قسم الملخص العلوي
  Widget _buildSummary() {
    return LayoutBuilder(builder: (ctx, constraints) {
      final maxWidth = constraints.maxWidth;
      const spacing = 10.0;
      final twoCols = maxWidth >= 420;
      final half = (maxWidth - spacing) / 2;

      Widget tile(String title, IconData icon, MaterialColor color, int count,
              double amount, String label) =>
          _squareTile(
            context: ctx,
            width: twoCols ? half : maxWidth,
            title: title,
            icon: icon,
            color: color,
            bgColor: color.shade50,
            borderColor: color.shade200,
            count: count,
            amount: amount,
            countLabel: label,
          );

      final paymentRow = twoCols
          ? Row(children: [
              tile('المدفوع نقداً', Icons.payments, Colors.teal, cashCount,
                  cashTotal, 'عملية'),
              const SizedBox(width: spacing),
              tile('أجل', Icons.schedule, Colors.purple, creditCount,
                  creditTotal, 'عملية'),
            ])
          : Column(children: [
              tile('المدفوع نقداً', Icons.payments, Colors.teal, cashCount,
                  cashTotal, 'عملية'),
              const SizedBox(height: spacing),
              tile('أجل', Icons.schedule, Colors.purple, creditCount,
                  creditTotal, 'عملية'),
            ]);

      // في الوضع العريض: عمود يمين (شراء وتجديد) وعمود يسار (العدد الكلي + المجموع الكلي)
      final opsSection = twoCols
          ? Row(children: [
              // Right column (RTL) purchase & renewal
              SizedBox(
                width: half,
                child: Column(children: [
                  tile('عمليات الشراء', Icons.shopping_cart, Colors.blue,
                      purchaseCount, purchaseTotal, 'عملية'),
                  const SizedBox(height: spacing),
                  tile('عمليات التجديد', Icons.refresh, Colors.orange,
                      renewalCount, renewalTotal, 'عملية'),
                ]),
              ),
              const SizedBox(width: spacing),
              // Left column (RTL) totals (count + amount)
              SizedBox(
                width: half,
                child: Column(children: [
                  _squareTile(
                    context: ctx,
                    width: half,
                    title: 'العدد الكلي',
                    icon: Icons.format_list_numbered,
                    color: Colors.green,
                    bgColor: Colors.green.shade50,
                    borderColor: Colors.green.shade200,
                    count: totalRecords,
                    amount: 0,
                    countLabel: 'سجل',
                    showAmount: false,
                  ),
                  const SizedBox(height: spacing),
                  _squareTile(
                    context: ctx,
                    width: half,
                    title: 'المجموع الكلي',
                    icon: Icons.account_balance_wallet,
                    color: Colors.teal,
                    bgColor: Colors.teal.shade50,
                    borderColor: Colors.teal.shade200,
                    count: totalRecords,
                    amount: totalAmount,
                    countLabel: 'سجلات',
                    showCount: false,
                  ),
                ]),
              ),
            ])
          : Column(children: [
              // في العرض الضيق نبقي التسلسل: شراء، تجديد، العدد، المجموع
              tile('عمليات الشراء', Icons.shopping_cart, Colors.blue,
                  purchaseCount, purchaseTotal, 'عملية'),
              const SizedBox(height: spacing),
              tile('عمليات التجديد', Icons.refresh, Colors.orange, renewalCount,
                  renewalTotal, 'عملية'),
              const SizedBox(height: spacing),
              _squareTile(
                context: ctx,
                width: maxWidth,
                title: 'العدد الكلي',
                icon: Icons.format_list_numbered,
                color: Colors.green,
                bgColor: Colors.green.shade50,
                borderColor: Colors.green.shade200,
                count: totalRecords,
                amount: 0,
                countLabel: 'سجل',
                showAmount: false,
              ),
              const SizedBox(height: spacing),
              _squareTile(
                context: ctx,
                width: maxWidth,
                title: 'المجموع الكلي',
                icon: Icons.account_balance_wallet,
                color: Colors.teal,
                bgColor: Colors.teal.shade50,
                borderColor: Colors.teal.shade200,
                count: totalRecords,
                amount: totalAmount,
                countLabel: 'سجلات',
                showCount: false,
              ),
            ]);

      return Column(children: [
        paymentRow,
        const SizedBox(height: 8),
        const Divider(thickness: 4, color: Color.fromARGB(255, 208, 55, 55)),
        const SizedBox(height: 8),
        opsSection,
      ]);
    });
  }

  // بطاقات المستخدمين (العنوان فوق البطاقة)
  List<Widget> _buildUserTiles(BuildContext context) {
    return userStats
        .map((u) => Card(
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Colors.black, width: 1),
              ),
              child: InkWell(
                onTap: () => _navigateToUserRecords(
                    context, u.name), // تغيير إلى صفحة السجلات الجديدة
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // صف يحتوي الصورة الرمزية واسم المستخدم داخل البطاقة
                      Row(
                        children: [
                          CircleAvatar(
                            radius: _isPhone(context) ? 16 : 20,
                            backgroundColor: Colors.deepPurple.shade100,
                            child: Text(
                              u.name.isNotEmpty ? u.name.characters.first : '?',
                              style: TextStyle(
                                  color: Colors.deepPurple.shade800,
                                  fontSize: _fs(context, 16)),
                            ),
                          ),
                          SizedBox(width: _isPhone(context) ? 6 : 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(u.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: _fs(context, 16),
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text('اضغط لعرض السجلات التفصيلية',
                                    style: TextStyle(
                                        fontSize: _fs(context, 11),
                                        color: Colors.grey.shade600,
                                        fontStyle: FontStyle.italic)),
                              ],
                            ),
                          ),
                          // زر اسمية الوصولات
                          Flexible(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.deepPurple.shade50,
                                    Colors.deepPurple.shade100
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: Colors.deepPurple.shade200),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    // إيقاف انتشار الضغطة للبطاقة الأصلية
                                    _navigateToConnectionsList(context, u.name);
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: _isPhone(context) ? 8 : 12, vertical: _isPhone(context) ? 6 : 8),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.assignment_outlined,
                                          size: _isPhone(context) ? 14 : 16,
                                          color: Colors.deepPurple.shade700,
                                        ),
                                        SizedBox(width: _isPhone(context) ? 2 : 4),
                                        Flexible(
                                          child: Text(
                                            _isPhone(context) ? 'الوصولات' : ' الوصولات التوصيل',
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: _fs(context, 12),
                                              fontWeight: FontWeight.w600,
                                              color: Colors.deepPurple.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          _metricGroup([
                            _metricBox(context, 'شراء', u.purchaseCount,
                                u.purchaseAmount, Colors.blue,
                                margin:
                                    const EdgeInsetsDirectional.only(end: 12)),
                            _metricBox(context, 'تجديد', u.renewalCount, u.renewalAmount,
                                Colors.orange,
                                margin: EdgeInsetsDirectional.zero),
                          ]),
                          _metricGroup([
                            _metricBox(context,
                                'نقد', u.cashCount, u.cashAmount, Colors.teal,
                                margin:
                                    const EdgeInsetsDirectional.only(end: 12)),
                            _metricBox(context, 'أجل', u.creditCount, u.creditAmount,
                                Colors.purple,
                                margin: EdgeInsetsDirectional.zero),
                          ]),
                          _metricBox(context, 'الإجمالي', u.totalActivations,
                              u.totalAmount, Colors.green),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
            ))
        .toList();
  }

  Widget _emptyUsersBox() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: const Text('لا توجد بيانات مستخدمين متاحة لهذه التصفية',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      );

  Widget _metricBox(BuildContext context, String label, int count, double amount,
          MaterialColor color,
          {EdgeInsetsDirectional? margin}) {
    final phone = _isPhone(context);
    final screenW = MediaQuery.of(context).size.width;
    final isTotal = label == 'الإجمالي';
    final boxWidth = isTotal
        ? (phone ? screenW * 0.85 : 480.0)
        : (phone ? screenW * 0.4 : 300.0);

    return Container(
        width: boxWidth,
        margin: margin ?? const EdgeInsetsDirectional.only(end: 16),
        padding: EdgeInsets.symmetric(
            horizontal: isTotal ? (phone ? 10 : 16) : (phone ? 8 : 14),
            vertical: isTotal ? (phone ? 10 : 14) : (phone ? 8 : 12)),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 1),
        ),
        child: Column(
          mainAxisAlignment:
              isTotal ? MainAxisAlignment.start : MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: isTotal ? _fs(context, 14) : _fs(context, 12),
                    fontWeight: FontWeight.w600,
                    color: color.shade800)),
            SizedBox(height: isTotal ? 8 : 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(_formatAmount(amount),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: isTotal ? _fs(context, 22) : _fs(context, 18),
                      fontWeight: FontWeight.w800,
                      color: color.shade900)),
            ),
            SizedBox(height: isTotal ? 10 : 6),
            Text('$count',
                style: TextStyle(
                    fontSize: isTotal ? _fs(context, 18) : _fs(context, 15),
                    fontWeight: FontWeight.w600,
                    color: color.shade700)),
          ],
        ),
      );
  }

  // تجميع عدة مربعات داخل إطار واحد
  Widget _metricGroup(List<Widget> children) => Container(
        margin: const EdgeInsetsDirectional.only(end: 16),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black, width: 1.2),
        ),
        child: Row(children: children),
      );

  // _detailChip أزيل لعدم الحاجة بعد إزالة صف الشيبس

  Widget _squareTile({
    required BuildContext context,
    required double width,
    required String title,
    required IconData icon,
    required MaterialColor color,
    required Color bgColor,
    required Color borderColor,
    required int count,
    required double amount,
    String countLabel = 'عملية',
    bool showCount = true,
    bool showAmount = true,
  }) {
    final phone = _isPhone(context);
    return SizedBox(
        width: width,
        child: Container(
          height: phone ? 70 : 80,
          padding: EdgeInsets.symmetric(horizontal: phone ? 8 : 12, vertical: phone ? 6 : 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(children: [
            Expanded(
                child: Row(children: [
              Icon(icon, color: color.shade700, size: phone ? 15 : 18),
              SizedBox(width: phone ? 4 : 8),
              Flexible(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: _fs(context, 16),
                          fontWeight: FontWeight.bold,
                          color: color.shade800))),
            ])),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (showCount)
                Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('$count',
                          style: TextStyle(
                              fontSize: _fs(context, 20),
                              fontWeight: FontWeight.bold,
                              color: color.shade900)),
                      Text(countLabel,
                          style:
                              TextStyle(fontSize: _fs(context, 12), color: color.shade700)),
                    ]),
              if (showCount && showAmount) SizedBox(width: phone ? 8 : 14),
              if (showAmount)
                Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(_formatAmount(amount),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: _fs(context, 16),
                              fontWeight: FontWeight.bold,
                              color: color.shade800)),
                      Text('IQD', style: TextStyle(fontSize: _fs(context, 12))),
                    ]),
                ]),
              ),
            ),
          ]),
        ),
      );
  }
}

// نموذج بيانات المستخدم
class UserAccountStat {
  final String name;
  final int purchaseCount;
  final double purchaseAmount;
  final int renewalCount;
  final double renewalAmount;
  final int cashCount;
  final double cashAmount;
  final int creditCount;
  final double creditAmount;

  const UserAccountStat({
    required this.name,
    this.purchaseCount = 0,
    this.purchaseAmount = 0,
    this.renewalCount = 0,
    this.renewalAmount = 0,
    this.cashCount = 0,
    this.cashAmount = 0,
    this.creditCount = 0,
    this.creditAmount = 0,
  });

  int get totalActivations => purchaseCount + renewalCount;
  double get totalAmount => purchaseAmount + renewalAmount;
}
