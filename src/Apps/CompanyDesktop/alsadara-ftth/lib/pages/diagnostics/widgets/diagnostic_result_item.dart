import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../models/diagnostic_test.dart';

/// عنصر نتيجة التشخيص
class DiagnosticResultItem extends StatelessWidget {
  final DiagnosticTestResult result;
  final String testName;
  final bool isExpanded;
  final VoidCallback? onTap;

  const DiagnosticResultItem({
    super.key,
    required this.result,
    required this.testName,
    this.isExpanded = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = result.success ? SdColors.success : SdColors.danger;
    final statusIcon = result.success ? Icons.check_circle : Icons.cancel;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: statusColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          testName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          result.message,
                          style: const TextStyle(
                            fontSize: 12,
                            color: SdColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      result.durationText,
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: SdColors.faint,
                  ),
                ],
              ),

              // Expanded details
              if (isExpanded && result.details != null) ...[
                const Divider(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SdColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'التفاصيل:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: result.toString()),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم نسخ النتيجة'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            tooltip: 'نسخ',
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        result.details!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                      if (result.metadata != null) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'البيانات الإضافية:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          result.metadata.toString(),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'وقت التنفيذ: ${result.timestamp}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: SdColors.faint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// ملخص نتائج التشخيص
class DiagnosticSummaryCard extends StatelessWidget {
  final int totalTests;
  final int passedTests;
  final int failedTests;
  final Duration totalDuration;
  final VoidCallback? onCopyReport;
  final VoidCallback? onExportReport;

  const DiagnosticSummaryCard({
    super.key,
    required this.totalTests,
    required this.passedTests,
    required this.failedTests,
    required this.totalDuration,
    this.onCopyReport,
    this.onExportReport,
  });

  @override
  Widget build(BuildContext context) {
    final successRate = totalTests > 0 ? (passedTests / totalTests) * 100 : 0.0;
    final statusColor = failedTests == 0
        ? SdColors.success
        : failedTests < totalTests / 2
            ? SdColors.warning
            : SdColors.danger;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SdRadius.lg),
        gradient: LinearGradient(
          colors: [
            statusColor.withValues(alpha: 0.1),
            statusColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: SdDepth.raised(),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Title
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.analytics_outlined, color: statusColor, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'ملخص نتائج التشخيص',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Success rate circle
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                children: [
                  Center(
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: CircularProgressIndicator(
                        value: successRate / 100,
                        strokeWidth: 12,
                        backgroundColor: SdColors.divider,
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      ),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${successRate.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                        Text(
                          'نسبة النجاح',
                          style: const TextStyle(
                            fontSize: 10,
                            color: SdColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatColumn(
                  icon: Icons.format_list_numbered,
                  value: totalTests.toString(),
                  label: 'إجمالي الاختبارات',
                  color: SdColors.info,
                ),
                _buildStatColumn(
                  icon: Icons.check_circle,
                  value: passedTests.toString(),
                  label: 'اختبار ناجح',
                  color: SdColors.success,
                ),
                _buildStatColumn(
                  icon: Icons.cancel,
                  value: failedTests.toString(),
                  label: 'اختبار فاشل',
                  color: SdColors.danger,
                ),
                _buildStatColumn(
                  icon: Icons.timer,
                  value: '${totalDuration.inSeconds}s',
                  label: 'المدة الإجمالية',
                  color: SdColors.platformBase,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SdButton(
                  label: 'نسخ التقرير',
                  icon: Icons.copy,
                  onPressed: onCopyReport,
                ),
                const SizedBox(width: 16),
                SdButton(
                  label: 'تصدير JSON',
                  icon: Icons.download,
                  kind: SdButtonKind.secondary,
                  onPressed: onExportReport,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
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
          style: const TextStyle(
            fontSize: 10,
            color: SdColors.muted,
          ),
        ),
      ],
    );
  }
}
