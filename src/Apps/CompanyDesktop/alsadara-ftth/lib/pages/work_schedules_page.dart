/// اسم الصفحة: جداول الدوام
/// وصف الصفحة: إدارة جداول الدوام (أوقات العمل) للشركة والمراكز
/// المؤلف: تطبيق السدارة
library;

import 'package:flutter/material.dart';
import '../utils/responsive_helper.dart';
import '../services/attendance_api_service.dart';

class WorkSchedulesPage extends StatefulWidget {
  final String? companyId;

  const WorkSchedulesPage({super.key, this.companyId});

  @override
  State<WorkSchedulesPage> createState() => _WorkSchedulesPageState();
}

class _WorkSchedulesPageState extends State<WorkSchedulesPage> {
  final AttendanceApiService _api = AttendanceApiService.instance;
  List<Map<String, dynamic>> _schedules = [];
  bool _loading = true;

  static const List<String> _dayNames = [
    'الأحد',
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
  ];

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    setState(() => _loading = true);
    try {
      final data = await _api.getSchedules(companyId: widget.companyId);
      setState(() {
        _schedules = data;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل الجداول: $e')),
        );
      }
    }
  }

  String _dayName(dynamic dayOfWeek) {
    if (dayOfWeek == null) return 'جميع الأيام';
    final idx = dayOfWeek is int ? dayOfWeek : int.tryParse('$dayOfWeek') ?? -1;
    if (idx >= 0 && idx < _dayNames.length) return _dayNames[idx];
    return 'غير معروف';
  }

  Future<void> _showAddEditDialog({Map<String, dynamic>? existing}) async {
    final nameCtrl = TextEditingController(
        text: existing?['Name'] ?? existing?['name'] ?? '');
    final centerCtrl = TextEditingController(
        text: existing?['CenterName'] ?? existing?['centerName'] ?? '');
    final startCtrl = TextEditingController(
        text: existing?['WorkStartTime'] ??
            existing?['workStartTime'] ??
            '08:00');
    final endCtrl = TextEditingController(
        text: existing?['WorkEndTime'] ?? existing?['workEndTime'] ?? '16:00');
    final graceCtrl = TextEditingController(
        text:
            '${existing?['LateGraceMinutes'] ?? existing?['lateGraceMinutes'] ?? 15}');
    final earlyCtrl = TextEditingController(
        text:
            '${existing?['EarlyDepartureThresholdMinutes'] ?? existing?['earlyDepartureThresholdMinutes'] ?? 15}');

    int? selectedDay = existing?['DayOfWeek'] ?? existing?['dayOfWeek'];
    bool isDefault = existing?['IsDefault'] ?? existing?['isDefault'] ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing != null ? 'تعديل جدول الدوام' : 'إضافة جدول دوام',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم الجدول *',
                      hintText: 'مثلاً: الدوام الرسمي',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.schedule),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: centerCtrl,
                    decoration: const InputDecoration(
                      labelText: 'المركز (اختياري)',
                      hintText: 'اتركه فارغاً لجميع المراكز',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: selectedDay,
                    decoration: const InputDecoration(
                      labelText: 'اليوم',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('جميع الأيام')),
                      for (int i = 0; i < 7; i++)
                        DropdownMenuItem(value: i, child: Text(_dayNames[i])),
                    ],
                    onChanged: (v) => setDialogState(() => selectedDay = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startCtrl,
                          decoration: const InputDecoration(
                            labelText: 'بداية الدوام *',
                            hintText: '08:00',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.login),
                          ),
                          onTap: () async {
                            final time = await _pickTime(ctx, startCtrl.text);
                            if (time != null) startCtrl.text = time;
                          },
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: endCtrl,
                          decoration: const InputDecoration(
                            labelText: 'نهاية الدوام *',
                            hintText: '16:00',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.logout),
                          ),
                          onTap: () async {
                            final time = await _pickTime(ctx, endCtrl.text);
                            if (time != null) endCtrl.text = time;
                          },
                          readOnly: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: graceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'سماح التأخير (دقيقة)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.timer),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: earlyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'حد الانصراف المبكر (دقيقة)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.timer_off),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('جدول افتراضي'),
                    subtitle:
                        const Text('يُطبق تلقائياً عند عدم وجود جدول مخصص'),
                    value: isDefault,
                    onChanged: (v) => setDialogState(() => isDefault = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    if (nameCtrl.text.trim().isEmpty ||
        startCtrl.text.isEmpty ||
        endCtrl.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى ملء الحقول المطلوبة')),
        );
      }
      return;
    }

    try {
      if (existing != null) {
        final id = existing['Id'] ?? existing['id'];
        await _api.updateSchedule(
          id: id is int ? id : int.parse('$id'),
          name: nameCtrl.text.trim(),
          workStartTime: startCtrl.text,
          workEndTime: endCtrl.text,
          companyId: widget.companyId,
          centerName:
              centerCtrl.text.trim().isEmpty ? null : centerCtrl.text.trim(),
          dayOfWeek: selectedDay,
          lateGraceMinutes: int.tryParse(graceCtrl.text) ?? 15,
          earlyDepartureThresholdMinutes: int.tryParse(earlyCtrl.text) ?? 15,
          isDefault: isDefault,
        );
      } else {
        await _api.addSchedule(
          name: nameCtrl.text.trim(),
          workStartTime: startCtrl.text,
          workEndTime: endCtrl.text,
          companyId: widget.companyId,
          centerName:
              centerCtrl.text.trim().isEmpty ? null : centerCtrl.text.trim(),
          dayOfWeek: selectedDay,
          lateGraceMinutes: int.tryParse(graceCtrl.text) ?? 15,
          earlyDepartureThresholdMinutes: int.tryParse(earlyCtrl.text) ?? 15,
          isDefault: isDefault,
        );
      }
      _loadSchedules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الحفظ بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    }
  }

  Future<String?> _pickTime(BuildContext context, String current) async {
    final parts = current.split(':');
    final hour = int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 8;
    final minute = int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return null;
    return '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _deleteSchedule(Map<String, dynamic> schedule) async {
    final name = schedule['Name'] ?? schedule['name'] ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف جدول "$name"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final id = schedule['Id'] ?? schedule['id'];
      await _api.deleteSchedule(id is int ? id : int.parse('$id'));
      _loadSchedules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الحذف')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الحذف: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('جداول الدوام',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: r.appBarTitleSize)),
          centerTitle: true,
          backgroundColor: Colors.teal[700],
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: _loadSchedules,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddEditDialog(),
          icon: const Icon(Icons.add),
          label: const Text('إضافة جدول'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _schedules.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule, size: 80, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'لا توجد جداول دوام',
                          style:
                              TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'قم بإضافة جدول دوام لتفعيل نظام التأخير والوقت الإضافي',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _schedules.length,
                    itemBuilder: (ctx, i) => _buildScheduleCard(_schedules[i]),
                  ),
      ),
    );
  }

  Widget _buildScheduleCard(Map<String, dynamic> s) {
    final name = s['Name'] ?? s['name'] ?? '';
    final center = s['CenterName'] ?? s['centerName'];
    final dayOfWeek = s['DayOfWeek'] ?? s['dayOfWeek'];
    final start = s['WorkStartTime'] ?? s['workStartTime'] ?? '';
    final end = s['WorkEndTime'] ?? s['workEndTime'] ?? '';
    final grace = s['LateGraceMinutes'] ?? s['lateGraceMinutes'] ?? 15;
    final earlyDep = s['EarlyDepartureThresholdMinutes'] ??
        s['earlyDepartureThresholdMinutes'] ??
        15;
    final isDefault = s['IsDefault'] ?? s['isDefault'] ?? false;

    // تنسيق الوقت (قد يأتي كـ "08:00:00" أو "08:00")
    String formatTime(String t) {
      final parts = t.split(':');
      if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
      return t;
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (isDefault)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('افتراضي',
                        style: TextStyle(
                            color: Colors.green[800],
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  tooltip: 'تعديل',
                  onPressed: () => _showAddEditDialog(existing: s),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: 'حذف',
                  onPressed: () => _deleteSchedule(s),
                ),
              ],
            ),
            const Divider(),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _infoChip(Icons.login, 'البداية', formatTime('$start')),
                _infoChip(Icons.logout, 'النهاية', formatTime('$end')),
                _infoChip(Icons.calendar_today, 'اليوم', _dayName(dayOfWeek)),
                _infoChip(Icons.timer, 'سماح التأخير', '$grace دقيقة'),
                _infoChip(
                    Icons.timer_off, 'حد الانصراف المبكر', '$earlyDep دقيقة'),
                if (center != null && '$center'.isNotEmpty)
                  _infoChip(Icons.business, 'المركز', '$center'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text('$label: ',
            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}
