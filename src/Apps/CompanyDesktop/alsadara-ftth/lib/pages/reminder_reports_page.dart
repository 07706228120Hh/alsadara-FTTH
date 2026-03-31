import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تقارير التذكير التلقائي'),
          centerTitle: true,
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('لا توجد تقارير', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _logs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
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

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // نوع (تلقائي/يدوي)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isManual ? Colors.orange.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isManual ? Colors.orange : Colors.blue, width: 0.5),
                  ),
                  child: Text(
                    isManual ? 'يدوي' : 'تلقائي',
                    style: TextStyle(fontSize: 11, color: isManual ? Colors.orange.shade800 : Colors.blue.shade800, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                // الفئة
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_daysLabel(days), style: TextStyle(fontSize: 11, color: Colors.purple.shade800)),
                ),
                if (isManual && triggeredBy.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text('بواسطة: $triggeredBy', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
                const Spacer(),
                Text(timeStr, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 12),
            // إحصائيات
            Row(
              children: [
                _stat(Icons.groups, '$total', 'الإجمالي', Colors.blue),
                const SizedBox(width: 16),
                _stat(Icons.check_circle, '$sent', 'نجح', Colors.green),
                const SizedBox(width: 16),
                _stat(Icons.error, '$failed', 'فشل', Colors.red),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      Text('${successRate.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: successRate >= 90 ? Colors.green : successRate >= 50 ? Colors.orange : Colors.red,
                          )),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: successRate / 100,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation(
                            successRate >= 90 ? Colors.green : successRate >= 50 ? Colors.orange : Colors.red,
                          ),
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
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }
}
