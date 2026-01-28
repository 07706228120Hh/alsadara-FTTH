import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // إضافة للتحقق من النظام
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/task.dart';
import '../services/whatsapp_template_storage.dart';
import '../services/google_sheets_service.dart';
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
  final List<String> _statuses = ['مفتوحة', 'قيد التنفيذ', 'مكتملة', 'ملغية'];

  // متغيرات لجلب بيانات الو��لاء
  sheets.SheetsApi? _sheetsApi;
  AuthClient? _client;
  final String spreadsheetId = '1MGY8UhtHaUiRaUKbohEi3a74jgEh7NeOuTEHBQ83KZc';
  List<Map<String, dynamic>> agents = [];
  bool isLoadingAgents = false;

  @override
  Widget build(BuildContext context) {
    final currentUserName = widget.currentUserName.trim();
    final taskTechnician = widget.task.technician.trim();

    if (widget.currentUserRole == 'فني' && taskTechnician != currentUserName) {
      return _buildNoTasksMessage();
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _getStatusColor(widget.task.status).withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Colors.grey.shade50,
            ],
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              showDetails = !showDetails;
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // العنوان المضغوط والأنيق
                _buildCompactHeader(),
                const SizedBox(height: 12),

                // المعلومات الأساسية في تخطيط مضغوط
                _buildCompactBasicInfo(),

                // التفاصيل المتقدمة
                if (showDetails) ...[
                  const SizedBox(height: 12),
                  _buildCompactDetailedInfo(),
                ],

                // شريط الإجراءات السفلي
                const SizedBox(height: 8),
                _buildCompactActionBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// عنوان مضغوط وأنيق
  Widget _buildCompactHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getStatusColor(widget.task.status).withValues(alpha: 0.1),
            _getStatusColor(widget.task.status).withValues(alpha: 0.05),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getStatusColor(widget.task.status).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // أيقونة الأولوية
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _getStatusColor(widget.task.status),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              _getPriorityIcon(widget.task.priority),
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),

          // العنوان والقسم
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.task.title.isNotEmpty
                      ? widget.task.title
                      : 'مهمة غير محددة',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${widget.task.department} • رقم ${widget.task.id}',
                  style: TextStyle(
                    fontSize: 12,
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

  /// حالة مضغوطة
  Widget _buildCompactStatusBadge() {
    return GestureDetector(
      onTap: () => _showStatusChangeDialog(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _getStatusColor(widget.task.status),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _getStatusColor(widget.task.status).withValues(alpha: 0.3),
              spreadRadius: 0,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          widget.task.status,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
        ),
      ),
    );
  }

  /// المعلومات الأساسية في تخطيط مضغوط
  Widget _buildCompactBasicInfo() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // الصف الأول: العميل والفني
          Row(
            children: [
              Expanded(
                child: _buildCompactInfoItem(
                  Icons.person,
                  'العميل',
                  widget.task.username,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactInfoItem(
                  Icons.engineering,
                  'الفني',
                  widget.task.technician,
                  Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // الصف الثاني: FBG والهاتف
          Row(
            children: [
              Expanded(
                child: _buildCompactInfoItem(
                  Icons.router,
                  'FBG',
                  widget.task.fbg,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactInfoItem(
                  Icons.phone,
                  'الهاتف',
                  widget.task.phone,
                  Colors.purple,
                ),
              ),
            ],
          ),

          // المبلغ إذا كان متوفر
          if (widget.task.amount.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildCompactInfoItem(
              Icons.monetization_on,
              'المبلغ',
              widget.task.amount,
              Colors.red,
            ),
          ],
        ],
      ),
    );
  }

  /// عنصر معلومات مضغوط
  Widget _buildCompactInfoItem(
      IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: color.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value.isNotEmpty ? value : 'غير متوفر',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // إضافة أيقونة النسخ للهاتف فقط
                    if (label == 'الهاتف' && value.isNotEmpty)
                      GestureDetector(
                        onTap: () => _copyPhoneNumber(value),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.content_copy,
                            size: 12,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    // إضافة أيقونة إرسال المهمة للفني
                    if (label == 'الفني' &&
                        value.isNotEmpty &&
                        value != 'غير متوفر')
                      GestureDetector(
                        onTap: () => _sendTaskToTechnician(value),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.send,
                            size: 12,
                            color: Colors.green,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDetailedInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Text(
                'التفاصيل الإضافية',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // تفاصيل في شبكة مضغوطة
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 6,
            children: [
              _buildCompactDetailItem('الموقع', widget.task.location),
              _buildCompactDetailItem('FAT', widget.task.fat),
              _buildCompactDetailItem('الأولوية', widget.task.priority),
              _buildCompactDetailItem(
                  'الإنشاء', DateFormat('MM/dd').format(widget.task.createdAt)),
            ],
          ),

          // الملاحظات والملخص
          if (widget.task.notes.isNotEmpty ||
              widget.task.summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            if (widget.task.notes.isNotEmpty)
              _buildExpandableText('ملاحظات', widget.task.notes),
            if (widget.task.summary.isNotEmpty)
              _buildExpandableText('الملخص', widget.task.summary),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactDetailItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value.isNotEmpty ? value : '-',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableText(String label, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// شريط الإجراءات المضغوط
  Widget _buildCompactActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // واتساب
          if (widget.task.phone.isNotEmpty)
            _buildCompactActionButton(
              Icons.message,
              'واتساب',
              Colors.green,
              () => _launchWhatsApp(widget.task.phone),
            ),

          // وكيل
          if (widget.currentUserRole == 'ليدر' ||
              widget.currentUserRole == 'مدير')
            _buildCompactActionButton(
              Icons.group,
              'وكيل',
              Colors.purple,
              _showAgentsDialog,
            ),

          // تعديل
          if (widget.currentUserRole == 'مدير' ||
              widget.currentUserRole == 'ليدر')
            _buildCompactActionButton(
              Icons.edit,
              'تعديل',
              Colors.blue,
              _showEditTaskDialog,
            ),

          // حذف
          if (widget.currentUserRole == 'مدير')
            _buildCompactActionButton(
              Icons.delete,
              'حذف',
              Colors.red,
              _confirmDeleteTask,
            ),
        ],
      ),
    );
  }

  Widget _buildCompactActionButton(
      IconData icon, String label, Color color, VoidCallback onPressed) {
    return Expanded(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: color,
              width: 2.0, // خط غامق
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.2),
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.bold, // نص غامق
                ),
              ),
            ],
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
    String selectedStatus = widget.task.status;
    final TextEditingController amountController =
        TextEditingController(text: widget.task.amount);
    final TextEditingController notesController =
        TextEditingController(text: widget.task.notes);

    showDialog(
      context: context,
      barrierDismissible: false, // منع إغلاق النافذة بالنقر خارجها
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height *
                    0.8, // ارتفاع ثابت بدلاً من constraints
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // العنوان
                    Row(
                      children: [
                        Icon(Icons.edit, color: Colors.blue),
                        const SizedBox(width: 8),
                        const Text(
                          'تغيير حالة المهمة',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // المحتوى القابل للتمرير
                    Expanded(
                      // استخدام Expanded بدلاً من Flexible
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            // 1. قائمة تغيير الحالة
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.blue.shade300, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.shade200
                                        .withValues(alpha: 0.3),
                                    spreadRadius: 1,
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '🔄 تغيير حالة المهمة:',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade800,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: Colors.blue.shade400,
                                          width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.blue.shade100
                                              .withValues(alpha: 0.5),
                                          spreadRadius: 1,
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 4),
                                    child: DropdownButton<String>(
                                      value: selectedStatus,
                                      isExpanded: true,
                                      underline: Container(),
                                      icon: Icon(Icons.arrow_drop_down,
                                          color: Colors.blue.shade600,
                                          size: 28),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue.shade800,
                                      ),
                                      items: _statuses.map((status) {
                                        return DropdownMenuItem(
                                          value: status,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 4),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 12,
                                                  height: 12,
                                                  decoration: BoxDecoration(
                                                    color:
                                                        _getStatusColor(status),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(status),
                                              ],
                                            ),
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
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // 2. مربع نص المبلغ
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.green.shade300, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.shade200
                                        .withValues(alpha: 0.3),
                                    spreadRadius: 1,
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '💰 المبلغ المطلوب:',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: Colors.green.shade400,
                                          width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.green.shade100
                                              .withValues(alpha: 0.5),
                                          spreadRadius: 1,
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: TextField(
                                      controller: amountController,
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600),
                                      inputFormatters: [
                                        // فلتر لقبول الأرقام الإنجليزية فقط
                                        FilteringTextInputFormatter.allow(
                                            RegExp(r'[0-9.]')),
                                        // تحويل الأرقام العربية إلى إنجليزية أثناء الكتابة
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
                                                offset: converted.length),
                                          );
                                        }),
                                      ],
                                      decoration: const InputDecoration(
                                        labelText: 'المبلغ',
                                        hintText:
                                            'أدخل المبلغ المطلوب (اختياري)',
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                        prefixIcon: Icon(Icons.attach_money,
                                            color: Colors.green),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // 3. مربع نص الملاحظات
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.orange.shade300, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.orange.shade200
                                        .withValues(alpha: 0.3),
                                    spreadRadius: 1,
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '📝 ملاحظات الفني:',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade800,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: Colors.orange.shade400,
                                          width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.orange.shade100
                                              .withValues(alpha: 0.5),
                                          spreadRadius: 1,
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: TextField(
                                      controller: notesController,
                                      maxLines: 4,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500),
                                      decoration: const InputDecoration(
                                        labelText: 'م��احظات',
                                        hintText:
                                            'اكتب أي ملاحظات إضافية (��ختياري)',
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                        prefixIcon: Icon(Icons.note_add,
                                            color: Colors.orange),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),

                    // الأزرار
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.grey.shade400, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.shade300
                                      .withValues(alpha: 0.3),
                                  spreadRadius: 1,
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: TextButton(
                              onPressed: () {
                                amountController.dispose();
                                notesController.dispose();
                                Navigator.of(context).pop();
                              },
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                backgroundColor: Colors.grey.shade200,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.cancel,
                                      color: Colors.grey.shade700, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'إلغاء',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.blue.shade400, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.shade300
                                      .withValues(alpha: 0.3),
                                  spreadRadius: 1,
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: () async {
                                // حفظ القيم قبل إغلاق النافذة
                                final String newStatus = selectedStatus;
                                final String amount =
                                    amountController.text.trim();
                                final String notes =
                                    notesController.text.trim();

                                // إغلاق النافذة أولاً
                                Navigator.of(context).pop();

                                // انتظار قصير للتأكد من إغلاق النافذة تماماً
                                await Future.delayed(
                                    const Duration(milliseconds: 100));

                                // تنظيف الـ controllers بعد التأكد من إغلاق النافذة
                                try {
                                  amountController.dispose();
                                  notesController.dispose();
                                } catch (e) {
                                  // تجاهل أخطاء dispose إذا حدثت
                                  print('تم تجاهل خطأ dispose: $e');
                                }

                                // تحديث المهمة بعد إغلاق النافذة وتنظيف الـ controllers
                                _updateTaskStatus(
                                  newStatus,
                                  amount: amount,
                                  notes: notes,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                backgroundColor: Colors.blue,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.update,
                                      color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'تحديث المهمة',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
    print('🟦 [DEBUG] المبلغ: "$amount"');
    print('🟦 [DEBUG] الملاحظا��: "$notes"');

    try {
      final updatedTask = widget.task.copyWith(
        status: newStatus,
        amount: amount,
        notes: notes,
        closedAt: newStatus == 'مكتملة' || newStatus == 'ملغية'
            ? DateTime.now()
            : null,
      );

      print('🟦 [DEBUG] ت�� إنشاء المهمة المحدثة بنجاح');
      print('🟦 [DEBUG] معرف المهمة المحدثة: ${updatedTask.id}');
      print('🟦 [DEBUG] مبلغ المهمة المحدثة: "${updatedTask.amount}"');

      // تحديث المهمة محلياً أولاً
      print('🟦 [DEBUG] بدء التحديث المحلي...');
      widget.onStatusChanged(updatedTask);
      print('🟦 [DEBUG] تم التحديث المحلي بنجاح');

      // عرض رسالة التحديث المحلي
      if (mounted) {
        print('🟦 [DEBUG] عرض رسالة النجاح المحلي...');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تحديث حالة المهمة إلى: $newStatus'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // تحديث الحالة في Google Sheets بشكل متزامن
      print('🟦 [DEBUG] بدء التحديث في Google Sheets...');
      await _updateStatusInSheet(updatedTask);
      print('🟦 [DEBUG] تم التحديث في Google Sheets بنجاح');
    } catch (e, stackTrace) {
      print('🔴 [ERROR] خطأ في تحديث حالة المهمة: $e');
      print('🔴 [ERROR] Stack trace: $stackTrace');

      if (mounted) {
        // عرض الخطأ في نافذة يمكن نسخ محتواها
        _showErrorDialog('خطأ في تحديث المهمة', '''
تفاصيل الخطأ:
${e.toString()}

معلومات تقنية إضافية:
$stackTrace

البيانات المحاولة تحديثه��:
- الحالة: $newStatus
- المبلغ: $amount
- الملاحظات: $notes
- معرف المهمة: ${widget.task.id}
        ''');
      }
    }
  }

  /// تحديث حالة المهمة في Google Sheets
  Future<void> _updateStatusInSheet(Task task) async {
    try {
      // استخدام خدمة Google Sheets المحسنة
      await GoogleSheetsService.updateTaskStatus(task);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'تم تحديث الحالة والمبلغ والملاحظات في Google Sheets بنجاح'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating status in Google Sheets: $e');

      // محاولة التحديث اليدوي إذا فشلت الخدمة
      try {
        await _manualUpdateTaskInSheet(task);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'تم تحديث الحالة والمبلغ والملاحظات بنجاح (نسخة احتياطية)'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (manualError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ في تحديث الحالة: $manualError'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  /// تهيئة Sheets API - نفس طريقة agents_page.dart
  Future<void> _initializeSheetsAPI() async {
    if (_sheetsApi != null) return;

    try {
      // محاولة تحميل ملف service account
      String jsonString;
      try {
        jsonString = await rootBundle.loadString('assets/service_account.json');
      } catch (e) {
        debugPrint('تعذر العثور على ملف service_account.json: $e');
        throw 'ملف الاعتماد مفقود. يرجى التحقق من ملف service_account.json';
      }

      final accountCredentials =
          ServiceAccountCredentials.fromJson(jsonDecode(jsonString));
      final scopes = [sheets.SheetsApi.spreadsheetsScope];
      _client = await clientViaServiceAccount(accountCredentials, scopes);
      _sheetsApi = sheets.SheetsApi(_client!);

      debugPrint('✅ تم تهيئة Google Sheets API بنجاح!');
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة Sheets API: $e');
      throw 'فشل في تهيئة خدمة Google Sheets: ${e.toString()}';
    }
  }

  /// تحديث يدوي للمهمة في Google Sheets كنسخة احتياطية
  Future<void> _manualUpdateTaskInSheet(Task task) async {
    await _initializeSheetsAPI();

    if (_sheetsApi == null) {
      throw 'فشل في تهيئة API';
    }

    // قائمة بأسماء الأوراق المحتملة
    List<String> possibleSheetNames = [
      'المهام',
      'tasks',
      'Tasks',
      'TASKS',
      'مهام'
    ];

    bool updated = false;
    debugPrint('🔍 [Manual Update] البحث عن المهمة بمعرف: ${task.id}');

    for (String sheetName in possibleSheetNames) {
      try {
        debugPrint('📋 [Manual Update] البحث في ورقة: $sheetName');

        final range = '$sheetName!A2:Z';
        final response =
            await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);
        final rows = response.values ?? [];

        debugPrint(
            '📊 [Manual Update] عدد الصفوف في $sheetName: ${rows.length}');

        // البحث عن ال��همة بناءً على معرفها مع معالجة أنواع البيانات المختلفة
        int? rowIndex;

        for (int i = 0; i < rows.length; i++) {
          if (rows[i].isNotEmpty) {
            // تحويل كلا القيمتين إ��ى نص وإزالة المسافات
            String rowId = rows[i][0].toString().trim();
            String taskId = task.id.toString().trim();

            debugPrint(
                '🔍 [Manual Update] مقارنة: صف $i -> "$rowId" (نوع: ${rows[i][0].runtimeType}) مع "$taskId" (نوع: ${task.id.runtimeType})');

            // مقارنة مباشرة كنصوص
            bool isMatch = rowId == taskId;

            // مقارنة إضافية كأرقام إذا كانت القيم رقمية
            if (!isMatch) {
              try {
                double? rowIdNum = double.tryParse(rowId);
                double? taskIdNum = double.tryParse(taskId);
                if (rowIdNum != null && taskIdNum != null) {
                  isMatch = rowIdNum == taskIdNum;
                  debugPrint(
                      '🔢 [Manual Update] مقارنة رقمية: $rowIdNum == $taskIdNum -> $isMatch');
                }
              } catch (e) {
                // تجاهل أخطاء التحويل الرقمي
              }
            }

            if (isMatch) {
              rowIndex = i + 2; // +2 لأن الصفوف تبدأ من 1 والنطاق من A2
              debugPrint(
                  '✅ [Manual Update] تم العثور على المهمة في الصف: $rowIndex');
              break;
            }
          }
        }

        if (rowIndex != null) {
          debugPrint('🔄 [Manual Update] تحديث المهمة في الصف: $rowIndex');

          // تحديث الصف الكا��ل للمهمة
          final updateRange = '$sheetName!A$rowIndex:Q$rowIndex';

          final valueRange = sheets.ValueRange(
            range: updateRange,
            values: [
              [
                task.id, // الحفاظ على المعرف كما هو
                task.status,
                task.department,
                task.title,
                task.leader,
                task.technician,
                task.username,
                task.phone,
                task.fbg,
                task.fat,
                task.location,
                task.notes,
                task.createdAt.toIso8601String(),
                task.closedAt?.toIso8601String() ?? '',
                task.summary,
                task.priority,
                task.agents.join(','),
              ],
            ],
          );

          debugPrint('📝 [Manual Update] نطاق التحديث: $updateRange');
          debugPrint(
              '📋 [Manual Update] البيانات المراد تحدي��ها: المعرف=${task.id}, الحالة=${task.status}, ا��عنوان=${task.title}');

          await _sheetsApi!.spreadsheets.values.update(
            valueRange,
            spreadsheetId,
            updateRange,
            valueInputOption: 'USER_ENTERED',
          );

          debugPrint('✅ [Manual Update] تم تحديث المهمة بنجاح في $sheetName');
          updated = true;
          break; // نجح التحد��ث، توقف عن المحاولة
        } else {
          debugPrint(
              '❌ [Manual Update] لم يتم العثور على المهمة في $sheetName');
        }
      } catch (e) {
        debugPrint('⚠️ [Manual Update] خطأ في معالجة ورقة $sheetName: $e');
        // تج��هل الأخطاء وحاول الورقة التالية
        continue;
      }
    }

    if (!updated) {
      debugPrint('❌ [Manual Update] فشل في العثور على المهمة في جميع الأوراق');
      throw 'لم يتم العثور على المهمة بمعرف "${task.id}" في أي من أوراق Google Sheets';
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

  /// حذف المهمة من Google Sheets
  Future<void> _deleteTask() async {
    try {
      await _initializeSheetsAPI();

      if (_sheetsApi == null) {
        throw 'فشل في تهيئة API';
      }

      // البحث عن المهمة في الشيت وحذفها
      final range = 'المهام!A2:Z';
      final response =
          await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);
      final rows = response.values ?? [];

      int? rowIndex;
      for (int i = 0; i < rows.length; i++) {
        if (rows[i].isNotEmpty && rows[i][0] == widget.task.id) {
          rowIndex = i + 2; // +2 لأن الصفوف تبدأ من 1 والنطاق من A2
          break;
        }
      }

      if (rowIndex == null) {
        throw 'لم يتم العثور على المهمة في الشيت';
      }

      // حذف الصف
      final deleteRequest = sheets.DeleteDimensionRequest(
        range: sheets.DimensionRange(
          sheetId: 0, // ID الخاص بورقة المهام
          dimension: 'ROWS',
          startIndex: rowIndex - 1,
          endIndex: rowIndex,
        ),
      );

      final batchUpdateRequest = sheets.BatchUpdateSpreadsheetRequest(
        requests: [
          sheets.Request(deleteDimension: deleteRequest),
        ],
      );

      await _sheetsApi!.spreadsheets
          .batchUpdate(batchUpdateRequest, spreadsheetId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف المهمة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );

        // إعادة تحميل الصفحة أو إخفاء الكارت
        Navigator.of(context).pop(); // إذا كان في صفحة منفصلة
      }
    } catch (e) {
      debugPrint('Error deleting task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حذف المهمة: $e'),
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
              'هل أنت متأكد من رغبتك في حذف هذه المهمة؟\nسيتم حذفها نهائياً من Google Sheets.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إل��اء'),
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
      print('خطأ في بناء رسالة الواتساب: $e');
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
      case 'قيد التنفيذ':
        return Colors.orange;
      case 'مكتملة':
        return Colors.green;
      case 'ملغية':
        return Colors.red;
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

  /// جلب بيانات الوكلاء
  Future<void> _fetchAgentsData() async {
    if (isLoadingAgents) return;

    setState(() {
      isLoadingAgents = true;
    });

    try {
      await _initializeSheetsAPI();

      if (_sheetsApi == null) {
        throw 'فشل في تهيئة API';
      }

      debugPrint('جلب بيانات الوكلاء للمجموعة: ${widget.task.fbg}');

      // جلب بيانات الوكلاء من شيت الوكلاء (نفس آلية agents_page.dart)
      final range = 'الوكلاء!A2:AE'; // تعديل النطاق لجلب الأعمدة من 1 إلى 31
      final response =
          await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);
      final rows = response.values ?? [];

      if (rows.isEmpty) {
        setState(() {
          agents = [];
          isLoadingAgents = false;
        });
        return;
      }

      // تحويل البيانات لنفس تنسيق agents_page.dart
      final List<Map<String, dynamic>> fetchedAgents = rows.map((row) {
        final Map<String, dynamic> agentData = {
          'group': row.isNotEmpty ? row[0].toString() : '', // اسم المجموعة
        };
        for (int i = 1; i < row.length; i += 2) {
          if (i + 1 < row.length) {
            final name = row[i]?.toString() ?? '';
            final phone = row[i + 1]?.toString() ?? '';
            if (name.isNotEmpty && phone.isNotEmpty) {
              agentData['agent${(i + 1) ~/ 2}'] = {
                'name': name,
                'phone': phone
              };
            }
          }
        }
        return agentData;
      }).toList();

      // فلترة البيانات حسب FBG المرسل (نفس آلية agents_page.dart)
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
      debugPrint('❌ خطأ في جلب بيانات الوكلاء: $e');
      setState(() {
        isLoadingAgents = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في جلب بيانات الوكلاء: $e'),
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
          debugPrint('❌ خطأ في فتح الواتساب (ديسكتوب): $e');
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
      debugPrint('❌ خطأ في نسخ تفاصيل المهمة: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في نسخ تفاصيل المهمة: $e'),
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

      // تحديث في Google Sheets
      _updateStatusInSheet(updatedTask);

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تعيين المهمة للوكيل $agentName'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('خطأ في تعيين المهمة للوكيل: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تعيين المهمة: $e'),
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
      debugPrint('خطأ في إرسال المهمة للفني: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إرسال المهمة للفني: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// البحث عن رقم هاتف الفني في قاعدة البيانات
  Future<String> _getTechnicianPhoneNumber(String technicianName) async {
    try {
      // التحقق أولاً من وجود رقم هاتف الفني في المهمة نفسها
      if (widget.task.technicianPhone.isNotEmpty) {
        return widget.task.technicianPhone;
      }

      // البحث في شيت الفنيين إذا لم يكن متوفراً في المهمة
      await _initializeSheetsAPI();

      if (_sheetsApi == null) {
        return '';
      }

      // قائمة بأسماء الأوراق المحتملة للفنيين
      List<String> possibleSheetNames = [
        'الفنيين',
        'فنيين',
        'Technicians',
        'technicians'
      ];

      for (String sheetName in possibleSheetNames) {
        try {
          final range = '$sheetName!A2:C';
          final response =
              await _sheetsApi!.spreadsheets.values.get(spreadsheetId, range);
          final rows = response.values ?? [];

          for (var row in rows) {
            if (row.length >= 2) {
              String name = row[0]?.toString().trim() ?? '';
              String phone = row[1]?.toString().trim() ?? '';

              if (name.toLowerCase() == technicianName.toLowerCase() &&
                  phone.isNotEmpty) {
                return phone;
              }
            }
          }
        } catch (e) {
          // تجاهل أخطاء الأوراق غير الموجودة
          continue;
        }
      }

      return '';
    } catch (e) {
      debugPrint('خطأ في البحث عن رقم هاتف الفني: $e');
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
