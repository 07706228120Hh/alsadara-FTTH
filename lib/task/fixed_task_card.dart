import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/task.dart';
import 'package:intl/intl.dart';

/// نسخة مصححة من TaskCard مع عرض جميل لعنوان المهمة
class FixedTaskCard extends StatefulWidget {
  final Task task;
  final String currentUserRole;
  final String currentUserName;
  final Function(Task) onStatusChanged;

  const FixedTaskCard({
    super.key,
    required this.task,
    required this.currentUserRole,
    required this.currentUserName,
    required this.onStatusChanged,
  });

  @override
  State<FixedTaskCard> createState() => _FixedTaskCardState();
}

class _FixedTaskCardState extends State<FixedTaskCard> {
  bool isLoading = false;
  List<Map<String, dynamic>> agents = [];
  String? errorMessage;
  bool showDetails = false;

  @override
  Widget build(BuildContext context) {
    final currentUserName = widget.currentUserName.trim();
    final taskTechnician = widget.task.technician.trim();

    if (widget.currentUserRole == 'فني' && taskTechnician != currentUserName) {
      return _buildNoTasksMessage();
    }

    return Card(
      elevation: 6,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _getPriorityColor(widget.task.priority).withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
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
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              showDetails = !showDetails;
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // عنوان المهمة الجميل
                _buildTaskHeader(),
                const SizedBox(height: 16),

                // المعلومات الأساسية
                _buildBasicInfo(),

                // التفاصيل المتقدمة
                if (showDetails) ...[
                  const Divider(height: 24),
                  _buildDetailedInfo(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade600,
            Colors.blue.shade700,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.3),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.assignment,
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.task.title.isNotEmpty
                      ? widget.task.title
                      : 'مهمة بدون عنوان',
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.task.department,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // حالة المهمة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getStatusColor(widget.task.status),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  spreadRadius: 1,
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              widget.task.status,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.person, 'الفني', widget.task.technician),
          const Divider(height: 16),
          _buildInfoRow(Icons.router, 'FBG', widget.task.fbg),
          const Divider(height: 16),
          _buildInfoRow(
              Icons.account_circle, 'اسم المستخدم', widget.task.username),
          const Divider(height: 16),
          _buildInfoRow(Icons.phone, 'رقم الهاتف', widget.task.phone),
          if (widget.task.amount.isNotEmpty) ...[
            const Divider(height: 16),
            _buildInfoRow(Icons.attach_money, 'المبلغ', widget.task.amount),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: Colors.blue.shade700,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value.isNotEmpty ? value : 'غير متوفر',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailedInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'التفاصيل الإضافية',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade800,
            ),
          ),
          const SizedBox(height: 12),
          _buildDetailRow('الموقع', widget.task.location),
          _buildDetailRow('FAT', widget.task.fat),
          _buildDetailRow('الأولوية', widget.task.priority),
          _buildDetailRow('ملاحظات', widget.task.notes),
          _buildDetailRow('الملخص', widget.task.summary),
          _buildDetailRow(
            'تاريخ الإنشاء',
            DateFormat('yyyy-MM-dd – HH:mm').format(widget.task.createdAt),
          ),
          if (widget.task.closedAt != null)
            _buildDetailRow(
              'تاريخ الإكمال',
              DateFormat('yyyy-MM-dd – HH:mm').format(widget.task.closedAt!),
            ),

          // أزرار الإجراءات
          const SizedBox(height: 16),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : 'غير متوفر',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (widget.currentUserRole == 'مدير' ||
            widget.currentUserRole == 'ليدر')
          ElevatedButton.icon(
            onPressed: () {
              // TODO: إضافة وظيفة تعديل المهمة
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('سيتم إضافة وظيفة التعديل قريباً')),
              );
            },
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('تعديل'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        const SizedBox(width: 8),
        if (widget.task.phone.isNotEmpty)
          ElevatedButton.icon(
            onPressed: () => _launchWhatsApp(widget.task.phone),
            icon: const Icon(Icons.message, size: 16),
            label: const Text('واتساب'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        const SizedBox(width: 8),
        if (widget.currentUserRole == 'مدير')
          ElevatedButton.icon(
            onPressed: () {
              // TODO: إضافة وظيفة حذف المهمة
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('سيتم إضافة وظيفة الحذف قريباً')),
              );
            },
            icon: const Icon(Icons.delete, size: 16),
            label: const Text('حذف'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
      ],
    );
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

  Future<void> _launchWhatsApp(String phone) async {
    String formattedPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (formattedPhone.startsWith('0')) {
      formattedPhone = '964${formattedPhone.substring(1)}';
    }

    final url = 'https://wa.me/$formattedPhone';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل في فتح واتساب: $e')),
      );
    }
  }

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
}
