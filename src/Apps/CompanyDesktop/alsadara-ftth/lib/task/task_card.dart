import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // إضافة للتحقق من النظام
import 'package:url_launcher/url_launcher.dart';
import '../models/task.dart';
import '../services/whatsapp_template_storage.dart';
import '../services/task_api_service.dart';
import 'task_attachments_widget.dart';
import '../widgets/maintenance_messages_dialog.dart';
import '../widgets/edit_task_dialog.dart';
import '../ftth/users/quick_search_users_page.dart';
import '../services/auth_service.dart';
import '../pages/kml_zones_map_page.dart';
import '../permissions/permission_manager.dart';
import '../services/dual_auth_service.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../inventory/services/inventory_api_service.dart';
import '../services/vps_auth_service.dart';
import '../utils/responsive_helper.dart';
import 'task_status_colors.dart';
import 'task_comments_section.dart';
import 'task_materials_dialog.dart';
import '../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)

/// تسجيل تشخيصي يعمل في وضع التطوير فقط، فلا تتسرّب السجلّات (أرقام هواتف/نتائج API)
/// إلى سجلّات أجهزة الإصدار (release). خلافاً لـ debugPrint الذي يطبع في كل الأوضاع.
void _devLog(String message) {
  if (kDebugMode) debugPrint(message);
}

/// TaskCard محسن مع عرض جميل لعنوان المهم�� وحل لجميع ����لأخطاء
class TaskCard extends StatefulWidget {
  final Task task;
  final String currentUserRole;
  final String currentUserName;
  final Function(Task) onStatusChanged;

  const TaskCard({
    super.key,
    required this.task,
    required this.currentUserRole,
    required this.currentUserName,
    required this.onStatusChanged,
  });

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  bool showDetails = false;

  // مؤقّت يحدّث عرض «المدة منذ الإنشاء» باستمرار (بدقّة الدقيقة)
  Timer? _ageTimer;

  // كاش تعليقات المهمة — يبقى حيّاً عبر طيّ/توسيع البطاقة (كسلوك الأصل قبل الاستخراج)،
  // فلا يُعاد الجلب من الـAPI عند إعادة التوسيع. null = لم يُحمَّل بعد.
  List<Map<String, dynamic>>? _commentsCache;

  // المواد المصروفة
  List<dynamic> _dispensedMaterials = [];
  bool _isLoadingMaterials = false;
  bool _materialsLoaded = false;

  // ═══════ الحالات المتاحة للمستخدم حسب الحالة الحالية ═══════
  /// الحصول على الحالات المسموح الانتقال إليها (يعرض فقط الحالات العملية)
  List<String> _getAvailableStatuses() {
    final current = widget.task.status;
    // جميع الحالات متاحة دائماً (يمكن التراجع عن أي حالة)
    return {current, 'مفتوحة', 'قيد التنفيذ', 'مكتملة', 'ملغية'}.toList();
  }

  @override
  void initState() {
    super.initState();
    // تحديث دوري كل دقيقة لإبقاء «المدة منذ الإنشاء» حيّة دون إعادة بناء مكلفة.
    _ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ageTimer?.cancel();
    super.dispose();
  }

  // هل المهمة من نوع تحصيل
  bool _isCollectionTask() =>
      widget.task.title.contains('تحصيل مبلغ') ||
      widget.task.title.contains('استحصال مبلغ');

  bool _isPurchaseTask() => widget.task.title.contains('شراء اشتراك');
  bool _isRenewalTask() => widget.task.title.contains('تجديد اشتراك');
  bool _isMaintenanceTask() =>
      !_isPurchaseTask() && !_isRenewalTask() && !_isCollectionTask();

  String _getAmountLabel() {
    if (_isPurchaseTask() || _isRenewalTask() || _isCollectionTask())
      return 'سعر الاشتراك';
    return 'أجور الصيانة';
  }

  String _getFeeLabel() {
    if (_isPurchaseTask()) return 'أجور التنصيب';
    if (_isRenewalTask()) return 'أجور أخرى';
    return 'أجور التوصيل';
  }

  // متغيرات لجلب بيانات الوكلاء
  List<Map<String, dynamic>> agents = [];
  bool isLoadingAgents = false;

  @override
  Widget build(BuildContext context) {
    final currentUserName = normalizeName(widget.currentUserName);
    final taskTechnician = normalizeName(widget.task.technician);

    final isTech = widget.currentUserRole == 'فني' ||
        widget.currentUserRole.toLowerCase() == 'technician';
    if (isTech && taskTechnician != currentUserName) {
      return const SizedBox.shrink();
    }

    final statusColor = _getStatusColor(widget.task.status);
    final isSmall = MediaQuery.of(context).size.width < 420;
    final isCollectionTask = widget.task.title.contains('تحصيل مبلغ') ||
        widget.task.title.contains('استحصال مبلغ');
    return Container(
      margin: EdgeInsets.symmetric(
          vertical: isSmall ? 3 : 5, horizontal: isSmall ? 4 : 12),
      decoration: BoxDecoration(
        color: isCollectionTask ? SdColors.warningTint : SdColors.surface,
        borderRadius: BorderRadius.circular(isSmall ? 12 : 16),
        // إطار بارز بلون حالة البطاقة ليبرز كل كرت على حدة (أخضر=مفتوحة…)
        border: Border.all(
          color: statusColor.withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: SdDepth.raised(
          edge: statusColor.withValues(alpha: 0.35),
          depth: SdDepth.small,
          glow: statusColor.withValues(alpha: 0.18),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isSmall ? 10 : 14),
        child: InkWell(
          onTap: () {
            setState(() {
              showDetails = !showDetails;
            });
            if (showDetails) {
              if (!_isCollectionTask() &&
                  !_materialsLoaded &&
                  !_isLoadingMaterials) _loadDispensedMaterials();
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الشريط العلوي الملون - Header
              _buildPremiumHeader(statusColor),

              // المعلومات الأساسية
              Padding(
                padding: EdgeInsets.fromLTRB(isSmall ? 8 : 14, isSmall ? 6 : 10,
                    isSmall ? 8 : 14, isSmall ? 3 : 6),
                child: _buildCompactBasicInfo(),
              ),

              if (showDetails) ...[
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: isSmall ? 8 : 14),
                  child: _buildCompactDetailedInfo(),
                ),
                // سجل الحالة
                if (widget.task.statusHistory.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: isSmall ? 8 : 14),
                    child: _buildStatusTimeline(),
                  ),
                // التعليقات — وحدة مستقلة (TaskCommentsSection) تملك حالتها
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      isSmall ? 8 : 14, 4, isSmall ? 8 : 14, 6),
                  child: TaskCommentsSection(
                    taskId: widget.task.guid.isNotEmpty
                        ? widget.task.guid
                        : widget.task.id,
                    initialComments: _commentsCache,
                    onCommentsLoaded: (list) => _commentsCache = list,
                  ),
                ),
                // المواد المصروفة — تظهر في كل المهام ما عدا التحصيل
                if (!_isCollectionTask())
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        isSmall ? 8 : 14, 4, isSmall ? 8 : 14, 6),
                    child: _buildDispensedMaterialsSection(),
                  ),
                // المرفقات
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      isSmall ? 8 : 14, 4, isSmall ? 8 : 14, 6),
                  child: TaskAttachmentsWidget(
                    taskId: widget.task.guid.isNotEmpty
                        ? widget.task.guid
                        : widget.task.id,
                  ),
                ),
              ],

              Divider(height: 1, color: SdColors.divider),

              Padding(
                padding: EdgeInsets.fromLTRB(isSmall ? 4 : 8, isSmall ? 2 : 4,
                    isSmall ? 4 : 8, isSmall ? 3 : 6),
                child: _buildCompactActionBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// عنوان فخم مع شريط ملون
  Widget _buildPremiumHeader(Color statusColor) {
    final isSmall = MediaQuery.of(context).size.width < 420;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isSmall ? 8 : 14, vertical: isSmall ? 6 : 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            statusColor.withValues(alpha: 0.12),
            statusColor.withValues(alpha: 0.04),
          ],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        border: Border(
          bottom: BorderSide(
            color: statusColor.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // أيقونة الأولوية في دائرة
          Container(
            width: isSmall ? 24 : 32,
            height: isSmall ? 24 : 32,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(isSmall ? 6 : 8),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              _isCollectionTask()
                  ? Icons.attach_money
                  : _getPriorityIcon(widget.task.priority),
              color: Colors.white,
              size: 16,
            ),
          ),
          SizedBox(width: isSmall ? 6 : 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // نوع المهمة — سطر مستقل يُقصّ بـ ellipsis
                Text(
                  widget.task.title.isNotEmpty
                      ? widget.task.title
                      : 'مهمة غير محددة',
                  style: TextStyle(
                    fontSize: isSmall ? 12 : 15,
                    fontWeight: FontWeight.w700,
                    color: SdColors.ink,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                // القسم ورقم المهمة — يُقصّ بـ ellipsis فلا يتجاوز
                Text(
                  '${widget.task.department} • #${widget.task.id}',
                  style: TextStyle(
                    fontSize: isSmall ? 11 : 12,
                    color: SdColors.muted,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                // الشارات (أجور التوصيل/التحصيل + SLA + الحالة) تلتفّ لسطر ثانٍ
                // على الهاتف الضيّق بدل التجاوز الأفقي.
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_isCollectionTask() && widget.task.hasAmount)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: SdColors.warning,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${widget.task.amountFormatted} د.ع',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ),
                    if (!_isMaintenanceTask() && widget.task.hasDeliveryFee)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: SdColors.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_getFeeLabel()} ${widget.task.deliveryFeeFormatted} د.ع',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ),
                    // مؤشر عمر التذكرة (المدة المنقضية منذ الإنشاء)
                    if (!widget.task.isCompleted && !widget.task.isCancelled)
                      _buildAgeIndicator(),
                    // حالة المهمة
                    _buildCompactStatusBadge(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// مؤشر عمر التذكرة — المدة المنقضية منذ الإنشاء (كم مضى عليها)
  Widget _buildAgeIndicator() {
    final elapsed = widget.task.ageSinceCreated;
    if (elapsed.isNegative) return const SizedBox.shrink();

    // اللون: إن وُجد SLA نعكس حالته (أخضر/أصفر/أحمر)، وإلا لون محايد.
    final Color color;
    if (widget.task.hasSla) {
      switch (widget.task.slaStatus) {
        case 'overdue':
          color = SdColors.danger;
          break;
        case 'warning':
          color = SdColors.warning;
          break;
        default:
          color = SdColors.success;
      }
    } else {
      color = SdColors.info;
    }

    // تنسيق المدة المنقضية منذ الإنشاء
    final String timeText;
    final totalMinutes = elapsed.inMinutes;
    if (totalMinutes < 1) {
      timeText = 'الآن';
    } else if (totalMinutes < 60) {
      timeText = '$totalMinutesد';
    } else if (totalMinutes < 1440) {
      final h = totalMinutes ~/ 60;
      final m = totalMinutes % 60;
      timeText = m > 0 ? '$hس $mد' : '$hس';
    } else {
      final d = totalMinutes ~/ 1440;
      final h = (totalMinutes % 1440) ~/ 60;
      timeText = h > 0 ? '$dي $hس' : '$dي';
    }

    return Tooltip(
      message: 'مضى على الإنشاء $timeText',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 13, color: color),
            const SizedBox(width: 3),
            Text(
              timeText,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }

  /// حالة مضغوطة فخمة
  Widget _buildCompactStatusBadge() {
    final statusColor = _getStatusColor(widget.task.status);
    return GestureDetector(
      onTap: () => _showStatusChangeDialog(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: statusColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.5),
                    blurRadius: 3,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            Text(
              widget.task.status,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// المعلومات الأساسية في تخطيط شبكي أنيق
  Widget _buildCompactBasicInfo() {
    final w = MediaQuery.of(context).size.width;
    final compact = w < 500;
    final isMobile = w < 420;
    final gap = isMobile ? 3.0 : (compact ? 6.0 : 8.0);
    final vGap = isMobile ? 3.0 : (compact ? 5.0 : 6.0);
    final cols = isMobile ? 2 : 3; // حقلين على الهاتف، 3 على الديسكتوب

    final tiles = <Widget>[
      _buildInfoTile(Icons.person_outline_rounded, 'العميل',
          widget.task.username, SdColors.info,
          compact: compact),
      _buildInfoTile(Icons.engineering_outlined, 'الفني',
          widget.task.technician, SdColors.accent,
          compact: compact,
          trailing: widget.task.technician.isNotEmpty &&
                  widget.task.technician != 'غير متوفر'
              ? _buildMiniIconButton(
                  Icons.send_rounded,
                  SdColors.accent,
                  () => _sendTaskToTechnician(widget.task.technician))
              : null),
      _buildInfoTile(
          Icons.hub_outlined, 'FBG', widget.task.fbg, SdColors.success,
          compact: compact),
      _buildInfoTile(Icons.phone_outlined, 'الهاتف', widget.task.phone,
          SdColors.platformBase,
          compact: compact,
          trailing: widget.task.phone.isNotEmpty
              ? _buildMiniIconButton(
                  Icons.copy_rounded,
                  SdColors.platformBase,
                  () => _copyPhoneNumber(widget.task.phone))
              : null),
      if (widget.task.agentName.isNotEmpty)
        _buildInfoTile(
            Icons.storefront_outlined,
            'الوكيل',
            '${widget.task.agentName}${widget.task.pageId.isNotEmpty ? ' - ${widget.task.pageId}' : ''}',
            SdColors.primaryLight,
            compact: compact,
            trailing: widget.task.pageId.isNotEmpty
                ? _buildMiniIconButton(
                    Icons.copy_rounded, SdColors.primaryLight, () {
                    Clipboard.setData(ClipboardData(text: widget.task.pageId));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('تم نسخ: ${widget.task.pageId}'),
                        duration: const Duration(seconds: 2)));
                  })
                : null),
      if (widget.task.hasAmount)
        _buildInfoTile(Icons.payments_outlined, _getAmountLabel(),
            '${widget.task.amountFormatted} د.ع', SdColors.danger,
            compact: compact),
      if (widget.task.hasDeliveryFee && !_isMaintenanceTask())
        _buildInfoTile(Icons.local_shipping, _getFeeLabel(),
            '${widget.task.deliveryFeeFormatted} د.ع', SdColors.accent,
            compact: compact),
      if (widget.task.createdByName.isNotEmpty)
        _buildInfoTile(Icons.person_add_outlined, 'أنشأها',
            widget.task.createdByName, SdColors.infoLight,
            compact: compact),
      if (widget.task.serviceType.isNotEmpty)
        _buildInfoTile(Icons.speed_outlined, 'الخدمة',
            '${widget.task.serviceType} Mbps', SdColors.warning,
            compact: compact),
      if (widget.task.subscriptionDuration.isNotEmpty)
        _buildInfoTile(Icons.timer_outlined, 'المدة',
            widget.task.subscriptionDuration, SdColors.accent,
            compact: compact),
    ];

    // بناء الصفوف ديناميكياً حسب عدد الأعمدة
    final rows = <Widget>[];
    for (int i = 0; i < tiles.length; i += cols) {
      final rowChildren = <Widget>[];
      for (int j = i; j < i + cols && j < tiles.length; j++) {
        if (rowChildren.isNotEmpty) rowChildren.add(SizedBox(width: gap));
        rowChildren.add(Expanded(child: tiles[j]));
      }
      // إذا الصف ناقص عمود — أضف فراغ
      if (rowChildren.length < cols * 2 - 1) {
        rowChildren.add(SizedBox(width: gap));
        rowChildren.add(const Expanded(child: SizedBox.shrink()));
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: vGap));
      rows.add(Row(children: rowChildren));
    }

    return Column(children: rows);
  }

  /// خلية معلومات أنيقة مع عنوان وقيمة
  Widget _buildInfoTile(IconData icon, String label, String value, Color color,
      {Widget? trailing, bool compact = false}) {
    final isSmall = MediaQuery.of(context).size.width < 420;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 4 : (compact ? 6 : 10),
        vertical: isSmall ? 3 : (compact ? 5 : 7),
      ),
      decoration: BoxDecoration(
        color: SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SdRadius.xs),
        border: Border.all(color: SdColors.divider, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 3 : 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: compact ? 11 : 14, color: color),
          ),
          SizedBox(width: compact ? 4 : 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: compact ? 9 : 10,
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: compact ? 1 : 2),
                Text(
                  value.isNotEmpty ? value : '-',
                  style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: compact ? 12 : 14,
                    color: SdColors.ink,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  /// أيقونة صغيرة أنيقة — توسيع منطقة اللمس أفقياً ≥44px دون تكبير الأيقونة.
  /// ملاحظة: هذه الأيقونة تُستخدم كـ trailing داخل بطاقات info مضغوطة، لذا لا
  /// نفرض minHeight:44 حتى لا يتضخّم ارتفاع البطاقة؛ نكتفي بمنطقة لمس أفقية مريحة
  /// مع padding رأسي بسيط.
  Widget _buildMiniIconButton(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(icon, size: 13, color: color),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactDetailedInfo() {
    final statusColor = _getStatusColor(widget.task.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SdRadius.sm),
        border: Border.all(color: SdColors.divider, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان صغير
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(Icons.info_outline_rounded,
                    size: 12, color: statusColor),
              ),
              const SizedBox(width: 6),
              Text(
                'التفاصيل',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // صف التفاصيل الأول
          Row(
            children: [
              Expanded(
                child: _buildCompactDetailItem(Icons.location_on_outlined,
                    'الموقع', widget.task.location, SdColors.info),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactDetailItem(Icons.cable_outlined, 'FAT',
                    widget.task.fat, SdColors.success),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // صف التفاصيل الثاني
          Row(
            children: [
              Expanded(
                child: _buildCompactDetailItem(Icons.flag_outlined, 'الأولوية',
                    widget.task.priority, SdColors.warning),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactDetailItem(
                    Icons.calendar_today_rounded,
                    'الإنشاء',
                    DateFormat('MM/dd').format(widget.task.createdAt),
                    SdColors.platformBase),
              ),
            ],
          ),

          // الملاحظات والملخص
          if (widget.task.notes.isNotEmpty ||
              widget.task.summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            if (widget.task.notes.isNotEmpty)
              _buildExpandableText('ملاحظات', widget.task.notes),
            if (widget.task.summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              _buildExpandableText('الملخص', widget.task.summary),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCompactDetailItem(
      IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SdRadius.xs),
        border: Border.all(color: SdColors.divider, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(icon, size: 12, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isNotEmpty ? value : '-',
                  style: const TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 13,
                    color: SdColors.ink,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
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

  Widget _buildExpandableText(String label, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SdColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notes_rounded, size: 13, color: SdColors.faint),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: SdColors.faint,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 11,
                    color: SdColors.ink,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════ سجل الحالة (Timeline) ═══════

  Widget _buildStatusTimeline() {
    final history = widget.task.statusHistory;
    if (history.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SdColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SdColors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: SdColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Icon(Icons.timeline_rounded,
                    size: 14, color: SdColors.primary),
              ),
              const SizedBox(width: 6),
              const Text('سجل الحالة',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: SdColors.primary)),
              const Spacer(),
              Text('${history.length} تغيير',
                  style: TextStyle(fontSize: 11, color: SdColors.faint)),
            ],
          ),
          const SizedBox(height: 8),
          ...history.reversed.take(5).map((h) {
            final statusColor = _getStatusColor(h.toStatus);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: statusColor, shape: BoxShape.circle),
                      ),
                      Container(
                          width: 2, height: 20, color: SdColors.edge),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(h.fromStatus,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: SdColors.muted,
                                    decoration: TextDecoration.lineThrough)),
                            const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(Icons.arrow_forward,
                                    size: 12, color: SdColors.faint)),
                            Text(h.toStatus,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor)),
                          ],
                        ),
                        Row(
                          children: [
                            if (h.changedBy.isNotEmpty)
                              Text(h.changedBy,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: SdColors.faint)),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('MM/dd HH:mm').format(h.changedAt),
                              style: TextStyle(
                                  fontSize: 11, color: SdColors.faint),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          if (history.length > 5)
            Center(
              child: Text('+ ${history.length - 5} تغييرات أخرى',
                  style: TextStyle(fontSize: 11, color: SdColors.faint)),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  المواد المصروفة — عرض المواد المرتبطة بالمهمة
  // ═══════════════════════════════════════════════════════════

  Future<void> _loadDispensedMaterials() async {
    if (_isLoadingMaterials) return;
    setState(() => _isLoadingMaterials = true);
    try {
      final taskGuid = widget.task.guid;
      if (taskGuid.isEmpty) {
        setState(() {
          _dispensedMaterials = [];
          _materialsLoaded = true;
          _isLoadingMaterials = false;
        });
        return;
      }
      // نجلب الشركة من VpsAuthService
      final companyId = VpsAuthService.instance.currentCompanyId ?? '';
      final result =
          await InventoryApiService.instance.getDispensingsByServiceRequest(
        taskGuid,
        companyId: companyId,
      );
      if (!mounted) return;
      final dispensings = (result['data'] as List<dynamic>?) ?? [];
      // نستخلص كل المواد من كل سند صرف
      final allItems = <Map<String, dynamic>>[];
      for (final d in dispensings) {
        // الباكند يُرجع المفاتيح بصيغة PascalCase (Items/ItemName/Quantity…)
        // بينما كود قديم يستخدم camelCase — نقرأ الحالتين دفاعياً (كما في باقي التطبيق).
        final items =
            (d['Items'] ?? d['items']) as List<dynamic>? ?? const [];
        for (final item in items) {
          allItems.add({
            'itemName': item['ItemName'] ??
                item['itemName'] ??
                item['inventoryItemName'] ??
                'مادة',
            'itemSku': item['ItemSku'] ?? item['itemSku'] ?? item['sku'] ?? '',
            'quantity': item['Quantity'] ?? item['quantity'] ?? 0,
            'returnedQuantity':
                item['ReturnedQuantity'] ?? item['returnedQuantity'] ?? 0,
            'voucherNumber': d['VoucherNumber'] ?? d['voucherNumber'] ?? '',
            'status': d['Status'] ?? d['status'] ?? '',
            'technicianName': d['TechnicianName'] ?? d['technicianName'] ?? '',
            'dispensingDate': d['DispensingDate'] ?? d['dispensingDate'] ?? '',
          });
        }
      }
      setState(() {
        _dispensedMaterials = allItems;
        _materialsLoaded = true;
        _isLoadingMaterials = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _dispensedMaterials = [];
          _materialsLoaded = true;
          _isLoadingMaterials = false;
        });
      }
    }
  }

  Widget _buildDispensedMaterialsSection() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SdColors.warning.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SdColors.warning.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: SdColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Icon(Icons.inventory_2_outlined,
                    size: 14, color: SdColors.warning),
              ),
              const SizedBox(width: 6),
              const Text('المواد المصروفة',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: SdColors.warning)),
              const Spacer(),
              if (_dispensedMaterials.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: SdColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${_dispensedMaterials.length}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: SdColors.warning,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              // بعد صرف مواد: يتحوّل زر «إضافة» البرتقالي إلى شارة خضراء «تم الصرف»
              // (تبقى قابلة للنقر لإضافة مزيد عند الحاجة). قبل الصرف: زر إضافة برتقالي.
              GestureDetector(
                onTap: _showAddMaterialsDialog,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _dispensedMaterials.isNotEmpty
                        ? SdColors.success
                        : SdColors.warning,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          _dispensedMaterials.isNotEmpty
                              ? Icons.check_circle_outline
                              : Icons.add,
                          size: 13,
                          color: Colors.white),
                      const SizedBox(width: 2),
                      Text(
                          _dispensedMaterials.isNotEmpty
                              ? 'تم الصرف'
                              : 'إضافة',
                          style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // القائمة
          if (_isLoadingMaterials)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: SdColors.warning))))
          else if (_dispensedMaterials.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('لا توجد مواد مصروفة',
                  style: TextStyle(fontSize: 12, color: SdColors.faint)),
            )
          else
            ..._dispensedMaterials.map((m) => _buildMaterialItem(m)),
        ],
      ),
    );
  }

  Widget _buildMaterialItem(dynamic material) {
    final name = material['itemName']?.toString() ?? '';
    final sku = material['itemSku']?.toString() ?? '';
    final qty = material['quantity'] ?? 0;
    final returned = material['returnedQuantity'] ?? 0;
    final net = (qty is int ? qty : 0) - (returned is int ? returned : 0);
    final voucher = material['voucherNumber']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SdColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: SdColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.build_circle_outlined,
                size: 16, color: SdColors.warning),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: SdColors.ink)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SdColors.warningTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$net',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: SdColors.warning)),
              ),
              if (returned > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('مرجع: $returned',
                      style: TextStyle(
                          fontSize: 10, color: SdColors.success)),
                ),
            ],
          ),
          if (voucher.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(voucher,
                  style: TextStyle(fontSize: 10, color: SdColors.faint)),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  نافذة إضافة مواد مصروفة مباشرة من بطاقة المهمة
  // ═══════════════════════════════════════════════════════════

  Future<void> _showAddMaterialsDialog() async {
    final saved = await showDispenseMaterialsDialog(
      context,
      companyId: VpsAuthService.instance.currentCompanyId ?? '',
      taskGuid: widget.task.guid,
      techId: widget.task.technicianId,
    );
    if (saved && mounted) {
      _materialsLoaded = false;
      _loadDispensedMaterials();
    }
  }

  /// شريط الإجراءات — على الموبايل: أزرار رئيسية + قائمة منبثقة
  Widget _buildCompactActionBar() {
    final isMobile = context.responsive.isMobile;

    // الأزرار الرئيسية (تظهر دائماً)
    final primaryButtons = <Widget>[];
    if (widget.task.phone.isNotEmpty || widget.task.username.isNotEmpty) {
      primaryButtons.add(_buildCompactActionButton(
        Icons.open_in_new_rounded,
        'تفاصيل',
        SdColors.info,
        _openSubscriptionDetails,
      ));
    }
    if (widget.task.phone.isNotEmpty) {
      primaryButtons.add(_buildCompactActionButton(
        Icons.message_rounded,
        'واتساب',
        SdColors.whatsapp,
        () => _launchWhatsApp(widget.task.phone),
      ));
    }
    if (widget.task.fbg.isNotEmpty || widget.task.fat.isNotEmpty) {
      primaryButtons.add(_buildCompactActionButton(
        Icons.map_rounded,
        'خريطة',
        SdColors.accent,
        _openZonesMap,
      ));
    }

    // الأزرار الثانوية (popup menu على الموبايل)
    final menuItems = <PopupMenuEntry<String>>[];
    if (widget.currentUserRole == 'ليدر' || widget.currentUserRole == 'مدير') {
      menuItems.add(const PopupMenuItem(
          value: 'agent',
          child: Row(children: [
            Icon(Icons.group_rounded, size: 18, color: SdColors.platformBase),
            SizedBox(width: 8),
            Text('وكيل'),
          ])));
    }
    if (widget.currentUserRole == 'مدير' || widget.currentUserRole == 'ليدر') {
      menuItems.add(const PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_rounded, size: 18, color: SdColors.info),
            SizedBox(width: 8),
            Text('تعديل'),
          ])));
    }
    if (widget.currentUserRole == 'مدير') {
      menuItems.add(const PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline_rounded,
                size: 18, color: SdColors.danger),
            SizedBox(width: 8),
            Text('حذف'),
          ])));
    }
    // زر التفعيل في القائمة المنبثقة (موبايل)
    if (widget.task.isCompleted &&
        !widget.task.notes.contains('[مفعّل]') &&
        (widget.currentUserRole == 'مدير' ||
            widget.currentUserRole == 'ليدر')) {
      menuItems.add(const PopupMenuItem(
          value: 'activate',
          child: Row(children: [
            Icon(Icons.verified_rounded, size: 18, color: SdColors.success),
            SizedBox(width: 8),
            Text('تفعيل'),
          ])));
    }

    if (primaryButtons.isEmpty && menuItems.isEmpty)
      return const SizedBox.shrink();

    // على الموبايل: أزرار رئيسية + قائمة منبثقة
    if (isMobile && menuItems.isNotEmpty) {
      return Row(
        children: [
          ...primaryButtons,
          if (menuItems.isNotEmpty)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                child: PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'agent':
                        _showAgentsDialog();
                        break;
                      case 'edit':
                        _showEditTaskDialog();
                        break;
                      case 'delete':
                        _confirmDeleteTask();
                        break;
                      case 'activate':
                        _markAsActivated();
                        break;
                    }
                  },
                  itemBuilder: (_) => menuItems,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: SdColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(SdRadius.xs),
                      border: Border.all(color: SdColors.divider, width: 1),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.more_horiz, size: 18, color: SdColors.muted),
                        SizedBox(width: 4),
                        Text('المزيد',
                            style: TextStyle(
                                fontFamily: SdText.family,
                                fontSize: 11.5,
                                color: SdColors.muted,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    // على الديسكتوب: كل الأزرار في صف واحد
    final allButtons = [...primaryButtons];
    if (widget.currentUserRole == 'ليدر' || widget.currentUserRole == 'مدير') {
      allButtons.add(_buildCompactActionButton(Icons.group_rounded, 'وكيل',
          SdGroup.platform.tone.base, _showAgentsDialog));
    }
    if (widget.currentUserRole == 'مدير' || widget.currentUserRole == 'ليدر') {
      allButtons.add(_buildCompactActionButton(Icons.edit_rounded, 'تعديل',
          SdColors.primary, _showEditTaskDialog));
    }
    if (widget.currentUserRole == 'مدير') {
      allButtons.add(_buildCompactActionButton(Icons.delete_outline_rounded,
          'حذف', SdColors.danger, _confirmDeleteTask));
    }
    // زر تفعيل — يظهر فقط للمهام المكتملة غير المفعّلة (ليدر أو مدير)
    if (widget.task.isCompleted &&
        !widget.task.notes.contains('[مفعّل]') &&
        (widget.currentUserRole == 'مدير' ||
            widget.currentUserRole == 'ليدر')) {
      allButtons.add(_buildCompactActionButton(
        Icons.verified_rounded,
        'تفعيل',
        SdColors.success,
        _markAsActivated,
      ));
    }
    return Row(children: allButtons);
  }

  Widget _buildCompactActionButton(
      IconData icon, String label, Color color, VoidCallback onPressed) {
    final isNarrow = context.responsive.availableWidth < 360;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(SdRadius.xs),
          border: Border.all(color: color.withValues(alpha: 0.32), width: 1),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(SdRadius.xs),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: isNarrow
                  ? Icon(icon, size: 18, color: color)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 16, color: color),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontFamily: SdText.family,
                              fontSize: 11.5,
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// الحصول على أيقونة الأولوية
  /// تنسيق المبلغ بفواصل المراتب (5225 → 5,225)
  String _formatAmount(String amount) {
    // إزالة الجزء العشري أولاً (60000.0 → 60000) ثم استخراج الأرقام
    final wholePart = amount.contains('.') ? amount.split('.').first : amount;
    final digits = wholePart.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return amount;
    final buffer = StringBuffer();
    final len = digits.length;
    for (int i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  IconData _getPriorityIcon(String priority) {
    switch (priority) {
      case 'عاجل':
        return Icons.emergency;
      case 'عالي':
        return Icons.priority_high;
      case 'متوسط':
        return Icons.remove;
      case 'منخفض':
        return Icons.low_priority;
      default:
        return Icons.assignment;
    }
  }

  Widget _buildNoTasksMessage() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'لا توجد مهام متاحة لهذا المستخدم',
          style: TextStyle(
            fontSize: 16,
            color: SdColors.faint,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _showStatusChangeDialog() {
    final availableStatuses = _getAvailableStatuses();

    // إذا كانت حالة نهائية (لا يوجد انتقالات مسموحة)
    if (availableStatuses.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'لا يمكن تغيير الحالة - "${widget.task.status}" حالة نهائية'),
          backgroundColor: SdColors.warning,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    String selectedStatus = widget.task.status;
    // تنسيق المبلغ المبدئي بفواصل المراتب
    String initialAmount = widget.task.amount?.toInt().toString() ?? '';
    if (initialAmount.isNotEmpty) {
      final digits = initialAmount.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.isNotEmpty) {
        final buf = StringBuffer();
        for (int i = 0; i < digits.length; i++) {
          if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
          buf.write(digits[i]);
        }
        initialAmount = buf.toString();
      }
    }
    // تنسيق أجور التوصيل المبدئية بفواصل المراتب
    String initialDeliveryFee =
        widget.task.deliveryFee?.toInt().toString() ?? '';
    if (initialDeliveryFee.isEmpty) {
      initialDeliveryFee = '1,000';
    } else {
      final digits = initialDeliveryFee.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.isNotEmpty) {
        final buf = StringBuffer();
        for (int i = 0; i < digits.length; i++) {
          if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
          buf.write(digits[i]);
        }
        initialDeliveryFee = buf.toString();
      }
    }
    final TextEditingController amountController =
        TextEditingController(text: initialAmount);
    final TextEditingController deliveryFeeController =
        TextEditingController(text: initialDeliveryFee);
    final TextEditingController notesController =
        TextEditingController(text: widget.task.notes);
    bool controllersDisposed = false;
    void disposeControllers() {
      if (controllersDisposed) return;
      controllersDisposed = true;
      amountController.dispose();
      deliveryFeeController.dispose();
      notesController.dispose();
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final statusColor = _getStatusColor(selectedStatus);
            final dialogWidth = MediaQuery.of(context).size.width;
            return Dialog(
              insetPadding: EdgeInsets.symmetric(
                  horizontal: context.responsive.isMobile ? 12 : 40,
                  vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 8,
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: context.responsive.dialogMaxWidth),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Header ──
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                              colors: [SdColors.primary, SdColors.primaryMid]),
                          borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20)),
                        ),
                        child: Row(
                          children: [
                            const Spacer(),
                            const Text('تغيير حالة المهمة',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                            const SizedBox(width: 8),
                            const Icon(Icons.edit_note_rounded,
                                color: Colors.white70, size: 22),
                          ],
                        ),
                      ),

                      // ── Body ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // 1. حالة المهمة
                            Text('حالة المهمة',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: SdColors.muted)),
                            const SizedBox(height: 6),
                            Container(
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: statusColor.withValues(alpha: 0.4)),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 2),
                              child: DropdownButton<String>(
                                value: selectedStatus,
                                isExpanded: true,
                                underline: const SizedBox.shrink(),
                                icon: Icon(Icons.keyboard_arrow_down_rounded,
                                    color: statusColor, size: 24),
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                    fontFamily: 'Cairo'),
                                items: _getAvailableStatuses().map((status) {
                                  final c = _getStatusColor(status);
                                  return DropdownMenuItem(
                                    value: status,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text(status,
                                            style: TextStyle(
                                                color: c,
                                                fontWeight: FontWeight.w600)),
                                        const SizedBox(width: 8),
                                        Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                                color: c,
                                                shape: BoxShape.circle)),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setDialogState(() {
                                    selectedStatus =
                                        value ?? widget.task.status;
                                  });
                                },
                              ),
                            ),

                            const SizedBox(height: 16),

                            // 2. المبلغ — الاسم يتغير حسب نوع المهمة
                            Text(_getAmountLabel(),
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: SdColors.muted)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: amountController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.left,
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                              inputFormatters: [
                                TextInputFormatter.withFunction(
                                    (oldValue, newValue) {
                                  // تحويل الأرقام العربية
                                  String converted = newValue.text
                                      .replaceAll('٠', '0')
                                      .replaceAll('١', '1')
                                      .replaceAll('٢', '2')
                                      .replaceAll('٣', '3')
                                      .replaceAll('٤', '4')
                                      .replaceAll('٥', '5')
                                      .replaceAll('٦', '6')
                                      .replaceAll('٧', '7')
                                      .replaceAll('٨', '8')
                                      .replaceAll('٩', '9');
                                  // إزالة كل شيء ماعدا الأرقام
                                  final digits = converted.replaceAll(
                                      RegExp(r'[^\d]'), '');
                                  if (digits.isEmpty) {
                                    return const TextEditingValue(
                                        text: '',
                                        selection:
                                            TextSelection.collapsed(offset: 0));
                                  }
                                  // إضافة فواصل المراتب
                                  final buffer = StringBuffer();
                                  final len = digits.length;
                                  for (int i = 0; i < len; i++) {
                                    if (i > 0 && (len - i) % 3 == 0)
                                      buffer.write(',');
                                    buffer.write(digits[i]);
                                  }
                                  final formatted = buffer.toString();
                                  return TextEditingValue(
                                      text: formatted,
                                      selection: TextSelection.collapsed(
                                          offset: formatted.length));
                                }),
                              ],
                              decoration: InputDecoration(
                                hintText: '0',
                                hintStyle:
                                    TextStyle(color: SdColors.faint),
                                filled: true,
                                fillColor: SdColors.surfaceAlt,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                prefixIcon: Container(
                                  width: 36,
                                  alignment: Alignment.center,
                                  child: Text('\$',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: SdColors.success)),
                                ),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: SdColors.edge)),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: SdColors.edge)),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: SdColors.success,
                                        width: 1.5)),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // 2.5 حقل الأجور الثاني — يتغير حسب نوع المهمة (يختفي في الصيانة)
                            if (!_isMaintenanceTask()) ...[
                              Text(_getFeeLabel(),
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: SdColors.muted)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: deliveryFeeController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.left,
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600),
                                inputFormatters: [
                                  TextInputFormatter.withFunction(
                                      (oldValue, newValue) {
                                    String converted = newValue.text
                                        .replaceAll('٠', '0')
                                        .replaceAll('١', '1')
                                        .replaceAll('٢', '2')
                                        .replaceAll('٣', '3')
                                        .replaceAll('٤', '4')
                                        .replaceAll('٥', '5')
                                        .replaceAll('٦', '6')
                                        .replaceAll('٧', '7')
                                        .replaceAll('٨', '8')
                                        .replaceAll('٩', '9');
                                    final digits = converted.replaceAll(
                                        RegExp(r'[^\d]'), '');
                                    if (digits.isEmpty) {
                                      return const TextEditingValue(
                                          text: '',
                                          selection: TextSelection.collapsed(
                                              offset: 0));
                                    }
                                    final buffer = StringBuffer();
                                    final len = digits.length;
                                    for (int i = 0; i < len; i++) {
                                      if (i > 0 && (len - i) % 3 == 0)
                                        buffer.write(',');
                                      buffer.write(digits[i]);
                                    }
                                    final formatted = buffer.toString();
                                    return TextEditingValue(
                                        text: formatted,
                                        selection: TextSelection.collapsed(
                                            offset: formatted.length));
                                  }),
                                ],
                                decoration: InputDecoration(
                                  hintText: '0',
                                  hintStyle:
                                      TextStyle(color: SdColors.faint),
                                  filled: true,
                                  fillColor: SdColors.surfaceAlt,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  prefixIcon: Container(
                                    width: 36,
                                    alignment: Alignment.center,
                                    child: Icon(Icons.local_shipping,
                                        size: 18, color: SdColors.accent),
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(Icons.close_rounded,
                                        size: 18, color: SdColors.danger),
                                    tooltip: 'بدون أجور توصيل',
                                    onPressed: () {
                                      deliveryFeeController.clear();
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: SdColors.edge)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: SdColors.edge)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: SdColors.accentLight,
                                          width: 1.5)),
                                ),
                              ),
                            ],

                            const SizedBox(height: 16),

                            // 3. ملاحظات (إجباري عند الإلغاء)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (selectedStatus == 'ملغية')
                                  Text(' * مطلوب',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: SdColors.danger,
                                          fontWeight: FontWeight.w600)),
                                const SizedBox(width: 4),
                                Text(
                                    selectedStatus == 'ملغية'
                                        ? 'سبب الإلغاء'
                                        : 'ملاحظات الفني',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: selectedStatus == 'ملغية'
                                            ? SdColors.danger
                                            : SdColors.muted)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: notesController,
                              maxLines: 3,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                hintText: selectedStatus == 'ملغية'
                                    ? 'اكتب سبب الإلغاء...'
                                    : 'ملاحظات إضافية (اختياري)',
                                hintStyle: TextStyle(
                                    color: selectedStatus == 'ملغية'
                                        ? SdColors.dangerTintEdge
                                        : SdColors.faint,
                                    fontSize: 13),
                                filled: true,
                                fillColor: SdColors.surfaceAlt,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: SdColors.edge)),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: selectedStatus == 'ملغية'
                                            ? SdColors.dangerTintEdge
                                            : SdColors.edge)),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: selectedStatus == 'ملغية'
                                            ? SdColors.danger
                                            : SdColors.warning,
                                        width: 1.5)),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Buttons ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  disposeControllers();
                                  Navigator.of(dialogContext).pop();
                                },
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  side: BorderSide(color: SdColors.faint),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text('إلغاء',
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: SdColors.muted,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  final String newStatus = selectedStatus;
                                  final String amount =
                                      amountController.text.trim();
                                  final String notes =
                                      notesController.text.trim();

                                  // التحقق: سبب الإلغاء إجباري
                                  if (newStatus == 'ملغية' && notes.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('يجب كتابة سبب الإلغاء'),
                                        backgroundColor: SdColors.danger,
                                      ),
                                    );
                                    return;
                                  }

                                  // التحقق: المبلغ إذا أُدخل يجب أن يكون 1000 على الأقل
                                  final digits =
                                      amount.replaceAll(RegExp(r'[^\d]'), '');
                                  if (digits.isNotEmpty && digits.length < 4) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'المبلغ يجب أن يكون 1,000 على الأقل'),
                                        backgroundColor: SdColors.warning,
                                      ),
                                    );
                                    return;
                                  }

                                  final String deliveryFee =
                                      deliveryFeeController.text.trim();

                                  disposeControllers();
                                  Navigator.of(dialogContext).pop();

                                  _updateTaskStatus(newStatus,
                                      amount: double.tryParse(
                                          amount.replaceAll(',', '')),
                                      notes: notes,
                                      deliveryFee: double.tryParse(
                                          deliveryFee.replaceAll(',', '')));
                                },
                                icon: const Icon(Icons.check_rounded, size: 20),
                                label: const Text('تحديث المهمة',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  backgroundColor: SdColors.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
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
            );
          },
        );
      },
    ).then((_) => disposeControllers()); // تنظيف عند إغلاق الـ dialog بأي طريقة
  }

  /// هل المهمة تتطلب ذكر المواد المصروفة؟ (كل المهام ما عدا التحصيل والتجديد)
  bool _requiresMaterials() {
    return !_isCollectionTask() && !_isRenewalTask();
  }

  void _updateTaskStatus(String newStatus,
      {double? amount, String notes = '', double? deliveryFee}) async {
    // ── التحقق من المواد المصروفة عند إكمال مهمة صيانة/تنصيب ──
    if (newStatus == 'مكتملة' && _requiresMaterials()) {
      // تحميل المواد إن لم تُحمل
      if (!_materialsLoaded) await _loadDispensedMaterials();

      if (_dispensedMaterials.isEmpty) {
        if (!mounted) return;
        final choice = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Row(children: [
                Icon(Icons.warning_amber_rounded,
                    color: SdColors.warning),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('المواد المصروفة',
                        style: TextStyle(fontSize: 16))),
              ]),
              content: const Text(
                'لم يتم تسجيل أي مواد مصروفة لهذه المهمة.\nهل تريد إضافة مواد أم تأكيد عدم الصرف؟',
                style: TextStyle(fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text('إلغاء'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, 'no_materials'),
                  child: const Text('لم يُصرف شيء'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: SdColors.warning),
                  onPressed: () => Navigator.pop(ctx, 'add_materials'),
                  child: const Text('إضافة مواد'),
                ),
              ],
            ),
          ),
        );

        if (choice == 'add_materials') {
          await _showAddMaterialsDialog();
          // بعد الإضافة نكمل المهمة تلقائياً (المواد تُحمّل داخل _showAddMaterialsDialog)
        } else if (choice == 'cancel' || choice == null) {
          return; // إلغاء — لا يكمل المهمة
        }
        // choice == 'no_materials' → يكمل عادي
      }
    }

    _devLog('🟦 [DEBUG] بدء تحديث المهمة - ID: ${widget.task.id}');
    _devLog('🟦 [DEBUG] الحالة الجديدة: $newStatus');

    final oldTask = widget.task; // حفظ المهمة الأصلية للتراجع عند الفشل

    try {
      final updatedTask = widget.task.copyWith(
        status: newStatus,
        amount: amount,
        deliveryFee: deliveryFee,
        notes: notes,
        closedAt: newStatus == 'مكتملة' || newStatus == 'ملغية'
            ? DateTime.now()
            : null,
      );

      // تحديث المهمة محلياً أولاً (optimistic)
      widget.onStatusChanged(updatedTask);

      // تحديث الحالة في API والتحقق من النتيجة
      final result = await _updateStatusViaApi(updatedTask);

      if (!mounted) return; // Widget قد يكون أُتلف أثناء انتظار الـ API

      if (result) {
        // نجاح حقيقي من السيرفر
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تحديث حالة المهمة إلى: $newStatus'),
            backgroundColor: SdColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        // فشل من السيرفر - التراجع عن التحديث المحلي
        widget.onStatusChanged(oldTask);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل تحديث الحالة - الانتقال غير مسموح'),
            backgroundColor: SdColors.danger,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // التراجع عن التحديث المحلي عند حدوث خطأ
      if (!mounted) return;
      widget.onStatusChanged(oldTask);
      _devLog('🔴 [ERROR] خطأ في تحديث حالة المهمة');

      _showErrorDialog('خطأ في تحديث المهمة',
          'فشل تحديث حالة المهمة، يرجى المحاولة مرة أخرى');
    }
  }

  /// تحديث حالة المهمة عبر API - يُرجع true عند النجاح
  Future<bool> _updateStatusViaApi(Task task) async {
    try {
      final apiStatus = Task.mapArabicStatusToApi(task.status);
      final taskId = task.guid.isNotEmpty ? task.guid : task.id;
      _devLog('🌐 [API] إرسال طلب تحديث الحالة...');
      _devLog('🌐 [API] Task ID: $taskId');
      _devLog('🌐 [API] Task GUID: "${task.guid}"');
      _devLog('🌐 [API] Task id: "${task.id}"');
      _devLog('🌐 [API] API Status: $apiStatus');
      _devLog('🌐 [API] Arabic Status: ${task.status}');

      final result = await TaskApiService.instance.updateStatus(
        taskId,
        status: apiStatus,
        amount: task.amount,
        deliveryFee: task.deliveryFee,
      );

      _devLog('🌐 [API] النتيجة الكاملة: $result');
      _devLog('🌐 [API] success: ${result['success']}');
      _devLog('🌐 [API] statusCode: ${result['statusCode']}');
      _devLog('🌐 [API] message: ${result['message']}');

      if (result['success'] == true) {
        _devLog('✅ تم تحديث الحالة في السيرفر بنجاح');
        return true;
      } else {
        final msg = result['message'] ?? 'فشل غير معروف';
        _devLog('❌ فشل تحديث الحالة في السيرفر: $msg');
        return false;
      }
    } catch (e) {
      _devLog('Error updating status via API');
      return false;
    }
  }

  /// عرض نافذة تعديل المهمة الشاملة الجديدة
  void _showEditTaskDialog() {
    showDialog(
      context: context,
      builder: (context) => EditTaskDialog(
        task: widget.task,
        onTaskUpdated: (updatedTask) {
          // تحديث المهمة محلياً
          widget.onStatusChanged(updatedTask);
        },
      ),
    );
  }

  /// حذف المهمة عبر API
  Future<void> _deleteTask() async {
    try {
      final result = await TaskApiService.instance.deleteRequest(
          widget.task.guid.isNotEmpty ? widget.task.guid : widget.task.id);

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حذف المهمة بنجاح'),
              backgroundColor: SdColors.success,
            ),
          );
          // تحديث القائمة بدل الرجوع للصفحة السابقة
          widget.onStatusChanged(widget.task);
        } else {
          final msg = result['message']?.toString() ?? 'فشل حذف المهمة';
          final code = result['statusCode'];
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(code == 403 ? 'لا تملك صلاحية حذف المهمة' : msg),
              backgroundColor: SdColors.danger,
            ),
          );
        }
      }
    } catch (e) {
      _devLog('Error deleting task');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('خطأ في حذف المهمة'),
            backgroundColor: SdColors.danger,
          ),
        );
      }
    }
  }

  void _confirmDeleteTask() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: const Text(
              'هل أنت متأكد من رغبتك في حذف هذه المهمة؟\nسيتم حذفها نهائياً.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _deleteTask();
              },
              style: ElevatedButton.styleFrom(backgroundColor: SdColors.danger),
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  /// تحويل المهمة إلى مكتملة مفعّل
  Future<void> _markAsActivated() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد التفعيل'),
        content: const Text('هل تم تفعيل الاشتراك لهذا المشترك؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: SdColors.success),
            child: const Text('نعم، تم التفعيل',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final taskId =
          widget.task.guid.isNotEmpty ? widget.task.guid : widget.task.id;
      await TaskApiService.instance.updateStatus(
        taskId,
        status: 'Completed',
        note: '[مفعّل] تم التفعيل يدوياً',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم تحويل المهمة إلى مكتملة مفعّل'),
              backgroundColor: SdColors.success),
        );
        widget.onStatusChanged(widget.task);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger),
        );
      }
    }
  }

  /// فتح خريطة الزونات مع فلتر FBG/FAT من المهمة
  void _openZonesMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KmlZonesMapPage(
          initialFbg: widget.task.fbg.isNotEmpty ? widget.task.fbg : null,
          initialFat: widget.task.fat.isNotEmpty ? widget.task.fat : null,
        ),
      ),
    );
  }

  /// فتح صفحة البحث عن المشترك مع تمرير بيانات المهمة
  Future<void> _openSubscriptionDetails() async {
    // البحث بالهاتف أولاً — أدق
    String searchQuery = '';
    if (widget.task.phone.isNotEmpty) {
      searchQuery = widget.task.phone.replaceAll(RegExp(r'[^\d]'), '');
      if (searchQuery.startsWith('964'))
        searchQuery = '0${searchQuery.substring(3)}';
    } else {
      searchQuery = widget.task.username;
    }

    final token = await AuthService.instance.getAccessToken() ?? '';
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يجب تسجيل الدخول لنظام FTTH أولاً'),
            backgroundColor: SdColors.danger),
      );
      return;
    }

    // بناء ملاحظات المهمة لتمريرها تلقائياً لشاشة التجديد
    final taskInfo = StringBuffer();
    if (widget.task.createdByName.isNotEmpty)
      taskInfo.writeln('أنشأها: ${widget.task.createdByName}');
    if (widget.task.technician.isNotEmpty)
      taskInfo.writeln('الفني: ${widget.task.technician}');
    if (widget.task.serviceType.isNotEmpty)
      taskInfo.writeln('الخدمة: ${widget.task.serviceType} Mbps');
    if (widget.task.subscriptionDuration.isNotEmpty)
      taskInfo.writeln('المدة: ${widget.task.subscriptionDuration}');
    if (widget.task.hasAmount)
      taskInfo.writeln('المبلغ: ${widget.task.amountFormatted}');
    if (widget.task.agentName.isNotEmpty)
      taskInfo.writeln('الوكيل: ${widget.task.agentName}');
    if (widget.task.pageId.isNotEmpty)
      taskInfo.writeln('كود الوكيل: ${widget.task.pageId}');
    if (widget.task.notes.isNotEmpty)
      taskInfo.writeln('ملاحظات: ${widget.task.notes}');

    final taskNotesStr = taskInfo.toString().trim();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuickSearchUsersPage(
          authToken: token,
          activatedBy: widget.currentUserName,
          initialSearchQuery: searchQuery,
          hasServerSavePermission:
              PermissionManager.instance.canView('google_sheets'),
          hasWhatsAppPermission: PermissionManager.instance.canView('whatsapp'),
          isAdminFlag: DualAuthService.instance.ftthIsAdmin,
          importantFtthApiPermissions:
              DualAuthService.instance.ftthImportantPermissions.isNotEmpty
                  ? DualAuthService.instance.ftthImportantPermissions
                  : null,
          taskAgentName:
              widget.task.agentName.isNotEmpty ? widget.task.agentName : null,
          taskAgentCode:
              widget.task.pageId.isNotEmpty ? widget.task.pageId : null,
          taskNotes: taskNotesStr.isNotEmpty ? taskNotesStr : null,
          taskId: widget.task.guid.isNotEmpty ? widget.task.guid : null,
          taskServiceType: widget.task.serviceType.isNotEmpty
              ? widget.task.serviceType
              : null,
          taskDuration: widget.task.subscriptionDuration.isNotEmpty
              ? widget.task.subscriptionDuration
              : null,
          taskAmount:
              widget.task.hasAmount ? widget.task.amountFormatted : null,
        ),
      ),
    );
  }

  Future<void> _launchWhatsApp(String phone) async {
    String formattedPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (formattedPhone.startsWith('0')) {
      formattedPhone = '964${formattedPhone.substring(1)}';
    }

    // إنشاء رسالة تلقائية للمشترك
    String message = await _buildWhatsAppMessage();

    // التحقق من النظام وتطبيق استراتيجية مناسبة
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux) {
      // استراتيجية الديسكتوب: فتح بدون نص أولاً ثم نسخ للحافظة
      _devLog('🖥️ اكتشاف نظام ديسكتوب للمشترك - استخدام استراتيجية خاصة');

      // نسخ الرسالة للحافظة
      await Clipboard.setData(ClipboardData(text: message));

      final whatsappAppUrl = 'whatsapp://send?phone=$formattedPhone';
      final whatsappWebUrl = 'https://wa.me/$formattedPhone';

      try {
        // محاولة فتح تطبيق WhatsApp أولاً
        if (await canLaunchUrl(Uri.parse(whatsappAppUrl))) {
          await launchUrl(Uri.parse(whatsappAppUrl),
              mode: LaunchMode.externalApplication);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.desktop_windows,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        const Text('تم فتح الواتساب للمشترك'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'تم نسخ رسالة المهمة للحافظة - استخدم Ctrl+V للصق النص',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
                backgroundColor: SdColors.info,
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'نسخ مرة أخرى',
                  textColor: Colors.white,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: message));
                  },
                ),
              ),
            );
          }
          return;
        }

        // إذا لم يكن التطبيق متاحاً، فتح WhatsApp Web
        if (await canLaunchUrl(Uri.parse(whatsappWebUrl))) {
          await launchUrl(Uri.parse(whatsappWebUrl),
              mode: LaunchMode.externalApplication);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.web, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        const Text('تم فتح الواتساب ويب للمشترك'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'تم نسخ رسالة المهمة للحافظة - استخدم Ctrl+V للصق النص',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
                backgroundColor: SdColors.info,
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'نسخ مرة أخرى',
                  textColor: Colors.white,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: message));
                  },
                ),
              ),
            );
          }
          return;
        }

        throw 'لم يتم العثور على تطبيق WhatsApp';
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      const Text('تم نسخ رسالة المهمة للحافظة'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('افتح الواتساب يدوياً واذهب إلى: $formattedPhone'),
                  const SizedBox(height: 4),
                  const Text('ثم استخدم Ctrl+V للصق الرسالة',
                      style: TextStyle(fontSize: 11)),
                ],
              ),
              backgroundColor: SdColors.warning,
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: 'نسخ الرقم',
                textColor: Colors.white,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: formattedPhone));
                },
              ),
            ),
          );
        }
      }
    } else {
      // استراتيجية الموبايل: إرسال النص مباشرة في الرابط
      _devLog('📱 اكتشاف نظام موبايل للمشترك - إرسال النص مباشرة');

      // ترميز الرسالة للـ URL
      String encodedMessage = Uri.encodeComponent(message);

      // محاولة فتح تطبيق WhatsApp المثبت على الحاسوب
      final whatsappAppUrl =
          'whatsapp://send?phone=$formattedPhone&text=$encodedMessage';
      final whatsappWebUrl =
          'https://wa.me/$formattedPhone?text=$encodedMessage';

      try {
        // محاولة فتح تطبيق WhatsApp أولاً
        if (await canLaunchUrl(Uri.parse(whatsappAppUrl))) {
          await launchUrl(Uri.parse(whatsappAppUrl),
              mode: LaunchMode.externalApplication);
          return;
        }

        // إذا لم يكن التطبيق متاحاً، فتح WhatsApp Web
        if (await canLaunchUrl(Uri.parse(whatsappWebUrl))) {
          await launchUrl(Uri.parse(whatsappWebUrl),
              mode: LaunchMode.externalApplication);
          return;
        }

        throw 'لم يتم العثور على تطبيق WhatsApp';
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'فشل في فتح واتساب: $e\nيرجى التأكد من تثبيت تطبيق واتساب'),
              backgroundColor: SdColors.danger,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  /// فتح حوار إعدادات رسائل الصيانة
  void _showMaintenanceMessagesDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => MaintenanceMessagesDialog(
        currentUserName: widget.currentUserName,
      ),
    );

    // إذا تم حفظ الرسائل بنجاح، عرض رسالة تأكيد
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث رسائل الصيانة بنجاح'),
          backgroundColor: SdColors.success,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// إنشاء رسالة واتساب مخصصة للمشترك باستخدام القالب القابل للتعديل
  Future<String> _buildWhatsAppMessage() async {
    try {
      // محاولة الحصول على القالب المحفوظ أولاً
      String? template = await WhatsAppTemplateStorage.loadTemplate();

      if (template == null || template.isEmpty) {
        // إذا لم يوجد قالب محفوظ، استخدم القالب الافتراضي
        template = _getDefaultTemplate();
      }

      // استبدال المتغيرات في القالب
      String message = template
          .replaceAll('{id}', widget.task.id.toString())
          .replaceAll('{title}', widget.task.title)
          .replaceAll('{status}', widget.task.status)
          .replaceAll('{department}', widget.task.department)
          .replaceAll('{leader}', widget.task.leader)
          .replaceAll('{technician}', widget.task.technician)
          .replaceAll('{username}', widget.task.username)
          .replaceAll('{phone}', widget.task.phone)
          .replaceAll('{technician_phone}', _getTechnicianPhone())
          .replaceAll('{fbg}', widget.task.fbg)
          .replaceAll('{fat}', widget.task.fat)
          .replaceAll('{location}', widget.task.location)
          .replaceAll('{amount}', widget.task.amountFormatted)
          .replaceAll('{created_at}',
              DateFormat('yyyy-MM-dd HH:mm').format(widget.task.createdAt))
          .replaceAll('{created_by}', widget.task.createdBy)
          .replaceAll('{priority}', widget.task.priority)
          .replaceAll('{notes}', widget.task.notes);

      return message;
    } catch (e) {
      _devLog('خطأ في بناء رسالة الواتساب');
      // في حالة حدوث خطأ، استخدم القالب الافتراضي
      return _getDefaultTemplate()
          .replaceAll('{id}', widget.task.id.toString())
          .replaceAll('{title}', widget.task.title)
          .replaceAll('{status}', widget.task.status)
          .replaceAll('{department}', widget.task.department)
          .replaceAll('{leader}', widget.task.leader)
          .replaceAll('{technician}', widget.task.technician)
          .replaceAll('{username}', widget.task.username)
          .replaceAll('{phone}', widget.task.phone)
          .replaceAll('{technician_phone}', _getTechnicianPhone())
          .replaceAll('{fbg}', widget.task.fbg)
          .replaceAll('{fat}', widget.task.fat)
          .replaceAll('{location}', widget.task.location)
          .replaceAll('{amount}', widget.task.amountFormatted)
          .replaceAll('{created_at}',
              DateFormat('yyyy-MM-dd HH:mm').format(widget.task.createdAt))
          .replaceAll('{created_by}', widget.task.createdBy)
          .replaceAll('{priority}', widget.task.priority)
          .replaceAll('{notes}', widget.task.notes);
    }
  }

  /// الحصول على القالب الافتراضي
  String _getDefaultTemplate() {
    return '''السلام عليكم ورحمة الله وبركاته
👤 اسم المستخدم: {username}
📞 رقم الهاتف: {phone}
📋 تم إنشاء مهمة جديدة:
🆔 معرف المهمة: {id}
📝 العنوان: {title}
📊 الحالة: {status}
👨‍🔧 الفني المختص: {technician}
📱 هاتف الفني: {technician_phone}
📡 FBG: {fbg}
🔌 FAT: {fat}
💰 المبلغ: {amount}
🕐 تاريخ الإنشاء: {created_at}
👨‍💻 منشئ المهمة: {created_by}

شركة رمز الصدارة المشغل الرسمي للمشروع الوطني 
فريق الدعم الفني''';
  }

  /// الحصول على رقم هاتف الفني
  String _getTechnicianPhone() {
    // التحقق من وجود رقم هاتف الفني في المهمة
    if (widget.task.technicianPhone.isNotEmpty) {
      return widget.task.technicianPhone;
    }
    // إذا لم يكن متوفراً، إرجاع رسالة بديلة
    return "متاح عند الحاجة";
  }

  /// تحديد لون الأولوية
  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'عاجل':
        return SdColors.danger;
      case 'عالي':
        return SdColors.warning;
      case 'متوسط':
        return SdColors.warning;
      case 'منخفض':
        return SdColors.success;
      default:
        return SdColors.faint;
    }
  }

  /// تحديد لون حالة المهمة — مصدر موحّد عبر شاشات المهام.
  Color _getStatusColor(String status) => TaskStatusColors.colorFor(status);

  // وظائف الوكلاء

  /// عرض dialog قائمة الوكلاء المفلترين حسب FBG المهمة
  void _showAgentsDialog() async {
    if (agents.isEmpty) {
      await _fetchAgentsData();
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => _buildAgentsDialog(),
    );
  }

  /// فلترة الوكلاء حسب FBG المهمة
  List<Map<String, dynamic>> _filterAgentsByFBG() {
    if (agents.isEmpty) return [];

    final taskFBG = widget.task.fbg.trim().toLowerCase();

    return agents.where((agent) {
      final agentZone = (agent['zone'] ?? '').toString().trim().toLowerCase();

      // مقارنة دقيقة للـ FBG
      return agentZone == taskFBG ||
          agentZone.contains(taskFBG) ||
          taskFBG.contains(agentZone);
    }).toList();
  }

  /// جلب بيانات الوكلاء من API
  Future<void> _fetchAgentsData() async {
    if (isLoadingAgents) return;

    setState(() {
      isLoadingAgents = true;
    });

    try {
      _devLog('جلب بيانات الوكلاء للمجموعة: ${widget.task.fbg}');

      // جلب الموظفين من API (task-staff)
      final response = await TaskApiService.instance.getTaskStaff();
      final List<dynamic> staffList =
          response['staff'] ?? response['Staff'] ?? [];

      // تحويل بيانات الموظفين لنفس تنسيق agents
      final List<Map<String, dynamic>> fetchedAgents = [];

      // تجميع الموظفين حسب القسم/المجموعة
      final Map<String, List<Map<String, String>>> grouped = {};
      for (var staff in staffList) {
        final dept =
            (staff['Department'] ?? staff['department'] ?? '').toString();
        final name = (staff['FullName'] ?? staff['fullName'] ?? '').toString();
        final phone =
            (staff['PhoneNumber'] ?? staff['phoneNumber'] ?? '').toString();
        if (name.isNotEmpty) {
          grouped.putIfAbsent(dept, () => []);
          grouped[dept]!.add({'name': name, 'phone': phone});
        }
      }

      grouped.forEach((group, members) {
        final Map<String, dynamic> agentData = {'group': group};
        for (int i = 0; i < members.length; i++) {
          agentData['agent${i + 1}'] = members[i];
        }
        fetchedAgents.add(agentData);
      });

      // فلترة البيانات حسب FBG المرسل
      List<Map<String, dynamic>> fbgFilteredAgents = [];
      final taskFBG = widget.task.fbg.trim();

      if (taskFBG.isNotEmpty && taskFBG != 'الكل') {
        fbgFilteredAgents = fetchedAgents
            .where((agent) =>
                agent['group']?.toString().toLowerCase() ==
                taskFBG.toLowerCase())
            .toList();
      } else {
        fbgFilteredAgents = fetchedAgents;
      }

      setState(() {
        agents = fbgFilteredAgents;
        isLoadingAgents = false;
      });

      _devLog(
          '✅ تم جلب ${agents.length} مجموعة وكلاء للـ FBG: ${widget.task.fbg}');
    } catch (e) {
      _devLog('❌ خطأ في جلب بيانات الوكلاء');
      setState(() {
        isLoadingAgents = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في جلب بيانات الوكلاء'),
            backgroundColor: SdColors.danger,
          ),
        );
      }
    }
  }

  /// بناء dialog الوكلاء مع فلترة حسب FBG وإرسال واتساب
  Widget _buildAgentsDialog() {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // عنوان النافذة مع FBG المهمة
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [SdColors.platformBase, SdColors.platformLight],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.group, color: Colors.white, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'إرسال المهمة للوكلاء',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'FBG: ${widget.task.fbg}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // معلومات المهمة المختصرة
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SdColors.infoTint,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SdColors.infoTintEdge),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text('المهمة: ${widget.task.title}',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold))),
                      Text('العميل: ${widget.task.username}',
                          style: TextStyle(fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('الهاتف: ${widget.task.phone}',
                          style:
                              TextStyle(fontSize: 11, color: SdColors.info)),
                      const SizedBox(width: 16),
                      Text('الموقع: ${widget.task.location}',
                          style:
                              TextStyle(fontSize: 11, color: SdColors.info)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // قائمة الوكلاء المفلترين حسب FBG
            Expanded(
              child: isLoadingAgents
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: SdColors.platformBase),
                          SizedBox(height: 16),
                          Text('جاري جلب بيانات الوكلاء...'),
                        ],
                      ),
                    )
                  : agents.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_off,
                                  size: 48, color: SdColors.faint),
                              const SizedBox(height: 16),
                              Text(
                                'لا يوجد وكلاء متاحون في منطقة ${widget.task.fbg}',
                                style: TextStyle(color: SdColors.muted),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : _buildAgentsList(),
            ),
          ],
        ),
      ),
    );
  }

  /// بناء قائمة الوكلاء مع أزرار إرسال واتساب
  Widget _buildAgentsList() {
    List<Widget> agentWidgets = [];

    for (var agentGroup in agents) {
      String groupName = agentGroup['group'] ?? '';

      // إضافة عنوان المجموعة
      agentWidgets.add(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: SdColors.platformTint,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: SdColors.platformTintEdge, width: 2),
              boxShadow: [
                BoxShadow(
                  color: SdColors.platformTintEdge.withValues(alpha: 0.3),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              'مجموعة: $groupName',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: SdColors.platformBase,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
          ),
        ),
      );

      // إضافة وكلاء المجموعة
      for (int i = 1; i <= 15; i++) {
        var agentKey = 'agent$i';
        if (agentGroup.containsKey(agentKey) && agentGroup[agentKey] != null) {
          var agentInfo = agentGroup[agentKey];
          String name = agentInfo['name'] ?? '';
          String phone = agentInfo['phone'] ?? '';

          if (name.isNotEmpty && phone.isNotEmpty) {
            agentWidgets.add(_buildAgentCard(name, phone, groupName));
          }
        }
      }
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: agentWidgets,
      ),
    );
  }

  /// بناء كارد وكيل مع زر واتساب مع نسخ تفاصيل المهمة
  Widget _buildAgentCard(String name, String phone, String group) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // معلومات الوكيل
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: SdColors.platformTint,
                    radius: 18,
                    child:
                        Icon(Icons.person, color: SdColors.platformBase, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                          textDirection: TextDirection.rtl,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$phone • $group',
                          style: TextStyle(
                            fontSize: 12,
                            color: SdColors.muted,
                            fontFamily: 'Cairo',
                          ),
                          textDirection: TextDirection.rtl,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // أزرار العمليات
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // زر نسخ التفاصيل وفتح واتساب
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _copyTaskDetailsAndOpenWhatsApp(phone, name),
                      icon:
                          const Icon(Icons.copy, color: Colors.white, size: 16),
                      label: const Text(
                        'نسخ وإرسال',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SdColors.success,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // زر تعيين المهمة
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          _assignTaskToAgentNew(name, phone, group),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SdColors.platformBase,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Text(
                        'تعيين',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// نسخ تفاصيل المهمة إلى الحافظة وفتح محادثة واتساب مع التفاصيل
  Future<void> _copyTaskDetailsAndOpenWhatsApp(
      String phone, String agentName) async {
    try {
      // إنشاء رسالة تفاصيل المهمة
      String taskDetails = _buildAgentWhatsAppMessage(agentName);

      // نسخ التفاصيل إلى الحافظة كنسخة احتياطية
      await Clipboard.setData(ClipboardData(text: taskDetails));

      // تنسيق رقم الهاتف
      String formattedPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
      if (formattedPhone.startsWith('0')) {
        formattedPhone = '964${formattedPhone.substring(1)}';
      }
      if (!formattedPhone.startsWith('+')) {
        formattedPhone = '+$formattedPhone';
      }

      // التحقق من النظام وتطبيق استراتيجية مناسبة
      bool opened = false;

      if (kIsWeb ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux) {
        // استراتيجية الديسكتوب: فتح بدون نص أولاً ثم نسخ للحافظة
        _devLog('🖥️ اكتشاف نظام ديسكتوب - استخدام استراتيجية خاصة');

        final whatsappAppUrl = 'whatsapp://send?phone=$formattedPhone';
        final whatsappWebUrl = 'https://wa.me/$formattedPhone';

        try {
          // محاولة فتح تطبيق WhatsApp ديسكتوب
          if (await canLaunchUrl(Uri.parse(whatsappAppUrl))) {
            await launchUrl(Uri.parse(whatsappAppUrl),
                mode: LaunchMode.externalApplication);
            opened = true;
          } else {
            // فتح WhatsApp Web
            final webUri = Uri.parse(whatsappWebUrl);
            if (await canLaunchUrl(webUri)) {
              await launchUrl(webUri, mode: LaunchMode.externalApplication);
              opened = true;
            }
          }

          if (opened) {
            // إغلاق نافذة الوكلاء
            Navigator.of(context).pop();

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.desktop_windows,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text('تم فتح الواتساب للوكيل $agentName'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'تم نسخ تفاصيل المهمة للحافظة - استخدم Ctrl+V للصق النص',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                  backgroundColor: SdColors.success,
                  duration: const Duration(seconds: 6),
                  action: SnackBarAction(
                    label: 'نسخ مرة أخرى',
                    textColor: Colors.white,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: taskDetails));
                    },
                  ),
                ),
              );
            }
          } else {
            throw 'لم يتم العثور على تطبيق WhatsApp';
          }
        } catch (e) {
          _devLog('❌ خطأ في فتح الواتساب (ديسكتوب)');
          _showDesktopFallbackMessage(formattedPhone, taskDetails, agentName);
        }
      } else {
        // استراتيجية الموبايل: إرسال النص مباشرة في الرابط
        _devLog('📱 اكتشاف نظام موبايل - إرسال النص مباشرة');

        final encodedMessage = Uri.encodeComponent(taskDetails);
        final whatsappAppUrl =
            'whatsapp://send?phone=$formattedPhone&text=$encodedMessage';
        final whatsappWebUrl =
            'https://wa.me/$formattedPhone?text=$encodedMessage';

        try {
          // محاولة فتح تطبيق WhatsApp أولاً
          if (await canLaunchUrl(Uri.parse(whatsappAppUrl))) {
            await launchUrl(Uri.parse(whatsappAppUrl),
                mode: LaunchMode.externalApplication);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text('تم إرسال المهمة للوكيل $agentName عبر الواتساب'),
                  backgroundColor: SdColors.success,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
            return;
          }

          // إذا لم يكن التطبيق متاحاً، فتح WhatsApp Web
          if (await canLaunchUrl(Uri.parse(whatsappWebUrl))) {
            await launchUrl(Uri.parse(whatsappWebUrl),
                mode: LaunchMode.externalApplication);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text('تم إرسال المهمة للوكيل $agentName عبر واتساب ويب'),
                  backgroundColor: SdColors.success,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
            return;
          }

          throw 'لم يتم العثور على تطبيق WhatsApp';
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'فشل في فتح واتساب: $e\nيرجى التأكد من تثبيت تطبيق واتساب'),
                backgroundColor: SdColors.danger,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }

      _devLog('🟢 إرسال تفاصيل المهمة للوكيل: $agentName');
      _devLog('📱 رقم الهاتف: $formattedPhone');
      _devLog('📋 تم نسخ التفاصيل إلى الحافظة');
    } catch (e) {
      _devLog('❌ خطأ في نسخ تفاصيل المهمة');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في نسخ تفاصيل المهمة'),
            backgroundColor: SdColors.danger,
          ),
        );
      }
    }
  }

  /// عرض رسالة احتياطية للديسكتوب
  void _showDesktopFallbackMessage(
      String formattedPhone, String taskDetails, String agentName) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text('تم نسخ التفاصيل للحافظة'),
                ],
              ),
              const SizedBox(height: 4),
              Text('افتح الواتساب يدوياً واذهب إلى: $formattedPhone'),
              const SizedBox(height: 2),
              const Text('ثم استخدم Ctrl+V للصق التفاصيل',
                  style: TextStyle(fontSize: 11)),
            ],
          ),
          backgroundColor: SdColors.warning,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'نسخ الرقم',
            textColor: Colors.white,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: formattedPhone));
            },
          ),
        ),
      );
    }
  }

  /// عرض رسالة احتياطية للموبايل
  void _showMobileFallbackMessage(
      String formattedPhone, String taskDetails, String agentName) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text('تم نسخ التفاصيل للحافظة'),
                ],
              ),
              const SizedBox(height: 4),
              Text('يمكنك لصقها يدوياً في الواتساب: $formattedPhone'),
            ],
          ),
          backgroundColor: SdColors.warning,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'نسخ الرقم',
            textColor: Colors.white,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: formattedPhone));
            },
          ),
        ),
      );
    }
  }

  /// إنشاء رسالة واتساب مخصصة ومختصرة للوكيل تحتوي على تفاصيل المهمة
  String _buildAgentWhatsAppMessage(String agentName) {
    return '''السلام عليكم أخي $agentName 👋

📋 مهمة جديدة #${widget.task.id}
📝 ${widget.task.title}

👤 العميل: ${widget.task.username}
📞 ${widget.task.phone}
📍 ${widget.task.location}

🔧 FBG: ${widget.task.fbg}
${widget.task.fat.isNotEmpty ? '🔌 FAT: ${widget.task.fat}' : ''}
${widget.task.hasAmount ? '💰 ${widget.task.amountFormatted} دينار' : ''}

👨‍🔧 الفني: ${widget.task.technician}
🎯 ${widget.task.priority}

${widget.task.notes.isNotEmpty ? '📝 ${widget.task.notes}' : ''}

يرجى التواصل مع العميل
شركة رمز الصدارة 🌟''';
  }

  /// تعيين المهمة لوكيل جديد
  void _assignTaskToAgentNew(
      String agentName, String agentPhone, String agentGroup) {
    try {
      // إضافة الوكيل لقائمة وكلاء المهمة
      List<String> updatedAgents = List.from(widget.task.agents);
      String agentInfo = '$agentName ($agentPhone)';

      if (!updatedAgents.contains(agentInfo)) {
        updatedAgents.add(agentInfo);
      }

      final updatedTask = widget.task.copyWith(
        agents: updatedAgents,
      );

      // تحديث المهمة محلياً
      widget.onStatusChanged(updatedTask);

      // تحديث عبر API
      _updateStatusViaApi(updatedTask);

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تعيين المهمة للوكيل $agentName'),
          backgroundColor: SdColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      _devLog('خطأ في تعيين المهمة للوكيل');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تعيين المهمة'),
            backgroundColor: SdColors.danger,
          ),
        );
      }
    }
  }

  /// نسخ رقم الهاتف إلى الحافظة
  void _copyPhoneNumber(String phoneNumber) {
    Clipboard.setData(ClipboardData(text: phoneNumber)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم نسخ رقم الهاتف إلى الحافظة'),
          backgroundColor: SdColors.info,
          duration: Duration(seconds: 2),
        ),
      );
    });
  }

  /// إرسال المهمة للفني عبر الواتساب
  void _sendTaskToTechnician(String technicianName) async {
    try {
      // البحث عن رقم هاتف الفني
      String technicianPhone = await _getTechnicianPhoneNumber(technicianName);

      if (technicianPhone.isEmpty) {
        // عرض نافذة لإدخال رقم هاتف الفني يدوياً
        _showTechnicianPhoneInputDialog(technicianName);
        return;
      }

      // إنشاء رسالة واتساب للفني
      String message = await _buildTechnicianWhatsAppMessage(technicianName);

      // فتح الواتساب وإرسال الرسالة
      await _launchWhatsAppForTechnician(
          technicianPhone, message, technicianName);
    } catch (e) {
      _devLog('خطأ في إرسال المهمة للفني');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إرسال المهمة للفني'),
            backgroundColor: SdColors.danger,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// البحث عن رقم هاتف الفني
  Future<String> _getTechnicianPhoneNumber(String technicianName) async {
    try {
      // التحقق أولاً من وجود رقم هاتف الفني في المهمة نفسها
      if (widget.task.technicianPhone.isNotEmpty) {
        return widget.task.technicianPhone;
      }

      // البحث في قائمة الموظفين من API
      try {
        final response = await TaskApiService.instance.getTaskStaff();
        final List<dynamic> staffList =
            response['staff'] ?? response['Staff'] ?? [];

        for (var staff in staffList) {
          final name =
              (staff['FullName'] ?? staff['fullName'] ?? '').toString().trim();
          final phone = (staff['PhoneNumber'] ?? staff['phoneNumber'] ?? '')
              .toString()
              .trim();

          if (name.toLowerCase() == technicianName.toLowerCase() &&
              phone.isNotEmpty) {
            return phone;
          }
        }
      } catch (e) {
        _devLog('خطأ في البحث عن الفني من API');
      }

      return '';
    } catch (e) {
      _devLog('خطأ في البحث عن رقم هاتف الفني');
      return '';
    }
  }

  /// عرض نافذة لإدخال رقم هاتف الفني يدوياً
  void _showTechnicianPhoneInputDialog(String technicianName) {
    final TextEditingController phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.phone, color: SdColors.success),
              const SizedBox(width: 8),
              const Text('رقم هاتف الفني'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('لم يتم العثور على رقم هاتف للفني: $technicianName'),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  hintText: '07xxxxxxxx',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                phoneController.dispose();
                Navigator.of(context).pop();
              },
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                String phone = phoneController.text.trim();
                if (phone.isNotEmpty) {
                  Navigator.of(context).pop();

                  // إنشاء رسالة واتساب للفني
                  String message =
                      await _buildTechnicianWhatsAppMessage(technicianName);

                  // فتح الواتساب وإرسال الرسالة
                  await _launchWhatsAppForTechnician(
                      phone, message, technicianName);
                }
                phoneController.dispose();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: SdColors.success,
                foregroundColor: Colors.white,
              ),
              child: const Text('إرسال'),
            ),
          ],
        );
      },
    );
  }

  /// فتح الواتساب وإرسال رسالة للفني
  Future<void> _launchWhatsAppForTechnician(
      String phone, String message, String technicianName) async {
    String formattedPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (formattedPhone.startsWith('0')) {
      formattedPhone = '964${formattedPhone.substring(1)}';
    }

    // التحقق من النظام وتطبيق استراتيجية مناسبة
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux) {
      // استراتيجية الديسكتوب: فتح بدون نص أولاً ثم نسخ للحافظة
      _devLog('🖥️ اكتشاف نظام ديسكتوب للفني - استخدام استراتيجية خاصة');

      // نسخ الرسالة للحافظة
      await Clipboard.setData(ClipboardData(text: message));

      final whatsappAppUrl = 'whatsapp://send?phone=$formattedPhone';
      final whatsappWebUrl = 'https://wa.me/$formattedPhone';

      try {
        // محاولة فتح تطبيق WhatsApp أولاً
        if (await canLaunchUrl(Uri.parse(whatsappAppUrl))) {
          await launchUrl(Uri.parse(whatsappAppUrl),
              mode: LaunchMode.externalApplication);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.desktop_windows,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text('تم فتح الواتساب للفني $technicianName'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'تم نسخ رسالة المهمة للحافظة - استخدم Ctrl+V للصق النص',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
                backgroundColor: SdColors.success,
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'نسخ مرة أخرى',
                  textColor: Colors.white,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: message));
                  },
                ),
              ),
            );
          }
          return;
        }

        // إذا لم يكن التطبيق متاحاً، فتح WhatsApp Web
        if (await canLaunchUrl(Uri.parse(whatsappWebUrl))) {
          await launchUrl(Uri.parse(whatsappWebUrl),
              mode: LaunchMode.externalApplication);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.web, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text('تم فتح الواتساب ويب للفني $technicianName'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'تم نسخ رسالة المهمة للحافظة - استخدم Ctrl+V للصق النص',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
                backgroundColor: SdColors.success,
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'نسخ مرة أخرى',
                  textColor: Colors.white,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: message));
                  },
                ),
              ),
            );
          }
          return;
        }

        throw 'لم يتم العثور على تطبيق WhatsApp';
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      const Text('تم نسخ رسالة المهمة للحافظة'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('افتح الواتساب يدوياً واذهب إلى: $formattedPhone'),
                  const SizedBox(height: 4),
                  const Text('ثم استخدم Ctrl+V للصق الرسالة',
                      style: TextStyle(fontSize: 11)),
                ],
              ),
              backgroundColor: SdColors.warning,
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: 'نسخ الرقم',
                textColor: Colors.white,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: formattedPhone));
                },
              ),
            ),
          );
        }
      }
    } else {
      // استراتيجية الموبايل: إرسال النص مباشرة في الرابط
      _devLog('📱 اكتشاف نظام موبايل للفني - إرسال النص مباشرة');

      // ترميز الرسالة للـ URL
      String encodedMessage = Uri.encodeComponent(message);

      final whatsappAppUrl =
          'whatsapp://send?phone=$formattedPhone&text=$encodedMessage';
      final whatsappWebUrl =
          'https://wa.me/$formattedPhone?text=$encodedMessage';

      try {
        // محاولة فتح تطبيق WhatsApp أولاً
        if (await canLaunchUrl(Uri.parse(whatsappAppUrl))) {
          await launchUrl(Uri.parse(whatsappAppUrl),
              mode: LaunchMode.externalApplication);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('تم إرسال المهمة للفني $technicianName عبر الواتساب'),
                backgroundColor: SdColors.success,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return;
        }

        // إذا لم يكن التطبيق متاحاً، فتح WhatsApp Web
        if (await canLaunchUrl(Uri.parse(whatsappWebUrl))) {
          await launchUrl(Uri.parse(whatsappWebUrl),
              mode: LaunchMode.externalApplication);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'تم إرسال المهمة للفني $technicianName عبر واتساب ويب'),
                backgroundColor: SdColors.success,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return;
        }

        throw 'لم يتم العثور على تطبيق WhatsApp';
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'فشل في فتح واتساب: $e\nيرجى التأكد من تثبيت تطبيق واتساب'),
              backgroundColor: SdColors.danger,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  /// إنشاء رسالة واتساب مخصصة للفني تحتوي على تفاصيل المهمة
  Future<String> _buildTechnicianWhatsAppMessage(String technicianName) async {
    return '''السلام عليكم أستاذ $technicianName 👋

🔧 مهمة فنية جديدة #${widget.task.id}

📋 تفاصيل المهمة:
📝 العنوان: ${widget.task.title}
📊 الحالة: ${widget.task.status}
🎯 الأولوية: ${widget.task.priority}

👤 بيانات العميل:
🏠 الاسم: ${widget.task.username}
📞 الهاتف: ${widget.task.phone}
📍 الموقع: ${widget.task.location}

🔧 التفاصيل الفنية:
📡 FBG: ${widget.task.fbg}
${widget.task.fat.isNotEmpty ? '🔌 FAT: ${widget.task.fat}' : ''}
${widget.task.hasAmount ? '💰 المبلغ المطلوب: ${widget.task.amountFormatted} دينار' : ''}

${widget.task.notes.isNotEmpty ? '📝 ملاحظات إضافية:\n${widget.task.notes}' : ''}

🕐 تاريخ الإنشاء: ${DateFormat('yyyy-MM-dd HH:mm').format(widget.task.createdAt)}
👨‍💼 منشئ المهمة: ${widget.task.createdBy}

يرجى التواصل مع العميل وتنفيذ المهمة في أقرب وقت ممكن.
 
      اكمل الاجراء
    باستخدام التطبيق
شركة رمز الصدارة للاتصالات 🌟
  ''';
  }

  /// عرض نافذة خطأ مع تفاصيل يمكن نسخها
  void _showErrorDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.error, color: SdColors.danger),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: Container(
            constraints: const BoxConstraints(maxHeight: 400),
            child: SingleChildScrollView(
              child: SelectableText(content),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إغلاق'),
            ),
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم نسخ تفاصيل الخطأ إلى الحافظة'),
                    backgroundColor: SdColors.info,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('نسخ التفاصيل'),
            ),
          ],
        );
      },
    );
  }
}
