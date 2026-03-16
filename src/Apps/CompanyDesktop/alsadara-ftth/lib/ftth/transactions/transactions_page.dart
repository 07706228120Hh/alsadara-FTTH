/// اسم الصفحة: التحويلات
/// وصف الصفحة: صفحة إدارة المعاملات المالية
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:excel/excel.dart' as ExcelLib;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../../services/auth_service.dart';
import '../auth/auth_error_handler.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';
import 'creator_amounts_page.dart';
import '../reports/profits_page.dart';

class TransactionsPage extends StatefulWidget {
  final String authToken;

  const TransactionsPage({
    super.key,
    required this.authToken,
  });

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  bool isLoading = true;
  List<Map<String, dynamic>> transactions = [];
  List<Map<String, dynamic>> filteredTransactions = []; // للبحث المحلي
  String searchQuery = ''; // نص البحث
  String selectedSearchField = 'all'; // حقل البحث المختار
  final TextEditingController _searchController = TextEditingController();

  // خيارات حقول البحث
  final List<Map<String, String>> searchFieldOptions = [
    {'value': 'all', 'label': 'الكل'},
    {'value': 'customer', 'label': 'العميل'},
    {'value': 'device', 'label': 'الجهاز'},
    {'value': 'creator', 'label': 'المنشئ'},
    {'value': 'service', 'label': 'الخدمة'},
    {'value': 'zone', 'label': 'الزون'},
    {'value': 'amount', 'label': 'المبلغ'},
    {'value': 'id', 'label': 'معرف المعاملة'},
  ];

  int totalCount = 0;
  int currentPage = 1;
  int pageSize = 750; // تعيين 750 معاملة كافتراضي لكل صفحة
  final ScrollController _scrollController = ScrollController();
  bool isLoadingMore = false;
  // مجموع المبالغ الموجبة والسالبة للمعاملات المعروضة
  double positiveSum = 0.0;
  double negativeSum = 0.0;
  // مجموع لكل الصفحات (لكل النتائج المفلترة على الخادم)
  double positiveSumAll = 0.0;
  double negativeSumAll = 0.0;
  // مجموع المبالغ السالبة للمعاملات بدون اسم منشئ
  double negativeSumWithoutCreator = 0.0;
  double negativeSumWithoutCreatorAll = 0.0;
  // عدد العمليات المجدولة
  int scheduledCount = 0;
  int scheduledCountAll = 0;
  // مجموع مبالغ العمليات المجدولة
  double scheduledSum = 0.0;
  double scheduledSumAll = 0.0;
  // عدد العمليات لكل نوع
  int positiveCount = 0;
  int positiveCountAll = 0;
  int negativeCount = 0;
  int negativeCountAll = 0;
  int withoutCreatorCount = 0;
  int withoutCreatorCountAll = 0;
  bool isLoadingAllTotals = false;

  // متغيرات لحساب المبلغ الإجمالي حسب اسم المنشأة
  Map<String, double> creatorAmounts = {};
  bool isCalculatingCreatorAmounts = false;

  // متغيرات التصفية
  List<String> selectedWalletTypes = [];
  List<String> selectedWalletOwnerTypes = [];
  List<String> selectedSalesTypes = [];
  List<String> selectedChangeTypes = [];
  List<String> selectedPaymentMethods = [];
  DateTime? fromDate;
  DateTime? toDate;
  List<String> selectedZones = []; // تم التغيير من String? إلى List<String>
  List<String> selectedTransactionTypes = [];

  // متغيرات لتحميل قائمة المناطق من الـ API
  List<String> availableZones = [];
  bool isLoadingZones = false;
  List<String> selectedServiceNames = [];
  String? transactionUser;

  // متغير لتتبع نوع الفلتر السريع المستخدم
  String? quickFilterType;
  bool showTransactionsWithoutUser = false; // لإظهار العمليات بدون اسم مستخدم
  // قائمة أسماء المستخدمين المستخرجة من الـ API لاستخدامها في الاقتراحات
  List<String> availableUsernames = [];
  bool isLoadingUsernames = false;

  // فلاتر إضافية للعرض بعد التصفية الأساسية
  bool showPositiveOnly = false; // عرض العمليات الموجبة فقط
  bool showNegativeOnly = false; // عرض العمليات السالبة فقط
  bool showWithoutCreatorOnly = false; // عرض العمليات بدون منشئ فقط
  bool showScheduledOnly = false; // عرض العمليات المجدولة فقط

  // متغير لإخفاء/إظهار بطاقات الخدمات والإحصائيات
  bool showServicesBar = true; // إظهار شريط الخدمات افتراضياً

  // خيارات عدد المعاملات المعروضة
  final List<Map<String, dynamic>> pageSizeOptions = [
    {'value': 500, 'label': '500 معاملة '},
    {'value': 100, 'label': '100 معاملة'},
    {'value': 250, 'label': '250 معاملة'},
    {'value': 750, 'label': '750 معاملة'},
    {'value': 1000, 'label': '1000 معاملة'},
    {'value': 2000, 'label': '2000 معاملة'},
    {'value': 5000, 'label': '5000 معاملة'},
  ];

  // قوائم الخيارات
  final List<Map<String, String>> walletTypes = [
    {'value': 'Main', 'label': 'المحفظة الرئيسية'},
    {'value': 'Secondary', 'label': 'المحفظة الثانوية'},
  ];

  // أنواع مالك المحفظة (قيمة الخادم قد تختلف - افترضنا هذه القيم)
  final List<Map<String, String>> walletOwnerTypes = [
    {'value': 'partner', 'label': 'شريك'},
    {'value': 'customer', 'label': 'عميل'},
  ];

  final List<Map<String, String>> salesTypes = [
    {'value': '0', 'label': 'دفعة واحدة'},
    {'value': '1', 'label': 'دفعات شهرية'},
  ];

  final List<Map<String, String>> changeTypes = [
    {'value': '0', 'label': 'مجدول'},
    {'value': '1', 'label': 'فوري'},
  ];

  final List<Map<String, String>> paymentMethods = [
    {'value': '0', 'label': 'نقدي'},
    {'value': '1', 'label': 'بطاقة ائتمان'},
    {'value': '2', 'label': 'تحويل بنكي'},
    {'value': '3', 'label': 'محفظة إلكترونية'},
    {'value': '4', 'label': 'فاست بي'},
  ];

  final List<Map<String, String>> transactionTypes = [
    {'value': 'BAL_CARD_SELL', 'label': 'بيع بطاقة رصيد'},
    {'value': 'CASHBACK_COMMISSION', 'label': 'عمولة استرداد نقدي'},
    {'value': 'CASHOUT', 'label': 'سحب نقدي'},
    {'value': 'HARDWARE_SELL', 'label': 'بيع أجهزة'},
    {'value': 'MAINTENANCE_COMMISSION', 'label': 'عمولة صيانة'},
    {'value': 'PLAN_CHANGE', 'label': 'تغيير الباقة'},
    {'value': 'PLAN_PURCHASE', 'label': 'شراء باقة'},
    {'value': 'PLAN_RENEW', 'label': 'تجديد الباقة'},
    {'value': 'PURCHASE_COMMISSION', 'label': 'عمولة شراء'},
    {'value': 'SCHEDULE_CANCEL', 'label': 'إلغاء جدولة'},
    {'value': 'SCHEDULE_CHANGE', 'label': 'تغيير جدولة'},
    {'value': 'TERMINATE', 'label': 'إنهاء'},
    {'value': 'TRIAL_PERIOD', 'label': 'فترة تجريبية'},
    {'value': 'WALLET_REFUND', 'label': 'استرداد محفظة'},
    {'value': 'WALLET_TOPUP', 'label': 'شحن محفظة'},
    {'value': 'WALLET_TRANSFER', 'label': 'تحويل محفظة'},
    {'value': 'PLAN_SCHEDULE', 'label': 'جدولة باقة'},
    {'value': 'PURCH_COMM_REVERSAL', 'label': 'عكس عمولة شراء'},
    {'value': 'AUTO_RENEW', 'label': 'تجديد تلقائي'},
    {'value': 'TERMINATE_SUBSCRIPTION', 'label': 'إنهاء اشتراك'},
    {'value': 'PURCHASE_REVERSAL', 'label': 'عكس شراء'},
    {'value': 'HIER_COMM_REVERSAL', 'label': 'عكس عمولة هرمية'},
    {'value': 'HIERACHY_COMMISSION', 'label': 'عمولة هرمية'},
    {'value': 'WALLET_TRANSFER_COMMISSION', 'label': 'عمولة تحويل محفظة'},
    {'value': 'COMMISSION_TRANSFER', 'label': 'تحويل عمولة'},
    {'value': 'RENEW_REVERSAL', 'label': 'عكس تجديد'},
    {'value': 'MAINT_COMM_REVERSAL', 'label': 'عكس عمولة صيانة'},
    {'value': 'WALLET_REVERSAL', 'label': 'عكس محفظة'},
    {'value': 'WALLET_TRANSFER_FEE', 'label': 'رسوم تحويل محفظة'},
    {'value': 'PLAN_EMI_RENEW', 'label': 'تجديد قسط باقة'},
    {'value': 'PLAN_SUSPEND', 'label': 'تعليق باقة'},
    {'value': 'PLAN_REACTIVATE', 'label': 'إعادة تفعيل باقة'},
    {'value': 'REFILL_TEAM_MEMBER_BALANCE', 'label': 'تعبئة رصيد عضو فريق'},
    {
      'value': 'PurchaseSubscriptionFromTrial',
      'label': 'شراء اشتراك من التجربة'
    },
  ];

  final List<Map<String, String>> serviceNames = [
    {'value': 'FIBER 35', 'label': 'FIBER 35'},
    {'value': 'FIBER 50', 'label': 'FIBER 50'},
    {'value': 'FIBER 75', 'label': 'FIBER 75'},
    {'value': 'FIBER 150', 'label': 'FIBER 150'},
    {'value': 'IPTV', 'label': 'IPTV'},
    {'value': 'Parental Control', 'label': 'الرقابة الأبوية'},
    {'value': 'VOIP', 'label': 'VOIP'},
    {'value': 'VOD', 'label': 'VOD'},
    {'value': 'Learning Platform', 'label': 'منصة التعلم'},
    {'value': 'Hardware Plan ONT', 'label': 'باقة جهاز ONT'},
    {'value': 'Hardware Plan Router', 'label': 'باقة راوتر'},
    {'value': 'Grace Plan', 'label': 'باقة السماح'},
  ];

  @override
  void initState() {
    super.initState();
    // تعيين التاريخ الافتراضي لعرض عمليات الأمس (من 9 مساءً قبل الأمس إلى 9 مساءً الأمس)
    // التوقيت هنا بالتوقيت المحلي العراقي، وسيتم تحويله إلى UTC عند الإرسال للسيرفر
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    // تعيين نوع الفلتر السريع الافتراضي
    quickFilterType = 'yesterday';

    // من الساعة 9 مساءً لليوم السابق للأمس (بالتوقيت المحلي العراقي)
    fromDate =
        DateTime(yesterday.year, yesterday.month, yesterday.day - 1, 21, 0, 0);
    // إلى الساعة 9 مساءً للأمس (بالتوقيت المحلي العراقي)
    toDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 21, 0, 0);

    // تعيين مالك المحفظة الافتراضي كشريك
    selectedWalletOwnerTypes = ['partner'];

    // ⚡ تأجيل تحميل البيانات حتى بعد انتهاء انيميشن الانتقال
    // يمنع setState() من التعارض مع transition animation ويُحسّن الأداء على الهاتف
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTransactions();
      // تحميل أسماء المستخدمين للاقتراحات في مربع البحث
      _loadUsernames();
      // تحميل قائمة المناطق
      _loadZones();
    });
  }

  // دالة لجلب قائمة المناطق من الـ API (مثل صفحة الاشتراكات)
  Future<void> _loadZones() async {
    if (!mounted) return;
    if (isLoadingZones) return; // منع التكرار

    setState(() {
      isLoadingZones = true;
    });

    try {
      debugPrint('[transactions_page] _loadZones: بدء تحميل المناطق...');

      // استخدام نفس الطريقة المستخدمة في صفحة الاشتراكات
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/locations/zones',
      );

      if (!mounted) return;

      debugPrint(
          '[transactions_page] _loadZones: استجابة API = ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> rawZones = data['items'] ?? [];

        debugPrint(
            '[transactions_page] _loadZones: تم جلب ${rawZones.length} منطقة');

        final List<String> fetchedZones = [];

        for (final zone in rawZones) {
          if (zone is Map<String, dynamic>) {
            String? zoneName;
            // استخراج الاسم من self أو مباشرة
            if (zone['self'] != null && zone['self'] is Map<String, dynamic>) {
              final self = zone['self'] as Map<String, dynamic>;
              zoneName =
                  self['displayValue']?.toString() ?? self['id']?.toString();
            } else {
              zoneName = zone['displayValue']?.toString() ??
                  zone['name']?.toString() ??
                  zone['id']?.toString();
            }

            if (zoneName != null && zoneName.isNotEmpty) {
              fetchedZones.add(zoneName);
            }
          }
        }

        if (fetchedZones.isNotEmpty) {
          // ترتيب أبجدي رقمي
          fetchedZones.sort((a, b) => _alphaNumericCompare(a, b));

          setState(() {
            availableZones = fetchedZones;
          });
          debugPrint(
              '[transactions_page] _loadZones: تم حفظ ${availableZones.length} منطقة');
        }
      } else if (response.statusCode == 401) {
        debugPrint('[transactions_page] _loadZones: خطأ 401 - غير مصرح');
        _handle401Error();
      } else {
        debugPrint('[transactions_page] _loadZones: خطأ ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[transactions_page] _loadZones error=$e');
    } finally {
      if (mounted) {
        setState(() {
          isLoadingZones = false;
        });
      }
    }
  }

  // مقارنة أبجدية-رقمية للترتيب الصحيح
  int _alphaNumericCompare(String a, String b) {
    final la = a.toLowerCase();
    final lb = b.toLowerCase();
    final reg = RegExp(r'^(.*?)(\d+)(.*)');
    final ma = reg.firstMatch(la);
    final mb = reg.firstMatch(lb);

    if (ma != null && mb != null) {
      final pa = ma.group(1) ?? '';
      final pb = mb.group(1) ?? '';
      final prefixCompare = pa.compareTo(pb);
      if (prefixCompare != 0) return prefixCompare;
      final na = int.tryParse(ma.group(2) ?? '') ?? 0;
      final nb = int.tryParse(mb.group(2) ?? '') ?? 0;
      if (na != nb) return na.compareTo(nb);
      return la.compareTo(lb);
    }
    return la.compareTo(lb);
  }

  // نحاول استدعاء عدد من المسارات المعقولة حتى نجد بيانات المستخدمين
  Future<void> _loadUsernames() async {
    if (!mounted) return;
    setState(() {
      isLoadingUsernames = true;
    });
    final String url = 'https://admin.ftth.iq/api/users?pageSize=1000';
    try {
      final response =
          await AuthService.instance.authenticatedRequest('GET', url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List items = [];
        if (data is Map && data['items'] is List) {
          items = List.from(data['items']);
        }
        final names = <String>[];
        for (final it in items) {
          if (it is Map && it['username'] != null) {
            names.add(it['username'].toString());
          }
        }

        if (names.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            availableUsernames = names.toSet().toList();
          });
        } else {
          // إذا لم نجد أي أسماء من الـ API، نحاول تحميل ملف fallback من الأصول
          await _loadUsernamesFromAsset();
        }
      } else if (response.statusCode == 401) {
        _handle401Error();
      } else if (response.statusCode == 403) {
        // محظور - استخدم الملف الاحتياطي
        await _loadUsernamesFromAsset();
      } else {
        // عرض رسالة للمستخدم في الواجهة إذا لم نتمكن من تحميل الأسماء
        if (mounted) {
          _showError('فشل في تحميل أسماء المستخدمين: ${response.statusCode}');
        }
      }
    } catch (e) {
      // طباعة الخطأ لمساعدة التصحيح
      // ignore: avoid_print
      debugPrint('[transactions_page] _loadUsernames error=$e');
      if (mounted) {
        _showError('خطأ عند جلب أسماء المستخدمين');
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoadingUsernames = false;
        });
      }
    }
  }

  Future<void> _loadUsernamesFromAsset() async {
    try {
      final content = await rootBundle.loadString('assets/users_fallback.json');
      final data = jsonDecode(content);
      List items = [];
      if (data is Map && data['items'] is List) {
        items = List.from(data['items']);
      }
      final names = <String>[];
      for (final it in items) {
        if (it is Map && it['username'] != null) {
          names.add(it['username'].toString());
        }
      }
      if (names.isNotEmpty && mounted) {
        setState(() {
          availableUsernames = names.toSet().toList();
        });
      }
    } catch (e) {
      // ignore errors from asset loading
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // دالة البحث المحلي في المعاملات
  void _filterTransactions(String query) {
    setState(() {
      searchQuery = query.toLowerCase();
      if (searchQuery.isEmpty) {
        filteredTransactions = List.from(transactions);
      } else {
        filteredTransactions = transactions.where((transaction) {
          // البحث في اسم العميل
          final customerName = (transaction['customer']?['displayValue'] ?? '')
              .toString()
              .toLowerCase();
          // البحث في اسم الجهاز
          final deviceUsername =
              (transaction['deviceUsername'] ?? '').toString().toLowerCase();
          // البحث في اسم المنشئ
          final createdBy =
              (transaction['createdBy'] ?? '').toString().toLowerCase();
          // البحث في نوع المعاملة
          final type = (transaction['type'] ?? '').toString().toLowerCase();
          // البحث في اسم الخدمة
          final service = (transaction['subscription']?['subscriptionService']
                      ?['service']?['displayValue'] ??
                  '')
              .toString()
              .toLowerCase();
          // البحث في المبلغ
          final amount =
              (transaction['transactionAmount']?['value'] ?? '').toString();
          // البحث في الزون
          final zone = (transaction['zoneId'] ?? '').toString().toLowerCase();
          // البحث في معرف المعاملة
          final id = (transaction['id'] ?? '').toString();

          // البحث حسب الحقل المختار
          switch (selectedSearchField) {
            case 'customer':
              return customerName.contains(searchQuery);
            case 'device':
              return deviceUsername.contains(searchQuery);
            case 'creator':
              return createdBy.contains(searchQuery);
            case 'service':
              return service.contains(searchQuery);
            case 'zone':
              return zone.contains(searchQuery);
            case 'amount':
              return amount.contains(searchQuery);
            case 'id':
              return id.contains(searchQuery);
            case 'all':
            default:
              return customerName.contains(searchQuery) ||
                  deviceUsername.contains(searchQuery) ||
                  createdBy.contains(searchQuery) ||
                  type.contains(searchQuery) ||
                  service.contains(searchQuery) ||
                  amount.contains(searchQuery) ||
                  zone.contains(searchQuery) ||
                  id.contains(searchQuery);
          }
        }).toList();
      }
    });
  }

  // دالة لجلب العدد الإجمالي للمعاملات
  Future<void> _fetchTotalCount() async {
    try {
      // نجرب أولاً جلب صفحة كبيرة لتقدير العدد الإجمالي
      String countUrl = _buildCountUrl();

      debugPrint('[transactions_page] GET COUNT: $countUrl');

      final response =
          await AuthService.instance.authenticatedRequest('GET', countUrl);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final serverTotal =
            data['totalCount'] ?? data['total'] ?? data['count'];
        final items = data['items'] ?? [];

        if (serverTotal != null) {
          if (!mounted) return;
          setState(() {
            totalCount = serverTotal;
          });
          debugPrint('[transactions_page] Total count from server: $totalCount');
        } else if (items.length > 0) {
          // إذا لم يكن هناك عدد إجمالي، نحاول تقدير العدد بناءً على النتائج
          final estimatedTotal = _estimateTotalCount(items.length);
          if (!mounted) return;
          setState(() {
            totalCount = estimatedTotal;
          });
          debugPrint('[transactions_page] Estimated total count: $totalCount');
        }
      }
    } catch (e) {
      debugPrint('[transactions_page] Error fetching total count');
      // في حالة فشل جلب العدد، سنعتمد على البيانات المستلمة
    }
  }

  // دالة لتقدير العدد الإجمالي
  int _estimateTotalCount(int receivedCount) {
    // إذا استلمنا عدد أقل من حجم الصفحة المطلوب، فهذا هو العدد الإجمالي
    if (receivedCount < pageSize) {
      return receivedCount;
    }
    // إذا استلمنا العدد الكامل، نفترض وجود المزيد ونضرب في عدد تقديري من الصفحات
    return receivedCount * 3; // تقدير محافظ
  }

  // بناء رابط للحصول على العدد الإجمالي
  String _buildCountUrl() {
    List<String> queryParams = [];

    // نجلب صفحة كبيرة لتقدير العدد الإجمالي بشكل أفضل
    queryParams.add('pageSize=10000'); // عدد كبير لجلب معظم النتائج
    queryParams.add('pageNumber=1');
    queryParams.add('sortCriteria.property=occuredAt');
    queryParams.add('sortCriteria.direction=desc');

    // إضافة جميع معاملات التصفية الحالية
    queryParams.addAll(_buildFilterParams());

    String baseUrl = 'https://admin.ftth.iq/api/transactions';
    return '$baseUrl?${queryParams.join('&')}';
  }

  // دالة مساعدة لبناء معاملات التصفية
  // ملاحظة مهمة: جميع التواريخ في التطبيق تُحفظ بالتوقيت المحلي العراقي (GMT+3)
  // ويتم تحويلها تلقائياً إلى UTC عند إرسالها للسيرفر
  List<String> _buildFilterParams() {
    List<String> params = [];

    // أنواع المحافظ
    if (selectedWalletTypes.isNotEmpty) {
      for (String walletType in selectedWalletTypes) {
        params.add('walletType=$walletType');
      }
    }

    // مالك المحفظة (partner أو client)
    if (selectedWalletOwnerTypes.isNotEmpty) {
      for (String owner in selectedWalletOwnerTypes) {
        params.add('walletOwnerType=$owner');
      }
    }

    // أنواع المبيعات
    if (selectedSalesTypes.isNotEmpty) {
      for (String salesType in selectedSalesTypes) {
        params.add('salesTypes=$salesType');
      }
    }

    // أنواع التغيير
    if (selectedChangeTypes.isNotEmpty) {
      for (String changeType in selectedChangeTypes) {
        params.add('changeTypes=$changeType');
      }
    }

    // طرق الدفع
    if (selectedPaymentMethods.isNotEmpty) {
      for (String paymentMethod in selectedPaymentMethods) {
        params.add('paymentMethods=$paymentMethod');
      }
    }

    // التواريخ - تحويل من التوقيت المحلي العراقي إلى UTC للسيرفر
    if (fromDate != null) {
      // تحويل التاريخ من التوقيت المحلي العراقي (GMT+3) إلى UTC
      // إذا كان المستخدم اختار 9:00 صباحاً بتوقيت العراق، سيصبح 6:00 صباحاً UTC
      final utcFromDate = fromDate!.toUtc();
      String fromDateStr =
          '${DateFormat('yyyy-MM-ddTHH:mm:ss.SSS').format(utcFromDate)}Z';

      // إرسال التاريخ لعدة حقول لضمان جلب جميع البيانات
      params.add('createdAt.from=$fromDateStr');
      params.add('occuredAt.from=$fromDateStr');
      params.add('transactionDate.from=$fromDateStr');

      // أضف planStartedAt فقط إذا كنا نصفي حسب أنواع باقات/خدمات
      final planRelated = selectedTransactionTypes.any((t) =>
          t.startsWith('PLAN_') ||
          t == 'PLAN_SUBSCRIBE' ||
          t == 'PLAN_EMI_RENEW');
      if (planRelated || selectedServiceNames.isNotEmpty) {
        params.add('planStartedAt.from=$fromDateStr');
      }
    }

    if (toDate != null) {
      // تحويل التاريخ من التوقيت المحلي العراقي (GMT+3) إلى UTC
      // إذا كان المستخدم اختار 9:00 مساءً بتوقيت العراق، سيصبح 6:00 مساءً UTC
      final utcToDate = toDate!.toUtc();
      String toDateStr =
          '${DateFormat('yyyy-MM-ddTHH:mm:ss.SSS').format(utcToDate)}Z';

      // إرسال التاريخ لعدة حقول لضمان جلب جميع البيانات
      params.add('createdAt.to=$toDateStr');
      params.add('occuredAt.to=$toDateStr');
      params.add('transactionDate.to=$toDateStr');

      final planRelated = selectedTransactionTypes.any((t) =>
          t.startsWith('PLAN_') ||
          t == 'PLAN_SUBSCRIBE' ||
          t == 'PLAN_EMI_RENEW');
      if (planRelated || selectedServiceNames.isNotEmpty) {
        params.add('planStartedAt.to=$toDateStr');
      }
    }

    // المنطقة - دعم اختيار متعدد
    if (selectedZones.isNotEmpty) {
      for (String zone in selectedZones) {
        params.add('zones=$zone');
      }
    }

    // أنواع المعاملات
    if (selectedTransactionTypes.isNotEmpty) {
      for (String transactionType in selectedTransactionTypes) {
        params.add('transactionTypes=$transactionType');
      }
    } else {
      // إذا لم يحدد المستخدم نوع معاملات، أرسل جميع أنواع المعاملات
      for (final t in transactionTypes) {
        final val = t['value'];
        if (val != null && val.isNotEmpty) params.add('transactionTypes=$val');
      }
    }

    // أسماء الخدمات
    if (selectedServiceNames.isNotEmpty) {
      for (String serviceName in selectedServiceNames) {
        String encodedServiceName = Uri.encodeComponent(serviceName);
        params.add('subscriptionServiceNames=$encodedServiceName');
      }
    }

    // المستخدم — نرسل عدة مفتاحّات شائعة لزيادة فرص المطابقة على الخادم
    if (transactionUser != null && transactionUser!.isNotEmpty) {
      params.add('transactionUser=${Uri.encodeComponent(transactionUser!)}');
      params.add('createdBy=${Uri.encodeComponent(transactionUser!)}');
      params.add('username=${Uri.encodeComponent(transactionUser!)}');
    }

    return params;
  }

  Future<void> _loadTransactions({bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() {
        currentPage = 1;
        transactions.clear();
        isLoading = true;
      });
    }

    try {
      // أولاً نجلب العدد الإجمالي للنتائج
      await _fetchTotalCount();

      // بناء الرابط مع معاملات التصفية
      String url = _buildFilteredUrl();

      // طباعة للرابط المرسَل للمساعدة في التصحيح
      // ignore: avoid_print
      debugPrint('[transactions_page] GET $url');

      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        url,
      );

      // طباعة سريعة لحالة الاستجابة وجسمها لمساعدة التتبع
      // ignore: avoid_print
      debugPrint(
          '[transactions_page] status=${response.statusCode} body=${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Map<String, dynamic>> allTransactions =
            List<Map<String, dynamic>>.from(data['items'] ?? []);

        // تطبيق الفلترة المحلية للعمليات بدون اسم مستخدم
        if (showTransactionsWithoutUser) {
          allTransactions = allTransactions.where((transaction) {
            final createdBy = transaction['createdBy'];
            final transactionUser = transaction['transactionUser'];
            final username = transaction['username'];

            // اعتبر العملية بدون اسم مستخدم إذا كانت كل الحقول فارغة أو null
            return (createdBy == null || createdBy.toString().trim().isEmpty) &&
                (transactionUser == null ||
                    transactionUser.toString().trim().isEmpty) &&
                (username == null || username.toString().trim().isEmpty);
          }).toList();
        }

        // تطبيق الفلاتر الإضافية بعد التصفية
        allTransactions = _applyAdditionalFilters(allTransactions);

        if (!mounted) return;
        setState(() {
          // الحصول على العدد الإجمالي الحقيقي من استجابة الخادم
          final serverTotalCount = data['totalCount'] ?? data['total'];
          if (serverTotalCount != null) {
            totalCount = serverTotalCount;
          }

          transactions = allTransactions;
          filteredTransactions =
              List.from(transactions); // تحديث القائمة المفلترة
          searchQuery = ''; // إعادة تعيين البحث
          _searchController.clear();

          // حساب مجموع المبالغ الموجبة والسالبة للمعروض حاليا
          positiveSum = 0.0;
          negativeSum = 0.0;
          negativeSumWithoutCreator = 0.0;
          scheduledCount = 0;
          scheduledSum = 0.0;
          positiveCount = 0;
          negativeCount = 0;
          withoutCreatorCount = 0;
          for (final t in transactions) {
            final amtDynamic = t['transactionAmount']?['value'] ?? 0.0;
            final num amtNum = (amtDynamic is num)
                ? amtDynamic
                : double.tryParse(amtDynamic.toString()) ?? 0.0;
            final double val = amtNum.toDouble();

            // فحص إذا كانت المعاملة بدون اسم منشئ
            final createdBy = t['createdBy'];
            final transactionUser = t['transactionUser'];
            final username = t['username'];
            final hasNoCreator =
                (createdBy == null || createdBy.toString().trim().isEmpty) &&
                    (transactionUser == null ||
                        transactionUser.toString().trim().isEmpty) &&
                    (username == null || username.toString().trim().isEmpty);

            // فحص إذا كانت المعاملة مجدولة
            final isScheduled = t['changeType'] != null &&
                t['changeType']['displayValue'] == 'Scheduled';
            if (isScheduled) {
              scheduledCount++;
              scheduledSum += val;
            }

            if (val > 0) {
              positiveSum += val;
              positiveCount++;
            } else if (val < 0) {
              negativeSum += val; // negativeSum will be negative
              negativeCount++;

              // إذا كانت المعاملة بدون اسم منشئ وسالبة
              if (hasNoCreator) {
                negativeSumWithoutCreator += val;
                withoutCreatorCount++;
              }
            }
          }

          isLoading = false;
          isLoadingMore = false;
        });
        // بعد تحديث البيانات الأساسية، ابدأ في حساب مجموع كل النتائج على الخادم
        // بشكل غير متزامن حتى لا نوقف واجهة المستخدم
        _fetchAllPagesSums();
      } else if (response.statusCode == 401) {
        _handle401Error();
      } else {
        _showError('فشل في تحميل التحويلات: ${response.statusCode}');
      }
    } catch (e) {
      if (e.toString().contains('انتهت جلسة المستخدم')) {
        _handle401Error();
        return;
      }
      _showError('حدث خطأ في تحميل التحويلات');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          isLoadingMore = false;
        });
      }
    }
  }

  // تطبيق الفلاتر الإضافية على النتائج
  List<Map<String, dynamic>> _applyAdditionalFilters(
      List<Map<String, dynamic>> transactions) {
    // إذا لم تكن هناك فلاتر إضافية، إرجاع كل شيء
    if (!showPositiveOnly &&
        !showNegativeOnly &&
        !showWithoutCreatorOnly &&
        !showScheduledOnly) {
      return transactions;
    }

    return transactions.where((transaction) {
      final amtDynamic = transaction['transactionAmount']?['value'] ?? 0.0;
      final num amtNum = (amtDynamic is num)
          ? amtDynamic
          : double.tryParse(amtDynamic.toString()) ?? 0.0;
      final double amount = amtNum.toDouble();

      // فحص إذا كانت المعاملة بدون اسم منشئ
      final createdBy = transaction['createdBy'];
      final transactionUser = transaction['transactionUser'];
      final username = transaction['username'];
      final hasNoCreator =
          (createdBy == null || createdBy.toString().trim().isEmpty) &&
              (transactionUser == null ||
                  transactionUser.toString().trim().isEmpty) &&
              (username == null || username.toString().trim().isEmpty);

      // فحص إذا كانت المعاملة مجدولة
      final isScheduled = transaction['changeType'] != null &&
          transaction['changeType']['displayValue'] == 'Scheduled';

      // تطبيق الفلاتر حسب الخيارات المحددة
      if (showPositiveOnly) {
        return amount > 0;
      }

      if (showNegativeOnly) {
        return amount < 0;
      }

      if (showWithoutCreatorOnly) {
        return hasNoCreator;
      }

      if (showScheduledOnly) {
        return isScheduled;
      }

      return true;
    }).toList();
  }

  String _buildFilteredUrl() {
    List<String> queryParams = [];

    // معاملات أساسية
    queryParams.add('pageSize=$pageSize');
    queryParams.add('pageNumber=$currentPage');
    queryParams.add('sortCriteria.property=occuredAt');
    queryParams.add('sortCriteria.direction=desc');

    // إضافة معاملات التصفية
    queryParams.addAll(_buildFilterParams());

    String baseUrl = 'https://admin.ftth.iq/api/transactions';
    return '$baseUrl?${queryParams.join('&')}';
  }

  void _handle401Error() {
    AuthErrorHandler.handle401Error(context);
  }

  // دالة لتجميع بيانات الفلتر الحالية
  Map<String, dynamic> _getCurrentFilterData() {
    Map<String, dynamic> filterData = {};

    if (fromDate != null) {
      filterData['fromDate'] = fromDate!.toIso8601String();
    }

    if (toDate != null) {
      filterData['toDate'] = toDate!.toIso8601String();
    }

    if (selectedWalletTypes.isNotEmpty) {
      filterData['selectedWalletTypes'] = selectedWalletTypes;
    }

    if (selectedWalletOwnerTypes.isNotEmpty) {
      filterData['selectedWalletOwnerTypes'] = selectedWalletOwnerTypes;
    }

    if (selectedSalesTypes.isNotEmpty) {
      filterData['selectedSalesTypes'] = selectedSalesTypes;
    }

    if (selectedChangeTypes.isNotEmpty) {
      filterData['selectedChangeTypes'] = selectedChangeTypes;
    }

    if (selectedPaymentMethods.isNotEmpty) {
      filterData['selectedPaymentMethods'] = selectedPaymentMethods;
    }

    if (selectedZones.isNotEmpty) {
      filterData['selectedZones'] = selectedZones;
    }

    if (selectedTransactionTypes.isNotEmpty) {
      filterData['selectedTransactionTypes'] = selectedTransactionTypes;
    }

    if (selectedServiceNames.isNotEmpty) {
      filterData['selectedServiceNames'] = selectedServiceNames;
    }

    if (transactionUser != null) {
      filterData['transactionUser'] = transactionUser;
    }

    if (showTransactionsWithoutUser) {
      filterData['showTransactionsWithoutUser'] = showTransactionsWithoutUser;
    }

    if (showPositiveOnly) {
      filterData['showPositiveOnly'] = showPositiveOnly;
    }

    if (showNegativeOnly) {
      filterData['showNegativeOnly'] = showNegativeOnly;
    }

    if (showWithoutCreatorOnly) {
      filterData['showWithoutCreatorOnly'] = showWithoutCreatorOnly;
    }

    if (showScheduledOnly) {
      filterData['showScheduledOnly'] = showScheduledOnly;
    }

    return filterData;
  }

  // دالة للانتقال إلى صفحة الأرباح
  Future<void> _navigateToProfitsPage() async {
    final filterData = _getCurrentFilterData();

    // عرض رسالة تحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'جاري جلب المعاملات المفلترة...',
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      // جلب كل المعاملات المفلترة ثم تصفية السالبة فقط
      List<Map<String, dynamic>> negativeTransactions =
          await _fetchAllFilteredNegativeTransactions();

      // إغلاق رسالة التحميل
      if (mounted) {
        Navigator.of(context).pop();
      }

      debugPrint('====== _navigateToProfitsPage ======');
      debugPrint(
          'إجمالي المعاملات السالبة المفلترة: ${negativeTransactions.length}');
      if (negativeTransactions.isNotEmpty) {
        debugPrint('أول معاملة سالبة: ${negativeTransactions.first['type']}');
        debugPrint(
            'قيمة أول معاملة: ${negativeTransactions.first['transactionAmount']?['value']}');
      }
      debugPrint('===================================');

      // الانتقال لصفحة الأرباح مع المعاملات السالبة المفلترة
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfitsPage(
              authToken: widget.authToken,
              filterData: filterData,
              transactions:
                  negativeTransactions, // تمرير المعاملات السالبة المفلترة
            ),
          ),
        );
      }
    } catch (e) {
      // إغلاق رسالة التحميل
      if (mounted) {
        Navigator.of(context).pop();
      }
      _showError('فشل في جلب البيانات');
    }
  }

  // جلب كل المعاملات المفلترة (كل الصفحات) ثم تصفية السالبة فقط
  Future<List<Map<String, dynamic>>>
      _fetchAllFilteredNegativeTransactions() async {
    List<Map<String, dynamic>> allNegativeTransactions = [];
    int pageTemp = 1;
    bool hasMore = true;
    const int pageSizeTemp = 1000;

    debugPrint('====== بدء جلب المعاملات المفلترة ======');
    debugPrint('الفلاتر النشطة:');
    debugPrint('  showPositiveOnly: $showPositiveOnly');
    debugPrint('  showNegativeOnly: $showNegativeOnly');
    debugPrint('  showWithoutCreatorOnly: $showWithoutCreatorOnly');
    debugPrint('  showScheduledOnly: $showScheduledOnly');
    debugPrint('  showTransactionsWithoutUser: $showTransactionsWithoutUser');

    while (hasMore) {
      try {
        // بناء URL مع الفلاتر الحالية
        String url = _buildFilteredUrlForPage(pageTemp, pageSizeTemp);

        final response = await AuthService.instance.authenticatedRequest(
          'GET',
          url,
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          List<Map<String, dynamic>> pageTransactions =
              List<Map<String, dynamic>>.from(data['items'] ?? []);
          final int totalCount = data['totalCount'] ?? 0;

          debugPrint('الصفحة $pageTemp: ${pageTransactions.length} معاملة');

          if (pageTransactions.isEmpty) {
            hasMore = false;
          } else {
            // تطبيق نفس الفلاتر المحلية
            if (showTransactionsWithoutUser) {
              pageTransactions = pageTransactions.where((transaction) {
                final createdBy = transaction['createdBy'];
                final transactionUser = transaction['transactionUser'];
                final username = transaction['username'];
                return (createdBy == null ||
                        createdBy.toString().trim().isEmpty) &&
                    (transactionUser == null ||
                        transactionUser.toString().trim().isEmpty) &&
                    (username == null || username.toString().trim().isEmpty);
              }).toList();
            }

            // تطبيق الفلاتر الإضافية (نفس طريقة _calculateAllTotals)
            pageTransactions = _applyAdditionalFilters(pageTransactions);

            // عد المعاملات السالبة فقط وإضافتها
            int negativeCount = 0;
            for (var transaction in pageTransactions) {
              final amtDynamic =
                  transaction['transactionAmount']?['value'] ?? 0.0;
              final num amtNum = (amtDynamic is num)
                  ? amtDynamic
                  : double.tryParse(amtDynamic.toString()) ?? 0.0;
              final double val = amtNum.toDouble();

              // فقط المعاملات السالبة (نفس طريقة negativeSumAll)
              if (val < 0) {
                allNegativeTransactions.add(transaction);
                negativeCount++;
              }
            }

            debugPrint('  → معاملات بعد الفلاتر: ${pageTransactions.length}');
            debugPrint('  → معاملات سالبة: $negativeCount');
            debugPrint(
                '  → إجمالي المعاملات السالبة حتى الآن: ${allNegativeTransactions.length}');

            // التحقق من وجود المزيد
            if (pageTemp * pageSizeTemp >= totalCount) {
              hasMore = false;
            } else {
              pageTemp++;
            }
          }
        } else if (response.statusCode == 401) {
          throw Exception('انتهت صلاحية الجلسة');
        } else {
          throw Exception('فشل في جلب البيانات: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('خطأ في جلب الصفحة $pageTemp');
        throw Exception('خطأ في الاتصال');
      }
    }

    debugPrint('====== انتهى الجلب ======');
    debugPrint('إجمالي الصفحات: $pageTemp');
    debugPrint('إجمالي المعاملات السالبة: ${allNegativeTransactions.length}');
    debugPrint('========================');

    return allNegativeTransactions;
  }

  // دالة مساعدة لبناء URL لصفحة معينة
  String _buildFilteredUrlForPage(int page, int size) {
    List<String> queryParams = [];

    // معاملات الصفحة والترتيب
    queryParams.add('pageSize=$size');
    queryParams.add('pageNumber=$page');
    queryParams.add('sortCriteria.property=occuredAt');
    queryParams.add('sortCriteria.direction=desc');

    // إضافة جميع الفلاتر الحالية (نفس طريقة _buildFilteredUrl)
    queryParams.addAll(_buildFilterParams());

    String baseUrl = 'https://admin.ftth.iq/api/transactions';
    return '$baseUrl?${queryParams.join('&')}';
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

  // دالة إظهار نافذة التصفية
  void _showFilterDialog() {
    // إذا لم تكن أسماء المستخدمين محمّلة بعد، ابدأ التحميل الآن
    if (availableUsernames.isEmpty && !isLoadingUsernames) {
      _loadUsernames();
    }

    // إذا لم تكن المناطق محمّلة بعد، ابدأ التحميل الآن
    if (availableZones.isEmpty && !isLoadingZones) {
      _loadZones();
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.filter_list,
                    color: const Color(0xFF1A237E),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'تصفية المعاملات',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                ],
              ),
              content: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // رسالة توضيحية
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.blue[700],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'استخدم خيارات التصفية أدناه لتخصيص نتائج البحث حسب احتياجاتك',
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // اسم المستخدم في الأعلى (مع اقتراحات من الـ API)
                      _buildFilterSection(
                        'اسم المستخدم',
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isLoadingUsernames) ...[
                              Row(
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('جارٍ تحميل الاقتراحات...')
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              decoration:
                                  _getInputDecoration('اختر اسم المستخدم'),
                              initialValue: (transactionUser != null &&
                                      availableUsernames
                                          .contains(transactionUser))
                                  ? transactionUser
                                  : null,
                              items: availableUsernames
                                  .map((u) => DropdownMenuItem<String>(
                                      value: u, child: Text(u)))
                                  .toList(),
                              onChanged: (value) {
                                setDialogState(() {
                                  transactionUser = value;
                                });
                              },
                              hint: Text(isLoadingUsernames
                                  ? 'جارٍ تحميل...'
                                  : (availableUsernames.isEmpty
                                      ? 'لا توجد أسماء'
                                      : 'اختر اسم المستخدم')),
                              validator: (v) => null,
                            ),
                            const SizedBox(height: 8),
                            // زر لمسح الاختيار أو إدخال يدوي
                            Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () {
                                    setDialogState(() {
                                      transactionUser = null;
                                    });
                                  },
                                  icon: const Icon(Icons.clear),
                                  label: const Text('مسح'),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () {
                                    final controller = TextEditingController(
                                        text: transactionUser ?? '');
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('أدخل اسم المستخدم'),
                                        content: TextFormField(
                                          controller: controller,
                                          decoration: _getInputDecoration(
                                              'أدخل اسم المستخدم'),
                                          autofocus: true,
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(),
                                            child: const Text('إلغاء'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () {
                                              setState(() {
                                                transactionUser = controller
                                                        .text
                                                        .trim()
                                                        .isEmpty
                                                    ? null
                                                    : controller.text.trim();
                                              });
                                              Navigator.of(ctx).pop();
                                            },
                                            child: const Text('حفظ'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.edit),
                                  label: const Text('ادخال يدوي'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // خيار لإظهار العمليات بدون اسم مستخدم
                            CheckboxListTile(
                              title: const Text(
                                'إظهار العمليات بدون اسم مستخدم',
                                style: TextStyle(fontSize: 14),
                              ),
                              subtitle: const Text(
                                'عرض العمليات التي لم يتم تسجيل منفذها',
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              value: showTransactionsWithoutUser,
                              onChanged: (bool? value) {
                                setDialogState(() {
                                  showTransactionsWithoutUser = value ?? false;
                                  // إذا تم تفعيل هذا الخيار، امسح اسم المستخدم المحدد
                                  if (showTransactionsWithoutUser) {
                                    transactionUser = null;
                                  }
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                      // تصفية التاريخ - أزرار سريعة محسنة مع quickFilterType
                      _buildFilterSection(
                        'الفترة الزمنية',
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // عرض التاريخ الحالي إذا كان محدداً
                            if (fromDate != null || toDate != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blue[50]!,
                                      Colors.blue[100]!
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.blue[200]!),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.date_range,
                                        color: Colors.blue[700], size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'الفترة المحددة: ',
                                      style: TextStyle(
                                        color: Colors.blue[800],
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        '${fromDate != null ? _formatDisplayDate(fromDate!) : 'غير محدد'} - ${toDate != null ? _formatDisplayDate(toDate!) : 'غير محدد'}',
                                        style: TextStyle(
                                          color: Colors.blue[900],
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],

                            // أزرار التصفية السريعة
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildQuickDateButton(
                                  icon: Icons.nightlight_round,
                                  label: 'من الأمس 9م',
                                  color: Colors.indigo,
                                  isSelected: quickFilterType == 'yesterday',
                                  onPressed: () {
                                    // إنشاء التواريخ بالتوقيت المحلي العراقي
                                    // سيتم تحويلها تلقائياً إلى UTC عند الإرسال للسيرفر
                                    final now = DateTime.now();
                                    final yesterday =
                                        now.subtract(const Duration(days: 1));
                                    setDialogState(() {
                                      // من الساعة 9 مساءً الأمس (بالتوقيت المحلي)
                                      fromDate = DateTime(
                                          yesterday.year,
                                          yesterday.month,
                                          yesterday.day,
                                          21,
                                          0);
                                      // إلى الساعة 9 مساءً اليوم (بالتوقيت المحلي)
                                      toDate = DateTime(
                                          now.year, now.month, now.day, 21, 0);
                                      quickFilterType = 'yesterday';
                                    });
                                  },
                                ),
                                _buildQuickDateButton(
                                  icon: Icons.today,
                                  label: 'اليوم',
                                  color: Colors.blue,
                                  isSelected: quickFilterType == 'today',
                                  onPressed: () {
                                    // إنشاء تاريخ اليوم بالتوقيت المحلي العراقي
                                    final now = DateTime.now();
                                    setDialogState(() {
                                      // من بداية اليوم (00:00 بالتوقيت المحلي)
                                      fromDate = DateTime(
                                          now.year, now.month, now.day);
                                      // إلى نهاية اليوم (23:59 بالتوقيت المحلي)
                                      toDate = DateTime(now.year, now.month,
                                          now.day, 23, 59, 59);
                                      quickFilterType = 'today';
                                    });
                                  },
                                ),
                                _buildQuickDateButton(
                                  icon: Icons.history,
                                  label: 'الأمس',
                                  color: Colors.orange,
                                  isSelected:
                                      quickFilterType == 'yesterday_only',
                                  onPressed: () {
                                    // إنشاء تاريخ الأمس بالتوقيت المحلي العراقي
                                    final yesterday = DateTime.now()
                                        .subtract(const Duration(days: 1));
                                    setDialogState(() {
                                      // من بداية الأمس (00:00 بالتوقيت المحلي)
                                      fromDate = DateTime(yesterday.year,
                                          yesterday.month, yesterday.day);
                                      // إلى نهاية الأمس (23:59 بالتوقيت المحلي)
                                      toDate = DateTime(
                                          yesterday.year,
                                          yesterday.month,
                                          yesterday.day,
                                          23,
                                          59,
                                          59);
                                      quickFilterType = 'yesterday_only';
                                    });
                                  },
                                ),
                                _buildQuickDateButton(
                                  icon: Icons.date_range,
                                  label: '7 أيام',
                                  color: Colors.green,
                                  isSelected: quickFilterType == 'week',
                                  onPressed: () {
                                    // إنشاء نطاق 7 أيام بالتوقيت المحلي العراقي
                                    final now = DateTime.now();
                                    setDialogState(() {
                                      // من 6 أيام مضت + اليوم = 7 أيام (بالتوقيت المحلي)
                                      fromDate = DateTime(
                                              now.year, now.month, now.day)
                                          .subtract(const Duration(days: 6));
                                      // إلى نهاية اليوم (بالتوقيت المحلي)
                                      toDate = DateTime(now.year, now.month,
                                          now.day, 23, 59, 59);
                                      quickFilterType = 'week';
                                    });
                                  },
                                ),
                                _buildQuickDateButton(
                                  icon: Icons.calendar_month,
                                  label: '30 يوم',
                                  color: Colors.purple,
                                  isSelected: quickFilterType == 'month',
                                  onPressed: () {
                                    // إنشاء نطاق 30 يوم بالتوقيت المحلي العراقي
                                    final now = DateTime.now();
                                    setDialogState(() {
                                      // من 29 يوم مضت + اليوم = 30 يوم (بالتوقيت المحلي)
                                      fromDate = DateTime(
                                              now.year, now.month, now.day)
                                          .subtract(const Duration(days: 29));
                                      // إلى نهاية اليوم (بالتوقيت المحلي)
                                      toDate = DateTime(now.year, now.month,
                                          now.day, 23, 59, 59);
                                      quickFilterType = 'month';
                                    });
                                  },
                                ),
                                _buildQuickDateButton(
                                  icon: Icons.calendar_view_month,
                                  label: '90 يوم',
                                  color: Colors.teal,
                                  isSelected: quickFilterType == 'quarter',
                                  onPressed: () {
                                    // إنشاء نطاق 90 يوم بالتوقيت المحلي العراقي
                                    final now = DateTime.now();
                                    setDialogState(() {
                                      // من 89 يوم مضت + اليوم = 90 يوم (بالتوقيت المحلي)
                                      fromDate = DateTime(
                                              now.year, now.month, now.day)
                                          .subtract(const Duration(days: 89));
                                      // إلى نهاية اليوم (بالتوقيت المحلي)
                                      toDate = DateTime(now.year, now.month,
                                          now.day, 23, 59, 59);
                                      quickFilterType = 'quarter';
                                    });
                                  },
                                ),
                                _buildQuickDateButton(
                                  icon: Icons.clear_all,
                                  label: 'كل الفترة',
                                  color: Colors.grey,
                                  isSelected: quickFilterType == 'all',
                                  onPressed: () {
                                    setDialogState(() {
                                      fromDate = null;
                                      toDate = null;
                                      quickFilterType = 'all';
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // أزرار التاريخ اليدوي
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.event, size: 18),
                                    label: const Text('تاريخ مخصص'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.brown[600],
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () =>
                                        _selectCustomDateRange(setDialogState),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text('إعادة تعيين'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red[600],
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () {
                                      setDialogState(() {
                                        fromDate = null;
                                        toDate = null;
                                        quickFilterType = null;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // نوع المحفظة
                      _buildFilterSection(
                        'نوع المحفظة',
                        MultiSelectDialogField<String>(
                          items: walletTypes
                              .map((type) => MultiSelectItem<String>(
                                  type['value']!, type['label']!))
                              .toList(),
                          initialValue: selectedWalletTypes,
                          title: Text('اختر نوع المحفظة'),
                          buttonText: Text('اختر نوع المحفظة'),
                          searchable: true,
                          onConfirm: (values) {
                            setDialogState(() {
                              selectedWalletTypes = List<String>.from(values);
                            });
                          },
                          chipDisplay: MultiSelectChipDisplay.none(),
                        ),
                      ),

                      // مالك المحفظة (شريك / عميل)
                      _buildFilterSection(
                        'مالك المحفظة',
                        MultiSelectDialogField<String>(
                          items: walletOwnerTypes
                              .map((type) => MultiSelectItem<String>(
                                  type['value']!, type['label']!))
                              .toList(),
                          initialValue: selectedWalletOwnerTypes,
                          title: Text('اختر مالك المحفظة'),
                          buttonText: Text('اختر مالك المحفظة'),
                          searchable: true,
                          onConfirm: (values) {
                            setDialogState(() {
                              selectedWalletOwnerTypes =
                                  List<String>.from(values);
                            });
                          },
                          chipDisplay: MultiSelectChipDisplay.none(),
                        ),
                      ),

                      // التواريخ
                      _buildFilterSection(
                        'الفترة الزمنية',
                        Column(
                          children: [
                            // من تاريخ
                            TextFormField(
                              decoration:
                                  _getInputDecoration('من تاريخ').copyWith(
                                suffixIcon: const Icon(Icons.date_range),
                              ),
                              readOnly: true,
                              onTap: () =>
                                  _selectDate(context, true, setDialogState),
                              controller: TextEditingController(
                                text: fromDate != null
                                    ? DateFormat('yyyy/MM/dd').format(fromDate!)
                                    : '',
                              ),
                            ),
                            const SizedBox(height: 12),
                            // إلى تاريخ
                            TextFormField(
                              decoration:
                                  _getInputDecoration('إلى تاريخ').copyWith(
                                suffixIcon: const Icon(Icons.date_range),
                              ),
                              readOnly: true,
                              onTap: () =>
                                  _selectDate(context, false, setDialogState),
                              controller: TextEditingController(
                                text: toDate != null
                                    ? DateFormat('yyyy/MM/dd').format(toDate!)
                                    : '',
                              ),
                            ),
                          ],
                        ),
                      ),

                      // المنطقة - زر لفتح BottomSheet للاختيار المتعدد
                      _buildFilterSection(
                        'المنطقة (Zone)',
                        _buildZonesSelectorButton(setDialogState),
                      ),

                      // أنواع المبيعات
                      _buildFilterSection(
                        'أنواع المبيعات',
                        MultiSelectDialogField<String>(
                          items: salesTypes
                              .map((type) => MultiSelectItem<String>(
                                  type['value']!, type['label']!))
                              .toList(),
                          initialValue: selectedSalesTypes,
                          title: Text('اختر أنواع المبيعات'),
                          buttonText: Text('اختر أنواع المبيعات'),
                          searchable: true,
                          onConfirm: (values) {
                            setDialogState(() {
                              selectedSalesTypes = List<String>.from(values);
                            });
                          },
                          chipDisplay: MultiSelectChipDisplay.none(),
                        ),
                      ),

                      // أنواع التغيير
                      _buildFilterSection(
                        'أنواع التغيير',
                        MultiSelectDialogField<String>(
                          items: changeTypes
                              .map((type) => MultiSelectItem<String>(
                                  type['value']!, type['label']!))
                              .toList(),
                          initialValue: selectedChangeTypes,
                          title: Text('اختر أنواع التغيير'),
                          buttonText: Text('اختر أنواع التغيير'),
                          searchable: true,
                          onConfirm: (values) {
                            setDialogState(() {
                              selectedChangeTypes = List<String>.from(values);
                            });
                          },
                          chipDisplay: MultiSelectChipDisplay.none(),
                        ),
                      ),

                      // طرق الدفع
                      _buildFilterSection(
                        'طرق الدفع',
                        MultiSelectDialogField<String>(
                          items: paymentMethods
                              .map((type) => MultiSelectItem<String>(
                                  type['value']!, type['label']!))
                              .toList(),
                          initialValue: selectedPaymentMethods,
                          title: Text('اختر طرق الدفع'),
                          buttonText: Text('اختر طرق الدفع'),
                          searchable: true,
                          onConfirm: (values) {
                            setDialogState(() {
                              selectedPaymentMethods =
                                  List<String>.from(values);
                            });
                          },
                          chipDisplay: MultiSelectChipDisplay.none(),
                        ),
                      ),

                      // أنواع المعاملات
                      _buildFilterSection(
                        'أنواع المعاملات',
                        MultiSelectDialogField<String>(
                          items: transactionTypes
                              .map((type) => MultiSelectItem<String>(
                                  type['value']!, type['label']!))
                              .toList(),
                          initialValue: selectedTransactionTypes,
                          title: Text('اختر أنواع المعاملات'),
                          buttonText: Text('اختر أنواع المعاملات'),
                          searchable: true,
                          onConfirm: (values) {
                            setDialogState(() {
                              selectedTransactionTypes =
                                  List<String>.from(values);
                            });
                          },
                          chipDisplay: MultiSelectChipDisplay.none(),
                        ),
                      ),

                      // أسماء الخدمات
                      _buildFilterSection(
                        'أسماء الخدمات',
                        MultiSelectDialogField<String>(
                          items: serviceNames
                              .map((type) => MultiSelectItem<String>(
                                  type['value']!, type['label']!))
                              .toList(),
                          initialValue: selectedServiceNames,
                          title: Text('اختر أسماء الخدمات'),
                          buttonText: Text('اختر أسماء الخدمات'),
                          searchable: true,
                          onConfirm: (values) {
                            setDialogState(() {
                              selectedServiceNames = List<String>.from(values);
                            });
                          },
                          chipDisplay: MultiSelectChipDisplay.none(),
                        ),
                      ),

                      // عدد المعاملات المعروضة
                      _buildFilterSection(
                        'عدد المعاملات المعروضة',
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<int>(
                              decoration:
                                  _getInputDecoration('اختر عدد المعاملات'),
                              initialValue: pageSize,
                              items: pageSizeOptions
                                  .map((option) => DropdownMenuItem<int>(
                                      value: option['value'],
                                      child: Text(option['label'])))
                                  .toList(),
                              onChanged: (value) {
                                setDialogState(() {
                                  if (value != null) {
                                    pageSize = value;
                                  }
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue[200]!),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.blue[600],
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'الإعداد الافتراضي: 500 معاملة لكل صفحة - يمكنك تغيير هذا الرقم حسب الحاجة',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue[700],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // إحصائيات التصفية
                      if (_hasActiveFilters()) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.green[50]!, Colors.green[100]!],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green[300]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.filter_alt,
                                    color: Colors.green[700],
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'ملخص التصفية النشطة:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if (selectedTransactionTypes.isNotEmpty)
                                    _buildFilterChip(
                                        'أنواع المعاملات: ${selectedTransactionTypes.length}'),
                                  if (selectedSalesTypes.isNotEmpty)
                                    _buildFilterChip(
                                        'أنواع المبيعات: ${selectedSalesTypes.length}'),
                                  if (selectedPaymentMethods.isNotEmpty)
                                    _buildFilterChip(
                                        'طرق الدفع: ${selectedPaymentMethods.length}'),
                                  if (selectedServiceNames.isNotEmpty)
                                    _buildFilterChip(
                                        'الخدمات: ${selectedServiceNames.length}'),
                                  if (selectedWalletTypes.isNotEmpty)
                                    _buildFilterChip(
                                        'أنواع المحافظ: ${selectedWalletTypes.length}'),
                                  if (selectedWalletOwnerTypes.isNotEmpty)
                                    _buildFilterChip(
                                        'مالك المحفظة: ${selectedWalletOwnerTypes.length}'),
                                  if (selectedChangeTypes.isNotEmpty)
                                    _buildFilterChip(
                                        'أنواع التغيير: ${selectedChangeTypes.length}'),
                                  if (fromDate != null || toDate != null)
                                    _buildFilterChip('فترة زمنية'),
                                  if (selectedZones.isNotEmpty)
                                    _buildFilterChip(
                                        'المناطق: ${selectedZones.length}'),
                                  if (transactionUser != null &&
                                      transactionUser!.isNotEmpty)
                                    _buildFilterChip('مستخدم'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                // زر إعادة تعيين
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      _resetFilters();
                    });
                  },
                  child: const Text('إعادة تعيين'),
                ),
                // زر إلغاء
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إلغاء'),
                ),
                // زر تطبيق
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _loadTransactions(isRefresh: true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('تطبيق'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ...existing code...

  Widget _buildFilterSection(String title, Widget content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A237E),
            ),
          ),
          const SizedBox(height: 8),
          content,
        ],
      ),
    );
  }

  InputDecoration _getInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF1A237E)),
      ),
    );
  }

  Future<void> _selectDate(
      BuildContext context, bool isFromDate, StateSetter setDialogState) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1A237E),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setDialogState(() {
        // إعادة تعيين نوع الفلتر السريع عند اختيار تاريخ يدوي
        quickFilterType = null;
        // التاريخ المختار بالتوقيت المحلي العراقي
        // سيتم تحويله تلقائياً إلى UTC عند الإرسال للسيرفر
        if (isFromDate) {
          fromDate = picked;
        } else {
          toDate = picked;
        }
      });
    }
  }

  // دالة لتنسيق عرض التواريخ في مربعات التصفية
  // العرض يكون بالتوقيت المحلي العراقي للمستخدم
  String _formatDisplayDate(DateTime? date) {
    if (date == null) return '';

    // إذا كان التاريخ مع وقت محدد (21:00)، فهذا يعني أنه من الفلاتر السريعة
    if (date.hour == 21 && date.minute == 0 && date.second == 0) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(Duration(days: 1));

      // استخدام نوع الفلتر السريع لتحديد العرض
      if (quickFilterType == 'today') {
        // عند اختيار "اليوم"، كلا التاريخين يظهران كاليوم
        return DateFormat('yyyy/MM/dd').format(today);
      } else if (quickFilterType == 'yesterday') {
        // عند اختيار "الأمس"، كلا التاريخين يظهران كالأمس
        return DateFormat('yyyy/MM/dd').format(yesterday);
      } else {
        // للحالات الأخرى، نضيف 3 ساعات للحصول على اليوم التالي المنطقي
        return DateFormat('yyyy/MM/dd').format(date.add(Duration(hours: 3)));
      }
    } else {
      // للتواريخ العادية، نعرضها كما هي (بالتوقيت المحلي)
      return DateFormat('yyyy/MM/dd').format(date);
    }
  }

  void _resetFilters() {
    selectedWalletTypes.clear();
    selectedWalletOwnerTypes.clear();
    selectedSalesTypes.clear();
    selectedChangeTypes.clear();
    selectedPaymentMethods.clear();
    selectedZones.clear(); // تم التغيير من selectedZone = null
    selectedTransactionTypes.clear();
    selectedServiceNames.clear();
    transactionUser = null;
    showTransactionsWithoutUser = false;
    // إعادة تعيين الفلاتر الإضافية
    showPositiveOnly = false;
    showNegativeOnly = false;
    showWithoutCreatorOnly = false;
    showScheduledOnly = false;

    // إعادة تعيين نوع الفلتر السريع
    quickFilterType = 'yesterday'; // الافتراضي هو الأمس

    // إعادة تعيين الإعدادات الافتراضية للأمس (من 9 مساءً قبل الأمس إلى 9 مساءً الأمس)
    // التوقيت هنا بالتوقيت المحلي العراقي، وسيتم تحويله إلى UTC عند الإرسال
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    // من الساعة 9 مساءً لليوم السابق للأمس (بالتوقيت المحلي العراقي)
    fromDate =
        DateTime(yesterday.year, yesterday.month, yesterday.day - 1, 21, 0, 0);
    // إلى الساعة 9 مساءً للأمس (بالتوقيت المحلي العراقي)
    toDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 21, 0, 0);
    selectedWalletOwnerTypes = ['partner']; // شريك كافتراضي
  }

  bool _hasActiveFilters() {
    return selectedWalletTypes.isNotEmpty ||
        selectedWalletOwnerTypes.isNotEmpty ||
        selectedSalesTypes.isNotEmpty ||
        selectedChangeTypes.isNotEmpty ||
        selectedPaymentMethods.isNotEmpty ||
        fromDate != null ||
        toDate != null ||
        selectedZones.isNotEmpty || // تم التغيير
        selectedTransactionTypes.isNotEmpty ||
        selectedServiceNames.isNotEmpty ||
        (transactionUser != null && transactionUser!.isNotEmpty);
  }

  // زر فتح اختيار المناطق في BottomSheet
  Widget _buildZonesSelectorButton(StateSetter setDialogState) {
    final count =
        selectedZones.isEmpty ? 'الكل' : '${selectedZones.length} مختارة';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: isLoadingZones
                  ? null
                  : () async {
                      if (availableZones.isEmpty && !isLoadingZones) {
                        await _loadZones();
                      }
                      if (!mounted) return;
                      if (availableZones.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('لا توجد مناطق متاحة'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }
                      _openZonesBottomSheet(setDialogState);
                    },
              icon: const Icon(Icons.map, size: 18),
              label: Text('اختيار المناطق: $count'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
            if (isLoadingZones)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            if (selectedZones.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => setDialogState(() {
                  selectedZones.clear();
                }),
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('مسح'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
          ],
        ),
        if (selectedZones.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: selectedZones.take(5).map((zone) {
              return Chip(
                label: Text(zone, style: const TextStyle(fontSize: 11)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () => setDialogState(() {
                  selectedZones.remove(zone);
                }),
                backgroundColor: Colors.blue[50],
                padding: const EdgeInsets.symmetric(horizontal: 4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
          if (selectedZones.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${selectedZones.length - 5} منطقة أخرى',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ),
        ],
      ],
    );
  }

  // فتح BottomSheet لاختيار المناطق
  void _openZonesBottomSheet(StateSetter setDialogState) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        // نسخة عمل مؤقتة (حتى يتم الحفظ)
        final tempSelected = Set<String>.from(selectedZones);
        String localSearch = '';
        final List<String> allZones = List<String>.from(availableZones);
        const int maxDisplay = 500;
        List<String> filtered = [];
        final ScrollController zonesScrollController = ScrollController();

        // دالة فلترة
        List<String> runFilter(String q) {
          final query = q.toLowerCase();
          if (query.isEmpty) {
            return allZones.length > maxDisplay
                ? allZones.take(maxDisplay).toList()
                : allZones;
          }
          final List<String> out = [];
          for (final z in allZones) {
            if (z.toLowerCase().contains(query)) {
              out.add(z);
              if (out.length >= maxDisplay) break;
            }
          }
          return out;
        }

        filtered = runFilter(localSearch);

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // مقبض السحب
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    // العنوان
                    Row(
                      children: [
                        const Icon(Icons.map, color: Color(0xFF1A237E)),
                        const SizedBox(width: 8),
                        Text(
                          'اختيار المناطق',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${tempSelected.length} مختارة',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // حقل البحث
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'بحث عن منطقة...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        setModalState(() {
                          localSearch = v.trim();
                          filtered = runFilter(localSearch);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    // صف الكل + تفريغ
                    Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('جميع المناطق'),
                            dense: true,
                            value: tempSelected.isEmpty,
                            onChanged: (v) {
                              setModalState(() {
                                tempSelected.clear();
                              });
                            },
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setModalState(() => tempSelected.clear()),
                          child: const Text('تفريغ الكل'),
                        ),
                        TextButton(
                          onPressed: () => setModalState(() {
                            tempSelected.addAll(filtered);
                          }),
                          child: const Text('تحديد الكل'),
                        ),
                      ],
                    ),
                    // قائمة المناطق
                    SizedBox(
                      height: 300,
                      child: Scrollbar(
                        controller: zonesScrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: zonesScrollController,
                          primary: false,
                          itemCount: filtered.length,
                          itemBuilder: (c, i) {
                            final zone = filtered[i];
                            final checked = tempSelected.contains(zone);
                            return CheckboxListTile(
                              title: Text(
                                zone,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              value: checked,
                              dense: true,
                              onChanged: (v) {
                                setModalState(() {
                                  if (v == true) {
                                    tempSelected.add(zone);
                                  } else {
                                    tempSelected.remove(zone);
                                  }
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          },
                        ),
                      ),
                    ),
                    if (filtered.length >= maxDisplay)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'عرض أول $maxDisplay فقط - استخدم البحث لتصفية أكثر',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ),
                    const SizedBox(height: 12),
                    // أزرار الإغلاق والحفظ
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                            label: const Text('إغلاق'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              // حفظ الاختيارات وتحديث الـ dialog الرئيسي
                              selectedZones
                                ..clear()
                                ..addAll(tempSelected);
                              setDialogState(() {});
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('حفظ'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A237E),
                              foregroundColor: Colors.white,
                            ),
                          ),
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

  Widget _buildFilterChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green[200],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[400]!),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.green[800],
        ),
      ),
    );
  }

  int _getActiveFiltersCount() {
    int count = 0;
    if (selectedWalletTypes.isNotEmpty) count++;
    if (selectedWalletOwnerTypes.isNotEmpty) count++;
    if (selectedSalesTypes.isNotEmpty) count++;
    if (selectedChangeTypes.isNotEmpty) count++;
    if (selectedPaymentMethods.isNotEmpty) count++;
    if (fromDate != null || toDate != null) count++;
    if (selectedZones.isNotEmpty) count++; // تم التغيير
    if (selectedTransactionTypes.isNotEmpty) count++;
    if (selectedServiceNames.isNotEmpty) count++;
    if (transactionUser != null && transactionUser!.isNotEmpty) count++;
    return count;
  }

  String _formatCurrency(dynamic value) {
    if (value == null) return '0';
    final amount = (value is int) ? value : (value as double).round();
    return amount.toString();
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
        return Icons.settings;
      default:
        return Icons.help;
    }
  }

  // دالة لبناء زر التاريخ السريع
  Widget _buildQuickDateButton({
    required IconData icon,
    required String label,
    required MaterialColor color,
    required bool isSelected,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? color[800] : color[600],
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        elevation: isSelected ? 8 : 2,
        shadowColor: color.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: isSelected
              ? BorderSide(color: color[900]!, width: 2)
              : BorderSide.none,
        ),
      ),
      onPressed: onPressed,
    );
  }

  // دالة لاختيار نطاق تاريخ مخصص
  Future<void> _selectCustomDateRange(StateSetter setDialogState) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: (fromDate != null && toDate != null)
          ? DateTimeRange(start: fromDate!, end: toDate!)
          : null,
      locale: const Locale('ar'),
      helpText: 'اختر نطاق التاريخ (بالتوقيت المحلي العراقي)',
      cancelText: 'إلغاء',
      confirmText: 'موافق',
      fieldStartLabelText: 'من تاريخ',
      fieldEndLabelText: 'إلى تاريخ',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue[700]!,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setDialogState(() {
        // التواريخ المختارة بالتوقيت المحلي العراقي
        // سيتم تحويلها تلقائياً إلى UTC عند الإرسال للسيرفر
        fromDate = picked.start;
        toDate = DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
        quickFilterType = 'custom';
      });
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'غير محدد';
    try {
      // تحويل التاريخ من UTC (المُستلم من السيرفر) إلى التوقيت المحلي العراقي (+3 GMT) للعرض
      final utcDate = DateTime.parse(dateStr);
      final localDate = utcDate.toLocal();
      return DateFormat('yyyy/MM/dd HH:mm').format(localDate);
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
        return Icons.refresh;
      case 'PLAN_SUBSCRIBE':
        return Icons.add_shopping_cart;
      case 'WALLET_TRANSFER':
        return Icons.swap_horiz;
      case 'COMMISSION':
        return Icons.monetization_on;
      case 'PAYMENT':
        return Icons.payment;
      default:
        return Icons.receipt;
    }
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
    final createdBy = transaction['createdBy'] ?? '';
    final paymentMode = transaction['paymentMode'] ?? '';
    final paymentMethod = transaction['paymentMethod'];
    final serialNumber = transaction['serialNumber'] ?? '';
    final lineOfBusiness = transaction['lineOfBusiness'];
    final walletOwnerType = transaction['walletOwnerType'];
    final walletType = transaction['walletType'];
    final salesType = transaction['salesType'];
    final discountAmount = transaction['discountAmount'] ?? 0;
    final deviceUsername = transaction['deviceUsername'] ?? '';

    // تحديد ما إذا كانت المعاملة مجدولة
    final isScheduled = transaction['changeType'] != null &&
        transaction['changeType']['displayValue'] == 'Scheduled';

    final color = _getTransactionColor(transaction);
    final icon = _getTransactionIcon(type);

    // تجميع المعلومات المهمة بدون تكرار - العميل أولاً (المنفذ أصبح في الأعلى)
    final List<Map<String, String>> infoItems = [];

    // العميل أولاً (المنفذ الآن في المكان البارز أعلاه)
    if (customer != null && customer['displayValue']?.isNotEmpty == true) {
      infoItems.add({'label': 'العميل', 'value': customer['displayValue']});
    }

    // إضافة معرف المعاملة في قائمة المعلومات
    if (transaction['id'] != null) {
      infoItems.add(
          {'label': 'معرف المعاملة', 'value': transaction['id'].toString()});
    }

    // إضافة معرف المشترك إذا كان متوفراً
    if (customer != null && customer['id'] != null) {
      infoItems
          .add({'label': 'معرف المشترك', 'value': customer['id'].toString()});
    }

    if (zoneId.isNotEmpty) {
      infoItems.add({'label': 'الزون', 'value': zoneId});
    }

    if (subscription != null &&
        subscription['displayValue']?.isNotEmpty == true) {
      infoItems
          .add({'label': 'الاشتراك', 'value': subscription['displayValue']});

      // حساب فترة الاشتراك إذا توفرت التواريخ
      if (subscription['startsAt'] != null && subscription['endsAt'] != null) {
        try {
          final startDate = DateTime.parse(subscription['startsAt']);
          final endDate = DateTime.parse(subscription['endsAt']);
          final durationInDays = endDate.difference(startDate).inDays;
          final durationInMonths = (durationInDays / 30).round();

          String durationText;
          if (durationInMonths == 0) {
            durationText = '$durationInDays يوم';
          } else if (durationInMonths == 1) {
            durationText = 'شهر واحد';
          } else if (durationInMonths == 2) {
            durationText = 'شهرين';
          } else if (durationInMonths >= 3 && durationInMonths <= 10) {
            durationText = '$durationInMonths أشهر';
          } else {
            durationText = '$durationInMonths شهر';
          }

          infoItems.add({'label': 'مدة الاشتراك', 'value': durationText});

          // إضافة تاريخ البداية والنهاية
          final dateFormat = DateFormat('yyyy-MM-dd', 'ar');
          infoItems.add({
            'label': 'بداية الاشتراك',
            'value': dateFormat.format(startDate)
          });
          infoItems.add(
              {'label': 'نهاية الاشتراك', 'value': dateFormat.format(endDate)});
        } catch (e) {
          // في حالة فشل تحليل التاريخ، لا نضيف شيء
        }
      }
    }

    if (paymentMode.isNotEmpty) {
      infoItems.add({'label': 'طريقة الدفع', 'value': paymentMode});
    }

    if (paymentMethod != null &&
        paymentMethod['displayValue']?.isNotEmpty == true) {
      infoItems
          .add({'label': 'نوع الدفع', 'value': paymentMethod['displayValue']});
    }

    if (serialNumber.isNotEmpty) {
      infoItems.add({'label': 'الرقم التسلسلي', 'value': serialNumber});
    }

    if (lineOfBusiness != null &&
        lineOfBusiness['displayValue']?.isNotEmpty == true) {
      infoItems.add(
          {'label': 'خط الأعمال', 'value': lineOfBusiness['displayValue']});
    }

    if (walletOwnerType != null &&
        walletOwnerType['displayValue']?.isNotEmpty == true) {
      infoItems.add(
          {'label': 'مالك المحفظة', 'value': walletOwnerType['displayValue']});
    }

    if (walletType != null && walletType['displayValue']?.isNotEmpty == true) {
      infoItems
          .add({'label': 'نوع المحفظة', 'value': walletType['displayValue']});
    }

    if (salesType != null && salesType['displayValue']?.isNotEmpty == true) {
      infoItems
          .add({'label': 'نوع المبيعات', 'value': salesType['displayValue']});
    }

    if (discountAmount > 0) {
      infoItems.add({
        'label': 'الخصم',
        'value': '${_formatCurrency(discountAmount)} $currency'
      });
    }

    if (deviceUsername.isNotEmpty) {
      infoItems.add({'label': 'الجهاز', 'value': deviceUsername});
    }

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
                // الصف العلوي - معلومات أساسية
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
                      child: Icon(
                        icon,
                        color: color,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // عرض كل معلومة في بطاقة منفصلة صغيرة بدل صندوق كبير
                          Row(
                            children: [
                              if (createdBy.isNotEmpty) ...[
                                GestureDetector(
                                  onTap: () => _copyToClipboard(
                                      createdBy, 'اسم المستخدم'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.green[600]!,
                                          Colors.green[700]!,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.person,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            createdBy,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.copy,
                                          size: 12,
                                          color: Colors.white70,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],

                              // بطاقة نوع المعاملة
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blue[600]!,
                                      Colors.blue[700]!,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      icon,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _translateTransactionType(type),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // شارة المعاملة المجدولة أو نوع التغيير
                              if (transaction['changeType'] != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: _getChangeTypeColors(
                                          transaction['changeType']
                                                  ['displayValue'] ??
                                              ''),
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _getChangeTypeColors(
                                                transaction['changeType']
                                                        ['displayValue'] ??
                                                    '')
                                            .first
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
                                                    ['displayValue'] ??
                                                ''),
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _translateChangeType(
                                            transaction['changeType']
                                                    ['displayValue'] ??
                                                ''),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],

                              // بطاقة الوقت والتاريخ
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.grey[700],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  () {
                                    final formatted = _formatDate(occuredAt);
                                    final parts = formatted.split(' ');
                                    final datePart =
                                        parts.isNotEmpty ? parts[0] : '';
                                    final timePart =
                                        parts.length > 1 ? parts[1] : '';
                                    return '$timePart  $datePart';
                                  }(),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // صندوق المبلغ — اضبط القيود ليطابق ارتفاع البطاقات الأخرى ويزيد العرض
                              Container(
                                constraints: const BoxConstraints(
                                  minWidth: 120,
                                  minHeight: 44,
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: color.withValues(alpha: 0.25),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${amount >= 0 ? '+' : ''}${_formatCurrency(amount)}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: color,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      currency,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // صندوق المبلغ المتبقي - نقل من الأسفل إلى نفس الصف
                              Container(
                                constraints: const BoxConstraints(
                                  minWidth: 120,
                                  minHeight: 44,
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.blue[50]!,
                                      Colors.blue[100]!,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.blue[300]!,
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.withValues(alpha: 0.1),
                                      blurRadius: 3,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'الرصيد المتبقي: ',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.blue[700],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${_formatCurrency(balance)} $currency',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[800],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (infoItems.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.grey[300]!,
                          Colors.transparent
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // عرض المعلومات في شبكة مرنة مع تحسين البروز
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children:
                        infoItems.map((item) => _buildInfoItem(item)).toList(),
                  ),
                ],

                // أزيلت المساحة الفارغة والصف غير الضروري
              ],
            ),
          ),
        ),
      ),
    );
  }

  // دالة مساعدة لنسخ النص
  Future<void> _copyToClipboard(String text, String itemName) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم نسخ $itemName: $text'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // دالة لبناء عنصر المعلومات مع إمكانية النسخ للعناصر المحددة
  Widget _buildInfoItem(Map<String, String> item) {
    final label = item['label']!;
    final value = item['value']!;

    // الحقول القابلة للنسخ
    final copyableFields = [
      'معرف المعاملة',
      'معرف المشترك',
      'العميل',
      'الاشتراك',
      'الرقم التسلسلي',
      'اسم المستخدم للجهاز'
    ];

    final isCopyable = copyableFields.contains(label);

    return GestureDetector(
      onTap: isCopyable ? () => _copyToClipboard(value, label) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              isCopyable ? Colors.blue[50]! : Colors.grey[100]!,
              isCopyable ? Colors.blue[100]! : Colors.grey[50]!,
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCopyable ? Colors.blue[300]! : Colors.grey[400]!,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (isCopyable ? Colors.blue : Colors.grey)
                  .withValues(alpha: 0.1),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: isCopyable ? Colors.blue[600] : Colors.blue[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const Text(
              ': ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isCopyable ? Colors.blue[800]! : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isCopyable) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.copy,
                size: 14,
                color: Colors.blue[600],
              ),
            ],
          ],
        ),
      ),
    );
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
                  _buildDetailRow('المبلغ',
                      '${transaction['transactionAmount']?['value'] ?? 0} ${transaction['transactionAmount']?['currency'] ?? 'IQD'}'),
                  _buildDetailRow('الرصيد المتبقي',
                      '${transaction['remainingBalance']?['value'] ?? 0} ${transaction['remainingBalance']?['currency'] ?? 'IQD'}'),
                  _buildDetailRow(
                      'التاريخ', _formatDate(transaction['occuredAt'])),
                  _buildDetailRow('الشريك',
                      transaction['partner']?['displayValue'] ?? 'غير محدد'),
                  if (transaction['customer']?['displayValue']?.isNotEmpty ==
                      true)
                    _buildDetailRow(
                        'العميل', transaction['customer']['displayValue']),
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
                    _buildDetailRow('نوع الاشتراك',
                        transaction['subscription']['type'] ?? 'غير محدد'),
                    if (transaction['subscription']['startsAt'] != null)
                      _buildDetailRow('بداية الاشتراك',
                          _formatDate(transaction['subscription']['startsAt'])),
                    if (transaction['subscription']['endsAt'] != null)
                      _buildDetailRow('نهاية الاشتراك',
                          _formatDate(transaction['subscription']['endsAt'])),
                    // إضافة مدة الاشتراك
                    if (transaction['subscription']['startsAt'] != null &&
                        transaction['subscription']['endsAt'] != null)
                      (() {
                        try {
                          final startDate = DateTime.parse(
                              transaction['subscription']['startsAt']);
                          final endDate = DateTime.parse(
                              transaction['subscription']['endsAt']);
                          final durationInDays =
                              endDate.difference(startDate).inDays;
                          final durationInMonths =
                              (durationInDays / 30).round();

                          String durationText;
                          if (durationInMonths == 0) {
                            durationText = '$durationInDays يوم';
                          } else if (durationInMonths == 1) {
                            durationText = 'شهر واحد';
                          } else if (durationInMonths == 2) {
                            durationText = 'شهرين';
                          } else if (durationInMonths >= 3 &&
                              durationInMonths <= 10) {
                            durationText = '$durationInMonths أشهر';
                          } else {
                            durationText = '$durationInMonths شهر';
                          }

                          return _buildDetailRow('مدة الاشتراك', durationText);
                        } catch (e) {
                          return const SizedBox.shrink();
                        }
                      })(),
                  ],
                  _buildDetailRow(
                      'أنشأ بواسطة', transaction['createdBy'] ?? 'غير محدد'),
                  _buildDetailRow(
                      'طريقة الدفع', transaction['paymentMode'] ?? 'غير محدد'),
                  _buildDetailRow(
                      'نوع الدفع',
                      transaction['paymentMethod']?['displayValue'] ??
                          'غير محدد'),
                  _buildDetailRow('الرقم التسلسلي',
                      transaction['serialNumber'] ?? 'غير محدد'),
                  _buildDetailRow(
                      'خط الأعمال',
                      transaction['lineOfBusiness']?['displayValue'] ??
                          'غير محدد'),
                  _buildDetailRow(
                      'مالك المحفظة',
                      transaction['walletOwnerType']?['displayValue'] ??
                          'غير محدد'),
                  _buildDetailRow('نوع المحفظة',
                      transaction['walletType']?['displayValue'] ?? 'غير محدد'),
                  _buildDetailRow('نوع المبيعات',
                      transaction['salesType']?['displayValue'] ?? 'غير محدد'),
                  if (transaction['discountAmount'] != null &&
                      transaction['discountAmount'] > 0) ...[
                    _buildDetailRow(
                        'مبلغ الخصم', '${transaction['discountAmount']} IQD'),
                    _buildDetailRow(
                        'نوع الخصم', transaction['discountType'] ?? 'غير محدد'),
                  ],
                  if (transaction['deviceUsername']?.isNotEmpty == true)
                    _buildDetailRow(
                        'اسم المستخدم للجهاز', transaction['deviceUsername']),
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
              child: const Text('نسخ التفاصيل'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text(
                'إغلاق',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final labelWidth = MediaQuery.of(context).size.width <= 600 ? 90.0 : 120.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
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
    details.writeln(
        'المبلغ: ${transaction['transactionAmount']?['value'] ?? 0} ${transaction['transactionAmount']?['currency'] ?? 'IQD'}');
    details.writeln(
        'الرصيد المتبقي: ${transaction['remainingBalance']?['value'] ?? 0} ${transaction['remainingBalance']?['currency'] ?? 'IQD'}');
    details.writeln('التاريخ: ${_formatDate(transaction['occuredAt'])}');
    details.writeln(
        'الشريك: ${transaction['partner']?['displayValue'] ?? 'غير محدد'}');

    if (transaction['customer']?['displayValue']?.isNotEmpty == true) {
      details.writeln('العميل: ${transaction['customer']['displayValue']}');
    }

    if (transaction['zoneId']?.isNotEmpty == true) {
      details.writeln('الزون: ${transaction['zoneId']}');
    }

    if (transaction['subscription'] != null) {
      details.writeln(
          'الاشتراك: ${transaction['subscription']['displayValue'] ?? 'غير محدد'}');
      details.writeln(
          'نوع الاشتراك: ${transaction['subscription']['type'] ?? 'غير محدد'}');

      // إضافة تواريخ الاشتراك ومدته
      if (transaction['subscription']['startsAt'] != null) {
        details.writeln(
            'بداية الاشتراك: ${_formatDate(transaction['subscription']['startsAt'])}');
      }
      if (transaction['subscription']['endsAt'] != null) {
        details.writeln(
            'نهاية الاشتراك: ${_formatDate(transaction['subscription']['endsAt'])}');
      }

      // حساب مدة الاشتراك
      if (transaction['subscription']['startsAt'] != null &&
          transaction['subscription']['endsAt'] != null) {
        try {
          final startDate =
              DateTime.parse(transaction['subscription']['startsAt']);
          final endDate = DateTime.parse(transaction['subscription']['endsAt']);
          final durationInDays = endDate.difference(startDate).inDays;
          final durationInMonths = (durationInDays / 30).round();

          String durationText;
          if (durationInMonths == 0) {
            durationText = '$durationInDays يوم';
          } else if (durationInMonths == 1) {
            durationText = 'شهر واحد';
          } else if (durationInMonths == 2) {
            durationText = 'شهرين';
          } else if (durationInMonths >= 3 && durationInMonths <= 10) {
            durationText = '$durationInMonths أشهر';
          } else {
            durationText = '$durationInMonths شهر';
          }

          details.writeln('مدة الاشتراك: $durationText');
        } catch (e) {
          // في حالة فشل تحليل التاريخ، لا نضيف شيء
        }
      }
    }

    details.writeln('أنشأ بواسطة: ${transaction['createdBy'] ?? 'غير محدد'}');
    details.writeln('طريقة الدفع: ${transaction['paymentMode'] ?? 'غير محدد'}');

    return details.toString();
  }

  void _goToPage(int page) {
    if (page >= 1 && page <= _getTotalPages() && page != currentPage) {
      setState(() {
        currentPage = page;
        transactions.clear();
        isLoading = true;
      });
      _loadTransactions();
    }
  }

  void _nextPage() {
    if (currentPage < _getTotalPages()) {
      _goToPage(currentPage + 1);
    }
  }

  void _previousPage() {
    if (currentPage > 1) {
      _goToPage(currentPage - 1);
    }
  }

  int _getTotalPages() {
    return (totalCount / pageSize).ceil();
  }

  Future<void> _fetchAllPagesSums() async {
    // يحسب مجموع كل النتائج المفلترة على الخادم (جميع الصفحات)
    if (totalCount == 0) {
      if (!mounted) return;
      setState(() {
        positiveSumAll = 0.0;
        negativeSumAll = 0.0;
        scheduledCountAll = 0;
        scheduledSumAll = 0.0;
        positiveCountAll = 0;
        negativeCountAll = 0;
        withoutCreatorCountAll = 0;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      isLoadingAllTotals = true;
      positiveSumAll = 0.0;
      negativeSumAll = 0.0;
      negativeSumWithoutCreatorAll = 0.0;
      scheduledCountAll = 0;
      scheduledSumAll = 0.0;
      positiveCountAll = 0;
      negativeCountAll = 0;
      withoutCreatorCountAll = 0;
    });
    try {
      final int totalPages = _getTotalPages();
      for (int page = 1; page <= totalPages; page++) {
        final int tempPage = currentPage;
        currentPage = page;
        final url = _buildFilteredUrl();
        currentPage = tempPage;

        final response =
            await AuthService.instance.authenticatedRequest('GET', url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          List<Map<String, dynamic>> items =
              List<Map<String, dynamic>>.from(data['items'] ?? []);

          // تطبيق الفلاتر الإضافية على البيانات
          items = _applyAdditionalFilters(items);

          for (final t in items) {
            final amtDynamic = t['transactionAmount']?['value'] ?? 0.0;
            final num amtNum = (amtDynamic is num)
                ? amtDynamic
                : double.tryParse(amtDynamic.toString()) ?? 0.0;
            final double val = amtNum.toDouble();

            // فحص إذا كانت المعاملة بدون اسم منشئ
            final createdBy = t['createdBy'];
            final transactionUser = t['transactionUser'];
            final username = t['username'];
            final hasNoCreator =
                (createdBy == null || createdBy.toString().trim().isEmpty) &&
                    (transactionUser == null ||
                        transactionUser.toString().trim().isEmpty) &&
                    (username == null || username.toString().trim().isEmpty);

            // فحص إذا كانت المعاملة مجدولة
            final isScheduled = t['changeType'] != null &&
                t['changeType']['displayValue'] == 'Scheduled';
            if (isScheduled) {
              scheduledCountAll++;
              scheduledSumAll += val;
            }

            if (val > 0) {
              positiveSumAll += val;
              positiveCountAll++;
            } else if (val < 0) {
              negativeSumAll += val;
              negativeCountAll++;

              // إذا كانت المعاملة بدون اسم منشئ وسالبة
              if (hasNoCreator) {
                negativeSumWithoutCreatorAll += val;
                withoutCreatorCountAll++;
              }
            }
          }
        } else if (response.statusCode == 401) {
          _handle401Error();
          break;
        } else {
          // إذا حدث خطأ في صفحة ما، نكمل الباقي لكنه يستحق إعلام المستخدم
          // نكمل لنجمع ما يمكن
        }
      }
    } catch (e) {
      // تجاهل الخطأ هنا، يمكن عرض رسالة إن رغبت
    } finally {
      if (mounted) {
        setState(() {
          isLoadingAllTotals = false;
        });
      }
    }
  }

  // دالة جديدة لحساب المبلغ الإجمالي حسب اسم المنشأة
  Future<void> _calculateCreatorAmounts() async {
    if (totalCount == 0) {
      if (!mounted) return;
      setState(() {
        creatorAmounts = {};
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      isCalculatingCreatorAmounts = true;
      creatorAmounts = {};
    });

    try {
      final int totalPages = _getTotalPages();
      Map<String, double> tempCreatorAmounts = {};
      List<Map<String, dynamic>> allTransactions = []; // لجمع جميع المعاملات

      for (int page = 1; page <= totalPages; page++) {
        final int tempPage = currentPage;
        currentPage = page;
        final url = _buildFilteredUrl();
        currentPage = tempPage;

        final response =
            await AuthService.instance.authenticatedRequest('GET', url);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          List<Map<String, dynamic>> items =
              List<Map<String, dynamic>>.from(data['items'] ?? []);

          // تطبيق الفلاتر الإضافية على البيانات
          items = _applyAdditionalFilters(items);

          // إضافة العناصر لقائمة جميع المعاملات
          allTransactions.addAll(items);

          for (final transaction in items) {
            final amtDynamic =
                transaction['transactionAmount']?['value'] ?? 0.0;
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
            } else if (username != null &&
                username.toString().trim().isNotEmpty) {
              creatorName = username.toString().trim();
            }

            // إضافة المبلغ للمنشأة
            if (tempCreatorAmounts.containsKey(creatorName)) {
              tempCreatorAmounts[creatorName] =
                  tempCreatorAmounts[creatorName]! + amount;
            } else {
              tempCreatorAmounts[creatorName] = amount;
            }
          }
        } else if (response.statusCode == 401) {
          _handle401Error();
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        creatorAmounts = tempCreatorAmounts;
      });

      // عرض النتائج في نافذة منبثقة مع تمرير المعاملات المفصلة
      _showCreatorAmountsDialog(allTransactions);
    } catch (e) {
      _showError('خطأ في حساب المبالغ حسب المنشأة');
    } finally {
      if (mounted) {
        setState(() {
          isCalculatingCreatorAmounts = false;
        });
      }
    }
  }

  // عرض نتائج المبالغ حسب المنشأة
  void _showCreatorAmountsDialog(
      [List<Map<String, dynamic>>? allTransactions]) {
    if (creatorAmounts.isEmpty) {
      _showError('لا توجد بيانات لعرضها');
      return;
    }

    // الانتقال إلى الصفحة الجديدة
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreatorAmountsPage(
          creatorAmounts: creatorAmounts,
          detailedTransactions: allTransactions, // تمرير المعاملات المفصلة
          authToken: widget.authToken, // تمرير الرمز المميز للمصادقة
          onFilterByCreator: (creatorName, showWithoutUser) {
            if (!mounted) return;
            setState(() {
              transactionUser = creatorName;
              showTransactionsWithoutUser = showWithoutUser;
            });
            _loadTransactions(isRefresh: true);
          },
        ),
      ),
    );
  }

  // الشريط السفلي الموحد (التنقل + الخدمات + الإحصائيات)
  Widget _buildUnifiedBottomBar() {
    final totalPages = _getTotalPages();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: Colors.black,
          width: 2,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // شريط الخدمات القابل للإظهار/الإخفاء مع تأثير انزلاق
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            height: showServicesBar ? null : 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: showServicesBar ? 1.0 : 0.0,
              child: showServicesBar
                  ? Column(
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            // إجمالي المعاملات
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.receipt_long,
                                      color: Colors.black,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'إجمالي المعاملات',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          _formatCurrency(totalCount),
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            // بطاقات الخدمات
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _buildServiceCard(
                                        'FIBER 35',
                                        _getServiceTransactionCount(
                                            'FIBER 35')),
                                  ),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: _buildServiceCard(
                                        'FIBER 50',
                                        _getServiceTransactionCount(
                                            'FIBER 50')),
                                  ),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: _buildServiceCard(
                                        'FIBER 75',
                                        _getServiceTransactionCount(
                                            'FIBER 75')),
                                  ),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: _buildServiceCard(
                                        'FIBER 150',
                                        _getServiceTransactionCount(
                                            'FIBER 150')),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),

          // شريط التنقل (يظهر فقط إذا كان هناك أكثر من صفحة واحدة)
          if (totalPages > 1) ...[
            SizedBox(height: showServicesBar ? 6 : 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  // معلومات الصفحة
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'الصفحة $currentPage من $totalPages',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        'معروض: ${transactions.length} | حجم الصفحة: $pageSize',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.black.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // أزرار التنقل
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // زر الصفحة الأولى
                      _buildNavigationButton(
                        icon: Icons.first_page,
                        label: 'الأولى',
                        onPressed: currentPage > 1 ? () => _goToPage(1) : null,
                        color: Colors.grey[200]!,
                      ),
                      // زر الصفحة السابقة
                      _buildNavigationButton(
                        icon: Icons.arrow_back_ios,
                        label: 'السابق',
                        onPressed: currentPage > 1 ? _previousPage : null,
                        color: Colors.orange[200]!,
                      ),
                      // أرقام الصفحات المجاورة
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ..._buildCompactPageNumbers(),
                            const SizedBox(width: 6),
                            // زر إظهار/إخفاء الخدمات
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  showServicesBar = !showServicesBar;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blue[400]!,
                                      Colors.blue[300]!
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      showServicesBar ? 'إخفاء' : 'إظهار',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    AnimatedRotation(
                                      turns: showServicesBar ? 0.5 : 0.0,
                                      duration:
                                          const Duration(milliseconds: 300),
                                      child: const Icon(
                                        Icons.keyboard_arrow_up,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // زر الصفحة التالية
                      _buildNavigationButton(
                        icon: Icons.arrow_forward_ios,
                        label: 'التالي',
                        onPressed: currentPage < totalPages ? _nextPage : null,
                        color: Colors.green[200]!,
                      ),
                      // زر الصفحة الأخيرة
                      _buildNavigationButton(
                        icon: Icons.last_page,
                        label: 'الأخيرة',
                        onPressed: currentPage < totalPages
                            ? () => _goToPage(totalPages)
                            : null,
                        color: Colors.grey[200]!,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // دالة مساعدة لبناء أزرار التنقل المضغوطة
  Widget _buildNavigationButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: onPressed != null ? 0.9 : 0.3),
        foregroundColor: const Color(0xFF1A237E),
        disabledBackgroundColor: Colors.grey.withValues(alpha: 0.2),
        disabledForegroundColor: Colors.grey.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        minimumSize: const Size(50, 28),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // أرقام الصفحات مضغوطة للشريط السفلي
  List<Widget> _buildCompactPageNumbers() {
    final totalPages = _getTotalPages();
    List<Widget> pageButtons = [];

    int startPage = (currentPage - 1).clamp(1, totalPages);
    int endPage = (currentPage + 1).clamp(1, totalPages);

    for (int i = startPage; i <= endPage; i++) {
      pageButtons.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: ElevatedButton(
            onPressed: i != currentPage ? () => _goToPage(i) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  i == currentPage ? Colors.blue[600] : Colors.grey[300],
              foregroundColor:
                  i == currentPage ? Colors.white : const Color(0xFF1A237E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.all(4),
              minimumSize: const Size(24, 24),
            ),
            child: Text(
              '$i',
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    i == currentPage ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }

    return pageButtons;
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
              Text('جاري تصدير البيانات...'),
            ],
          ),
        ),
      );

      // جلب جميع البيانات
      List<Map<String, dynamic>> allTransactions = [];
      int totalPages = _getTotalPages();

      for (int page = 1; page <= totalPages; page++) {
        // تحديث الصفحة المؤقت للحصول على البيانات الصحيحة
        int tempCurrentPage = currentPage;
        currentPage = page;
        String url = _buildFilteredUrl();
        currentPage = tempCurrentPage; // إعادة القيمة الأصلية

        final response = await AuthService.instance.authenticatedRequest(
          'GET',
          url,
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          allTransactions
              .addAll(List<Map<String, dynamic>>.from(data['items'] ?? []));
        }
      }

      // إنشاء ملف Excel
      var excel = ExcelLib.Excel.createExcel();
      ExcelLib.Sheet sheetObject = excel['التحويلات'];

      // إضافة العناوين
      sheetObject.cell(ExcelLib.CellIndex.indexByString("A1")).value =
          ExcelLib.TextCellValue('معرف المعاملة');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("B1")).value =
          ExcelLib.TextCellValue('نوع المعاملة');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("C1")).value =
          ExcelLib.TextCellValue('المبلغ');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("D1")).value =
          ExcelLib.TextCellValue('العملة');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("E1")).value =
          ExcelLib.TextCellValue('الرصيد المتبقي');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("F1")).value =
          ExcelLib.TextCellValue('التاريخ');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("G1")).value =
          ExcelLib.TextCellValue('المنفذ');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("H1")).value =
          ExcelLib.TextCellValue('العميل');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("I1")).value =
          ExcelLib.TextCellValue('الزون');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("J1")).value =
          ExcelLib.TextCellValue('الاشتراك');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("K1")).value =
          ExcelLib.TextCellValue('طريقة الدفع');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("L1")).value =
          ExcelLib.TextCellValue('نوع الدفع');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("M1")).value =
          ExcelLib.TextCellValue('الرقم التسلسلي');
      sheetObject.cell(ExcelLib.CellIndex.indexByString("N1")).value =
          ExcelLib.TextCellValue('نوع التغيير');

      // تنسيق العناوين
      for (int col = 0; col < 14; col++) {
        var cell = sheetObject.cell(
            ExcelLib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
        cell.cellStyle = ExcelLib.CellStyle(
          bold: true,
          backgroundColorHex: ExcelLib.ExcelColor.blue,
          fontColorHex: ExcelLib.ExcelColor.white,
        );
      }

      // إضافة البيانات
      for (int i = 0; i < allTransactions.length; i++) {
        var transaction = allTransactions[i];
        int row = i + 2; // البداية من الصف الثاني

        sheetObject.cell(ExcelLib.CellIndex.indexByString("A$row")).value =
            ExcelLib.TextCellValue(transaction['id']?.toString() ?? '');
        sheetObject.cell(ExcelLib.CellIndex.indexByString("B$row")).value =
            ExcelLib.TextCellValue(
                _translateTransactionType(transaction['type'] ?? ''));
        sheetObject.cell(ExcelLib.CellIndex.indexByString("C$row")).value =
            ExcelLib.DoubleCellValue(
                transaction['transactionAmount']?['value']?.toDouble() ?? 0.0);
        sheetObject.cell(ExcelLib.CellIndex.indexByString("D$row")).value =
            ExcelLib.TextCellValue(
                transaction['transactionAmount']?['currency'] ?? 'IQD');
        sheetObject.cell(ExcelLib.CellIndex.indexByString("E$row")).value =
            ExcelLib.DoubleCellValue(
                transaction['remainingBalance']?['value']?.toDouble() ?? 0.0);
        sheetObject.cell(ExcelLib.CellIndex.indexByString("F$row")).value =
            ExcelLib.TextCellValue(_formatDate(transaction['occuredAt']));
        sheetObject.cell(ExcelLib.CellIndex.indexByString("G$row")).value =
            ExcelLib.TextCellValue(transaction['createdBy'] ?? '');
        sheetObject.cell(ExcelLib.CellIndex.indexByString("H$row")).value =
            ExcelLib.TextCellValue(
                transaction['customer']?['displayValue'] ?? '');
        sheetObject.cell(ExcelLib.CellIndex.indexByString("I$row")).value =
            ExcelLib.TextCellValue(transaction['zoneId'] ?? '');
        sheetObject.cell(ExcelLib.CellIndex.indexByString("J$row")).value =
            ExcelLib.TextCellValue(
                transaction['subscription']?['displayValue'] ?? '');
        sheetObject.cell(ExcelLib.CellIndex.indexByString("K$row")).value =
            ExcelLib.TextCellValue(transaction['paymentMode'] ?? '');
        sheetObject.cell(ExcelLib.CellIndex.indexByString("L$row")).value =
            ExcelLib.TextCellValue(
                transaction['paymentMethod']?['displayValue'] ?? '');
        sheetObject.cell(ExcelLib.CellIndex.indexByString("M$row")).value =
            ExcelLib.TextCellValue(transaction['serialNumber'] ?? '');
        sheetObject.cell(ExcelLib.CellIndex.indexByString("N$row")).value =
            ExcelLib.TextCellValue(
                _translateChangeType(transaction['changeType'] ?? ''));
      }

      // حفظ الملف
      Directory? directory;
      if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      String fileName =
          'التحويلات_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}.xlsx';
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
                child: Text('تم تصدير ${allTransactions.length} معاملة بنجاح'),
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
            onPressed: () => OpenFile.open(filePath),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'التحويلات',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 20),
            // زر حساب المبالغ حسب المنشأة في الوسط
            Expanded(
              child: Center(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: isCalculatingCreatorAmounts
                        ? null
                        : _calculateCreatorAmounts,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1A237E),
                      disabledBackgroundColor: Colors.grey[300],
                      disabledForegroundColor: Colors.grey[600],
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    icon: isCalculatingCreatorAmounts
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  const Color(0xFF1A237E)),
                            ),
                          )
                        : const Icon(
                            Icons.analytics,
                            size: 20,
                            color: Color(0xFF1A237E),
                          ),
                    label: Text(
                      isCalculatingCreatorAmounts
                          ? 'جاري الحساب...'
                          : 'حساب المبالغ الكلي ',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A237E),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1A237E),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: Icon(
                  Icons.filter_list,
                  color: Colors.white,
                  size: _hasActiveFilters() ? 26 : 24,
                ),
                onPressed: _showFilterDialog,
                tooltip: _hasActiveFilters()
                    ? 'تصفية نشطة - انقر للتعديل'
                    : 'تصفية المعاملات',
              ),
              if (_hasActiveFilters()) ...[
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${_getActiveFiltersCount()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ],
          ),
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: Colors.white),
            onPressed: _navigateToProfitsPage,
            tooltip: 'حساب الارباح',
          ),
          IconButton(
            icon: const Icon(Icons.file_download, color: Colors.white),
            onPressed: _exportToExcel,
            tooltip: 'تصدير إلى Excel',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _loadTransactions(isRefresh: true),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: Column(
        children: [
          // مربع البحث مع القائمة المنسدلة
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                // القائمة المنسدلة لاختيار حقل البحث
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedSearchField,
                      icon:
                          Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                      style:
                          const TextStyle(color: Colors.black87, fontSize: 14),
                      items: searchFieldOptions.map((option) {
                        return DropdownMenuItem<String>(
                          value: option['value'],
                          child: Text(option['label']!),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedSearchField = value!;
                          // إعادة تطبيق البحث مع الحقل الجديد
                          _filterTransactions(searchQuery);
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // مربع البحث
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _filterTransactions,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      hintText: selectedSearchField == 'all'
                          ? 'بحث عن عميل، جهاز، منشئ، خدمة...'
                          : 'بحث في ${searchFieldOptions.firstWhere((o) => o['value'] == selectedSearchField)['label']}...',
                      hintStyle:
                          TextStyle(color: Colors.grey[500], fontSize: 14),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: Colors.grey[600]),
                              onPressed: () {
                                _searchController.clear();
                                _filterTransactions('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Color(0xFF1A237E), width: 2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // عرض عدد النتائج إذا كان هناك بحث
          if (searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'تم العثور على ${filteredTransactions.length} نتيجة',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          // بطاقات الملخص (مجموع المبالغ الموجبة والسالبة) - قابلة للنقر للتصفية
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _buildSummaryCards(),
          ),

          Expanded(
            child: isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: Color(0xFF1A237E),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'جاري تحميل التحويلات...',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                      ],
                    ),
                  )
                : transactions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'لا توجد معاملات متاحة',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'لم يتم العثور على أي معاملات مالية',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : filteredTransactions.isEmpty && searchQuery.isNotEmpty
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
                                  'لا توجد نتائج للبحث',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'جرب كلمات بحث مختلفة',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () => _loadTransactions(isRefresh: true),
                            child: Column(
                              children: [
                                Expanded(
                                  child: ListView.builder(
                                    controller: _scrollController,
                                    itemCount: filteredTransactions.length,
                                    itemBuilder: (context, index) {
                                      return _buildTransactionCard(
                                          filteredTransactions[index]);
                                    },
                                  ),
                                ),
                                // الشريط السفلي الموحد (التنقل + الخدمات)
                                _buildUnifiedBottomBar(),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    // عرض خمس بطاقات في صف واحد: الموجب، السالب، بدون اسم منشئ، المجدولة، وإظهار الكل
    final currency = 'IQD';
    final bool showingAll = !showPositiveOnly &&
        !showNegativeOnly &&
        !showWithoutCreatorOnly &&
        !showScheduledOnly;

    return Row(
      children: [
        // البطاقة الأولى - الموجب (قابلة للضغط)
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                // إعادة تعيين جميع الفلاتر
                showPositiveOnly = !showPositiveOnly;
                if (showPositiveOnly) {
                  showNegativeOnly = false;
                  showWithoutCreatorOnly = false;
                  showScheduledOnly = false;
                }
              });
              // إعادة تحميل البيانات مع الفلتر الجديد
              _loadTransactions(isRefresh: true);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: showPositiveOnly ? Colors.green[100] : Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: showPositiveOnly
                      ? Colors.green[400]!
                      : Colors.green[200]!,
                  width: showPositiveOnly ? 2 : 1,
                ),
                boxShadow: showPositiveOnly
                    ? [
                        BoxShadow(
                          color: Colors.green.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.arrow_circle_up,
                        color: showPositiveOnly
                            ? Colors.green[800]
                            : Colors.green[700],
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'إجمالي الموجب',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: showPositiveOnly
                                ? Colors.green[900]
                                : Colors.green[800],
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (showPositiveOnly)
                        Icon(
                          Icons.check_circle,
                          color: Colors.green[800],
                          size: 14,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_formatCurrency(positiveSum)} $currency',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color:
                          showPositiveOnly ? Colors.green[800] : Colors.green,
                    ),
                  ),
                  Text(
                    '$positiveCount عملية',
                    style: TextStyle(
                      fontSize: 12,
                      color: showPositiveOnly
                          ? Colors.green[700]
                          : Colors.green[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  isLoadingAllTotals
                      ? Row(
                          children: const [
                            SizedBox(
                                width: 12,
                                height: 12,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 4),
                            Expanded(
                                child: Text('جاري الحساب...',
                                    style: TextStyle(fontSize: 9))),
                          ],
                        )
                      : Text(
                          'الكل: ${_formatCurrency(positiveSumAll)} ($positiveCountAll عملية)',
                          style:
                              TextStyle(fontSize: 9, color: Colors.green[700]),
                        ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),

        // البطاقة الثانية - السالب (قابلة للضغط)
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                // إعادة تعيين جميع الفلاتر
                showNegativeOnly = !showNegativeOnly;
                if (showNegativeOnly) {
                  showPositiveOnly = false;
                  showWithoutCreatorOnly = false;
                  showScheduledOnly = false;
                }
              });
              // إعادة تحميل البيانات مع الفلتر الجديد
              _loadTransactions(isRefresh: true);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: showNegativeOnly ? Colors.red[100] : Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: showNegativeOnly ? Colors.red[400]! : Colors.red[200]!,
                  width: showNegativeOnly ? 2 : 1,
                ),
                boxShadow: showNegativeOnly
                    ? [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.arrow_circle_down,
                        color: showNegativeOnly
                            ? Colors.red[800]
                            : Colors.red[700],
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'إجمالي السالب',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: showNegativeOnly
                                ? Colors.red[900]
                                : Colors.red[800],
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (showNegativeOnly)
                        Icon(
                          Icons.check_circle,
                          color: Colors.red[800],
                          size: 14,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_formatCurrency(negativeSum.abs())} $currency',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: showNegativeOnly ? Colors.red[800] : Colors.red,
                    ),
                  ),
                  Text(
                    '$negativeCount عملية',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          showNegativeOnly ? Colors.red[700] : Colors.red[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  isLoadingAllTotals
                      ? Row(
                          children: const [
                            SizedBox(
                                width: 12,
                                height: 12,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 4),
                            Expanded(
                                child: Text('جاري الحساب...',
                                    style: TextStyle(fontSize: 9))),
                          ],
                        )
                      : Text(
                          'الكل: ${_formatCurrency(negativeSumAll.abs())} ($negativeCountAll عملية)',
                          style: TextStyle(fontSize: 9, color: Colors.red[700]),
                        ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),

        // البطاقة الثالثة - السالب بدون اسم منشئ (قابلة للضغط)
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                // إعادة تعيين جميع الفلاتر
                showWithoutCreatorOnly = !showWithoutCreatorOnly;
                if (showWithoutCreatorOnly) {
                  showPositiveOnly = false;
                  showNegativeOnly = false;
                  showScheduledOnly = false;
                }
              });
              // إعادة تحميل البيانات مع الفلتر الجديد
              _loadTransactions(isRefresh: true);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    showWithoutCreatorOnly ? Colors.blue[100] : Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: showWithoutCreatorOnly
                      ? Colors.blue[400]!
                      : Colors.blue[200]!,
                  width: showWithoutCreatorOnly ? 2 : 1,
                ),
                boxShadow: showWithoutCreatorOnly
                    ? [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.person_off,
                        color: showWithoutCreatorOnly
                            ? Colors.blue[800]
                            : Colors.blue[700],
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'بدون منشئ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: showWithoutCreatorOnly
                                ? Colors.blue[900]
                                : Colors.blue[800],
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (showWithoutCreatorOnly)
                        Icon(
                          Icons.check_circle,
                          color: Colors.blue[800],
                          size: 14,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_formatCurrency(negativeSumWithoutCreator.abs())} $currency',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: showWithoutCreatorOnly
                          ? Colors.blue[800]
                          : Colors.blue[700],
                    ),
                  ),
                  Text(
                    '$withoutCreatorCount عملية',
                    style: TextStyle(
                      fontSize: 12,
                      color: showWithoutCreatorOnly
                          ? Colors.blue[700]
                          : Colors.blue[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  isLoadingAllTotals
                      ? Row(
                          children: const [
                            SizedBox(
                                width: 12,
                                height: 12,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 4),
                            Expanded(
                                child: Text('جاري الحساب...',
                                    style: TextStyle(fontSize: 9))),
                          ],
                        )
                      : Text(
                          'الكل: ${_formatCurrency(negativeSumWithoutCreatorAll.abs())} ($withoutCreatorCountAll عملية)',
                          style:
                              TextStyle(fontSize: 9, color: Colors.blue[700]),
                        ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),

        // البطاقة الرابعة - العمليات المجدولة (قابلة للضغط)
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                // إعادة تعيين جميع الفلاتر
                showScheduledOnly = !showScheduledOnly;
                if (showScheduledOnly) {
                  showPositiveOnly = false;
                  showNegativeOnly = false;
                  showWithoutCreatorOnly = false;
                }
              });
              // إعادة تحميل البيانات مع الفلتر الجديد
              _loadTransactions(isRefresh: true);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    showScheduledOnly ? Colors.orange[100] : Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: showScheduledOnly
                      ? Colors.orange[400]!
                      : Colors.orange[200]!,
                  width: showScheduledOnly ? 2 : 1,
                ),
                boxShadow: showScheduledOnly
                    ? [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        color: showScheduledOnly
                            ? Colors.orange[800]
                            : Colors.orange[700],
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'مجدولة',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: showScheduledOnly
                                ? Colors.orange[900]
                                : Colors.orange[800],
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (showScheduledOnly)
                        Icon(
                          Icons.check_circle,
                          color: Colors.orange[800],
                          size: 14,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_formatCurrency(scheduledSum.abs())} $currency',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: showScheduledOnly
                          ? Colors.orange[800]
                          : Colors.orange[700],
                    ),
                  ),
                  Text(
                    '$scheduledCount عملية',
                    style: TextStyle(
                      fontSize: 12,
                      color: showScheduledOnly
                          ? Colors.orange[700]
                          : Colors.orange[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  isLoadingAllTotals
                      ? Row(
                          children: const [
                            SizedBox(
                                width: 12,
                                height: 12,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 4),
                            Expanded(
                                child: Text('جاري الحساب...',
                                    style: TextStyle(fontSize: 9))),
                          ],
                        )
                      : Text(
                          'الكل: ${_formatCurrency(scheduledSumAll.abs())} ($scheduledCountAll عملية)',
                          style:
                              TextStyle(fontSize: 9, color: Colors.orange[700]),
                        ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),

        // البطاقة الخامسة - إظهار الكل (قابلة للضغط)
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                // إعادة تعيين جميع الفلاتر لإظهار الكل
                showPositiveOnly = false;
                showNegativeOnly = false;
                showWithoutCreatorOnly = false;
                showScheduledOnly = false;
              });
              // إعادة تحميل البيانات مع الفلتر الجديد
              _loadTransactions(isRefresh: true);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: showingAll ? Colors.grey[100] : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: showingAll ? Colors.grey[400]! : Colors.grey[200]!,
                  width: showingAll ? 2 : 1,
                ),
                boxShadow: showingAll
                    ? [
                        BoxShadow(
                          color: Colors.grey.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.visibility,
                        color: showingAll ? Colors.grey[800] : Colors.grey[700],
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'إظهار الكل',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: showingAll
                                ? Colors.grey[900]
                                : Colors.grey[800],
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (showingAll)
                        Icon(
                          Icons.check_circle,
                          color: Colors.grey[800],
                          size: 14,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_formatCurrency(totalCount)} معاملة',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: showingAll ? Colors.grey[800] : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'جميع المعاملات',
                    style: TextStyle(fontSize: 9, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'اضغط لإلغاء التصفية',
                    style: TextStyle(
                      fontSize: 9,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // دالة لحساب عدد المعاملات لخدمة معينة
  int _getServiceTransactionCount(String serviceName) {
    if (transactions.isEmpty) return 0;

    // طباعة عينة من البيانات للتشخيص (أول 3 معاملات)
    if (transactions.isNotEmpty) {
      debugPrint('=== عينة من البيانات للخدمة $serviceName ===');
      for (int i = 0;
          i < (transactions.length < 3 ? transactions.length : 3);
          i++) {
        final transaction = transactions[i];
        debugPrint('المعاملة $i:');
        debugPrint('  - type: ${transaction['type']}');
        debugPrint('  - description: ${transaction['description']}');

        final subscription = transaction['subscription'];
        if (subscription != null) {
          debugPrint(
              '  - subscription displayValue: ${subscription['displayValue']}');
          final subscriptionService = subscription['subscriptionService'];
          if (subscriptionService != null) {
            final service = subscriptionService['service'];
            if (service != null) {
              debugPrint('  - service displayValue: ${service['displayValue']}');
            }
          }
        }
        debugPrint('  ---');
      }
    }

    return transactions.where((transaction) {
      // البحث في مسارات البيانات المختلفة

      // 1. البحث في subscription -> subscriptionService -> service -> displayValue
      final subscription = transaction['subscription'];
      if (subscription != null) {
        final subscriptionService = subscription['subscriptionService'];
        if (subscriptionService != null) {
          final service = subscriptionService['service'];
          if (service != null) {
            final serviceDisplayValue = service['displayValue'] ?? '';
            if (serviceDisplayValue
                .toString()
                .toUpperCase()
                .contains(serviceName.toUpperCase())) {
              return true;
            }
          }
        }
      }

      // 2. البحث في subscription -> displayValue مباشرة
      if (subscription != null) {
        final subscriptionDisplayValue = subscription['displayValue'] ?? '';
        if (subscriptionDisplayValue
            .toString()
            .toUpperCase()
            .contains(serviceName.toUpperCase())) {
          return true;
        }
      }

      // 3. البحث في حقول أخرى محتملة
      final description = transaction['description'] ?? '';
      if (description
          .toString()
          .toUpperCase()
          .contains(serviceName.toUpperCase())) {
        return true;
      }

      // 4. البحث بالرقم فقط (35, 50, 75, 150)
      final serviceNumber = serviceName.replaceAll('FIBER ', '');
      if (subscription != null) {
        final subscriptionDisplayValue = subscription['displayValue'] ?? '';
        if (subscriptionDisplayValue.toString().contains(serviceNumber)) {
          return true;
        }
      }

      return false;
    }).length;
  }

  // دالة لبناء مربع الخدمة
  Widget _buildServiceCard(String serviceName, int count) {
    return GestureDetector(
      onTap: () {
        // تطبيق فلتر للخدمة المحددة
        setState(() {
          selectedServiceNames = [serviceName];
        });
        _loadTransactions(isRefresh: true);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              serviceName.replaceAll('FIBER ', ''),
              style: const TextStyle(
                color: Colors.black,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
