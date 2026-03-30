import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../providers/agent_auth_provider.dart';
import '../../services/agent_api_service.dart';

/// عنصر موحد يمثل عملية مالية أو طلب خدمة
class UnifiedOperation {
  final String id;
  final String title;
  final String subtitle;
  final DateTime date;
  final double? amount;
  final bool isIncoming;
  final double? balanceAfter;
  final String category; // 'charge', 'payment', 'activation', 'other'
  final IconData icon;
  final Color color;
  final String? status; // للطلبات فقط

  UnifiedOperation({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.date,
    this.amount,
    this.isIncoming = false,
    this.balanceAfter,
    required this.category,
    required this.icon,
    required this.color,
    this.status,
  });
}

/// صفحة سجل العمليات
class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  String _selectedFilter = 'all';
  DateTimeRange? _dateRange;
  List<UnifiedOperation> _allOperations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllOperations();
  }

  Future<void> _loadAllOperations() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final agentAuth = context.read<AgentAuthProvider>();

    try {
      // تحميل العمليات المالية وطلبات الخدمة بالتوازي
      final results = await Future.wait([
        agentAuth.getTransactions(
          pageSize: 100,
          startDate: _dateRange?.start,
          endDate: _dateRange?.end,
        ),
        agentAuth.agentApi.getMyServiceRequests(pageSize: 100),
      ]);

      final transactions = results[0] as List<AgentTransactionData>;
      final serviceRequestsResult = results[1] as Map<String, dynamic>;

      final operations = <UnifiedOperation>[];

      // تحويل طلبات الخدمة أولاً
      final serviceRequests = serviceRequestsResult['data'] as List? ?? [];
      final srIds = <String>{};
      for (final sr in serviceRequests) {
        if (sr is Map<String, dynamic>) {
          final id = (_get(sr, 'Id') ?? '').toString();
          if (id.isNotEmpty) srIds.add(id);
          operations.add(_serviceRequestToOperation(sr));
        }
      }

      // تحويل العمليات المالية - تخطي المكررة المرتبطة بطلبات خدمة
      for (final tx in transactions) {
        // إذا كانت العملية المالية مرتبطة بطلب خدمة موجود → تخطيها (لتجنب التكرار)
        // ودمج المبلغ في طلب الخدمة المقابل
        final txSrId = tx.serviceRequestId;
        if (txSrId != null && txSrId.isNotEmpty && srIds.contains(txSrId)) {
          // دمج: تحديث طلب الخدمة بالمبلغ
          final idx = operations.indexWhere((op) => op.id == 'sr_$txSrId');
          if (idx >= 0) {
            final op = operations[idx];
            operations[idx] = UnifiedOperation(
              id: op.id,
              title: op.title,
              subtitle: op.subtitle,
              date: op.date,
              amount: tx.amount,
              isIncoming: tx.isIncoming,
              balanceAfter: tx.balanceAfter,
              category: op.category,
              icon: op.icon,
              color: op.color,
              status: op.status,
            );
          }
          continue;
        }
        operations.add(_transactionToOperation(tx));
      }

      // ترتيب حسب التاريخ (الأحدث أولاً)
      operations.sort((a, b) => b.date.compareTo(a.date));

      if (mounted) {
        setState(() {
          _allOperations = operations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  UnifiedOperation _transactionToOperation(AgentTransactionData tx) {
    IconData icon;
    Color color;
    String category;

    switch (tx.type) {
      case 0:
        icon = Icons.account_balance_wallet;
        color = AppTheme.agentColor;
        category = 'charge';
        break;
      case 1:
        icon = Icons.receipt_long;
        color = AppTheme.successColor;
        category = 'payment';
        break;
      default:
        icon = Icons.tune;
        color = AppTheme.textGrey;
        category = 'other';
    }

    return UnifiedOperation(
      id: 'tx_${tx.id}',
      title: tx.description ?? tx.typeName,
      subtitle: tx.categoryName,
      date: tx.createdAt,
      amount: tx.amount,
      isIncoming: tx.isIncoming,
      balanceAfter: tx.balanceAfter,
      category: category,
      icon: icon,
      color: color,
    );
  }

  /// قراءة قيمة من Map بدعم PascalCase و camelCase
  dynamic _get(Map<String, dynamic> map, String key) {
    // جرب camelCase أولاً ثم PascalCase
    return map[key] ??
        map[key[0].toUpperCase() + key.substring(1)] ??
        map[key[0].toLowerCase() + key.substring(1)];
  }

  UnifiedOperation _serviceRequestToOperation(Map<String, dynamic> sr) {
    final status = (_get(sr, 'Status') ?? _get(sr, 'status') ?? 'Pending')
        .toString()
        .toLowerCase();
    String statusAr;
    Color color;

    switch (status) {
      case 'pending':
      case '0':
        statusAr = 'قيد المراجعة';
        color = Colors.orange;
        break;
      case 'reviewing':
      case '1':
        statusAr = 'قيد المراجعة';
        color = Colors.orange;
        break;
      case 'approved':
      case '2':
        statusAr = 'تمت الموافقة';
        color = Colors.green;
        break;
      case 'assigned':
      case '3':
        statusAr = 'تم التعيين';
        color = Colors.blue;
        break;
      case 'inprogress':
      case '4':
        statusAr = 'قيد التنفيذ';
        color = Colors.blue;
        break;
      case 'completed':
      case '5':
        statusAr = 'مكتمل';
        color = AppTheme.successColor;
        break;
      case 'rejected':
      case '7':
        statusAr = 'مرفوض';
        color = Colors.red;
        break;
      case 'cancelled':
      case '6':
        statusAr = 'ملغي';
        color = Colors.grey;
        break;
      default:
        statusAr = status;
        color = Colors.orange;
    }

    // استخراج معلومات العميل من Details (JSON)
    String customerName = '';
    String customerPhone = '';
    final details = _get(sr, 'Details');
    if (details != null && details is String && details.isNotEmpty) {
      try {
        final parsed = json.decode(details);
        if (parsed is Map) {
          customerName = (parsed['customerName'] ?? '').toString();
          customerPhone = (parsed['customerPhone'] ?? '').toString();
        }
      } catch (_) {}
    }
    // fallback: ContactPhone
    if (customerPhone.isEmpty) {
      customerPhone = (_get(sr, 'ContactPhone') ?? '').toString();
    }

    final requestNumber = (_get(sr, 'RequestNumber') ?? '').toString();
    final serviceName = (_get(sr, 'ServiceName') ?? 'طلب تفعيل').toString();
    final id = (_get(sr, 'Id') ?? '').toString();

    final subtitle = customerName.isNotEmpty
        ? '$customerName${customerPhone.isNotEmpty ? ' - $customerPhone' : ''}'
        : customerPhone.isNotEmpty
        ? customerPhone
        : statusAr;

    final dateStr = (_get(sr, 'RequestedAt') ?? _get(sr, 'CreatedAt') ?? '')
        .toString();

    return UnifiedOperation(
      id: 'sr_$id',
      title: requestNumber.isNotEmpty
          ? '$serviceName (#$requestNumber)'
          : serviceName,
      subtitle: subtitle,
      date: DateTime.tryParse(dateStr) ?? DateTime.now(),
      amount: null,
      isIncoming: false,
      category: 'activation',
      icon: Icons.person_add_alt_1,
      color: color,
      status: statusAr,
    );
  }

  List<UnifiedOperation> get _filteredOperations {
    return _allOperations.where((op) {
      if (_selectedFilter == 'all') return true;
      return op.category == _selectedFilter;
    }).toList();
  }

  int get _operationsCount => _filteredOperations.length;

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) {
      return 'منذ ${diff.inMinutes} دقيقة';
    } else if (diff.inHours < 24) {
      return 'منذ ${diff.inHours} ساعة';
    } else {
      return intl.DateFormat('yyyy/MM/dd', 'ar').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredOperations;

    return Theme(
      data: AppTheme.agentTheme,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(
            title: const Text('سجل العمليات'),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/agent/home'),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadAllOperations,
              ),
            ],
          ),
          body: Column(
            children: [
              // Filters
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Column(
                  children: [
                    // Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('all', 'الكل', Icons.list),
                          _buildFilterChip(
                            'charge',
                            'شحن',
                            Icons.account_balance_wallet,
                          ),
                          _buildFilterChip(
                            'payment',
                            'تسديد',
                            Icons.receipt_long,
                          ),
                          _buildFilterChip(
                            'activation',
                            'تفعيل',
                            Icons.person_add_alt_1,
                          ),
                          _buildFilterChip('other', 'أخرى', Icons.tune),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Date Range
                    OutlinedButton.icon(
                      onPressed: () async {
                        final range = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2024),
                          lastDate: DateTime.now(),
                          locale: const Locale('ar'),
                        );
                        if (range != null) {
                          setState(() => _dateRange = range);
                          _loadAllOperations();
                        }
                      },
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        _dateRange != null
                            ? '${intl.DateFormat('MM/dd').format(_dateRange!.start)} - ${intl.DateFormat('MM/dd').format(_dateRange!.end)}'
                            : 'تحديد الفترة',
                      ),
                    ),
                  ],
                ),
              ),

              // Stats Summary
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Row(
                  children: [
                    _buildStatItem(
                      'عدد العمليات',
                      '$_operationsCount',
                      'عملية',
                      AppTheme.primaryColor,
                    ),
                    Container(width: 1, height: 40, color: Colors.grey[300]),
                    _buildStatItem(
                      'طلبات التفعيل',
                      '${_allOperations.where((o) => o.category == 'activation').length}',
                      'طلب',
                      Colors.blue,
                    ),
                  ],
                ),
              ),

              // Operations List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'لا توجد عمليات',
                          style: TextStyle(color: AppTheme.textGrey),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadAllOperations,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            return _buildOperationCard(filtered[index]);
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, IconData icon) {
    final isSelected = _selectedFilter == value;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        avatar: isSelected
            ? null
            : Icon(icon, size: 16, color: AppTheme.textGrey),
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedFilter = value),
        selectedColor: AppTheme.agentColor,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : AppTheme.textDark,
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, String unit, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              Text(unit, style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOperationCard(UnifiedOperation op) {
    final isActivation = op.category == 'activation';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: op.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(op.icon, color: op.color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  op.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  op.subtitle,
                  style: const TextStyle(
                    color: AppTheme.textGrey,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(op.date),
                  style: const TextStyle(
                    color: AppTheme.textGrey,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isActivation && op.status != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: op.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    op.status!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: op.color,
                    ),
                  ),
                ),
              if (!isActivation && op.amount != null) ...[
                Text(
                  '${op.isIncoming ? '+' : '-'}${op.amount!.toStringAsFixed(0)} د.ع',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: op.isIncoming ? AppTheme.successColor : Colors.red,
                  ),
                ),
                if (op.balanceAfter != null)
                  Text(
                    'الرصيد: ${op.balanceAfter!.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: 10,
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
