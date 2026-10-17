import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';
import '../models/task.dart';
import '../services/task_api_service.dart';
import '../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import 'task_status_colors.dart';
import 'widgets/task_common_widgets.dart';

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
      debugPrint('❌ [FollowUp] خطأ');
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
          const SnackBar(
            content: Text('خطأ في حفظ التدقيق'),
            backgroundColor: SdColors.danger,
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
    return SdPage(
      padding: EdgeInsets.zero,
      maxWidth: double.infinity,
      scrollable: false,
      appBar: const SdAppBar(title: 'المتابعة والتقييم'),
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
    );
  }

  Widget _buildStatsBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [SdColors.primary, SdColors.primaryEdge],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: SdColors.primary.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildStatItem('الكل', _totalCount, Colors.white),
          _buildStatDivider(),
          _buildStatItem('مكتملة', _completedCount, SdStatus.success.tone.light),
          _buildStatDivider(),
          _buildStatItem('ملغية', _cancelledCount, SdStatus.danger.tone.light),
          _buildStatDivider(),
          _buildStatItem(
              'تم تدقيقها', _followedUpCount, SdStatus.info.tone.light),
          _buildStatDivider(),
          _buildStatItem('مشاكل', _issueCount, SdStatus.warning.tone.light),
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
              fontFamily: SdText.family,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: SdText.family,
              fontSize: 11.5,
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
                  AppFilterChip(
                    label: 'الكل',
                    currentFilter: _statusFilter,
                    onSelected: (v) => setState(() => _statusFilter = v),
                    icon: Icons.list_rounded,
                    color: SdColors.primary,
                  ),
                  const SizedBox(width: 6),
                  AppFilterChip(
                    label: 'مكتملة',
                    currentFilter: _statusFilter,
                    onSelected: (v) => setState(() => _statusFilter = v),
                    icon: Icons.check_circle_outline,
                    color: SdColors.success,
                  ),
                  const SizedBox(width: 6),
                  AppFilterChip(
                    label: 'ملغية',
                    currentFilter: _statusFilter,
                    onSelected: (v) => setState(() => _statusFilter = v),
                    icon: Icons.cancel_outlined,
                    color: SdColors.danger,
                  ),
                  const SizedBox(width: 12),
                  Container(width: 1, height: 24, color: SdColors.divider),
                  const SizedBox(width: 12),
                  AppFilterChip(
                    label: 'لم يتم',
                    currentFilter: _followUpFilter,
                    onSelected: (v) => setState(() =>
                        _followUpFilter = _followUpFilter == v ? 'الكل' : v),
                    icon: Icons.pending_outlined,
                    color: SdColors.faint,
                  ),
                  const SizedBox(width: 6),
                  AppFilterChip(
                    label: 'تم التدقيق',
                    currentFilter: _followUpFilter,
                    onSelected: (v) => setState(() =>
                        _followUpFilter = _followUpFilter == v ? 'الكل' : v),
                    icon: Icons.verified_outlined,
                    color: SdColors.info,
                  ),
                  const SizedBox(width: 6),
                  AppFilterChip(
                    label: 'مشكلة',
                    currentFilter: _followUpFilter,
                    onSelected: (v) => setState(() =>
                        _followUpFilter = _followUpFilter == v ? 'الكل' : v),
                    icon: Icons.warning_amber_rounded,
                    color: SdColors.warning,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: SdEmptyState(
        icon: Icons.fact_check_outlined,
        title: 'لا توجد مهام للمتابعة',
        message: 'لم يتم العثور على مهام مكتملة أو ملغية',
      ),
    );
  }

  Widget _buildFollowUpCard(Task task) {
    final statusColor = TaskStatusColors.colorFor(task.status);
    final followUpState = _followUpStatus[task.id] ?? 'لم يتم';
    final rating = _ratings[task.id] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SdCard(
        padding: EdgeInsets.zero,
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
      ),
    );
  }

  Widget _buildCardHeader(Task task, Color statusColor, String followUpState) {
    Color followUpColor;
    IconData followUpIcon;
    switch (followUpState) {
      case 'تم التدقيق':
        followUpColor = SdColors.info;
        followUpIcon = Icons.verified_rounded;
        break;
      case 'مشكلة':
        followUpColor = SdColors.warning;
        followUpIcon = Icons.warning_rounded;
        break;
      default:
        followUpColor = SdColors.faint;
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
                    fontFamily: SdText.family,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: SdColors.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Text(
                      '${task.department} • #${task.id}',
                      style: const TextStyle(
                        fontFamily: SdText.family,
                        fontSize: 11.5,
                        color: SdColors.muted,
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
                Icon(followUpIcon, size: 13, color: followUpColor),
                const SizedBox(width: 3),
                Text(
                  followUpState,
                  style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 11.5,
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
          child: AppInfoTile(
            icon: Icons.person_outline_rounded,
            label: 'العميل',
            value: task.username,
            color: SdColors.info,
          ),
        ),
        const SizedBox(width: 6),
        // الفني
        Expanded(
          child: AppInfoTile(
            icon: Icons.engineering_rounded,
            label: 'الفني',
            value: task.technician,
            color: SdColors.accent,
          ),
        ),
        const SizedBox(width: 6),
        // المبلغ
        if (task.hasAmount)
          Expanded(
            child: AppInfoTile(
              icon: Icons.monetization_on_outlined,
              label: 'المبلغ',
              value: '${task.amountFormatted} د.ع',
              color: SdColors.danger,
            ),
          ),
      ],
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
      color: SdColors.info,
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
          color = SdGroup.platform.tone.base;
          label = 'المراجعة';
          break;
        case 'مفتوحة':
          icon = Icons.assignment_outlined;
          color = SdColors.info;
          label = 'التعيين';
          break;
        case 'قيد التنفيذ':
          icon = Icons.play_circle_outline_rounded;
          color = SdColors.warning;
          label = 'بدء التنفيذ';
          break;
        case 'مكتملة':
          icon = Icons.check_circle_outline_rounded;
          color = SdColors.success;
          label = 'الإكمال';
          break;
        case 'ملغية':
          icon = Icons.cancel_outlined;
          color = SdColors.danger;
          label = 'الإلغاء';
          break;
        default:
          icon = Icons.circle_outlined;
          color = SdColors.faint;
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
        color: SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SdColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان الجدول الزمني
          Row(
            children: [
              const Icon(Icons.timeline_rounded,
                  size: 14, color: SdColors.muted),
              const SizedBox(width: 4),
              const Text(
                'مراحل التنفيذ',
                style: TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: SdColors.muted,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: SdColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'المدة: $durationText',
                  style: const TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: SdColors.primary,
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
            fontFamily: SdText.family,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: stage.color,
          ),
        ),
        Text(
          DateFormat('MM/dd HH:mm').format(stage.time),
          style: const TextStyle(fontFamily: SdText.family, fontSize: 11.5, color: SdColors.muted),
        ),
        if (stage.by != null)
          Text(
            stage.by!,
            style: const TextStyle(fontFamily: SdText.family, fontSize: 11.5, color: SdColors.faint),
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
            style: const TextStyle(fontFamily: SdText.family, fontSize: 11.5, color: SdColors.faint),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingAndActions(Task task, int rating, String followUpState) {
    // لفّ العناصر بـ Wrap لمنع overflow على الشاشات الضيقة (360px):
    // النجوم + أزرار الاتصال في مجموعة، وأزرار التدقيق في مجموعة تنساب لسطر ثانٍ.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // مجموعة: التقييم بالنجوم + الاتصال
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // التقييم بالنجوم
              _buildStarRating(task, rating),

              // فاصل
              Container(width: 1, height: 28, color: SdColors.divider),

              // أزرار الاتصال
              if (task.phone.isNotEmpty)
                _buildActionBtn(
                  Icons.phone_rounded,
                  'العميل',
                  SdColors.success,
                  () => _makeCall(task.phone),
                ),
              if (task.agentName.isNotEmpty)
                _buildActionBtn(
                  Icons.person_pin_rounded,
                  'الوكيل',
                  SdGroup.platform.tone.base,
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
                  SdColors.whatsapp,
                  () => _launchWhatsApp(task.phone),
                ),
            ],
          ),

          // مجموعة: أزرار حالة التدقيق
          Wrap(
            spacing: 4,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildFollowUpBtn(
                task,
                'تم التدقيق',
                Icons.verified_rounded,
                SdColors.info,
                followUpState,
              ),
              _buildFollowUpBtn(
                task,
                'مشكلة',
                Icons.warning_rounded,
                SdColors.warning,
                followUpState,
              ),
            ],
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
                  ? SdColors.warning
                  : SdColors.divider,
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
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: SdText.family,
                fontSize: 11.5,
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
            Icon(icon, size: 14, color: isActive ? Colors.white : color),
            const SizedBox(width: 3),
            Text(
              status,
              style: TextStyle(
                fontFamily: SdText.family,
                fontSize: 11.5,
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
              Icon(Icons.warning_rounded, color: SdColors.warning, size: 20),
              SizedBox(width: 8),
              Text('تفاصيل المشكلة', style: TextStyle(fontFamily: SdText.family, fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'اكتب تفاصيل المشكلة...',
              hintStyle: const TextStyle(fontSize: 13, color: SdColors.faint),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
          actions: [
            SdButton(
              label: 'إلغاء',
              kind: SdButtonKind.secondary,
              onPressed: () => Navigator.pop(ctx),
            ),
            SdButton(
              label: 'حفظ',
              kind: SdButtonKind.accent,
              onPressed: () {
                setState(() {
                  _followUpNotes[task.id] = controller.text;
                });
                _saveAuditToServer(task.id);
                Navigator.pop(ctx);
              },
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
