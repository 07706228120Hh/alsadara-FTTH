import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../services/period_closing_service.dart';
import '../../services/audit_trail_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

/// صفحة تحصيلات الفنيين - عرض موحّد للمستحقات مع إمكانية إضافة تحصيل وتسديد
class CollectionsPage extends StatefulWidget {
  final String? companyId;

  const CollectionsPage({super.key, this.companyId});

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _technicians = [];
  Map<String, dynamic> _summary = {};
  String _techFilter = 'all'; // all, debtor, creditor
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String _sortBy = 'net'; // 'net', 'name', 'charges', 'payments'
  bool _sortAsc = false; // false = تنازلي (الأعلى أولاً)

  @override
  void initState() {
    super.initState();
    _loadDues();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDues() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await AccountingService.instance.getTechnicianDues();
      if (result['success'] == true) {
        final data = result['data'];
        if (data is Map<String, dynamic>) {
          _technicians =
              (data['technicians'] is List) ? data['technicians'] : [];
          _summary =
              (data['summary'] is Map<String, dynamic>) ? data['summary'] : {};
        } else {
          _technicians = [];
          _summary = {};
        }
      } else {
        _error = result['message'] ?? 'خطأ في جلب المستحقات';
      }
    } catch (e) {
      _error = 'خطأ';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: SafeArea(
          child: Column(
            children: [
              _buildToolbar(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  شريط الأدوات العلوي
  // ═══════════════════════════════════════════════════
  Widget _buildToolbar() {
    final ar = context.accR;
    final isMobile = ar.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? ar.spaceS : ar.spaceXL,
          vertical: isMobile ? ar.spaceXS : ar.spaceL),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'رجوع',
            iconSize: isMobile ? 20 : null,
            constraints: isMobile
                ? const BoxConstraints(minWidth: 32, minHeight: 32)
                : null,
            padding: isMobile ? EdgeInsets.zero : null,
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          SizedBox(width: isMobile ? 4 : ar.spaceS),
          Container(
            padding: EdgeInsets.all(isMobile ? 4 : ar.spaceS),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonBlueGradient,
              borderRadius: BorderRadius.circular(ar.btnRadius),
            ),
            child: Icon(Icons.engineering_rounded,
                color: Colors.white, size: isMobile ? 16 : ar.iconM),
          ),
          SizedBox(width: isMobile ? 6 : ar.spaceM),
          Expanded(
            child: Text('تحصيلات الفنيين',
                style: GoogleFonts.cairo(
                    fontSize: isMobile ? 14 : ar.headingMedium,
                    fontWeight: FontWeight.bold,
                    color: AccountingTheme.textPrimary),
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            onPressed: _loadDues,
            icon: Icon(Icons.refresh, size: isMobile ? 18 : ar.iconM),
            tooltip: 'تحديث',
            constraints: isMobile
                ? const BoxConstraints(minWidth: 32, minHeight: 32)
                : null,
            padding: isMobile ? EdgeInsets.zero : null,
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          SizedBox(width: isMobile ? 4 : ar.spaceS),
          ElevatedButton.icon(
            onPressed: _showAddDialog,
            icon: Icon(Icons.add, size: isMobile ? 16 : ar.iconM),
            label: Text(isMobile ? 'إضافة تحصيل' : 'إضافة تحصيل',
                style:
                    GoogleFonts.cairo(fontSize: isMobile ? 11 : ar.buttonText)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.neonBlue,
              foregroundColor: Colors.white,
              padding: isMobile
                  ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                  : ar.buttonPadding,
              minimumSize: isMobile ? const Size(0, 30) : null,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  محتوى الصفحة
  // ═══════════════════════════════════════════════════
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AccountingTheme.neonBlue),
      );
    }
    if (_error != null) {
      final ar = context.accR;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                color: AccountingTheme.danger, size: ar.iconXL),
            SizedBox(height: ar.spaceM),
            Text(_error!,
                style: const TextStyle(color: AccountingTheme.danger)),
            SizedBox(height: ar.spaceM),
            ElevatedButton.icon(
              onPressed: _loadDues,
              icon: Icon(Icons.refresh, size: ar.iconXS),
              label: Text('إعادة المحاولة',
                  style: GoogleFonts.cairo(fontSize: ar.buttonText)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AccountingTheme.neonBlue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildSummaryBar(),
        // مربع البحث + أزرار التصفية
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: context.accR.paddingH,
              vertical: context.accR.spaceXS),
          child: Row(
            children: [
              _techFilterBtn('الكل', 'all'),
              SizedBox(width: context.accR.spaceS),
              _techFilterBtn('مديون', 'debtor'),
              SizedBox(width: context.accR.spaceS),
              _techFilterBtn('دائن', 'creditor'),
              const Spacer(),
              SizedBox(
                width: context.accR.isMobile ? 160 : 250,
                height: context.accR.isMobile ? 34 : 40,
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  textDirection: TextDirection.rtl,
                  style: GoogleFonts.cairo(
                    fontSize: context.accR.isMobile ? 12 : 14,
                    color: AccountingTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'بحث عن فني...',
                    hintStyle: GoogleFonts.cairo(
                      fontSize: context.accR.isMobile ? 12 : 14,
                      color: AccountingTheme.textMuted,
                    ),
                    prefixIcon: Icon(Icons.search,
                        size: context.accR.isMobile ? 16 : 20,
                        color: AccountingTheme.textMuted),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close,
                                size: context.accR.isMobile ? 14 : 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          )
                        : null,
                    filled: true,
                    fillColor: AccountingTheme.bgCard,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          context.accR.isMobile ? 8 : 10),
                      borderSide:
                          const BorderSide(color: AccountingTheme.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          context.accR.isMobile ? 8 : 10),
                      borderSide:
                          const BorderSide(color: AccountingTheme.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          context.accR.isMobile ? 8 : 10),
                      borderSide: const BorderSide(
                          color: AccountingTheme.neonBlue, width: 1.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // أزرار الترتيب
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: context.accR.paddingH),
          child: Row(
            children: [
              Text('ترتيب حسب:',
                  style: GoogleFonts.cairo(
                      fontSize: context.accR.isMobile ? 11 : 13,
                      color: AccountingTheme.textMuted)),
              SizedBox(width: context.accR.spaceXS),
              _sortBtn('المستحق', 'net'),
              SizedBox(width: context.accR.spaceXS),
              _sortBtn('الاسم', 'name'),
              SizedBox(width: context.accR.spaceXS),
              _sortBtn('الأجور', 'charges'),
              SizedBox(width: context.accR.spaceXS),
              _sortBtn('التسديدات', 'payments'),
            ],
          ),
        ),
        SizedBox(height: context.accR.spaceXS),
        Expanded(
          child: _filteredTechnicians.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: AccountingTheme.success,
                          size: context.accR.iconEmpty),
                      SizedBox(height: context.accR.spaceXL),
                      Text(
                          _techFilter == 'all'
                              ? 'لا توجد مستحقات على الفنيين'
                              : _techFilter == 'debtor'
                                  ? 'لا يوجد فنيين مدينون'
                                  : 'لا يوجد فنيين دائنون',
                          style: TextStyle(
                              color: AccountingTheme.textMuted,
                              fontSize: context.accR.body)),
                    ],
                  ),
                )
              : _buildTechnicianList(),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  شريط الملخص
  // ═══════════════════════════════════════════════════
  Widget _buildSummaryBar() {
    final ar = context.accR;
    final isMobile = ar.isMobile;
    final totalCharges = (_summary['totalCharges'] ?? 0).toDouble();
    final totalPayments = (_summary['totalPayments'] ?? 0).toDouble();
    final totalNet = (_summary['totalNetBalance'] ?? 0).toDouble();
    final techCount = _summary['technicianCount'] ?? 0;
    final debtorCount = _summary['debtorCount'] ?? 0;

    return Container(
      padding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
          : ar.cardPadding,
      margin: EdgeInsets.all(isMobile ? ar.spaceXS : ar.spaceM),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(ar.cardRadius),
        border: Border.all(
          color: AccountingTheme.neonBlue.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AccountingTheme.neonBlue.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              children: [
                Row(
                  children: [
                    Expanded(
                        child: _statCompact(
                            'إجمالي التسديدات',
                            _fmt(totalPayments),
                            AccountingTheme.success,
                            Icons.payments)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _statCompact(
                            'صافي المستحقات',
                            '${_fmt(totalNet.abs())} د.ع',
                            totalNet < 0
                                ? AccountingTheme.danger
                                : AccountingTheme.success,
                            Icons.account_balance_wallet)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _statCompact('إجمالي الأجور', _fmt(totalCharges),
                            AccountingTheme.danger, Icons.receipt_long)),
                    const SizedBox(width: 8),
                    _chip('فنيين', '$techCount', AccountingTheme.neonBlue),
                    const SizedBox(width: 6),
                    _chip('مدينون', '$debtorCount', AccountingTheme.danger),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                _stat('إجمالي الأجور', _fmt(totalCharges),
                    AccountingTheme.danger, Icons.receipt_long),
                SizedBox(width: ar.spaceL),
                _stat('إجمالي التسديدات', _fmt(totalPayments),
                    AccountingTheme.success, Icons.payments),
                SizedBox(width: ar.spaceL),
                _stat(
                    'صافي المستحقات',
                    '${_fmt(totalNet.abs())} د.ع',
                    totalNet < 0
                        ? AccountingTheme.danger
                        : AccountingTheme.success,
                    Icons.account_balance_wallet),
                const Spacer(),
                _chip('فنيين', '$techCount', AccountingTheme.neonBlue),
                SizedBox(width: context.accR.spaceS),
                _chip('مدينون', '$debtorCount', AccountingTheme.danger),
              ],
            ),
    );
  }

  Widget _statCompact(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: AccountingTheme.textMuted, fontSize: 9),
                    overflow: TextOverflow.ellipsis),
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color, IconData icon) {
    final ar = context.accR;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(ar.spaceS),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(ar.btnRadius),
          ),
          child: Icon(icon, color: color, size: ar.iconM),
        ),
        SizedBox(width: ar.spaceS),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: AccountingTheme.textMuted, fontSize: ar.caption)),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: ar.financialSmall)),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  قائمة الفنيين
  // ═══════════════════════════════════════════════════
  List<dynamic> get _filteredTechnicians {
    var list = List<dynamic>.from(_technicians);
    if (_techFilter != 'all') {
      list = list.where((t) {
        final net = (t['netBalance'] ?? 0).toDouble();
        return _techFilter == 'debtor' ? net < 0 : net >= 0;
      }).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((t) {
        final name = (t['name'] ?? '').toString().toLowerCase();
        final phone = (t['phone'] ?? '').toString().toLowerCase();
        return name.contains(q) || phone.contains(q);
      }).toList();
    }
    // ترتيب
    list.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case 'name':
          cmp = (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
          break;
        case 'charges':
          cmp = (a['totalCharges'] ?? 0).toDouble().compareTo((b['totalCharges'] ?? 0).toDouble());
          break;
        case 'payments':
          cmp = (a['totalPayments'] ?? 0).toDouble().compareTo((b['totalPayments'] ?? 0).toDouble());
          break;
        default: // 'net'
          cmp = (a['netBalance'] ?? 0).toDouble().abs().compareTo((b['netBalance'] ?? 0).toDouble().abs());
      }
      return _sortAsc ? cmp : -cmp;
    });
    return list;
  }

  Widget _techFilterBtn(String label, String value) {
    final ar = context.accR;
    final isActive = _techFilter == value;
    final color = value == 'debtor'
        ? AccountingTheme.danger
        : value == 'creditor'
            ? AccountingTheme.success
            : AccountingTheme.neonBlue;
    return InkWell(
      onTap: () => setState(() => _techFilter = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding:
            EdgeInsets.symmetric(horizontal: ar.btnPadH, vertical: ar.spaceXS),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? color : AccountingTheme.borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? color : AccountingTheme.textMuted,
            fontSize: ar.small,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _sortBtn(String label, String value) {
    final ar = context.accR;
    final isActive = _sortBy == value;
    return InkWell(
      onTap: () {
        setState(() {
          if (_sortBy == value) {
            _sortAsc = !_sortAsc;
          } else {
            _sortBy = value;
            _sortAsc = value == 'name'; // الاسم تصاعدي افتراضياً، البقية تنازلي
          }
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: ar.isMobile ? 8 : 10, vertical: ar.isMobile ? 3 : 4),
        decoration: BoxDecoration(
          color: isActive
              ? AccountingTheme.neonBlue.withValues(alpha: 0.12)
              : AccountingTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? AccountingTheme.neonBlue.withValues(alpha: 0.4)
                : AccountingTheme.borderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive ? AccountingTheme.neonBlue : AccountingTheme.textMuted,
                fontSize: ar.isMobile ? 10 : 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 2),
              Icon(
                _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                size: ar.isMobile ? 12 : 14,
                color: AccountingTheme.neonBlue,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicianList() {
    final ar = context.accR;
    final isMobile = ar.isMobile;
    final list = _filteredTechnicians;
    return ListView.builder(
      padding:
          EdgeInsets.symmetric(horizontal: isMobile ? ar.spaceXS : ar.spaceM),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final tech = list[i];
        final name = tech['name'] ?? 'فني';
        final phone = tech['phone'] ?? '';
        final totalCharges = (tech['totalCharges'] ?? 0).toDouble();
        final totalPayments = (tech['totalPayments'] ?? 0).toDouble();
        final netBalance = (tech['netBalance'] ?? 0).toDouble();
        final txCount = tech['transactionCount'] ?? 0;
        final lastDate = tech['lastTransactionDate'];
        final isDebtor = netBalance < 0;
        // ignore: unused_local_variable
        final _ = phone;

        final cardColor = isDebtor ? AccountingTheme.danger : AccountingTheme.success;
        return Container(
          margin: EdgeInsets.only(bottom: ar.spaceS),
          decoration: BoxDecoration(
            color: AccountingTheme.bgCard,
            borderRadius: BorderRadius.circular(ar.cardRadius),
            border: Border.all(
              color: cardColor.withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: cardColor.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ar.cardRadius),
              border: Border(
                right: BorderSide(
                  color: cardColor,
                  width: isMobile ? 3 : 5,
                ),
              ),
            ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(ar.cardRadius),
              onTap: () => _showTechnicianDetails(tech),
              child: Padding(
                padding: isMobile
                    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 8)
                    : ar.cardPadding,
                child: isMobile
                    ? _buildTechCardMobile(
                        name: name,
                        phone: phone,
                        totalCharges: totalCharges,
                        totalPayments: totalPayments,
                        netBalance: netBalance,
                        txCount: txCount,
                        lastDate: lastDate,
                        isDebtor: isDebtor,
                        tech: tech,
                      )
                    : Row(
                        children: [
                          Container(
                            width: ar.iconXL,
                            height: ar.iconXL,
                            decoration: BoxDecoration(
                              color: (isDebtor
                                      ? AccountingTheme.danger
                                      : AccountingTheme.success)
                                  .withValues(alpha: 0.1),
                              borderRadius:
                                  BorderRadius.circular(ar.cardRadius),
                            ),
                            child: Icon(
                              isDebtor
                                  ? Icons.warning_amber_rounded
                                  : Icons.check_circle_outline,
                              color: isDebtor
                                  ? AccountingTheme.danger
                                  : AccountingTheme.success,
                              size: ar.iconM,
                            ),
                          ),
                          SizedBox(width: ar.spaceL),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: GoogleFonts.cairo(
                                        fontSize: ar.body,
                                        fontWeight: FontWeight.bold,
                                        color: AccountingTheme.textPrimary)),
                                if (phone.isNotEmpty)
                                  Text(phone,
                                      style: TextStyle(
                                          color: AccountingTheme.textMuted,
                                          fontSize: ar.small)),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                Text('الأجور',
                                    style: TextStyle(
                                        color: AccountingTheme.textMuted,
                                        fontSize: ar.caption)),
                                Text('${_fmt(totalCharges)} د.ع',
                                    style: TextStyle(
                                        color: AccountingTheme.danger,
                                        fontWeight: FontWeight.bold,
                                        fontSize: ar.financialSmall)),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                Text('التسديدات',
                                    style: TextStyle(
                                        color: AccountingTheme.textMuted,
                                        fontSize: ar.caption)),
                                Text('${_fmt(totalPayments)} د.ع',
                                    style: TextStyle(
                                        color: AccountingTheme.success,
                                        fontWeight: FontWeight.bold,
                                        fontSize: ar.financialSmall)),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                Text('المستحق',
                                    style: TextStyle(
                                        color: AccountingTheme.textMuted,
                                        fontSize: ar.caption)),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: ar.spaceS,
                                      vertical: ar.spaceXS),
                                  decoration: BoxDecoration(
                                    color: (isDebtor
                                            ? AccountingTheme.danger
                                            : AccountingTheme.success)
                                        .withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(ar.btnRadius),
                                  ),
                                  child: Text(
                                    '${_fmt(netBalance.abs())} د.ع',
                                    style: TextStyle(
                                        color: isDebtor
                                            ? AccountingTheme.danger
                                            : AccountingTheme.success,
                                        fontWeight: FontWeight.bold,
                                        fontSize: ar.financialSmall),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: ar.colStatusW,
                            child: Column(
                              children: [
                                Text('$txCount معاملة',
                                    style: TextStyle(
                                        color: AccountingTheme.textSecondary,
                                        fontSize: ar.caption)),
                                if (lastDate != null)
                                  Text(_formatDate(lastDate),
                                      style: TextStyle(
                                          color: AccountingTheme.textMuted,
                                          fontSize: ar.caption)),
                              ],
                            ),
                          ),
                          SizedBox(width: ar.spaceS),
                          if (isDebtor)
                            ElevatedButton.icon(
                              onPressed: () => _showRecordPaymentDialog(tech),
                              icon: Icon(Icons.payments, size: ar.iconXS),
                              label: Text('تسديد',
                                  style: TextStyle(fontSize: ar.caption)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AccountingTheme.success
                                    .withValues(alpha: 0.15),
                                foregroundColor: AccountingTheme.success,
                                padding: EdgeInsets.symmetric(
                                    horizontal: ar.spaceM,
                                    vertical: ar.spaceXS),
                                elevation: 0,
                              ),
                            ),
                          SizedBox(width: context.accR.spaceXS),
                          Icon(Icons.chevron_left,
                              color: AccountingTheme.textMuted, size: ar.iconM),
                        ],
                      ),
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════
  //  بطاقة فني - تخطيط موبايل
  // ═══════════════════════════════════════════════════
  Widget _buildTechCardMobile({
    required String name,
    required String phone,
    required double totalCharges,
    required double totalPayments,
    required double netBalance,
    required int txCount,
    required dynamic lastDate,
    required bool isDebtor,
    required dynamic tech,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // الصف الأول: أيقونة + اسم + رقم + زر تسديد
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: (isDebtor
                        ? AccountingTheme.danger
                        : AccountingTheme.success)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isDebtor
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
                color:
                    isDebtor ? AccountingTheme.danger : AccountingTheme.success,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.textPrimary),
                      overflow: TextOverflow.ellipsis),
                  if (phone.isNotEmpty)
                    Text(phone,
                        style: const TextStyle(
                            color: AccountingTheme.textMuted, fontSize: 10)),
                ],
              ),
            ),
            if (isDebtor)
              ElevatedButton.icon(
                onPressed: () => _showRecordPaymentDialog(tech),
                icon: const Icon(Icons.payments, size: 14),
                label: const Text('تسديد', style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      AccountingTheme.success.withValues(alpha: 0.15),
                  foregroundColor: AccountingTheme.success,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: const Size(0, 26),
                  elevation: 0,
                ),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_left,
                color: AccountingTheme.textMuted, size: 18),
          ],
        ),
        const SizedBox(height: 8),
        // الصف الثاني: الأجور + التسديدات + المستحق + معاملات
        Row(
          children: [
            Expanded(
              child: _miniStat('الأجور', '${_fmt(totalCharges)} د.ع',
                  AccountingTheme.danger),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _miniStat('التسديدات', '${_fmt(totalPayments)} د.ع',
                  AccountingTheme.success),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: (isDebtor
                          ? AccountingTheme.danger
                          : AccountingTheme.success)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  children: [
                    const Text('المستحق',
                        style: TextStyle(
                            color: AccountingTheme.textMuted, fontSize: 9)),
                    Text('${_fmt(netBalance.abs())} د.ع',
                        style: TextStyle(
                            color: isDebtor
                                ? AccountingTheme.danger
                                : AccountingTheme.success,
                            fontWeight: FontWeight.bold,
                            fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Column(
              children: [
                Text('$txCount معاملة',
                    style: const TextStyle(
                        color: AccountingTheme.textSecondary, fontSize: 9)),
                if (lastDate != null)
                  Text(_formatDate(lastDate),
                      style: const TextStyle(
                          color: AccountingTheme.textMuted, fontSize: 9)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label,
            style:
                const TextStyle(color: AccountingTheme.textMuted, fontSize: 9)),
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 11),
            overflow: TextOverflow.ellipsis),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  حوار تفاصيل معاملات فني
  // ═══════════════════════════════════════════════════
  void _showTechnicianDetails(dynamic tech) {
    final techId = tech['id']?.toString() ?? '';
    final name = tech['name'] ?? 'فني';

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: AccountingTheme.bgPrimary,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.accR.radiusL)),
          child: SizedBox(
            width: context.accR.dialogLargeW,
            height: context.accR.dialogMaxH,
            child: _TechnicianDetailsDialog(
              technicianId: techId,
              technicianName: name,
              onChanged: _loadDues,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  حوار تسجيل تسديد
  // ═══════════════════════════════════════════════════
  void _showRecordPaymentDialog(dynamic tech) {
    final name = tech['name'] ?? 'فني';
    final netBalance = (tech['netBalance'] ?? 0).toDouble();
    final techId = tech['id']?.toString() ?? '';

    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AccountingTheme.bgCard,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(context.accR.cardRadius)),
            title: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(context.accR.spaceS),
                  decoration: BoxDecoration(
                    color: AccountingTheme.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.payments,
                      color: AccountingTheme.success, size: context.accR.iconM),
                ),
                SizedBox(width: context.accR.spaceM),
                Expanded(
                  child: Text('تسجيل تسديد - $name',
                      style: GoogleFonts.cairo(
                          fontSize: context.accR.headingSmall,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.textPrimary)),
                ),
              ],
            ),
            content: SizedBox(
              width: context.accR.dialogSmallW,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(context.accR.spaceM),
                    decoration: BoxDecoration(
                      color: AccountingTheme.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: AccountingTheme.danger,
                            size: context.accR.iconM),
                        SizedBox(width: context.accR.spaceS),
                        Text('المبلغ المستحق: ${_fmt(netBalance.abs())} د.ع',
                            style: const TextStyle(
                                color: AccountingTheme.danger,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  SizedBox(height: context.accR.spaceXL),
                  _field('مبلغ التسديد', amountCtrl, isNumber: true),
                  SizedBox(height: context.accR.spaceM),
                  // حقل التاريخ
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2024),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                        locale: const Locale('ar'),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: AccountingTheme.accent, size: 18),
                          SizedBox(width: 8),
                          Text('التاريخ: ${selectedDate.year}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.day.toString().padLeft(2, '0')}',
                              style: TextStyle(fontSize: 14)),
                          const Spacer(),
                          Icon(Icons.edit, color: Colors.grey, size: 16),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: context.accR.spaceM),
                  _field('ملاحظات (اختياري)', notesCtrl),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(color: AccountingTheme.textMuted)),
              ),
              ElevatedButton.icon(
                icon: Icon(Icons.check, size: context.accR.iconM),
                label: const Text('تأكيد التسديد'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.success,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text) ?? 0;
                  if (amount <= 0) {
                    _snack('الرجاء إدخال مبلغ صحيح', AccountingTheme.warning);
                    return;
                  }
                  Navigator.pop(ctx);
                  // فحص الفترة المحاسبية
                  final payOk = await PeriodClosingService.checkAndWarnIfClosed(
                    context, date: selectedDate, companyId: widget.companyId ?? '',
                  );
                  if (!payOk) return;
                  final result =
                      await AccountingService.instance.recordTechnicianPayment(
                    technicianId: techId,
                    amount: amount,
                    notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                    transactionDate: selectedDate,
                  );
                  if (result['success'] == true) {
                    _snack('تم تسجيل التسديد بنجاح', AccountingTheme.success);
                    AuditTrailService.instance.log(
                      action: AuditAction.create,
                      entityType: AuditEntityType.collection,
                      entityId: techId,
                      entityDescription: 'تسديد: ${tech['name'] ?? ''}',
                      details: 'مبلغ: $amount',
                    );
                    _loadDues();
                  } else {
                    _snack(result['message'] ?? 'خطأ في تسجيل التسديد',
                        AccountingTheme.danger);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  حوار إضافة تحصيل
  // ═══════════════════════════════════════════════════
  void _showAddDialog() {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final receivedByCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    // توليد رقم الإيصال تلقائياً
    final now = DateTime.now();
    final rnd = (DateTime.now().millisecondsSinceEpoch % 9000) + 1000;
    final autoReceipt =
        '${now.year % 100}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}$rnd';

    // بيانات البحث عن الفنيين
    List<Map<String, dynamic>> allEmployees = [];
    List<Map<String, dynamic>> filteredEmployees = [];
    Map<String, dynamic>? selectedEmployee;
    bool isLoadingEmployees = true;
    String searchText = '';
    final searchCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // جلب الموظفين عند أول بناء
          if (isLoadingEmployees && allEmployees.isEmpty) {
            AccountingService.instance
                .getCompanyEmployees(widget.companyId ?? '')
                .then((employees) {
              setDialogState(() {
                allEmployees = employees;
                filteredEmployees = employees;
                isLoadingEmployees = false;
              });
            }).catchError((_) {
              setDialogState(() => isLoadingEmployees = false);
            });
          }

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: AccountingTheme.bgCard,
              title: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(context.accR.spaceS),
                    decoration: BoxDecoration(
                      gradient: AccountingTheme.neonBlueGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.add_card,
                        color: Colors.white, size: context.accR.iconM),
                  ),
                  SizedBox(width: context.accR.spaceM),
                  Text('إضافة تحصيل',
                      style: GoogleFonts.cairo(
                          fontSize: context.accR.headingSmall,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.textPrimary)),
                ],
              ),
              content: SizedBox(
                width: context.accR.dialogMediumW,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // === اختيار الفني ===
                      Text('الفني *',
                          style: TextStyle(
                              color: AccountingTheme.textMuted,
                              fontSize: context.accR.financialSmall)),
                      SizedBox(height: context.accR.spaceXS),
                      if (selectedEmployee != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AccountingTheme.neonBlue
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AccountingTheme.neonBlue
                                    .withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: AccountingTheme.neonBlue,
                                child: Text(
                                  (selectedEmployee!['FullName'] ?? '?')
                                      .toString()
                                      .substring(0, 1),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              SizedBox(width: context.accR.spaceM),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selectedEmployee!['FullName'] ?? '',
                                      style: const TextStyle(
                                          color: AccountingTheme.textPrimary,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    if (selectedEmployee!['Department'] != null)
                                      Text(
                                        selectedEmployee!['Department'],
                                        style: TextStyle(
                                            color: AccountingTheme.textMuted,
                                            fontSize: context.accR.small),
                                      ),
                                  ],
                                ),
                              ),
                              InkWell(
                                onTap: () => setDialogState(() {
                                  selectedEmployee = null;
                                  searchCtrl.clear();
                                  filteredEmployees = allEmployees;
                                }),
                                child: Icon(Icons.close,
                                    color: AccountingTheme.danger,
                                    size: context.accR.iconM),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        TextField(
                          controller: searchCtrl,
                          style: const TextStyle(
                              color: AccountingTheme.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'ابحث عن الفني بالاسم...',
                            hintStyle: TextStyle(
                                color: AccountingTheme.textMuted
                                    .withValues(alpha: 0.6)),
                            prefixIcon: const Icon(Icons.search,
                                color: AccountingTheme.neonBlue),
                            filled: true,
                            fillColor: AccountingTheme.bgCardHover,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none),
                          ),
                          onChanged: (val) {
                            setDialogState(() {
                              searchText = val;
                              filteredEmployees = allEmployees.where((e) {
                                final name = (e['FullName'] ?? '')
                                    .toString()
                                    .toLowerCase();
                                final phone =
                                    (e['PhoneNumber'] ?? '').toString();
                                return name.contains(val.toLowerCase()) ||
                                    phone.contains(val);
                              }).toList();
                            });
                          },
                        ),
                        if (isLoadingEmployees)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(
                                child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))),
                          )
                        else if (searchText.isNotEmpty ||
                            filteredEmployees.length <= 10)
                          Container(
                            constraints: const BoxConstraints(maxHeight: 180),
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: AccountingTheme.bgCardHover,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: filteredEmployees.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text('لا توجد نتائج',
                                        style: TextStyle(
                                            color: AccountingTheme.textMuted)),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: filteredEmployees.length,
                                    itemBuilder: (_, i) {
                                      final emp = filteredEmployees[i];
                                      return ListTile(
                                        dense: true,
                                        leading: CircleAvatar(
                                          radius: 14,
                                          backgroundColor: AccountingTheme
                                              .neonBlue
                                              .withValues(alpha: 0.15),
                                          child: Text(
                                            (emp['FullName'] ?? '?')
                                                .toString()
                                                .substring(0, 1),
                                            style: TextStyle(
                                                color: AccountingTheme.neonBlue,
                                                fontSize: context.accR.small,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        title: Text(
                                          emp['FullName'] ?? '',
                                          style: TextStyle(
                                              color:
                                                  AccountingTheme.textPrimary,
                                              fontSize:
                                                  context.accR.financialSmall),
                                        ),
                                        subtitle: Text(
                                          '${emp['Department'] ?? ''} • ${emp['PhoneNumber'] ?? ''}',
                                          style: TextStyle(
                                              color: AccountingTheme.textMuted,
                                              fontSize: context.accR.small),
                                        ),
                                        onTap: () {
                                          setDialogState(() {
                                            selectedEmployee = emp;
                                          });
                                        },
                                      );
                                    },
                                  ),
                          ),
                      ],

                      SizedBox(height: context.accR.spaceL),
                      _field('المبلغ *', amountCtrl, isNumber: true),
                      SizedBox(height: context.accR.spaceM),
                      _field('الوصف *', descCtrl),
                      SizedBox(height: context.accR.spaceM),
                      _field('المستلم', receivedByCtrl),
                      SizedBox(height: context.accR.spaceM),

                      // رقم الإيصال (تلقائي)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: AccountingTheme.bgCardHover,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.receipt_long,
                                color: AccountingTheme.textMuted,
                                size: context.accR.iconM),
                            SizedBox(width: context.accR.spaceS),
                            Text('رقم الإيصال: ',
                                style: TextStyle(
                                    color: AccountingTheme.textMuted,
                                    fontSize: context.accR.financialSmall)),
                            Text(autoReceipt,
                                style: TextStyle(
                                    color: AccountingTheme.accent,
                                    fontWeight: FontWeight.w600,
                                    fontSize: context.accR.financialSmall)),
                          ],
                        ),
                      ),
                      SizedBox(height: context.accR.spaceM),
                      _field('ملاحظات', notesCtrl),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('إلغاء',
                        style: TextStyle(color: AccountingTheme.textMuted))),
                ElevatedButton.icon(
                  icon: Icon(Icons.check, size: context.accR.iconM),
                  label: const Text('إضافة'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AccountingTheme.neonGreen,
                      foregroundColor: Colors.white),
                  onPressed: () async {
                    if (selectedEmployee == null) {
                      _snack('الرجاء اختيار الفني', AccountingTheme.warning);
                      return;
                    }
                    if (amountCtrl.text.isEmpty || descCtrl.text.isEmpty) {
                      _snack('الرجاء ملء الحقول المطلوبة',
                          AccountingTheme.warning);
                      return;
                    }
                    Navigator.pop(ctx);
                    // فحص الفترة المحاسبية
                    final createOk = await PeriodClosingService.checkAndWarnIfClosed(
                      context, date: DateTime.now(), companyId: widget.companyId ?? '',
                    );
                    if (!createOk) return;
                    final result =
                        await AccountingService.instance.createCollection(
                      technicianId: selectedEmployee!['Id']?.toString() ?? '',
                      amount: double.tryParse(amountCtrl.text) ?? 0,
                      description: descCtrl.text,
                      receiptNumber: autoReceipt,
                      receivedBy: receivedByCtrl.text.isEmpty
                          ? null
                          : receivedByCtrl.text,
                      notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                      companyId: widget.companyId ?? '',
                    );
                    if (result['success'] == true) {
                      _snack('تم إضافة التحصيل بنجاح', AccountingTheme.success);
                      AuditTrailService.instance.log(
                        action: AuditAction.create,
                        entityType: AuditEntityType.collection,
                        entityId: result['data']?['Id']?.toString() ?? '',
                        entityDescription: 'تحصيل: ${descCtrl.text}',
                        details: 'فني: ${selectedEmployee!['FullName'] ?? ''}',
                      );
                      _loadDues();
                    } else {
                      _snack(
                          result['message'] ?? 'خطأ', AccountingTheme.danger);
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  أدوات مشتركة
  // ═══════════════════════════════════════════════════
  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.spaceM, vertical: context.accR.spaceXS),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: context.accR.small)),
          SizedBox(width: context.accR.spaceXS),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: context.accR.body)),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AccountingTheme.textPrimary),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AccountingTheme.textMuted),
        filled: true,
        fillColor: AccountingTheme.bgCardHover,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none),
      ),
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  String _fmt(dynamic value) {
    if (value == null || value == 0) return '0';
    final n = value is num ? value : double.tryParse(value.toString()) ?? 0;
    return n.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      final parsed = DateTime.parse(date.toString());
      final d = parsed.isUtc ? parsed.toLocal() : parsed.toLocal();
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

// ═══════════════════════════════════════════════════
//  ويدجت تفاصيل معاملات الفني (حوار مستقل)
// ═══════════════════════════════════════════════════
class _TechnicianDetailsDialog extends StatefulWidget {
  final String technicianId;
  final String technicianName;
  final VoidCallback? onChanged;

  const _TechnicianDetailsDialog({
    required this.technicianId,
    required this.technicianName,
    this.onChanged,
  });

  @override
  State<_TechnicianDetailsDialog> createState() =>
      _TechnicianDetailsDialogState();
}

class _TechnicianDetailsDialogState extends State<_TechnicianDetailsDialog> {
  bool _isLoading = true;
  List<dynamic> _transactions = [];
  String? _error;
  String _filter = 'all'; // all, charge, payment

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);
    try {
      final result = await AccountingService.instance
          .getTechnicianTransactions(widget.technicianId);
      if (result['success'] == true) {
        final data = result['data'];
        if (data is Map<String, dynamic>) {
          _transactions =
              (data['transactions'] is List) ? data['transactions'] : [];
        }
      } else {
        _error = result['message'] ?? 'خطأ';
      }
    } catch (e) {
      _error = 'خطأ';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _showTransactionInfo(dynamic tx) {
    final type = tx['type']?.toString() ?? '';
    final isCharge = type.contains('Charge') ||
        type == '0' ||
        type == 'MaintenanceCharge' ||
        type == 'SubscriptionCharge';
    final amount = (tx['amount'] ?? 0).toDouble();
    final balanceAfter = (tx['balanceAfter'] ?? 0).toDouble();
    final desc = tx['description'] ?? '';
    final date = tx['createdAt'];
    final customerName = tx['customerName'] ?? '';
    final taskType = tx['taskType'] ?? '';
    final notes = tx['notes'] ?? '';
    final category = tx['category']?.toString() ?? '';
    final refNumber = tx['referenceNumber'] ?? '';
    final area = tx['area'] ?? '';
    final address = tx['address'] ?? '';
    final contactPhone = tx['contactPhone'] ?? '';
    final city = tx['city'] ?? '';
    final finalCost = tx['finalCost'];
    final serviceRequestId = tx['serviceRequestId'] ?? '';
    final receivedBy = tx['receivedBy'] ?? '';
    final journalEntryNumber = tx['journalEntryNumber']?.toString() ?? '';

    String typeLabel = isCharge ? 'أجور (خصم)' : 'تسديد (دفع)';
    String categoryLabel = _categoryLabel(category);

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.accR.radiusL)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(context.accR.spaceS),
                decoration: BoxDecoration(
                  color: (isCharge
                          ? AccountingTheme.danger
                          : AccountingTheme.success)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                    isCharge ? Icons.arrow_downward : Icons.arrow_upward,
                    color: isCharge
                        ? AccountingTheme.danger
                        : AccountingTheme.success,
                    size: context.accR.iconM),
              ),
              SizedBox(width: context.accR.spaceM),
              Expanded(
                child: Text('تفاصيل المعاملة',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.headingSmall,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.textPrimary)),
              ),
            ],
          ),
          content: SizedBox(
            width: context.accR.dialogMediumW,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // المبلغ الكبير
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(context.accR.spaceXL),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isCharge
                            ? [
                                AccountingTheme.danger.withValues(alpha: 0.08),
                                AccountingTheme.danger.withValues(alpha: 0.02)
                              ]
                            : [
                                AccountingTheme.success.withValues(alpha: 0.08),
                                AccountingTheme.success.withValues(alpha: 0.02)
                              ],
                      ),
                      borderRadius:
                          BorderRadius.circular(context.accR.cardRadius),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${isCharge ? "-" : "+"}${_fmt(amount)} د.ع',
                          style: TextStyle(
                              color: isCharge
                                  ? AccountingTheme.danger
                                  : AccountingTheme.success,
                              fontWeight: FontWeight.bold,
                              fontSize: context.accR.financialLarge),
                        ),
                        SizedBox(height: context.accR.spaceXS),
                        Text(typeLabel,
                            style: TextStyle(
                                color: isCharge
                                    ? AccountingTheme.danger
                                    : AccountingTheme.success,
                                fontSize: context.accR.small)),
                      ],
                    ),
                  ),
                  SizedBox(height: context.accR.spaceL),
                  // تفاصيل المعاملة
                  _infoRow('الوصف', desc),
                  _infoRow('الفئة', categoryLabel),
                  _infoRow('التاريخ', _formatDate(date)),
                  _infoRow('الرصيد بعد المعاملة', '${_fmt(balanceAfter)} د.ع'),
                  if (refNumber.isNotEmpty) _infoRow('رقم المرجع', refNumber),
                  if (journalEntryNumber.isNotEmpty)
                    _infoRow('رقم القيد', journalEntryNumber),
                  if (receivedBy.isNotEmpty) _infoRow('المستلم', receivedBy),
                  if (customerName.isNotEmpty) _infoRow('العميل', customerName),
                  if (taskType.isNotEmpty) _infoRow('نوع المهمة', taskType),
                  if (city.isNotEmpty) _infoRow('المدينة', city),
                  if (area.isNotEmpty) _infoRow('المنطقة', area),
                  if (address.isNotEmpty) _infoRow('العنوان', address),
                  if (contactPhone.isNotEmpty)
                    _infoRow('هاتف التواصل', contactPhone),
                  if (finalCost != null)
                    _infoRow('التكلفة النهائية',
                        '${_fmt((finalCost as num).toDouble())} د.ع'),
                  if (serviceRequestId.toString().isNotEmpty &&
                      serviceRequestId.toString() != 'null')
                    _infoRow(
                        'طلب الخدمة',
                        serviceRequestId.toString().length > 8
                            ? serviceRequestId.toString().substring(0, 8)
                            : serviceRequestId.toString()),
                  if (notes.isNotEmpty) _infoRow('ملاحظات', notes),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _showEditDialog(tx);
              },
              icon: Icon(Icons.edit_outlined, size: context.accR.iconS),
              label: const Text('تعديل'),
              style: TextButton.styleFrom(
                  foregroundColor: AccountingTheme.neonBlue),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _confirmDelete(tx);
              },
              icon: Icon(Icons.delete_outline, size: context.accR.iconS),
              label: const Text('حذف'),
              style:
                  TextButton.styleFrom(foregroundColor: AccountingTheme.danger),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: AccountingTheme.bgCardHover,
                foregroundColor: AccountingTheme.textPrimary,
              ),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.accR.spaceS),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(
                    color: AccountingTheme.textMuted,
                    fontSize: context.accR.small)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: AccountingTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: context.accR.financialSmall)),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(String cat) {
    switch (cat) {
      case 'SubscriptionCharge':
        return 'أجور اشتراك';
      case 'MaintenanceCharge':
        return 'أجور صيانة';
      case 'CashPayment':
        return 'تسديد نقدي';
      case 'CollectionPayment':
        return 'تحصيل';
      case 'Deduction':
        return 'خصم';
      case 'Adjustment':
        return 'تعديل';
      case 'Bonus':
        return 'مكافأة';
      default:
        return cat.isNotEmpty ? cat : 'غير محدد';
    }
  }

  void _showEditDialog(dynamic tx) {
    final txId = tx['id']?.toString() ?? '';
    final amountCtrl =
        TextEditingController(text: (tx['amount'] ?? 0).toString());
    final descCtrl = TextEditingController(text: tx['description'] ?? '');
    final notesCtrl = TextEditingController(text: tx['notes'] ?? '');
    final receivedByCtrl = TextEditingController(text: tx['receivedBy'] ?? '');
    final refNumber = tx['referenceNumber']?.toString() ?? '';
    // تاريخ المعاملة الحالي
    DateTime txDate = (() {
      try {
        final parsed = DateTime.parse(tx['createdAt']?.toString() ?? '');
        return parsed.isUtc ? parsed.toLocal() : parsed;
      } catch (_) {
        return DateTime.now();
      }
    })();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AccountingTheme.bgCard,
            title: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(context.accR.spaceS),
                  decoration: BoxDecoration(
                    gradient: AccountingTheme.neonBlueGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.edit,
                      color: Colors.white, size: context.accR.iconM),
                ),
                SizedBox(width: context.accR.spaceM),
                Text('تعديل تحصيل',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.headingSmall,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.textPrimary)),
              ],
            ),
            content: SizedBox(
              width: context.accR.dialogMediumW,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _dialogField('المبلغ *', amountCtrl, isNumber: true),
                    SizedBox(height: context.accR.spaceM),
                    _dialogField('الوصف *', descCtrl),
                    SizedBox(height: context.accR.spaceM),
                    _dialogField('المستلم', receivedByCtrl),
                    SizedBox(height: context.accR.spaceM),

                    // حقل تعديل التاريخ
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: txDate,
                          firstDate: DateTime(2024),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                          locale: const Locale('ar'),
                        );
                        if (picked != null) {
                          setDialogState(() => txDate = picked);
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, color: AccountingTheme.accent, size: 18),
                            SizedBox(width: 8),
                            Text('التاريخ: ${txDate.year}/${txDate.month.toString().padLeft(2, '0')}/${txDate.day.toString().padLeft(2, '0')}',
                                style: TextStyle(fontSize: 14)),
                            const Spacer(),
                            Icon(Icons.edit, color: Colors.grey, size: 16),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: context.accR.spaceM),

                    // رقم الإيصال (للعرض فقط)
                    if (refNumber.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: AccountingTheme.bgCardHover,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.receipt_long,
                                color: AccountingTheme.textMuted,
                                size: context.accR.iconM),
                            SizedBox(width: context.accR.spaceS),
                            Text('رقم الإيصال: ',
                                style: TextStyle(
                                    color: AccountingTheme.textMuted,
                                    fontSize: context.accR.financialSmall)),
                            Text(refNumber,
                                style: TextStyle(
                                    color: AccountingTheme.accent,
                                    fontWeight: FontWeight.w600,
                                    fontSize: context.accR.financialSmall)),
                          ],
                        ),
                      ),
                    if (refNumber.isNotEmpty)
                      SizedBox(height: context.accR.spaceM),

                    _dialogField('ملاحظات', notesCtrl),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إلغاء',
                      style: TextStyle(color: AccountingTheme.textMuted))),
              ElevatedButton.icon(
                icon: Icon(Icons.check, size: context.accR.iconM),
                label: const Text('حفظ التعديل'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AccountingTheme.neonBlue,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text);
                  if (amount == null || amount <= 0) {
                    _snack('أدخل مبلغ صحيح', AccountingTheme.warning);
                    return;
                  }
                  if (descCtrl.text.trim().isEmpty) {
                    _snack('أدخل الوصف', AccountingTheme.warning);
                    return;
                  }
                  Navigator.pop(ctx);
                  // فحص الفترة المحاسبية
                  final editOk = await PeriodClosingService.checkAndWarnIfClosed(
                    context, date: txDate, companyId: VpsAuthService.instance.currentCompanyId ?? '',
                  );
                  if (!editOk) return;
                  final result = await AccountingService.instance
                      .updateTechnicianTransaction(
                    transactionId: txId,
                    amount: amount,
                    description: descCtrl.text,
                    notes: notesCtrl.text,
                    receivedBy:
                        receivedByCtrl.text.isEmpty ? null : receivedByCtrl.text,
                    transactionDate: txDate,
                  );
                  if (result['success'] == true) {
                    _snack('تم تعديل المعاملة', AccountingTheme.success);
                    AuditTrailService.instance.log(
                      action: AuditAction.edit,
                      entityType: AuditEntityType.collection,
                      entityId: txId,
                      entityDescription: 'تعديل تحصيل: ${descCtrl.text}',
                    );
                    _loadTransactions();
                    widget.onChanged?.call();
                  } else {
                    _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(dynamic tx) {
    final txId = tx['id']?.toString() ?? '';
    final desc = tx['description'] ?? 'معاملة';
    final amount = (tx['amount'] ?? 0).toDouble();

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.accR.cardRadius)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(context.accR.spaceS),
                decoration: BoxDecoration(
                  color: AccountingTheme.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.delete_forever,
                    color: AccountingTheme.danger, size: context.accR.iconM),
              ),
              SizedBox(width: context.accR.spaceM),
              Text('تأكيد الحذف',
                  style: GoogleFonts.cairo(
                      fontSize: context.accR.headingSmall,
                      fontWeight: FontWeight.bold,
                      color: AccountingTheme.textPrimary)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('هل تريد حذف هذه المعاملة؟',
                  style: TextStyle(
                      color: AccountingTheme.textPrimary,
                      fontSize: context.accR.body)),
              SizedBox(height: context.accR.spaceM),
              Container(
                padding: EdgeInsets.all(context.accR.spaceM),
                decoration: BoxDecoration(
                  color: AccountingTheme.danger.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(desc,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AccountingTheme.textPrimary)),
                    Text('${_fmt(amount)} د.ع',
                        style: const TextStyle(
                            color: AccountingTheme.danger,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              SizedBox(height: context.accR.spaceS),
              Text('سيتم عكس تأثير المعاملة على رصيد الفني',
                  style: TextStyle(
                      color: AccountingTheme.warning,
                      fontSize: context.accR.small)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.delete, size: context.accR.iconM),
              label: const Text('حذف'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AccountingTheme.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                // فحص الفترة المحاسبية
                final delDate = DateTime.tryParse(tx['createdAt']?.toString() ?? '');
                if (delDate != null) {
                  final delOk = await PeriodClosingService.checkAndWarnIfClosed(
                    context, date: delDate, companyId: VpsAuthService.instance.currentCompanyId ?? '',
                  );
                  if (!delOk) return;
                }
                final result = await AccountingService.instance
                    .deleteTechnicianTransaction(txId);
                if (result['success'] == true) {
                  _snack('تم حذف المعاملة', AccountingTheme.success);
                  AuditTrailService.instance.log(
                    action: AuditAction.delete,
                    entityType: AuditEntityType.collection,
                    entityId: txId,
                    entityDescription: 'حذف تحصيل: $desc',
                  );
                  _loadTransactions();
                  widget.onChanged?.call();
                } else {
                  _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogField(String label, TextEditingController ctrl,
      {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AccountingTheme.textPrimary),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AccountingTheme.textMuted),
        filled: true,
        fillColor: AccountingTheme.bgCardHover,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none),
      ),
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          // العنوان
          Container(
            padding: EdgeInsets.all(context.accR.spaceXL),
            decoration: const BoxDecoration(
              color: AccountingTheme.bgCard,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                  bottom: BorderSide(color: AccountingTheme.borderColor)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(context.accR.spaceS),
                  decoration: BoxDecoration(
                    color: AccountingTheme.neonBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.receipt_long,
                      color: AccountingTheme.neonBlue,
                      size: context.accR.iconM),
                ),
                SizedBox(width: context.accR.spaceM),
                Expanded(
                  child: Text('معاملات ${widget.technicianName}',
                      style: GoogleFonts.cairo(
                          fontSize: context.accR.headingSmall,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.textPrimary)),
                ),
                IconButton(
                  onPressed: _loadTransactions,
                  icon: Icon(Icons.refresh, size: context.accR.iconM),
                  tooltip: 'تحديث',
                  style: IconButton.styleFrom(
                      foregroundColor: AccountingTheme.textSecondary),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, size: context.accR.iconM),
                  style: IconButton.styleFrom(
                      foregroundColor: AccountingTheme.textMuted),
                ),
              ],
            ),
          ),
          // أزرار التصفية
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: context.accR.paddingH,
                vertical: context.accR.spaceS),
            color: AccountingTheme.bgPrimary,
            child: Row(
              children: [
                _filterBtn('الكل', 'all'),
                SizedBox(width: context.accR.spaceS),
                _filterBtn('مديون', 'charge'),
                SizedBox(width: context.accR.spaceS),
                _filterBtn('دائن', 'payment'),
              ],
            ),
          ),
          // المحتوى
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AccountingTheme.neonBlue))
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style:
                                const TextStyle(color: AccountingTheme.danger)))
                    : _transactions.isEmpty
                        ? const Center(
                            child: Text('لا توجد معاملات',
                                style: TextStyle(
                                    color: AccountingTheme.textMuted)))
                        : ListView.builder(
                            padding: EdgeInsets.all(context.accR.spaceM),
                            itemCount: _filteredTransactions.length,
                            itemBuilder: (_, i) {
                              final tx = _filteredTransactions[i];
                              final type = tx['type']?.toString() ?? '';
                              final isCharge = type.contains('Charge') ||
                                  type == '0' ||
                                  type == 'MaintenanceCharge' ||
                                  type == 'SubscriptionCharge';
                              final amount = (tx['amount'] ?? 0).toDouble();
                              final desc = tx['description'] ?? '';
                              final date = tx['createdAt'];
                              final customerName = tx['customerName'] ?? '';
                              final taskType = tx['taskType'] ?? '';
                              final notes = tx['notes'] ?? '';

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                      context.accR.cardRadius),
                                  onTap: () => _showTransactionInfo(tx),
                                  child: Container(
                                    margin: EdgeInsets.only(
                                        bottom: context.accR.spaceS),
                                    padding:
                                        EdgeInsets.all(context.accR.spaceL),
                                    decoration: BoxDecoration(
                                      color: AccountingTheme.bgCard,
                                      borderRadius: BorderRadius.circular(
                                          context.accR.cardRadius),
                                      border: Border(
                                        right: BorderSide(
                                          color: isCharge
                                              ? AccountingTheme.danger
                                              : AccountingTheme.success,
                                          width: 3,
                                        ),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.03),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isCharge
                                              ? Icons.arrow_downward
                                              : Icons.arrow_upward,
                                          color: isCharge
                                              ? AccountingTheme.danger
                                              : AccountingTheme.success,
                                          size: context.accR.iconM,
                                        ),
                                        SizedBox(width: context.accR.spaceM),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(desc,
                                                  style: TextStyle(
                                                      color: AccountingTheme
                                                          .textPrimary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: context.accR
                                                          .financialSmall)),
                                              if (customerName.isNotEmpty)
                                                Text('العميل: $customerName',
                                                    style: TextStyle(
                                                        color: AccountingTheme
                                                            .textMuted,
                                                        fontSize: context
                                                            .accR.small)),
                                              if (taskType.isNotEmpty)
                                                Text('النوع: $taskType',
                                                    style: TextStyle(
                                                        color: AccountingTheme
                                                            .textMuted,
                                                        fontSize: context
                                                            .accR.small)),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '${isCharge ? "-" : "+"}${_fmt(amount)} د.ع',
                                          style: TextStyle(
                                              color: isCharge
                                                  ? AccountingTheme.danger
                                                  : AccountingTheme.success,
                                              fontWeight: FontWeight.bold,
                                              fontSize: context.accR.body),
                                        ),
                                        SizedBox(width: context.accR.spaceM),
                                        Text(_formatDate(date),
                                            style: TextStyle(
                                                color:
                                                    AccountingTheme.textMuted,
                                                fontSize:
                                                    context.accR.caption)),
                                        SizedBox(width: context.accR.spaceXS),
                                        // أزرار سريعة
                                        InkWell(
                                          onTap: () => _showEditDialog(tx),
                                          child: Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(Icons.edit_outlined,
                                                size: context.accR.iconS,
                                                color:
                                                    AccountingTheme.neonBlue),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => _confirmDelete(tx),
                                          child: Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(Icons.delete_outline,
                                                size: context.accR.iconS,
                                                color: AccountingTheme.danger),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  List<dynamic> get _filteredTransactions {
    if (_filter == 'all') return _transactions;
    return _transactions.where((tx) {
      final type = tx['type']?.toString() ?? '';
      final isCharge = type.contains('Charge') ||
          type == '0' ||
          type == 'MaintenanceCharge' ||
          type == 'SubscriptionCharge';
      return _filter == 'charge' ? isCharge : !isCharge;
    }).toList();
  }

  Widget _filterBtn(String label, String value) {
    final isActive = _filter == value;
    final color = value == 'charge'
        ? AccountingTheme.danger
        : value == 'payment'
            ? AccountingTheme.success
            : AccountingTheme.neonBlue;
    return InkWell(
      onTap: () => setState(() => _filter = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? color : AccountingTheme.borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? color : AccountingTheme.textMuted,
            fontSize: context.accR.small,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  String _fmt(dynamic value) {
    if (value == null || value == 0) return '0';
    final n = value is num ? value : double.tryParse(value.toString()) ?? 0;
    return n.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      final parsed = DateTime.parse(date.toString());
      final d = parsed.isUtc ? parsed.toLocal() : parsed.toLocal();
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
