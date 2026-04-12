import 'dart:convert';
import 'package:flutter/material.dart';
import '../../theme/energy_dashboard_theme.dart';
import '../../services/sadara_api_service.dart';
import '../citizen_portal/models/citizen_portal_models.dart';

/// صفحة إدارة طلبات الخدمة
class ServiceRequestsManagementPage extends StatefulWidget {
  const ServiceRequestsManagementPage({super.key});

  @override
  State<ServiceRequestsManagementPage> createState() =>
      _ServiceRequestsManagementPageState();
}

class _ServiceRequestsManagementPageState
    extends State<ServiceRequestsManagementPage> {
  final SadaraApiService _api = SadaraApiService.instance;

  bool _isLoading = true;
  String? _errorMessage;
  List<ServiceRequestModel> _requests = [];
  Map<String, dynamic> _statistics = {};
  ServiceRequestStatus? _statusFilter;
  String _searchQuery = '';
  ServiceRequestModel? _selectedRequest;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        _api.getServiceRequests(page: 1, pageSize: 100),
        _api.getServiceRequestStatistics(),
      ]);

      final requestsList = results[0] as List<dynamic>;
      final stats = results[1] as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _requests = requestsList.map((r) {
          if (r is Map<String, dynamic>) {
            return ServiceRequestModel.fromJson(r);
          }
          return ServiceRequestModel.fromJson({});
        }).toList();
        _statistics = stats['data'] ?? stats;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'حدث خطأ';
        _isLoading = false;
      });
    }
  }

  List<ServiceRequestModel> get _filteredRequests {
    var list = _requests;
    if (_statusFilter != null) {
      list = list.where((r) => r.status == _statusFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((r) {
        return r.requestNumber.toLowerCase().contains(q) ||
            (r.citizenName?.toLowerCase().contains(q) ?? false) ||
            (r.citizenPhone?.toLowerCase().contains(q) ?? false) ||
            (r.serviceName?.toLowerCase().contains(q) ?? false) ||
            (r.address?.toLowerCase().contains(q) ?? false) ||
            (r.details?.toLowerCase().contains(q) ?? false);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: EnergyDashboardTheme.bgPrimary,
        child: Column(
          children: [
            _buildToolbar(),
            _buildStatisticsBar(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? _buildErrorWidget()
                      : _selectedRequest != null
                          ? _buildDetailView()
                          : _buildRequestsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        border: Border(
          bottom: BorderSide(color: EnergyDashboardTheme.borderColor),
        ),
      ),
      child: Row(
        children: [
          if (_selectedRequest != null)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _selectedRequest = null),
            ),
          Icon(
            _selectedRequest != null
                ? Icons.assignment
                : Icons.receipt_long_rounded,
            color: EnergyDashboardTheme.neonBlue,
            size: 24,
          ),
          const SizedBox(width: 12),
          Text(
            _selectedRequest != null
                ? 'تفاصيل الطلب: ${_selectedRequest!.requestNumber}'
                : 'طلبات الخدمة',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: EnergyDashboardTheme.textPrimary,
            ),
          ),
          const Spacer(),
          if (_selectedRequest == null) ...[
            // بحث
            SizedBox(
              width: 250,
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'بحث...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: EnergyDashboardTheme.borderColor),
                  ),
                  filled: true,
                  fillColor: EnergyDashboardTheme.bgPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // فلتر الحالة
            PopupMenuButton<ServiceRequestStatus?>(
              icon: Badge(
                isLabelVisible: _statusFilter != null,
                child: const Icon(Icons.filter_list),
              ),
              onSelected: (value) => setState(() => _statusFilter = value),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: null,
                  child: Text('الكل'),
                ),
                ...ServiceRequestStatus.values.map(
                  (s) => PopupMenuItem(
                    value: s,
                    child: Row(
                      children: [
                        Icon(s.icon, color: s.color, size: 18),
                        const SizedBox(width: 8),
                        Text(s.nameAr),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            // تحديث
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: 'تحديث',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatisticsBar() {
    if (_selectedRequest != null || _statistics.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: EnergyDashboardTheme.bgSecondary,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildStatChip(
              'الكل',
              _statistics['total'] ?? 0,
              EnergyDashboardTheme.neonBlue,
              Icons.list_alt,
            ),
            _buildStatChip(
              'جديد',
              _statistics['pending'] ?? 0,
              Colors.blue,
              Icons.hourglass_empty,
            ),
            _buildStatChip(
              'قيد المراجعة',
              _statistics['reviewing'] ?? 0,
              Colors.orange,
              Icons.visibility,
            ),
            _buildStatChip(
              'قيد التنفيذ',
              _statistics['inProgress'] ?? 0,
              Colors.indigo,
              Icons.engineering,
            ),
            _buildStatChip(
              'مكتمل',
              _statistics['completed'] ?? 0,
              Colors.green,
              Icons.check_circle,
            ),
            _buildStatChip(
              'ملغي',
              _statistics['cancelled'] ?? 0,
              Colors.grey,
              Icons.cancel,
            ),
            _buildStatChip(
              'مرفوض',
              _statistics['rejected'] ?? 0,
              Colors.red,
              Icons.block,
            ),
            const SizedBox(width: 16),
            _buildStatChip(
              'اليوم',
              _statistics['todayCreated'] ?? 0,
              EnergyDashboardTheme.neonPurple,
              Icons.today,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(
      String label, dynamic count, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: $count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'خطأ غير معروف',
            style: const TextStyle(color: Colors.red),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsList() {
    final list = _filteredRequests;

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded,
                size: 64, color: EnergyDashboardTheme.textMuted),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty || _statusFilter != null
                  ? 'لا توجد نتائج مطابقة'
                  : 'لا توجد طلبات خدمة',
              style: TextStyle(
                  fontSize: 16, color: EnergyDashboardTheme.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final req = list[index];
        return _buildRequestCard(req);
      },
    );
  }

  Widget _buildRequestCard(ServiceRequestModel req) {
    // Parse details to get customer info
    String customerName = req.citizenName ?? '';
    String customerPhone = req.citizenPhone ?? req.details ?? '';
    if (req.details != null) {
      try {
        final details = json.decode(req.details!);
        if (details is Map) {
          customerName = details['customerName'] ?? customerName;
          customerPhone = details['customerPhone'] ?? customerPhone;
        }
      } catch (_) {}
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: EnergyDashboardTheme.borderColor),
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedRequest = req),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // أيقونة الحالة
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: req.status.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(req.status.icon, color: req.status.color, size: 24),
              ),
              const SizedBox(width: 16),
              // المعلومات
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          req.requestNumber,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: req.status.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            req.status.nameAr,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: req.status.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${req.serviceName ?? 'خدمة'} - ${customerName.isNotEmpty ? customerName : 'غير محدد'}',
                      style: TextStyle(
                        color: EnergyDashboardTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    if (customerPhone.isNotEmpty &&
                        !customerPhone.startsWith('{'))
                      Text(
                        customerPhone,
                        style: TextStyle(
                          color: EnergyDashboardTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              // التكلفة والتاريخ
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (req.estimatedCost != null && req.estimatedCost! > 0)
                    Text(
                      '${req.estimatedCost!.toStringAsFixed(0)} د.ع',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: EnergyDashboardTheme.neonGreen,
                      ),
                    ),
                  Text(
                    _formatDate(req.requestedAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: EnergyDashboardTheme.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_left,
                  color: EnergyDashboardTheme.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailView() {
    final req = _selectedRequest!;
    // Parse details JSON
    Map<String, dynamic> details = {};
    if (req.details != null) {
      try {
        final parsed = json.decode(req.details!);
        if (parsed is Map) details = Map<String, dynamic>.from(parsed);
      } catch (_) {}
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // بطاقة الحالة الرئيسية
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: req.status.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: req.status.color.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: req.status.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      Icon(req.status.icon, color: req.status.color, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.requestNumber,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'الحالة: ${req.status.nameAr}',
                        style: TextStyle(
                          color: req.status.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // أزرار تغيير الحالة والحذف
                Row(
                  children: [
                    _buildStatusActions(req),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _showAssignDialog(req),
                      icon: const Icon(Icons.person_add, size: 16),
                      label: const Text('تعيين لموظف',
                          style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _showDeleteDialog(req),
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent),
                      tooltip: 'حذف الطلب نهائياً',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.redAccent.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // بطاقات المعلومات
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // معلومات الخدمة
              Expanded(
                child: _buildInfoCard(
                  'معلومات الخدمة',
                  Icons.miscellaneous_services,
                  [
                    _detailRow('الخدمة', req.serviceName ?? '-'),
                    _detailRow('نوع العملية', req.operationTypeName ?? '-'),
                    _detailRow('الأولوية', req.priority.nameAr),
                    if (req.estimatedCost != null)
                      _detailRow('التكلفة المتوقعة',
                          '${req.estimatedCost!.toStringAsFixed(0)} د.ع'),
                    if (req.finalCost != null)
                      _detailRow('التكلفة النهائية',
                          '${req.finalCost!.toStringAsFixed(0)} د.ع'),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // معلومات العميل (من details JSON)
              Expanded(
                child: _buildInfoCard(
                  'معلومات العميل/الوكيل',
                  Icons.person,
                  [
                    _detailRow('الاسم',
                        details['customerName'] ?? req.citizenName ?? '-'),
                    _detailRow('الهاتف',
                        details['customerPhone'] ?? req.citizenPhone ?? '-'),
                    if (details['agentCode'] != null)
                      _detailRow('كود الوكيل', details['agentCode']),
                    if (details['agentName'] != null)
                      _detailRow('اسم الوكيل', details['agentName']),
                    if (details['source'] != null)
                      _detailRow(
                          'المصدر',
                          details['source'] == 'agent_portal'
                              ? 'بوابة الوكيل'
                              : details['source']),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // العنوان والموقع
              Expanded(
                child: _buildInfoCard(
                  'العنوان والموقع',
                  Icons.location_on,
                  [
                    _detailRow('العنوان', req.address ?? '-'),
                    if (details['latitude'] != null && details['longitude'] != null)
                      _detailRow('الإحداثيات', '${details["latitude"]}, ${details["longitude"]}'),
                    if (details['locationUrl'] != null)
                      _detailRow('رابط الموقع', details['locationUrl']),
                    if (details['notes'] != null && details['notes'].toString().isNotEmpty)
                      _detailRow('ملاحظات', details['notes']),
                    if (details['citizenCity'] != null)
                      _detailRow('المدينة', details['citizenCity']),
                    if (details['citizenAddress'] != null)
                      _detailRow('عنوان المواطن', details['citizenAddress']),
                    if (details['planName'] != null) ...[
                      _detailRow('الباقة', details['planName']),
                      if (details['planSpeed'] != null)
                        _detailRow('السرعة', '${details["planSpeed"]} Mbps'),
                      if (details['monthlyPrice'] != null)
                        _detailRow(
                            'السعر الشهري', '${details["monthlyPrice"]} د.ع'),
                      if (details['installationFee'] != null)
                        _detailRow('رسوم التركيب',
                            '${details["installationFee"]} د.ع'),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // التواريخ
              Expanded(
                child: _buildInfoCard(
                  'التواريخ',
                  Icons.calendar_today,
                  [
                    _detailRow('تاريخ الطلب', _formatDate(req.requestedAt)),
                    if (req.assignedAt != null)
                      _detailRow('تاريخ التعيين', _formatDate(req.assignedAt!)),
                    if (req.completedAt != null)
                      _detailRow(
                          'تاريخ الإكمال', _formatDate(req.completedAt!)),
                    if (req.assignedToName != null)
                      _detailRow('معين لـ', req.assignedToName!),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: EnergyDashboardTheme.neonBlue),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: EnergyDashboardTheme.textPrimary,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                color: EnergyDashboardTheme.textMuted,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusActions(ServiceRequestModel req) {
    // Determine available next statuses
    final nextStatuses = _getNextStatuses(req.status);
    if (nextStatuses.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: nextStatuses.map((status) {
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ElevatedButton.icon(
            onPressed: () => _updateStatus(req.id, status),
            icon: Icon(status.icon, size: 16),
            label: Text(status.nameAr, style: const TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: status.color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  List<ServiceRequestStatus> _getNextStatuses(ServiceRequestStatus current) {
    switch (current) {
      case ServiceRequestStatus.pending:
        return [ServiceRequestStatus.reviewing, ServiceRequestStatus.rejected];
      case ServiceRequestStatus.reviewing:
        return [
          ServiceRequestStatus.approved,
          ServiceRequestStatus.inProgress,
          ServiceRequestStatus.rejected
        ];
      case ServiceRequestStatus.approved:
        return [ServiceRequestStatus.assigned, ServiceRequestStatus.inProgress];
      case ServiceRequestStatus.assigned:
        return [ServiceRequestStatus.inProgress];
      case ServiceRequestStatus.inProgress:
        return [ServiceRequestStatus.completed];
      case ServiceRequestStatus.onHold:
        return [ServiceRequestStatus.inProgress];
      default:
        return [];
    }
  }

  Future<void> _showDeleteDialog(ServiceRequestModel req) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الطلب نهائياً'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'هل أنت متأكد من حذف هذا الطلب نهائياً من قاعدة البيانات؟'),
              const SizedBox(height: 12),
              Text('رقم الطلب: ${req.requestNumber}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (req.serviceName != null) Text('الخدمة: ${req.serviceName}'),
              const SizedBox(height: 8),
              const Text(
                'تحذير: لا يمكن التراجع عن هذا الإجراء!',
                style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('حذف نهائي'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await _api.deleteServiceRequest(req.id);
        setState(() {
          _requests.removeWhere((r) => r.id == req.id);
          if (_selectedRequest?.id == req.id) _selectedRequest = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حذف الطلب نهائياً'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل الحذف'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _showAssignDialog(ServiceRequestModel req) async {
    // جلب بيانات الموظفين والأقسام
    Map<String, dynamic>? lookupData;
    try {
      lookupData = await _api.getTaskLookupData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل جلب بيانات الأقسام'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    final lookup = lookupData['data'] as Map<String, dynamic>? ?? {};
    final departments = (lookup['departments'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    String? selectedDepartment;
    String? selectedLeader;
    String? selectedTechnician;
    String? selectedTechnicianPhone;
    String? note;
    var leaders = <Map<String, dynamic>>[];
    var technicians = <Map<String, dynamic>>[];
    var techPhones = <String, String>{};
    bool isLoadingStaff = false;

    // دالة جلب الموظفين حسب القسم
    Future<void> fetchStaffByDepartment(
        String dept, StateSetter setDialogState) async {
      setDialogState(() {
        isLoadingStaff = true;
        selectedLeader = null;
        selectedTechnician = null;
        selectedTechnicianPhone = null;
        leaders = [];
        technicians = [];
        techPhones = {};
      });
      try {
        final staffData = await _api.getTaskStaff(department: dept);
        final staff = staffData['data'] as Map<String, dynamic>? ?? {};
        leaders = (staff['leaders'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        // نستخدم allStaff (كل موظفي القسم) بدلاً من technicians فقط
        technicians = (staff['allStaff'] as List<dynamic>? ?? staff['technicians'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        techPhones = {};
        for (var t in technicians) {
          techPhones[t['Name']?.toString() ?? ''] =
              t['PhoneNumber']?.toString() ?? '';
        }
      } catch (_) {}
      setDialogState(() => isLoadingStaff = false);
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Row(
                  children: [
                    const Icon(Icons.person_add, color: Colors.indigo),
                    const SizedBox(width: 8),
                    Text('تعيين الطلب ${req.requestNumber} لموظف'),
                  ],
                ),
                content: SizedBox(
                  width: 450,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // القسم
                        DropdownButtonFormField<String>(
                          value: selectedDepartment,
                          decoration: const InputDecoration(
                            labelText: 'القسم',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.business),
                          ),
                          items: departments.map((d) {
                            return DropdownMenuItem<String>(
                              value: d['nameAr']?.toString() ??
                                  d['name']?.toString() ??
                                  '',
                              child: Text(d['nameAr']?.toString() ??
                                  d['name']?.toString() ??
                                  ''),
                            );
                          }).toList(),
                          onChanged: (v) {
                            setDialogState(() => selectedDepartment = v);
                            if (v != null)
                              fetchStaffByDepartment(v, setDialogState);
                          },
                        ),
                        const SizedBox(height: 12),
                        if (isLoadingStaff)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        if (!isLoadingStaff && selectedDepartment != null) ...[
                          // القائد
                          DropdownButtonFormField<String>(
                            value: selectedLeader,
                            decoration: const InputDecoration(
                              labelText: 'القائد / الليدر',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.supervisor_account),
                            ),
                            items: leaders.map((l) {
                              return DropdownMenuItem<String>(
                                value: l['Name']?.toString() ?? '',
                                child: Text(l['Name']?.toString() ?? ''),
                              );
                            }).toList(),
                            onChanged: (v) =>
                                setDialogState(() => selectedLeader = v),
                          ),
                          const SizedBox(height: 12),
                          // الفني
                          DropdownButtonFormField<String>(
                            value: selectedTechnician,
                            decoration: const InputDecoration(
                              labelText: 'الفني المسؤول',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.engineering),
                            ),
                            items: technicians.map((t) {
                              return DropdownMenuItem<String>(
                                value: t['Name']?.toString() ?? '',
                                child: Text(
                                    '${t["Name"] ?? ""} - ${t["PhoneNumber"] ?? ""}'),
                              );
                            }).toList(),
                            onChanged: (v) {
                              setDialogState(() {
                                selectedTechnician = v;
                                selectedTechnicianPhone =
                                    techPhones[v ?? ''] ?? '';
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          // ملاحظة
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'ملاحظة (اختياري)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.note),
                            ),
                            maxLines: 2,
                            onChanged: (v) => note = v,
                          ),
                        ],
                        if (!isLoadingStaff &&
                            selectedDepartment != null &&
                            technicians.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'لا يوجد فنيين في قسم "$selectedDepartment"',
                              style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton.icon(
                    onPressed:
                        selectedTechnician != null || selectedLeader != null
                            ? () => Navigator.of(ctx).pop(true)
                            : null,
                    icon: const Icon(Icons.check),
                    label: const Text('تعيين'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed == true) {
      try {
        await _api.assignTask(
          req.id,
          department: selectedDepartment,
          leader: selectedLeader,
          technician: selectedTechnician,
          technicianPhone: selectedTechnicianPhone,
          note: note,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'تم تعيين الطلب للفني: ${selectedTechnician ?? selectedLeader ?? "غير محدد"}'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _loadData();
        if (_selectedRequest != null) {
          final updated = _requests.where((r) => r.id == req.id).firstOrNull;
          if (updated != null) setState(() => _selectedRequest = updated);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('فشل التعيين'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _updateStatus(
      String requestId, ServiceRequestStatus newStatus) async {
    try {
      await _api.updateServiceRequestStatus(
        requestId,
        newStatus.name,
        notes: null,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تحديث الحالة إلى: ${newStatus.nameAr}'),
          backgroundColor: Colors.green,
        ),
      );

      // Reload data
      await _loadData();
      // Re-select the same request to refresh detail
      if (_selectedRequest != null) {
        final updated = _requests.where((r) => r.id == requestId).firstOrNull;
        if (updated != null) {
          setState(() => _selectedRequest = updated);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
