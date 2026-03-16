import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/agent_api_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

/// صفحة أرباح الباقات - Plan Profits Page
/// تحديد الربح الصافي لكل باقة إنترنت
class PlanProfitsPage extends StatefulWidget {
  final String? companyId;

  const PlanProfitsPage({super.key, this.companyId});

  @override
  State<PlanProfitsPage> createState() => _PlanProfitsPageState();
}

class _PlanProfitsPageState extends State<PlanProfitsPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _plans = [];
  final Map<String, TextEditingController> _profitControllers = {};

  String get _companyId =>
      widget.companyId ?? VpsAuthService.instance.currentCompanyId ?? '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
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
      _plans = await AgentApiService.instance.getPlansWithProfit(_companyId);

      for (final plan in _plans) {
        final planId = plan['Id']?.toString() ?? '';
        final profit = (plan['ProfitAmount'] ?? 0).toDouble();
        _profitControllers[planId]?.dispose();
        _profitControllers[planId] = TextEditingController(
            text: profit > 0 ? profit.toStringAsFixed(0) : '');
      }
    } catch (e) {
      _errorMessage = 'خطأ';
    }
    if (mounted) setState(() => _isLoading = false);
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
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        appBar: AppBar(
          backgroundColor: AccountingTheme.bgSidebar,
          iconTheme: const IconThemeData(color: Colors.white),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            '💰 أرباح الباقات',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: isMob ? 16 : context.accR.headingSmall,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.save_rounded,
                  color: AccountingTheme.neonGreen),
              onPressed: _saveAllProfits,
              tooltip: 'حفظ الكل',
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadData,
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildError()
                : isMob
                    ? _buildMobileBody()
                    : _buildDesktopBody(),
      ),
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
    if (_plans.isEmpty) {
      return Center(
        child: Text(
          'لا توجد باقات',
          style:
              GoogleFonts.cairo(fontSize: 16, color: AccountingTheme.textMuted),
        ),
      );
    }

    return Column(
      children: [
        // وصف
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: AccountingTheme.neonGreen.withOpacity(0.05),
          child: Text(
            'الربح = المبلغ الصافي بعد خصم التكاليف — العمولة تُحسب كنسبة من الربح',
            style: GoogleFonts.cairo(
              fontSize: 11,
              color: AccountingTheme.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        // قائمة الباقات
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
                    // اسم الباقة  + السرعة
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
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AccountingTheme.textPrimary,
                            ),
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
                              color: AccountingTheme.neonPurple,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // السعر + حقل الربح
                    Row(
                      children: [
                        // السعر الشهري
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
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AccountingTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // حقل الربح
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
                              color: AccountingTheme.neonGreen,
                            ),
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
                        // زر حفظ
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
    return Padding(
      padding: EdgeInsets.all(context.accR.spaceXXL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان + وصف
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
          SizedBox(height: context.accR.spaceXL),

          // جدول الباقات
          Expanded(
            child: _plans.isEmpty
                ? Center(
                    child: Text(
                      'لا توجد باقات',
                      style: GoogleFonts.cairo(
                          fontSize: context.accR.headingSmall,
                          color: AccountingTheme.textMuted),
                    ),
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
                                        suffixStyle: GoogleFonts.cairo(
                                            fontSize: context.accR.small),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
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
                                  ),
                                ),
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

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = (value is num)
        ? value.toDouble()
        : (double.tryParse(value.toString()) ?? 0);
    return n.round().toString();
  }
}
