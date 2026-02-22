import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/attendance_api_service.dart';
import '../../services/vps_auth_service.dart';

/// صفحة إدارة طلبات سحب الأموال - قسم الحسابات
class WithdrawalRequestsPage extends StatefulWidget {
  final String? companyId;

  const WithdrawalRequestsPage({super.key, this.companyId});

  @override
  State<WithdrawalRequestsPage> createState() => _WithdrawalRequestsPageState();
}

class _WithdrawalRequestsPageState extends State<WithdrawalRequestsPage> {
  // ── ألوان ──
  static const _bgPage = Color(0xFFF5F6FA);
  static const _bgCard = Colors.white;
  static const _textDark = Color(0xFF2C3E50);
  static const _textGray = Color(0xFF95A5A6);
  static const _accentGreen = Color(0xFF27AE60);
  static const _accentRed = Color(0xFFE74C3C);
  static const _accentOrange = Color(0xFFF39C12);
  static const _accentBlue = Color(0xFF3498DB);
  static const _accentTeal = Color(0xFF1ABC9C);
  static const _accentPurple = Color(0xFF8E44AD);

  final _api = AttendanceApiService.instance;

  bool _isLoading = true;
  List<dynamic> _requests = [];
  int _total = 0;
  int _page = 1;
  int _totalPages = 1;
  int? _statusFilter;

  // إحصائيات
  int _pendingCount = 0;
  int _approvedCount = 0;
  int _paidCount = 0;
  int _rejectedCount = 0;
  double _pendingAmount = 0;
  double _paidAmount = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadRequests(), _loadStats()]);
  }

  Future<void> _loadRequests({int page = 1}) async {
    setState(() => _isLoading = true);
    try {
      final data = await _api.getWithdrawalRequests(
        companyId: widget.companyId ?? VpsAuthService.instance.currentCompanyId,
        status: _statusFilter,
        page: page,
        pageSize: 30,
      );
      if (!mounted) return;
      setState(() {
        _requests = List<dynamic>.from(data['requests'] ?? []);
        _total = data['total'] ?? 0;
        _page = data['page'] ?? 1;
        _totalPages = data['totalPages'] ?? 1;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading withdrawal requests: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats() async {
    try {
      final companyId =
          widget.companyId ?? VpsAuthService.instance.currentCompanyId;
      // جلب جميع الطلبات بدون فلتر حالة للإحصائيات
      final data = await _api.getWithdrawalRequests(
        companyId: companyId,
        pageSize: 1000,
      );
      if (!mounted) return;
      final all = List<dynamic>.from(data['requests'] ?? []);
      setState(() {
        _pendingCount = all.where((r) => r['Status'] == 0).length;
        _approvedCount = all.where((r) => r['Status'] == 1).length;
        _paidCount = all.where((r) => r['Status'] == 4).length;
        _rejectedCount =
            all.where((r) => r['Status'] == 2 || r['Status'] == 3).length;
        _pendingAmount = all.where((r) => r['Status'] == 0).fold<double>(
            0, (sum, r) => sum + ((r['Amount'] ?? 0) as num).toDouble());
        _paidAmount = all.where((r) => r['Status'] == 4).fold<double>(
            0, (sum, r) => sum + ((r['Amount'] ?? 0) as num).toDouble());
      });
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bgPage,
        appBar: AppBar(
          backgroundColor: _bgCard,
          elevation: 0,
          centerTitle: true,
          title: Text('طلبات سحب الأموال',
              style: GoogleFonts.cairo(
                  fontSize: 18, fontWeight: FontWeight.bold, color: _textDark)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: _textDark, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: _accentBlue),
              onPressed: _loadAll,
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _loadAll,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatsRow(),
                const SizedBox(height: 20),
                _buildFilterRow(),
                const SizedBox(height: 16),
                _buildRequestsList(),
                if (_totalPages > 1) ...[
                  const SizedBox(height: 16),
                  _buildPagination(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  بطاقات الإحصائيات
  // ═══════════════════════════════════════════════
  Widget _buildStatsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 800 ? 4 : 2;
        final spacing = 12.0;
        final w = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
                width: w,
                child: _statCard(
                    'معلّقة',
                    _pendingCount,
                    _formatAmount(_pendingAmount),
                    Icons.hourglass_empty,
                    _accentOrange)),
            SizedBox(
                width: w,
                child: _statCard('موافق عليها', _approvedCount, '',
                    Icons.check_circle_outline, _accentBlue)),
            SizedBox(
                width: w,
                child: _statCard(
                    'مصروفة',
                    _paidCount,
                    _formatAmount(_paidAmount),
                    Icons.payments_rounded,
                    _accentGreen)),
            SizedBox(
                width: w,
                child: _statCard('مرفوضة / ملغاة', _rejectedCount, '',
                    Icons.cancel_outlined, _accentRed)),
          ],
        );
      },
    );
  }

  Widget _statCard(
      String label, int count, String subtitle, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$count',
                    style: GoogleFonts.cairo(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: color)),
                Text(label,
                    style: GoogleFonts.cairo(fontSize: 11, color: _textGray)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: GoogleFonts.cairo(
                          fontSize: 10,
                          color: _textGray,
                          fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  شريط الفلترة
  // ═══════════════════════════════════════════════
  Widget _buildFilterRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6),
        ],
      ),
      child: Row(
        children: [
          Text('الحالة:',
              style: GoogleFonts.cairo(fontSize: 13, color: _textDark)),
          const SizedBox(width: 8),
          ..._filterChips(),
          const Spacer(),
          Text('الإجمالي: $_total',
              style: GoogleFonts.cairo(fontSize: 12, color: _textGray)),
        ],
      ),
    );
  }

  List<Widget> _filterChips() {
    final filters = [
      {'label': 'الكل', 'value': null},
      {'label': 'معلّقة', 'value': 0},
      {'label': 'موافق عليها', 'value': 1},
      {'label': 'مصروفة', 'value': 4},
      {'label': 'مرفوضة', 'value': 2},
    ];
    return filters.map((f) {
      final isSelected = _statusFilter == f['value'];
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: ChoiceChip(
          label: Text(f['label'] as String,
              style: GoogleFonts.cairo(
                  fontSize: 11, color: isSelected ? Colors.white : _textDark)),
          selected: isSelected,
          selectedColor: _accentBlue,
          backgroundColor: _bgPage,
          onSelected: (_) {
            setState(() => _statusFilter = f['value'] as int?);
            _loadRequests();
          },
        ),
      );
    }).toList();
  }

  // ═══════════════════════════════════════════════
  //  قائمة الطلبات
  // ═══════════════════════════════════════════════
  Widget _buildRequestsList() {
    if (_isLoading) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(strokeWidth: 2)));
    }

    if (_requests.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(Icons.inbox_rounded,
                size: 48, color: _textGray.withOpacity(0.4)),
            const SizedBox(height: 8),
            Text('لا توجد طلبات',
                style: GoogleFonts.cairo(color: _textGray, fontSize: 14)),
          ],
        ),
      );
    }

    return Column(
      children: _requests
          .map((r) => _buildRequestCard(r as Map<String, dynamic>))
          .toList(),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final status = req['Status'] as int? ?? 0;
    final statusInfo = _statusInfo(status);
    final amount = (req['Amount'] ?? 0) as num;
    final userName = req['UserName']?.toString() ?? 'غير معروف';
    final reason = req['Reason']?.toString() ?? '';
    final notes = req['Notes']?.toString() ?? '';
    final reviewNotes = req['ReviewNotes']?.toString() ?? '';
    final reviewedBy = req['ReviewedByUserName']?.toString() ?? '';
    final createdAt = _formatDate(req['CreatedAt']?.toString());
    final reviewedAt = _formatDate(req['ReviewedAt']?.toString());
    final id = req['Id'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border(
            right: BorderSide(color: statusInfo['color'] as Color, width: 4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رأس البطاقة
          Row(
            children: [
              // أيقونة الحالة
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (statusInfo['color'] as Color).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(statusInfo['icon'] as IconData,
                    color: statusInfo['color'] as Color, size: 20),
              ),
              const SizedBox(width: 10),
              // اسم الموظف
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(userName,
                        style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _textDark)),
                    Text('طلب #$id • $createdAt',
                        style:
                            GoogleFonts.cairo(fontSize: 10, color: _textGray)),
                  ],
                ),
              ),
              // شارة الحالة
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (statusInfo['color'] as Color).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(statusInfo['label'] as String,
                    style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusInfo['color'] as Color)),
              ),
              const SizedBox(width: 12),
              // المبلغ
              Text('${_formatAmount(amount)} د.ع',
                  style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _accentRed)),
            ],
          ),

          // السبب والملاحظات
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.notes, size: 14, color: _textGray.withOpacity(0.7)),
                const SizedBox(width: 6),
                Text('السبب: $reason',
                    style: GoogleFonts.cairo(fontSize: 12, color: _textGray)),
              ],
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.comment,
                    size: 14, color: _textGray.withOpacity(0.7)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('ملاحظات: $notes',
                      style: GoogleFonts.cairo(fontSize: 11, color: _textGray)),
                ),
              ],
            ),
          ],

          // ملاحظات المراجعة
          if (reviewedBy.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _bgPage,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 14, color: _accentPurple),
                  const SizedBox(width: 6),
                  Text('$reviewedBy • $reviewedAt',
                      style: GoogleFonts.cairo(
                          fontSize: 10, color: _accentPurple)),
                  if (reviewNotes.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text('— $reviewNotes',
                        style:
                            GoogleFonts.cairo(fontSize: 10, color: _textGray)),
                  ],
                ],
              ),
            ),
          ],

          // أزرار الإجراءات (للطلبات المعلقة والموافق عليها)
          if (status == 0 || status == 1) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (status == 0) ...[
                  // رفض
                  _actionButton(
                    label: 'رفض',
                    icon: Icons.close,
                    color: _accentRed,
                    onTap: () => _showRejectDialog(id),
                  ),
                  const SizedBox(width: 8),
                ],
                // صرف (موافقة + صرف + قيد)
                _actionButton(
                  label: 'صرف المبلغ',
                  icon: Icons.payments_rounded,
                  color: _accentGreen,
                  isPrimary: true,
                  onTap: () => _showPayDialog(id, amount, userName),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isPrimary ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isPrimary ? null : Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isPrimary ? Colors.white : color),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isPrimary ? Colors.white : color)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  Pagination
  // ═══════════════════════════════════════════════
  Widget _buildPagination() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _page > 1 ? () => _loadRequests(page: _page - 1) : null,
        ),
        Text('$_page / $_totalPages',
            style: GoogleFonts.cairo(fontSize: 13, color: _textDark)),
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed:
              _page < _totalPages ? () => _loadRequests(page: _page + 1) : null,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════
  //  حوار الصرف
  // ═══════════════════════════════════════════════
  void _showPayDialog(int id, num amount, String userName) {
    final notesCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: _accentGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.payments_rounded,
                    color: _accentGreen, size: 22),
              ),
              const SizedBox(width: 10),
              Text('تأكيد الصرف',
                  style: GoogleFonts.cairo(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _accentGreen.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _accentGreen.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    Text('صرف مبلغ لـ $userName',
                        style:
                            GoogleFonts.cairo(fontSize: 13, color: _textDark)),
                    const SizedBox(height: 4),
                    Text('${_formatAmount(amount)} د.ع',
                        style: GoogleFonts.cairo(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _accentGreen)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _accentOrange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: _accentOrange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'سيتم إنشاء قيد حسابي (أجور) على حساب الموظف بهذا المبلغ',
                        style: GoogleFonts.cairo(
                            fontSize: 11, color: _accentOrange),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  labelStyle: GoogleFonts.cairo(fontSize: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: GoogleFonts.cairo(fontSize: 13),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo(color: _textGray)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentGreen,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.payments_rounded,
                  size: 18, color: Colors.white),
              label: Text('تأكيد الصرف',
                  style: GoogleFonts.cairo(color: Colors.white)),
              onPressed: () async {
                Navigator.pop(ctx);
                await _payRequest(id, notesCtrl.text);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  حوار الرفض
  // ═══════════════════════════════════════════════
  void _showRejectDialog(int id) {
    final notesCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              const Icon(Icons.cancel_outlined, color: _accentRed),
              const SizedBox(width: 8),
              Text('رفض الطلب',
                  style: GoogleFonts.cairo(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: notesCtrl,
                decoration: InputDecoration(
                  labelText: 'سبب الرفض',
                  labelStyle: GoogleFonts.cairo(fontSize: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: GoogleFonts.cairo(fontSize: 13),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo(color: _textGray)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentRed,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.close, size: 18, color: Colors.white),
              label: Text('تأكيد الرفض',
                  style: GoogleFonts.cairo(color: Colors.white)),
              onPressed: () async {
                Navigator.pop(ctx);
                await _rejectRequest(id, notesCtrl.text);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  إجراءات API
  // ═══════════════════════════════════════════════
  Future<void> _payRequest(int id, String notes) async {
    try {
      await _api.payWithdrawalRequest(id,
          notes: notes.isNotEmpty ? notes : null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم صرف المبلغ وإنشاء القيد المحاسبي بنجاح',
              style: GoogleFonts.cairo()),
          backgroundColor: _accentGreen,
        ),
      );
      _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في الصرف: $e', style: GoogleFonts.cairo()),
          backgroundColor: _accentRed,
        ),
      );
    }
  }

  Future<void> _rejectRequest(int id, String notes) async {
    try {
      await _api.rejectWithdrawalRequest(id,
          notes: notes.isNotEmpty ? notes : null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم رفض الطلب', style: GoogleFonts.cairo()),
          backgroundColor: _accentOrange,
        ),
      );
      _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في الرفض: $e', style: GoogleFonts.cairo()),
          backgroundColor: _accentRed,
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════
  Map<String, dynamic> _statusInfo(int status) {
    switch (status) {
      case 0:
        return {
          'label': 'معلّقة',
          'color': _accentOrange,
          'icon': Icons.hourglass_empty
        };
      case 1:
        return {
          'label': 'موافق عليها',
          'color': _accentBlue,
          'icon': Icons.check_circle_outline
        };
      case 2:
        return {
          'label': 'مرفوضة',
          'color': _accentRed,
          'icon': Icons.cancel_outlined
        };
      case 3:
        return {'label': 'ملغاة', 'color': _textGray, 'icon': Icons.block};
      case 4:
        return {
          'label': 'مصروفة',
          'color': _accentGreen,
          'icon': Icons.payments_rounded
        };
      default:
        return {
          'label': 'غير معروف',
          'color': _textGray,
          'icon': Icons.help_outline
        };
    }
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '0';
    final num val =
        amount is num ? amount : num.tryParse(amount.toString()) ?? 0;
    if (val == 0) return '0';
    return val
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return '${dt.year}/${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }
}
