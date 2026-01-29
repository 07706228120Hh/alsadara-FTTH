/// صفحة طلبات المواطنين
library;

import 'package:flutter/material.dart';
import 'models/citizen_portal_models.dart';
import 'services/citizen_portal_service.dart';
import 'widgets/request_status_badge.dart';

class CitizenRequestsPage extends StatefulWidget {
  const CitizenRequestsPage({super.key});

  @override
  State<CitizenRequestsPage> createState() => _CitizenRequestsPageState();
}

class _CitizenRequestsPageState extends State<CitizenRequestsPage> {
  final CitizenPortalService _service = CitizenPortalService.instance;
  final ScrollController _scrollController = ScrollController();

  List<ServiceRequestModel> _requests = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 1;
  bool _hasMore = true;
  ServiceRequestStatus? _filterStatus;

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentPage = 1;
      _hasMore = true;
    });

    final response = await _service.getRequests(
      page: 1,
      status: _filterStatus?.value,
    );

    if (response.isSuccess && response.data != null) {
      setState(() {
        _requests = response.data!;
        _isLoading = false;
        _hasMore = response.data!.length >= 20;
      });
    } else {
      setState(() {
        _error = response.message ?? 'فشل في تحميل الطلبات';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    final response = await _service.getRequests(
      page: _currentPage + 1,
      status: _filterStatus?.value,
    );

    if (response.isSuccess && response.data != null) {
      setState(() {
        _requests.addAll(response.data!);
        _currentPage++;
        _isLoadingMore = false;
        _hasMore = response.data!.length >= 20;
      });
    } else {
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          // شريط الفلترة
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
            child: Row(
              children: [
                // فلتر الحالة
                const Text('الحالة: '),
                const SizedBox(width: 8),
                DropdownButton<ServiceRequestStatus?>(
                  value: _filterStatus,
                  hint: const Text('جميع الحالات'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('جميع الحالات'),
                    ),
                    ...ServiceRequestStatus.values
                        .map((status) => DropdownMenuItem(
                              value: status,
                              child: Row(
                                children: [
                                  Icon(status.icon,
                                      size: 18, color: status.color),
                                  const SizedBox(width: 8),
                                  Text(status.nameAr),
                                ],
                              ),
                            )),
                  ],
                  onChanged: (value) {
                    setState(() => _filterStatus = value);
                    _loadRequests();
                  },
                ),

                const Spacer(),

                // زر التحديث
                IconButton(
                  onPressed: _loadRequests,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'تحديث',
                ),
              ],
            ),
          ),

          // إحصائيات سريعة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildQuickStat(
                  'جديد',
                  _requests
                      .where((r) => r.status == ServiceRequestStatus.pending)
                      .length,
                  Colors.blue,
                ),
                _buildQuickStat(
                  'قيد التنفيذ',
                  _requests
                      .where((r) => r.status == ServiceRequestStatus.inProgress)
                      .length,
                  Colors.indigo,
                ),
                _buildQuickStat(
                  'مكتمل',
                  _requests
                      .where((r) => r.status == ServiceRequestStatus.completed)
                      .length,
                  Colors.green,
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

  Widget _buildQuickStat(String label, int count, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha((0.1 * 255).round()),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
              ),
            ),
          ],
        ),
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
              onPressed: _loadRequests,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (_requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.list_alt_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'لا توجد طلبات',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      color: Colors.teal,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _requests.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _requests.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: Colors.teal),
              ),
            );
          }

          final request = _requests[index];
          return _buildRequestCard(request);
        },
      ),
    );
  }

  Widget _buildRequestCard(ServiceRequestModel request) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: request.status.color.withAlpha((0.3 * 255).round()),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showRequestDetails(request),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الرأس
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          request.status.color.withAlpha((0.15 * 255).round()),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      request.status.icon,
                      color: request.status.color,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'طلب #${request.requestNumber}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          request.serviceName ?? 'خدمة ${request.serviceId}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      RequestStatusBadge(status: request.status),
                      const SizedBox(height: 4),
                      RequestPriorityBadge(priority: request.priority),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // المعلومات
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      Icons.person,
                      'المواطن',
                      request.citizenName ?? 'غير محدد',
                    ),
                  ),
                  Expanded(
                    child: _buildInfoItem(
                      Icons.phone,
                      'الهاتف',
                      request.citizenPhone ?? '-',
                    ),
                  ),
                  Expanded(
                    child: _buildInfoItem(
                      Icons.calendar_today,
                      'التاريخ',
                      _formatDate(request.requestedAt),
                    ),
                  ),
                ],
              ),

              // المعين إليه
              if (request.assignedToName != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.engineering, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      'معين إلى: ${request.assignedToName}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],

              // أزرار الإجراءات
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (request.status == ServiceRequestStatus.pending ||
                      request.status == ServiceRequestStatus.reviewing)
                    TextButton.icon(
                      onPressed: () => _assignRequest(request),
                      icon: const Icon(Icons.person_add, size: 18),
                      label: const Text('تعيين'),
                    ),
                  if (request.status != ServiceRequestStatus.completed &&
                      request.status != ServiceRequestStatus.cancelled)
                    TextButton.icon(
                      onPressed: () => _changeStatus(request),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('تغيير الحالة'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
              ),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ],
    );
  }

  void _showRequestDetails(ServiceRequestModel request) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('طلب #${request.requestNumber}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RequestProgressIndicator(status: request.status),
                const SizedBox(height: 20),
                _buildDetailRow('الخدمة', request.serviceName ?? '-'),
                _buildDetailRow(
                    'نوع العملية', request.operationTypeName ?? '-'),
                _buildDetailRow('المواطن', request.citizenName ?? '-'),
                _buildDetailRow('الهاتف', request.citizenPhone ?? '-'),
                _buildDetailRow('العنوان', request.address ?? '-'),
                _buildDetailRow('التفاصيل', request.details ?? '-'),
                if (request.estimatedCost != null)
                  _buildDetailRow('التكلفة المقدرة',
                      '${request.estimatedCost!.toStringAsFixed(0)} د.ع'),
                if (request.finalCost != null)
                  _buildDetailRow('التكلفة النهائية',
                      '${request.finalCost!.toStringAsFixed(0)} د.ع'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _assignRequest(ServiceRequestModel request) {
    // TODO: فتح نافذة اختيار الموظف
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('سيتم إضافة نافذة اختيار الموظف')),
    );
  }

  void _changeStatus(ServiceRequestModel request) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تغيير الحالة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: ServiceRequestStatus.values
                .where((s) =>
                    s != ServiceRequestStatus.cancelled &&
                    s != ServiceRequestStatus.rejected)
                .map((status) => ListTile(
                      leading: Icon(status.icon, color: status.color),
                      title: Text(status.nameAr),
                      selected: request.status == status,
                      onTap: () async {
                        Navigator.pop(context);
                        await _service.updateRequestStatus(
                          request.id,
                          status.value,
                        );
                        _loadRequests();
                      },
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
