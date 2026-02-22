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
                  // المحتوى - بطاقات موحدة
                  Expanded(child: _buildUnifiedList()),
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

  /// ربط كل مصروف بسجل الدفع للشهر المحدد
  Map<String, dynamic>? _findPaymentForExpense(Map<String, dynamic> expense) {
    final expenseId = expense['Id'];
    for (final p in _payments) {
      if (p['FixedExpenseId'] == expenseId) return p as Map<String, dynamic>;
    }
    return null;
  }

  // ═══ قائمة موحدة: كل بطاقة = مصروف + حالة الدفع ═══
  Widget _buildUnifiedList() {
    final filtered = _selectedCategoryFilter == null
        ? _fixedExpenses
        : _fixedExpenses
            .where((e) => e['Category'] == _selectedCategoryFilter)
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFFE8EAF6),
          child: Row(
            children: [
              const Icon(Icons.receipt_long,
                  size: 18, color: Color(0xFF1A237E)),
              const SizedBox(width: 8),
              Text(
                _selectedCategoryFilter == null
                    ? 'المصاريف الثابتة - ${_arabicMonth(_selectedMonth)} $_selectedYear'
                    : '${_getCategoryInfo(_selectedCategoryFilter)['label']} - ${_arabicMonth(_selectedMonth)} $_selectedYear',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF1A237E)),
              ),
              const Spacer(),
              Text('${filtered.length} مصروف',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('لا توجد مصاريف ثابتة مسجلة',
                      style: TextStyle(color: Colors.grey, fontSize: 14)))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final item = filtered[i] as Map<String, dynamic>;
                    final catInfo = _getCategoryInfo(item['Category']);
                    final isActive = item['IsActive'] == true;
                    final payment = _findPaymentForExpense(item);
                    final isPaid = payment?['IsPaid'] == true;
                    final catColor = catInfo['color'] as Color;

                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isPaid
                              ? Colors.green.withValues(alpha: 0.4)
                              : Colors.red.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      color:
                          isPaid ? Colors.green.withValues(alpha: 0.03) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            // أيقونة الفئة
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: catColor.withValues(alpha: 0.15),
                              child: Icon(catInfo['icon'] as IconData,
                                  color: catColor, size: 22),
                            ),
                            const SizedBox(width: 14),
                            // معلومات المصروف
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['Name'] ?? '',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      decoration: isActive
                                          ? null
                                          : TextDecoration.lineThrough,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color:
                                              catColor.withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          item['CategoryAr'] ?? '',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: catColor,
                                              fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        '${_formatNumber(item['MonthlyAmount'])} د.ع',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1A237E),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // حالة الدفع + أزرار
                            if (isPaid) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color:
                                          Colors.green.withValues(alpha: 0.3)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle,
                                        color: Colors.green, size: 16),
                                    SizedBox(width: 4),
                                    Text('مدفوع',
                                        style: TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.undo, size: 20),
                                tooltip: 'إلغاء الدفع',
                                onPressed: () => _unpayExpense(payment!),
                                color: Colors.orange,
                                splashRadius: 20,
                              ),
                            ] else ...[
                              ElevatedButton.icon(
                                onPressed: isActive
                                    ? () => _payExpenseFromItem(item)
                                    : null,
                                icon: const Icon(Icons.payment, size: 16),
                                label: const Text('تسديد',
                                    style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1A237E),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                            const SizedBox(width: 4),
                            // قائمة الإجراءات
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert,
                                  color: Colors.grey),
                              splashRadius: 20,
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit,
                                            size: 18, color: Colors.blue),
                                        SizedBox(width: 8),
                                        Text('تعديل'),
                                      ],
                                    )),
                                PopupMenuItem(
                                  value: 'toggle',
                                  child: Row(
                                    children: [
                                      Icon(
                                          isActive
                                              ? Icons.pause_circle
                                              : Icons.play_circle,
                                          size: 18,
                                          color: Colors.orange),
                                      const SizedBox(width: 8),
                                      Text(isActive ? 'إيقاف' : 'تفعيل'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete,
                                            size: 18, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('حذف',
                                            style:
                                                TextStyle(color: Colors.red)),
                                      ],
                                    )),
                              ],
                              onSelected: (v) => _onExpenseAction(v, item),
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

  int _categoryKeyToValue(String? key) {
    const map = {
      'OfficeRent': 0,
      'GeneratorCost': 1,
      'Internet': 2,
      'Electricity': 3,
      'Water': 4,
      'Other': 99,
    };
    return map[key] ?? 99;
  }

  Future<void> _showEditDialog(Map<String, dynamic> item) async {
    final nameCtrl = TextEditingController(text: item['Name']);
    final amountCtrl =
        TextEditingController(text: '${item['MonthlyAmount'] ?? 0}');
    final descCtrl = TextEditingController(text: item['Description'] ?? '');
    int selectedCat = _categoryKeyToValue(item['Category']);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
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
      ),
    );

    if (result != true) return;
    try {
      final res = await _api.updateFixedExpense(item['Id'], {
        'Name': nameCtrl.text,
        'MonthlyAmount': double.tryParse(amountCtrl.text),
        'Description': descCtrl.text,
        'Category': selectedCat,
      });
      if (res['success'] == true) {
        _showSuccess('تم التعديل');
        _loadData();
      }
    } catch (e) {
      _showError('خطأ: $e');
    }
  }

  // ═══ تسديد من بطاقة المصروف مباشرة ═══
  Future<void> _payExpenseFromItem(Map<String, dynamic> item) async {
    if (_companyId == null) return;
    try {
      final res = await _api.payFixedExpense(
        fixedExpenseId: item['Id'],
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
