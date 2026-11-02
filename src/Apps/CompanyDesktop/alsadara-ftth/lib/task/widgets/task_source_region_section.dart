import 'package:flutter/material.dart';
import '../../models/task_source_pool.dart';
import '../../services/task_api_service.dart';
import '../../frontend/tokens/sd_colors.dart' show SdColors;

/// اختيار «حساب مصدر + منطقة» لمهمة (المرحلة 1).
///
/// القيم المرسلة للباكند: [type] (0=لا شيء/1=FTTH/2=ساس)، [accountId]،
/// [partnerId]/[partnerName] (FTTH فقط)، و[regionRef] (Guid منطقة ساس كنص،
/// أو نص يدوي حرّ لـ FTTH). التسميات (Label/RegionName) تُشتَقّ خادمياً فلا تُرسل.
class TaskSourceSelection {
  final int type;
  final String accountId;
  final String partnerId;
  final String partnerName;
  final String regionRef;

  const TaskSourceSelection({
    this.type = 0,
    this.accountId = '',
    this.partnerId = '',
    this.partnerName = '',
    this.regionRef = '',
  });

  TaskSourceSelection copyWith({
    int? type,
    String? accountId,
    String? partnerId,
    String? partnerName,
    String? regionRef,
  }) {
    return TaskSourceSelection(
      type: type ?? this.type,
      accountId: accountId ?? this.accountId,
      partnerId: partnerId ?? this.partnerId,
      partnerName: partnerName ?? this.partnerName,
      regionRef: regionRef ?? this.regionRef,
    );
  }
}

/// قسم منسدلات متتالية (cascading) لربط المهمة بحساب مصدر ومنطقة.
/// يجلب المجمّع مرة واحدة عند أول بناء (أو يستقبله جاهزاً عبر [pool]).
class TaskSourceRegionSection extends StatefulWidget {
  final TaskSourceSelection initial;
  final ValueChanged<TaskSourceSelection> onChanged;

  /// لقطات العرض الحالية (للتعديل) — تُستخدم كبديل إن لم يَعُد الحساب/المنطقة
  /// ضمن المجمّع (حُذف لاحقاً) حتى لا تُفقد القيمة المخزّنة.
  final String initialAccountLabel;
  final String initialRegionName;

  /// مجمّع جاهز (اختياري) — إن مُرِّر لا يُعاد الجلب.
  final TaskSourcePool? pool;

  const TaskSourceRegionSection({
    super.key,
    required this.initial,
    required this.onChanged,
    this.initialAccountLabel = '',
    this.initialRegionName = '',
    this.pool,
  });

  @override
  State<TaskSourceRegionSection> createState() =>
      _TaskSourceRegionSectionState();
}

class _TaskSourceRegionSectionState extends State<TaskSourceRegionSection> {
  TaskSourcePool? _pool;
  bool _loading = false;
  late TaskSourceSelection _sel;
  final _regionTextController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sel = widget.initial;
    // لـ FTTH: RegionRef نصّي يدوي — نملأ الحقل بالقيمة الأولية.
    if (_sel.type == 1) _regionTextController.text = _sel.regionRef;
    if (widget.pool != null) {
      _pool = widget.pool;
    } else {
      _loadPool();
    }
  }

  @override
  void dispose() {
    _regionTextController.dispose();
    super.dispose();
  }

  Future<void> _loadPool() async {
    setState(() => _loading = true);
    try {
      final pool = await TaskApiService.instance.fetchSourcePool();
      if (mounted) setState(() => _pool = pool);
    } catch (_) {
      // المجمّع اختياري — نتجاهل الفشل ونترك الحقول فارغة.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _emit(TaskSourceSelection next) {
    setState(() => _sel = next);
    widget.onChanged(next);
  }

  List<SourceAccountOption> get _accounts {
    final p = _pool;
    if (p == null) return const [];
    if (_sel.type == 1) return p.ftthAccounts;
    if (_sel.type == 2) return p.sasAccounts;
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final pool = _pool;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1) نوع الحساب
        DropdownButtonFormField<int>(
          value: _sel.type,
          isExpanded: true,
          decoration: _dec('حساب المصدر', Icons.account_tree_outlined),
          style: const TextStyle(fontSize: 13, color: SdColors.ink),
          items: const [
            DropdownMenuItem(value: 0, child: Text('لا شيء')),
            DropdownMenuItem(value: 1, child: Text('FTTH')),
            DropdownMenuItem(value: 2, child: Text('ساس')),
          ],
          onChanged: _loading
              ? null
              : (v) {
                  if (v == null) return;
                  _regionTextController.clear();
                  // تغيير النوع يصفّر كل الاختيارات التابعة.
                  _emit(TaskSourceSelection(type: v));
                },
        ),

        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),

        // 2) الحساب (من المجمّع)
        if (_sel.type != 0 && pool != null) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _accountValue(),
            isExpanded: true,
            decoration: _dec('الحساب', Icons.badge_outlined),
            style: const TextStyle(fontSize: 13, color: SdColors.ink),
            items: _accountItems(),
            onChanged: (v) => _emit(_sel.copyWith(accountId: v ?? '')),
          ),
        ],

        // 3) الشريك الرئيسي (FTTH فقط)
        if (_sel.type == 1 && pool != null) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _partnerValue(pool),
            isExpanded: true,
            decoration: _dec('الشريك الرئيسي', Icons.handshake_outlined),
            style: const TextStyle(fontSize: 13, color: SdColors.ink),
            items: pool.partners
                .map((p) => DropdownMenuItem(
                      value: p.partnerId,
                      child: Text(p.partnerName,
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) {
              final name = pool.partners
                  .firstWhere((p) => p.partnerId == v,
                      orElse: () => const PartnerOption(
                          partnerId: '', partnerName: ''))
                  .partnerName;
              _emit(_sel.copyWith(partnerId: v ?? '', partnerName: name));
            },
          ),
        ],

        // 4) المنطقة
        if (_sel.type == 2 && pool != null) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _regionValue(pool),
            isExpanded: true,
            decoration: _dec('المنطقة (ساس)', Icons.map_outlined),
            style: const TextStyle(fontSize: 13, color: SdColors.ink),
            items: pool.sasRegions
                .map((r) => DropdownMenuItem(
                      value: r.id,
                      child: Text(
                          r.code.isNotEmpty ? '${r.name} (${r.code})' : r.name,
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => _emit(_sel.copyWith(regionRef: v ?? '')),
          ),
        ],
        if (_sel.type == 1) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _regionTextController,
            decoration: _dec('المنطقة (يدوية)', Icons.edit_location_alt_outlined)
                .copyWith(hintText: 'اكتب اسم المنطقة...'),
            style: const TextStyle(fontSize: 13),
            onChanged: (v) => _emit(_sel.copyWith(regionRef: v.trim())),
          ),
        ],
      ],
    );
  }

  // ─── قيم مع بديل اصطناعي للقيمة المحذوفة من المجمّع ───

  String? _accountValue() {
    // دائماً صالح: إن لم يكن ضمن المجمّع نضيف بنداً اصطناعياً في _accountItems().
    return _sel.accountId.isEmpty ? null : _sel.accountId;
  }

  List<DropdownMenuItem<String>> _accountItems() {
    final items = _accounts
        .map((a) => DropdownMenuItem(
              value: a.id,
              child: Text(a.display, overflow: TextOverflow.ellipsis),
            ))
        .toList();
    // الحساب المخزّن غير موجود بالمجمّع (حُذف) → أضف بنداً اصطناعياً باللقطة.
    if (_sel.accountId.isNotEmpty &&
        !_accounts.any((a) => a.id == _sel.accountId)) {
      items.insert(
        0,
        DropdownMenuItem(
          value: _sel.accountId,
          child: Text(
            widget.initialAccountLabel.isNotEmpty
                ? widget.initialAccountLabel
                : 'حساب محفوظ',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return items;
  }

  String? _partnerValue(TaskSourcePool pool) {
    if (_sel.partnerId.isEmpty) return null;
    return pool.partners.any((p) => p.partnerId == _sel.partnerId)
        ? _sel.partnerId
        : null;
  }

  String? _regionValue(TaskSourcePool pool) {
    if (_sel.regionRef.isEmpty) return null;
    return pool.sasRegions.any((r) => r.id == _sel.regionRef)
        ? _sel.regionRef
        : null;
  }

  InputDecoration _dec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      prefixIcon: Icon(icon, size: 18, color: SdColors.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      filled: true,
      fillColor: SdColors.surface,
    );
  }
}
