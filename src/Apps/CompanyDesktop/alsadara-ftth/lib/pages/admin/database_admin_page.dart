/// صفحة إدارة قاعدة البيانات — CRUD ديناميكي لكل الجداول
/// تستخدم generic endpoint لقراءة/تعديل/حذف أي جدول تلقائياً
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../theme/energy_dashboard_theme.dart';
import '../../utils/responsive_helper.dart';
import '../super_admin/widgets/super_admin_widgets.dart';

class DatabaseAdminPage extends StatefulWidget {
  const DatabaseAdminPage({super.key});

  @override
  State<DatabaseAdminPage> createState() => _DatabaseAdminPageState();
}

class _DatabaseAdminPageState extends State<DatabaseAdminPage> {
  static const String baseUrl = 'https://api.ramzalsadara.tech/api';
  static const String apiKey = 'sadara-internal-2024-secure-key';

  // State
  List<Map<String, dynamic>> _tables = [];
  List<Map<String, dynamic>> _tableData = [];
  List<Map<String, dynamic>> _columns = [];
  Map<String, dynamic>? _pagination;
  String? _selectedTableName;
  String? _selectedCategory;
  bool _isLoadingTables = true;
  bool _isLoadingData = false;
  String? _error;
  String _searchQuery = '';
  int _currentPage = 1;

  // Cleanup state
  bool _showCleanupView = false;
  Map<String, dynamic>? _cleanupStats;
  bool _isLoadingStats = false;
  bool _isCleaningUp = false;
  Map<String, dynamic>? _lastCleanupReport;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // API Helpers
  // ═══════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> _apiGet(String path) async {
    try {
      final client = HttpClient()
        ..badCertificateCallback = (_, __, ___) => true;
      final request = await client.getUrl(Uri.parse('$baseUrl$path'));
      request.headers.set('X-Api-Key', apiKey);
      request.headers.set('Accept', 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) return json.decode(body);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _apiDelete(String path) async {
    try {
      final client = HttpClient()
        ..badCertificateCallback = (_, __, ___) => true;
      final request = await client.deleteUrl(Uri.parse('$baseUrl$path'));
      request.headers.set('X-Api-Key', apiKey);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return json.decode(body);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _apiPost(String path) async {
    try {
      final client = HttpClient()
        ..badCertificateCallback = (_, __, ___) => true;
      final request = await client.postUrl(Uri.parse('$baseUrl$path'));
      request.headers.set('X-Api-Key', apiKey);
      request.headers.set('Content-Type', 'application/json');
      request.contentLength = 0;
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return json.decode(body);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _apiPut(
      String path, Map<String, dynamic> data) async {
    try {
      final client = HttpClient()
        ..badCertificateCallback = (_, __, ___) => true;
      final request = await client.putUrl(Uri.parse('$baseUrl$path'));
      request.headers.set('X-Api-Key', apiKey);
      request.headers.set('Content-Type', 'application/json');
      request.write(json.encode(data));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return json.decode(body);
    } catch (_) {}
    return null;
  }

  // ═══════════════════════════════════════════════════════════════
  // Data Loading
  // ═══════════════════════════════════════════════════════════════

  Future<void> _loadTables() async {
    setState(() => _isLoadingTables = true);
    final result = await _apiGet('/databaseadmin/tables');
    if (mounted && result != null && result['success'] == true) {
      setState(() {
        _tables = List<Map<String, dynamic>>.from(result['data'] ?? []);
        _isLoadingTables = false;
      });
    } else if (mounted) {
      setState(() {
        _error = 'فشل تحميل الجداول';
        _isLoadingTables = false;
      });
    }
  }

  Future<void> _loadTableData(String tableName, {int page = 1}) async {
    setState(() {
      _isLoadingData = true;
      _currentPage = page;
      _error = null;
    });

    var path =
        '/databaseadmin/generic/$tableName?page=$page&pageSize=50';
    if (_searchQuery.isNotEmpty) {
      path += '&search=${Uri.encodeComponent(_searchQuery)}';
    }

    final result = await _apiGet(path);
    if (mounted && result != null && result['success'] == true) {
      setState(() {
        _tableData =
            List<Map<String, dynamic>>.from(result['data'] ?? []);
        _columns =
            List<Map<String, dynamic>>.from(result['columns'] ?? []);
        _pagination = result['pagination'];
        _isLoadingData = false;
      });
    } else if (mounted) {
      setState(() {
        _error = 'فشل تحميل البيانات';
        _isLoadingData = false;
      });
    }
  }

  Future<void> _deleteRecord(String id) async {
    if (_selectedTableName == null) return;

    final confirm = await EnergyDashboardTheme.confirmDialog(
      context,
      title: 'حذف السجل',
      message: 'هل أنت متأكد من حذف هذا السجل؟ هذا الإجراء لا يمكن التراجع عنه.',
      confirmLabel: 'حذف',
      confirmColor: EnergyDashboardTheme.danger,
    );

    if (confirm != true) return;

    final result =
        await _apiDelete('/databaseadmin/generic/$_selectedTableName/$id');
    if (mounted) {
      if (result?['success'] == true) {
        EnergyDashboardTheme.showSnack(
            context, 'تم الحذف بنجاح', EnergyDashboardTheme.success);
        _loadTableData(_selectedTableName!, page: _currentPage);
      } else {
        EnergyDashboardTheme.showSnack(
            context,
            result?['message'] ?? 'فشل الحذف',
            EnergyDashboardTheme.danger);
      }
    }
  }

  Future<void> _updateRecord(
      String id, Map<String, dynamic> data) async {
    if (_selectedTableName == null) return;

    final result =
        await _apiPut('/databaseadmin/generic/$_selectedTableName/$id', data);
    if (mounted) {
      if (result?['success'] == true) {
        EnergyDashboardTheme.showSnack(
            context, 'تم التحديث بنجاح', EnergyDashboardTheme.success);
        Navigator.pop(context);
        _loadTableData(_selectedTableName!, page: _currentPage);
      } else {
        EnergyDashboardTheme.showSnack(
            context,
            result?['message'] ?? 'فشل التحديث',
            EnergyDashboardTheme.danger);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Archive (Download Excel)
  // ═══════════════════════════════════════════════════════════════

  bool _isArchiving = false;

  Future<void> _archiveData(String category) async {
    final categoryLabels = {
      'accounting': 'المحاسبة',
      'attendance': 'الحضور والبصمات',
      'inventory': 'المخزون',
      'all': 'جميع العمليات',
    };

    setState(() => _isArchiving = true);

    try {
      final client = HttpClient()
        ..badCertificateCallback = (_, __, ___) => true;
      final request = await client.getUrl(
          Uri.parse('$baseUrl/databaseadmin/archive/$category'));
      request.headers.set('X-Api-Key', apiKey);
      final response = await request.close();

      if (response.statusCode == 200) {
        // حفظ الملف
        final bytes = await response.fold<List<int>>(
            <int>[], (prev, chunk) => prev..addAll(chunk));
        final dir = await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
        final timestamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
        final filePath =
            '${dir.path}/Sadara_Archive_${category}_$timestamp.xlsx';
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        if (mounted) {
          setState(() => _isArchiving = false);
          EnergyDashboardTheme.showSnack(
            context,
            'تم حفظ الأرشيف: ${categoryLabels[category]}',
            EnergyDashboardTheme.success,
          );
          // فتح الملف
          await OpenFilex.open(filePath);
        }
      } else {
        final body = await response.transform(utf8.decoder).join();
        if (mounted) {
          setState(() => _isArchiving = false);
          final parsed = json.decode(body);
          EnergyDashboardTheme.showSnack(
            context,
            parsed['message'] ?? 'فشل التصدير',
            EnergyDashboardTheme.danger,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isArchiving = false);
        EnergyDashboardTheme.showSnack(
          context,
          'خطأ في التصدير: $e',
          EnergyDashboardTheme.danger,
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Cleanup Operations
  // ═══════════════════════════════════════════════════════════════

  Future<void> _loadCleanupStats() async {
    setState(() => _isLoadingStats = true);
    final result = await _apiGet('/databaseadmin/cleanup-stats');
    if (mounted) {
      setState(() {
        _cleanupStats = result?['success'] == true
            ? result!['data'] as Map<String, dynamic>?
            : null;
        _isLoadingStats = false;
      });
    }
  }

  Future<void> _executeCleanup(String category) async {
    final categoryLabels = {
      'accounting': 'المحاسبة والعمليات المالية',
      'attendance': 'الحضور والبصمات والإجازات',
      'inventory': 'المخزون والمستودعات',
      'all': 'جميع العمليات (محاسبة + حضور + مخزون)',
    };

    final confirm = await EnergyDashboardTheme.confirmDialog(
      context,
      title: 'تصفير ${categoryLabels[category]}',
      message:
          'هل أنت متأكد؟ سيتم حذف جميع السجلات وتصفير الأرصدة.\nهذا الإجراء لا يمكن التراجع عنه!',
      confirmLabel: 'تصفير',
      confirmColor: EnergyDashboardTheme.danger,
    );

    if (confirm != true) return;

    // تأكيد مزدوج للتصفير الشامل
    if (category == 'all') {
      final doubleConfirm = await EnergyDashboardTheme.confirmDialog(
        context,
        title: 'تأكيد نهائي — تصفير شامل',
        message:
            'أنت على وشك حذف جميع العمليات المحاسبية والحضور والمخزون.\nهل تريد المتابعة؟',
        confirmLabel: 'نعم، صفّر الكل',
        confirmColor: EnergyDashboardTheme.danger,
      );
      if (doubleConfirm != true) return;
    }

    setState(() => _isCleaningUp = true);

    final endpoint = category == 'all'
        ? '/databaseadmin/cleanup-all'
        : '/databaseadmin/cleanup-$category';

    final result = await _apiPost(endpoint);

    if (mounted) {
      setState(() => _isCleaningUp = false);

      if (result?['success'] == true) {
        setState(() => _lastCleanupReport = result);
        EnergyDashboardTheme.showSnack(
          context,
          result?['message'] ?? 'تم التصفير بنجاح',
          EnergyDashboardTheme.success,
        );
        _loadCleanupStats(); // refresh stats
        _showCleanupReport(result!);
      } else {
        EnergyDashboardTheme.showSnack(
          context,
          result?['message'] ?? 'فشل التصفير',
          EnergyDashboardTheme.danger,
        );
      }
    }
  }

  void _showCleanupReport(Map<String, dynamic> result) {
    final report = result['report'];
    if (report == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EnergyDashboardTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded,
                color: EnergyDashboardTheme.success, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'تقرير التصفير',
                style: GoogleFonts.cairo(
                  color: EnergyDashboardTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
            maxHeight: 400,
          ),
          child: ListView(
            shrinkWrap: true,
            children: _buildReportItems(report),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: EnergyDashboardTheme.neonGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('حسناً', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildReportItems(dynamic report) {
    final items = <Widget>[];

    void addSection(String title, Map<String, dynamic> data) {
      items.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(
          title,
          style: GoogleFonts.cairo(
            color: EnergyDashboardTheme.neonBlue,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ));
      for (final entry in data.entries) {
        items.add(Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: EnergyDashboardTheme.bgPrimary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                entry.key,
                style: GoogleFonts.cairo(
                  color: EnergyDashboardTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (entry.value as num) > 0
                      ? EnergyDashboardTheme.danger.withOpacity(0.15)
                      : EnergyDashboardTheme.bgSecondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${entry.value}',
                  style: GoogleFonts.cairo(
                    color: (entry.value as num) > 0
                        ? EnergyDashboardTheme.danger
                        : EnergyDashboardTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ));
      }
    }

    if (report is Map<String, dynamic>) {
      // Check if it's a nested report (cleanup-all)
      if (report.containsKey('accounting') ||
          report.containsKey('attendance') ||
          report.containsKey('inventory')) {
        if (report['accounting'] != null) {
          addSection('المحاسبة',
              Map<String, dynamic>.from(report['accounting'] as Map));
        }
        if (report['attendance'] != null) {
          addSection('الحضور والبصمات',
              Map<String, dynamic>.from(report['attendance'] as Map));
        }
        if (report['inventory'] != null) {
          addSection('المخزون',
              Map<String, dynamic>.from(report['inventory'] as Map));
        }
      } else {
        // Single category report
        for (final entry in report.entries) {
          items.add(Container(
            margin: const EdgeInsets.only(bottom: 3),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: EnergyDashboardTheme.bgPrimary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  entry.key,
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: EnergyDashboardTheme.danger.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${entry.value}',
                    style: GoogleFonts.cairo(
                      color: EnergyDashboardTheme.danger,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ));
        }
      }
    }
    return items;
  }

  // ═══════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════

  List<String> get _categories {
    return _tables
        .map((t) => t['category']?.toString() ?? '')
        .toSet()
        .toList();
  }

  List<Map<String, dynamic>> get _filteredTables {
    if (_selectedCategory == null) return _tables;
    return _tables
        .where((t) => t['category'] == _selectedCategory)
        .toList();
  }

  Map<String, dynamic>? get _selectedTableInfo {
    if (_selectedTableName == null) return null;
    return _tables.firstWhere(
      (t) =>
          t['name']?.toString().toLowerCase() ==
          _selectedTableName!.toLowerCase(),
      orElse: () => {},
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Container(
      color: EnergyDashboardTheme.bgPrimary,
      child: _isLoadingTables
          ? const Center(
              child: CircularProgressIndicator(
                  color: EnergyDashboardTheme.neonGreen))
          : _showCleanupView
              ? _buildCleanupView()
              : r.isMobile
                  // Mobile: show sidebar or data view, not both
                  ? (_selectedTableName == null
                      ? _buildTablesSidebar()
                      : Column(
                          children: [
                            // Back button to table list
                            Container(
                              color: EnergyDashboardTheme.bgCard,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () =>
                                        setState(() => _selectedTableName = null),
                                    icon: const Icon(Icons.arrow_back_rounded,
                                        size: 18),
                                    label: Text('الجداول',
                                        style: GoogleFonts.cairo(fontSize: 12)),
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          EnergyDashboardTheme.neonGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(child: _buildDataView()),
                          ],
                        ))
                  : Row(
                      children: [
                        // Sidebar — Tables list
                        SizedBox(
                          width: 260,
                          child: _buildTablesSidebar(),
                        ),
                        // Divider
                        Container(
                          width: 1,
                          color: EnergyDashboardTheme.borderColor,
                        ),
                        // Main content — Data view
                        Expanded(child: _buildDataView()),
                      ],
                    ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Tables Sidebar
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTablesSidebar() {
    return Container(
      color: EnergyDashboardTheme.bgCard,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border(
                bottom:
                    BorderSide(color: EnergyDashboardTheme.borderColor),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.storage_rounded,
                    color: EnergyDashboardTheme.neonGreen, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'قاعدة البيانات',
                    style: GoogleFonts.cairo(
                      color: EnergyDashboardTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SACountBadge(
                  count: _tables.length,
                  color: EnergyDashboardTheme.neonBlue,
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    setState(() {
                      _showCleanupView = !_showCleanupView;
                      if (_showCleanupView) _loadCleanupStats();
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _showCleanupView
                          ? EnergyDashboardTheme.danger.withOpacity(0.2)
                          : EnergyDashboardTheme.bgSecondary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      _showCleanupView
                          ? Icons.table_chart_rounded
                          : Icons.delete_sweep_rounded,
                      size: 16,
                      color: _showCleanupView
                          ? EnergyDashboardTheme.danger
                          : EnergyDashboardTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Category chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _categoryChip(null, 'الكل'),
                  ..._categories.map((c) => _categoryChip(c, c)),
                ],
              ),
            ),
          ),
          // Tables list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _filteredTables.length,
              itemBuilder: (_, i) => _buildTableItem(_filteredTables[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(String? key, String label) {
    final isSelected = _selectedCategory == key;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: () => setState(() => _selectedCategory = key),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? EnergyDashboardTheme.neonGreen.withOpacity(0.2)
                : EnergyDashboardTheme.bgSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? EnergyDashboardTheme.neonGreen
                  : EnergyDashboardTheme.borderColor,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.cairo(
              color: isSelected
                  ? EnergyDashboardTheme.neonGreen
                  : EnergyDashboardTheme.textMuted,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableItem(Map<String, dynamic> table) {
    final name = table['name']?.toString() ?? '';
    final displayName = table['displayName']?.toString() ?? name;
    final category = table['category']?.toString() ?? '';
    final isSelected =
        _selectedTableName?.toLowerCase() == name.toLowerCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTableName = name;
            _searchQuery = '';
            _searchController.clear();
          });
          _loadTableData(name);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? EnergyDashboardTheme.neonGreen.withOpacity(0.1)
                : null,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(
                    color:
                        EnergyDashboardTheme.neonGreen.withOpacity(0.3))
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: (isSelected
                          ? EnergyDashboardTheme.neonGreen
                          : EnergyDashboardTheme.textMuted)
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.table_chart_rounded,
                  size: 14,
                  color: isSelected
                      ? EnergyDashboardTheme.neonGreen
                      : EnergyDashboardTheme.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: GoogleFonts.cairo(
                        color: isSelected
                            ? EnergyDashboardTheme.neonGreen
                            : EnergyDashboardTheme.textPrimary,
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$category / $name',
                      style: GoogleFonts.cairo(
                        color: EnergyDashboardTheme.textMuted,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Data View (Right panel)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDataView() {
    if (_selectedTableName == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app_rounded,
                size: 64,
                color: EnergyDashboardTheme.textMuted.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              'اختر جدولاً من القائمة',
              style: GoogleFonts.cairo(
                color: EnergyDashboardTheme.textMuted,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_tables.length} جدول متاح',
              style: GoogleFonts.cairo(
                color: EnergyDashboardTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    final info = _selectedTableInfo;

    return Column(
      children: [
        // Table header
        _buildDataHeader(info),
        // Search & filters
        _buildSearchBar(),
        // Data table
        Expanded(
          child: _isLoadingData
              ? const Center(
                  child: CircularProgressIndicator(
                      color: EnergyDashboardTheme.neonGreen))
              : _tableData.isEmpty
                  ? Center(
                      child: Text('لا توجد بيانات',
                          style: GoogleFonts.cairo(
                              color: EnergyDashboardTheme.textMuted)))
                  : _buildDataTable(),
        ),
        // Pagination
        if (_pagination != null) _buildPagination(),
      ],
    );
  }

  Widget _buildDataHeader(Map<String, dynamic>? info) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        border: Border(
          bottom: BorderSide(color: EnergyDashboardTheme.borderColor),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: EnergyDashboardTheme.neonBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.table_chart_rounded,
                color: EnergyDashboardTheme.neonBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info?['displayName']?.toString() ??
                      _selectedTableName ?? '',
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${info?['category'] ?? ''} / $_selectedTableName — ${_columns.length} عمود',
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (_pagination != null)
            SACountBadge(
              count: _pagination!['totalCount'] ?? 0,
              color: EnergyDashboardTheme.neonBlue,
            ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () =>
                _loadTableData(_selectedTableName!, page: _currentPage),
            icon: const Icon(Icons.refresh_rounded,
                color: EnergyDashboardTheme.neonGreen, size: 20),
            tooltip: 'تحديث',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: EnergyDashboardTheme.bgCard,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: EnergyDashboardTheme.bgPrimary,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: EnergyDashboardTheme.borderColor),
              ),
              child: TextField(
                controller: _searchController,
                onSubmitted: (_) {
                  _searchQuery = _searchController.text;
                  _loadTableData(_selectedTableName!, page: 1);
                },
                style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'بحث...',
                  hintStyle: GoogleFonts.cairo(
                      color: EnergyDashboardTheme.textMuted, fontSize: 12),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: EnergyDashboardTheme.textMuted, size: 18),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Columns info button
          IconButton(
            onPressed: _showColumnsDialog,
            icon: Icon(Icons.view_column_rounded,
                color: EnergyDashboardTheme.neonPurple, size: 20),
            tooltip: 'معلومات الأعمدة',
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Data Table
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDataTable() {
    final r = context.responsive;
    // Show fewer columns on mobile
    final maxCols = r.isMobile ? 3 : 8;
    final visibleColumns = _columns.take(maxCols).toList();
    final minRowWidth = r.isMobile ? visibleColumns.length * 120.0 + 80 : 0.0;

    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: r.isMobile ? minRowWidth : MediaQuery.of(context).size.width - 262,
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: EnergyDashboardTheme.bgSecondary,
                  child: Row(
                    children: [
                      ...visibleColumns.map((col) => Expanded(
                            child: Text(
                              col['clrName']?.toString() ?? col['name']?.toString() ?? '',
                              style: GoogleFonts.cairo(
                                color: EnergyDashboardTheme.textMuted,
                                fontSize: r.isMobile ? 9 : 10,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                      // Actions column
                      SizedBox(
                        width: 80,
                        child: Text(
                          'إجراءات',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(
                            color: EnergyDashboardTheme.textMuted,
                            fontSize: r.isMobile ? 9 : 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Rows
                ..._tableData.map((row) => _buildDataRow(row, visibleColumns)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataRow(
      Map<String, dynamic> row, List<Map<String, dynamic>> visibleColumns) {
    final id = row['Id']?.toString() ?? row['id']?.toString() ?? '';

    return InkWell(
      onTap: () => _showRecordDialog(row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: EnergyDashboardTheme.borderColor.withOpacity(0.3)),
          ),
        ),
        child: Row(
          children: [
            ...visibleColumns.map((col) {
              final colName = col['name']?.toString() ?? '';
              final value = row[colName];
              final displayValue = _formatValue(value);
              final type = col['type']?.toString() ?? '';

              Color textColor = EnergyDashboardTheme.textSecondary;
              if (type == 'Boolean') {
                textColor = value == true
                    ? EnergyDashboardTheme.success
                    : EnergyDashboardTheme.danger;
              }

              return Expanded(
                child: Text(
                  displayValue,
                  style: GoogleFonts.cairo(
                    color: textColor,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
            // Action buttons
            SizedBox(
              width: 80,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  InkWell(
                    onTap: () => _showEditDialog(row),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: EnergyDashboardTheme.neonBlue
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.edit_rounded,
                          color: EnergyDashboardTheme.neonBlue,
                          size: 14),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _deleteRecord(id),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color:
                            EnergyDashboardTheme.danger.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.delete_rounded,
                          color: EnergyDashboardTheme.danger, size: 14),
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

  String _formatValue(dynamic value) {
    if (value == null) return '-';
    if (value is bool) return value ? 'نعم' : 'لا';
    final str = value.toString();
    // Format dates
    if (str.length > 18 && str.contains('T')) {
      try {
        final dt = DateTime.parse(str).toLocal();
        return DateFormat('yyyy/MM/dd HH:mm').format(dt);
      } catch (_) {}
    }
    if (str.length > 50) return '${str.substring(0, 50)}...';
    return str;
  }

  // ═══════════════════════════════════════════════════════════════
  // Pagination
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPagination() {
    final totalPages = _pagination?['totalPages'] ?? 1;
    final totalCount = _pagination?['totalCount'] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        border: Border(
          top: BorderSide(color: EnergyDashboardTheme.borderColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'صفحة $_currentPage من $totalPages ($totalCount سجل)',
            style: GoogleFonts.cairo(
              color: EnergyDashboardTheme.textMuted,
              fontSize: 11,
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: _currentPage > 1
                    ? () => _loadTableData(_selectedTableName!,
                        page: _currentPage - 1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                color: EnergyDashboardTheme.neonGreen,
                disabledColor: EnergyDashboardTheme.textMuted,
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: EnergyDashboardTheme.neonGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_currentPage',
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.neonGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                onPressed: _currentPage < totalPages
                    ? () => _loadTableData(_selectedTableName!,
                        page: _currentPage + 1)
                    : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                color: EnergyDashboardTheme.neonGreen,
                disabledColor: EnergyDashboardTheme.textMuted,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Cleanup View
  // ═══════════════════════════════════════════════════════════════

  Widget _buildCleanupView() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: EnergyDashboardTheme.bgCard,
            border: Border(
              bottom: BorderSide(color: EnergyDashboardTheme.borderColor),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: EnergyDashboardTheme.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.delete_sweep_rounded,
                    color: EnergyDashboardTheme.danger, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تصفير العمليات',
                      style: GoogleFonts.cairo(
                        color: EnergyDashboardTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'حذف جميع السجلات التشغيلية وتصفير الأرصدة — لا يمكن التراجع',
                      style: GoogleFonts.cairo(
                        color: EnergyDashboardTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loadCleanupStats,
                icon: Icon(Icons.refresh_rounded,
                    color: EnergyDashboardTheme.neonGreen, size: 20),
                tooltip: 'تحديث الإحصائيات',
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _showCleanupView = false),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: EnergyDashboardTheme.bgSecondary,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: EnergyDashboardTheme.borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded,
                          size: 14, color: EnergyDashboardTheme.textMuted),
                      const SizedBox(width: 4),
                      Text('العودة للجداول',
                          style: GoogleFonts.cairo(
                              color: EnergyDashboardTheme.textMuted,
                              fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: _isLoadingStats
              ? const Center(
                  child: CircularProgressIndicator(
                      color: EnergyDashboardTheme.neonGreen))
              : _isCleaningUp
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                              color: EnergyDashboardTheme.danger),
                          const SizedBox(height: 16),
                          Text('جارٍ التصفير...',
                              style: GoogleFonts.cairo(
                                  color: EnergyDashboardTheme.textMuted,
                                  fontSize: 14)),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: EdgeInsets.all(
                          MediaQuery.of(context).size.width <= 600 ? 10 : 20),
                      child: MediaQuery.of(context).size.width <= 600
                          ? Column(
                              children: [
                                _buildCleanupCard(
                                  'accounting',
                                  'المحاسبة والعمليات المالية',
                                  Icons.account_balance_rounded,
                                  EnergyDashboardTheme.neonBlue,
                                  [
                                    'القيود المحاسبية وبنودها',
                                    'معاملات وتحصيلات الفنيين',
                                    'معاملات الوكلاء',
                                    'حركات الصندوق',
                                    'المصروفات ودفعات المصاريف',
                                    'الرواتب والخصومات والمكافآت',
                                    'تقارير التسوية اليومية',
                                    'طلبات السحب',
                                    'سجلات الاشتراكات',
                                    'تصفير: أرصدة الحسابات + الصناديق + الفنيين + الوكلاء',
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _buildCleanupCard(
                                  'attendance',
                                  'الحضور والبصمات والإجازات',
                                  Icons.fingerprint_rounded,
                                  EnergyDashboardTheme.neonPurple,
                                  [
                                    'سجلات الحضور والانصراف',
                                    'سجل تدقيق محاولات الحضور',
                                    'طلبات الإجازة',
                                    'أرصدة الإجازات',
                                    'تصفير: بصمات الأجهزة المسجلة',
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _buildCleanupCard(
                                  'inventory',
                                  'المخزون والمستودعات',
                                  Icons.warehouse_rounded,
                                  EnergyDashboardTheme.warning,
                                  [
                                    'صرف مواد الفنيين وبنودها',
                                    'أوامر الشراء وبنودها',
                                    'عمليات البيع وبنودها',
                                    'حركات المخزن',
                                    'تصفير: أرصدة المخزون',
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _buildCleanupAllCard(),
                              ],
                            )
                          : Column(
                              children: [
                                // Cleanup cards grid
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                        child: _buildCleanupCard(
                                      'accounting',
                                      'المحاسبة والعمليات المالية',
                                      Icons.account_balance_rounded,
                                      EnergyDashboardTheme.neonBlue,
                                      [
                                        'القيود المحاسبية وبنودها',
                                        'معاملات وتحصيلات الفنيين',
                                        'معاملات الوكلاء',
                                        'حركات الصندوق',
                                        'المصروفات ودفعات المصاريف',
                                        'الرواتب والخصومات والمكافآت',
                                        'تقارير التسوية اليومية',
                                        'طلبات السحب',
                                        'سجلات الاشتراكات',
                                        'تصفير: أرصدة الحسابات + الصناديق + الفنيين + الوكلاء',
                                      ],
                                    )),
                                    const SizedBox(width: 16),
                                    Expanded(
                                        child: _buildCleanupCard(
                                      'attendance',
                                      'الحضور والبصمات والإجازات',
                                      Icons.fingerprint_rounded,
                                      EnergyDashboardTheme.neonPurple,
                                      [
                                        'سجلات الحضور والانصراف',
                                        'سجل تدقيق محاولات الحضور',
                                        'طلبات الإجازة',
                                        'أرصدة الإجازات',
                                        'تصفير: بصمات الأجهزة المسجلة',
                                      ],
                                    )),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                        child: _buildCleanupCard(
                                      'inventory',
                                      'المخزون والمستودعات',
                                      Icons.warehouse_rounded,
                                      EnergyDashboardTheme.warning,
                                      [
                                        'صرف مواد الفنيين وبنودها',
                                        'أوامر الشراء وبنودها',
                                        'عمليات البيع وبنودها',
                                        'حركات المخزن',
                                        'تصفير: أرصدة المخزون',
                                      ],
                                    )),
                                    const SizedBox(width: 16),
                                    Expanded(
                                        child: _buildCleanupAllCard()),
                                  ],
                                ),
                              ],
                            ),
                    ),
        ),
      ],
    );
  }

  Widget _buildCleanupCard(
    String category,
    String title,
    IconData icon,
    Color color,
    List<String> items,
  ) {
    final stats = _cleanupStats?[category] as Map<String, dynamic>?;
    final totalRecords = stats?.values
            .whereType<int>()
            .fold<int>(0, (sum, v) => sum + v) ??
        0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: totalRecords > 0
                      ? color.withOpacity(0.15)
                      : EnergyDashboardTheme.bgSecondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$totalRecords سجل',
                  style: GoogleFonts.cairo(
                    color: totalRecords > 0
                        ? color
                        : EnergyDashboardTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Stats detail
          if (stats != null)
            ...stats.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        e.key,
                        style: GoogleFonts.cairo(
                          color: EnergyDashboardTheme.textMuted,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        '${e.value}',
                        style: GoogleFonts.cairo(
                          color: (e.value as num) > 0
                              ? color
                              : EnergyDashboardTheme.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )),
          const SizedBox(height: 8),
          // What will be deleted
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: EnergyDashboardTheme.bgPrimary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'سيتم حذف/تصفير:',
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ...items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ',
                              style: GoogleFonts.cairo(
                                  color: EnergyDashboardTheme.textMuted,
                                  fontSize: 10)),
                          Expanded(
                            child: Text(
                              item,
                              style: GoogleFonts.cairo(
                                color: EnergyDashboardTheme.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Action buttons
          Row(
            children: [
              // زر الأرشفة
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: totalRecords > 0 && !_isArchiving
                      ? () => _archiveData(category)
                      : null,
                  icon: Icon(
                      _isArchiving
                          ? Icons.hourglass_top_rounded
                          : Icons.archive_rounded,
                      size: 16),
                  label: Text(
                    _isArchiving ? 'جارٍ التصدير...' : 'أرشفة Excel',
                    style: GoogleFonts.cairo(fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EnergyDashboardTheme.neonGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: EnergyDashboardTheme.bgSecondary,
                    disabledForegroundColor: EnergyDashboardTheme.textMuted,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // زر التصفير
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: totalRecords > 0
                      ? () => _executeCleanup(category)
                      : null,
                  icon: Icon(Icons.delete_forever_rounded, size: 16),
                  label: Text(
                    totalRecords > 0 ? 'تصفير' : 'لا توجد بيانات',
                    style: GoogleFonts.cairo(fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EnergyDashboardTheme.danger,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: EnergyDashboardTheme.bgSecondary,
                    disabledForegroundColor: EnergyDashboardTheme.textMuted,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCleanupAllCard() {
    final allTotal = _cleanupStats?.values
            .whereType<Map<String, dynamic>>()
            .expand((m) => m.values.whereType<int>())
            .fold<int>(0, (sum, v) => sum + v) ??
        0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: EnergyDashboardTheme.danger.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: EnergyDashboardTheme.danger.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: EnergyDashboardTheme.danger.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.warning_amber_rounded,
                    color: EnergyDashboardTheme.danger, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'تصفير شامل',
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.danger,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: EnergyDashboardTheme.danger.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$allTotal سجل',
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Warning
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: EnergyDashboardTheme.danger.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: EnergyDashboardTheme.danger.withOpacity(0.2),
              ),
            ),
            child: Column(
              children: [
                Icon(Icons.dangerous_rounded,
                    color: EnergyDashboardTheme.danger, size: 32),
                const SizedBox(height: 8),
                Text(
                  'تحذير: هذا الإجراء سيحذف جميع العمليات',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'سيتم تصفير كل البيانات المحاسبية والحضور والبصمات والمخزون دفعة واحدة. يتطلب تأكيد مزدوج.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Summary
          ..._cleanupStats?.entries.map((category) {
                final catTotal =
                    (category.value as Map<String, dynamic>?)?.values
                            .whereType<int>()
                            .fold<int>(0, (s, v) => s + v) ??
                        0;
                final labels = {
                  'accounting': 'المحاسبة',
                  'attendance': 'الحضور',
                  'inventory': 'المخزون',
                };
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        labels[category.key] ?? category.key,
                        style: GoogleFonts.cairo(
                          color: EnergyDashboardTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        '$catTotal سجل',
                        style: GoogleFonts.cairo(
                          color: catTotal > 0
                              ? EnergyDashboardTheme.danger
                              : EnergyDashboardTheme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList() ??
              [],
          const SizedBox(height: 16),
          // أرشفة شاملة أولاً
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: allTotal > 0 && !_isArchiving
                  ? () => _archiveData('all')
                  : null,
              icon: Icon(
                  _isArchiving
                      ? Icons.hourglass_top_rounded
                      : Icons.archive_rounded,
                  size: 18),
              label: Text(
                _isArchiving
                    ? 'جارٍ تصدير الأرشيف...'
                    : 'أرشفة الكل كـ Excel',
                style: GoogleFonts.cairo(
                    fontSize: 13, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: EnergyDashboardTheme.neonGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: EnergyDashboardTheme.bgSecondary,
                disabledForegroundColor: EnergyDashboardTheme.textMuted,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // تصفير شامل
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  allTotal > 0 ? () => _executeCleanup('all') : null,
              icon: Icon(Icons.delete_forever_rounded, size: 18),
              label: Text(
                allTotal > 0 ? 'تصفير جميع العمليات' : 'لا توجد بيانات',
                style: GoogleFonts.cairo(
                    fontSize: 13, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: EnergyDashboardTheme.danger,
                foregroundColor: Colors.white,
                disabledBackgroundColor: EnergyDashboardTheme.bgSecondary,
                disabledForegroundColor: EnergyDashboardTheme.textMuted,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Dialogs
  // ═══════════════════════════════════════════════════════════════

  void _showRecordDialog(Map<String, dynamic> row) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EnergyDashboardTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.info_rounded,
                color: EnergyDashboardTheme.neonBlue, size: 20),
            const SizedBox(width: 8),
            Text('تفاصيل السجل',
                style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
            maxHeight: 400,
          ),
          child: ListView(
            shrinkWrap: true,
            children: row.entries.map((e) {
              final isMobile = MediaQuery.of(context).size.width <= 600;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.key,
                                  style: GoogleFonts.cairo(
                                    color: EnergyDashboardTheme.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(
                                      text: e.value?.toString() ?? ''));
                                  EnergyDashboardTheme.showSnack(ctx,
                                      'تم النسخ', EnergyDashboardTheme.success);
                                },
                                child: Icon(Icons.copy_rounded,
                                    size: 14,
                                    color: EnergyDashboardTheme.textMuted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            _formatValue(e.value),
                            style: GoogleFonts.cairo(
                              color: EnergyDashboardTheme.textPrimary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 140,
                            child: Text(
                              e.key,
                              style: GoogleFonts.cairo(
                                color: EnergyDashboardTheme.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              _formatValue(e.value),
                              style: GoogleFonts.cairo(
                                color: EnergyDashboardTheme.textPrimary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(
                                  text: e.value?.toString() ?? ''));
                              EnergyDashboardTheme.showSnack(ctx,
                                  'تم النسخ', EnergyDashboardTheme.success);
                            },
                            icon: Icon(Icons.copy_rounded,
                                size: 14,
                                color: EnergyDashboardTheme.textMuted),
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إغلاق',
                style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textMuted)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showEditDialog(row);
            },
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: Text('تعديل', style: GoogleFonts.cairo()),
            style: ElevatedButton.styleFrom(
              backgroundColor: EnergyDashboardTheme.neonBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> row) {
    final id = row['Id']?.toString() ?? row['id']?.toString() ?? '';
    final controllers = <String, TextEditingController>{};
    final editableEntries = row.entries.where((e) {
      final key = e.key.toLowerCase();
      return key != 'id'; // Don't edit PK
    }).toList();

    for (final e in editableEntries) {
      controllers[e.key] =
          TextEditingController(text: e.value?.toString() ?? '');
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EnergyDashboardTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.edit_rounded,
                color: EnergyDashboardTheme.neonBlue, size: 20),
            const SizedBox(width: 8),
            Text('تعديل السجل',
                style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
            maxHeight: 400,
          ),
          child: ListView(
            shrinkWrap: true,
            children: editableEntries.map((e) {
              final isMobile = MediaQuery.of(context).size.width <= 600;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.key,
                            style: GoogleFonts.cairo(
                              color: EnergyDashboardTheme.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: controllers[e.key],
                            style: GoogleFonts.cairo(
                                color: EnergyDashboardTheme.textPrimary,
                                fontSize: 12),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: EnergyDashboardTheme.bgPrimary,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                    color: EnergyDashboardTheme.borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                    color: EnergyDashboardTheme.borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: EnergyDashboardTheme.neonGreen),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          e.key,
                          style: GoogleFonts.cairo(
                            color: EnergyDashboardTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: controllers[e.key],
                        style: GoogleFonts.cairo(
                            color: EnergyDashboardTheme.textPrimary,
                            fontSize: 12),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: EnergyDashboardTheme.bgPrimary,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color:
                                    EnergyDashboardTheme.borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color:
                                    EnergyDashboardTheme.borderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color:
                                    EnergyDashboardTheme.neonGreen),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء',
                style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textMuted)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final updatedData = <String, dynamic>{};
              for (final entry in editableEntries) {
                final newValue = controllers[entry.key]?.text;
                final oldValue = entry.value?.toString() ?? '';
                if (newValue != oldValue) {
                  // Try to preserve types
                  if (entry.value is bool) {
                    updatedData[entry.key] =
                        newValue == 'true' || newValue == 'نعم';
                  } else if (entry.value is int) {
                    updatedData[entry.key] = int.tryParse(newValue ?? '');
                  } else if (entry.value is double) {
                    updatedData[entry.key] =
                        double.tryParse(newValue ?? '');
                  } else {
                    updatedData[entry.key] = newValue;
                  }
                }
              }
              if (updatedData.isEmpty) {
                Navigator.pop(ctx);
                return;
              }
              _updateRecord(id, updatedData);
            },
            icon: const Icon(Icons.save_rounded, size: 16),
            label: Text('حفظ', style: GoogleFonts.cairo()),
            style: ElevatedButton.styleFrom(
              backgroundColor: EnergyDashboardTheme.neonGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );

    // Cleanup
    // Controllers will be disposed when dialog closes
  }

  void _showColumnsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EnergyDashboardTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.view_column_rounded,
                color: EnergyDashboardTheme.neonPurple, size: 20),
            const SizedBox(width: 8),
            Text('أعمدة الجدول (${_columns.length})',
                style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
            maxHeight: 300,
          ),
          child: ListView(
            shrinkWrap: true,
            children: _columns.map((col) {
              final isPK = col['isPrimaryKey'] == true;
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isPK
                      ? EnergyDashboardTheme.neonGreen.withOpacity(0.05)
                      : null,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isPK
                        ? EnergyDashboardTheme.neonGreen.withOpacity(0.2)
                        : EnergyDashboardTheme.borderColor
                            .withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    if (isPK)
                      Icon(Icons.key_rounded,
                          color: EnergyDashboardTheme.neonGreen, size: 14)
                    else
                      Icon(Icons.circle,
                          color: EnergyDashboardTheme.textMuted, size: 6),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        col['clrName']?.toString() ?? '',
                        style: GoogleFonts.cairo(
                          color: EnergyDashboardTheme.textPrimary,
                          fontSize: 12,
                          fontWeight:
                              isPK ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color:
                            EnergyDashboardTheme.neonBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        col['type']?.toString() ?? '',
                        style: GoogleFonts.cairo(
                          color: EnergyDashboardTheme.neonBlue,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    if (col['isNullable'] == true)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          '?',
                          style: GoogleFonts.cairo(
                            color: EnergyDashboardTheme.warning,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إغلاق',
                style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textMuted)),
          ),
        ],
      ),
    );
  }
}
