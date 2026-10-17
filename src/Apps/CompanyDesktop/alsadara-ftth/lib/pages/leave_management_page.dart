/// اسم الصفحة: إدارة الإجازات
/// وصف الصفحة: تقديم ومراجعة طلبات الإجازة مع عرض الأرصدة
/// المؤلف: تطبيق السدارة
library;

import 'dart:math';

import 'package:flutter/material.dart';
import '../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../services/attendance_api_service.dart';
import '../services/vps_auth_service.dart';

class LeaveManagementPage extends StatefulWidget {
  final String? companyId;

  const LeaveManagementPage({super.key, this.companyId});

  @override
  State<LeaveManagementPage> createState() => _LeaveManagementPageState();
}

class _LeaveManagementPageState extends State<LeaveManagementPage>
    with SingleTickerProviderStateMixin {
  final AttendanceApiService _api = AttendanceApiService.instance;
  late TabController _tabController;
  List<Map<String, dynamic>> _requests = [];
  Map<String, dynamic>? _balances;
  Map<String, dynamic>? _summary;
  bool _loading = true;
  int _totalRequests = 0;

  // أنواع الإجازات
  static const List<Map<String, dynamic>> _leaveTypes = [
    {
      'value': 0,
      'label': 'سنوية',
      'icon': Icons.beach_access,
      'color': Colors.blue
    },
    {
      'value': 1,
      'label': 'مرضية',
      'icon': Icons.local_hospital,
      'color': Colors.red
    },
    {
      'value': 2,
      'label': 'بدون راتب',
      'icon': Icons.money_off,
      'color': Colors.grey
    },
    {
      'value': 3,
      'label': 'طارئة',
      'icon': Icons.emergency,
      'color': Colors.orange
    },
    {'value': 4, 'label': 'رسمية', 'icon': Icons.flag, 'color': Colors.green},
    {'value': 5, 'label': 'زواج', 'icon': Icons.favorite, 'color': Colors.pink},
    {
      'value': 6,
      'label': 'أبوة/أمومة',
      'icon': Icons.child_care,
      'color': Colors.purple
    },
    {
      'value': 7,
      'label': 'وفاة',
      'icon': Icons.sentiment_very_dissatisfied,
      'color': Colors.brown
    },
  ];

  static const List<Map<String, dynamic>> _statusTypes = [
    {'value': 0, 'label': 'بانتظار الموافقة', 'color': SdColors.warning},
    {'value': 1, 'label': 'موافق عليها', 'color': SdColors.success},
    {'value': 2, 'label': 'مرفوضة', 'color': SdColors.danger},
    {'value': 3, 'label': 'ملغاة', 'color': SdColors.muted},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _loadRequests(),
        _loadBalances(),
        _loadSummary(),
      ]);
    } catch (e) {
      debugPrint('Error loading leave data');
    }
    setState(() => _loading = false);
  }

  Future<void> _loadRequests() async {
    try {
      final data = await _api.getLeaveRequests(companyId: widget.companyId);
      setState(() {
        _requests = List<Map<String, dynamic>>.from(
            data['requests'] ?? data['Requests'] ?? []);
        _totalRequests = data['total'] ?? data['Total'] ?? _requests.length;
      });
    } catch (e) {
      debugPrint('Error loading requests');
    }
  }

  Future<void> _loadBalances() async {
    try {
      final userId = VpsAuthService.instance.currentUser?.id;
      if (userId == null) return;
      final data = await _api.getLeaveBalances(userId);
      setState(() => _balances = data);
    } catch (e) {
      debugPrint('Error loading balances');
    }
  }

  Future<void> _loadSummary() async {
    try {
      final data = await _api.getLeaveSummary(companyId: widget.companyId);
      setState(() => _summary = data);
    } catch (e) {
      debugPrint('Error loading summary');
    }
  }

  String _leaveTypeName(dynamic val) {
    final v = val is int ? val : int.tryParse('$val') ?? -1;
    if (v >= 0 && v < _leaveTypes.length)
      return _leaveTypes[v]['label'] as String;
    // try string match
    for (var t in _leaveTypes) {
      if ('${t['label']}'.toLowerCase() == '$val'.toLowerCase())
        return t['label'] as String;
    }
    return '$val';
  }

  Color _leaveTypeColor(dynamic val) {
    final v = val is int ? val : int.tryParse('$val') ?? -1;
    if (v >= 0 && v < _leaveTypes.length)
      return _leaveTypes[v]['color'] as Color;
    return SdColors.muted;
  }

  IconData _leaveTypeIcon(dynamic val) {
    final v = val is int ? val : int.tryParse('$val') ?? -1;
    if (v >= 0 && v < _leaveTypes.length)
      return _leaveTypes[v]['icon'] as IconData;
    return Icons.event;
  }

  Color _statusColor(dynamic val) {
    final v = val is int ? val : int.tryParse('$val') ?? -1;
    if (v >= 0 && v < _statusTypes.length)
      return _statusTypes[v]['color'] as Color;
    return SdColors.muted;
  }

  String _statusName(dynamic val) {
    final v = val is int ? val : int.tryParse('$val') ?? -1;
    if (v >= 0 && v < _statusTypes.length)
      return _statusTypes[v]['label'] as String;
    return '$val';
  }

  // ============================================================
  //  تقديم طلب إجازة جديد
  // ============================================================
  Future<void> _showNewRequestDialog() async {
    int selectedType = 0;
    final reasonCtrl = TextEditingController();
    DateTimeRange? dateRange;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('طلب إجازة جديد',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: min(450, MediaQuery.of(context).size.width * 0.85),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // نوع الإجازة
                  DropdownButtonFormField<int>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'نوع الإجازة',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                    items: _leaveTypes
                        .map((t) => DropdownMenuItem<int>(
                              value: t['value'] as int,
                              child: Row(
                                children: [
                                  Icon(t['icon'] as IconData,
                                      color: t['color'] as Color, size: 20),
                                  const SizedBox(width: 8),
                                  Text(t['label'] as String),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedType = v ?? 0),
                  ),
                  const SizedBox(height: 16),

                  // اختيار التاريخ
                  InkWell(
                    onTap: () async {
                      final picked = await showDateRangePicker(
                        context: ctx,
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        locale: const Locale('ar'),
                        builder: (context, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme:
                                ColorScheme.light(primary: SdColors.primary),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        setDialogState(() => dateRange = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'فترة الإجازة',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.date_range),
                      ),
                      child: Text(
                        dateRange != null
                            ? '${dateRange!.start.toString().split(' ')[0]}  →  ${dateRange!.end.toString().split(' ')[0]}'
                            : 'اضغط لاختيار التاريخ',
                        style: TextStyle(
                          color:
                              dateRange != null ? SdColors.ink : SdColors.faint,
                        ),
                      ),
                    ),
                  ),
                  if (dateRange != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: SdColors.infoTint,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.timer, size: 18, color: SdColors.info),
                          const SizedBox(width: 6),
                          Text(
                            '${dateRange!.end.difference(dateRange!.start).inDays + 1} أيام',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: SdColors.info,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // السبب
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'السبب (اختياري)',
                      hintText: 'اكتب سبب الإجازة...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.note),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.send),
              label: const Text('تقديم الطلب'),
            ),
          ],
        ),
      ),
    );

    if (result != true || dateRange == null) return;

    try {
      final userId = VpsAuthService.instance.currentUser?.id ?? '';
      final res = await _api.submitLeaveRequest(
        userId: userId,
        leaveType: selectedType,
        startDate: dateRange!.start.toString().split(' ')[0],
        endDate: dateRange!.end.toString().split(' ')[0],
        reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      );

      if (mounted) {
        final msg = res['message'] ?? res['Message'] ?? 'تم التقديم';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$msg'), backgroundColor: SdColors.success),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ'), backgroundColor: SdColors.danger),
        );
      }
    }
  }

  // ============================================================
  //  مراجعة طلب (موافقة / رفض)
  // ============================================================
  Future<void> _reviewRequest(Map<String, dynamic> req, bool approve) async {
    final notesCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'تأكيد الموافقة' : 'تأكيد الرفض',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الموظف: ${req['userName'] ?? req['UserName'] ?? ''}'),
            Text(
                'الفترة: ${req['startDate'] ?? req['StartDate']} → ${req['endDate'] ?? req['EndDate']}'),
            Text(
                'النوع: ${_leaveTypeName(req['leaveTypeValue'] ?? req['LeaveTypeValue'])}'),
            Text('المدة: ${req['totalDays'] ?? req['TotalDays']} أيام'),
            const SizedBox(height: 16),
            TextField(
              controller: notesCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: approve ? 'ملاحظات (اختياري)' : 'سبب الرفض',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: approve ? SdColors.success : SdColors.danger,
            ),
            child: Text(approve ? 'موافقة' : 'رفض'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final id = req['id'] ?? req['Id'];
      final idInt = id is int ? id : int.parse('$id');
      final notes =
          notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim();

      if (approve) {
        await _api.approveLeaveRequest(idInt, notes: notes);
      } else {
        await _api.rejectLeaveRequest(idInt, notes: notes);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve ? 'تمت الموافقة' : 'تم الرفض'),
            backgroundColor: approve ? SdColors.success : SdColors.danger,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: SdAppBar(
        title: 'إدارة الإجازات',
        actions: [
          SdAppBarAction(
            icon: Icons.refresh,
            label: 'تحديث',
            onPressed: _loadData,
          ),
        ],
        bottom: SdTabBar(
          controller: _tabController,
          height: 72,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: 'الطلبات'),
            Tab(icon: Icon(Icons.account_balance_wallet), text: 'الأرصدة'),
            Tab(icon: Icon(Icons.pie_chart), text: 'الإحصائيات'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewRequestDialog,
        backgroundColor: SdColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('طلب إجازة',
            style: TextStyle(
                fontFamily: SdText.family, fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: SdColors.primary))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildRequestsTab(),
                      _buildBalancesTab(),
                      _buildSummaryTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  //  تبويب الطلبات
  // ============================================================
  Widget _buildRequestsTab() {
    if (_requests.isEmpty) {
      return const SdEmptyState(
        icon: Icons.event_busy,
        title: 'لا توجد طلبات إجازة',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('إجمالي: $_totalRequests طلب', style: SdText.bodySm),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _requests.length,
            itemBuilder: (ctx, i) => _buildRequestCard(_requests[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final userName = req['userName'] ?? req['UserName'] ?? '';
    final typeVal = req['leaveTypeValue'] ?? req['LeaveTypeValue'] ?? 0;
    final statusVal = req['statusValue'] ?? req['StatusValue'] ?? 0;
    final startDate = req['startDate'] ?? req['StartDate'] ?? '';
    final endDate = req['endDate'] ?? req['EndDate'] ?? '';
    final totalDays = req['totalDays'] ?? req['TotalDays'] ?? 0;
    final reason = req['reason'] ?? req['Reason'] ?? '';
    final reviewNotes = req['reviewNotes'] ?? req['ReviewNotes'];
    final reviewedBy = req['reviewedByUserName'] ?? req['ReviewedByUserName'];
    final isPending = statusVal == 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SdCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      _leaveTypeColor(typeVal).withValues(alpha: 0.15),
                  child: Icon(_leaveTypeIcon(typeVal),
                      color: _leaveTypeColor(typeVal), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userName, style: SdText.titleSm.copyWith(fontSize: 15)),
                      Text(_leaveTypeName(typeVal),
                          style: SdText.bodySm.copyWith(
                              color: _leaveTypeColor(typeVal), fontSize: 13)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _statusColor(statusVal).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _statusName(statusVal),
                    style: SdText.caption.copyWith(
                      color: _statusColor(statusVal),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20, color: SdColors.divider),

            // Details
            Wrap(
              spacing: 20,
              runSpacing: 6,
              children: [
                _infoItem(Icons.calendar_today, 'من', '$startDate'),
                _infoItem(Icons.event, 'إلى', '$endDate'),
                _infoItem(Icons.timer, 'المدة', '$totalDays أيام'),
              ],
            ),

            if ('$reason'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.note, size: 16, color: SdColors.faint),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('$reason',
                        style: SdText.bodySm.copyWith(fontSize: 13)),
                  ),
                ],
              ),
            ],

            if (reviewNotes != null && '$reviewNotes'.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: SdColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(SdRadius.xs),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.comment, size: 16, color: SdColors.faint),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${reviewedBy ?? 'المدير'}: $reviewNotes',
                        style: SdText.bodySm.copyWith(
                            fontSize: 12.5, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Action buttons (pending only)
            if (isPending) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SdButton(
                    label: 'رفض',
                    icon: Icons.close,
                    kind: SdButtonKind.danger,
                    height: 44,
                    onPressed: () => _reviewRequest(req, false),
                  ),
                  const SizedBox(width: 8),
                  SdButton(
                    label: 'موافقة',
                    icon: Icons.check,
                    kind: SdButtonKind.accent,
                    height: 44,
                    onPressed: () => _reviewRequest(req, true),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  //  تبويب الأرصدة
  // ============================================================
  Widget _buildBalancesTab() {
    final balanceList = _balances?['balances'] ?? _balances?['Balances'];
    if (balanceList == null || (balanceList is List && balanceList.isEmpty)) {
      return const SdEmptyState(
        icon: Icons.account_balance_wallet,
        title: 'لا يوجد رصيد إجازات محدد',
        message: 'يتم تعيين الرصيد من قبل المدير',
      );
    }

    final items = List<Map<String, dynamic>>.from(balanceList);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final b = items[i];
        final typeVal = b['leaveTypeValue'] ?? b['LeaveTypeValue'] ?? 0;
        final total = b['totalAllowance'] ?? b['TotalAllowance'] ?? 0;
        final used = b['usedDays'] ?? b['UsedDays'] ?? 0;
        final remaining =
            b['remainingDays'] ?? b['RemainingDays'] ?? (total - used);
        final progress = total > 0 ? used / total : 0.0;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SdCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_leaveTypeIcon(typeVal),
                        color: _leaveTypeColor(typeVal)),
                    const SizedBox(width: 8),
                    Text(_leaveTypeName(typeVal), style: SdText.titleSm),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0).toDouble(),
                    minHeight: 10,
                    backgroundColor: SdColors.divider,
                    valueColor: AlwaysStoppedAnimation(
                      remaining > 0
                          ? _leaveTypeColor(typeVal)
                          : SdColors.danger,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('مستخدم: $used',
                        style: SdText.bodySm.copyWith(fontSize: 13)),
                    Text('متبقي: $remaining',
                        style: SdText.label.copyWith(
                          fontSize: 13,
                          color: remaining > 0
                              ? SdColors.success
                              : SdColors.danger,
                        )),
                    Text('إجمالي: $total',
                        style: SdText.bodySm.copyWith(fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  //  تبويب الإحصائيات
  // ============================================================
  Widget _buildSummaryTab() {
    if (_summary == null) {
      return const Center(child: Text('لا توجد بيانات'));
    }

    final total = _summary!['totalRequests'] ?? _summary!['TotalRequests'] ?? 0;
    final pending = _summary!['pending'] ?? _summary!['Pending'] ?? 0;
    final approved = _summary!['approved'] ?? _summary!['Approved'] ?? 0;
    final rejected = _summary!['rejected'] ?? _summary!['Rejected'] ?? 0;
    final cancelled = _summary!['cancelled'] ?? _summary!['Cancelled'] ?? 0;
    final totalDays =
        _summary!['totalApprovedDays'] ?? _summary!['TotalApprovedDays'] ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // بطاقات الإحصائيات
          Row(
            children: [
              Expanded(
                  child: _statCard('إجمالي الطلبات', '$total', SdColors.info)),
              const SizedBox(width: 8),
              Expanded(
                  child: _statCard('بانتظار', '$pending', SdColors.warning)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child:
                      _statCard('موافق عليها', '$approved', SdColors.success)),
              const SizedBox(width: 8),
              Expanded(child: _statCard('مرفوضة', '$rejected', SdColors.danger)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _statCard('ملغاة', '$cancelled', SdColors.muted)),
              const SizedBox(width: 8),
              Expanded(
                  child: _statCard(
                      'أيام إجازة (موافق)', '$totalDays', SdColors.accent)),
            ],
          ),
          const SizedBox(height: 20),

          // توزيع حسب النوع
          SdCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('توزيع الإجازات حسب النوع', style: SdText.titleSm),
                const Divider(color: SdColors.divider),
                ..._buildTypeDistribution(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTypeDistribution() {
    final byType = _summary?['byType'] ?? _summary?['ByType'];
    if (byType == null || byType is! List || byType.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('لا توجد إجازات موافق عليها', style: SdText.bodySm),
        )
      ];
    }

    return List<Map<String, dynamic>>.from(byType).map((item) {
      final typeVal = item['typeValue'] ?? item['TypeValue'] ?? 0;
      final count = item['count'] ?? item['Count'] ?? 0;
      final days = item['totalDays'] ?? item['TotalDays'] ?? 0;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(_leaveTypeIcon(typeVal),
                color: _leaveTypeColor(typeVal), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_leaveTypeName(typeVal),
                  style: const TextStyle(fontSize: 14)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _leaveTypeColor(typeVal).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(SdRadius.sm),
              ),
              child: Text('$count طلب · $days يوم',
                  style: SdText.caption
                      .copyWith(color: _leaveTypeColor(typeVal))),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _statCard(String label, String value, Color color) {
    return SdCard(
      child: Column(
        children: [
          Text(value,
              style: SdText.number.copyWith(fontSize: 28, color: color)),
          const SizedBox(height: 4),
          Text(label, style: SdText.bodySm.copyWith(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _infoItem(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: SdColors.faint),
        const SizedBox(width: 4),
        Text('$label: ', style: SdText.caption.copyWith(fontSize: 12)),
        Text(value, style: SdText.label.copyWith(fontSize: 12)),
      ],
    );
  }
}
