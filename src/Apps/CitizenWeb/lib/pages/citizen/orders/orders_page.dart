import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/app_theme.dart';

/// صفحة الطلبات والفواتير
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // طلبات تجريبية
  final List<Map<String, dynamic>> _orders = [
    {
      'id': 'ORD-001',
      'type': 'subscription',
      'title': 'تجديد اشتراك إنترنت',
      'description': 'باقة 100 ميجا - شهر واحد',
      'amount': 299.0,
      'status': 'completed',
      'date': '2026-01-30',
      'paymentMethod': 'visa',
    },
    {
      'id': 'ORD-002',
      'type': 'upgrade',
      'title': 'ترقية الباقة',
      'description': 'من 50 ميجا إلى 100 ميجا',
      'amount': 50.0,
      'status': 'processing',
      'date': '2026-01-28',
      'paymentMethod': 'apple_pay',
    },
    {
      'id': 'ORD-003',
      'type': 'store',
      'title': 'راوتر واي فاي 6',
      'description': 'TP-Link AX3000',
      'amount': 450.0,
      'status': 'shipping',
      'date': '2026-01-25',
      'paymentMethod': 'stc_pay',
    },
    {
      'id': 'ORD-004',
      'type': 'master',
      'title': 'شحن ماستر كارد',
      'description': 'شحن رصيد 500 د.ع',
      'amount': 500.0,
      'status': 'completed',
      'date': '2026-01-20',
      'paymentMethod': 'visa',
    },
    {
      'id': 'ORD-005',
      'type': 'maintenance',
      'title': 'طلب صيانة',
      'description': 'إصلاح انقطاع الخدمة',
      'amount': 0.0,
      'status': 'pending',
      'date': '2026-01-15',
      'paymentMethod': null,
    },
  ];

  // فواتير تجريبية
  final List<Map<String, dynamic>> _invoices = [
    {
      'id': 'INV-2026-001',
      'period': 'يناير 2026',
      'amount': 299.0,
      'status': 'paid',
      'dueDate': '2026-01-15',
      'paidDate': '2026-01-10',
      'items': [
        {'name': 'اشتراك إنترنت 100 ميجا', 'amount': 270.0},
        {'name': 'ضريبة القيمة المضافة (15%)', 'amount': 29.0},
      ],
    },
    {
      'id': 'INV-2026-002',
      'period': 'فبراير 2026',
      'amount': 349.0,
      'status': 'unpaid',
      'dueDate': '2026-02-15',
      'paidDate': null,
      'items': [
        {'name': 'اشتراك إنترنت 100 ميجا', 'amount': 270.0},
        {'name': 'رسوم ترقية', 'amount': 50.0},
        {'name': 'ضريبة القيمة المضافة (15%)', 'amount': 29.0},
      ],
    },
    {
      'id': 'INV-2025-012',
      'period': 'ديسمبر 2025',
      'amount': 249.0,
      'status': 'paid',
      'dueDate': '2025-12-15',
      'paidDate': '2025-12-14',
      'items': [
        {'name': 'اشتراك إنترنت 50 ميجا', 'amount': 220.0},
        {'name': 'ضريبة القيمة المضافة (15%)', 'amount': 29.0},
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('الطلبات والفواتير'),
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/citizen/home'),
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: 'الطلبات', icon: Icon(Icons.shopping_bag)),
              Tab(text: 'الفواتير', icon: Icon(Icons.receipt_long)),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // تبويب الطلبات
            _buildOrdersTab(isWide),
            // تبويب الفواتير
            _buildInvoicesTab(isWide),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersTab(bool isWide) {
    return ListView.builder(
      padding: EdgeInsets.all(isWide ? 32 : 16),
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        return _buildOrderCard(_orders[index]);
      },
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showOrderDetails(order),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildOrderTypeIcon(order['type']),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order['title'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order['description'],
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (order['amount'] > 0)
                        Text(
                          '${order['amount'].toStringAsFixed(0)} د.ع',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      const SizedBox(height: 4),
                      _buildOrderStatusBadge(order['status']),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.tag, size: 14, color: AppTheme.textGrey),
                  const SizedBox(width: 4),
                  Text(
                    order['id'],
                    style: const TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: AppTheme.textGrey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    order['date'],
                    style: const TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: 12,
                    ),
                  ),
                  if (order['paymentMethod'] != null) ...[
                    const Spacer(),
                    _buildPaymentMethodIcon(order['paymentMethod']),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderTypeIcon(String type) {
    IconData icon;
    Color color;

    switch (type) {
      case 'subscription':
        icon = Icons.wifi;
        color = AppTheme.internetColor;
        break;
      case 'upgrade':
        icon = Icons.upgrade;
        color = AppTheme.successColor;
        break;
      case 'store':
        icon = Icons.shopping_cart;
        color = AppTheme.storeColor;
        break;
      case 'master':
        icon = Icons.credit_card;
        color = AppTheme.masterCardColor;
        break;
      case 'maintenance':
        icon = Icons.build;
        color = AppTheme.warningColor;
        break;
      default:
        icon = Icons.receipt;
        color = AppTheme.textGrey;
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color),
    );
  }

  Widget _buildOrderStatusBadge(String status) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case 'completed':
        color = AppTheme.successColor;
        label = 'مكتمل';
        icon = Icons.check_circle;
        break;
      case 'processing':
        color = AppTheme.infoColor;
        label = 'قيد المعالجة';
        icon = Icons.sync;
        break;
      case 'shipping':
        color = AppTheme.warningColor;
        label = 'قيد الشحن';
        icon = Icons.local_shipping;
        break;
      case 'pending':
        color = AppTheme.textGrey;
        label = 'معلق';
        icon = Icons.hourglass_empty;
        break;
      case 'cancelled':
        color = AppTheme.errorColor;
        label = 'ملغي';
        icon = Icons.cancel;
        break;
      default:
        color = AppTheme.textGrey;
        label = status;
        icon = Icons.info;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodIcon(String method) {
    String label;
    IconData icon;

    switch (method) {
      case 'visa':
        label = 'Visa';
        icon = Icons.credit_card;
        break;
      case 'apple_pay':
        label = 'Apple Pay';
        icon = Icons.apple;
        break;
      case 'stc_pay':
        label = 'STC Pay';
        icon = Icons.account_balance_wallet;
        break;
      default:
        label = method;
        icon = Icons.payment;
    }

    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textGrey),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textGrey, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildInvoicesTab(bool isWide) {
    return ListView.builder(
      padding: EdgeInsets.all(isWide ? 32 : 16),
      itemCount: _invoices.length,
      itemBuilder: (context, index) {
        return _buildInvoiceCard(_invoices[index]);
      },
    );
  }

  Widget _buildInvoiceCard(Map<String, dynamic> invoice) {
    final isPaid = invoice['status'] == 'paid';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showInvoiceDetails(invoice),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isPaid
                    ? AppTheme.successColor.withOpacity(0.1)
                    : AppTheme.warningColor.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isPaid ? Icons.check_circle : Icons.schedule,
                    color: isPaid
                        ? AppTheme.successColor
                        : AppTheme.warningColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isPaid ? 'مدفوعة' : 'غير مدفوعة',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isPaid
                          ? AppTheme.successColor
                          : AppTheme.warningColor,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    invoice['id'],
                    style: const TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'فاتورة',
                            style: TextStyle(
                              color: AppTheme.textGrey,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            invoice['period'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'المبلغ',
                            style: TextStyle(
                              color: AppTheme.textGrey,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '${invoice['amount'].toStringAsFixed(0)} د.ع',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isPaid ? 'تاريخ السداد' : 'موعد السداد',
                              style: const TextStyle(
                                color: AppTheme.textGrey,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              isPaid ? invoice['paidDate'] : invoice['dueDate'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isPaid)
                        ElevatedButton(
                          onPressed: () => context.go(
                            '/citizen/payment?amount=${invoice['amount']}&type=invoice',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                          ),
                          child: const Text('دفع الآن'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        order['id'],
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Text(
                    order['title'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildOrderStatusBadge(order['status']),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  _buildDetailRow('الوصف', order['description']),
                  _buildDetailRow('التاريخ', order['date']),
                  if (order['amount'] > 0)
                    _buildDetailRow(
                      'المبلغ',
                      '${order['amount'].toStringAsFixed(0)} د.ع',
                    ),
                  if (order['paymentMethod'] != null)
                    _buildDetailRow(
                      'طريقة الدفع',
                      _getPaymentMethodLabel(order['paymentMethod']),
                    ),
                  const SizedBox(height: 24),
                  _buildOrderTimeline(order['status']),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textGrey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildOrderTimeline(String currentStatus) {
    final statuses = [
      {'status': 'pending', 'label': 'تم الطلب', 'icon': Icons.shopping_bag},
      {'status': 'processing', 'label': 'قيد المعالجة', 'icon': Icons.sync},
      {
        'status': 'shipping',
        'label': 'قيد الشحن',
        'icon': Icons.local_shipping,
      },
      {'status': 'completed', 'label': 'مكتمل', 'icon': Icons.check_circle},
    ];

    final currentIndex = statuses.indexWhere(
      (s) => s['status'] == currentStatus,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'تتبع الطلب',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...statuses.asMap().entries.map((entry) {
          final index = entry.key;
          final status = entry.value;
          final isCompleted = index <= currentIndex;
          final isLast = index == statuses.length - 1;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? AppTheme.successColor
                          : AppTheme.textGrey.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      status['icon'] as IconData,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 40,
                      color: isCompleted
                          ? AppTheme.successColor
                          : AppTheme.textGrey.withOpacity(0.3),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  status['label'] as String,
                  style: TextStyle(
                    color: isCompleted ? AppTheme.textDark : AppTheme.textGrey,
                    fontWeight: isCompleted
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  void _showInvoiceDetails(Map<String, dynamic> invoice) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'تفاصيل الفاتورة',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // معلومات الفاتورة
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow('رقم الفاتورة', invoice['id']),
                        _buildDetailRow('الفترة', invoice['period']),
                        _buildDetailRow('موعد السداد', invoice['dueDate']),
                        if (invoice['paidDate'] != null)
                          _buildDetailRow('تاريخ السداد', invoice['paidDate']),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // تفاصيل المبالغ
                  const Text(
                    'التفاصيل',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...(invoice['items'] as List).map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(item['name']),
                          Text(
                            '${item['amount'].toStringAsFixed(0)} د.ع',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'الإجمالي',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${invoice['amount'].toStringAsFixed(0)} د.ع',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // أزرار
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.download),
                          label: const Text('تحميل PDF'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.share),
                          label: const Text('مشاركة'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (invoice['status'] != 'paid')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          context.go(
                            '/citizen/payment?amount=${invoice['amount']}&type=invoice',
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('دفع الفاتورة'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getPaymentMethodLabel(String method) {
    switch (method) {
      case 'visa':
        return 'بطاقة ائتمانية';
      case 'apple_pay':
        return 'Apple Pay';
      case 'stc_pay':
        return 'STC Pay';
      default:
        return method;
    }
  }
}
