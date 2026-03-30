/// خدمة إعدادات الشركة
/// تدير حفظ وقراءة إعدادات الشركة من Firebase
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'custom_auth_service.dart';

/// نموذج إعدادات الشركة
class CompanySettings {
  // معلومات مدير النظام
  final String? managerName;
  final String? managerWhatsApp;
  final bool receiveReports;

  // إعدادات التقارير
  final bool bulkSendReport; // تقرير بعد الإرسال الجماعي
  final bool dailyReport; // تقرير يومي (مستقبلاً)
  final bool weeklyReport; // تقرير أسبوعي (مستقبلاً)

  // بيانات المستخدم الميداني (لتسجيل الدخول التلقائي للتذاكر)
  final String? fieldUsername;
  final String? fieldPassword;

  final DateTime? updatedAt;

  CompanySettings({
    this.managerName,
    this.managerWhatsApp,
    this.receiveReports = true,
    this.bulkSendReport = true,
    this.dailyReport = false,
    this.weeklyReport = false,
    this.fieldUsername,
    this.fieldPassword,
    this.updatedAt,
  });

  /// تحويل من Map
  factory CompanySettings.fromMap(Map<String, dynamic> data) {
    final reportSettings =
        data['reportSettings'] as Map<String, dynamic>? ?? {};

    final fieldUser =
        data['fieldUser'] as Map<String, dynamic>? ?? {};

    return CompanySettings(
      managerName: data['managerName'] as String?,
      managerWhatsApp: data['managerWhatsApp'] as String?,
      receiveReports: data['receiveReports'] as bool? ?? true,
      bulkSendReport: reportSettings['bulkSendReport'] as bool? ?? true,
      dailyReport: reportSettings['dailyReport'] as bool? ?? false,
      weeklyReport: reportSettings['weeklyReport'] as bool? ?? false,
      fieldUsername: fieldUser['username'] as String?,
      fieldPassword: fieldUser['password'] as String?,
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// تحويل إلى Map
  Map<String, dynamic> toMap() {
    return {
      'managerName': managerName,
      'managerWhatsApp': managerWhatsApp,
      'receiveReports': receiveReports,
      'reportSettings': {
        'bulkSendReport': bulkSendReport,
        'dailyReport': dailyReport,
        'weeklyReport': weeklyReport,
      },
      'fieldUser': {
        'username': fieldUsername,
        'password': fieldPassword,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// نسخة معدلة
  CompanySettings copyWith({
    String? managerName,
    String? managerWhatsApp,
    bool? receiveReports,
    bool? bulkSendReport,
    bool? dailyReport,
    bool? weeklyReport,
    String? fieldUsername,
    String? fieldPassword,
  }) {
    return CompanySettings(
      managerName: managerName ?? this.managerName,
      managerWhatsApp: managerWhatsApp ?? this.managerWhatsApp,
      receiveReports: receiveReports ?? this.receiveReports,
      bulkSendReport: bulkSendReport ?? this.bulkSendReport,
      dailyReport: dailyReport ?? this.dailyReport,
      weeklyReport: weeklyReport ?? this.weeklyReport,
      fieldUsername: fieldUsername ?? this.fieldUsername,
      fieldPassword: fieldPassword ?? this.fieldPassword,
      updatedAt: updatedAt,
    );
  }

  /// التحقق من وجود بيانات المستخدم الميداني
  bool get hasFieldUser =>
      fieldUsername != null &&
      fieldUsername!.isNotEmpty &&
      fieldPassword != null &&
      fieldPassword!.isNotEmpty;
}

/// خدمة إعدادات الشركة
class CompanySettingsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CustomAuthService _authService = CustomAuthService();

  static String? get _currentTenantId => _authService.currentTenantId;

  /// مسار الإعدادات في Firebase
  static String _getSettingsPath(String tenantId) {
    return 'tenants/$tenantId/settings/company';
  }

  /// حفظ إعدادات الشركة
  static Future<bool> saveSettings(CompanySettings settings,
      {String? tenantId}) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) {
        debugPrint('❌ لا يوجد tenant محدد');
        return false;
      }

      await _firestore.doc(_getSettingsPath(tid)).set(
            settings.toMap(),
            SetOptions(merge: true),
          );

      debugPrint('✅ تم حفظ إعدادات الشركة');
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في حفظ إعدادات الشركة');
      return false;
    }
  }

  /// تحميل إعدادات الشركة
  static Future<CompanySettings> getSettings({String? tenantId}) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) {
        debugPrint('⚠️ لا يوجد tenant - إرجاع الإعدادات الافتراضية');
        return CompanySettings();
      }

      final doc = await _firestore.doc(_getSettingsPath(tid)).get();

      if (doc.exists && doc.data() != null) {
        return CompanySettings.fromMap(doc.data()!);
      }

      return CompanySettings();
    } catch (e) {
      debugPrint('⚠️ خطأ في تحميل الإعدادات');
      return CompanySettings();
    }
  }

  /// الحصول على بيانات المستخدم الميداني
  static Future<({String username, String password})?> getFieldUser(
      {String? tenantId}) async {
    final settings = await getSettings(tenantId: tenantId);
    if (settings.hasFieldUser) {
      return (username: settings.fieldUsername!, password: settings.fieldPassword!);
    }
    return null;
  }

  /// حفظ رقم واتساب المدير فقط
  static Future<bool> saveManagerWhatsApp(String phone,
      {String? tenantId}) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return false;

      await _firestore.doc(_getSettingsPath(tid)).set({
        'managerWhatsApp': phone,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      debugPrint('❌ خطأ في حفظ رقم المدير');
      return false;
    }
  }

  /// الحصول على رقم واتساب المدير
  static Future<String?> getManagerWhatsApp({String? tenantId}) async {
    final settings = await getSettings(tenantId: tenantId);
    return settings.managerWhatsApp;
  }

  /// التحقق من تفعيل استلام التقارير
  static Future<bool> isReportEnabled(String reportType,
      {String? tenantId}) async {
    final settings = await getSettings(tenantId: tenantId);

    if (!settings.receiveReports) return false;

    switch (reportType) {
      case 'bulk_send':
        return settings.bulkSendReport;
      case 'daily':
        return settings.dailyReport;
      case 'weekly':
        return settings.weeklyReport;
      default:
        return false;
    }
  }

  /// إرسال تقرير للمدير عبر واتساب
  static Future<bool> sendReportToManager({
    required String reportTitle,
    required String reportContent,
    String? tenantId,
  }) async {
    try {
      final settings = await getSettings(tenantId: tenantId);

      if (!settings.receiveReports) {
        debugPrint('📵 استلام التقارير معطل');
        return false;
      }

      final managerPhone = settings.managerWhatsApp;
      if (managerPhone == null || managerPhone.isEmpty) {
        debugPrint('📵 لا يوجد رقم واتساب للمدير');
        return false;
      }

      // هنا سيتم الإرسال الفعلي (سنربطه لاحقاً مع خدمة الواتساب)
      debugPrint('📤 إرسال تقرير للمدير: $managerPhone');
      debugPrint('📋 العنوان: $reportTitle');
      debugPrint('📝 المحتوى: $reportContent');

      // TODO: ربط مع WhatsAppServerService أو API

      return true;
    } catch (e) {
      debugPrint('❌ خطأ في إرسال التقرير');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════
  //  إعدادات التذكير التلقائي (Auto Reminder)
  //  تُحفظ في: tenants/{tenantId}/settings/auto_reminders
  // ══════════════════════════════════════════════════════

  static String _getRemindersPath(String tenantId) {
    return 'tenants/$tenantId/settings/auto_reminders';
  }

  static String _getReminderResultsPath(String tenantId) {
    return 'tenants/$tenantId/settings/auto_reminder_results';
  }

  /// حفظ إعدادات التذكير التلقائي
  static Future<bool> saveReminderSettings({
    required bool enabled,
    required List<Map<String, dynamic>> batches,
    String? tenantId,
  }) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return false;

      await _firestore.doc(_getRemindersPath(tid)).set({
        'enabled': enabled,
        'batches': batches,
        'tenantId': tid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('✅ تم حفظ إعدادات التذكير التلقائي');
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في حفظ إعدادات التذكير: $e');
      return false;
    }
  }

  /// تحميل إعدادات التذكير التلقائي
  static Future<Map<String, dynamic>> getReminderSettings({
    String? tenantId,
  }) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return {'enabled': false, 'batches': []};

      final doc = await _firestore.doc(_getRemindersPath(tid)).get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!;
      }
      return {'enabled': false, 'batches': []};
    } catch (e) {
      debugPrint('⚠️ خطأ في تحميل إعدادات التذكير: $e');
      return {'enabled': false, 'batches': []};
    }
  }

  /// حفظ نتائج آخر تنفيذ لوجبة
  static Future<bool> saveReminderResult({
    required String batchId,
    required Map<String, dynamic> result,
    String? tenantId,
  }) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return false;

      await _firestore.doc(_getReminderResultsPath(tid)).set({
        batchId: result,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      debugPrint('❌ خطأ في حفظ نتيجة التذكير: $e');
      return false;
    }
  }

  /// تحميل نتائج التذكير
  static Future<Map<String, dynamic>> getReminderResults({
    String? tenantId,
  }) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return {};

      final doc = await _firestore.doc(_getReminderResultsPath(tid)).get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!;
      }
      return {};
    } catch (e) {
      debugPrint('⚠️ خطأ في تحميل نتائج التذكير: $e');
      return {};
    }
  }

  /// تنسيق رقم الهاتف للواتساب
  static String formatPhoneForWhatsApp(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');

    // إزالة 00 من البداية
    if (cleaned.startsWith('00')) {
      cleaned = cleaned.substring(2);
    }

    // تحويل 07 إلى 9647
    if (cleaned.startsWith('07')) {
      cleaned = '964${cleaned.substring(1)}';
    }

    // تحويل 7 إلى 9647
    if (cleaned.startsWith('7') && cleaned.length == 10) {
      cleaned = '964$cleaned';
    }

    return cleaned;
  }
}
