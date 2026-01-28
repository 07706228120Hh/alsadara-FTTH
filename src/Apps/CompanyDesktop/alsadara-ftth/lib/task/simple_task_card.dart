import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/task.dart';
import 'package:intl/intl.dart';

/// نسخة بديلة ومبسطة من TaskCard خالية من الأخطاء
class SimpleTaskCard extends StatefulWidget {
  final Task task;
  final String currentUserRole;
  final String currentUserName;
  final Function(Task) onStatusChanged;

  const SimpleTaskCard({
    super.key,
    required this.task,
    required this.currentUserRole,
    required this.currentUserName,
    required this.onStatusChanged,
  });

  @override
  State<SimpleTaskCard> createState() => _SimpleTaskCardState();
}

class _SimpleTaskCardState extends State<SimpleTaskCard> {
  bool showDetails = false;

  @override
  Widget build(BuildContext context) {
    // فحص صلاحيات العرض
    final currentUserName = widget.currentUserName.trim();
    final taskTechnician = widget.task.technician.trim();

    if (widget.currentUserRole == 'فني' && taskTechnician != currentUserName) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            showDetails = !showDetails;
          });
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _getPriorityColor(widget.task.priority),
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // عنوان المهمة
                _buildTaskTitle(),
                const SizedBox(height: 12),

                // المعلومات الأساسية
                _buildBasicInfo(),

                // التفاصيل (تظهر عند الضغط)
                if (showDetails) ...[
                  const Divider(height: 20),
                  _buildDetailedInfo(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskTitle() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade600,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.assignment,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.task.title.isNotEmpty
                  ? widget.task.title
                  : 'مهمة بدون عنوان',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // شارة الحالة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getStatusColor(widget.task.status),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              widget.task.status,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfo() {
    return Column(
      children: [
        _buildInfoRow('الفني:', widget.task.technician),
        _buildInfoRow('القسم:', widget.task.department),
        _buildInfoRow('اسم المستخدم:', widget.task.username),
        _buildInfoRow('رقم الهاتف:', widget.task.phone),
        if (widget.task.amount.isNotEmpty)
          _buildInfoRow('المبلغ:', widget.task.amount),
        _buildInfoRow('FBG:', widget.task.fbg),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
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

  Widget _buildDetailedInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'التفاصيل الإضافية',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade700,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow('الموقع:', widget.task.location),
        _buildInfoRow('FAT:', widget.task.fat),
        _buildInfoRow('الأولوية:', widget.task.priority),
        _buildInfoRow('الليدر:', widget.task.leader),
        _buildInfoRow('ملاحظات:', widget.task.notes),
        _buildInfoRow('الملخص:', widget.task.summary),
        _buildInfoRow(
          'تاريخ الإنشاء:',
          DateFormat('yyyy-MM-dd HH:mm').format(widget.task.createdAt),
        ),
        if (widget.task.closedAt != null)
          _buildInfoRow(
            'تاريخ الإكمال:',
            DateFormat('yyyy-MM-dd HH:mm').format(widget.task.closedAt!),
          ),

        // أزرار الإجراءات
        const SizedBox(height: 12),
        _buildActionButtons(),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Wrap(
      spacing: 8,
      children: [
        if (widget.task.phone.isNotEmpty)
          ElevatedButton.icon(
            onPressed: () => _launchWhatsApp(widget.task.phone),
            icon: const Icon(Icons.message, size: 14),
            label: const Text('واتساب'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
        if (widget.currentUserRole == 'مدير' ||
            widget.currentUserRole == 'ليدر')
          ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('وظيفة التعديل قيد التطوير')),
              );
            },
            icon: const Icon(Icons.edit, size: 14),
            label: const Text('تعديل'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
        if (widget.currentUserRole == 'مدير')
          ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('وظيفة الحذف قيد التطوير')),
              );
            },
            icon: const Icon(Icons.delete, size: 14),
            label: const Text('حذف'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
      ],
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل في فتح واتساب: $e')),
        );
      }
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
