/// اسم الصفحة: التحليلات
/// وصف الصفحة: صفحة التحليلات والتقارير المفصلة للبيانات
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'charts_page.dart';
import '../widgets/responsive_body.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});
  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  final String apiKey = 'AIzaSyDdwZK0D8uRoPSKS0axA5dQjwMCQJtF1BU';
  final String spreadsheetId = '1MGY8UhtHaUiRaUKbohEi3a74jgEh7NeOuTEHBQ83KZc';
  final String range = 'Sheet1!A2:E';

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
    if (decimals > 0) {
      final s = number.toStringAsFixed(decimals);
      final parts = s.split('.');
      final intPart = parts[0];
      final decPart = parts[1];
      final formattedInt = intPart.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
      return '$formattedInt.$decPart';
    } else {
      final intPart = number.round().toString();
      final formattedInt = intPart.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
      return formattedInt;
    }
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
    final url =
        'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/$range?key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['values'] != null) {
          final rows = data['values'] as List;

          int fatsSum = 0;
          int usersSum = 0;
          int activeUsersSum = 0;
          int inactiveUsersSum = 0;

          List<int> fatsList = [];
          List<int> usersList = [];

          for (var row in rows) {
            if (row.length > 1) {
              int fats = int.tryParse(row[1]) ?? 0;
              fatsSum += fats;
              fatsList.add(fats);
            }
            if (row.length > 2) {
              int users = int.tryParse(row[2]) ?? 0;
              usersSum += users;
              usersList.add(users);
            }
            if (row.length > 3) {
              int inactiveUsers = int.tryParse(row[3]) ?? 0;
              inactiveUsersSum += inactiveUsers;
            }
            if (row.length > 4) {
              int activeUsers = int.tryParse(row[4]) ?? 0;
              activeUsersSum += activeUsers;
            }
          }

          setState(() {
            totalZones = rows.length;
            totalUsers = usersSum;
            totalActiveUsers = activeUsersSum;
            totalInactiveUsers = inactiveUsersSum;
            totalFats = fatsSum;

            if (fatsList.isNotEmpty) {
              minFats = fatsList.reduce((a, b) => a < b ? a : b);
              maxFats = fatsList.reduce((a, b) => a > b ? a : b);
              avgFats = fatsSum / fatsList.length;
            }

            if (usersList.isNotEmpty) {
              minUsers = usersList.reduce((a, b) => a < b ? a : b);
              maxUsers = usersList.reduce((a, b) => a > b ? a : b);
              avgUsers = usersSum / usersList.length;
            }

            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage = 'لم يتم العثور على بيانات.';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'خطأ في جلب البيانات: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ: $e';
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
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
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _animatedNumber(
                  value,
                  decimals: decimals,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
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
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${(percent * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
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
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.purple[800]!,
                Colors.purple[600]!,
                Colors.purple[400]!,
              ],
            ),
          ),
        ),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
              size: 20,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.analytics,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'تحليل المعلومات',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: () async {
              setState(() => isLoading = true);
              await fetchAnalysisData();
            },
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.refresh, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.purple[50]!,
              Colors.white,
            ],
          ),
        ),
        child: ResponsiveBody(
          child: isLoading
              ? Center(
                  child: Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.purple.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.purple[600]!),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'جاري تحليل البيانات...',
                          style: TextStyle(
                            color: Colors.purple[600],
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : errorMessage != null
                  ? Center(
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red[600],
                              size: 50,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'حدث خطأ',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[600],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              errorMessage!,
                              style: TextStyle(
                                color: Colors.red[400],
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () async {
                                setState(() => isLoading = true);
                                await fetchAnalysisData();
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('إعادة المحاولة'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red[600],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            )
                          ],
                        ),
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
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.purple[600]!,
                                  Colors.purple[700]!,
                                  Colors.purple[800]!,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.purple.withValues(alpha: 0.25),
                                  blurRadius: 18,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
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
                                          color: Colors.blue[700]!,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.people,
                                          title: 'المستخدمون',
                                          value: totalUsers,
                                          color: Colors.green[700]!,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.check_circle_outline,
                                          title: 'فعّالون',
                                          value: totalActiveUsers,
                                          color: Colors.orange[700]!,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.highlight_off,
                                          title: 'غير مفعلين',
                                          value: totalInactiveUsers,
                                          color: Colors.red[700]!,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.functions,
                                          title: 'مجموع FATS',
                                          value: totalFats,
                                          color: Colors.teal[700]!,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.timeline,
                                          title: 'متوسط FATS',
                                          value: avgFats,
                                          decimals: 2,
                                          color: Colors.cyan[700]!,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.trending_up,
                                          title: 'أكبر FATS',
                                          value: maxFats,
                                          color: Colors.green[700]!,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.trending_down,
                                          title: 'أصغر FATS',
                                          value: minFats,
                                          color: Colors.red[700]!,
                                        ),
                                      ),
                                      // إحصائيات المستخدمين في الملخص السريع
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.trending_up,
                                          title: 'أكبر مستخدمين',
                                          value: maxUsers,
                                          color: Colors.green[800]!,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.trending_down,
                                          title: 'أصغر مستخدمين',
                                          value: minUsers,
                                          color: Colors.red[800]!,
                                        ),
                                      ),
                                      SizedBox(
                                        width: itemWidth,
                                        child: _buildKpiCard(
                                          icon: Icons.timeline,
                                          title: 'متوسط المستخدمين',
                                          value: avgUsers,
                                          decimals: 2,
                                          color: Colors.indigo[700]!,
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
                                        color: Colors.green[600]!,
                                        icon: Icons.verified_user,
                                      ),
                                      _buildProgressTile(
                                        title:
                                            'غير مفعلين من إجمالي المستخدمين',
                                        ratio: totalUsers == 0
                                            ? 0
                                            : totalInactiveUsers / totalUsers,
                                        color: Colors.red[600]!,
                                        icon: Icons.block,
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                            Colors.deepPurple[400]!,
                          ),

                          // عرض المخططات مع تصميم محسن (منقول لأسفل الصفحة)
                          Container(
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.purple[600]!,
                                  Colors.purple[800]!,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.purple.withValues(alpha: 0.3),
                                  blurRadius: 15,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.2),
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
                                      foregroundColor: Colors.purple[600],
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
                                          color: Colors.purple[600],
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'افتح المخططات',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.purple[600],
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
        ),
      ),
    );
  }
}
