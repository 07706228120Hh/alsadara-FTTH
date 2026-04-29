import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: SafeArea(
          child: Column(
            children: [
              _buildToolbar(),
              _buildSearchBar(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filtered.isEmpty
                        ? Center(
                            child: Text('لا توجد أجور صيانة مضافة',
                                style: GoogleFonts.cairo(color: AccountingTheme.textMuted)))
                        : _buildList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.spaceXL, vertical: context.accR.spaceL),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_forward_rounded),
            style: IconButton.styleFrom(foregroundColor: AccountingTheme.textSecondary),
          ),
          SizedBox(width: context.accR.spaceS),
          Container(
            padding: EdgeInsets.all(context.accR.spaceS),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonGreenGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.build_circle, color: Colors.white, size: context.accR.iconM),
          ),
          SizedBox(width: context.accR.spaceM),
          Expanded(
            child: Text('أجور صيانة الزونات',
                style: GoogleFonts.cairo(
                    fontSize: context.accR.headingMedium,
                    fontWeight: FontWeight.bold,
                    color: AccountingTheme.textPrimary)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AccountingTheme.neonPink.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${_fees.length}',
                style: GoogleFonts.cairo(
                    fontSize: context.accR.small,
                    fontWeight: FontWeight.bold,
                    color: AccountingTheme.neonPink)),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _loadData,
            icon: Icon(Icons.refresh, size: context.accR.iconM),
            style: IconButton.styleFrom(foregroundColor: AccountingTheme.textSecondary),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: _showAddDialog,
            icon: Icon(Icons.add, size: context.accR.iconS),
            label: Text('إضافة', style: GoogleFonts.cairo(fontSize: context.accR.financialSmall)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.neonGreen,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: context.accR.spaceL, vertical: context.accR.spaceS),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AccountingTheme.bgCard,
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        style: const TextStyle(color: AccountingTheme.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'بحث بالاسم...',
          hintStyle: TextStyle(color: AccountingTheme.textMuted.withOpacity(0.5)),
          prefixIcon: const Icon(Icons.search, size: 18, color: AccountingTheme.textMuted),
          filled: true,
          fillColor: AccountingTheme.bgPrimary,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildList() {
    final list = _filtered;
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final f = list[i];
        final name = f['ZoneName'] ?? f['zoneName'] ?? '';
        final amount = ((f['MaintenanceAmount'] ?? f['maintenanceAmount'] ?? 0) as num).toDouble();
        final enabled = f['IsEnabled'] ?? f['isEnabled'] ?? true;
        final notes = f['Notes'] ?? f['notes'] ?? '';
        final id = (f['Id'] ?? f['id'])?.toString() ?? '';

        return Card(
          color: AccountingTheme.bgCard,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: enabled ? AccountingTheme.neonGreen.withOpacity(0.3) : AccountingTheme.textMuted.withOpacity(0.2),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (enabled ? AccountingTheme.neonGreen : AccountingTheme.textMuted).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                enabled ? Icons.build_circle : Icons.block,
                color: enabled ? AccountingTheme.neonGreen : AccountingTheme.textMuted,
                size: 20,
              ),
            ),
            title: Text(name,
                style: GoogleFonts.cairo(
                    color: AccountingTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            subtitle: notes.isNotEmpty
                ? Text(notes, style: GoogleFonts.cairo(color: AccountingTheme.textMuted, fontSize: 11))
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${amount.toStringAsFixed(0)} د.ع',
                    style: GoogleFonts.cairo(
                        color: AccountingTheme.neonGreen,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18, color: AccountingTheme.textMuted),
                  color: AccountingTheme.bgCard,
                  onSelected: (action) {
                    if (action == 'edit') _showEditDialog(f);
                    if (action == 'toggle') _toggleEnabled(id, enabled);
                    if (action == 'delete') _confirmDelete(id, name);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Text('تعديل', style: GoogleFonts.cairo(color: AccountingTheme.textPrimary, fontSize: 13))),
                    PopupMenuItem(
                        value: 'toggle',
                        child: Text(enabled ? 'تعطيل' : 'تفعيل',
                            style: GoogleFonts.cairo(color: enabled ? AccountingTheme.warning : AccountingTheme.success, fontSize: 13))),
                    PopupMenuItem(value: 'delete', child: Text('حذف', style: GoogleFonts.cairo(color: AccountingTheme.danger, fontSize: 13))),
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
        Uri.parse('https://api.ramzalsadara.tech/api/zonestatistics'),
        headers: {'X-Api-Key': 'sadara-internal-2024-secure-key'},
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
              backgroundColor: AccountingTheme.bgCard,
              title: Text('إضافة أجور صيانة', style: GoogleFonts.cairo(color: AccountingTheme.textPrimary)),
              content: SizedBox(
                width: 450,
                height: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // حقل بحث الزون
                    TextField(
                      controller: zoneSearchCtrl,
                      style: const TextStyle(color: AccountingTheme.textPrimary, fontSize: 13),
                      onChanged: (v) => setDState(() {
                        zoneFilter = v;
                        // إذا كتب اسم يدوياً
                        if (v.isNotEmpty && !availableZones.contains(selectedZone)) {
                          selectedZone = v;
                        }
                      }),
                      decoration: InputDecoration(
                        labelText: 'بحث أو كتابة اسم الزون',
                        labelStyle: const TextStyle(color: AccountingTheme.textMuted, fontSize: 12),
                        prefixIcon: const Icon(Icons.search, size: 18, color: AccountingTheme.textMuted),
                        suffixIcon: selectedZone != null && selectedZone!.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Chip(
                                  label: Text(selectedZone!, style: const TextStyle(fontSize: 11, color: Colors.white)),
                                  backgroundColor: AccountingTheme.neonGreen,
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
                        fillColor: AccountingTheme.bgCardHover,
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
                          color: AccountingTheme.bgPrimary,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AccountingTheme.borderColor),
                        ),
                        child: filtered.isEmpty
                            ? Center(child: Text(
                                zoneFilter.isEmpty ? 'اكتب اسم الزون للبحث...' : 'لا توجد نتائج — اضغط إضافة لاستخدام "$zoneFilter"',
                                style: GoogleFonts.cairo(color: AccountingTheme.textMuted, fontSize: 11),
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
                                    selectedTileColor: AccountingTheme.neonGreen.withOpacity(0.1),
                                    leading: Icon(
                                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                                      size: 18,
                                      color: isSelected ? AccountingTheme.neonGreen : AccountingTheme.textMuted,
                                    ),
                                    title: Text(name, style: TextStyle(
                                      color: isSelected ? AccountingTheme.neonGreen : AccountingTheme.textPrimary,
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
                      style: const TextStyle(color: AccountingTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'مبلغ الصيانة (د.ع)',
                        labelStyle: const TextStyle(color: AccountingTheme.textMuted),
                        filled: true,
                        fillColor: AccountingTheme.bgCardHover,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      style: const TextStyle(color: AccountingTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'ملاحظات (اختياري)',
                        labelStyle: const TextStyle(color: AccountingTheme.textMuted),
                        filled: true,
                        fillColor: AccountingTheme.bgCardHover,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إلغاء', style: GoogleFonts.cairo(color: AccountingTheme.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AccountingTheme.neonGreen, foregroundColor: Colors.white),
                  onPressed: () async {
                    // استخدام النص المكتوب إذا لم يتم اختيار من القائمة
                    final zoneName = selectedZone?.isNotEmpty == true
                        ? selectedZone!
                        : zoneSearchCtrl.text.trim();
                    if (zoneName.isEmpty || amountCtrl.text.isEmpty) {
                      _snack('يجب تحديد الزون والمبلغ', AccountingTheme.warning);
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
                      _snack('تم إضافة أجور صيانة $zoneName', AccountingTheme.success);
                    } else {
                      _snack(result['message'] ?? 'خطأ في الإضافة', AccountingTheme.danger);
                    }
                    _loadData();
                  },
                  child: Text('إضافة', style: GoogleFonts.cairo()),
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
          backgroundColor: AccountingTheme.bgCard,
          title: Text('تعديل أجور صيانة: ${fee['ZoneName'] ?? fee['zoneName']}',
              style: GoogleFonts.cairo(color: AccountingTheme.textPrimary, fontSize: 14)),
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
                  style: const TextStyle(color: AccountingTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'مبلغ الصيانة (د.ع)',
                    labelStyle: const TextStyle(color: AccountingTheme.textMuted),
                    filled: true,
                    fillColor: AccountingTheme.bgCardHover,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  style: const TextStyle(color: AccountingTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'ملاحظات',
                    labelStyle: const TextStyle(color: AccountingTheme.textMuted),
                    filled: true,
                    fillColor: AccountingTheme.bgCardHover,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.info, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await AccountingService.instance.updateZoneMaintenanceFee(id, {
                  'MaintenanceAmount': double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0,
                  'Notes': notesCtrl.text.isEmpty ? null : notesCtrl.text,
                });
                _snack(result['message'] ?? 'تم', result['success'] == true ? AccountingTheme.success : AccountingTheme.danger);
                _loadData();
              },
              child: Text('حفظ', style: GoogleFonts.cairo()),
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
        result['success'] == true ? AccountingTheme.success : AccountingTheme.danger);
    _loadData();
  }

  void _confirmDelete(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text('حذف أجور صيانة', style: GoogleFonts.cairo(color: AccountingTheme.danger)),
          content: Text('هل تريد حذف أجور صيانة الزون "$name"؟',
              style: const TextStyle(color: AccountingTheme.textPrimary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.danger, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await AccountingService.instance.deleteZoneMaintenanceFee(id);
                _snack(result['message'] ?? 'تم', result['success'] == true ? AccountingTheme.success : AccountingTheme.danger);
                _loadData();
              },
              child: Text('حذف', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: GoogleFonts.cairo()), backgroundColor: color));
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
