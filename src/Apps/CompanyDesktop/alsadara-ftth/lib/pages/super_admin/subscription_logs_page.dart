/// صفحة سجلات الاشتراكات - لوحة تحكم مدير النظام
/// تعرض جميع عمليات التجديد والشراء والتفعيل
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/api_service.dart';

import '../../frontend/tokens/sd_colors.dart' show SdColors;
class SubscriptionLogsPage extends StatefulWidget {
  const SubscriptionLogsPage({super.key});

  @override
  State<SubscriptionLogsPage> createState() => _SubscriptionLogsPageState();
}

class _SubscriptionLogsPageState extends State<SubscriptionLogsPage> {
  final ApiService _apiService = ApiService.instance;

  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String? _error;

  // Pagination
  int _currentPage = 1;
  int _totalRecords = 0;
  final int _pageSize = 50;

  // Filters
  String? _selectedZone;
  String? _selectedOperationType;
  DateTime? _fromDate;
  DateTime? _toDate;

  // Stats
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load logs and stats in parallel
      final results = await Future.wait([
        _fetchLogs(),
        _fetchStats(),
      ]);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'حدث خطأ';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchLogs() async {
    try {
      final queryParams = {
        'page': _currentPage.toString(),
        'pageSize': _pageSize.toString(),
        if (_selectedZone != null) 'zoneId': _selectedZone!,
        if (_selectedOperationType != null)
          'operationType': _selectedOperationType!,
        if (_fromDate != null) 'fromDate': _fromDate!.toIso8601String().split('T')[0],
        if (_toDate != null) 'toDate': _toDate!.toIso8601String().split('T')[0],
      };

      final uri = Uri.parse('${ApiService.baseUrl}/subscriptionlogs')
          .replace(queryParameters: queryParams);

      final response = await _apiService.get(uri.toString());

      if (response['success'] == true) {
        setState(() {
          _logs = List<Map<String, dynamic>>.from(response['data'] ?? []);
          _totalRecords = response['total'] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error fetching logs');
      rethrow;
    }
  }

  Future<void> _fetchStats() async {
    try {
      final response = await _apiService.get(
        '${ApiService.baseUrl}/subscriptionlogs/stats',
      );

      if (response['success'] == true) {
        setState(() {
          _stats = response['data'];
        });
      }
    } catch (e) {
      debugPrint('Error fetching stats');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SdColors.ground,
            SdColors.groundAlt,
          ],
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          if (_stats != null) _buildStatsCards(),
          _buildFilters(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: SdColors.success,
                    ),
                  )
                : _error != null
                    ? _buildErrorWidget()
                    : _buildLogsTable(),
          ),
          _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  SdColors.success.withOpacity(0.2),
                  SdColors.info.withOpacity(0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: SdColors.success.withOpacity(0.3),
              ),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: SdColors.success,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سجلات الاشتراكات',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: SdColors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'عمليات التجديد والشراء والتفعيل',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: SdColors.muted,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(
              Icons.refresh_rounded,
              color: SdColors.info,
            ),
            tooltip: 'تحديث',
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _buildStatCard(
            'إجمالي العمليات',
            '${_stats?['totalOperations'] ?? 0}',
            Icons.analytics_rounded,
            SdColors.success,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            'التجديدات',
            '${_stats?['renewals'] ?? 0}',
            Icons.autorenew_rounded,
            SdColors.info,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            'المشتريات',
            '${_stats?['purchases'] ?? 0}',
            Icons.shopping_cart_rounded,
            SdColors.platformBase,
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            'الإيرادات',
            '${NumberFormat('#,###').format(_stats?['totalRevenue'] ?? 0)} د.ع',
            Icons.attach_money_rounded,
            SdColors.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SdColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: SdColors.muted,
                    fontSize: 12,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: SdColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SdColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedOperationType,
              decoration: InputDecoration(
                labelText: 'نوع العملية',
                labelStyle: TextStyle(
                  fontFamily: 'Cairo',
                  color: SdColors.muted,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: SdColors.ground,
              ),
              dropdownColor: SdColors.surface,
              style: TextStyle(fontFamily: 'Cairo', color: SdColors.ink),
              items: const [
                DropdownMenuItem(value: null, child: Text('الكل')),
                DropdownMenuItem(value: 'renewal', child: Text('تجديد')),
                DropdownMenuItem(value: 'purchase', child: Text('شراء')),
                DropdownMenuItem(value: 'change', child: Text('تغيير')),
              ],
              onChanged: (value) {
                setState(() => _selectedOperationType = value);
                _currentPage = 1;
                _loadData();
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _fromDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setState(() => _fromDate = picked);
                  _currentPage = 1;
                  _loadData();
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'من تاريخ',
                  labelStyle: TextStyle(
                    fontFamily: 'Cairo',
                    color: SdColors.muted,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: SdColors.ground,
                  suffixIcon: const Icon(
                    Icons.calendar_today,
                    color: SdColors.muted,
                  ),
                ),
                child: Text(
                  _fromDate != null
                      ? DateFormat('yyyy-MM-dd').format(_fromDate!)
                      : 'اختر',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: SdColors.ink,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _toDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setState(() => _toDate = picked);
                  _currentPage = 1;
                  _loadData();
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'إلى تاريخ',
                  labelStyle: TextStyle(
                    fontFamily: 'Cairo',
                    color: SdColors.muted,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: SdColors.ground,
                  suffixIcon: const Icon(
                    Icons.calendar_today,
                    color: SdColors.muted,
                  ),
                ),
                child: Text(
                  _toDate != null
                      ? DateFormat('yyyy-MM-dd').format(_toDate!)
                      : 'اختر',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: SdColors.ink,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _selectedOperationType = null;
                _selectedZone = null;
                _fromDate = null;
                _toDate = null;
                _currentPage = 1;
              });
              _loadData();
            },
            icon: const Icon(Icons.clear_all),
            label: Text('مسح الفلاتر', style: TextStyle(fontFamily: 'Cairo')),
            style: ElevatedButton.styleFrom(
              backgroundColor: SdColors.groundAlt,
              foregroundColor: SdColors.ink,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsTable() {
    if (_logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_rounded,
              size: 64,
              color: SdColors.faint,
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد سجلات',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: SdColors.muted,
                fontSize: 18,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SdColors.divider),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            SdColors.groundAlt,
          ),
          dataRowColor: WidgetStateProperty.all(Colors.transparent),
          columns: [
            _buildColumn('التاريخ'),
            _buildColumn('العميل'),
            _buildColumn('الاشتراك'),
            _buildColumn('الباقة'),
            _buildColumn('السعر'),
            _buildColumn('نوع العملية'),
            _buildColumn('المنفذ'),
            _buildColumn('الحالة'),
          ],
          rows: _logs.map((log) => _buildDataRow(log)).toList(),
        ),
      ),
    );
  }

  DataColumn _buildColumn(String label) {
    return DataColumn(
      label: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          color: SdColors.ink,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  DataRow _buildDataRow(Map<String, dynamic> log) {
    final operationType = log['operationType'] ?? '';
    final operationColor = switch (operationType) {
      'renewal' => SdColors.success,
      'purchase' => SdColors.info,
      'change' => SdColors.warning,
      _ => SdColors.muted,
    };
    final operationLabel = switch (operationType) {
      'renewal' => 'تجديد',
      'purchase' => 'شراء',
      'change' => 'تغيير',
      _ => operationType,
    };

    return DataRow(
      cells: [
        DataCell(Text(
          log['activationDate'] != null
              ? DateFormat('yyyy-MM-dd HH:mm').format(
                  DateTime.parse(log['activationDate']).toLocal(),
                )
              : '-',
          style: TextStyle(fontFamily: 'Cairo', color: SdColors.muted),
        )),
        DataCell(Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              log['customerName'] ?? '-',
              style: TextStyle(fontFamily: 'Cairo', color: SdColors.ink),
            ),
            Text(
              log['phoneNumber'] ?? '',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: SdColors.faint,
                fontSize: 11,
              ),
            ),
          ],
        )),
        DataCell(Text(
          log['subscriptionId'] ?? '-',
          style: TextStyle(fontFamily: 'Cairo', color: SdColors.muted),
        )),
        DataCell(Text(
          log['planName'] ?? '-',
          style: TextStyle(fontFamily: 'Cairo', color: SdColors.ink),
        )),
        DataCell(Text(
          '${NumberFormat('#,###').format(log['planPrice'] ?? 0)} د.ع',
          style: TextStyle(
            fontFamily: 'Cairo',
            color: SdColors.success,
            fontWeight: FontWeight.bold,
          ),
        )),
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: operationColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: operationColor.withOpacity(0.3)),
          ),
          child: Text(
            operationLabel,
            style: TextStyle(
              fontFamily: 'Cairo',
              color: operationColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        )),
        DataCell(Text(
          log['activatedBy'] ?? '-',
          style: TextStyle(fontFamily: 'Cairo', color: SdColors.muted),
        )),
        DataCell(Row(
          children: [
            if (log['isPrinted'] == true)
              const Icon(Icons.print,
                  size: 16, color: SdColors.success),
            const SizedBox(width: 4),
            if (log['isWhatsAppSent'] == true)
              const Icon(Icons.message,
                  size: 16, color: SdColors.success),
          ],
        )),
      ],
    );
  }

  Widget _buildPagination() {
    final totalPages = (_totalRecords / _pageSize).ceil();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'إجمالي: $_totalRecords سجل',
            style: TextStyle(fontFamily: 'Cairo', color: SdColors.muted),
          ),
          const SizedBox(width: 24),
          IconButton(
            onPressed: _currentPage > 1
                ? () {
                    setState(() => _currentPage--);
                    _loadData();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
            color: SdColors.info,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: SdColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'صفحة $_currentPage من $totalPages',
              style: TextStyle(fontFamily: 'Cairo', color: SdColors.ink),
            ),
          ),
          IconButton(
            onPressed: _currentPage < totalPages
                ? () {
                    setState(() => _currentPage++);
                    _loadData();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
            color: SdColors.info,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: SdColors.danger,
          ),
          const SizedBox(height: 16),
          Text(
            'حدث خطأ',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: SdColors.ink,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? '',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: SdColors.muted,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: Text('إعادة المحاولة', style: TextStyle(fontFamily: 'Cairo')),
            style: ElevatedButton.styleFrom(
              backgroundColor: SdColors.info,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
