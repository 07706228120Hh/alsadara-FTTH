import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../services/whatsapp_batch_report_service.dart';

/// صفحة تقارير الإرسال الجماعي
class WhatsAppBatchReportsPage extends StatefulWidget {
  const WhatsAppBatchReportsPage({super.key});

  @override
  State<WhatsAppBatchReportsPage> createState() =>
      _WhatsAppBatchReportsPageState();
}

class _WhatsAppBatchReportsPageState extends State<WhatsAppBatchReportsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _reports = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _reports = await WhatsAppBatchReportService.getBatchReports(limit: 50);
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'حدث خطأ';
      });
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('yyyy/MM/dd hh:mm a', 'ar').format(date.toLocal());
    } catch (e) {
      return dateStr;
    }
  }

  SdStatus _getStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return SdStatus.success;
      case 'in_progress':
      case 'processing':
        return SdStatus.warning;
      case 'failed':
        return SdStatus.danger;
      default:
        return SdStatus.neutral;
    }
  }

  Color _getStatusColor(String? status) => _getStatus(status).tone.base;

  IconData _getStatusIcon(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return Icons.check_circle;
      case 'in_progress':
      case 'processing':
        return Icons.sync;
      case 'failed':
        return Icons.error;
      default:
        return Icons.help;
    }
  }

  String _getStatusText(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return 'مكتمل';
      case 'in_progress':
      case 'processing':
        return 'جاري...';
      case 'failed':
        return 'فشل';
      default:
        return status ?? 'غير معروف';
    }
  }

  String _getTemplateText(String? templateType) {
    switch (templateType) {
      case 'sadara_reminder':
        return '⏰ تذكير بالتجديد';
      case 'sadara_renewed':
        return '✅ تجديد ناجح';
      case 'sadara_expired':
        return '⚠️ انتهاء الاشتراك';
      default:
        return templateType ?? 'غير محدد';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'تقارير الإرسال الجماعي',
          actions: [
            SdAppBarAction(
              icon: Icons.refresh,
              label: 'تحديث',
              onPressed: _loadReports,
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: SdColors.primary),
            SizedBox(height: 16),
            Text('جاري تحميل التقارير...', style: SdText.bodySm),
          ],
        ),
      );
    }

    if (_error != null) {
      return SdEmptyState(
        title: 'خطأ: $_error',
        icon: Icons.error_outline_rounded,
        status: SdStatus.danger,
        action: SdButton(
          label: 'إعادة المحاولة',
          icon: Icons.refresh,
          kind: SdButtonKind.secondary,
          onPressed: _loadReports,
        ),
      );
    }

    if (_reports.isEmpty) {
      return const SdEmptyState(
        title: 'لا توجد تقارير',
        message: 'ستظهر هنا تقارير الإرسال الجماعي',
        icon: Icons.inbox_rounded,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _reports.length,
        itemBuilder: (context, index) => _buildReportCard(_reports[index]),
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final status = report['status']?.toString();
    final sent = report['sent'] ?? 0;
    final failed = report['failed'] ?? 0;
    final total = report['total'] ?? 0;
    final rate = report['rate']?.toString() ?? '0%';
    final templateType = report['templateType']?.toString();
    final batchId = report['batchId']?.toString() ?? report['docId'];
    final completedAt = report['completedAt']?.toString();
    final createdAt = report['createdAt']?.toString();

    // حساب نسبة النجاح
    double successRate = 0;
    if (total > 0) {
      successRate = (sent / total) * 100;
    }

    final Color rateColor = successRate >= 90
        ? SdColors.success
        : successRate >= 50
            ? SdColors.warning
            : SdColors.danger;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SdRaised(
        onTap: () => _showReportDetails(report),
        semanticLabel: _getTemplateText(templateType),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الصف العلوي - الحالة والتاريخ
            Row(
              children: [
                SdStatusChip(
                  _getStatusText(status),
                  status: _getStatus(status),
                  icon: _getStatusIcon(status),
                ),
                const Spacer(),
                Text(
                  _formatDate(completedAt ?? createdAt),
                  style: SdText.caption,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // القالب
            if (templateType != null) ...[
              Text(
                _getTemplateText(templateType),
                style: SdText.titleSm,
              ),
              const SizedBox(height: 8),
            ],

            // الإحصائيات
            Row(
              children: [
                _buildStatItem(
                  icon: Icons.groups,
                  label: 'الإجمالي',
                  value: total.toString(),
                  color: SdColors.info,
                ),
                const SizedBox(width: 16),
                _buildStatItem(
                  icon: Icons.check_circle,
                  label: 'نجح',
                  value: sent.toString(),
                  color: SdColors.success,
                ),
                const SizedBox(width: 16),
                _buildStatItem(
                  icon: Icons.error,
                  label: 'فشل',
                  value: failed.toString(),
                  color: SdColors.danger,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // شريط التقدم
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('نسبة النجاح', style: SdText.caption),
                    Text(
                      rate,
                      style: TextStyle(
                        fontFamily: SdText.family,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: rateColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: successRate / 100,
                    backgroundColor: SdColors.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(rateColor),
                    minHeight: 8,
                  ),
                ),
              ],
            ),

            // معرف الدفعة
            const SizedBox(height: 8),
            Text(
              'ID: ${batchId ?? "-"}',
              style: SdText.mono.copyWith(fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontFamily: SdText.family,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: SdText.family,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportDetails(Map<String, dynamic> report) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: SdColors.edge,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Text(
                      '📋 تفاصيل التقرير',
                      style: SdText.title,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildDetailRow('معرف الدفعة', report['batchId'] ?? '-'),
                    _buildDetailRow(
                        'الحالة', _getStatusText(report['status']?.toString())),
                    _buildDetailRow('نوع القالب',
                        _getTemplateText(report['templateType']?.toString())),
                    _buildDetailRow(
                        'إجمالي المستلمين', '${report['total'] ?? 0}'),
                    _buildDetailRow(
                        'تم الإرسال بنجاح', '${report['sent'] ?? 0}',
                        color: SdColors.success),
                    _buildDetailRow('فشل الإرسال', '${report['failed'] ?? 0}',
                        color: SdColors.danger),
                    _buildDetailRow(
                        'نسبة النجاح', report['rate']?.toString() ?? '0%'),
                    _buildDetailRow('تاريخ الإنشاء',
                        _formatDate(report['createdAt']?.toString())),
                    _buildDetailRow('تاريخ الاكتمال',
                        _formatDate(report['completedAt']?.toString())),

                    // معلومات إضافية إن وجدت
                    if (report['error'] != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: SdColors.dangerTint,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: SdColors.dangerTintEdge),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: SdColors.danger, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'رسالة الخطأ',
                                  style: SdText.label
                                      .copyWith(color: SdColors.danger),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              report['error'].toString(),
                              style: SdText.bodySm,
                            ),
                          ],
                        ),
                      ),
                    ],

                    // زر حذف التقرير
                    const SizedBox(height: 24),
                    SdButton(
                      label: 'حذف التقرير',
                      icon: Icons.delete,
                      kind: SdButtonKind.danger,
                      expand: true,
                      onPressed: () => _confirmDeleteReport(report),
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

  Widget _buildDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: SdText.bodySm,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: SdText.label.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteReport(Map<String, dynamic> report) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: const Text('هل أنت متأكد من حذف هذا التقرير؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.danger),
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      try {
        final id = report['id'] ?? report['Id'];
        if (id != null) {
          await WhatsAppBatchReportService.deleteBatchReport(
              id is int ? id : int.tryParse(id.toString()) ?? 0);
        }

        if (mounted) {
          Navigator.pop(context); // Close bottom sheet
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حذف التقرير'),
              backgroundColor: Colors.green,
            ),
          );
          _loadReports();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('خطأ في الحذف'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
