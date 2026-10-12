import 'dart:async';

import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_refresh_bus.dart';
import '../widgets/sas_state_views.dart';

/// الحقول المنطقية التي يمكن استيرادها لكل مشترك (معرّف ثابت + تسمية عربية).
///
/// ترتيب هذه القائمة = ترتيب أعمدة النموذج المتوقّع + ترتيب خانات الجدول.
enum _Col {
  username,
  password,
  firstname,
  lastname,
  phone,
  email,
  city,
  address,
  nationalId,
  staticIp,
  notes,
  profile,
}

extension _ColX on _Col {
  String get key {
    switch (this) {
      case _Col.username:
        return 'username';
      case _Col.password:
        return 'password';
      case _Col.firstname:
        return 'firstname';
      case _Col.lastname:
        return 'lastname';
      case _Col.phone:
        return 'phone';
      case _Col.email:
        return 'email';
      case _Col.city:
        return 'city';
      case _Col.address:
        return 'address';
      case _Col.nationalId:
        return 'national_id';
      case _Col.staticIp:
        return 'static_ip';
      case _Col.notes:
        return 'notes';
      case _Col.profile:
        return 'profile';
    }
  }

  String get labelAr {
    switch (this) {
      case _Col.username:
        return 'اسم المستخدم';
      case _Col.password:
        return 'كلمة المرور';
      case _Col.firstname:
        return 'الاسم الأول';
      case _Col.lastname:
        return 'الاسم الأخير';
      case _Col.phone:
        return 'الهاتف';
      case _Col.email:
        return 'البريد';
      case _Col.city:
        return 'المدينة';
      case _Col.address:
        return 'العنوان';
      case _Col.nationalId:
        return 'الهوية الوطنية';
      case _Col.staticIp:
        return 'IP ثابت';
      case _Col.notes:
        return 'ملاحظات';
      case _Col.profile:
        return 'الباقة';
    }
  }

  /// مرادفات رؤوس الأعمدة (عربي/إنجليزي) للمطابقة التلقائية.
  List<String> get aliases {
    switch (this) {
      case _Col.username:
        return ['username', 'user', 'اسم المستخدم', 'المستخدم', 'الحساب'];
      case _Col.password:
        return ['password', 'pass', 'pwd', 'كلمة المرور', 'كلمةالمرور', 'الرمز'];
      case _Col.firstname:
        return ['firstname', 'first name', 'first', 'الاسم الأول', 'الاسم'];
      case _Col.lastname:
        return ['lastname', 'last name', 'last', 'الاسم الأخير', 'اللقب'];
      case _Col.phone:
        return ['phone', 'mobile', 'tel', 'الهاتف', 'الجوال', 'رقم الهاتف'];
      case _Col.email:
        return ['email', 'mail', 'البريد', 'الايميل', 'البريد الإلكتروني'];
      case _Col.city:
        return ['city', 'المدينة', 'المنطقة'];
      case _Col.address:
        return ['address', 'العنوان', 'السكن'];
      case _Col.nationalId:
        return ['national_id', 'nationalid', 'national id', 'id', 'الهوية', 'الهوية الوطنية', 'البطاقة'];
      case _Col.staticIp:
        return ['static_ip', 'staticip', 'static ip', 'ip', 'آيبي', 'ايبي'];
      case _Col.notes:
        return ['notes', 'note', 'ملاحظات', 'ملاحظة'];
      case _Col.profile:
        return ['profile', 'package', 'plan', 'profile_id', 'الباقة', 'الخطة', 'الاشتراك'];
    }
  }
}

/// حالة صفّ أثناء/بعد الإنشاء.
enum _RowStatus { pending, running, success, failed }

/// صفّ مشترك قابل للتعديل في الجدول قبل الإنشاء.
class _Entry {
  final Map<_Col, TextEditingController> ctrls = {
    for (final c in _Col.values) c: TextEditingController(),
  };

  /// معرّف بروفايل خاص بهذا الصفّ (يتجاوز الباقة الافتراضية إن حُدّد).
  int? profileId;

  _RowStatus status = _RowStatus.pending;
  String? error;

  _Entry();

  factory _Entry.fromValues(Map<_Col, String> values) {
    final e = _Entry();
    values.forEach((col, v) => e.ctrls[col]!.text = v);
    return e;
  }

  String val(_Col c) => (ctrls[c]!.text).trim();

  void dispose() {
    for (final c in ctrls.values) {
      c.dispose();
    }
  }
}

/// شاشة «رفع مجموعة مشتركين» — تنشئ عدّة مشتركين في SAS4 عبر تكرار نداء الإنشاء
/// الموجود (`createUser`) صفّاً صفّاً (SAS4 لا يدعم الإنشاء الجماعي أصلاً).
///
/// مصدران: استيراد ملف Excel/CSV (مع مطابقة أعمدة) أو إدخال يدوي في جدول. في
/// الوضعين تُجمَّع الصفوف في جدول واحد قابل للتعديل/الحذف/الإضافة قبل الإنشاء.
///
/// العزل: كل النداءات عبر الحساب المحدَّد [account] فقط.
/// أمن: كلمات المرور لا تُطبَع في أي سجل/شاشة سجل (حقل مُقنَّع في الجدول).
class SasBulkImportPage extends StatefulWidget {
  final SasAccount account;

  const SasBulkImportPage({super.key, required this.account});

  @override
  State<SasBulkImportPage> createState() => _SasBulkImportPageState();
}

class _SasBulkImportPageState extends State<SasBulkImportPage> {
  final _api = SasAgentApiService.instance;

  // الباقات المجلوبة (id + name) لمنتقي الباقة والمطابقة بالاسم.
  List<Map<String, dynamic>> _profiles = const [];
  int? _defaultProfileId;

  bool _loadingProfiles = true;
  String? _loadError;

  final List<_Entry> _rows = [];

  bool _creating = false;
  bool _cancelRequested = false;
  int _doneCount = 0;
  int _successCount = 0;
  int _failCount = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _rows.add(_Entry()); // ابدأ بصفّ فارغ واحد للإدخال اليدوي.
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  // ───────────────────────────── تحميل الباقات ─────────────────────────────

  Future<void> _loadProfiles() async {
    setState(() {
      _loadingProfiles = true;
      _loadError = null;
    });
    try {
      final profiles = await _api.getPackages(widget.account.id);
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _loadingProfiles = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString().replaceFirst('Exception: ', '').trim();
        _loadingProfiles = false;
      });
    }
  }

  static int? _asInt(dynamic v) =>
      v is int ? v : (v == null ? null : int.tryParse(v.toString()));

  String _profileName(int id) {
    final p = _profiles.firstWhere(
      (e) => _asInt(e['id']) == id,
      orElse: () => const {},
    );
    return (p['name'] ?? p['id'] ?? id).toString();
  }

  /// يطابق نصّ باقة (رقم أو اسم) إلى `profile_id`. يعيد null إن لم يُطابَق.
  int? _matchProfile(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final asId = int.tryParse(t);
    if (asId != null && _profiles.any((p) => _asInt(p['id']) == asId)) {
      return asId;
    }
    final lower = t.toLowerCase();
    for (final p in _profiles) {
      final name = (p['name'] ?? '').toString().trim().toLowerCase();
      if (name.isNotEmpty && name == lower) return _asInt(p['id']);
    }
    // مطابقة جزئية احتياطية.
    for (final p in _profiles) {
      final name = (p['name'] ?? '').toString().trim().toLowerCase();
      if (name.isNotEmpty && (name.contains(lower) || lower.contains(name))) {
        return _asInt(p['id']);
      }
    }
    return null;
  }

  /// الباقة الفعّالة لصفّ: الخاصّة به إن حُدّدت، وإلا الافتراضية.
  int? _effectiveProfile(_Entry e) => e.profileId ?? _defaultProfileId;

  // ───────────────────────────── استيراد ملف ─────────────────────────────

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final file = res.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        _snack('تعذّر قراءة الملف (لا توجد بيانات)', error: true);
        return;
      }
      final name = (file.name).toLowerCase();
      final List<List<String>> table;
      if (name.endsWith('.csv')) {
        table = _parseCsv(String.fromCharCodes(bytes));
      } else {
        table = _parseXlsx(bytes);
      }
      if (table.isEmpty) {
        _snack('الملف فارغ', error: true);
        return;
      }
      if (!mounted) return;
      await _openColumnMapping(table);
    } catch (e) {
      _snack('فشل الاستيراد: ${e.toString().replaceFirst('Exception: ', '').trim()}',
          error: true);
    }
  }

  List<List<String>> _parseXlsx(List<int> bytes) {
    final excel = xls.Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return const [];
    final sheet = excel.tables.values.first;
    final out = <List<String>>[];
    for (final row in sheet.rows) {
      final cells = row.map((d) => _cellText(d?.value)).toList();
      // تجاهل الصفوف الفارغة تماماً.
      if (cells.every((c) => c.trim().isEmpty)) continue;
      out.add(cells);
    }
    return out;
  }

  static String _cellText(xls.CellValue? v) {
    if (v == null) return '';
    if (v is xls.TextCellValue) return v.value.text ?? '';
    if (v is xls.IntCellValue) return v.value.toString();
    if (v is xls.DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    if (v is xls.BoolCellValue) return v.value ? '1' : '0';
    if (v is xls.DateCellValue) return v.asDateTimeLocal().toIso8601String();
    return v.toString();
  }

  /// محلّل CSV بسيط يدعم الفواصل والاقتباس المزدوج والأسطر داخل الخلايا.
  List<List<String>> _parseCsv(String content) {
    final text = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = <List<String>>[];
    var field = StringBuffer();
    var row = <String>[];
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
        } else if (ch == ',') {
          row.add(field.toString());
          field = StringBuffer();
        } else if (ch == '\n') {
          row.add(field.toString());
          field = StringBuffer();
          if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
          row = <String>[];
        } else {
          field.write(ch);
        }
      }
    }
    // آخر خلية/صفّ.
    row.add(field.toString());
    if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
    return rows;
  }

  /// يفتح حوار مطابقة الأعمدة؛ عند التأكيد يضيف الصفوف إلى الجدول الموحّد.
  Future<void> _openColumnMapping(List<List<String>> table) async {
    final headers = table.first.map((h) => h.trim()).toList();
    // محاولة مطابقة تلقائية: لكل حقل منطقي نبحث عن رأس يطابق أحد مرادفاته.
    final mapping = <_Col, int?>{};
    for (final col in _Col.values) {
      int? idx;
      for (var i = 0; i < headers.length; i++) {
        final h = headers[i].toLowerCase();
        if (col.aliases.any((a) => a.toLowerCase() == h)) {
          idx = i;
          break;
        }
      }
      mapping[col] = idx;
    }
    final confirmed = await showDialog<Map<_Col, int?>>(
      context: context,
      builder: (_) => _ColumnMappingDialog(
        headers: headers,
        initial: mapping,
        sampleRowCount: table.length - 1,
      ),
    );
    if (confirmed == null || !mounted) return;

    // بناء الصفوف من الصفوف بعد صفّ الرأس وفق المطابقة.
    final added = <_Entry>[];
    for (var r = 1; r < table.length; r++) {
      final rowCells = table[r];
      final values = <_Col, String>{};
      confirmed.forEach((col, idx) {
        if (idx != null && idx >= 0 && idx < rowCells.length) {
          values[col] = rowCells[idx].trim();
        }
      });
      // تجاهل الصفوف الفارغة كلياً.
      if (values.values.every((v) => v.isEmpty)) continue;
      final entry = _Entry.fromValues(values);
      // مطابقة الباقة بالاسم/المعرّف إن وُجد عمود باقة.
      final profRaw = values[_Col.profile];
      if (profRaw != null && profRaw.isNotEmpty) {
        entry.profileId = _matchProfile(profRaw);
      }
      added.add(entry);
    }
    if (added.isEmpty) {
      _snack('لا صفوف بيانات صالحة في الملف', error: true);
      return;
    }
    setState(() {
      // إن كان الجدول يحوي فقط الصفّ الفارغ الابتدائي، استبدله.
      if (_rows.length == 1 && _rows.first.val(_Col.username).isEmpty) {
        _rows.first.dispose();
        _rows.clear();
      }
      _rows.addAll(added);
      _resetRunState();
    });
    _snack('أُضيف ${added.length} صفّ من الملف');
  }

  // ───────────────────────────── إدارة الجدول ─────────────────────────────

  void _addEmptyRow() {
    setState(() {
      _rows.add(_Entry());
      _resetRunState();
    });
  }

  void _removeRow(int i) {
    setState(() {
      _rows[i].dispose();
      _rows.removeAt(i);
      if (_rows.isEmpty) _rows.add(_Entry());
      _resetRunState();
    });
  }

  void _clearAll() {
    setState(() {
      for (final r in _rows) {
        r.dispose();
      }
      _rows.clear();
      _rows.add(_Entry());
      _resetRunState();
    });
  }

  void _resetRunState() {
    _finished = false;
    _doneCount = 0;
    _successCount = 0;
    _failCount = 0;
  }

  /// صحّة صفّ: username + password + باقة فعّالة.
  bool _rowValid(_Entry e) =>
      e.val(_Col.username).isNotEmpty &&
      e.val(_Col.password).isNotEmpty &&
      _effectiveProfile(e) != null;

  int get _validCount => _rows.where(_rowValid).length;

  // ───────────────────────────── التنفيذ ─────────────────────────────

  Future<void> _createAll({bool failedOnly = false}) async {
    final targets = <_Entry>[];
    for (final e in _rows) {
      if (!_rowValid(e)) continue;
      if (failedOnly && e.status != _RowStatus.failed) continue;
      if (!failedOnly && e.status == _RowStatus.success) continue;
      targets.add(e);
    }
    if (targets.isEmpty) {
      _snack(failedOnly ? 'لا صفوف فاشلة لإعادتها' : 'لا صفوف صالحة للإنشاء',
          error: true);
      return;
    }

    setState(() {
      _creating = true;
      _cancelRequested = false;
      _finished = false;
      if (!failedOnly) {
        _doneCount = 0;
        _successCount = 0;
        _failCount = 0;
      }
      for (final e in targets) {
        e.status = _RowStatus.pending;
        e.error = null;
      }
    });

    for (final e in targets) {
      if (_cancelRequested) break;
      setState(() => e.status = _RowStatus.running);
      try {
        await _api.createUser(widget.account.id, _payloadFor(e));
        if (!mounted) return;
        setState(() {
          e.status = _RowStatus.success;
          e.error = null;
          _successCount++;
          _doneCount++;
        });
      } catch (err) {
        if (!mounted) return;
        setState(() {
          e.status = _RowStatus.failed;
          e.error = err.toString().replaceFirst('Exception: ', '').trim();
          _failCount++;
          _doneCount++;
        });
      }
      // فاصل بسيط لتفادي إغراق SAS4.
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    if (!mounted) return;
    setState(() {
      _creating = false;
      _finished = true;
    });
    // أبلغ بقية التبويبات لتحديث القوائم بعد الإنشاء.
    if (_successCount > 0) {
      SasRefreshBus.instance.notify(
        accountId: widget.account.id,
        reason: 'bulk-import',
      );
    }
  }

  /// حمولة إنشاء صفّ — بنية مطابقة لـ `_saveCreate` في نموذج المشترك.
  Map<String, dynamic> _payloadFor(_Entry e) {
    final staticIp = e.val(_Col.staticIp);
    return <String, dynamic>{
      'username': e.val(_Col.username),
      'password': e.ctrls[_Col.password]!.text,
      'confirm_password': e.ctrls[_Col.password]!.text,
      'enabled': 1,
      'profile_id': _effectiveProfile(e),
      'mac_auth': 0,
      'auto_renew': 0,
      'firstname': e.val(_Col.firstname),
      'lastname': e.val(_Col.lastname),
      'email': e.val(_Col.email),
      'phone': e.val(_Col.phone),
      'city': e.val(_Col.city),
      'address': e.val(_Col.address),
      'national_id': e.val(_Col.nationalId),
      'contract_id': '',
      'static_ip': staticIp.isEmpty ? null : staticIp,
      'notes': e.val(_Col.notes),
      'simultaneous_sessions': 1,
      'user_type': '0',
    };
  }

  void _cancel() => setState(() => _cancelRequested = true);

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ───────────────────────────── البناء ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: AppTheme.primaryColor,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.blueGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Text(
            'رفع مجموعة مشتركين',
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.w800, color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: _loadingProfiles
            ? const SasLoadingView(message: 'جاري تحميل الباقات…')
            : _loadError != null
                ? SasErrorView(message: _loadError!, onRetry: _loadProfiles)
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    return SasContentWrap(
      maxWidth: 1500,
      child: Column(
        children: [
          _toolbar(),
          if (_creating || _finished) _progressBar(),
          Expanded(child: _table()),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Container(
      margin: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 6.h),
      padding: EdgeInsets.all(12.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SasSectionHeader(
            title: 'مصدر البيانات',
            icon: Icons.upload_file_rounded,
            gradient: AppTheme.blueGradient,
          ),
          SizedBox(height: 12.h),
          Wrap(
            spacing: 10.w,
            runSpacing: 10.h,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _creating ? null : _pickFile,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
                ),
                icon: const Icon(Icons.file_open_rounded, size: 19),
                label: Text('استيراد ملف (Excel/CSV)',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
              ),
              OutlinedButton.icon(
                onPressed: _creating ? null : _addEmptyRow,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: BorderSide(
                      color: AppTheme.primaryColor.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
                ),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: Text('إضافة صفّ يدوي',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
              ),
              TextButton.icon(
                onPressed: _creating ? null : _showTemplate,
                icon: Icon(Icons.description_outlined,
                    size: 18, color: AppTheme.infoColor),
                label: Text('نموذج الأعمدة',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.infoColor)),
              ),
              TextButton.icon(
                onPressed: _creating ? null : _clearAll,
                icon: Icon(Icons.delete_sweep_rounded,
                    size: 18, color: AppTheme.errorColor),
                label: Text('مسح الكل',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.errorColor)),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(flex: 2, child: _defaultProfileDropdown()),
              SizedBox(width: 12.w),
              Expanded(child: _createButton()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _defaultProfileDropdown() {
    return DropdownButtonFormField<int>(
      initialValue: _defaultProfileId,
      isExpanded: true,
      style: GoogleFonts.cairo(
          fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E)),
      decoration: InputDecoration(
        labelText: 'الباقة الافتراضية (لكل الصفوف) *',
        labelStyle: GoogleFonts.cairo(color: Colors.grey[600]),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.16)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.16)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
          borderSide:
              const BorderSide(color: AppTheme.primaryColor, width: 1.6),
        ),
      ),
      items: [
        for (final p in _profiles)
          DropdownMenuItem(
            value: _asInt(p['id']),
            child: Text('${p['name'] ?? p['id']}',
                overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _creating
          ? null
          : (v) => setState(() {
                _defaultProfileId = v;
                _resetRunState();
              }),
    );
  }

  Widget _createButton() {
    if (_creating) {
      return SizedBox(
        height: 48.h,
        child: OutlinedButton.icon(
          onPressed: _cancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.errorColor,
            side: BorderSide(color: AppTheme.errorColor.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
          ),
          icon: const Icon(Icons.stop_rounded, size: 20),
          label: Text('إيقاف',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
        ),
      );
    }
    return SizedBox(
      height: 48.h,
      child: FilledButton.icon(
        onPressed: _validCount == 0 ? null : () => _createAll(),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.successColor,
          disabledBackgroundColor: Colors.grey.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
        ),
        icon: const Icon(Icons.cloud_upload_rounded, size: 20),
        label: Text('إنشاء الكل ($_validCount)',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _progressBar() {
    final total = _creating || _finished ? (_doneCount + _pendingTargets()) : 0;
    final pct = total == 0 ? 0.0 : _doneCount / total;
    return Container(
      margin: EdgeInsets.fromLTRB(14.w, 0, 14.w, 6.h),
      padding: EdgeInsets.all(12.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _finished ? 'اكتمل الإنشاء' : 'جارٍ الإنشاء…',
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1A2E)),
              ),
              const Spacer(),
              _countPill('نجح', _successCount, AppTheme.successColor),
              SizedBox(width: 6.w),
              _countPill('فشل', _failCount, AppTheme.errorColor),
              SizedBox(width: 6.w),
              _countPill('تمّ', _doneCount, AppTheme.infoColor),
            ],
          ),
          SizedBox(height: 8.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(8.r),
            child: LinearProgressIndicator(
              value: _creating ? (pct == 0 ? null : pct) : 1.0,
              minHeight: 8,
              backgroundColor: Colors.grey.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(
                  _failCount > 0 && _finished
                      ? AppTheme.warningColor
                      : AppTheme.successColor),
            ),
          ),
          if (_finished && _failCount > 0) ...[
            SizedBox(height: 10.h),
            SizedBox(
              height: 40.h,
              child: OutlinedButton.icon(
                onPressed: () => _createAll(failedOnly: true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.warningColor,
                  side: BorderSide(
                      color: AppTheme.warningColor.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
                ),
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: Text('إعادة محاولة الفاشلين ($_failCount)',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _pendingTargets() => _rows
      .where((e) =>
          (e.status == _RowStatus.pending || e.status == _RowStatus.running))
      .length;

  Widget _countPill(String label, int value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text('$label: $value',
          style: GoogleFonts.cairo(
              fontSize: 11.sp, fontWeight: FontWeight.w800, color: color)),
    );
  }

  Widget _table() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 20.h),
      child: Column(
        children: [
          _tableHeader(),
          SizedBox(height: 6.h),
          for (var i = 0; i < _rows.length; i++) ...[
            _rowCard(i, _rows[i]),
            SizedBox(height: 8.h),
          ],
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w),
      child: Row(
        children: [
          Text('#',
              style: GoogleFonts.cairo(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[600])),
          const Spacer(),
          Text('عدد الصفوف: ${_rows.length} · صالح: $_validCount',
              style: GoogleFonts.cairo(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _rowCard(int index, _Entry e) {
    final valid = _rowValid(e);
    final (statusColor, statusIcon, statusText) = _statusMeta(e, valid);
    return Container(
      padding: EdgeInsets.all(10.w),
      decoration: SasUi.card(
        borderColor: valid || e.status != _RowStatus.pending
            ? statusColor.withValues(alpha: 0.35)
            : AppTheme.errorColor.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: statusColor.withValues(alpha: 0.12),
                child: Icon(statusIcon, size: 16, color: statusColor),
              ),
              SizedBox(width: 8.w),
              Text('صفّ ${index + 1}',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A2E))),
              SizedBox(width: 8.w),
              SasStatusBadge(label: statusText, color: statusColor),
              const Spacer(),
              IconButton(
                tooltip: 'حذف الصفّ',
                onPressed: _creating ? null : () => _removeRow(index),
                icon: Icon(Icons.close_rounded,
                    size: 18, color: Colors.grey[500]),
              ),
            ],
          ),
          if (e.status == _RowStatus.failed && e.error != null)
            Padding(
              padding: EdgeInsets.only(bottom: 6.h, right: 4.w),
              child: Text(
                'سبب الفشل: ${e.error}',
                style: GoogleFonts.cairo(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.errorColor),
              ),
            ),
          SizedBox(height: 4.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              _cell(e, _Col.username, width: 160, required: true),
              _cell(e, _Col.password, width: 150, required: true, obscure: true),
              _rowProfileDropdown(e),
              _cell(e, _Col.firstname, width: 130),
              _cell(e, _Col.lastname, width: 130),
              _cell(e, _Col.phone, width: 140, ltr: true),
              _cell(e, _Col.email, width: 180, ltr: true),
              _cell(e, _Col.city, width: 120),
              _cell(e, _Col.address, width: 180),
              _cell(e, _Col.nationalId, width: 150),
              _cell(e, _Col.staticIp, width: 130, ltr: true),
              _cell(e, _Col.notes, width: 200),
            ],
          ),
        ],
      ),
    );
  }

  (Color, IconData, String) _statusMeta(_Entry e, bool valid) {
    switch (e.status) {
      case _RowStatus.success:
        return (AppTheme.successColor, Icons.check_circle_rounded, 'أُنشئ');
      case _RowStatus.failed:
        return (AppTheme.errorColor, Icons.error_rounded, 'فشل');
      case _RowStatus.running:
        return (AppTheme.infoColor, Icons.sync_rounded, 'جارٍ…');
      case _RowStatus.pending:
        return valid
            ? (AppTheme.infoColor, Icons.pending_rounded, 'جاهز')
            : (AppTheme.errorColor, Icons.warning_amber_rounded, 'ناقص');
    }
  }

  Widget _cell(
    _Entry e,
    _Col col, {
    required double width,
    bool required = false,
    bool obscure = false,
    bool ltr = false,
  }) {
    final field = TextField(
      controller: e.ctrls[col],
      obscureText: obscure,
      enabled: !_creating && e.status != _RowStatus.success,
      textDirection: ltr ? TextDirection.ltr : null,
      onChanged: (_) => setState(_resetRunState),
      style: GoogleFonts.cairo(fontSize: 12.sp, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: required ? '${col.labelAr} *' : col.labelAr,
        labelStyle:
            GoogleFonts.cairo(fontSize: 11.sp, color: Colors.grey[600]),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.16)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.16)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.6),
        ),
      ),
    );
    return SizedBox(width: width.w, child: field);
  }

  Widget _rowProfileDropdown(_Entry e) {
    return SizedBox(
      width: 170.w,
      child: DropdownButtonFormField<int>(
        initialValue: _effectiveProfile(e),
        isExpanded: true,
        style: GoogleFonts.cairo(
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1A2E)),
        decoration: InputDecoration(
          labelText: 'الباقة *',
          labelStyle:
              GoogleFonts.cairo(fontSize: 11.sp, color: Colors.grey[600]),
          isDense: true,
          contentPadding:
              EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
            borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.16)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
            borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.16)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
            borderSide:
                const BorderSide(color: AppTheme.primaryColor, width: 1.6),
          ),
        ),
        items: [
          for (final p in _profiles)
            DropdownMenuItem(
              value: _asInt(p['id']),
              child: Text('${p['name'] ?? p['id']}',
                  overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (_creating || e.status == _RowStatus.success)
            ? null
            : (v) => setState(() {
                  e.profileId = v;
                  _resetRunState();
                }),
      ),
    );
  }

  // ───────────────────────────── نموذج الأعمدة ─────────────────────────────

  void _showTemplate() {
    showDialog<void>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.description_outlined, color: AppTheme.infoColor),
              SizedBox(width: 8.w),
              Text('نموذج الأعمدة المتوقّعة',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'يُفضَّل أن يحوي الصفّ الأول رؤوس الأعمدة. الأعمدة الإلزامية: '
                    'اسم المستخدم، كلمة المرور، والباقة (أو اختر باقة افتراضية). '
                    'يمكنك مطابقة الأعمدة يدوياً بعد الاستيراد.',
                    style: GoogleFonts.cairo(
                        fontSize: 12.5.sp, height: 1.6, color: Colors.grey[700]),
                  ),
                  SizedBox(height: 12.h),
                  Container(
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(
                      color: SasUi.pageBg,
                      borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
                      border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: SelectableText(
                      _Col.values.map((c) => c.key).join(','),
                      style: GoogleFonts.robotoMono(
                          fontSize: 12.sp, color: const Color(0xFF1A1A2E)),
                    ),
                  ),
                  SizedBox(height: 10.h),
                  ..._Col.values.map((c) => Padding(
                        padding: EdgeInsets.symmetric(vertical: 2.h),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 6.w, vertical: 1.h),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6.r),
                              ),
                              child: Text(c.key,
                                  style: GoogleFonts.robotoMono(
                                      fontSize: 11.sp,
                                      color: AppTheme.primaryColor)),
                            ),
                            SizedBox(width: 8.w),
                            Text(c.labelAr,
                                style: GoogleFonts.cairo(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('حسناً',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

/// حوار مطابقة أعمدة الملف المستورد إلى الحقول المنطقية.
class _ColumnMappingDialog extends StatefulWidget {
  final List<String> headers;
  final Map<_Col, int?> initial;
  final int sampleRowCount;

  const _ColumnMappingDialog({
    required this.headers,
    required this.initial,
    required this.sampleRowCount,
  });

  @override
  State<_ColumnMappingDialog> createState() => _ColumnMappingDialogState();
}

class _ColumnMappingDialogState extends State<_ColumnMappingDialog> {
  late final Map<_Col, int?> _map = Map.of(widget.initial);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.table_chart_rounded, color: AppTheme.primaryColor),
            SizedBox(width: 8.w),
            Expanded(
              child: Text('مطابقة الأعمدة',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'عدد صفوف البيانات: ${widget.sampleRowCount}. طابق كل حقل بعموده '
                'في الملف (أو اتركه «— بلا —»).',
                style: GoogleFonts.cairo(
                    fontSize: 12.sp, color: Colors.grey[700], height: 1.5),
              ),
              SizedBox(height: 12.h),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final col in _Col.values)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 4.h),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 120.w,
                                child: Text(col.labelAr,
                                    style: GoogleFonts.cairo(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w700)),
                              ),
                              Expanded(
                                child: DropdownButtonFormField<int?>(
                                  initialValue: _map[col],
                                  isExpanded: true,
                                  style: GoogleFonts.cairo(
                                      fontSize: 12.sp,
                                      color: const Color(0xFF1A1A2E)),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10.w, vertical: 8.h),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          SasUi.radiusSm.r),
                                    ),
                                  ),
                                  items: [
                                    DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text('— بلا —',
                                          style: GoogleFonts.cairo(
                                              color: Colors.grey[500])),
                                    ),
                                    for (var i = 0;
                                        i < widget.headers.length;
                                        i++)
                                      DropdownMenuItem<int?>(
                                        value: i,
                                        child: Text(
                                          widget.headers[i].isEmpty
                                              ? 'عمود ${i + 1}'
                                              : widget.headers[i],
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _map[col] = v),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_map),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor),
            child: Text('استيراد',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
