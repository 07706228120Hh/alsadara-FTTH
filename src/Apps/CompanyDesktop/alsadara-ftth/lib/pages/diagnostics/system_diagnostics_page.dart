import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/diagnostic_test.dart';
import 'models/diagnostic_result.dart';
import 'services/diagnostic_service.dart';
import 'widgets/diagnostic_category_card.dart';
import 'widgets/diagnostic_result_item.dart';

/// صفحة تشخيص النظام الشاملة
class SystemDiagnosticsPage extends StatefulWidget {
  const SystemDiagnosticsPage({super.key});

  @override
  State<SystemDiagnosticsPage> createState() => _SystemDiagnosticsPageState();
}

class _SystemDiagnosticsPageState extends State<SystemDiagnosticsPage>
    with SingleTickerProviderStateMixin {
  final DiagnosticService _diagnosticService = DiagnosticService();
  late TabController _tabController;

  bool _isRunning = false;
  int _currentTest = 0;
  int _totalTests = 0;
  String _currentCategory = '';

  DiagnosticReport? _lastReport;
  final List<DiagnosticTestResult> _results = [];
  final Map<String, CategoryDiagnosticSummary> _categorySummaries = {};
  final Set<String> _expandedResults = {};

  String _selectedCategoryFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeCategorySummaries();
  }

  void _initializeCategorySummaries() {
    for (var category in DiagnosticCategories.all) {
      final testsInCategory = _diagnosticService
          .getAllTests()
          .where((t) => t.category == category.id)
          .length;

      _categorySummaries[category.id] = CategoryDiagnosticSummary(
        category: category,
        total: testsInCategory,
        passed: 0,
        failed: 0,
        warnings: 0,
        totalDuration: Duration.zero,
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _runAllTests() async {
    setState(() {
      _isRunning = true;
      _results.clear();
      _currentTest = 0;
      _totalTests = _diagnosticService.getAllTests().length;
      _initializeCategorySummaries();
    });

    final report = await _diagnosticService.runAllTests(
      onTestComplete: (result) {
        setState(() {
          _results.add(result);
          _updateCategorySummary(result);
        });
      },
      onProgress: (current, total) {
        setState(() {
          _currentTest = current;
          _totalTests = total;
        });
      },
    );

    setState(() {
      _isRunning = false;
      _lastReport = report;
    });

    _showCompletionDialog(report);
  }

  Future<void> _runCategoryTests(String categoryId) async {
    final categoryTests = _diagnosticService
        .getAllTests()
        .where((t) => t.category == categoryId)
        .length;

    setState(() {
      _isRunning = true;
      _currentCategory = categoryId;
      _currentTest = 0;
      _totalTests = categoryTests;
    });

    await _diagnosticService.runCategoryTests(
      categoryId,
      onTestComplete: (result) {
        setState(() {
          _results.removeWhere((r) {
            final test = _diagnosticService
                .getAllTests()
                .firstWhere((t) => t.id == r.testId);
            return test.category == categoryId;
          });
          _results.add(result);
          _updateCategorySummary(result);
        });
      },
      onProgress: (current, total) {
        setState(() {
          _currentTest = current;
          _totalTests = total;
        });
      },
    );

    // إنشاء تقرير شامل بناءً على جميع النتائج المحفوظة
    final updatedReport = _generateUpdatedReport();

    setState(() {
      _isRunning = false;
      _currentCategory = '';
      _lastReport = updatedReport;
    });
  }

  /// إنشاء تقرير محدث بناءً على جميع النتائج المحفوظة
  DiagnosticReport _generateUpdatedReport() {
    final categorySummary = <String, int>{};
    for (var result in _results) {
      final test = _diagnosticService
          .getAllTests()
          .firstWhere((t) => t.id == result.testId);
      categorySummary[test.category] =
          (categorySummary[test.category] ?? 0) + 1;
    }

    final totalDuration = _results.fold<Duration>(
      Duration.zero,
      (sum, r) => sum + r.duration,
    );

    return DiagnosticReport(
      reportId: 'RPT-${DateTime.now().millisecondsSinceEpoch}',
      generatedAt: DateTime.now(),
      results: List.from(_results),
      categorySummary: categorySummary,
      totalTests: _results.length,
      passedTests: _results.where((r) => r.success).length,
      failedTests: _results.where((r) => !r.success).length,
      totalDuration: totalDuration,
    );
  }

  void _updateCategorySummary(DiagnosticTestResult result) {
    final test = _diagnosticService
        .getAllTests()
        .firstWhere((t) => t.id == result.testId);
    final categoryId = test.category;

    final currentSummary = _categorySummaries[categoryId]!;
    final categoryResults = _results.where((r) {
      final t =
          _diagnosticService.getAllTests().firstWhere((t) => t.id == r.testId);
      return t.category == categoryId;
    }).toList();

    _categorySummaries[categoryId] = CategoryDiagnosticSummary(
      category: currentSummary.category,
      total: currentSummary.total,
      passed: categoryResults.where((r) => r.success).length,
      failed: categoryResults.where((r) => !r.success).length,
      warnings: 0,
      totalDuration: categoryResults.fold(
        Duration.zero,
        (sum, r) => sum + r.duration,
      ),
    );
  }

  void _showCompletionDialog(DiagnosticReport report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              report.failedTests == 0 ? Icons.check_circle : Icons.warning,
              color: report.failedTests == 0 ? Colors.green : Colors.orange,
              size: 28,
            ),
            const SizedBox(width: 12),
            const Text('اكتمل الفحص'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'تم تنفيذ ${report.totalTests} اختبار',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildResultChip(
                  'نجح',
                  report.passedTests.toString(),
                  Colors.green,
                ),
                _buildResultChip(
                  'فشل',
                  report.failedTests.toString(),
                  Colors.red,
                ),
                _buildResultChip(
                  'النسبة',
                  '${report.successRate.toStringAsFixed(0)}%',
                  report.successRate >= 80 ? Colors.green : Colors.orange,
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _copyReportToClipboard(report);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('نسخ التقرير'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }

  void _copyReportToClipboard(DiagnosticReport report) {
    Clipboard.setData(ClipboardData(text: report.toFullReport()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ التقرير الكامل إلى الحافظة'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _exportReportAsJson() {
    if (_lastReport == null) return;

    final jsonData = {
      'reportId': _lastReport!.reportId,
      'generatedAt': _lastReport!.generatedAt.toIso8601String(),
      'summary': {
        'totalTests': _lastReport!.totalTests,
        'passedTests': _lastReport!.passedTests,
        'failedTests': _lastReport!.failedTests,
        'successRate': _lastReport!.successRate,
        'totalDuration': _lastReport!.totalDuration.inMilliseconds,
      },
      'results': _lastReport!.results.map((r) => r.toJson()).toList(),
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
    Clipboard.setData(ClipboardData(text: jsonString));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ التقرير بصيغة JSON إلى الحافظة'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  List<DiagnosticTestResult> get _filteredResults {
    if (_selectedCategoryFilter == 'all') {
      return _results;
    }
    return _results.where((r) {
      final test =
          _diagnosticService.getAllTests().firstWhere((t) => t.id == r.testId);
      return test.category == _selectedCategoryFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Header
          _buildHeader(),

          // Progress indicator when running
          if (_isRunning) _buildProgressSection(),

          // Tab bar
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Theme.of(context).primaryColor,
              tabs: const [
                Tab(icon: Icon(Icons.dashboard), text: 'نظرة عامة'),
                Tab(icon: Icon(Icons.category), text: 'الفئات'),
                Tab(icon: Icon(Icons.list_alt), text: 'النتائج التفصيلية'),
              ],
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildCategoriesTab(),
                _buildResultsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).primaryColor,
            Theme.of(context).primaryColor.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🔧 مركز تشخيص النظام',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'فحص شامل لجميع مكونات النظام',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isRunning ? null : _runAllTests,
                  icon: _isRunning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.play_arrow),
                  label:
                      Text(_isRunning ? 'جاري الفحص...' : 'بدء الفحص الشامل'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Theme.of(context).primaryColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    final progress = _totalTests > 0 ? _currentTest / _totalTests : 0.0;
    final categoryName = _currentCategory.isNotEmpty
        ? DiagnosticCategories.all
            .firstWhere(
              (c) => c.id == _currentCategory,
              orElse: () => DiagnosticCategories.connection,
            )
            .nameAr
        : 'جميع الاختبارات';

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue.withOpacity(0.1),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'جاري تنفيذ: $categoryName',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                '$_currentTest / $_totalTests',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey[300],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    if (_lastReport == null && _results.isEmpty) {
      return _buildEmptyState();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (_lastReport != null)
            DiagnosticSummaryCard(
              totalTests: _lastReport!.totalTests,
              passedTests: _lastReport!.passedTests,
              failedTests: _lastReport!.failedTests,
              totalDuration: _lastReport!.totalDuration,
              onCopyReport: () => _copyReportToClipboard(_lastReport!),
              onExportReport: _exportReportAsJson,
            ),

          const SizedBox(height: 24),

          // Quick stats grid
          _buildQuickStatsGrid(),

          const SizedBox(height: 24),

          // Failed tests section
          if (_results.any((r) => !r.success)) ...[
            _buildSectionHeader(
              '⚠️ الاختبارات الفاشلة',
              'تحتاج إلى اهتمام',
              Colors.red,
            ),
            const SizedBox(height: 16),
            ...(_results.where((r) => !r.success).take(5).map((result) {
              final test = _diagnosticService
                  .getAllTests()
                  .firstWhere((t) => t.id == result.testId);
              return DiagnosticResultItem(
                result: result,
                testName: test.nameAr,
                isExpanded: _expandedResults.contains(result.testId),
                onTap: () {
                  setState(() {
                    if (_expandedResults.contains(result.testId)) {
                      _expandedResults.remove(result.testId);
                    } else {
                      _expandedResults.add(result.testId);
                    }
                  });
                },
              );
            })),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.science_outlined,
            size: 100,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 24),
          Text(
            'لم يتم تشغيل أي اختبارات بعد',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'اضغط على "بدء الفحص الشامل" لبدء تشخيص النظام',
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _runAllTests,
            icon: const Icon(Icons.play_arrow),
            label: const Text('بدء الفحص الشامل'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatsGrid() {
    final passedCategories = _categorySummaries.values
        .where((s) => s.passed == s.total && s.total > 0)
        .length;
    final totalCategories = _categorySummaries.length;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.category,
            title: 'الفئات',
            value: '$passedCategories / $totalCategories',
            subtitle: 'فئات ناجحة',
            color: Colors.purple,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            icon: Icons.speed,
            title: 'الأداء',
            value: _lastReport != null
                ? '${_lastReport!.totalDuration.inSeconds}s'
                : '-',
            subtitle: 'إجمالي وقت الفحص',
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            icon: Icons.verified,
            title: 'الحالة',
            value: _lastReport != null
                ? _lastReport!.failedTests == 0
                    ? 'ممتاز'
                    : 'يحتاج مراجعة'
                : '-',
            subtitle: 'حالة النظام',
            color: _lastReport?.failedTests == 0 ? Colors.green : Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoriesTab() {
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.2,
      ),
      itemCount: DiagnosticCategories.all.length,
      itemBuilder: (context, index) {
        final category = DiagnosticCategories.all[index];
        final summary = _categorySummaries[category.id]!;
        final isRunningThisCategory =
            _isRunning && _currentCategory == category.id;

        return DiagnosticCategoryCard(
          category: category,
          totalTests: summary.total,
          completedTests: summary.passed + summary.failed,
          passedTests: summary.passed,
          failedTests: summary.failed,
          isRunning: isRunningThisCategory,
          onRunTests: _isRunning ? null : () => _runCategoryTests(category.id),
        );
      },
    );
  }

  Widget _buildResultsTab() {
    return Column(
      children: [
        // Filter bar
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[50],
          child: Row(
            children: [
              const Text(
                'فلترة حسب الفئة:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('all', 'الكل'),
                      ...DiagnosticCategories.all.map(
                        (c) => _buildFilterChip(c.id, c.nameAr),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Results list
        Expanded(
          child: _filteredResults.isEmpty
              ? Center(
                  child: Text(
                    'لا توجد نتائج',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filteredResults.length,
                  itemBuilder: (context, index) {
                    final result = _filteredResults[index];
                    final test = _diagnosticService
                        .getAllTests()
                        .firstWhere((t) => t.id == result.testId);

                    return DiagnosticResultItem(
                      result: result,
                      testName: test.nameAr,
                      isExpanded: _expandedResults.contains(result.testId),
                      onTap: () {
                        setState(() {
                          if (_expandedResults.contains(result.testId)) {
                            _expandedResults.remove(result.testId);
                          } else {
                            _expandedResults.add(result.testId);
                          }
                        });
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String id, String label) {
    final isSelected = _selectedCategoryFilter == id;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedCategoryFilter = selected ? id : 'all';
          });
        },
        selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
        checkmarkColor: Theme.of(context).primaryColor,
      ),
    );
  }
}
