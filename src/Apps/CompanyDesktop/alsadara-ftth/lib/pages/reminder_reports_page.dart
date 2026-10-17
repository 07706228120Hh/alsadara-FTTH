import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../services/api/api_client.dart';

class ReminderReportsPage extends StatefulWidget {
  const ReminderReportsPage({super.key});

  @override
  State<ReminderReportsPage> createState() => _ReminderReportsPageState();
}

class _ReminderReportsPageState extends State<ReminderReportsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await ApiClient.instance.get(
        '/reminders/logs?limit=100',
        (data) => data,
        useInternalKey: true,
      );
      if (result.isSuccess && result.data != null) {
        final raw = result.data;
        final list = raw is List ? raw : (raw is Map ? (raw['data'] as List?) ?? [] : []);
        _logs = list.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _daysLabel(int days) {
    if (days == 0) return 'المنتهي اليوم';
    if (days == 1) return 'المنتهي غداً';
    return 'خلال $days أيام';
  }

  @override
  Widget build(BuildContext context) {
    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'تقارير التذكير التلقائي',
          actions: [
            SdAppBarAction(
              icon: Icons.refresh,
              label: 'تحديث',
              onPressed: _load,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _logs.isEmpty
                ? const SdEmptyState(
                    title: 'لا توجد تقارير',
                    icon: Icons.inbox_rounded,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _logs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _buildCard(_logs[i]),
                  ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> log) {
    final sent = log['sent'] ?? 0;
    final failed = log['failed'] ?? 0;
    final total = log['total'] ?? 0;
    final days = log['days'] ?? 0;
    final isManual = log['isManual'] == true;
    final triggeredBy = log['triggeredBy']?.toString() ?? '';
    final executedAt = log['executedAt']?.toString() ?? '';

    String timeStr = '';
    try {
      final dt = DateTime.tryParse(executedAt)?.toLocal();
      if (dt != null) timeStr = DateFormat('yyyy/MM/dd hh:mm a', 'ar').format(dt);
    } catch (_) {
      timeStr = executedAt;
    }

    final successRate = total > 0 ? (sent / total * 100) : 0.0;
    final Color rateColor = successRate >= 90
        ? SdColors.success
        : successRate >= 50
            ? SdColors.warning
            : SdColors.danger;

    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              // نوع (تلقائي/يدوي)
              SdStatusChip(
                isManual ? 'يدوي' : 'تلقائي',
                status: isManual ? SdStatus.warning : SdStatus.info,
              ),
              // الفئة
              SdStatusChip(_daysLabel(days), status: SdStatus.neutral),
              if (isManual && triggeredBy.isNotEmpty)
                Text('بواسطة: $triggeredBy', style: SdText.caption),
              Text(timeStr, style: SdText.caption),
            ],
          ),
          const SizedBox(height: 12),
          // إحصائيات
          Row(
            children: [
              _stat(Icons.groups, '$total', 'الإجمالي', SdColors.info),
              const SizedBox(width: 16),
              _stat(Icons.check_circle, '$sent', 'نجح', SdColors.success),
              const SizedBox(width: 16),
              _stat(Icons.error, '$failed', 'فشل', SdColors.danger),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    Text('${successRate.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontFamily: SdText.family,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: rateColor,
                        )),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: successRate / 100,
                        backgroundColor: SdColors.divider,
                        valueColor: AlwaysStoppedAnimation(rateColor),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontFamily: SdText.family,
                fontWeight: FontWeight.w900,
                color: color,
                fontSize: 14)),
        Text(label, style: SdText.caption),
      ],
    );
  }
}
