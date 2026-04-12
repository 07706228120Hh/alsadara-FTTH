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
      key: 'hr.security_code',
      labelAr: 'كود أمان البصمة',
      description: 'عرض وتعديل كود أمان البصمة للموظفين',
      icon: Icons.shield_rounded,
      category: 'الموارد البشرية',
      parent: 'hr',
      allowedActions: ['view', 'edit'],
    ),
    PermissionEntry(
      key: 'hr.ftth_info',
      labelAr: 'معلومات FTTH',
      description: 'عرض وتعديل بيانات ربط نظام FTTH للموظفين',
      icon: Icons.router_rounded,
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

    // ─── تتبع المواقع ───
    PermissionEntry(
      key: 'tracking',
      labelAr: 'تتبع المواقع',
      description: 'عرض مواقع الفنيين على الخريطة والتقارير',
      icon: Icons.location_searching_rounded,
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

    // ─── المحادثة الداخلية (Sadara Chat) ───
    PermissionEntry(
      key: 'chat',
      labelAr: 'المحادثة الداخلية',
      description: 'نظام المحادثة الداخلي بين الموظفين',
      icon: Icons.forum_rounded,
      category: 'التواصل',
    ),
    PermissionEntry(
      key: 'chat.send_text',
      labelAr: 'إرسال نص',
      description: 'إرسال رسائل نصية',
      icon: Icons.message_rounded,
      category: 'التواصل',
      parent: 'chat',
      allowedActions: ['view', 'send'],
    ),
    PermissionEntry(
      key: 'chat.send_image',
      labelAr: 'إرسال صور',
      description: 'إرسال صور ومرفقات صورية',
      icon: Icons.image_rounded,
      category: 'التواصل',
      parent: 'chat',
      allowedActions: ['view', 'send'],
    ),
    PermissionEntry(
      key: 'chat.send_audio',
      labelAr: 'إرسال صوت',
      description: 'إرسال رسائل صوتية',
      icon: Icons.mic_rounded,
      category: 'التواصل',
      parent: 'chat',
      allowedActions: ['view', 'send'],
    ),
    PermissionEntry(
      key: 'chat.send_location',
      labelAr: 'إرسال موقع',
      description: 'مشاركة الموقع الجغرافي',
      icon: Icons.location_on_rounded,
      category: 'التواصل',
      parent: 'chat',
      allowedActions: ['view', 'send'],
    ),
    PermissionEntry(
      key: 'chat.send_contact',
      labelAr: 'إرسال جهة اتصال',
      description: 'مشاركة أرقام الموظفين',
      icon: Icons.contact_phone_rounded,
      category: 'التواصل',
      parent: 'chat',
      allowedActions: ['view', 'send'],
    ),
    PermissionEntry(
      key: 'chat.send_file',
      labelAr: 'إرسال ملفات',
      description: 'إرسال مستندات وملفات',
      icon: Icons.attach_file_rounded,
      category: 'التواصل',
      parent: 'chat',
      allowedActions: ['view', 'send'],
    ),
    PermissionEntry(
      key: 'chat.create_group',
      labelAr: 'إنشاء مجموعة',
      description: 'إنشاء مجموعات محادثة مخصصة',
      icon: Icons.group_add_rounded,
      category: 'التواصل',
      parent: 'chat',
      allowedActions: ['add'],
    ),
    PermissionEntry(
      key: 'chat.create_broadcast',
      labelAr: 'بث للجميع',
      description: 'إرسال رسالة بث لجميع الموظفين',
      icon: Icons.campaign_rounded,
      category: 'التواصل',
      parent: 'chat',
      allowedActions: ['add', 'send'],
    ),
    PermissionEntry(
      key: 'chat.create_department',
      labelAr: 'محادثة قسم',
      description: 'إنشاء محادثة قسم',
      icon: Icons.groups_rounded,
      category: 'التواصل',
      parent: 'chat',
      allowedActions: ['add'],
    ),
    PermissionEntry(
      key: 'chat.delete_messages',
      labelAr: 'حذف الرسائل',
      description: 'حذف رسائل الآخرين (مدير)',
      icon: Icons.delete_sweep_rounded,
      category: 'التواصل',
      parent: 'chat',
      allowedActions: ['delete'],
    ),
    PermissionEntry(
      key: 'chat.manage_members',
      labelAr: 'إدارة الأعضاء',
      description: 'إضافة وإزالة أعضاء من المجموعات',
      icon: Icons.manage_accounts_rounded,
      category: 'التواصل',
      parent: 'chat',
      allowedActions: ['add', 'edit', 'delete'],
    ),
    PermissionEntry(
      key: 'chat.mention',
      labelAr: 'تاق الموظفين',
      description: 'ذكر (@) موظفين في المحادثة',
      icon: Icons.alternate_email_rounded,
      category: 'التواصل',
      parent: 'chat',
      allowedActions: ['send'],
    ),
    PermissionEntry(
      key: 'chat.view_profile',
      labelAr: 'بطاقة الموظف',
      description: 'عرض تفاصيل الموظف عند الضغط على الاسم',
      icon: Icons.badge_rounded,
      category: 'التواصل',
      parent: 'chat',
      allowedActions: ['view'],
    ),
    PermissionEntry(
      key: 'chat.search',
      labelAr: 'بحث في المحادثات',
      description: 'البحث في الرسائل والمحادثات',
      icon: Icons.search_rounded,
      category: 'التواصل',
      parent: 'chat',
      allowedActions: ['view'],
    ),
    PermissionEntry(
      key: 'chat.export',
      labelAr: 'تصدير المحادثات',
      description: 'تصدير سجل المحادثات',
      icon: Icons.download_rounded,
      category: 'التواصل',
      parent: 'chat',
      allowedActions: ['export'],
    ),

    // ─── الإعلانات والتبليغات ───
    PermissionEntry(
      key: 'announcements',
      labelAr: 'الإعلانات والتبليغات',
      description: 'عرض وإدارة الإعلانات والتبليغات',
      icon: Icons.campaign_rounded,
      category: 'الإدارة',
    ),
    PermissionEntry(
      key: 'announcements.manage',
      labelAr: 'إدارة الإعلانات',
      description: 'إضافة وتعديل وحذف الإعلانات',
      icon: Icons.edit_notifications_rounded,
      category: 'الإدارة',
      parent: 'announcements',
      allowedActions: ['view', 'add', 'edit', 'delete'],
    ),

    // ─── الشريط العائم ───
    PermissionEntry(
      key: 'fab_tasks',
      labelAr: 'زر المهام العائم',
      description: 'عرض زر المهام في الشريط العائم',
      icon: Icons.assignment_rounded,
      category: 'الشريط العائم',
      allowedActions: ['view'],
    ),
    PermissionEntry(
      key: 'fab_chat',
      labelAr: 'زر المحادثة العائم',
      description: 'عرض زر المحادثة الداخلية في الشريط العائم',
      icon: Icons.forum_rounded,
      category: 'الشريط العائم',
      allowedActions: ['view'],
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
    PermissionEntry(
      key: 'subscriptions.activate',
      labelAr: 'تفعيل الاشتراكات',
      description: 'تفعيل عادي للاشتراكات يدوياً',
      icon: Icons.touch_app_rounded,
      category: 'المشتركين',
      parent: 'subscriptions',
      allowedActions: ['view', 'add'],
    ),
    PermissionEntry(
      key: 'subscriptions.print_receipt',
      labelAr: 'طباعة وصل التجديد',
      description: 'طباعة وصل عند تجديد اشتراك',
      icon: Icons.print_rounded,
      category: 'المشتركين',
      parent: 'subscriptions',
      allowedActions: ['view', 'print'],
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

    // ─── الشريط العائم ───
    PermissionEntry(
      key: 'fab_tasks',
      labelAr: 'زر المهام العائم',
      description: 'عرض زر المهام في الشريط العائم',
      icon: Icons.assignment_rounded,
      category: 'الشريط العائم',
      allowedActions: ['view'],
    ),
    PermissionEntry(
      key: 'fab_chat',
      labelAr: 'زر المحادثة العائم',
      description: 'عرض زر المحادثة الداخلية في الشريط العائم',
      icon: Icons.forum_rounded,
      category: 'الشريط العائم',
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

  // ═══ القوالب المخصصة (محفوظة في السيرفر + كاش محلي) ═══
  static const String _customTemplatesKey = 'custom_permission_templates';
  static Map<String, Map<String, Map<String, List<String>>>> _customTemplates =
      {};
  static String? _companyId;

  /// تحميل القوالب المخصصة من السيرفر (مع كاش محلي)
  static Future<void> loadCustomTemplates({String? companyId}) async {
    _companyId = companyId;

    // كاش محلي أولاً (للسرعة)
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_customTemplatesKey);
      if (cached != null) _parseTemplatesJson(cached);
    } catch (_) {}

    // جلب من السيرفر
    if (companyId != null && companyId.isNotEmpty) {
      try {
        final api = _getApiClient();
        if (api != null) {
          final response = await api.get(
            '/internal/companies/$companyId/permission-templates',
            (data) => data,
            useInternalKey: true,
          );
          if (response.isSuccess && response.data != null) {
            final serverData = response.data is Map ? response.data['data'] : response.data;
            if (serverData is String && serverData.isNotEmpty) {
              _parseTemplatesJson(serverData);
              // حفظ الكاش المحلي
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(_customTemplatesKey, serverData);
            }
          }
        }
      } catch (_) {
        // فشل الجلب من السيرفر — نستخدم الكاش المحلي
      }
    }
  }

  static void _parseTemplatesJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      _customTemplates = decoded.map((key, value) {
        final templateMap = (value as Map<String, dynamic>).map((fKey, fVal) {
          final actions = (fVal as Map<String, dynamic>)['actions'] as List;
          return MapEntry(fKey, {'actions': actions.cast<String>().toList()});
        });
        return MapEntry(key, templateMap);
      });
    } catch (_) {
      _customTemplates = {};
    }
  }

  /// الحصول على ApiClient (lazy — لتجنب circular dependency)
  static dynamic Function()? _apiClientGetter;
  static void setApiClientGetter(dynamic Function() getter) {
    _apiClientGetter = getter;
  }
  static dynamic _getApiClient() {
    return _apiClientGetter?.call();
  }

  /// حفظ قالب مخصص (في السيرفر + كاش محلي)
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
    // حفظ كاش محلي
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_customTemplates);
    await prefs.setString(_customTemplatesKey, encoded);

    // حفظ في السيرفر
    if (_companyId != null && _companyId!.isNotEmpty) {
      try {
        final api = _getApiClient();
        if (api != null) {
          await api.put(
            '/internal/companies/$_companyId/permission-templates',
            {'templates': encoded},
            (data) => data,
            useInternalKey: true,
          );
        }
      } catch (_) {
        // فشل الحفظ في السيرفر — محفوظ محلياً على الأقل
      }
    }
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
      // ═══ عام ═══
      case 'manager':
        return _buildTemplateAll();
      case 'employee':
        return _buildEmployeeTemplate();
      case 'viewer':
        return _buildViewerTemplate();
      // ═══ قسم الفنيين ═══
      case 'tech_manager':
        return _buildTechManagerTemplate();
      case 'tech_leader':
        return _buildTechLeaderTemplate();
      case 'technician':
        return _buildTechnicianTemplate();
      case 'tech_viewer':
        return _buildTechViewerTemplate();
      // ═══ قسم الحسابات ═══
      case 'acc_manager':
        return _buildAccManagerTemplate();
      case 'acc_leader':
        return _buildAccLeaderTemplate();
      case 'accountant':
        return _buildAccountantTemplate();
      case 'acc_viewer':
        return _buildAccViewerTemplate();
      // ═══ قسم HR ═══
      case 'hr_manager':
        return _buildHrManagerTemplate();
      case 'hr_leader':
        return _buildHrLeaderTemplate();
      case 'hr_viewer':
        return _buildHrViewerTemplate();
      default:
        return {};
    }
  }

  static Map<String, Map<String, List<String>>> _buildTemplateAll() {
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
    'view', 'add', 'edit', 'delete', 'export', 'import', 'print', 'send'
  ];

  // ═══ صلاحيات أساسية مشتركة (بصمة + شاشتي + إعلانات عرض) ═══
  static Map<String, Map<String, List<String>>> _basePermissions() => {
    'attendance': {'actions': ['view', 'add']},
    'attendance.checkin': {'actions': ['view', 'add']},
    'my_dashboard': {'actions': ['view']},
    'announcements': {'actions': ['view']},
    'fab_tasks': {'actions': ['view']},
    'fab_chat': {'actions': ['view']},
  };

  // ═══════════════════════════════════════
  //  عام
  // ═══════════════════════════════════════

  static Map<String, Map<String, List<String>>> _buildEmployeeTemplate() {
    return {
      ..._basePermissions(),
      'tasks': {'actions': ['view']},
      'hr': {'actions': ['view']},
    };
  }

  static Map<String, Map<String, List<String>>> _buildViewerTemplate() {
    final result = <String, Map<String, List<String>>>{};
    for (final sys in [firstSystem, secondSystem]) {
      for (final e in sys) {
        if (e.isTopLevel) {
          result[e.key] = {'actions': ['view']};
        }
      }
    }
    return result;
  }

  // ═══════════════════════════════════════
  //  قسم الفنيين
  // ═══════════════════════════════════════

  static Map<String, Map<String, List<String>>> _buildTechManagerTemplate() {
    return {
      ..._basePermissions(),
      // إعلانات — إدارة كاملة
      'announcements': {'actions': ['view', 'add', 'edit', 'delete']},
      'announcements.manage': {'actions': ['view', 'add', 'edit', 'delete']},
      // حضور كامل
      'attendance': {'actions': _allActions},
      'attendance.dashboard': {'actions': ['view']},
      'attendance.records': {'actions': ['view', 'add', 'edit', 'delete', 'export']},
      'attendance.reports': {'actions': ['view', 'export', 'print']},
      // مهام كاملة
      'tasks': {'actions': _allActions},
      'tasks.assign': {'actions': ['view', 'add', 'edit']},
      'tasks.audit': {'actions': ['view', 'edit']},
      // HR — إدارة موظفي القسم
      'hr': {'actions': ['view', 'edit']},
      'hr.employees': {'actions': ['view', 'add', 'edit', 'delete']},
      'hr.leaves': {'actions': ['view', 'add', 'edit', 'delete']},
      'hr.permissions': {'actions': ['view', 'edit']},
      'hr.security_code': {'actions': ['view', 'edit']},
      'hr.ftth_info': {'actions': ['view', 'edit']},
      'hr.reports': {'actions': ['view', 'export', 'print']},
      // تتبع + متابعة
      'tracking': {'actions': ['view']},
      'follow_up': {'actions': ['view', 'add', 'edit']},
      // اشتراكات
      'subscriptions': {'actions': ['view']},
      'subscriptions.activate': {'actions': ['view', 'add']},
      'subscriptions.print_receipt': {'actions': ['view', 'print']},
      // FTTH
      'users': {'actions': ['view']},
      'zones': {'actions': ['view']},
    };
  }

  static Map<String, Map<String, List<String>>> _buildTechLeaderTemplate() {
    return {
      ..._basePermissions(),
      // حضور
      'attendance.dashboard': {'actions': ['view']},
      'attendance.records': {'actions': ['view']},
      'attendance.reports': {'actions': ['view', 'export']},
      // مهام كاملة + توزيع + تدقيق
      'tasks': {'actions': ['view', 'add', 'edit', 'delete']},
      'tasks.assign': {'actions': ['view', 'add', 'edit']},
      'tasks.audit': {'actions': ['view', 'edit']},
      // HR — عرض + تعديل موظفين
      'hr': {'actions': ['view']},
      'hr.employees': {'actions': ['view', 'edit']},
      'hr.leaves': {'actions': ['view']},
      'hr.security_code': {'actions': ['view', 'edit']},
      // تتبع + متابعة
      'tracking': {'actions': ['view']},
      'follow_up': {'actions': ['view', 'add', 'edit']},
      // اشتراكات
      'subscriptions': {'actions': ['view']},
      'subscriptions.activate': {'actions': ['view', 'add']},
      'subscriptions.print_receipt': {'actions': ['view', 'print']},
    };
  }

  static Map<String, Map<String, List<String>>> _buildTechnicianTemplate() {
    return {
      ..._basePermissions(),
      'tasks': {'actions': ['view', 'add', 'edit']},
      'subscriptions': {'actions': ['view']},
      'subscriptions.print_receipt': {'actions': ['view', 'print']},
    };
  }

  static Map<String, Map<String, List<String>>> _buildTechViewerTemplate() {
    return {
      ..._basePermissions(),
      'tasks': {'actions': ['view']},
      'tracking': {'actions': ['view']},
      'follow_up': {'actions': ['view']},
      'subscriptions': {'actions': ['view']},
      'users': {'actions': ['view']},
    };
  }

  // ═══════════════════════════════════════
  //  قسم الحسابات
  // ═══════════════════════════════════════

  static Map<String, Map<String, List<String>>> _buildAccManagerTemplate() {
    return {
      ..._basePermissions(),
      // إعلانات — إدارة كاملة
      'announcements': {'actions': ['view', 'add', 'edit', 'delete']},
      'announcements.manage': {'actions': ['view', 'add', 'edit', 'delete']},
      // محاسبة كاملة
      'accounting': {'actions': _allActions},
      for (final e in firstSystem.where((e) => e.parent == 'accounting'))
        e.key: {'actions': e.allowedActions ?? _allActions},
      // HR — رواتب + خصومات
      'hr': {'actions': ['view']},
      'hr.salaries': {'actions': ['view', 'add', 'edit', 'export', 'print']},
      'hr.deductions': {'actions': ['view', 'add', 'edit', 'delete']},
      'hr.advances': {'actions': ['view', 'add', 'edit', 'delete']},
      'hr.employees': {'actions': ['view']},
      'hr.reports': {'actions': ['view', 'export', 'print']},
      // حضور — عرض
      'attendance': {'actions': ['view']},
      'attendance.reports': {'actions': ['view', 'export']},
      // FTTH مالي
      'transactions': {'actions': _allActions},
      'accounts': {'actions': _allActions},
      'account_records': {'actions': _allActions},
      'wallet_balance': {'actions': ['view']},
    };
  }

  static Map<String, Map<String, List<String>>> _buildAccLeaderTemplate() {
    return {
      ..._basePermissions(),
      // محاسبة — بدون حذف وإعدادات
      'accounting': {'actions': ['view', 'add', 'edit', 'export', 'print']},
      'accounting.dashboard': {'actions': ['view']},
      'accounting.journals': {'actions': ['view', 'add', 'edit', 'print']},
      'accounting.compound_journals': {'actions': ['view', 'add', 'edit']},
      'accounting.expenses': {'actions': ['view', 'add', 'edit', 'export']},
      'accounting.revenue': {'actions': ['view', 'add', 'edit', 'export']},
      'accounting.collections': {'actions': ['view', 'add', 'edit', 'export']},
      'accounting.cashbox': {'actions': ['view', 'add', 'edit']},
      'accounting.client_accounts': {'actions': ['view', 'export']},
      'accounting.statistics': {'actions': ['view', 'export']},
      'accounting.ftth_operators': {'actions': ['view']},
      'accounting.audit_trail': {'actions': ['view']},
      // HR — رواتب عرض
      'hr.salaries': {'actions': ['view', 'export', 'print']},
      'attendance': {'actions': ['view']},
      // FTTH مالي
      'transactions': {'actions': ['view', 'add', 'edit']},
      'accounts': {'actions': ['view']},
      'wallet_balance': {'actions': ['view']},
    };
  }

  static Map<String, Map<String, List<String>>> _buildAccountantTemplate() {
    return {
      ..._basePermissions(),
      // محاسبة — إدخال فقط
      'accounting': {'actions': ['view', 'add', 'edit']},
      'accounting.dashboard': {'actions': ['view']},
      'accounting.journals': {'actions': ['view', 'add', 'edit']},
      'accounting.expenses': {'actions': ['view', 'add', 'edit']},
      'accounting.revenue': {'actions': ['view', 'add']},
      'accounting.collections': {'actions': ['view', 'add', 'edit']},
      'accounting.cashbox': {'actions': ['view', 'add']},
      'accounting.client_accounts': {'actions': ['view']},
      'accounting.statistics': {'actions': ['view']},
      // FTTH مالي
      'transactions': {'actions': ['view', 'add']},
      'accounts': {'actions': ['view']},
    };
  }

  static Map<String, Map<String, List<String>>> _buildAccViewerTemplate() {
    return {
      ..._basePermissions(),
      'accounting': {'actions': ['view']},
      'accounting.dashboard': {'actions': ['view']},
      'accounting.statistics': {'actions': ['view']},
      'accounting.funds_overview': {'actions': ['view']},
      'accounting.balance_verification': {'actions': ['view']},
      'transactions': {'actions': ['view']},
      'accounts': {'actions': ['view']},
      'wallet_balance': {'actions': ['view']},
    };
  }

  // ═══════════════════════════════════════
  //  قسم HR
  // ═══════════════════════════════════════

  static Map<String, Map<String, List<String>>> _buildHrManagerTemplate() {
    return {
      ..._basePermissions(),
      // إعلانات — إدارة كاملة
      'announcements': {'actions': ['view', 'add', 'edit', 'delete']},
      'announcements.manage': {'actions': ['view', 'add', 'edit', 'delete']},
      // HR كامل
      'hr': {'actions': _allActions},
      for (final e in firstSystem.where((e) => e.parent == 'hr'))
        e.key: {'actions': e.allowedActions ?? _allActions},
      // حضور كامل
      'attendance': {'actions': _allActions},
      for (final e in firstSystem.where((e) => e.parent == 'attendance'))
        e.key: {'actions': e.allowedActions ?? _allActions},
      // تتبع
      'tracking': {'actions': ['view']},
      // مهام — عرض
      'tasks': {'actions': ['view']},
    };
  }

  static Map<String, Map<String, List<String>>> _buildHrLeaderTemplate() {
    return {
      ..._basePermissions(),
      // HR — بدون صلاحيات وحذف
      'hr': {'actions': ['view', 'add', 'edit']},
      'hr.employees': {'actions': ['view', 'add', 'edit']},
      'hr.salaries': {'actions': ['view', 'export', 'print']},
      'hr.leaves': {'actions': ['view', 'add', 'edit']},
      'hr.deductions': {'actions': ['view', 'add', 'edit']},
      'hr.advances': {'actions': ['view', 'add', 'edit']},
      'hr.schedules': {'actions': ['view', 'edit']},
      'hr.departments': {'actions': ['view']},
      'hr.security_code': {'actions': ['view', 'edit']},
      'hr.reports': {'actions': ['view', 'export', 'print']},
      // حضور
      'attendance': {'actions': ['view', 'add']},
      'attendance.dashboard': {'actions': ['view']},
      'attendance.records': {'actions': ['view', 'export']},
      'attendance.reports': {'actions': ['view', 'export', 'print']},
      // تتبع
      'tracking': {'actions': ['view']},
    };
  }

  static Map<String, Map<String, List<String>>> _buildHrViewerTemplate() {
    return {
      ..._basePermissions(),
      'hr': {'actions': ['view']},
      'hr.employees': {'actions': ['view']},
      'hr.salaries': {'actions': ['view']},
      'hr.leaves': {'actions': ['view']},
      'hr.reports': {'actions': ['view']},
      'attendance': {'actions': ['view']},
      'attendance.dashboard': {'actions': ['view']},
      'attendance.records': {'actions': ['view']},
      'attendance.reports': {'actions': ['view']},
    };
  }

  // ═══════════════════════════════════════
  //  أسماء وأيقونات القوالب
  // ═══════════════════════════════════════

  /// أسماء القوالب بالعربي — مُنظمة حسب القسم
  static const Map<String, String> templateNames = {
    // عام
    'manager': 'مدير عام',
    'employee': 'موظف عام',
    'viewer': 'مشاهد عام',
    // قسم الفنيين
    'tech_manager': 'مدير الفنيين',
    'tech_leader': 'ليدر الفنيين',
    'technician': 'فني',
    'tech_viewer': 'مشاهد الفنيين',
    // قسم الحسابات
    'acc_manager': 'مدير الحسابات',
    'acc_leader': 'ليدر الحسابات',
    'accountant': 'محاسب',
    'acc_viewer': 'مشاهد الحسابات',
    // قسم HR
    'hr_manager': 'مدير HR',
    'hr_leader': 'ليدر HR',
    'hr_viewer': 'مشاهد HR',
  };

  /// أيقونة كل قالب
  static const Map<String, IconData> templateIcons = {
    // عام
    'manager': Icons.admin_panel_settings_rounded,
    'employee': Icons.person_rounded,
    'viewer': Icons.visibility_rounded,
    // قسم الفنيين
    'tech_manager': Icons.manage_accounts_rounded,
    'tech_leader': Icons.military_tech_rounded,
    'technician': Icons.engineering_rounded,
    'tech_viewer': Icons.preview_rounded,
    // قسم الحسابات
    'acc_manager': Icons.account_balance_rounded,
    'acc_leader': Icons.leaderboard_rounded,
    'accountant': Icons.calculate_rounded,
    'acc_viewer': Icons.analytics_rounded,
    // قسم HR
    'hr_manager': Icons.supervisor_account_rounded,
    'hr_leader': Icons.groups_rounded,
    'hr_viewer': Icons.person_search_rounded,
  };

  /// تصنيف القوالب حسب القسم (للعرض المُنظم في الواجهة)
  static const Map<String, List<String>> templateCategories = {
    'عام': ['manager', 'employee', 'viewer'],
    'الفنيين': ['tech_manager', 'tech_leader', 'technician', 'tech_viewer'],
    'الحسابات': ['acc_manager', 'acc_leader', 'accountant', 'acc_viewer'],
    'HR': ['hr_manager', 'hr_leader', 'hr_viewer'],
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
