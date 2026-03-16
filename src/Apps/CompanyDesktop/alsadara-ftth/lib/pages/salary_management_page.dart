/// اسم الصفحة: إدارة الرواتب
/// وصف الصفحة: إنشاء مسيّر الرواتب مع الربط التلقائي بالحضور والإجازات
/// المؤلف: تطبيق السدارة
library;

import 'package:flutter/material.dart';
import '../utils/responsive_helper.dart';
import '../services/attendance_api_service.dart';
import '../services/vps_auth_service.dart';

class SalaryManagementPage extends StatefulWidget {
  final String? companyId;

  const SalaryManagementPage({super.key, this.companyId});

  @override
  State<SalaryManagementPage> createState() => _SalaryManagementPageState();
}

class _SalaryManagementPageState extends State<SalaryManagementPage>
    with SingleTickerProviderStateMixin {
  final AttendanceApiService _api = AttendanceApiService.instance;
  late TabController _tabController;

  // Payroll tab
  List<Map<String, dynamic>> _salaries = [];
  Map<String, dynamic>? _summary;
  bool _loading = true;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  // Policy tab
  List<Map<String, dynamic>> _policies = [];
  bool _policyLoading = true;

  String? get _companyId =>
      widget.companyId ?? VpsAuthService.instance.currentCompanyId;
  String? get _userId => VpsAuthService.instance.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 0) _loadSalaries();
        if (_tabController.index == 1) _loadPolicies();
      }
    });
    _loadSalaries();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSalaries() async {
    setState(() => _loading = true);
    try {
      final data = await _api.getSalaries(
        companyId: _companyId,
        month: _selectedMonth,
        year: _selectedYear,
      );
      setState(() {
        _salaries = List<Map<String, dynamic>>.from(data['data'] ?? []);
        _summary = data['summary'] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل الرواتب')),
        );
      }
    }
  }

  Future<void> _loadPolicies() async {
    if (_companyId == null) return;
    setState(() => _policyLoading = true);
    try {
      final data = await _api.getSalaryPolicies(_companyId!);
      setState(() {
        _policies = List<Map<String, dynamic>>.from(data['data'] ?? []);
        _policyLoading = false;
      });
    } catch (e) {
      setState(() => _policyLoading = false);
    }
  }

  Future<void> _generatePayroll() async {
    if (_companyId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إنشاء مسيّر رواتب'),
          content: Text(
            'هل تريد إنشاء مسيّر رواتب لشهر $_selectedMonth/$_selectedYear؟\n'
            'سيتم حساب الخصومات والمكافآت تلقائياً من بيانات الحضور والإجازات.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
              ),
              child: const Text('إنشاء', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await _api.generateMonthlySalaries(
        companyId: _companyId!,
        month: _selectedMonth,
        year: _selectedYear,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'تم إنشاء المسيّر'),
            backgroundColor: Colors.green,
          ),
        );
        _loadSalaries();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _payAllSalaries() async {
    if (_companyId == null || _userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('صرف جميع الرواتب'),
          content: Text(
            'هل تريد صرف جميع رواتب شهر $_selectedMonth/$_selectedYear؟\n'
            'الإجمالي: ${_formatCurrency(_summary?['TotalNet'] ?? 0)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child:
                  const Text('صرف الكل', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await _api.payAllSalaries(
        companyId: _companyId!,
        month: _selectedMonth,
        year: _selectedYear,
        paidById: _userId!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'تم صرف الرواتب'),
            backgroundColor: Colors.green,
          ),
        );
        _loadSalaries();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deletePayroll() async {
    if (_companyId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف مسيّر الرواتب'),
          content: Text(
            'هل تريد حذف مسيّر رواتب شهر $_selectedMonth/$_selectedYear؟\n'
            'لا يمكن حذف المسيّر إذا تم صرف أي راتب.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await _api.deletePayroll(
        companyId: _companyId!,
        month: _selectedMonth,
        year: _selectedYear,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'تم الحذف'),
            backgroundColor: Colors.orange,
          ),
        );
        _loadSalaries();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _paySingleSalary(Map<String, dynamic> salary) async {
    if (_userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('صرف راتب'),
          content: Text(
            'هل تريد صرف راتب ${salary['UserName'] ?? 'الموظف'}؟\n'
            'المبلغ: ${_formatCurrency(salary['NetSalary'] ?? 0)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              child: const Text('صرف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await _api.paySalary(
        salary['Id'],
        paidById: _userId!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'تم صرف الراتب'),
            backgroundColor: Colors.green,
          ),
        );
        _loadSalaries();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatCurrency(dynamic amount) {
    final val = (amount is int)
        ? amount
        : (amount is double)
            ? amount.round()
            : (double.tryParse(amount.toString()) ?? 0).round();
    return '$val د.ع';
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      final dt = DateTime.parse(date.toString());
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return date.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: Text('إدارة الرواتب',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: r.appBarTitleSize)),
          backgroundColor: Colors.teal[700],
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(icon: Icon(Icons.receipt_long), text: 'مسيّر الرواتب'),
              Tab(icon: Icon(Icons.settings), text: 'سياسة الرواتب'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildPayrollTab(),
            _buildPolicyTab(),
          ],
        ),
      ),
    );
  }

  // ==================== تبويب مسيّر الرواتب ====================

  Widget _buildPayrollTab() {
    return Column(
      children: [
        _buildMonthSelector(),
        _buildSummaryCards(),
        _buildActionButtons(),
        Expanded(child: _buildSalaryList()),
      ],
    );
  }

  Widget _buildMonthSelector() {
    final r = context.responsive;
    return Container(
      margin: EdgeInsets.all(r.isMobile ? 10 : 16),
      padding: EdgeInsets.symmetric(
        horizontal: r.isMobile ? 10 : 16,
        vertical: r.isMobile ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month, color: Colors.teal),
          const SizedBox(width: 12),
          const Text('الشهر:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _selectedMonth,
            items: List.generate(12, (i) {
              final months = [
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
                'ديسمبر'
              ];
              return DropdownMenuItem(value: i + 1, child: Text(months[i]));
            }),
            onChanged: (v) {
              if (v != null) {
                setState(() => _selectedMonth = v);
                _loadSalaries();
              }
            },
          ),
          const SizedBox(width: 16),
          const Text('السنة:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _selectedYear,
            items: List.generate(5, (i) {
              final y = DateTime.now().year - 2 + i;
              return DropdownMenuItem(value: y, child: Text('$y'));
            }),
            onChanged: (v) {
              if (v != null) {
                setState(() => _selectedYear = v);
                _loadSalaries();
              }
            },
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadSalaries,
            icon: const Icon(Icons.refresh, color: Colors.teal),
            tooltip: 'تحديث',
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    if (_summary == null || _salaries.isEmpty) return const SizedBox.shrink();
    final r = context.responsive;
    final cardWidth = r.isMobile ? 130.0 : 160.0;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: r.isMobile ? 10 : 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(
            width: cardWidth,
            child: _buildStatCard(
              'عدد الموظفين',
              '${_summary!['Count'] ?? 0}',
              Icons.people,
              Colors.blue,
            ),
          ),
          SizedBox(
            width: cardWidth,
            child: _buildStatCard(
              'إجمالي الأساسي',
              _formatCurrency(_summary!['TotalBaseSalary'] ?? 0),
              Icons.account_balance_wallet,
              Colors.teal,
            ),
          ),
          SizedBox(
            width: cardWidth,
            child: _buildStatCard(
              'إجمالي الخصومات',
              _formatCurrency(_summary!['TotalDeductions'] ?? 0),
              Icons.remove_circle,
              Colors.red,
            ),
          ),
          SizedBox(
            width: cardWidth,
            child: _buildStatCard(
              'إجمالي المكافآت',
              _formatCurrency(_summary!['TotalBonuses'] ?? 0),
              Icons.add_circle,
              Colors.green,
            ),
          ),
          SizedBox(
            width: cardWidth,
            child: _buildStatCard(
              'صافي الرواتب',
              _formatCurrency(_summary!['TotalNet'] ?? 0),
              Icons.payments,
              Colors.deepPurple,
            ),
          ),
          if ((_summary!['TotalManualDeductions'] ?? 0) > 0)
            SizedBox(
              width: cardWidth,
              child: _buildStatCard(
                'خصومات يدوية',
                _formatCurrency(_summary!['TotalManualDeductions'] ?? 0),
                Icons.money_off,
                Colors.orange,
              ),
            ),
          if ((_summary!['TotalManualBonuses'] ?? 0) > 0)
            SizedBox(
              width: cardWidth,
              child: _buildStatCard(
                'مكافآت يدوية',
                _formatCurrency(_summary!['TotalManualBonuses'] ?? 0),
                Icons.card_giftcard,
                Colors.indigo,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.8), color],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            Text(title,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    final hasSalaries = _salaries.isNotEmpty;
    final hasPending = _salaries.any((s) => s['Status'] == 'Pending');

    return Container(
      margin: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (!hasSalaries)
            ElevatedButton.icon(
              onPressed: _generatePayroll,
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('إنشاء مسيّر الرواتب'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          if (hasSalaries && hasPending) ...[
            ElevatedButton.icon(
              onPressed: _payAllSalaries,
              icon: const Icon(Icons.payments, size: 18),
              label: const Text('صرف جميع الرواتب'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _deletePayroll,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('حذف المسيّر'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSalaryList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_salaries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'لا يوجد مسيّر رواتب لشهر $_selectedMonth/$_selectedYear',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'اضغط "إنشاء مسيّر الرواتب" للبدء',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _salaries.length,
      itemBuilder: (context, index) => _buildSalaryCard(_salaries[index]),
    );
  }

  Widget _buildSalaryCard(Map<String, dynamic> salary) {
    final status = salary['Status'] ?? 'Pending';
    final isPaid = status == 'Paid';
    final statusColor = isPaid ? Colors.green : Colors.orange;
    final statusText = isPaid ? 'مصروف' : 'بانتظار الصرف';
    final hasDeductions = (salary['Deductions'] ?? 0) > 0;
    final hasBonuses = (salary['Bonuses'] ?? 0) > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showSalaryDetails(salary),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.teal[100],
                    child: Icon(Icons.person, color: Colors.teal[700]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          salary['UserName'] ?? 'موظف',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          'الراتب الأساسي: ${_formatCurrency(salary['BaseSalary'] ?? 0)}',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(statusText,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const Divider(height: 16),
              Row(
                children: [
                  // أيام الحضور
                  _buildInfoChip(
                    Icons.check_circle,
                    '${salary['AttendanceDays'] ?? 0} حضور',
                    Colors.green,
                  ),
                  const SizedBox(width: 8),
                  // أيام الغياب
                  _buildInfoChip(
                    Icons.cancel,
                    '${salary['AbsentDays'] ?? 0} غياب',
                    Colors.red,
                  ),
                  const SizedBox(width: 8),
                  // التأخير
                  if ((salary['TotalLateMinutes'] ?? 0) > 0)
                    _buildInfoChip(
                      Icons.access_time,
                      '${salary['TotalLateMinutes']} د تأخير',
                      Colors.orange,
                    ),
                  const Spacer(),
                  // الخصومات
                  if (hasDeductions)
                    Text(
                      '- ${_formatCurrency(salary['Deductions'])}',
                      style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  if (hasDeductions && hasBonuses) const SizedBox(width: 8),
                  // المكافآت
                  if (hasBonuses)
                    Text(
                      '+ ${_formatCurrency(salary['Bonuses'])}',
                      style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  const SizedBox(width: 16),
                  // صافي الراتب
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatCurrency(salary['NetSalary'] ?? 0),
                      style: TextStyle(
                        color: Colors.deepPurple[700],
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  // زر صرف فردي
                  if (!isPaid) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.payment, color: Colors.teal),
                      tooltip: 'صرف هذا الراتب',
                      onPressed: () => _paySingleSalary(salary),
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  void _showSalaryDetails(Map<String, dynamic> salary) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('كشف راتب - ${salary['UserName'] ?? 'موظف'}'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _detailSection('معلومات الشهر', [
                    _detailRow(
                        'الشهر/السنة', '${salary['Month']}/${salary['Year']}'),
                    _detailRow('أيام العمل المتوقعة',
                        '${salary['ExpectedWorkDays'] ?? 26}'),
                  ]),
                  const Divider(),
                  _detailSection('بيانات الحضور', [
                    _detailRow(
                        'أيام الحضور', '${salary['AttendanceDays'] ?? 0}'),
                    _detailRow('أيام الغياب', '${salary['AbsentDays'] ?? 0}',
                        isNegative: (salary['AbsentDays'] ?? 0) > 0),
                    _detailRow('دقائق التأخير',
                        '${salary['TotalLateMinutes'] ?? 0} دقيقة',
                        isNegative: (salary['TotalLateMinutes'] ?? 0) > 0),
                    _detailRow('دقائق الساعات الإضافية',
                        '${salary['TotalOvertimeMinutes'] ?? 0} دقيقة',
                        isPositive: (salary['TotalOvertimeMinutes'] ?? 0) > 0),
                    _detailRow('المغادرة المبكرة',
                        '${salary['TotalEarlyDepartureMinutes'] ?? 0} دقيقة',
                        isNegative:
                            (salary['TotalEarlyDepartureMinutes'] ?? 0) > 0),
                  ]),
                  const Divider(),
                  _detailSection('الإجازات', [
                    _detailRow(
                        'إجازات مدفوعة', '${salary['PaidLeaveDays'] ?? 0} يوم'),
                    _detailRow('إجازات بدون راتب',
                        '${salary['UnpaidLeaveDays'] ?? 0} يوم',
                        isNegative: (salary['UnpaidLeaveDays'] ?? 0) > 0),
                  ]),
                  const Divider(),
                  _detailSection('تفاصيل مالية', [
                    _detailRow('الراتب الأساسي',
                        _formatCurrency(salary['BaseSalary'] ?? 0)),
                    if ((salary['Allowances'] ?? 0) > 0)
                      _detailRow('البدلات',
                          '+ ${_formatCurrency(salary['Allowances'])}',
                          isPositive: true),
                    if ((salary['LateDeduction'] ?? 0) > 0)
                      _detailRow('خصم التأخير',
                          '- ${_formatCurrency(salary['LateDeduction'])}',
                          isNegative: true),
                    if ((salary['AbsentDeduction'] ?? 0) > 0)
                      _detailRow('خصم الغياب',
                          '- ${_formatCurrency(salary['AbsentDeduction'])}',
                          isNegative: true),
                    if ((salary['EarlyDepartureDeduction'] ?? 0) > 0)
                      _detailRow('خصم المغادرة المبكرة',
                          '- ${_formatCurrency(salary['EarlyDepartureDeduction'])}',
                          isNegative: true),
                    if ((salary['UnpaidLeaveDeduction'] ?? 0) > 0)
                      _detailRow('خصم إجازة بدون راتب',
                          '- ${_formatCurrency(salary['UnpaidLeaveDeduction'])}',
                          isNegative: true),
                    if ((salary['ManualDeductions'] ?? 0) > 0)
                      _detailRow('خصومات يدوية',
                          '- ${_formatCurrency(salary['ManualDeductions'])}',
                          isNegative: true),
                    if ((salary['OvertimeBonus'] ?? 0) > 0)
                      _detailRow('مكافأة ساعات إضافية',
                          '+ ${_formatCurrency(salary['OvertimeBonus'])}',
                          isPositive: true),
                    if ((salary['ManualBonuses'] ?? 0) > 0)
                      _detailRow('مكافآت يدوية',
                          '+ ${_formatCurrency(salary['ManualBonuses'])}',
                          isPositive: true),
                    const Divider(),
                    _detailRow('إجمالي الخصومات',
                        '- ${_formatCurrency(salary['Deductions'] ?? 0)}',
                        isNegative: true, isBold: true),
                    _detailRow('إجمالي المكافآت',
                        '+ ${_formatCurrency(salary['Bonuses'] ?? 0)}',
                        isPositive: true, isBold: true),
                    if ((salary['Allowances'] ?? 0) > 0)
                      _detailRow('إجمالي البدلات',
                          '+ ${_formatCurrency(salary['Allowances'] ?? 0)}',
                          isPositive: true, isBold: true),
                    const Divider(thickness: 2),
                    _detailRow('صافي الراتب',
                        _formatCurrency(salary['NetSalary'] ?? 0),
                        isBold: true, fontSize: 18),
                  ]),
                  if (salary['JournalEntryId'] != null) ...[
                    const Divider(),
                    _detailSection('الربط المحاسبي', [
                      _detailRow('رقم القيد', '${salary['JournalEntryId']}'),
                      _detailRow('الحالة', salary['Status'] ?? ''),
                      if (salary['PaidAt'] != null)
                        _detailRow(
                            'تاريخ الصرف', _formatDate(salary['PaidAt'])),
                    ]),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(title,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.teal[700])),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _detailRow(String label, String value,
      {bool isNegative = false,
      bool isPositive = false,
      bool isBold = false,
      double fontSize = 14}) {
    Color textColor = Colors.black87;
    if (isNegative) textColor = Colors.red[700]!;
    if (isPositive) textColor = Colors.green[700]!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: fontSize - 1,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontSize: fontSize,
                  color: textColor,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
        ],
      ),
    );
  }

  // ==================== تبويب سياسة الرواتب ====================

  Widget _buildPolicyTab() {
    if (_policyLoading && _policies.isEmpty) {
      _loadPolicies();
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('سياسات خصم ومكافأة الرواتب',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[700])),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _showCreatePolicyDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إضافة سياسة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_policies.isEmpty)
            _buildEmptyPolicyState()
          else
            ..._policies.map(_buildPolicyCard),
        ],
      ),
    );
  }

  Widget _buildEmptyPolicyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.policy, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('لا توجد سياسات رواتب',
                style: TextStyle(fontSize: 16, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text(
              'أنشئ سياسة لتفعيل الحساب التلقائي للخصومات والمكافآت',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _showCreatePolicyDialog,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('إنشاء سياسة افتراضية'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyCard(Map<String, dynamic> policy) {
    final isDefault = policy['IsDefault'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isDefault ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDefault
            ? const BorderSide(color: Colors.teal, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.policy,
                    color: isDefault ? Colors.teal : Colors.grey),
                const SizedBox(width: 8),
                Text(
                  policy['Name'] ?? 'سياسة',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (isDefault) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.teal[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal),
                    ),
                    child: const Text('افتراضية',
                        style: TextStyle(
                            color: Colors.teal,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _showEditPolicyDialog(policy),
                  tooltip: 'تعديل',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                  onPressed: () => _deletePolicy(policy['Id']),
                  tooltip: 'حذف',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildPolicyItem('خصم التأخير/دقيقة',
                    '${policy['DeductionPerLateMinute'] ?? 0} د.ع'),
                _buildPolicyItem('حد أقصى خصم تأخير',
                    '${policy['MaxLateDeductionPercent'] ?? 25}%'),
                _buildPolicyItem('معامل خصم الغياب',
                    '×${policy['AbsentDayMultiplier'] ?? 1}'),
                _buildPolicyItem('معامل الساعات الإضافية',
                    '×${policy['OvertimeHourlyMultiplier'] ?? 1.5}'),
                _buildPolicyItem('حد ساعات إضافية/شهر',
                    '${policy['MaxOvertimeHoursPerMonth'] ?? 40} ساعة'),
                _buildPolicyItem('أيام العمل/شهر',
                    '${policy['WorkDaysPerMonth'] ?? 26} يوم'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyItem(String label, String value) {
    return SizedBox(
      width: 180,
      child: Row(
        children: [
          Text('$label: ',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showCreatePolicyDialog() {
    _showPolicyFormDialog(null);
  }

  void _showEditPolicyDialog(Map<String, dynamic> policy) {
    _showPolicyFormDialog(policy);
  }

  void _showPolicyFormDialog(Map<String, dynamic>? existing) {
    final isEdit = existing != null;
    final nameCtrl =
        TextEditingController(text: existing?['Name'] ?? 'سياسة افتراضية');
    final lateMinCtrl = TextEditingController(
        text: '${existing?['DeductionPerLateMinute'] ?? 0}');
    final maxLateCtrl = TextEditingController(
        text: '${existing?['MaxLateDeductionPercent'] ?? 25}');
    final absentMultCtrl =
        TextEditingController(text: '${existing?['AbsentDayMultiplier'] ?? 1}');
    final earlyDepCtrl = TextEditingController(
        text: '${existing?['DeductionPerEarlyDepartureMinute'] ?? 0}');
    final overtimeMultCtrl = TextEditingController(
        text: '${existing?['OvertimeHourlyMultiplier'] ?? 1.5}');
    final maxOvertimeCtrl = TextEditingController(
        text: '${existing?['MaxOvertimeHoursPerMonth'] ?? 40}');
    final unpaidMultCtrl = TextEditingController(
        text: '${existing?['UnpaidLeaveDayMultiplier'] ?? 1}');
    final workDaysCtrl =
        TextEditingController(text: '${existing?['WorkDaysPerMonth'] ?? 26}');
    bool isDefault = existing?['IsDefault'] ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(isEdit ? 'تعديل سياسة الرواتب' : 'إنشاء سياسة رواتب'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'اسم السياسة',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: const Text('سياسة افتراضية'),
                      subtitle: const Text(
                          'تُستخدم تلقائياً عند إنشاء مسيّر الرواتب'),
                      value: isDefault,
                      onChanged: (v) =>
                          setDialogState(() => isDefault = v ?? true),
                    ),
                    const Divider(),
                    const Text('قواعد خصم التأخير',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: lateMinCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'خصم لكل دقيقة تأخير (د.ع)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maxLateCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'حد أقصى خصم تأخير (%)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('قواعد الغياب والمغادرة المبكرة',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: absentMultCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'معامل خصم الغياب',
                              helperText: '1 = خصم يوم واحد, 2 = يومين',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: earlyDepCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'خصم كل دقيقة مغادرة مبكرة',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('قواعد الساعات الإضافية',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: overtimeMultCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'معامل أجر الساعة الإضافية',
                              helperText: '1.5 = ساعة ونصف',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maxOvertimeCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'حد ساعات إضافية/شهر',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: unpaidMultCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'معامل خصم إجازة بدون راتب',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: workDaysCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'أيام العمل في الشهر',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    if (isEdit) {
                      await _api.updateSalaryPolicy(
                        existing['Id'],
                        companyId: _companyId!,
                        name: nameCtrl.text,
                        isDefault: isDefault,
                        deductionPerLateMinute:
                            double.tryParse(lateMinCtrl.text) ?? 0,
                        maxLateDeductionPercent:
                            double.tryParse(maxLateCtrl.text) ?? 25,
                        absentDayMultiplier:
                            double.tryParse(absentMultCtrl.text) ?? 1,
                        deductionPerEarlyDepartureMinute:
                            double.tryParse(earlyDepCtrl.text) ?? 0,
                        overtimeHourlyMultiplier:
                            double.tryParse(overtimeMultCtrl.text) ?? 1.5,
                        maxOvertimeHoursPerMonth:
                            int.tryParse(maxOvertimeCtrl.text) ?? 40,
                        unpaidLeaveDayMultiplier:
                            double.tryParse(unpaidMultCtrl.text) ?? 1,
                        workDaysPerMonth: int.tryParse(workDaysCtrl.text) ?? 26,
                      );
                    } else {
                      await _api.createSalaryPolicy(
                        companyId: _companyId!,
                        name: nameCtrl.text,
                        isDefault: isDefault,
                        deductionPerLateMinute:
                            double.tryParse(lateMinCtrl.text) ?? 0,
                        maxLateDeductionPercent:
                            double.tryParse(maxLateCtrl.text) ?? 25,
                        absentDayMultiplier:
                            double.tryParse(absentMultCtrl.text) ?? 1,
                        deductionPerEarlyDepartureMinute:
                            double.tryParse(earlyDepCtrl.text) ?? 0,
                        overtimeHourlyMultiplier:
                            double.tryParse(overtimeMultCtrl.text) ?? 1.5,
                        maxOvertimeHoursPerMonth:
                            int.tryParse(maxOvertimeCtrl.text) ?? 40,
                        unpaidLeaveDayMultiplier:
                            double.tryParse(unpaidMultCtrl.text) ?? 1,
                        workDaysPerMonth: int.tryParse(workDaysCtrl.text) ?? 26,
                      );
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              isEdit ? 'تم تحديث السياسة' : 'تم إنشاء السياسة'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      _loadPolicies();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('خطأ'),
                            backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                child: Text(isEdit ? 'تحديث' : 'إنشاء'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deletePolicy(dynamic id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف سياسة الرواتب'),
          content: const Text('هل تريد حذف هذه السياسة؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await _api.deleteSalaryPolicy(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف السياسة'),
            backgroundColor: Colors.orange,
          ),
        );
        _loadPolicies();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
