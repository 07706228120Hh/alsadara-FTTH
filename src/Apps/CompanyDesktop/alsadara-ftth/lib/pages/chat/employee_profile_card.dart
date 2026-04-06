import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/chat_service.dart';

/// بطاقة ملف الموظف — تظهر عند الضغط على الصورة/الاسم في المحادثة
class EmployeeProfileCard extends StatefulWidget {
  final String userId;
  const EmployeeProfileCard({super.key, required this.userId});

  // ═══════════════════════════════════════
  // Static show — Dialog على سطح المكتب، BottomSheet على الموبايل
  // ═══════════════════════════════════════
  static void show(BuildContext context, String userId) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width > 600 ? 380 : MediaQuery.of(context).size.width * 0.9,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SingleChildScrollView(
                child: EmployeeProfileCard(userId: userId),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<EmployeeProfileCard> createState() => _EmployeeProfileCardState();
}

class _EmployeeProfileCardState extends State<EmployeeProfileCard> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ChatService.instance.getUserProfileCard(widget.userId);
      if (!mounted) return;
      if (data == null) {
        setState(() {
          _error = 'لم يتم العثور على بيانات الموظف';
          _loading = false;
        });
      } else {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'حدث خطأ أثناء تحميل البيانات';
        _loading = false;
      });
    }
  }

  // ═══════════════════════════════════════
  // Role mapping
  // ═══════════════════════════════════════
  String _formatDateTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  String _getRoleDisplayName(dynamic role, String? roleName) {
    // أولاً: ترجمة roleName الإنجليزي
    if (roleName != null && roleName.isNotEmpty) {
      return switch (roleName) {
        'Citizen' => 'مواطن',
        'Employee' => 'موظف',
        'Technician' => 'فني',
        'TechnicalLeader' => 'قائد فني',
        'Manager' => 'مشرف',
        'CompanyAdmin' => 'مدير شركة',
        'Admin' => 'مسؤول',
        'SuperAdmin' => 'مسؤول أعلى',
        _ => roleName,
      };
    }
    // ثانياً: حسب الرقم
    if (role is int) {
      return switch (role) {
        0 => 'مواطن', 10 => 'موظف', 12 => 'فني',
        13 => 'قائد فني', 14 => 'مشرف', 20 => 'مدير شركة',
        90 => 'مسؤول', 100 => 'مسؤول أعلى', _ => 'موظف',
      };
    }
    return 'غير محدد';
  }

  // ═══════════════════════════════════════
  // Build
  // ═══════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    final d = _data!;
    final fullName = d['fullName'] as String? ?? '';
    final phone = d['phoneNumber'] as String? ?? '';
    final email = d['email'] as String?;
    final profileImg = d['profileImageUrl'] as String?;
    final department = d['department'] as String?;
    final departments = d['departments'] as List?;
    final role = d['role'];
    final roleName = d['roleName'] as String?;
    final center = d['center'] as String?;
    final employeeCode = d['employeeCode'] as String?;
    final isActive = d['isActive'] == true;
    final lastLogin = d['lastLoginAt'] as String?;

    final deptDisplay = department ?? (departments != null && departments.isNotEmpty
        ? departments.map((d) => d is Map ? (d['name'] ?? d['nameAr'] ?? '') : d.toString()).join('، ')
        : null);
    final roleDisplay = _getRoleDisplayName(role, roleName);

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── صورة الملف الشخصي ──
          CircleAvatar(
            radius: 40,
            backgroundImage: profileImg != null && profileImg.isNotEmpty ? NetworkImage(profileImg) : null,
            child: profileImg == null || profileImg.isEmpty
                ? const Icon(Icons.person, size: 40)
                : null,
          ),
          const SizedBox(height: 12),

          // ── الاسم ──
          Text(
            fullName,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),

          // ── حالة النشاط ──
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isActive ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isActive ? 'نشط' : 'غير نشط',
                style: TextStyle(
                  color: isActive ? Colors.green.shade700 : Colors.red.shade700,
                  fontSize: 13,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // ── تفاصيل ──
          if (phone.isNotEmpty)
            _InfoRow(
              icon: Icons.phone_android,
              label: phone,
              onTap: () {
                Clipboard.setData(ClipboardData(text: phone));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم النسخ'), duration: Duration(seconds: 1)),
                );
              },
            ),
          if (email != null && email.isNotEmpty)
            _InfoRow(icon: Icons.email_outlined, label: email),
          if (deptDisplay != null && deptDisplay.isNotEmpty)
            _InfoRow(icon: Icons.business, label: deptDisplay),
          if (roleDisplay.isNotEmpty)
            _InfoRow(icon: Icons.badge_outlined, label: roleDisplay),
          if (center != null && center.isNotEmpty)
            _InfoRow(icon: Icons.location_on_outlined, label: center),
          if (employeeCode != null && employeeCode.isNotEmpty)
            _InfoRow(icon: Icons.numbers, label: employeeCode),
          if (lastLogin != null && lastLogin.isNotEmpty)
            _InfoRow(icon: Icons.access_time, label: 'آخر دخول: ${_formatDateTime(lastLogin)}'),

          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 12),

          // ── أزرار الإجراءات ──
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openDirectChat(context),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('محادثة خاصة'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: phone.isNotEmpty ? () => _callPhone(phone) : null,
                  icon: const Icon(Icons.phone_outlined, size: 18),
                  label: const Text('اتصال'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // Actions
  // ═══════════════════════════════════════

  Future<void> _openDirectChat(BuildContext context) async {
    Navigator.of(context).pop(); // أغلق البطاقة أولاً
    try {
      // type 0 = محادثة خاصة (direct)
      await ChatService.instance.createRoomPost(
        type: 0,
        memberIds: [widget.userId],
      );
    } catch (_) {
      // silent — ممكن الغرفة موجودة مسبقاً
    }
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // fallback: نسخ الرقم
      Clipboard.setData(ClipboardData(text: phone));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم نسخ الرقم'), duration: Duration(seconds: 1)),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// صف معلومات واحد
// ═══════════════════════════════════════════════════════════════
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _InfoRow({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          if (onTap != null)
            const Icon(Icons.copy, size: 16, color: Colors.grey),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: row,
      );
    }
    return row;
  }
}
