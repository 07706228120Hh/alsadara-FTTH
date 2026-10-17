import 'package:flutter/material.dart';
import '../../services/accounting_service.dart';
import '../../theme/accounting_responsive.dart';
import '../../frontend/frontend.dart';
import '../../frontend/components/sd_ui_kit.dart';

/// صفحة شجرة الحسابات
class ChartOfAccountsPage extends StatefulWidget {
  final String? companyId;

  const ChartOfAccountsPage({super.key, this.companyId});

  @override
  State<ChartOfAccountsPage> createState() => _ChartOfAccountsPageState();
}

class _ChartOfAccountsPageState extends State<ChartOfAccountsPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _accounts = [];
  List<dynamic> _treeData = [];
  bool _showTree = true;
  String _searchQuery = '';
  final Set<String> _expandedNodes = {};

  final _accountTypes = [
    'Assets',
    'Liabilities',
    'Equity',
    'Revenue',
    'Expenses'
  ];
  final _accountTypeLabels = {
    'Assets': 'أصول',
    'Liabilities': 'التزامات',
    'Equity': 'حقوق ملكية',
    'Revenue': 'إيرادات',
    'Expenses': 'مصروفات',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      debugPrint('📊 شجرة الحسابات: بدء تحميل البيانات (companyId=${widget.companyId})');
      final results = await Future.wait([
        AccountingService.instance.getAccounts(companyId: widget.companyId),
        AccountingService.instance.getAccountsTree(companyId: widget.companyId),
      ]).timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception('انتهت مهلة الاتصال');
      });
      debugPrint('📊 شجرة الحسابات: وصلت النتائج - accounts success=${results[0]['success']}, tree success=${results[1]['success']}');

      if (results[0]['success'] == true) {
        _accounts = (results[0]['data'] is List) ? results[0]['data'] : [];
      } else {
        debugPrint('⚠️ فشل جلب الحسابات: ${results[0]['message']}');
        _accounts = [];
      }
      if (results[1]['success'] == true) {
        _treeData = (results[1]['data'] is List) ? results[1]['data'] : [];
      } else {
        debugPrint('⚠️ فشل جلب الشجرة: ${results[1]['message']}');
        _treeData = [];
      }
      debugPrint('📊 شجرة الحسابات: accounts=${_accounts.length}, tree=${_treeData.length}');

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      // إذا لم توجد حسابات وكلا الطلبين نجح، نعرض رسالة تهيئة
      if (_accounts.isEmpty &&
          results[0]['success'] == true &&
          results[1]['success'] == true) {
        _showSeedDialog();
      } else if (_accounts.isEmpty &&
          results[0]['success'] != true) {
        // فشل في الاتصال
        setState(() {
          _errorMessage = results[0]['message']?.toString() ?? 'فشل في جلب البيانات';
        });
      }
    } catch (e) {
      debugPrint('❌ شجرة الحسابات: خطأ - $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'خطأ في الاتصال: $e';
        _isLoading = false;
      });
    }
  }

  void _showSeedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: SdColors.surface,
          title: Text('تهيئة شجرة الحسابات',
              style: TextStyle(color: SdColors.ink)),
          content: const Text(
            'لا توجد حسابات بعد. هل تريد تهيئة الحسابات الافتراضية (30 حساب)؟',
            style: TextStyle(color: SdColors.muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('لاحقاً',
                  style: TextStyle(color: SdColors.faint)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _seedAccounts();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: SdColors.success,
                foregroundColor: Colors.white,
              ),
              child: const Text('تهيئة الآن'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _seedAccounts() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final result = await AccountingService.instance.seedAccounts(
        companyId: widget.companyId ?? '',
      );
      if (result['success'] == true) {
        _showSnackBar('تم تهيئة الحسابات بنجاح', SdColors.success);
        await _loadData();
      } else {
        _showSnackBar(result['message'] ?? 'خطأ', SdColors.danger);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      _showSnackBar('خطأ', SdColors.danger);
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      return SdPage(
        scrollable: false,
        padding: EdgeInsets.zero,
        maxWidth: double.infinity,
        appBar: SdAppBar(
          title: 'شجرة الحسابات',
          subtitle: '${_accounts.length} حساب',
          actions: [
            SdAppBarAction(
              icon: _showTree ? Icons.list : Icons.account_tree,
              label: _showTree ? 'عرض قائمة' : 'عرض شجري',
              onPressed: () => setState(() => _showTree = !_showTree),
            ),
            if (_showTree) ...[
              SdAppBarAction(
                icon: Icons.unfold_more,
                label: 'توسيع الكل',
                onPressed: () => setState(
                    () => _collectAllNodeIds(_treeData, _expandedNodes)),
              ),
              SdAppBarAction(
                icon: Icons.unfold_less,
                label: 'طي الكل',
                onPressed: () => setState(() => _expandedNodes.clear()),
              ),
            ],
            SdAppBarAction(
              icon: Icons.refresh,
              label: 'تحديث',
              onPressed: _loadData,
            ),
            SdAppBarAction(
              icon: Icons.add,
              label: 'حساب جديد',
              onPressed: _showAddAccountDialog,
            ),
          ],
        ),
        body: Column(
          children: [
            _buildSearchBar(),
            _buildStatsBar(),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: SdColors.success))
                  : _errorMessage != null
                      ? _buildError()
                      : _showTree
                          ? _buildTreeView()
                          : _buildListView(),
            ),
          ],
        ),
      );
    } catch (e) {
      return Scaffold(
        body: Center(child: Text('خطأ في عرض الصفحة: $e')),
      );
    }
  }

  Widget _buildSearchBar() {
    final isMobile = context.accR.isMobile;
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : context.accR.spaceXL,
          vertical: isMobile ? 6 : context.accR.spaceS),
      child: SizedBox(
        height: isMobile ? 36 : 40,
        child: TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          textDirection: TextDirection.rtl,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: context.accR.financialSmall,
              color: SdColors.ink),
          decoration: InputDecoration(
            hintText: 'بحث في الحسابات...',
            hintStyle: TextStyle(
                fontFamily: 'Cairo',
                fontSize: context.accR.financialSmall,
                color: SdColors.faint),
            prefixIcon: Icon(Icons.search,
                size: context.accR.iconM, color: SdColors.faint),
            filled: true,
            fillColor: SdColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: SdColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: SdColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: SdColors.primary),
            ),
            contentPadding:
                EdgeInsets.symmetric(horizontal: context.accR.spaceM),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsBar() {
    int assets = 0, liabilities = 0, equity = 0, revenue = 0, expenses = 0;
    for (final a in _accounts) {
      switch (a['AccountType']) {
        case 'Assets':
          assets++;
          break;
        case 'Liabilities':
          liabilities++;
          break;
        case 'Equity':
          equity++;
          break;
        case 'Revenue':
          revenue++;
          break;
        case 'Expenses':
          expenses++;
          break;
      }
    }
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.spaceXL, vertical: context.accR.spaceM),
      decoration: BoxDecoration(
        color: SdColors.surface,
        border: Border(bottom: BorderSide(color: SdColors.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildStatChip(
                'أصول', '$assets', SdColors.info, Icons.business),
            SizedBox(width: context.accR.isMobile ? 4 : context.accR.spaceM),
            _buildStatChip('التزامات', '$liabilities', SdColors.warning,
                Icons.balance),
            SizedBox(width: context.accR.isMobile ? 4 : context.accR.spaceM),
            _buildStatChip(
                'ملكية', '$equity', SdColors.platformMid, Icons.verified),
            SizedBox(width: context.accR.isMobile ? 4 : context.accR.spaceM),
            _buildStatChip('إيرادات', '$revenue', SdColors.success,
                Icons.trending_up),
            SizedBox(width: context.accR.isMobile ? 4 : context.accR.spaceM),
            _buildStatChip('مصروفات', '$expenses', SdColors.danger,
                Icons.trending_down),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(
      String label, String value, Color color, IconData icon) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.spaceM, vertical: context.accR.spaceXS),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: context.accR.iconS, color: color),
          SizedBox(width: context.accR.spaceXS),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: context.accR.financialSmall,
                  fontWeight: FontWeight.bold,
                  color: color)),
          SizedBox(width: context.accR.spaceXS),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: context.accR.small, color: color.withOpacity(0.8))),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline,
              color: SdColors.danger.withOpacity(0.5),
              size: context.accR.iconXL),
          SizedBox(height: context.accR.spaceM),
          Text(_errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  color: SdColors.muted,
                  fontSize: context.accR.body)),
          SizedBox(height: context.accR.spaceS),
          Text('تحقق من الاتصال بالخادم وصلاحيات الحساب',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  color: SdColors.faint,
                  fontSize: context.accR.small)),
          SizedBox(height: context.accR.spaceL),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: Icon(Icons.refresh, size: context.accR.iconS),
            label: Text('إعادة المحاولة',
                style:
                    TextStyle(fontFamily: 'Cairo', fontSize: context.accR.financialSmall)),
            style: ElevatedButton.styleFrom(
              backgroundColor: SdColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeView() {
    if (_treeData.isEmpty) {
      return const Center(
        child: Text('لا توجد حسابات',
            style: TextStyle(color: SdColors.faint)),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: context.accR.spaceM),
      itemCount: _treeData.length,
      itemBuilder: (context, index) => _buildTreeNode(_treeData[index], 0),
    );
  }

  bool _hasMatchInSubtree(dynamic node, String query) {
    final name = (node['Name'] ?? '').toString();
    final code = (node['Code'] ?? '').toString();
    if (name.contains(query) || code.contains(query)) return true;
    final children = (node['Children'] as List?) ?? [];
    return children.any((c) => _hasMatchInSubtree(c, query));
  }

  Widget _buildTreeNode(dynamic node, int depth) {
    // حماية ضد العمق الزائد (تجنب infinite recursion)
    if (depth > 20) return const SizedBox.shrink();

    final name = node['Name'] ?? '';
    final code = node['Code'] ?? '';
    final type = node['AccountType'] ?? '';
    final children = (node['Children'] as List?) ?? [];
    final isLeaf = children.isEmpty;
    // الرصيد محسوب مسبقاً من البيكاند (يشمل مجموع الأبناء)
    final balance = node['CurrentBalance'] ?? 0;
    final isActive = node['IsActive'] ?? true;
    final nodeId = node['Id']?.toString() ?? code.toString();
    final isExpanded = _expandedNodes.contains(nodeId);

    // عند البحث: إخفاء العناصر غير المطابقة
    if (_searchQuery.isNotEmpty && !_hasMatchInSubtree(node, _searchQuery)) {
      return const SizedBox.shrink();
    }

    // عند البحث: توسيع تلقائي لإظهار النتائج
    final forceExpand = _searchQuery.isNotEmpty && !isLeaf;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: isLeaf
              ? () => _showAccountStatement(node)
              : () {
                  setState(() {
                    if (_expandedNodes.contains(nodeId)) {
                      _expandedNodes.remove(nodeId);
                    } else {
                      _expandedNodes.add(nodeId);
                    }
                  });
                },
          borderRadius: BorderRadius.circular(context.accR.cardRadius),
          child: Container(
            margin: EdgeInsets.only(right: depth * 28.0, bottom: 4, top: 4),
            padding: EdgeInsets.symmetric(
                horizontal: context.accR.spaceL, vertical: context.accR.spaceM),
            decoration: BoxDecoration(
              color: isLeaf
                  ? SdColors.surface
                  : (isExpanded || forceExpand)
                      ? _getTypeColor(type).withOpacity(0.06)
                      : SdColors.surface,
              borderRadius: BorderRadius.circular(context.accR.cardRadius),
              border: Border.all(
                  color: isLeaf
                      ? SdColors.divider
                      : (isExpanded || forceExpand)
                          ? _getTypeColor(type).withOpacity(0.4)
                          : SdColors.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                // أيقونة التوسيع/الطي
                if (!isLeaf)
                  AnimatedRotation(
                    turns: (isExpanded || forceExpand) ? 0.25 : 0,
                    duration: Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_left,
                      color: _getTypeColor(type),
                      size: context.accR.iconM,
                    ),
                  )
                else
                  SizedBox(width: context.accR.spaceXL),
                SizedBox(width: context.accR.spaceXS),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _getTypeColor(type).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: _getTypeColor(type).withOpacity(0.4)),
                  ),
                  child: Center(
                    child: Icon(
                      isLeaf
                          ? Icons.description_outlined
                          : (isExpanded || forceExpand)
                              ? Icons.folder_open_rounded
                              : Icons.folder_rounded,
                      color: _getTypeColor(type),
                      size: context.accR.iconS,
                    ),
                  ),
                ),
                SizedBox(width: context.accR.spaceM),
                Text(
                  code,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: SdColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: context.accR.financialSmall,
                  ),
                ),
                SizedBox(width: context.accR.spaceM),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: isActive
                          ? SdColors.ink
                          : SdColors.faint,
                      fontSize: context.accR.body,
                      fontWeight: isLeaf ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                ),
                // عدد الأبناء
                if (!isLeaf)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    margin: EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color: _getTypeColor(type).withOpacity(0.15),
                      borderRadius:
                          BorderRadius.circular(context.accR.cardRadius),
                    ),
                    child: Text(
                      '${children.length}',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          color: _getTypeColor(type),
                          fontSize: context.accR.small,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getTypeColor(type).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _accountTypeLabels[type] ?? type,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: _getTypeColor(type),
                        fontSize: context.accR.small),
                  ),
                ),
                SizedBox(width: context.accR.spaceM),
                Text(
                  _formatNumber(balance),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: (balance is num && balance < 0)
                        ? SdColors.danger
                        : SdColors.success,
                    fontWeight: FontWeight.bold,
                    fontSize: context.accR.financialSmall,
                  ),
                ),
                SizedBox(width: context.accR.spaceS),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      color: SdColors.faint,
                      size: context.accR.iconM),
                  color: SdColors.surface,
                  onSelected: (action) => _handleAccountAction(action, node),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'add_child',
                        child: Text('إضافة حساب فرعي',
                            style:
                                TextStyle(color: SdColors.ink))),
                    const PopupMenuItem(
                        value: 'edit',
                        child: Text('تعديل',
                            style:
                                TextStyle(color: SdColors.ink))),
                    if (isLeaf)
                      const PopupMenuItem(
                          value: 'statement',
                          child: Text('كشف حساب',
                              style: TextStyle(
                                  color: SdColors.ink))),
                    const PopupMenuItem(
                        value: 'delete',
                        child: Text('حذف',
                            style: TextStyle(color: SdColors.danger))),
                  ],
                ),
              ],
            ),
          ),
        ),
        // عرض الأبناء فقط إذا كان العنصر موسع أو عند البحث
        if (isExpanded || forceExpand)
          ...children.map((c) => _buildTreeNode(c, depth + 1)),
      ],
    );
  }

  Widget _buildListView() {
    var filtered = _accounts.where((a) {
      if (_searchQuery.isEmpty) return true;
      final name = (a['Name'] ?? '').toString();
      final code = (a['Code'] ?? '').toString();
      return name.contains(_searchQuery) || code.contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_rounded,
                size: context.accR.iconXL,
                color: SdColors.faint.withOpacity(0.3)),
            SizedBox(height: context.accR.spaceM),
            Text('لا توجد نتائج',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: context.accR.headingSmall,
                    color: SdColors.faint)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(context.accR.spaceXL),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final a = filtered[i];
        final type = a['AccountType'] ?? '';
        return Container(
          margin: EdgeInsets.only(bottom: context.accR.spaceS),
          decoration: BoxDecoration(
            color: SdColors.surface,
            borderRadius: BorderRadius.circular(context.accR.cardRadius),
            border: Border.all(color: SdColors.divider),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 1)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(context.accR.cardRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(context.accR.cardRadius),
              onTap: () {},
              child: Padding(
                padding: EdgeInsets.all(context.accR.spaceL),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _getTypeColor(type).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _getTypeColor(type).withOpacity(0.5)),
                      ),
                      child: Center(
                        child: Icon(Icons.description_outlined,
                            size: context.accR.iconM,
                            color: _getTypeColor(type)),
                      ),
                    ),
                    SizedBox(width: context.accR.spaceM),
                    Text(
                      a['Code'] ?? '',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: SdColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: context.accR.financialSmall,
                      ),
                    ),
                    SizedBox(width: context.accR.spaceM),
                    Expanded(
                      child: Text(
                        a['Name'] ?? '',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            color: SdColors.ink,
                            fontSize: context.accR.body),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getTypeColor(type).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _accountTypeLabels[type] ?? type,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            color: _getTypeColor(type),
                            fontSize: context.accR.small),
                      ),
                    ),
                    SizedBox(width: context.accR.spaceM),
                    Text(
                      _formatNumber(a['CurrentBalance']),
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          color: SdColors.success,
                          fontWeight: FontWeight.bold),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert,
                          color: SdColors.faint,
                          size: context.accR.iconM),
                      color: SdColors.surface,
                      onSelected: (action) => _handleAccountAction(action, a),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'edit',
                            child: Text('تعديل',
                                style: TextStyle(
                                    color: SdColors.ink))),
                        const PopupMenuItem(
                            value: 'statement',
                            child: Text('كشف حساب',
                                style: TextStyle(
                                    color: SdColors.ink))),
                        const PopupMenuItem(
                            value: 'delete',
                            child: Text('حذف',
                                style:
                                    TextStyle(color: SdColors.danger))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleAccountAction(String action, dynamic account) {
    switch (action) {
      case 'edit':
        _showEditAccountDialog(account);
        break;
      case 'statement':
        _showAccountStatement(account);
        break;
      case 'delete':
        _confirmDelete(account);
        break;
      case 'add_child':
        _showAddSubAccountDialog(account);
        break;
    }
  }

  /// حساب الكود التلقائي للحساب الفرعي الجديد
  String _suggestChildCode(dynamic parentNode) {
    final parentCode = (parentNode['Code'] ?? '').toString();
    final children = (parentNode['Children'] as List?) ?? [];
    if (children.isEmpty) {
      return '${parentCode}1';
    }
    // إيجاد أعلى كود فرعي وزيادته
    int maxSuffix = 0;
    for (final c in children) {
      final childCode = (c['Code'] ?? '').toString();
      if (childCode.startsWith(parentCode)) {
        final suffix = childCode.substring(parentCode.length);
        final num = int.tryParse(suffix) ?? 0;
        if (num > maxSuffix) maxSuffix = num;
      }
    }
    return '$parentCode${maxSuffix + 1}';
  }

  void _showAddSubAccountDialog(dynamic parentNode) {
    final parentCode = (parentNode['Code'] ?? '').toString();
    final parentName = (parentNode['Name'] ?? '').toString();
    final parentType = (parentNode['AccountType'] ?? 'Assets').toString();
    final parentId = (parentNode['Id'] ?? '').toString();
    final suggestedCode = _suggestChildCode(parentNode);

    final codeCtrl = TextEditingController(text: suggestedCode);
    final nameCtrl = TextEditingController();
    final nameEnCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final balanceCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: SdColors.surface,
          title: Text('إضافة حساب فرعي تحت: $parentName',
              style: TextStyle(
                  color: SdColors.ink,
                  fontSize: context.accR.headingSmall)),
          content: SizedBox(
            width: context.accR.dialogSmallW,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // عرض الأب
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(context.accR.spaceM),
                    decoration: BoxDecoration(
                      color: _getTypeColor(parentType).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _getTypeColor(parentType).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.account_tree,
                            size: context.accR.iconS,
                            color: _getTypeColor(parentType)),
                        SizedBox(width: context.accR.spaceS),
                        Text('$parentCode - $parentName',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: context.accR.financialSmall,
                                color: _getTypeColor(parentType),
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  SizedBox(height: context.accR.spaceL),
                  _buildField('رمز الحساب', codeCtrl, hint: suggestedCode),
                  SizedBox(height: context.accR.spaceM),
                  _buildField('اسم الحساب', nameCtrl),
                  SizedBox(height: context.accR.spaceM),
                  _buildField('الاسم بالإنجليزية', nameEnCtrl),
                  SizedBox(height: context.accR.spaceM),
                  _buildField('الرصيد الافتتاحي', balanceCtrl, isNumber: true),
                  SizedBox(height: context.accR.spaceM),
                  _buildField('الوصف', descCtrl, maxLines: 2),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: TextStyle(color: SdColors.faint)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.success,
                  foregroundColor: Colors.black),
              onPressed: () async {
                if (codeCtrl.text.isEmpty || nameCtrl.text.isEmpty) {
                  _showSnackBar(
                      'الرجاء ملء الحقول المطلوبة', SdColors.warning);
                  return;
                }
                Navigator.pop(ctx);
                final result = await AccountingService.instance.createAccount(
                  code: codeCtrl.text,
                  name: nameCtrl.text,
                  nameEn: nameEnCtrl.text.isEmpty ? null : nameEnCtrl.text,
                  accountType: parentType,
                  parentAccountId: parentId,
                  openingBalance: double.tryParse(balanceCtrl.text) ?? 0,
                  description: descCtrl.text.isEmpty ? null : descCtrl.text,
                  companyId: widget.companyId ?? '',
                );
                if (result['success'] == true) {
                  _showSnackBar(
                      'تم إنشاء الحساب الفرعي بنجاح', SdColors.success);
                  // توسيع الأب لإظهار الفرع الجديد
                  _expandedNodes.add(parentId);
                  _loadData();
                } else {
                  _showSnackBar(
                      result['message'] ?? 'خطأ', SdColors.danger);
                }
              },
              child: const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddAccountDialog() {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final nameEnCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final balanceCtrl = TextEditingController(text: '0');
    String selectedType = 'Assets';
    String? parentId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: SdColors.surface,
            title: Text('إضافة حساب جديد',
                style: TextStyle(color: SdColors.ink)),
            content: SizedBox(
              width: context.accR.dialogSmallW,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildField('رمز الحساب', codeCtrl, hint: '1100'),
                    SizedBox(height: context.accR.spaceM),
                    _buildField('اسم الحساب', nameCtrl),
                    SizedBox(height: context.accR.spaceM),
                    _buildField('الاسم بالإنجليزية', nameEnCtrl),
                    SizedBox(height: context.accR.spaceM),
                    _buildDropdown(
                      'نوع الحساب',
                      selectedType,
                      _accountTypes
                          .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(_accountTypeLabels[t] ?? t)))
                          .toList(),
                      (v) => setDialogState(() => selectedType = v ?? 'Assets'),
                    ),
                    SizedBox(height: context.accR.spaceM),
                    _buildDropdown(
                      'الحساب الأب',
                      parentId,
                      [
                        const DropdownMenuItem(
                            value: null, child: Text('— حساب رئيسي —')),
                        ..._accounts
                            .where((a) =>
                                !(a['IsLeaf'] ?? true) || a['Level'] == 0)
                            .map(
                              (a) => DropdownMenuItem(
                                value: a['Id']?.toString(),
                                child: Text('${a['Code']} - ${a['Name']}'),
                              ),
                            ),
                      ],
                      (v) => setDialogState(() => parentId = v),
                    ),
                    SizedBox(height: context.accR.spaceM),
                    _buildField('الرصيد الافتتاحي', balanceCtrl,
                        isNumber: true),
                    SizedBox(height: context.accR.spaceM),
                    _buildField('الوصف', descCtrl, maxLines: 2),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(color: SdColors.faint)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: SdColors.success,
                    foregroundColor: Colors.black),
                onPressed: () async {
                  if (codeCtrl.text.isEmpty || nameCtrl.text.isEmpty) {
                    _showSnackBar(
                        'الرجاء ملء الحقول المطلوبة', SdColors.warning);
                    return;
                  }
                  Navigator.pop(ctx);
                  final result = await AccountingService.instance.createAccount(
                    code: codeCtrl.text,
                    name: nameCtrl.text,
                    nameEn: nameEnCtrl.text.isEmpty ? null : nameEnCtrl.text,
                    accountType: selectedType,
                    parentAccountId: parentId,
                    openingBalance: double.tryParse(balanceCtrl.text) ?? 0,
                    description: descCtrl.text.isEmpty ? null : descCtrl.text,
                    companyId: widget.companyId ?? '',
                  );
                  if (result['success'] == true) {
                    _showSnackBar(
                        'تم إنشاء الحساب بنجاح', SdColors.success);
                    _loadData();
                  } else {
                    _showSnackBar(
                        result['message'] ?? 'خطأ', SdColors.danger);
                  }
                },
                child: const Text('إنشاء'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditAccountDialog(dynamic account) {
    final nameCtrl = TextEditingController(text: account['Name'] ?? '');
    final nameEnCtrl = TextEditingController(text: account['NameEn'] ?? '');
    final descCtrl = TextEditingController(text: account['Description'] ?? '');
    final openingBalanceCtrl = TextEditingController(
        text: (account['OpeningBalance'] ?? 0).toString());
    bool isActive = account['IsActive'] ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: SdColors.surface,
            title: Text('تعديل: ${account['Name']}',
                style: TextStyle(color: SdColors.ink)),
            content: SizedBox(
              width: context.accR.dialogSmallW,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildField('اسم الحساب', nameCtrl),
                    SizedBox(height: context.accR.spaceM),
                    _buildField('الاسم بالإنجليزية', nameEnCtrl),
                    SizedBox(height: context.accR.spaceM),
                    _buildField('الرصيد الافتتاحي', openingBalanceCtrl,
                        isNumber: true),
                    SizedBox(height: context.accR.spaceM),
                    _buildField('الوصف', descCtrl, maxLines: 2),
                    SizedBox(height: context.accR.spaceM),
                    SwitchListTile(
                      title: Text('نشط',
                          style: TextStyle(color: SdColors.ink)),
                      value: isActive,
                      activeColor: SdColors.success,
                      onChanged: (v) => setDialogState(() => isActive = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(color: SdColors.faint)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: SdColors.success,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final newBalance = double.tryParse(openingBalanceCtrl.text);
                  final oldBalance =
                      (account['OpeningBalance'] as num?)?.toDouble() ?? 0;
                  final result = await AccountingService.instance.updateAccount(
                    account['Id'],
                    name: nameCtrl.text,
                    nameEn: nameEnCtrl.text.isEmpty ? null : nameEnCtrl.text,
                    description: descCtrl.text.isEmpty ? null : descCtrl.text,
                    isActive: isActive,
                    openingBalance:
                        (newBalance != null && newBalance != oldBalance)
                            ? newBalance
                            : null,
                  );
                  if (result['success'] == true) {
                    _showSnackBar('تم التعديل بنجاح', SdColors.success);
                    _loadData();
                  } else {
                    _showSnackBar(
                        result['message'] ?? 'خطأ', SdColors.danger);
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccountStatement(dynamic account) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: SdColors.success)),
    );
    try {
      final result =
          await AccountingService.instance.getAccountStatement(account['Id']);
      if (!mounted) return;
      Navigator.pop(context);
      if (result['success'] == true) {
        final data = result['data'];
        final lines = (data['Lines'] as List?) ?? [];
        final summary = data['Summary'] as Map<String, dynamic>? ?? {};
        final acctInfo = data['Account'] as Map<String, dynamic>? ?? {};
        final totalDebit = (summary['TotalDebit'] ?? 0);
        final totalCredit = (summary['TotalCredit'] ?? 0);
        final balance = (summary['Balance'] ?? account['CurrentBalance'] ?? 0);
        showDialog(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: SdColors.surface,
              titlePadding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(context.accR.spaceXS),
                        decoration: BoxDecoration(
                          gradient: SdUiKit.neonBlueGradient,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(Icons.receipt_long,
                            color: Colors.white, size: context.accR.iconS),
                      ),
                      SizedBox(width: context.accR.spaceM),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'كشف حساب: ${account['Name']}',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: SdColors.ink,
                                  fontSize: context.accR.headingSmall,
                                  fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${acctInfo['Code'] ?? account['Code'] ?? ''} - ${_accountTypeLabels[acctInfo['AccountType'] ?? account['AccountType']] ?? ''}',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: SdColors.faint,
                                  fontSize: context.accR.small),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: context.accR.spaceM),
                  // ملخص الأرصدة
                  Container(
                    padding: EdgeInsets.all(context.accR.spaceM),
                    decoration: BoxDecoration(
                      color: SdColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: SdColors.divider),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text('إجمالي مدين',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: SdColors.faint,
                                      fontSize: context.accR.small)),
                              Text(_formatNumber(totalDebit),
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: SdColors.success,
                                      fontSize: context.accR.body,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Container(
                            width: 1,
                            height: 30,
                            color: SdColors.divider),
                        Expanded(
                          child: Column(
                            children: [
                              Text('إجمالي دائن',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: SdColors.faint,
                                      fontSize: context.accR.small)),
                              Text(_formatNumber(totalCredit),
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: SdColors.danger,
                                      fontSize: context.accR.body,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Container(
                            width: 1,
                            height: 30,
                            color: SdColors.divider),
                        Expanded(
                          child: Column(
                            children: [
                              Text('الرصيد',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: SdColors.faint,
                                      fontSize: context.accR.small)),
                              Text(_formatNumber(balance),
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: (balance is num && balance < 0)
                                          ? SdColors.danger
                                          : SdColors.primary,
                                      fontSize: context.accR.body,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: context.accR.isMobile
                    ? MediaQuery.of(context).size.width * 0.92
                    : 650,
                height: context.accR.isMobile
                    ? MediaQuery.of(context).size.height * 0.5
                    : 400,
                child: lines.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long,
                                color:
                                    SdColors.faint.withOpacity(0.3),
                                size: context.accR.iconXL),
                            SizedBox(height: context.accR.spaceM),
                            Text('لا توجد حركات مرحّلة على هذا الحساب',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    color: SdColors.faint,
                                    fontSize: context.accR.body)),
                            SizedBox(height: context.accR.spaceXS),
                            Text(
                                'الرصيد الحالي قد يكون من الرصيد الافتتاحي أو حركات غير مرحّلة',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    color: SdColors.faint,
                                    fontSize: context.accR.small)),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          // رأس الجدول
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: SdColors.surfaceAlt,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6)),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                    width: 60,
                                    child: Text('رقم القيد',
                                        style: TextStyle(
                                            fontFamily: 'Cairo',
                                            color: SdColors.faint,
                                            fontSize: context.accR.small,
                                            fontWeight: FontWeight.bold))),
                                SizedBox(
                                    width: 80,
                                    child: Text('التاريخ',
                                        style: TextStyle(
                                            fontFamily: 'Cairo',
                                            color: SdColors.faint,
                                            fontSize: context.accR.small,
                                            fontWeight: FontWeight.bold))),
                                Expanded(
                                    child: Text('البيان',
                                        style: TextStyle(
                                            fontFamily: 'Cairo',
                                            color: SdColors.faint,
                                            fontSize: context.accR.small,
                                            fontWeight: FontWeight.bold))),
                                SizedBox(
                                    width: 80,
                                    child: Text('مدين',
                                        style: TextStyle(
                                            fontFamily: 'Cairo',
                                            color: SdColors.success,
                                            fontSize: context.accR.small,
                                            fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center)),
                                SizedBox(
                                    width: 80,
                                    child: Text('دائن',
                                        style: TextStyle(
                                            fontFamily: 'Cairo',
                                            color: SdColors.danger,
                                            fontSize: context.accR.small,
                                            fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center)),
                              ],
                            ),
                          ),
                          const Divider(
                              color: SdColors.divider, height: 1),
                          // الحركات
                          Expanded(
                            child: ListView.builder(
                              itemCount: lines.length,
                              itemBuilder: (_, i) {
                                final e = lines[i];
                                final debit = (e['DebitAmount'] ?? 0);
                                final credit = (e['CreditAmount'] ?? 0);
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: i % 2 == 0
                                        ? Colors.transparent
                                        : SdColors.surfaceAlt
                                            .withOpacity(0.5),
                                    border: Border(
                                        bottom: BorderSide(
                                            color: SdColors.divider
                                                .withOpacity(0.5))),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                          width: 60,
                                          child: Text(
                                              '#${e['EntryNumber'] ?? ''}',
                                              style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  color:
                                                      SdColors.primary,
                                                  fontSize: context.accR.small,
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      SizedBox(
                                          width: 80,
                                          child: Text(
                                              _formatDate(e['EntryDate']),
                                              style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  color:
                                                      SdColors.faint,
                                                  fontSize:
                                                      context.accR.small))),
                                      Expanded(
                                          child: Text(
                                              e['Description'] ??
                                                  e['EntryDescription'] ??
                                                  '',
                                              style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  color: SdUiKit
                                                      .textPrimary,
                                                  fontSize: context.accR.small),
                                              overflow: TextOverflow.ellipsis)),
                                      SizedBox(
                                          width: 80,
                                          child: Text(
                                              debit > 0
                                                  ? _formatNumber(debit)
                                                  : '-',
                                              style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  color: debit > 0
                                                      ? SdColors.success
                                                      : SdUiKit
                                                          .textMuted,
                                                  fontSize: context.accR.small),
                                              textAlign: TextAlign.center)),
                                      SizedBox(
                                          width: 80,
                                          child: Text(
                                              credit > 0
                                                  ? _formatNumber(credit)
                                                  : '-',
                                              style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  color: credit > 0
                                                      ? SdColors.danger
                                                      : SdUiKit
                                                          .textMuted,
                                                  fontSize: context.accR.small),
                                              textAlign: TextAlign.center)),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إغلاق',
                      style: TextStyle(fontFamily: 'Cairo', color: SdColors.success)),
                ),
              ],
            ),
          ),
        );
      } else {
        _showSnackBar(result['message'] ?? 'خطأ', SdColors.danger);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('خطأ', SdColors.danger);
    }
  }

  void _confirmDelete(dynamic account) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: SdColors.surface,
          title: Text('تأكيد الحذف',
              style: TextStyle(color: SdColors.ink)),
          content: Text('هل تريد حذف الحساب "${account['Name']}"؟',
              style: const TextStyle(color: SdColors.muted)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: TextStyle(color: SdColors.faint)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.danger),
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await AccountingService.instance
                    .deleteAccount(account['Id']);
                if (result['success'] == true) {
                  _showSnackBar('تم الحذف', SdColors.success);
                  _loadData();
                } else {
                  _showSnackBar(
                      result['message'] ?? 'خطأ', SdColors.danger);
                }
              },
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl,
      {String? hint, bool isNumber = false, int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: SdColors.ink),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: SdColors.faint),
        hintStyle: const TextStyle(color: SdColors.faint),
        filled: true,
        fillColor: SdColors.surfaceAlt,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildDropdown(String label, String? value,
      List<DropdownMenuItem<String?>> items, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String?>(
      value: value,
      items: items,
      onChanged: onChanged,
      dropdownColor: SdColors.surface,
      style: const TextStyle(color: SdColors.ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: SdColors.faint),
        filled: true,
        fillColor: SdColors.surfaceAlt,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none),
      ),
    );
  }

  void _collectAllNodeIds(List<dynamic> nodes, Set<String> ids) {
    for (final node in nodes) {
      final children = (node['Children'] as List?) ?? [];
      if (children.isNotEmpty) {
        final nodeId = node['Id']?.toString() ?? node['Code']?.toString() ?? '';
        ids.add(nodeId);
        _collectAllNodeIds(children, ids);
      }
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'Assets':
        return SdColors.info;
      case 'Liabilities':
        return SdColors.warning;
      case 'Equity':
        return SdColors.platformMid;
      case 'Revenue':
        return SdColors.success;
      case 'Expenses':
        return SdColors.danger;
      default:
        return SdColors.faint;
    }
  }

  String _formatNumber(dynamic value) {
    if (value == null || value == 0) return '0';
    final n = value is num ? value : double.tryParse(value.toString()) ?? 0;
    return n.round().toString();
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      final d = DateTime.parse(date.toString()).toLocal();
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
