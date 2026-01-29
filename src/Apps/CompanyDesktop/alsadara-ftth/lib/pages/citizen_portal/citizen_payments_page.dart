/// صفحة مدفوعات المواطنين
library;

import 'package:flutter/material.dart';
import 'models/citizen_portal_models.dart';
import 'services/citizen_portal_service.dart';

class CitizenPaymentsPage extends StatefulWidget {
  const CitizenPaymentsPage({super.key});

  @override
  State<CitizenPaymentsPage> createState() => _CitizenPaymentsPageState();
}

class _CitizenPaymentsPageState extends State<CitizenPaymentsPage> {
  final CitizenPortalService _service = CitizenPortalService.instance;

  List<CitizenPaymentModel> _payments = [];
  bool _isLoading = true;
  String? _error;
  String? _filterStatus;

  double get _totalAmount => _payments.fold(
      0, (sum, p) => sum + (p.status == 'success' ? p.amount : 0));

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final response = await _service.getPayments(
      pageSize: 100,
      status: _filterStatus,
    );

    if (response.isSuccess && response.data != null) {
      setState(() {
        _payments = response.data!;
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = response.message ?? 'فشل في تحميل المدفوعات';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          // شريط الفلترة والإحصائيات
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade200,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // الفلترة
                Row(
                  children: [
                    const Text('الحالة: '),
                    const SizedBox(width: 8),
                    DropdownButton<String?>(
                      value: _filterStatus,
                      hint: const Text('جميع المدفوعات'),
                      items: const [
                        DropdownMenuItem(
                            value: null, child: Text('جميع المدفوعات')),
                        DropdownMenuItem(value: 'success', child: Text('ناجح')),
                        DropdownMenuItem(value: 'pending', child: Text('معلق')),
                        DropdownMenuItem(value: 'failed', child: Text('فشل')),
                      ],
                      onChanged: (value) {
                        setState(() => _filterStatus = value);
                        _loadPayments();
                      },
                    ),

                    const Spacer(),

                    // زر التحديث
                    IconButton(
                      onPressed: _loadPayments,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'تحديث',
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // الإحصائيات
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'إجمالي الناجح',
                        '${_totalAmount.toStringAsFixed(0)} د.ع',
                        Icons.check_circle,
                        Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        'عدد العمليات',
                        '${_payments.length}',
                        Icons.receipt_long,
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        'معلق',
                        '${_payments.where((p) => p.status == 'pending').length}',
                        Icons.pending,
                        Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        'فشل',
                        '${_payments.where((p) => p.status == 'failed').length}',
                        Icons.error,
                        Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // القائمة
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha((0.1 * 255).round()),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withAlpha((0.3 * 255).round()),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.teal),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadPayments,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (_payments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.payments_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'لا توجد مدفوعات',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPayments,
      color: Colors.teal,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _payments.length,
        itemBuilder: (context, index) {
          final payment = _payments[index];
          return _buildPaymentCard(payment);
        },
      ),
    );
  }

  Widget _buildPaymentCard(CitizenPaymentModel payment) {
    final color = payment.status == 'success'
        ? Colors.green
        : payment.status == 'pending'
            ? Colors.orange
            : Colors.red;

    final statusIcon = payment.status == 'success'
        ? Icons.check_circle
        : payment.status == 'pending'
            ? Icons.pending
            : Icons.error;

    final statusText = payment.status == 'success'
        ? 'ناجح'
        : payment.status == 'pending'
            ? 'معلق'
            : 'فشل';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: color.withAlpha((0.3 * 255).round()),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // أيقونة الحالة
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withAlpha((0.15 * 255).round()),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                statusIcon,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),

            // المعلومات
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${payment.amount.toStringAsFixed(0)} د.ع',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withAlpha((0.15 * 255).round()),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.person, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          payment.citizenName ?? 'غير محدد',
                          style: TextStyle(color: Colors.grey.shade700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.payment, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        _getPaymentMethodName(payment.paymentMethod),
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const Spacer(),
                      const Icon(Icons.access_time,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        _formatDateTime(payment.createdAt),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  if (payment.transactionId != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.receipt, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          'رقم العملية: ${payment.transactionId}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getPaymentMethodName(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'نقدي';
      case 'card':
        return 'بطاقة';
      case 'zain_cash':
        return 'زين كاش';
      case 'asiacell_cash':
        return 'آسيا كاش';
      default:
        return method;
    }
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
