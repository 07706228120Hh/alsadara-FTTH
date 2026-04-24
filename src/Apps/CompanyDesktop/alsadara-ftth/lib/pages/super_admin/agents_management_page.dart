/// صفحة إدارة الوكلاء - Agents Management Page
/// عرض الوكلاء + إضافة/تعديل/حذف + المحاسبة (أجور + تسديد + صافي)
library;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../theme/accounting_theme.dart';
import '../../models/agent.dart';
import '../../services/agent_api_service.dart';
import '../accounting/agent_transactions_page.dart';
import '../accounting/agent_commission_page.dart';

class AgentsManagementPage extends StatefulWidget {
  final String? initialAgentId;
  final String? companyId;
  const AgentsManagementPage({super.key, this.initialAgentId, this.companyId});

  @override
  State<AgentsManagementPage> createState() => _AgentsManagementPageState();
}

class _AgentsManagementPageState extends State<AgentsManagementPage> {
  final AgentApiService _agentService = AgentApiService.instance;

  bool _isLoading = true;
  String? _errorMessage;
  List<AgentModel> _agents = [];
  String _searchQuery = '';
  AgentStatus? _statusFilter;
  AgentModel? _selectedAgent; // للعرض التفصيلي

  // قائمة التبويب الجانبية
  int _sidebarIndex = 0; // 0=الوكلاء، 1=المعاملات، 2=العمولات

  // محاسبة
  AgentAccountingSummary? _accountingSummary;

  bool get _isSingleAgentMode => widget.initialAgentId != null;

  @override
  void initState() {
    super.initState();
    if (_isSingleAgentMode) {
      _loadSingleAgent();
    } else {
      _loadData();
    }
  }

  Future<void> _loadSingleAgent() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final agent = await _agentService.getById(widget.initialAgentId!);
      if (!mounted) return;
      if (agent != null) {
        setState(() {
          _selectedAgent = agent;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'لم يتم العثور على الوكيل';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'حدث خطأ';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // جلب البيانات بشكل مستقل لتجنب فشل الكل عند فشل أحدها
      List<AgentModel> agents = [];
      AgentAccountingSummary? summary;
      String? partialError;

      try {
        agents = await _agentService.getAll();
      } catch (e) {
        partialError = 'خطأ في جلب الوكلاء';
      }

      try {
        summary = await _agentService.getAccountingSummary();
      } catch (e) {
        // لا نعرض خطأ إذا نجح جلب الوكلاء
        if (agents.isEmpty && partialError != null) {
          partialError = '$partialError\n$e';
        }
      }

      if (!mounted) return;
      setState(() {
        _agents = agents;
        _accountingSummary = summary;
        _errorMessage = agents.isEmpty ? partialError : null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'حدث خطأ';
        _isLoading = false;
      });
    }
  }

  List<AgentModel> get _filteredAgents {
    var list = _agents;
    if (_statusFilter != null) {
      list = list.where((a) => a.status == _statusFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((a) =>
              a.name.toLowerCase().contains(q) ||
              a.agentCode.toLowerCase().contains(q) ||
              a.phoneNumber.contains(q) ||
              (a.city?.toLowerCase().contains(q) ?? false) ||
              (a.area?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isMob = MediaQuery.of(context).size.width < 700;

    // وضع عرض وكيل واحد فقط
    if (_isSingleAgentMode) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: AccountingTheme.bgPrimary,
          body: SafeArea(
            child: Column(
              children: [
                // شريط علوي بزر رجوع
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: isMob ? 12 : 20, vertical: isMob ? 10 : 14),
                  decoration: BoxDecoration(
                    color: AccountingTheme.bgCard,
                    border: Border(
                        bottom: BorderSide(color: AccountingTheme.borderColor)),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: 'رجوع',
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: AccountingTheme.neonPurpleGradient,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.support_agent_rounded,
                            color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedAgent?.name ?? 'تفاصيل الوكيل',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AccountingTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage != null
                          ? _buildError()
                          : _selectedAgent != null
                              ? _buildAgentDetail()
                              : const Center(
                                  child: Text('لم يتم العثور على الوكيل')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // الوضع العادي - موبايل مع شريط تنقل سفلي
    if (isMob) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: AccountingTheme.bgPrimary,
          body: SafeArea(
            child: Column(
              children: [
                _buildToolbar(),
                if (_sidebarIndex == 0 && _selectedAgent == null)
                  _buildAccountingBar(),
                Expanded(
                  child: _sidebarIndex == 0
                      ? _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _errorMessage != null
                              ? _buildError()
                              : _selectedAgent != null
                                  ? _buildAgentDetail()
                                  : _buildAgentsList()
                      : _sidebarIndex == 1
                          ? AgentTransactionsPage(companyId: widget.companyId)
                          : AgentCommissionPage(companyId: widget.companyId),
                ),
              ],
            ),
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: AccountingTheme.bgCard,
              border: const Border(
                  top: BorderSide(color: AccountingTheme.borderColor)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    _buildMobileNavItem(0, Icons.support_agent_rounded,
                        'الوكلاء', AccountingTheme.neonPurple),
                    _buildMobileNavItem(1, Icons.receipt_long, 'المعاملات',
                        AccountingTheme.neonOrange),
                    _buildMobileNavItem(
                        2, Icons.percent, 'العمولات', AccountingTheme.neonPink),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // الوضع العادي - ديسكتوب مع القائمة الجانبية
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: SafeArea(
          child: Row(
            children: [
              _buildSidebar(),
              Expanded(
                child: Column(
                  children: [
                    _buildToolbar(),
                    if (_sidebarIndex == 0) _buildAccountingBar(),
                    Expanded(
                      child: _sidebarIndex == 0
                          ? _isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : _errorMessage != null
                                  ? _buildError()
                                  : _selectedAgent != null
                                      ? _buildAgentDetail()
                                      : _buildAgentsList()
                          : _sidebarIndex == 1
                              ? AgentTransactionsPage(
                                  companyId: widget.companyId)
                              : AgentCommissionPage(
                                  companyId: widget.companyId),
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

  // ==================== القائمة الجانبية ====================

  Widget _buildSidebar() {
    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: const Border(
          left: BorderSide(color: AccountingTheme.borderColor, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          // زر العودة
          Tooltip(
            message: 'العودة',
            preferBelow: false,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(8),
              hoverColor: AccountingTheme.neonBlue.withOpacity(0.08),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AccountingTheme.neonBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: AccountingTheme.neonBlue,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(
              height: 1,
              color: AccountingTheme.borderColor,
              indent: 10,
              endIndent: 10),
          const SizedBox(height: 8),
          // عناصر القائمة
          _SidebarItem(
            icon: Icons.support_agent_rounded,
            label: 'الوكلاء',
            color: AccountingTheme.neonPurple,
            isSelected: _sidebarIndex == 0,
            onTap: () => setState(() => _sidebarIndex = 0),
          ),
          _SidebarItem(
            icon: Icons.receipt_long,
            label: 'المعاملات',
            color: AccountingTheme.neonOrange,
            isSelected: _sidebarIndex == 1,
            onTap: () => setState(() => _sidebarIndex = 1),
          ),
          _SidebarItem(
            icon: Icons.percent,
            label: 'العمولات',
            color: AccountingTheme.neonPink,
            isSelected: _sidebarIndex == 2,
            onTap: () => setState(() => _sidebarIndex = 2),
          ),
          const Spacer(),
          // تحديث
          Tooltip(
            message: 'تحديث',
            preferBelow: false,
            child: InkWell(
              onTap: () {
                if (_sidebarIndex == 0) _loadData();
              },
              borderRadius: BorderRadius.circular(8),
              hoverColor: AccountingTheme.neonGreen.withOpacity(0.08),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AccountingTheme.neonGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.refresh,
                  color: AccountingTheme.neonGreen,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildMobileNavItem(
      int index, IconData icon, String label, Color color) {
    final isSelected = _sidebarIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _sidebarIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isSelected ? color : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 20,
                  color: isSelected ? color : AccountingTheme.textMuted),
              const SizedBox(height: 2),
              Text(label,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? color : AccountingTheme.textMuted,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== شريط الأدوات ====================

  Widget _buildToolbar() {
    final isMob = MediaQuery.of(context).size.width < 700;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 12 : 20, vertical: isMob ? 10 : 14),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child:
          isMob ? _buildMobileToolbarContent() : _buildDesktopToolbarContent(),
    );
  }

  // الحصول على عنوان وأيقونة ولون التبويب الحالي
  ({String title, IconData icon, Color color}) get _currentTabInfo {
    switch (_sidebarIndex) {
      case 1:
        return (
          title: 'معاملات الوكلاء',
          icon: Icons.receipt_long,
          color: AccountingTheme.neonOrange
        );
      case 2:
        return (
          title: 'العمولات',
          icon: Icons.percent,
          color: AccountingTheme.neonPink
        );
      default:
        return (
          title: 'إدارة الوكلاء',
          icon: Icons.support_agent_rounded,
          color: AccountingTheme.neonPurple
        );
    }
  }

  Widget _buildMobileToolbarContent() {
    final tabInfo = _currentTabInfo;
    return Column(
      children: [
        Row(
          children: [
            if (_sidebarIndex == 0 && _selectedAgent != null)
              GestureDetector(
                onTap: () => setState(() => _selectedAgent = null),
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.arrow_back_rounded,
                      size: 20, color: AccountingTheme.neonPink),
                ),
              )
            else
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 20, color: AccountingTheme.textSecondary),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: _sidebarIndex == 0
                    ? AccountingTheme.neonPurpleGradient
                    : null,
                color:
                    _sidebarIndex != 0 ? tabInfo.color.withOpacity(0.1) : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(tabInfo.icon,
                  color: _sidebarIndex == 0 ? Colors.white : tabInfo.color,
                  size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _sidebarIndex == 0
                    ? (_selectedAgent?.name ?? tabInfo.title)
                    : tabInfo.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_sidebarIndex == 0 && _selectedAgent == null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AccountingTheme.neonPink.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${_filteredAgents.length}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.neonPink)),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'تحديث',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                style: IconButton.styleFrom(
                    foregroundColor: AccountingTheme.textSecondary),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => _showAddAgentDialog(),
                icon: const Icon(Icons.add_circle,
                    size: 22, color: AccountingTheme.neonPink),
                tooltip: 'وكيل جديد',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ],
        ),
        if (_sidebarIndex == 0 && _selectedAgent == null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      hintText: 'بحث عن وكيل...',
                      hintStyle: const TextStyle(
                          fontSize: 12, color: AccountingTheme.textMuted),
                      prefixIcon: const Icon(Icons.search,
                          size: 16, color: AccountingTheme.textMuted),
                      filled: true,
                      fillColor: AccountingTheme.bgPrimary,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: AccountingTheme.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: AccountingTheme.borderColor),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<AgentStatus?>(
                tooltip: 'فلتر الحالة',
                onSelected: (v) => setState(() => _statusFilter = v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: null, child: Text('الكل')),
                  const PopupMenuItem(
                      value: AgentStatus.active, child: Text('نشط')),
                  const PopupMenuItem(
                      value: AgentStatus.suspended, child: Text('معلق')),
                  const PopupMenuItem(
                      value: AgentStatus.banned, child: Text('محظور')),
                  const PopupMenuItem(
                      value: AgentStatus.inactive, child: Text('غير مفعل')),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(color: AccountingTheme.borderColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.filter_list,
                      size: 16,
                      color: _statusFilter != null
                          ? AccountingTheme.neonPink
                          : AccountingTheme.textMuted),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDesktopToolbarContent() {
    final tabInfo = _currentTabInfo;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient:
                _sidebarIndex == 0 ? AccountingTheme.neonPurpleGradient : null,
            color: _sidebarIndex != 0 ? tabInfo.color.withOpacity(0.1) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(tabInfo.icon,
              color: _sidebarIndex == 0 ? Colors.white : tabInfo.color,
              size: 18),
        ),
        const SizedBox(width: 12),
        if (_sidebarIndex == 0 && _selectedAgent != null) ...[
          GestureDetector(
            onTap: () => setState(() => _selectedAgent = null),
            child: Text('الوكلاء',
                style: TextStyle(
                  fontSize: 16,
                  color: AccountingTheme.neonPink,
                  decoration: TextDecoration.underline,
                )),
          ),
          const Text(' / ',
              style: TextStyle(
                  fontSize: 16, color: AccountingTheme.textSecondary)),
          Text(_selectedAgent!.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AccountingTheme.textPrimary,
              )),
        ] else ...[
          Text(tabInfo.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AccountingTheme.textPrimary,
              )),
          if (_sidebarIndex == 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AccountingTheme.neonPink.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${_filteredAgents.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AccountingTheme.neonPink,
                  )),
            ),
          ],
        ],
        const Spacer(),
        if (_sidebarIndex == 0 && _selectedAgent == null)
          SizedBox(
            width: 220,
            height: 36,
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: 'بحث عن وكيل...',
                hintStyle: const TextStyle(
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        if (_sidebarIndex == 0) const SizedBox(width: 8),
        if (_sidebarIndex == 0 && _selectedAgent == null)
          PopupMenuButton<AgentStatus?>(
            tooltip: 'فلتر الحالة',
            onSelected: (v) => setState(() => _statusFilter = v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('الكل')),
              const PopupMenuItem(
                  value: AgentStatus.active, child: Text('نشط')),
              const PopupMenuItem(
                  value: AgentStatus.suspended, child: Text('معلق')),
              const PopupMenuItem(
                  value: AgentStatus.banned, child: Text('محظور')),
              const PopupMenuItem(
                  value: AgentStatus.inactive, child: Text('غير مفعل')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AccountingTheme.borderColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_list,
                      size: 16,
                      color: _statusFilter != null
                          ? AccountingTheme.neonPink
                          : AccountingTheme.textMuted),
                  const SizedBox(width: 4),
                  Text(_statusFilter?.displayName ?? 'الحالة',
                      style: TextStyle(
                        fontSize: 12,
                        color: _statusFilter != null
                            ? AccountingTheme.neonPink
                            : AccountingTheme.textSecondary,
                      )),
                ],
              ),
            ),
          ),
        if (_sidebarIndex == 0) ...[
          const SizedBox(width: 8),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(
              foregroundColor: AccountingTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: () => _showAddAgentDialog(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('وكيل جديد', style: TextStyle(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.neonPink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ],
    );
  }

  // ==================== شريط المحاسبة ====================

  Widget _buildAccountingBar() {
    final isMob = MediaQuery.of(context).size.width < 700;
    final s = _accountingSummary;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 10 : 20, vertical: isMob ? 8 : 10),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: isMob
          ? Row(
              children: [
                Expanded(
                  child: _buildStatChip(
                      'الوكلاء',
                      '${s?.totalAgents ?? _agents.length}',
                      AccountingTheme.neonBlue,
                      Icons.people),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildStatChip(
                      'نشط',
                      '${s?.activeAgents ?? _agents.where((a) => a.status == AgentStatus.active).length}',
                      AccountingTheme.neonGreen,
                      Icons.check_circle),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildStatChip(
                      'الأجور',
                      _formatCurrency(s?.totalCharges ?? 0),
                      AccountingTheme.neonOrange,
                      Icons.trending_up),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildStatChip(
                      'التسديد',
                      _formatCurrency(s?.totalPayments ?? 0),
                      AccountingTheme.neonGreen,
                      Icons.trending_down),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildStatChip(
                      'الصافي',
                      _formatCurrency(s?.totalNetBalance ?? 0),
                      AccountingTheme.neonPink,
                      Icons.account_balance_wallet),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _buildStatChip(
                      'إجمالي الوكلاء',
                      '${s?.totalAgents ?? _agents.length}',
                      AccountingTheme.neonBlue,
                      Icons.people),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatChip(
                      'نشط',
                      '${s?.activeAgents ?? _agents.where((a) => a.status == AgentStatus.active).length}',
                      AccountingTheme.neonGreen,
                      Icons.check_circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatChip(
                      'إجمالي الأجور',
                      _formatCurrency(s?.totalCharges ?? 0),
                      AccountingTheme.neonOrange,
                      Icons.trending_up),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatChip(
                      'إجمالي التسديد',
                      _formatCurrency(s?.totalPayments ?? 0),
                      AccountingTheme.neonGreen,
                      Icons.trending_down),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatChip(
                      'صافي الرصيد',
                      _formatCurrency(s?.totalNetBalance ?? 0),
                      AccountingTheme.neonPink,
                      Icons.account_balance_wallet),
                ),
              ],
            ),
    );
  }

  Widget _buildStatChip(
      String label, String value, Color color, IconData icon) {
    final isMob = MediaQuery.of(context).size.width < 700;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 4 : 12, vertical: isMob ? 4 : 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: isMob
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: color),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
                Text(label,
                    style:
                        TextStyle(fontSize: 8, color: color.withOpacity(0.8)),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(value,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color)),
                const SizedBox(width: 4),
                Text(label,
                    style:
                        TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
              ],
            ),
    );
  }

  // ==================== قائمة الوكلاء ====================

  Widget _buildAgentsList() {
    final agents = _filteredAgents;
    if (agents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.support_agent_rounded,
                size: 48, color: AccountingTheme.textMuted.withOpacity(0.5)),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty ? 'لا توجد نتائج' : 'لا يوجد وكلاء بعد',
              style: const TextStyle(
                  fontSize: 16, color: AccountingTheme.textMuted),
            ),
            const SizedBox(height: 8),
            if (_searchQuery.isEmpty)
              TextButton.icon(
                onPressed: () => _showAddAgentDialog(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('إضافة أول وكيل'),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding:
          EdgeInsets.all(MediaQuery.of(context).size.width < 700 ? 10 : 16),
      itemCount: agents.length,
      itemBuilder: (context, index) => _buildAgentCard(agents[index]),
    );
  }

  Widget _buildAgentCard(AgentModel agent) {
    final isMob = MediaQuery.of(context).size.width < 700;
    final statusColor = _getStatusColor(agent.status);
    final isActive = agent.status == AgentStatus.active;

    return Container(
      margin: EdgeInsets.only(bottom: isMob ? 6 : 8),
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
          onTap: () => setState(() => _selectedAgent = agent),
          child: Padding(
            padding: EdgeInsets.all(isMob ? 10 : 14),
            child: isMob
                ? _buildMobileAgentCardContent(agent, statusColor, isActive)
                : _buildDesktopAgentCardContent(agent, statusColor, isActive),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileAgentCardContent(
      AgentModel agent, Color statusColor, bool isActive) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // الصف الأول: أيقونة + اسم + حالة + قائمة
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor.withOpacity(0.5)),
              ),
              child: Center(
                  child:
                      Icon(Icons.support_agent, size: 18, color: statusColor)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(agent.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AccountingTheme.textPrimary,
                            )),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(agent.status.displayName,
                            style: TextStyle(
                              fontSize: 9,
                              color: statusColor,
                              fontWeight: FontWeight.w500,
                            )),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(agent.agentCode,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AccountingTheme.neonPink,
                            fontWeight: FontWeight.w500,
                          )),
                      const SizedBox(width: 6),
                      const Icon(Icons.phone,
                          size: 10, color: AccountingTheme.textMuted),
                      const SizedBox(width: 2),
                      Text(agent.phoneNumber,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AccountingTheme.textSecondary,
                          )),
                    ],
                  ),
                ],
              ),
            ),
            _buildAgentPopupMenu(agent, isActive),
          ],
        ),
        const SizedBox(height: 8),
        // الصف الثاني: ملخص المحاسبة
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: AccountingTheme.neonOrange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    Text('أجور',
                        style: TextStyle(
                            fontSize: 9,
                            color:
                                AccountingTheme.neonOrange.withOpacity(0.8))),
                    Text(_formatCurrency(agent.totalCharges),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.neonOrange,
                        )),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: AccountingTheme.neonGreen.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    Text('تسديد',
                        style: TextStyle(
                            fontSize: 9,
                            color: AccountingTheme.neonGreen.withOpacity(0.8))),
                    Text(_formatCurrency(agent.totalPayments),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.neonGreen,
                        )),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: agent.hasDebt
                      ? AccountingTheme.danger.withOpacity(0.15)
                      : AccountingTheme.neonGreen.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    Text('صافي',
                        style: TextStyle(
                            fontSize: 9,
                            color: (agent.hasDebt
                                    ? AccountingTheme.danger
                                    : AccountingTheme.neonGreen)
                                .withOpacity(0.8))),
                    Text(_formatCurrency(agent.netBalance),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: agent.hasDebt
                              ? AccountingTheme.danger
                              : AccountingTheme.neonGreen,
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopAgentCardContent(
      AgentModel agent, Color statusColor, bool isActive) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: statusColor.withOpacity(0.5)),
          ),
          child: Center(
              child: Icon(Icons.support_agent, size: 20, color: statusColor)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(agent.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AccountingTheme.textPrimary,
                      )),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(agent.status.displayName,
                        style: TextStyle(
                          fontSize: 10,
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                        )),
                  ),
                  const SizedBox(width: 6),
                  Text(agent.type.displayName,
                      style: TextStyle(
                        fontSize: 10,
                        color: AccountingTheme.textMuted,
                      )),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(agent.agentCode,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AccountingTheme.neonPink,
                        fontWeight: FontWeight.w500,
                      )),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: agent.phoneNumber));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تم نسخ ${agent.phoneNumber}'), duration: const Duration(seconds: 1)),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.phone, size: 11, color: AccountingTheme.textMuted),
                        const SizedBox(width: 3),
                        Text(agent.phoneNumber,
                            style: const TextStyle(fontSize: 11, color: AccountingTheme.textSecondary)),
                        const SizedBox(width: 2),
                        const Icon(Icons.copy, size: 10, color: AccountingTheme.textMuted),
                      ],
                    ),
                  ),
                  if (agent.plainPassword != null && agent.plainPassword!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: agent.plainPassword!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم نسخ كلمة المرور'), duration: Duration(seconds: 1)),
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock, size: 11, color: AccountingTheme.textMuted),
                          const SizedBox(width: 3),
                          Text(agent.plainPassword!,
                              style: const TextStyle(fontSize: 11, color: AccountingTheme.textSecondary)),
                          const SizedBox(width: 2),
                          const Icon(Icons.copy, size: 10, color: AccountingTheme.textMuted),
                        ],
                      ),
                    ),
                  ],
                  if (agent.city != null) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.location_on,
                        size: 11, color: AccountingTheme.textMuted),
                    const SizedBox(width: 3),
                    Text(
                        '${agent.city}${agent.area != null ? ' - ${agent.area}' : ''}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AccountingTheme.textSecondary,
                        )),
                  ],
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _sendAgentInfoViaWhatsApp(agent),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.send, size: 10, color: Color(0xFF25D366)),
                          SizedBox(width: 3),
                          Text('إرسال البيانات', style: TextStyle(fontSize: 10, color: Color(0xFF25D366), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('أجور: ',
                    style: TextStyle(
                        fontSize: 10, color: AccountingTheme.textMuted)),
                Text(_formatCurrency(agent.totalCharges),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AccountingTheme.neonOrange,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('تسديد: ',
                    style: TextStyle(
                        fontSize: 10, color: AccountingTheme.textMuted)),
                Text(_formatCurrency(agent.totalPayments),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AccountingTheme.neonGreen,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: agent.hasDebt
                    ? AccountingTheme.danger.withOpacity(0.2)
                    : AccountingTheme.neonGreen.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'صافي: ${_formatCurrency(agent.netBalance)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: agent.hasDebt
                      ? AccountingTheme.danger
                      : AccountingTheme.neonGreen,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
        _buildAgentPopupMenu(agent, isActive),
      ],
    );
  }

  Future<void> _sendAgentInfoViaWhatsApp(AgentModel agent) async {
    final phone = agent.phoneNumber.startsWith('0')
        ? '964${agent.phoneNumber.substring(1)}'
        : agent.phoneNumber;
    final msg = 'مرحباً ${agent.name}\n\n'
        'بيانات حسابك في منصة الصدارة:\n\n'
        'كود الوكيل: ${agent.agentCode}\n'
        'كلمة المرور: ${agent.plainPassword ?? "---"}\n\n'
        'رابط الدخول:\nhttps://ramzbot.com\n\n'
        'شركة الصدارة - المشغل الرسمي للمشروع الوطني';
    final encoded = Uri.encodeComponent(msg);
    final url = 'whatsapp://send?phone=$phone&text=$encoded';
    try {
      await launchUrl(Uri.parse(url));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح واتساب'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildAgentPopupMenu(AgentModel agent, bool isActive) {
    return PopupMenuButton<String>(
      tooltip: 'خيارات',
      onSelected: (v) => _handleAgentAction(v, agent),
      itemBuilder: (_) => [
        const PopupMenuItem(
            value: 'charge',
            child: Row(children: [
              Icon(Icons.add_circle_outline,
                  size: 16, color: AccountingTheme.neonOrange),
              SizedBox(width: 8),
              Text('إضافة أجور'),
            ])),
        const PopupMenuItem(
            value: 'payment',
            child: Row(children: [
              Icon(Icons.payments_outlined,
                  size: 16, color: AccountingTheme.neonGreen),
              SizedBox(width: 8),
              Text('تسجيل تسديد'),
            ])),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: 'edit',
            child: Row(children: [
              Icon(Icons.edit_outlined,
                  size: 16, color: AccountingTheme.neonBlue),
              SizedBox(width: 8),
              Text('تعديل'),
            ])),
        if (isActive)
          const PopupMenuItem(
              value: 'suspend',
              child: Row(children: [
                Icon(Icons.pause_circle_outline,
                    size: 16, color: AccountingTheme.warning),
                SizedBox(width: 8),
                Text('تعليق'),
              ]))
        else
          const PopupMenuItem(
              value: 'activate',
              child: Row(children: [
                Icon(Icons.play_circle_outline,
                    size: 16, color: AccountingTheme.neonGreen),
                SizedBox(width: 8),
                Text('تفعيل'),
              ])),
        const PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              Icon(Icons.delete_outline,
                  size: 16, color: AccountingTheme.danger),
              SizedBox(width: 8),
              Text('حذف'),
            ])),
      ],
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          border: Border.all(color: AccountingTheme.borderColor),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.more_vert,
            size: 16, color: AccountingTheme.textMuted),
      ),
    );
  }

  // ==================== تفاصيل الوكيل ====================

  Widget _buildAgentDetail() {
    final isMob = MediaQuery.of(context).size.width < 700;
    final agent = _selectedAgent!;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMob ? 10 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(agent),
          const SizedBox(height: 12),
          _buildAccountingActions(agent),
          const SizedBox(height: 12),
          _buildTransactionsSection(agent),
        ],
      ),
    );
  }

  Widget _buildInfoCard(AgentModel agent) {
    final isMob = MediaQuery.of(context).size.width < 700;
    final statusColor = _getStatusColor(agent.status);
    return Container(
      padding: EdgeInsets.all(isMob ? 12 : 16),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AccountingTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: isMob ? 40 : 50,
                height: isMob ? 40 : 50,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withOpacity(0.5)),
                ),
                child: Center(
                    child: Icon(Icons.support_agent,
                        size: isMob ? 22 : 26, color: statusColor)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(agent.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: isMob ? 15 : 18,
                                  fontWeight: FontWeight.bold,
                                  color: AccountingTheme.textPrimary)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(agent.status.displayName,
                              style: TextStyle(
                                  fontSize: isMob ? 10 : 11,
                                  color: statusColor,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${agent.agentCode}  •  ${agent.type.displayName}',
                        style: TextStyle(
                            fontSize: isMob ? 11 : 12,
                            color: AccountingTheme.neonPink)),
                  ],
                ),
              ),
              if (!isMob)
                TextButton.icon(
                  onPressed: () => _showEditAgentDialog(agent),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('تعديل', style: TextStyle(fontSize: 12)),
                ),
              if (isMob)
                IconButton(
                  onPressed: () => _showEditAgentDialog(agent),
                  icon: const Icon(Icons.edit_outlined,
                      size: 16, color: AccountingTheme.neonBlue),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'تعديل',
                ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: AccountingTheme.borderColor, height: 1),
          const SizedBox(height: 14),
          Wrap(
            spacing: isMob ? 12 : 24,
            runSpacing: 8,
            children: [
              _buildDetailItem(Icons.phone, 'الهاتف', agent.phoneNumber),
              _buildPasswordItem(agent.plainPassword),
              if (agent.email != null)
                _buildDetailItem(Icons.email, 'البريد', agent.email!),
              if (agent.city != null)
                _buildDetailItem(Icons.location_city, 'المدينة', agent.city!),
              if (agent.area != null)
                _buildDetailItem(Icons.map, 'المنطقة', agent.area!),
              if (agent.pageId != null)
                _buildDetailItem(Icons.badge, 'معرف الصفحة', agent.pageId!),
              if (agent.companyName != null)
                _buildDetailItem(Icons.business, 'الشركة', agent.companyName!),
              if (agent.lastLoginAt != null)
                _buildDetailItem(Icons.access_time, 'آخر دخول',
                    DateFormat('yyyy-MM-dd HH:mm').format(agent.lastLoginAt!)),
              _buildDetailItem(Icons.calendar_today, 'تاريخ الإنشاء',
                  DateFormat('yyyy-MM-dd').format(agent.createdAt)),
            ],
          ),
          const SizedBox(height: 14),
          // ملخص المحاسبة
          Row(
            children: [
              Expanded(
                  child: _buildBalanceBox('الأجور', agent.totalCharges,
                      AccountingTheme.neonOrange)),
              const SizedBox(width: 10),
              Expanded(
                  child: _buildBalanceBox('التسديد', agent.totalPayments,
                      AccountingTheme.neonGreen)),
              const SizedBox(width: 10),
              Expanded(
                  child: _buildBalanceBox(
                      'الصافي',
                      agent.netBalance,
                      agent.hasDebt
                          ? AccountingTheme.danger
                          : AccountingTheme.neonGreen)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AccountingTheme.textMuted),
        const SizedBox(width: 4),
        Text('$label: ',
            style: const TextStyle(
                fontSize: 12, color: AccountingTheme.textMuted)),
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                color: AccountingTheme.textPrimary,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildPasswordItem(String? password) {
    if (password == null || password.isEmpty) return const SizedBox.shrink();
    return StatefulBuilder(
      builder: (context, setLocalState) {
        bool obscured = true;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 14, color: AccountingTheme.textMuted),
            const SizedBox(width: 4),
            const Text('كلمة المرور: ',
                style: TextStyle(fontSize: 12, color: AccountingTheme.textMuted)),
            StatefulBuilder(
              builder: (ctx, setState2) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      obscured ? '••••••••' : password,
                      style: TextStyle(
                        fontSize: 12,
                        color: obscured ? AccountingTheme.textMuted : AccountingTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontFamily: obscured ? null : 'monospace',
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => setState2(() => obscured = !obscured),
                      child: Icon(
                        obscured ? Icons.visibility_off : Icons.visibility,
                        size: 16,
                        color: AccountingTheme.textMuted,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildBalanceBox(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
          const SizedBox(height: 4),
          Text(_formatCurrency(amount),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text('د.ع',
              style: TextStyle(fontSize: 10, color: color.withOpacity(0.6))),
        ],
      ),
    );
  }

  Widget _buildAccountingActions(AgentModel agent) {
    final isMob = MediaQuery.of(context).size.width < 700;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _showTransactionDialog(agent, isCharge: true),
            icon: Icon(Icons.add_circle_outline, size: isMob ? 14 : 16),
            label:
                Text('إضافة أجور', style: TextStyle(fontSize: isMob ? 12 : 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.neonOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _showTransactionDialog(agent, isCharge: false),
            icon: Icon(Icons.payments_outlined, size: isMob ? 14 : 16),
            label: Text('تسجيل تسديد',
                style: TextStyle(fontSize: isMob ? 12 : 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.neonGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionsSection(AgentModel agent) {
    final isMob = MediaQuery.of(context).size.width < 700;
    return Container(
      padding: EdgeInsets.all(isMob ? 10 : 16),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AccountingTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_rounded,
                  size: 18, color: AccountingTheme.neonPink),
              SizedBox(width: 8),
              Text('المعاملات المالية',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AccountingTheme.textPrimary,
                  )),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, dynamic>>(
            future: _agentService.getTransactions(agent.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ));
              }
              if (snapshot.hasError) {
                return Center(
                    child: Text('خطأ في جلب المعاملات',
                        style: TextStyle(color: AccountingTheme.danger)));
              }
              final data = snapshot.data ?? {};
              final List<AgentTransactionModel> transactions =
                  data['transactions'] ?? [];
              if (transactions.isEmpty) {
                return const Center(
                    child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('لا توجد معاملات',
                      style: TextStyle(color: AccountingTheme.textMuted)),
                ));
              }
              return Column(
                children:
                    transactions.map((tx) => _buildTransactionRow(tx)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(AgentTransactionModel tx) {
    final isCharge = tx.isCharge;
    final color =
        isCharge ? AccountingTheme.neonOrange : AccountingTheme.neonGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(isCharge ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(tx.type.displayName,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: color)),
                    const SizedBox(width: 6),
                    Text(tx.category.displayName,
                        style: const TextStyle(
                            fontSize: 10, color: AccountingTheme.textMuted)),
                  ],
                ),
                if (tx.description.isNotEmpty)
                  Text(tx.description,
                      style: const TextStyle(
                          fontSize: 11, color: AccountingTheme.textSecondary)),
                if (tx.referenceNumber != null &&
                    tx.referenceNumber!.isNotEmpty)
                  Text('مرجع: ${tx.referenceNumber}',
                      style: const TextStyle(
                          fontSize: 10, color: AccountingTheme.textMuted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${isCharge ? '+' : '-'} ${_formatCurrency(tx.amount)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  )),
              Text('الرصيد: ${_formatCurrency(tx.balanceAfter)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AccountingTheme.textMuted,
                  )),
            ],
          ),
          const SizedBox(width: 8),
          Text(DateFormat('MM/dd').format(tx.createdAt),
              style: const TextStyle(
                fontSize: 10,
                color: AccountingTheme.textMuted,
              )),
          const SizedBox(width: 4),
          // أزرار التعديل والحذف (مدير النظام فقط)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert,
                size: 16, color: AccountingTheme.textMuted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 14, color: AccountingTheme.neonBlue),
                    SizedBox(width: 6),
                    Text('تعديل', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 14, color: Colors.red),
                    SizedBox(width: 6),
                    Text('حذف',
                        style: TextStyle(fontSize: 12, color: Colors.red)),
                  ],
                ),
              ),
            ],
            onSelected: (action) {
              if (action == 'edit') {
                _showEditTransactionDialog(tx);
              } else if (action == 'delete') {
                _showDeleteTransactionDialog(tx);
              }
            },
          ),
        ],
      ),
    );
  }

  // ==================== حوارات (Dialogs) ====================

  void _showAddAgentDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final areaCtrl = TextEditingController();
    final pageIdCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    AgentType selectedType = AgentType.privateAgent;

    // قائمة الشركات
    List<Map<String, dynamic>> companies = [];
    String? selectedCompanyId;
    bool loadingCompanies = true;
    bool companiesFetched = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        // جلب الشركات مرة واحدة فقط عند أول بناء
        if (!companiesFetched) {
          companiesFetched = true;
          _agentService.getCompanies().then((list) {
            setDialogState(() {
              companies = list;
              if (companies.isNotEmpty) {
                selectedCompanyId =
                    (companies.first['Id'] ?? companies.first['id'])
                        ?.toString();
              }
              loadingCompanies = false;
            });
          }).catchError((e) {
            setDialogState(() => loadingCompanies = false);
          });
        }

        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.person_add,
                    size: 20, color: AccountingTheme.neonPink),
                SizedBox(width: 8),
                Text('إضافة وكيل جديد', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: min(400, MediaQuery.of(context).size.width * 0.85),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dialogTextField(nameCtrl, 'اسم الوكيل *', Icons.person),
                    const SizedBox(height: 10),
                    _dialogTextField(phoneCtrl, 'رقم الهاتف *', Icons.phone),
                    const SizedBox(height: 10),
                    _dialogTextField(passwordCtrl, 'كلمة المرور *', Icons.lock,
                        obscure: true),
                    const SizedBox(height: 10),
                    // نوع الوكيل
                    DropdownButtonFormField<AgentType>(
                      value: selectedType,
                      decoration: InputDecoration(
                        labelText: 'نوع الوكيل',
                        prefixIcon: const Icon(Icons.category, size: 18),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      items: AgentType.values
                          .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(t.displayName,
                                    style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(
                          () => selectedType = v ?? AgentType.privateAgent),
                    ),
                    const SizedBox(height: 10),
                    // اختيار الشركة
                    Builder(
                      builder: (_) {
                        if (loadingCompanies) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        if (companies.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('لا توجد شركات',
                                style: TextStyle(color: Colors.orange)),
                          );
                        }
                        return DropdownButtonFormField<String>(
                          value: selectedCompanyId,
                          decoration: InputDecoration(
                            labelText: 'الشركة *',
                            prefixIcon: const Icon(Icons.business, size: 18),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          items: companies
                              .map((c) => DropdownMenuItem(
                                    value:
                                        (c['Id'] ?? c['id'])?.toString() ?? '',
                                    child: Text(
                                        (c['Name'] ??
                                                    c['name'] ??
                                                    c['companyName'])
                                                ?.toString() ??
                                            'بدون اسم',
                                        style: const TextStyle(fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => selectedCompanyId = v),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _dialogTextField(
                        emailCtrl, 'البريد الإلكتروني', Icons.email),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                            child: _dialogTextField(
                                cityCtrl, 'المدينة', Icons.location_city)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _dialogTextField(
                                areaCtrl, 'المنطقة', Icons.map)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _dialogTextField(pageIdCtrl, 'معرف الصفحة', Icons.badge),
                    const SizedBox(height: 10),
                    _dialogTextField(notesCtrl, 'ملاحظات', Icons.note,
                        maxLines: 2),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.isEmpty ||
                      phoneCtrl.text.isEmpty ||
                      passwordCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('الاسم ورقم الهاتف وكلمة المرور مطلوبة')),
                    );
                    return;
                  }
                  if (selectedCompanyId == null || selectedCompanyId!.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يرجى اختيار الشركة')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    await _agentService.create(
                      name: nameCtrl.text,
                      type: selectedType,
                      phoneNumber: phoneCtrl.text,
                      password: passwordCtrl.text,
                      companyId: selectedCompanyId!,
                      email: emailCtrl.text.isEmpty ? null : emailCtrl.text,
                      city: cityCtrl.text.isEmpty ? null : cityCtrl.text,
                      area: areaCtrl.text.isEmpty ? null : areaCtrl.text,
                      pageId: pageIdCtrl.text.isEmpty ? null : pageIdCtrl.text,
                      notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                    );
                    await _loadData();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('تم إنشاء الوكيل بنجاح ✓'),
                            backgroundColor: Colors.green),
                      );
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
                  backgroundColor: AccountingTheme.neonPink,
                  foregroundColor: Colors.white,
                ),
                child: const Text('إنشاء'),
              ),
            ],
          ),
        );
      }),
    );
  }

  void _showEditAgentDialog(AgentModel agent) {
    final nameCtrl = TextEditingController(text: agent.name);
    final phoneCtrl = TextEditingController(text: agent.phoneNumber);
    final emailCtrl = TextEditingController(text: agent.email ?? '');
    final cityCtrl = TextEditingController(text: agent.city ?? '');
    final areaCtrl = TextEditingController(text: agent.area ?? '');
    final pageIdCtrl = TextEditingController(text: agent.pageId ?? '');
    final notesCtrl = TextEditingController(text: agent.notes ?? '');
    final passwordCtrl = TextEditingController();
    AgentType selectedType = agent.type;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.edit,
                    size: 20, color: AccountingTheme.neonBlue),
                const SizedBox(width: 8),
                Text('تعديل ${agent.name}',
                    style: const TextStyle(fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: min(400, MediaQuery.of(context).size.width * 0.85),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dialogTextField(nameCtrl, 'اسم الوكيل', Icons.person),
                    const SizedBox(height: 10),
                    _dialogTextField(phoneCtrl, 'رقم الهاتف', Icons.phone),
                    const SizedBox(height: 10),
                    _dialogTextField(passwordCtrl,
                        'كلمة مرور جديدة (اتركها فارغة)', Icons.lock,
                        obscure: true),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<AgentType>(
                      value: selectedType,
                      decoration: InputDecoration(
                        labelText: 'نوع الوكيل',
                        prefixIcon: const Icon(Icons.category, size: 18),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      items: AgentType.values
                          .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(t.displayName,
                                    style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedType = v ?? agent.type),
                    ),
                    const SizedBox(height: 10),
                    _dialogTextField(
                        emailCtrl, 'البريد الإلكتروني', Icons.email),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                            child: _dialogTextField(
                                cityCtrl, 'المدينة', Icons.location_city)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _dialogTextField(
                                areaCtrl, 'المنطقة', Icons.map)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _dialogTextField(pageIdCtrl, 'معرف الصفحة', Icons.badge),
                    const SizedBox(height: 10),
                    _dialogTextField(notesCtrl, 'ملاحظات', Icons.note,
                        maxLines: 2),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    final updated = await _agentService.update(
                      agent.id,
                      name: nameCtrl.text,
                      type: selectedType,
                      phoneNumber: phoneCtrl.text,
                      newPassword:
                          passwordCtrl.text.isEmpty ? null : passwordCtrl.text,
                      email: emailCtrl.text.isEmpty ? null : emailCtrl.text,
                      city: cityCtrl.text.isEmpty ? null : cityCtrl.text,
                      area: areaCtrl.text.isEmpty ? null : areaCtrl.text,
                      pageId: pageIdCtrl.text.isEmpty ? null : pageIdCtrl.text,
                      notes: notesCtrl.text,
                    );
                    await _loadData();
                    if (updated != null && mounted) {
                      setState(() => _selectedAgent = updated);
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('تم تعديل الوكيل بنجاح ✓'),
                            backgroundColor: Colors.green),
                      );
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
                  backgroundColor: AccountingTheme.neonBlue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTransactionDialog(AgentModel agent, {required bool isCharge}) {
    final amountCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    TransactionCategory selectedCategory = isCharge
        ? TransactionCategory.newSubscription
        : TransactionCategory.cashPayment;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                Icon(
                  isCharge ? Icons.add_circle_outline : Icons.payments_outlined,
                  size: 20,
                  color: isCharge
                      ? AccountingTheme.neonOrange
                      : AccountingTheme.neonGreen,
                ),
                const SizedBox(width: 8),
                Text(isCharge ? 'إضافة أجور' : 'تسجيل تسديد',
                    style: const TextStyle(fontSize: 16)),
                const Spacer(),
                Text(agent.name,
                    style: const TextStyle(
                        fontSize: 12, color: AccountingTheme.textMuted)),
              ],
            ),
            content: SizedBox(
              width: min(360, MediaQuery.of(context).size.width * 0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dialogTextField(
                      amountCtrl, 'المبلغ (د.ع) *', Icons.attach_money,
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<TransactionCategory>(
                    value: selectedCategory,
                    decoration: InputDecoration(
                      labelText: 'الفئة',
                      prefixIcon: const Icon(Icons.category, size: 18),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: TransactionCategory.values
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c.displayName,
                                  style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(
                        () => selectedCategory = v ?? selectedCategory),
                  ),
                  const SizedBox(height: 10),
                  _dialogTextField(descriptionCtrl, 'الوصف', Icons.description),
                  const SizedBox(height: 10),
                  _dialogTextField(refCtrl, 'رقم المرجع', Icons.tag),
                  const SizedBox(height: 10),
                  _dialogTextField(notesCtrl, 'ملاحظات', Icons.note),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text);
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('أدخل مبلغ صحيح')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    if (isCharge) {
                      await _agentService.addCharge(
                        agent.id,
                        amount: amount,
                        category: selectedCategory,
                        description: descriptionCtrl.text.isEmpty
                            ? null
                            : descriptionCtrl.text,
                        referenceNumber:
                            refCtrl.text.isEmpty ? null : refCtrl.text,
                        notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                      );
                    } else {
                      await _agentService.addPayment(
                        agent.id,
                        amount: amount,
                        category: selectedCategory,
                        description: descriptionCtrl.text.isEmpty
                            ? null
                            : descriptionCtrl.text,
                        referenceNumber:
                            refCtrl.text.isEmpty ? null : refCtrl.text,
                        notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                      );
                    }
                    await _loadData();
                    // تحديث الوكيل المحدد
                    final updated = await _agentService.getById(agent.id);
                    if (updated != null && mounted) {
                      setState(() => _selectedAgent = updated);
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isCharge
                              ? 'تم إضافة الأجور ✓'
                              : 'تم تسجيل التسديد ✓'),
                          backgroundColor: Colors.green,
                        ),
                      );
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
                  backgroundColor: isCharge
                      ? AccountingTheme.neonOrange
                      : AccountingTheme.neonGreen,
                  foregroundColor: Colors.white,
                ),
                child: Text(isCharge ? 'إضافة أجور' : 'تسجيل تسديد'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== تعديل/حذف المعاملات ====================

  void _showEditTransactionDialog(AgentTransactionModel tx) {
    final amountCtrl =
        TextEditingController(text: tx.amount.toStringAsFixed(0));
    final descriptionCtrl = TextEditingController(text: tx.description);
    final notesCtrl = TextEditingController(text: tx.notes ?? '');
    TransactionCategory selectedCategory = tx.category;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.edit,
                    size: 20, color: AccountingTheme.neonBlue),
                const SizedBox(width: 8),
                const Text('تعديل المعاملة', style: TextStyle(fontSize: 16)),
                const Spacer(),
                Text('#${tx.id}',
                    style: const TextStyle(
                        fontSize: 11, color: AccountingTheme.textMuted)),
              ],
            ),
            content: SizedBox(
              width: min(360, MediaQuery.of(context).size.width * 0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // النوع (للقراءة فقط)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (tx.isCharge
                              ? AccountingTheme.neonOrange
                              : AccountingTheme.neonGreen)
                          .withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                            tx.isCharge
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 16,
                            color: tx.isCharge
                                ? AccountingTheme.neonOrange
                                : AccountingTheme.neonGreen),
                        const SizedBox(width: 6),
                        Text(tx.type.displayName,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: tx.isCharge
                                    ? AccountingTheme.neonOrange
                                    : AccountingTheme.neonGreen)),
                        const Spacer(),
                        Text(DateFormat('yyyy/MM/dd').format(tx.createdAt),
                            style: const TextStyle(
                                fontSize: 11,
                                color: AccountingTheme.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _dialogTextField(
                      amountCtrl, 'المبلغ (د.ع)', Icons.attach_money,
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<TransactionCategory>(
                    value: selectedCategory,
                    decoration: InputDecoration(
                      labelText: 'الفئة',
                      prefixIcon: const Icon(Icons.category, size: 18),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: TransactionCategory.values
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c.displayName,
                                  style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(
                        () => selectedCategory = v ?? selectedCategory),
                  ),
                  const SizedBox(height: 10),
                  _dialogTextField(descriptionCtrl, 'الوصف', Icons.description),
                  const SizedBox(height: 10),
                  _dialogTextField(notesCtrl, 'ملاحظات', Icons.note),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text);
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('أدخل مبلغ صحيح')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    await _agentService.updateTransaction(
                      tx.id,
                      amount: amount,
                      category: selectedCategory,
                      description: descriptionCtrl.text.isEmpty
                          ? null
                          : descriptionCtrl.text,
                      notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                    );
                    await _loadData();
                    if (_selectedAgent != null) {
                      final updated =
                          await _agentService.getById(_selectedAgent!.id);
                      if (updated != null && mounted) {
                        setState(() => _selectedAgent = updated);
                      }
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('تم تعديل المعاملة بنجاح ✓'),
                            backgroundColor: Colors.green),
                      );
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
                  backgroundColor: AccountingTheme.neonBlue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('حفظ التعديل'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteTransactionDialog(AgentTransactionModel tx) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 22, color: Colors.red),
              SizedBox(width: 8),
              Text('حذف المعاملة', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: min(360, MediaQuery.of(context).size.width * 0.85),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('هل أنت متأكد من حذف هذه المعاملة؟',
                    style: TextStyle(fontSize: 14)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(tx.type.displayName,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: tx.isCharge
                                      ? AccountingTheme.neonOrange
                                      : AccountingTheme.neonGreen)),
                          const SizedBox(width: 8),
                          Text(tx.category.displayName,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AccountingTheme.textMuted)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${_formatCurrency(tx.amount)} د.ع',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      if (tx.description.isNotEmpty)
                        Text(tx.description,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AccountingTheme.textSecondary)),
                      Text(
                          DateFormat('yyyy/MM/dd - HH:mm').format(tx.createdAt),
                          style: const TextStyle(
                              fontSize: 10, color: AccountingTheme.textMuted)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text('⚠️ سيتم إعادة حساب رصيد الوكيل تلقائياً',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _agentService.deleteTransaction(tx.id);
                  await _loadData();
                  if (_selectedAgent != null) {
                    final updated =
                        await _agentService.getById(_selectedAgent!.id);
                    if (updated != null && mounted) {
                      setState(() => _selectedAgent = updated);
                    }
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('تم حذف المعاملة بنجاح ✓'),
                          backgroundColor: Colors.green),
                    );
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
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogTextField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool obscure = false,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textDirection: TextDirection.rtl,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        prefixIcon: Icon(icon, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  // ==================== إجراءات ====================

  void _handleAgentAction(String action, AgentModel agent) async {
    switch (action) {
      case 'charge':
        _showTransactionDialog(agent, isCharge: true);
        break;
      case 'payment':
        _showTransactionDialog(agent, isCharge: false);
        break;
      case 'edit':
        _showEditAgentDialog(agent);
        break;
      case 'suspend':
        await _updateAgentStatus(agent, AgentStatus.suspended);
        break;
      case 'activate':
        await _updateAgentStatus(agent, AgentStatus.active);
        break;
      case 'delete':
        _confirmDelete(agent);
        break;
    }
  }

  Future<void> _updateAgentStatus(AgentModel agent, AgentStatus status) async {
    try {
      await _agentService.update(agent.id, status: status);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تم تغيير الحالة إلى ${status.displayName} ✓'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _confirmDelete(AgentModel agent) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف', style: TextStyle(fontSize: 16)),
          content: Text(
              'هل تريد حذف الوكيل "${agent.name}"؟\nهذا الإجراء لا يمكن التراجع عنه.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _agentService.delete(agent.id);
                  if (mounted) {
                    setState(() => _selectedAgent = null);
                  }
                  await _loadData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('تم حذف الوكيل ✓'),
                          backgroundColor: Colors.green),
                    );
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
                  backgroundColor: AccountingTheme.danger,
                  foregroundColor: Colors.white),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== مساعدات ====================

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline,
              size: 48, color: AccountingTheme.danger),
          const SizedBox(height: 12),
          Text(_errorMessage ?? 'خطأ غير معروف',
              style: const TextStyle(color: AccountingTheme.danger)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(AgentStatus status) {
    switch (status) {
      case AgentStatus.active:
        return AccountingTheme.neonGreen;
      case AgentStatus.suspended:
        return AccountingTheme.warning;
      case AgentStatus.banned:
        return AccountingTheme.danger;
      case AgentStatus.inactive:
        return AccountingTheme.textMuted;
    }
  }

  String _formatCurrency(double amount) {
    if (amount == 0) return '0';
    return amount.round().toString();
  }
}

/// عنصر القائمة الجانبية - ستايل المحاسبة
class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
      child: Tooltip(
        message: label,
        preferBelow: false,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            hoverColor: color.withOpacity(0.08),
            splashColor: color.withOpacity(0.15),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color:
                    isSelected ? color.withOpacity(0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withOpacity(0.2)
                          : color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      size: 19,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? color : AccountingTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
