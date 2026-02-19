import 'package:flutter/material.dart';

/// ═══════════════════════════════════════════════════════════════
/// سجل الصلاحيات المركزي - المصدر الوحيد للحقيقة
/// ═══════════════════════════════════════════════════════════════
///
/// عند إضافة ميزة جديدة:
/// 1. أضف [PermissionEntry] في القائمة المناسبة هنا
/// 2. انتهى! ← تظهر تلقائياً في:
///    - واجهة إدارة الصلاحيات (V1 + V2)
///    - PermissionsService (حفظ/استرجاع)
///    - الفلاتر والحراسات
///
/// لا حاجة لتعديل أي ملف آخر.
/// ═══════════════════════════════════════════════════════════════

/// تعريف صلاحية واحدة
class PermissionEntry {
  /// المفتاح الفريد (مثل 'accounting', 'users')
  final String key;

  /// الاسم بالعربي
  final String labelAr;

  /// الوصف (للـ V2 page)
  final String description;

  /// الأيقونة
  final IconData icon;

  /// القيمة الافتراضية (دائماً false — لا شيء مفعل تلقائياً)
  final bool defaultValue;

  /// الفئة/القسم في واجهة الإدارة
  final String category;

  const PermissionEntry({
    required this.key,
    required this.labelAr,
    required this.description,
    required this.icon,
    this.defaultValue = false,
    this.category = 'عام',
  });
}

/// سجل الصلاحيات المركزي
class PermissionRegistry {
  PermissionRegistry._();

  // ═══════════════════════════════════════
  // النظام الأول — الصفحة الرئيسية
  // ═══════════════════════════════════════

  static const List<PermissionEntry> firstSystem = [
    PermissionEntry(
      key: 'attendance',
      labelAr: 'صفحة البصمة',
      description: 'تسجيل حضور وانصراف الموظفين',
      icon: Icons.fingerprint_rounded,
      category: 'الموارد البشرية',
    ),
    PermissionEntry(
      key: 'agent',
      labelAr: 'صفحة الوكيل',
      description: 'إدارة وكلاء المبيعات والتوزيع',
      icon: Icons.support_agent_rounded,
      category: 'المبيعات',
    ),
    PermissionEntry(
      key: 'tasks',
      labelAr: 'المهام',
      description: 'إدارة المهام والتكليفات',
      icon: Icons.task_alt_rounded,
      category: 'التشغيل',
    ),
    PermissionEntry(
      key: 'zones',
      labelAr: 'الزونات',
      description: 'تحديد مناطق العمل والتغطية',
      icon: Icons.map_rounded,
      category: 'التشغيل',
    ),
    PermissionEntry(
      key: 'ai_search',
      labelAr: 'البحث بالذكاء الاصطناعي',
      description: 'بحث بالذكاء الاصطناعي',
      icon: Icons.auto_awesome_rounded,
      category: 'أدوات',
    ),
    PermissionEntry(
      key: 'sadara_portal',
      labelAr: 'منصة الصدارة',
      description: 'الوصول لمنصة الصدارة الإدارية',
      icon: Icons.admin_panel_settings_rounded,
      category: 'الإدارة',
    ),
    PermissionEntry(
      key: 'accounting',
      labelAr: 'النظام المحاسبي',
      description: 'إدارة الحسابات والمصروفات والرواتب',
      icon: Icons.account_balance_rounded,
      category: 'المالية',
    ),
    PermissionEntry(
      key: 'diagnostics',
      labelAr: 'تشخيص النظام',
      description: 'أدوات فحص وتشخيص حالة النظام',
      icon: Icons.bug_report_rounded,
      category: 'النظام',
    ),
  ];

  // ═══════════════════════════════════════
  // النظام الثاني — FTTH
  // ═══════════════════════════════════════

  static const List<PermissionEntry> secondSystem = [
    // إدارة المشتركين
    PermissionEntry(
      key: 'users',
      labelAr: 'إدارة المستخدمين',
      description: 'إدارة المشتركين والعملاء',
      icon: Icons.people_rounded,
      category: 'المشتركين',
    ),
    PermissionEntry(
      key: 'subscriptions',
      labelAr: 'إدارة الاشتراكات',
      description: 'إدارة باقات الاشتراك',
      icon: Icons.card_membership_rounded,
      category: 'المشتركين',
    ),
    PermissionEntry(
      key: 'tasks',
      labelAr: 'المهام',
      description: 'إدارة مهام الصيانة والتركيب',
      icon: Icons.assignment_rounded,
      category: 'التشغيل',
    ),
    PermissionEntry(
      key: 'zones',
      labelAr: 'المناطق',
      description: 'تحديد مناطق التغطية',
      icon: Icons.location_on_rounded,
      category: 'التشغيل',
    ),

    // المالية
    PermissionEntry(
      key: 'accounts',
      labelAr: 'الحسابات',
      description: 'إدارة الحسابات المالية',
      icon: Icons.account_balance_wallet_rounded,
      category: 'المالية',
    ),
    PermissionEntry(
      key: 'account_records',
      labelAr: 'سجلات الحسابات',
      description: 'عرض سجلات المعاملات',
      icon: Icons.receipt_long_rounded,
      category: 'المالية',
    ),
    PermissionEntry(
      key: 'wallet_balance',
      labelAr: 'رصيد المحفظة',
      description: 'عرض أرصدة المحفظة',
      icon: Icons.account_balance_rounded,
      category: 'المالية',
    ),
    PermissionEntry(
      key: 'transactions',
      labelAr: 'التحويلات',
      description: 'سجل المعاملات المالية',
      icon: Icons.swap_horiz_rounded,
      category: 'المالية',
    ),

    // البيانات والتقارير
    PermissionEntry(
      key: 'export',
      labelAr: 'تصدير البيانات',
      description: 'تصدير البيانات والتقارير',
      icon: Icons.file_download_rounded,
      category: 'التقارير',
    ),
    PermissionEntry(
      key: 'quick_search',
      labelAr: 'البحث السريع',
      description: 'البحث السريع في البيانات',
      icon: Icons.search_rounded,
      category: 'التقارير',
    ),
    PermissionEntry(
      key: 'expiring_soon',
      labelAr: 'اشتراكات منتهية قريباً',
      description: 'عرض الاشتراكات القريبة من الانتهاء',
      icon: Icons.warning_amber_rounded,
      category: 'التقارير',
    ),
    PermissionEntry(
      key: 'notifications',
      labelAr: 'الإشعارات',
      description: 'إدارة الإشعارات',
      icon: Icons.notifications_rounded,
      category: 'التقارير',
    ),
    PermissionEntry(
      key: 'audit_logs',
      labelAr: 'سجل التدقيق',
      description: 'سجل العمليات والتغييرات',
      icon: Icons.history_rounded,
      category: 'التقارير',
    ),
    PermissionEntry(
      key: 'superset_reports',
      labelAr: 'تقارير Superset',
      description: 'لوحات التقارير والرسوم البيانية',
      icon: Icons.dashboard_rounded,
      category: 'التقارير',
    ),
    PermissionEntry(
      key: 'server_data',
      labelAr: 'بيانات السيرفر',
      description: 'عرض ملفات بيانات السيرفر',
      icon: Icons.storage_rounded,
      category: 'التقارير',
    ),
    PermissionEntry(
      key: 'dashboard_project',
      labelAr: 'مشروع Dashboard',
      description: 'لوحة بيانات الشارتات والمشاريع',
      icon: Icons.dashboard_customize_rounded,
      category: 'التقارير',
    ),
    PermissionEntry(
      key: 'fetch_server_data',
      labelAr: 'جلب بيانات الموقع',
      description: 'تحميل بيانات من السيرفر',
      icon: Icons.cloud_download_rounded,
      category: 'التقارير',
    ),

    // الوكلاء والفنيين
    PermissionEntry(
      key: 'agents',
      labelAr: 'الوكلاء',
      description: 'إدارة نقاط البيع',
      icon: Icons.store_rounded,
      category: 'الوكلاء',
    ),
    PermissionEntry(
      key: 'technicians',
      labelAr: 'فني التوصيل',
      description: 'إدارة فريق الصيانة',
      icon: Icons.engineering_rounded,
      category: 'الوكلاء',
    ),

    // واتساب
    PermissionEntry(
      key: 'whatsapp',
      labelAr: 'رسائل WhatsApp',
      description: 'إرسال رسائل واتساب',
      icon: Icons.chat_rounded,
      category: 'واتساب',
    ),
    PermissionEntry(
      key: 'whatsapp_link',
      labelAr: 'ربط واتساب',
      description: 'ربط حساب واتساب عبر QR',
      icon: Icons.qr_code_rounded,
      category: 'واتساب',
    ),
    PermissionEntry(
      key: 'whatsapp_settings',
      labelAr: 'إعدادات واتساب',
      description: 'إعدادات رسائل واتساب',
      icon: Icons.settings_rounded,
      category: 'واتساب',
    ),
    PermissionEntry(
      key: 'whatsapp_business_api',
      labelAr: 'WhatsApp Business API',
      description: 'إعدادات API الأعمال',
      icon: Icons.business_rounded,
      category: 'واتساب',
    ),
    PermissionEntry(
      key: 'whatsapp_bulk_sender',
      labelAr: 'إرسال رسائل جماعية',
      description: 'إرسال رسائل جماعية',
      icon: Icons.send_rounded,
      category: 'واتساب',
    ),
    PermissionEntry(
      key: 'whatsapp_conversations_fab',
      labelAr: 'محادثات واتساب',
      description: 'عرض زر المحادثات العائم',
      icon: Icons.forum_rounded,
      category: 'واتساب',
    ),

    // البيانات والتخزين
    PermissionEntry(
      key: 'google_sheets',
      labelAr: 'حفظ في الخادم',
      description: 'حفظ البيانات في خادم VPS',
      icon: Icons.cloud_upload_rounded,
      category: 'البيانات',
    ),
    PermissionEntry(
      key: 'local_storage',
      labelAr: 'التخزين المحلي',
      description: 'التخزين المحلي للمشتركين',
      icon: Icons.storage_rounded,
      category: 'البيانات',
    ),
    PermissionEntry(
      key: 'local_storage_import',
      labelAr: 'استيراد البيانات',
      description: 'استيراد من التخزين المحلي',
      icon: Icons.upload_file_rounded,
      category: 'البيانات',
    ),

    // خطط وباقات
    PermissionEntry(
      key: 'plans_bundles',
      labelAr: 'الباقات والعروض',
      description: 'إدارة باقات الاشتراك',
      icon: Icons.local_offer_rounded,
      category: 'المبيعات',
    ),
  ];

  // ═══════════════════════════════════════
  // دوال مساعدة — تُستخدم من باقي الملفات
  // ═══════════════════════════════════════

  /// قائمة مفاتيح النظام الأول
  static List<String> get firstSystemKeys =>
      firstSystem.map((e) => e.key).toList();

  /// قائمة مفاتيح النظام الثاني
  static List<String> get secondSystemKeys =>
      secondSystem.map((e) => e.key).toList();

  /// القيم الافتراضية للنظام الأول (كلها false)
  static Map<String, bool> get firstSystemDefaults =>
      {for (var e in firstSystem) e.key: e.defaultValue};

  /// القيم الافتراضية للنظام الثاني (كلها false)
  static Map<String, bool> get secondSystemDefaults =>
      {for (var e in secondSystem) e.key: e.defaultValue};

  /// البحث عن صلاحية بالمفتاح
  static PermissionEntry? findByKey(String key) {
    for (var e in firstSystem) {
      if (e.key == key) return e;
    }
    for (var e in secondSystem) {
      if (e.key == key) return e;
    }
    return null;
  }

  /// خريطة الأسماء بالعربي لكل مفتاح (للـ V1 Panel)
  static Map<String, String> get allLabelsAr {
    final map = <String, String>{};
    for (var e in firstSystem) {
      map[e.key] = e.labelAr;
    }
    for (var e in secondSystem) {
      map[e.key] = e.labelAr;
    }
    return map;
  }

  /// بناء خريطة features للـ V2 page من قائمة entries
  static Map<String, Map<String, dynamic>> buildV2FeaturesMap(
      List<PermissionEntry> entries) {
    final map = <String, Map<String, dynamic>>{};
    for (var e in entries) {
      map[e.key] = {
        'label': e.labelAr,
        'icon': e.icon,
        'description': e.description,
      };
    }
    return map;
  }
}
