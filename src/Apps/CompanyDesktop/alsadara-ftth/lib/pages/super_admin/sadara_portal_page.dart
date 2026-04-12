/// صفحة منصة الصدارة - طلبات المواطن والوكيل
/// تعرض جميع طلبات الخدمة مقسمة بتبويبين: المواطن والوكيل
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/accounting_theme.dart';
import '../../services/sadara_api_service.dart';
import '../../services/vps_auth_service.dart';
import '../citizen_portal/models/citizen_portal_models.dart';
import 'agents_management_page.dart';

class SadaraPortalPage extends StatefulWidget {
  const SadaraPortalPage({super.key});

  @override
  State<SadaraPortalPage> createState() => _SadaraPortalPageState();
}

class _SadaraPortalPageState extends State<SadaraPortalPage>
    with SingleTickerProviderStateMixin {
  final SadaraApiService _api = SadaraApiService.instance;
  late TabController _tabController;

  bool _isLoading = true;
  bool _isLoadingDetail = false;
  String? _errorMessage;
  List<ServiceRequestModel> _allRequests = [];
  String _searchQuery = '';
  ServiceRequestStatus? _statusFilter;
  ServiceRequestModel? _selectedRequest;

  // إحصائيات
  int _citizenCount = 0;
  int _agentCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedRequest = null;
          _searchQuery = '';
          _statusFilter = null;
        });
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // محاولة تحديث التوكن إذا لم يكن صالحاً
      if (!_api.isAuthenticated) {
        final vps = VpsAuthService.instance;
        debugPrint('🔍 SadaraPortal: API not authenticated, checking VPS...');
        debugPrint(
            '   VPS token: ${vps.accessToken != null ? "exists (${vps.accessToken!.length} chars)" : "NULL"}');
        if (vps.accessToken == null) {
          debugPrint('   Attempting restoreSession...');
          await vps.restoreSession();
        }
        if (vps.accessToken == null) {
          await vps.refreshAccessToken();
        }
      }

      final results = await _api.getServiceRequests(page: 1, pageSize: 200, serviceId: 11);
      final requests = results.map((r) {
        if (r is Map<String, dynamic>) {
          return ServiceRequestModel.fromJson(r);
        }
        return ServiceRequestModel.fromJson({});
      }).toList();

      if (!mounted) return;
      setState(() {
        _allRequests = requests;
        _citizenCount = _getCitizenRequests(requests).length;
        _agentCount = _getAgentRequests(requests).length;
        _isLoading = false;
      });
    } catch (e) {
      // إذا كان خطأ 401، حاول تحديث التوكن ثم إعادة المحاولة
      if (e.toString().contains('401') || e.toString().contains('صلاحية')) {
        try {
          final refreshed = await VpsAuthService.instance.refreshAccessToken();
          if (refreshed) {
            final results =
                await _api.getServiceRequests(page: 1, pageSize: 200, serviceId: 11);
            final requests = results.map((r) {
              if (r is Map<String, dynamic>) {
                return ServiceRequestModel.fromJson(r);
              }
              return ServiceRequestModel.fromJson({});
            }).toList();
            if (!mounted) return;
            setState(() {
              _allRequests = requests;
              _citizenCount = _getCitizenRequests(requests).length;
              _agentCount = _getAgentRequests(requests).length;
              _isLoading = false;
            });
            return;
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _errorMessage = 'حدث خطأ';
        _isLoading = false;
      });
    }
  }

  /// جلب تفاصيل الطلب (مع سجل الحالات) واختياره
  Future<void> _selectRequest(ServiceRequestModel req) async {
    setState(() {
      _selectedRequest = req;
      _isLoadingDetail = true;
    });
    try {
      final result = await _api.getServiceRequest(req.id);
      final data = result['data'] ?? result;
      if (data is Map<String, dynamic>) {
        final detailed = ServiceRequestModel.fromJson(data);
        if (mounted) {
          setState(() {
            _selectedRequest = detailed;
            _isLoadingDetail = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingDetail = false);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load detail');
      if (mounted) setState(() => _isLoadingDetail = false);
    }
  }

  /// تحديد مصدر الطلب من حقل Details JSON
  String _getSource(ServiceRequestModel req) {
    if (req.details != null) {
      try {
        final details = json.decode(req.details!);
        if (details is Map && details['source'] != null) {
          return details['source'].toString().toLowerCase();
        }
      } catch (_) {}
    }
    return 'citizen_portal'; // افتراضي: مواطن
  }

  List<ServiceRequestModel> _getCitizenRequests(
      List<ServiceRequestModel> list) {
    return list.where((r) {
      final source = _getSource(r);
      return source != 'agent_portal';
    }).toList();
  }

  List<ServiceRequestModel> _getAgentRequests(List<ServiceRequestModel> list) {
    return list.where((r) {
      final source = _getSource(r);
      return source == 'agent_portal';
    }).toList();
  }

  List<ServiceRequestModel> get _currentTabRequests {
    final isAgent = _tabController.index == 1;
    var list = isAgent
        ? _getAgentRequests(_allRequests)
        : _getCitizenRequests(_allRequests);

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
            _getAgentName(r).toLowerCase().contains(q) ||
            _getAgentCode(r).toLowerCase().contains(q);
      }).toList();
    }
    return list;
  }

  String _getAgentName(ServiceRequestModel req) {
    if (req.details != null) {
      try {
        final details = json.decode(req.details!);
        if (details is Map) return details['agentName'] ?? '';
      } catch (_) {}
    }
    return '';
  }

  String _getAgentCode(ServiceRequestModel req) {
    if (req.details != null) {
      try {
        final details = json.decode(req.details!);
        if (details is Map) return details['agentCode'] ?? '';
      } catch (_) {}
    }
    return '';
  }

  Map<String, dynamic> _parseDetails(ServiceRequestModel req) {
    if (req.details != null) {
      try {
        final parsed = json.decode(req.details!);
        if (parsed is Map) return Map<String, dynamic>.from(parsed);
      } catch (_) {}
    }
    return {};
  }

  /// استخراج نوع العملية من حقل details إذا لم يكن متاحاً من API
  String? _getOperationTypeFromDetails(Map<String, dynamic> details) {
    final type = details['type']?.toString().toLowerCase();
    if (type == null) return null;
    switch (type) {
      case 'balance_request':
        return 'طلب رصيد';
      case 'debt_payment':
        return 'تسديد حساب';
      case 'master_recharge':
        return 'شحن ماستر';
      case 'subscription_activation':
        return 'تفعيل اشتراك';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: AccountingTheme.bgPrimary,
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            if (_selectedRequest == null) _buildStatsRow(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? _buildError()
                      : _selectedRequest != null
                          ? _buildDetailView()
                          : _buildRequestsList(),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // الهيدر
  // ══════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(
          bottom: BorderSide(color: AccountingTheme.borderColor),
        ),
      ),
      child: Row(
        children: [
          // زر العودة
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AccountingTheme.bgSecondary,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AccountingTheme.borderColor),
                ),
                child: Icon(Icons.arrow_back_rounded,
                    size: 18, color: AccountingTheme.textSecondary),
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (_selectedRequest != null) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              onPressed: () => setState(() => _selectedRequest = null),
              tooltip: 'رجوع',
            ),
            const SizedBox(width: 4),
          ],
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667eea), Color(0xFF764ba2)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.hub_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            _selectedRequest != null
                ? 'تفاصيل الطلب: ${_selectedRequest!.requestNumber}'
                : 'منصة الصدارة',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AccountingTheme.textPrimary,
            ),
          ),
          const Spacer(),
          if (_selectedRequest == null) ...[
            // بحث
            SizedBox(
              width: 240,
              height: 36,
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'بحث...',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: AccountingTheme.textMuted,
                  ),
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: AccountingTheme.textMuted),
                  filled: true,
                  fillColor: AccountingTheme.bgPrimary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AccountingTheme.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AccountingTheme.borderColor),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // فلتر الحالة
            PopupMenuButton<ServiceRequestStatus?>(
              icon: Badge(
                isLabelVisible: _statusFilter != null,
                child: const Icon(Icons.filter_list, size: 20),
              ),
              tooltip: 'فلتر الحالة',
              onSelected: (value) => setState(() => _statusFilter = value),
              itemBuilder: (context) => [
                const PopupMenuItem(value: null, child: Text('الكل')),
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
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _loadData,
              tooltip: 'تحديث',
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // التبويبات
  // ══════════════════════════════════════════════════════════

  Widget _buildTabBar() {
    if (_selectedRequest != null) return const SizedBox.shrink();

    final selectedIndex = _tabController.index;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(
          bottom: BorderSide(color: AccountingTheme.borderColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // تبويب المواطن
          GestureDetector(
            onTap: () => setState(() => _tabController.index = 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: selectedIndex == 0
                    ? AccountingTheme.neonBlue.withOpacity(0.12)
                    : AccountingTheme.bgSecondary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selectedIndex == 0
                      ? AccountingTheme.neonBlue
                      : AccountingTheme.borderColor,
                  width: selectedIndex == 0 ? 2 : 1,
                ),
                boxShadow: selectedIndex == 0
                    ? [
                        BoxShadow(
                          color: AccountingTheme.neonBlue.withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_rounded,
                      size: 20,
                      color: selectedIndex == 0
                          ? AccountingTheme.neonBlue
                          : AccountingTheme.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    'المواطن',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selectedIndex == 0
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: selectedIndex == 0
                          ? AccountingTheme.neonBlue
                          : AccountingTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: selectedIndex == 0
                          ? AccountingTheme.neonBlue.withOpacity(0.2)
                          : AccountingTheme.borderColor.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$_citizenCount',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: selectedIndex == 0
                            ? AccountingTheme.neonBlue
                            : AccountingTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // فاصل
          Container(
            width: 1,
            height: 30,
            color: AccountingTheme.borderColor,
          ),
          const SizedBox(width: 16),
          // تبويب الوكيل
          GestureDetector(
            onTap: () => setState(() => _tabController.index = 1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: selectedIndex == 1
                    ? AccountingTheme.neonPink.withOpacity(0.12)
                    : AccountingTheme.bgSecondary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selectedIndex == 1
                      ? AccountingTheme.neonPink
                      : AccountingTheme.borderColor,
                  width: selectedIndex == 1 ? 2 : 1,
                ),
                boxShadow: selectedIndex == 1
                    ? [
                        BoxShadow(
                          color: AccountingTheme.neonPink.withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storefront_rounded,
                      size: 20,
                      color: selectedIndex == 1
                          ? AccountingTheme.neonPink
                          : AccountingTheme.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    'الوكيل',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selectedIndex == 1
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: selectedIndex == 1
                          ? AccountingTheme.neonPink
                          : AccountingTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: selectedIndex == 1
                          ? AccountingTheme.neonPink.withOpacity(0.2)
                          : AccountingTheme.borderColor.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$_agentCount',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: selectedIndex == 1
                            ? AccountingTheme.neonPink
                            : AccountingTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // إحصائيات سريعة
  // ══════════════════════════════════════════════════════════

  Widget _buildStatsRow() {
    // نستخدم القائمة بدون فلتر الحالة لإظهار الأعداد الحقيقية دائماً
    final isAgent = _tabController.index == 1;
    final allList = isAgent
        ? _getAgentRequests(_allRequests)
        : _getCitizenRequests(_allRequests);
    // تطبيق فلتر البحث فقط (بدون فلتر الحالة)
    var list = allList;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((r) {
        return r.requestNumber.toLowerCase().contains(q) ||
            (r.citizenName?.toLowerCase().contains(q) ?? false) ||
            (r.citizenPhone?.toLowerCase().contains(q) ?? false) ||
            (r.serviceName?.toLowerCase().contains(q) ?? false) ||
            (r.address?.toLowerCase().contains(q) ?? false) ||
            _getAgentName(r).toLowerCase().contains(q) ||
            _getAgentCode(r).toLowerCase().contains(q);
      }).toList();
    }

    final pending =
        list.where((r) => r.status == ServiceRequestStatus.pending).length;
    final approved =
        list.where((r) => r.status == ServiceRequestStatus.approved).length;
    final assigned =
        list.where((r) => r.status == ServiceRequestStatus.assigned).length;
    final inProgress =
        list.where((r) => r.status == ServiceRequestStatus.inProgress).length;
    final completed =
        list.where((r) => r.status == ServiceRequestStatus.completed).length;
    final onHold =
        list.where((r) => r.status == ServiceRequestStatus.onHold).length;
    final cancelled =
        list.where((r) => r.status == ServiceRequestStatus.cancelled).length;
    final rejected =
        list.where((r) => r.status == ServiceRequestStatus.rejected).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AccountingTheme.bgSecondary,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildStatChip('الكل', list.length, AccountingTheme.neonBlue,
                Icons.list_alt, null),
            _buildStatChip('جديد', pending, Colors.blue, Icons.hourglass_empty,
                ServiceRequestStatus.pending),
            _buildStatChip('موافق عليه', approved, Colors.teal,
                Icons.check_circle_outline, ServiceRequestStatus.approved),
            _buildStatChip('تم التعيين', assigned, Colors.purple,
                Icons.person_add, ServiceRequestStatus.assigned),
            _buildStatChip('قيد التنفيذ', inProgress, Colors.indigo,
                Icons.engineering, ServiceRequestStatus.inProgress),
            _buildStatChip('مكتمل', completed, Colors.green, Icons.check_circle,
                ServiceRequestStatus.completed),
            _buildStatChip('معلق', onHold, Colors.amber, Icons.pause_circle,
                ServiceRequestStatus.onHold),
            _buildStatChip('ملغي', cancelled, Colors.grey, Icons.cancel,
                ServiceRequestStatus.cancelled),
            _buildStatChip('مرفوض', rejected, Colors.red, Icons.block,
                ServiceRequestStatus.rejected),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color, IconData icon,
      ServiceRequestStatus? status) {
    final isSelected = _statusFilter == status;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = status),
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.25) : color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : color.withOpacity(0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              '$label: $count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // قائمة الطلبات
  // ══════════════════════════════════════════════════════════

  Widget _buildRequestsList() {
    final list = _currentTabRequests;
    final isAgent = _tabController.index == 1;

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAgent ? Icons.storefront_rounded : Icons.person_rounded,
              size: 64,
              color: AccountingTheme.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty || _statusFilter != null
                  ? 'لا توجد نتائج مطابقة'
                  : isAgent
                      ? 'لا توجد طلبات من الوكلاء'
                      : 'لا توجد طلبات من المواطنين',
              style: TextStyle(
                fontSize: 16,
                color: AccountingTheme.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // تبويب المواطن
        _buildListView(_getCitizenRequests(_allRequests)),
        // تبويب الوكيل
        _buildListView(_getAgentRequests(_allRequests)),
      ],
    );
  }

  Widget _buildListView(List<ServiceRequestModel> sourceList) {
    // تطبيق الفلتر والبحث
    var list = sourceList;
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
            _getAgentName(r).toLowerCase().contains(q) ||
            _getAgentCode(r).toLowerCase().contains(q);
      }).toList();
    }

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded,
                size: 64, color: AccountingTheme.textMuted),
            const SizedBox(height: 16),
            Text(
              'لا توجد طلبات',
              style: TextStyle(
                fontSize: 16,
                color: AccountingTheme.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) => _buildRequestCard(list[index]),
    );
  }

  Widget _buildRequestCard(ServiceRequestModel req) {
    final details = _parseDetails(req);
    final isAgent = _getSource(req) == 'agent_portal';
    final customerName =
        details['customerName'] ?? req.citizenName ?? 'غير محدد';
    final customerPhone = details['customerPhone'] ?? req.citizenPhone ?? '';
    final agentName = details['agentName'] ?? req.agentName ?? '';
    final agentCode = details['agentCode'] ?? req.agentCode ?? '';
    final agentType = details['agentType'] ?? '';
    final pageId = details['pageId'] ?? '';

    // نوع العملية: من API أو من details
    final operationType =
        req.operationTypeName ?? _getOperationTypeFromDetails(details) ?? '';

    // المبلغ: من estimatedCost أو details
    final amount = req.estimatedCost ??
        (details['amount'] != null
            ? double.tryParse(details['amount'].toString())
            : null);

    // اسم الخدمة بالعربي
    final serviceName = req.serviceName ?? 'خدمة';

    // تحديد اللون حسب نوع العملية: تسديد = أخضر، طلبات = أحمر
    final isPayment = req.operationTypeId == 11 ||
        operationType.contains('تسديد') ||
        operationType.contains('دفع');
    final cardColor =
        isPayment ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final cardBgColor =
        isPayment ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2);
    final cardBorderColor =
        isPayment ? const Color(0xFF86EFAC) : const Color(0xFFFECACA);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: cardBgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cardBorderColor),
      ),
      child: InkWell(
        onTap: () => _selectRequest(req),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // أيقونة المصدر
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isAgent
                          ? AccountingTheme.neonPink
                          : AccountingTheme.neonBlue)
                      .withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isAgent ? Icons.storefront_rounded : Icons.person_rounded,
                  color: isAgent
                      ? AccountingTheme.neonPink
                      : AccountingTheme.neonBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              // المعلومات
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // سطر 1: نوع الوكيل + الاسم + معرف الصفحة + الحالة
                    if (isAgent)
                      Row(
                        children: [
                          if (agentType.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    AccountingTheme.neonPink.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                agentType,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AccountingTheme.neonPink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (agentName.isNotEmpty)
                            Text(
                              agentName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AccountingTheme.neonPink,
                              ),
                            ),
                          if (pageId.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              pageId,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AccountingTheme.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 3),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: pageId));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تم نسخ رقم الصفحة'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: const Icon(
                                Icons.copy_rounded,
                                size: 13,
                                color: AccountingTheme.textMuted,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: req.status.color.withOpacity(0.2),
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
                      )
                    else
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              customerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: req.status.color.withOpacity(0.2),
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
                    // سطر 2: نوع العملية + معلومات العميل (للاشتراكات)
                    Row(
                      children: [
                        if (operationType.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: cardColor.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              operationType,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: cardColor,
                              ),
                            ),
                          ),
                        // معلومات العميل (للاشتراكات)
                        if (isAgent &&
                            customerName.isNotEmpty &&
                            customerName != agentName &&
                            customerName != 'غير محدد') ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.person_outline,
                              size: 13, color: AccountingTheme.textMuted),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              customerName,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AccountingTheme.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 3),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: customerName));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم نسخ اسم العميل'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            child: const Icon(Icons.copy_rounded,
                                size: 12, color: AccountingTheme.textMuted),
                          ),
                          if (customerPhone.isNotEmpty &&
                              !customerPhone.startsWith('{')) ...[
                            const SizedBox(width: 6),
                            Text(
                              customerPhone,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AccountingTheme.textMuted,
                              ),
                            ),
                            const SizedBox(width: 3),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(
                                    ClipboardData(text: customerPhone));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تم نسخ رقم العميل'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: const Icon(Icons.copy_rounded,
                                  size: 12, color: AccountingTheme.textMuted),
                            ),
                          ],
                        ],
                        // رقم هاتف المواطن
                        if (!isAgent &&
                            customerPhone.isNotEmpty &&
                            !customerPhone.startsWith('{')) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.phone_outlined,
                              size: 12, color: AccountingTheme.textMuted),
                          const SizedBox(width: 3),
                          Text(
                            customerPhone,
                            style: const TextStyle(
                              color: AccountingTheme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                    // سطر 3: الصافي
                    if (isAgent && req.agentNetBalance != null) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: (req.agentNetBalance! >= 0
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFEF4444))
                              .withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'الصافي: ${req.agentNetBalance!.toStringAsFixed(0)} د.ع',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: req.agentNetBalance! >= 0
                                ? const Color(0xFF22C55E)
                                : const Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // التكلفة والتاريخ
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (amount != null && amount > 0)
                    Text(
                      '${isPayment ? "+" : "-"}${amount.toStringAsFixed(0)} د.ع',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: cardColor,
                      ),
                    ),
                  Text(
                    _formatDate(req.requestedAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AccountingTheme.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_left,
                  color: AccountingTheme.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // عرض التفاصيل
  // ══════════════════════════════════════════════════════════

  Widget _buildDetailView() {
    final req = _selectedRequest!;
    final details = _parseDetails(req);
    final isAgent = _getSource(req) == 'agent_portal';

    // نوع العملية
    final operationType =
        req.operationTypeName ?? _getOperationTypeFromDetails(details) ?? '-';

    // المبلغ
    final amount = req.estimatedCost ??
        (details['amount'] != null
            ? double.tryParse(details['amount'].toString())
            : null);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ══════ بطاقة الحالة + ملخص مدمجان ══════
          _buildCompactStatusCard(req, details, amount, isAgent),
          const SizedBox(height: 14),

          // ══════ 3 أعمدة للمعلومات ══════
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // العمود 1: معلومات الخدمة والتفاصيل
                Expanded(
                  child: Column(
                    children: [
                      _buildInfoCard(
                        'معلومات الخدمة',
                        Icons.miscellaneous_services_rounded,
                        AccountingTheme.neonBlue,
                        [
                          _buildDetailItem(Icons.wifi_rounded, 'الخدمة',
                              req.serviceName ?? '-', AccountingTheme.neonBlue),
                          _buildDetailItem(
                              Icons.category_rounded,
                              'نوع العملية',
                              operationType,
                              AccountingTheme.neonPurple),
                          _buildDetailItem(
                              Icons.flag_rounded,
                              'الأولوية',
                              req.priority.nameAr,
                              _getPriorityColor(req.priority)),
                          if (details['planName'] != null)
                            _buildDetailItem(Icons.wifi_rounded, 'الباقة',
                                details['planName'], AccountingTheme.neonBlue),
                          if (details['planSpeed'] != null)
                            _buildDetailItem(
                                Icons.speed_rounded,
                                'السرعة',
                                '${details["planSpeed"]} Mbps',
                                AccountingTheme.neonPurple),
                          if (details['monthlyPrice'] != null)
                            _buildDetailItem(
                                Icons.calendar_month_rounded,
                                'السعر الشهري',
                                '${_formatAmount(double.tryParse(details["monthlyPrice"].toString()) ?? 0)} د.ع',
                                AccountingTheme.neonGreen),
                          if (details['installationFee'] != null)
                            _buildDetailItem(
                                Icons.construction_rounded,
                                'رسوم التركيب',
                                '${_formatAmount(double.tryParse(details["installationFee"].toString()) ?? 0)} د.ع',
                                AccountingTheme.neonOrange),
                          if (details['subscriptionDuration'] != null)
                            _buildDetailItem(
                                Icons.date_range_rounded,
                                'فترة الاشتراك',
                                _formatDuration(
                                    details['subscriptionDuration']),
                                AccountingTheme.neonPink),
                          if (amount != null)
                            _buildDetailItem(
                                Icons.payments_rounded,
                                'المبلغ',
                                '${_formatAmount(amount)} د.ع',
                                AccountingTheme.neonGreen),
                          if (req.finalCost != null)
                            _buildDetailItem(
                                Icons.price_check_rounded,
                                'التكلفة النهائية',
                                '${_formatAmount(req.finalCost!)} د.ع',
                                AccountingTheme.success),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInfoCard(
                        'التواريخ',
                        Icons.calendar_today_rounded,
                        AccountingTheme.neonGreen,
                        [
                          _buildDetailItem(
                              Icons.schedule_rounded,
                              'تاريخ الطلب',
                              _formatDateFull(req.requestedAt),
                              AccountingTheme.neonBlue),
                          if (req.assignedAt != null)
                            _buildDetailItem(
                                Icons.assignment_ind_rounded,
                                'تاريخ التعيين',
                                _formatDateFull(req.assignedAt!),
                                AccountingTheme.neonPurple),
                          if (req.completedAt != null)
                            _buildDetailItem(
                                Icons.check_circle_outline_rounded,
                                'تاريخ الإكمال',
                                _formatDateFull(req.completedAt!),
                                AccountingTheme.success),
                          if (req.assignedToName != null)
                            _buildDetailItem(
                                Icons.person_pin_rounded,
                                'معين لـ',
                                req.assignedToName!,
                                AccountingTheme.neonPink),
                          if (req.statusNote != null &&
                              req.statusNote!.isNotEmpty)
                            _buildDetailItem(
                                Icons.comment_rounded,
                                'ملاحظة الحالة',
                                req.statusNote!,
                                AccountingTheme.neonOrange),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // العمود 2: معلومات العميل/الوكيل
                Expanded(
                  child: _buildInfoCard(
                    isAgent ? 'معلومات الوكيل والعميل' : 'معلومات المواطن',
                    isAgent ? Icons.storefront_rounded : Icons.person_rounded,
                    isAgent
                        ? AccountingTheme.neonPink
                        : AccountingTheme.neonPurple,
                    [
                      _buildDetailItem(
                          Icons.person_outline_rounded,
                          'اسم العميل',
                          details['customerName'] ?? req.citizenName ?? '-',
                          AccountingTheme.neonBlue),
                      _buildDetailItem(
                          Icons.phone_rounded,
                          'هاتف العميل',
                          details['customerPhone'] ?? req.citizenPhone ?? '-',
                          AccountingTheme.neonGreen),
                      if (isAgent) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 3),
                          child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                        ),
                        _buildDetailItem(
                            Icons.badge_rounded,
                            'رقم المعرف',
                            details['pageId'] ?? '-',
                            AccountingTheme.neonOrange),
                        _buildAgentNameRow(
                            details['agentName'] ?? '-', req.agentId),
                        _buildDetailItem(
                            Icons.business_center_rounded,
                            'نوع الوكيل',
                            details['agentType'] ?? '-',
                            AccountingTheme.neonPurple),
                      ],
                      _buildDetailItem(
                          Icons.source_rounded,
                          'المصدر',
                          isAgent ? 'بوابة الوكيل' : 'بوابة المواطن',
                          isAgent
                              ? AccountingTheme.neonPink
                              : AccountingTheme.neonBlue),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // العمود 3: العنوان والملاحظات + معلومات المهمة
                Expanded(
                  child: Column(
                    children: [
                      _buildInfoCard(
                        'العنوان',
                        Icons.location_on_rounded,
                        AccountingTheme.neonOrange,
                        [
                          _buildDetailItem(Icons.map_rounded, 'العنوان',
                              req.address ?? '-', AccountingTheme.neonOrange),
                          if (details['latitude'] != null && details['longitude'] != null) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                height: 200,
                                child: FlutterMap(
                                  options: MapOptions(
                                    initialCenter: LatLng(
                                      (details['latitude'] as num).toDouble(),
                                      (details['longitude'] as num).toDouble(),
                                    ),
                                    initialZoom: 15,
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName: 'com.sadara.ftth',
                                    ),
                                    MarkerLayer(markers: [
                                      Marker(
                                        point: LatLng(
                                          (details['latitude'] as num).toDouble(),
                                          (details['longitude'] as num).toDouble(),
                                        ),
                                        width: 40,
                                        height: 40,
                                        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                                      ),
                                    ]),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () => launchUrl(Uri.parse(details['locationUrl'] ?? 'https://www.google.com/maps?q=${details["latitude"]},${details["longitude"]}')),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.open_in_new, size: 14, color: Colors.blue[700]),
                                  const SizedBox(width: 4),
                                  Text('فتح في Google Maps', style: TextStyle(color: Colors.blue[700], fontSize: 12, decoration: TextDecoration.underline)),
                                ],
                              ),
                            ),
                          ],
                          if (details['notes'] != null && details['notes'].toString().isNotEmpty)
                            _buildDetailItem(Icons.note_alt_rounded, 'ملاحظات',
                                details['notes'], AccountingTheme.textMuted),
                        ],
                      ),
                      // معلومات المهمة (FBG, FAT, القسم, الفني)
                      if (details['department'] != null ||
                          details['fbg'] != null ||
                          details['technician'] != null) ...[
                        const SizedBox(height: 12),
                        _buildInfoCard(
                          'تفاصيل المهمة',
                          Icons.engineering_rounded,
                          AccountingTheme.neonPink,
                          [
                            if (details['taskType'] != null)
                              _buildDetailItem(
                                  Icons.category_rounded,
                                  'نوع المهمة',
                                  details['taskType'],
                                  AccountingTheme.neonPurple),
                            if (details['department'] != null)
                              _buildDetailItem(
                                  Icons.business_rounded,
                                  'القسم',
                                  details['department'],
                                  AccountingTheme.neonBlue),
                            if (details['leader'] != null)
                              _buildDetailItem(
                                  Icons.supervisor_account_rounded,
                                  'القائد',
                                  details['leader'],
                                  AccountingTheme.neonGreen),
                            if (details['technician'] != null)
                              _buildDetailItem(
                                  Icons.engineering_rounded,
                                  'الفني',
                                  details['technician'],
                                  AccountingTheme.neonPink),
                            if (details['technicianPhone'] != null)
                              _buildDetailItem(
                                  Icons.phone_android_rounded,
                                  'هاتف الفني',
                                  details['technicianPhone'],
                                  AccountingTheme.neonGreen),
                            if (details['fbg'] != null &&
                                details['fbg'].toString().isNotEmpty)
                              _buildDetailItem(Icons.dns_rounded, 'FBG',
                                  details['fbg'], AccountingTheme.neonOrange),
                            if (details['fat'] != null &&
                                details['fat'].toString().isNotEmpty)
                              _buildDetailItem(Icons.cable_rounded, 'FAT',
                                  details['fat'], AccountingTheme.neonBlue),
                            if (details['summary'] != null &&
                                details['summary'].toString().isNotEmpty)
                              _buildDetailItem(
                                  Icons.summarize_rounded,
                                  'الملخص',
                                  details['summary'],
                                  AccountingTheme.textMuted),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ══════ سجل الحالات (Timeline) ══════
          const SizedBox(height: 14),
          _buildStatusTimeline(req),

          // ══════ أزرار WhatsApp ══════
          if (_hasContactInfo(details, req)) ...[
            const SizedBox(height: 14),
            _buildWhatsAppBar(req, details),
          ],
        ],
      ),
    );
  }

  // ═══════ WhatsApp ═══════

  bool _hasContactInfo(Map<String, dynamic> details, ServiceRequestModel req) {
    return (details['customerPhone'] != null &&
            details['customerPhone'].toString().isNotEmpty) ||
        (req.citizenPhone != null && req.citizenPhone!.isNotEmpty) ||
        (details['technicianPhone'] != null &&
            details['technicianPhone'].toString().isNotEmpty);
  }

  Widget _buildWhatsAppBar(
      ServiceRequestModel req, Map<String, dynamic> details) {
    final customerPhone =
        details['customerPhone']?.toString() ?? req.citizenPhone ?? '';
    final technicianPhone = details['technicianPhone']?.toString() ?? '';
    final customerName =
        details['customerName']?.toString() ?? req.citizenName ?? 'العميل';
    final technicianName = details['technician']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF25D366).withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF25D366).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 20),
          const SizedBox(width: 8),
          const Text('واتساب',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF25D366))),
          const SizedBox(width: 16),
          if (customerPhone.isNotEmpty)
            _buildWhatsAppButton(
              label: 'العميل ($customerName)',
              phone: customerPhone,
              message: _buildCustomerWhatsAppMessage(req, details),
              icon: Icons.person_rounded,
            ),
          if (customerPhone.isNotEmpty && technicianPhone.isNotEmpty)
            const SizedBox(width: 8),
          if (technicianPhone.isNotEmpty)
            _buildWhatsAppButton(
              label: 'الفني ($technicianName)',
              phone: technicianPhone,
              message: _buildTechnicianWhatsAppMessage(req, details),
              icon: Icons.engineering_rounded,
            ),
          const Spacer(),
          if (customerPhone.isNotEmpty)
            IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: customerPhone));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('تم نسخ رقم العميل'),
                      duration: Duration(seconds: 1)),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              tooltip: 'نسخ رقم العميل',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: const EdgeInsets.all(4),
            ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppButton({
    required String label,
    required String phone,
    required String message,
    required IconData icon,
  }) {
    return OutlinedButton.icon(
      onPressed: () => _sendWhatsApp(phone, message),
      icon: Icon(icon, size: 14, color: const Color(0xFF25D366)),
      label: Text(label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF25D366))),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Color(0xFF25D366), width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        minimumSize: const Size(0, 30),
      ),
    );
  }

  String _buildCustomerWhatsAppMessage(
      ServiceRequestModel req, Map<String, dynamic> details) {
    final customerName =
        details['customerName']?.toString() ?? req.citizenName ?? 'العميل';
    String msg = '🔔 تحديث طلبك - ${req.requestNumber}\n';
    msg += '════════════════════════\n\n';
    msg += '👤 عزيزي/عزيزتي $customerName\n\n';
    msg += '📋 حالة الطلب: ${req.status.nameAr}\n';
    if (details['taskType'] != null) {
      msg += '🔧 نوع المهمة: ${details["taskType"]}\n';
    }
    if (req.serviceName != null) {
      msg += '📡 الخدمة: ${req.serviceName}\n';
    }
    msg += '\n────────────────────────\n';
    msg += '🚀 شركة الصدارة للاتصالات';
    return msg;
  }

  String _buildTechnicianWhatsAppMessage(
      ServiceRequestModel req, Map<String, dynamic> details) {
    final customerName =
        details['customerName']?.toString() ?? req.citizenName ?? 'العميل';
    final customerPhone = details['customerPhone']?.toString() ?? '';
    String msg = '🔔 مهمة جديدة - ${req.requestNumber}\n';
    msg += '════════════════════════\n\n';
    msg += '👤 معلومات العميل:\n';
    msg += '• الاسم: $customerName\n';
    if (customerPhone.isNotEmpty) msg += '• الهاتف: $customerPhone\n';
    if (req.address != null) msg += '• العنوان: ${req.address}\n';
    if (details['taskType'] != null) {
      msg += '\n🔧 تفاصيل المهمة:\n';
      msg += '• النوع: ${details["taskType"]}\n';
    }
    if (details['fbg'] != null) msg += '• FBG: ${details["fbg"]}\n';
    if (details['fat'] != null) msg += '• FAT: ${details["fat"]}\n';
    if (details['serviceType'] != null) {
      msg += '• سرعة الخدمة: ${details["serviceType"]} Mbps\n';
    }
    if (details['notes'] != null && details['notes'].toString().isNotEmpty) {
      msg += '\n📝 ملاحظات: ${details["notes"]}\n';
    }
    msg += '\n────────────────────────\n';
    msg += '⏰ ${DateTime.now().toString().split('.')[0]}\n';
    msg += '🚀 يرجى البدء في تنفيذ المهمة';
    return msg;
  }

  Future<void> _sendWhatsApp(String phone, String message) async {
    try {
      String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanPhone.length < 8) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('رقم الهاتف غير صحيح'),
                backgroundColor: Colors.red),
          );
        }
        return;
      }
      if (!cleanPhone.startsWith('964')) cleanPhone = '964$cleanPhone';

      await Clipboard.setData(ClipboardData(text: message));

      String cleanMessage =
          message.replaceAll('&', 'و').replaceAll('+', 'زائد');
      final encodedMessage = Uri.encodeComponent(cleanMessage);

      final urls = [
        'whatsapp://send?phone=$cleanPhone&text=$encodedMessage',
        'https://web.whatsapp.com/send?phone=$cleanPhone&text=$encodedMessage',
        'https://wa.me/$cleanPhone?text=$encodedMessage',
      ];

      for (final url in urls) {
        try {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('✅ تم فتح واتساب + نسخ الرسالة للحافظة'),
                    backgroundColor: Color(0xFF25D366),
                    duration: Duration(seconds: 3)),
              );
            }
            return;
          }
        } catch (e) {
          continue;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('📋 تم نسخ الرسالة للحافظة (واتساب غير متوفر)'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3)),
        );
      }
    } catch (e) {
      print('❌ خطأ في WhatsApp');
    }
  }

  /// بطاقة الحالة المدمجة مع الملخص
  Widget _buildCompactStatusCard(ServiceRequestModel req,
      Map<String, dynamic> details, double? amount, bool isAgent) {
    final statusColor = req.status.color;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            statusColor.withOpacity(0.15),
            statusColor.withOpacity(0.18),
          ],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // أيقونة الحالة
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  statusColor.withOpacity(0.35),
                  statusColor.withOpacity(0.25)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: statusColor.withOpacity(0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Icon(req.status.icon, color: statusColor, size: 28),
          ),
          const SizedBox(width: 16),
          // رقم الطلب والحالة
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(req.requestNumber,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      )),
                  const SizedBox(width: 10),
                  _buildMiniTag(
                    isAgent ? Icons.storefront_rounded : Icons.person_rounded,
                    isAgent ? 'طلب وكيل' : 'طلب مواطن',
                    isAgent
                        ? AccountingTheme.neonPink
                        : AccountingTheme.neonBlue,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(req.status.nameAr,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    )),
              ),
            ],
          ),
          const SizedBox(width: 20),
          // ملخص chips مدمجة
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.start,
              children: [
                _buildSummaryChip(Icons.wifi_rounded, req.serviceName ?? '-',
                    AccountingTheme.neonBlue),
                if (amount != null && amount > 0)
                  _buildSummaryChip(
                      Icons.payments_rounded,
                      '${_formatAmount(amount)} د.ع',
                      AccountingTheme.neonGreen),
                if (details['planName'] != null)
                  _buildSummaryChip(Icons.speed_rounded, details['planName'],
                      AccountingTheme.neonPurple),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // أزرار الإجراءات
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatusActions(req),
              const SizedBox(width: 6),
              Container(
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
                ),
                child: IconButton(
                  onPressed: () => _showDeleteRequestDialog(req),
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent, size: 18),
                  tooltip: 'حذف الطلب',
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: const EdgeInsets.all(6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniTag(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(text,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              )),
        ],
      ),
    );
  }

  /// عنصر تفصيلي مع أيقونة
  Widget _buildDetailItem(
      IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                label,
                style: const TextStyle(
                  color: AccountingTheme.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AccountingTheme.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// تنسيق المبالغ بفواصل
  String _formatAmount(double amount) {
    if (amount >= 1000) {
      return amount.toStringAsFixed(0).replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]},',
          );
    }
    return amount.toStringAsFixed(0);
  }

  /// تنسيق مدة الاشتراك بالأشهر
  String _formatDuration(dynamic duration) {
    final months = int.tryParse(duration.toString()) ?? 0;
    if (months == 1) return 'شهر واحد';
    if (months == 2) return 'شهران';
    if (months >= 3 && months <= 10) return '$months أشهر';
    if (months == 12) return 'سنة واحدة';
    return '$months شهر';
  }

  /// لون الأولوية
  Color _getPriorityColor(dynamic priority) {
    final name = priority.toString().toLowerCase();
    if (name.contains('عاجل') ||
        name.contains('urgent') ||
        name.contains('high')) {
      return AccountingTheme.danger;
    } else if (name.contains('متوسط') || name.contains('medium')) {
      return AccountingTheme.warning;
    }
    return AccountingTheme.neonGreen;
  }

  // ═══════ سجل الحالات Timeline ═══════

  Widget _buildStatusTimeline(ServiceRequestModel req) {
    if (_isLoadingDetail) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AccountingTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    final history = req.statusHistory;
    if (history.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AccountingTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                color: AccountingTheme.textMuted, size: 18),
            const SizedBox(width: 8),
            Text(
              'لا يوجد سجل حالات لهذا الطلب',
              style: TextStyle(color: AccountingTheme.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AccountingTheme.neonPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.timeline_rounded,
                    color: AccountingTheme.neonPurple, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'سجل الحالات',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AccountingTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AccountingTheme.neonPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${history.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AccountingTheme.neonPurple,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Timeline items
          ...List.generate(history.length, (index) {
            final item = history[index];
            final isLast = index == history.length - 1;
            final statusColor = _getStatusColorByName(item.toStatus);
            final statusIcon = _getStatusIconByName(item.toStatus);

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timeline line + dot
                  SizedBox(
                    width: 40,
                    child: Column(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: statusColor, width: 2),
                          ),
                          child: Icon(statusIcon, size: 14, color: statusColor),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: const Color(0xFFE2E8F0),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Content
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: statusColor.withOpacity(0.15)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // الحالة
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  StatusHistoryItem.statusNameAr(item.toStatus),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              // التاريخ والوقت
                              Text(
                                _formatDateTimeFull(item.changedAt),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AccountingTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // من قام بالتغيير
                          Row(
                            children: [
                              Icon(Icons.person_outline,
                                  size: 14,
                                  color: AccountingTheme.textSecondary),
                              const SizedBox(width: 4),
                              Text(
                                item.changedBy ?? 'النظام',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AccountingTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          // ملاحظة
                          if (item.note != null && item.note!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.notes_rounded,
                                    size: 14, color: AccountingTheme.textMuted),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    item.note!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AccountingTheme.textMuted,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Color _getStatusColorByName(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.blue;
      case 'reviewing':
        return Colors.orange;
      case 'approved':
        return Colors.teal;
      case 'assigned':
        return Colors.purple;
      case 'inprogress':
        return Colors.indigo;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.grey;
      case 'rejected':
        return Colors.red;
      case 'onhold':
        return Colors.amber;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _getStatusIconByName(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.hourglass_empty;
      case 'reviewing':
        return Icons.visibility;
      case 'approved':
        return Icons.check_circle_outline;
      case 'assigned':
        return Icons.person_add;
      case 'inprogress':
        return Icons.engineering;
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      case 'rejected':
        return Icons.block;
      case 'onhold':
        return Icons.pause_circle;
      default:
        return Icons.info_outline;
    }
  }

  String _formatDateTimeFull(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildInfoCard(
      String title, IconData icon, Color color, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AccountingTheme.textPrimary,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
          ),
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
              style: const TextStyle(
                color: AccountingTheme.textMuted,
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

  // ══════════════════════════════════════════════════════════
  // صف اسم الوكيل القابل للنقر
  // ══════════════════════════════════════════════════════════

  Widget _buildAgentNameRow(String agentName, String? agentId) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              'اسم الوكيل:',
              style: const TextStyle(
                color: AccountingTheme.textMuted,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: agentId != null ? () => _openAgentPage(agentId) : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    agentName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: agentId != null
                          ? AccountingTheme.neonPink
                          : AccountingTheme.textPrimary,
                      decoration:
                          agentId != null ? TextDecoration.underline : null,
                      decorationColor: AccountingTheme.neonPink,
                    ),
                  ),
                  if (agentId != null) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.open_in_new_rounded,
                      size: 14,
                      color: AccountingTheme.neonPink,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openAgentPage(String agentId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AgentsManagementPage(initialAgentId: agentId),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // أزرار تغيير الحالة
  // ══════════════════════════════════════════════════════════

  Widget _buildStatusActions(ServiceRequestModel req) {
    final isAgent = req.agentId != null && req.agentId!.isNotEmpty;
    final isPendingOrReviewing = req.status == ServiceRequestStatus.pending ||
        req.status == ServiceRequestStatus.reviewing;

    // طلبات الوكلاء في حالة الانتظار/المراجعة: قبول وتعيين + رفض
    if (isAgent && isPendingOrReviewing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton.icon(
            onPressed: () => _showAcceptAndAssignDialog(req),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
            label: const Text('قبول وتعيين لموظف',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () =>
                _updateStatus(req.id, ServiceRequestStatus.rejected),
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: const Text('رفض',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      );
    }

    // الحالات الأخرى: أزرار تغيير الحالة العادية
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
        // جديد → قبول (قيد المراجعة) أو رفض
        return [ServiceRequestStatus.reviewing, ServiceRequestStatus.rejected];
      case ServiceRequestStatus.reviewing:
        // قيد المراجعة → قيد التنفيذ
        return [ServiceRequestStatus.inProgress];
      case ServiceRequestStatus.inProgress:
        // قيد التنفيذ → مكتمل / معلق / ملغي
        return [
          ServiceRequestStatus.completed,
          ServiceRequestStatus.onHold,
          ServiceRequestStatus.cancelled,
        ];
      case ServiceRequestStatus.onHold:
        // معلق → استئناف (قيد التنفيذ) أو إلغاء
        return [
          ServiceRequestStatus.inProgress,
          ServiceRequestStatus.cancelled,
        ];
      default:
        // مكتمل / ملغي / مرفوض = حالات نهائية
        return [];
    }
  }

  Future<void> _showDeleteRequestDialog(ServiceRequestModel req) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الطلب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('هل أنت متأكد من حذف هذا الطلب؟'),
              const SizedBox(height: 12),
              Text('رقم الطلب: ${req.requestNumber}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (req.serviceName != null) Text('الخدمة: ${req.serviceName}'),
              if (req.estimatedCost != null)
                Text('المبلغ: ${req.estimatedCost!.toStringAsFixed(0)} د.ع'),
              const SizedBox(height: 8),
              const Text(
                'سيتم حذف الطلب والمعاملة المالية المرتبطة به.',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
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
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await _api.deleteServiceRequest(req.id);
        if (!mounted) return;
        setState(() {
          _allRequests.removeWhere((r) => r.id == req.id);
          _selectedRequest = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حذف الطلب بنجاح'),
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

  /// حوار قبول طلب الوكيل وتعيينه لموظف
  Future<void> _showAcceptAndAssignDialog(ServiceRequestModel req) async {
    // جلب بيانات الموظفين والأقسام
    Map<String, dynamic>? lookupData;
    try {
      lookupData = await _api.getTaskLookupData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل جلب بيانات الأقسام'),
            backgroundColor: Colors.red,
          ),
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
    String? selectedFbg;
    String? selectedFat;
    String? address;
    String? note;
    var leaders = <Map<String, dynamic>>[];
    var technicians = <Map<String, dynamic>>[];
    var techPhones = <String, String>{};
    bool isLoadingStaff = false;

    // خيارات FBG من lookup
    final fbgOptions = (lookup['fbgOptions'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();

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
        technicians = (staff['technicians'] as List<dynamic>? ?? [])
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
                    const Icon(Icons.check_circle_outline,
                        color: Color(0xFF2E7D32)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'قبول الطلب ${req.requestNumber} وتعيين لموظف',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 450,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // معلومات الطلب
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.blue.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'الخدمة: ${req.serviceName ?? "-"}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              if (req.citizenName != null)
                                Text('العميل: ${req.citizenName}'),
                              if (req.agentName != null)
                                Text('الوكيل: ${req.agentName}'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
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
                              labelText: 'الفني المسؤول *',
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
                          // FBG و FAT والموقع
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: selectedFbg,
                                  decoration: const InputDecoration(
                                    labelText: 'FBG',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.hub_outlined),
                                  ),
                                  items: fbgOptions.map((f) {
                                    return DropdownMenuItem<String>(
                                      value: f,
                                      child: Text(f),
                                    );
                                  }).toList(),
                                  onChanged: (v) =>
                                      setDialogState(() => selectedFbg = v),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  decoration: const InputDecoration(
                                    labelText: 'FAT',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.cable_outlined),
                                  ),
                                  onChanged: (v) => selectedFat = v,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // الموقع / العنوان
                          TextFormField(
                            initialValue: req.address,
                            decoration: const InputDecoration(
                              labelText: 'الموقع / العنوان',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.location_on_outlined),
                            ),
                            onChanged: (v) => address = v,
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
                    onPressed: selectedTechnician != null
                        ? () => Navigator.of(ctx).pop(true)
                        : null,
                    icon: const Icon(Icons.check),
                    label: const Text('قبول وتعيين'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
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

    if (confirmed == true && selectedTechnician != null) {
      try {
        await _api.assignTask(
          req.id,
          department: selectedDepartment,
          leader: selectedLeader,
          technician: selectedTechnician,
          technicianPhone: selectedTechnicianPhone,
          fbg: selectedFbg,
          fat: selectedFat,
          address: address,
          note: note,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'تم قبول الطلب وتعيينه للفني: ${selectedTechnician ?? "غير محدد"}'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _loadData();
        if (mounted && _selectedRequest != null) {
          final updated = _allRequests.where((r) => r.id == req.id).firstOrNull;
          if (updated != null) setState(() => _selectedRequest = updated);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل التعيين'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _updateStatus(
      String requestId, ServiceRequestStatus newStatus) async {
    try {
      await _api.updateServiceRequestStatus(requestId, newStatus.name);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تحديث الحالة إلى: ${newStatus.nameAr}'),
            backgroundColor: Colors.green,
          ),
        );
      }

      await _loadData();
      // إعادة تحديد الطلب بعد التحديث
      if (mounted && _selectedRequest != null) {
        final updated =
            _allRequests.where((r) => r.id == requestId).firstOrNull;
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

  // ══════════════════════════════════════════════════════════
  // خطأ
  // ══════════════════════════════════════════════════════════

  Widget _buildError() {
    final is401 = _errorMessage?.contains('401') == true ||
        _errorMessage?.contains('مصرح') == true ||
        _errorMessage?.contains('صلاحية') == true;

    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(32),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: AccountingTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: is401
                ? Colors.orange.withValues(alpha: 0.5)
                : Colors.red.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color:
                  (is401 ? Colors.orange : Colors.red).withValues(alpha: 0.15),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    (is401 ? Colors.orange : Colors.red).withValues(alpha: 0.2),
              ),
              child: Icon(
                is401
                    ? Icons.lock_outline_rounded
                    : Icons.error_outline_rounded,
                size: 48,
                color: is401 ? Colors.orange : Colors.red,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              is401 ? 'جلسة المصادقة منتهية' : 'حدث خطأ',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: is401 ? Colors.orange : Colors.red,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              is401
                  ? 'يرجى تسجيل الخروج وإعادة الدخول للحصول على جلسة جديدة.\n\nإذا استمرت المشكلة، قد يحتاج السيرفر لتحديث.'
                  : _errorMessage ?? 'خطأ غير معروف',
              style: const TextStyle(
                color: AccountingTheme.textSecondary,
                fontSize: 14,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('إعادة المحاولة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF667eea),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (Navigator.of(context).canPop())
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.home_rounded, size: 18),
                    label: const Text('العودة للرئيسية'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AccountingTheme.textSecondary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: BorderSide(color: AccountingTheme.borderColor),
                    ),
                  ),
              ],
            ),
            if (is401) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.35)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: Colors.orange),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'حل سريع: اذهب للإعدادات → تسجيل خروج → أعد الدخول',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // أدوات مساعدة
  // ══════════════════════════════════════════════════════════

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDateFull(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
