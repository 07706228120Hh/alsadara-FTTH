import 'package:flutter/material.dart';
import '../../models/task_source_pool.dart';
import '../../services/task_api_service.dart';
import '../../frontend/tokens/sd_colors.dart' show SdColors;

/// اختيار «نوع حساب مصدر + منطقة» لمهمة (المرحلة 1).
///
/// القيم المرسلة للباكند: [type] (0=لا شيء/1=FTTH/2=ساس)،
/// [partnerId]/[partnerName] (FTTH فقط)، و[regionRef] (Guid منطقة ساس كنص،
/// أو نص يدوي حرّ لـ FTTH). التسميات (Label/RegionName) تُشتَقّ خادمياً فلا تُرسل.
/// ملاحظة: لم يَعُد يُختار حساب محدّد (أُزيلت منسدلة «الحساب»).
class TaskSourceSelection {
  final int type;
  final String partnerId;
  final String partnerName;
  final String regionRef;

  const TaskSourceSelection({
    this.type = 0,
    this.partnerId = '',
    this.partnerName = '',
    this.regionRef = '',
  });

  TaskSourceSelection copyWith({
    int? type,
    String? partnerId,
    String? partnerName,
    String? regionRef,
  }) {
    return TaskSourceSelection(
      type: type ?? this.type,
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

  /// لقطة العرض الحالية (للتعديل) — تُستخدم كبديل إن لم تَعُد المنطقة
  /// ضمن المجمّع (حُذفت لاحقاً) حتى لا تُفقد القيمة المخزّنة.
  final String initialRegionName;

  /// مجمّع جاهز (اختياري) — إن مُرِّر لا يُعاد الجلب.
  final TaskSourcePool? pool;

  const TaskSourceRegionSection({
    super.key,
    required this.initial,
    required this.onChanged,
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

        // 2) الشريك الرئيسي (FTTH فقط)
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

        // 3) المنطقة
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
