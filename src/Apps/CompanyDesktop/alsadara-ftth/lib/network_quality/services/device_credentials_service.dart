/// إدارة اعتمادات الدخول لأجهزة الشبكة — Network Quality
///
/// (1) قاعدة اعتمادات افتراضية لكل ماركة (تُجرَّب تلقائياً).
/// (2) حفظ/استرجاع اعتماد يدوي لكل جهاز (IP) مشفّراً عبر flutter_secure_storage.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceCredential {
  final String user;
  final String pass;
  const DeviceCredential(this.user, this.pass);

  Map<String, String> toJson() => {'u': user, 'p': pass};
  factory DeviceCredential.fromJson(Map j) =>
      DeviceCredential(j['u']?.toString() ?? '', j['p']?.toString() ?? '');
}

class DeviceCredentialsService {
  static const _storage = FlutterSecureStorage();
  static const _prefix = 'nq_cred_'; // مفتاح مخزّن لكل IP

  /// اعتمادات افتراضية شائعة لكل ماركة (قراءة فقط لجلب المعلومات).
  static const Map<String, List<DeviceCredential>> _defaults = {
    'huawei': [
      DeviceCredential('telecomadmin', 'admintelecom'),
      DeviceCredential('root', 'adminHW'),
      DeviceCredential('admin', 'admin'),
      DeviceCredential('admin', 'admin@huawei.com'),
    ],
    'zte': [
      DeviceCredential('admin', 'admin'),
      DeviceCredential('user', 'user'),
      DeviceCredential('admin', 'Web@0063'),
    ],
    'tp-link': [
      DeviceCredential('admin', 'admin'),
      DeviceCredential('admin', 'password'),
    ],
    'tenda': [
      DeviceCredential('admin', 'admin'),
      DeviceCredential('admin', ''),
    ],
    'd-link': [
      DeviceCredential('admin', 'admin'),
      DeviceCredential('admin', ''),
    ],
    'mikrotik': [
      DeviceCredential('admin', ''),
      DeviceCredential('admin', 'admin'),
    ],
    'netis': [
      DeviceCredential('admin', 'admin'),
      DeviceCredential('guest', 'guest'),
    ],
    'nokia': [
      DeviceCredential('admin', '1234'),
      DeviceCredential('AdminGPON', 'ALC#FGU'),
      DeviceCredential('admin', 'admin'),
    ],
  };

  /// قائمة الاعتمادات المرشّحة لجهاز: المحفوظ يدوياً أولاً ثم الافتراضي للماركة.
  static Future<List<DeviceCredential>> candidatesFor(
      String ip, String brandGuess) async {
    final list = <DeviceCredential>[];
    final saved = await getSaved(ip);
    if (saved != null) list.add(saved);

    final key = brandGuess.toLowerCase();
    for (final entry in _defaults.entries) {
      if (key.contains(entry.key) || entry.key.contains(key.split(' ').first)) {
        list.addAll(entry.value);
      }
    }
    // إن لم تُعرف الماركة، جرّب الأكثر شيوعاً.
    if (list.isEmpty || (saved == null && !_defaults.keys.any((k) => key.contains(k)))) {
      list.addAll(const [
        DeviceCredential('admin', 'admin'),
        DeviceCredential('telecomadmin', 'admintelecom'),
        DeviceCredential('admin', ''),
      ]);
    }
    return list;
  }

  static Future<DeviceCredential?> getSaved(String ip) async {
    try {
      final raw = await _storage.read(key: '$_prefix$ip');
      if (raw == null) return null;
      return DeviceCredential.fromJson(jsonDecode(raw) as Map);
    } catch (e) {
      debugPrint('[Creds] read error: $e');
      return null;
    }
  }

  static Future<void> save(String ip, DeviceCredential cred) async {
    try {
      await _storage.write(
          key: '$_prefix$ip', value: jsonEncode(cred.toJson()));
    } catch (e) {
      debugPrint('[Creds] save error: $e');
    }
  }

  static Future<void> remove(String ip) async {
    try {
      await _storage.delete(key: '$_prefix$ip');
    } catch (_) {}
  }
}
