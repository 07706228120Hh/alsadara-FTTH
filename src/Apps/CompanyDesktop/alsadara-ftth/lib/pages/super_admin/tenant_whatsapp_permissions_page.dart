/// صفحة إدارة صلاحيات الواتساب للشركة
/// يستخدمها Super Admin لتفعيل/تعطيل أنظمة الواتساب للشركة
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/tenant.dart';
import '../../whatsapp/services/whatsapp_permissions_service.dart';

class TenantWhatsAppPermissionsPage extends StatefulWidget {
  final Tenant tenant;

  const TenantWhatsAppPermissionsPage({super.key, required this.tenant});

  @override
  State<TenantWhatsAppPermissionsPage> createState() =>
      _TenantWhatsAppPermissionsPageState();
}

class _TenantWhatsAppPermissionsPageState
    extends State<TenantWhatsAppPermissionsPage> {
  Map<String, bool> _permissions = {};
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

    final perms = await WhatsAppPermissionsService.getTenantWhatsAppPermissions(
        widget.tenant.id);

    setState(() {
      _permissions = perms;
      _isLoading = false;
    });
  }

  Future<void> _savePermissions() async {
    setState(() => _isSaving = true);

    final success =
        await WhatsAppPermissionsService.updateTenantWhatsAppPermissions(
      tenantId: widget.tenant.id,
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

  @override
  Widget build(BuildContext context) {
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
              widget.tenant.name,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF25D366), // لون الواتساب
        foregroundColor: Colors.white,
        actions: [
          if (_hasChanges && !_isSaving)
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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // شرح الصفحة
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF25D366).withOpacity(0.1),
                          const Color(0xFF128C7E).withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF25D366).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Color(0xFF25D366), size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'حدد أنظمة الواتساب المتاحة لهذه الشركة.\n'
                            'الأنظمة المعطلة لن تظهر لأي مستخدم في الشركة.',
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              color: const Color(0xFF128C7E),
                              height: 1.5,
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

                  // قائمة الأنظمة
                  Text(
                    'أنظمة الواتساب المتاحة',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // الواتساب العادي
                  _buildSystemCard(
                    key: 'whatsapp_normal',
                    title: 'الواتساب العادي (Desktop)',
                    description:
                        'إرسال الرسائل عبر تطبيق WhatsApp Desktop المثبت على الجهاز',
                    icon: Icons.computer,
                    color: const Color(0xFF25D366),
                  ),

                  // واتساب ويب
                  _buildSystemCard(
                    key: 'whatsapp_web',
                    title: 'واتساب ويب الداخلي',
                    description:
                        'استخدام واتساب ويب داخل التطبيق مباشرة بدون فتح المتصفح',
                    icon: Icons.web,
                    color: const Color(0xFF128C7E),
                  ),

                  // واتساب السيرفر
                  _buildSystemCard(
                    key: 'whatsapp_server',
                    title: 'واتساب السيرفر (VPS)',
                    description:
                        'إرسال عبر سيرفر خارجي (whatsapp-web.js) - يتطلب إعداد السيرفر',
                    icon: Icons.dns,
                    color: const Color(0xFF075E54),
                    isPremium: true,
                  ),

                  // واتساب API
                  _buildSystemCard(
                    key: 'whatsapp_api',
                    title: 'واتساب API (Meta Business)',
                    description:
                        'واجهة Meta الرسمية - قوالب معتمدة، موثوقية عالية، تكلفة إضافية',
                    icon: Icons.api,
                    color: const Color(0xFF1877F2),
                    isPremium: true,
                  ),

                  const SizedBox(height: 24),

                  // ملاحظات
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lightbulb_outline,
                                color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'ملاحظات هامة',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildNote(
                            '• مدير الشركة يمكنه توزيع الصلاحيات على الموظفين'),
                        _buildNote(
                            '• الأنظمة المتميزة (Premium) تتطلب إعدادات إضافية'),
                        _buildNote(
                            '• واتساب API يتطلب حساب Meta Business معتمد'),
                        _buildNote(
                            '• واتساب السيرفر يتطلب VPS مع whatsapp-web.js'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSystemCard({
    required String key,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    bool isPremium = false,
  }) {
    final isEnabled = _permissions[key] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isEnabled ? color.withOpacity(0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEnabled ? color.withOpacity(0.5) : Colors.grey.shade300,
          width: isEnabled ? 2 : 1,
        ),
        boxShadow: isEnabled
            ? [
                BoxShadow(
                  color: color.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isEnabled ? color : Colors.grey.shade400,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        title: Row(
          children: [
            Text(
              title,
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                color: isEnabled ? color : Colors.grey.shade600,
              ),
            ),
            if (isPremium) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Premium',
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            description,
            style: GoogleFonts.cairo(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
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

  Widget _buildNote(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: GoogleFonts.cairo(
          fontSize: 12,
          color: Colors.orange.shade700,
        ),
      ),
    );
  }
}
