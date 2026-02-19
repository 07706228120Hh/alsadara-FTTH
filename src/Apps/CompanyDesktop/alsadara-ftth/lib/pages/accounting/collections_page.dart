import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../theme/accounting_theme.dart';

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

  @override
  void initState() {
    super.initState();
    _loadDues();
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
      _error = 'خطأ: $e';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: Column(
          children: [
            _buildToolbar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  شريط الأدوات العلوي
  // ═══════════════════════════════════════════════════
  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonBlueGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.engineering_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text('تحصيلات الفنيين',
              style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.textPrimary)),
          const Spacer(),
          IconButton(
            onPressed: _loadDues,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _showAddDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('إضافة تحصيل'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.neonBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                color: AccountingTheme.danger, size: 48),
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: AccountingTheme.danger)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadDues,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('إعادة المحاولة'),
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
        // أزرار التصفية
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              _techFilterBtn('الكل', 'all'),
              const SizedBox(width: 8),
              _techFilterBtn('مديون', 'debtor'),
              const SizedBox(width: 8),
              _techFilterBtn('دائن', 'creditor'),
            ],
          ),
        ),
        Expanded(
          child: _filteredTechnicians.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: AccountingTheme.success, size: 64),
                      const SizedBox(height: 16),
                      Text(
                          _techFilter == 'all'
                              ? 'لا توجد مستحقات على الفنيين'
                              : _techFilter == 'debtor'
                                  ? 'لا يوجد فنيين مدينون'
                                  : 'لا يوجد فنيين دائنون',
                          style: const TextStyle(
                              color: AccountingTheme.textMuted, fontSize: 16)),
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
    final totalCharges = (_summary['totalCharges'] ?? 0).toDouble();
    final totalPayments = (_summary['totalPayments'] ?? 0).toDouble();
    final totalNet = (_summary['totalNetBalance'] ?? 0).toDouble();
    final techCount = _summary['technicianCount'] ?? 0;
    final debtorCount = _summary['debtorCount'] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _stat('إجمالي الأجور', _fmt(totalCharges), AccountingTheme.danger,
              Icons.receipt_long),
          const SizedBox(width: 16),
          _stat('إجمالي التسديدات', _fmt(totalPayments),
              AccountingTheme.success, Icons.payments),
          const SizedBox(width: 16),
          _stat(
              'صافي المستحقات',
              '${_fmt(totalNet.abs())} د.ع',
              totalNet < 0 ? AccountingTheme.danger : AccountingTheme.success,
              Icons.account_balance_wallet),
          const Spacer(),
          _chip('فنيين', '$techCount', AccountingTheme.neonBlue),
          const SizedBox(width: 8),
          _chip('مدينون', '$debtorCount', AccountingTheme.danger),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AccountingTheme.textMuted, fontSize: 11)),
            Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  قائمة الفنيين
  // ═══════════════════════════════════════════════════
  List<dynamic> get _filteredTechnicians {
    if (_techFilter == 'all') return _technicians;
    return _technicians.where((t) {
      final net = (t['netBalance'] ?? 0).toDouble();
      return _techFilter == 'debtor' ? net < 0 : net >= 0;
    }).toList();
  }

  Widget _techFilterBtn(String label, String value) {
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
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTechnicianList() {
    final list = _filteredTechnicians;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
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

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AccountingTheme.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              right: BorderSide(
                color:
                    isDebtor ? AccountingTheme.danger : AccountingTheme.success,
                width: 4,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showTechnicianDetails(tech),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // أيقونة الفني
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: (isDebtor
                                ? AccountingTheme.danger
                                : AccountingTheme.success)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isDebtor
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        color: isDebtor
                            ? AccountingTheme.danger
                            : AccountingTheme.success,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // اسم الفني ورقمه
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: GoogleFonts.cairo(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AccountingTheme.textPrimary)),
                          if (phone.isNotEmpty)
                            Text(phone,
                                style: const TextStyle(
                                    color: AccountingTheme.textMuted,
                                    fontSize: 12)),
                        ],
                      ),
                    ),
                    // إجمالي الأجور
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          const Text('الأجور',
                              style: TextStyle(
                                  color: AccountingTheme.textMuted,
                                  fontSize: 10)),
                          Text('${_fmt(totalCharges)} د.ع',
                              style: const TextStyle(
                                  color: AccountingTheme.danger,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                    // التسديدات
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          const Text('التسديدات',
                              style: TextStyle(
                                  color: AccountingTheme.textMuted,
                                  fontSize: 10)),
                          Text('${_fmt(totalPayments)} د.ع',
                              style: const TextStyle(
                                  color: AccountingTheme.success,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                    // صافي المستحق
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          const Text('المستحق',
                              style: TextStyle(
                                  color: AccountingTheme.textMuted,
                                  fontSize: 10)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: (isDebtor
                                      ? AccountingTheme.danger
                                      : AccountingTheme.success)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${_fmt(netBalance.abs())} د.ع',
                              style: TextStyle(
                                  color: isDebtor
                                      ? AccountingTheme.danger
                                      : AccountingTheme.success,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // عدد المعاملات وآخر تاريخ
                    SizedBox(
                      width: 100,
                      child: Column(
                        children: [
                          Text('$txCount معاملة',
                              style: const TextStyle(
                                  color: AccountingTheme.textSecondary,
                                  fontSize: 11)),
                          if (lastDate != null)
                            Text(_formatDate(lastDate),
                                style: const TextStyle(
                                    color: AccountingTheme.textMuted,
                                    fontSize: 10)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // زر تسديد
                    if (isDebtor)
                      ElevatedButton.icon(
                        onPressed: () => _showRecordPaymentDialog(tech),
                        icon: const Icon(Icons.payments, size: 14),
                        label:
                            const Text('تسديد', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              AccountingTheme.success.withValues(alpha: 0.15),
                          foregroundColor: AccountingTheme.success,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          elevation: 0,
                        ),
                      ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_left,
                        color: AccountingTheme.textMuted, size: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 750,
            height: 550,
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

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AccountingTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.payments,
                    color: AccountingTheme.success, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('تسجيل تسديد - $name',
                    style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.textPrimary)),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AccountingTheme.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: AccountingTheme.danger, size: 18),
                      const SizedBox(width: 8),
                      Text('المبلغ المستحق: ${_fmt(netBalance.abs())} د.ع',
                          style: const TextStyle(
                              color: AccountingTheme.danger,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _field('مبلغ التسديد', amountCtrl, isNumber: true),
                const SizedBox(height: 10),
                _field('ملاحظات (اختياري)', notesCtrl),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check, size: 18),
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
                final result =
                    await AccountingService.instance.recordTechnicianPayment(
                  technicianId: techId,
                  amount: amount,
                  notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                );
                if (result['success'] == true) {
                  _snack('تم تسجيل التسديد بنجاح', AccountingTheme.success);
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: AccountingTheme.neonBlueGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add_card,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text('إضافة تحصيل',
                      style: GoogleFonts.cairo(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.textPrimary)),
                ],
              ),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // === اختيار الفني ===
                      const Text('الفني *',
                          style: TextStyle(
                              color: AccountingTheme.textMuted, fontSize: 13)),
                      const SizedBox(height: 6),
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
                              const SizedBox(width: 10),
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
                                        style: const TextStyle(
                                            color: AccountingTheme.textMuted,
                                            fontSize: 12),
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
                                child: const Icon(Icons.close,
                                    color: AccountingTheme.danger, size: 18),
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
                                            style: const TextStyle(
                                                color: AccountingTheme.neonBlue,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        title: Text(
                                          emp['FullName'] ?? '',
                                          style: const TextStyle(
                                              color:
                                                  AccountingTheme.textPrimary,
                                              fontSize: 13),
                                        ),
                                        subtitle: Text(
                                          '${emp['Department'] ?? ''} • ${emp['PhoneNumber'] ?? ''}',
                                          style: const TextStyle(
                                              color: AccountingTheme.textMuted,
                                              fontSize: 11),
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

                      const SizedBox(height: 14),
                      _field('المبلغ *', amountCtrl, isNumber: true),
                      const SizedBox(height: 10),
                      _field('الوصف *', descCtrl),
                      const SizedBox(height: 10),
                      _field('المستلم', receivedByCtrl),
                      const SizedBox(height: 10),

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
                            const Icon(Icons.receipt_long,
                                color: AccountingTheme.textMuted, size: 18),
                            const SizedBox(width: 8),
                            const Text('رقم الإيصال: ',
                                style: TextStyle(
                                    color: AccountingTheme.textMuted,
                                    fontSize: 13)),
                            Text(autoReceipt,
                                style: const TextStyle(
                                    color: AccountingTheme.accent,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _field('ملاحظات', notesCtrl),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء',
                        style: TextStyle(color: AccountingTheme.textMuted))),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 18),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style:
                  TextStyle(color: color.withValues(alpha: 0.7), fontSize: 12)),
          const SizedBox(width: 6),
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 14)),
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
      final d = DateTime.parse(date.toString());
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
      _error = 'خطأ: $e';
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

    String typeLabel = isCharge ? 'أجور (خصم)' : 'تسديد (دفع)';
    String categoryLabel = _categoryLabel(category);

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
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
                    size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('تفاصيل المعاملة',
                    style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.textPrimary)),
              ),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // المبلغ الكبير
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
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
                      borderRadius: BorderRadius.circular(10),
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
                              fontSize: 24),
                        ),
                        const SizedBox(height: 4),
                        Text(typeLabel,
                            style: TextStyle(
                                color: isCharge
                                    ? AccountingTheme.danger
                                    : AccountingTheme.success,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // تفاصيل المعاملة
                  _infoRow('الوصف', desc),
                  _infoRow('الفئة', categoryLabel),
                  _infoRow('التاريخ', _formatDate(date)),
                  _infoRow('الرصيد بعد المعاملة', '${_fmt(balanceAfter)} د.ع'),
                  if (refNumber.isNotEmpty) _infoRow('رقم المرجع', refNumber),
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
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('تعديل'),
              style: TextButton.styleFrom(
                  foregroundColor: AccountingTheme.neonBlue),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _confirmDelete(tx);
              },
              icon: const Icon(Icons.delete_outline, size: 16),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    color: AccountingTheme.textMuted, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AccountingTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 13)),
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

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: AccountingTheme.neonBlueGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.edit, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Text('تعديل تحصيل',
                  style: GoogleFonts.cairo(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AccountingTheme.textPrimary)),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _dialogField('المبلغ *', amountCtrl, isNumber: true),
                  const SizedBox(height: 10),
                  _dialogField('الوصف *', descCtrl),
                  const SizedBox(height: 10),
                  _dialogField('المستلم', receivedByCtrl),
                  const SizedBox(height: 10),

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
                          const Icon(Icons.receipt_long,
                              color: AccountingTheme.textMuted, size: 18),
                          const SizedBox(width: 8),
                          const Text('رقم الإيصال: ',
                              style: TextStyle(
                                  color: AccountingTheme.textMuted,
                                  fontSize: 13)),
                          Text(refNumber,
                              style: const TextStyle(
                                  color: AccountingTheme.accent,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  if (refNumber.isNotEmpty) const SizedBox(height: 10),

                  _dialogField('ملاحظات', notesCtrl),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء',
                    style: TextStyle(color: AccountingTheme.textMuted))),
            ElevatedButton.icon(
              icon: const Icon(Icons.check, size: 18),
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
                final result = await AccountingService.instance
                    .updateTechnicianTransaction(
                  transactionId: txId,
                  amount: amount,
                  description: descCtrl.text,
                  notes: notesCtrl.text,
                  receivedBy:
                      receivedByCtrl.text.isEmpty ? null : receivedByCtrl.text,
                );
                if (result['success'] == true) {
                  _snack('تم تعديل المعاملة', AccountingTheme.success);
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AccountingTheme.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_forever,
                    color: AccountingTheme.danger, size: 20),
              ),
              const SizedBox(width: 10),
              Text('تأكيد الحذف',
                  style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AccountingTheme.textPrimary)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('هل تريد حذف هذه المعاملة؟',
                  style: TextStyle(
                      color: AccountingTheme.textPrimary, fontSize: 14)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
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
              const SizedBox(height: 8),
              const Text('سيتم عكس تأثير المعاملة على رصيد الفني',
                  style:
                      TextStyle(color: AccountingTheme.warning, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete, size: 18),
              label: const Text('حذف'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AccountingTheme.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await AccountingService.instance
                    .deleteTechnicianTransaction(txId);
                if (result['success'] == true) {
                  _snack('تم حذف المعاملة', AccountingTheme.success);
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
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AccountingTheme.bgCard,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                  bottom: BorderSide(color: AccountingTheme.borderColor)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AccountingTheme.neonBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.receipt_long,
                      color: AccountingTheme.neonBlue, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('معاملات ${widget.technicianName}',
                      style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.textPrimary)),
                ),
                IconButton(
                  onPressed: _loadTransactions,
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'تحديث',
                  style: IconButton.styleFrom(
                      foregroundColor: AccountingTheme.textSecondary),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                  style: IconButton.styleFrom(
                      foregroundColor: AccountingTheme.textMuted),
                ),
              ],
            ),
          ),
          // أزرار التصفية
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AccountingTheme.bgPrimary,
            child: Row(
              children: [
                _filterBtn('الكل', 'all'),
                const SizedBox(width: 8),
                _filterBtn('مديون', 'charge'),
                const SizedBox(width: 8),
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
                            padding: const EdgeInsets.all(12),
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
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => _showTransactionInfo(tx),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: AccountingTheme.bgCard,
                                      borderRadius: BorderRadius.circular(10),
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
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(desc,
                                                  style: const TextStyle(
                                                      color: AccountingTheme
                                                          .textPrimary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13)),
                                              if (customerName.isNotEmpty)
                                                Text('العميل: $customerName',
                                                    style: const TextStyle(
                                                        color: AccountingTheme
                                                            .textMuted,
                                                        fontSize: 11)),
                                              if (taskType.isNotEmpty)
                                                Text('النوع: $taskType',
                                                    style: const TextStyle(
                                                        color: AccountingTheme
                                                            .textMuted,
                                                        fontSize: 11)),
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
                                              fontSize: 14),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(_formatDate(date),
                                            style: const TextStyle(
                                                color:
                                                    AccountingTheme.textMuted,
                                                fontSize: 10)),
                                        const SizedBox(width: 6),
                                        // أزرار سريعة
                                        InkWell(
                                          onTap: () => _showEditDialog(tx),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(Icons.edit_outlined,
                                                size: 16,
                                                color:
                                                    AccountingTheme.neonBlue),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => _confirmDelete(tx),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(Icons.delete_outline,
                                                size: 16,
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
            fontSize: 12,
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
      final d = DateTime.parse(date.toString());
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
