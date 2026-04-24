/// صفحة التسديدات اليومية
/// يقوم المشغل بإرسال تقرير يومي (ملاحظات + مبالغ)
/// المحاسب/المدير يرى كشف بكل العمليات
/// مع مقارنة ببيانات الاشتراكات الفعلية من النظام
library;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart' hide TextDirection;

class DailySettlementPage extends StatefulWidget {
  final String authToken;
  final String activatedBy;
  final Map<String, bool>? permissions;

  const DailySettlementPage({
    super.key,
    required this.authToken,
    required this.activatedBy,
    this.permissions,
  });

  @override
  State<DailySettlementPage> createState() => _DailySettlementPageState();
}

class _DailySettlementPageState extends State<DailySettlementPage> {
  static const String _vpsBaseUrl =
      'https://api.ramzalsadara.tech/api/internal';
  static const String _vpsApiKey = 'sadara-internal-2024-secure-key';

  bool isAdmin = false;

  // === Tab 1: إرسال تقرير ===
  bool _reportLoading = false;
  bool _reportSubmitted = false;
  int? _reportId;
  DateTime _selectedDate = DateTime.now();
  final List<Map<String, dynamic>> _items = [];
  final _notesController = TextEditingController();
  final _deliveredToController = TextEditingController();

  // === بيانات الاشتراكات للمقارنة ===
  bool _subsLoading = false;
  List<Map<String, dynamic>> _subscriptionLogs = [];
  double _subsTotalAmount = 0;
  int _subsPurchaseCount = 0;
  double _subsPurchaseTotal = 0;
  int _subsRenewalCount = 0;
  double _subsRenewalTotal = 0;
  // تفصيل حسب نوع التحصيل
  double _subsCashTotal = 0;
  double _subsCreditTotal = 0;
  double _subsMasterTotal = 0;
  double _subsTechTotal = 0;
  double _subsAgentTotal = 0;
  int _subsCashCount = 0;
  int _subsCreditCount = 0;
  int _subsMasterCount = 0;
  int _subsTechCount = 0;
  int _subsAgentCount = 0;

  // أصناف البنود
  static const List<String> _itemCategories = ['مصاريف', 'إضافة أموال', 'أخرى'];


  // === الأيام الناقصة (بدون تقرير) ===
  bool _missingDaysLoading = false;
  List<DateTime> _missingDays = [];

  // === قائمة الموظفين ===
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  bool _showEmployeeDropdown = false;
  String? _selectedDeliveredToId;

  // === Tab 2: كشف العمليات ===
  bool _allLoading = false;
  List<Map<String, dynamic>> _allReports = [];
  DateTime? _filterFrom;
  DateTime? _filterTo;
  String _filterOperator = 'الكل';
  List<String> _operatorNames = ['الكل'];

  @override
  void initState() {
    super.initState();
    _determineAdmin();
    _addEmptyItem();
    _checkReportForDate();
    _loadSubscriptionData();
    _loadMissingDays();
    _loadEmployees();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _deliveredToController.dispose();
    for (final item in _items) {
      (item['noteController'] as TextEditingController?)?.dispose();
      (item['amountController'] as TextEditingController?)?.dispose();
    }
    super.dispose();
  }

  void _determineAdmin() {
    final name = widget.activatedBy.trim().toLowerCase();
    final perms = widget.permissions;
    if (perms != null) {
      isAdmin = (perms['admin'] == true) || (perms['is_admin'] == true);
    }
    if (!isAdmin) {
      isAdmin = name.contains('admin') || name == 'root';
    }
  }

  // ========== HTTP Helpers ==========
  Future<dynamic> _apiGet(String path) async {
    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    final request = await client.getUrl(Uri.parse('$_vpsBaseUrl/$path'));
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Accept', 'application/json');
    request.headers.set('X-Api-Key', _vpsApiKey);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    client.close();
    if (response.statusCode != 200) throw Exception('خطأ: ${response.statusCode}');
    return json.decode(body);
  }

  Future<dynamic> _apiPost(String path, Map<String, dynamic> data) async {
    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    final request = await client.postUrl(Uri.parse('$_vpsBaseUrl/$path'));
    request.headers.set('Content-Type', 'application/json; charset=utf-8');
    request.headers.set('Accept', 'application/json');
    request.headers.set('X-Api-Key', _vpsApiKey);
    request.add(utf8.encode(json.encode(data)));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    client.close();
    return json.decode(body);
  }

  Future<dynamic> _apiDelete(String path) async {
    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    final request = await client.deleteUrl(Uri.parse('$_vpsBaseUrl/$path'));
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Accept', 'application/json');
    request.headers.set('X-Api-Key', _vpsApiKey);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    client.close();
    return json.decode(body);
  }

  // ========== تاريخ مختار ==========
  String get _selectedDateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);
  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  bool get _isYesterday {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return _selectedDate.year == yesterday.year &&
        _selectedDate.month == yesterday.month &&
        _selectedDate.day == yesterday.day;
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _reportSubmitted = false;
      _reportId = null;
      _notesController.clear();
      _deliveredToController.clear();
      _selectedDeliveredToId = null;
      for (final item in _items) {
        (item['noteController'] as TextEditingController?)?.dispose();
        (item['amountController'] as TextEditingController?)?.dispose();
      }
      _items.clear();
      _addEmptyItem();
      _subscriptionLogs.clear();
      _subsTotalAmount = 0;
      _subsPurchaseCount = 0;
      _subsPurchaseTotal = 0;
      _subsRenewalCount = 0;
      _subsRenewalTotal = 0;
    });
    _checkReportForDate();
    _loadSubscriptionData();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      _selectDate(picked);
    }
  }

  // ========== Tab 1: تقرير ==========
  void _addEmptyItem() {
    _items.add({
      'note': '',
      'amount': 0.0,
      'category': '',
      'noteController': TextEditingController(),
      'amountController': TextEditingController(),
    });
  }

  /// إدارة البنود تلقائياً: إضافة بند فارغ عند الكتابة + حذف الفارغ الزائد
  void _autoManageItems() {
    // هل يوجد بند فارغ؟
    bool hasEmpty = false;
    for (int i = _items.length - 1; i >= 0; i--) {
      final amt = ((_items[i]['amountController'] as TextEditingController).text).replaceAll(',', '');
      final note = (_items[i]['noteController'] as TextEditingController).text;
      final isEmpty = amt.isEmpty && note.isEmpty;
      if (isEmpty) {
        if (hasEmpty && _items.length > 1) {
          // بند فارغ زائد — حذفه
          (_items[i]['noteController'] as TextEditingController).dispose();
          (_items[i]['amountController'] as TextEditingController).dispose();
          _items.removeAt(i);
        } else {
          hasEmpty = true;
        }
      }
    }
    // إذا لا يوجد بند فارغ → إضافة واحد
    if (!hasEmpty) {
      _addEmptyItem();
    }
  }

  Future<void> _checkReportForDate() async {
    setState(() => _reportLoading = true);
    try {
      final result = await _apiGet(
          'settlement-reports/check?operatorName=${Uri.encodeComponent(widget.activatedBy)}&date=$_selectedDateStr');
      if (result['submitted'] == true) {
        _reportSubmitted = true;
        _reportId = result['reportId'];
        await _loadReportForDate();
      }
    } catch (e) {
      debugPrint('Error checking report: $e');
    }
    if (mounted) setState(() => _reportLoading = false);
  }

  Future<void> _loadReportForDate() async {
    try {
      final result = await _apiGet(
          'settlement-reports?operatorName=${Uri.encodeComponent(widget.activatedBy)}&fromDate=$_selectedDateStr&toDate=$_selectedDateStr');
      if (result is List && result.isNotEmpty) {
        final report = result.first;
        final rawNotes = report['Notes'] ?? report['notes'] ?? '';
        // استخراج "تم التسليم إلى" من الملاحظات
        if (rawNotes.startsWith('[تسليم:')) {
          final endIdx = rawNotes.indexOf(']');
          if (endIdx > 0) {
            _deliveredToController.text = rawNotes.substring(7, endIdx).trim();
            _notesController.text = rawNotes.substring(endIdx + 1).trim();
          } else {
            _notesController.text = rawNotes;
          }
        } else {
          _notesController.text = rawNotes;
        }
        _reportId = report['Id'] ?? report['id'];
        // استعادة معرف المستلم
        final savedDelId = report['DeliveredToId'] ?? report['deliveredToId'];
        if (savedDelId != null) _selectedDeliveredToId = savedDelId.toString();
        for (final item in _items) {
          (item['noteController'] as TextEditingController?)?.dispose();
          (item['amountController'] as TextEditingController?)?.dispose();
        }
        _items.clear();
        final itemsStr = report['ItemsJson'] ?? report['itemsJson'] ?? '[]';
        final List<dynamic> items = json.decode(itemsStr);
        for (final item in items) {
          _items.add({
            'note': item['note'] ?? '',
            'amount': (item['amount'] ?? 0).toDouble(),
            'category': item['category'] ?? 'مصاريف',
            'noteController': TextEditingController(text: item['note'] ?? ''),
            'amountController': TextEditingController(
                text: (item['amount'] ?? 0) > 0
                    ? NumberFormat('#,###').format((item['amount'] as num).toInt())
                    : ''),
          });
        }
        if (_items.isEmpty) _addEmptyItem();
      }
    } catch (e) {
      debugPrint('Error loading report: $e');
    }
  }

  /// مجموع المصاريف والبنود المضافة
  double get _totalExpenses {
    double total = 0;
    for (final item in _items) {
      if (item['category'] == 'إضافة أموال') continue;
      total += (item['amount'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  /// إجمالي الأموال المضافة (إيرادات خارجية)
  double get _totalExtraIncome {
    double total = 0;
    for (final item in _items) {
      if (item['category'] != 'إضافة أموال') continue;
      total += (item['amount'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  /// النقد الصافي = نقد النظام − المصاريف + إضافة أموال
  double get _netCashAmount => _subsCashTotal - _totalExpenses + _totalExtraIncome;

  double get _totalAmount {
    double total = 0;
    for (final item in _items) {
      total += (item['amount'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  Future<void> _submitReport() async {
    // التحقق من حقل التسليم
    final deliveredTo = _deliveredToController.text.trim();
    if (deliveredTo.isEmpty) {
      _showSnackBar('يجب كتابة اسم مستلم المبلغ (تم التسليم إلى)', isError: true);
      return;
    }

    for (final item in _items) {
      item['note'] = (item['noteController'] as TextEditingController).text;
      final amtText = (item['amountController'] as TextEditingController).text.replaceAll(',', '');
      item['amount'] = double.tryParse(amtText) ?? 0;
    }
    final validItems = _items
        .where((i) => (i['note'] as String).isNotEmpty || (i['amount'] as num) > 0)
        .map((i) => {'note': i['note'], 'amount': i['amount'], 'category': i['category'] ?? ''})
        .toList();

    // تضمين اسم المستلم في الملاحظات
    final notesWithDelivery = '[تسليم:$deliveredTo]${_notesController.text}'.trim();

    setState(() => _reportLoading = true);
    try {
      // البحث عن معرف المشغل من قائمة الموظفين
      final operatorEntry = _employees.cast<Map<String, dynamic>?>().firstWhere(
          (e) => e!['name'] == widget.activatedBy, orElse: () => null);
      final operatorUserId = operatorEntry?['id'];
      final operatorCompanyId = operatorEntry?['companyId'];

      final result = await _apiPost('settlement-reports', {
        'reportDate': _selectedDateStr,
        'operatorName': widget.activatedBy,
        'operatorId': operatorUserId,
        'companyId': operatorCompanyId,
        'notes': notesWithDelivery,
        'items': validItems,
        'deliveredToId': _selectedDeliveredToId,
        'deliveredToName': deliveredTo,
        // تفاصيل النظام
        'systemTotal': _subsTotalAmount,
        'systemCashTotal': _subsCashTotal,
        'systemCreditTotal': _subsCreditTotal,
        'systemMasterTotal': _subsMasterTotal,
        'systemTechTotal': _subsTechTotal,
        'systemAgentTotal': _subsAgentTotal,
        'systemCashCount': _subsCashCount,
        'systemCreditCount': _subsCreditCount,
        'systemMasterCount': _subsMasterCount,
        'systemTechCount': _subsTechCount,
        'systemAgentCount': _subsAgentCount,
        // المبالغ المحسوبة
        'totalExpenses': _totalExpenses,
        'totalExtraIncome': _totalExtraIncome,
        'netCashAmount': _netCashAmount,
      });
      if (result['success'] == true) {
        _reportSubmitted = true;
        _reportId = result['id'];
        final isUpdate = result['updated'] == true;
        _showSnackBar(isUpdate ? 'تم تحديث التقرير بنجاح' : 'تم إرسال التقرير بنجاح');
        _loadMissingDays();
      } else {
        _showSnackBar(result['message'] ?? 'فشل الإرسال', isError: true);
      }
    } catch (e) {
      _showSnackBar('خطأ: $e', isError: true);
    }
    if (mounted) setState(() => _reportLoading = false);
  }

  // ========== جلب بيانات الاشتراكات للمقارنة ==========
  Future<void> _loadSubscriptionData() async {
    setState(() => _subsLoading = true);
    try {
      final client = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      final request = await client.getUrl(Uri.parse('$_vpsBaseUrl/subscriptionlogs'));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      request.headers.set('X-Api-Key', _vpsApiKey);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 200) throw Exception('خطأ: ${response.statusCode}');
      final List<dynamic> allLogs = json.decode(body) is List ? json.decode(body) : [];

      // تصفية حسب التاريخ المختار + اسم المشغل (إذا غير مدير)
      final selectedDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final filtered = <Map<String, dynamic>>[];
      for (final item in allLogs) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);

        // تصفية بالتاريخ
        final actDate = m['ActivationDate']?.toString() ?? '';
        if (actDate.isEmpty) continue;
        DateTime? recordDate;
        try {
          recordDate = DateTime.parse(actDate);
        } catch (_) {
          continue;
        }
        final dayOnly = DateTime(recordDate.year, recordDate.month, recordDate.day);
        if (dayOnly != selectedDay) continue;

        // تصفية بالمشغل (غير المدير يرى سجلاته فقط)
        if (!isAdmin) {
          final activatedBy = (m['ActivatedBy'] ?? '').toString().trim().toLowerCase();
          if (activatedBy != widget.activatedBy.trim().toLowerCase()) continue;
        }

        filtered.add(m);
      }

      _subscriptionLogs = filtered;

      // حساب الإحصائيات
      double totalAmt = 0;
      int purchaseCount = 0;
      double purchaseTotal = 0;
      int renewalCount = 0;
      double renewalTotal = 0;
      // تفصيل حسب نوع التحصيل
      double cashT = 0, creditT = 0, masterT = 0, techT = 0, agentT = 0;
      int cashC = 0, creditC = 0, masterC = 0, techC = 0, agentC = 0;

      for (final m in filtered) {
        final price = (m['PlanPrice'] as num?)?.toDouble() ?? 0;
        totalAmt += price;

        final opType = (m['OperationType'] ?? '').toString().toLowerCase();
        if (opType == 'purchase' || opType.contains('شراء')) {
          purchaseCount++;
          purchaseTotal += price;
        } else {
          renewalCount++;
          renewalTotal += price;
        }

        // تصنيف حسب نوع التحصيل
        final colType = (m['CollectionType'] ?? 'cash').toString().toLowerCase();
        switch (colType) {
          case 'credit':
            creditT += price; creditC++;
            break;
          case 'master':
            masterT += price; masterC++;
            break;
          case 'technician':
            techT += price; techC++;
            break;
          case 'agent':
            agentT += price; agentC++;
            break;
          default:
            cashT += price; cashC++;
        }
      }

      _subsTotalAmount = totalAmt;
      _subsPurchaseCount = purchaseCount;
      _subsPurchaseTotal = purchaseTotal;
      _subsRenewalCount = renewalCount;
      _subsRenewalTotal = renewalTotal;
      _subsCashTotal = cashT; _subsCashCount = cashC;
      _subsCreditTotal = creditT; _subsCreditCount = creditC;
      _subsMasterTotal = masterT; _subsMasterCount = masterC;
      _subsTechTotal = techT; _subsTechCount = techC;
      _subsAgentTotal = agentT; _subsAgentCount = agentC;
    } catch (e) {
      debugPrint('Error loading subscription data: $e');
    }
    if (mounted) setState(() => _subsLoading = false);
  }

  // ========== الأيام الناقصة (بدون تقرير) ==========
  Future<void> _loadMissingDays() async {
    setState(() => _missingDaysLoading = true);
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final checkDays = 30;
      final missing = <DateTime>[];

      // جلب كل تقارير المشغل في آخر 30 يوم
      final fromDate = today.subtract(Duration(days: checkDays));
      final result = await _apiGet(
          'settlement-reports?operatorName=${Uri.encodeComponent(widget.activatedBy)}&fromDate=${DateFormat('yyyy-MM-dd').format(fromDate)}&toDate=${DateFormat('yyyy-MM-dd').format(today)}');

      final submittedDates = <String>{};
      if (result is List) {
        for (final r in result) {
          final date = (r['ReportDate'] ?? r['reportDate'])?.toString() ?? '';
          if (date.isNotEmpty) {
            try {
              final dt = DateTime.parse(date);
              submittedDates.add(DateFormat('yyyy-MM-dd').format(dt));
            } catch (_) {}
          }
        }
      }

      // التحقق من كل يوم (ما عدا الجمعة - عطلة)
      for (int i = 1; i <= checkDays; i++) {
        final day = today.subtract(Duration(days: i));
        if (day.weekday == DateTime.friday) continue; // تخطي الجمعة
        final dayStr = DateFormat('yyyy-MM-dd').format(day);
        if (!submittedDates.contains(dayStr)) {
          missing.add(day);
        }
      }

      _missingDays = missing;
    } catch (e) {
      debugPrint('Error loading missing days: $e');
    }
    if (mounted) setState(() => _missingDaysLoading = false);
  }

  // ========== جلب قائمة الموظفين ==========
  Future<void> _loadEmployees() async {
    try {
      final result = await _apiGet('users');
      if (result is List) {
        final seen = <String>{};
        final list = <Map<String, dynamic>>[];
        for (final u in result) {
          final name = (u['FullName'] ?? u['fullName'] ?? '').toString().trim();
          final id = (u['Id'] ?? u['id'] ?? '').toString();
          if (name.isNotEmpty && seen.add(name)) {
            list.add({'name': name, 'id': id, 'companyId': (u['CompanyId'] ?? u['companyId'] ?? '').toString()});
          }
        }
        list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
        if (mounted) {
          setState(() {
            _employees = list;
            _filteredEmployees = list;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading employees: $e');
    }
  }

  void _filterEmployeeList(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredEmployees = _employees;
      } else {
        _filteredEmployees = _employees
            .where((e) => (e['name'] as String).contains(query))
            .toList();
      }
    });
  }

  // ========== Tab 2: كشف العمليات ==========
  Future<void> _loadAllReports() async {
    setState(() => _allLoading = true);
    try {
      String path = 'settlement-reports?pageSize=2000';
      if (_filterFrom != null) path += '&fromDate=${DateFormat('yyyy-MM-dd').format(_filterFrom!)}';
      if (_filterTo != null) path += '&toDate=${DateFormat('yyyy-MM-dd').format(_filterTo!)}';
      if (_filterOperator != 'الكل') path += '&operatorName=${Uri.encodeComponent(_filterOperator)}';
      final result = await _apiGet(path);
      if (result is List) {
        _allReports = result.map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r)).toList();
        final names = <String>{'الكل'};
        for (final r in _allReports) {
          final name = (r['OperatorName'] ?? r['operatorName'])?.toString() ?? '';
          if (name.isNotEmpty) names.add(name);
        }
        _operatorNames = names.toList();
      }
    } catch (e) {
      _showSnackBar('خطأ في جلب التقارير: $e', isError: true);
    }
    if (mounted) setState(() => _allLoading = false);
  }

  Future<void> _deleteReport(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف التقرير', textDirection: TextDirection.rtl),
        content: const Text('هل أنت متأكد من حذف هذا التقرير؟', textDirection: TextDirection.rtl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _apiDelete('settlement-reports/$id');
      _showSnackBar('تم حذف التقرير');
      _loadAllReports();
    } catch (e) {
      _showSnackBar('خطأ: $e', isError: true);
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, textDirection: TextDirection.rtl),
      backgroundColor: isError ? Colors.red : Colors.green,
      duration: const Duration(seconds: 2),
    ));
  }

  // ========== UI ==========
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          title: const Text('التسديدات اليومية',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          toolbarHeight: 46,
          actions: [
            _buildAppBarDateButton('اليوم', _isToday, () => _selectDate(DateTime.now())),
            _buildAppBarDateButton('الأمس', _isYesterday, () => _selectDate(DateTime.now().subtract(const Duration(days: 1)))),
            IconButton(
              onPressed: _pickDate,
              icon: Icon(
                Icons.date_range,
                size: 20,
                color: (!_isToday && !_isYesterday) ? Colors.amber : Colors.white70,
              ),
              tooltip: (!_isToday && !_isYesterday)
                  ? DateFormat('yyyy/MM/dd').format(_selectedDate)
                  : 'تاريخ آخر',
            ),
            _buildMissingDaysButton(),
            if (isAdmin)
              IconButton(
                onPressed: () {
                  if (_allReports.isEmpty) _loadAllReports();
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => Directionality(
                      textDirection: TextDirection.rtl,
                      child: Container(
                        height: MediaQuery.of(context).size.height * 0.85,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.receipt_long, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  const Text('كشف العمليات', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  IconButton(
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(child: _buildAllReportsTab()),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.receipt_long, size: 20),
                tooltip: 'كشف العمليات',
              ),
          ],
        ),
        body: GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            if (_showEmployeeDropdown) setState(() => _showEmployeeDropdown = false);
          },
          behavior: HitTestBehavior.translucent,
          child: _buildMyReportTab(),
        ),
      ),
    );
  }

  // ========== Tab 1: إرسال تقرير ==========
  Widget _buildMyReportTab() {
    if (_reportLoading && _items.length <= 1 && !_reportSubmitted) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // المحتوى
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // بيانات النظام (شريط ملون)
                _buildSystemStatsBar(),
                const SizedBox(height: 12),

                // جدول البنود والملاحظات
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black87, width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // صف العناوين
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.shade50,
                          border: Border(bottom: BorderSide(color: Colors.black87, width: 1.5)),
                        ),
                        padding: EdgeInsets.symmetric(
                          vertical: (Platform.isAndroid || Platform.isIOS || MediaQuery.of(context).size.width < 600) ? 6 : 10,
                          horizontal: (Platform.isAndroid || Platform.isIOS || MediaQuery.of(context).size.width < 600) ? 6 : 10,
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              SizedBox(
                                width: (Platform.isAndroid || Platform.isIOS || MediaQuery.of(context).size.width < 600) ? 22 : 28,
                                child: Center(
                                  child: Text('ت', style: TextStyle(color: Colors.deepPurple.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              VerticalDivider(width: 6, thickness: 1.5, color: Colors.black87),
                              Expanded(
                                flex: 2,
                                child: Center(
                                  child: Text('المبلغ', style: TextStyle(color: Colors.deepPurple.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              VerticalDivider(width: 6, thickness: 1.5, color: Colors.black87),
                              Expanded(
                                flex: 2,
                                child: Center(
                                  child: Text('الصنف', style: TextStyle(color: Colors.deepPurple.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              VerticalDivider(width: 6, thickness: 1.5, color: Colors.black87),
                              Expanded(
                                flex: 3,
                                child: Center(
                                  child: Text('التفاصيل', style: TextStyle(color: Colors.deepPurple.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // صفوف البنود
                      ...List.generate(_items.length, (i) => Container(
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: Colors.grey.shade400, width: 1.2)),
                        ),
                        child: _buildItemRow(i),
                      )),
                      // ملاحظات عامة
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          border: Border(top: BorderSide(color: Colors.black87, width: 1.5)),
                        ),
                        child: TextField(
                          controller: _notesController,
                          maxLines: 1,
                          decoration: InputDecoration(
                            hintText: 'ملاحظات عامة...',
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            prefixIcon: Icon(Icons.notes, color: Colors.grey.shade400, size: 20),
                            filled: true,
                            fillColor: Colors.transparent,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // صف الإجمالي
                _buildTotalRow(),
                const SizedBox(height: 10),

                // تم التسليم إلى + زر الإرسال في صف واحد
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // حقل التسليم
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _deliveredToController,
                            onChanged: (val) {
                              _filterEmployeeList(val);
                              setState(() => _showEmployeeDropdown = true);
                            },
                            onTap: () {
                              _filterEmployeeList(_deliveredToController.text);
                              setState(() => _showEmployeeDropdown = true);
                            },
                            decoration: InputDecoration(
                              hintText: 'تم التسليم إلى...',
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              prefixIcon: Icon(Icons.person_pin, color: Colors.deepPurple.shade400, size: 20),
                              suffixIcon: _deliveredToController.text.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.clear, color: Colors.grey.shade500, size: 18),
                                      onPressed: () {
                                        _deliveredToController.clear();
                                        _selectedDeliveredToId = null;
                                        setState(() {
                                          _filteredEmployees = _employees;
                                          _showEmployeeDropdown = false;
                                        });
                                      },
                                    )
                                  : Icon(Icons.arrow_drop_down, color: Colors.grey.shade500),
                              filled: true,
                              fillColor: Colors.white,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: Colors.red.shade200)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: Colors.red.shade200)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Colors.deepPurple, width: 1.5)),
                            ),
                          ),
                          if (_showEmployeeDropdown && _filteredEmployees.isNotEmpty)
                            Container(
                              constraints: const BoxConstraints(maxHeight: 160),
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.deepPurple.shade200),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 3))],
                              ),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: _filteredEmployees.length,
                                itemBuilder: (ctx, i) {
                                  final emp = _filteredEmployees[i];
                                  final name = emp['name'] as String;
                                  return ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: Colors.deepPurple.shade50,
                                      child: Text(name.isNotEmpty ? name[0] : '?',
                                          style: TextStyle(color: Colors.deepPurple.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
                                    ),
                                    title: Text(name, style: const TextStyle(fontSize: 13)),
                                    onTap: () {
                                      _deliveredToController.text = name;
                                      _selectedDeliveredToId = emp['id'] as String?;
                                      setState(() => _showEmployeeDropdown = false);
                                    },
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // زر الإرسال
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: _reportLoading ? null : _submitReport,
                          icon: _reportLoading
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Icon(_reportSubmitted ? Icons.update : Icons.send, size: 20),
                          label: Text(
                            _reportSubmitted ? 'تحديث' : 'إرسال التقرير',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _reportSubmitted ? Colors.orange : Colors.deepPurple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // زر تاريخ في الشريط العلوي
  Widget _buildAppBarDateButton(String label, bool isSelected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withOpacity(0.25) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? Border.all(color: Colors.white70, width: 1) : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  // حالة التقرير
  Widget _buildStatusBanner() {
    if (_reportSubmitted) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          border: Border(bottom: BorderSide(color: Colors.green.shade200)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'تم إرسال التقرير  (الإجمالي: ${NumberFormat('#,###').format(_totalAmount)} د.ع)',
                style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _isToday ? Colors.red.shade50 : Colors.orange.shade50,
        border: Border(bottom: BorderSide(color: _isToday ? Colors.red.shade200 : Colors.orange.shade200)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: _isToday ? Colors.red.shade700 : Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isToday
                  ? 'لم تُرسل تقرير التسديدات لهذا اليوم بعد'
                  : 'لا يوجد تقرير لتاريخ ${DateFormat('yyyy/MM/dd').format(_selectedDate)}',
              style: TextStyle(
                  color: _isToday ? Colors.red.shade800 : Colors.orange.shade800,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // شريط الإحصائيات الملون (نمط صفحة السجلات)
  Widget _buildSystemStatsBar() {
    if (_subsLoading) {
      return const SizedBox(height: 50, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // صف 1: إجمالي + تفصيل حسب نوع التحصيل
        final fmt = NumberFormat('#,###');
        final row1 = [
          _statBarCard('إجمالي العمليات', fmt.format(_subsTotalAmount),
              '${_subscriptionLogs.length} عملية', [const Color(0xFF880E4F), const Color(0xFFAD1457)], Icons.receipt_long),
          _statBarCard('نقد', fmt.format(_subsCashTotal),
              '$_subsCashCount عملية', [const Color(0xFF2E7D32), const Color(0xFF43A047)], Icons.attach_money),
          _statBarCard('آجل', fmt.format(_subsCreditTotal),
              '$_subsCreditCount عملية', [const Color(0xFFE65100), const Color(0xFFEF6C00)], Icons.access_time),
          _statBarCard('ماستر', fmt.format(_subsMasterTotal),
              '$_subsMasterCount عملية', [const Color(0xFF4A148C), const Color(0xFF7B1FA2)], Icons.credit_card),
          _statBarCard('وكيل', fmt.format(_subsAgentTotal),
              '$_subsAgentCount عملية', [const Color(0xFF1565C0), const Color(0xFF1E88E5)], Icons.storefront),
          _statBarCard('فني', fmt.format(_subsTechTotal),
              '$_subsTechCount عملية', [const Color(0xFF00695C), const Color(0xFF00897B)], Icons.engineering),
        ];

        if (constraints.maxWidth < 600) {
          // موبايل: شبكة 3×2 متساوية مضغوطة
          Widget cCard(String t, String amt, String sub, List<Color> clrs, IconData ic) =>
              _statBarCard(t, amt, sub, clrs, ic, compact: true);
          Widget pair(Widget a, Widget b) => IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: a), const SizedBox(width: 4), Expanded(child: b),
                ]),
              );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pair(
                cCard('الإجمالي', fmt.format(_subsTotalAmount), '${_subscriptionLogs.length} عملية', [const Color(0xFF880E4F), const Color(0xFFAD1457)], Icons.receipt_long),
                cCard('نقد', fmt.format(_subsCashTotal), '$_subsCashCount عملية', [const Color(0xFF2E7D32), const Color(0xFF43A047)], Icons.attach_money),
              ),
              const SizedBox(height: 4),
              pair(
                cCard('آجل', fmt.format(_subsCreditTotal), '$_subsCreditCount عملية', [const Color(0xFFE65100), const Color(0xFFEF6C00)], Icons.access_time),
                cCard('ماستر', fmt.format(_subsMasterTotal), '$_subsMasterCount عملية', [const Color(0xFF4A148C), const Color(0xFF7B1FA2)], Icons.credit_card),
              ),
              const SizedBox(height: 4),
              pair(
                cCard('وكيل', fmt.format(_subsAgentTotal), '$_subsAgentCount عملية', [const Color(0xFF1565C0), const Color(0xFF1E88E5)], Icons.storefront),
                cCard('فني', fmt.format(_subsTechTotal), '$_subsTechCount عملية', [const Color(0xFF00695C), const Color(0xFF00897B)], Icons.engineering),
              ),
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: row1[0]),
              Expanded(flex: 2, child: row1[1]),
              Expanded(flex: 2, child: row1[2]),
              Expanded(flex: 2, child: row1[3]),
              Expanded(flex: 2, child: row1[4]),
              Expanded(flex: 2, child: row1[5]),
            ],
          ),
        );
      },
    );
  }

  Widget _statBarCard(String title, String amount, String subtitle,
      List<Color> colors, IconData icon, {bool compact = false}) {
    final double hPad = compact ? 6 : 8;
    final double vPad = compact ? 5 : 8;
    final double iconSz = compact ? 14 : 20;
    final double titleSz = compact ? 9 : 10;
    final double amtSz = compact ? 13 : 15;
    final double subSz = compact ? 8 : 9;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: compact ? 0 : 2),
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        border: Border.all(color: Colors.black26, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: iconSz),
          SizedBox(width: compact ? 4 : 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(color: Colors.white70, fontSize: titleSz, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.center,
                  child: Text('$amount د.ع',
                      style: TextStyle(color: Colors.white, fontSize: amtSz, fontWeight: FontWeight.w900)),
                ),
                Text(subtitle,
                    style: TextStyle(color: Colors.white60, fontSize: subSz),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // زر الأيام الناقصة في الشريط العلوي
  Widget _buildMissingDaysButton() {
    if (_missingDaysLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        onTap: () => _showMissingDaysDialog(),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _missingDays.isNotEmpty ? Colors.red.withOpacity(0.3) : Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_busy, size: 18, color: Colors.white),
              if (_missingDays.isNotEmpty) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_missingDays.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showMissingDaysDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.event_busy, color: Colors.red.shade700, size: 22),
              const SizedBox(width: 8),
              Text('بدون تقرير (${_missingDays.length})',
                  style: TextStyle(color: Colors.red.shade800, fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _loadMissingDays();
                },
                child: Icon(Icons.refresh, color: Colors.grey.shade600, size: 20),
              ),
            ],
          ),
          content: _missingDays.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('لا توجد أيام ناقصة - أحسنت!',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.green, fontSize: 14)),
                )
              : SizedBox(
                  width: min(400, MediaQuery.of(context).size.width * 0.85),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _missingDays.map((day) {
                        final isRecent = DateTime.now().difference(day).inDays <= 3;
                        return InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            _selectDate(day);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isRecent ? Colors.red.shade50 : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isRecent ? Colors.red.shade300 : Colors.grey.shade300),
                            ),
                            child: Text(
                              DateFormat('MM/dd (E)', 'ar').format(day),
                              style: TextStyle(
                                color: isRecent ? Colors.red.shade900 : Colors.grey.shade800,
                                fontSize: 13,
                                fontWeight: isRecent ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  // صف الإجمالي + النقد الصافي
  Widget _buildTotalRow() {
    final fmt = NumberFormat('#,###');
    final netCash = _netCashAmount;
    final isNeg = netCash < 0;
    final hasExpenses = _totalExpenses > 0;
    final hasIncome = _totalExtraIncome > 0;

    final borderColor = isNeg ? Colors.red.shade300 : Colors.green.shade400;
    return Container(
      decoration: BoxDecoration(
        color: isNeg ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_wallet, color: isNeg ? Colors.red.shade700 : Colors.green.shade700, size: 22),
              const SizedBox(width: 8),
              Text('النقد الصافي',
                  style: TextStyle(color: isNeg ? Colors.red.shade800 : Colors.green.shade800, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasExpenses) ...[
                Text('مصاريف: ', style: TextStyle(color: Colors.orange.shade700, fontSize: 11)),
                Text('−${fmt.format(_totalExpenses)}', style: TextStyle(color: Colors.orange.shade900, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
              ],
              if (hasIncome) ...[
                Text('إضافة: ', style: TextStyle(color: Colors.blue.shade700, fontSize: 11)),
                Text('+${fmt.format(_totalExtraIncome)}', style: TextStyle(color: Colors.blue.shade900, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
              ],
              Text('${fmt.format(netCash)} د.ع',
                  style: TextStyle(color: isNeg ? Colors.red.shade900 : Colors.green.shade900, fontSize: 16, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(int index) {
    final item = _items[index];
    final noteCtrl = item['noteController'] as TextEditingController;
    final amountCtrl = item['amountController'] as TextEditingController;

    final category = (item['category'] ?? '') as String;
    final isIncome = category == 'إضافة أموال';

    final bool isMobile = Platform.isAndroid || Platform.isIOS || MediaQuery.of(context).size.width < 600;
    return Container(
      color: isIncome ? Colors.blue.shade50 : null,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 10, vertical: isMobile ? 4 : 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: isMobile ? 10 : 14,
            backgroundColor: isIncome ? Colors.blue.shade100 : Colors.deepPurple.shade50,
            child: Text('${index + 1}',
                style: TextStyle(color: isIncome ? Colors.blue.shade700 : Colors.deepPurple.shade700, fontSize: isMobile ? 9 : 12, fontWeight: FontWeight.bold)),
          ),
          SizedBox(width: isMobile ? 4 : 8),
          // المبلغ
          Expanded(
            flex: 2,
            child: TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [_ThousandsFormatter()],
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: isMobile ? 12 : 14),
              onChanged: (val) {
                final raw = val.replaceAll(',', '');
                final number = int.tryParse(raw) ?? 0;
                item['amount'] = number.toDouble();
                setState(() => _autoManageItems());
              },
              decoration: InputDecoration(
                hintText: 'المبلغ',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: isMobile ? 11 : 13),
                suffixText: 'د.ع',
                suffixStyle: TextStyle(color: Colors.grey.shade500, fontSize: 9),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 10, vertical: isMobile ? 6 : 10),
                border: const OutlineInputBorder(borderSide: BorderSide(color: Colors.black54)),
                enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.black54)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.deepPurple, width: 1.5)),
              ),
            ),
          ),
          SizedBox(width: isMobile ? 4 : 8),
          // الصنف
          Expanded(
            flex: 2,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 2 : 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black54),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: category.isEmpty ? null : category,
                  isExpanded: true,
                  isDense: true,
                  hint: Center(child: Text('الصنف', style: TextStyle(fontSize: isMobile ? 11 : 13, color: Colors.grey.shade400))),
                  style: TextStyle(fontSize: isMobile ? 11 : 13, color: Colors.black87),
                  items: _itemCategories.map((c) => DropdownMenuItem(value: c, child: Center(child: Text(c)))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => item['category'] = val);
                  },
                ),
              ),
            ),
          ),
          SizedBox(width: isMobile ? 4 : 8),
          // التفاصيل
          Expanded(
            flex: 3,
            child: TextField(
              controller: noteCtrl,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: isMobile ? 12 : 14),
              onChanged: (val) {
                item['note'] = val;
                setState(() => _autoManageItems());
              },
              decoration: InputDecoration(
                hintText: 'التفاصيل',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: isMobile ? 11 : 13),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: isMobile ? 4 : 10, vertical: isMobile ? 6 : 10),
                border: const OutlineInputBorder(borderSide: BorderSide(color: Colors.black54)),
                enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.black54)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.deepPurple, width: 1.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========== Tab 2: كشف العمليات ==========
  Widget _buildAllReportsTab() {
    return Column(
      children: [
        // فلاتر
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _filterOperator,
                  style: const TextStyle(color: Colors.black87, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'المشغل',
                    labelStyle: TextStyle(color: Colors.grey.shade600),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade300)),
                  ),
                  items: _operatorNames.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                  onChanged: (v) {
                    _filterOperator = v ?? 'الكل';
                    _loadAllReports();
                  },
                ),
              ),
              const SizedBox(width: 8),
              _buildFilterDateChip('من', _filterFrom, (d) {
                setState(() => _filterFrom = d);
                _loadAllReports();
              }),
              const SizedBox(width: 4),
              _buildFilterDateChip('إلى', _filterTo, (d) {
                setState(() => _filterTo = d);
                _loadAllReports();
              }),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _loadAllReports,
                icon: const Icon(Icons.refresh, color: Colors.deepPurple),
                tooltip: 'تحديث',
              ),
            ],
          ),
        ),

        // إحصائيات
        if (_allReports.isNotEmpty) _buildStatsBar(),

        // القائمة
        Expanded(
          child: _allLoading
              ? const Center(child: CircularProgressIndicator())
              : _allReports.isEmpty
                  ? Center(child: Text('لا توجد تقارير', style: TextStyle(color: Colors.grey.shade500)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _allReports.length,
                      itemBuilder: (ctx, i) => _buildReportCard(_allReports[i]),
                    ),
        ),
      ],
    );
  }

  Widget _buildFilterDateChip(String label, DateTime? value, Function(DateTime?) onPick) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2024),
          lastDate: DateTime.now().add(const Duration(days: 1)),
        );
        if (picked != null && mounted) onPick(picked);
      },
      onLongPress: () => onPick(null),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value != null ? Colors.deepPurple.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: value != null ? Colors.deepPurple : Colors.grey.shade400),
        ),
        child: Text(
          value != null ? '$label: ${DateFormat('MM/dd').format(value)}' : label,
          style: TextStyle(color: value != null ? Colors.deepPurple : Colors.grey.shade600, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildStatsBar() {
    double totalAll = 0;
    int reportCount = _allReports.length;
    final operatorTotals = <String, double>{};
    for (final r in _allReports) {
      final amt = ((r['TotalAmount'] ?? r['totalAmount']) as num?)?.toDouble() ?? 0;
      totalAll += amt;
      final name = (r['OperatorName'] ?? r['operatorName'])?.toString() ?? '?';
      operatorTotals[name] = (operatorTotals[name] ?? 0) + amt;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _statChip('التقارير', '$reportCount', Colors.blue),
              const SizedBox(width: 8),
              _statChip('الإجمالي الكلي', '${NumberFormat('#,###').format(totalAll)} د.ع', Colors.deepPurple),
              const SizedBox(width: 8),
              _statChip('المشغلين', '${operatorTotals.length}', Colors.orange),
            ],
          ),
          if (operatorTotals.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: operatorTotals.entries.map((e) {
                return Chip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  avatar: CircleAvatar(
                    radius: 10,
                    backgroundColor: Colors.deepPurple.shade100,
                    child: Text(e.key.isNotEmpty ? e.key[0] : '?',
                        style: TextStyle(fontSize: 10, color: Colors.deepPurple.shade700)),
                  ),
                  label: Text('${e.key}: ${NumberFormat('#,###').format(e.value)} د.ع',
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.grey.shade50,
                  side: BorderSide(color: Colors.grey.shade300),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 10)),
            FittedBox(
              child: Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final date = (report['ReportDate'] ?? report['reportDate'])?.toString() ?? '';
    String formattedDate = date;
    try {
      final dt = DateTime.parse(date);
      formattedDate = DateFormat('yyyy/MM/dd').format(dt);
    } catch (_) {}

    final operatorName = (report['OperatorName'] ?? report['operatorName'])?.toString() ?? '?';
    final totalAmount = ((report['TotalAmount'] ?? report['totalAmount']) as num?)?.toDouble() ?? 0;
    final notes = (report['Notes'] ?? report['notes'])?.toString() ?? '';
    final id = report['Id'] ?? report['id'];

    List<dynamic> items = [];
    try {
      final itemsStr = (report['ItemsJson'] ?? report['itemsJson'])?.toString() ?? '[]';
      items = json.decode(itemsStr);
    } catch (_) {}

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        iconColor: Colors.deepPurple,
        collapsedIconColor: Colors.grey,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.deepPurple.shade50,
              child: Text(operatorName.isNotEmpty ? operatorName[0] : '?',
                  style: TextStyle(color: Colors.deepPurple.shade700, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(operatorName,
                      style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(formattedDate, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${NumberFormat('#,###').format(totalAmount)} د.ع',
                    style: TextStyle(color: Colors.deepPurple.shade700, fontSize: 15, fontWeight: FontWeight.w900)),
                Text('${items.length} بند', style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
              ],
            ),
          ],
        ),
        children: [
          if (notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.notes, color: Colors.grey.shade400, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(notes, style: TextStyle(color: Colors.grey.shade600, fontSize: 12))),
                ],
              ),
            ),
          Divider(color: Colors.grey.shade200, height: 8),
          ...items.map((item) {
            final note = item['note']?.toString() ?? '';
            final amt = (item['amount'] as num?)?.toDouble() ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              child: Row(
                children: [
                  Icon(Icons.circle, color: Colors.deepPurple.shade300, size: 8),
                  const SizedBox(width: 8),
                  Expanded(child: Text(note, style: const TextStyle(color: Colors.black87, fontSize: 13))),
                  Text('${NumberFormat('#,###').format(amt)} د.ع',
                      style: TextStyle(color: Colors.grey.shade800, fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            );
          }),
          if (isAdmin)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _deleteReport(id),
                  icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                  label: const Text('حذف', style: TextStyle(color: Colors.red, fontSize: 12)),
                ),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// فورماتر لعرض الأرقام بفواصل المراتب (1,000,000)
class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.replaceAll(',', '');
    if (raw.isEmpty) return newValue.copyWith(text: '');
    // السماح بالأرقام فقط
    if (!RegExp(r'^\d+$').hasMatch(raw)) return oldValue;
    final number = int.tryParse(raw);
    if (number == null) return oldValue;
    final formatted = NumberFormat('#,###').format(number);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
