/// صفحة تفاصيل المواطن
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/citizen_portal_models.dart';
import 'services/citizen_portal_service.dart';
import 'widgets/request_status_badge.dart';

class CitizenDetailsPage extends StatefulWidget {
  final CitizenModel citizen;

  const CitizenDetailsPage({super.key, required this.citizen});

  @override
  State<CitizenDetailsPage> createState() => _CitizenDetailsPageState();
}

class _CitizenDetailsPageState extends State<CitizenDetailsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final CitizenPortalService _service = CitizenPortalService.instance;

  CitizenModel? _citizen;
  List<ServiceRequestModel> _requests = [];
  List<CitizenSubscriptionModel> _subscriptions = [];
  List<CitizenPaymentModel> _payments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _citizen = widget.citizen;
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // تحميل البيانات بالتوازي
    await Future.wait([
      _loadCitizenDetails(),
      _loadRequests(),
      _loadSubscriptions(),
      _loadPayments(),
    ]);

    setState(() => _isLoading = false);
  }

  Future<void> _loadCitizenDetails() async {
    final response = await _service.getCitizenById(widget.citizen.id);
    if (response.isSuccess && response.data != null) {
      setState(() => _citizen = response.data);
    }
  }

  Future<void> _loadRequests() async {
    final response =
        await _service.getRequests(citizenId: widget.citizen.id, pageSize: 50);
    if (response.isSuccess && response.data != null) {
      setState(() => _requests = response.data!);
    }
  }

  Future<void> _loadSubscriptions() async {
    final response = await _service.getSubscriptions(
        citizenId: widget.citizen.id, pageSize: 50);
    if (response.isSuccess && response.data != null) {
      setState(() => _subscriptions = response.data!);
    }
  }

  Future<void> _loadPayments() async {
    final response =
        await _service.getPayments(citizenId: widget.citizen.id, pageSize: 50);
    if (response.isSuccess && response.data != null) {
      setState(() => _payments = response.data!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_citizen?.fullName ?? 'تفاصيل المواطن'),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: 'تحديث',
            ),
            PopupMenuButton<String>(
              onSelected: _onMenuAction,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: const Row(
                    children: [
                      Icon(Icons.edit),
                      SizedBox(width: 8),
                      Text('تعديل البيانات'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: _citizen?.isBanned == true ? 'unban' : 'ban',
                  child: Row(
                    children: [
                      Icon(_citizen?.isBanned == true
                          ? Icons.lock_open
                          : Icons.block),
                      const SizedBox(width: 8),
                      Text(_citizen?.isBanned == true ? 'إلغاء الحظر' : 'حظر'),
                    ],
                  ),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(icon: Icon(Icons.person), text: 'المعلومات'),
              Tab(icon: Icon(Icons.list_alt), text: 'الطلبات'),
              Tab(icon: Icon(Icons.card_membership), text: 'الاشتراكات'),
              Tab(icon: Icon(Icons.payments), text: 'المدفوعات'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.teal))
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildInfoTab(),
                  _buildRequestsTab(),
                  _buildSubscriptionsTab(),
                  _buildPaymentsTab(),
                ],
              ),
      ),
    );
  }

  void _onMenuAction(String action) {
    switch (action) {
      case 'edit':
        // TODO: فتح نافذة التعديل
        break;
      case 'ban':
      case 'unban':
        _toggleBan();
        break;
    }
  }

  Future<void> _toggleBan() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:
              Text(_citizen?.isBanned == true ? 'إلغاء الحظر' : 'حظر المواطن'),
          content: Text(
            _citizen?.isBanned == true
                ? 'هل تريد إلغاء حظر هذا المواطن؟'
                : 'هل تريد حظر هذا المواطن؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _citizen?.isBanned == true ? Colors.green : Colors.red,
              ),
              child: Text(_citizen?.isBanned == true ? 'إلغاء الحظر' : 'حظر'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final response = await _service.toggleCitizenBan(widget.citizen.id);
      if (response.isSuccess) {
        _loadCitizenDetails();
      }
    }
  }

  Widget _buildInfoTab() {
    if (_citizen == null) return const SizedBox();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // بطاقة المعلومات الأساسية
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // الصورة والاسم
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.teal.shade100,
                        backgroundImage: _citizen!.profileImageUrl != null
                            ? NetworkImage(_citizen!.profileImageUrl!)
                            : null,
                        child: _citizen!.profileImageUrl == null
                            ? Text(
                                _citizen!.fullName.isNotEmpty
                                    ? _citizen!.fullName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal.shade700,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _citizen!.fullName,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (_citizen!.isBanned)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.block,
                                            size: 16, color: Colors.red),
                                        SizedBox(width: 4),
                                        Text(
                                          'محظور',
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              icon: Icons.phone,
                              label: 'رقم الهاتف',
                              value: _citizen!.phoneNumber,
                              verified: _citizen!.isPhoneVerified,
                              onCopy: () => _copyToClipboard(
                                  _citizen!.phoneNumber, 'رقم الهاتف'),
                            ),
                            if (_citizen!.email != null) ...[
                              const SizedBox(height: 4),
                              _buildInfoRow(
                                icon: Icons.email,
                                label: 'البريد الإلكتروني',
                                value: _citizen!.email!,
                                onCopy: () => _copyToClipboard(
                                    _citizen!.email!, 'البريد الإلكتروني'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 20),

                  // الإحصائيات
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        label: 'الطلبات',
                        value: '${_citizen!.totalRequests}',
                        icon: Icons.list_alt,
                        color: Colors.blue,
                      ),
                      _buildStatItem(
                        label: 'المدفوعات',
                        value: '${_citizen!.totalPaid.toStringAsFixed(0)} د.ع',
                        icon: Icons.payments,
                        color: Colors.green,
                      ),
                      _buildStatItem(
                        label: 'نقاط الولاء',
                        value: '${_citizen!.loyaltyPoints}',
                        icon: Icons.stars,
                        color: Colors.amber,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // العنوان
          if (_citizen!.fullAddress != null ||
              _citizen!.city != null ||
              _citizen!.district != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.teal),
                        SizedBox(width: 8),
                        Text(
                          'العنوان',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    if (_citizen!.city != null)
                      _buildDetailRow('المدينة', _citizen!.city!),
                    if (_citizen!.district != null)
                      _buildDetailRow('المنطقة', _citizen!.district!),
                    if (_citizen!.fullAddress != null)
                      _buildDetailRow('العنوان الكامل', _citizen!.fullAddress!),
                    if (_citizen!.latitude != null &&
                        _citizen!.longitude != null)
                      Row(
                        children: [
                          const Text('الموقع: '),
                          TextButton.icon(
                            onPressed: () {
                              // TODO: فتح الخريطة
                            },
                            icon: const Icon(Icons.map, size: 18),
                            label: const Text('عرض على الخريطة'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // معلومات إضافية
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.teal),
                      SizedBox(width: 8),
                      Text(
                        'معلومات إضافية',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  _buildDetailRow(
                    'تاريخ التسجيل',
                    _formatDate(_citizen!.createdAt),
                  ),
                  if (_citizen!.lastLoginAt != null)
                    _buildDetailRow(
                      'آخر تسجيل دخول',
                      _formatDate(_citizen!.lastLoginAt!),
                    ),
                  _buildDetailRow(
                    'حالة الحساب',
                    _citizen!.isActive ? 'نشط' : 'غير نشط',
                  ),
                  _buildDetailRow(
                    'تحقق الهاتف',
                    _citizen!.isPhoneVerified ? 'تم التحقق' : 'لم يتم التحقق',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsTab() {
    if (_requests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.list_alt_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('لا توجد طلبات', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final request = _requests[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: request.status.color.withAlpha((0.15 * 255).round()),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                request.status.icon,
                color: request.status.color,
              ),
            ),
            title: Text(
              request.serviceName ?? 'طلب #${request.requestNumber}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.operationTypeName ??
                    'نوع العملية: ${request.operationTypeId}'),
                const SizedBox(height: 4),
                Text(
                  _formatDate(request.requestedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            trailing: RequestStatusBadge(status: request.status),
            onTap: () {
              // TODO: فتح تفاصيل الطلب
            },
          ),
        );
      },
    );
  }

  Widget _buildSubscriptionsTab() {
    if (_subscriptions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.card_membership_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('لا توجد اشتراكات', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _subscriptions.length,
      itemBuilder: (context, index) {
        final sub = _subscriptions[index];
        final color = sub.isExpired
            ? Colors.red
            : sub.isExpiringSoon
                ? Colors.orange
                : Colors.green;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withAlpha((0.15 * 255).round()),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                sub.isExpired
                    ? Icons.event_busy
                    : sub.isExpiringSoon
                        ? Icons.warning
                        : Icons.event_available,
                color: color,
              ),
            ),
            title: Text(
              sub.planName ?? 'اشتراك',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${sub.price.toStringAsFixed(0)} د.ع'),
                const SizedBox(height: 4),
                Text(
                  sub.isExpired ? 'منتهي' : 'متبقي ${sub.daysRemaining} يوم',
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            trailing: sub.isActive && !sub.isExpired
                ? ElevatedButton(
                    onPressed: () async {
                      await _service.renewSubscription(sub.id);
                      _loadSubscriptions();
                    },
                    child: const Text('تجديد'),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildPaymentsTab() {
    if (_payments.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.payments_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('لا توجد مدفوعات', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _payments.length,
      itemBuilder: (context, index) {
        final payment = _payments[index];
        final color = payment.status == 'success'
            ? Colors.green
            : payment.status == 'pending'
                ? Colors.orange
                : Colors.red;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withAlpha((0.15 * 255).round()),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                payment.status == 'success'
                    ? Icons.check_circle
                    : payment.status == 'pending'
                        ? Icons.pending
                        : Icons.error,
                color: color,
              ),
            ),
            title: Text(
              '${payment.amount.toStringAsFixed(0)} د.ع',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payment.paymentMethod == 'cash'
                    ? 'نقدي'
                    : payment.paymentMethod),
                const SizedBox(height: 4),
                Text(
                  _formatDate(payment.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withAlpha((0.15 * 255).round()),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                payment.status == 'success'
                    ? 'ناجح'
                    : payment.status == 'pending'
                        ? 'معلق'
                        : 'فشل',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool verified = false,
    VoidCallback? onCopy,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Text(value),
              if (verified)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.verified,
                      size: 16, color: Colors.green.shade600),
                ),
            ],
          ),
        ),
        if (onCopy != null)
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            onPressed: onCopy,
            tooltip: 'نسخ',
          ),
      ],
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 28, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
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
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم نسخ $label')),
    );
  }
}
