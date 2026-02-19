import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';

/// صفحة إدخال قيد مركب - Compound Journal Entry
class CompoundJournalEntryPage extends StatefulWidget {
  final String? companyId;

  const CompoundJournalEntryPage({super.key, this.companyId});

  @override
  State<CompoundJournalEntryPage> createState() =>
      _CompoundJournalEntryPageState();
}

class _CompoundJournalEntryPageState extends State<CompoundJournalEntryPage> {
  final _descCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  List<dynamic> _accounts = [];

  // خطوط القيد المركب
  final List<_JournalLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    // إضافة 5 أسطر مبدئية
    for (int i = 0; i < 5; i++) {
      _lines.add(_JournalLine());
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _notesCtrl.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    setState(() => _isLoading = true);
    try {
      final result = await AccountingService.instance
          .getAccounts(companyId: widget.companyId);
      if (result['success'] == true) {
        _accounts = (result['data'] as List?) ?? [];
        // ترتيب حسب الكود
        _accounts.sort((a, b) => (a['Code']?.toString() ?? '')
            .compareTo(b['Code']?.toString() ?? ''));
      }
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  double get _totalDebit => _lines.fold(0, (s, l) => s + l.debit);

  double get _totalCredit => _lines.fold(0, (s, l) => s + l.credit);

  bool get _isBalanced =>
      _totalDebit > 0 && (_totalDebit - _totalCredit).abs() < 0.01;

  double get _difference => (_totalDebit - _totalCredit).abs();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: Column(
          children: [
            _buildPageToolbar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AccountingTheme.neonGreen))
                  : _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageToolbar() {
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
              gradient: AccountingTheme.neonPurpleGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.post_add_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text('قيد مركب',
              style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.textPrimary)),
          const Spacer(),
          TextButton.icon(
            onPressed:
                _isBalanced && !_isSaving ? () => _save(post: false) : null,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('حفظ مسودة'),
            style: TextButton.styleFrom(
                foregroundColor: AccountingTheme.neonGreen),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed:
                _isBalanced && !_isSaving ? () => _save(post: true) : null,
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('حفظ وترحيل'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isBalanced
                  ? AccountingTheme.neonGreen
                  : AccountingTheme.textMuted,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // معلومات القيد
        _buildHeader(),
        // شريط الفرق / التوازن
        _buildBalanceBar(),
        // خطوط القيد
        Expanded(child: _buildLinesTable()),
        // شريط الإجماليات
        _buildTotalsBar(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          // الوصف
          Expanded(
            flex: 3,
            child: TextField(
              controller: _descCtrl,
              style: const TextStyle(
                  color: AccountingTheme.textPrimary, fontSize: 15),
              decoration: _inputDeco('وصف القيد *', Icons.description),
            ),
          ),
          const SizedBox(width: 16),
          // التاريخ
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AccountingTheme.bgCardHover,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today,
                    color: AccountingTheme.accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  _formatDate(DateTime.now()),
                  style: const TextStyle(
                      color: AccountingTheme.textSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // ملاحظات
          Expanded(
            flex: 2,
            child: TextField(
              controller: _notesCtrl,
              style: const TextStyle(
                  color: AccountingTheme.textPrimary, fontSize: 14),
              decoration: _inputDeco('ملاحظات', Icons.notes),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceBar() {
    final balanced = _isBalanced;
    final diff = _difference;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: balanced
          ? AccountingTheme.success.withValues(alpha: 0.18)
          : AccountingTheme.danger.withValues(alpha: 0.18),
      child: Row(
        children: [
          Icon(
            balanced ? Icons.check_circle : Icons.warning_amber,
            color: balanced ? AccountingTheme.success : AccountingTheme.danger,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            balanced
                ? 'القيد متوازن ✓'
                : 'القيد غير متوازن - الفرق: ${_fmt(diff)}',
            style: TextStyle(
              color: balanced ? AccountingTheme.accent : AccountingTheme.danger,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          // زر إضافة سطر
          ElevatedButton.icon(
            onPressed: _addLine,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('إضافة سطر'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.accent.withValues(alpha: 0.15),
              foregroundColor: AccountingTheme.accent,
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinesTable() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AccountingTheme.borderColor),
      ),
      child: Column(
        children: [
          // رأس الجدول
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AccountingTheme.bgCardHover,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                  bottom: BorderSide(
                      color: AccountingTheme.accent.withValues(alpha: 0.5))),
            ),
            child: Row(
              children: [
                const SizedBox(
                    width: 40,
                    child: Text('#',
                        style: TextStyle(
                            color: AccountingTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                        textAlign: TextAlign.center)),
                const SizedBox(width: 8),
                const Expanded(
                  flex: 4,
                  child: Text('الحساب',
                      style: TextStyle(
                          color: AccountingTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: Text('مدين',
                      style: TextStyle(
                          color: AccountingTheme.success,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                      textAlign: TextAlign.center),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: Text('دائن',
                      style: TextStyle(
                          color: AccountingTheme.danger,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                      textAlign: TextAlign.center),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  flex: 2,
                  child: Text('البيان',
                      style: TextStyle(
                          color: AccountingTheme.textSecondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
                const SizedBox(width: 44),
              ],
            ),
          ),
          // سطور القيد
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _lines.length,
              itemBuilder: (_, i) => _buildLineRow(i),
            ),
          ),
        ],
      ),
    );
  }

  /// بناء widget بحث الحساب باستخدام Autocomplete
  Widget _buildAccountSearch(_JournalLine line) {
    return Autocomplete<Map<String, dynamic>>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return _accounts.cast<Map<String, dynamic>>();
        }
        final query = textEditingValue.text.toLowerCase();
        return _accounts.where((a) {
          final code = (a['Code']?.toString() ?? '').toLowerCase();
          final name = (a['Name']?.toString() ?? '').toLowerCase();
          return code.contains(query) || name.contains(query);
        }).cast<Map<String, dynamic>>();
      },
      displayStringForOption: (a) => '${a['Code']} - ${a['Name']}',
      onSelected: (a) {
        setState(() {
          line.accountId = a['Id']?.toString();
          line.accountName = '${a['Code']} - ${a['Name']}';
        });
      },
      initialValue: line.accountName != null
          ? TextEditingValue(text: line.accountName!)
          : null,
      optionsMaxHeight: 250,
      optionsViewOpenDirection: OptionsViewOpenDirection.down,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        // sync controller with stored value
        if (line.accountName != null && controller.text.isEmpty) {
          controller.text = line.accountName!;
        }
        return TextField(
          controller: controller,
          focusNode: focusNode,
          style:
              const TextStyle(color: AccountingTheme.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'ابحث بالاسم أو الكود...',
            hintStyle: TextStyle(
                color: AccountingTheme.textMuted.withValues(alpha: 0.5),
                fontSize: 12),
            prefixIcon: Icon(Icons.search,
                color: AccountingTheme.accent.withValues(alpha: 0.6), size: 18),
            filled: true,
            fillColor: AccountingTheme.bgCardHover,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: AccountingTheme.textMuted.withValues(alpha: 0.3))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: AccountingTheme.textMuted.withValues(alpha: 0.25))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AccountingTheme.neonBlue)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topRight,
          child: Material(
            elevation: 4,
            color: AccountingTheme.bgCard,
            borderRadius: BorderRadius.circular(8),
            shadowColor: Colors.black26,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 250, maxWidth: 400),
              decoration: BoxDecoration(
                border: Border.all(color: AccountingTheme.borderColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final opt = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(opt),
                    hoverColor: AccountingTheme.bgCardHover,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                              color: AccountingTheme.borderColor
                                  .withValues(alpha: 0.5)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AccountingTheme.accent
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              opt['Code']?.toString() ?? '',
                              style: const TextStyle(
                                  color: AccountingTheme.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              opt['Name']?.toString() ?? '',
                              style: const TextStyle(
                                  color: AccountingTheme.textPrimary,
                                  fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLineRow(int index) {
    final line = _lines[index];
    final isEven = index % 2 == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isEven
            ? Colors.transparent
            : AccountingTheme.textMuted.withValues(alpha: 0.05),
      ),
      child: Row(
        children: [
          // رقم السطر
          SizedBox(
            width: 40,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AccountingTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                    color: AccountingTheme.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // بحث الحساب
          Expanded(
            flex: 4,
            child: _buildAccountSearch(line),
          ),
          const SizedBox(width: 8),
          // مبلغ المدين
          SizedBox(
            width: 150,
            child: TextField(
              controller: line.debitCtrl,
              style: const TextStyle(
                  color: AccountingTheme.debitText,
                  fontSize: 15,
                  fontWeight: FontWeight.w500),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              onChanged: (v) {
                setState(() {
                  line.debit = double.tryParse(v) ?? 0;
                  if (line.debit > 0 && line.credit > 0) {
                    line.credit = 0;
                    line.creditCtrl.clear();
                  }
                });
              },
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(
                    color: AccountingTheme.textMuted.withValues(alpha: 0.4)),
                filled: true,
                fillColor: AccountingTheme.debitFill,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: AccountingTheme.success.withValues(alpha: 0.4))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: AccountingTheme.success.withValues(alpha: 0.4))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: AccountingTheme.neonGreen, width: 1.5)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // مبلغ الدائن
          SizedBox(
            width: 150,
            child: TextField(
              controller: line.creditCtrl,
              style: const TextStyle(
                  color: AccountingTheme.creditText,
                  fontSize: 15,
                  fontWeight: FontWeight.w500),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              onChanged: (v) {
                setState(() {
                  line.credit = double.tryParse(v) ?? 0;
                  if (line.credit > 0 && line.debit > 0) {
                    line.debit = 0;
                    line.debitCtrl.clear();
                  }
                });
              },
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(
                    color: AccountingTheme.textMuted.withValues(alpha: 0.4)),
                filled: true,
                fillColor: AccountingTheme.creditFill,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: AccountingTheme.danger.withValues(alpha: 0.4))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: AccountingTheme.danger.withValues(alpha: 0.4))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: AccountingTheme.danger, width: 1.5)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // البيان
          Expanded(
            flex: 2,
            child: TextField(
              controller: line.descCtrl,
              style: const TextStyle(
                  color: AccountingTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'بيان السطر',
                hintStyle: TextStyle(
                    color: AccountingTheme.textMuted.withValues(alpha: 0.4),
                    fontSize: 12),
                filled: true,
                fillColor: AccountingTheme.bgCardHover,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color:
                            AccountingTheme.textMuted.withValues(alpha: 0.2))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color:
                            AccountingTheme.textMuted.withValues(alpha: 0.2))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: AccountingTheme.accent.withValues(alpha: 0.5))),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              ),
            ),
          ),
          // زر حذف السطر
          SizedBox(
            width: 44,
            child: _lines.length > 2
                ? IconButton(
                    icon: Icon(Icons.remove_circle,
                        color: AccountingTheme.danger, size: 22),
                    onPressed: () => _removeLine(index),
                    tooltip: 'حذف السطر',
                  )
                : const SizedBox(),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(
            top: BorderSide(
                color: AccountingTheme.accent.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          const Text('عدد الأسطر: ',
              style: TextStyle(
                  color: AccountingTheme.textSecondary, fontSize: 14)),
          Text('${_lines.length}',
              style: const TextStyle(
                  color: AccountingTheme.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const Spacer(),
          // إجمالي المدين
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: AccountingTheme.debitFill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AccountingTheme.success.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Text('إجمالي المدين: ',
                    style: TextStyle(
                        color: AccountingTheme.neonGreen, fontSize: 14)),
                Text(_fmt(_totalDebit),
                    style: const TextStyle(
                        color: AccountingTheme.neonGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // إجمالي الدائن
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: AccountingTheme.creditFill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AccountingTheme.danger.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Text('إجمالي الدائن: ',
                    style:
                        TextStyle(color: AccountingTheme.danger, fontSize: 14)),
                Text(_fmt(_totalCredit),
                    style: const TextStyle(
                        color: AccountingTheme.danger,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // الفرق
          if (!_isBalanced)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: AccountingTheme.warning.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AccountingTheme.warning.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Text('الفرق: ',
                      style: TextStyle(
                          color: AccountingTheme.warning, fontSize: 14)),
                  Text(_fmt(_difference),
                      style: const TextStyle(
                          color: AccountingTheme.warning,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _addLine() {
    setState(() => _lines.add(_JournalLine()));
  }

  void _removeLine(int index) {
    if (_lines.length <= 2) return;
    setState(() {
      _lines[index].dispose();
      _lines.removeAt(index);
    });
  }

  Future<void> _save({required bool post}) async {
    // التحقق من الوصف
    if (_descCtrl.text.trim().isEmpty) {
      _snack('الرجاء إدخال وصف القيد', AccountingTheme.warning);
      return;
    }
    // التحقق من التوازن
    if (!_isBalanced) {
      _snack('القيد غير متوازن', AccountingTheme.warning);
      return;
    }
    // التحقق من الأسطر
    final validLines = _lines
        .where((l) => l.accountId != null && (l.debit > 0 || l.credit > 0))
        .toList();
    if (validLines.length < 2) {
      _snack(
          'يجب أن يكون هناك سطران صالحان على الأقل', AccountingTheme.warning);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userId = VpsAuthService.instance.currentUser?.id;
      // إنشاء القيد
      final result = await AccountingService.instance.createJournalEntry(
        description: _descCtrl.text.trim(),
        lines: validLines
            .map((l) => {
                  'AccountId': l.accountId,
                  'DebitAmount': l.debit,
                  'CreditAmount': l.credit,
                  'Description':
                      l.descCtrl.text.isNotEmpty ? l.descCtrl.text : null,
                })
            .toList(),
        notes: _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
        companyId: widget.companyId ?? '',
        createdById: userId,
      );

      if (result['success'] == true) {
        if (post) {
          // ترحيل القيد مباشرةً
          final entryId = result['data']?['Id']?.toString();
          if (entryId != null) {
            final postResult = await AccountingService.instance
                .postJournalEntry(entryId, approvedById: userId);
            if (postResult['success'] == true) {
              _snack('تم حفظ وترحيل القيد بنجاح', AccountingTheme.success);
            } else {
              _snack('تم الحفظ لكن فشل الترحيل: ${postResult['message']}',
                  AccountingTheme.warning);
            }
          }
        } else {
          _snack('تم حفظ القيد كمسودة', AccountingTheme.success);
        }
        if (mounted) Navigator.pop(context, true);
      } else {
        _snack(result['message'] ?? 'خطأ في حفظ القيد', AccountingTheme.danger);
      }
    } catch (e) {
      _snack('خطأ: $e', AccountingTheme.danger);
    }

    if (mounted) setState(() => _isSaving = false);
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          const TextStyle(color: AccountingTheme.textMuted, fontSize: 13),
      prefixIcon: Icon(icon, color: AccountingTheme.accent, size: 20),
      filled: true,
      fillColor: AccountingTheme.bgCardHover,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
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

  String _formatDate(DateTime d) {
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }
}

/// نموذج سطر القيد - يحتوي على controllers وقيم
class _JournalLine {
  String? accountId;
  String? accountName;
  double debit = 0;
  double credit = 0;
  final debitCtrl = TextEditingController();
  final creditCtrl = TextEditingController();
  final descCtrl = TextEditingController();

  void dispose() {
    debitCtrl.dispose();
    creditCtrl.dispose();
    descCtrl.dispose();
  }
}
