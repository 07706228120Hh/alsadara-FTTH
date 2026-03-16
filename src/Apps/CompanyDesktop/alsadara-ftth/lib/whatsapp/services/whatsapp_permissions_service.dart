/// خدمة صلاحيات الواتساب
/// تقرأ من PermissionManager (المحمّل عند تسجيل الدخول من VPS)
/// لا تحتاج API calls — الصلاحيات موجودة محلياً
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../permissions/permission_manager.dart';
import '../../services/vps_auth_service.dart';
import '../../services/custom_auth_service.dart';

/// أنظمة الواتساب المتاحة
enum WhatsAppSystem {
  normal('whatsapp_system_normal', 'التطبيق العادي', 'فتح تطبيق واتساب'),
  web('whatsapp_system_web', 'واتساب ويب', 'واتساب ويب داخل التطبيق'),
  server('whatsapp_system_server', 'واتساب السيرفر', 'VPS Server'),
  api('whatsapp_system_api', 'واتساب API', 'Meta Business API');

  final String key;
  final String arabicName;
  final String description;

  const WhatsAppSystem(this.key, this.arabicName, this.description);

  static WhatsAppSystem? fromKey(String key) {
    try {
      return WhatsAppSystem.values.firstWhere((s) => s.key == key);
    } catch (_) {
      return null;
    }
  }
}

/// صلاحيات الموظف داخل الشركة
enum WhatsAppUserPermission {
  sendRenewal('whatsapp', 'إرسال رسائل التجديد'),
  sendExpiring('whatsapp', 'إرسال تذكيرات قرب الانتهاء'),
  sendExpired('whatsapp', 'إرسال رسائل المنتهي + عروض'),
  sendNotification('whatsapp', 'إرسال تبليغات عامة'),
  editTemplates('whatsapp_templates', 'تعديل قوالب الرسائل'),
  bulkSend('whatsapp_bulk_sender', 'الإرسال الجماعي'),
  viewConversations('whatsapp_conversations_fab', 'عرض المحادثات');

  final String key;
  final String arabicName;

  const WhatsAppUserPermission(this.key, this.arabicName);
}

const Map<String, bool> defaultUserWhatsAppPermissions = {
  'whatsapp': false,
  'whatsapp_templates': false,
  'whatsapp_bulk_sender': false,
  'whatsapp_conversations_fab': false,
};

Map<String, bool> get adminWhatsAppPermissions =>
    defaultUserWhatsAppPermissions.map((key, _) => MapEntry(key, true));

/// نتيجة فحص الصلاحية
class PermissionCheckResult {
  final bool allowed;
  final String reason;
  final String? deniedBy;

  PermissionCheckResult({
    required this.allowed,
    required this.reason,
    required this.deniedBy,
  });
}

/// قدرات المستخدم في الواتساب
class UserWhatsAppCapabilities {
  final List<WhatsAppSystem> enabledSystems;
  final Map<String, bool> userPermissions;
  final bool isAdmin;

  UserWhatsAppCapabilities({
    required this.enabledSystems,
    required this.userPermissions,
    required this.isAdmin,
  });

  factory UserWhatsAppCapabilities.none() => UserWhatsAppCapabilities(
        enabledSystems: [],
        userPermissions: Map.from(defaultUserWhatsAppPermissions),
        isAdmin: false,
      );

  bool get hasAnySystem => enabledSystems.isNotEmpty;
  bool hasSystem(WhatsAppSystem system) => enabledSystems.contains(system);
  bool hasPermission(WhatsAppUserPermission permission) =>
      isAdmin || (userPermissions[permission.key] ?? false);

  bool get canSendRenewal => hasPermission(WhatsAppUserPermission.sendRenewal);
  bool get canSendExpiring => hasPermission(WhatsAppUserPermission.sendExpiring);
  bool get canSendExpired => hasPermission(WhatsAppUserPermission.sendExpired);
  bool get canSendNotification =>
      hasPermission(WhatsAppUserPermission.sendNotification);
  bool get canEditTemplates =>
      hasPermission(WhatsAppUserPermission.editTemplates);
  bool get canBulkSend => hasPermission(WhatsAppUserPermission.bulkSend);
  bool get canViewConversations =>
      hasPermission(WhatsAppUserPermission.viewConversations);
}

/// صلاحيات الواتساب الافتراضية للشركة
const Map<String, bool> defaultTenantWhatsAppPermissions = {
  'whatsapp_normal': false,
  'whatsapp_web': false,
  'whatsapp_server': false,
  'whatsapp_api': false,
};

/// خدمة صلاحيات الواتساب
class WhatsAppPermissionsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ============================================
  // أسماء الأنظمة
  // ============================================

  static Map<String, String> get systemNames => {
        'whatsapp_normal': 'التطبيق العادي',
        'whatsapp_web': 'واتساب ويب',
        'whatsapp_server': 'واتساب السيرفر (VPS)',
        'whatsapp_api': 'واتساب API (Meta Business)',
      };

  static Map<String, String> get userPermissionNames => {
        'send_renewal': 'إرسال رسائل التجديد',
        'send_expiring': 'إرسال تذكيرات قرب الانتهاء',
        'send_expired': 'إرسال رسائل المنتهي + عروض',
        'send_notification': 'إرسال تبليغات عامة',
        'edit_templates': 'تعديل قوالب الرسائل',
        'bulk_send': 'الإرسال الجماعي',
        'view_conversations': 'عرض المحادثات',
      };

  // ============================================
  // صلاحيات الشركة (Firebase) — للصفحات المنقولة
  // ============================================

  static Future<Map<String, bool>> getTenantWhatsAppPermissions(
      String tenantId) async {
    try {
      final doc = await _firestore
          .collection('tenants')
          .doc(tenantId)
          .collection('settings')
          .doc('whatsapp_permissions')
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return {
          'whatsapp_normal': data['whatsapp_normal'] ?? false,
          'whatsapp_web': data['whatsapp_web'] ?? false,
          'whatsapp_server': data['whatsapp_server'] ?? false,
          'whatsapp_api': data['whatsapp_api'] ?? false,
        };
      }
      return Map.from(defaultTenantWhatsAppPermissions);
    } catch (e) {
      return Map.from(defaultTenantWhatsAppPermissions);
    }
  }

  static Future<bool> updateTenantWhatsAppPermissions({
    required String tenantId,
    required Map<String, bool> permissions,
  }) async {
    try {
      await _firestore
          .collection('tenants')
          .doc(tenantId)
          .collection('settings')
          .doc('whatsapp_permissions')
          .set({
        ...permissions,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': CustomAuthService.currentSuperAdmin?.username ?? 'system',
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      return false;
    }
  }

  // ============================================
  // صلاحيات الموظف (Firebase) — للصفحات المنقولة
  // ============================================

  static Future<Map<String, bool>> getUserWhatsAppPermissions({
    required String tenantId,
    required String oderId,
  }) async {
    try {
      final doc = await _firestore
          .collection('tenants')
          .doc(tenantId)
          .collection('users')
          .doc(oderId)
          .get();
      if (doc.exists && doc.data() != null) {
        final whatsappPerms =
            doc.data()!['whatsappPermissions'] as Map<String, dynamic>?;
        if (whatsappPerms != null) {
          return {
            'send_renewal': whatsappPerms['send_renewal'] ?? false,
            'send_expiring': whatsappPerms['send_expiring'] ?? false,
            'send_expired': whatsappPerms['send_expired'] ?? false,
            'send_notification': whatsappPerms['send_notification'] ?? false,
            'edit_templates': whatsappPerms['edit_templates'] ?? false,
            'bulk_send': whatsappPerms['bulk_send'] ?? false,
            'view_conversations': whatsappPerms['view_conversations'] ?? false,
          };
        }
      }
      return Map.from(defaultUserWhatsAppPermissions);
    } catch (e) {
      return Map.from(defaultUserWhatsAppPermissions);
    }
  }

  static Future<bool> updateUserWhatsAppPermissions({
    required String tenantId,
    required String userId,
    required Map<String, bool> permissions,
  }) async {
    try {
      await _firestore
          .collection('tenants')
          .doc(tenantId)
          .collection('users')
          .doc(userId)
          .update({
        'whatsappPermissions': permissions,
        'whatsappPermissionsUpdatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  // ============================================
  // الدالة الرئيسية — تقرأ من PermissionManager
  // ============================================

  /// الحصول على أنظمة الواتساب المفعلة (تجاهل tenantId — يُقرأ من PermissionManager)
  static Future<List<WhatsAppSystem>> getTenantEnabledSystems(
      String tenantId) async {
    final pm = PermissionManager.instance;
    return WhatsAppSystem.values.where((s) => pm.canView(s.key)).toList();
  }

  /// التحقق من إمكانية الإرسال (متوافق مع الكود القديم)
  static Future<PermissionCheckResult> canUserSendMessage({
    required String tenantId,
    required String userId,
    required WhatsAppSystem system,
    required WhatsAppUserPermission messageType,
  }) async {
    final pm = PermissionManager.instance;

    if (!pm.canView(system.key)) {
      return PermissionCheckResult(
        allowed: false,
        reason: 'النظام ${system.arabicName} غير مفعّل للشركة',
        deniedBy: 'tenant',
      );
    }

    if (!pm.canSend(messageType.key) && !pm.canView(messageType.key)) {
      return PermissionCheckResult(
        allowed: false,
        reason: 'ليس لديك صلاحية ${messageType.arabicName}',
        deniedBy: 'user',
      );
    }

    return PermissionCheckResult(allowed: true, reason: 'مسموح', deniedBy: null);
  }

  /// الحصول على جميع قدرات المستخدم الحالي
  static Future<UserWhatsAppCapabilities> getCurrentUserCapabilities() async {
    final vpsAuth = VpsAuthService.instance;
    final vpsUser = vpsAuth.currentUser;
    final pm = PermissionManager.instance;

    // مدير الشركة: له كل الصلاحيات الممنوحة للشركة
    if (vpsUser?.isAdmin == true) {
      final enabledSystems = WhatsAppSystem.values
          .where((s) => pm.canView(s.key))
          .toList();
      return UserWhatsAppCapabilities(
        enabledSystems: enabledSystems,
        userPermissions: adminWhatsAppPermissions,
        isAdmin: true,
      );
    }

    // موظف عادي: يتحقق من صلاحياته في PermissionManager
    if (vpsUser != null) {
      final enabledSystems = WhatsAppSystem.values
          .where((s) => pm.canView(s.key))
          .toList();

      final userPerms = {
        'whatsapp': pm.canView('whatsapp') || pm.canSend('whatsapp'),
        'whatsapp_templates': pm.canView('whatsapp_templates'),
        'whatsapp_bulk_sender': pm.canView('whatsapp_bulk_sender') ||
            pm.canSend('whatsapp_bulk_sender'),
        'whatsapp_conversations_fab':
            pm.canView('whatsapp_conversations_fab'),
      };

      return UserWhatsAppCapabilities(
        enabledSystems: enabledSystems,
        userPermissions: userPerms,
        isAdmin: false,
      );
    }

    return UserWhatsAppCapabilities.none();
  }
}
