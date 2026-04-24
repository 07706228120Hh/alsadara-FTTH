/// اسم الصفحة: مبالغ المنشئين
/// وصف الصفحة: صفحة مبالغ ومستحقات المنشئين
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:excel/excel.dart' as ExcelLib;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'creator_transactions_detail_page.dart';

//صفحة اسماء المنشاة للعمليات  الحسابة
class CreatorAmountsPage extends StatefulWidget {
  final Map<String, double> creatorAmounts;
  final Function(String?, bool) onFilterByCreator;
  // إضافة المعاملات المفصلة لحساب أنواع العمليات
  final List<Map<String, dynamic>>? detailedTransactions;
  final String? authToken; // إضافة الرمز المميز للمصادقة

  const CreatorAmountsPage({
    super.key,
    required this.creatorAmounts,
    required this.onFilterByCreator,
    this.detailedTransactions,
    this.authToken,
  });

  @override
  State<CreatorAmountsPage> createState() => _CreatorAmountsPageState();
}

class _CreatorAmountsPageState extends State<CreatorAmountsPage> {
  bool get _isPhone => MediaQuery.of(context).size.width < 500;
  double _fs(double base) => _isPhone ? base * 0.85 : base;

  List<MapEntry<String, double>> sortedEntries = [];
  String searchQuery = '';
  String sortBy = 'name'; // تغيير الافتراضي إلى الترتيب حسب الأسماء الأبجدية
  bool isAscending = true; // ترتيب تصاعدي للأسماء الأبجدية
  bool showSortingOptions = false;

  // إضافة TextEditingController لإدارة نص البحث
  final TextEditingController _searchController = TextEditingController();

  // إضافة متغيرات جديدة لحساب أنواع العمليات حسب المنشأة
  Map<String, Map<String, double>> creatorTransactionTypes = {};

  @override
  void initState() {
    super.initState();
    _initializeData();
    _calculateTransactionTypesByCreator();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // دالة جديدة لحساب أنواع العمليات حسب كل منشأة وإعادة حساب المبلغ الإجمالي
  void _calculateTransactionTypesByCreator() {
    if (widget.detailedTransactions == null) return;

    creatorTransactionTypes = {};

    // خريطة جديدة لحساب المبالغ الإجمالية المحدثة
    Map<String, double> updatedCreatorAmounts = {};

    for (final transaction in widget.detailedTransactions!) {
      final amtDynamic = transaction['transactionAmount']?['value'] ?? 0.0;
      final num amtNum = (amtDynamic is num)
          ? amtDynamic
          : double.tryParse(amtDynamic.toString()) ?? 0.0;
      final double amount = amtNum.toDouble();

      // الحصول على اسم المنشأة
      String creatorName = 'بدون منشأة';
      final createdBy = transaction['createdBy'];
      final transactionUser = transaction['transactionUser'];
      final username = transaction['username'];

      if (createdBy != null && createdBy.toString().trim().isNotEmpty) {
        creatorName = createdBy.toString().trim();
      } else if (transactionUser != null &&
          transactionUser.toString().trim().isNotEmpty) {
        creatorName = transactionUser.toString().trim();
      } else if (username != null && username.toString().trim().isNotEmpty) {
        creatorName = username.toString().trim();
      }

      // تصنيف العملية
      final transactionType = transaction['type'] ?? '';
      String category = 'أخرى';

      // تعبئة رصيد عضو الفريق
      if (transactionType == 'REFILL_TEAM_MEMBER_BALANCE' ||
          transactionType == 'WALLET_TOPUP' ||
          transactionType == 'WALLET_TRANSFER') {
        category = 'تعبئة رصيد';
      }
      // عمليات الشراء
      else if (transactionType == 'PLAN_PURCHASE' ||
          transactionType == 'PLAN_SUBSCRIBE' ||
          transactionType == 'PURCHASE_COMMISSION' ||
          transactionType == 'HARDWARE_SELL' ||
          transactionType == 'BAL_CARD_SELL' ||
          transactionType.contains('PURCHASE')) {
        category = 'عمليات الشراء';
      }
      // عمليات التجديد والتغيير والمجدول
      else if (transactionType == 'PLAN_RENEW' ||
          transactionType == 'AUTO_RENEW' ||
          transactionType == 'PLAN_EMI_RENEW' ||
          transactionType == 'PLAN_CHANGE' ||
          transactionType == 'PLAN_SCHEDULE' ||
          transactionType == 'SCHEDULE_CHANGE' ||
          transactionType.contains('RENEW') ||
          transactionType.contains('SCHEDULE')) {
        category = 'تجديد وتغيير ومجدول';
      }

      // إضافة المبلغ للمنشأة والفئة
      if (!creatorTransactionTypes.containsKey(creatorName)) {
        creatorTransactionTypes[creatorName] = {
          'تعبئة رصيد': 0.0,
          'عمليات الشراء': 0.0,
          'تجديد وتغيير ومجدول': 0.0,
          'أخرى': 0.0,
        };
        updatedCreatorAmounts[creatorName] = 0.0;
      }

      creatorTransactionTypes[creatorName]![category] =
          (creatorTransactionTypes[creatorName]![category] ?? 0.0) + amount;

      // حساب المبلغ الإجمالي: فقط عمليات الشراء + التجديد والتغيير والمجدول
      if (category == 'عمليات الشراء' || category == 'تجديد وتغيير ومجدول') {
        updatedCreatorAmounts[creatorName] =
            (updatedCreatorAmounts[creatorName] ?? 0.0) + amount;
      }
    }

    // تحديث المبالغ الإجمالية لتعكس فقط عمليات الشراء والتجديد
    widget.creatorAmounts.clear();
    widget.creatorAmounts.addAll(updatedCreatorAmounts);

    // إعادة تحديث القائمة المرتبة
    _initializeData();
  }

  void _initializeData() {
    sortedEntries = widget.creatorAmounts.entries.toList();
    _sortEntries();
  }

  void _sortEntries() {
    // إعادة تعيين القائمة إلى جميع الإدخالات أولاً
    sortedEntries = widget.creatorAmounts.entries.toList();

    // تطبيق الفلترة بناءً على البحث أولاً
    if (searchQuery.isNotEmpty) {
      sortedEntries = sortedEntries
          .where((entry) =>
              entry.key.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();
    }

    // ثم تطبيق الترتيب
    switch (sortBy) {
      case 'amount':
        sortedEntries.sort((a, b) => isAscending
            ? a.value.abs().compareTo(b.value.abs())
            : b.value.abs().compareTo(a.value.abs()));
        break;
      case 'name':
        sortedEntries.sort((a, b) {
          // جعل "بدون منشأة" دائماً في المقدمة
          if (a.key == 'بدون منشأة' && b.key != 'بدون منشأة') return -1;
          if (b.key == 'بدون منشأة' && a.key != 'بدون منشأة') return 1;

          return isAscending ? a.key.compareTo(b.key) : b.key.compareTo(a.key);
        });
        break;
      case 'alphabetical':
        sortedEntries.sort((a, b) {
          // جعل "بدون منشأة" دائماً في المقدمة
          if (a.key == 'بدون منشأة' && b.key != 'بدون منشأة') return -1;
          if (b.key == 'بدون منشأة' && a.key != 'بدون منشأة') return 1;

          return isAscending ? a.key.compareTo(b.key) : b.key.compareTo(a.key);
        });
        break;
    }

    setState(() {});
  }

  String _formatCurrency(dynamic value) {
    if (value == null) return '0';
    final amount = (value is int) ? value : (value as double).round();
    return amount.toString();
  }

  // حساب المجموع الكلي لجميع المبالغ
  double _calculateTotalAmount() {
    double total = 0;
    for (var entry in sortedEntries) {
      total += entry.value;
    }
    return total;
  }

  // نسخ نتائج المنشآت إلى الحافظة
  Future<void> _copyCreatorAmountsToClipboard() async {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('المبالغ حسب المنشأة (عمليات الشراء والتجديد فقط):');
    buffer.writeln('=========================================');
    buffer.writeln();

    for (int i = 0; i < sortedEntries.length; i++) {
      final entry = sortedEntries[i];
      buffer.writeln(
          '${i + 1}. ${entry.key}: ${_formatCurrency(entry.value)} IQD');
    }

    buffer.writeln();
    buffer.writeln('إجمالي المنشآت: ${widget.creatorAmounts.length}');
    buffer.writeln(
        'ملاحظة: المبالغ تشمل عمليات الشراء والتجديد والتغيير والمجدول فقط');

    await Clipboard.setData(ClipboardData(text: buffer.toString()));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم نسخ نتائج المنشآت إلى الحافظة'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // تصدير نتائج المنشآت إلى Excel
  Future<void> _exportCreatorAmountsToExcel() async {
    try {
      // إظهار مؤشر التحميل
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF1A237E)),
              SizedBox(height: 16),
              Text('جاري تصدير بيانات المنشآت...'),
            ],
          ),
        ),
      );

      // إنشاء ملف Excel
      var excel = ExcelLib.Excel.createExcel();
      ExcelLib.Sheet sheetObject = excel['المبالغ حسب المنشأة (شراء+تجديد)'];

      // إضافة العناوين
      sheetObject.cell(ExcelLib.CellIndex.indexByString("A1")).value =
          ExcelLib.TextCellValue('الترتيب');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("B1")).value =
          ExcelLib.TextCellValue('اسم المنشأة');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("C1")).value =
          ExcelLib.TextCellValue('المبلغ الإجمالي');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("D1")).value =
          ExcelLib.TextCellValue('العملة');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("E1")).value =
          ExcelLib.TextCellValue('نوع المبلغ');

      // تنسيق العناوين
      for (int col = 0; col < 5; col++) {
        var cell = sheetObject.cell(
            ExcelLib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
        cell.cellStyle = ExcelLib.CellStyle(
          bold: true,
          backgroundColorHex: ExcelLib.ExcelColor.blue,
          fontColorHex: ExcelLib.ExcelColor.white,
        );
      }

      // إضافة البيانات
      for (int i = 0; i < sortedEntries.length; i++) {
        final entry = sortedEntries[i];
        int row = i + 2;

        sheetObject.cell(ExcelLib.CellIndex.indexByString("A$row")).value =
            ExcelLib.IntCellValue(i + 1);
        sheetObject.cell(ExcelLib.CellIndex.indexByString("B$row")).value =
            ExcelLib.TextCellValue(entry.key);
        sheetObject.cell(ExcelLib.CellIndex.indexByString("C$row")).value =
            ExcelLib.DoubleCellValue(entry.value);
        sheetObject.cell(ExcelLib.CellIndex.indexByString("D$row")).value =
            ExcelLib.TextCellValue('IQD');
        sheetObject.cell(ExcelLib.CellIndex.indexByString("E$row")).value =
            ExcelLib.TextCellValue(entry.value > 0
                ? 'موجب'
                : entry.value < 0
                    ? 'سالب'
                    : 'صفر');
      }

      // حفظ الملف
      Directory? directory;
      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      String fileName =
          'المبالغ_حسب_المنشأة_شراء_تجديد_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.xlsx';
      String filePath = '${directory!.path}/$fileName';

      File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(excel.encode()!);

      // إغلاق مؤشر التحميل
      Navigator.of(context).pop();

      // إظهار رسالة نجاح
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text('تم تصدير ${sortedEntries.length} منشأة بنجاح'),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          action: SnackBarAction(
            label: 'فتح',
            textColor: Colors.white,
            onPressed: () => OpenFilex.open(filePath),
          ),
        ),
      );
    } catch (e) {
      // إغلاق مؤشر التحميل في حالة الخطأ
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل في تصدير بيانات المنشآت'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Widget _buildSortingOptions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sort, color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'خيارات الترتيب',
                style: TextStyle(
                  fontSize: _fs(16),
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSortButton('المبلغ', 'amount', Icons.attach_money),
              _buildSortButton('الاسم', 'name', Icons.person),
              _buildSortButton('أبجدي', 'alphabetical', Icons.sort_by_alpha),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                color: Colors.grey[600],
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                isAscending ? 'تصاعدي' : 'تنازلي',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Switch(
                value: isAscending,
                onChanged: (value) {
                  setState(() {
                    isAscending = value;
                  });
                  _sortEntries();
                },
                activeThumbColor: const Color(0xFF1A237E),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSortButton(String label, String value, IconData icon) {
    final isSelected = sortBy == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          sortBy = value;
        });
        _sortEntries();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A237E) : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF1A237E) : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // بناء بطاقة نوع عملية واحدة - مصغرة للعرض في نفس الصف
  Widget _buildSmallOperationTypeCard(
      String title, double amount, MaterialColor color, IconData icon) {
    return Expanded(
      // تغيير إلى Expanded لتوزيع المساحة بالتساوي
      child: Container(
        height: _isPhone ? 48 : 60, // ارتفاع أكبر قليلاً
        padding: EdgeInsets.symmetric(
            horizontal: _isPhone ? 4 : 6, vertical: _isPhone ? 4 : 8), // زيادة الحشو الأفقي
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.15),
              color.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // النص والمبلغ في صف واحد
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // النص
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: _fs(13), // زيادة من 11 إلى 13
                      fontWeight: FontWeight.w900, // خط أعرض (أكثر سمكاً)
                      color: color[700],
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: _isPhone ? 3 : 6), // مسافة بين النص والمبلغ
                // المبلغ
                Flexible(
                  child: Text(
                    _formatCurrency(amount),
                    style: TextStyle(
                      fontSize: _fs(14), // زيادة من 12 إلى 14
                      fontWeight: FontWeight.w900, // خط أعرض (أكثر سمكاً)
                      color: color[800],
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreatorCard(MapEntry<String, double> entry, int index) {
    final creatorName = entry.key;
    final amount = entry.value;
    final isPositive = amount > 0;
    final isNegative = amount < 0;
    final creatorTypes = creatorTransactionTypes[creatorName];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          // فتح صفحة تفاصيل المعاملات للمنشأة المحددة
          if (widget.detailedTransactions != null && widget.authToken != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CreatorTransactionsDetailPage(
                  creatorName: creatorName,
                  creatorAmounts: widget.creatorAmounts,
                  allTransactions: widget.detailedTransactions!,
                  authToken: widget.authToken!,
                ),
              ),
            );
          } else {
            // إذا لم تكن البيانات متوفرة، استخدم الطريقة القديمة
            widget.onFilterByCreator(
              creatorName == 'بدون منشأة' ? null : creatorName,
              creatorName == 'بدون منشأة',
            );
            Navigator.of(context).pop();
          }
        },
        child: Card(
          margin: const EdgeInsets.all(0),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: Colors.black,
              width: 3.0,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(_isPhone ? 8 : 12),
            child: Row(
              children: [
                // أيقونة المنشأة
                Container(
                  width: _isPhone ? 32 : 40,
                  height: _isPhone ? 32 : 40,
                  decoration: BoxDecoration(
                    color: isPositive
                        ? Colors.green[100]
                        : isNegative
                            ? Colors.red[100]
                            : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isPositive
                          ? Colors.green[300]!
                          : isNegative
                              ? Colors.red[300]!
                              : Colors.grey[300]!,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    creatorName == 'بدون منشأة'
                        ? Icons.person_off
                        : Icons.person,
                    color: isPositive
                        ? Colors.green[700]
                        : isNegative
                            ? Colors.red[700]
                            : Colors.grey[700],
                    size: _isPhone ? 16 : 20,
                  ),
                ),
                SizedBox(width: _isPhone ? 6 : 12),

                // معلومات المنشأة
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // الصف الأول: اسم المنشأة + مربعات العمليات
                      Row(
                        children: [
                          // اسم المنشأة ورقمها
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  creatorName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: creatorName == 'بدون منشأة'
                                        ? Colors.orange[800]
                                        : Colors.black87,
                                    fontSize: _fs(14),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.numbers,
                                      size: _isPhone ? 10 : 12,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'رقم ${index + 1}',
                                      style: TextStyle(
                                        fontSize: _fs(11),
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 8),

                          // مربعات أنواع العمليات - بتوزيع متساوي للمساحة
                          if (creatorTypes != null)
                            Expanded(
                              flex: 3, // تأخذ 3 أجزاء من المساحة المتاحة
                              child: Row(
                                children: [
                                  // مربع تعبئة الرصيد
                                  _buildSmallOperationTypeCard(
                                    'تعبئة',
                                    creatorTypes['تعبئة رصيد'] ?? 0.0,
                                    Colors.blue,
                                    Icons.account_balance_wallet,
                                  ),
                                  const SizedBox(width: 4),
                                  // مربع عمليات الشراء
                                  _buildSmallOperationTypeCard(
                                    'شراء',
                                    creatorTypes['عمليات الشراء'] ?? 0.0,
                                    Colors.orange,
                                    Icons.shopping_cart,
                                  ),
                                  const SizedBox(width: 4),
                                  // مربع التجديد
                                  _buildSmallOperationTypeCard(
                                    'تجديد',
                                    creatorTypes['تجديد وتغيير ومجدول'] ?? 0.0,
                                    Colors.purple,
                                    Icons.refresh,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // بطاقة المبلغ الإجمالي - بنفس عرض المربعات الأخرى
                Expanded(
                  child: Container(
                    height: _isPhone ? 48 : 60, // نفس ارتفاع المربعات الأخرى
                    padding:
                        EdgeInsets.symmetric(horizontal: _isPhone ? 4 : 6, vertical: _isPhone ? 4 : 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          isPositive
                              ? Colors.green[50]!
                              : isNegative
                                  ? Colors.red[50]!
                                  : Colors.grey[50]!,
                          isPositive
                              ? Colors.green[100]!
                              : isNegative
                                  ? Colors.red[100]!
                                  : Colors.grey[100]!,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isPositive
                            ? Colors.green[300]!
                            : isNegative
                                ? Colors.red[300]!
                                : Colors.grey[300]!,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isPositive
                                  ? Colors.green
                                  : isNegative
                                      ? Colors.red
                                      : Colors.grey)
                              .withValues(alpha: 0.08),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // المبلغ والعملة ونوع العملية في صف واحد
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // المبلغ مع العملة
                            Flexible(
                              child: Text(
                                '${amount >= 0 ? '+' : ''}${_formatCurrency(amount)} IQD',
                                style: TextStyle(
                                  fontWeight: FontWeight
                                      .w900, // نفس سمك خط المربعات الأخرى
                                  color: isPositive
                                      ? Colors.green[800]
                                      : isNegative
                                          ? Colors.red[800]
                                          : Colors.grey[800],
                                  fontSize:
                                      _fs(16), // تكبير حجم المبلغ في المجموع النهائي
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            // نص المؤشر مختصر
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: isPositive
                                    ? Colors.green[200]
                                    : isNegative
                                        ? Colors.red[200]
                                        : Colors.grey[200],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'المجموع',
                                style: TextStyle(
                                  fontSize: 10, // زيادة من 8 إلى 10
                                  fontWeight: FontWeight.w900,
                                  color: isPositive
                                      ? Colors.green[800]
                                      : isNegative
                                          ? Colors.red[800]
                                          : Colors.grey[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // أيقونة السهم للنقر
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        elevation: 0,
        toolbarHeight:
            _isPhone ? 56 : 68, // زيادة ارتفاع الشريط أكثر لتجنب التداخل مع مربع البحث
        iconTheme: const IconThemeData(color: Colors.white),
        title: Container(
          margin: const EdgeInsets.only(
              top: 5), // تقليل المسافة قليلاً مع زيادة الارتفاع
          padding: EdgeInsets.symmetric(
              horizontal: _isPhone ? 10 : 18, vertical: _isPhone ? 6 : 8), // تقليل الـ padding العمودي قليلاً
          decoration: BoxDecoration(
            color: Colors.white, // خلفية بيضاء صلبة بدلاً من الشفاف
            borderRadius: BorderRadius.circular(16), // حواف مدورة أكثر
            border: Border.all(
                color: Colors.grey.withValues(alpha: 0.3),
                width: 1.5), // حدود أفتح للتباين مع الخلفية البيضاء
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: 0.15), // تقليل قوة الظل قليلاً
                blurRadius: 8, // تقليل الضبابية
                offset: const Offset(0, 4), // تقليل الإزاحة
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.1), // ظل أبيض أخف
                blurRadius: 3,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(_isPhone ? 4 : 6), // تكبير إطار الأيقونة
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E)
                        .withValues(alpha: 0.1), // خلفية أزرق فاتح
                    borderRadius: BorderRadius.circular(10), // حواف مدورة أكثر
                  ),
                  child: Icon(
                    Icons.account_balance_wallet,
                    color: const Color(0xFF1A237E), // لون أزرق داكن للأيقونة
                    size: _isPhone ? 16 : 22, // تكبير الأيقونة أكثر
                  ),
                ),
                SizedBox(width: _isPhone ? 6 : 10), // زيادة المسافة
                Text(
                  'المجموع: ',
                  style: TextStyle(
                    color: const Color(
                        0xFF1A237E), // لون أزرق داكن يتناسق مع لون الشريط
                    fontSize: _fs(16), // تكبير الخط أكثر
                    fontWeight: FontWeight.w700, // تقوية الخط
                  ),
                ),
                Text(
                  '${_formatCurrency(_calculateTotalAmount())} IQD',
                  style: TextStyle(
                    color: const Color.fromARGB(
                        255, 201, 12, 12), // لون أخضر داكن للمبلغ
                    fontSize: _isPhone ? 18 : 28, // تكبير خط المبلغ أكثر
                    fontWeight: FontWeight.w900, // أثقل خط للمبلغ
                    letterSpacing: _isPhone ? 0.5 : 1.2, // تباعد بين الأحرف للمظهر الأنيق
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          // زر خيارات الترتيب
          IconButton(
            icon: Icon(
              showSortingOptions ? Icons.expand_less : Icons.expand_more,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                showSortingOptions = !showSortingOptions;
              });
            },
            tooltip: showSortingOptions
                ? 'إخفاء خيارات الترتيب'
                : 'عرض خيارات الترتيب',
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
            onPressed: _copyCreatorAmountsToClipboard,
            tooltip: 'نسخ النتائج',
          ),
          IconButton(
            icon: const Icon(Icons.file_download, color: Colors.white),
            onPressed: _exportCreatorAmountsToExcel,
            tooltip: 'تصدير إلى Excel',
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط البحث والإحصائيات
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(_isPhone ? 10 : 16),
            decoration: const BoxDecoration(
              color: Color(0xFF1A237E),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // شريط البحث
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'البحث في أسماء المنشآت...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: Colors.grey[400]),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                searchQuery = '';
                              });
                              _sortEntries();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  onChanged: (value) {
                    setState(() {
                      searchQuery = value;
                    });
                    _sortEntries();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // خيارات الترتيب (مشروطة)
          if (showSortingOptions) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildSortingOptions(),
            ),
            const SizedBox(height: 16),
          ],

          // قائمة المنشآت
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: _isPhone ? 8 : 16),
              child: sortedEntries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: _isPhone ? 56 : 80,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            searchQuery.isNotEmpty
                                ? 'لا توجد نتائج للبحث'
                                : 'لا توجد بيانات لعرضها',
                            style: TextStyle(
                              fontSize: _fs(18),
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: sortedEntries.length,
                      itemBuilder: (context, index) {
                        return _buildCreatorCard(sortedEntries[index], index);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
