import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ═══════════════════════════════════════════════════════════════
/// سجل الصلاحيات المركزي V3 — هرمي دقيق
/// ═══════════════════════════════════════════════════════════════
///
/// البنية: قسم → ميزة فرعية → إجراء
/// المفتاح الفرعي يستخدم نقطة: 'accounting.journals'
///
/// القاعدة الهرمية:
///   - إذا الأب مغلق ← جميع الأبناء مغلقة تلقائياً
///   - إذا الأب مفتوح + الابن غير موجود ← يرث من الأب
///   - إذا الأب مفتوح + الابن موجود ← يستخدم قيمة الابن
///
/// عند إضافة ميزة جديدة:
/// 1. أضف [PermissionEntry] في القائمة المناسبة هنا
/// 2. انتهى! ← تظهر تلقائياً في كل مكان
/// ═══════════════════════════════════════════════════════════════

/// تعريف صلاحية واحدة
class PermissionEntry {
  /// المفتاح الفريد (مثل 'accounting', 'accounting.journals')
  final String key;

  /// الاسم بالعربي
  final String labelAr;

  /// الوصف (للـ V2 page)
  final String description;

  /// الأيقونة
  final IconData icon;

  /// القيمة الافتراضية (دائماً false)
  final bool defaultValue;

  /// الفئة/القسم في واجهة الإدارة
  final String category;

  /// المفتاح الأب (null = مفتاح رئيسي)
  final String? parent;

  /// الإجراءات المسموحة لهذه الميزة (null = جميع الإجراءات)
  final List<String>? allowedActions;

  const PermissionEntry({
    required this.key,
    required this.labelAr,
    required this.description,
    required this.icon,
    this.defaultValue = false,
    this.category = 'عام',
    this.parent,
    this.allowedActions,
  });

  /// هل هذا مفتاح رئيسي (بدون أب)؟
  bool get isTopLevel => parent == null;

  /// هل هذا مفتاح فرعي؟
  bool get isSubKey => parent != null;
}

/// سجل الصلاحيات المركزي
class PermissionRegistry {
  PermissionRegistry._();

  // ═══════════════════════════════════════
  // النظام الأول — الصفحة الرئيسية
  // ═══════════════════════════════════════

  static const List<PermissionEntry> firstSystem = [
    // ─── البصمة والحضور ───
    PermissionEntry(
      key: 'attendance',
      labelAr: 'البصمة والحضور',
      description: 'تسجيل حضور وانصراف الموظفين',
      icon: Icons.fingerprint_rounded,
      category: 'الموارد البشرية',
    ),
    PermissionEntry(
      key: 'attendance.dashboard',
      labelAr: 'لوحة الحضور',
      description: 'عرض ملخص حالة الحضور والغياب',
      icon: Icons.dashboard_rounded,
      category: 'الموارد البشرية',
      parent: 'attendance',
      allowedActions: ['view'],
    ),
    PermissionEntry(
      key: 'attendance.checkin',
      labelAr: 'تسجيل الدخول/الخروج',
      description: 'تسجيل بصمة الحضور والانصراف',
      icon: Icons.login_rounded,
      category: 'الموارد البشرية',
      parent: 'attendance',
      allowedActions: ['view', 'add'],
    ),
    PermissionEntry(
      key: 'attendance.records',
      labelAr: 'سجلات الحضور',
      description: 'عرض وتعديل سجلات الحضور',
      icon: Icons.list_alt_rounded,
      category: 'الموارد البشرية',
      parent: 'attendance',
      allowedActions: ['view', 'add', 'edit', 'delete', 'export'],
    ),
    PermissionEntry(
      key: 'attendance.reports',
      labelAr: 'تقارير الحضور',
      description: 'عرض وطباعة تقارير الحضور',
      icon: Icons.assessment_rounded,
      category: 'الموارد البشرية',
      parent: 'attendance',
      allowedActions: ['view', 'export', 'print'],
    ),

    // ─── الموارد البشرية ───
    PermissionEntry(
      key: 'hr',
      labelAr: 'الموارد البشرية',
      description: 'إدارة شؤون الموظفين والرواتب',
      icon: Icons.people_alt_rounded,
      category: 'الموارد البشرية',
    ),
    PermissionEntry(
      key: 'hr.employees',
      labelAr: 'إدارة الموظفين',
      description: 'عرض وتعديل بيانات الموظفين',
      icon: Icons.badge_rounded,
      category: 'الموارد البشرية',
      parent: 'hr',
      allowedActions: ['view', 'add', 'edit', 'delete'],
    ),
    PermissionEntry(
      key: 'hr.salaries',
      labelAr: 'الرواتب',
      description: 'إدارة رواتب الموظفين',
      icon: Icons.payments_rounded,
      category: 'الموارد البشرية',
      parent: 'hr',
      allowedActions: ['view', 'add', 'edit', 'export', 'print'],
    ),
    PermissionEntry(
      key: 'hr.leaves',
      labelAr: 'الإجازات',
      description: 'إدارة طلبات الإجازات',
      icon: Icons.event_busy_rounded,
      category: 'الموارد البشرية',
      parent: 'hr',
      allowedActions: ['view', 'add', 'edit', 'delete'],
    ),
    PermissionEntry(
      key: 'hr.deductions',
      labelAr: 'الخصومات',
      description: 'إدارة خصومات الموظفين',
      icon: Icons.money_off_rounded,
      category: 'الموارد البشرية',
      parent: 'hr',
      allowedActions: ['view', 'add', 'edit', 'delete'],
    ),
    PermissionEntry(
      key: 'hr.advances',
      labelAr: 'السلف',
      description: 'إدارة سلف الموظفين',
      icon: Icons.request_quote_rounded,
      category: 'الموارد البشرية',
      parent: 'hr',
      allowedActions: ['view', 'add', 'edit', 'delete'],
    ),
    PermissionEntry(
      key: 'hr.schedules',
      labelAr: 'جداول العمل',
      description: 'إدارة مواعيد الدوام',
      icon: Icons.schedule_rounded,
      category: 'الموارد البشرية',
      parent: 'hr',
      allowedActions: ['view', 'add', 'edit', 'delete'],
    ),
    PermissionEntry(
      key: 'hr.departments',
      labelAr: 'الأقسام',
      description: 'إدارة أقسام الشركة',
      icon: Icons.account_tree_rounded,
      category: 'الموارد البشرية',
      parent: 'hr',
      allowedActions: ['view', 'add', 'edit', 'delete'],
    ),
    PermissionEntry(
      key: 'hr.permissions',
      labelAr: 'صلاحيات الموظف',
      description: 'تعديل صلاحيات الموظفين',
      icon: Icons.admin_panel_settings_rounded,
      category: 'الموارد البشرية',
      parent: 'hr',
      allowedActions: ['view', 'edit'],
    ),
    PermissionEntry(
      key: 'hr.reports',
      labelAr: 'تقارير HR',
      description: 'عرض وتصدير تقارير الموارد البشرية',
      icon: Icons.summarize_rounded,
      category: 'الموارد البشرية',
      parent: 'hr',
      allowedActions: ['view', 'export', 'print'],
    ),

    // ─── صفحة الوكيل ───
    PermissionEntry(
      key: 'agent',
      labelAr: 'صفحة الوكيل',
      description: 'إدارة وكلاء المبيعات والتوزيع',
      icon: Icons.support_agent_rounded,
      category: 'المبيعات',
    ),

    // ─── المهام ───
    PermissionEntry(
      key: 'tasks',
      labelAr: 'المهام',
      description: 'إدارة المهام والتكليفات',
      icon: Icons.task_alt_rounded,
      category: 'التشغيل',
    ),
    PermissionEntry(
      key: 'tasks.assign',
      labelAr: 'توزيع المهام',
      description: 'إسناد المهام للموظفين',
      icon: Icons.assignment_ind_rounded,
      category: 'التشغيل',
      parent: 'tasks',
      allowedActions: ['view', 'add', 'edit'],
    ),
    PermissionEntry(
      key: 'tasks.audit',
      labelAr: 'تدقيق المهام',
      description: 'مراجعة وتدقيق المهام المنجزة',
      icon: Icons.fact_check_rounded,
      category: 'التشغيل',
      parent: 'tasks',
      allowedActions: ['view', 'edit'],
    ),

    // ─── الزونات ───
    PermissionEntry(
      key: 'zones',
      labelAr: 'الزونات',
      description: 'تحديد مناطق العمل والتغطية',
      icon: Icons.map_rounded,
      category: 'التشغيل',
    ),

    // ─── البحث الذكي ───
    PermissionEntry(
      key: 'ai_search',
      labelAr: 'البحث بالذكاء الاصطناعي',
      description: 'بحث بالذكاء الاصطناعي',
      icon: Icons.auto_awesome_rounded,
      category: 'أدوات',
    ),

    // ─── منصة الصدارة ───
    PermissionEntry(
      key: 'sadara_portal',
      labelAr: 'منصة الصدارة',
      description: 'الوصول لمنصة الصدارة الإدارية',
      icon: Icons.admin_panel_settings_rounded,
      category: 'الإدارة',
    ),

    // ─── النظام المحاسبي ───
    PermissionEntry(
      key: 'accounting',
      labelAr: 'النظام المحاسبي',
      description: 'إدارة الحسابات والمصروفات والرواتب',
      icon: Icons.account_balance_rounded,
      category: 'المالية',
    ),
    PermissionEntry(
      key: 'accounting.dashboard',
      labelAr: 'لوحة القيادة المحاسبية',
      description: 'ملخص الوضع المالي والإحصائيات',
      icon: Icons.dashboard_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view'],
    ),
    PermissionEntry(
      key: 'accounting.chart',
      labelAr: 'شجرة الحسابات',
      description: 'دليل الحسابات المحاسبية',
      icon: Icons.account_tree_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'add', 'edit', 'delete'],
    ),
    PermissionEntry(
      key: 'accounting.journals',
      labelAr: 'القيود اليومية',
      description: 'إدخال ومراجعة القيود المحاسبية',
      icon: Icons.menu_book_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'add', 'edit', 'delete', 'print'],
    ),
    PermissionEntry(
      key: 'accounting.compound_journals',
      labelAr: 'القيود المركبة',
      description: 'قيود محاسبية متعددة الأطراف',
      icon: Icons.auto_stories_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'add', 'edit', 'delete'],
    ),
    PermissionEntry(
      key: 'accounting.expenses',
      labelAr: 'المصروفات',
      description: 'تسجيل وإدارة المصروفات',
      icon: Icons.money_off_csred_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'add', 'edit', 'delete', 'export'],
    ),
    PermissionEntry(
      key: 'accounting.fixed_expenses',
      labelAr: 'المصروفات الثابتة',
      description: 'المصروفات المتكررة والثابتة',
      icon: Icons.event_repeat_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'add', 'edit', 'delete'],
    ),
    PermissionEntry(
      key: 'accounting.revenue',
      labelAr: 'الإيرادات',
      description: 'تسجيل وتتبع الإيرادات',
      icon: Icons.trending_up_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'add', 'edit', 'delete', 'export'],
    ),
    PermissionEntry(
      key: 'accounting.salaries',
      labelAr: 'تحويلات الرواتب',
      description: 'تحويل ودفع رواتب الموظفين',
      icon: Icons.price_check_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'add', 'export', 'print'],
    ),
    PermissionEntry(
      key: 'accounting.cashbox',
      labelAr: 'الصندوق',
      description: 'إدارة الصندوق النقدي',
      icon: Icons.point_of_sale_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'add', 'edit'],
    ),
    PermissionEntry(
      key: 'accounting.collections',
      labelAr: 'التحصيلات',
      description: 'متابعة التحصيلات والمبالغ الواردة',
      icon: Icons.receipt_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'add', 'edit', 'export'],
    ),
    PermissionEntry(
      key: 'accounting.client_accounts',
      labelAr: 'حسابات العملاء',
      description: 'كشوف حسابات العملاء والأرصدة',
      icon: Icons.people_outline_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'export', 'print'],
    ),
    PermissionEntry(
      key: 'accounting.agent_transactions',
      labelAr: 'معاملات الوكلاء',
      description: 'معاملات وكلاء المبيعات',
      icon: Icons.swap_horiz_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'add', 'edit', 'export'],
    ),
    PermissionEntry(
      key: 'accounting.agent_commission',
      labelAr: 'عمولات الوكلاء',
      description: 'حساب وإدارة عمولات الوكلاء',
      icon: Icons.percent_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'edit', 'export'],
    ),
    PermissionEntry(
      key: 'accounting.ftth_operators',
      labelAr: 'مشغلي FTTH',
      description: 'لوحة مشغلي الألياف',
      icon: Icons.cable_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'add', 'edit'],
    ),
    PermissionEntry(
      key: 'accounting.withdrawals',
      labelAr: 'طلبات السحب',
      description: 'إدارة طلبات السحب والصرف',
      icon: Icons.call_made_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'add', 'edit', 'delete'],
    ),
    PermissionEntry(
      key: 'accounting.statistics',
      labelAr: 'الإحصائيات المالية',
      description: 'رسوم بيانية وإحصائيات',
      icon: Icons.bar_chart_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'export'],
    ),
    PermissionEntry(
      key: 'accounting.funds_overview',
      labelAr: 'نظرة عامة على الأموال',
      description: 'ملخص الأرصدة والتدفقات',
      icon: Icons.account_balance_wallet_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view'],
    ),
    PermissionEntry(
      key: 'accounting.settings',
      labelAr: 'إعدادات المحاسبة',
      description: 'إعدادات النظام المحاسبي',
      icon: Icons.settings_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'edit'],
    ),
    PermissionEntry(
      key: 'accounting.period_closing',
      labelAr: 'إقفال الفترات',
      description: 'إدارة إقفال وفتح الفترات المحاسبية',
      icon: Icons.lock_clock_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'edit'],
    ),
    PermissionEntry(
      key: 'accounting.audit_trail',
      labelAr: 'سجل التدقيق',
      description: 'عرض سجل العمليات والتغييرات المحاسبية',
      icon: Icons.history_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view', 'export'],
    ),
    PermissionEntry(
      key: 'accounting.balance_verification',
      labelAr: 'تحقق التوازن',
      description: 'التحقق من توازن الحسابات',
      icon: Icons.verified_rounded,
      category: 'المالية',
      parent: 'accounting',
      allowedActions: ['view'],
    ),

    // ─── المتابعة ───
    PermissionEntry(
      key: 'follow_up',
      labelAr: 'المتابعة',
      description: 'متابعة المهام والطلبات',
      icon: Icons.playlist_add_check_rounded,
      category: 'التشغيل',
    ),

    // ─── داشبورد التدقيق ───
    PermissionEntry(
      key: 'audit_dashboard',
      labelAr: 'داشبورد التدقيق',
      description: 'لوحة تدقيق ومراجعة المهام',
      icon: Icons.verified_rounded,
      category: 'التشغيل',
    ),

    // ─── شاشتي ───
    PermissionEntry(
      key: 'my_dashboard',
      labelAr: 'شاشتي',
      description: 'لوحة المهام الشخصية',
      icon: Icons.person_pin_rounded,
      category: 'التشغيل',
    ),

    // ─── مشتركي IPTV ───
    PermissionEntry(
      key: 'iptv',
      labelAr: 'مشتركي IPTV',
      description: 'إدارة اشتراكات التلفزيون عبر الإنترنت',
      icon: Icons.live_tv_rounded,
      category: 'الخدمات',
    ),
    PermissionEntry(
      key: 'iptv.manage',
      labelAr: 'إدارة المشتركين',
      description: 'إضافة وتعديل وحذف مشتركي IPTV',
      icon: Icons.edit_rounded,
      category: 'الخدمات',
      parent: 'iptv',
      allowedActions: ['view', 'add', 'edit', 'delete'],
    ),
    PermissionEntry(
      key: 'iptv.whatsapp',
      labelAr: 'إرسال بيانات IPTV',
      description: 'إرسال بيانات الاشتراك عبر واتساب',
      icon: Icons.send_rounded,
      category: 'الخدمات',
      parent: 'iptv',
      allowedActions: ['view', 'send'],
    ),

    // ─── تشخيص النظام ───
    PermissionEntry(
      key: 'diagnostics',
      labelAr: 'تشخيص النظام',
      description: 'أدوات فحص وتشخيص حالة النظام',
      icon: Icons.bug_report_rounded,
      category: 'النظام',
    ),

    // ─── واتساب (النظام الأول) ───
    PermissionEntry(
      key: 'whatsapp',
      labelAr: 'رسائل WhatsApp',
      description: 'إرسال رسائل واتساب',
      icon: Icons.chat_rounded,
      category: 'واتساب',
      allowedActions: ['view', 'send'],
    ),
    PermissionEntry(
      key: 'whatsapp_conversations_fab',
      labelAr: 'محادثات واتساب',
      description: 'عرض زر المحادثات العائم',
      icon: Icons.forum_rounded,
      category: 'واتساب',
      allowedActions: ['view'],
    ),
  ];

  // ═══════════════════════════════════════
  // النظام الثاني — FTTH
  // ═══════════════════════════════════════

  static const List<PermissionEntry> secondSystem = [
    // ─── المشتركين ───
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

    // ─── التشغيل ───
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

    // ─── المالية ───
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
      allowedActions: ['view'],
    ),
    PermissionEntry(
      key: 'transactions',
      labelAr: 'التحويلات',
      description: 'سجل المعاملات المالية',
      icon: Icons.swap_horiz_rounded,
      category: 'المالية',
    ),

    // ─── التقارير والبيانات ───
    PermissionEntry(
      key: 'export',
      labelAr: 'تصدير البيانات',
      description: 'تصدير البيانات والتقارير',
      icon: Icons.file_download_rounded,
      category: 'التقارير',
      allowedActions: ['view', 'export'],
    ),
    PermissionEntry(
      key: 'quick_search',
      labelAr: 'البحث السريع',
      description: 'البحث السريع في البيانات',
      icon: Icons.search_rounded,
      category: 'التقارير',
      allowedActions: ['view'],
    ),
    PermissionEntry(
      key: 'expiring_soon',
      labelAr: 'اشتراكات منتهية قريباً',
      description: 'عرض الاشتراكات القريبة من الانتهاء',
      icon: Icons.warning_amber_rounded,
      category: 'التقارير',
      allowedActions: ['view', 'export', 'send'],
    ),
    PermissionEntry(
      key: 'notifications',
      labelAr: 'الإشعارات',
      description: 'إدارة الإشعارات',
      icon: Icons.notifications_rounded,
      category: 'التقارير',
      allowedActions: ['view', 'add', 'send'],
    ),
    PermissionEntry(
      key: 'audit_logs',
      labelAr: 'سجل التدقيق',
      description: 'سجل العمليات والتغييرات',
      icon: Icons.history_rounded,
      category: 'التقارير',
      allowedActions: ['view', 'export'],
    ),
    PermissionEntry(
      key: 'server_data',
      labelAr: 'بيانات السيرفر',
      description: 'عرض ملفات بيانات السيرفر',
      icon: Icons.storage_rounded,
      category: 'التقارير',
      allowedActions: ['view'],
    ),
    PermissionEntry(
      key: 'dashboard_project',
      labelAr: 'مشروع Dashboard',
      description: 'لوحة بيانات الشارتات والمشاريع',
      icon: Icons.dashboard_customize_rounded,
      category: 'التقارير',
      allowedActions: ['view'],
    ),
    PermissionEntry(
      key: 'fetch_server_data',
      labelAr: 'جلب بيانات الموقع',
      description: 'تحميل بيانات من السيرفر',
      icon: Icons.cloud_download_rounded,
      category: 'التقارير',
      allowedActions: ['view'],
    ),

    // ─── الوكلاء والفنيين ───
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

    // ─── واتساب ───
    PermissionEntry(
      key: 'whatsapp',
      labelAr: 'رسائل WhatsApp',
      description: 'إرسال رسائل واتساب',
      icon: Icons.chat_rounded,
      category: 'واتساب',
      allowedActions: ['view', 'send'],
    ),
    PermissionEntry(
      key: 'whatsapp_link',
      labelAr: 'ربط واتساب',
      description: 'ربط حساب واتساب عبر QR',
      icon: Icons.qr_code_rounded,
      category: 'واتساب',
      allowedActions: ['view'],
    ),
    PermissionEntry(
      key: 'whatsapp_settings',
      labelAr: 'إعدادات واتساب',
      description: 'إعدادات رسائل واتساب',
      icon: Icons.settings_rounded,
      category: 'واتساب',
      allowedActions: ['view', 'edit'],
    ),
    PermissionEntry(
      key: 'whatsapp_business_api',
      labelAr: 'WhatsApp Business API',
      description: 'إعدادات API الأعمال',
      icon: Icons.business_rounded,
      category: 'واتساب',
      allowedActions: ['view', 'edit'],
    ),
    PermissionEntry(
      key: 'whatsapp_bulk_sender',
      labelAr: 'إرسال رسائل جماعية',
      description: 'إرسال رسائل جماعية',
      icon: Icons.send_rounded,
      category: 'واتساب',
      allowedActions: ['view', 'send'],
    ),
    PermissionEntry(
      key: 'whatsapp_conversations_fab',
      labelAr: 'محادثات واتساب',
      description: 'عرض زر المحادثات العائم',
      icon: Icons.forum_rounded,
      category: 'واتساب',
      allowedActions: ['view'],
    ),
    PermissionEntry(
      key: 'whatsapp_templates',
      labelAr: 'قوالب الرسائل',
      description: 'إدارة قوالب رسائل WhatsApp',
      icon: Icons.description_rounded,
      category: 'واتساب',
      allowedActions: ['view'],
    ),

    // ─── أنظمة الواتساب (يتطلب تفعيل الشركة) ───
    PermissionEntry(
      key: 'whatsapp_system_normal',
      labelAr: 'نظام: تطبيق واتساب العادي',
      description: 'تفعيل استخدام تطبيق واتساب المثبت على الجهاز',
      icon: Icons.phone_android_rounded,
      category: 'واتساب',
      allowedActions: ['view', 'send'],
    ),
    PermissionEntry(
      key: 'whatsapp_system_web',
      labelAr: 'نظام: واتساب ويب',
      description: 'تفعيل واتساب ويب داخل التطبيق',
      icon: Icons.language_rounded,
      category: 'واتساب',
      allowedActions: ['view', 'send'],
    ),
    PermissionEntry(
      key: 'whatsapp_system_server',
      labelAr: 'نظام: واتساب السيرفر (VPS)',
      description: 'تفعيل الإرسال التلقائي عبر سيرفر مخصص',
      icon: Icons.dns_rounded,
      category: 'واتساب',
      allowedActions: ['view', 'send'],
    ),
    PermissionEntry(
      key: 'whatsapp_system_api',
      labelAr: 'نظام: واتساب API (Meta Business)',
      description: 'تفعيل Meta Business API للإرسال الجماعي',
      icon: Icons.api_rounded,
      category: 'واتساب',
      allowedActions: ['view', 'send'],
    ),

    // ─── البيانات والتخزين ───
    PermissionEntry(
      key: 'google_sheets',
      labelAr: 'حفظ في الخادم',
      description: 'حفظ البيانات في خادم VPS',
      icon: Icons.cloud_upload_rounded,
      category: 'البيانات',
      allowedActions: ['view'],
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
      allowedActions: ['view', 'import'],
    ),

    // ─── المبيعات ───
    PermissionEntry(
      key: 'plans_bundles',
      labelAr: 'الباقات والعروض',
      description: 'إدارة باقات الاشتراك',
      icon: Icons.local_offer_rounded,
      category: 'المبيعات',
    ),
  ];

  // ═══════════════════════════════════════
  // قوالب الصلاحيات الجاهزة
  // ═══════════════════════════════════════

  /// قالب: مدير — جميع الصلاحيات
  static const String templateManager = 'manager';

  /// قالب: محاسب — المحاسبة + التقارير
  static const String templateAccountant = 'accountant';

  /// قالب: فني — المهام + الحضور فقط
  static const String templateTechnician = 'technician';

  /// قالب: موظف عادي — عرض فقط
  static const String templateEmployee = 'employee';

  /// قالب: مشاهد — عرض فقط بدون أي إجراء
  static const String templateViewer = 'viewer';

  // ═══ القوالب المخصصة (محفوظة محلياً) ═══
  static const String _customTemplatesKey = 'custom_permission_templates';
  static Map<String, Map<String, Map<String, List<String>>>> _customTemplates =
      {};

  /// تحميل القوالب المخصصة من SharedPreferences
  static Future<void> loadCustomTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_customTemplatesKey);
    if (jsonStr == null) return;
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      _customTemplates = decoded.map((key, value) {
        final templateMap = (value as Map<String, dynamic>).map((fKey, fVal) {
          final actions = (fVal as Map<String, dynamic>)['actions'] as List;
          return MapEntry(
              fKey, {'actions': actions.cast<String>().toList()});
        });
        return MapEntry(key, templateMap);
      });
    } catch (_) {
      _customTemplates = {};
    }
  }

  /// حفظ قالب مخصص
  static Future<void> saveCustomTemplate(
      String key, Map<String, Map<String, List<String>>> template) async {
    _customTemplates[key] = template;
    await _persistCustomTemplates();
  }

  /// حذف قالب مخصص (إعادة للافتراضي)
  static Future<void> resetTemplate(String key) async {
    _customTemplates.remove(key);
    await _persistCustomTemplates();
  }

  /// هل القالب معدّل عن الافتراضي؟
  static bool isCustomized(String key) => _customTemplates.containsKey(key);

  /// القالب الافتراضي (الأصلي)
  static Map<String, Map<String, List<String>>> getDefaultTemplate(
      String name) {
    return _getBuiltInTemplate(name);
  }

  static Future<void> _persistCustomTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_customTemplates);
    await prefs.setString(_customTemplatesKey, encoded);
  }

  /// تعريف القوالب — يتحقق أولاً من المخصصة ثم الافتراضية
  static Map<String, Map<String, List<String>>> getTemplate(String name) {
    if (_customTemplates.containsKey(name)) {
      return _customTemplates[name]!;
    }
    return _getBuiltInTemplate(name);
  }

  static Map<String, Map<String, List<String>>> _getBuiltInTemplate(
      String name) {
    switch (name) {
      case 'manager':
        return _buildTemplateAll(true);
      case 'accountant':
        return _buildAccountantTemplate();
      case 'technician':
        return _buildTechnicianTemplate();
      case 'employee':
        return _buildEmployeeTemplate();
      case 'viewer':
        return _buildViewerTemplate();
      default:
        return {};
    }
  }

  static Map<String, Map<String, List<String>>> _buildTemplateAll(bool all) {
    final result = <String, Map<String, List<String>>>{};
    for (final sys in [firstSystem, secondSystem]) {
      for (final e in sys) {
        result[e.key] = {
          'actions': e.allowedActions ?? _allActions,
        };
      }
    }
    return result;
  }

  static const List<String> _allActions = [
    'view',
    'add',
    'edit',
    'delete',
    'export',
    'import',
    'print',
    'send'
  ];

  static Map<String, Map<String, List<String>>> _buildAccountantTemplate() {
    return {
      'accounting': {'actions': _allActions},
      for (final e in firstSystem.where((e) => e.parent == 'accounting'))
        e.key: {'actions': e.allowedActions ?? _allActions},
      'attendance': {
        'actions': ['view']
      },
      'hr.salaries': {
        'actions': ['view', 'export', 'print']
      },
    };
  }

  static Map<String, Map<String, List<String>>> _buildTechnicianTemplate() {
    return {
      'attendance': {
        'actions': ['view', 'add']
      },
      'attendance.checkin': {
        'actions': ['view', 'add']
      },
      'tasks': {
        'actions': ['view', 'add', 'edit']
      },
    };
  }

  static Map<String, Map<String, List<String>>> _buildEmployeeTemplate() {
    return {
      'attendance': {
        'actions': ['view', 'add']
      },
      'attendance.checkin': {
        'actions': ['view', 'add']
      },
      'tasks': {
        'actions': ['view']
      },
      'hr': {
        'actions': ['view']
      },
    };
  }

  static Map<String, Map<String, List<String>>> _buildViewerTemplate() {
    final result = <String, Map<String, List<String>>>{};
    for (final sys in [firstSystem, secondSystem]) {
      for (final e in sys) {
        if (e.isTopLevel) {
          result[e.key] = {
            'actions': ['view'],
          };
        }
      }
    }
    return result;
  }

  /// أسماء القوالب بالعربي
  static const Map<String, String> templateNames = {
    'manager': 'مدير — صلاحيات كاملة',
    'accountant': 'محاسب — المالية والتقارير',
    'technician': 'فني — المهام والحضور',
    'employee': 'موظف — أساسية',
    'viewer': 'مشاهد — عرض فقط',
  };

  /// أيقونة كل قالب
  static const Map<String, IconData> templateIcons = {
    'manager': Icons.admin_panel_settings_rounded,
    'accountant': Icons.account_balance_rounded,
    'technician': Icons.engineering_rounded,
    'employee': Icons.person_rounded,
    'viewer': Icons.visibility_rounded,
  };

  // ═══════════════════════════════════════
  // دوال مساعدة
  // ═══════════════════════════════════════

  /// قائمة مفاتيح النظام الأول (الرئيسية فقط — للتوافق مع V1)
  static List<String> get firstSystemKeys =>
      firstSystem.where((e) => e.isTopLevel).map((e) => e.key).toList();

  /// قائمة مفاتيح النظام الثاني (الرئيسية فقط — للتوافق مع V1)
  static List<String> get secondSystemKeys =>
      secondSystem.where((e) => e.isTopLevel).map((e) => e.key).toList();

  /// جميع مفاتيح النظام الأول (رئيسية + فرعية)
  static List<String> get allFirstSystemKeys =>
      firstSystem.map((e) => e.key).toList();

  /// جميع مفاتيح النظام الثاني (رئيسية + فرعية)
  static List<String> get allSecondSystemKeys =>
      secondSystem.map((e) => e.key).toList();

  /// القيم الافتراضية للنظام الأول
  static Map<String, bool> get firstSystemDefaults =>
      {for (var e in firstSystem) e.key: e.defaultValue};

  /// القيم الافتراضية للنظام الثاني
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

  /// الحصول على أبناء مفتاح رئيسي
  static List<PermissionEntry> getChildren(String parentKey) {
    final all = [...firstSystem, ...secondSystem];
    return all.where((e) => e.parent == parentKey).toList();
  }

  /// الحصول على المفاتيح الرئيسية فقط من قائمة
  static List<PermissionEntry> getTopLevel(List<PermissionEntry> entries) {
    return entries.where((e) => e.isTopLevel).toList();
  }

  /// الحصول على المفاتيح الرئيسية مع أبنائها مجمعة
  static Map<PermissionEntry, List<PermissionEntry>> getGrouped(
      List<PermissionEntry> entries) {
    final map = <PermissionEntry, List<PermissionEntry>>{};
    for (final e in entries.where((e) => e.isTopLevel)) {
      map[e] = entries.where((c) => c.parent == e.key).toList();
    }
    return map;
  }

  /// خريطة الأسماء بالعربي لكل مفتاح
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
        if (e.parent != null) 'parent': e.parent,
        if (e.allowedActions != null) 'allowedActions': e.allowedActions,
      };
    }
    return map;
  }

  /// الإجراءات المسموحة لمفتاح معين
  static List<String> getAllowedActions(String key) {
    final entry = findByKey(key);
    return entry?.allowedActions ?? _allActions;
  }
}
