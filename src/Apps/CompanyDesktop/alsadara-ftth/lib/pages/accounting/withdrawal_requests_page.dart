import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/accounting_responsive.dart';
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
                  fontSize: context.accR.headingSmall,
                  fontWeight: FontWeight.bold,
                  color: _textDark)),
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios,
                color: _textDark, size: context.accR.iconM),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: _accentBlue),
              onPressed: _loadAll,
            ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadAll,
            child: SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(context.accR.isMobile
                  ? context.accR.spaceM
                  : context.accR.spaceXL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatsRow(),
                  SizedBox(
                      height: context.accR.isMobile
                          ? context.accR.spaceM
                          : context.accR.spaceXL),
                  _buildFilterRow(),
                  SizedBox(
                      height: context.accR.isMobile
                          ? context.accR.spaceM
                          : context.accR.spaceXL),
                  _buildRequestsList(),
                  if (_totalPages > 1) ...[
                    SizedBox(height: context.accR.spaceXL),
                    _buildPagination(),
                  ],
                ],
              ),
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
    final isMobile = context.accR.isMobile;
    final iconBoxSize = isMobile ? 32.0 : 42.0;
    return Container(
      padding: EdgeInsets.all(isMobile ? 8 : context.accR.spaceL),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
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
            width: iconBoxSize,
            height: iconBoxSize,
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(
                    isMobile ? 6 : context.accR.cardRadius)),
            child: Icon(icon,
                color: color, size: isMobile ? 18 : context.accR.iconM),
          ),
          SizedBox(width: isMobile ? 6 : context.accR.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$count',
                    style: GoogleFonts.cairo(
                        fontSize: isMobile ? 16 : context.accR.financialLarge,
                        fontWeight: FontWeight.bold,
                        color: color)),
                Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                        fontSize: isMobile ? 10 : context.accR.small,
                        color: _textGray)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                          fontSize: isMobile ? 9 : context.accR.caption,
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
    final isMobile = context.accR.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 4 : context.accR.spaceM,
          vertical: isMobile ? 4 : context.accR.spaceS),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6),
        ],
      ),
      child: isMobile
          ? Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: _filterChips(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text('$_total',
                      style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _textGray)),
                ),
              ],
            )
          : Row(
              children: [
                Text('الحالة:',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.financialSmall,
                        color: _textDark)),
                SizedBox(width: context.accR.spaceS),
                ..._filterChips(),
                Spacer(),
                Text('الإجمالي: $_total',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.small, color: _textGray)),
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
    final isMobile = context.accR.isMobile;
    return filters.map((f) {
      final isSelected = _statusFilter == f['value'];
      return ChoiceChip(
        label: Text(f['label'] as String,
            style: GoogleFonts.cairo(
                fontSize: isMobile ? 10 : context.accR.small,
                height: 1.2,
                color: isSelected ? Colors.white : _textDark)),
        selected: isSelected,
        selectedColor: _accentBlue,
        backgroundColor: _bgPage,
        visualDensity: isMobile
            ? const VisualDensity(horizontal: -4, vertical: -4)
            : VisualDensity.standard,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: isMobile
            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 0)
            : null,
        labelPadding:
            isMobile ? const EdgeInsets.symmetric(horizontal: 2) : null,
        onSelected: (_) {
          setState(() => _statusFilter = f['value'] as int?);
          _loadRequests();
        },
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
        padding: EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(context.accR.cardRadius),
        ),
        child: Column(
          children: [
            Icon(Icons.inbox_rounded,
                size: context.accR.iconXL, color: _textGray.withOpacity(0.4)),
            SizedBox(height: context.accR.spaceS),
            Text('لا توجد طلبات',
                style: GoogleFonts.cairo(
                    color: _textGray, fontSize: context.accR.body)),
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
    final isMobile = context.accR.isMobile;

    return Container(
      margin: EdgeInsets.only(bottom: isMobile ? 8 : 10),
      padding: EdgeInsets.all(isMobile ? 10 : context.accR.spaceXL),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
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
                width: isMobile ? 32 : 38,
                height: isMobile ? 32 : 38,
                decoration: BoxDecoration(
                  color: (statusInfo['color'] as Color).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(statusInfo['icon'] as IconData,
                    color: statusInfo['color'] as Color,
                    size: isMobile ? 18 : context.accR.iconM),
              ),
              SizedBox(width: isMobile ? 8 : context.accR.spaceM),
              // اسم الموظف
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(userName,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                            fontSize: isMobile ? 13 : context.accR.body,
                            fontWeight: FontWeight.bold,
                            color: _textDark)),
                    Text('طلب #$id • $createdAt',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                            fontSize: isMobile ? 10 : context.accR.caption,
                            color: _textGray)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 6 : context.accR.spaceS),
          // صف الحالة + المبلغ
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 8 : context.accR.spaceM,
                    vertical: 2),
                decoration: BoxDecoration(
                  color: (statusInfo['color'] as Color).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(statusInfo['label'] as String,
                    style: GoogleFonts.cairo(
                        fontSize: isMobile ? 11 : context.accR.small,
                        fontWeight: FontWeight.w600,
                        color: statusInfo['color'] as Color)),
              ),
              Spacer(),
              Text('${_formatAmount(amount)} د.ع',
                  style: GoogleFonts.cairo(
                      fontSize: isMobile ? 15 : context.accR.headingSmall,
                      fontWeight: FontWeight.bold,
                      color: _accentRed)),
            ],
          ),

          // السبب والملاحظات
          if (reason.isNotEmpty) ...[
            SizedBox(height: context.accR.spaceS),
            Row(
              children: [
                Icon(Icons.notes,
                    size: isMobile ? 14 : context.accR.iconS,
                    color: _textGray.withOpacity(0.7)),
                SizedBox(width: context.accR.spaceXS),
                Flexible(
                  child: Text('السبب: $reason',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                          fontSize: isMobile ? 11 : context.accR.small,
                          color: _textGray)),
                ),
              ],
            ),
          ],
          if (notes.isNotEmpty) ...[
            SizedBox(height: context.accR.spaceXS),
            Row(
              children: [
                Icon(Icons.comment,
                    size: isMobile ? 14 : context.accR.iconS,
                    color: _textGray.withOpacity(0.7)),
                SizedBox(width: context.accR.spaceXS),
                Flexible(
                  child: Text('ملاحظات: $notes',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                          fontSize: isMobile ? 11 : context.accR.small,
                          color: _textGray)),
                ),
              ],
            ),
          ],

          // ملاحظات المراجعة
          if (reviewedBy.isNotEmpty) ...[
            SizedBox(height: context.accR.spaceXS),
            Container(
              padding: EdgeInsets.all(isMobile ? 6 : context.accR.spaceS),
              decoration: BoxDecoration(
                color: _bgPage,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.person,
                      size: isMobile ? 14 : context.accR.iconS,
                      color: _accentPurple),
                  SizedBox(width: context.accR.spaceXS),
                  Expanded(
                    child: Text(
                      '$reviewedBy • $reviewedAt${reviewNotes.isNotEmpty ? ' — $reviewNotes' : ''}',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                          fontSize: isMobile ? 10 : context.accR.caption,
                          color: _accentPurple),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // أزرار الإجراءات (للطلبات المعلقة والموافق عليها)
          if (status == 0 || status == 1) ...[
            SizedBox(height: context.accR.spaceM),
            Divider(height: 1),
            SizedBox(height: context.accR.spaceS),
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
                  SizedBox(width: context.accR.spaceS),
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
    final isMobile = context.accR.isMobile;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 10 : 14, vertical: isMobile ? 5 : 7),
        decoration: BoxDecoration(
          color: isPrimary ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isPrimary ? null : Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: isMobile ? 14 : context.accR.iconS,
                color: isPrimary ? Colors.white : color),
            SizedBox(width: context.accR.spaceXS),
            Text(label,
                style: GoogleFonts.cairo(
                    fontSize: isMobile ? 11 : context.accR.small,
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
            style: GoogleFonts.cairo(
                fontSize: context.accR.financialSmall, color: _textDark)),
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
    bool overrideLimit = false;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx2, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(context.accR.radiusL)),
            title: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: _accentGreen.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.payments_rounded,
                      color: _accentGreen, size: context.accR.iconM),
                ),
                SizedBox(width: context.accR.spaceM),
                Text('تأكيد الصرف',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.headingSmall,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(context.accR.spaceM),
                  decoration: BoxDecoration(
                    color: _accentGreen.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _accentGreen.withOpacity(0.2)),
                  ),
                  child: Column(
                    children: [
                      Text('صرف سلفة لـ $userName',
                          style: GoogleFonts.cairo(
                              fontSize: context.accR.financialSmall,
                              color: _textDark)),
                      SizedBox(height: context.accR.spaceXS),
                      Text('${_formatAmount(amount)} د.ع',
                          style: GoogleFonts.cairo(
                              fontSize: context.accR.financialLarge,
                              fontWeight: FontWeight.bold,
                              color: _accentGreen)),
                    ],
                  ),
                ),
                SizedBox(height: context.accR.spaceM),
                Container(
                  padding: EdgeInsets.all(context.accR.spaceS),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: context.accR.iconS, color: Color(0xFF1565C0)),
                      SizedBox(width: context.accR.spaceXS),
                      Expanded(
                        child: Text(
                          'سيتم خصم المبلغ كسلفة من راتب الموظف',
                          style: GoogleFonts.cairo(
                              fontSize: context.accR.small,
                              color: Color(0xFF1565C0)),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: context.accR.spaceM),
                TextField(
                  controller: notesCtrl,
                  decoration: InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    labelStyle: GoogleFonts.cairo(fontSize: context.accR.small),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  style:
                      GoogleFonts.cairo(fontSize: context.accR.financialSmall),
                  maxLines: 2,
                ),
                SizedBox(height: context.accR.spaceS),
                CheckboxListTile(
                  value: overrideLimit,
                  onChanged: (v) =>
                      setDialogState(() => overrideLimit = v ?? false),
                  title: Text('تجاوز حد السحب',
                      style: GoogleFonts.cairo(fontSize: context.accR.small)),
                  subtitle: Text(
                    'السماح بصرف المبلغ حتى لو تجاوز الراتب المستحق',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.caption, color: _textGray),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: _accentOrange,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    Text('إلغاء', style: GoogleFonts.cairo(color: _textGray)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGreen,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: Icon(Icons.payments_rounded,
                    size: context.accR.iconM, color: Colors.white),
                label: Text('تأكيد الصرف',
                    style: GoogleFonts.cairo(color: Colors.white)),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _payRequest(id, notesCtrl.text, overrideLimit);
                },
              ),
            ],
          ),
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.accR.radiusL)),
          title: Row(
            children: [
              Icon(Icons.cancel_outlined, color: _accentRed),
              SizedBox(width: context.accR.spaceS),
              Text('رفض الطلب',
                  style: GoogleFonts.cairo(
                      fontSize: context.accR.headingSmall,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: notesCtrl,
                decoration: InputDecoration(
                  labelText: 'سبب الرفض',
                  labelStyle: GoogleFonts.cairo(fontSize: context.accR.small),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: context.accR.spaceM,
                      vertical: context.accR.spaceM),
                ),
                style: GoogleFonts.cairo(fontSize: context.accR.financialSmall),
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
              icon: Icon(Icons.close,
                  size: context.accR.iconM, color: Colors.white),
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
  Future<void> _payRequest(int id, String notes, bool overrideLimit) async {
    try {
      await _api.payWithdrawalRequest(id,
          notes: notes.isNotEmpty ? notes : null, overrideLimit: overrideLimit);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم صرف السلفة بنجاح', style: GoogleFonts.cairo()),
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
