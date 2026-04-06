/// اسم الصفحة: تفاصيل معاملات المنشئين
/// وصف الصفحة: صفحة تفاصيل معاملات المنشئين المالية
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
import 'dart:convert';
import '../../services/auth_service.dart';
import '../transactions/transactions_page.dart';
import '../auth/auth_error_handler.dart';

/// صفحة عرض تفاصيل معاملات منشأة محددة
class CreatorTransactionsDetailPage extends StatefulWidget {
  final String creatorName;
  final Map<String, double> creatorAmounts;
  final List<Map<String, dynamic>> allTransactions;
  final String authToken;
  final List<String>? customerIds; // إضافة معرفات العملاء

  const CreatorTransactionsDetailPage({
    super.key,
    required this.creatorName,
    required this.creatorAmounts,
    required this.allTransactions,
    required this.authToken,
    this.customerIds,
  });

  @override
  State<CreatorTransactionsDetailPage> createState() =>
      _CreatorTransactionsDetailPageState();
}

class _CreatorTransactionsDetailPageState
    extends State<CreatorTransactionsDetailPage> {
  late List<Map<String, dynamic>> creatorTransactions;
  late List<Map<String, dynamic>> filteredTransactions;
  String searchQuery = '';
  String sortBy = 'date'; // date, amount, type
  bool isAscending = false; // ترتيب تنازلي افتراضياً للتاريخ

  // إحصائيات المعاملات
  double totalAmount = 0.0;
  double positiveAmount = 0.0;
  double negativeAmount = 0.0;
  Map<String, int> transactionTypeCounts = {};
  Map<String, double> transactionTypeAmounts = {};

  // إحصائيات تفصيلية حسب فئات المعاملات
  double purchaseAmount = 0.0;
  int purchaseCount = 0;
  double renewChangeScheduleAmount = 0.0;
  int renewChangeScheduleCount = 0;
  double walletTopupAmount = 0.0;
  int walletTopupCount = 0;
  double otherAmount = 0.0;
  int otherCount = 0;

  // متغيرات لجلب معلومات المنشأة
  Map<String, String> customerOrganizations =
      {}; // تخزين معرف العميل -> اسم المنشأة
  bool isLoadingOrganizations = false;

  // متغيرات لتخزين معلومات المستخدم (Actor)
  Map<String, Map<String, dynamic>> customerActors =
      {}; // تخزين معرف العميل -> معلومات المستخدم
  bool isLoadingActors = false;

  // متغيرات لتخزين معلومات العميل التفصيلية
  Map<String, Map<String, dynamic>> customerDetails =
      {}; // تخزين معرف العميل -> معلومات العميل التفصيلية
  bool isLoadingCustomerDetails = false;

  @override
  void initState() {
    super.initState();
    _initializeData();

    // جلب معلومات المنشآت والمستخدمين تلقائياً إذا كانت المنشأة "بدون منشأة"
    if (widget.creatorName == 'بدون منشأة') {
      _autoFetchAllCustomersInfo();
    }
  }

  void _initializeData() {
    // استخراج المعاملات المتعلقة بهذه المنشأة فقط
    creatorTransactions = widget.allTransactions.where((transaction) {
      String transactionCreator = 'بدون منشأة';
      final createdBy = transaction['createdBy'];
      final transactionUser = transaction['transactionUser'];
      final username = transaction['username'];

      if (createdBy != null && createdBy.toString().trim().isNotEmpty) {
        transactionCreator = createdBy.toString().trim();
      } else if (transactionUser != null &&
          transactionUser.toString().trim().isNotEmpty) {
        transactionCreator = transactionUser.toString().trim();
      } else if (username != null && username.toString().trim().isNotEmpty) {
        transactionCreator = username.toString().trim();
      }

      return transactionCreator == widget.creatorName;
    }).toList();

    filteredTransactions = List.from(creatorTransactions);
    _calculateStatistics();
    _sortTransactions();
  }

  // دالة لجلب معلومات العميل التفصيلية
  Future<void> _fetchCustomerDetails(String customerId) async {
    if (customerId.isEmpty || customerDetails.containsKey(customerId)) {
      return; // إذا كان معرف العميل فارغ أو تم جلب البيانات مسبقاً
    }

    setState(() {
      isLoadingCustomerDetails = true;
    });

    try {
      // استخدام نفس الـ API المستخدم في جلب معلومات المستخدم
      final url =
          'https://admin.ftth.iq/api/audit-logs?pageSize=20&pageNumber=1&sortCriteria.property=CreatedAt&sortCriteria.direction=%20desc&customerId=$customerId';

      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        url,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List?;

        if (items != null && items.isNotEmpty) {
          // البحث عن معلومات العميل في البيانات
          for (var item in items) {
            final customer = item['customer'];
            final zone = item['zone'];

            if (customer != null && !customerDetails.containsKey(customerId)) {
              Map<String, dynamic> customerInfo = {};

              // جلب اسم العميل
              if (customer['displayValue'] != null) {
                customerInfo['displayValue'] =
                    customer['displayValue'].toString();
              }

              // جلب معرف العميل
              if (customer['id'] != null) {
                customerInfo['id'] = customer['id'].toString();
              }

              // جلب معلومات المنطقة إذا كانت متوفرة
              if (zone != null) {
                if (zone['id'] != null) {
                  customerInfo['zoneId'] = zone['id'].toString();
                }
                if (zone['displayValue'] != null) {
                  customerInfo['zoneDisplayValue'] =
                      zone['displayValue'].toString();
                }
              }

              // جلب معلومات إضافية من البيانات
              if (item['eventType'] != null) {
                customerInfo['lastEventType'] = item['eventType'].toString();
              }

              if (item['createdAt'] != null) {
                customerInfo['lastActivity'] = item['createdAt'].toString();
              }

              setState(() {
                customerDetails[customerId] = customerInfo;
              });
              break; // تم العثور على المعلومات، يمكن التوقف
            }
          }
        }

        // إضافة قيم افتراضية إذا لم يتم العثور على المعلومات
        if (!customerDetails.containsKey(customerId)) {
          setState(() {
            customerDetails[customerId] = {
              'id': customerId,
              'displayValue': 'لا توجد معلومات عميل متاحة',
              'error': 'لم يتم العثور على معلومات إضافية'
            };
          });
        }
      } else if (response.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      } else {
        throw Exception('فشل في جلب البيانات: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        customerDetails[customerId] = {
          'id': customerId,
          'error': 'خطأ في جلب البيانات',
          'displayValue': 'خطأ في الجلب'
        };
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل في جلب معلومات العميل'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() {
        isLoadingCustomerDetails = false;
      });
    }
  }

  // دالة لجلب معلومات المنشآت والمستخدمين وتفاصيل العملاء تلقائياً
  Future<void> _autoFetchAllCustomersInfo() async {
    // الحصول على جميع معرفات العملاء الفريدة
    Set<String> customerIds = {};
    for (var transaction in filteredTransactions) {
      final customerId = transaction['customer']?['id']?.toString();
      if (customerId != null && customerId.isNotEmpty) {
        customerIds.add(customerId);
      }
    }

    // جلب المعلومات لكل عميل
    for (String customerId in customerIds) {
      await _fetchCustomerOrganizationAndActor(customerId);
      await _fetchCustomerDetails(
          customerId); // إضافة جلب معلومات العميل التفصيلية
      // تأخير قصير لتجنب إرهاق الخادم
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  // دالة لجلب معلومات المنشأة والمستخدم للعميل المحدد
  Future<void> _fetchCustomerOrganizationAndActor(String customerId) async {
    if (customerId.isEmpty ||
        (customerOrganizations.containsKey(customerId) &&
            customerActors.containsKey(customerId))) {
      return; // إذا كان معرف العميل فارغ أو تم جلب البيانات مسبقاً
    }

    setState(() {
      isLoadingOrganizations = true;
      isLoadingActors = true;
    });

    try {
      final url =
          'https://admin.ftth.iq/api/audit-logs?pageSize=10&pageNumber=1&sortCriteria.property=CreatedAt&sortCriteria.direction=%20desc&customerId=$customerId';

      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        url,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List?;

        if (items != null && items.isNotEmpty) {
          // البحث عن معلومات المنشأة والمستخدم في البيانات
          for (var item in items) {
            final actor = item['actor'];

            // معالجة معلومات المستخدم (Actor)
            if (actor != null && !customerActors.containsKey(customerId)) {
              Map<String, dynamic> actorInfo = {};

              // جلب اسم المستخدم
              if (actor['username'] != null) {
                actorInfo['username'] = actor['username'].toString();
              }

              // جلب عنوان IP
              if (actor['ipAddress'] != null) {
                actorInfo['ipAddress'] = actor['ipAddress'].toString();
              }

              // جلب نوع الحساب
              if (actor['accountType'] != null &&
                  actor['accountType']['displayValue'] != null) {
                actorInfo['accountType'] =
                    actor['accountType']['displayValue'].toString();
              }

              // جلب تاريخ العملية
              if (item['createdAt'] != null) {
                actorInfo['createdAt'] = item['createdAt'].toString();
              }

              // جلب حالة العملية
              if (item['isSuccessful'] != null) {
                actorInfo['isSuccessful'] = item['isSuccessful'];
              }

              // جلب نوع العملية
              if (item['eventType'] != null) {
                actorInfo['eventType'] = item['eventType'].toString();
              }

              setState(() {
                customerActors[customerId] = actorInfo;
              });
            }

            // معالجة معلومات المنشأة (كما كان من قبل)
            if (actor != null &&
                actor['accountType'] != null &&
                !customerOrganizations.containsKey(customerId)) {
              final accountTypeDisplay = actor['accountType']['displayValue'];
              if (accountTypeDisplay != null &&
                  accountTypeDisplay != 'Partner') {
                setState(() {
                  customerOrganizations[customerId] = accountTypeDisplay;
                });
              }
            }

            // إذا تم العثور على كلا المعلومتين، يمكن التوقف
            if (customerOrganizations.containsKey(customerId) &&
                customerActors.containsKey(customerId)) {
              break;
            }
          }
        }

        // إضافة قيم افتراضية إذا لم يتم العثور على المعلومات
        if (!customerOrganizations.containsKey(customerId)) {
          setState(() {
            customerOrganizations[customerId] = 'لا توجد معلومات منشأة متاحة';
          });
        }

        if (!customerActors.containsKey(customerId)) {
          setState(() {
            customerActors[customerId] = {
              'username': 'غير متاح',
              'accountType': 'غير محدد',
              'ipAddress': 'غير متاح',
              'eventType': 'غير محدد',
              'createdAt': null,
              'isSuccessful': null
            };
          });
        }
      } else if (response.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      } else {
        throw Exception('فشل في جلب البيانات: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        customerOrganizations[customerId] =
            'خطأ في جلب البيانات';
        customerActors[customerId] = {
          'username': 'خطأ في الجلب',
          'error': 'حدث خطأ'
        };
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل في جلب معلومات العميل'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() {
        isLoadingOrganizations = false;
        isLoadingActors = false;
      });
    }
  }

  void _calculateStatistics() {
    totalAmount = 0.0;
    positiveAmount = 0.0;
    negativeAmount = 0.0;
    transactionTypeCounts.clear();
    transactionTypeAmounts.clear();

    // إعادة تعيين الإحصائيات التفصيلية
    purchaseAmount = 0.0;
    purchaseCount = 0;
    renewChangeScheduleAmount = 0.0;
    renewChangeScheduleCount = 0;
    walletTopupAmount = 0.0;
    walletTopupCount = 0;
    otherAmount = 0.0;
    otherCount = 0;

    for (final transaction in filteredTransactions) {
      final amtDynamic = transaction['transactionAmount']?['value'] ?? 0.0;
      final num amtNum = (amtDynamic is num)
          ? amtDynamic
          : double.tryParse(amtDynamic.toString()) ?? 0.0;
      final double amount = amtNum.toDouble();
      final String type = transaction['type'] ?? 'UNKNOWN';

      totalAmount += amount;
      if (amount > 0) {
        positiveAmount += amount;
      } else if (amount < 0) {
        negativeAmount += amount;
      }

      // عد أنواع المعاملات
      transactionTypeCounts[type] = (transactionTypeCounts[type] ?? 0) + 1;
      transactionTypeAmounts[type] =
          (transactionTypeAmounts[type] ?? 0.0) + amount;

      // تصنيف المعاملات حسب الفئات
      _categorizeTransaction(type, amount);
    }
  }

  // دالة تصنيف المعاملات حسب الفئات
  void _categorizeTransaction(String type, double amount) {
    // عمليات الشراء
    if (type == 'PLAN_PURCHASE' ||
        type == 'PLAN_SUBSCRIBE' ||
        type == 'PURCHASE_COMMISSION' ||
        type == 'HARDWARE_SELL' ||
        type == 'BAL_CARD_SELL' ||
        type.contains('PURCHASE')) {
      purchaseAmount += amount;
      purchaseCount++;
    }
    // عمليات التجديد والتغيير والمجدول
    else if (type == 'PLAN_RENEW' ||
        type == 'AUTO_RENEW' ||
        type == 'PLAN_EMI_RENEW' ||
        type == 'PLAN_CHANGE' ||
        type == 'PLAN_SCHEDULE' ||
        type == 'SCHEDULE_CHANGE' ||
        type.contains('RENEW') ||
        type.contains('SCHEDULE')) {
      renewChangeScheduleAmount += amount;
      renewChangeScheduleCount++;
    }
    // تعبئة رصيد
    else if (type == 'REFILL_TEAM_MEMBER_BALANCE' ||
        type == 'WALLET_TOPUP' ||
        type == 'WALLET_TRANSFER') {
      walletTopupAmount += amount;
      walletTopupCount++;
    }
    // أخرى
    else {
      otherAmount += amount;
      otherCount++;
    }
  }

  void _sortTransactions() {
    switch (sortBy) {
      case 'date':
        filteredTransactions.sort((a, b) {
          final dateA =
              DateTime.tryParse(a['occuredAt'] ?? '') ?? DateTime.now();
          final dateB =
              DateTime.tryParse(b['occuredAt'] ?? '') ?? DateTime.now();
          return isAscending ? dateA.compareTo(dateB) : dateB.compareTo(dateA);
        });
        break;
      case 'amount':
        filteredTransactions.sort((a, b) {
          final amountA = (a['transactionAmount']?['value'] ?? 0.0).toDouble();
          final amountB = (b['transactionAmount']?['value'] ?? 0.0).toDouble();
          return isAscending
              ? amountA.compareTo(amountB)
              : amountB.compareTo(amountA);
        });
        break;
      case 'type':
        filteredTransactions.sort((a, b) {
          final typeA = _translateTransactionType(a['type'] ?? '');
          final typeB = _translateTransactionType(b['type'] ?? '');
          return isAscending ? typeA.compareTo(typeB) : typeB.compareTo(typeA);
        });
        break;
    }
  }

  void _applySearch() {
    if (searchQuery.isEmpty) {
      filteredTransactions = List.from(creatorTransactions);
    } else {
      filteredTransactions = creatorTransactions.where((transaction) {
        final type =
            _translateTransactionType(transaction['type'] ?? '').toLowerCase();
        final changeType = (transaction['changeType'] != null &&
                transaction['changeType']['displayValue'] != null)
            ? _translateChangeType(transaction['changeType']['displayValue'])
                .toLowerCase()
            : '';
        final customer =
            (transaction['customer']?['displayValue'] ?? '').toLowerCase();
        final customerId =
            (transaction['customer']?['id']?.toString() ?? '').toLowerCase();
        final subscription =
            (transaction['subscription']?['displayValue'] ?? '').toLowerCase();
        final id = (transaction['id']?.toString() ?? '').toLowerCase();
        final amount =
            (transaction['transactionAmount']?['value']?.toString() ?? '')
                .toLowerCase();
        final query = searchQuery.toLowerCase();

        return type.contains(query) ||
            changeType.contains(query) ||
            customer.contains(query) ||
            customerId.contains(query) ||
            subscription.contains(query) ||
            id.contains(query) ||
            amount.contains(query);
      }).toList();
    }
    _calculateStatistics();
    _sortTransactions();
    setState(() {});
  }

  String _formatCurrency(dynamic value) {
    if (value == null) return '0';
    final amount = (value is int) ? value : (value as double).round();
    return amount.toString();
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'غير محدد';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return DateFormat('yyyy/MM/dd HH:mm').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  String _translateTransactionType(String type) {
    switch (type) {
      case 'BAL_CARD_SELL':
        return 'بيع بطاقة رصيد';
      case 'CASHBACK_COMMISSION':
        return 'عمولة استرداد نقدي';
      case 'CASHOUT':
        return 'سحب نقدي';
      case 'HARDWARE_SELL':
        return 'بيع أجهزة';
      case 'MAINTENANCE_COMMISSION':
        return 'عمولة صيانة';
      case 'PLAN_CHANGE':
        return 'تغيير الباقة';
      case 'PLAN_PURCHASE':
        return 'شراء باقة';
      case 'PLAN_RENEW':
        return 'تجديد الباقة';
      case 'PURCHASE_COMMISSION':
        return 'عمولة شراء';
      case 'SCHEDULE_CANCEL':
        return 'إلغاء جدولة';
      case 'SCHEDULE_CHANGE':
        return 'تغيير جدولة';
      case 'TERMINATE':
        return 'إنهاء';
      case 'TRIAL_PERIOD':
        return 'فترة تجريبية';
      case 'WALLET_REFUND':
        return 'استرداد محفظة';
      case 'WALLET_TOPUP':
        return 'شحن محفظة';
      case 'WALLET_TRANSFER':
        return 'تحويل محفظة';
      case 'PLAN_SCHEDULE':
        return 'جدولة باقة';
      case 'PURCH_COMM_REVERSAL':
        return 'عكس عمولة شراء';
      case 'AUTO_RENEW':
        return 'تجديد تلقائي';
      case 'TERMINATE_SUBSCRIPTION':
        return 'إنهاء اشتراك';
      case 'PURCHASE_REVERSAL':
        return 'عكس شراء';
      case 'HIER_COMM_REVERSAL':
        return 'عكس عمولة هرمية';
      case 'HIERACHY_COMMISSION':
        return 'عمولة هرمية';
      case 'WALLET_TRANSFER_COMMISSION':
        return 'عمولة تحويل محفظة';
      case 'COMMISSION_TRANSFER':
        return 'تحويل عمولة';
      case 'RENEW_REVERSAL':
        return 'عكس تجديد';
      case 'MAINT_COMM_REVERSAL':
        return 'عكس عمولة صيانة';
      case 'WALLET_REVERSAL':
        return 'عكس محفظة';
      case 'WALLET_TRANSFER_FEE':
        return 'رسوم تحويل محفظة';
      case 'PLAN_EMI_RENEW':
        return 'تجديد قسط باقة';
      case 'PLAN_SUSPEND':
        return 'تعليق باقة';
      case 'PLAN_REACTIVATE':
        return 'إعادة تفعيل باقة';
      case 'REFILL_TEAM_MEMBER_BALANCE':
        return 'تعبئة رصيد عضو الفريق';
      case 'PLAN_SUBSCRIBE':
        return 'اشتراك جديد';
      case 'COMMISSION':
        return 'عمولة';
      case 'PAYMENT':
        return 'دفع';
      default:
        return type;
    }
  }

  String _translateChangeType(String changeType) {
    switch (changeType) {
      case 'Scheduled':
        return 'مجدول';
      case 'Immediate':
        return 'فوري';
      case 'Instant':
        return 'فوري';
      case 'Manual':
        return 'يدوي';
      case 'Automatic':
        return 'تلقائي';
      default:
        return changeType;
    }
  }

  // دالة لتحديد لون شارة نوع التغيير
  List<Color> _getChangeTypeColors(String changeType) {
    switch (changeType) {
      case 'Scheduled':
        return [Colors.deepOrange[400]!, Colors.orange[400]!];
      case 'Immediate':
        return [Colors.red[400]!, Colors.pink[400]!];
      case 'Instant':
        return [Colors.red[400]!, Colors.pink[400]!];
      case 'Manual':
        return [Colors.blue[400]!, Colors.indigo[400]!];
      case 'Automatic':
        return [Colors.green[400]!, Colors.teal[400]!];
      default:
        return [Colors.grey[400]!, Colors.grey[500]!];
    }
  }

  // دالة لتحديد أيقونة نوع التغيير
  IconData _getChangeTypeIcon(String changeType) {
    switch (changeType) {
      case 'Scheduled':
        return Icons.schedule;
      case 'Immediate':
        return Icons.flash_on;
      case 'Instant':
        return Icons.flash_on;
      case 'Manual':
        return Icons.pan_tool;
      case 'Automatic':
        return Icons.auto_mode;
      default:
        return Icons.info;
    }
  }

  Color _getTransactionColor(Map<String, dynamic> transaction) {
    final amount = transaction['transactionAmount']?['value'] ?? 0.0;
    if (amount > 0) {
      return Colors.green;
    } else if (amount < 0) {
      return Colors.red;
    } else {
      return Colors.blue;
    }
  }

  IconData _getTransactionIcon(String type) {
    switch (type) {
      case 'REFILL_TEAM_MEMBER_BALANCE':
        return Icons.account_balance_wallet;
      case 'PLAN_RENEW':
      case 'AUTO_RENEW':
      case 'PLAN_EMI_RENEW':
        return Icons.refresh;
      case 'PLAN_PURCHASE':
      case 'PLAN_SUBSCRIBE':
        return Icons.add_shopping_cart;
      case 'WALLET_TRANSFER':
        return Icons.swap_horiz;
      case 'PURCHASE_COMMISSION':
      case 'HIERACHY_COMMISSION':
      case 'MAINTENANCE_COMMISSION':
        return Icons.monetization_on;
      case 'HARDWARE_SELL':
      case 'BAL_CARD_SELL':
        return Icons.point_of_sale;
      case 'PLAN_CHANGE':
        return Icons.change_circle;
      case 'PLAN_SCHEDULE':
        return Icons.schedule;
      case 'TERMINATE':
      case 'TERMINATE_SUBSCRIPTION':
        return Icons.cancel;
      default:
        return Icons.receipt;
    }
  }

  Future<void> _openFilterPage() async {
    // العودة إلى صفحة المبالغ حسب المنشأة، ثم فتح صفحة التصفية مع تطبيق فلتر المنشأة المحددة
    Navigator.pop(context); // العودة لصفحة المبالغ حسب المنشأة

    // ثم فتح صفحة التصفية
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionsPage(authToken: widget.authToken),
      ),
    );
  }

  Future<void> _exportToExcel() async {
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
              Text('جاري تصدير تفاصيل المعاملات...'),
            ],
          ),
        ),
      );

      // إنشاء ملف Excel
      var excel = ExcelLib.Excel.createExcel();
      ExcelLib.Sheet sheetObject =
          excel['تفاصيل معاملات ${widget.creatorName}'];

      // إضافة العناوين
      List<String> headers = [
        'معرف المعاملة',
        'نوع المعاملة',
        'نوع التغيير',
        'المبلغ',
        'العملة',
        'الرصيد المتبقي',
        'التاريخ',
        'العميل',
        'معرف العميل',
        'منطقة العميل',
        'اسم منطقة العميل',
        'آخر حدث للعميل',
        'الزون',
        'الاشتراك',
        'طريقة الدفع',
        'نوع الدفع',
        'الرقم التسلسلي'
      ];

      for (int i = 0; i < headers.length; i++) {
        String cellAddress = '${String.fromCharCode(65 + i)}1';
        sheetObject.cell(ExcelLib.CellIndex.indexByString(cellAddress)).value =
            ExcelLib.TextCellValue(headers[i]);
      }

      // تنسيق العناوين
      for (int col = 0; col < headers.length; col++) {
        var cell = sheetObject.cell(
            ExcelLib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
        cell.cellStyle = ExcelLib.CellStyle(
          bold: true,
          backgroundColorHex: ExcelLib.ExcelColor.blue,
          fontColorHex: ExcelLib.ExcelColor.white,
        );
      }

      // إضافة البيانات
      for (int i = 0; i < filteredTransactions.length; i++) {
        var transaction = filteredTransactions[i];
        int row = i + 2;

        List<dynamic> rowData = [
          transaction['id']?.toString() ?? '',
          _translateTransactionType(transaction['type'] ?? ''),
          // إضافة نوع التغيير
          (transaction['changeType'] != null &&
                  transaction['changeType']['displayValue'] != null)
              ? _translateChangeType(transaction['changeType']['displayValue'])
              : '',
          transaction['transactionAmount']?['value']?.toDouble() ?? 0.0,
          transaction['transactionAmount']?['currency'] ?? 'IQD',
          transaction['remainingBalance']?['value']?.toDouble() ?? 0.0,
          _formatDate(transaction['occuredAt']),
          transaction['customer']?['displayValue'] ?? '',
          transaction['customer']?['id']?.toString() ?? '',
          // إضافة معلومات العميل التفصيلية
          customerDetails[transaction['customer']?['id']?.toString()]
                  ?['zoneId'] ??
              '',
          customerDetails[transaction['customer']?['id']?.toString()]
                  ?['zoneDisplayValue'] ??
              '',
          customerDetails[transaction['customer']?['id']?.toString()]
                  ?['lastEventType'] ??
              '',
          transaction['zoneId'] ?? '',
          transaction['subscription']?['displayValue'] ?? '',
          transaction['paymentMode'] ?? '',
          transaction['paymentMethod']?['displayValue'] ?? '',
          transaction['serialNumber'] ?? '',
        ];

        for (int j = 0; j < rowData.length; j++) {
          String cellAddress = String.fromCharCode(65 + j) + row.toString();
          var cellValue = rowData[j];

          if (cellValue is double) {
            sheetObject
                .cell(ExcelLib.CellIndex.indexByString(cellAddress))
                .value = ExcelLib.DoubleCellValue(cellValue);
          } else {
            sheetObject
                .cell(ExcelLib.CellIndex.indexByString(cellAddress))
                .value = ExcelLib.TextCellValue(cellValue.toString());
          }
        }
      }

      // حفظ الملف
      Directory? directory;
      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      String fileName =
          'تفاصيل_معاملات_${widget.creatorName}_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.xlsx';
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
                child: Text(
                    'تم تصدير ${filteredTransactions.length} معاملة بنجاح'),
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
          content: Text('فشل في تصدير البيانات'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _copyAllToClipboard() async {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('تفاصيل معاملات ${widget.creatorName}');
    buffer.writeln('=' * 50);
    buffer.writeln();
    buffer.writeln('الإحصائيات:');
    buffer.writeln('إجمالي المعاملات: ${filteredTransactions.length}');
    buffer.writeln('المجموع الكلي: ${_formatCurrency(totalAmount)} IQD');
    buffer.writeln('المبالغ الموجبة: ${_formatCurrency(positiveAmount)} IQD');
    buffer.writeln('المبالغ السالبة: ${_formatCurrency(negativeAmount)} IQD');
    buffer.writeln();
    buffer.writeln('تفاصيل المعاملات:');
    buffer.writeln('-' * 30);

    for (int i = 0; i < filteredTransactions.length; i++) {
      final transaction = filteredTransactions[i];
      buffer.writeln();
      buffer.writeln(
          '${i + 1}. معرف المعاملة: ${transaction['id'] ?? 'غير محدد'}');
      buffer.writeln(
          '   النوع: ${_translateTransactionType(transaction['type'] ?? '')}');
      buffer.writeln(
          '   المبلغ: ${transaction['transactionAmount']?['value'] ?? 0} ${transaction['transactionAmount']?['currency'] ?? 'IQD'}');
      buffer.writeln('   التاريخ: ${_formatDate(transaction['occuredAt'])}');
      if (transaction['customer']?['displayValue']?.isNotEmpty == true) {
        buffer.writeln('   العميل: ${transaction['customer']['displayValue']}');
      }
      // إضافة معرف العميل إذا كان متوفراً
      if (transaction['customer']?['id'] != null) {
        buffer.writeln('   معرف العميل: ${transaction['customer']['id']}');
      }
      if (transaction['subscription']?['displayValue']?.isNotEmpty == true) {
        buffer.writeln(
            '   الاشتراك: ${transaction['subscription']['displayValue']}');
      }
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم نسخ تفاصيل جميع المعاملات إلى الحافظة'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildStatisticsCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إحصائيات المعاملات',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A237E),
              ),
            ),
            const SizedBox(height: 16),

            // الصف الوحيد - جميع الإحصائيات
            Row(
              children: [
                // المربع الأول - تعبئة الرصيد
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.teal[50]!, Colors.teal[100]!],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.teal[300]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.teal.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تعبئة رصيد',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.teal[700],
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '$walletTopupCount معاملة',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.teal[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatCurrency(walletTopupAmount),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // المربع الثاني - عمليات الشراء
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.orange[50]!, Colors.orange[100]!],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[300]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'عمليات الشراء',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.orange[700],
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '$purchaseCount معاملة',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.orange[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatCurrency(purchaseAmount),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // المربع الثالث - التجديد والتغيير
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.purple[50]!, Colors.purple[100]!],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple[300]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.purple.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تجديد وتغيير',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.purple[700],
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '$renewChangeScheduleCount معاملة',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.purple[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatCurrency(renewChangeScheduleAmount),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // المربع الرابع - المبالغ السالبة
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.red[50]!, Colors.red[100]!],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[300]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'المبالغ الكلي',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.red[700],
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${filteredTransactions.where((t) => (double.tryParse(t['amount']?.toString() ?? '0') ?? 0.0) < 0).length} معاملة',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.red[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatCurrency(negativeAmount),
                          style: TextStyle(
                            fontSize: 17,
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
          ],
        ),
      ),
    );
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('خيارات الترتيب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Radio<String>(
                  value: 'date',
                  groupValue: sortBy,
                  onChanged: (value) {
                    setState(() {
                      sortBy = value!;
                    });
                    _sortTransactions();
                    Navigator.of(context).pop();
                  },
                ),
                title: const Text('ترتيب حسب التاريخ'),
              ),
              ListTile(
                leading: Radio<String>(
                  value: 'amount',
                  groupValue: sortBy,
                  onChanged: (value) {
                    setState(() {
                      sortBy = value!;
                    });
                    _sortTransactions();
                    Navigator.of(context).pop();
                  },
                ),
                title: const Text('ترتيب حسب المبلغ'),
              ),
              ListTile(
                leading: Radio<String>(
                  value: 'type',
                  groupValue: sortBy,
                  onChanged: (value) {
                    setState(() {
                      sortBy = value!;
                    });
                    _sortTransactions();
                    Navigator.of(context).pop();
                  },
                ),
                title: const Text('ترتيب حسب نوع المعاملة'),
              ),
              const Divider(),
              SwitchListTile(
                title: Text(isAscending ? 'تصاعدي' : 'تنازلي'),
                subtitle: Text(isAscending
                    ? 'من الأقل إلى الأكبر'
                    : 'من الأكبر إلى الأقل'),
                value: isAscending,
                onChanged: (value) {
                  setState(() {
                    isAscending = value;
                  });
                  _sortTransactions();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSortAndSearchControls() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
      child: TextField(
        decoration: InputDecoration(
          hintText: 'البحث في المعاملات...',
          prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey[100],
        ),
        onChanged: (value) {
          setState(() {
            searchQuery = value;
          });
          _applySearch();
        },
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    final transactionAmount = transaction['transactionAmount'];
    final remainingBalance = transaction['remainingBalance'];
    final amount = transactionAmount?['value'] ?? 0.0;
    final currency = transactionAmount?['currency'] ?? 'IQD';
    final balance = remainingBalance?['value'] ?? 0.0;
    final type = transaction['type'] ?? '';
    final occuredAt = transaction['occuredAt'];
    final customer = transaction['customer'];
    final subscription = transaction['subscription'];
    final zoneId = transaction['zoneId'] ?? '';
    final paymentMode = transaction['paymentMode'] ?? '';
    final serialNumber = transaction['serialNumber'] ?? '';

    final color = _getTransactionColor(transaction);
    final icon = _getTransactionIcon(type);

    // تحديد ما إذا كانت المعاملة مجدولة
    final isScheduled = transaction['changeType'] != null &&
        transaction['changeType']['displayValue'] == 'Scheduled';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: isScheduled ? 8 : 4, // ارتفاع أكبر للمجدول
      shadowColor: isScheduled
          ? Colors.red[300]!.withValues(alpha: 0.5) // ظلال حمراء للمجدول
          : null, // ظلال عادية للباقي
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isScheduled
              ? Colors.red[400]! // حدود حمراء للمجدول
              : Colors.black, // حدود سوداء للباقي
          width: isScheduled ? 2.0 : 1.5, // عرض أكبر للحدود المجدولة
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showTransactionDetails(transaction),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isScheduled
                  ? [Colors.red[50]!, Colors.red[100]!] // خلفية حمراء للمجدول
                  : [Colors.white, Colors.grey[50]!], // خلفية عادية للباقي
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // الصف العلوي
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: color.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // صف نوع المعاملة مع نوع التغيير
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _translateTransactionType(type),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isScheduled
                                        ? Colors.red[800] // أحمر داكن للمجدول
                                        : Colors.grey[800], // رمادي داكن للباقي
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // إضافة نوع التغيير كشارة بارزة للمجدول فقط
                              if (transaction['changeType'] != null &&
                                  transaction['changeType']['displayValue'] ==
                                      'Scheduled') ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: _getChangeTypeColors(
                                          transaction['changeType']
                                              ['displayValue']),
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _getChangeTypeColors(
                                                transaction['changeType']
                                                    ['displayValue'])[0]
                                            .withValues(alpha: 0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _getChangeTypeIcon(
                                            transaction['changeType']
                                                ['displayValue']),
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _translateChangeType(
                                            transaction['changeType']
                                                ['displayValue']),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(occuredAt),
                            style: TextStyle(
                              fontSize: 13,
                              color: isScheduled
                                  ? Colors.red[600] // أحمر متوسط للمجدول
                                  : Colors.grey[600], // رمادي للباقي
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '${amount >= 0 ? '+' : ''}${_formatCurrency(amount)} $currency',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // معلومات إضافية
                // عرض نوع التغيير كشارة منفصلة وبارزة للمجدول فقط
                if (transaction['changeType'] != null &&
                    transaction['changeType']['displayValue'] ==
                        'Scheduled') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isScheduled
                            ? [
                                Colors.red[100]!,
                                Colors.red[200]!
                              ] // خلفية حمراء أقوى للمجدول
                            : _getChangeTypeColors(
                                    transaction['changeType']['displayValue'])
                                .map((c) => c.withValues(alpha: 0.1))
                                .toList(),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isScheduled
                            ? Colors.red[400]! // حدود حمراء للمجدول
                            : _getChangeTypeColors(transaction['changeType']
                                    ['displayValue'])[0]
                                .withValues(alpha: 0.3),
                        width: isScheduled ? 2 : 1, // حدود أسمك للمجدول
                      ),
                      boxShadow: isScheduled
                          ? [
                              BoxShadow(
                                color: Colors.red[300]!.withValues(alpha: 0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : [], // ظلال للمجدول فقط
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isScheduled) ...[
                          // إضافة أيقونة تحذيرية للمجدول
                          Icon(
                            Icons.warning,
                            color: Colors.red[700],
                            size: 22,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Icon(
                          _getChangeTypeIcon(
                              transaction['changeType']['displayValue']),
                          color: isScheduled
                              ? Colors.red[700] // أحمر داكن للمجدول
                              : _getChangeTypeColors(
                                  transaction['changeType']['displayValue'])[0],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'نوع التغيير: ${_translateChangeType(transaction['changeType']['displayValue'])}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isScheduled
                                ? Colors.red[800] // أحمر أغمق للمجدول
                                : _getChangeTypeColors(transaction['changeType']
                                    ['displayValue'])[0],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (customer != null &&
                    customer['displayValue']?.isNotEmpty == true) ...[
                  _buildInfoRow(
                      Icons.person, 'العميل', customer['displayValue']),
                ],
                // إضافة معرف العميل إذا كان متوفراً
                if (customer != null && customer['id'] != null) ...[
                  _buildClickableCustomerIdRow(customer['id'].toString()),
                ],
                // عرض معلومات المستخدم (Actor) إذا كانت متوفرة ومن "بدون منشأة"
                if (widget.creatorName == 'بدون منشأة' &&
                    customer != null &&
                    customer['id'] != null &&
                    customerActors.containsKey(customer['id'].toString())) ...[
                  _buildActorInfoRow(customer['id'].toString()),
                ],
                // عرض معلومات العميل التفصيلية تلقائياً (اسم العميل)
                if (customer != null &&
                    customer['id'] != null &&
                    customerDetails.containsKey(customer['id'].toString())) ...[
                  _buildCustomerInfoRow(customer['id'].toString()),
                ],
                if (subscription != null &&
                    subscription['displayValue']?.isNotEmpty == true) ...[
                  _buildInfoRow(Icons.subscriptions, 'الاشتراك',
                      subscription['displayValue']),
                ],
                if (zoneId.isNotEmpty) ...[
                  _buildInfoRow(Icons.location_on, 'الزون', zoneId),
                ],
                if (paymentMode.isNotEmpty) ...[
                  _buildInfoRow(Icons.payment, 'طريقة الدفع', paymentMode),
                ],
                if (serialNumber.isNotEmpty) ...[
                  _buildInfoRow(Icons.confirmation_number, 'الرقم التسلسلي',
                      serialNumber),
                ],

                const SizedBox(height: 8),

                // الرصيد المتبقي
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet,
                          color: Colors.blue[600], size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'الرصيد المتبقي: ${_formatCurrency(balance)} $currency',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // دالة لعرض معرف العميل القابل للنقر
  Widget _buildClickableCustomerIdRow(String customerId) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.badge, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            'معرف العميل: ',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          GestureDetector(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: customerId));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم نسخ معرف العميل: $customerId'),
                    duration: const Duration(seconds: 2),
                    backgroundColor: Colors.blue,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue[300]!, width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    customerId,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[800],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.copy,
                    size: 12,
                    color: Colors.blue[600],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // دالة لعرض معلومات المستخدم (Actor) - تصميم بسيط ومختصر
  Widget _buildActorInfoRow(String customerId) {
    final actorInfo = customerActors[customerId];
    if (actorInfo == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber[200]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الصف الأول: المستخدم ونوع المحفظة
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // أيقونة صغيرة
              Icon(Icons.person, size: 14, color: Colors.amber[600]),
              const SizedBox(width: 6),

              // اسم المستخدم مع نص توضيحي
              if (actorInfo['username'] != null) ...[
                Text(
                  'المستخدم: ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  actorInfo['username'].toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber[800],
                  ),
                ),
              ],

              // فاصل
              if (actorInfo['username'] != null &&
                  actorInfo['accountType'] != null &&
                  actorInfo['accountType'] != 'غير محدد') ...[
                Text(
                  ' • ',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],

              // نوع الحساب مع نص توضيحي
              if (actorInfo['accountType'] != null &&
                  actorInfo['accountType'] != 'غير محدد') ...[
                Text(
                  'نوع المحفظة: ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  actorInfo['accountType'].toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber[700],
                  ),
                ),
              ],
            ],
          ),

          // الصف الثاني: تاريخ العملية وحالة العملية
          if (actorInfo['createdAt'] != null ||
              actorInfo['isSuccessful'] != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // أيقونة التاريخ
                Icon(Icons.access_time, size: 12, color: Colors.amber[600]),
                const SizedBox(width: 4),

                // تاريخ العملية
                if (actorInfo['createdAt'] != null) ...[
                  Text(
                    'تاريخ العملية: ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    _formatDate(actorInfo['createdAt'].toString()),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber[700],
                    ),
                  ),
                ],

                // فاصل
                if (actorInfo['createdAt'] != null &&
                    actorInfo['isSuccessful'] != null) ...[
                  Text(
                    ' • ',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                    ),
                  ),
                ],

                // حالة العملية
                if (actorInfo['isSuccessful'] != null) ...[
                  Icon(
                    actorInfo['isSuccessful'] == true
                        ? Icons.check_circle
                        : Icons.error,
                    size: 12,
                    color: actorInfo['isSuccessful'] == true
                        ? Colors.green[600]
                        : Colors.red[600],
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'حالة العملية: ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    actorInfo['isSuccessful'] == true ? 'نجحت' : 'فشلت',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: actorInfo['isSuccessful'] == true
                          ? Colors.green[700]
                          : Colors.red[700],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  // دالة لعرض معلومات العميل التفصيلية البسيطة - تلقائياً
  Widget _buildCustomerInfoRow(String customerId) {
    final customerInfo = customerDetails[customerId];
    if (customerInfo == null) return const SizedBox.shrink();

    // عرض اسم العميل فقط إذا كان متوفراً
    if (customerInfo['displayValue'] != null &&
        customerInfo['displayValue'] != 'لا توجد معلومات عميل متاحة' &&
        customerInfo['displayValue'] != 'خطأ في الجلب') {
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.green[200]!, width: 1),
        ),
        child: Row(
          mainAxisSize:
              MainAxisSize.min, // إضافة هذا لجعل البطاقة على حجم المحتوى
          children: [
            // أيقونة صغيرة
            Icon(Icons.account_circle, size: 14, color: Colors.green[600]),
            const SizedBox(width: 6),

            // اسم العميل مع نص توضيحي
            Text(
              'اسم العميل: ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
            // استخدام Flexible بدلاً من Expanded لأننا نريد حجم المحتوى
            Flexible(
              child: Text(
                customerInfo['displayValue'].toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[800],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  void _showTransactionDetails(Map<String, dynamic> transaction) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                _getTransactionIcon(transaction['type'] ?? ''),
                color: _getTransactionColor(transaction),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'تفاصيل المعاملة',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
              ),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('معرف المعاملة',
                      transaction['id']?.toString() ?? 'غير محدد'),
                  _buildDetailRow('النوع',
                      _translateTransactionType(transaction['type'] ?? '')),
                  // إضافة نوع التغيير إذا كان متوفراً
                  if (transaction['changeType'] != null &&
                      transaction['changeType']['displayValue'] != null)
                    _buildDetailRow(
                        'نوع التغيير',
                        _translateChangeType(
                            transaction['changeType']['displayValue'])),
                  _buildDetailRow('المبلغ',
                      '${transaction['transactionAmount']?['value'] ?? 0} ${transaction['transactionAmount']?['currency'] ?? 'IQD'}'),
                  _buildDetailRow('الرصيد المتبقي',
                      '${transaction['remainingBalance']?['value'] ?? 0} ${transaction['remainingBalance']?['currency'] ?? 'IQD'}'),
                  _buildDetailRow(
                      'التاريخ', _formatDate(transaction['occuredAt'])),
                  if (transaction['customer']?['displayValue']?.isNotEmpty ==
                      true)
                    _buildDetailRow(
                        'العميل', transaction['customer']['displayValue']),
                  // إضافة معرف العميل إذا كان متوفراً
                  if (transaction['customer']?['id'] != null)
                    _buildDetailRow('معرف العميل',
                        transaction['customer']['id'].toString()),
                  // إضافة معلومات العميل التفصيلية إذا كانت متوفرة
                  if (transaction['customer']?['id'] != null &&
                      customerDetails.containsKey(
                          transaction['customer']['id'].toString())) ...[
                    _buildDetailRow('تفاصيل إضافية للعميل', '---'),
                    if (customerDetails[transaction['customer']['id']
                            .toString()]!['zoneId'] !=
                        null)
                      _buildDetailRow(
                          'منطقة العميل',
                          customerDetails[transaction['customer']['id']
                                  .toString()]!['zoneId']
                              .toString()),
                    if (customerDetails[transaction['customer']['id']
                            .toString()]!['zoneDisplayValue'] !=
                        null)
                      _buildDetailRow(
                          'اسم منطقة العميل',
                          customerDetails[transaction['customer']['id']
                                  .toString()]!['zoneDisplayValue']
                              .toString()),
                    if (customerDetails[transaction['customer']['id']
                            .toString()]!['lastEventType'] !=
                        null)
                      _buildDetailRow(
                          'آخر نوع حدث للعميل',
                          customerDetails[transaction['customer']['id']
                                  .toString()]!['lastEventType']
                              .toString()),
                    if (customerDetails[transaction['customer']['id']
                            .toString()]!['lastActivity'] !=
                        null)
                      _buildDetailRow(
                          'آخر نشاط للعميل',
                          _formatDate(customerDetails[transaction['customer']
                                      ['id']
                                  .toString()]!['lastActivity']
                              .toString())),
                  ],
                  // إضافة معلومات المنشأة إذا كانت متوفرة ومن "بدون منشأة"
                  if (widget.creatorName == 'بدون منشأة' &&
                      transaction['customer']?['id'] != null &&
                      customerOrganizations.containsKey(
                          transaction['customer']['id'].toString()))
                    _buildDetailRow(
                        'المنشأة الأصلية',
                        customerOrganizations[
                            transaction['customer']['id'].toString()]!),
                  // إضافة معلومات المستخدم إذا كانت متوفرة ومن "بدون منشأة"
                  if (widget.creatorName == 'بدون منشأة' &&
                      transaction['customer']?['id'] != null &&
                      customerActors.containsKey(
                          transaction['customer']['id'].toString())) ...[
                    _buildDetailRow('--- معلومات المستخدم المنفذ ---', ''),
                    _buildDetailRow(
                        'المستخدم المنفذ',
                        customerActors[transaction['customer']['id']
                                    .toString()]!['username']
                                ?.toString() ??
                            'غير محدد'),
                    if (customerActors[transaction['customer']['id']
                            .toString()]!['accountType'] !=
                        null)
                      _buildDetailRow(
                          'نوع حساب المنفذ',
                          customerActors[transaction['customer']['id']
                                  .toString()]!['accountType']
                              .toString()),
                    if (customerActors[transaction['customer']['id']
                            .toString()]!['ipAddress'] !=
                        null)
                      _buildDetailRow(
                          'IP المنفذ',
                          customerActors[transaction['customer']['id']
                                  .toString()]!['ipAddress']
                              .toString()),
                    if (customerActors[transaction['customer']['id']
                            .toString()]!['eventType'] !=
                        null)
                      _buildDetailRow(
                          'نوع العملية الأصلية',
                          customerActors[transaction['customer']['id']
                                  .toString()]!['eventType']
                              .toString()),
                    if (customerActors[transaction['customer']['id']
                            .toString()]!['createdAt'] !=
                        null)
                      _buildDetailRow(
                          'تاريخ العملية الأصلية',
                          _formatDate(customerActors[transaction['customer']
                                      ['id']
                                  .toString()]!['createdAt']
                              .toString())),
                    if (customerActors[transaction['customer']['id']
                            .toString()]!['isSuccessful'] !=
                        null)
                      _buildDetailRow(
                          'حالة العملية الأصلية',
                          customerActors[transaction['customer']['id']
                                      .toString()]!['isSuccessful'] ==
                                  true
                              ? 'نجحت ✅'
                              : 'فشلت ❌'),
                  ],
                  if (transaction['zoneId']?.isNotEmpty == true)
                    _buildDetailRow('الزون', transaction['zoneId']),
                  if (transaction['subscription'] != null) ...[
                    _buildDetailRow(
                        'معرف المشترك',
                        transaction['subscription']['id']?.toString() ??
                            'غير محدد'),
                    _buildDetailRow(
                        'الاشتراك',
                        transaction['subscription']['displayValue'] ??
                            'غير محدد'),
                  ],
                  _buildDetailRow(
                      'طريقة الدفع', transaction['paymentMode'] ?? 'غير محدد'),
                  _buildDetailRow(
                      'نوع الدفع',
                      transaction['paymentMethod']?['displayValue'] ??
                          'غير محدد'),
                  _buildDetailRow('الرقم التسلسلي',
                      transaction['serialNumber'] ?? 'غير محدد'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final detailsText = _buildTransactionDetailsText(transaction);
                await Clipboard.setData(ClipboardData(text: detailsText));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم نسخ تفاصيل المعاملة'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('نسخ'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
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
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          const Text(': '),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2C3E50),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildTransactionDetailsText(Map<String, dynamic> transaction) {
    final details = StringBuffer();
    details.writeln('تفاصيل المعاملة:');
    details.writeln('================');
    details.writeln('معرف المعاملة: ${transaction['id'] ?? 'غير محدد'}');
    details.writeln(
        'النوع: ${_translateTransactionType(transaction['type'] ?? '')}');
    // إضافة نوع التغيير إذا كان متوفراً
    if (transaction['changeType'] != null &&
        transaction['changeType']['displayValue'] != null) {
      details.writeln(
          'نوع التغيير: ${_translateChangeType(transaction['changeType']['displayValue'])}');
    }
    details.writeln(
        'المبلغ: ${transaction['transactionAmount']?['value'] ?? 0} ${transaction['transactionAmount']?['currency'] ?? 'IQD'}');
    details.writeln(
        'الرصيد المتبقي: ${transaction['remainingBalance']?['value'] ?? 0} ${transaction['remainingBalance']?['currency'] ?? 'IQD'}');
    details.writeln('التاريخ: ${_formatDate(transaction['occuredAt'])}');

    if (transaction['customer']?['displayValue']?.isNotEmpty == true) {
      details.writeln('العميل: ${transaction['customer']['displayValue']}');
    }

    // إضافة معرف العميل إذا كان متوفراً
    if (transaction['customer']?['id'] != null) {
      details.writeln('معرف العميل: ${transaction['customer']['id']}');

      // إضافة معلومات العميل التفصيلية إذا كانت متوفرة
      if (customerDetails
          .containsKey(transaction['customer']['id'].toString())) {
        final customerInfo =
            customerDetails[transaction['customer']['id'].toString()]!;
        details.writeln('--- تفاصيل إضافية للعميل ---');

        if (customerInfo['zoneId'] != null) {
          details.writeln('منطقة العميل: ${customerInfo['zoneId']}');
        }

        if (customerInfo['zoneDisplayValue'] != null) {
          details
              .writeln('اسم منطقة العميل: ${customerInfo['zoneDisplayValue']}');
        }

        if (customerInfo['lastEventType'] != null) {
          details
              .writeln('آخر نوع حدث للعميل: ${customerInfo['lastEventType']}');
        }

        if (customerInfo['lastActivity'] != null) {
          details.writeln(
              'آخر نشاط للعميل: ${_formatDate(customerInfo['lastActivity'].toString())}');
        }
      }
    }

    // إضافة معلومات المنشأة إذا كانت متوفرة
    if (widget.creatorName == 'بدون منشأة' &&
        transaction['customer']?['id'] != null &&
        customerOrganizations
            .containsKey(transaction['customer']['id'].toString())) {
      details.writeln(
          'المنشأة الأصلية: ${customerOrganizations[transaction['customer']['id'].toString()]}');
    }

    // إضافة معلومات المستخدم إذا كانت متوفرة
    if (widget.creatorName == 'بدون منشأة' &&
        transaction['customer']?['id'] != null &&
        customerActors.containsKey(transaction['customer']['id'].toString())) {
      final actorInfo =
          customerActors[transaction['customer']['id'].toString()]!;
      details.writeln('--- معلومات المستخدم المنفذ ---');
      if (actorInfo['username'] != null) {
        details.writeln('المستخدم المنفذ: ${actorInfo['username']}');
      }
      if (actorInfo['accountType'] != null) {
        details.writeln('نوع حساب المنفذ: ${actorInfo['accountType']}');
      }
      if (actorInfo['ipAddress'] != null) {
        details.writeln('IP المنفذ: ${actorInfo['ipAddress']}');
      }
      if (actorInfo['eventType'] != null) {
        details.writeln('نوع العملية الأصلية: ${actorInfo['eventType']}');
      }
      if (actorInfo['createdAt'] != null) {
        details.writeln(
            'تاريخ العملية الأصلية: ${_formatDate(actorInfo['createdAt'].toString())}');
      }
      if (actorInfo['isSuccessful'] != null) {
        details.writeln(
            'حالة العملية الأصلية: ${actorInfo['isSuccessful'] == true ? 'نجحت ✅' : 'فشلت ❌'}');
      }
    }

    if (transaction['zoneId']?.isNotEmpty == true) {
      details.writeln('الزون: ${transaction['zoneId']}');
    }

    if (transaction['subscription'] != null) {
      details.writeln(
          'الاشتراك: ${transaction['subscription']['displayValue'] ?? 'غير محدد'}');
    }

    details.writeln('طريقة الدفع: ${transaction['paymentMode'] ?? 'غير محدد'}');

    return details.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تفاصيل معاملات',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              widget.creatorName,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort, color: Colors.white),
            onPressed: _showSortDialog,
            tooltip: 'خيارات الترتيب',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onPressed: _openFilterPage,
            tooltip: 'فتح صفحة التصفية',
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
            onPressed: _copyAllToClipboard,
            tooltip: 'نسخ جميع المعاملات',
          ),
          IconButton(
            icon: const Icon(Icons.file_download, color: Colors.white),
            onPressed: _exportToExcel,
            tooltip: 'تصدير إلى Excel',
          ),
        ],
      ),
      body: Column(
        children: [
          // بطاقة الإحصائيات
          _buildStatisticsCard(),

          // أدوات التحكم في البحث والترتيب
          _buildSortAndSearchControls(),

          const SizedBox(height: 16),

          // قائمة المعاملات
          Expanded(
            child: filteredTransactions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          searchQuery.isNotEmpty
                              ? 'لا توجد نتائج للبحث'
                              : 'لا توجد معاملات لعرضها',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredTransactions.length,
                    itemBuilder: (context, index) {
                      return _buildTransactionCard(filteredTransactions[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
