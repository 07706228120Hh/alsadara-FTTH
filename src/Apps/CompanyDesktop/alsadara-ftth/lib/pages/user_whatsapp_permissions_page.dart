/// صفحة إدارة صلاحيات الواتساب للموظف
/// يستخدمها مدير الشركة لتفعيل/تعطيل صلاحيات الواتساب للموظفين
library;

import 'package:flutter/material.dart';
import '../../models/tenant_user.dart';
import '../../whatsapp/services/whatsapp_permissions_service.dart';
import '../frontend/tokens/sd_colors.dart' show SdColors;
import '../frontend/components/sd_app_bar.dart';

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
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: success ? SdColors.success : SdColors.danger,
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
      appBar: SdAppBar(title: 'صلاحيات الواتساب', subtitle: widget.user.fullName.isNotEmpty
                  ? widget.user.fullName
                  : widget.user.username, actions: [
          if (_hasChanges && !_isSaving && !isAdmin)
            TextButton.icon(
              onPressed: _savePermissions,
              icon: const Icon(Icons.save, color: Colors.white),
              label: Text(
                'حفظ',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
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
        ]),
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
              color: SdColors.faint,
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد أنظمة واتساب متاحة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: SdColors.muted,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'الشركة غير مرخصة لاستخدام أي نظام واتساب.\nتواصل مع مدير النظام لتفعيل الأنظمة.',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                color: SdColors.faint,
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
                color: SdColors.warningTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.admin_panel_settings,
                size: 48,
                color: SdColors.warning,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'هذا المستخدم مدير',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: SdColors.warning,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'المدراء لديهم جميع صلاحيات الواتساب تلقائياً\n'
              'لا يمكن تعديل صلاحياتهم',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                color: SdColors.muted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // عرض الأنظمة المتاحة للشركة
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SdColors.successTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SdColors.successTintEdge),
              ),
              child: Column(
                children: [
                  Text(
                    'الأنظمة المتاحة للشركة:',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      color: SdColors.success,
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
              const Icon(Icons.check_circle, color: SdColors.success, size: 16),
              const SizedBox(width: 4),
              Text(
                names[key] ?? key,
                style: TextStyle(fontFamily: 'Cairo', fontSize: 12),
              ),
            ],
          ),
        );
      }
    });

    if (systems.isEmpty) {
      systems.add(Text(
        'لا توجد أنظمة مفعلة',
        style: TextStyle(
          fontFamily: 'Cairo',
          color: SdColors.faint,
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
                  SdColors.infoTint,
                  SdColors.primaryTint,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SdColors.infoTintEdge),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: SdColors.info,
                  radius: 24,
                  child: Text(
                    widget.user.username[0].toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'Cairo',
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
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${widget.user.role.arabicName} • @${widget.user.username}',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: SdColors.muted,
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
              color: SdColors.whatsapp.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 20, color: SdColors.whatsappEdge),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الأنظمة المتاحة للشركة: ${_getEnabledSystemsText()}',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: SdColors.whatsappEdge,
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
                label: Text('تفعيل الكل', style: TextStyle(fontFamily: 'Cairo')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.success,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _disableAll,
                icon: const Icon(Icons.cancel, size: 18),
                label: Text('تعطيل الكل', style: TextStyle(fontFamily: 'Cairo')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SdColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // صلاحيات الإرسال
          Text(
            '📤 صلاحيات الإرسال',
            style: TextStyle(
              fontFamily: 'Cairo',
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
            color: SdColors.success,
          ),
          _buildPermissionCard(
            key: 'send_expiring',
            title: 'إرسال تذكيرات قرب الانتهاء',
            description: 'إرسال تنبيهات للمشتركين قبل انتهاء اشتراكهم',
            icon: Icons.warning_amber,
            color: SdColors.warning,
          ),
          _buildPermissionCard(
            key: 'send_expired',
            title: 'إرسال رسائل المنتهي + عروض',
            description: 'إرسال رسائل للمشتركين المنتهية اشتراكاتهم',
            icon: Icons.event_busy,
            color: SdColors.danger,
          ),
          _buildPermissionCard(
            key: 'send_notification',
            title: 'إرسال تبليغات عامة',
            description: 'إرسال إشعارات وتبليغات لمجموعة مشتركين',
            icon: Icons.campaign,
            color: SdColors.info,
          ),

          const SizedBox(height: 24),

          // صلاحيات متقدمة
          Text(
            '⚙️ صلاحيات متقدمة',
            style: TextStyle(
              fontFamily: 'Cairo',
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
            color: SdColors.platformBase,
          ),
          _buildPermissionCard(
            key: 'bulk_send',
            title: 'الإرسال الجماعي',
            description: 'إرسال رسائل لعدة مشتركين دفعة واحدة',
            icon: Icons.send,
            color: SdColors.accent,
          ),
          _buildPermissionCard(
            key: 'view_conversations',
            title: 'عرض المحادثات',
            description: 'الوصول لسجل المحادثات والرسائل المرسلة',
            icon: Icons.forum,
            color: SdColors.primary,
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
        color: isEnabled ? color.withOpacity(0.05) : SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isEnabled ? color.withOpacity(0.4) : SdColors.edge,
          width: isEnabled ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isEnabled ? color : SdColors.faint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: isEnabled ? color : SdColors.muted,
          ),
        ),
        subtitle: Text(
          description,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11,
            color: SdColors.muted,
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
