import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

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
        body: SafeArea(
          child: Column(
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
      ),
    );
  }

  Widget _buildPageToolbar() {
    final ar = context.accR;
    final isMob = ar.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 8 : ar.spaceM, vertical: isMob ? 6 : ar.spaceXS),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_forward_rounded, size: isMob ? 20 : 24),
            tooltip: 'رجوع',
            padding: isMob ? EdgeInsets.all(4) : null,
            constraints: isMob
                ? const BoxConstraints(minWidth: 32, minHeight: 32)
                : null,
            style: IconButton.styleFrom(foregroundColor: Colors.black),
          ),
          SizedBox(width: isMob ? 4 : ar.spaceS),
          Container(
            padding: EdgeInsets.all(isMob ? 4 : ar.spaceS),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonPurpleGradient,
              borderRadius: BorderRadius.circular(isMob ? 6 : 8),
            ),
            child: Icon(Icons.post_add_rounded,
                color: Colors.white, size: isMob ? 16 : ar.iconM),
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          Text('قيد مركب',
              style: GoogleFonts.cairo(
                  fontSize: isMob ? 14 : ar.headingMedium,
                  fontWeight: FontWeight.bold,
                  color: Colors.black)),
          const Spacer(),
          if (isMob) ...[
            // أيقونات القوالب على الهاتف
            IconButton(
              onPressed: _loadTemplate,
              icon: Icon(Icons.file_open, size: 20),
              tooltip: 'تحميل قالب',
              padding: EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              style: IconButton.styleFrom(
                  foregroundColor: AccountingTheme.neonBlue),
            ),
            SizedBox(width: 4),
            IconButton(
              onPressed: _saveAsTemplate,
              icon: Icon(Icons.save_alt, size: 20),
              tooltip: 'حفظ كقالب',
              padding: EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              style: IconButton.styleFrom(
                  foregroundColor: AccountingTheme.neonOrange),
            ),
            SizedBox(width: 4),
            // أيقونات الحفظ على الهاتف
            IconButton(
              onPressed:
                  _isBalanced && !_isSaving ? () => _save(post: false) : null,
              icon: Icon(Icons.save_outlined, size: 20),
              tooltip: 'حفظ مسودة',
              padding: EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              style: IconButton.styleFrom(
                  foregroundColor: AccountingTheme.neonGreen),
            ),
            SizedBox(width: 4),
            IconButton(
              onPressed:
                  _isBalanced && !_isSaving ? () => _save(post: true) : null,
              icon: Icon(Icons.check_circle,
                  size: 20,
                  color: _isBalanced
                      ? AccountingTheme.neonGreen
                      : AccountingTheme.textMuted),
              tooltip: 'حفظ وترحيل',
              padding: EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ] else ...[
            IconButton(
              onPressed: _loadTemplate,
              icon: Icon(Icons.file_open, size: ar.iconM),
              tooltip: 'تحميل قالب',
              style: IconButton.styleFrom(
                  foregroundColor: AccountingTheme.neonBlue),
            ),
            IconButton(
              onPressed: _saveAsTemplate,
              icon: Icon(Icons.save_alt, size: ar.iconM),
              tooltip: 'حفظ كقالب',
              style: IconButton.styleFrom(
                  foregroundColor: AccountingTheme.neonOrange),
            ),
            SizedBox(width: ar.spaceS),
            TextButton.icon(
              onPressed:
                  _isBalanced && !_isSaving ? () => _save(post: false) : null,
              icon: Icon(Icons.save_outlined, size: ar.iconM),
              label: const Text('حفظ مسودة'),
              style: TextButton.styleFrom(
                  foregroundColor: AccountingTheme.neonGreen),
            ),
            SizedBox(width: ar.spaceS),
            ElevatedButton.icon(
              onPressed:
                  _isBalanced && !_isSaving ? () => _save(post: true) : null,
              icon: Icon(Icons.check_circle, size: ar.iconM),
              label: const Text('حفظ وترحيل'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isBalanced
                    ? AccountingTheme.neonGreen
                    : AccountingTheme.textMuted,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    final isMob = context.accR.isMobile;
    return Column(
      children: [
        if (isMob) ...[
          // الصف الأول: التاريخ + التوازن
          _buildDateAndBalanceRow(),
          // الصف الثاني: الوصف
          _buildDescriptionField(),
        ] else ...[
          // شريط التاريخ والتوازن
          _buildBalanceBar(),
          // معلومات القيد (ديسكتوب)
          _buildHeader(),
        ],
        // خطوط القيد
        Expanded(child: _buildLinesTable()),
        // شريط الإجماليات
        _buildTotalsBar(),
      ],
    );
  }

  /// الصف الأول في الهاتف: التاريخ + حالة التوازن + زر إضافة سطر
  Widget _buildDateAndBalanceRow() {
    final balanced = _isBalanced;
    final diff = _difference;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF3D5AFE).withValues(alpha: 0.18), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3D5AFE).withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // التاريخ
          Icon(Icons.calendar_today_rounded,
              color: const Color(0xFF1565C0), size: 15),
          const SizedBox(width: 5),
          Text(
            _formatDate(DateTime.now()),
            style: GoogleFonts.cairo(
                color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          // شارة مسودة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('مسودة',
                style: GoogleFonts.cairo(
                    color: const Color(0xFF1565C0),
                    fontSize: 9,
                    fontWeight: FontWeight.bold)),
          ),
          const Spacer(),
          // حالة التوازن
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: balanced
                    ? [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)]
                    : [const Color(0xFFFFF3E0), const Color(0xFFFFE0B2)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (balanced
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFE65100))
                    .withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  balanced
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                  color: balanced
                      ? AccountingTheme.success
                      : AccountingTheme.danger,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  balanced ? 'متوازن ✓' : 'الفرق: ${_fmt(diff)}',
                  style: GoogleFonts.cairo(
                    color: balanced
                        ? AccountingTheme.success
                        : AccountingTheme.danger,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // زر إضافة سطر
          Material(
            color: AccountingTheme.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _addLine,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded,
                        size: 13, color: AccountingTheme.accent),
                    const SizedBox(width: 3),
                    Text('سطر',
                        style: GoogleFonts.cairo(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AccountingTheme.accent)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// حقل الوصف للهاتف (صف ثاني)
  Widget _buildDescriptionField() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: TextField(
        controller: _descCtrl,
        style: const TextStyle(color: Colors.black, fontSize: 13),
        decoration: InputDecoration(
          labelText: 'وصف القيد *',
          labelStyle: const TextStyle(color: Colors.black, fontSize: 12),
          prefixIcon: const Icon(Icons.description_outlined,
              color: Color(0xFF1565C0), size: 18),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.2))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.2))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFF1565C0), width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final ar = context.accR;
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: ar.spaceM, vertical: ar.spaceXS),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _descCtrl,
              style: TextStyle(color: Colors.black, fontSize: ar.body),
              decoration: _inputDeco('وصف القيد *', Icons.description),
            ),
          ),
          SizedBox(width: ar.spaceM),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _notesCtrl,
              style: TextStyle(color: Colors.black, fontSize: ar.body),
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
    final ar = context.accR;
    final isMob = ar.isMobile;

    if (isMob) {
      // تصميم الهاتف - كما هو
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: balanced
                ? [
                    const Color(0xFFE8F5E9),
                    const Color(0xFFC8E6C9).withValues(alpha: 0.5)
                  ]
                : [
                    const Color(0xFFFFF3E0),
                    const Color(0xFFFFE0B2).withValues(alpha: 0.5)
                  ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                (balanced ? const Color(0xFF2E7D32) : const Color(0xFFE65100))
                    .withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: (balanced
                        ? AccountingTheme.success
                        : AccountingTheme.danger)
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                balanced
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                color:
                    balanced ? AccountingTheme.success : AccountingTheme.danger,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                balanced
                    ? 'القيد متوازن ✓'
                    : 'غير متوازن · الفرق: ${_fmt(diff)}',
                style: GoogleFonts.cairo(
                  color: balanced
                      ? AccountingTheme.success
                      : AccountingTheme.danger,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Material(
              color: AccountingTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: _addLine,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded,
                          size: 14, color: AccountingTheme.accent),
                      const SizedBox(width: 4),
                      Text('سطر',
                          style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AccountingTheme.accent)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // تصميم الديسكتوب - بطاقات بسيطة في صف واحد
    final balanceColor =
        balanced ? AccountingTheme.success : AccountingTheme.danger;
    return Padding(
      padding:
          EdgeInsets.symmetric(horizontal: ar.spaceM, vertical: ar.spaceXS),
      child: Row(
        children: [
          // بطاقة التاريخ (يمين)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_rounded,
                    color: AccountingTheme.accent, size: 16),
                const SizedBox(width: 8),
                Text(
                  _formatDate(DateTime.now()),
                  style: GoogleFonts.cairo(
                      color: Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Spacer(),
          // بطاقة التوازن (وسط)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: balanceColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: balanceColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  balanced
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                  color: balanceColor,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  balanced ? 'متوازن ✓' : 'غير متوازن · الفرق: ${_fmt(diff)}',
                  style: GoogleFonts.cairo(
                    color: balanceColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // زر إضافة سطر (يسار)
          Material(
            color: AccountingTheme.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _addLine,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded,
                        size: 16, color: AccountingTheme.accent),
                    const SizedBox(width: 6),
                    Text('+ إضافة سطر',
                        style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AccountingTheme.accent)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinesTable() {
    final ar = context.accR;
    final isMob = ar.isMobile;
    return Container(
      margin: EdgeInsets.symmetric(
          horizontal: isMob ? 4 : ar.spaceM, vertical: isMob ? 4 : ar.spaceXS),
      decoration: BoxDecoration(
        color: isMob ? Colors.transparent : AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(isMob ? 8 : ar.cardRadius),
        border: isMob ? null : Border.all(color: AccountingTheme.borderColor),
      ),
      child: Column(
        children: [
          // رأس الجدول
          if (!isMob)
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: ar.spaceM, vertical: ar.spaceXS),
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
                  SizedBox(
                      width: 32,
                      child: Text('#',
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: ar.body),
                          textAlign: TextAlign.center)),
                  SizedBox(width: ar.spaceS),
                  Expanded(
                    flex: 4,
                    child: Text('الحساب',
                        style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: ar.body)),
                  ),
                  SizedBox(width: ar.spaceS),
                  SizedBox(
                    width: 150,
                    child: Text('مدين',
                        style: TextStyle(
                            color: AccountingTheme.success,
                            fontWeight: FontWeight.bold,
                            fontSize: ar.body),
                        textAlign: TextAlign.center),
                  ),
                  SizedBox(width: ar.spaceS),
                  SizedBox(
                    width: 150,
                    child: Text('دائن',
                        style: TextStyle(
                            color: AccountingTheme.danger,
                            fontWeight: FontWeight.bold,
                            fontSize: ar.body),
                        textAlign: TextAlign.center),
                  ),
                  SizedBox(width: ar.spaceS),
                  Expanded(
                    flex: 2,
                    child: Text('البيان',
                        style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: ar.body)),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
          // سطور القيد
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(vertical: isMob ? 4 : 4),
              itemCount: _lines.length,
              itemBuilder: (_, i) =>
                  isMob ? _buildMobileLineRow(i) : _buildLineRow(i),
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
          style: TextStyle(
              color: Colors.black, fontSize: context.accR.financialSmall),
          decoration: InputDecoration(
            hintText: 'ابحث بالاسم أو الكود...',
            hintStyle:
                TextStyle(color: Colors.black, fontSize: context.accR.small),
            prefixIcon: Icon(Icons.search,
                color: AccountingTheme.accent.withValues(alpha: 0.6),
                size: context.accR.iconM),
            filled: true,
            fillColor: AccountingTheme.bgCardHover,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: Colors.black.withValues(alpha: 0.2))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: Colors.black.withValues(alpha: 0.15))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AccountingTheme.neonBlue)),
            contentPadding: EdgeInsets.symmetric(
                horizontal: context.accR.spaceM, vertical: context.accR.spaceM),
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
                              style: TextStyle(
                                  color: AccountingTheme.accent,
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          SizedBox(width: context.accR.spaceS),
                          Expanded(
                            child: Text(
                              opt['Name']?.toString() ?? '',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontSize: context.accR.financialSmall),
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

  /// سطر القيد - تصميم بطاقة جميلة للهاتف
  Widget _buildMobileLineRow(int index) {
    final line = _lines[index];

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.black,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // الصف العلوي: رقم + بحث الحساب مباشر + حذف
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: AccountingTheme.bgCardHover.withValues(alpha: 0.6),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                // رقم السطر
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    gradient: AccountingTheme.neonPurpleGradient,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // بحث الحساب المباشر
                Expanded(
                  child: _buildMobileAccountSearch(line),
                ),
                // زر الحذف
                if (_lines.length > 2) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _removeLine(index),
                    child: Container(
                      padding: EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AccountingTheme.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.close_rounded,
                          color: AccountingTheme.danger.withValues(alpha: 0.7),
                          size: 14),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // الصف السفلي: حقول المدين والدائن
          Padding(
            padding: EdgeInsets.fromLTRB(6, 2, 6, 4),
            child: Row(
              children: [
                // حقل المدين
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: TextField(
                      controller: line.debitCtrl,
                      style: GoogleFonts.cairo(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
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
                        hintText: 'مدين',
                        hintStyle: GoogleFonts.cairo(
                            color:
                                AccountingTheme.success.withValues(alpha: 0.5),
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                        filled: true,
                        fillColor: AccountingTheme.debitFill,
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                                color: AccountingTheme.success
                                    .withValues(alpha: 0.3))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                                color: AccountingTheme.success
                                    .withValues(alpha: 0.3))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                                color: AccountingTheme.neonGreen, width: 1.5)),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // حقل الدائن
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: TextField(
                      controller: line.creditCtrl,
                      style: GoogleFonts.cairo(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
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
                        hintText: 'دائن',
                        hintStyle: GoogleFonts.cairo(
                            color:
                                AccountingTheme.danger.withValues(alpha: 0.5),
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                        filled: true,
                        fillColor: AccountingTheme.creditFill,
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                                color: AccountingTheme.danger
                                    .withValues(alpha: 0.3))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                                color: AccountingTheme.danger
                                    .withValues(alpha: 0.3))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                                color: AccountingTheme.danger, width: 1.5)),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// بحث الحساب المباشر للهاتف - بدون نافذة منبثقة
  Widget _buildMobileAccountSearch(_JournalLine line) {
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
      optionsMaxHeight: 200,
      optionsViewOpenDirection: OptionsViewOpenDirection.down,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        if (line.accountName != null && controller.text.isEmpty) {
          controller.text = line.accountName!;
        }
        return SizedBox(
          height: 42,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            style: GoogleFonts.cairo(
                color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم أو الكود...',
              hintStyle: GoogleFonts.cairo(
                  color: Colors.black.withValues(alpha: 0.4), fontSize: 11),
              suffixIcon: line.accountId != null
                  ? Icon(Icons.check_circle_rounded,
                      color: AccountingTheme.success.withValues(alpha: 0.7),
                      size: 14)
                  : Icon(Icons.search_rounded,
                      color: Colors.black.withValues(alpha: 0.3), size: 14),
              suffixIconConstraints:
                  BoxConstraints(minWidth: 24, minHeight: 24),
              filled: true,
              fillColor: Colors.white,
              isDense: false,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.black, width: 1.2)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.black, width: 1.2)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: AccountingTheme.accent, width: 1.5)),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
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
              constraints: BoxConstraints(
                maxHeight: 200,
                maxWidth: MediaQuery.of(context).size.width * 0.85,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: AccountingTheme.borderColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 2),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final opt = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(opt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                              color: AccountingTheme.borderColor
                                  .withValues(alpha: 0.3)),
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
                              style: GoogleFonts.cairo(
                                  color: AccountingTheme.accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              opt['Name']?.toString() ?? '',
                              style: GoogleFonts.cairo(
                                  color: Colors.black, fontSize: 11),
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

  /// حوار اختيار الحساب للهاتف - تصميم محسّن
  void _showAccountPickerDialog(_JournalLine line) {
    final searchCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final query = searchCtrl.text.toLowerCase();
            final filtered = query.isEmpty
                ? _accounts
                : _accounts.where((a) {
                    final code = (a['Code']?.toString() ?? '').toLowerCase();
                    final name = (a['Name']?.toString() ?? '').toLowerCase();
                    return code.contains(query) || name.contains(query);
                  }).toList();

            return Directionality(
              textDirection: TextDirection.rtl,
              child: Dialog(
                insetPadding: EdgeInsets.all(16),
                backgroundColor: AccountingTheme.bgPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: SizedBox(
                  width: double.infinity,
                  height: MediaQuery.of(ctx).size.height * 0.7,
                  child: Column(
                    children: [
                      // عنوان الحوار
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: AccountingTheme.neonPurpleGradient,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.account_balance_rounded,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Text('اختر الحساب',
                                style: GoogleFonts.cairo(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => Navigator.pop(ctx),
                              child: Container(
                                padding: EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.close_rounded,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // شريط البحث
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: TextField(
                          controller: searchCtrl,
                          autofocus: true,
                          style: TextStyle(color: Colors.black, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'ابحث بالاسم أو الكود...',
                            hintStyle:
                                TextStyle(color: Colors.black54, fontSize: 12),
                            prefixIcon: Icon(Icons.search_rounded,
                                color: AccountingTheme.accent, size: 20),
                            filled: true,
                            fillColor: AccountingTheme.bgCard,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: AccountingTheme.borderColor)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: AccountingTheme.borderColor)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: AccountingTheme.accent)),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                      // عدد النتائج
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Text('${filtered.length} حساب',
                                style: TextStyle(
                                    color: Colors.black54, fontSize: 10)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      // قائمة الحسابات
                      Expanded(
                        child: ListView.separated(
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: AccountingTheme.borderColor
                                  .withValues(alpha: 0.3)),
                          itemBuilder: (_, i) {
                            final a = filtered[i];
                            final isSelected =
                                line.accountId == a['Id']?.toString();
                            return Material(
                              color: isSelected
                                  ? AccountingTheme.accent
                                      .withValues(alpha: 0.1)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    line.accountId = a['Id']?.toString();
                                    line.accountName =
                                        '${a['Code']} - ${a['Name']}';
                                  });
                                  Navigator.pop(ctx);
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  child: Row(
                                    children: [
                                      // كود الحساب
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AccountingTheme.accent
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          a['Code']?.toString() ?? '',
                                          style: GoogleFonts.cairo(
                                              color: AccountingTheme.accent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      // اسم الحساب
                                      Expanded(
                                        child: Text(
                                          a['Name']?.toString() ?? '',
                                          style: GoogleFonts.cairo(
                                              color: Colors.black,
                                              fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(Icons.check_circle_rounded,
                                            color: AccountingTheme.accent,
                                            size: 18),
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
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLineRow(int index) {
    final line = _lines[index];
    final isEven = index % 2 == 0;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.spaceS, vertical: context.accR.spaceXS),
      decoration: BoxDecoration(
        color: isEven
            ? Colors.transparent
            : AccountingTheme.textMuted.withValues(alpha: 0.05),
        border: Border.all(color: Colors.black, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // رقم السطر
          SizedBox(
            width: 32,
            child: Container(
              padding: EdgeInsets.all(context.accR.spaceXS),
              decoration: BoxDecoration(
                color: AccountingTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                    color: AccountingTheme.accent,
                    fontSize: context.accR.body,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          SizedBox(width: context.accR.spaceS),
          // بحث الحساب
          Expanded(
            flex: 4,
            child: _buildAccountSearch(line),
          ),
          SizedBox(width: context.accR.spaceS),
          // مبلغ المدين
          SizedBox(
            width: 150,
            child: TextField(
              controller: line.debitCtrl,
              style: TextStyle(
                  color: Colors.black,
                  fontSize: context.accR.body,
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
                hintStyle: TextStyle(color: Colors.black),
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
                contentPadding: EdgeInsets.symmetric(
                    horizontal: context.accR.spaceS,
                    vertical: context.accR.spaceXS),
              ),
            ),
          ),
          SizedBox(width: context.accR.spaceS),
          // مبلغ الدائن
          SizedBox(
            width: 150,
            child: TextField(
              controller: line.creditCtrl,
              style: TextStyle(
                  color: Colors.black,
                  fontSize: context.accR.body,
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
                hintStyle: TextStyle(color: Colors.black),
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
                contentPadding: EdgeInsets.symmetric(
                    horizontal: context.accR.spaceS,
                    vertical: context.accR.spaceXS),
              ),
            ),
          ),
          SizedBox(width: context.accR.spaceS),
          // البيان
          Expanded(
            flex: 2,
            child: TextField(
              controller: line.descCtrl,
              style: TextStyle(
                  color: Colors.black, fontSize: context.accR.financialSmall),
              decoration: InputDecoration(
                hintText: 'بيان السطر',
                hintStyle: TextStyle(
                    color: Colors.black, fontSize: context.accR.small),
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
                contentPadding: EdgeInsets.symmetric(
                    horizontal: context.accR.spaceS,
                    vertical: context.accR.spaceXS),
              ),
            ),
          ),
          // زر حذف السطر
          SizedBox(
            width: 44,
            child: _lines.length > 2
                ? IconButton(
                    icon: Icon(Icons.remove_circle,
                        color: AccountingTheme.danger,
                        size: context.accR.iconM),
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
    final ar = context.accR;
    final isMob = ar.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 10 : 10, vertical: isMob ? 10 : 6),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(
            top: BorderSide(
                color: AccountingTheme.accent.withValues(alpha: 0.3),
                width: 1.5)),
        boxShadow: isMob
            ? [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: Offset(0, -2))
              ]
            : null,
      ),
      child: isMob
          ? Row(
              children: [
                // إجمالي المدين
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AccountingTheme.debitFill,
                          AccountingTheme.success.withValues(alpha: 0.08)
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              AccountingTheme.success.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.arrow_upward_rounded,
                                color: AccountingTheme.neonGreen, size: 10),
                            const SizedBox(width: 2),
                            Text('المدين',
                                style: GoogleFonts.cairo(
                                    color: AccountingTheme.neonGreen,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(_fmt(_totalDebit),
                            style: GoogleFonts.cairo(
                                color: AccountingTheme.neonGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // إجمالي الدائن
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AccountingTheme.creditFill,
                          AccountingTheme.danger.withValues(alpha: 0.08)
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AccountingTheme.danger.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.arrow_downward_rounded,
                                color: AccountingTheme.danger, size: 10),
                            const SizedBox(width: 2),
                            Text('الدائن',
                                style: GoogleFonts.cairo(
                                    color: AccountingTheme.danger,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(_fmt(_totalCredit),
                            style: GoogleFonts.cairo(
                                color: AccountingTheme.danger,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // الفرق
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AccountingTheme.warning.withValues(alpha: 0.15),
                          AccountingTheme.warning.withValues(alpha: 0.05)
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              AccountingTheme.warning.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.compare_arrows_rounded,
                                color: AccountingTheme.warning, size: 10),
                            const SizedBox(width: 2),
                            Text('الفرق',
                                style: GoogleFonts.cairo(
                                    color: AccountingTheme.warning,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(_fmt(_difference),
                            style: GoogleFonts.cairo(
                                color: AccountingTheme.warning,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                // عدد الأسطر (يمين)
                Text('عدد الأسطر: ',
                    style: TextStyle(color: Colors.black, fontSize: ar.body)),
                Text('${_lines.length}',
                    style: TextStyle(
                        color: AccountingTheme.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: ar.headingSmall)),
                const Spacer(),
                // إجمالي المدين (وسط)
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AccountingTheme.debitFill,
                      borderRadius: BorderRadius.circular(ar.cardRadius),
                      border: Border.all(
                          color:
                              AccountingTheme.success.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('المدين: ',
                            style: TextStyle(
                                color: Colors.black, fontSize: ar.body)),
                        Text(_fmt(_totalDebit),
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: ar.headingSmall)),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: ar.spaceM),
                // إجمالي الدائن
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AccountingTheme.creditFill,
                      borderRadius: BorderRadius.circular(ar.cardRadius),
                      border: Border.all(
                          color: AccountingTheme.danger.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('الدائن: ',
                            style: TextStyle(
                                color: Colors.black, fontSize: ar.body)),
                        Text(_fmt(_totalCredit),
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: ar.headingSmall)),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: ar.spaceM),
                // الفرق
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isBalanced
                          ? AccountingTheme.success.withValues(alpha: 0.1)
                          : AccountingTheme.warning.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(ar.cardRadius),
                      border: Border.all(
                          color: _isBalanced
                              ? AccountingTheme.success.withValues(alpha: 0.4)
                              : AccountingTheme.warning.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('الفرق: ',
                            style: TextStyle(
                                color: Colors.black, fontSize: ar.body)),
                        Text(_fmt(_difference),
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: ar.headingSmall)),
                      ],
                    ),
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

  // ═══════════════════════════════════════════════════════════════
  // حفظ / تحميل القوالب
  // ═══════════════════════════════════════════════════════════════

  Future<void> _saveAsTemplate() async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AccountingTheme.radiusLarge)),
          title: Text('حفظ كقالب',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.textPrimary)),
          content: TextField(
            controller: nameController,
            style: GoogleFonts.cairo(color: AccountingTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'اسم القالب',
              labelStyle: GoogleFonts.cairo(color: AccountingTheme.textSecondary),
              border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AccountingTheme.radiusMedium)),
              enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AccountingTheme.radiusMedium),
                  borderSide:
                      const BorderSide(color: AccountingTheme.borderColor)),
              focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AccountingTheme.radiusMedium),
                  borderSide:
                      const BorderSide(color: AccountingTheme.neonBlue, width: 2)),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: GoogleFonts.cairo(
                        color: AccountingTheme.textMuted))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
              style: AccountingTheme.primaryButton,
              child: Text('حفظ', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (result == null || result.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final templates =
        json.decode(prefs.getString('journal_templates') ?? '[]') as List;

    // بناء القالب من حالة النموذج الحالية
    templates.add({
      'name': result,
      'description': _descCtrl.text,
      'notes': _notesCtrl.text,
      'lines': _lines
          .where((l) => l.accountId != null)
          .map((l) => {
                'accountId': l.accountId,
                'accountName': l.accountName,
                'debit': l.debit,
                'credit': l.credit,
                'description': l.descCtrl.text,
              })
          .toList(),
      'createdAt': DateTime.now().toIso8601String(),
    });
    await prefs.setString('journal_templates', json.encode(templates));
    if (mounted) {
      _snack('تم حفظ القالب: $result', AccountingTheme.success);
    }
  }

  Future<void> _loadTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    final templates =
        json.decode(prefs.getString('journal_templates') ?? '[]') as List;
    if (templates.isEmpty) {
      if (mounted) {
        _snack('لا توجد قوالب محفوظة', AccountingTheme.warning);
      }
      return;
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AccountingTheme.radiusLarge)),
          title: Text('تحميل قالب',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.textPrimary)),
          content: SizedBox(
            width: 400,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: templates.length,
              itemBuilder: (_, i) {
                final t = templates[i] as Map<String, dynamic>;
                final lineCount =
                    (t['lines'] as List?)?.length ?? 0;
                return ListTile(
                  title: Text(t['name'] ?? '',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w600,
                          color: AccountingTheme.textPrimary)),
                  subtitle: Text(
                    '${t['description'] ?? ''} ($lineCount سطر)',
                    style: GoogleFonts.cairo(
                        fontSize: 12, color: AccountingTheme.textMuted),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    tooltip: 'حذف القالب',
                    onPressed: () async {
                      templates.removeAt(i);
                      await prefs.setString(
                          'journal_templates', json.encode(templates));
                      Navigator.pop(ctx);
                      _loadTemplate(); // إعادة فتح القائمة
                    },
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _applyTemplate(t);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: GoogleFonts.cairo(
                        color: AccountingTheme.textMuted))),
          ],
        ),
      ),
    );
  }

  void _applyTemplate(Map<String, dynamic> template) {
    // تعيين الوصف والملاحظات
    _descCtrl.text = template['description'] ?? '';
    _notesCtrl.text = template['notes'] ?? '';

    // مسح الأسطر الحالية
    for (final l in _lines) {
      l.dispose();
    }
    _lines.clear();

    // إضافة أسطر القالب
    final templateLines = template['lines'] as List? ?? [];
    for (final tl in templateLines) {
      final line = _JournalLine();
      line.accountId = tl['accountId']?.toString();
      line.accountName = tl['accountName']?.toString();
      line.debit = (tl['debit'] is num)
          ? (tl['debit'] as num).toDouble()
          : double.tryParse(tl['debit']?.toString() ?? '') ?? 0;
      line.credit = (tl['credit'] is num)
          ? (tl['credit'] as num).toDouble()
          : double.tryParse(tl['credit']?.toString() ?? '') ?? 0;
      line.descCtrl.text = tl['description']?.toString() ?? '';
      if (line.debit > 0) line.debitCtrl.text = line.debit.toStringAsFixed(0);
      if (line.credit > 0) line.creditCtrl.text = line.credit.toStringAsFixed(0);
      _lines.add(line);
    }

    // إضافة أسطر فارغة إذا كان العدد أقل من 3
    while (_lines.length < 3) {
      _lines.add(_JournalLine());
    }

    setState(() {});
    _snack('تم تحميل القالب: ${template['name']}', AccountingTheme.info);
  }

  // ═══════════════════════════════════════════════════════════════
  // حفظ القيد
  // ═══════════════════════════════════════════════════════════════

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
      _snack('خطأ', AccountingTheme.danger);
    }

    if (mounted) setState(() => _isSaving = false);
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          TextStyle(color: Colors.black, fontSize: context.accR.financialSmall),
      prefixIcon:
          Icon(icon, color: AccountingTheme.accent, size: context.accR.iconM),
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
