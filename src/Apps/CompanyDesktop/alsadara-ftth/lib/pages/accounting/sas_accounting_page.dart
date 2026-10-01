import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/vps_auth_service.dart';
import '../../services/api/api_config.dart';
import '../../theme/accounting_theme.dart';

/// 📡 صفحة «نظام الساس — الحسابات»
/// تعرض ملخّص محاسبة عمليات الساس فقط (SubscriptionLog.Source == Sas) من الدفتر المحاسبي الموحّد.
/// تقرأ من `GET /api/accounting/sas-summary?companyId=&from=&to=` بنفس نمط مصادقة الصفحات الأخرى.
/// حالياً قد تكون فارغة (0 عمليات) — تعرض حالة فارغة لطيفة وتمتلئ لاحقاً.
class SasAccountingPage extends StatefulWidget {
  final String? companyId;

  const SasAccountingPage({super.key, this.companyId});

  @override
  State<SasAccountingPage> createState() => _SasAccountingPageState();
}

class _SasAccountingPageState extends State<SasAccountingPage> {
  bool _isLoading = true;
  String? _error;

  // ملخّص
  int _totalOperations = 0;
  double _totalCollected = 0;
  double _totalBasePrice = 0;
  double _totalMaintenance = 0;
  double _totalManualDiscount = 0;
  List<Map<String, dynamic>> _byCollectionType = [];
  List<Map<String, dynamic>> _recent = [];

  // فلتر المدى (اختياري)
  DateTime? _fromDate;
  DateTime? _toDate;

  final _currencyFormat = NumberFormat('#,###', 'ar');

  String get _companyId =>
      widget.companyId ?? VpsAuthService.instance.currentCompanyId ?? '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      var url = '${ApiConfig.vpsBaseUrl}/api/accounting/sas-summary';
      final params = <String>[];
      if (_companyId.isNotEmpty) params.add('companyId=$_companyId');
      if (_fromDate != null) {
        params.add('from=${_fromDate!.toIso8601String().split('T')[0]}');
      }
      if (_toDate != null) {
        params.add('to=${_toDate!.toIso8601String().split('T')[0]}');
      }
      if (params.isNotEmpty) url += '?${params.join('&')}';

      final token = VpsAuthService.instance.accessToken;
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'X-Api-Key': 'sadara-internal-2024-secure-key',
        },
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final data = (result['data'] as Map?)?.cast<String, dynamic>() ?? {};
          _totalOperations = _asInt(data['totalOperations']);
          _totalCollected = _asDouble(data['totalCollected']);
          _totalBasePrice = _asDouble(data['totalBasePrice']);
          _totalMaintenance = _asDouble(data['totalMaintenance']);
          _totalManualDiscount = _asDouble(data['totalManualDiscount']);
          _byCollectionType = ((data['byCollectionType'] as List?) ?? [])
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
          _recent = ((data['recent'] as List?) ?? [])
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
        } else {
          _error = result['message']?.toString() ?? 'حدث خطأ';
        }
      } else {
        _error = 'خطأ في الاتصال: ${response.statusCode}';
      }
    } catch (e) {
      _error = 'تعذّر جلب البيانات';
    }

    if (mounted) setState(() => _isLoading = false);
  }

  int _asInt(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

  double _asDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initialRange = (_fromDate != null && _toDate != null)
        ? DateTimeRange(start: _fromDate!, end: _toDate!)
        : DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: initialRange,
      locale: const Locale('ar'),
    );

    if (picked != null && mounted) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      _loadData();
    }
  }

  void _clearDateRange() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _loadData();
  }

  String _collectionTypeLabel(String? type) {
    switch (type) {
      case 'cash':
        return 'نقد';
      case 'credit':
        return 'آجل';
      case 'agent':
        return 'وكيل';
      case 'master':
        return 'ماستر';
      case null:
      case '':
        return 'غير محدد';
      default:
        return type;
    }
  }

  String _actionLabel(String? action) {
    switch (action) {
      case 'activate':
        return 'تفعيل';
      case 'extend':
        return 'تمديد';
      case 'changeProfile':
        return 'تغيير باقة';
      case null:
      case '':
        return '—';
      default:
        return action;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        appBar: AppBar(
          backgroundColor: AccountingTheme.bgSidebar,
          foregroundColor: AccountingTheme.textOnDark,
          title: Text(
            'نظام الساس — الحسابات',
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold, color: AccountingTheme.textOnDark),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _loadData,
            ),
          ],
        ),
        body: Column(
          children: [
            _buildDateFilterBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildDateFilterBar() {
    final hasRange = _fromDate != null && _toDate != null;
    final label = hasRange
        ? '${DateFormat('yyyy/MM/dd').format(_fromDate!)} — ${DateFormat('yyyy/MM/dd').format(_toDate!)}'
        : 'كل الفترات';
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AccountingTheme.bgCard,
      child: Row(
        children: [
          const Icon(Icons.date_range,
              size: 18, color: AccountingTheme.textMuted),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.cairo(
                color: AccountingTheme.textSecondary,
                fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (hasRange)
            TextButton.icon(
              onPressed: _clearDateRange,
              icon: const Icon(Icons.clear, size: 16),
              label: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
          OutlinedButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.filter_alt_outlined, size: 18),
            label: Text('تصفية بالتاريخ', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return AccountingTheme.errorView(_error!, _loadData);
    }
    if (_totalOperations == 0) {
      return AccountingTheme.emptyState(
        'لا توجد عمليات ساس محاسبية بعد\nستظهر الحركات هنا بعد أول تفعيل عبر نظام الساس',
        icon: Icons.router,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryCards(),
          const SizedBox(height: 20),
          _buildCollectionTypeSection(),
          const SizedBox(height: 20),
          _buildRecentSection(),
        ],
      ),
    );
  }

  // ─────────────────────────── بطاقات الملخّص ───────────────────────────
  Widget _buildSummaryCards() {
    final cards = [
      _SummaryCardData(
        title: 'عدد العمليات',
        value: _currencyFormat.format(_totalOperations),
        icon: Icons.sync_alt,
        color: AccountingTheme.neonBlue,
      ),
      _SummaryCardData(
        title: 'إجمالي المحصّل',
        value: _currencyFormat.format(_totalCollected),
        icon: Icons.payments,
        color: AccountingTheme.neonGreen,
      ),
      _SummaryCardData(
        title: 'الكلفة الأساسية',
        value: _currencyFormat.format(_totalBasePrice),
        icon: Icons.sell_outlined,
        color: AccountingTheme.neonOrange,
      ),
      _SummaryCardData(
        title: 'أجور الصيانة',
        value: _currencyFormat.format(_totalMaintenance),
        icon: Icons.build_circle_outlined,
        color: AccountingTheme.neonPurple,
      ),
      _SummaryCardData(
        title: 'الخصومات اليدوية',
        value: _currencyFormat.format(_totalManualDiscount),
        icon: Icons.discount_outlined,
        color: AccountingTheme.neonPink,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final cols = maxW > 1000
            ? 5
            : maxW > 740
                ? 3
                : maxW > 480
                    ? 2
                    : 1;
        const spacing = 12.0;
        final cardW = (maxW - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map((c) => SizedBox(width: cardW, child: _summaryCard(c)))
              .toList(),
        );
      },
    );
  }

  Widget _summaryCard(_SummaryCardData c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AccountingTheme.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(c.icon, color: c.color, size: 22),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            c.value,
            style: GoogleFonts.cairo(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AccountingTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            c.title,
            style: GoogleFonts.cairo(
                fontSize: 13, color: AccountingTheme.textMuted),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── توزيع حسب نوع التحصيل ───────────────────────
  Widget _buildCollectionTypeSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AccountingTheme.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('توزيع حسب نوع التحصيل', Icons.pie_chart_outline),
          const SizedBox(height: 12),
          if (_byCollectionType.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('لا توجد بيانات',
                  style: GoogleFonts.cairo(color: AccountingTheme.textMuted)),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _byCollectionType.map((e) {
                final count = _asInt(e['count']);
                final total = _asDouble(e['total']);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AccountingTheme.bgSecondary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _collectionTypeLabel(e['type']?.toString()),
                        style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            color: AccountingTheme.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_currencyFormat.format(count)} عملية · ${_currencyFormat.format(total)}',
                        style: GoogleFonts.cairo(
                            fontSize: 12, color: AccountingTheme.textSecondary),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ───────────────────────── قائمة آخر الحركات ─────────────────────────
  Widget _buildRecentSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AccountingTheme.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('آخر الحركات', Icons.history),
          const SizedBox(height: 12),
          if (_recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('لا توجد حركات',
                  style: GoogleFonts.cairo(color: AccountingTheme.textMuted)),
            )
          else
            ..._recent.map(_recentRow),
        ],
      ),
    );
  }

  Widget _recentRow(Map<String, dynamic> r) {
    final createdAt = DateTime.tryParse(r['createdAt']?.toString() ?? '');
    final dateLabel = createdAt != null
        ? DateFormat('yyyy/MM/dd HH:mm').format(createdAt.toLocal())
        : '—';
    final username = r['subscriberUsername']?.toString() ?? '—';
    final plan = r['planName']?.toString() ?? '—';
    final collected = _asDouble(r['collectedAmount']);
    final type = _collectionTypeLabel(r['collectionType']?.toString());
    final action = _actionLabel(r['action']?.toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AccountingTheme.bgSecondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      color: AccountingTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  plan,
                  style: GoogleFonts.cairo(
                      fontSize: 12, color: AccountingTheme.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateLabel,
                    style: GoogleFonts.cairo(
                        fontSize: 11, color: AccountingTheme.textSecondary)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _chip(action, AccountingTheme.neonBlue),
                    const SizedBox(width: 6),
                    _chip(type, AccountingTheme.neonPurple),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _currencyFormat.format(collected),
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold, color: AccountingTheme.debitText),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.cairo(fontSize: 10, color: color),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AccountingTheme.neonBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.cairo(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AccountingTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _SummaryCardData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  _SummaryCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
}
