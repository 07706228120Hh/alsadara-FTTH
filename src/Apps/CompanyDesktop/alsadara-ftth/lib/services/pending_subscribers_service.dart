/// خدمة المشتركين المعلّقين — يحفظ آخر 10 مشتركين محلياً للاستخدام أوفلاين
library;

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PendingSubscriber {
  final String name;
  final String phone;
  final String pppoeUser;
  final String pppoePass;
  final String serviceType;
  final String fbg;
  final String fat;
  final String notes;
  final DateTime addedAt;

  PendingSubscriber({
    required this.name,
    required this.phone,
    this.pppoeUser = '',
    this.pppoePass = '',
    this.serviceType = '',
    this.fbg = '',
    this.fat = '',
    this.notes = '',
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'pppoeUser': pppoeUser,
    'pppoePass': pppoePass,
    'serviceType': serviceType,
    'fbg': fbg,
    'fat': fat,
    'notes': notes,
    'addedAt': addedAt.toIso8601String(),
  };

  factory PendingSubscriber.fromJson(Map<String, dynamic> j) => PendingSubscriber(
    name: j['name'] ?? '',
    phone: j['phone'] ?? '',
    pppoeUser: j['pppoeUser'] ?? '',
    pppoePass: j['pppoePass'] ?? '',
    serviceType: j['serviceType'] ?? '',
    fbg: j['fbg'] ?? '',
    fat: j['fat'] ?? '',
    notes: j['notes'] ?? '',
    addedAt: j['addedAt'] != null ? DateTime.tryParse(j['addedAt']) ?? DateTime.now() : DateTime.now(),
  );
}

class PendingSubscribersService {
  static const _key = 'pending_subscribers_v1';
  static const _maxItems = 10;

  static Future<List<PendingSubscriber>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => PendingSubscriber.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(PendingSubscriber sub) async {
    final all = await getAll();
    // أزل المكرر (بنفس الهاتف)
    all.removeWhere((s) => s.phone == sub.phone);
    // أضف في البداية
    all.insert(0, sub);
    // احتفظ بآخر 10 فقط
    if (all.length > _maxItems) all.removeRange(_maxItems, all.length);
    await _save(all);
  }

  static Future<void> remove(String phone) async {
    final all = await getAll();
    all.removeWhere((s) => s.phone == phone);
    await _save(all);
  }

  static Future<void> _save(List<PendingSubscriber> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  static Future<PendingSubscriber?> findByPhone(String phone) async {
    final all = await getAll();
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    for (final s in all) {
      if (s.phone.replaceAll(RegExp(r'\D'), '') == clean) return s;
    }
    return null;
  }
}
