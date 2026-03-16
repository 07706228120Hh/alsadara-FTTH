import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/whatsapp_system_settings_service.dart';
import '../services/whatsapp_permissions_service.dart' as perms;

/// صفحة إعدادات نظام الواتساب المستخدم
class WhatsAppSystemSettingsPage extends StatefulWidget {
  const WhatsAppSystemSettingsPage({super.key});

  @override
  State<WhatsAppSystemSettingsPage> createState() =>
      _WhatsAppSystemSettingsPageState();
}

class _WhatsAppSystemSettingsPageState
    extends State<WhatsAppSystemSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;

  WhatsAppSystem _renewalSystem = WhatsAppSystem.app;
  WhatsAppSystem _bulkSystem = WhatsAppSystem.server;

  // حالة توفر الأنظمة (إعداد تقني)
  Map<WhatsAppSystem, bool> _systemAvailability = {
    WhatsAppSystem.app: true,
    WhatsAppSystem.web: true,
    WhatsAppSystem.server: false,
    WhatsAppSystem.api: false,
  };

  // صلاحيات الشركة (من Super Admin)
  Map<WhatsAppSystem, bool> _tenantPermissions = {
    WhatsAppSystem.app: false,
    WhatsAppSystem.web: false,
    WhatsAppSystem.server: false,
    WhatsAppSystem.api: false,
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings = await WhatsAppSystemSettingsService.getSystemSettings();
      _renewalSystem = settings['renewal']!;
      _bulkSystem = settings['bulk']!;

      // تحميل صلاحيات الشركة من PermissionManager (لا يحتاج tenantId)
      final enabledSystems =
          await perms.WhatsAppPermissionsService.getTenantEnabledSystems('');
      _tenantPermissions = {
        WhatsAppSystem.app:
            enabledSystems.any((s) => s.key == 'whatsapp_system_normal'),
        WhatsAppSystem.web:
            enabledSystems.any((s) => s.key == 'whatsapp_system_web'),
        WhatsAppSystem.server:
            enabledSystems.any((s) => s.key == 'whatsapp_system_server'),
        WhatsAppSystem.api:
            enabledSystems.any((s) => s.key == 'whatsapp_system_api'),
      };

      // التحقق من الإعداد التقني للأنظمة
      _systemAvailability = {
        WhatsAppSystem.app: true,
        WhatsAppSystem.web: true,
        WhatsAppSystem.server:
            await WhatsAppSystemSettingsService.isSystemAvailable(
                WhatsAppSystem.server),
        WhatsAppSystem.api:
            await WhatsAppSystemSettingsService.isSystemAvailable(
                WhatsAppSystem.api),
      };
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل الإعدادات')),
        );
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    final success = await WhatsAppSystemSettingsService.saveSystemSettings(
      renewalSystem: _renewalSystem,
      bulkSystem: _bulkSystem,
    );

    if (mounted) {
      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                success ? 'تم حفظ الإعدادات بنجاح' : 'فشل في حفظ الإعدادات',
                style: GoogleFonts.cairo(),
              ),
            ],
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

      if (success) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          title: Text(
            'نظام الواتساب',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF7C3AED),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoCard(),
                    const SizedBox(height: 20),

                    // نظام التجديد
                    _buildSystemSection(
                      title: 'نظام التجديد',
                      subtitle: 'يُستخدم عند التجديد اليدوي أو التلقائي',
                      icon: Icons.autorenew_rounded,
                      color: const Color(0xFF22C55E),
                      operationType: WhatsAppOperationType.renewal,
                      selectedSystem: _renewalSystem,
                      onChanged: (system) {
                        setState(() => _renewalSystem = system);
                      },
                    ),

                    const SizedBox(height: 16),

                    // نظام الإرسال الجماعي
                    _buildSystemSection(
                      title: 'الإرسال الجماعي',
                      subtitle: 'للتنبيهات والمنتهي والعروض',
                      icon: Icons.campaign_rounded,
                      color: const Color(0xFF3B82F6),
                      operationType: WhatsAppOperationType.bulk,
                      selectedSystem: _bulkSystem,
                      onChanged: (system) {
                        setState(() => _bulkSystem = system);
                      },
                    ),

                    const SizedBox(height: 24),
                    _buildNoteCard(),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveSettings,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          _isSaving ? 'جاري الحفظ...' : 'حفظ الإعدادات',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade400, Colors.purple.shade600],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'حدد النظام المستخدم لكل نوع من العمليات',
              style: GoogleFonts.cairo(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required WhatsAppOperationType operationType,
    required WhatsAppSystem selectedSystem,
    required Function(WhatsAppSystem) onChanged,
  }) {
    final availableSystems =
        WhatsAppSystemSettingsService.getAvailableSystemsForOperation(
            operationType);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withOpacity(0.8)],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.cairo(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // الخيارات
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: availableSystems.map((system) {
                final isSelected = selectedSystem == system;
                final isTechnicallyAvailable =
                    _systemAvailability[system] ?? false;
                final hasTenantPermission = _tenantPermissions[system] ?? false;

                final isFullyAvailable = hasTenantPermission &&
                    (isTechnicallyAvailable || system == WhatsAppSystem.app);

                final systemName =
                    WhatsAppSystemSettingsService.systemNames[system]!;
                final systemIcon =
                    WhatsAppSystemSettingsService.systemIcons[system]!;
                final systemDesc =
                    WhatsAppSystemSettingsService.systemDescriptions[system]!;

                String? unavailableReason;
                if (!hasTenantPermission) {
                  unavailableReason = 'غير مرخص للشركة';
                } else if (!isTechnicallyAvailable &&
                    system != WhatsAppSystem.app) {
                  unavailableReason = 'يحتاج إعداد';
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: isFullyAvailable ? () => onChanged(system) : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withOpacity(0.1)
                            : isFullyAvailable
                                ? Colors.grey.shade50
                                : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? color : Colors.grey.shade200,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          // أيقونة الاختيار
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  isSelected ? color : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? color
                                    : Colors.grey.shade400,
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 16)
                                : null,
                          ),
                          const SizedBox(width: 14),

                          // الأيقونة والاسم
                          Text(
                            systemIcon,
                            style: TextStyle(
                              fontSize: 22,
                              color: isFullyAvailable
                                  ? null
                                  : Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  systemName,
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: isFullyAvailable
                                        ? Colors.grey.shade800
                                        : Colors.grey.shade400,
                                  ),
                                ),
                                Text(
                                  systemDesc,
                                  style: GoogleFonts.cairo(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // حالة التوفر
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isFullyAvailable
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isFullyAvailable
                                  ? 'متاح ✓'
                                  : unavailableReason ?? 'غير متاح',
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isFullyAvailable
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, color: Colors.amber.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ملاحظة',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.amber.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'لتفعيل السيرفر أو API، اذهب إلى صفحة الإعدادات وقم بتكوينها أولاً.',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: Colors.amber.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
