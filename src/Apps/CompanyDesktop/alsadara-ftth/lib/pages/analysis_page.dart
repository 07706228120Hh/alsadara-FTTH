/// اسم الصفحة: التحليلات
/// وصف الصفحة: صفحة التحليلات والتقارير المفصلة للبيانات
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'charts_page.dart';
import '../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../services/zone_statistics_api_service.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});
  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  bool isLoading = true;
  String? errorMessage;

  int totalZones = 0;
  int totalUsers = 0;
  int totalActiveUsers = 0;
  int totalInactiveUsers = 0;

  int minFats = 0;
  int maxFats = 0;
  double avgFats = 0.0;
  int totalFats = 0;

  int minUsers = 0;
  int maxUsers = 0;
  double avgUsers = 0.0;

  @override
  void initState() {
    super.initState();
    fetchAnalysisData();
  }

  // Format numbers with thousands separators and optional decimals
  String _formatNumber(num number, {int decimals = 0}) {
    return number.round().toString();
  }

  Widget _animatedNumber(num target,
      {int decimals = 0,
      TextStyle? style,
      Duration duration = const Duration(milliseconds: 900)}) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final display = _formatNumber(decimals == 0 ? value.round() : value,
            decimals: decimals);
        return Text(
          display,
          style: style,
        );
      },
    );
  }

  Future<void> fetchAnalysisData() async {
    try {
      final data = await ZoneStatisticsApiService.instance.getSummary();

      if (data.isNotEmpty) {
        setState(() {
          totalZones = (data['totalZones'] ?? data['TotalZones'] ?? 0) as int;
          totalUsers = (data['totalUsers'] ?? data['TotalUsers'] ?? 0) as int;
          totalActiveUsers =
              (data['totalActive'] ?? data['TotalActive'] ?? 0) as int;
          totalInactiveUsers =
              (data['totalInactive'] ?? data['TotalInactive'] ?? 0) as int;
          totalFats = (data['totalFats'] ?? data['TotalFats'] ?? 0) as int;

          avgFats = (data['avgFatsPerZone'] ?? data['AvgFatsPerZone'] ?? 0.0)
              .toDouble();
          minFats = (data['minFats'] ?? data['MinFats'] ?? 0) as int;
          maxFats = (data['maxFats'] ?? data['MaxFats'] ?? 0) as int;

          avgUsers = (data['avgUsersPerZone'] ?? data['AvgUsersPerZone'] ?? 0.0)
              .toDouble();
          minUsers = (data['minUsers'] ?? data['MinUsers'] ?? 0) as int;
          maxUsers = (data['maxUsers'] ?? data['MaxUsers'] ?? 0) as int;

          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'لم يتم العثور على بيانات.';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ';
        isLoading = false;
      });
    }
  }

  Widget _buildEnhancedSection(
      String title, IconData titleIcon, List<Widget> items, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color,
                color.withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      titleIcon,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ...items,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required IconData icon,
    required String title,
    required num value,
    int decimals = 0,
    required Color color,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.md),
        boxShadow: SdDepth.raised(),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(SdRadius.sm),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SdText.caption.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 6),
                _animatedNumber(
                  value,
                  decimals: decimals,
                  style: SdText.numberSm.copyWith(
                    fontSize: 20,
                    color: color,
                  ),
                  duration: const Duration(milliseconds: 700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressTile({
    required String title,
    required double ratio,
    required Color color,
    required IconData icon,
  }) {
    final percent =
        (ratio.isNaN || ratio.isInfinite) ? 0.0 : (ratio.clamp(0.0, 1.0));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.md),
        boxShadow: SdDepth.raised(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(SdRadius.sm),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: SdText.label,
                ),
              ),
              Text(
                '${(percent * 100).toStringAsFixed(1)}%',
                style: SdText.label.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 10,
              color: color,
              backgroundColor: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: SdAppBar(
        title: 'تحليل المعلومات',
        actions: [
          SdAppBarAction(
            icon: Icons.refresh,
            label: 'تحديث',
            onPressed: () async {
              setState(() => isLoading = true);
              await fetchAnalysisData();
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(SdSpace.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: SdColors.primary),
                    SizedBox(height: 20),
                    Text('جاري تحليل البيانات...', style: SdText.titleSm),
                  ],
                ),
              ),
            )
          : errorMessage != null
              ? SdEmptyState(
                  icon: Icons.error_outline,
                  status: SdStatus.danger,
                  title: 'حدث خطأ',
                  message: errorMessage!,
                  action: SdButton(
                    label: 'إعادة المحاولة',
                    icon: Icons.refresh,
                    kind: SdButtonKind.danger,
                    onPressed: () async {
                      setState(() => isLoading = true);
                      await fetchAnalysisData();
                    },
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async => fetchAnalysisData(),
                  child: ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: [
                          // ملخص سريع
                          Container(
                            padding: const EdgeInsets.all(18),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  SdColors.primaryLight,
                                  SdColors.primaryMid,
                                  SdColors.primary,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(SdRadius.lg),
                              boxShadow: SdDepth.raised(
                                  edge: SdColors.primaryEdge,
                                  glow: const Color(0x401A237E)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.white.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.insights,
                                          color: Colors.white, size: 26),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'ملخص سريع',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    // شبكة مرنة تتكيّف مع عرض الجهاز لمنع تداخل الأيقونات والنصوص
                                    final width = constraints.maxWidth;
                                    // تحديد عدد الأعمدة بشكل ديناميكي
                                    int cols;
                                    if (width >= 1000) {
                                      cols = 4;
                                    } else if (width >= 750) {
                                      cols = 3;
                                    } else if (width >= 480) {
                                      cols = 2;
                                    } else {
                                      cols =
                                          1; // شاشة هاتف صغيرة: بطاقة واحدة في الصف
                                    }

                                    const spacing = 12.0;
                                    final itemWidth =
                                        (width - spacing * (cols - 1)) / cols;

                                    final items = <Widget>[
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.location_on,
                                          title: 'الزونات',
                                          value: totalZones,
                                          color: SdColors.info,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.people,
                                          title: 'المستخدمون',
                                          value: totalUsers,
                                          color: SdColors.success,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.check_circle_outline,
                                          title: 'فعّالون',
                                          value: totalActiveUsers,
                                          color: SdColors.warning,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.highlight_off,
                                          title: 'غير مفعلين',
                                          value: totalInactiveUsers,
                                          color: SdColors.danger,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.functions,
                                          title: 'مجموع FATS',
                                          value: totalFats,
                                          color: SdColors.accent,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.timeline,
                                          title: 'متوسط FATS',
                                          value: avgFats,
                                          decimals: 2,
                                          color: SdColors.accent,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.trending_up,
                                          title: 'أكبر FATS',
                                          value: maxFats,
                                          color: SdColors.success,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.trending_down,
                                          title: 'أصغر FATS',
                                          value: minFats,
                                          color: SdColors.danger,
                                        ),
                                      ),
                                      // إحصائيات المستخدمين في الملخص السريع
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.trending_up,
                                          title: 'أكبر مستخدمين',
                                          value: maxUsers,
                                          color: SdColors.success,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.trending_down,
                                          title: 'أصغر مستخدمين',
                                          value: minUsers,
                                          color: SdColors.danger,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.timeline,
                                          title: 'متوسط المستخدمين',
                                          value: avgUsers,
                                          decimals: 2,
                                          color: SdColors.primary,
                                        ),
                                      ),
                                    ];

                                    return Wrap(
                                      spacing: spacing,
                                      runSpacing: spacing,
                                      children: items,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),

                          // نسبة التفعيل
                          _buildEnhancedSection(
                            'نسبة التفعيل',
                            Icons.percent,
                            [
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final isWide = constraints.maxWidth > 640;
                                  return GridView(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: isWide ? 2 : 1,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: isWide ? 3.6 : 3.0,
                                    ),
                                    children: [
                                      _buildProgressTile(
                                        title: 'فعّالون من إجمالي المستخدمين',
                                        ratio: totalUsers == 0
                                            ? 0
                                            : totalActiveUsers / totalUsers,
                                        color: SdColors.success,
                                        icon: Icons.verified_user,
                                      ),
                                      _buildProgressTile(
                                        title:
                                            'غير مفعلين من إجمالي المستخدمين',
                                        ratio: totalUsers == 0
                                            ? 0
                                            : totalInactiveUsers / totalUsers,
                                        color: SdColors.danger,
                                        icon: Icons.block,
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                            SdGroup.platform.tone.base,
                          ),

                          // عرض المخططات مع تصميم محسن (منقول لأسفل الصفحة)
                          Container(
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  SdColors.primaryMid,
                                  SdColors.primary,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(SdRadius.lg),
                              boxShadow: SdDepth.raised(
                                  edge: SdColors.primaryEdge,
                                  glow: const Color(0x401A237E)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.white.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.show_chart,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    const Expanded(
                                      child: Text(
                                        'عرض المخططات التفاعلية',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const ChartsPage(),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: SdColors.primary,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                      elevation: 5,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.bar_chart,
                                          size: 24,
                                          color: SdColors.primary,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'افتح المخططات',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: SdColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}
