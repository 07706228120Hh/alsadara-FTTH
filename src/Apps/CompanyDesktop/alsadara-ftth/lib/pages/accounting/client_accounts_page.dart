import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../theme/accounting_theme.dart';

/// صفحة حسابات العملاء - بسيطة ومباشرة
class ClientAccountsPage extends StatefulWidget {
  final String? companyId;

  const ClientAccountsPage({super.key, this.companyId});

  @override
  State<ClientAccountsPage> createState() => _ClientAccountsPageState();
}

class _ClientAccountsPageState extends State<ClientAccountsPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _clientAccounts = [];
  List<dynamic> _allAccounts = [];
  String _searchQuery = '';

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
      final result = await AccountingService.instance
          .getAccounts(companyId: widget.companyId);
      if (!mounted) return;
      if (result['success'] == true) {
        _allAccounts = (result['data'] as List?) ?? [];
        // تصفية حسابات العملاء (كود 1200-1299 أو يحتوي على "عميل" أو "ذمم")
        _clientAccounts = _allAccounts.where((a) {
          final code = a['Code']?.toString() ?? '';
          final name = (a['Name']?.toString() ?? '').toLowerCase();
          return code.startsWith('12') ||
              name.contains('عميل') ||
              name.contains('عملاء') ||
              name.contains('ذمم') ||
              name.contains('مدينون');
        }).toList();
        _clientAccounts.sort((a, b) => (a['Code']?.toString() ?? '')
            .compareTo(b['Code']?.toString() ?? ''));
      } else {
        _errorMessage = result['message'] ?? 'خطأ';
      }
    } catch (e) {
      if (!mounted) return;
      _errorMessage = 'خطأ: $e';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  List<dynamic> get _filtered {
    if (_searchQuery.isEmpty) return _clientAccounts;
    final q = _searchQuery.toLowerCase();
    return _clientAccounts.where((a) {
      final name = (a['Name']?.toString() ?? '').toLowerCase();
      final code = (a['Code']?.toString() ?? '').toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();
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
            _buildSummaryBar(),
            // بحث
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                height: 36,
                child: TextField(
                  style: GoogleFonts.cairo(
                      fontSize: 13, color: AccountingTheme.textPrimary),
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'بحث عن عميل...',
                    hintStyle: GoogleFonts.cairo(
                        fontSize: 13, color: AccountingTheme.textMuted),
                    prefixIcon: const Icon(Icons.search,
                        size: 18, color: AccountingTheme.textMuted),
                    filled: true,
                    fillColor: AccountingTheme.bgPrimary,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                            color: AccountingTheme.borderColor)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                            color: AccountingTheme.borderColor)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: AccountingTheme.neonBlue)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border:
            Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
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
            child:
                const Icon(Icons.people_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text('حسابات العملاء',
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AccountingTheme.textPrimary,
              )),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AccountingTheme.neonPink.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${_clientAccounts.length}',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.neonPink,
                )),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: _showAddClientDialog,
            icon: const Icon(Icons.add, size: 16),
            label: Text('إضافة عميل', style: GoogleFonts.cairo(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.neonGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    double totalDebit = 0;
    double totalCredit = 0;
    for (final a in _clientAccounts) {
      final balance =
          ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble();
      if (balance > 0) {
        totalDebit += balance;
      } else {
        totalCredit += balance.abs();
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AccountingTheme.bgCard,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _chip('عدد العملاء ${_clientAccounts.length}',
              AccountingTheme.neonGreen),
          const SizedBox(width: 8),
          _chip('مدين ${_fmt(totalDebit)} د.ع', AccountingTheme.danger),
          const SizedBox(width: 8),
          _chip('دائن ${_fmt(totalCredit)} د.ع', AccountingTheme.success),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: color.withAlpha(150)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyan));
    }
    if (_errorMessage != null) {
      return Center(
          child: Text(_errorMessage!,
              style: const TextStyle(color: AccountingTheme.danger)));
    }
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline,
                size: 64, color: AccountingTheme.textMuted.withAlpha(80)),
            const SizedBox(height: 12),
            Text(
                _clientAccounts.isEmpty
                    ? 'لا توجد حسابات عملاء'
                    : 'لا توجد نتائج',
                style: const TextStyle(color: AccountingTheme.textMuted)),
            if (_clientAccounts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('اضغط + لإضافة عميل جديد',
                    style: TextStyle(
                        color: AccountingTheme.textMuted.withAlpha(100),
                        fontSize: 12)),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final a = items[i];
        final code = a['Code']?.toString() ?? '';
        final name = a['Name']?.toString() ?? '';
        final balance =
            ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble();
        final isDebit = balance > 0;
        final balanceColor = balance == 0
            ? AccountingTheme.textMuted
            : (isDebit
                ? AccountingTheme.danger
                : AccountingTheme.accent);
        final balanceLabel =
            balance == 0 ? 'مسدد' : (isDebit ? 'مدين' : 'دائن');

        return Card(
          color: AccountingTheme.bgCard,
          margin: const EdgeInsets.only(bottom: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.cyan.withAlpha(30),
              child: const Icon(Icons.person, color: Colors.cyan),
            ),
            title: Text(name,
                style: const TextStyle(
                    color: AccountingTheme.textPrimary,
                    fontWeight: FontWeight.bold)),
            subtitle: Text('كود: $code',
                style: const TextStyle(
                    color: AccountingTheme.textMuted, fontSize: 12)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${_fmt(balance.abs())} د.ع',
                    style: TextStyle(
                        color: balanceColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                Text(balanceLabel,
                    style: TextStyle(color: balanceColor, fontSize: 11)),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── إضافة عميل جديد ───
  void _showAddClientDialog() {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final balanceCtrl = TextEditingController(text: '0');

    // تحديد أول كود متاح في سلسلة 12xx
    _suggestNextCode(codeCtrl);

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, ss) => AlertDialog(
            backgroundColor: AccountingTheme.bgCard,
            title: const Text('إضافة عميل جديد',
                style: TextStyle(color: AccountingTheme.textPrimary)),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _field('اسم العميل *', nameCtrl),
                    const SizedBox(height: 10),
                    _field('كود الحساب *', codeCtrl),
                    const SizedBox(height: 10),
                    _field('رقم الهاتف (اختياري)', phoneCtrl),
                    const SizedBox(height: 10),
                    _field('الرصيد الافتتاحي', balanceCtrl, isNumber: true),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.cyan.withAlpha(60)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.cyan, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'حساب العميل يُنشأ كـ "أصول" (ذمم مدينة).\n'
                              'رصيد موجب = عليه (مدين)\n'
                              'رصيد سالب = له (دائن)',
                              style:
                                  TextStyle(color: Colors.cyan, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء',
                      style: TextStyle(color: AccountingTheme.textMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty ||
                      codeCtrl.text.trim().isEmpty) {
                    _snack('الرجاء ملء الاسم والكود',
                        AccountingTheme.warning);
                    return;
                  }
                  Navigator.pop(ctx);

                  // تحديد الحساب الأب (1200 - ذمم مدينة) إن وُجد
                  String? parentId = _findParentAccountId();

                  final desc = phoneCtrl.text.trim().isNotEmpty
                      ? 'عميل - هاتف: ${phoneCtrl.text.trim()}'
                      : 'حساب عميل';

                  final result = await AccountingService.instance.createAccount(
                    code: codeCtrl.text.trim(),
                    name: nameCtrl.text.trim(),
                    accountType: 'Assets',
                    parentAccountId: parentId,
                    openingBalance: double.tryParse(balanceCtrl.text) ?? 0,
                    description: desc,
                    companyId: widget.companyId ?? '',
                  );

                  if (result['success'] == true) {
                    _snack(
                        'تم إضافة العميل بنجاح', AccountingTheme.success);
                    _loadData();
                  } else {
                    _snack(result['message'] ?? 'خطأ',
                        AccountingTheme.danger);
                  }
                },
                child: const Text('إضافة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// البحث عن أول كود متاح في سلسلة 12xx
  void _suggestNextCode(TextEditingController ctrl) {
    final existingCodes = _allAccounts
        .map((a) => a['Code']?.toString() ?? '')
        .where((c) => c.startsWith('12'))
        .toList()
      ..sort();

    if (existingCodes.isEmpty) {
      ctrl.text = '1201';
      return;
    }

    // ابدأ من 1201 وابحث عن أول رقم غير مستخدم
    for (int i = 1201; i < 1300; i++) {
      if (!existingCodes.contains(i.toString())) {
        ctrl.text = i.toString();
        return;
      }
    }
    ctrl.text = '1201';
  }

  /// البحث عن الحساب الأب (1200 - ذمم مدينة)
  String? _findParentAccountId() {
    for (final a in _allAccounts) {
      final code = a['Code']?.toString() ?? '';
      if (code == '1200') {
        return a['Id']?.toString();
      }
    }
    // إذا لم يتم العثور على 1200، ابحث عن أي حساب أصول رئيسي
    for (final a in _allAccounts) {
      final code = a['Code']?.toString() ?? '';
      if (code == '1000' || code == '10') {
        return a['Id']?.toString();
      }
    }
    return null;
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
}
