import 'package:flutter/material.dart';
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';

/// صفحة إدارة المصاريف الثابتة الشهرية (إيجارات، مولد، ...)
class FixedExpensesPage extends StatefulWidget {
  final String? companyId;
  const FixedExpensesPage({super.key, this.companyId});

  @override
  State<FixedExpensesPage> createState() => _FixedExpensesPageState();
}

class _FixedExpensesPageState extends State<FixedExpensesPage> {
  final _api = AccountingService.instance;
  String? get _companyId =>
      widget.companyId ?? VpsAuthService.instance.currentCompanyId;

  bool _loading = true;
  List<dynamic> _fixedExpenses = [];
  List<dynamic> _payments = [];
  Map<String, dynamic>? _paymentSummary;

  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  /// فلتر الفئة: null = الكل
  String? _selectedCategoryFilter;

  // فئات المصاريف
  static const _categories = [
    {
      'value': 0,
      'label': 'إيجار مكتب',
      'icon': Icons.business,
      'color': Color(0xFFE67E22)
    },
    {
      'value': 1,
      'label': 'تكلفة مولد',
      'icon': Icons.flash_on,
      'color': Color(0xFFF39C12)
    },
    {
      'value': 2,
      'label': 'إنترنت',
      'icon': Icons.wifi,
      'color': Color(0xFF3498DB)
    },
    {
      'value': 3,
      'label': 'كهرباء',
      'icon': Icons.electrical_services,
      'color': Color(0xFF2ECC71)
    },
    {
      'value': 4,
      'label': 'ماء',
      'icon': Icons.water_drop,
      'color': Color(0xFF1ABC9C)
    },
    {
      'value': 99,
      'label': 'أخرى',
      'icon': Icons.more_horiz,
      'color': Color(0xFF95A5A6)
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getFixedExpenses(companyId: _companyId),
        _api.getFixedExpensePayments(
          companyId: _companyId,
          month: _selectedMonth,
          year: _selectedYear,
        ),
      ]);

      final expRes = results[0];
      final payRes = results[1];

      setState(() {
        if (expRes['success'] == true) {
          final d = expRes['data'];
          _fixedExpenses =
              (d is List) ? d : ((d is Map ? d['data'] : null) as List?) ?? [];
        }
        if (payRes['success'] == true) {
          final d = payRes['data'];
          if (d is List) {
            _payments = d;
            _paymentSummary = null;
          } else if (d is Map) {
            _payments = (d['data'] as List?) ?? [];
            _paymentSummary = d['summary'] as Map<String, dynamic>?;
          }
        }
      });
    } catch (e) {
      _showError('خطأ في تحميل البيانات: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }

  String _formatNumber(dynamic v) {
    if (v == null) return '0';
    if (v is int) return v.toString();
    if (v is double) return v.round().toString();
    final n = double.tryParse(v.toString());
    return n != null ? n.round().toString() : v.toString();
  }

  String _arabicMonth(int m) {
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return months[m - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المصاريف الثابتة الشهرية',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: 'تحديث',
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddDialog,
          icon: const Icon(Icons.add),
          label: const Text('إضافة مصروف ثابت'),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // شريط الشهر/السنة + الملخص
                  _buildHeader(),
                  // فلتر الفئات
                  _buildCategoryFilter(),
                  const Divider(height: 1),
                  // المحتوى
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // قائمة المصاريف الثابتة
                        Expanded(flex: 2, child: _buildFixedExpensesList()),
                        const VerticalDivider(width: 1),
                        // سجلات الدفع الشهرية
                        Expanded(flex: 3, child: _buildPaymentsList()),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    final total = _paymentSummary?['TotalAmount'] ?? 0;
    final paid = _paymentSummary?['PaidAmount'] ?? 0;
    final unpaid = _paymentSummary?['UnpaidAmount'] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.grey.shade100,
      child: Row(
        children: [
          // فلتر الشهر
          const Icon(Icons.calendar_today, size: 18, color: Color(0xFF1A237E)),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _selectedMonth,
            items: List.generate(12, (i) {
              final m = i + 1;
              return DropdownMenuItem(value: m, child: Text(_arabicMonth(m)));
            }),
            onChanged: (v) {
              if (v != null) {
                setState(() => _selectedMonth = v);
                _loadData();
              }
            },
          ),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _selectedYear,
            items: List.generate(5, (i) {
              final y = DateTime.now().year - i;
              return DropdownMenuItem(value: y, child: Text('$y'));
            }),
            onChanged: (v) {
              if (v != null) {
                setState(() => _selectedYear = v);
                _loadData();
              }
            },
          ),
          const SizedBox(width: 24),
          // ملخص
          _headerStat('إجمالي', _formatNumber(total), Colors.blue),
          const SizedBox(width: 16),
          _headerStat('مدفوع', _formatNumber(paid), Colors.green),
          const SizedBox(width: 16),
          _headerStat('غير مدفوع', _formatNumber(unpaid), Colors.red),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: FilterChip(
                label: const Text('الكل', style: TextStyle(fontSize: 12)),
                selected: _selectedCategoryFilter == null,
                onSelected: (_) =>
                    setState(() => _selectedCategoryFilter = null),
                selectedColor: const Color(0xFF1A237E).withValues(alpha: 0.15),
                checkmarkColor: const Color(0xFF1A237E),
                labelStyle: TextStyle(
                  color: _selectedCategoryFilter == null
                      ? const Color(0xFF1A237E)
                      : Colors.grey.shade700,
                  fontWeight: _selectedCategoryFilter == null
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
            ..._categories.map((cat) {
              final catKey = _categoryValueToKey(cat['value'] as int);
              final isSelected = _selectedCategoryFilter == catKey;
              final color = cat['color'] as Color;
              return Padding(
                padding: const EdgeInsets.only(left: 4),
                child: FilterChip(
                  avatar: Icon(cat['icon'] as IconData,
                      size: 16, color: isSelected ? color : Colors.grey),
                  label: Text(cat['label'] as String,
                      style: const TextStyle(fontSize: 12)),
                  selected: isSelected,
                  onSelected: (_) => setState(() {
                    _selectedCategoryFilter = isSelected ? null : catKey;
                  }),
                  selectedColor: color.withValues(alpha: 0.15),
                  checkmarkColor: color,
                  labelStyle: TextStyle(
                    color: isSelected ? color : Colors.grey.shade700,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _categoryValueToKey(int value) {
    const map = {
      0: 'OfficeRent',
      1: 'GeneratorCost',
      2: 'Internet',
      3: 'Electricity',
      4: 'Water',
      99: 'Other',
    };
    return map[value] ?? 'Other';
  }

  Widget _headerStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(width: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  // ═══ قائمة المصاريف الثابتة (الجانب الأيسر) ═══
  Widget _buildFixedExpensesList() {
    final filtered = _selectedCategoryFilter == null
        ? _fixedExpenses
        : _fixedExpenses
            .where((e) => e['Category'] == _selectedCategoryFilter)
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFFE8EAF6),
          child: Text(
              _selectedCategoryFilter == null
                  ? 'المصاريف الثابتة المسجلة'
                  : 'المصاريف الثابتة المسجلة (${_getCategoryInfo(_selectedCategoryFilter)['label']})',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF1A237E))),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('لا توجد مصاريف ثابتة مسجلة',
                      style: TextStyle(color: Colors.grey)))
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (ctx, i) {
                    final item = filtered[i];
                    final catInfo = _getCategoryInfo(item['Category']);
                    final isActive = item['IsActive'] == true;

                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: (catInfo['color'] as Color)
                              .withValues(alpha: 0.15),
                          child: Icon(catInfo['icon'] as IconData,
                              color: catInfo['color'] as Color, size: 20),
                        ),
                        title: Text(item['Name'] ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              decoration:
                                  isActive ? null : TextDecoration.lineThrough,
                            )),
                        subtitle: Text(
                          '${item['CategoryAr']} • ${_formatNumber(item['MonthlyAmount'])} شهرياً',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                        trailing: PopupMenuButton(
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                                value: 'edit', child: Text('تعديل')),
                            PopupMenuItem(
                              value: 'toggle',
                              child: Text(isActive ? 'إيقاف' : 'تفعيل'),
                            ),
                            const PopupMenuItem(
                                value: 'delete',
                                child: Text('حذف',
                                    style: TextStyle(color: Colors.red))),
                          ],
                          onSelected: (v) => _onExpenseAction(v, item),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ═══ سجلات الدفع الشهرية (الجانب الأيمن) ═══
  Widget _buildPaymentsList() {
    final filtered = _selectedCategoryFilter == null
        ? _payments
        : _payments
            .where((p) => p['Category'] == _selectedCategoryFilter)
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFFE8EAF6),
          child: Text(
            'سجلات الدفع - ${_arabicMonth(_selectedMonth)} $_selectedYear',
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFF1A237E)),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('لا توجد سجلات دفع',
                      style: TextStyle(color: Colors.grey)))
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (ctx, i) {
                    final p = filtered[i];
                    final isPaid = p['IsPaid'] == true;
                    final catInfo = _getCategoryInfo(p['Category']);

                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      color: isPaid
                          ? Colors.green.withValues(alpha: 0.04)
                          : Colors.red.withValues(alpha: 0.04),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isPaid
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.15),
                          child: Icon(
                            isPaid ? Icons.check_circle : Icons.pending,
                            color: isPaid ? Colors.green : Colors.red,
                            size: 22,
                          ),
                        ),
                        title: Text(p['ExpenseName'] ?? '',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(
                          '${p['CategoryAr']} • ${_formatNumber(p['Amount'])} د.ع',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isPaid) ...[
                              const Icon(Icons.check,
                                  color: Colors.green, size: 18),
                              const SizedBox(width: 4),
                              const Text('مدفوع',
                                  style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.undo, size: 18),
                                tooltip: 'إلغاء الدفع',
                                onPressed: () => _unpayExpense(p),
                                color: Colors.orange,
                              ),
                            ] else
                              ElevatedButton.icon(
                                onPressed: () => _payExpense(p),
                                icon: const Icon(Icons.payment, size: 16),
                                label: const Text('تسديد',
                                    style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1A237E),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                ),
                              ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              tooltip: 'حذف سجل الدفع',
                              onPressed: () => _deletePayment(p),
                              color: Colors.red.shade400,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Map<String, dynamic> _getCategoryInfo(String? category) {
    final map = {
      'OfficeRent': _categories[0],
      'GeneratorCost': _categories[1],
      'Internet': _categories[2],
      'Electricity': _categories[3],
      'Water': _categories[4],
      'Other': _categories[5],
    };
    return (map[category] ?? _categories[5]) as Map<String, dynamic>;
  }

  // ═══ إضافة مصروف ثابت ═══
  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    int selectedCat = 0;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('إضافة مصروف ثابت'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم المصروف',
                    hintText: 'مثال: إيجار المكتب الرئيسي',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: selectedCat,
                  decoration: const InputDecoration(
                    labelText: 'الفئة',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories.map((c) {
                    return DropdownMenuItem(
                      value: c['value'] as int,
                      child: Row(
                        children: [
                          Icon(c['icon'] as IconData,
                              color: c['color'] as Color, size: 18),
                          const SizedBox(width: 8),
                          Text(c['label'] as String),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedCat = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'المبلغ الشهري (د.ع)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
              ),
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );

    if (result != true || _companyId == null) return;
    if (nameCtrl.text.isEmpty || amountCtrl.text.isEmpty) {
      _showError('يرجى ملء جميع الحقول المطلوبة');
      return;
    }

    final amount = double.tryParse(amountCtrl.text);
    if (amount == null || amount <= 0) {
      _showError('المبلغ غير صحيح');
      return;
    }

    try {
      final res = await _api.createFixedExpense(
        name: nameCtrl.text,
        category: selectedCat,
        monthlyAmount: amount,
        description: descCtrl.text.isEmpty ? null : descCtrl.text,
        companyId: _companyId!,
      );
      if (res['success'] == true) {
        _showSuccess('تم إضافة المصروف الثابت');
        _loadData();
      } else {
        _showError(res['message'] ?? 'خطأ');
      }
    } catch (e) {
      _showError('خطأ: $e');
    }
  }

  // ═══ إجراءات على المصروف ═══
  void _onExpenseAction(String action, Map<String, dynamic> item) async {
    final id = item['Id'];
    if (action == 'edit') {
      await _showEditDialog(item);
    } else if (action == 'toggle') {
      final isActive = item['IsActive'] == true;
      try {
        final res = await _api.updateFixedExpense(id, {'IsActive': !isActive});
        if (res['success'] == true) {
          _showSuccess(isActive ? 'تم إيقاف المصروف' : 'تم تفعيل المصروف');
          _loadData();
        }
      } catch (e) {
        _showError('خطأ: $e');
      }
    } else if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('هل تريد حذف "${item['Name']}"؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm == true) {
        try {
          final res = await _api.deleteFixedExpense(id);
          if (res['success'] == true) {
            _showSuccess('تم الحذف');
            _loadData();
          }
        } catch (e) {
          _showError('خطأ: $e');
        }
      }
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> item) async {
    final nameCtrl = TextEditingController(text: item['Name']);
    final amountCtrl =
        TextEditingController(text: '${item['MonthlyAmount'] ?? 0}');
    final descCtrl = TextEditingController(text: item['Description'] ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل المصروف الثابت'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'اسم المصروف', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'المبلغ الشهري', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'ملاحظات', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
            ),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (result != true) return;
    try {
      final res = await _api.updateFixedExpense(item['Id'], {
        'Name': nameCtrl.text,
        'MonthlyAmount': double.tryParse(amountCtrl.text),
        'Description': descCtrl.text,
      });
      if (res['success'] == true) {
        _showSuccess('تم التعديل');
        _loadData();
      }
    } catch (e) {
      _showError('خطأ: $e');
    }
  }

  // ═══ تسديد / إلغاء دفع ═══
  Future<void> _payExpense(Map<String, dynamic> payment) async {
    if (_companyId == null) return;
    try {
      final res = await _api.payFixedExpense(
        fixedExpenseId: payment['FixedExpenseId'],
        month: _selectedMonth,
        year: _selectedYear,
        companyId: _companyId!,
      );
      if (res['success'] == true) {
        _showSuccess('تم تسجيل الدفع');
        _loadData();
      } else {
        _showError(res['message'] ?? 'خطأ');
      }
    } catch (e) {
      _showError('خطأ: $e');
    }
  }

  Future<void> _unpayExpense(Map<String, dynamic> payment) async {
    try {
      final res = await _api.unpayFixedExpense(payment['Id']);
      if (res['success'] == true) {
        _showSuccess('تم إلغاء الدفع');
        _loadData();
      }
    } catch (e) {
      _showError('خطأ: $e');
    }
  }

  Future<void> _deletePayment(Map<String, dynamic> payment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content:
            Text('هل تريد حذف سجل الدفع "${payment['ExpenseName'] ?? ''}"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final res = await _api.deleteFixedExpensePayment(payment['Id']);
      if (res['success'] == true) {
        _showSuccess('تم حذف سجل الدفع');
        _loadData();
      } else {
        _showError(res['message'] ?? 'خطأ في الحذف');
      }
    } catch (e) {
      _showError('خطأ: $e');
    }
  }
}
