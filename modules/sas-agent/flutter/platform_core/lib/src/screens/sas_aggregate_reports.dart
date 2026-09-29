// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../api/staff_api.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

// ─────────────────────────── مساعدات ───────────────────────────

int _asInt(dynamic v, [int d = 0]) {
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? d;
}

// ══════════════════════════════════════════════════════════════
// الشاشة ١: العملاء (SasClientsReport)
// ══════════════════════════════════════════════════════════════

class SasClientsReport extends StatefulWidget {
  final StaffApi api;
  final int cid;
  const SasClientsReport({super.key, required this.api, required this.cid});

  @override
  State<SasClientsReport> createState() => _SasClientsReportState();
}

class _SasClientsReportState extends State<SasClientsReport> {
  // ─── بيانات الملخّص ───
  int _total = 0, _active = 0, _expired = 0;
  bool _summaryLoading = true;
  String? _summaryError;

  // ─── بيانات الباقات ───
  List<Map<String, dynamic>> _profiles = [];
  bool _profilesLoading = true;
  String? _profilesError;

  // ─── بيانات الوكلاء ───
  List<Map<String, dynamic>> _managers = [];
  bool _managersLoading = true;
  String? _managersError;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    _loadSummary();
    _loadProfiles();
    _loadManagers();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _summaryLoading = true;
      _summaryError = null;
    });
    try {
      final r = await widget.api.sasGet(widget.cid, 'usersReport/summary');
      if (!mounted) return;
      final data = (r is Map) ? (r['data'] is Map ? r['data'] as Map : null) : null;
      setState(() {
        _total = _asInt(data?['total']);
        _active = _asInt(data?['active']);
        _expired = _asInt(data?['expired']);
        _summaryLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _summaryError = '$e';
          _summaryLoading = false;
        });
      }
    }
  }

  Future<void> _loadProfiles() async {
    setState(() {
      _profilesLoading = true;
      _profilesError = null;
    });
    try {
      final r = await widget.api.sasPostList(widget.cid, 'usersReport/perProfile', {});
      if (!mounted) return;
      final list = (r is Map) ? (r['data'] as List?) : (r as List?);
      setState(() {
        _profiles = (list ?? []).whereType<Map>().map((e) {
          return e.cast<String, dynamic>();
        }).toList();
        _profilesLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _profilesError = '$e';
          _profilesLoading = false;
        });
      }
    }
  }

  Future<void> _loadManagers() async {
    setState(() {
      _managersLoading = true;
      _managersError = null;
    });
    try {
      final r = await widget.api.sasGet(widget.cid, 'usersReport/perManager');
      if (!mounted) return;
      final list = (r is Map) ? (r['data'] as List?) : (r as List?);
      setState(() {
        _managers = (list ?? []).whereType<Map>().map((e) {
          return e.cast<String, dynamic>();
        }).toList();
        _managersLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _managersError = '$e';
          _managersLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('العملاء'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed:
                  (_summaryLoading || _profilesLoading || _managersLoading)
                      ? null
                      : _loadAll,
              icon: const Icon(PhosphorIconsBold.arrowsClockwise),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── قسم الملخّص ───
              SectionTitle('إجمالي المشتركين'),
              _buildSummarySection(pal),
              // ─── قسم الباقات ───
              SectionTitle('توزيع الباقات'),
              _buildProfilesSection(pal),
              // ─── قسم الوكلاء ───
              SectionTitle('توزيع الوكلاء الفرعيين'),
              _buildManagersSection(pal),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ─── ملخّص: ٣ بطاقات إحصائية ───
  Widget _buildSummarySection(PlatformPalette pal) {
    if (_summaryLoading) return const Padding(padding: EdgeInsets.all(16), child: LoadingView());
    if (_summaryError != null) return ErrorView(_summaryError!, onRetry: _loadSummary);
    return StatGrid([
      StatTile(
        label: 'الإجمالي',
        value: '$_total',
        icon: PhosphorIconsDuotone.users,
        color: pal.accent,
      ),
      StatTile(
        label: 'نشط',
        value: '$_active',
        icon: PhosphorIconsDuotone.checkCircle,
        color: pal.success,
      ),
      StatTile(
        label: 'منتهٍ',
        value: '$_expired',
        icon: PhosphorIconsDuotone.xCircle,
        color: pal.danger,
      ),
    ]);
  }

  // ─── جدول الباقات ───
  Widget _buildProfilesSection(PlatformPalette pal) {
    if (_profilesLoading) return const Padding(padding: EdgeInsets.all(16), child: LoadingView());
    if (_profilesError != null) return ErrorView(_profilesError!, onRetry: _loadProfiles);
    if (_profiles.isEmpty) {
      return EmptyView(icon: PhosphorIconsDuotone.package, title: 'لا توجد باقات');
    }
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 24,
          headingRowHeight: 42,
          dataRowMinHeight: 38,
          dataRowMaxHeight: 48,
          columns: const [
            DataColumn(label: Text('الباقة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
            DataColumn(label: Text('العدد الكلي', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)), numeric: true),
            DataColumn(label: Text('نشط', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)), numeric: true),
            DataColumn(label: Text('منتهٍ', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)), numeric: true),
          ],
          rows: _profiles.map((row) {
            final name = '${row['profile_name'] ?? row['profile_id'] ?? '-'}';
            final total = _asInt(row['c']);
            final active = _asInt(row['active']);
            final expired = _asInt(row['expired']);
            return DataRow(cells: [
              DataCell(Text(name, style: const TextStyle(fontSize: 12.5))),
              DataCell(Text('$total', style: TextStyle(fontSize: 12.5, color: pal.text))),
              DataCell(Text('$active', style: TextStyle(fontSize: 12.5, color: pal.success, fontWeight: FontWeight.w600))),
              DataCell(Text('$expired', style: TextStyle(fontSize: 12.5, color: pal.danger, fontWeight: FontWeight.w600))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  // ─── جدول الوكلاء الفرعيين ───
  Widget _buildManagersSection(PlatformPalette pal) {
    if (_managersLoading) return const Padding(padding: EdgeInsets.all(16), child: LoadingView());
    if (_managersError != null) return ErrorView(_managersError!, onRetry: _loadManagers);
    if (_managers.isEmpty) {
      return EmptyView(icon: PhosphorIconsDuotone.userCircle, title: 'لا توجد وكلاء فرعيون');
    }
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 24,
          headingRowHeight: 42,
          dataRowMinHeight: 38,
          dataRowMaxHeight: 48,
          columns: const [
            DataColumn(label: Text('الوكيل الفرعي', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
            DataColumn(label: Text('العدد الكلي', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)), numeric: true),
            DataColumn(label: Text('نشط', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)), numeric: true),
            DataColumn(label: Text('منتهٍ', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)), numeric: true),
          ],
          rows: _managers.map((row) {
            final name = '${row['manager_name'] ?? row['parent_id'] ?? '-'}';
            final total = _asInt(row['c']);
            final active = _asInt(row['active']);
            final expired = _asInt(row['expired']);
            return DataRow(cells: [
              DataCell(Text(name, style: const TextStyle(fontSize: 12.5))),
              DataCell(Text('$total', style: TextStyle(fontSize: 12.5, color: pal.text))),
              DataCell(Text('$active', style: TextStyle(fontSize: 12.5, color: pal.success, fontWeight: FontWeight.w600))),
              DataCell(Text('$expired', style: TextStyle(fontSize: 12.5, color: pal.danger, fontWeight: FontWeight.w600))),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// الشاشة ٢: إحصائيات التفعيل (SasActivationsStats)
// ══════════════════════════════════════════════════════════════

class SasActivationsStats extends StatefulWidget {
  final StaffApi api;
  final int cid;
  const SasActivationsStats({super.key, required this.api, required this.cid});

  @override
  State<SasActivationsStats> createState() => _SasActivationsStatsState();
}

class _SasActivationsStatsState extends State<SasActivationsStats> {
  int _grandTotal = 0;
  // كل عنصر: {day: int, total: int}
  List<Map<String, int>> _dailyRows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // report/activations يتطلّب الشهر/السنة + النطاق (مكتشَف بفكّ حمولة لوحة SAS).
      final now = DateTime.now();
      final r = await widget.api.sasPostList(widget.cid, 'report/activations', {
        'type': 'daily', 'month': now.month, 'year': now.year,
        'manager_id': -1, 'sub_managers': 'true', 'activation_method': 'any',
      });
      if (!mounted) return;

      final rawData = (r is Map) ? (r['data'] as List?) : (r as List?);
      final rows = (rawData ?? []).whereType<Map>().toList();

      int grand = 0;
      final Map<int, int> dailyMap = {};

      for (final row in rows) {
        final dayVal = row['day'];
        final profileIdVal = row['profile_id'];
        final totalVal = _asInt(row['total']);

        final bool isDayNull = dayVal == null;
        final bool isProfileNull = profileIdVal == null;

        if (isDayNull && isProfileNull) {
          // إجمالي كلي للشهر
          grand = totalVal;
        } else if (!isDayNull && isProfileNull) {
          // إجمالي اليوم
          final day = _asInt(dayVal);
          dailyMap[day] = totalVal;
        }
        // الصفوف التي profile_id != null هي تفاصيل الباقات — لا نعرضها هنا
      }

      // رتّب تصاعدياً باليوم
      final sortedDays = dailyMap.keys.toList()..sort();
      final dailyRows = sortedDays
          .map((d) => {'day': d, 'total': dailyMap[d] ?? 0})
          .toList();

      if (!mounted) return;
      setState(() {
        _grandTotal = grand;
        _dailyRows = dailyRows;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final tt = Theme.of(context).textTheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إحصائيات التفعيل'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: const Icon(PhosphorIconsBold.arrowsClockwise),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: ErrorView(_error!, onRetry: _load),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ─── بطاقة الإجمالي الكلي ───
                        _buildGrandTotalCard(pal, tt),
                        const SizedBox(height: 24),

                        // ─── جدول/قائمة الأيام ───
                        SectionTitle('التفعيلات اليومية'),
                        if (_dailyRows.isEmpty)
                          EmptyView(
                            icon: PhosphorIconsDuotone.calendarBlank,
                            title: 'لا توجد بيانات يومية',
                          )
                        else
                          _buildDailySection(pal),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildGrandTotalCard(PlatformPalette pal, TextTheme tt) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: pal.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(PhosphorIconsDuotone.lightning, color: pal.accent, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إجمالي التفعيلات هذا الشهر',
                    style: tt.bodySmall?.copyWith(color: pal.textMuted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$_grandTotal',
                    style: tt.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: pal.accent,
                      fontSize: 40,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailySection(PlatformPalette pal) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 32,
          headingRowHeight: 42,
          dataRowMinHeight: 38,
          dataRowMaxHeight: 48,
          columns: const [
            DataColumn(
              label: Text('اليوم', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              numeric: true,
            ),
            DataColumn(
              label: Text('إجمالي التفعيلات', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              numeric: true,
            ),
          ],
          rows: _dailyRows.map((row) {
            final day = row['day'] ?? 0;
            final total = row['total'] ?? 0;
            return DataRow(cells: [
              DataCell(Text(
                'يوم $day',
                style: TextStyle(fontSize: 12.5, color: pal.textMuted),
              )),
              DataCell(Text(
                '$total',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: total > 0 ? pal.info : pal.textMuted,
                ),
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
