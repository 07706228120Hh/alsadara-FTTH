/// صفحة إدارة بيانات VPS/API
/// تعرض جميع البيانات المخزنة في قاعدة بيانات الخادم مع إمكانية التعديل والحذف
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart' hide TextDirection;
import '../../theme/energy_dashboard_theme.dart';

class VpsDataManagerPage extends StatefulWidget {
  const VpsDataManagerPage({super.key});

  @override
  State<VpsDataManagerPage> createState() => _VpsDataManagerPageState();
}

class _VpsDataManagerPageState extends State<VpsDataManagerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // يمكنك تغيير هذا الرابط حسب بيئة العمل
  static const String baseUrl = 'https://api.ramzalsadara.tech/api/internal';

  // API Key للوصول الداخلي
  static const String apiKey = 'sadara-internal-2024-secure-key';

  // رابط بديل للتطوير المحلي
  // static const String baseUrl = 'http://localhost:5000/api/internal';

  String _searchQuery = '';
  bool _isLoading = false;
  String? _errorMessage;
  String? _errorDetails;

  // الجداول الرئيسية في VPS - استخدام endpoints صغيرة
  final List<_TableInfo> _tables = [
    _TableInfo('companies', '🏢 الشركات', Icons.business),
    _TableInfo('users', '👤 المستخدمين', Icons.person),
    _TableInfo('citizens', '🪪 المواطنين', Icons.assignment_ind),
    _TableInfo('customers', '👥 العملاء', Icons.people),
    _TableInfo('merchants', '🏪 التجار', Icons.storefront),
    _TableInfo('products', '📦 المنتجات', Icons.inventory),
    _TableInfo('orders', '🛒 الطلبات', Icons.shopping_cart),
    _TableInfo('cities', '🌆 المدن', Icons.location_city),
    _TableInfo('servicerequests', '📋 طلبات الخدمة', Icons.support_agent),
    _TableInfo('subscriptionlogs', '📊 سجلات الاشتراكات', Icons.receipt_long),
  ];

  int _selectedTableIndex = 0;
  List<dynamic> _currentData = [];
  Map<String, dynamic>? _selectedItem;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tables.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() {
          _selectedTableIndex = _tabController.index;
          _selectedItem = null;
        });
        _fetchData(_tables[_tabController.index].endpoint);
      }
    });
    _fetchData(_tables[0].endpoint);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData(String endpoint) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorDetails = null;
    });

    try {
      final client = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(Uri.parse('$baseUrl/$endpoint'));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Accept', 'application/json');
      request.headers.set('X-Api-Key', apiKey); // إضافة API Key

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final decoded = json.decode(responseBody);
        if (!mounted) return;
        setState(() {
          if (decoded is List) {
            _currentData = decoded;
          } else if (decoded is Map && decoded.containsKey('data')) {
            _currentData =
                decoded['data'] is List ? decoded['data'] : [decoded['data']];
          } else if (decoded is Map) {
            _currentData = [decoded];
          }
          _isLoading = false;
        });
      } else {
        String errorMsg = 'خطأ في الاتصال: ${response.statusCode}';
        String? details;

        switch (response.statusCode) {
          case 401:
            errorMsg = '❌ خطأ 401: غير مصرح - API Key غير صحيح';
            details =
                'تأكد من:\n• أن خادم API يعمل على الخادم\n• أن API Key صحيح\n• تحقق من /api/internal/ping';
            break;
          case 403:
            errorMsg = '❌ خطأ 403: ممنوع الوصول';
            details = 'ليس لديك صلاحية للوصول لهذا المورد';
            break;
          case 404:
            errorMsg = '❌ خطأ 404: المورد غير موجود';
            details =
                'الجدول "$endpoint" غير موجود في الـ API\nتأكد من نشر الـ API الجديد على الخادم';
            break;
          case 500:
            errorMsg = '❌ خطأ 500: خطأ في الخادم';
            details = 'حدث خطأ داخلي في الخادم';
            break;
        }

        if (!mounted) return;
        setState(() {
          _errorMessage = errorMsg;
          _errorDetails = details;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '❌ فشل الاتصال بالخادم';
        _errorDetails =
            'تأكد من:\n• أن الخادم VPS يعمل على $baseUrl\n• أن لديك اتصال بالإنترنت\n\nالخطأ';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteItem(String endpoint, String id) async {
    try {
      final client = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      final request =
          await client.deleteUrl(Uri.parse('$baseUrl/$endpoint/$id'));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('X-Api-Key', apiKey);

      final response = await request.close();

      if (response.statusCode == 200 || response.statusCode == 204) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم الحذف بنجاح'), backgroundColor: Colors.green),
        );
        _fetchData(endpoint);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل الحذف: ${response.statusCode}'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _updateItem(
      String endpoint, String id, Map<String, dynamic> data) async {
    try {
      final client = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      final request = await client.putUrl(Uri.parse('$baseUrl/$endpoint/$id'));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('X-Api-Key', apiKey);

      // تحويل البيانات لـ UTF-8 bytes بشكل صحيح
      final jsonData = json.encode(data);
      final bytes = utf8.encode(jsonData);
      request.headers.set('Content-Length', bytes.length.toString());
      request.add(bytes);

      final response = await request.close();

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم التحديث بنجاح'), backgroundColor: Colors.green),
        );
        _fetchData(endpoint);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل التحديث: ${response.statusCode}'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _createItem(String endpoint, Map<String, dynamic> data) async {
    try {
      final client = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;

      final request = await client.postUrl(Uri.parse('$baseUrl/$endpoint'));
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('X-Api-Key', apiKey);

      // تحويل البيانات لـ UTF-8 bytes بشكل صحيح
      final jsonData = json.encode(data);
      final bytes = utf8.encode(jsonData);
      request.headers.set('Content-Length', bytes.length.toString());
      request.add(bytes);

      final response = await request.close();

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تمت الإضافة بنجاح'),
              backgroundColor: Colors.green),
        );
        _fetchData(endpoint);
      } else {
        final responseBody = await response.transform(utf8.decoder).join();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل الإضافة: $responseBody'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EnergyDashboardTheme.bgLight,
      appBar: AppBar(
        backgroundColor: EnergyDashboardTheme.bgLightCard,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: EnergyDashboardTheme.glowShadow(
                    const Color(0xFF3B82F6).withOpacity(0.3)),
              ),
              child:
                  const Icon(Icons.dns_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إدارة بيانات VPS',
                  style: TextStyle(
                    color: EnergyDashboardTheme.textDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                Text(
                  'عرض وتعديل بيانات الخادم',
                  style: TextStyle(
                    color: EnergyDashboardTheme.textMedium,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        iconTheme: IconThemeData(color: EnergyDashboardTheme.textDark),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: EnergyDashboardTheme.borderColor),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: _tables.asMap().entries.map((entry) {
                      final index = entry.key;
                      final t = entry.value;
                      final isSelected = _selectedTableIndex == index;
                      return GestureDetector(
                        onTap: () {
                          _tabController.animateTo(index);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? EnergyDashboardTheme.primaryColor
                                    .withOpacity(0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected
                                  ? EnergyDashboardTheme.primaryColor
                                      .withOpacity(0.3)
                                  : EnergyDashboardTheme.borderColor,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(t.icon,
                                  size: 14,
                                  color: isSelected
                                      ? EnergyDashboardTheme.primaryColor
                                      : EnergyDashboardTheme.textMuted),
                              const SizedBox(width: 4),
                              Text(
                                t.displayName
                                    .replaceAll(
                                        RegExp(r'[^\w\s\u0600-\u06FF]'), '')
                                    .trim(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? EnergyDashboardTheme.primaryColor
                                      : EnergyDashboardTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          // حالة الاتصال
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _errorMessage == null && !_isLoading
                  ? EnergyDashboardTheme.accentColor.withOpacity(0.1)
                  : EnergyDashboardTheme.warningColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _errorMessage == null && !_isLoading
                    ? EnergyDashboardTheme.accentColor.withOpacity(0.3)
                    : EnergyDashboardTheme.warningColor.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _errorMessage == null && !_isLoading
                        ? EnergyDashboardTheme.accentColor
                        : EnergyDashboardTheme.warningColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _errorMessage == null && !_isLoading ? 'متصل' : 'غير متصل',
                  style: TextStyle(
                    color: _errorMessage == null && !_isLoading
                        ? EnergyDashboardTheme.accentColor
                        : EnergyDashboardTheme.warningColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: EnergyDashboardTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.refresh,
                  color: EnergyDashboardTheme.primaryColor, size: 20),
            ),
            onPressed: () => _fetchData(_tables[_selectedTableIndex].endpoint),
            tooltip: 'تحديث',
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: () => _showAddDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة جديد'),
              style: ElevatedButton.styleFrom(
                backgroundColor: EnergyDashboardTheme.accentColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          // القائمة الرئيسية
          Expanded(
            flex: 2,
            child: Column(
              children: [
                // شريط البحث
                Container(
                  padding: const EdgeInsets.all(20),
                  child: EnergyDashboardTheme.buildSearchBar(
                    hint:
                        'البحث في ${_tables[_selectedTableIndex].displayName}...',
                    onChanged: (value) =>
                        setState(() => _searchQuery = value.toLowerCase()),
                  ),
                ),
                // إحصائيات
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: EnergyDashboardTheme.buildStatCard(
                          title: 'إجمالي السجلات',
                          value: _currentData.length.toString(),
                          icon: Icons.storage,
                          color: EnergyDashboardTheme.infoColor,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: EnergyDashboardTheme.buildStatCard(
                          title: 'الجدول الحالي',
                          value: _tables[_selectedTableIndex].displayName,
                          icon: Icons.table_chart,
                          color: EnergyDashboardTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // قائمة البيانات
                Expanded(
                  child: _buildDataList(),
                ),
              ],
            ),
          ),
          // لوحة التفاصيل
          if (_selectedItem != null)
            Container(
              width: 420,
              decoration: BoxDecoration(
                color: EnergyDashboardTheme.surfaceColor,
                border: Border(
                  left: BorderSide(color: EnergyDashboardTheme.borderColor),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(-4, 0),
                  ),
                ],
              ),
              child: _buildDetailPanel(),
            ),
        ],
      ),
    );
  }

  Widget _buildDataList() {
    if (_isLoading) {
      return EnergyDashboardTheme.buildLoadingIndicator(
          message: 'جاري تحميل البيانات...');
    }

    if (_errorMessage != null) {
      return EnergyDashboardTheme.buildErrorWidget(
        message: _errorMessage!,
        details: _errorDetails,
        onRetry: () => _fetchData(_tables[_selectedTableIndex].endpoint),
      );
    }

    // تصفية البيانات
    final filteredData = _currentData.where((item) {
      if (_searchQuery.isEmpty) return true;
      return item.toString().toLowerCase().contains(_searchQuery);
    }).toList();

    if (filteredData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: EnergyDashboardTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(Icons.inbox_outlined,
                  size: 48, color: EnergyDashboardTheme.primaryColor),
            ),
            const SizedBox(height: 20),
            Text(
              _searchQuery.isEmpty ? 'لا توجد بيانات' : 'لا توجد نتائج',
              style: const TextStyle(
                  color: EnergyDashboardTheme.textSecondary,
                  fontSize: 18,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: filteredData.length,
      itemBuilder: (context, index) {
        final item = filteredData[index] as Map<String, dynamic>;
        return _buildItemCard(item);
      },
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final isSelected = _selectedItem == item;
    final id = item['id']?.toString() ?? '';
    final name = item['name'] ??
        item['fullName'] ??
        item['subscriptionNumber'] ??
        item['code'] ??
        id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected
            ? EnergyDashboardTheme.primaryColor.withOpacity(0.15)
            : EnergyDashboardTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: EnergyDashboardTheme.cardShadow,
        border: Border.all(
          color: isSelected
              ? EnergyDashboardTheme.primaryColor
              : EnergyDashboardTheme.borderColor,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: () => setState(() => _selectedItem = item),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: EnergyDashboardTheme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_tables[_selectedTableIndex].icon,
              color: EnergyDashboardTheme.primaryColor, size: 22),
        ),
        title: Text(
          name.toString(),
          style: const TextStyle(
            color: EnergyDashboardTheme.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'ID: $id',
            style: const TextStyle(
                color: EnergyDashboardTheme.textMuted, fontSize: 12),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // حالة النشاط
            if (item.containsKey('isActive'))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: item['isActive'] == true
                      ? Colors.green.withOpacity(0.2)
                      : Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item['isActive'] == true ? 'نشط' : 'معطل',
                  style: TextStyle(
                    color: item['isActive'] == true ? Colors.green : Colors.red,
                    fontSize: 10,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
              onPressed: () => _showEditDialog(item),
              tooltip: 'تعديل',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
              onPressed: () => _showDeleteDialog(item),
              tooltip: 'حذف',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPanel() {
    if (_selectedItem == null) return const SizedBox();

    return Column(
      children: [
        // رأس اللوحة
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: EnergyDashboardTheme.borderColor)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: EnergyDashboardTheme.infoColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.info_outline,
                    color: EnergyDashboardTheme.infoColor, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'تفاصيل العنصر',
                style: TextStyle(
                    color: EnergyDashboardTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close,
                    color: EnergyDashboardTheme.textMuted),
                onPressed: () => setState(() => _selectedItem = null),
              ),
            ],
          ),
        ),
        // المحتوى
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _selectedItem!.entries.map((entry) {
                return _buildDetailRow(entry.key, entry.value);
              }).toList(),
            ),
          ),
        ),
        // أزرار الإجراءات
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(
                top: BorderSide(color: EnergyDashboardTheme.borderColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showEditDialog(_selectedItem!),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('تعديل'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EnergyDashboardTheme.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showDeleteDialog(_selectedItem!),
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('حذف'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EnergyDashboardTheme.dangerColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String key, dynamic value) {
    String displayValue = _formatValue(value);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _getFieldLabel(key),
            style: const TextStyle(
                color: EnergyDashboardTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  displayValue,
                  style: const TextStyle(
                      color: EnergyDashboardTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy,
                    size: 16, color: EnergyDashboardTheme.textMuted),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: displayValue));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم النسخ')),
                  );
                },
                tooltip: 'نسخ',
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';
    if (value is Map || value is List) return json.encode(value);
    if (value is String && value.contains('T') && value.contains('-')) {
      try {
        final date = DateTime.parse(value);
        return DateFormat('yyyy-MM-dd HH:mm').format(date);
      } catch (_) {}
    }
    return value.toString();
  }

  // ================= Dialogs =================

  // دالة للحصول على العنوان العربي للحقل
  String _getFieldLabel(String field) {
    final labels = {
      'name': 'الاسم',
      'nameAr': 'الاسم بالعربي',
      'fullName': 'الاسم الكامل',
      'email': 'البريد الإلكتروني',
      'phone': 'رقم الهاتف',
      'phoneNumber': 'رقم الهاتف',
      'password': 'كلمة المرور',
      'plainPassword': 'كلمة المرور',
      'code': 'الكود',
      'address': 'العنوان',
      'city': 'المدينة',
      'role': 'الدور / الصلاحية',
      'price': 'السعر',
      'stock': 'المخزون',
      'isActive': 'نشط',
      'status': 'الحالة',
      'description': 'الوصف',
      'subscriptionNumber': 'رقم الاشتراك',
      'companyId': 'الشركة',
      'createdAt': 'تاريخ الإنشاء',
      'updatedAt': 'تاريخ التحديث',
      'district': 'الحي',
      'isPhoneVerified': 'تم التحقق',
      'isBanned': 'محظور',
      'fullAddress': 'العنوان الكامل',
    };
    return labels[field] ?? field;
  }

  // دالة للحصول على أيقونة الحقل
  IconData _getFieldIcon(String field) {
    final icons = {
      'name': Icons.text_fields,
      'nameAr': Icons.translate,
      'fullName': Icons.badge,
      'email': Icons.email,
      'phone': Icons.phone,
      'phoneNumber': Icons.phone_android,
      'password': Icons.lock,
      'plainPassword': Icons.lock_outline,
      'code': Icons.qr_code,
      'address': Icons.location_on,
      'city': Icons.location_city,
      'role': Icons.admin_panel_settings,
      'price': Icons.attach_money,
      'stock': Icons.inventory,
      'isActive': Icons.toggle_on,
      'status': Icons.info_outline,
      'description': Icons.description,
      'subscriptionNumber': Icons.numbers,
      'companyId': Icons.business,
      'district': Icons.map,
      'isPhoneVerified': Icons.verified_user,
      'isBanned': Icons.block,
      'fullAddress': Icons.home,
    };
    return icons[field] ?? Icons.text_fields;
  }

  // حقل نص موحد للنوافذ
  Widget _buildDialogTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    Color color = EnergyDashboardTheme.primaryColor,
    bool obscureText = false,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      obscureText: obscureText,
      style: TextStyle(
        color: readOnly
            ? EnergyDashboardTheme.textMuted
            : EnergyDashboardTheme.textPrimary,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: EnergyDashboardTheme.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
        ),
        filled: true,
        fillColor: readOnly ? const Color(0xFFF1F5F9) : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: EnergyDashboardTheme.borderColor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 2),
        ),
        prefixIcon: Icon(icon, color: color.withOpacity(0.7)),
      ),
    );
  }

  void _showAddDialog() {
    final table = _tables[_selectedTableIndex];
    final controllers = <String, TextEditingController>{};

    // حقول حسب نوع الجدول
    List<String> fields = [];
    switch (table.endpoint) {
      case 'companies':
        fields = ['name', 'code', 'email', 'phone', 'address', 'city'];
        break;
      case 'users':
        fields = ['fullName', 'phoneNumber', 'email', 'password', 'role'];
        break;
      case 'citizens':
        fields = [
          'fullName',
          'phoneNumber',
          'email',
          'password',
          'city',
          'district'
        ];
        break;
      case 'customers':
        fields = ['name', 'phoneNumber', 'email'];
        break;
      case 'merchants':
        fields = ['name', 'phoneNumber', 'email'];
        break;
      case 'products':
        fields = ['name', 'nameAr', 'price', 'stock'];
        break;
      case 'cities':
        fields = ['name', 'nameAr'];
        break;
      default:
        fields = ['name', 'value'];
    }

    for (var field in fields) {
      controllers[field] = TextEditingController();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EnergyDashboardTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: EnergyDashboardTheme.accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.add_circle,
                  color: EnergyDashboardTheme.accentColor, size: 22),
            ),
            const SizedBox(width: 12),
            Text('إضافة ${table.displayName}',
                style: const TextStyle(
                    color: EnergyDashboardTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: fields.map((field) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _buildDialogTextField(
                    controller: controllers[field]!,
                    label: _getFieldLabel(field),
                    icon: _getFieldIcon(field),
                    color: EnergyDashboardTheme.accentColor,
                    obscureText: field.toLowerCase().contains('password'),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء',
                style: TextStyle(color: EnergyDashboardTheme.textMuted)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final data = <String, dynamic>{};
              controllers.forEach((key, controller) {
                if (controller.text.isNotEmpty) {
                  // تحويل الأرقام
                  if (key.contains('price') ||
                      key.contains('Price') ||
                      key.contains('Speed') ||
                      key.contains('stock') ||
                      key.contains('Mbps')) {
                    data[key] =
                        num.tryParse(controller.text) ?? controller.text;
                  } else {
                    data[key] = controller.text;
                  }
                }
              });
              _createItem(table.endpoint, data);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('إضافة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: EnergyDashboardTheme.accentColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> item) {
    final table = _tables[_selectedTableIndex];
    final controllers = <String, TextEditingController>{};

    // إنشاء controllers للحقول القابلة للتعديل
    item.forEach((key, value) {
      if (key != 'id' &&
          key != 'createdAt' &&
          key != 'updatedAt' &&
          key != 'passwordHash' && // تخطي passwordHash
          value != null &&
          value is! Map &&
          value is! List) {
        controllers[key] = TextEditingController(text: value.toString());
      }
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EnergyDashboardTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: EnergyDashboardTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.edit,
                  color: EnergyDashboardTheme.primaryColor, size: 22),
            ),
            const SizedBox(width: 12),
            const Text('تعديل العنصر',
                style: TextStyle(
                    color: EnergyDashboardTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: controllers.entries.map((entry) {
                final isReadOnly =
                    entry.key == 'id' || entry.key == 'companyId';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _buildDialogTextField(
                    controller: entry.value,
                    label: _getFieldLabel(entry.key),
                    icon: _getFieldIcon(entry.key),
                    color: EnergyDashboardTheme.primaryColor,
                    readOnly: isReadOnly,
                    obscureText: entry.key.toLowerCase().contains('password'),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء',
                style: TextStyle(color: EnergyDashboardTheme.textMuted)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final data = <String, dynamic>{};
              controllers.forEach((key, controller) {
                // الحفاظ على النوع الأصلي
                final originalValue = item[key];
                if (originalValue is bool) {
                  data[key] = controller.text.toLowerCase() == 'true';
                } else if (originalValue is num) {
                  data[key] = num.tryParse(controller.text) ?? controller.text;
                } else {
                  data[key] = controller.text;
                }
              });
              _updateItem(table.endpoint, item['id'].toString(), data);
              Navigator.pop(context);
              setState(() => _selectedItem = null);
            },
            icon: const Icon(Icons.save, size: 18),
            label: const Text('حفظ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: EnergyDashboardTheme.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EnergyDashboardTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: EnergyDashboardTheme.dangerColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: EnergyDashboardTheme.dangerColor, size: 22),
            ),
            const SizedBox(width: 12),
            const Text('تأكيد الحذف',
                style: TextStyle(
                    color: EnergyDashboardTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: EnergyDashboardTheme.dangerColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: EnergyDashboardTheme.dangerColor.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  color: EnergyDashboardTheme.dangerColor.withOpacity(0.7)),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'هل أنت متأكد من حذف هذا العنصر؟\nهذا الإجراء لا يمكن التراجع عنه.',
                  style: TextStyle(
                      color: EnergyDashboardTheme.textPrimary, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء',
                style: TextStyle(color: EnergyDashboardTheme.textMuted)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _deleteItem(
                  _tables[_selectedTableIndex].endpoint, item['id'].toString());
              Navigator.pop(context);
              setState(() => _selectedItem = null);
            },
            icon: const Icon(Icons.delete, size: 18),
            label: const Text('حذف'),
            style: ElevatedButton.styleFrom(
              backgroundColor: EnergyDashboardTheme.dangerColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableInfo {
  final String endpoint;
  final String displayName;
  final IconData icon;

  _TableInfo(this.endpoint, this.displayName, this.icon);
}
