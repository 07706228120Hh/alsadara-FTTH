/// صفحة إدارة صلاحيات الواتساب للموظف
/// يستخدمها مدير الشركة لتفعيل/تعطيل صلاحيات الواتساب للموظفين
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/tenant_user.dart';
import '../../whatsapp/services/whatsapp_permissions_service.dart';

class UserWhatsAppPermissionsPage extends StatefulWidget {
  final String tenantId;
  final TenantUser user;

  const UserWhatsAppPermissionsPage({
    super.key,
    required this.tenantId,
    required this.user,
  });

  @override
  State<UserWhatsAppPermissionsPage> createState() =>
      _UserWhatsAppPermissionsPageState();
}

class _UserWhatsAppPermissionsPageState
    extends State<UserWhatsAppPermissionsPage> {
  Map<String, bool> _permissions = {};
  Map<String, bool> _tenantPermissions = {};
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    setState(() => _isLoading = true);

    // تحميل صلاحيات الشركة (لمعرفة الأنظمة المتاحة)
    _tenantPermissions =
        await WhatsAppPermissionsService.getTenantWhatsAppPermissions(
            widget.tenantId);

    // تحميل صلاحيات الموظف
    _permissions = await WhatsAppPermissionsService.getUserWhatsAppPermissions(
      tenantId: widget.tenantId,
      oderId: widget.user.id,
    );

    setState(() => _isLoading = false);
  }

  Future<void> _savePermissions() async {
    setState(() => _isSaving = true);

    final success =
        await WhatsAppPermissionsService.updateUserWhatsAppPermissions(
      tenantId: widget.tenantId,
      userId: widget.user.id,
      permissions: _permissions,
    );

    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? '✅ تم حفظ الصلاحيات بنجاح' : '❌ فشل في حفظ الصلاحيات',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );

      if (success) {
        setState(() => _hasChanges = false);
      }
    }
  }

  void _togglePermission(String key, bool value) {
    setState(() {
      _permissions[key] = value;
      _hasChanges = true;
    });
  }

  void _enableAll() {
    setState(() {
      _permissions.updateAll((key, value) => true);
      _hasChanges = true;
    });
  }

  void _disableAll() {
    setState(() {
      _permissions.updateAll((key, value) => false);
      _hasChanges = true;
    });
  }

  bool get _hasAnyWhatsAppSystem {
    return _tenantPermissions.values.any((v) => v == true);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.user.role == UserRole.admin;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'صلاحيات الواتساب',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              widget.user.fullName.isNotEmpty
                  ? widget.user.fullName
                  : widget.user.username,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF25D366),
        foregroundColor: Colors.white,
        actions: [
          if (_hasChanges && !_isSaving && !isAdmin)
            TextButton.icon(
              onPressed: _savePermissions,
              icon: const Icon(Icons.save, color: Colors.white),
              label: Text(
                'حفظ',
                style: GoogleFonts.cairo(color: Colors.white),
              ),
            ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_hasAnyWhatsAppSystem
              ? _buildNoSystemsMessage()
              : isAdmin
                  ? _buildAdminMessage()
                  : _buildPermissionsList(),
    );
  }

  Widget _buildNoSystemsMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.block,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد أنظمة واتساب متاحة',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'الشركة غير مرخصة لاستخدام أي نظام واتساب.\nتواصل مع مدير النظام لتفعيل الأنظمة.',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.admin_panel_settings,
                size: 48,
                color: Colors.amber.shade700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'هذا المستخدم مدير',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.amber.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'المدراء لديهم جميع صلاحيات الواتساب تلقائياً\n'
              'لا يمكن تعديل صلاحياتهم',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // عرض الأنظمة المتاحة للشركة
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                children: [
                  Text(
                    'الأنظمة المتاحة للشركة:',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._buildEnabledSystemsList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildEnabledSystemsList() {
    final systems = <Widget>[];
    final names = WhatsAppPermissionsService.systemNames;

    _tenantPermissions.forEach((key, value) {
      if (value == true) {
        systems.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 16),
              const SizedBox(width: 4),
              Text(
                names[key] ?? key,
                style: GoogleFonts.cairo(fontSize: 12),
              ),
            ],
          ),
        );
      }
    });

    if (systems.isEmpty) {
      systems.add(Text(
        'لا توجد أنظمة مفعلة',
        style: GoogleFonts.cairo(
          color: Colors.grey,
          fontSize: 12,
        ),
      ));
    }

    return systems;
  }

  Widget _buildPermissionsList() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // معلومات المستخدم
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blue.shade50,
                  Colors.indigo.shade50,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.shade400,
                  radius: 24,
                  child: Text(
                    widget.user.username[0].toUpperCase(),
                    style: GoogleFonts.cairo(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.user.fullName.isNotEmpty
                            ? widget.user.fullName
                            : widget.user.username,
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${widget.user.role.arabicName} • @${widget.user.username}',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // الأنظمة المتاحة للشركة
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 20, color: Color(0xFF128C7E)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الأنظمة المتاحة للشركة: ${_getEnabledSystemsText()}',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: const Color(0xFF128C7E),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // أزرار تفعيل/تعطيل الكل
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _enableAll,
                icon: const Icon(Icons.check_circle, size: 18),
                label: Text('تفعيل الكل', style: GoogleFonts.cairo()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _disableAll,
                icon: const Icon(Icons.cancel, size: 18),
                label: Text('تعطيل الكل', style: GoogleFonts.cairo()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // صلاحيات الإرسال
          Text(
            '📤 صلاحيات الإرسال',
            style: GoogleFonts.cairo(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          _buildPermissionCard(
            key: 'send_renewal',
            title: 'إرسال رسائل التجديد',
            description: 'إرسال رسائل بعد تجديد الاشتراك',
            icon: Icons.check_circle_outline,
            color: Colors.green,
          ),
          _buildPermissionCard(
            key: 'send_expiring',
            title: 'إرسال تذكيرات قرب الانتهاء',
            description: 'إرسال تنبيهات للمشتركين قبل انتهاء اشتراكهم',
            icon: Icons.warning_amber,
            color: Colors.orange,
          ),
          _buildPermissionCard(
            key: 'send_expired',
            title: 'إرسال رسائل المنتهي + عروض',
            description: 'إرسال رسائل للمشتركين المنتهية اشتراكاتهم',
            icon: Icons.event_busy,
            color: Colors.red,
          ),
          _buildPermissionCard(
            key: 'send_notification',
            title: 'إرسال تبليغات عامة',
            description: 'إرسال إشعارات وتبليغات لمجموعة مشتركين',
            icon: Icons.campaign,
            color: Colors.blue,
          ),

          const SizedBox(height: 24),

          // صلاحيات متقدمة
          Text(
            '⚙️ صلاحيات متقدمة',
            style: GoogleFonts.cairo(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          _buildPermissionCard(
            key: 'edit_templates',
            title: 'تعديل قوالب الرسائل',
            description: 'تعديل قوالب رسائل التجديد والإشعارات',
            icon: Icons.edit_note,
            color: Colors.purple,
          ),
          _buildPermissionCard(
            key: 'bulk_send',
            title: 'الإرسال الجماعي',
            description: 'إرسال رسائل لعدة مشتركين دفعة واحدة',
            icon: Icons.send,
            color: Colors.teal,
          ),
          _buildPermissionCard(
            key: 'view_conversations',
            title: 'عرض المحادثات',
            description: 'الوصول لسجل المحادثات والرسائل المرسلة',
            icon: Icons.forum,
            color: Colors.indigo,
          ),
        ],
      ),
    );
  }

  String _getEnabledSystemsText() {
    final enabled = <String>[];
    final names = WhatsAppPermissionsService.systemNames;

    _tenantPermissions.forEach((key, value) {
      if (value == true) {
        enabled.add(names[key]?.split(' ').first ?? key);
      }
    });

    return enabled.isEmpty ? 'لا يوجد' : enabled.join('، ');
  }

  Widget _buildPermissionCard({
    required String key,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    final isEnabled = _permissions[key] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isEnabled ? color.withOpacity(0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isEnabled ? color.withOpacity(0.4) : Colors.grey.shade300,
          width: isEnabled ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isEnabled ? color : Colors.grey.shade400,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        title: Text(
          title,
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: isEnabled ? color : Colors.grey.shade600,
          ),
        ),
        subtitle: Text(
          description,
          style: GoogleFonts.cairo(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        trailing: Switch(
          value: isEnabled,
          onChanged: (value) => _togglePermission(key, value),
          activeColor: color,
        ),
      ),
    );
  }
}
