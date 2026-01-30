/// صفحة إدارة قاعدة البيانات VPS
/// تعرض جميع الجداول مع إمكانية العرض والتعديل والحذف
library;

import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import '../super_admin/admin_theme.dart';

class DatabaseAdminPage extends StatefulWidget {
  const DatabaseAdminPage({super.key});

  @override
  State<DatabaseAdminPage> createState() => _DatabaseAdminPageState();
}

class _DatabaseAdminPageState extends State<DatabaseAdminPage> {
  // إعدادات الاتصال - نفس طريقة vps_data_manager_page
  static const String baseUrl = 'http://72.61.183.61/api';
  static const String apiKey = 'sadara-internal-2024-secure-key';

  List<Map<String, dynamic>> _tables = [];
  Map<String, dynamic>? _selectedTable;
  List<Map<String, dynamic>> _tableData = [];
  Map<String, dynamic>? _pagination;
  Map<String, dynamic>? _stats;

  bool _isLoadingTables = true;
  bool _isLoadingData = false;
  String? _errorMessage;
  String? _errorDetails;
  String _searchQuery = '';
  int _currentPage = 1;
  bool _showGeneralStats = true; // عرض الإحصائيات العامة افتراضياً

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTables();
    _loadStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTables() async {
    debugPrint('🔍 _loadTables: بدء تحميل الجداول...');
    if (!mounted) return;
    setState(() {
      _isLoadingTables = true;
      _errorMessage = null;
      _errorDetails = null;
    });

    try {
      final client = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      final request =
          await client.getUrl(Uri.parse('$baseUrl/databaseadmin/tables'));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      request.headers.set('X-Api-Key', apiKey);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      debugPrint('🔍 Response status: ${response.statusCode}');
      debugPrint('🔍 Response body: $responseBody');

      if (response.statusCode == 200) {
        final decoded = json.decode(responseBody);
        if (!mounted) return;
        if (decoded['success'] == true) {
          setState(() {
            _tables = List<Map<String, dynamic>>.from(decoded['data']);
            _isLoadingTables = false;
          });
          debugPrint('✅ تم تحميل ${_tables.length} جدول');
        } else {
          setState(() {
            _errorMessage = decoded['message'] ?? 'فشل في تحميل الجداول';
            _isLoadingTables = false;
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'خطأ في الاتصال: ${response.statusCode}';
          _errorDetails = responseBody;
          _isLoadingTables = false;
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'فشل الاتصال بالخادم';
        _errorDetails = e.toString();
        _isLoadingTables = false;
      });
    }
  }

  Future<void> _loadStats() async {
    try {
      final client = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      final request =
          await client.getUrl(Uri.parse('$baseUrl/databaseadmin/stats'));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('X-Api-Key', apiKey);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final decoded = json.decode(responseBody);
        if (decoded['success'] == true && mounted) {
          setState(() {
            _stats = decoded['data'];
          });
        }
      }
    } catch (e) {
      debugPrint('خطأ في تحميل الإحصائيات: $e');
    }
  }

  Future<void> _loadTableData(String tableName, {int page = 1}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingData = true;
      _currentPage = page;
    });

    try {
      String url =
          '$baseUrl/databaseadmin/table/$tableName?page=$page&pageSize=50';
      if (_searchQuery.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(_searchQuery)}';
      }

      final client = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('X-Api-Key', apiKey);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final decoded = json.decode(responseBody);
        if (decoded['success'] == true && mounted) {
          setState(() {
            _tableData = List<Map<String, dynamic>>.from(decoded['data']);
            _pagination = decoded['pagination'];
            _isLoadingData = false;
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'خطأ: ${response.statusCode}';
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoadingData = false;
      });
    }
  }

  Future<void> _deleteRecord(String tableName, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AdminTheme.surfaceColor,
        title: const Text('تأكيد الحذف',
            style: TextStyle(color: AdminTheme.textPrimary)),
        content: const Text('هل أنت متأكد من حذف هذا السجل؟',
            style: TextStyle(color: AdminTheme.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final client = HttpClient()
          ..badCertificateCallback = (cert, host, port) => true;

        final request = await client.deleteUrl(
            Uri.parse('$baseUrl/databaseadmin/table/$tableName/$id'));
        request.headers.set('Content-Type', 'application/json');
        request.headers.set('X-Api-Key', apiKey);

        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();

        if (response.statusCode == 200) {
          final decoded = json.decode(responseBody);
          if (decoded['success'] == true) {
            _showSnackBar('تم الحذف بنجاح', isError: false);
            _loadTableData(tableName, page: _currentPage);
          } else {
            _showSnackBar(decoded['message'] ?? 'فشل الحذف', isError: true);
          }
        } else {
          _showSnackBar('خطأ: ${response.statusCode}', isError: true);
        }
      } catch (e) {
        _showSnackBar(e.toString(), isError: true);
      }
    }
  }

  void _showEditDialog(String tableName, Map<String, dynamic> record) {
    final controllers = <String, TextEditingController>{};
    // استبعاد الحقول غير القابلة للتعديل (camelCase و PascalCase)
    final nonEditableFields = [
      'id',
      'Id',
      'createdAt',
      'CreatedAt',
      'updatedAt',
      'UpdatedAt',
      'passwordHash',
      'PasswordHash',
      'refreshToken',
      'RefreshToken',
      'refreshTokenExpiryTime',
      'RefreshTokenExpiryTime',
      'lastLoginAt',
      'LastLoginAt'
    ];
    final editableFields =
        record.keys.where((k) => !nonEditableFields.contains(k)).toList();

    for (var field in editableFields) {
      controllers[field] =
          TextEditingController(text: record[field]?.toString() ?? '');
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AdminTheme.surfaceColor,
        title:
            Text('تعديل سجل', style: TextStyle(color: AdminTheme.textPrimary)),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: editableFields.map((field) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: controllers[field],
                    style: const TextStyle(color: AdminTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: field,
                      labelStyle: const TextStyle(color: AdminTheme.textMuted),
                      filled: true,
                      fillColor: AdminTheme.backgroundColor,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final data = <String, dynamic>{};
              for (var entry in controllers.entries) {
                var value = entry.value.text;
                // تحويل اسم الحقل إلى camelCase
                String fieldName = entry.key;
                if (fieldName.isNotEmpty &&
                    fieldName[0] == fieldName[0].toUpperCase()) {
                  fieldName =
                      fieldName[0].toLowerCase() + fieldName.substring(1);
                }
                // تحويل القيم المنطقية
                if (value.toLowerCase() == 'true') {
                  data[fieldName] = true;
                } else if (value.toLowerCase() == 'false') {
                  data[fieldName] = false;
                } else {
                  data[fieldName] = value;
                }
              }

              try {
                final client = HttpClient()
                  ..badCertificateCallback = (cert, host, port) => true;

                final recordId = record['id'] ?? record['Id'];
                final url = '$baseUrl/databaseadmin/table/$tableName/$recordId';
                debugPrint('📤 URL: $url');
                debugPrint('📤 Data: $data');

                final request = await client.putUrl(Uri.parse(url));
                request.headers
                    .set('Content-Type', 'application/json; charset=utf-8');
                request.headers.set('X-Api-Key', apiKey);

                final jsonData = json.encode(data);
                final bytes = utf8.encode(jsonData);
                request.headers.set('Content-Length', bytes.length.toString());
                request.add(bytes);

                final response = await request.close();
                final responseBody =
                    await response.transform(utf8.decoder).join();

                debugPrint(
                    '📥 Response: ${response.statusCode} - $responseBody');

                if (response.statusCode == 200) {
                  final decoded = json.decode(responseBody);
                  if (decoded['success'] == true) {
                    if (context.mounted) Navigator.pop(context);
                    _showSnackBar('تم التحديث بنجاح', isError: false);
                    // إعادة تحميل البيانات
                    await _loadTableData(tableName, page: _currentPage);
                  } else {
                    _showSnackBar(decoded['message'] ?? 'فشل التحديث',
                        isError: true);
                  }
                } else {
                  // محاولة قراءة رسالة الخطأ من الاستجابة
                  String errorMsg = 'خطأ: ${response.statusCode}';
                  try {
                    final decoded = json.decode(responseBody);
                    if (decoded['message'] != null) {
                      errorMsg = decoded['message'];
                    }
                  } catch (_) {}
                  debugPrint('❌ خطأ API: $responseBody');
                  _showSnackBar(errorMsg, isError: true);
                }
              } catch (e) {
                debugPrint('❌ Exception: $e');
                _showSnackBar(e.toString(), isError: true);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AdminTheme.primaryColor),
            child: const Text('حفظ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    // تنظيف الـ controllers عند إغلاق الحوار
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // تجميع الجداول حسب الفئة
  Map<String, List<Map<String, dynamic>>> get _groupedTables {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (var table in _tables) {
      final category = table['category'] as String? ?? 'Other';
      grouped.putIfAbsent(category, () => []).add(table);
    }
    return grouped;
  }

  // ترتيب الفئات - يطابق الفئات الفعلية من API
  List<String> get _categoryOrder => [
        'Core',
        'Commerce',
        'System',
        'Company',
        'Permissions',
        'Services',
        'CitizenPortal',
      ];

  // الحصول على جميع الفئات (المرتبة + أي فئات جديدة)
  List<String> _getAllCategories() {
    final allCategories = <String>[];
    // أضف الفئات المرتبة أولاً
    for (var cat in _categoryOrder) {
      if (_groupedTables.containsKey(cat)) {
        allCategories.add(cat);
      }
    }
    // أضف أي فئات جديدة غير موجودة في الترتيب
    for (var cat in _groupedTables.keys) {
      if (!allCategories.contains(cat)) {
        allCategories.add(cat);
      }
    }
    return allCategories;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.backgroundColor,
      body: Column(
        children: [
          // شريط التبويبات العلوي
          _buildTopTabBar(),

          // المحتوى الرئيسي
          Expanded(
            child: _showGeneralStats
                ? _buildGeneralStatsView()
                : (_selectedTable == null
                    ? _buildWelcomeView()
                    : _buildDataView()),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTabBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AdminTheme.surfaceColor,
        border: Border(bottom: BorderSide(color: AdminTheme.borderColor)),
      ),
      child: Row(
        children: [
          // التبويبات مع القوائم المنسدلة - تملأ المساحة المتاحة
          Expanded(
            child: _isLoadingTables
                ? const Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      // تبويب عام
                      _buildGeneralTab(),
                      // باقي التبويبات
                      ..._getAllCategories()
                          .map((category) => _buildCategoryDropdown(category))
                          .toList(),
                    ],
                  ),
          ),

          const SizedBox(width: 8),

          // زر التحديث
          IconButton(
            icon: const Icon(Icons.refresh,
                color: AdminTheme.textMuted, size: 20),
            onPressed: () {
              _loadTables();
              _loadStats();
              if (_selectedTable != null) {
                _loadTableData(_selectedTable!['name']);
              }
            },
            tooltip: 'تحديث',
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralTab() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showGeneralStats = true;
          _selectedTable = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _showGeneralStats
              ? AdminTheme.primaryColor.withOpacity(0.1)
              : AdminTheme.backgroundColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _showGeneralStats
                ? AdminTheme.primaryColor.withOpacity(0.3)
                : AdminTheme.borderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dashboard,
              size: 14,
              color: _showGeneralStats
                  ? AdminTheme.primaryColor
                  : AdminTheme.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              'عام',
              style: TextStyle(
                color: _showGeneralStats
                    ? AdminTheme.primaryColor
                    : AdminTheme.textPrimary,
                fontWeight:
                    _showGeneralStats ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralStatsView() {
    if (_isLoadingTables) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AdminTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.analytics,
                    color: AdminTheme.primaryColor, size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'إحصائيات قاعدة البيانات',
                    style: TextStyle(
                      color: AdminTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${_tables.length} جدول',
                    style: TextStyle(color: AdminTheme.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // بطاقات الجداول مقسمة حسب الفئات
          ..._getAllCategories()
              .map((category) => _buildCategorySection(category))
              .toList(),
        ],
      ),
    );
  }

  Widget _buildCategorySection(String category) {
    final tables = _groupedTables[category] ?? [];
    if (tables.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // عنوان الفئة
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getCategoryColor(category).withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border:
                Border.all(color: _getCategoryColor(category).withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_getCategoryIcon(category),
                  size: 14, color: _getCategoryColor(category)),
              const SizedBox(width: 6),
              Text(
                _getCategoryName(category),
                style: TextStyle(
                  color: _getCategoryColor(category),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: _getCategoryColor(category).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${tables.length}',
                  style: TextStyle(
                    color: _getCategoryColor(category),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // بطاقات الجداول
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              tables.map((table) => _buildTableCard(table, category)).toList(),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTableCard(Map<String, dynamic> table, String category) {
    final color = _getCategoryColor(category);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTable = table;
            _showGeneralStats = false;
            _searchQuery = '';
            _searchController.clear();
          });
          _loadTableData(table['name']);
        },
        child: Container(
          width: 140,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AdminTheme.surfaceColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AdminTheme.borderColor),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  _getIconData(table['icon']),
                  size: 14,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  table['displayName'] ?? table['name'],
                  style: const TextStyle(
                    color: AdminTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Core':
        return Colors.blue;
      case 'Commerce':
        return Colors.orange;
      case 'System':
        return Colors.purple;
      case 'Company':
        return Colors.teal;
      case 'Permissions':
        return Colors.red;
      case 'Services':
        return Colors.green;
      case 'CitizenPortal':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  Widget _buildCategoryDropdown(String category) {
    final tables = _groupedTables[category] ?? [];
    final isCurrentCategory = _selectedTable != null &&
        tables.any((t) => t['name'] == _selectedTable!['name']);

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: PopupMenuButton<Map<String, dynamic>>(
        offset: const Offset(0, 45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: AdminTheme.surfaceColor,
        onSelected: (table) {
          setState(() {
            _selectedTable = table;
            _showGeneralStats = false;
            _searchQuery = '';
            _searchController.clear();
          });
          _loadTableData(table['name']);
        },
        itemBuilder: (context) => tables.map((table) {
          final isSelected = _selectedTable?['name'] == table['name'];
          return PopupMenuItem<Map<String, dynamic>>(
            value: table,
            child: Row(
              children: [
                Icon(
                  _getIconData(table['icon']),
                  size: 18,
                  color: isSelected
                      ? AdminTheme.primaryColor
                      : AdminTheme.textMuted,
                ),
                const SizedBox(width: 10),
                Text(
                  table['displayName'],
                  style: TextStyle(
                    color: isSelected
                        ? AdminTheme.primaryColor
                        : AdminTheme.textPrimary,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Icon(Icons.check, size: 16, color: AdminTheme.primaryColor),
                ],
              ],
            ),
          );
        }).toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isCurrentCategory
                ? AdminTheme.primaryColor.withOpacity(0.1)
                : AdminTheme.backgroundColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isCurrentCategory
                  ? AdminTheme.primaryColor.withOpacity(0.3)
                  : AdminTheme.borderColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getCategoryIcon(category),
                size: 14,
                color: isCurrentCategory
                    ? AdminTheme.primaryColor
                    : AdminTheme.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                _getCategoryName(category),
                style: TextStyle(
                  color: isCurrentCategory
                      ? AdminTheme.primaryColor
                      : AdminTheme.textPrimary,
                  fontWeight:
                      isCurrentCategory ? FontWeight.bold : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: isCurrentCategory
                    ? AdminTheme.primaryColor
                    : AdminTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Core':
        return Icons.diamond;
      case 'Commerce':
        return Icons.shopping_bag;
      case 'System':
        return Icons.settings;
      case 'Company':
        return Icons.business;
      case 'Permissions':
        return Icons.security;
      case 'Services':
        return Icons.miscellaneous_services;
      case 'CitizenPortal':
        return Icons.people;
      default:
        return Icons.folder;
    }
  }

  Widget _buildWelcomeView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AdminTheme.primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.touch_app,
                size: 60, color: AdminTheme.primaryColor.withOpacity(0.7)),
          ),
          const SizedBox(height: 24),
          const Text(
            'اختر فئة من الأعلى ثم حدد الجدول',
            style: TextStyle(
              color: AdminTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'يمكنك عرض وتعديل وحذف البيانات من أي جدول',
            style: TextStyle(color: AdminTheme.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 40),

          // عرض الإحصائيات
          if (_stats != null) _buildStatsGrid(),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final statItems = [
      {
        'label': 'المستخدمين',
        'value': _stats!['users'],
        'icon': Icons.person,
        'color': Colors.blue
      },
      {
        'label': 'الشركات',
        'value': _stats!['companies'],
        'icon': Icons.business,
        'color': Colors.purple
      },
      {
        'label': 'الطلبات',
        'value': _stats!['orders'],
        'icon': Icons.shopping_cart,
        'color': Colors.orange
      },
      {
        'label': 'المدن',
        'value': _stats!['cities'],
        'icon': Icons.location_city,
        'color': Colors.green
      },
      {
        'label': 'المواطنين',
        'value': _stats!['citizens'],
        'icon': Icons.badge,
        'color': Colors.teal
      },
      {
        'label': 'تذاكر الدعم',
        'value': _stats!['supportTickets'],
        'icon': Icons.support_agent,
        'color': Colors.red
      },
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: statItems.map((item) {
        return Container(
          width: 180,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AdminTheme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AdminTheme.borderColor),
          ),
          child: Column(
            children: [
              Icon(item['icon'] as IconData,
                  size: 32, color: item['color'] as Color),
              const SizedBox(height: 8),
              Text(
                '${item['value']}',
                style: const TextStyle(
                  color: AdminTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                item['label'] as String,
                style:
                    const TextStyle(color: AdminTheme.textMuted, fontSize: 12),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDataView() {
    return Column(
      children: [
        // شريط الأدوات
        _buildToolbar(),

        // الجدول
        Expanded(
          child: _isLoadingData
              ? const Center(child: CircularProgressIndicator())
              : _tableData.isEmpty
                  ? const Center(
                      child: Text('لا توجد بيانات',
                          style: TextStyle(color: AdminTheme.textMuted)),
                    )
                  : _buildDataTable(),
        ),

        // شريط الصفحات
        if (_pagination != null) _buildPagination(),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AdminTheme.backgroundColor,
      ),
      child: Row(
        children: [
          // اسم الجدول المحدد
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AdminTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AdminTheme.primaryColor.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_getIconData(_selectedTable!['icon']),
                    color: AdminTheme.primaryColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  _selectedTable!['displayName'],
                  style: const TextStyle(
                    color: AdminTheme.primaryColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (_pagination != null)
            Text(
              '${_pagination!['totalCount']} سجل',
              style: const TextStyle(color: AdminTheme.textMuted, fontSize: 13),
            ),
          const Spacer(),

          // حقل البحث
          SizedBox(
            width: 280,
            child: TextField(
              controller: _searchController,
              style:
                  const TextStyle(color: AdminTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'بحث...',
                hintStyle: const TextStyle(color: AdminTheme.textMuted),
                prefixIcon: const Icon(Icons.search,
                    color: AdminTheme.textMuted, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: AdminTheme.textMuted),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          _loadTableData(_selectedTable!['name']);
                        },
                      )
                    : null,
                filled: true,
                fillColor: AdminTheme.backgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (value) {
                setState(() => _searchQuery = value);
                _loadTableData(_selectedTable!['name']);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable() {
    if (_tableData.isEmpty) return const SizedBox();

    final columns = _tableData.first.keys.toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AdminTheme.surfaceColor),
          dataRowColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return AdminTheme.primaryColor.withOpacity(0.05);
            }
            return Colors.transparent;
          }),
          columns: [
            const DataColumn(
                label: Text('إجراءات',
                    style: TextStyle(
                        color: AdminTheme.textPrimary,
                        fontWeight: FontWeight.bold))),
            ...columns.map((col) => DataColumn(
                  label: Text(
                    col,
                    style: const TextStyle(
                        color: AdminTheme.textPrimary,
                        fontWeight: FontWeight.bold),
                  ),
                )),
          ],
          rows: _tableData.map((row) {
            return DataRow(
              cells: [
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        color: AdminTheme.primaryColor,
                        tooltip: 'تعديل',
                        onPressed: () =>
                            _showEditDialog(_selectedTable!['name'], row),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 18),
                        color: Colors.red,
                        tooltip: 'حذف',
                        onPressed: () => _deleteRecord(
                            _selectedTable!['name'], row['id'].toString()),
                      ),
                    ],
                  ),
                ),
                ...columns.map((col) {
                  final value = row[col];
                  return DataCell(
                    _buildCellContent(col, value),
                  );
                }),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCellContent(String column, dynamic value) {
    if (value == null) {
      return const Text('-', style: TextStyle(color: AdminTheme.textMuted));
    }

    // عرض القيم المنطقية كشارات
    if (value is bool) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: value
              ? Colors.green.withOpacity(0.1)
              : Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          value ? 'نعم' : 'لا',
          style: TextStyle(
            color: value ? Colors.green : Colors.red,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    // تنسيق التواريخ
    if (column.toLowerCase().contains('at') ||
        column.toLowerCase().contains('date')) {
      try {
        final date = DateTime.parse(value.toString());
        return Text(
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          style: const TextStyle(color: AdminTheme.textPrimary, fontSize: 13),
        );
      } catch (_) {}
    }

    // عرض الحالات بألوان
    if (column.toLowerCase() == 'status' || column.toLowerCase() == 'role') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AdminTheme.primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          value.toString(),
          style: const TextStyle(
            color: AdminTheme.primaryColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    // القيم العادية
    String text = value.toString();
    if (text.length > 50) {
      text = '${text.substring(0, 50)}...';
    }

    return Text(
      text,
      style: const TextStyle(color: AdminTheme.textPrimary, fontSize: 13),
    );
  }

  Widget _buildPagination() {
    final totalPages = _pagination!['totalPages'] as int;
    final currentPage = _pagination!['page'] as int;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminTheme.surfaceColor,
        border: Border(top: BorderSide(color: AdminTheme.borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.first_page),
            onPressed: currentPage > 1
                ? () => _loadTableData(_selectedTable!['name'], page: 1)
                : null,
            color: AdminTheme.primaryColor,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: currentPage > 1
                ? () => _loadTableData(_selectedTable!['name'],
                    page: currentPage - 1)
                : null,
            color: AdminTheme.primaryColor,
          ),
          const SizedBox(width: 16),
          Text(
            'صفحة $currentPage من $totalPages',
            style: const TextStyle(color: AdminTheme.textPrimary),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: currentPage < totalPages
                ? () => _loadTableData(_selectedTable!['name'],
                    page: currentPage + 1)
                : null,
            color: AdminTheme.primaryColor,
          ),
          IconButton(
            icon: const Icon(Icons.last_page),
            onPressed: currentPage < totalPages
                ? () =>
                    _loadTableData(_selectedTable!['name'], page: totalPages)
                : null,
            color: AdminTheme.primaryColor,
          ),
        ],
      ),
    );
  }

  String _getCategoryName(String category) {
    switch (category) {
      case 'Core':
        return 'الأساسيات';
      case 'Commerce':
        return 'التجارة';
      case 'System':
        return 'النظام';
      case 'Company':
        return 'الشركات';
      case 'Permissions':
        return 'الصلاحيات';
      case 'Services':
        return 'الخدمات';
      case 'CitizenPortal':
        return 'المواطن';
      default:
        return category;
    }
  }

  IconData _getIconData(String? iconName) {
    switch (iconName) {
      case 'person':
        return Icons.person;
      case 'store':
        return Icons.store;
      case 'people':
        return Icons.people;
      case 'inventory':
        return Icons.inventory;
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'payment':
        return Icons.payment;
      case 'category':
        return Icons.category;
      case 'location_city':
        return Icons.location_city;
      case 'map':
        return Icons.map;
      case 'star':
        return Icons.star;
      case 'local_offer':
        return Icons.local_offer;
      case 'home':
        return Icons.home;
      case 'notifications':
        return Icons.notifications;
      case 'campaign':
        return Icons.campaign;
      case 'system_update':
        return Icons.system_update;
      case 'settings':
        return Icons.settings;
      case 'business':
        return Icons.business;
      case 'miscellaneous_services':
        return Icons.miscellaneous_services;
      case 'security':
        return Icons.security;
      case 'lock':
        return Icons.lock;
      case 'verified_user':
        return Icons.verified_user;
      case 'description':
        return Icons.description;
      case 'build':
        return Icons.build;
      case 'playlist_add_check':
        return Icons.playlist_add_check;
      case 'assignment':
        return Icons.assignment;
      case 'badge':
        return Icons.badge;
      case 'wifi':
        return Icons.wifi;
      case 'subscriptions':
        return Icons.subscriptions;
      case 'support_agent':
        return Icons.support_agent;
      case 'receipt':
        return Icons.receipt;
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'local_shipping':
        return Icons.local_shipping;
      default:
        return Icons.table_chart;
    }
  }
}
