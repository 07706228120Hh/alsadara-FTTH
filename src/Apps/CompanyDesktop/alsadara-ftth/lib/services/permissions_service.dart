import 'package:shared_preferences/shared_preferences.dart';

/// خدمة إدارة الصلاحيات مع فصل كامل بين النظامين
class PermissionsService {
  // =================
  // النظام الأول (lib/pages/home_page.dart)
  // =================

  static const String _firstSystemPrefix = 'first_system_permission_';
  static const String _firstSystemConfigKey = 'first_system_configured';
  static const String _firstSystemUpdateKey = 'first_system_last_update';

  static const List<String> firstSystemPermissions = [
    'attendance', // صفحة الحضور والغياب
    'agent', // صفحة الوكلاء
    'tasks', // إدارة المهام (النظام الأول)
    'zones', // إدارة الزونات (النظام الأول)
    'ai_search', // البحث بالذكاء الاصطناعي
    'sadara_portal', // منصة الصدارة
    'accounting', // النظام المحاسبي
    'diagnostics', // تشخيص النظام
  ];

  static const Map<String, bool> firstSystemDefaults = {
    'attendance': false,
    'agent': false,
    'tasks': false,
    'zones': false,
    'ai_search': false,
    'sadara_portal': false,
    'accounting': false,
    'diagnostics': false,
  };

  // =================
  // النظام الثاني (lib/ftth/home_page.dart)
  // =================

  static const String _secondSystemPrefix = 'second_system_permission_';
  static const String _secondSystemConfigKey = 'second_system_configured';
  static const String _secondSystemUpdateKey = 'second_system_last_update';
  // مفتاح كلمة المرور الافتراضية للنظام الثاني
  static const String _secondSystemDefaultPasswordKey =
      'second_system_default_password';

  static const List<String> secondSystemPermissions = [
    'users', // إدارة المستخدمين
    'subscriptions', // إدارة الاشتراكات
    'tasks', // إدارة المهام (النظام الثاني)
    'zones', // إدارة الزونات (النظام الثاني)
    'accounts', // إدارة الحسابات
    'account_records', // سجلات الحسابات (منفصلة عن إدارة الحسابات)
    'export', // تصدير البيانات
    'agents', // إدارة الوكلاء
    'google_sheets', // حفظ البيانات في الخادم
    'whatsapp', // رسائل WhatsApp
    'wallet_balance', // رصيد المحفظة
    'expiring_soon', // الاشتراكات المنتهية قريباً
    'quick_search', // البحث السريع (إظهار زر البحث السريع)
    'technicians', // فني التوصيل (محلي) - تمت إضافته
    // === مفاتيح كانت موجودة في واجهة النظام ولم تُحفظ سابقاً (إضافة لإصلاح مشكلة الرجوع للوضع الافتراضي) ===
    'transactions', // التحويلات
    'notifications', // الإشعارات
    'audit_logs', // سجل التدقيق
    'whatsapp_link', // ربط الواتساب (QR)
    'whatsapp_settings', // إعدادات الواتساب
    'plans_bundles', // الباقات والعروض
    // === صلاحيات الواتساب الجديدة ===
    'whatsapp_business_api', // إعدادات WhatsApp Business API
    'whatsapp_bulk_sender', // إرسال رسائل جماعية
    'whatsapp_conversations_fab', // الزر العائم لمحادثات الواتساب
    // === صلاحيات التخزين المحلي ===
    'local_storage', // التخزين المحلي للمشتركين
    'local_storage_import', // زر استيراد البيانات في التخزين المحلي
    // صلاحيات جديدة — كانت مفتوحة بدون حماية
    'superset_reports', // تقارير Superset
    'server_data', // بيانات السيرفر
    'dashboard_project', // مشروع Dashboard
    'fetch_server_data', // جلب بيانات الموقع
  ];

  static const Map<String, bool> secondSystemDefaults = {
    'users': false, // ✅ السماح بعرض المستخدمين للجميع
    'subscriptions': false, // ✅ السماح بعرض الاشتراكات للجميع
    'tasks': false, // ✅ السماح بعرض المهام للجميع
    'agents': false, // ✅ السماح بعرض تفاصيل الوكلاء للجميع
    'wallet_balance': false, // ✅ السماح بمشاهدة رصيد المحفظة للجميع
    'expiring_soon': false, // ✅ السماح بعرض الاشتراكات المنتهية قريباً للجميع
    'quick_search': false, // ✅ السماح بعرض زر "البحث السريع" افتراضياً مغلق
    'technicians': false, // 🔧 فني التوصيل (محلي) - مخفي افتراضياً
    'zones': false, // 🔒 منع إدارة المناطق (للمديرين فقط)
    'accounts': false, // 🔒 منع إدارة الحسابات (للمديرين فقط)
    'account_records': false, // 🔒 سجلات الحسابات (مستقل)
    'export': false, // 🔒 منع تصدير البيانات (للمديرين فقط)
    'google_sheets': false, // 🔒 منع حفظ البيانات في الخادم
    'whatsapp': false, // 🔒 منع إرسال رسائل WhatsApp
    // المفاتيح الجديدة المضافة لضمان الحفظ والاسترجاع
    'transactions': false,
    'notifications': false,
    'audit_logs': false,
    'whatsapp_link': false,
    'whatsapp_settings': false,
    'plans_bundles': false,
    // صلاحيات الواتساب الجديدة
    'whatsapp_business_api': false,
    'whatsapp_bulk_sender': false,
    'whatsapp_conversations_fab': false,
    // صلاحيات التخزين المحلي
    'local_storage': false, // التخزين المحلي للمشتركين
    'local_storage_import': false, // زر استيراد البيانات في التخزين المحلي
    // صلاحيات جديدة — كانت مفتوحة بدون حماية
    'superset_reports': false, // تقارير Superset
    'server_data': false, // بيانات السيرفر
    'dashboard_project': false, // مشروع Dashboard
    'fetch_server_data': false, // جلب بيانات الموقع
  };

  // =================
  // دوال النظام الأول
  // =================

  /// الحصول على صلاحيات النظام الأول
  static Future<Map<String, bool>> getFirstSystemPermissions() async {
    final prefs = await SharedPreferences.getInstance();

    // ترحيل البيانات القديمة للنظام الأول (إن وجدت)
    await _migrateFirstSystemLegacyData();

    // التحقق إذا كانت الصلاحيات تم تكوينها مسبقاً
    bool isConfigured = prefs.getBool(_firstSystemConfigKey) ?? false;

    Map<String, bool> permissions = {};

    for (String key in firstSystemPermissions) {
      if (isConfigured) {
        // إذا تم التكوين مسبقاً، جلب القيم المحفوظة
        permissions[key] = prefs.getBool('$_firstSystemPrefix$key') ??
            firstSystemDefaults[key]!;
      } else {
        // القيم الافتراضية - جميع الصلاحيات مغلقة عند التثبيت الأول
        permissions[key] = firstSystemDefaults[key]!;
      }
    }

    return permissions;
  }

  /// حفظ صلاحيات النظام الأول
  static Future<void> saveFirstSystemPermissions(
      Map<String, bool> permissions) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      // حفظ الصلاحيات مع بادئة النظام الأول
      for (String key in firstSystemPermissions) {
        if (permissions.containsKey(key)) {
          await prefs.setBool('$_firstSystemPrefix$key',
              permissions[key] ?? firstSystemDefaults[key]!);
        }
      }

      // حفظ وقت آخر تحديث للنظام الأول
      await prefs.setString(
          _firstSystemUpdateKey, DateTime.now().toIso8601String());

      // وضع علامة أن النظام الأول تم تكوينه
      await prefs.setBool(_firstSystemConfigKey, true);
    } catch (e) {
      throw Exception('فشل في حفظ صلاحيات النظام الأول: $e');
    }
  }

  /// التحقق من صلاحية معينة في النظام الأول
  static Future<bool> hasFirstSystemPermission(String permission) async {
    final permissions = await getFirstSystemPermissions();
    return permissions[permission] ?? firstSystemDefaults[permission]!;
  }

  /// إعادة تعيين صلاحيات النظام الأول
  static Future<void> resetFirstSystemPermissions() async {
    final prefs = await SharedPreferences.getInstance();

    // حذف جميع صلاحيات النظام الأول
    for (String key in firstSystemPermissions) {
      await prefs.remove('$_firstSystemPrefix$key');
    }

    // حذف معلومات النظام الأول
    await prefs.remove(_firstSystemConfigKey);
    await prefs.remove(_firstSystemUpdateKey);
  }

  // =================
  // دوال النظام الثاني
  // =================

  /// الحصول على صلاحيات النظام الثاني
  static Future<Map<String, bool>> getSecondSystemPermissions() async {
    final prefs = await SharedPreferences.getInstance();

    // ترحيل البيانات القديمة للنظام الثاني (إن وجدت)
    await _migrateSecondSystemLegacyData();

    // التحقق إذا كانت الصلاحيات تم تكوينها مسبقاً
    bool isConfigured = prefs.getBool(_secondSystemConfigKey) ?? false;

    Map<String, bool> permissions = {};

    for (String key in secondSystemPermissions) {
      if (isConfigured) {
        // إذا تم التكوين مسبقاً، جلب القيم المحفوظة
        permissions[key] = prefs.getBool('$_secondSystemPrefix$key') ??
            secondSystemDefaults[key]!;
      } else {
        // القيم الافتراضية - جميع الصلاحيات مغلقة عند التثبيت الأول
        permissions[key] = secondSystemDefaults[key]!;
      }
    }

    return permissions;
  }

  /// حفظ صلاحيات النظام الثاني
  static Future<void> saveSecondSystemPermissions(
      Map<String, bool> permissions) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      // حفظ الصلاحيات مع بادئة النظام الثاني
      for (String key in secondSystemPermissions) {
        if (permissions.containsKey(key)) {
          await prefs.setBool('$_secondSystemPrefix$key',
              permissions[key] ?? secondSystemDefaults[key]!);
        }
      }

      // حفظ وقت آخر تحديث للنظام الثاني
      await prefs.setString(
          _secondSystemUpdateKey, DateTime.now().toIso8601String());

      // وضع علامة أن النظام الثاني تم تكوينه
      await prefs.setBool(_secondSystemConfigKey, true);
    } catch (e) {
      throw Exception('فشل في حفظ صلاحيات النظام الثاني: $e');
    }
  }

  // =================
  // كلمة المرور الافتراضية للنظام الثاني
  // =================

  /// حفظ كلمة المرور الافتراضية (يتم استبدالها)
  static Future<void> saveSecondSystemDefaultPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    if (password.trim().isEmpty) {
      // حذف إذا كانت فارغة
      await prefs.remove(_secondSystemDefaultPasswordKey);
    } else {
      await prefs.setString(_secondSystemDefaultPasswordKey, password.trim());
    }
  }

  /// جلب كلمة المرور الافتراضية (قد ترجع null إذا غير موجودة)
  static Future<String?> getSecondSystemDefaultPassword() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_secondSystemDefaultPasswordKey);
    if (stored == null || stored.trim().isEmpty) {
      // تعيين القيمة الافتراضية لأول مرة إن لم تكن موجودة
      const defaultValue = '0770';
      // لا نحفظها إجبارياً لترك خيار الحذف الحقيقي (إرجاع نفس الافتراضي دائماً عند الفراغ)
      return defaultValue;
    }
    return stored;
  }

  /// التحقق من صلاحية معينة في النظام الثاني
  static Future<bool> hasSecondSystemPermission(String permission) async {
    final permissions = await getSecondSystemPermissions();
    return permissions[permission] ?? secondSystemDefaults[permission]!;
  }

  /// إعادة تعيين صلاحيات النظام الثاني
  static Future<void> resetSecondSystemPermissions() async {
    final prefs = await SharedPreferences.getInstance();

    // حذف جميع صلاحيات النظام الثاني
    for (String key in secondSystemPermissions) {
      await prefs.remove('$_secondSystemPrefix$key');
    }

    // حذف معلومات النظام الثاني
    await prefs.remove(_secondSystemConfigKey);
    await prefs.remove(_secondSystemUpdateKey);
  }

  // =================
  // دوال الترحيل من الأنظمة القديمة
  // =================

  /// ترحيل البيانات القديمة للنظام الأول
  static Future<void> _migrateFirstSystemLegacyData() async {
    final prefs = await SharedPreferences.getInstance();

    // التحقق إذا تم الترحيل مسبقاً
    bool alreadyMigrated = prefs.getBool('first_system_migrated') ?? false;
    if (alreadyMigrated) return;

    Map<String, bool> migratedPermissions = {};
    bool hasLegacyData = false;

    // البحث عن البيانات القديمة بصيغ مختلفة
    final legacyPrefixes = ['global_perm_', 'global_permission_', ''];

    for (String key in firstSystemPermissions) {
      for (String prefix in legacyPrefixes) {
        final legacyValue = prefs.getBool('$prefix$key');
        if (legacyValue != null) {
          migratedPermissions[key] = legacyValue;
          hasLegacyData = true;
          break;
        }
      }
    }

    // إذا وُجدت بيانات قديمة، احفظها في النظام الجديد
    if (hasLegacyData) {
      await saveFirstSystemPermissions(migratedPermissions);
      print(
          'تم ترحيل ${migratedPermissions.length} صلاحية للنظام الأول من النظام القديم');
    }

    // وضع علامة أن الترحيل تم
    await prefs.setBool('first_system_migrated', true);
  }

  /// ترحيل البيانات القديمة للنظام الثاني
  static Future<void> _migrateSecondSystemLegacyData() async {
    final prefs = await SharedPreferences.getInstance();

    // التحقق إذا تم الترحيل مسبقاً
    bool alreadyMigrated = prefs.getBool('second_system_migrated') ?? false;
    if (alreadyMigrated) return;

    Map<String, bool> migratedPermissions = {};
    bool hasLegacyData = false;

    // البحث عن البيانات القديمة بصيغ مختلفة
    final legacyPrefixes = [
      'global_perm_',
      'global_permission_',
      'permission_',
      ''
    ];

    for (String key in secondSystemPermissions) {
      for (String prefix in legacyPrefixes) {
        final legacyValue = prefs.getBool('$prefix$key');
        if (legacyValue != null) {
          migratedPermissions[key] = legacyValue;
          hasLegacyData = true;
          break;
        }
      }
    }

    // إذا وُجدت بيانات قديمة، احفظها في النظام الجديد
    if (hasLegacyData) {
      await saveSecondSystemPermissions(migratedPermissions);
      print(
          'تم ترحيل ${migratedPermissions.length} صلاحية للنظام الثاني من النظام القديم');
    }

    // وضع علامة أن الترحيل تم
    await prefs.setBool('second_system_migrated', true);
  }

  // =================
  // دوال المطورين والتشخيص
  // =================

  /// إعادة تعيين النظامين بالكامل (للمطورين فقط)
  static Future<void> resetBothSystems() async {
    await resetFirstSystemPermissions();
    await resetSecondSystemPermissions();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('first_system_migrated');
    await prefs.remove('second_system_migrated');
  }

  /// الحصول على تقرير حالة النظامين
  static Future<Map<String, dynamic>> getSystemsStatus() async {
    final prefs = await SharedPreferences.getInstance();

    return {
      'first_system': {
        'configured': prefs.getBool(_firstSystemConfigKey) ?? false,
        'last_update': prefs.getString(_firstSystemUpdateKey) ?? 'غير محدد',
        'migrated': prefs.getBool('first_system_migrated') ?? false,
        'permissions': await getFirstSystemPermissions(),
      },
      'second_system': {
        'configured': prefs.getBool(_secondSystemConfigKey) ?? false,
        'last_update': prefs.getString(_secondSystemUpdateKey) ?? 'غير محدد',
        'migrated': prefs.getBool('second_system_migrated') ?? false,
        'permissions': await getSecondSystemPermissions(),
      }
    };
  }

  // ==========================================
  // V2 - نظام الصلاحيات المفصل (إجراءات)
  // ==========================================
  // هذا النظام الجديد يدعم إجراءات مفصلة لكل صلاحية:
  // view: عرض
  // add: إضافة
  // edit: تعديل
  // delete: حذف
  // export: تصدير
  // import: استيراد
  // print: طباعة
  // send: إرسال (مثل رسائل واتساب)

  static const String _firstSystemPrefixV2 = 'first_system_permission_v2_';
  static const String _firstSystemConfigKeyV2 = 'first_system_configured_v2';
  static const String _secondSystemPrefixV2 = 'second_system_permission_v2_';
  static const String _secondSystemConfigKeyV2 = 'second_system_configured_v2';

  /// قائمة الإجراءات المتاحة
  static const List<String> availableActions = [
    'view', // عرض
    'add', // إضافة
    'edit', // تعديل
    'delete', // حذف
    'export', // تصدير
    'import', // استيراد
    'print', // طباعة
    'send', // إرسال
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

  /// الحصول على صلاحيات V2 للنظام الأول
  static Future<Map<String, Map<String, bool>>>
      getFirstSystemPermissionsV2() async {
    final prefs = await SharedPreferences.getInstance();
    final isConfiguredV2 = prefs.getBool(_firstSystemConfigKeyV2) ?? false;

    Map<String, Map<String, bool>> permissions = {};

    for (String key in firstSystemPermissions) {
      Map<String, bool> actions = {};
      for (String action in availableActions) {
        if (isConfiguredV2) {
          // جلب من V2 المحفوظ
          actions[action] =
              prefs.getBool('$_firstSystemPrefixV2${key}_$action') ?? false;
        } else {
          // Fallback للنظام القديم (V1)
          // إذا كانت الصلاحية مفعلة في V1، نفعل view فقط
          final v1Permission = prefs.getBool('$_firstSystemPrefix$key') ??
              firstSystemDefaults[key] ??
              false;
          actions[action] = action == 'view' ? v1Permission : false;
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
      for (String key in firstSystemPermissions) {
        if (permissions.containsKey(key)) {
          for (String action in availableActions) {
            final value = permissions[key]?[action] ?? false;
            await prefs.setBool('$_firstSystemPrefixV2${key}_$action', value);
          }
        }
      }

      await prefs.setBool(_firstSystemConfigKeyV2, true);
    } catch (e) {
      throw Exception('فشل في حفظ صلاحيات V2 للنظام الأول: $e');
    }
  }

  /// الحصول على صلاحيات V2 للنظام الثاني
  static Future<Map<String, Map<String, bool>>>
      getSecondSystemPermissionsV2() async {
    final prefs = await SharedPreferences.getInstance();
    final isConfiguredV2 = prefs.getBool(_secondSystemConfigKeyV2) ?? false;

    Map<String, Map<String, bool>> permissions = {};

    for (String key in secondSystemPermissions) {
      Map<String, bool> actions = {};
      for (String action in availableActions) {
        if (isConfiguredV2) {
          // جلب من V2 المحفوظ
          actions[action] =
              prefs.getBool('$_secondSystemPrefixV2${key}_$action') ?? false;
        } else {
          // Fallback للنظام القديم (V1)
          // إذا كانت الصلاحية مفعلة في V1، نفعل view فقط
          final v1Permission = prefs.getBool('$_secondSystemPrefix$key') ??
              secondSystemDefaults[key] ??
              false;
          actions[action] = action == 'view' ? v1Permission : false;
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
      for (String key in secondSystemPermissions) {
        if (permissions.containsKey(key)) {
          for (String action in availableActions) {
            final value = permissions[key]?[action] ?? false;
            await prefs.setBool('$_secondSystemPrefixV2${key}_$action', value);
          }
        }
      }

      await prefs.setBool(_secondSystemConfigKeyV2, true);
    } catch (e) {
      throw Exception('فشل في حفظ صلاحيات V2 للنظام الثاني: $e');
    }
  }

  /// التحقق من صلاحية وإجراء معين في النظام الأول (V2)
  /// الدالة القديمة hasFirstSystemPermission تبقى تعمل
  static Future<bool> hasFirstSystemPermissionAction(
      String permission, String action) async {
    final prefs = await SharedPreferences.getInstance();
    final isConfiguredV2 = prefs.getBool(_firstSystemConfigKeyV2) ?? false;

    if (isConfiguredV2) {
      return prefs.getBool('$_firstSystemPrefixV2${permission}_$action') ??
          false;
    } else {
      // Fallback: إذا V2 غير مكون، نستخدم V1 للـ view فقط
      if (action == 'view') {
        return await hasFirstSystemPermission(permission);
      }
      return false;
    }
  }

  /// التحقق من صلاحية وإجراء معين في النظام الثاني (V2)
  /// الدالة القديمة hasSecondSystemPermission تبقى تعمل
  static Future<bool> hasSecondSystemPermissionAction(
      String permission, String action) async {
    final prefs = await SharedPreferences.getInstance();
    final isConfiguredV2 = prefs.getBool(_secondSystemConfigKeyV2) ?? false;

    if (isConfiguredV2) {
      return prefs.getBool('$_secondSystemPrefixV2${permission}_$action') ??
          false;
    } else {
      // Fallback: إذا V2 غير مكون، نستخدم V1 للـ view فقط
      if (action == 'view') {
        return await hasSecondSystemPermission(permission);
      }
      return false;
    }
  }

  /// إعادة تعيين صلاحيات V2 للنظام الأول
  static Future<void> resetFirstSystemPermissionsV2() async {
    final prefs = await SharedPreferences.getInstance();

    for (String key in firstSystemPermissions) {
      for (String action in availableActions) {
        await prefs.remove('$_firstSystemPrefixV2${key}_$action');
      }
    }
    await prefs.remove(_firstSystemConfigKeyV2);
  }

  /// إعادة تعيين صلاحيات V2 للنظام الثاني
  static Future<void> resetSecondSystemPermissionsV2() async {
    final prefs = await SharedPreferences.getInstance();

    for (String key in secondSystemPermissions) {
      for (String action in availableActions) {
        await prefs.remove('$_secondSystemPrefixV2${key}_$action');
      }
    }
    await prefs.remove(_secondSystemConfigKeyV2);
  }

  /// التحقق هل تم إعداد V2
  static Future<bool> isV2Configured() async {
    final prefs = await SharedPreferences.getInstance();
    final firstV2 = prefs.getBool(_firstSystemConfigKeyV2) ?? false;
    final secondV2 = prefs.getBool(_secondSystemConfigKeyV2) ?? false;
    return firstV2 || secondV2;
  }

  /// الحصول على تقرير حالة النظامين بما فيها V2
  static Future<Map<String, dynamic>> getSystemsStatusV2() async {
    final prefs = await SharedPreferences.getInstance();

    return {
      'first_system': {
        'configured_v1': prefs.getBool(_firstSystemConfigKey) ?? false,
        'configured_v2': prefs.getBool(_firstSystemConfigKeyV2) ?? false,
        'permissions_v1': await getFirstSystemPermissions(),
        'permissions_v2': await getFirstSystemPermissionsV2(),
      },
      'second_system': {
        'configured_v1': prefs.getBool(_secondSystemConfigKey) ?? false,
        'configured_v2': prefs.getBool(_secondSystemConfigKeyV2) ?? false,
        'permissions_v1': await getSecondSystemPermissions(),
        'permissions_v2': await getSecondSystemPermissionsV2(),
      }
    };
  }
}
