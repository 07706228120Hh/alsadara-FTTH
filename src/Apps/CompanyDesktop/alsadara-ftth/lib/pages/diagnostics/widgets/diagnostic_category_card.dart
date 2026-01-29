import 'package:flutter/material.dart';
import '../models/diagnostic_result.dart';

/// بطاقة فئة التشخيص
class DiagnosticCategoryCard extends StatelessWidget {
  final DiagnosticCategory category;
  final int totalTests;
  final int completedTests;
  final int passedTests;
  final int failedTests;
  final bool isRunning;
  final VoidCallback? onRunTests;

  const DiagnosticCategoryCard({
    super.key,
    required this.category,
    required this.totalTests,
    required this.completedTests,
    required this.passedTests,
    required this.failedTests,
    required this.isRunning,
    this.onRunTests,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalTests > 0 ? completedTests / totalTests : 0.0;
    final successRate = completedTests > 0 ? passedTests / completedTests : 0.0;

    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (completedTests == 0) {
      statusColor = Colors.grey;
      statusIcon = Icons.pending_outlined;
      statusText = 'في انتظار التشغيل';
    } else if (failedTests > 0) {
      statusColor = Colors.red;
      statusIcon = Icons.error_outline;
      statusText = '$failedTests اختبار فاشل';
    } else if (passedTests == completedTests) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle_outline;
      statusText = 'جميع الاختبارات ناجحة';
    } else {
      statusColor = Colors.orange;
      statusIcon = Icons.warning_amber_outlined;
      statusText = 'بعض التحذيرات';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onRunTests,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        category.icon,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.nameAr,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          category.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isRunning)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(statusIcon, color: statusColor, size: 28),
                ],
              ),

              const SizedBox(height: 20),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              ),

              const SizedBox(height: 12),

              // Stats
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStat('الإجمالي', totalTests.toString(), Colors.blue),
                  _buildStat('نجح', passedTests.toString(), Colors.green),
                  _buildStat('فشل', failedTests.toString(), Colors.red),
                  _buildStat(
                    'النسبة',
                    '${(successRate * 100).toStringAsFixed(0)}%',
                    statusColor,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Status text
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(statusIcon, size: 16, color: statusColor),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
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

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
