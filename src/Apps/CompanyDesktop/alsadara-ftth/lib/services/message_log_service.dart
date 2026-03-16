/// خدمة تسجيل الرسائل اليومية
/// تسجل كل عملية إرسال واتساب (نجاح/فشل) في Firebase
/// وتولّد تقريراً يومياً للمدير
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'custom_auth_service.dart';
import 'company_settings_service.dart';
import '../whatsapp/services/whatsapp_server_service.dart';

/// أنواع الرسائل
enum MessageCategory {
  renewal, // تجديد اشتراك
  bulk, // إرسال جماعي
  notification, // إشعار فردي
}

/// خدمة تسجيل الرسائل
class MessageLogService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CustomAuthService _authService = CustomAuthService();

  static String? get _currentTenantId => _authService.currentTenantId;

  /// مسار سجل اليوم في Firebase
  static String _getDailyLogPath(String tenantId, String date) {
    return 'tenants/$tenantId/message_logs/daily_$date';
  }

  /// تاريخ اليوم بصيغة YYYY-MM-DD
  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// تاريخ الأمس بصيغة YYYY-MM-DD
  static String _yesterdayKey() {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
  }

  // ─── تسجيل الرسائل ──────────────────────────────────────

  /// تسجيل رسالة مرسلة (نجاح أو فشل)
  static Future<void> log({
    required MessageCategory category,
    required bool success,
    String? phone,
    String? tenantId,
  }) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return;

      final dateKey = _todayKey();
      final docRef = _firestore.doc(_getDailyLogPath(tid, dateKey));
      final categoryName = category.name; // 'renewal', 'bulk', 'notification'

      // استخدام FieldValue.increment للتحديث الذري
      final updates = <String, dynamic>{
        'date': dateKey,
        'updatedAt': FieldValue.serverTimestamp(),
        '$categoryName.total': FieldValue.increment(1),
      };

      if (success) {
        updates['$categoryName.sent'] = FieldValue.increment(1);
        updates['totalSent'] = FieldValue.increment(1);
      } else {
        updates['$categoryName.failed'] = FieldValue.increment(1);
        updates['totalFailed'] = FieldValue.increment(1);
        // حفظ الأرقام الفاشلة (حتى 50 رقم)
        if (phone != null) {
          updates['$categoryName.failedPhones'] = FieldValue.arrayUnion([phone]);
        }
      }

      await docRef.set(updates, SetOptions(merge: true));
    } catch (e) {
      debugPrint('⚠️ فشل تسجيل الرسالة');
    }
  }

  /// تسجيل نتيجة إرسال جماعي كاملة
  static Future<void> logBulkResult({
    required int sent,
    required int failed,
    required List<String> failedPhones,
    String? tenantId,
  }) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return;

      final dateKey = _todayKey();
      final docRef = _firestore.doc(_getDailyLogPath(tid, dateKey));

      final updates = <String, dynamic>{
        'date': dateKey,
        'updatedAt': FieldValue.serverTimestamp(),
        'bulk.total': FieldValue.increment(sent + failed),
        'bulk.sent': FieldValue.increment(sent),
        'bulk.failed': FieldValue.increment(failed),
        'totalSent': FieldValue.increment(sent),
        'totalFailed': FieldValue.increment(failed),
      };

      // حفظ الأرقام الفاشلة (حتى 50 رقم)
      if (failedPhones.isNotEmpty) {
        final phonesToSave = failedPhones.take(50).toList();
        updates['bulk.failedPhones'] = FieldValue.arrayUnion(phonesToSave);
      }

      await docRef.set(updates, SetOptions(merge: true));
      debugPrint('✅ تم تسجيل نتيجة الإرسال الجماعي: $sent نجح، $failed فشل');
    } catch (e) {
      debugPrint('⚠️ فشل تسجيل نتيجة الإرسال الجماعي');
    }
  }

  // ─── قراءة السجلات ──────────────────────────────────────

  /// قراءة سجل يوم محدد
  static Future<Map<String, dynamic>?> getDailyLog({
    required String date,
    String? tenantId,
  }) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return null;

      final doc = await _firestore.doc(_getDailyLogPath(tid, date)).get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!;
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ فشل قراءة السجل اليومي');
      return null;
    }
  }

  /// قراءة سجل اليوم
  static Future<Map<String, dynamic>?> getTodayLog({String? tenantId}) async {
    return getDailyLog(date: _todayKey(), tenantId: tenantId);
  }

  /// قراءة سجل الأمس
  static Future<Map<String, dynamic>?> getYesterdayLog({String? tenantId}) async {
    return getDailyLog(date: _yesterdayKey(), tenantId: tenantId);
  }

  // ─── التقرير اليومي ──────────────────────────────────────

  /// بناء نص التقرير اليومي
  static String buildDailyReport(Map<String, dynamic> log) {
    final date = log['date'] ?? '';
    final renewal = log['renewal'] as Map<String, dynamic>? ?? {};
    final bulk = log['bulk'] as Map<String, dynamic>? ?? {};
    final notification = log['notification'] as Map<String, dynamic>? ?? {};

    final totalSent = (log['totalSent'] ?? 0) as int;
    final totalFailed = (log['totalFailed'] ?? 0) as int;
    final grandTotal = totalSent + totalFailed;
    final successRate = grandTotal > 0
        ? ((totalSent / grandTotal) * 100).toStringAsFixed(1)
        : '0.0';

    final buffer = StringBuffer();
    buffer.writeln('📊 التقرير اليومي - $date');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('');

    // ملخص عام
    buffer.writeln('📈 الملخص العام:');
    buffer.writeln('   إجمالي الرسائل: $grandTotal');
    buffer.writeln('   ✅ ناجحة: $totalSent');
    buffer.writeln('   ❌ فاشلة: $totalFailed');
    buffer.writeln('   📊 نسبة النجاح: $successRate%');
    buffer.writeln('');

    // تفاصيل التجديد
    final rSent = (renewal['sent'] ?? 0) as int;
    final rFailed = (renewal['failed'] ?? 0) as int;
    if (rSent > 0 || rFailed > 0) {
      buffer.writeln('🔄 رسائل التجديد:');
      buffer.writeln('   ✅ ناجحة: $rSent');
      buffer.writeln('   ❌ فاشلة: $rFailed');
      final rFailedPhones = renewal['failedPhones'] as List<dynamic>? ?? [];
      if (rFailedPhones.isNotEmpty) {
        buffer.writeln('   📵 أرقام فاشلة:');
        for (final p in rFailedPhones.take(10)) {
          buffer.writeln('      • $p');
        }
      }
      buffer.writeln('');
    }

    // تفاصيل الإرسال الجماعي
    final bSent = (bulk['sent'] ?? 0) as int;
    final bFailed = (bulk['failed'] ?? 0) as int;
    if (bSent > 0 || bFailed > 0) {
      buffer.writeln('📤 الإرسال الجماعي:');
      buffer.writeln('   ✅ ناجحة: $bSent');
      buffer.writeln('   ❌ فاشلة: $bFailed');
      final bFailedPhones = bulk['failedPhones'] as List<dynamic>? ?? [];
      if (bFailedPhones.isNotEmpty) {
        buffer.writeln('   📵 أرقام فاشلة:');
        for (final p in bFailedPhones.take(10)) {
          buffer.writeln('      • $p');
        }
      }
      buffer.writeln('');
    }

    // تفاصيل الإشعارات
    final nSent = (notification['sent'] ?? 0) as int;
    final nFailed = (notification['failed'] ?? 0) as int;
    if (nSent > 0 || nFailed > 0) {
      buffer.writeln('🔔 الإشعارات:');
      buffer.writeln('   ✅ ناجحة: $nSent');
      buffer.writeln('   ❌ فاشلة: $nFailed');
      buffer.writeln('');
    }

    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('🤖 تقرير آلي - نظام السدارة');

    return buffer.toString();
  }

  /// إرسال التقرير اليومي للمدير
  /// يُرسل تقرير الأمس - يُستدعى عند فتح التطبيق
  static Future<bool> sendDailyReportIfNeeded({String? tenantId}) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return false;

      // التحقق من تفعيل التقرير اليومي
      final isEnabled = await CompanySettingsService.isReportEnabled(
        'daily',
        tenantId: tid,
      );
      if (!isEnabled) {
        debugPrint('📵 التقرير اليومي معطل');
        return false;
      }

      final yesterdayKey = _yesterdayKey();

      // التحقق: هل أُرسل التقرير مسبقاً؟
      final reportSentDoc = await _firestore
          .doc('tenants/$tid/message_logs/report_sent_$yesterdayKey')
          .get();
      if (reportSentDoc.exists) {
        debugPrint('✅ التقرير اليومي أُرسل مسبقاً لـ $yesterdayKey');
        return false;
      }

      // قراءة سجل الأمس
      final log = await getYesterdayLog(tenantId: tid);
      if (log == null) {
        debugPrint('📭 لا يوجد سجل لـ $yesterdayKey');
        return false;
      }

      // التحقق من وجود رسائل فعلاً
      final totalSent = (log['totalSent'] ?? 0) as int;
      final totalFailed = (log['totalFailed'] ?? 0) as int;
      if (totalSent == 0 && totalFailed == 0) {
        debugPrint('📭 لا توجد رسائل مسجلة لـ $yesterdayKey');
        return false;
      }

      // الحصول على رقم المدير
      final managerPhone =
          await CompanySettingsService.getManagerWhatsApp(tenantId: tid);
      if (managerPhone == null || managerPhone.isEmpty) {
        debugPrint('📵 لا يوجد رقم واتساب للمدير');
        return false;
      }

      // بناء وإرسال التقرير
      final report = buildDailyReport(log);
      final formattedPhone = CompanySettingsService.formatPhoneForWhatsApp(managerPhone);

      final sent = await WhatsAppServerService.sendMessage(
        tenantId: tid,
        phone: formattedPhone,
        message: report,
      );

      if (sent) {
        // تسجيل أن التقرير أُرسل
        await _firestore
            .doc('tenants/$tid/message_logs/report_sent_$yesterdayKey')
            .set({
          'sentAt': FieldValue.serverTimestamp(),
          'date': yesterdayKey,
        });
        debugPrint('✅ تم إرسال التقرير اليومي لـ $yesterdayKey');
      }

      return sent;
    } catch (e) {
      debugPrint('❌ خطأ في إرسال التقرير اليومي');
      return false;
    }
  }
}
