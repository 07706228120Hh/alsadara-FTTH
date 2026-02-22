import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/agent.dart';
import '../../services/agent_api_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';

/// صفحة إدارة عمولات الوكلاء
/// تحديد نسب العمولة لكل وكيل حسب الباقة
/// العمولة = نسبة مئوية × ربح الباقة
class AgentCommissionPage extends StatefulWidget {
  final String? companyId;

  const AgentCommissionPage({super.key, this.companyId});

  @override
  State<AgentCommissionPage> createState() => _AgentCommissionPageState();
}

class _AgentCommissionPageState extends State<AgentCommissionPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _errorMessage;

  // البيانات
  List<AgentModel> _agents = [];
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _commissionRates = [];

  // الوكيل المختار
  AgentModel? _selectedAgent;

  // Controllers لتعديل الأرباح والنسب
  final Map<String, TextEditingController> _profitControllers = {};
  final Map<String, TextEditingController> _rateControllers = {};

  String get _companyId =>
      widget.companyId ?? VpsAuthService.instance.currentCompanyId ?? '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _profitControllers.values) {
      c.dispose();
    }
    for (final c in _rateControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // جلب الوكلاء والباقات بالتوازي
      final agentsFuture = AgentApiService.instance.getAll();
      final plansFuture =
          AgentApiService.instance.getPlansWithProfit(_companyId);

      final agentsResult = await agentsFuture;
      _plans = await plansFuture;

      _agents = agentsResult;

      // تهيئة controllers الأرباح
      for (final plan in _plans) {
        final planId = plan['Id']?.toString() ?? '';
        final profit = (plan['ProfitAmount'] ?? 0).toDouble();
        _profitControllers[planId] = TextEditingController(
            text: profit > 0 ? profit.toStringAsFixed(0) : '');
      }

      // إذا كان هناك وكيل مختار سابقاً، أعد تحميل عمولاته
      if (_selectedAgent != null) {
        await _loadAgentRates(_selectedAgent!.id);
      }
    } catch (e) {
      _errorMessage = 'خطأ: $e';
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadAgentRates(String agentId) async {
    try {
      _commissionRates =
          await AgentApiService.instance.getAgentCommissionRates(agentId);

      // تهيئة controllers النسب
      _rateControllers.clear();
      for (final plan in _plans) {
        final planId = plan['Id']?.toString() ?? '';
        // البحث عن النسبة الحالية
        final existingRate = _commissionRates.firstWhere(
          (r) => r['InternetPlanId']?.toString() == planId,
          orElse: () => <String, dynamic>{},
        );
        final pct = (existingRate['CommissionPercentage'] ?? 0).toDouble();
        _rateControllers[planId] =
            TextEditingController(text: pct > 0 ? pct.toStringAsFixed(1) : '');
      }
    } catch (e) {
      _errorMessage = 'خطأ في جلب العمولات: $e';
    }
    setState(() {});
  }

  Future<void> _savePlanProfit(String planId, double profitAmount) async {
    try {
      final result =
          await AgentApiService.instance.updatePlanProfit(planId, profitAmount);
      if (result['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'تم الحفظ'),
            backgroundColor: AccountingTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('خطأ: $e'),
              backgroundColor: AccountingTheme.danger),
        );
      }
    }
  }

  Future<void> _saveAllProfits() async {
    int saved = 0;
    for (final plan in _plans) {
      final planId = plan['Id']?.toString() ?? '';
      final controller = _profitControllers[planId];
      if (controller == null) continue;
      final profit = double.tryParse(controller.text) ?? 0;
      if (profit > 0) {
        try {
          await AgentApiService.instance.updatePlanProfit(planId, profit);
          saved++;
        } catch (_) {}
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ أرباح $saved باقة'),
          backgroundColor: AccountingTheme.success,
        ),
      );
    }
    await _loadData();
  }

  Future<void> _saveAgentRates() async {
    if (_selectedAgent == null) return;

    final agentId = _selectedAgent!.id;
    final rates = <Map<String, dynamic>>[];

    for (final plan in _plans) {
      final planId = plan['Id']?.toString() ?? '';
      final controller = _rateControllers[planId];
      if (controller == null) continue;
      final pct = double.tryParse(controller.text) ?? 0;
      if (pct > 0) {
        rates.add({
          'internetPlanId': planId,
          'commissionPercentage': pct,
        });
      }
    }

    if (rates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لم يتم تحديد أي نسبة عمولة'),
          backgroundColor: AccountingTheme.warning,
        ),
      );
      return;
    }

    try {
      final result = await AgentApiService.instance.setBulkCommissionRates(
        agentId: agentId,
        companyId: _companyId,
        rates: rates,
      );

      if (result['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'تم الحفظ'),
            backgroundColor: AccountingTheme.success,
          ),
        );
        await _loadAgentRates(agentId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('خطأ: $e'),
              backgroundColor: AccountingTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        appBar: _buildAppBar(),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildError()
                : _buildBody(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AccountingTheme.bgSidebar,
      iconTheme: const IconThemeData(color: Colors.white),
      title: Text(
        '💰 إدارة عمولات الوكلاء',
        style: GoogleFonts.cairo(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: AccountingTheme.neonGreen,
        labelColor: Colors.white,
        unselectedLabelColor: AccountingTheme.textOnDarkMuted,
        labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        tabs: const [
          Tab(text: '📋 أرباح الباقات', icon: Icon(Icons.monetization_on)),
          Tab(text: '👤 نسب العمولات', icon: Icon(Icons.percent)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          onPressed: _loadData,
          tooltip: 'تحديث',
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline,
              size: 64, color: AccountingTheme.danger),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: GoogleFonts.cairo(fontSize: 16)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: Text('إعادة المحاولة', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildPlanProfitsTab(),
        _buildCommissionRatesTab(),
      ],
    );
  }

  // ==================== تبويب أرباح الباقات ====================

  Widget _buildPlanProfitsTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان + زر حفظ الكل
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تحديد ربح كل باقة',
                      style: GoogleFonts.cairo(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'الربح هو المبلغ الصافي بعد خصم التكاليف - العمولة تُحسب كنسبة من هذا الربح',
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        color: AccountingTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _saveAllProfits,
                icon: const Icon(Icons.save, size: 18),
                label: Text('حفظ الكل',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.neonGreen,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // جدول الباقات
          Expanded(
            child: _plans.isEmpty
                ? Center(
                    child: Text(
                      'لا توجد باقات',
                      style: GoogleFonts.cairo(
                          fontSize: 16, color: AccountingTheme.textMuted),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: AccountingTheme.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SingleChildScrollView(
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                              AccountingTheme.bgSecondary),
                          columnSpacing: 24,
                          columns: [
                            DataColumn(
                              label: Text('الباقة',
                                  style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.bold)),
                            ),
                            DataColumn(
                              label: Text('السرعة',
                                  style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.bold)),
                            ),
                            DataColumn(
                              label: Text('السعر الشهري',
                                  style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.bold)),
                            ),
                            DataColumn(
                              label: Text('الربح',
                                  style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.bold,
                                      color: AccountingTheme.neonGreen)),
                            ),
                            DataColumn(
                              label: Text('إجراء',
                                  style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                          rows: _plans.map((plan) {
                            final planId = plan['Id']?.toString() ?? '';
                            final controller = _profitControllers[planId];
                            return DataRow(cells: [
                              DataCell(Text(
                                plan['NameAr'] ?? plan['Name'] ?? '',
                                style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.w600),
                              )),
                              DataCell(Text(
                                '${plan['SpeedMbps'] ?? '-'} Mbps',
                                style: GoogleFonts.cairo(),
                              )),
                              DataCell(Text(
                                '${_formatNumber(plan['MonthlyPrice'])} د.ع',
                                style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.w600),
                              )),
                              DataCell(
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller: controller,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.bold,
                                      color: AccountingTheme.neonGreen,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: '0',
                                      hintStyle: GoogleFonts.cairo(
                                          color: AccountingTheme.textMuted),
                                      suffixText: 'د.ع',
                                      suffixStyle:
                                          GoogleFonts.cairo(fontSize: 11),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 8),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                IconButton(
                                  icon: const Icon(Icons.save,
                                      color: AccountingTheme.neonBlue,
                                      size: 20),
                                  tooltip: 'حفظ ربح هذه الباقة',
                                  onPressed: () {
                                    final profit = double.tryParse(
                                            controller?.text ?? '') ??
                                        0;
                                    if (profit > 0) {
                                      _savePlanProfit(planId, profit);
                                    }
                                  },
                                ),
                              ),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ==================== تبويب نسب العمولات ====================

  Widget _buildCommissionRatesTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // اختيار الوكيل
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildAgentSelector(),
              ),
              const SizedBox(width: 16),
              if (_selectedAgent != null)
                ElevatedButton.icon(
                  onPressed: _saveAgentRates,
                  icon: const Icon(Icons.save, size: 18),
                  label: Text('حفظ النسب',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AccountingTheme.neonGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // جدول النسب
          Expanded(
            child: _selectedAgent == null
                ? _buildSelectAgentPrompt()
                : _buildCommissionTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AccountingTheme.borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _selectedAgent?.id,
          hint: Text(
            'اختر الوكيل لتحديد نسب عمولاته...',
            style: GoogleFonts.cairo(color: AccountingTheme.textMuted),
          ),
          items: _agents.map((agent) {
            return DropdownMenuItem<String>(
              value: agent.id,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        AccountingTheme.neonBlue.withValues(alpha: 0.1),
                    child: Text(
                      agent.name.isNotEmpty ? agent.name[0] : '?',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.neonBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    agent.name,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${agent.agentCode})',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: AccountingTheme.textMuted,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (agentId) {
            AgentModel? found;
            for (final a in _agents) {
              if (a.id == agentId) {
                found = a;
                break;
              }
            }
            setState(() {
              _selectedAgent = found;
            });
            if (agentId != null) {
              _loadAgentRates(agentId);
            }
          },
        ),
      ),
    );
  }

  Widget _buildSelectAgentPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_search,
            size: 80,
            color: AccountingTheme.textMuted.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'اختر وكيلاً لعرض وتعديل نسب عمولاته',
            style: GoogleFonts.cairo(
              fontSize: 16,
              color: AccountingTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommissionTable() {
    return Container(
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            // رأس معلومات الوكيل
            Container(
              padding: const EdgeInsets.all(16),
              color: AccountingTheme.neonBlue.withValues(alpha: 0.05),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor:
                        AccountingTheme.neonBlue.withValues(alpha: 0.15),
                    child: Text(
                      _selectedAgent?.name.isNotEmpty == true
                          ? _selectedAgent!.name[0]
                          : '?',
                      style: GoogleFonts.cairo(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.neonBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedAgent?.name ?? '',
                        style: GoogleFonts.cairo(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'الكود: ${_selectedAgent?.agentCode ?? ''} | الهاتف: ${_selectedAgent?.phoneNumber ?? ''}',
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          color: AccountingTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // جدول النسب
            Expanded(
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowColor:
                      WidgetStateProperty.all(AccountingTheme.bgSecondary),
                  columnSpacing: 16,
                  columns: [
                    DataColumn(
                      label: Text('الباقة',
                          style:
                              GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text('السعر',
                          style:
                              GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text('الربح',
                          style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              color: AccountingTheme.neonGreen)),
                    ),
                    DataColumn(
                      label: Text('النسبة %',
                          style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              color: AccountingTheme.neonBlue)),
                    ),
                    DataColumn(
                      label: Text('مبلغ العمولة',
                          style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              color: AccountingTheme.neonPurple)),
                    ),
                  ],
                  rows: _plans.map((plan) {
                    final planId = plan['Id']?.toString() ?? '';
                    final controller = _rateControllers[planId];
                    final profit = (plan['ProfitAmount'] ?? 0).toDouble();
                    final pct = double.tryParse(controller?.text ?? '') ?? 0;
                    final commissionAmount = profit * pct / 100;

                    return DataRow(cells: [
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan['NameAr'] ?? plan['Name'] ?? '',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${plan['SpeedMbps'] ?? '-'} Mbps',
                              style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  color: AccountingTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      DataCell(Text(
                        '${_formatNumber(plan['MonthlyPrice'])} د.ع',
                        style: GoogleFonts.cairo(fontSize: 13),
                      )),
                      DataCell(Text(
                        profit > 0
                            ? '${_formatNumber(profit)} د.ع'
                            : 'غير محدد',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w600,
                          color: profit > 0
                              ? AccountingTheme.neonGreen
                              : AccountingTheme.danger,
                        ),
                      )),
                      DataCell(
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: controller,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              color: AccountingTheme.neonBlue,
                            ),
                            decoration: InputDecoration(
                              hintText: '0',
                              suffixText: '%',
                              suffixStyle: GoogleFonts.cairo(fontSize: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: commissionAmount > 0
                                ? AccountingTheme.neonPurple
                                    .withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            commissionAmount > 0
                                ? '${_formatNumber(commissionAmount)} د.ع'
                                : '-',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: commissionAmount > 0
                                  ? AccountingTheme.neonPurple
                                  : AccountingTheme.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ]);
                  }).toList(),
                ),
              ),
            ),

            // ملخص
            if (_selectedAgent != null)
              Container(
                padding: const EdgeInsets.all(16),
                color: AccountingTheme.bgSecondary,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildSummaryCard(
                      'إجمالي العمولة لكل اشتراك كامل',
                      _calculateTotalCommission(),
                      AccountingTheme.neonPurple,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: AccountingTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${_formatNumber(amount)} د.ع',
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  double _calculateTotalCommission() {
    double total = 0;
    for (final plan in _plans) {
      final planId = plan['Id']?.toString() ?? '';
      final controller = _rateControllers[planId];
      final profit = (plan['ProfitAmount'] ?? 0).toDouble();
      final pct = double.tryParse(controller?.text ?? '') ?? 0;
      total += profit * pct / 100;
    }
    return total;
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = (value is num)
        ? value.toDouble()
        : (double.tryParse(value.toString()) ?? 0);
    return n.round().toString();
  }
}
