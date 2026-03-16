/// خدمة تسجيل رسائل الواتساب المُرسلة محلياً
/// تحفظ سجل بكل رسالة مُرسلة مع التاريخ والحالة
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WhatsAppMessageLogEntry {
  final String phone;
  final String customerName;
  final String system; // server, app, web, api
  final String operationType; // renewal, bulk, test, manual
  final bool success;
  final String? error;
  final DateTime timestamp;
  final String? activatedBy; // منفذ العملية

  WhatsAppMessageLogEntry({
    required this.phone,
    required this.customerName,
    required this.system,
    required this.operationType,
    required this.success,
    this.error,
    DateTime? timestamp,
    this.activatedBy,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'customerName': customerName,
        'system': system,
        'operationType': operationType,
        'success': success,
        'error': error,
        'timestamp': timestamp.toIso8601String(),
        'activatedBy': activatedBy,
      };

  factory WhatsAppMessageLogEntry.fromJson(Map<String, dynamic> json) {
    return WhatsAppMessageLogEntry(
      phone: json['phone'] ?? '',
      customerName: json['customerName'] ?? '',
      system: json['system'] ?? 'unknown',
      operationType: json['operationType'] ?? 'unknown',
      success: json['success'] ?? false,
      error: json['error'],
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      activatedBy: json['activatedBy'],
    );
  }
}

class WhatsAppMessageLogService {
  static const String _storageKey = 'whatsapp_message_logs';
  static const int _maxEntries = 5000; // حد أقصى للسجلات

  /// تسجيل رسالة مُرسلة
  static Future<void> log({
    required String phone,
    String customerName = '',
    required String system,
    required String operationType,
    required bool success,
    String? error,
    String? activatedBy,
  }) async {
    try {
      final entry = WhatsAppMessageLogEntry(
        phone: phone,
        customerName: customerName,
        system: system,
        operationType: operationType,
        success: success,
        error: error,
        activatedBy: activatedBy,
      );

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      List<Map<String, dynamic>> logs = [];

      if (raw != null) {
        try {
          logs = List<Map<String, dynamic>>.from(jsonDecode(raw));
        } catch (_) {}
      }

      logs.insert(0, entry.toJson()); // أحدث أولاً

      // حذف القديم إذا تجاوز الحد
      if (logs.length > _maxEntries) {
        logs = logs.sublist(0, _maxEntries);
      }

      await prefs.setString(_storageKey, jsonEncode(logs));
      debugPrint('📝 تم تسجيل رسالة واتساب: $phone (${success ? "نجاح" : "فشل"})');
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل رسالة الواتساب');
    }
  }

  /// جلب السجلات مع تصفية اختيارية بالتاريخ
  static Future<List<WhatsAppMessageLogEntry>> getLogs({
    DateTime? fromDate,
    DateTime? toDate,
    String? system,
    String? operationType,
    bool? successOnly,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return [];

      final logs = List<Map<String, dynamic>>.from(jsonDecode(raw));
      var entries = logs.map((j) => WhatsAppMessageLogEntry.fromJson(j)).toList();

      // تصفية بالتاريخ
      if (fromDate != null) {
        final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
        entries = entries.where((e) => !e.timestamp.isBefore(from)).toList();
      }
      if (toDate != null) {
        final to = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);
        entries = entries.where((e) => !e.timestamp.isAfter(to)).toList();
      }

      // تصفية بالنظام
      if (system != null && system.isNotEmpty) {
        entries = entries.where((e) => e.system == system).toList();
      }

      // تصفية بنوع العملية
      if (operationType != null && operationType.isNotEmpty) {
        entries = entries.where((e) => e.operationType == operationType).toList();
      }

      // تصفية بالنجاح فقط
      if (successOnly != null) {
        entries = entries.where((e) => e.success == successOnly).toList();
      }

      return entries;
    } catch (e) {
      debugPrint('❌ خطأ في جلب سجلات الواتساب');
      return [];
    }
  }

  /// إحصائيات سريعة
  static Future<Map<String, int>> getStats({
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final logs = await getLogs(fromDate: fromDate, toDate: toDate);
    final total = logs.length;
    final success = logs.where((e) => e.success).length;
    final failed = total - success;

    // حسب النظام
    final byServer = logs.where((e) => e.system == 'server').length;
    final byApp = logs.where((e) => e.system == 'app').length;
    final byWeb = logs.where((e) => e.system == 'web').length;
    final byApi = logs.where((e) => e.system == 'api').length;

    // حسب النوع
    final renewal = logs.where((e) => e.operationType == 'renewal').length;
    final bulk = logs.where((e) => e.operationType == 'bulk').length;
    final test = logs.where((e) => e.operationType == 'test').length;
    final manual = logs.where((e) => e.operationType == 'manual').length;

    return {
      'total': total,
      'success': success,
      'failed': failed,
      'server': byServer,
      'app': byApp,
      'web': byWeb,
      'api': byApi,
      'renewal': renewal,
      'bulk': bulk,
      'test': test,
      'manual': manual,
    };
  }

  /// مسح كل السجلات
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
