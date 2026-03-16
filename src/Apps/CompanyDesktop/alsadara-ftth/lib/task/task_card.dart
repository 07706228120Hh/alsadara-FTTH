import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // إضافة للتحقق من النظام
import 'package:url_launcher/url_launcher.dart';
import '../models/task.dart';
import '../services/whatsapp_template_storage.dart';
import '../services/task_api_service.dart';
import '../widgets/maintenance_messages_dialog.dart';
import '../widgets/edit_task_dialog.dart';
import 'package:intl/intl.dart' hide TextDirection;

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

  // ═══════ الحالات المتاحة للمستخدم حسب الحالة الحالية ═══════
  /// الحصول على الحالات المسموح الانتقال إليها (يعرض فقط الحالات العملية)
  List<String> _getAvailableStatuses() {
    final current = widget.task.status;
    // الحالات النهائية
    if (current == 'مكتملة' || current == 'ملغية' || current == 'مرفوضة') {
      return [current];
    }
    // لأي حالة غير نهائية: اعرض الخيارات العملية فقط
    return {current, 'قيد التنفيذ', 'مكتملة', 'ملغية'}.toList();
  }

  // متغيرات لجلب بيانات الوكلاء
  List<Map<String, dynamic>> agents = [];
  bool isLoadingAgents = false;

  @override
  Widget build(BuildContext context) {
    final currentUserName = widget.currentUserName.trim();
    final taskTechnician = widget.task.technician.trim();

    final isTech = widget.currentUserRole == 'فني' ||
        widget.currentUserRole.toLowerCase() == 'technician';
    if (isTech && taskTechnician != currentUserName) {
      return const SizedBox.shrink();
    }

    final statusColor = _getStatusColor(widget.task.status);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.black,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            setState(() {
              showDetails = !showDetails;
            });
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الشريط العلوي الملون - Header
              _buildPremiumHeader(statusColor),

              // المعلومات الأساسية
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: _buildCompactBasicInfo(),
              ),

              // التفاصيل المتقدمة
              if (showDetails) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _buildCompactDetailedInfo(),
                ),
              ],

              // فاصل خفيف
              Divider(height: 1, color: Colors.grey.shade200),

              // شريط الإجراءات السفلي
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
        children: [
          // أيقونة الأولوية في دائرة
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              _getPriorityIcon(widget.task.priority),
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),

          // العنوان
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.task.title.isNotEmpty
                      ? widget.task.title
                      : 'مهمة غير محددة',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.task.department} • #${widget.task.id}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // حالة المهمة
          _buildCompactStatusBadge(),
        ],
      ),
    );
  }

  Widget _buildCompactHeader() {
    return _buildPremiumHeader(_getStatusColor(widget.task.status));
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
              width: 6,
              height: 6,
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
                fontSize: 10,
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
    return Column(
      children: [
        // الصف الأول: العميل | الفني | FBG
        Row(
          children: [
            Expanded(
              child: _buildInfoTile(
                Icons.person_outline_rounded,
                'العميل',
                widget.task.username,
                const Color(0xFF3498DB),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildInfoTile(
                Icons.engineering_outlined,
                'الفني',
                widget.task.technician,
                const Color(0xFF009688),
                trailing: widget.task.technician.isNotEmpty &&
                        widget.task.technician != 'غير متوفر'
                    ? _buildMiniIconButton(
                        Icons.send_rounded,
                        const Color(0xFF009688),
                        () => _sendTaskToTechnician(widget.task.technician))
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildInfoTile(
                Icons.hub_outlined,
                'FBG',
                widget.task.fbg,
                const Color(0xFF27AE60),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // الصف الثاني: الهاتف | الوكيل | المبلغ
        Row(
          children: [
            Expanded(
              child: _buildInfoTile(
                Icons.phone_outlined,
                'الهاتف',
                widget.task.phone,
                const Color(0xFF8E44AD),
                trailing: widget.task.phone.isNotEmpty
                    ? _buildMiniIconButton(
                        Icons.copy_rounded,
                        const Color(0xFF8E44AD),
                        () => _copyPhoneNumber(widget.task.phone))
                    : null,
              ),
            ),
            if (widget.task.agentName.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _buildInfoTile(
                  Icons.storefront_outlined,
                  'الوكيل',
                  '${widget.task.agentName}${widget.task.pageId.isNotEmpty ? ' - ${widget.task.pageId}' : ''}',
                  const Color(0xFF6C3483),
                  trailing: widget.task.pageId.isNotEmpty
                      ? _buildMiniIconButton(
                          Icons.copy_rounded, const Color(0xFF6C3483), () {
                          Clipboard.setData(
                              ClipboardData(text: widget.task.pageId));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('تم نسخ: ${widget.task.pageId}'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        })
                      : null,
                ),
              ),
            ],
            if (widget.task.amount.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _buildInfoTile(
                  Icons.payments_outlined,
                  'المبلغ',
                  '${widget.task.amount} د.ع',
                  const Color(0xFFE74C3C),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// خلية معلومات أنيقة مع عنوان وقيمة
  Widget _buildInfoTile(IconData icon, String label, String value, Color color,
      {Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    color: color.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value.isNotEmpty ? value : '-',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF2C3E50),
                    fontWeight: FontWeight.w700,
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

  /// أيقونة صغيرة أنيقة
  Widget _buildMiniIconButton(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 13, color: color),
      ),
    );
  }

  Widget _buildCompactDetailedInfo() {
    final statusColor = _getStatusColor(widget.task.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withValues(alpha: 0.12)),
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
                    'الموقع', widget.task.location, const Color(0xFF3498DB)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactDetailItem(Icons.cable_outlined, 'FAT',
                    widget.task.fat, const Color(0xFF27AE60)),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // صف التفاصيل الثاني
          Row(
            children: [
              Expanded(
                child: _buildCompactDetailItem(Icons.flag_outlined, 'الأولوية',
                    widget.task.priority, const Color(0xFFE67E22)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactDetailItem(
                    Icons.calendar_today_rounded,
                    'الإنشاء',
                    DateFormat('MM/dd').format(widget.task.createdAt),
                    const Color(0xFF9B59B6)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
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
                    fontSize: 9,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value.isNotEmpty ? value : '-',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF1A1A2E),
                    fontWeight: FontWeight.w600,
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
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notes_rounded, size: 13, color: Colors.grey.shade400),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF1A1A2E),
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

  /// شريط الإجراءات الفخم
  Widget _buildCompactActionBar() {
    return Row(
      children: [
        // واتساب
        if (widget.task.phone.isNotEmpty)
          _buildCompactActionButton(
            Icons.message_rounded,
            'واتساب',
            const Color(0xFF25D366),
            () => _launchWhatsApp(widget.task.phone),
          ),

        // وكيل
        if (widget.currentUserRole == 'ليدر' ||
            widget.currentUserRole == 'مدير')
          _buildCompactActionButton(
            Icons.group_rounded,
            'وكيل',
            const Color(0xFF8E44AD),
            _showAgentsDialog,
          ),

        // تعديل
        if (widget.currentUserRole == 'مدير' ||
            widget.currentUserRole == 'ليدر')
          _buildCompactActionButton(
            Icons.edit_rounded,
            'تعديل',
            const Color(0xFF3498DB),
            _showEditTaskDialog,
          ),

        // حذف
        if (widget.currentUserRole == 'مدير')
          _buildCompactActionButton(
            Icons.delete_outline_rounded,
            'حذف',
            const Color(0xFFE74C3C),
            _confirmDeleteTask,
          ),
      ],
    );
  }

  Widget _buildCompactActionButton(
      IconData icon, String label, Color color, VoidCallback onPressed) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600,
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
            color: Colors.grey,
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
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    String selectedStatus = widget.task.status;
    final TextEditingController amountController =
        TextEditingController(text: widget.task.amount);
    final TextEditingController notesController =
        TextEditingController(text: widget.task.notes);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final statusColor = _getStatusColor(selectedStatus);
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 8,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: EdgeInsets.zero,
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
                              colors: [Color(0xFF1A237E), Color(0xFF283593)]),
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
                                    color: Colors.grey.shade700)),
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

                            // 2. المبلغ
                            Text('المبلغ',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: amountController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.left,
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]')),
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
                                  return TextEditingValue(
                                      text: converted,
                                      selection: TextSelection.collapsed(
                                          offset: converted.length));
                                }),
                              ],
                              decoration: InputDecoration(
                                hintText: '0.00',
                                hintStyle:
                                    TextStyle(color: Colors.grey.shade400),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                prefixIcon: Container(
                                  width: 36,
                                  alignment: Alignment.center,
                                  child: Text('\$',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade600)),
                                ),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.green.shade400,
                                        width: 1.5)),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // 3. ملاحظات
                            Text('ملاحظات الفني',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: notesController,
                              maxLines: 3,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                hintText: 'ملاحظات إضافية (اختياري)',
                                hintStyle: TextStyle(
                                    color: Colors.grey.shade400, fontSize: 13),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.grey.shade300)),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.grey.shade300)),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.orange.shade400,
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
                                  amountController.dispose();
                                  notesController.dispose();
                                  Navigator.of(context).pop();
                                },
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  side: BorderSide(color: Colors.grey.shade400),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text('إلغاء',
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final String newStatus = selectedStatus;
                                  final String amount =
                                      amountController.text.trim();
                                  final String notes =
                                      notesController.text.trim();

                                  Navigator.of(context).pop();
                                  await Future.delayed(
                                      const Duration(milliseconds: 100));

                                  try {
                                    amountController.dispose();
                                    notesController.dispose();
                                  } catch (e) {
                                    print('تم تجاهل خطأ dispose');
                                  }

                                  _updateTaskStatus(newStatus,
                                      amount: amount, notes: notes);
                                },
                                icon: const Icon(Icons.check_rounded, size: 20),
                                label: const Text('تحديث المهمة',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  backgroundColor: const Color(0xFF1A237E),
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
    );
  }

  void _updateTaskStatus(String newStatus,
      {String amount = '', String notes = ''}) async {
    print('🟦 [DEBUG] بدء تحديث المهمة - ID: ${widget.task.id}');
    print('🟦 [DEBUG] الحالة الجديدة: $newStatus');

    final oldTask = widget.task; // حفظ المهمة الأصلية للتراجع عند الفشل

    try {
      final updatedTask = widget.task.copyWith(
        status: newStatus,
        amount: amount,
        notes: notes,
        closedAt: newStatus == 'مكتملة' || newStatus == 'ملغية'
            ? DateTime.now()
            : null,
      );

      // تحديث المهمة محلياً أولاً (optimistic)
      widget.onStatusChanged(updatedTask);

      // تحديث الحالة في API والتحقق من النتيجة
      final result = await _updateStatusViaApi(updatedTask);

      if (result) {
        // نجاح حقيقي من السيرفر
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم تحديث حالة المهمة إلى: $newStatus'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // فشل من السيرفر - التراجع عن التحديث المحلي
        widget.onStatusChanged(oldTask);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فشل تحديث الحالة - الانتقال غير مسموح'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      // التراجع عن التحديث المحلي عند حدوث خطأ
      widget.onStatusChanged(oldTask);
      print('🔴 [ERROR] خطأ في تحديث حالة المهمة');

      if (mounted) {
        _showErrorDialog('خطأ في تحديث المهمة', 'فشل تحديث حالة المهمة، يرجى المحاولة مرة أخرى');
      }
    }
  }

  /// تحديث حالة المهمة عبر API - يُرجع true عند النجاح
  Future<bool> _updateStatusViaApi(Task task) async {
    try {
      final apiStatus = Task.mapArabicStatusToApi(task.status);
      final taskId = task.guid.isNotEmpty ? task.guid : task.id;
      print('🌐 [API] إرسال طلب تحديث الحالة...');
      print('🌐 [API] Task ID: $taskId');
      print('🌐 [API] Task GUID: "${task.guid}"');
      print('🌐 [API] Task id: "${task.id}"');
      print('🌐 [API] API Status: $apiStatus');
      print('🌐 [API] Arabic Status: ${task.status}');

      final result = await TaskApiService.instance.updateStatus(
        taskId,
        status: apiStatus,
        amount: task.amount.isNotEmpty ? double.tryParse(task.amount) : null,
      );

      print('🌐 [API] النتيجة الكاملة: $result');
      print('🌐 [API] success: ${result['success']}');
      print('🌐 [API] statusCode: ${result['statusCode']}');
      print('🌐 [API] message: ${result['message']}');

      if (result['success'] == true) {
        print('✅ تم تحديث الحالة في السيرفر بنجاح');
        return true;
      } else {
        final msg = result['message'] ?? 'فشل غير معروف';
        print('❌ فشل تحديث الحالة في السيرفر: $msg');
        return false;
      }
    } catch (e) {
      debugPrint('Error updating status via API');
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
      await TaskApiService.instance.deleteRequest(
          widget.task.guid.isNotEmpty ? widget.task.guid : widget.task.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف المهمة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Error deleting task');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حذف المهمة'),
            backgroundColor: Colors.red,
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
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
      debugPrint('🖥️ اكتشاف نظام ديسكتوب للمشترك - استخدام استراتيجية خاصة');

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
                backgroundColor: Colors.blue,
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
                backgroundColor: Colors.blue,
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
                  const SizedBox(height: 2),
                  const Text('ثم استخدم Ctrl+V للصق الرسالة',
                      style: TextStyle(fontSize: 11)),
                ],
              ),
              backgroundColor: Colors.orange,
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
      debugPrint('📱 اكتشاف نظام موبايل للمشترك - إرسال النص مباشرة');

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
              backgroundColor: Colors.red,
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
          backgroundColor: Colors.green,
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
          .replaceAll('{amount}', widget.task.amount)
          .replaceAll('{created_at}',
              DateFormat('yyyy-MM-dd HH:mm').format(widget.task.createdAt))
          .replaceAll('{created_by}', widget.task.createdBy)
          .replaceAll('{priority}', widget.task.priority)
          .replaceAll('{notes}', widget.task.notes);

      return message;
    } catch (e) {
      print('خطأ في بناء رسالة الواتساب');
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
          .replaceAll('{amount}', widget.task.amount)
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
        return Colors.red;
      case 'عالي':
        return Colors.orange;
      case 'متوسط':
        return Colors.yellow.shade700;
      case 'منخفض':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  /// تحديد لون حالة المهمة
  Color _getStatusColor(String status) {
    switch (status) {
      case 'مفتوحة':
        return Colors.blue;
      case 'قيد المراجعة':
        return Colors.indigo;
      case 'موافق عليه':
        return Colors.teal;
      case 'معينة':
        return Colors.purple;
      case 'قيد التنفيذ':
        return Colors.orange;
      case 'معلقة':
        return Colors.amber.shade700;
      case 'مكتملة':
        return Colors.green;
      case 'ملغية':
        return Colors.red;
      case 'مرفوضة':
        return Colors.red.shade900;
      default:
        return Colors.grey;
    }
  }

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
      debugPrint('جلب بيانات الوكلاء للمجموعة: ${widget.task.fbg}');

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

      debugPrint(
          '✅ تم جلب ${agents.length} مجموعة وكلاء للـ FBG: ${widget.task.fbg}');
    } catch (e) {
      debugPrint('❌ خطأ في جلب بيانات الوكلاء');
      setState(() {
        isLoadingAgents = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في جلب بيانات الوكلاء'),
            backgroundColor: Colors.red,
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
                  colors: [Colors.purple[600]!, Colors.purple[400]!],
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
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
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
                              TextStyle(fontSize: 11, color: Colors.blue[700])),
                      const SizedBox(width: 16),
                      Text('الموقع: ${widget.task.location}',
                          style:
                              TextStyle(fontSize: 11, color: Colors.blue[700])),
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
                          CircularProgressIndicator(color: Colors.purple),
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
                                  size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'لا يوجد وكلاء متاحون في منطقة ${widget.task.fbg}',
                                style: TextStyle(color: Colors.grey[600]),
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
              color: Colors.purple[100],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.purple[300]!, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple[200]!.withValues(alpha: 0.3),
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
                color: Colors.purple[800],
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
                    backgroundColor: Colors.purple[100],
                    radius: 18,
                    child:
                        Icon(Icons.person, color: Colors.purple[700], size: 18),
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
                            color: Colors.grey[600],
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
                        backgroundColor: Colors.green,
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
                        backgroundColor: Colors.purple,
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
        debugPrint('🖥️ اكتشاف نظام ديسكتوب - استخدام استراتيجية خاصة');

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
                  backgroundColor: Colors.green,
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
          debugPrint('❌ خطأ في فتح الواتساب (ديسكتوب)');
          _showDesktopFallbackMessage(formattedPhone, taskDetails, agentName);
        }
      } else {
        // استراتيجية الموبايل: إرسال النص مباشرة في الرابط
        debugPrint('📱 اكتشاف نظام موبايل - إرسال النص مباشرة');

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
                  backgroundColor: Colors.green,
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
                  backgroundColor: Colors.green,
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
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }

      debugPrint('🟢 إرسال تفاصيل المهمة للوكيل: $agentName');
      debugPrint('📱 رقم الهاتف: $formattedPhone');
      debugPrint('📋 تم نسخ التفاصيل إلى الحافظة');
    } catch (e) {
      debugPrint('❌ خطأ في نسخ تفاصيل المهمة');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في نسخ تفاصيل المهمة'),
            backgroundColor: Colors.red,
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
          backgroundColor: Colors.orange,
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
          backgroundColor: Colors.orange,
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
${widget.task.amount.isNotEmpty ? '💰 ${widget.task.amount} دينار' : ''}

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
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('خطأ في تعيين المهمة للوكيل');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تعيين المهمة'),
            backgroundColor: Colors.red,
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
          backgroundColor: Colors.blue,
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
      debugPrint('خطأ في إرسال المهمة للفني');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إرسال المهمة للفني'),
            backgroundColor: Colors.red,
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
        debugPrint('خطأ في البحث عن الفني من API');
      }

      return '';
    } catch (e) {
      debugPrint('خطأ في البحث عن رقم هاتف الفني');
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
              const Icon(Icons.phone, color: Colors.green),
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
                backgroundColor: Colors.green,
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
      debugPrint('🖥️ اكتشاف نظام ديسكتوب للفني - استخدام استراتيجية خاصة');

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
                backgroundColor: Colors.green,
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
                backgroundColor: Colors.green,
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
                  const SizedBox(height: 2),
                  const Text('ثم استخدم Ctrl+V للصق الرسالة',
                      style: TextStyle(fontSize: 11)),
                ],
              ),
              backgroundColor: Colors.orange,
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
      debugPrint('📱 اكتشاف نظام موبايل للفني - إرسال النص مباشرة');

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
                backgroundColor: Colors.green,
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
                backgroundColor: Colors.green,
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
              backgroundColor: Colors.red,
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
${widget.task.amount.isNotEmpty ? '💰 المبلغ المطلوب: ${widget.task.amount} دينار' : ''}

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
              const Icon(Icons.error, color: Colors.red),
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
                    backgroundColor: Colors.blue,
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
