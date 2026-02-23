/// ═══════════════════════════════════════════════════════════════
/// خدمة الصلاحيات الموحدة — V2 فقط (SharedPreferences)
/// ═══════════════════════════════════════════════════════════════
///
/// هذه الخدمة مسؤولة عن:
/// - حفظ/قراءة صلاحيات V2 من SharedPreferences
/// - توفير الثوابت (الإجراءات المتاحة، الأسماء العربية)
///
/// لا تستخدم هذه الخدمة مباشرة — استخدم [PermissionManager.instance]
library;

import 'package:shared_preferences/shared_preferences.dart';
import 'permission_registry.dart';

/// خدمة الصلاحيات — V2 فقط
class PermissionService {
  PermissionService._();

  // ═══════════════════════════════════════
  // ثوابت
  // ═══════════════════════════════════════

  static const String _firstSystemPrefixV2 = 'first_system_permission_v2_';
  static const String _firstSystemConfigKeyV2 = 'first_system_configured_v2';
  static const String _secondSystemPrefixV2 = 'second_system_permission_v2_';
  static const String _secondSystemConfigKeyV2 = 'second_system_configured_v2';

  /// قائمة الإجراءات المتاحة
  static const List<String> availableActions = [
    'view',
    'add',
    'edit',
    'delete',
    'export',
    'import',
    'print',
    'send',
  ];

  /// أسماء الإجراءات بالعربي
  static const Map<String, String> actionNamesAr = {
    'view': 'عرض',
    'add': 'إضافة',
    'edit': 'تعديل',
    'delete': 'حذف',
    'export': 'تصدير',
    'import': 'استيراد',
    'print': 'طباعة',
    'send': 'إرسال',
  };

  // ═══════════════════════════════════════
  // كلمة المرور الافتراضية للنظام الثاني
  // ═══════════════════════════════════════

  static const String _secondSystemDefaultPasswordKey =
      'second_system_default_password';

  /// حفظ كلمة المرور الافتراضية
  static Future<void> saveSecondSystemDefaultPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    if (password.trim().isEmpty) {
      await prefs.remove(_secondSystemDefaultPasswordKey);
    } else {
      await prefs.setString(_secondSystemDefaultPasswordKey, password.trim());
    }
  }

  /// جلب كلمة المرور الافتراضية
  static Future<String?> getSecondSystemDefaultPassword() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_secondSystemDefaultPasswordKey);
    if (stored == null || stored.trim().isEmpty) {
      return '0770'; // القيمة الافتراضية
    }
    return stored;
  }

  // ═══════════════════════════════════════
  // قراءة وحفظ V2 — النظام الأول
  // ═══════════════════════════════════════

  /// الحصول على صلاحيات V2 للنظام الأول
  static Future<Map<String, Map<String, bool>>>
      getFirstSystemPermissionsV2() async {
    final prefs = await SharedPreferences.getInstance();
    final isConfigured = prefs.getBool(_firstSystemConfigKeyV2) ?? false;

    Map<String, Map<String, bool>> permissions = {};
    final allKeys = PermissionRegistry.allFirstSystemKeys;

    for (String key in allKeys) {
      Map<String, bool> actions = {};
      for (String action in availableActions) {
        if (isConfigured) {
          actions[action] =
              prefs.getBool('$_firstSystemPrefixV2${key}_$action') ?? false;
        } else {
          actions[action] = false;
        }
      }
      permissions[key] = actions;
    }

    return permissions;
  }

  /// حفظ صلاحيات V2 للنظام الأول
  static Future<void> saveFirstSystemPermissionsV2(
      Map<String, Map<String, bool>> permissions) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      for (final entry in permissions.entries) {
        for (String action in availableActions) {
          final value = entry.value[action] ?? false;
          await prefs.setBool(
              '$_firstSystemPrefixV2${entry.key}_$action', value);
        }
      }
      await prefs.setBool(_firstSystemConfigKeyV2, true);
    } catch (e) {
      throw Exception('فشل في حفظ صلاحيات V2 للنظام الأول: $e');
    }
  }

  // ═══════════════════════════════════════
  // قراءة وحفظ V2 — النظام الثاني
  // ═══════════════════════════════════════

  /// الحصول على صلاحيات V2 للنظام الثاني
  static Future<Map<String, Map<String, bool>>>
      getSecondSystemPermissionsV2() async {
    final prefs = await SharedPreferences.getInstance();
    final isConfigured = prefs.getBool(_secondSystemConfigKeyV2) ?? false;

    Map<String, Map<String, bool>> permissions = {};
    final allKeys = PermissionRegistry.allSecondSystemKeys;

    for (String key in allKeys) {
      Map<String, bool> actions = {};
      for (String action in availableActions) {
        if (isConfigured) {
          actions[action] =
              prefs.getBool('$_secondSystemPrefixV2${key}_$action') ?? false;
        } else {
          actions[action] = false;
        }
      }
      permissions[key] = actions;
    }

    return permissions;
  }

  /// حفظ صلاحيات V2 للنظام الثاني
  static Future<void> saveSecondSystemPermissionsV2(
      Map<String, Map<String, bool>> permissions) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      for (final entry in permissions.entries) {
        for (String action in availableActions) {
          final value = entry.value[action] ?? false;
          await prefs.setBool(
              '$_secondSystemPrefixV2${entry.key}_$action', value);
        }
      }
      await prefs.setBool(_secondSystemConfigKeyV2, true);
    } catch (e) {
      throw Exception('فشل في حفظ صلاحيات V2 للنظام الثاني: $e');
    }
  }

  // ═══════════════════════════════════════
  // إعادة التعيين
  // ═══════════════════════════════════════

  /// إعادة تعيين صلاحيات V2 للنظام الأول
  static Future<void> resetFirstSystemPermissionsV2() async {
    final prefs = await SharedPreferences.getInstance();
    for (String key in PermissionRegistry.allFirstSystemKeys) {
      for (String action in availableActions) {
        await prefs.remove('$_firstSystemPrefixV2${key}_$action');
      }
    }
    await prefs.remove(_firstSystemConfigKeyV2);
  }

  /// إعادة تعيين صلاحيات V2 للنظام الثاني
  static Future<void> resetSecondSystemPermissionsV2() async {
    final prefs = await SharedPreferences.getInstance();
    for (String key in PermissionRegistry.allSecondSystemKeys) {
      for (String action in availableActions) {
        await prefs.remove('$_secondSystemPrefixV2${key}_$action');
      }
    }
    await prefs.remove(_secondSystemConfigKeyV2);
  }

  /// إعادة تعيين النظامين بالكامل
  static Future<void> resetBothSystems() async {
    await resetFirstSystemPermissionsV2();
    await resetSecondSystemPermissionsV2();
  }

  /// هل تم إعداد V2؟
  static Future<bool> isV2Configured() async {
    final prefs = await SharedPreferences.getInstance();
    final firstV2 = prefs.getBool(_firstSystemConfigKeyV2) ?? false;
    final secondV2 = prefs.getBool(_secondSystemConfigKeyV2) ?? false;
    return firstV2 || secondV2;
  }

  /// تقرير الحالة
  static Future<Map<String, dynamic>> getSystemsStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'first_system': {
        'configured_v2': prefs.getBool(_firstSystemConfigKeyV2) ?? false,
        'permissions_v2': await getFirstSystemPermissionsV2(),
      },
      'second_system': {
        'configured_v2': prefs.getBool(_secondSystemConfigKeyV2) ?? false,
        'permissions_v2': await getSecondSystemPermissionsV2(),
      }
    };
  }
}
