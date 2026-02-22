import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../theme/accounting_theme.dart';

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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        AccountingService.instance.getAccounts(companyId: widget.companyId),
        AccountingService.instance.getAccountsTree(companyId: widget.companyId),
      ]);

      if (results[0]['success'] == true) {
        _accounts = (results[0]['data'] is List) ? results[0]['data'] : [];
      }
      if (results[1]['success'] == true) {
        _treeData = (results[1]['data'] is List) ? results[1]['data'] : [];
      }
      setState(() {
        _isLoading = false;
      });

      // إذا لم توجد حسابات، نعرض رسالة تهيئة
      if (_accounts.isEmpty) {
        _showSeedDialog();
      }
    } catch (e) {
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
          backgroundColor: AccountingTheme.bgCard,
          title: const Text('تهيئة شجرة الحسابات',
              style: TextStyle(color: AccountingTheme.textPrimary)),
          content: const Text(
            'لا توجد حسابات بعد. هل تريد تهيئة الحسابات الافتراضية (30 حساب)؟',
            style: TextStyle(color: AccountingTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('لاحقاً',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _seedAccounts();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AccountingTheme.neonGreen,
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
        _showSnackBar('تم تهيئة الحسابات بنجاح', AccountingTheme.success);
        await _loadData();
      } else {
        _showSnackBar(result['message'] ?? 'خطأ', AccountingTheme.danger);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      _showSnackBar('خطأ: $e', AccountingTheme.danger);
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: Column(
          children: [
            _buildToolbar(),
            _buildStatsBar(),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: AccountingTheme.neonGreen))
                  : _errorMessage != null
                      ? _buildError()
                      : _showTree
                          ? _buildTreeView()
                          : _buildListView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'رجوع',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonBlueGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.account_tree_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text('شجرة الحسابات',
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AccountingTheme.textPrimary,
              )),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AccountingTheme.neonPink.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${_accounts.length}',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.neonPink,
                )),
          ),
          const Spacer(),
          // بحث
          SizedBox(
            width: 220,
            height: 36,
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              textDirection: TextDirection.rtl,
              style: GoogleFonts.cairo(
                  fontSize: 13, color: AccountingTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'بحث في الحسابات...',
                hintStyle: GoogleFonts.cairo(
                    fontSize: 13, color: AccountingTheme.textMuted),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: AccountingTheme.textMuted),
                filled: true,
                fillColor: AccountingTheme.bgPrimary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AccountingTheme.borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AccountingTheme.borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AccountingTheme.neonBlue),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // تبديل العرض
          InkWell(
            onTap: () => setState(() => _showTree = !_showTree),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AccountingTheme.borderColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_showTree ? Icons.list : Icons.account_tree,
                      size: 16, color: AccountingTheme.textMuted),
                  const SizedBox(width: 4),
                  Text(_showTree ? 'قائمة' : 'شجري',
                      style: GoogleFonts.cairo(
                          fontSize: 12, color: AccountingTheme.textSecondary)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_showTree) ...[
            IconButton(
              onPressed: () {
                setState(() {
                  _collectAllNodeIds(_treeData, _expandedNodes);
                });
              },
              icon: const Icon(Icons.unfold_more, size: 18),
              tooltip: 'توسيع الكل',
              style: IconButton.styleFrom(
                  foregroundColor: AccountingTheme.textSecondary),
            ),
            IconButton(
              onPressed: () {
                setState(() => _expandedNodes.clear());
              },
              icon: const Icon(Icons.unfold_less, size: 18),
              tooltip: 'طي الكل',
              style: IconButton.styleFrom(
                  foregroundColor: AccountingTheme.textSecondary),
            ),
          ],
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: _showAddAccountDialog,
            icon: const Icon(Icons.add, size: 16),
            label: Text('حساب جديد', style: GoogleFonts.cairo(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.neonGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          _buildStatChip(
              'أصول', '$assets', AccountingTheme.info, Icons.business),
          const SizedBox(width: 12),
          _buildStatChip('التزامات', '$liabilities', AccountingTheme.warning,
              Icons.balance),
          const SizedBox(width: 12),
          _buildStatChip(
              'حقوق ملكية', '$equity', const Color(0xFF8B5CF6), Icons.verified),
          const SizedBox(width: 12),
          _buildStatChip('إيرادات', '$revenue', AccountingTheme.success,
              Icons.trending_up),
          const SizedBox(width: 12),
          _buildStatChip('مصروفات', '$expenses', AccountingTheme.danger,
              Icons.trending_down),
        ],
      ),
    );
  }

  Widget _buildStatChip(
      String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(value,
              style: GoogleFonts.cairo(
                  fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.cairo(
                  fontSize: 11, color: color.withOpacity(0.8))),
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
              color: AccountingTheme.textMuted.withOpacity(0.3), size: 48),
          const SizedBox(height: 12),
          Text(_errorMessage!,
              style: GoogleFonts.cairo(
                  color: AccountingTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 16),
            label:
                Text('إعادة المحاولة', style: GoogleFonts.cairo(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.neonBlue,
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
            style: TextStyle(color: AccountingTheme.textMuted)),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: _treeData.map((node) => _buildTreeNode(node, 0)).toList(),
    );
  }

  bool _hasMatchInSubtree(dynamic node, String query) {
    final name = (node['Name'] ?? '').toString();
    final code = (node['Code'] ?? '').toString();
    if (name.contains(query) || code.contains(query)) return true;
    final children = (node['Children'] as List?) ?? [];
    return children.any((c) => _hasMatchInSubtree(c, query));
  }

  /// حساب الرصيد الكلي لعقدة (مجموع أرصدة الأبناء تصاعدياً)
  double _calculateSubtreeBalance(dynamic node) {
    final children = (node['Children'] as List?) ?? [];
    if (children.isEmpty) {
      // عقدة نهائية: نرجع رصيدها المباشر
      final bal = node['CurrentBalance'];
      return (bal is num) ? bal.toDouble() : 0.0;
    }
    // عقدة أب: مجموع أرصدة جميع الأبناء
    double total = 0;
    for (final child in children) {
      total += _calculateSubtreeBalance(child);
    }
    return total;
  }

  Widget _buildTreeNode(dynamic node, int depth) {
    final name = node['Name'] ?? '';
    final code = node['Code'] ?? '';
    final type = node['AccountType'] ?? '';
    final children = (node['Children'] as List?) ?? [];
    final isLeaf = children.isEmpty;
    // للعقد الأب: نحسب مجموع أرصدة الأبناء. للعقد النهائية: الرصيد المباشر
    final balance =
        isLeaf ? (node['CurrentBalance'] ?? 0) : _calculateSubtreeBalance(node);
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
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: EdgeInsets.only(right: depth * 28.0, bottom: 4, top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isLeaf
                  ? AccountingTheme.bgCard
                  : (isExpanded || forceExpand)
                      ? _getTypeColor(type).withOpacity(0.06)
                      : AccountingTheme.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: isLeaf
                      ? AccountingTheme.borderColor
                      : (isExpanded || forceExpand)
                          ? _getTypeColor(type).withOpacity(0.4)
                          : AccountingTheme.borderColor),
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
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_left,
                      color: _getTypeColor(type),
                      size: 20,
                    ),
                  )
                else
                  const SizedBox(width: 20),
                const SizedBox(width: 6),
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
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  code,
                  style: GoogleFonts.cairo(
                    color: AccountingTheme.neonBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: GoogleFonts.cairo(
                      color: isActive
                          ? AccountingTheme.textPrimary
                          : AccountingTheme.textMuted,
                      fontSize: 14,
                      fontWeight: isLeaf ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                ),
                // عدد الأبناء
                if (!isLeaf)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color: _getTypeColor(type).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${children.length}',
                      style: GoogleFonts.cairo(
                          color: _getTypeColor(type),
                          fontSize: 11,
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
                    style: GoogleFonts.cairo(
                        color: _getTypeColor(type), fontSize: 11),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatNumber(balance),
                  style: GoogleFonts.cairo(
                    color: (balance is num && balance < 0)
                        ? AccountingTheme.danger
                        : AccountingTheme.neonGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      color: AccountingTheme.textMuted, size: 18),
                  color: AccountingTheme.bgCard,
                  onSelected: (action) => _handleAccountAction(action, node),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'add_child',
                        child: Text('إضافة حساب فرعي',
                            style:
                                TextStyle(color: AccountingTheme.textPrimary))),
                    const PopupMenuItem(
                        value: 'edit',
                        child: Text('تعديل',
                            style:
                                TextStyle(color: AccountingTheme.textPrimary))),
                    if (isLeaf)
                      const PopupMenuItem(
                          value: 'statement',
                          child: Text('كشف حساب',
                              style: TextStyle(
                                  color: AccountingTheme.textPrimary))),
                    const PopupMenuItem(
                        value: 'delete',
                        child: Text('حذف',
                            style: TextStyle(color: AccountingTheme.danger))),
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
                size: 48, color: AccountingTheme.textMuted.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text('لا توجد نتائج',
                style: GoogleFonts.cairo(
                    fontSize: 16, color: AccountingTheme.textMuted)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final a = filtered[i];
        final type = a['AccountType'] ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AccountingTheme.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AccountingTheme.borderColor),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 1)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.all(14),
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
                            size: 18, color: _getTypeColor(type)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      a['Code'] ?? '',
                      style: GoogleFonts.cairo(
                        color: AccountingTheme.neonBlue,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        a['Name'] ?? '',
                        style: GoogleFonts.cairo(
                            color: AccountingTheme.textPrimary, fontSize: 14),
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
                        style: GoogleFonts.cairo(
                            color: _getTypeColor(type), fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatNumber(a['CurrentBalance']),
                      style: GoogleFonts.cairo(
                          color: AccountingTheme.neonGreen,
                          fontWeight: FontWeight.bold),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          color: AccountingTheme.textMuted, size: 18),
                      color: AccountingTheme.bgCard,
                      onSelected: (action) => _handleAccountAction(action, a),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'edit',
                            child: Text('تعديل',
                                style: TextStyle(
                                    color: AccountingTheme.textPrimary))),
                        const PopupMenuItem(
                            value: 'statement',
                            child: Text('كشف حساب',
                                style: TextStyle(
                                    color: AccountingTheme.textPrimary))),
                        const PopupMenuItem(
                            value: 'delete',
                            child: Text('حذف',
                                style:
                                    TextStyle(color: AccountingTheme.danger))),
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
          backgroundColor: AccountingTheme.bgCard,
          title: Text('إضافة حساب فرعي تحت: $parentName',
              style: const TextStyle(
                  color: AccountingTheme.textPrimary, fontSize: 16)),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // عرض الأب
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _getTypeColor(parentType).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _getTypeColor(parentType).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.account_tree,
                            size: 16, color: _getTypeColor(parentType)),
                        const SizedBox(width: 8),
                        Text('$parentCode - $parentName',
                            style: GoogleFonts.cairo(
                                fontSize: 13,
                                color: _getTypeColor(parentType),
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildField('رمز الحساب', codeCtrl, hint: suggestedCode),
                  const SizedBox(height: 12),
                  _buildField('اسم الحساب', nameCtrl),
                  const SizedBox(height: 12),
                  _buildField('الاسم بالإنجليزية', nameEnCtrl),
                  const SizedBox(height: 12),
                  _buildField('الرصيد الافتتاحي', balanceCtrl, isNumber: true),
                  const SizedBox(height: 12),
                  _buildField('الوصف', descCtrl, maxLines: 2),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.neonGreen,
                  foregroundColor: Colors.black),
              onPressed: () async {
                if (codeCtrl.text.isEmpty || nameCtrl.text.isEmpty) {
                  _showSnackBar(
                      'الرجاء ملء الحقول المطلوبة', AccountingTheme.warning);
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
                      'تم إنشاء الحساب الفرعي بنجاح', AccountingTheme.success);
                  // توسيع الأب لإظهار الفرع الجديد
                  _expandedNodes.add(parentId);
                  _loadData();
                } else {
                  _showSnackBar(
                      result['message'] ?? 'خطأ', AccountingTheme.danger);
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
            backgroundColor: AccountingTheme.bgCard,
            title: const Text('إضافة حساب جديد',
                style: TextStyle(color: AccountingTheme.textPrimary)),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildField('رمز الحساب', codeCtrl, hint: '1100'),
                    const SizedBox(height: 12),
                    _buildField('اسم الحساب', nameCtrl),
                    const SizedBox(height: 12),
                    _buildField('الاسم بالإنجليزية', nameEnCtrl),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 12),
                    _buildField('الرصيد الافتتاحي', balanceCtrl,
                        isNumber: true),
                    const SizedBox(height: 12),
                    _buildField('الوصف', descCtrl, maxLines: 2),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء',
                    style: TextStyle(color: AccountingTheme.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AccountingTheme.neonGreen,
                    foregroundColor: Colors.black),
                onPressed: () async {
                  if (codeCtrl.text.isEmpty || nameCtrl.text.isEmpty) {
                    _showSnackBar(
                        'الرجاء ملء الحقول المطلوبة', AccountingTheme.warning);
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
                        'تم إنشاء الحساب بنجاح', AccountingTheme.success);
                    _loadData();
                  } else {
                    _showSnackBar(
                        result['message'] ?? 'خطأ', AccountingTheme.danger);
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
            backgroundColor: AccountingTheme.bgCard,
            title: Text('تعديل: ${account['Name']}',
                style: const TextStyle(color: AccountingTheme.textPrimary)),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildField('اسم الحساب', nameCtrl),
                    const SizedBox(height: 12),
                    _buildField('الاسم بالإنجليزية', nameEnCtrl),
                    const SizedBox(height: 12),
                    _buildField('الرصيد الافتتاحي', openingBalanceCtrl,
                        isNumber: true),
                    const SizedBox(height: 12),
                    _buildField('الوصف', descCtrl, maxLines: 2),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('نشط',
                          style: TextStyle(color: AccountingTheme.textPrimary)),
                      value: isActive,
                      activeColor: AccountingTheme.accent,
                      onChanged: (v) => setDialogState(() => isActive = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء',
                    style: TextStyle(color: AccountingTheme.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AccountingTheme.neonGreen,
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
                    _showSnackBar('تم التعديل بنجاح', AccountingTheme.success);
                    _loadData();
                  } else {
                    _showSnackBar(
                        result['message'] ?? 'خطأ', AccountingTheme.danger);
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
          child: CircularProgressIndicator(color: AccountingTheme.accent)),
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
              backgroundColor: AccountingTheme.bgCard,
              titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          gradient: AccountingTheme.neonBlueGradient,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.receipt_long,
                            color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'كشف حساب: ${account['Name']}',
                              style: GoogleFonts.cairo(
                                  color: AccountingTheme.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${acctInfo['Code'] ?? account['Code'] ?? ''} - ${_accountTypeLabels[acctInfo['AccountType'] ?? account['AccountType']] ?? ''}',
                              style: GoogleFonts.cairo(
                                  color: AccountingTheme.textMuted,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // ملخص الأرصدة
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AccountingTheme.bgCardHover,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AccountingTheme.borderColor),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text('إجمالي مدين',
                                  style: GoogleFonts.cairo(
                                      color: AccountingTheme.textMuted,
                                      fontSize: 11)),
                              Text(_formatNumber(totalDebit),
                                  style: GoogleFonts.cairo(
                                      color: AccountingTheme.success,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Container(
                            width: 1,
                            height: 30,
                            color: AccountingTheme.borderColor),
                        Expanded(
                          child: Column(
                            children: [
                              Text('إجمالي دائن',
                                  style: GoogleFonts.cairo(
                                      color: AccountingTheme.textMuted,
                                      fontSize: 11)),
                              Text(_formatNumber(totalCredit),
                                  style: GoogleFonts.cairo(
                                      color: AccountingTheme.danger,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Container(
                            width: 1,
                            height: 30,
                            color: AccountingTheme.borderColor),
                        Expanded(
                          child: Column(
                            children: [
                              Text('الرصيد',
                                  style: GoogleFonts.cairo(
                                      color: AccountingTheme.textMuted,
                                      fontSize: 11)),
                              Text(_formatNumber(balance),
                                  style: GoogleFonts.cairo(
                                      color: (balance is num && balance < 0)
                                          ? AccountingTheme.danger
                                          : AccountingTheme.neonBlue,
                                      fontSize: 14,
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
                width: 650,
                height: 400,
                child: lines.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long,
                                color:
                                    AccountingTheme.textMuted.withOpacity(0.3),
                                size: 48),
                            const SizedBox(height: 12),
                            Text('لا توجد حركات مرحّلة على هذا الحساب',
                                style: GoogleFonts.cairo(
                                    color: AccountingTheme.textMuted,
                                    fontSize: 14)),
                            const SizedBox(height: 4),
                            Text(
                                'الرصيد الحالي قد يكون من الرصيد الافتتاحي أو حركات غير مرحّلة',
                                style: GoogleFonts.cairo(
                                    color: AccountingTheme.textMuted,
                                    fontSize: 11)),
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
                              color: AccountingTheme.bgCardHover,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6)),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                    width: 60,
                                    child: Text('رقم القيد',
                                        style: GoogleFonts.cairo(
                                            color: AccountingTheme.textMuted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold))),
                                SizedBox(
                                    width: 80,
                                    child: Text('التاريخ',
                                        style: GoogleFonts.cairo(
                                            color: AccountingTheme.textMuted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold))),
                                Expanded(
                                    child: Text('البيان',
                                        style: GoogleFonts.cairo(
                                            color: AccountingTheme.textMuted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold))),
                                SizedBox(
                                    width: 80,
                                    child: Text('مدين',
                                        style: GoogleFonts.cairo(
                                            color: AccountingTheme.success,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center)),
                                SizedBox(
                                    width: 80,
                                    child: Text('دائن',
                                        style: GoogleFonts.cairo(
                                            color: AccountingTheme.danger,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center)),
                              ],
                            ),
                          ),
                          const Divider(
                              color: AccountingTheme.borderColor, height: 1),
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
                                        : AccountingTheme.bgCardHover
                                            .withOpacity(0.5),
                                    border: Border(
                                        bottom: BorderSide(
                                            color: AccountingTheme.borderColor
                                                .withOpacity(0.5))),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                          width: 60,
                                          child: Text(
                                              '#${e['EntryNumber'] ?? ''}',
                                              style: GoogleFonts.cairo(
                                                  color:
                                                      AccountingTheme.neonBlue,
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      SizedBox(
                                          width: 80,
                                          child: Text(
                                              _formatDate(e['EntryDate']),
                                              style: GoogleFonts.cairo(
                                                  color:
                                                      AccountingTheme.textMuted,
                                                  fontSize: 11))),
                                      Expanded(
                                          child: Text(
                                              e['Description'] ??
                                                  e['EntryDescription'] ??
                                                  '',
                                              style: GoogleFonts.cairo(
                                                  color: AccountingTheme
                                                      .textPrimary,
                                                  fontSize: 12),
                                              overflow: TextOverflow.ellipsis)),
                                      SizedBox(
                                          width: 80,
                                          child: Text(
                                              debit > 0
                                                  ? _formatNumber(debit)
                                                  : '-',
                                              style: GoogleFonts.cairo(
                                                  color: debit > 0
                                                      ? AccountingTheme.success
                                                      : AccountingTheme
                                                          .textMuted,
                                                  fontSize: 12),
                                              textAlign: TextAlign.center)),
                                      SizedBox(
                                          width: 80,
                                          child: Text(
                                              credit > 0
                                                  ? _formatNumber(credit)
                                                  : '-',
                                              style: GoogleFonts.cairo(
                                                  color: credit > 0
                                                      ? AccountingTheme.danger
                                                      : AccountingTheme
                                                          .textMuted,
                                                  fontSize: 12),
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
                      style: GoogleFonts.cairo(color: AccountingTheme.accent)),
                ),
              ],
            ),
          ),
        );
      } else {
        _showSnackBar(result['message'] ?? 'خطأ', AccountingTheme.danger);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('خطأ: $e', AccountingTheme.danger);
    }
  }

  void _confirmDelete(dynamic account) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: const Text('تأكيد الحذف',
              style: TextStyle(color: AccountingTheme.textPrimary)),
          content: Text('هل تريد حذف الحساب "${account['Name']}"؟',
              style: const TextStyle(color: AccountingTheme.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.danger),
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await AccountingService.instance
                    .deleteAccount(account['Id']);
                if (result['success'] == true) {
                  _showSnackBar('تم الحذف', AccountingTheme.success);
                  _loadData();
                } else {
                  _showSnackBar(
                      result['message'] ?? 'خطأ', AccountingTheme.danger);
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
      style: const TextStyle(color: AccountingTheme.textPrimary),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AccountingTheme.textMuted),
        hintStyle: const TextStyle(color: AccountingTheme.textMuted),
        filled: true,
        fillColor: AccountingTheme.bgCardHover,
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
      dropdownColor: AccountingTheme.bgCard,
      style: const TextStyle(color: AccountingTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AccountingTheme.textMuted),
        filled: true,
        fillColor: AccountingTheme.bgCardHover,
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
        return AccountingTheme.info;
      case 'Liabilities':
        return AccountingTheme.warning;
      case 'Equity':
        return const Color(0xFF8B5CF6);
      case 'Revenue':
        return AccountingTheme.success;
      case 'Expenses':
        return AccountingTheme.danger;
      default:
        return AccountingTheme.textMuted;
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
      final d = DateTime.parse(date.toString());
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
