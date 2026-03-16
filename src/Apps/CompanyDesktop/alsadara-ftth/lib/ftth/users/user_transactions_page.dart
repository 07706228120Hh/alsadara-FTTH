/// اسم الصفحة: معاملات المستخدم
/// وصف الصفحة: صفحة معاملات مستخدم محدد
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../models/filter_criteria.dart';
import 'dart:convert';

/// صفحة عرض معاملات مستخدم محدد
class UserTransactionsPage extends StatefulWidget {
  final String userName;
  final FilterCriteria? filterCriteria;

  const UserTransactionsPage({
    super.key,
    required this.userName,
    this.filterCriteria,
  });

  @override
  State<UserTransactionsPage> createState() => _UserTransactionsPageState();
}

class _UserTransactionsPageState extends State<UserTransactionsPage> {
  List<Map<String, dynamic>> transactions = [];
  List<Map<String, dynamic>> filteredTransactions = [];
  bool isLoading = true;
  String? errorMessage;
  String searchQuery = '';

  // إحصائيات المعاملات
  double totalAmount = 0.0;
  double positiveAmount = 0.0;
  double negativeAmount = 0.0;
  int totalCount = 0;
  Map<String, int> transactionTypeCounts = {};

  @override
  void initState() {
    super.initState();
    _loadUserTransactions();
  }

  /// جلب معاملات المستخدم من API
  Future<void> _loadUserTransactions() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      // بناء رابط API مع المعاملات للمستخدم المحدد
      String url = 'https://alsadara-ftth-api.alsadara-cctv.com/transactions?';

      // إضافة فلتر المستخدم
      url += 'transactionUser=${Uri.encodeComponent(widget.userName)}';

      // إضافة فلاتر إضافية من filterCriteria إذا كانت موجودة
      if (widget.filterCriteria != null) {
        final criteria = widget.filterCriteria!;

        if (criteria.fromDate != null) {
          url +=
              '&fromDate=${DateFormat('yyyy-MM-dd').format(criteria.fromDate!)}';
        }

        if (criteria.toDate != null) {
          url += '&toDate=${DateFormat('yyyy-MM-dd').format(criteria.toDate!)}';
        }

        if (criteria.selectedZoneFilter != 'الكل') {
          url += '&zone=${Uri.encodeComponent(criteria.selectedZoneFilter)}';
        }
      }

      url += '&page=1&limit=5000';

      print('🔍 جلب معاملات المستخدم من: $url');

      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        url,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<Map<String, dynamic>> fetchedTransactions =
            List<Map<String, dynamic>>.from(data['items'] ?? []);

        setState(() {
          transactions = fetchedTransactions;
          filteredTransactions = fetchedTransactions;
          isLoading = false;
        });

        _calculateStatistics();
      } else {
        setState(() {
          errorMessage = 'فشل في جلب المعاملات: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'خطأ في الاتصال بالخادم';
        isLoading = false;
      });
    }
  }

  /// حساب إحصائيات المعاملات
  void _calculateStatistics() {
    totalAmount = 0.0;
    positiveAmount = 0.0;
    negativeAmount = 0.0;
    totalCount = filteredTransactions.length;
    transactionTypeCounts.clear();

    for (final transaction in filteredTransactions) {
      final amtDynamic = transaction['transactionAmount']?['value'] ?? 0.0;
      final num amtNum = (amtDynamic is num)
          ? amtDynamic
          : double.tryParse(amtDynamic.toString()) ?? 0.0;
      final double amount = amtNum.toDouble();

      totalAmount += amount;
      if (amount > 0) {
        positiveAmount += amount;
      } else {
        negativeAmount += amount;
      }

      // حساب الإحصائيات حسب نوع المعاملة
      final transactionType = transaction['transactionType'] ?? 'غير محدد';
      transactionTypeCounts[transactionType] =
          (transactionTypeCounts[transactionType] ?? 0) + 1;
    }
  }

  /// تطبيق البحث
  void _applySearch() {
    setState(() {
      if (searchQuery.isEmpty) {
        filteredTransactions = transactions;
      } else {
        filteredTransactions = transactions.where((transaction) {
          final customerId = transaction['customerId']?.toString() ?? '';
          final transactionType =
              transaction['transactionType']?.toString() ?? '';
          final serviceName = transaction['serviceName']?.toString() ?? '';
          final amount =
              transaction['transactionAmount']?['value']?.toString() ?? '';

          return customerId.toLowerCase().contains(searchQuery.toLowerCase()) ||
              transactionType
                  .toLowerCase()
                  .contains(searchQuery.toLowerCase()) ||
              serviceName.toLowerCase().contains(searchQuery.toLowerCase()) ||
              amount.contains(searchQuery);
        }).toList();
      }
      _calculateStatistics();
    });
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('yyyy/MM/dd HH:mm').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  String _formatAmount(double amount) {
    return NumberFormat('#,###.##', 'ar').format(amount);
  }

  Color _getAmountColor(double amount) {
    if (amount > 0) return Colors.green;
    if (amount < 0) return Colors.red;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'معاملات: ${widget.userName}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUserTransactions,
            tooltip: 'تحديث البيانات',
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                  ),
                  SizedBox(height: 16),
                  Text('جاري تحميل المعاملات...'),
                ],
              ),
            )
          : errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 64, color: Colors.red.shade400),
                      const SizedBox(height: 16),
                      Text(
                        errorMessage!,
                        style: const TextStyle(fontSize: 16, color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadUserTransactions,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // مؤشر معايير التصفية النشطة
                    if (widget.filterCriteria != null &&
                        widget.filterCriteria!.hasActiveFilters)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.filter_alt,
                              color: Colors.blue.shade700,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'التصفية النشطة: ${widget.filterCriteria!.activeFiltersDescription}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade800,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // شريط الإحصائيات
                    _buildStatisticsBar(),

                    // شريط البحث
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'البحث في المعاملات...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        onChanged: (value) {
                          searchQuery = value;
                          _applySearch();
                        },
                      ),
                    ),

                    const SizedBox(height: 16),

                    // قائمة المعاملات
                    Expanded(
                      child: filteredTransactions.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 64, color: Colors.grey),
                                  SizedBox(height: 16),
                                  Text(
                                    'لا توجد معاملات لهذا المستخدم',
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: filteredTransactions.length,
                              itemBuilder: (context, index) {
                                return _buildTransactionCard(
                                    filteredTransactions[index]);
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatisticsBar() {
    return Card(
      margin: const EdgeInsets.all(16),
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
                color: Colors.deepPurple.shade700,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'العدد الإجمالي',
                    totalCount.toString(),
                    Colors.blue,
                    Icons.receipt_long,
                  ),
                ),
                Expanded(
                  child: _buildStatCard(
                    'المجموع الإجمالي',
                    '${_formatAmount(totalAmount)} IQD',
                    _getAmountColor(totalAmount),
                    Icons.account_balance_wallet,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'المبالغ الموجبة',
                    '${_formatAmount(positiveAmount)} IQD',
                    Colors.green,
                    Icons.trending_up,
                  ),
                ),
                Expanded(
                  child: _buildStatCard(
                    'المبالغ السالبة',
                    '${_formatAmount(negativeAmount)} IQD',
                    Colors.red,
                    Icons.trending_down,
                  ),
                ),
              ],
            ),
            if (transactionTypeCounts.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'توزيع أنواع المعاملات',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.deepPurple.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: transactionTypeCounts.entries
                    .map((entry) => Chip(
                          label: Text(
                            '${entry.key}: ${entry.value}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: Colors.grey.shade100,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    final amtDynamic = transaction['transactionAmount']?['value'] ?? 0.0;
    final num amtNum = (amtDynamic is num)
        ? amtDynamic
        : double.tryParse(amtDynamic.toString()) ?? 0.0;
    final double amount = amtNum.toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    transaction['transactionType']?.toString() ?? 'غير محدد',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
                Text(
                  '${_formatAmount(amount)} ${transaction['transactionAmount']?['currency'] ?? 'IQD'}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _getAmountColor(amount),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (transaction['serviceName'] != null) ...[
              Text(
                'اسم الخدمة: ${transaction['serviceName']}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (transaction['customerId'] != null) ...[
              Text(
                'معرف العميل: ${transaction['customerId']}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (transaction['zone'] != null) ...[
              Text(
                'المنطقة: ${transaction['zone']}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              'التاريخ: ${_formatDate(transaction['createdAt']?.toString() ?? '')}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            if (transaction['transactionStatus'] != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'الحالة: ${transaction['transactionStatus']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
