import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../services/accounting_service.dart';
import '../../services/linked_accounts_service.dart';
import '../../services/auth_service.dart';
import '../../services/ftth_api_config.dart';
import '../../services/vps_auth_service.dart';
import '../../services/api/api_config.dart';
import '../../permissions/permissions.dart';
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

  // الشركاء الرئيسيون — لفلترة/إسناد أجور الزونات لكل شريك.
  List<Map<String, dynamic>> _partners = [];
  String? _selectedPartnerId; // null = كل الشركاء (يشمل الاحتياطية بلا شريك)

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadPartners();
    await _loadData();
  }

  Future<void> _loadPartners() async {
    try {
      final res = await LinkedAccountsService.instance.getPartners();
      if (res['success'] == true) {
        final data = res['data'];
        final List raw = data is List
            ? data
            : (data is Map ? (data['data'] ?? data['items'] ?? []) as List : []);
        _partners = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
  }

  /// اسم الشريك من معرّفه (لعرضه على البطاقة).
  String _partnerNameOf(String? id) {
    if (id == null || id.isEmpty) return 'لكل الشركاء';
    final p = _partners.firstWhere(
      (e) => (e['id'] ?? e['Id'])?.toString() == id,
      orElse: () => const {},
    );
    final name = (p['name'] ?? p['Name'] ?? '').toString();
    return name.isEmpty ? 'شريك محذوف' : name;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final feesResult = await AccountingService.instance
          .getZoneMaintenanceFees(companyId: widget.companyId, partnerId: _selectedPartnerId);
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
            if (PermissionManager.instance.canAdd('accounting'))
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
              _buildPartnerSelector(),
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

  /// شريط اختيار الشريك — يفلتر الأجور ويحدّد الشريك الافتراضي عند الإضافة.
  Widget _buildPartnerSelector() {
    if (_partners.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SdSpace.md, vertical: SdSpace.xs),
      color: SdColors.surface,
      child: Row(
        children: [
          const Icon(Icons.handshake_outlined, size: 18, color: SdColors.muted),
          const SizedBox(width: 8),
          Text('الشريك:', style: SdText.caption),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedPartnerId,
                isExpanded: true,
                isDense: true,
                dropdownColor: SdColors.surface,
                style: const TextStyle(
                    fontFamily: SdText.family, color: SdColors.ink, fontSize: 13),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('كل الشركاء (يشمل الاحتياطية)',
                        style: TextStyle(fontFamily: SdText.family, fontSize: 13)),
                  ),
                  ..._partners.map((p) {
                    final id = (p['id'] ?? p['Id'])?.toString();
                    final name = (p['name'] ?? p['Name'] ?? '').toString();
                    return DropdownMenuItem<String?>(
                      value: id,
                      child: Text(name.isEmpty ? '—' : name,
                          style: const TextStyle(fontFamily: SdText.family, fontSize: 13)),
                    );
                  }),
                ],
                onChanged: (v) {
                  setState(() => _selectedPartnerId = v);
                  _loadData();
                },
              ),
            ),
          ),
        ],
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
        final partnerId = (f['PartnerId'] ?? f['partnerId'])?.toString();
        final hasPartner = partnerId != null && partnerId.isNotEmpty;
        final partnerLabel = _partnerNameOf(partnerId);
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
            isThreeLine: notes.toString().isNotEmpty,
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
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: hasPartner
                        ? SdColors.info.withOpacity(0.12)
                        : SdColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(SdRadius.xs),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(hasPartner ? Icons.handshake : Icons.public,
                          size: 11,
                          color: hasPartner ? SdColors.info : SdColors.muted),
                      const SizedBox(width: 3),
                      Text(partnerLabel,
                          style: TextStyle(
                              fontFamily: SdText.family,
                              fontSize: 10,
                              color: hasPartner ? SdColors.info : SdColors.muted)),
                    ],
                  ),
                ),
                if (notes.toString().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(notes, style: SdText.caption),
                ],
              ],
            ),
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
                if (PermissionManager.instance.canEdit('accounting') ||
                    PermissionManager.instance.canDelete('accounting'))
                  PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18, color: SdColors.muted),
                  color: SdColors.surface,
                  onSelected: (action) {
                    if (action == 'edit') _showEditDialog(f);
                    if (action == 'toggle') _toggleEnabled(id, enabled);
                    if (action == 'delete') _confirmDelete(id, name);
                  },
                  itemBuilder: (_) => [
                    if (PermissionManager.instance.canEdit('accounting')) ...[
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
                    ],
                    if (PermissionManager.instance.canDelete('accounting'))
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

  /// جلب مناطق شريك محدّد — المصدر الأساسي هو FTTH `admin.ftth.iq/api/locations/zones`
  /// بتوكن الشريك (نفس مصدر صفحة «الزونات»، عبر بوّابة Cloudflare)، فيُرجِع مناطق الشريك.
  /// احتياطي: مناطق الشريك من عملياته المُزامَنة عندنا (endpoint partner-zones).
  Future<List<Map<String, String>>> _loadPartnerZones(String partnerId) async {
    // 1) المصدر الأساسي: FTTH locations/zones بتوكن الشريك (كما في صفحة الزونات).
    try {
      final login = await LinkedAccountsService.instance.loginPartner(partnerId);
      final ldata = login['data'] ?? login;
      final token = (ldata is Map ? (ldata['accessToken'] ?? ldata['AccessToken']) : null)
          ?.toString();
      if (token != null && token.isNotEmpty) {
        final url = '${FtthApi.api}/locations/zones?pageSize=2000&pageNumber=1';
        final resp = await AuthService.instance.ftthRequestWithToken(
          'GET', url, token,
          extraHeaders: const {
            'x-user-role': '0',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        );
        if (resp.statusCode == 200) {
          final parsed = _parseZoneItems(jsonDecode(resp.body));
          if (parsed.isNotEmpty) return parsed;
        }
      }
    } catch (_) {/* نسقط للمصدر الاحتياطي */}

    // 2) احتياطي: مناطق الشريك من عملياته المُزامَنة عندنا.
    final res = await AccountingService.instance
        .getPartnerZones(partnerId, companyId: widget.companyId);
    final data = res['success'] == true ? res['data'] : null;
    final rows = (data is List ? data : (data is Map ? (data['data'] ?? []) : [])) as List;
    final seen = <String>{};
    final out = <Map<String, String>>[];
    for (final z in rows) {
      if (z is! Map) continue;
      final name = (z['zoneName'] ?? z['ZoneName'] ?? '').toString().trim();
      if (name.isEmpty || !seen.add(name)) continue;
      out.add({'name': name, 'id': (z['zoneId'] ?? z['ZoneId'] ?? '').toString().trim()});
    }
    out.sort((a, b) => a['name']!.compareTo(b['name']!));
    return out;
  }

  /// استخراج {name, id} من استجابة locations/zones بأشكالها (items/model.items/قائمة).
  List<Map<String, String>> _parseZoneItems(dynamic data) {
    List list = const [];
    if (data is List) {
      list = data;
    } else if (data is Map) {
      if (data['items'] is List) {
        list = data['items'] as List;
      } else if (data['model'] is Map && (data['model']['items'] is List)) {
        list = data['model']['items'] as List;
      } else if (data['data'] is List) {
        list = data['data'] as List;
      }
    }
    final seen = <String>{};
    final out = <Map<String, String>>[];
    for (final z in list) {
      if (z is! Map) continue;
      final self = z['self'] is Map ? z['self'] as Map : null;
      final name = (self?['displayValue'] ??
              z['displayValue'] ??
              z['name'] ??
              z['title'] ??
              z['zoneName'] ??
              '')
          .toString()
          .trim();
      final id = (self?['id'] ?? z['id'] ?? z['zoneId'] ?? '').toString().trim();
      if (name.isEmpty || !seen.add(name)) continue;
      out.add({'name': name, 'id': id});
    }
    out.sort((a, b) => a['name']!.compareTo(b['name']!));
    return out;
  }

  void _showAddDialog() {
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final zoneSearchCtrl = TextEditingController();
    String zoneFilter = '';
    String? dialogPartnerId = _selectedPartnerId; // الشريك المُسنَد لهذه الأجرة (null = احتياطية لكل الشركاء)

    List<Map<String, String>> zoneOptions = []; // زونات الشريك المحمّلة
    final Set<String> selectedZones = {}; // المناطق المحدَّدة (بالاسم) — تحديد متعدّد
    Map<String, String> zoneIdByName = {}; // اسم → معرّف الزون
    Set<String> existingForPartner = {}; // أسماء لها أجرة أصلاً لهذا الشريك (تُعطَّل)
    bool loadingZones = false;
    String? zonesError;
    String loadedForPartner = '__init__'; // مفتاح آخر شريك حُمِّلت زوناته

    Future<void> loadZones(void Function(void Function()) setDState, String key) async {
      try {
        // الأجور الموجودة لهذا الشريك تحديداً (لتعطيل المكرّر)
        final feesRes = await AccountingService.instance
            .getZoneMaintenanceFees(companyId: widget.companyId, partnerId: dialogPartnerId);
        final fd = feesRes['data'];
        final feeList = (fd is List ? fd : (fd is Map ? (fd['data'] ?? []) : [])) as List;
        existingForPartner = feeList
            .whereType<Map>()
            .where((f) {
              final pid = (f['PartnerId'] ?? f['partnerId'])?.toString();
              final norm = (pid == null || pid.isEmpty) ? null : pid;
              return norm == dialogPartnerId;
            })
            .map((f) => (f['ZoneName'] ?? f['zoneName'] ?? '').toString())
            .toSet();

        List<Map<String, String>> opts;
        if (dialogPartnerId != null) {
          opts = await _loadPartnerZones(dialogPartnerId!);
        } else {
          // بلا شريك: المناطق العامة من zonestatistics
          final names = await _fetchZoneNames();
          opts = (names.toSet().toList()..sort())
              .map((n) => {'name': n, 'id': ''})
              .toList();
        }
        zoneIdByName = {for (final z in opts) z['name']!: z['id'] ?? ''};
        if (loadedForPartner != key) return; // تغيّر الشريك أثناء التحميل
        setDState(() {
          zoneOptions = opts;
          loadingZones = false;
        });
      } catch (e) {
        if (loadedForPartner != key) return;
        setDState(() {
          zonesError = e.toString().replaceFirst('Exception: ', '');
          loadingZones = false;
        });
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) {
          // تحميل زونات الشريك الحالي (مرّة لكل شريك) — مجدوَل بعد الإطار لتفادي setState أثناء البناء
          final wantKey = dialogPartnerId ?? '__null__';
          if (loadedForPartner != wantKey) {
            loadedForPartner = wantKey;
            loadingZones = true;
            zonesError = null;
            zoneOptions = [];
            selectedZones.clear();
            WidgetsBinding.instance
                .addPostFrameCallback((_) => loadZones(setDState, wantKey));
          }

          final filtered = zoneFilter.isEmpty
              ? zoneOptions
              : zoneOptions
                  .where((z) => z['name']!.toLowerCase().contains(zoneFilter.toLowerCase()))
                  .toList();
          final selectableFiltered =
              filtered.where((z) => !existingForPartner.contains(z['name'])).toList();
          final allFilteredSelected = selectableFiltered.isNotEmpty &&
              selectableFiltered.every((z) => selectedZones.contains(z['name']));
          // إدخال يدوي: اسم منطقة غير موجود في القائمة (للشركاء بلا مناطق مُزامَنة).
          final manualTerm = zoneFilter.trim();
          final canAddManual = manualTerm.isNotEmpty &&
              !zoneOptions.any((z) => z['name']!.toLowerCase() == manualTerm.toLowerCase());
          void addManualZone() {
            if (manualTerm.isEmpty) return;
            if (!zoneOptions.any((z) => z['name'] == manualTerm)) {
              zoneOptions = [
                {'name': manualTerm, 'id': ''},
                ...zoneOptions,
              ];
              zoneIdByName[manualTerm] = '';
            }
            selectedZones.add(manualTerm);
            zoneFilter = '';
            zoneSearchCtrl.clear();
          }

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: SdColors.surface,
              title: Text('إضافة أجور صيانة', style: TextStyle(fontFamily: 'Cairo', color: SdColors.ink)),
              content: SizedBox(
                width: 480,
                height: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // اختيار الشريك الذي تتبعه هذه الأجرة
                    if (_partners.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: SdColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.handshake_outlined, size: 18, color: SdColors.faint),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String?>(
                                  value: dialogPartnerId,
                                  isExpanded: true,
                                  isDense: true,
                                  dropdownColor: SdColors.surface,
                                  hint: const Text('لكل الشركاء (احتياطية)',
                                      style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: SdColors.faint)),
                                  style: const TextStyle(fontFamily: 'Cairo', color: SdColors.ink, fontSize: 13),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('لكل الشركاء (احتياطية)',
                                          style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                                    ),
                                    ..._partners.map((p) {
                                      final id = (p['id'] ?? p['Id'])?.toString();
                                      final name = (p['name'] ?? p['Name'] ?? '').toString();
                                      return DropdownMenuItem<String?>(
                                        value: id,
                                        child: Text(name.isEmpty ? '—' : name,
                                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                                      );
                                    }),
                                  ],
                                  onChanged: (v) => setDState(() => dialogPartnerId = v),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    // حقل بحث/تصفية المناطق
                    TextField(
                      controller: zoneSearchCtrl,
                      style: const TextStyle(color: SdColors.ink, fontSize: 13),
                      onChanged: (v) => setDState(() => zoneFilter = v),
                      decoration: InputDecoration(
                        labelText: 'بحث وتصفية المناطق',
                        labelStyle: const TextStyle(color: SdColors.faint, fontSize: 12),
                        prefixIcon: const Icon(Icons.search, size: 18, color: SdColors.faint),
                        suffixIcon: zoneFilter.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 16, color: SdColors.faint),
                                onPressed: () => setDState(() {
                                  zoneFilter = '';
                                  zoneSearchCtrl.clear();
                                }),
                              )
                            : null,
                        filled: true,
                        fillColor: SdColors.surfaceAlt,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // شريط: عدد المحدَّد + تحديد الكل
                    Row(
                      children: [
                        Text('المحدَّد: ${selectedZones.length}',
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: SdColors.muted)),
                        const Spacer(),
                        if (selectableFiltered.isNotEmpty)
                          TextButton.icon(
                            onPressed: () => setDState(() {
                              if (allFilteredSelected) {
                                for (final z in selectableFiltered) {
                                  selectedZones.remove(z['name']);
                                }
                              } else {
                                for (final z in selectableFiltered) {
                                  selectedZones.add(z['name']!);
                                }
                              }
                            }),
                            icon: Icon(allFilteredSelected ? Icons.deselect : Icons.select_all,
                                size: 16, color: SdColors.info),
                            label: Text(allFilteredSelected ? 'إلغاء الكل' : 'تحديد الكل',
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: SdColors.info)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // قائمة المناطق (تحديد متعدّد)
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: SdColors.ground,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: SdColors.divider),
                        ),
                        child: loadingZones
                            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                            : zonesError != null
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.error_outline, color: SdColors.danger, size: 28),
                                          const SizedBox(height: 6),
                                          Text(zonesError!,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(fontFamily: 'Cairo', color: SdColors.danger, fontSize: 12)),
                                          const SizedBox(height: 6),
                                          TextButton(
                                            onPressed: () => setDState(() {
                                              loadedForPartner = '__retry__';
                                            }),
                                            child: const Text('إعادة المحاولة',
                                                style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : Column(
                                    children: [
                                      if (canAddManual)
                                        InkWell(
                                          onTap: () => setDState(addManualZone),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: SdColors.info.withOpacity(0.08),
                                              border: const Border(bottom: BorderSide(color: SdColors.divider)),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.add_circle, size: 18, color: SdColors.info),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text('إضافة «$manualTerm» كمنطقة يدوية',
                                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: SdColors.info)),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      Expanded(
                                        child: filtered.isEmpty
                                            ? Center(
                                                child: Padding(
                                                  padding: const EdgeInsets.all(12),
                                                  child: Text(
                                                    canAddManual
                                                        ? 'اضغط «إضافة «$manualTerm»» بالأعلى لإضافتها'
                                                        : (zoneOptions.isEmpty
                                                            ? (dialogPartnerId == null
                                                                ? 'لا توجد مناطق'
                                                                : 'لا مناطق مُزامَنة لهذا الشريك — اكتب اسم المنطقة لإضافتها يدوياً')
                                                            : 'لا نتائج للبحث'),
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(fontFamily: 'Cairo', color: SdColors.faint, fontSize: 12),
                                                  ),
                                                ),
                                              )
                                            : ListView.builder(
                                                itemCount: filtered.length,
                                                itemBuilder: (_, i) {
                                                  final name = filtered[i]['name']!;
                                                  final already = existingForPartner.contains(name);
                                                  final isSelected = selectedZones.contains(name);
                                                  return ListTile(
                                                    dense: true,
                                                    visualDensity: VisualDensity.compact,
                                                    enabled: !already,
                                                    selected: isSelected,
                                                    selectedTileColor: SdColors.success.withOpacity(0.08),
                                                    leading: Icon(
                                                      already
                                                          ? Icons.check_circle
                                                          : (isSelected
                                                              ? Icons.check_box
                                                              : Icons.check_box_outline_blank),
                                                      size: 20,
                                                      color: already
                                                          ? SdColors.muted
                                                          : (isSelected ? SdColors.success : SdColors.faint),
                                                    ),
                                                    title: Text(name,
                                                        style: TextStyle(
                                                          color: already ? SdColors.faint : SdColors.ink,
                                                          fontSize: 13,
                                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                        )),
                                                    trailing: already
                                                        ? const Text('مضافة',
                                                            style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: SdColors.muted))
                                                        : null,
                                                    onTap: already
                                                        ? null
                                                        : () => setDState(() {
                                                              if (isSelected) {
                                                                selectedZones.remove(name);
                                                              } else {
                                                                selectedZones.add(name);
                                                              }
                                                            }),
                                                  );
                                                },
                                              ),
                                      ),
                                    ],
                                  ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        _ThousandsSeparatorFormatter(),
                      ],
                      style: const TextStyle(color: SdColors.ink),
                      decoration: InputDecoration(
                        labelText: 'مبلغ الصيانة (د.ع) — يُطبَّق على كل المحدَّد',
                        labelStyle: const TextStyle(color: SdColors.faint, fontSize: 12),
                        filled: true,
                        fillColor: SdColors.surfaceAlt,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
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
                    if (selectedZones.isEmpty) {
                      _snack('اختر منطقة واحدة على الأقل', SdColors.warning);
                      return;
                    }
                    final amount = double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
                    if (amount <= 0) {
                      _snack('أدخل مبلغ صيانة صحيحاً', SdColors.warning);
                      return;
                    }
                    Navigator.pop(ctx);
                    final zones = selectedZones.map((n) {
                      final zid = zoneIdByName[n] ?? '';
                      return {
                        'ZoneName': n,
                        'ZoneId': zid.isEmpty ? null : zid,
                        'MaintenanceAmount': amount,
                        'Notes': notesCtrl.text.isEmpty ? null : notesCtrl.text,
                      };
                    }).toList();
                    final result = await AccountingService.instance.bulkCreateZoneMaintenanceFees({
                      'CompanyId': widget.companyId ?? VpsAuthService.instance.currentCompanyId ?? '',
                      'PartnerId': dialogPartnerId,
                      'Zones': zones,
                    });
                    _snack(
                        result['message']?.toString() ??
                            (result['success'] == true ? 'تم إضافة الأجور' : 'خطأ في الإضافة'),
                        result['success'] == true ? SdColors.success : SdColors.danger);
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
