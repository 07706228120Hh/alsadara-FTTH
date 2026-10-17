import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../services/api/api_config.dart';
import '../../config/app_secrets.dart';
/// صفحة إدارة أجور صيانة الزونات
class ZoneMaintenanceFeesPage extends StatefulWidget {
  final String? companyId;
  const ZoneMaintenanceFeesPage({super.key, this.companyId});

  @override
  State<ZoneMaintenanceFeesPage> createState() => _ZoneMaintenanceFeesPageState();
}

class _ZoneMaintenanceFeesPageState extends State<ZoneMaintenanceFeesPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _fees = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final feesResult = await AccountingService.instance.getZoneMaintenanceFees(companyId: widget.companyId);
      if (feesResult['success'] == true) {
        final data = feesResult['data'];
        _fees = (data is List ? data : (data is Map ? (data['data'] ?? []) : []))
            .cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _fees;
    final q = _search.toLowerCase();
    return _fees.where((f) {
      final name = (f['ZoneName'] ?? f['zoneName'] ?? '').toString().toLowerCase();
      final notes = (f['Notes'] ?? f['notes'] ?? '').toString().toLowerCase();
      return name.contains(q) || notes.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'أجور صيانة الزونات',
          subtitle: '${_fees.length} زون',
          actions: [
            SdAppBarAction(
              icon: Icons.refresh,
              label: 'تحديث',
              onPressed: _loadData,
            ),
            SdAppBarAction(
              icon: Icons.add,
              label: 'إضافة',
              onPressed: _showAddDialog,
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildSearchBar(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filtered.isEmpty
                        ? const Center(
                            child: SingleChildScrollView(
                              child: SdEmptyState(
                                title: 'لا توجد أجور صيانة مضافة',
                                icon: Icons.build_circle,
                              ),
                            ),
                          )
                        : _buildList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.md, vertical: SdSpace.xs),
      color: SdColors.surface,
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        style: const TextStyle(
            fontFamily: SdText.family, color: SdColors.ink, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'بحث بالاسم...',
          hintStyle: const TextStyle(
              fontFamily: SdText.family, color: SdColors.faint),
          prefixIcon: const Icon(Icons.search, size: 18, color: SdColors.muted),
          filled: true,
          fillColor: SdColors.surfaceAlt,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(SdRadius.xs),
              borderSide: const BorderSide(color: SdColors.edge)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(SdRadius.xs),
              borderSide: const BorderSide(color: SdColors.edge)),
        ),
      ),
    );
  }

  Widget _buildList() {
    final list = _filtered;
    return ListView.builder(
      padding: const EdgeInsets.all(SdSpace.sm),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final f = list[i];
        final name = f['ZoneName'] ?? f['zoneName'] ?? '';
        final amount = ((f['MaintenanceAmount'] ?? f['maintenanceAmount'] ?? 0) as num).toDouble();
        final enabled = f['IsEnabled'] ?? f['isEnabled'] ?? true;
        final notes = f['Notes'] ?? f['notes'] ?? '';
        final id = (f['Id'] ?? f['id'])?.toString() ?? '';
        final tone = enabled ? SdStatus.success.tone : SdGroup.neutral.tone;

        return Container(
          margin: const EdgeInsets.only(bottom: SdSpace.xs),
          decoration: BoxDecoration(
            color: SdColors.surface,
            borderRadius: BorderRadius.circular(SdRadius.md),
            boxShadow: SdDepth.raised(depth: SdDepth.small),
            border: Border(right: BorderSide(color: tone.base, width: 3)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: SdSpace.md, vertical: 4),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tone.tint,
                borderRadius: BorderRadius.circular(SdRadius.xs),
                boxShadow: [BoxShadow(color: tone.tintEdge, offset: const Offset(0, 2))],
              ),
              child: Icon(
                enabled ? Icons.build_circle : Icons.block,
                color: tone.base,
                size: 20,
              ),
            ),
            title: Text(name, style: SdText.label),
            subtitle: notes.isNotEmpty
                ? Text(notes, style: SdText.caption)
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${amount.toStringAsFixed(0)} د.ع',
                    style: const TextStyle(
                        fontFamily: SdText.family,
                        color: SdColors.success,
                        fontSize: 14,
                        fontWeight: FontWeight.w900)),
                const SizedBox(width: SdSpace.xs),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18, color: SdColors.muted),
                  color: SdColors.surface,
                  onSelected: (action) {
                    if (action == 'edit') _showEditDialog(f);
                    if (action == 'toggle') _toggleEnabled(id, enabled);
                    if (action == 'delete') _confirmDelete(id, name);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'edit',
                        child: Text('تعديل',
                            style: TextStyle(
                                fontFamily: SdText.family,
                                color: SdColors.ink,
                                fontSize: 13))),
                    PopupMenuItem(
                        value: 'toggle',
                        child: Text(enabled ? 'تعطيل' : 'تفعيل',
                            style: TextStyle(
                                fontFamily: SdText.family,
                                color: enabled
                                    ? SdColors.warningText
                                    : SdColors.success,
                                fontSize: 13))),
                    const PopupMenuItem(
                        value: 'delete',
                        child: Text('حذف',
                            style: TextStyle(
                                fontFamily: SdText.family,
                                color: SdColors.danger,
                                fontSize: 13))),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// جلب أسماء الزونات من ZoneStatistics API
  Future<List<String>> _fetchZoneNames() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.vpsBaseUrl}/api/zonestatistics'),
        headers: {'X-Api-Key': appSecrets.internalApiKey}, // LEGACY: ZoneStatistics (JWT = SuperAdmin only)
      );
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data
            .map((z) => (z['ZoneName'] ?? z['zoneName'] ?? '').toString())
            .where((n) => n.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  void _showAddDialog() {
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final zoneSearchCtrl = TextEditingController();
    String? selectedZone;
    String zoneFilter = '';
    List<String> availableZones = [];
    bool zonesLoaded = false;

    Future<void> loadZones(void Function(void Function()) setDState) async {
      if (zonesLoaded) return;
      zonesLoaded = true;
      try {
        final existingNames = _fees.map((f) => (f['ZoneName'] ?? f['zoneName'] ?? '').toString()).toSet();
        final all = await _fetchZoneNames();
        availableZones = all.where((n) => !existingNames.contains(n)).toList()..sort();
        setDState(() {});
      } catch (_) {}
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) {
          // تحميل الزونات مرة واحدة
          if (!zonesLoaded) loadZones(setDState);

          final filtered = zoneFilter.isEmpty
              ? <String>[]
              : availableZones.where((n) => n.toLowerCase().contains(zoneFilter.toLowerCase())).toList();

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: SdColors.surface,
              title: Text('إضافة أجور صيانة', style: TextStyle(fontFamily: 'Cairo', color: SdColors.ink)),
              content: SizedBox(
                width: 450,
                height: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // حقل بحث الزون
                    TextField(
                      controller: zoneSearchCtrl,
                      style: const TextStyle(color: SdColors.ink, fontSize: 13),
                      onChanged: (v) => setDState(() {
                        zoneFilter = v;
                        // إذا كتب اسم يدوياً
                        if (v.isNotEmpty && !availableZones.contains(selectedZone)) {
                          selectedZone = v;
                        }
                      }),
                      decoration: InputDecoration(
                        labelText: 'بحث أو كتابة اسم الزون',
                        labelStyle: const TextStyle(color: SdColors.faint, fontSize: 12),
                        prefixIcon: const Icon(Icons.search, size: 18, color: SdColors.faint),
                        suffixIcon: selectedZone != null && selectedZone!.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Chip(
                                  label: Text(selectedZone!, style: const TextStyle(fontSize: 11, color: Colors.white)),
                                  backgroundColor: SdColors.success,
                                  deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white),
                                  onDeleted: () => setDState(() {
                                    selectedZone = null;
                                    zoneSearchCtrl.clear();
                                    zoneFilter = '';
                                  }),
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: SdColors.surfaceAlt,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // قائمة الزونات
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: SdColors.ground,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: SdColors.divider),
                        ),
                        child: filtered.isEmpty
                            ? Center(child: Text(
                                zoneFilter.isEmpty ? 'اكتب اسم الزون للبحث...' : 'لا توجد نتائج — اضغط إضافة لاستخدام "$zoneFilter"',
                                style: TextStyle(fontFamily: 'Cairo', color: SdColors.faint, fontSize: 11),
                                textAlign: TextAlign.center,
                              ))
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final name = filtered[i];
                                  final isSelected = selectedZone == name;
                                  return ListTile(
                                    dense: true,
                                    visualDensity: VisualDensity.compact,
                                    selected: isSelected,
                                    selectedTileColor: SdColors.success.withOpacity(0.1),
                                    leading: Icon(
                                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                                      size: 18,
                                      color: isSelected ? SdColors.success : SdColors.faint,
                                    ),
                                    title: Text(name, style: TextStyle(
                                      color: isSelected ? SdColors.success : SdColors.ink,
                                      fontSize: 13,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    )),
                                    onTap: () => setDState(() {
                                      selectedZone = name;
                                      zoneSearchCtrl.text = name;
                                    }),
                                  );
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        _ThousandsSeparatorFormatter(),
                      ],
                      style: const TextStyle(color: SdColors.ink),
                      decoration: InputDecoration(
                        labelText: 'مبلغ الصيانة (د.ع)',
                        labelStyle: const TextStyle(color: SdColors.faint),
                        filled: true,
                        fillColor: SdColors.surfaceAlt,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      style: const TextStyle(color: SdColors.ink),
                      decoration: InputDecoration(
                        labelText: 'ملاحظات (اختياري)',
                        labelStyle: const TextStyle(color: SdColors.faint),
                        filled: true,
                        fillColor: SdColors.surfaceAlt,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: SdColors.faint)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: SdColors.success, foregroundColor: Colors.white),
                  onPressed: () async {
                    // استخدام النص المكتوب إذا لم يتم اختيار من القائمة
                    final zoneName = selectedZone?.isNotEmpty == true
                        ? selectedZone!
                        : zoneSearchCtrl.text.trim();
                    if (zoneName.isEmpty || amountCtrl.text.isEmpty) {
                      _snack('يجب تحديد الزون والمبلغ', SdColors.warning);
                      return;
                    }
                    Navigator.pop(ctx);
                    final result = await AccountingService.instance.createZoneMaintenanceFee({
                      'ZoneName': zoneName,
                      'MaintenanceAmount': double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0,
                      'Notes': notesCtrl.text.isEmpty ? null : notesCtrl.text,
                      'CompanyId': widget.companyId ?? VpsAuthService.instance.currentCompanyId ?? '',
                    });
                    if (result['success'] == true) {
                      _snack('تم إضافة أجور صيانة $zoneName', SdColors.success);
                    } else {
                      _snack(result['message'] ?? 'خطأ في الإضافة', SdColors.danger);
                    }
                    _loadData();
                  },
                  child: Text('إضافة', style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> fee) {
    final id = (fee['Id'] ?? fee['id'])?.toString() ?? '';
    final rawAmount = ((fee['MaintenanceAmount'] ?? fee['maintenanceAmount'] ?? 0) as num).toStringAsFixed(0);
    final formattedAmount = rawAmount.replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    final amountCtrl = TextEditingController(text: formattedAmount);
    final notesCtrl = TextEditingController(text: fee['Notes'] ?? fee['notes'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: SdColors.surface,
          title: Text('تعديل أجور صيانة: ${fee['ZoneName'] ?? fee['zoneName']}',
              style: TextStyle(fontFamily: 'Cairo', color: SdColors.ink, fontSize: 14)),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    _ThousandsSeparatorFormatter(),
                  ],
                  style: const TextStyle(color: SdColors.ink),
                  decoration: InputDecoration(
                    labelText: 'مبلغ الصيانة (د.ع)',
                    labelStyle: const TextStyle(color: SdColors.faint),
                    filled: true,
                    fillColor: SdColors.surfaceAlt,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  style: const TextStyle(color: SdColors.ink),
                  decoration: InputDecoration(
                    labelText: 'ملاحظات',
                    labelStyle: const TextStyle(color: SdColors.faint),
                    filled: true,
                    fillColor: SdColors.surfaceAlt,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: SdColors.faint)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.info, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await AccountingService.instance.updateZoneMaintenanceFee(id, {
                  'MaintenanceAmount': double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0,
                  'Notes': notesCtrl.text.isEmpty ? null : notesCtrl.text,
                });
                _snack(result['message'] ?? 'تم', result['success'] == true ? SdColors.success : SdColors.danger);
                _loadData();
              },
              child: Text('حفظ', style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleEnabled(String id, bool currentState) async {
    final result = await AccountingService.instance.updateZoneMaintenanceFee(id, {
      'IsEnabled': !currentState,
    });
    _snack(result['success'] == true ? (currentState ? 'تم التعطيل' : 'تم التفعيل') : 'خطأ',
        result['success'] == true ? SdColors.success : SdColors.danger);
    _loadData();
  }

  void _confirmDelete(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: SdColors.surface,
          title: Text('حذف أجور صيانة', style: TextStyle(fontFamily: 'Cairo', color: SdColors.danger)),
          content: Text('هل تريد حذف أجور صيانة الزون "$name"؟',
              style: const TextStyle(color: SdColors.ink)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: SdColors.faint)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.danger, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await AccountingService.instance.deleteZoneMaintenanceFee(id);
                _snack(result['message'] ?? 'تم', result['success'] == true ? SdColors.success : SdColors.danger);
                _loadData();
              },
              child: Text('حذف', style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: TextStyle(fontFamily: 'Cairo')), backgroundColor: color));
  }
}

/// فواصل المراتب للأرقام (1000 → 1,000)
class _ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(',', '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final formatted = digits.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
