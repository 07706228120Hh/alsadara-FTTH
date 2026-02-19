import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';
import '../models/task.dart';
import '../services/task_api_service.dart';

/// صفحة المتابعة - لمتابعة المهام المكتملة والملغية والتأكد من إتمامها
class FollowUpPage extends StatefulWidget {
  final String username;
  final String permissions;
  final String department;
  final String center;

  const FollowUpPage({
    super.key,
    required this.username,
    required this.permissions,
    required this.department,
    required this.center,
  });

  @override
  State<FollowUpPage> createState() => _FollowUpPageState();
}

class _FollowUpPageState extends State<FollowUpPage> {
  List<Task> _allTasks = [];
  bool _isLoading = true;
  String? _error;
  // فلتر الحالة: الكل، مكتملة، ملغية
  String _statusFilter = 'الكل';
  // فلتر التدقيق: الكل، لم يتم، تم التدقيق، مشكلة
  String _followUpFilter = 'لم يتم';
  // تخزين حالة التدقيق والتقييم (من السيرفر)
  final Map<String, String> _followUpStatus = {}; // taskId -> status
  final Map<String, int> _ratings = {}; // taskId -> rating (1-5)
  final Map<String, String> _followUpNotes = {}; // taskId -> notes

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  /// جلب المهام وبيانات التدقيق من السيرفر
  Future<void> _fetchData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      // جلب المهام وبيانات التدقيق بالتوازي مع timeout
      final results = await Future.wait([
        TaskApiService.instance.getRequests(pageSize: 200),
        TaskApiService.instance.getAuditsBulk(),
      ]).timeout(const Duration(seconds: 10));

      final tasksResponse = results[0];
      final auditsResponse = results[1];

      // معالجة المهام
      if (tasksResponse['success'] == true && tasksResponse['data'] is List) {
        final tasks = (tasksResponse['data'] as List)
            .map((item) =>
                Task.fromApiResponse(Map<String, dynamic>.from(item as Map)))
            .where((t) => t.status == 'مكتملة' || t.status == 'ملغية')
            .toList();
        tasks.sort((a, b) {
          final da = a.closedAt ?? a.createdAt;
          final db = b.closedAt ?? b.createdAt;
          return db.compareTo(da);
        });
        _allTasks = tasks;
      }

      // معالجة بيانات التدقيق
      if (auditsResponse['success'] == true && auditsResponse['data'] is Map) {
        final audits = Map<String, dynamic>.from(auditsResponse['data'] as Map);
        for (final entry in audits.entries) {
          final data = entry.value;
          if (data is Map) {
            final status = data['AuditStatus']?.toString() ?? 'لم يتم';
            final rating = data['Rating'] as int? ?? 0;
            final notes = data['Notes']?.toString();
            _followUpStatus[entry.key] = status;
            if (rating > 0) _ratings[entry.key] = rating;
            if (notes != null && notes.isNotEmpty) {
              _followUpNotes[entry.key] = notes;
            }
          }
        }
      }
    } on TimeoutException {
      debugPrint('⏰ [FollowUp] انتهت مهلة الاتصال');
    } catch (e) {
      debugPrint('❌ [FollowUp] خطأ: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// حفظ تدقيق مهمة على السيرفر
  Future<void> _saveAuditToServer(String taskId) async {
    try {
      await TaskApiService.instance.saveAudit(
        requestNumber: taskId,
        auditStatus: _followUpStatus[taskId],
        rating: _ratings[taskId],
        notes: _followUpNotes[taskId],
        auditedBy: widget.username,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حفظ التدقيق: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Task> get _filteredTasks {
    var tasks = List<Task>.from(_allTasks);

    // فلتر حسب الحالة
    if (_statusFilter == 'مكتملة') {
      tasks = tasks.where((t) => t.status == 'مكتملة').toList();
    } else if (_statusFilter == 'ملغية') {
      tasks = tasks.where((t) => t.status == 'ملغية').toList();
    }

    // فلتر حسب حالة التدقيق
    if (_followUpFilter != 'الكل') {
      tasks = tasks.where((t) {
        final status = _followUpStatus[t.id] ?? 'لم يتم';
        return status == _followUpFilter;
      }).toList();
    }

    // ترتيب حسب الأحدث
    tasks.sort((a, b) {
      final da = a.closedAt ?? a.createdAt;
      final db = b.closedAt ?? b.createdAt;
      return db.compareTo(da);
    });

    return tasks;
  }

  int get _totalCount => _allTasks.length;
  int get _completedCount =>
      _allTasks.where((t) => t.status == 'مكتملة').length;
  int get _cancelledCount => _allTasks.where((t) => t.status == 'ملغية').length;
  int get _followedUpCount =>
      _followUpStatus.values.where((s) => s == 'تم التدقيق').length;
  int get _issueCount =>
      _followUpStatus.values.where((s) => s == 'مشكلة').length;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: _buildAppBar(),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // إحصائيات سريعة
                  _buildStatsBar(),
                  // شريط الفلاتر
                  _buildFilterBar(),
                  // قائمة المهام
                  Expanded(
                    child: _filteredTasks.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            itemCount: _filteredTasks.length,
                            itemBuilder: (context, index) {
                              return _buildFollowUpCard(_filteredTasks[index]);
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1A1A2E),
      foregroundColor: Colors.white,
      elevation: 0,
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fact_check_rounded, size: 22),
          SizedBox(width: 8),
          Text(
            'المتابعة والتقييم',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
      centerTitle: true,
    );
  }

  Widget _buildStatsBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildStatItem('الكل', _totalCount, Colors.white),
          _buildStatDivider(),
          _buildStatItem('مكتملة', _completedCount, const Color(0xFF2ECC71)),
          _buildStatDivider(),
          _buildStatItem('ملغية', _cancelledCount, const Color(0xFFE74C3C)),
          _buildStatDivider(),
          _buildStatItem(
              'تم تدقيقها', _followedUpCount, const Color(0xFF3498DB)),
          _buildStatDivider(),
          _buildStatItem('مشاكل', _issueCount, const Color(0xFFE67E22)),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: 28,
      color: Colors.white.withValues(alpha: 0.15),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          // فلتر الحالة
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('الكل', _statusFilter, (v) {
                    setState(() => _statusFilter = v);
                  }, Icons.list_rounded, const Color(0xFF1A1A2E)),
                  const SizedBox(width: 6),
                  _buildFilterChip('مكتملة', _statusFilter, (v) {
                    setState(() => _statusFilter = v);
                  }, Icons.check_circle_outline, const Color(0xFF2ECC71)),
                  const SizedBox(width: 6),
                  _buildFilterChip('ملغية', _statusFilter, (v) {
                    setState(() => _statusFilter = v);
                  }, Icons.cancel_outlined, const Color(0xFFE74C3C)),
                  const SizedBox(width: 12),
                  Container(width: 1, height: 24, color: Colors.grey.shade300),
                  const SizedBox(width: 12),
                  _buildFilterChip('لم يتم', _followUpFilter, (v) {
                    setState(() =>
                        _followUpFilter = _followUpFilter == v ? 'الكل' : v);
                  }, Icons.pending_outlined, Colors.grey, isFollowUp: true),
                  const SizedBox(width: 6),
                  _buildFilterChip('تم التدقيق', _followUpFilter, (v) {
                    setState(() =>
                        _followUpFilter = _followUpFilter == v ? 'الكل' : v);
                  }, Icons.verified_outlined, const Color(0xFF3498DB),
                      isFollowUp: true),
                  const SizedBox(width: 6),
                  _buildFilterChip('مشكلة', _followUpFilter, (v) {
                    setState(() =>
                        _followUpFilter = _followUpFilter == v ? 'الكل' : v);
                  }, Icons.warning_amber_rounded, const Color(0xFFE67E22),
                      isFollowUp: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    String currentFilter,
    Function(String) onSelected,
    IconData icon,
    Color color, {
    bool isFollowUp = false,
  }) {
    final isSelected = currentFilter == label;
    return GestureDetector(
      onTap: () => onSelected(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14, color: isSelected ? Colors.white : Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.fact_check_outlined,
              size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'لا توجد مهام للمتابعة',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'لم يتم العثور على مهام مكتملة أو ملغية',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowUpCard(Task task) {
    final statusColor = task.status == 'مكتملة'
        ? const Color(0xFF2ECC71)
        : const Color(0xFFE74C3C);
    final followUpState = _followUpStatus[task.id] ?? 'لم يتم';
    final rating = _ratings[task.id] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // الشريط العلوي
          _buildCardHeader(task, statusColor, followUpState),
          // المحتوى
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Column(
              children: [
                // معلومات العميل والفني
                _buildInfoRow(task),
                const SizedBox(height: 8),
                // الجدول الزمني
                _buildTimeline(task),
                const SizedBox(height: 8),
                // التقييم والإجراءات
                _buildRatingAndActions(task, rating, followUpState),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardHeader(Task task, Color statusColor, String followUpState) {
    Color followUpColor;
    IconData followUpIcon;
    switch (followUpState) {
      case 'تم التدقيق':
        followUpColor = const Color(0xFF3498DB);
        followUpIcon = Icons.verified_rounded;
        break;
      case 'مشكلة':
        followUpColor = const Color(0xFFE67E22);
        followUpIcon = Icons.warning_rounded;
        break;
      default:
        followUpColor = Colors.grey;
        followUpIcon = Icons.pending_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            statusColor.withValues(alpha: 0.08),
            statusColor.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          // أيقونة الحالة
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              task.status == 'مكتملة'
                  ? Icons.check_circle_rounded
                  : Icons.cancel_rounded,
              size: 16,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 8),
          // العنوان والقسم
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Text(
                      '${task.department} • #${task.id}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // شارة حالة المتابعة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: followUpColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: followUpColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(followUpIcon, size: 11, color: followUpColor),
                const SizedBox(width: 3),
                Text(
                  followUpState,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: followUpColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(Task task) {
    return Row(
      children: [
        // العميل
        Expanded(
          child: _buildInfoTile(
            Icons.person_outline_rounded,
            'العميل',
            task.username,
            const Color(0xFF3498DB),
          ),
        ),
        const SizedBox(width: 6),
        // الفني
        Expanded(
          child: _buildInfoTile(
            Icons.engineering_rounded,
            'الفني',
            task.technician,
            const Color(0xFF009688),
          ),
        ),
        const SizedBox(width: 6),
        // المبلغ
        if (task.amount.isNotEmpty && task.amount != '0')
          Expanded(
            child: _buildInfoTile(
              Icons.monetization_on_outlined,
              'المبلغ',
              '${task.amount} د.ع',
              const Color(0xFFE74C3C),
            ),
          ),
      ],
    );
  }

  Widget _buildInfoTile(
      IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, size: 11, color: color),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
                ),
                Text(
                  value.isNotEmpty ? value : '-',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(Task task) {
    // بناء مراحل الجدول الزمني من سجل الحالة
    final stages = <_TimelineStage>[];

    // مرحلة الإنشاء
    stages.add(_TimelineStage(
      label: 'الإنشاء',
      icon: Icons.add_circle_outline_rounded,
      time: task.createdAt,
      color: const Color(0xFF3498DB),
      by: task.createdBy.isNotEmpty ? task.createdBy : null,
    ));

    // المراحل من سجل الحالة
    for (final h in task.statusHistory) {
      IconData icon;
      Color color;
      String label;

      switch (h.toStatus) {
        case 'قيد المراجعة':
          icon = Icons.visibility_outlined;
          color = const Color(0xFF9B59B6);
          label = 'المراجعة';
          break;
        case 'مفتوحة':
          icon = Icons.assignment_outlined;
          color = const Color(0xFF2196F3);
          label = 'التعيين';
          break;
        case 'قيد التنفيذ':
          icon = Icons.play_circle_outline_rounded;
          color = const Color(0xFFE67E22);
          label = 'بدء التنفيذ';
          break;
        case 'مكتملة':
          icon = Icons.check_circle_outline_rounded;
          color = const Color(0xFF2ECC71);
          label = 'الإكمال';
          break;
        case 'ملغية':
          icon = Icons.cancel_outlined;
          color = const Color(0xFFE74C3C);
          label = 'الإلغاء';
          break;
        default:
          icon = Icons.circle_outlined;
          color = Colors.grey;
          label = h.toStatus;
      }

      stages.add(_TimelineStage(
        label: label,
        icon: icon,
        time: h.changedAt,
        color: color,
        by: h.changedBy.isNotEmpty ? h.changedBy : null,
      ));
    }

    // حساب المدة الإجمالية
    final totalDuration =
        (task.closedAt ?? DateTime.now()).difference(task.createdAt);
    final durationText = _formatDuration(totalDuration);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان الجدول الزمني
          Row(
            children: [
              Icon(Icons.timeline_rounded,
                  size: 13, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                'مراحل التنفيذ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'المدة: $durationText',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // المراحل أفقياً
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < stages.length; i++) ...[
                  _buildTimelineStep(stages[i], i == stages.length - 1),
                  if (i < stages.length - 1)
                    _buildTimelineConnector(stages[i], stages[i + 1]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineStep(_TimelineStage stage, bool isLast) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: stage.color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: stage.color, width: 1.5),
          ),
          child: Icon(stage.icon, size: 12, color: stage.color),
        ),
        const SizedBox(height: 3),
        Text(
          stage.label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: stage.color,
          ),
        ),
        Text(
          DateFormat('MM/dd HH:mm').format(stage.time),
          style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
        ),
        if (stage.by != null)
          Text(
            stage.by!,
            style: TextStyle(fontSize: 7, color: Colors.grey.shade400),
          ),
      ],
    );
  }

  Widget _buildTimelineConnector(_TimelineStage from, _TimelineStage to) {
    final duration = to.time.difference(from.time);
    final durationText = _formatDuration(duration);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 1.5,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [from.color, to.color],
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            durationText,
            style: TextStyle(fontSize: 7, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingAndActions(Task task, int rating, String followUpState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          // التقييم بالنجوم
          _buildStarRating(task, rating),
          const SizedBox(width: 8),

          // فاصل
          Container(width: 1, height: 28, color: Colors.grey.shade200),
          const SizedBox(width: 8),

          // أزرار الاتصال
          if (task.phone.isNotEmpty)
            _buildActionBtn(
              Icons.phone_rounded,
              'العميل',
              const Color(0xFF2ECC71),
              () => _makeCall(task.phone),
            ),
          if (task.agentName.isNotEmpty)
            _buildActionBtn(
              Icons.person_pin_rounded,
              'الوكيل',
              const Color(0xFF9B59B6),
              () {
                // يمكن إضافة اتصال بالوكيل
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('الوكيل: ${task.agentName}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          if (task.phone.isNotEmpty)
            _buildActionBtn(
              Icons.message_rounded,
              'واتساب',
              const Color(0xFF25D366),
              () => _launchWhatsApp(task.phone),
            ),

          const Spacer(),

          // أزرار حالة التدقيق
          _buildFollowUpBtn(
            task,
            'تم التدقيق',
            Icons.verified_rounded,
            const Color(0xFF3498DB),
            followUpState,
          ),
          const SizedBox(width: 4),
          _buildFollowUpBtn(
            task,
            'مشكلة',
            Icons.warning_rounded,
            const Color(0xFFE67E22),
            followUpState,
          ),
        ],
      ),
    );
  }

  Widget _buildStarRating(Task task, int currentRating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        return GestureDetector(
          onTap: () {
            setState(() {
              _ratings[task.id] = starIndex;
            });
            _saveAuditToServer(task.id);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Icon(
              starIndex <= currentRating
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              size: 18,
              color: starIndex <= currentRating
                  ? const Color(0xFFF39C12)
                  : Colors.grey.shade300,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildActionBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowUpBtn(
    Task task,
    String status,
    IconData icon,
    Color color,
    String currentState,
  ) {
    final isActive = currentState == status;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isActive) {
            _followUpStatus[task.id] = 'لم يتم';
          } else {
            _followUpStatus[task.id] = status;
            if (status == 'مشكلة') {
              _showIssueNoteDialog(task);
            }
          }
        });
        _saveAuditToServer(task.id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? color : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? color : color.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isActive ? Colors.white : color),
            const SizedBox(width: 3),
            Text(
              status,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showIssueNoteDialog(Task task) {
    final controller =
        TextEditingController(text: _followUpNotes[task.id] ?? '');
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.warning_rounded, color: Color(0xFFE67E22), size: 20),
              SizedBox(width: 8),
              Text('تفاصيل المشكلة', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'اكتب تفاصيل المشكلة...',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _followUpNotes[task.id] = controller.text;
                });
                _saveAuditToServer(task.id);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE67E22),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays} يوم';
    } else if (duration.inHours > 0) {
      return '${duration.inHours} ساعة';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes} دقيقة';
    }
    return 'فوري';
  }

  Future<void> _makeCall(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchWhatsApp(String phone) async {
    String cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (!cleanPhone.startsWith('+') && !cleanPhone.startsWith('964')) {
      cleanPhone = '964$cleanPhone';
    }
    if (cleanPhone.startsWith('964') && !cleanPhone.startsWith('+')) {
      cleanPhone = '+$cleanPhone';
    }
    final uri = Uri.parse('https://wa.me/${cleanPhone.replaceAll('+', '')}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

/// نموذج مرحلة الجدول الزمني
class _TimelineStage {
  final String label;
  final IconData icon;
  final DateTime time;
  final Color color;
  final String? by;

  _TimelineStage({
    required this.label,
    required this.icon,
    required this.time,
    required this.color,
    this.by,
  });
}
