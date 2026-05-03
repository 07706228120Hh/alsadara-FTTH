import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/agent.dart';
import '../../services/agent_api_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

/// صفحة العمولات - تحتوي تبويبين: نسب العمولات + أرباح الباقات
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

  // بيانات العمولات
  List<AgentModel> _agents = [];
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _commissionRates = [];
  AgentModel? _selectedAgent;
  final Map<String, TextEditingController> _rateControllers = {};

  // بيانات أرباح الباقات
  final Map<String, TextEditingController> _profitControllers = {};

  // البحث عن وكيل (inline)
  final TextEditingController _agentSearchController = TextEditingController();
  final FocusNode _agentSearchFocusNode = FocusNode();
  bool _showSuggestions = false;
  List<AgentModel> _filteredAgents = [];

  // تبويب داخلي للموبايل
  int _innerTab = 0; // 0=نسب العمولات، 1=أرباح الباقات

  String get _companyId =>
      widget.companyId ?? VpsAuthService.instance.currentCompanyId ?? '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _agentSearchFocusNode.addListener(() {
      if (!_agentSearchFocusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_agentSearchFocusNode.hasFocus) {
            setState(() => _showSuggestions = false);
          }
        });
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _agentSearchController.dispose();
    _agentSearchFocusNode.dispose();
    for (final c in _rateControllers.values) {
      c.dispose();
    }
    for (final c in _profitControllers.values) {
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
      final agentsFuture = AgentApiService.instance.getAll();
      final plansFuture =
          AgentApiService.instance.getPlansWithProfit(_companyId);

      _agents = await agentsFuture;
      _plans = await plansFuture;

      // تهيئة controllers الأرباح
      for (final plan in _plans) {
        final planId = plan['Id']?.toString() ?? '';
        final profit = (plan['ProfitAmount'] ?? 0).toDouble();
        _profitControllers[planId]?.dispose();
        _profitControllers[planId] = TextEditingController(
            text: profit > 0 ? profit.toStringAsFixed(0) : '');
      }

      if (_selectedAgent != null) {
        await _loadAgentRates(_selectedAgent!.id);
      }
    } catch (e) {
      _errorMessage = 'خطأ';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadAgentRates(String agentId) async {
    try {
      _commissionRates =
          await AgentApiService.instance.getAgentCommissionRates(agentId);

      _rateControllers.clear();
      for (final plan in _plans) {
        final planId = plan['Id']?.toString() ?? '';
        final existingRate = _commissionRates.firstWhere(
          (r) => r['InternetPlanId']?.toString() == planId,
          orElse: () => <String, dynamic>{},
        );
        final pct = (existingRate['CommissionPercentage'] ?? 0).toDouble();
        _rateControllers[planId] =
            TextEditingController(text: pct > 0 ? pct.toStringAsFixed(1) : '');
      }
    } catch (e) {
      _errorMessage = 'خطأ في جلب العمولات';
    }
    setState(() {});
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
              content: Text('خطأ'),
              backgroundColor: AccountingTheme.danger),
        );
      }
    }
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
              content: Text('خطأ'),
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

  @override
  Widget build(BuildContext context) {
    final isMob = MediaQuery.of(context).size.width < 700;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildError()
              : isMob
                  ? _buildMobileBody()
                  : _buildDesktopBody(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline,
              size: context.accR.iconEmpty, color: AccountingTheme.danger),
          SizedBox(height: context.accR.spaceXL),
          Text(_errorMessage!,
              style: GoogleFonts.cairo(fontSize: context.accR.headingSmall)),
          SizedBox(height: context.accR.spaceXL),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: Text('إعادة المحاولة', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  // ==================== واجهة الهاتف ====================

  Widget _buildMobileBody() {
    return Column(
      children: [
        // تبويبات داخلية
        Container(
          decoration: const BoxDecoration(
            color: AccountingTheme.bgCard,
            border:
                Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
          ),
          child: Row(
            children: [
              _buildMobileTab(
                  0, Icons.percent, 'نسب العمولات', AccountingTheme.neonBlue),
              _buildMobileTab(1, Icons.monetization_on, 'أرباح الباقات',
                  AccountingTheme.neonOrange),
            ],
          ),
        ),

        // المحتوى
        Expanded(
          child: _innerTab == 0
              ? _buildMobileCommissionContent()
              : _buildMobileProfitsContent(),
        ),
      ],
    );
  }

  Widget _buildMobileTab(int index, IconData icon, String label, Color color) {
    final isSelected = _innerTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _innerTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? color : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14,
                  color: isSelected ? color : AccountingTheme.textMuted),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? color : AccountingTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- بحث واختيار الوكيل (inline) ----

  void _onAgentSearchChanged(String val) {
    final q = val.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredAgents = List.from(_agents);
      } else {
        _filteredAgents = _agents.where((a) {
          return a.name.toLowerCase().contains(q) ||
              a.agentCode.toLowerCase().contains(q) ||
              a.phoneNumber.toLowerCase().contains(q);
        }).toList();
      }
      _showSuggestions = true;
    });
  }

  void _selectAgent(AgentModel agent) {
    setState(() {
      _selectedAgent = agent;
      _showSuggestions = false;
      _agentSearchController.clear();
    });
    _loadAgentRates(agent.id);
  }

  void _clearSelectedAgent() {
    setState(() {
      _selectedAgent = null;
      _agentSearchController.clear();
      _filteredAgents = List.from(_agents);
    });
  }

  Widget _buildInlineAgentSearch({bool isMobile = false}) {
    final double fontSize = isMobile ? 12.0 : 13.0;
    final double avatarRadius = isMobile ? 14.0 : 16.0;
    final double maxSuggestHeight = isMobile ? 200.0 : 260.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // حقل البحث أو الوكيل المحدد
        Container(
          margin: EdgeInsets.all(isMobile ? 8 : 0),
          decoration: BoxDecoration(
            color: AccountingTheme.bgCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AccountingTheme.borderColor),
          ),
          child: _selectedAgent != null
              ? Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: avatarRadius,
                        backgroundColor:
                            AccountingTheme.neonBlue.withOpacity(0.1),
                        child: Text(
                          _selectedAgent!.name.isNotEmpty
                              ? _selectedAgent!.name[0]
                              : '?',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            color: AccountingTheme.neonBlue,
                            fontSize: isMobile ? 11 : 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_selectedAgent!.name} (${_selectedAgent!.agentCode})',
                          style: GoogleFonts.cairo(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w600,
                            color: AccountingTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: _clearSelectedAgent,
                        child: const Icon(Icons.close,
                            size: 18, color: AccountingTheme.textMuted),
                      ),
                      if (isMobile) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _saveAgentRates,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AccountingTheme.neonGreen,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('حفظ',
                                style: GoogleFonts.cairo(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : TextField(
                  controller: _agentSearchController,
                  focusNode: _agentSearchFocusNode,
                  onChanged: _onAgentSearchChanged,
                  onTap: () {
                    if (_filteredAgents.isEmpty) {
                      _filteredAgents = List.from(_agents);
                    }
                    setState(() => _showSuggestions = true);
                  },
                  style: GoogleFonts.cairo(
                      fontSize: fontSize, color: AccountingTheme.textPrimary),
                  textDirection: TextDirection.rtl,
                  decoration: InputDecoration(
                    hintText: 'ابحث عن وكيل بالاسم أو الكود...',
                    hintStyle: GoogleFonts.cairo(
                        fontSize: fontSize, color: AccountingTheme.textMuted),
                    prefixIcon: const Icon(Icons.search,
                        size: 18, color: AccountingTheme.textMuted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                    isDense: true,
                  ),
                ),
        ),

        // قائمة الاقتراحات
        if (_showSuggestions && _selectedAgent == null)
          Container(
            margin: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 0),
            constraints: BoxConstraints(maxHeight: maxSuggestHeight),
            decoration: BoxDecoration(
              color: AccountingTheme.bgCard,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(8)),
              border: Border.all(color: AccountingTheme.borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _filteredAgents.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text('لا يوجد نتائج',
                          style: GoogleFonts.cairo(
                              color: AccountingTheme.textMuted,
                              fontSize: fontSize)),
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    shrinkWrap: true,
                    itemCount: _filteredAgents.length,
                    itemBuilder: (_, i) {
                      final agent = _filteredAgents[i];
                      return InkWell(
                        onTap: () => _selectAgent(agent),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: avatarRadius,
                                backgroundColor:
                                    AccountingTheme.neonBlue.withOpacity(0.1),
                                child: Text(
                                  agent.name.isNotEmpty ? agent.name[0] : '?',
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    color: AccountingTheme.neonBlue,
                                    fontSize: isMobile ? 10 : 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      agent.name,
                                      style: GoogleFonts.cairo(
                                        fontSize: fontSize,
                                        fontWeight: FontWeight.w600,
                                        color: AccountingTheme.textPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${agent.agentCode} • ${agent.phoneNumber}',
                                      style: GoogleFonts.cairo(
                                        fontSize: isMobile ? 9 : 10,
                                        color: AccountingTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
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

  // ---- موبايل: نسب العمولات ----

  Widget _buildMobileCommissionContent() {
    return Column(
      children: [
        // اختيار الوكيل
        _buildInlineAgentSearch(isMobile: true),

        // المحتوى
        Expanded(
          child: _selectedAgent == null
              ? _buildSelectAgentPrompt()
              : _buildMobileCommissionList(),
        ),

        // ملخص الإجمالي
        if (_selectedAgent != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: AccountingTheme.bgSecondary,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.calculate,
                    size: 16, color: AccountingTheme.neonPurple),
                const SizedBox(width: 6),
                Text('إجمالي العمولة: ',
                    style: GoogleFonts.cairo(
                        fontSize: 11, color: AccountingTheme.textSecondary)),
                Text(
                  '${_formatNumber(_calculateTotalCommission())} د.ع',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AccountingTheme.neonPurple,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMobileCommissionList() {
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _plans.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final plan = _plans[index];
        final planId = plan['Id']?.toString() ?? '';
        final controller = _rateControllers[planId];
        final profit = (plan['ProfitAmount'] ?? 0).toDouble();
        final pct = double.tryParse(controller?.text ?? '') ?? 0;
        final commissionAmount = profit * pct / 100;

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AccountingTheme.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: pct > 0
                  ? AccountingTheme.neonBlue.withOpacity(0.3)
                  : AccountingTheme.borderColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AccountingTheme.neonBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.wifi,
                        size: 12, color: AccountingTheme.neonBlue),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      plan['NameAr'] ?? plan['Name'] ?? '',
                      style: GoogleFonts.cairo(
                          fontSize: 12, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AccountingTheme.neonPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${plan['SpeedMbps'] ?? '-'} Mbps',
                      style: GoogleFonts.cairo(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.neonPurple),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('السعر',
                            style: GoogleFonts.cairo(
                                fontSize: 8, color: AccountingTheme.textMuted)),
                        Text(
                          _formatNumber(plan['MonthlyPrice']),
                          style: GoogleFonts.cairo(
                              fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الربح',
                            style: GoogleFonts.cairo(
                                fontSize: 8, color: AccountingTheme.textMuted)),
                        Text(
                          profit > 0 ? _formatNumber(profit) : 'غير محدد',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: profit > 0
                                ? AccountingTheme.neonGreen
                                : AccountingTheme.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    height: 32,
                    child: TextField(
                      controller: controller,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.neonBlue,
                      ),
                      decoration: InputDecoration(
                        hintText: '0',
                        suffixText: '%',
                        suffixStyle: GoogleFonts.cairo(fontSize: 9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 4),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: commissionAmount > 0
                          ? AccountingTheme.neonPurple.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      commissionAmount > 0
                          ? '${_formatNumber(commissionAmount)} د.ع'
                          : '-',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: commissionAmount > 0
                            ? AccountingTheme.neonPurple
                            : AccountingTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ---- موبايل: أرباح الباقات ----

  Widget _buildMobileProfitsContent() {
    if (_plans.isEmpty) {
      return Center(
        child: Text('لا توجد باقات',
            style: GoogleFonts.cairo(
                fontSize: 14, color: AccountingTheme.textMuted)),
      );
    }
    return Column(
      children: [
        // وصف + زر حفظ الكل
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: AccountingTheme.neonGreen.withOpacity(0.05),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'الربح = المبلغ الصافي بعد خصم التكاليف',
                  style: GoogleFonts.cairo(
                      fontSize: 10, color: AccountingTheme.textMuted),
                ),
              ),
              GestureDetector(
                onTap: _saveAllProfits,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AccountingTheme.neonGreen,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.save, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('حفظ الكل',
                          style: GoogleFonts.cairo(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: _plans.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final plan = _plans[index];
              final planId = plan['Id']?.toString() ?? '';
              final controller = _profitControllers[planId];
              final profit = (plan['ProfitAmount'] ?? 0).toDouble();

              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AccountingTheme.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: profit > 0
                        ? AccountingTheme.neonGreen.withOpacity(0.3)
                        : AccountingTheme.borderColor,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AccountingTheme.neonBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.wifi,
                              size: 14, color: AccountingTheme.neonBlue),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            plan['NameAr'] ?? plan['Name'] ?? '',
                            style: GoogleFonts.cairo(
                                fontSize: 13, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AccountingTheme.neonPurple.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${plan['SpeedMbps'] ?? '-'} Mbps',
                            style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AccountingTheme.neonPurple),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('السعر الشهري',
                                  style: GoogleFonts.cairo(
                                      fontSize: 9,
                                      color: AccountingTheme.textMuted)),
                              Text(
                                '${_formatNumber(plan['MonthlyPrice'])} د.ع',
                                style: GoogleFonts.cairo(
                                    fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 110,
                          height: 36,
                          child: TextField(
                            controller: controller,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.cairo(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AccountingTheme.neonGreen),
                            decoration: InputDecoration(
                              hintText: '0',
                              hintStyle: GoogleFonts.cairo(
                                  color: AccountingTheme.textMuted,
                                  fontSize: 12),
                              suffixText: 'د.ع',
                              suffixStyle: GoogleFonts.cairo(fontSize: 9),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 6),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            final p =
                                double.tryParse(controller?.text ?? '') ?? 0;
                            if (p > 0) _savePlanProfit(planId, p);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AccountingTheme.neonBlue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.save,
                                size: 16, color: AccountingTheme.neonBlue),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== واجهة الحاسوب ====================

  Widget _buildDesktopBody() {
    return Column(
      children: [
        // شريط التبويبات
        Container(
          decoration: const BoxDecoration(
            color: AccountingTheme.bgCard,
            border:
                Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: AccountingTheme.neonPink,
            labelColor: AccountingTheme.textPrimary,
            unselectedLabelColor: AccountingTheme.textMuted,
            labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            unselectedLabelStyle: GoogleFonts.cairo(),
            tabs: const [
              Tab(
                icon: Icon(Icons.percent, size: 18),
                text: 'نسب العمولات',
              ),
              Tab(
                icon: Icon(Icons.monetization_on, size: 18),
                text: 'أرباح الباقات',
              ),
            ],
          ),
        ),

        // محتوى التبويبات
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDesktopCommissionContent(),
              _buildDesktopProfitsContent(),
            ],
          ),
        ),
      ],
    );
  }

  // ---- ديسكتوب: نسب العمولات ----

  Widget _buildDesktopCommissionContent() {
    return Padding(
      padding: EdgeInsets.all(context.accR.spaceXXL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(flex: 2, child: _buildAgentSelector()),
              SizedBox(width: context.accR.spaceXL),
              if (_selectedAgent != null)
                ElevatedButton.icon(
                  onPressed: _saveAgentRates,
                  icon: Icon(Icons.save, size: context.accR.iconM),
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
          SizedBox(height: context.accR.spaceXL),
          Expanded(
            child: _selectedAgent == null
                ? _buildSelectAgentPrompt()
                : _buildDesktopCommissionTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentSelector() {
    return _buildInlineAgentSearch(isMobile: false);
  }

  Widget _buildSelectAgentPrompt() {
    final isMob = MediaQuery.of(context).size.width < 700;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_search,
              size: isMob ? 48 : context.accR.iconEmpty,
              color: AccountingTheme.textMuted.withOpacity(0.3)),
          SizedBox(height: isMob ? 12 : context.accR.spaceXL),
          Text(
            'اختر وكيلاً لعرض وتعديل نسب عمولاته',
            style: GoogleFonts.cairo(
              fontSize: isMob ? 13 : context.accR.headingSmall,
              color: AccountingTheme.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopCommissionTable() {
    return Container(
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(context.accR.spaceXL),
              color: AccountingTheme.neonBlue.withOpacity(0.05),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AccountingTheme.neonBlue.withOpacity(0.15),
                    child: Text(
                      _selectedAgent?.name.isNotEmpty == true
                          ? _selectedAgent!.name[0]
                          : '?',
                      style: GoogleFonts.cairo(
                        fontSize: context.accR.headingMedium,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.neonBlue,
                      ),
                    ),
                  ),
                  SizedBox(width: context.accR.spaceXL),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedAgent?.name ?? '',
                        style: GoogleFonts.cairo(
                          fontSize: context.accR.headingSmall,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'الكود: ${_selectedAgent?.agentCode ?? ''} | الهاتف: ${_selectedAgent?.phoneNumber ?? ''}',
                        style: GoogleFonts.cairo(
                          fontSize: context.accR.financialSmall,
                          color: AccountingTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 48),
                    child: DataTable(
                    headingRowColor:
                        WidgetStateProperty.all(AccountingTheme.bgSecondary),
                    columnSpacing: 16,
                    columns: [
                      DataColumn(
                          label: Text('الباقة',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold))),
                      DataColumn(
                          label: Text('السعر',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold))),
                      DataColumn(
                          label: Text('الربح',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  color: AccountingTheme.neonGreen))),
                      DataColumn(
                          label: Text('النسبة %',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  color: AccountingTheme.neonBlue))),
                      DataColumn(
                          label: Text('مبلغ العمولة',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  color: AccountingTheme.neonPurple))),
                    ],
                    rows: _plans.map((plan) {
                      final planId = plan['Id']?.toString() ?? '';
                      final controller = _rateControllers[planId];
                      final profit = (plan['ProfitAmount'] ?? 0).toDouble();
                      final pct = double.tryParse(controller?.text ?? '') ?? 0;
                      final commissionAmount = profit * pct / 100;

                      return DataRow(cells: [
                        DataCell(Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(plan['NameAr'] ?? plan['Name'] ?? '',
                                style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.w600)),
                            Text('${plan['SpeedMbps'] ?? '-'} Mbps',
                                style: GoogleFonts.cairo(
                                    fontSize: context.accR.small,
                                    color: AccountingTheme.textMuted)),
                          ],
                        )),
                        DataCell(Text(
                          '${_formatNumber(plan['MonthlyPrice'])} د.ع',
                          style: GoogleFonts.cairo(
                              fontSize: context.accR.financialSmall),
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
                        DataCell(SizedBox(
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
                              suffixStyle: GoogleFonts.cairo(
                                  fontSize: context.accR.small),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        )),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: commissionAmount > 0
                                ? AccountingTheme.neonPurple.withOpacity(0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            commissionAmount > 0
                                ? '${_formatNumber(commissionAmount)} د.ع'
                                : '-',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: context.accR.body,
                              color: commissionAmount > 0
                                  ? AccountingTheme.neonPurple
                                  : AccountingTheme.textMuted,
                            ),
                          ),
                        )),
                      ]);
                    }).toList(),
                  ),
                  ),
                ),
              ),
            ),
            if (_selectedAgent != null)
              Container(
                padding: EdgeInsets.all(context.accR.spaceXL),
                color: AccountingTheme.bgSecondary,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTotalCard(
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

  // ---- ديسكتوب: أرباح الباقات ----

  Widget _buildDesktopProfitsContent() {
    return Padding(
      padding: EdgeInsets.all(context.accR.spaceXXL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تحديد ربح كل باقة',
                      style: GoogleFonts.cairo(
                        fontSize: context.accR.headingMedium,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: context.accR.spaceXS),
                    Text(
                      'الربح هو المبلغ الصافي بعد خصم التكاليف - العمولة تُحسب كنسبة من هذا الربح',
                      style: GoogleFonts.cairo(
                        fontSize: context.accR.financialSmall,
                        color: AccountingTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _saveAllProfits,
                icon: Icon(Icons.save, size: context.accR.iconM),
                label: Text('حفظ الكل',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.neonGreen,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                      horizontal: context.accR.spaceXXL,
                      vertical: context.accR.spaceM),
                ),
              ),
            ],
          ),
          SizedBox(height: context.accR.spaceXL),
          Expanded(
            child: _plans.isEmpty
                ? Center(
                    child: Text('لا توجد باقات',
                        style: GoogleFonts.cairo(
                            fontSize: context.accR.headingSmall,
                            color: AccountingTheme.textMuted)),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: AccountingTheme.bgCard,
                      borderRadius:
                          BorderRadius.circular(context.accR.cardRadius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(context.accR.cardRadius),
                      child: SingleChildScrollView(
                        child: SizedBox(
                          width: double.infinity,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                                AccountingTheme.bgSecondary),
                            columnSpacing: 24,
                            columns: [
                              DataColumn(
                                  label: Text('الباقة',
                                      style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.bold))),
                              DataColumn(
                                  label: Text('السرعة',
                                      style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.bold))),
                              DataColumn(
                                  label: Text('السعر الشهري',
                                      style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.bold))),
                              DataColumn(
                                  label: Text('الربح',
                                      style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.bold,
                                          color: AccountingTheme.neonGreen))),
                              DataColumn(
                                  label: Text('إجراء',
                                      style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.bold))),
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
                                DataCell(SizedBox(
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
                                      suffixStyle: GoogleFonts.cairo(
                                          fontSize: context.accR.small),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 8),
                                      isDense: true,
                                    ),
                                  ),
                                )),
                                DataCell(IconButton(
                                  icon: Icon(Icons.save,
                                      color: AccountingTheme.neonBlue,
                                      size: context.accR.iconM),
                                  tooltip: 'حفظ ربح هذه الباقة',
                                  onPressed: () {
                                    final profit = double.tryParse(
                                            controller?.text ?? '') ??
                                        0;
                                    if (profit > 0) {
                                      _savePlanProfit(planId, profit);
                                    }
                                  },
                                )),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalCard(String label, double amount, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.spaceXXL, vertical: context.accR.spaceM),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate, color: color, size: context.accR.iconM),
          SizedBox(width: context.accR.spaceS),
          Text(label,
              style: GoogleFonts.cairo(
                  fontSize: context.accR.body,
                  color: AccountingTheme.textSecondary)),
          SizedBox(width: context.accR.spaceM),
          Text(
            '${_formatNumber(amount)} د.ع',
            style: GoogleFonts.cairo(
              fontSize: context.accR.headingSmall,
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
