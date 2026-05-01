/// اسم الصفحة: الأرباح
/// وصف الصفحة: صفحة حساب وعرض الأرباح من المعاملات المالية
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/auth_service.dart';
import '../auth/auth_error_handler.dart';

class ProfitsPage extends StatefulWidget {
  final String authToken;
  final Map<String, dynamic>? filterData;
  final List<Map<String, dynamic>>? transactions; // البيانات الممررة مباشرة

  const ProfitsPage({
    super.key,
    required this.authToken,
    this.filterData,
    this.transactions, // استقبال البيانات مباشرة
  });

  @override
  State<ProfitsPage> createState() => _ProfitsPageState();
}

class _ProfitsPageState extends State<ProfitsPage> {
  bool isLoading = true;
  bool isCalculating = false;
  bool showAddProfitsDialog = false;

  // بيانات الأرباح
  Map<String, dynamic> profitData = {};
  List<Map<String, dynamic>> profitDetails = [];

  // ملخص الأرباح
  double totalRevenue = 0.0;
  double totalExpenses = 0.0;
  double netProfit = 0.0;
  double profitMargin = 0.0;

  // أرباح حسب النوع
  Map<String, double> profitsByType = {};
  Map<String, int> transactionCountByType = {};

  // أرباح حسب العميل
  Map<String, double> profitsByCustomer = {};

  // أرباح حسب الخدمة
  Map<String, double> profitsByService = {};

  // عدد المعاملات حسب الفئة ونوع المعاملة (إجمالي الأشهر بعد الضرب)
  Map<String, Map<String, int>> transactionCountByCategoryAndType = {};

  // عدد المعاملات الفعلي (قبل الضرب في الأشهر)
  Map<String, Map<String, int>> actualTransactionCountByCategoryAndType = {};

  // بيانات الأرباح الإضافية حسب الفئات
  Map<String, Map<String, TextEditingController>> categoryProfitControllers = {
    '35 Fiber': {
      'purchase': TextEditingController(),
      'renewalFromPurchase': TextEditingController(),
      'renewal': TextEditingController(),
    },
    '50 Fiber': {
      'purchase': TextEditingController(),
      'renewalFromPurchase': TextEditingController(),
      'renewal': TextEditingController(),
    },
    '75 Fiber': {
      'purchase': TextEditingController(),
      'renewalFromPurchase': TextEditingController(),
      'renewal': TextEditingController(),
    },
    '150 Fiber': {
      'purchase': TextEditingController(),
      'renewalFromPurchase': TextEditingController(),
      'renewal': TextEditingController(),
    },
  };

  // قيم الأرباح المحفوظة حسب الفئات
  Map<String, Map<String, double>> savedCategoryProfits = {};

  @override
  void dispose() {
    // تنظيف المتحكمات
    for (var category in categoryProfitControllers.values) {
      for (var controller in category.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  // تهيئة الصفحة بالترتيب الصحيح
  Future<void> _initializePage() async {
    await _loadSavedProfits();
    await _calculateProfits();
  }

  // تحميل القيم المحفوظة من SharedPreferences
  Future<void> _loadSavedProfits() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString('saved_category_profits');

      if (savedData != null) {
        final Map<String, dynamic> decoded = json.decode(savedData);
        setState(() {
          savedCategoryProfits = decoded.map((category, values) {
            return MapEntry(
              category,
              (values as Map<String, dynamic>).map(
                (type, value) => MapEntry(type, (value as num).toDouble()),
              ),
            );
          });

          // تحديث المتحكمات بالقيم المحفوظة
          for (var category in savedCategoryProfits.keys) {
            if (categoryProfitControllers.containsKey(category)) {
              for (var type in savedCategoryProfits[category]!.keys) {
                if (categoryProfitControllers[category]!.containsKey(type)) {
                  final value = savedCategoryProfits[category]![type]!;
                  categoryProfitControllers[category]![type]!.text =
                      value > 0 ? value.toStringAsFixed(0) : '';
                }
              }
            }
          }
        });
      }
    } catch (e) {
      print('Error loading saved profits');
    }
  }

  // حفظ القيم إلى SharedPreferences
  Future<void> _saveProfitsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataToSave = savedCategoryProfits.map((category, values) {
        return MapEntry(category, values);
      });
      await prefs.setString('saved_category_profits', json.encode(dataToSave));
    } catch (e) {
      print('Error saving profits');
    }
  }

  Future<void> _calculateProfits() async {
    setState(() {
      isLoading = true;
      isCalculating = true;
    });

    try {
      // استخدام البيانات الممررة إذا كانت موجودة، وإلا جلبها من API
      print('====== _calculateProfits ======');
      print('هل تم تمرير بيانات؟ ${widget.transactions != null}');
      print('عدد البيانات الممررة: ${widget.transactions?.length ?? 0}');

      if (widget.transactions != null && widget.transactions!.isNotEmpty) {
        print('✅ استخدام البيانات الممررة مباشرة');
        setState(() {
          profitDetails = widget.transactions!;
        });
      } else {
        print('❌ جلب البيانات من API');
        await _fetchProfitData();
      }

      print('عدد المعاملات في profitDetails: ${profitDetails.length}');
      _processProfitData();
    } catch (e) {
      _showError('حدث خطأ في حساب الأرباح');
    } finally {
      setState(() {
        isLoading = false;
        isCalculating = false;
      });
    }
  }

  Future<void> _fetchProfitData() async {
    // بناء URL مع الفلاتر المرسلة من صفحة المعاملات
    String url = _buildFilteredUrl();

    final response = await AuthService.instance.authenticatedRequest(
      'GET',
      url,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        profitDetails = List<Map<String, dynamic>>.from(data['items'] ?? []);
      });
    } else if (response.statusCode == 401) {
      _handle401Error();
    } else {
      throw Exception('فشل في تحميل بيانات الأرباح: ${response.statusCode}');
    }
  }

  String _buildFilteredUrl() {
    List<String> queryParams = [];

    // معاملات أساسية
    queryParams.add('pageSize=10000'); // جلب أكبر عدد ممكن
    queryParams.add('pageNumber=1');
    queryParams.add('sortCriteria.property=occuredAt');
    queryParams.add('sortCriteria.direction=desc');

    // إضافة الفلاتر المرسلة من صفحة المعاملات
    if (widget.filterData != null) {
      final filterData = widget.filterData!;

      // التواريخ
      if (filterData['fromDate'] != null) {
        final fromDate = DateTime.parse(filterData['fromDate']);
        final fromStr = '${fromDate.year.toString().padLeft(4, '0')}-${fromDate.month.toString().padLeft(2, '0')}-${fromDate.day.toString().padLeft(2, '0')}';
        queryParams.add('fromDate=$fromStr');
      }

      if (filterData['toDate'] != null) {
        final toDate = DateTime.parse(filterData['toDate']);
        final toStr = '${toDate.year.toString().padLeft(4, '0')}-${toDate.month.toString().padLeft(2, '0')}-${toDate.day.toString().padLeft(2, '0')}';
        queryParams.add('toDate=$toStr');
      }

      // أنواع المحفظة
      if (filterData['selectedWalletTypes'] != null) {
        for (String walletType in filterData['selectedWalletTypes']) {
          queryParams.add('walletTypes=$walletType');
        }
      }

      // أنواع المعاملات
      if (filterData['selectedTransactionTypes'] != null) {
        for (String transactionType in filterData['selectedTransactionTypes']) {
          queryParams.add('transactionTypes=$transactionType');
        }
      }

      // أسماء الخدمات
      if (filterData['selectedServiceNames'] != null) {
        for (String serviceName in filterData['selectedServiceNames']) {
          queryParams.add('serviceNames=$serviceName');
        }
      }

      // اسم المستخدم
      if (filterData['transactionUser'] != null) {
        queryParams.add('transactionUser=${filterData['transactionUser']}');
      }

      // الزون
      if (filterData['selectedZone'] != null) {
        queryParams.add('zoneId=${filterData['selectedZone']}');
      }
    }

    String baseUrl = 'https://admin.ftth.iq/api/transactions';
    return '$baseUrl?${queryParams.join('&')}';
  }

  void _processProfitData() {
    // إعادة تعيين البيانات
    totalRevenue = 0.0;
    totalExpenses = 0.0;
    profitsByType.clear();
    transactionCountByType.clear();
    profitsByCustomer.clear();
    profitsByService.clear();
    transactionCountByCategoryAndType.clear();
    actualTransactionCountByCategoryAndType.clear();

    // معلومات للتشخيص
    print('====== بدء معالجة بيانات الأرباح ======');
    print('إجمالي المعاملات المستلمة: ${profitDetails.length}');

    // الخطوة الأولى: حساب عدد المعاملات حسب الفئة ونوع المعاملة
    // فقط للمعاملات السالبة من الفئات المحددة
    int negativeCount = 0;
    int filteredCount = 0;

    for (var transaction in profitDetails) {
      // التحقق من أن المعاملة سالبة
      final amtDynamic = transaction['transactionAmount']?['value'] ?? 0.0;
      final num amtNum = (amtDynamic is num)
          ? amtDynamic
          : double.tryParse(amtDynamic.toString()) ?? 0.0;
      final double val = amtNum.toDouble();

      if (val < 0) negativeCount++;

      // تجاهل المعاملات غير السالبة (إذا مرت بالخطأ)
      if (val >= 0) continue;

      final transactionType = transaction['type'] ?? 'غير محدد';

      // محاولات متعددة لاستخراج اسم الفئة من مصادر مختلفة
      String service = 'غير محدد';

      // المحاولة 1: من subscriptionService.service.displayValue
      if (transaction['subscription']?['subscriptionService']?['service']
              ?['displayValue'] !=
          null) {
        service = transaction['subscription']['subscriptionService']['service']
            ['displayValue'];
      }
      // المحاولة 2: من subscription.displayValue
      else if (transaction['subscription']?['displayValue'] != null) {
        service = transaction['subscription']['displayValue'];
      }
      // المحاولة 3: من subscriptionService.displayValue
      else if (transaction['subscription']?['subscriptionService']
              ?['displayValue'] !=
          null) {
        service =
            transaction['subscription']['subscriptionService']['displayValue'];
      }
      // المحاولة 4: من service.displayValue مباشرة
      else if (transaction['service']?['displayValue'] != null) {
        service = transaction['service']['displayValue'];
      }

      // استخراج الفئة من اسم الخدمة
      String category = 'غير محدد';
      String serviceLower = service.toLowerCase();

      // ملاحظة: يجب فحص 150 قبل 50 لأن "50" موجود في "150"
      if (serviceLower.contains('150')) {
        category = '150 Fiber';
      } else if (serviceLower.contains('75')) {
        category = '75 Fiber';
      } else if (serviceLower.contains('50')) {
        category = '50 Fiber';
      } else if (serviceLower.contains('35')) {
        category = '35 Fiber';
      }

      // تجاهل المعاملات التي ليست من الفئات المطلوبة
      if (category == 'غير محدد') continue;

      filteredCount++;

      // تحديد نوع الربح (شراء أو تجديد/تغيير)
      String profitType = '';
      if (transactionType == 'PLAN_PURCHASE' ||
          transactionType == 'PurchaseSubscriptionFromTrial') {
        profitType = 'purchase';
      } else if (transactionType == 'PLAN_RENEW' ||
          transactionType == 'PLAN_CHANGE' ||
          transactionType == 'AUTO_RENEW' ||
          transactionType == 'PLAN_EMI_RENEW') {
        profitType = 'renewal';
      }

      // حساب مدة الاشتراك بالأشهر
      int durationInMonths = 1; // الافتراضي شهر واحد
      if (transaction['subscription']?['startsAt'] != null &&
          transaction['subscription']?['endsAt'] != null) {
        try {
          final startDate =
              DateTime.parse(transaction['subscription']['startsAt']);
          final endDate = DateTime.parse(transaction['subscription']['endsAt']);
          final durationInDays = endDate.difference(startDate).inDays;
          durationInMonths = (durationInDays / 30).round();
          if (durationInMonths < 1) {
            durationInMonths = 1; // الحد الأدنى شهر واحد
          }
        } catch (e) {
          durationInMonths = 1; // في حالة الخطأ، نستخدم شهر واحد
        }
      }

      // تحديث عداد المعاملات
      if (profitType.isNotEmpty) {
        // تحديث العدد الفعلي للمعاملات (قبل الضرب في الأشهر)
        if (!actualTransactionCountByCategoryAndType.containsKey(category)) {
          actualTransactionCountByCategoryAndType[category] = {
            'purchase': 0,
            'renewal': 0,
          };
        }
        actualTransactionCountByCategoryAndType[category]![profitType] =
            (actualTransactionCountByCategoryAndType[category]![profitType] ??
                    0) +
                1;

        // تحديث إجمالي الأشهر (بعد الضرب في مدة الاشتراك)
        if (!transactionCountByCategoryAndType.containsKey(category)) {
          transactionCountByCategoryAndType[category] = {
            'purchase': 0,
            'renewal': 0,
          };
        }
        transactionCountByCategoryAndType[category]![profitType] =
            (transactionCountByCategoryAndType[category]![profitType] ?? 0) +
                durationInMonths;
      }
    }

    print('عدد المعاملات السالبة: $negativeCount');
    print('عدد المعاملات المفلترة (فئات محددة): $filteredCount');
    print(
        'الفئات المحسوبة: ${transactionCountByCategoryAndType.keys.toList()}');
    transactionCountByCategoryAndType.forEach((category, counts) {
      print(
          '  $category: شراء=${counts["purchase"]}, تجديد=${counts["renewal"]}');
    });
    print('=====================================');

    // الخطوة الثانية: حساب الأرباح بناءً على العدد × القيمة المحفوظة
    // مع تطبيق القاعدة الجديدة: الشهر الأول من الشراء بقيمة الشراء، والأشهر المتبقية بقيمة تجديد من شراء
    Map<String, Map<String, double>> totalProfitsByCategory = {};

    // حساب الأرباح من معاملات الشراء مع تطبيق القاعدة الجديدة
    for (var category in ['35 Fiber', '50 Fiber', '75 Fiber', '150 Fiber']) {
      totalProfitsByCategory[category] = {
        'purchase': 0.0,
        'renewalFromPurchase': 0.0,
        'renewal': 0.0,
      };

      // حساب أرباح الشراء (مع القاعدة الجديدة)
      int purchaseCount =
          actualTransactionCountByCategoryAndType[category]?['purchase'] ?? 0;
      int purchaseTotalMonths =
          transactionCountByCategoryAndType[category]?['purchase'] ?? 0;
      double purchaseProfit =
          savedCategoryProfits[category]?['purchase'] ?? 0.0;
      double renewalFromPurchaseProfit =
          savedCategoryProfits[category]?['renewalFromPurchase'] ?? 0.0;
      double renewalProfit = savedCategoryProfits[category]?['renewal'] ?? 0.0;

      if (purchaseCount > 0) {
        // الشهر الأول من كل معاملة شراء بقيمة الشراء
        double firstMonthsProfit = purchaseCount * purchaseProfit;
        totalProfitsByCategory[category]!['purchase'] = firstMonthsProfit;

        // الأشهر المتبقية بقيمة تجديد من شراء
        int remainingMonths = purchaseTotalMonths - purchaseCount;
        double remainingMonthsProfit =
            remainingMonths * renewalFromPurchaseProfit;
        totalProfitsByCategory[category]!['renewalFromPurchase'] =
            remainingMonthsProfit;

        double totalPurchaseProfit = firstMonthsProfit + remainingMonthsProfit;

        // إضافة إلى الإجمالي
        if (totalPurchaseProfit > 0) {
          totalRevenue += totalPurchaseProfit;
        } else {
          totalExpenses += totalPurchaseProfit.abs();
        }
      }

      // حساب أرباح التجديد (بدون تغيير - كل الأشهر بقيمة التجديد)
      int renewalTotalMonths =
          transactionCountByCategoryAndType[category]?['renewal'] ?? 0;

      double totalRenewalProfit = renewalTotalMonths * renewalProfit;
      totalProfitsByCategory[category]!['renewal'] = totalRenewalProfit;

      // إضافة إلى الإجمالي
      if (totalRenewalProfit > 0) {
        totalRevenue += totalRenewalProfit;
      } else {
        totalExpenses += totalRenewalProfit.abs();
      }
    }

    // حساب صافي الربح ونسبة الربح
    netProfit = totalRevenue - totalExpenses;
    profitMargin = totalRevenue > 0 ? (netProfit / totalRevenue) * 100 : 0.0;

    // الخطوة الثالثة: معالجة المعاملات لأغراض أخرى (التصنيف حسب النوع، الشريك، الخدمة)
    for (var transaction in profitDetails) {
      final amtDynamic = transaction['transactionAmount']?['value'] ?? 0.0;
      final num amtNum = (amtDynamic is num)
          ? amtDynamic
          : double.tryParse(amtDynamic.toString()) ?? 0.0;
      final double amount = amtNum.toDouble();

      // الحصول على معلومات المعاملة
      final transactionType = transaction['type'] ?? 'غير محدد';

      // محاولات متعددة لاستخراج اسم الفئة
      String service = 'غير محدد';
      if (transaction['subscription']?['subscriptionService']?['service']
              ?['displayValue'] !=
          null) {
        service = transaction['subscription']['subscriptionService']['service']
            ['displayValue'];
      } else if (transaction['subscription']?['displayValue'] != null) {
        service = transaction['subscription']['displayValue'];
      } else if (transaction['subscription']?['subscriptionService']
              ?['displayValue'] !=
          null) {
        service =
            transaction['subscription']['subscriptionService']['displayValue'];
      } else if (transaction['service']?['displayValue'] != null) {
        service = transaction['service']['displayValue'];
      }

      // استخراج الفئة من اسم الخدمة
      String category = 'غير محدد';
      String serviceLower = service.toLowerCase();

      // ملاحظة: يجب فحص 150 قبل 50 لأن "50" موجود في "150"
      if (serviceLower.contains('150')) {
        category = '150 Fiber';
      } else if (serviceLower.contains('75')) {
        category = '75 Fiber';
      } else if (serviceLower.contains('50')) {
        category = '50 Fiber';
      } else if (serviceLower.contains('35')) {
        category = '35 Fiber';
      }

      // حساب قيمة الربح من الـ Map المحسوبة مسبقاً
      double profitAmount = 0.0;

      String profitType = '';
      if (transactionType == 'PLAN_PURCHASE' ||
          transactionType == 'PurchaseSubscriptionFromTrial') {
        profitType = 'purchase';
      } else if (transactionType == 'PLAN_RENEW' ||
          transactionType == 'PLAN_CHANGE' ||
          transactionType == 'AUTO_RENEW' ||
          transactionType == 'PLAN_EMI_RENEW') {
        profitType = 'renewal';
      }

      // حساب مدة الاشتراك بالأشهر لهذه المعاملة
      int durationInMonths = 1; // الافتراضي شهر واحد
      if (transaction['subscription']?['startsAt'] != null &&
          transaction['subscription']?['endsAt'] != null) {
        try {
          final startDate =
              DateTime.parse(transaction['subscription']['startsAt']);
          final endDate = DateTime.parse(transaction['subscription']['endsAt']);
          final durationInDays = endDate.difference(startDate).inDays;
          durationInMonths = (durationInDays / 30).round();
          if (durationInMonths < 1) {
            durationInMonths = 1; // الحد الأدنى شهر واحد
          }
        } catch (e) {
          durationInMonths = 1; // في حالة الخطأ، نستخدم شهر واحد
        }
      }

      // استخدام القيمة المحفوظة لهذه المعاملة الواحدة مع تطبيق القاعدة الجديدة
      if (profitType.isNotEmpty && savedCategoryProfits.containsKey(category)) {
        if (profitType == 'purchase') {
          // قاعدة الشراء: الشهر الأول بقيمة الشراء، والأشهر المتبقية بقيمة التجديد
          double purchaseProfitValue =
              savedCategoryProfits[category]?['purchase'] ?? 0.0;
          double renewalProfitValue =
              savedCategoryProfits[category]?['renewal'] ?? 0.0;

          if (durationInMonths == 1) {
            profitAmount = purchaseProfitValue;
          } else {
            // الشهر الأول بقيمة الشراء + الأشهر المتبقية بقيمة التجديد
            profitAmount = purchaseProfitValue +
                ((durationInMonths - 1) * renewalProfitValue);
          }
        } else {
          // التجديد: كل الأشهر بقيمة التجديد (بدون تغيير)
          double profitPerMonth =
              savedCategoryProfits[category]?[profitType] ?? 0.0;
          profitAmount = profitPerMonth * durationInMonths;
        }
      } else {
        profitAmount = amount;
      }

      // حساب الأرباح حسب النوع
      profitsByType[transactionType] =
          (profitsByType[transactionType] ?? 0.0) + profitAmount;
      transactionCountByType[transactionType] =
          (transactionCountByType[transactionType] ?? 0) + 1;

      // حساب الأرباح حسب نوع المعاملة
      profitsByType[transactionType] =
          (profitsByType[transactionType] ?? 0.0) + profitAmount;
      transactionCountByType[transactionType] =
          (transactionCountByType[transactionType] ?? 0) + 1;

      // حساب الأرباح حسب العميل
      final customer = transaction['customer']?['displayValue'] ?? 'غير محدد';
      profitsByCustomer[customer] =
          (profitsByCustomer[customer] ?? 0.0) + profitAmount;

      // حساب الأرباح حسب الخدمة
      profitsByService[service] =
          (profitsByService[service] ?? 0.0) + profitAmount;
    }
  }

  void _handle401Error() {
    AuthErrorHandler.handle401Error(context);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatCurrency(double amount) {
    return amount.round().toString();
  }

  String _translateTransactionType(String type) {
    const Map<String, String> translations = {
      'BAL_CARD_SELL': 'بيع بطاقة رصيد',
      'CASHBACK_COMMISSION': 'عمولة استرداد نقدي',
      'CASHOUT': 'سحب نقدي',
      'HARDWARE_SELL': 'بيع أجهزة',
      'MAINTENANCE_COMMISSION': 'عمولة صيانة',
      'PLAN_CHANGE': 'تغيير الباقة',
      'PLAN_PURCHASE': 'شراء باقة',
      'PLAN_RENEW': 'تجديد الباقة',
      'PURCHASE_COMMISSION': 'عمولة شراء',
      'SCHEDULE_CANCEL': 'إلغاء جدولة',
      'SCHEDULE_CHANGE': 'تغيير جدولة',
      'TERMINATE': 'إنهاء',
      'TRIAL_PERIOD': 'فترة تجريبية',
      'WALLET_REFUND': 'استرداد محفظة',
      'WALLET_TOPUP': 'شحن محفظة',
      'WALLET_TRANSFER': 'تحويل محفظة',
      'PLAN_SCHEDULE': 'جدولة باقة',
      'PURCH_COMM_REVERSAL': 'عكس عمولة شراء',
      'AUTO_RENEW': 'تجديد تلقائي',
      'TERMINATE_SUBSCRIPTION': 'إنهاء اشتراك',
      'PURCHASE_REVERSAL': 'عكس شراء',
      'HIER_COMM_REVERSAL': 'عكس عمولة هرمية',
      'HIERACHY_COMMISSION': 'عمولة هرمية',
      'WALLET_TRANSFER_COMMISSION': 'عمولة تحويل محفظة',
      'COMMISSION_TRANSFER': 'تحويل عمولة',
      'RENEW_REVERSAL': 'عكس تجديد',
      'MAINT_COMM_REVERSAL': 'عكس عمولة صيانة',
      'WALLET_REVERSAL': 'عكس محفظة',
      'WALLET_TRANSFER_FEE': 'رسوم تحويل محفظة',
      'PLAN_EMI_RENEW': 'تجديد قسط باقة',
      'PLAN_SUSPEND': 'تعليق باقة',
      'PLAN_REACTIVATE': 'إعادة تفعيل باقة',
      'REFILL_TEAM_MEMBER_BALANCE': 'تعبئة رصيد عضو فريق',
      'PurchaseSubscriptionFromTrial': 'شراء اشتراك من التجربة',
    };
    return translations[type] ?? type;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'حساب الأرباح',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF1A237E),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.white),
            onPressed: _showAddProfitsDialog,
            tooltip: 'إضافة أرباح',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _calculateProfits,
            tooltip: 'إعادة حساب الأرباح',
          ),
          IconButton(
            icon: const Icon(Icons.file_download, color: Colors.white),
            onPressed: _exportProfitData,
            tooltip: 'تصدير بيانات الأرباح',
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF1A237E)),
                  SizedBox(height: 16),
                  Text(
                    'جاري حساب الأرباح...',
                    style: TextStyle(fontSize: 16, color: Color(0xFF2C3E50)),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // بطاقة الإجمالي الكلي
                  if (savedCategoryProfits.isNotEmpty &&
                      transactionCountByCategoryAndType.isNotEmpty)
                    _buildTotalProfitCard(),
                  if (savedCategoryProfits.isNotEmpty &&
                      transactionCountByCategoryAndType.isNotEmpty)
                    const SizedBox(height: 18),

                  // تفاصيل الأرباح حسب الفئة ونوع المعاملة
                  if (savedCategoryProfits.isNotEmpty &&
                      transactionCountByCategoryAndType.isNotEmpty)
                    _buildProfitDetailsByCategorySection(),
                  if (savedCategoryProfits.isNotEmpty &&
                      transactionCountByCategoryAndType.isNotEmpty)
                    const SizedBox(height: 18),

                  // تم إخفاء الأقسام التالية لعرض جدول التفاصيل فقط:
                  // - الأرباح حسب نوع المعاملة
                  // - الأرباح حسب الشريك
                  // - الأرباح حسب الخدمة
                ],
              ),
            ),
    );
  }

  Widget _buildProfitSummaryCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ملخص الأرباح',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A237E),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // بطاقة إجمالي الإيرادات
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.trending_up,
                            color: Colors.green[700], size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'إجمالي الإيرادات',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_formatCurrency(totalRevenue)} IQD',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // بطاقة إجمالي المصروفات
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.trending_down,
                            color: Colors.red[700], size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'إجمالي المصروفات',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_formatCurrency(totalExpenses)} IQD',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[800],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // بطاقة صافي الربح ونسبة الربح
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: netProfit >= 0
                  ? [Colors.blue[400]!, Colors.blue[600]!]
                  : [Colors.orange[400]!, Colors.orange[600]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (netProfit >= 0 ? Colors.blue : Colors.orange)
                    .withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    netProfit >= 0 ? Icons.monetization_on : Icons.warning,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    netProfit >= 0 ? 'صافي الربح' : 'صافي الخسارة',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${_formatCurrency(netProfit.abs())} IQD',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'نسبة الربح: ${profitMargin.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTotalProfitCard() {
    double totalProfit = _calculateTotalProfitFromCategories();
    int totalTransactions = actualTransactionCountByCategoryAndType.values.fold(
        0,
        (sum, item) => sum + (item['purchase'] ?? 0) + (item['renewal'] ?? 0));

    // استخراج التواريخ بشكل منفصل
    String fromDateText = '';
    String toDateText = '';
    if (widget.filterData != null) {
      if (widget.filterData!['fromDate'] != null) {
        fromDateText = DateFormat('yyyy-MM-dd')
            .format(DateTime.parse(widget.filterData!['fromDate']));
      }
      if (widget.filterData!['toDate'] != null) {
        toDateText = DateFormat('yyyy-MM-dd')
            .format(DateTime.parse(widget.filterData!['toDate']));
      }
    }

    return Column(
      children: [
        // الصف الأول: بطاقتي التاريخ من وإلى
        Row(
          children: [
            // بطاقة من تاريخ
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.teal[400]!, Colors.teal[600]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.teal.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.calendar_today,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        const Text(
                          'من تاريخ',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      fromDateText.isNotEmpty ? fromDateText : '-',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // بطاقة إلى تاريخ
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.indigo[400]!, Colors.indigo[600]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.indigo.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.event, color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        const Text(
                          'إلى تاريخ',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      toDateText.isNotEmpty ? toDateText : '-',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // الصف الثاني: بطاقتي المبلغ وعدد المعاملات
        Row(
          children: [
            // بطاقة المبلغ الكلي
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: totalProfit >= 0
                        ? [Colors.blue[500]!, Colors.blue[700]!]
                        : [Colors.orange[500]!, Colors.orange[700]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: (totalProfit >= 0 ? Colors.blue : Colors.orange)
                          .withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          totalProfit >= 0
                              ? Icons.account_balance_wallet
                              : Icons.warning,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'إجمالي الأرباح',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${_formatCurrency(totalProfit.abs())} IQD',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // بطاقة عدد المعاملات
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.purple[400]!, Colors.purple[600]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.receipt_long,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        const Text(
                          'المعاملات',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$totalTransactions',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProfitDetailsByCategorySection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green[50]!, Colors.green[100]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // جدول التفاصيل
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Column(
              children: [
                // رأس الجدول
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.green[800],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      // الفئة
                      const Expanded(
                        flex: 2,
                        child: Text(
                          'الفئة',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // مجموعة الشراء
                      Expanded(
                        flex: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 4),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: Colors.green[400],
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: const [
                              Expanded(
                                child: Text(
                                  'عدد\nالشراء',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'مبلغ\nالشراء',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // مجموعة تجديد من شراء
                      Expanded(
                        flex: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 4),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: Colors.orange[400],
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: const [
                              Expanded(
                                child: Text(
                                  'أشهر تجديد\nمن شراء',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'مبلغ تجديد\nمن شراء',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // مجموعة التجديد العادي
                      Expanded(
                        flex: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 4),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: Colors.blue[400],
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: const [
                              Expanded(
                                child: Text(
                                  'عدد\nالتجديد',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'مبلغ\nالتجديد',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // الربح الكلي
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 4),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: Colors.purple[400],
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Text(
                            'الربح\nالكلي',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // صفوف البيانات - عرض جميع الفئات
                ...['35 Fiber', '50 Fiber', '75 Fiber', '150 Fiber']
                    .map((category) {
                  // الحصول على العدد الفعلي (قبل الضرب في الأشهر)
                  int actualPurchaseCount =
                      actualTransactionCountByCategoryAndType[category]
                              ?['purchase'] ??
                          0;
                  int actualRenewalCount =
                      actualTransactionCountByCategoryAndType[category]
                              ?['renewal'] ??
                          0;

                  // الحصول على إجمالي الأشهر (بعد الضرب في مدة الاشتراك)
                  int totalPurchaseMonths =
                      transactionCountByCategoryAndType[category]
                              ?['purchase'] ??
                          0;
                  int totalRenewalMonths =
                      transactionCountByCategoryAndType[category]?['renewal'] ??
                          0;

                  // حساب أشهر التجديد من الشراء
                  int renewalFromPurchaseMonths =
                      totalPurchaseMonths - actualPurchaseCount;
                  if (renewalFromPurchaseMonths < 0) {
                    renewalFromPurchaseMonths = 0;
                  }

                  // حساب الأرباح مع تطبيق القاعدة الجديدة
                  double purchaseProfit = 0.0;
                  double renewalFromPurchaseProfit = 0.0;
                  double renewalProfit = 0.0;

                  if (savedCategoryProfits.containsKey(category)) {
                    double purchaseProfitPerUnit =
                        savedCategoryProfits[category]?['purchase'] ?? 0.0;
                    double renewalFromPurchaseProfitPerUnit =
                        savedCategoryProfits[category]
                                ?['renewalFromPurchase'] ??
                            0.0;
                    double renewalProfitPerUnit =
                        savedCategoryProfits[category]?['renewal'] ?? 0.0;

                    // حساب أرباح الشراء (الشهر الأول فقط)
                    if (actualPurchaseCount > 0) {
                      purchaseProfit =
                          actualPurchaseCount * purchaseProfitPerUnit;
                      // حساب أرباح التجديد من الشراء (الأشهر المتبقية)
                      renewalFromPurchaseProfit = renewalFromPurchaseMonths *
                          renewalFromPurchaseProfitPerUnit;
                    }

                    // حساب أرباح التجديد العادي
                    renewalProfit = totalRenewalMonths * renewalProfitPerUnit;
                  }

                  double totalCategoryProfit = purchaseProfit +
                      renewalFromPurchaseProfit +
                      renewalProfit;

                  return Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[200]!),
                      ),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // اسم الفئة
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: Text(
                                category,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: Color(0xFF1A237E),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),

                          // مجموعة الشراء
                          Expanded(
                            flex: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 6),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: Colors.green[100],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.green[400]!, width: 2),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        '$actualPurchaseCount',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 18,
                                          color: Colors.black,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        _formatCurrency(purchaseProfit),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.black,
                                          fontWeight: FontWeight.w900,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // مجموعة تجديد من شراء
                          Expanded(
                            flex: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 6),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: Colors.orange[100],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.orange[400]!, width: 2),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        '$renewalFromPurchaseMonths',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 18,
                                          color: renewalFromPurchaseMonths > 0
                                              ? Colors.black
                                              : Colors.grey[500],
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        renewalFromPurchaseProfit > 0
                                            ? _formatCurrency(
                                                renewalFromPurchaseProfit)
                                            : (renewalFromPurchaseMonths > 0
                                                ? 'أدخل'
                                                : '0'),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: renewalFromPurchaseProfit > 0
                                              ? Colors.black
                                              : Colors.grey[500],
                                          fontWeight: FontWeight.w900,
                                          fontStyle:
                                              renewalFromPurchaseProfit > 0
                                                  ? FontStyle.normal
                                                  : FontStyle.italic,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // مجموعة التجديد العادي
                          Expanded(
                            flex: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 6),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: Colors.blue[100],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.blue[400]!, width: 2),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        totalRenewalMonths != actualRenewalCount
                                            ? '$actualRenewalCount ($totalRenewalMonths)'
                                            : '$actualRenewalCount',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                          color: Colors.black,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        _formatCurrency(renewalProfit),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.black,
                                          fontWeight: FontWeight.w900,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // الربح الكلي
                          Expanded(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 6),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.purple[200]!,
                                    Colors.purple[300]!
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.purple[500]!, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.purple.withValues(alpha: 0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  _formatCurrency(totalCategoryProfit),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                // صف الإجمالي
                if (transactionCountByCategoryAndType.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      border: Border(
                        top: BorderSide(color: Colors.grey[600]!, width: 3),
                      ),
                    ),
                    child: SizedBox(
                      height: 55,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: Text(
                                'الإجمالي',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  color: Colors.grey[900],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          // مجموعة إجمالي الشراء
                          Expanded(
                            flex: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 6),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: Colors.green[200],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.green[600]!, width: 2),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        '${actualTransactionCountByCategoryAndType.values.fold(0, (sum, item) => sum + (item['purchase'] ?? 0))}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 20,
                                          color: Colors.black,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        _formatCurrency(
                                            _calculateTotalPurchaseOnlyProfits()),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          color: Colors.black,
                                          fontWeight: FontWeight.w900,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // مجموعة إجمالي تجديد من شراء
                          Expanded(
                            flex: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 6),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: Colors.orange[200],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.orange[600]!, width: 2),
                              ),
                              child: Builder(
                                builder: (context) {
                                  final totalProfit =
                                      _calculateTotalRenewalFromPurchaseProfits();
                                  final totalMonths =
                                      _calculateTotalRenewalFromPurchaseMonths();
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: Center(
                                          child: Text(
                                            '$totalMonths',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 18,
                                              color: totalMonths > 0
                                                  ? Colors.black
                                                  : Colors.grey[600],
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Center(
                                          child: Text(
                                            totalProfit > 0
                                                ? _formatCurrency(totalProfit)
                                                : (totalMonths > 0
                                                    ? 'أدخل'
                                                    : '0'),
                                            style: TextStyle(
                                              fontSize: 17,
                                              color: totalProfit > 0
                                                  ? Colors.black
                                                  : Colors.grey[600],
                                              fontWeight: FontWeight.w900,
                                              fontStyle: totalProfit > 0
                                                  ? FontStyle.normal
                                                  : FontStyle.italic,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                          // مجموعة إجمالي التجديد العادي
                          Expanded(
                            flex: 4,
                            child: Builder(
                              builder: (context) {
                                final actualCount =
                                    actualTransactionCountByCategoryAndType
                                        .values
                                        .fold(
                                            0,
                                            (sum, item) =>
                                                sum + (item['renewal'] ?? 0));
                                final totalMonths =
                                    transactionCountByCategoryAndType.values
                                        .fold(
                                            0,
                                            (sum, item) =>
                                                sum + (item['renewal'] ?? 0));
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 6),
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[200],
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: Colors.blue[600]!, width: 2),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Center(
                                          child: Text(
                                            totalMonths != actualCount
                                                ? '$actualCount ($totalMonths)'
                                                : '$actualCount',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 18,
                                              color: Colors.black,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Center(
                                          child: Text(
                                            _formatCurrency(
                                                _calculateTotalRenewalProfits()),
                                            style: const TextStyle(
                                              fontSize: 17,
                                              color: Colors.black,
                                              fontWeight: FontWeight.w900,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          // الربح الكلي الإجمالي - الأكثر بروزاً
                          Expanded(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 6),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.purple[500]!,
                                    Colors.purple[700]!
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.purple[900]!, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.purple.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _formatCurrency(
                                        _calculateTotalProfitFromCategories()),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 20,
                                      color: Colors.white,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _calculateTotalProfitFromCategories() {
    double total = 0.0;
    for (var category in ['35 Fiber', '50 Fiber', '75 Fiber', '150 Fiber']) {
      if (savedCategoryProfits.containsKey(category)) {
        // حساب أرباح الشراء (مع القاعدة الجديدة)
        int actualPurchaseCount =
            actualTransactionCountByCategoryAndType[category]?['purchase'] ?? 0;
        int purchaseTotalMonths =
            transactionCountByCategoryAndType[category]?['purchase'] ?? 0;
        double purchaseProfitValue =
            savedCategoryProfits[category]?['purchase'] ?? 0.0;
        double renewalFromPurchaseProfitValue =
            savedCategoryProfits[category]?['renewalFromPurchase'] ?? 0.0;
        double renewalProfitValue =
            savedCategoryProfits[category]?['renewal'] ?? 0.0;

        double purchaseProfit = 0.0;
        double renewalFromPurchaseProfit = 0.0;
        if (actualPurchaseCount > 0) {
          // الشهر الأول من كل معاملة شراء بقيمة الشراء
          purchaseProfit = actualPurchaseCount * purchaseProfitValue;
          // الأشهر المتبقية بقيمة تجديد من شراء
          int remainingMonths = purchaseTotalMonths - actualPurchaseCount;
          renewalFromPurchaseProfit =
              remainingMonths * renewalFromPurchaseProfitValue;
        }

        // حساب أرباح التجديد العادي
        int renewalTotalMonths =
            transactionCountByCategoryAndType[category]?['renewal'] ?? 0;
        double renewalProfit = renewalTotalMonths * renewalProfitValue;

        total += purchaseProfit + renewalFromPurchaseProfit + renewalProfit;
      }
    }
    return total;
  }

  // حساب إجمالي أرباح الشراء فقط (الشهر الأول)
  double _calculateTotalPurchaseOnlyProfits() {
    double total = 0.0;
    for (var category in ['35 Fiber', '50 Fiber', '75 Fiber', '150 Fiber']) {
      if (savedCategoryProfits.containsKey(category)) {
        int actualPurchaseCount =
            actualTransactionCountByCategoryAndType[category]?['purchase'] ?? 0;
        double purchaseProfitValue =
            savedCategoryProfits[category]?['purchase'] ?? 0.0;
        total += actualPurchaseCount * purchaseProfitValue;
      }
    }
    return total;
  }

  // حساب إجمالي أشهر التجديد من الشراء
  int _calculateTotalRenewalFromPurchaseMonths() {
    int total = 0;
    for (var category in ['35 Fiber', '50 Fiber', '75 Fiber', '150 Fiber']) {
      int actualPurchaseCount =
          actualTransactionCountByCategoryAndType[category]?['purchase'] ?? 0;
      int purchaseTotalMonths =
          transactionCountByCategoryAndType[category]?['purchase'] ?? 0;
      int remainingMonths = purchaseTotalMonths - actualPurchaseCount;
      if (remainingMonths > 0) {
        total += remainingMonths;
      }
    }
    return total;
  }

  // حساب إجمالي أرباح التجديد من الشراء
  double _calculateTotalRenewalFromPurchaseProfits() {
    double total = 0.0;
    for (var category in ['35 Fiber', '50 Fiber', '75 Fiber', '150 Fiber']) {
      if (savedCategoryProfits.containsKey(category)) {
        int actualPurchaseCount =
            actualTransactionCountByCategoryAndType[category]?['purchase'] ?? 0;
        int purchaseTotalMonths =
            transactionCountByCategoryAndType[category]?['purchase'] ?? 0;
        double renewalFromPurchaseProfitValue =
            savedCategoryProfits[category]?['renewalFromPurchase'] ?? 0.0;
        int remainingMonths = purchaseTotalMonths - actualPurchaseCount;
        if (remainingMonths > 0) {
          total += remainingMonths * renewalFromPurchaseProfitValue;
        }
      }
    }
    return total;
  }

  double _calculateTotalPurchaseProfits() {
    double total = 0.0;
    for (var category in ['35 Fiber', '50 Fiber', '75 Fiber', '150 Fiber']) {
      if (savedCategoryProfits.containsKey(category)) {
        int actualPurchaseCount =
            actualTransactionCountByCategoryAndType[category]?['purchase'] ?? 0;
        int purchaseTotalMonths =
            transactionCountByCategoryAndType[category]?['purchase'] ?? 0;
        double purchaseProfitValue =
            savedCategoryProfits[category]?['purchase'] ?? 0.0;
        double renewalFromPurchaseProfitValue =
            savedCategoryProfits[category]?['renewalFromPurchase'] ?? 0.0;

        if (actualPurchaseCount > 0) {
          // الشهر الأول من كل معاملة شراء بقيمة الشراء
          double firstMonthsProfit = actualPurchaseCount * purchaseProfitValue;
          // الأشهر المتبقية بقيمة تجديد من شراء
          int remainingMonths = purchaseTotalMonths - actualPurchaseCount;
          double remainingMonthsProfit =
              remainingMonths * renewalFromPurchaseProfitValue;
          total += firstMonthsProfit + remainingMonthsProfit;
        }
      }
    }
    return total;
  }

  double _calculateTotalRenewalProfits() {
    double total = 0.0;
    transactionCountByCategoryAndType.forEach((category, counts) {
      if (savedCategoryProfits.containsKey(category)) {
        int renewalCount = counts['renewal'] ?? 0;
        double renewalProfitPerUnit =
            savedCategoryProfits[category]?['renewal'] ?? 0.0;
        total += renewalCount * renewalProfitPerUnit;
      }
    });
    return total;
  }

  Widget _buildProfitsByTypeSection() {
    if (profitsByType.isEmpty) return const SizedBox();

    // ترتيب الأنواع حسب الربح
    var sortedTypes = profitsByType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الأرباح حسب نوع المعاملة',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A237E),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedTypes.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = sortedTypes[index];
              final isProfit = entry.value > 0;
              final count = transactionCountByType[entry.key] ?? 0;

              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isProfit ? Colors.green[100] : Colors.red[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isProfit ? Icons.arrow_upward : Icons.arrow_downward,
                    color: isProfit ? Colors.green[700] : Colors.red[700],
                    size: 20,
                  ),
                ),
                title: Text(
                  _translateTransactionType(entry.key),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text('$count معاملة'),
                trailing: Text(
                  '${_formatCurrency(entry.value.abs())} IQD',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isProfit ? Colors.green[700] : Colors.red[700],
                    fontSize: 14,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProfitsByPartnerSection() {
    if (profitsByCustomer.isEmpty) return const SizedBox();

    var sortedCustomers = profitsByCustomer.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الأرباح حسب العميل',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A237E),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedCustomers.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = sortedCustomers[index];
              final isProfit = entry.value > 0;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      isProfit ? Colors.green[100] : Colors.red[100],
                  child: Icon(
                    Icons.person,
                    color: isProfit ? Colors.green[700] : Colors.red[700],
                    size: 20,
                  ),
                ),
                title: Text(
                  entry.key,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                trailing: Text(
                  '${_formatCurrency(entry.value.abs())} IQD',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isProfit ? Colors.green[700] : Colors.red[700],
                    fontSize: 14,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProfitsByServiceSection() {
    if (profitsByService.isEmpty) return const SizedBox();

    var sortedServices = profitsByService.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الأرباح حسب الخدمة',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A237E),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedServices.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = sortedServices[index];
              final isProfit = entry.value > 0;

              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isProfit ? Colors.blue[100] : Colors.orange[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.miscellaneous_services,
                    color: isProfit ? Colors.blue[700] : Colors.orange[700],
                    size: 20,
                  ),
                ),
                title: Text(
                  entry.key,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                trailing: Text(
                  '${_formatCurrency(entry.value.abs())} IQD',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isProfit ? Colors.blue[700] : Colors.orange[700],
                    fontSize: 14,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterInfoSection() {
    if (widget.filterData == null || widget.filterData!.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.grey),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'تم حساب الأرباح لجميع المعاملات بدون تطبيق فلاتر',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الفلاتر المطبقة',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A237E),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildFilterInfoItems(),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildFilterInfoItems() {
    final filterData = widget.filterData!;
    List<Widget> items = [];

    if (filterData['fromDate'] != null || filterData['toDate'] != null) {
      final fromDate = filterData['fromDate'] != null
          ? DateFormat('yyyy-MM-dd')
              .format(DateTime.parse(filterData['fromDate']))
          : 'غير محدد';
      final toDate = filterData['toDate'] != null
          ? DateFormat('yyyy-MM-dd')
              .format(DateTime.parse(filterData['toDate']))
          : 'غير محدد';

      items.add(
          _buildFilterInfoItem('النطاق الزمني', 'من $fromDate إلى $toDate'));
    }

    if (filterData['transactionUser'] != null) {
      items.add(
          _buildFilterInfoItem('اسم المستخدم', filterData['transactionUser']));
    }

    if (filterData['selectedZone'] != null) {
      items.add(_buildFilterInfoItem('الزون', filterData['selectedZone']));
    }

    if (filterData['selectedWalletTypes'] != null &&
        filterData['selectedWalletTypes'].isNotEmpty) {
      items.add(_buildFilterInfoItem(
          'أنواع المحفظة', filterData['selectedWalletTypes'].join(', ')));
    }

    if (filterData['selectedTransactionTypes'] != null &&
        filterData['selectedTransactionTypes'].isNotEmpty) {
      final translatedTypes = filterData['selectedTransactionTypes']
          .map((type) => _translateTransactionType(type))
          .join(', ');
      items.add(_buildFilterInfoItem('أنواع المعاملات', translatedTypes));
    }

    if (filterData['selectedServiceNames'] != null &&
        filterData['selectedServiceNames'].isNotEmpty) {
      items.add(_buildFilterInfoItem(
          'أسماء الخدمات', filterData['selectedServiceNames'].join(', ')));
    }

    items.add(_buildFilterInfoItem(
        'إجمالي المعاملات المحسوبة', '${profitDetails.length} معاملة'));

    return items;
  }

  Widget _buildFilterInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.blue[700],
              ),
            ),
          ),
          const Text(': '),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF2C3E50),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddProfitsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.8,
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // رأس الحوار
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'إضافة أرباح حسب الفئة',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A237E),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 10),

                    // ملاحظة توضيحية
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.blue[700], size: 20),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'سيتم احتساب الأرباح كالتالي: عدد المعاملات × قيمة الربح المدخلة',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF1565C0),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // جدول إدخال الأرباح
                    Expanded(
                      child: SingleChildScrollView(
                        child: _buildProfitCategoryTable(),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // أزرار الحفظ والإلغاء
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[300],
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 30, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('إلغاء'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            _saveCategoryProfits();
                            // لا نحتاج لإغلاق النافذة هنا لأن _saveCategoryProfits() يقوم بذلك
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A237E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 30, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('حفظ'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProfitCategoryTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // رأس الجدول
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E).withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'الفئة',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF1A237E),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'شراء باقة',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF1A237E),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'تجديد من شراء',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFFE65100),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'تجديد عادي',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF1A237E),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          // صفوف البيانات
          ...categoryProfitControllers.entries.map((entry) {
            String category = entry.key;
            Map<String, TextEditingController> controllers = entry.value;

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Row(
                children: [
                  // اسم الفئة
                  Expanded(
                    flex: 2,
                    child: Text(
                      category,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF2C3E50),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // حقل شراء باقة
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: TextField(
                        controller: controllers['purchase']!,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: '0',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),

                  // حقل تجديد من شراء
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: TextField(
                        controller: controllers['renewalFromPurchase']!,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: '0',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.orange[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                                color: Colors.orange[700]!, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),

                  // حقل تجديد عادي
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: TextField(
                        controller: controllers['renewal']!,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: '0',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _saveCategoryProfits() {
    try {
      // حفظ القيم المدخلة
      savedCategoryProfits.clear();

      categoryProfitControllers.forEach((category, controllers) {
        double purchaseProfit =
            double.tryParse(controllers['purchase']!.text) ?? 0.0;
        double renewalFromPurchaseProfit =
            double.tryParse(controllers['renewalFromPurchase']!.text) ?? 0.0;
        double renewalProfit =
            double.tryParse(controllers['renewal']!.text) ?? 0.0;

        savedCategoryProfits[category] = {
          'purchase': purchaseProfit,
          'renewalFromPurchase': renewalFromPurchaseProfit,
          'renewal': renewalProfit,
        };
      });

      // حفظ القيم في SharedPreferences
      _saveProfitsToStorage();

      // إعادة حساب الأرباح بناءً على القيم الجديدة
      setState(() {
        _processProfitData();
      });

      // إغلاق النافذة
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ قيم الأرباح بنجاح وإعادة حساب الأرباح'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      _showError('حدث خطأ في حفظ البيانات');
    }
  }

  Widget _buildSavedProfitsIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple[50]!, Colors.purple[100]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate, color: Colors.purple[700], size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'قيم الأرباح المخصصة مفعلة',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6A1B9A),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFF6A1B9A)),
                tooltip: 'إعادة تعيين الأرباح',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('إعادة تعيين الأرباح'),
                      content: const Text(
                        'هل تريد إعادة تعيين قيم الأرباح المخصصة والعودة للحساب الأصلي؟',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('إلغاء'),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            setState(() {
                              savedCategoryProfits.clear();
                              // مسح القيم من المتحكمات
                              for (var category
                                  in categoryProfitControllers.values) {
                                for (var controller in category.values) {
                                  controller.clear();
                                }
                              }
                              _processProfitData();
                            });
                            // حذف البيانات من التخزين
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.remove('saved_category_profits');

                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم إعادة تعيين الأرباح بنجاح'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          },
                          child: const Text('تأكيد'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'يتم حساب الأرباح بناءً على القيم المخصصة التي تم إدخالها:',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF4A148C),
            ),
          ),
          const SizedBox(height: 8),
          ...savedCategoryProfits.entries.map((entry) {
            String category = entry.key;
            double purchaseProfit = entry.value['purchase'] ?? 0.0;
            double renewalFromPurchaseProfit =
                entry.value['renewalFromPurchase'] ?? 0.0;
            double renewalProfit = entry.value['renewal'] ?? 0.0;

            if (purchaseProfit == 0.0 &&
                renewalFromPurchaseProfit == 0.0 &&
                renewalProfit == 0.0) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 8, color: Color(0xFF6A1B9A)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$category: شراء ${_formatCurrency(purchaseProfit)} - تجديد من شراء ${_formatCurrency(renewalFromPurchaseProfit)} - تجديد ${_formatCurrency(renewalProfit)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF4A148C),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _exportProfitData() async {
    try {
      // طلب إذن الوصول للتخزين
      if (Platform.isAndroid || Platform.isIOS) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          _showError('يجب منح إذن الوصول للتخزين لحفظ الملف');
          return;
        }
      }

      // إنشاء ملف Excel جديد
      var excel = excel_pkg.Excel.createExcel();

      // حذف الورقة الافتراضية
      excel.delete('Sheet1');

      // إنشاء ورقة الملخص
      var summarySheet = excel['ملخص الأرباح'];

      // إضافة عنوان التقرير
      summarySheet.merge(
        excel_pkg.CellIndex.indexByString('A1'),
        excel_pkg.CellIndex.indexByString('D1'),
      );
      var titleCell =
          summarySheet.cell(excel_pkg.CellIndex.indexByString('A1'));
      titleCell.value = excel_pkg.TextCellValue(
          'تقرير الأرباح - ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
      titleCell.cellStyle = excel_pkg.CellStyle(
        fontSize: 16,
        bold: true,
        horizontalAlign: excel_pkg.HorizontalAlign.Center,
      );

      // إضافة بيانات الملخص
      int row = 3;
      _addExcelRow(summarySheet, row++, ['البيان', 'القيمة'], isHeader: true);
      _addExcelRow(summarySheet, row++,
          ['إجمالي الإيرادات', '${_formatCurrency(totalRevenue)} IQD']);
      _addExcelRow(summarySheet, row++,
          ['إجمالي المصروفات', '${_formatCurrency(totalExpenses)} IQD']);
      _addExcelRow(summarySheet, row++,
          ['صافي الربح', '${_formatCurrency(netProfit)} IQD']);
      _addExcelRow(summarySheet, row++,
          ['نسبة الربح', '${profitMargin.toStringAsFixed(2)}%']);

      // إنشاء ورقة تفاصيل الأرباح حسب الفئة
      if (savedCategoryProfits.isNotEmpty &&
          transactionCountByCategoryAndType.isNotEmpty) {
        var categorySheet = excel['الأرباح حسب الفئة'];
        row = 1;

        _addExcelRow(
            categorySheet,
            row++,
            [
              'الفئة',
              'عدد الشراء',
              'مبلغ الشراء',
              'أشهر تجديد من شراء',
              'مبلغ تجديد من شراء',
              'عدد التجديد',
              'مبلغ التجديد',
              'الربح الكلي'
            ],
            isHeader: true);

        for (var category in [
          '35 Fiber',
          '50 Fiber',
          '75 Fiber',
          '150 Fiber'
        ]) {
          if (transactionCountByCategoryAndType.containsKey(category)) {
            final counts = transactionCountByCategoryAndType[category]!;

            // إجمالي الأشهر
            int totalPurchaseMonths = counts['purchase'] ?? 0;
            int totalRenewalMonths = counts['renewal'] ?? 0;

            // العدد الفعلي
            int actualPurchaseCount =
                actualTransactionCountByCategoryAndType[category]
                        ?['purchase'] ??
                    0;
            int actualRenewalCount =
                actualTransactionCountByCategoryAndType[category]?['renewal'] ??
                    0;

            // حساب أشهر تجديد من شراء (الأشهر المتبقية بعد الشهر الأول)
            int renewalFromPurchaseMonths = 0;
            if (actualPurchaseCount > 0 &&
                totalPurchaseMonths > actualPurchaseCount) {
              renewalFromPurchaseMonths =
                  totalPurchaseMonths - actualPurchaseCount;
            }

            double purchaseProfit = 0.0;
            double renewalFromPurchaseProfit = 0.0;
            double renewalProfit = 0.0;

            if (savedCategoryProfits.containsKey(category)) {
              double purchaseProfitPerUnit =
                  savedCategoryProfits[category]?['purchase'] ?? 0.0;
              double renewalFromPurchaseProfitPerUnit =
                  savedCategoryProfits[category]?['renewalFromPurchase'] ?? 0.0;
              double renewalProfitPerUnit =
                  savedCategoryProfits[category]?['renewal'] ?? 0.0;

              // ربح الشراء: عدد العمليات × ربح الشراء
              purchaseProfit = actualPurchaseCount * purchaseProfitPerUnit;

              // ربح تجديد من شراء: الأشهر المتبقية × ربح تجديد من شراء
              renewalFromPurchaseProfit =
                  renewalFromPurchaseMonths * renewalFromPurchaseProfitPerUnit;

              // ربح التجديد العادي: كل الأشهر × ربح التجديد
              renewalProfit = totalRenewalMonths * renewalProfitPerUnit;
            }

            double totalCategoryProfit =
                purchaseProfit + renewalFromPurchaseProfit + renewalProfit;

            if (actualPurchaseCount > 0 || actualRenewalCount > 0) {
              _addExcelRow(categorySheet, row++, [
                category,
                actualPurchaseCount.toString(),
                _formatCurrency(purchaseProfit),
                renewalFromPurchaseMonths.toString(),
                _formatCurrency(renewalFromPurchaseProfit),
                actualRenewalCount.toString(),
                _formatCurrency(renewalProfit),
                _formatCurrency(totalCategoryProfit),
              ]);
            }
          }
        }

        // إضافة صف الإجمالي
        int totalActualPurchases = actualTransactionCountByCategoryAndType
            .values
            .fold(0, (sum, item) => sum + (item['purchase'] ?? 0));
        int totalActualRenewals = actualTransactionCountByCategoryAndType.values
            .fold(0, (sum, item) => sum + (item['renewal'] ?? 0));

        _addExcelRow(
            categorySheet,
            row++,
            [
              'الإجمالي',
              totalActualPurchases.toString(),
              _formatCurrency(_calculateTotalPurchaseOnlyProfits()),
              _calculateTotalRenewalFromPurchaseMonths().toString(),
              _formatCurrency(_calculateTotalRenewalFromPurchaseProfits()),
              totalActualRenewals.toString(),
              _formatCurrency(_calculateTotalRenewalProfits()),
              _formatCurrency(_calculateTotalProfitFromCategories()),
            ],
            isHeader: true);
      }

      // إنشاء ورقة الأرباح حسب العميل
      if (profitsByCustomer.isNotEmpty) {
        var customerSheet = excel['الأرباح حسب العميل'];
        row = 1;

        _addExcelRow(customerSheet, row++, ['العميل', 'الأرباح'],
            isHeader: true);

        var sortedCustomers = profitsByCustomer.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        for (var entry in sortedCustomers) {
          _addExcelRow(customerSheet, row++, [
            entry.key,
            _formatCurrency(entry.value),
          ]);
        }

        // إضافة صف الإجمالي
        double totalCustomerProfits =
            profitsByCustomer.values.fold(0.0, (sum, value) => sum + value);
        _addExcelRow(customerSheet, row++,
            ['الإجمالي', _formatCurrency(totalCustomerProfits)],
            isHeader: true);
      }

      // إنشاء ورقة تفاصيل المعاملات
      var transactionsSheet = excel['تفاصيل المعاملات'];
      row = 1;

      _addExcelRow(
          transactionsSheet,
          row++,
          [
            'معرف المعاملة',
            'التاريخ',
            'نوع المعاملة',
            'الخدمة',
            'المبلغ',
            'العملة',
            'الرصيد المتبقي',
            'العميل',
            'معرف العميل',
            'الزون',
            'المستخدم',
            'طريقة الدفع',
            'نوع الدفع',
            'اسم الجهاز',
            'معرف الاشتراك',
            'بداية الاشتراك',
            'نهاية الاشتراك',
            'مدة الاشتراك',
            'نوع المحفظة',
            'مالك المحفظة',
            'نوع المبيعات',
            'نوع التغيير',
            'الخصم',
            'نوع الخصم',
          ],
          isHeader: true);

      for (var transaction in profitDetails) {
        final id = transaction['id']?.toString() ?? 'غير محدد';

        final date = transaction['occuredAt'] != null
            ? DateFormat('yyyy-MM-dd HH:mm')
                .format(DateTime.parse(transaction['occuredAt']))
            : 'غير محدد';

        final type =
            _translateTransactionType(transaction['type'] ?? 'غير محدد');

        String service = 'غير محدد';
        if (transaction['subscription']?['subscriptionService']?['service']
                ?['displayValue'] !=
            null) {
          service = transaction['subscription']['subscriptionService']
              ['service']['displayValue'];
        } else if (transaction['subscription']?['displayValue'] != null) {
          service = transaction['subscription']['displayValue'];
        }

        final amtDynamic = transaction['transactionAmount']?['value'] ?? 0.0;
        final num amtNum = (amtDynamic is num)
            ? amtDynamic
            : double.tryParse(amtDynamic.toString()) ?? 0.0;
        final double amount = amtNum.toDouble();

        final currency = transaction['transactionAmount']?['currency'] ?? 'IQD';

        final balanceDynamic = transaction['remainingBalance']?['value'] ?? 0.0;
        final num balanceNum = (balanceDynamic is num)
            ? balanceDynamic
            : double.tryParse(balanceDynamic.toString()) ?? 0.0;
        final double balance = balanceNum.toDouble();

        final customer = transaction['customer']?['displayValue'] ?? 'غير محدد';
        final customerId =
            transaction['customer']?['id']?.toString() ?? 'غير محدد';
        final zoneId = transaction['zoneId'] ?? 'غير محدد';
        final user = transaction['createdBy'] ?? 'غير محدد';
        final paymentMode = transaction['paymentMode'] ?? 'غير محدد';
        final paymentMethod =
            transaction['paymentMethod']?['displayValue'] ?? 'غير محدد';
        final deviceUsername = transaction['deviceUsername'] ?? 'غير محدد';

        final subscriptionId =
            transaction['subscription']?['id']?.toString() ?? 'غير محدد';

        String subscriptionStart = 'غير محدد';
        String subscriptionEnd = 'غير محدد';
        String subscriptionDuration = 'غير محدد';

        if (transaction['subscription']?['startsAt'] != null &&
            transaction['subscription']?['endsAt'] != null) {
          try {
            final startDate =
                DateTime.parse(transaction['subscription']['startsAt']);
            final endDate =
                DateTime.parse(transaction['subscription']['endsAt']);

            subscriptionStart = DateFormat('yyyy-MM-dd').format(startDate);
            subscriptionEnd = DateFormat('yyyy-MM-dd').format(endDate);

            final durationInDays = endDate.difference(startDate).inDays;
            final durationInMonths = (durationInDays / 30).round();

            if (durationInMonths == 0) {
              subscriptionDuration = '$durationInDays يوم';
            } else if (durationInMonths == 1) {
              subscriptionDuration = 'شهر واحد';
            } else if (durationInMonths == 2) {
              subscriptionDuration = 'شهرين';
            } else if (durationInMonths >= 3 && durationInMonths <= 10) {
              subscriptionDuration = '$durationInMonths أشهر';
            } else {
              subscriptionDuration = '$durationInMonths شهر';
            }
          } catch (e) {
            // في حالة فشل تحليل التاريخ
          }
        }

        final walletType =
            transaction['walletType']?['displayValue'] ?? 'غير محدد';
        final walletOwnerType =
            transaction['walletOwnerType']?['displayValue'] ?? 'غير محدد';
        final salesType =
            transaction['salesType']?['displayValue'] ?? 'غير محدد';
        final changeType =
            transaction['changeType']?['displayValue'] ?? 'غير محدد';
        final discountAmount = transaction['discountAmount']?.toString() ?? '0';
        final discountType = transaction['discountType'] ?? 'غير محدد';

        _addExcelRow(transactionsSheet, row++, [
          id,
          date,
          type,
          service,
          _formatCurrency(amount),
          currency,
          _formatCurrency(balance),
          customer,
          customerId,
          zoneId,
          user,
          paymentMode,
          paymentMethod,
          deviceUsername,
          subscriptionId,
          subscriptionStart,
          subscriptionEnd,
          subscriptionDuration,
          walletType,
          walletOwnerType,
          salesType,
          changeType,
          discountAmount,
          discountType,
        ]);
      }

      // حفظ الملف
      var fileBytes = excel.save();
      if (fileBytes == null) {
        _showError('فشل في إنشاء ملف Excel');
        return;
      }

      // تحديد المسار
      String? outputPath;
      if (Platform.isAndroid) {
        final directory = await getExternalStorageDirectory();
        outputPath =
            '${directory?.path}/الأرباح_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      } else if (Platform.isWindows) {
        final directory = await getDownloadsDirectory();
        outputPath =
            '${directory?.path}\\الأرباح_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      } else {
        final directory = await getApplicationDocumentsDirectory();
        outputPath =
            '${directory.path}/الأرباح_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      }

      // كتابة الملف
      File(outputPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ الملف بنجاح في:\n$outputPath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'نسخ المسار',
              textColor: Colors.white,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: outputPath!));
              },
            ),
          ),
        );
      }
    } catch (e) {
      _showError('حدث خطأ في تصدير البيانات');
    }
  }

  void _addExcelRow(excel_pkg.Sheet sheet, int rowIndex, List<String> values,
      {bool isHeader = false}) {
    for (int i = 0; i < values.length; i++) {
      var cell = sheet.cell(excel_pkg.CellIndex.indexByColumnRow(
          columnIndex: i, rowIndex: rowIndex));
      cell.value = excel_pkg.TextCellValue(values[i]);

      if (isHeader) {
        cell.cellStyle = excel_pkg.CellStyle(
          bold: true,
          fontSize: 12,
          horizontalAlign: excel_pkg.HorizontalAlign.Center,
        );
      }
    }
  }
}
