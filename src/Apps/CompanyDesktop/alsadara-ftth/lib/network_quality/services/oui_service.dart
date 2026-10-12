/// خدمة تمييز الشركة المصنّعة من عنوان MAC — Network Quality
///
/// تُحمّل جدول OUI المرفق (assets/network_quality/oui.json) أوفلاين، مع جدول
/// أساسي مضمّن احتياطياً حتى قبل تحميل الأصل.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class OuiService {
  static Map<String, String>? _table;

  /// جدول أساسي مضمّن لأهم موردي FTTH في العراق (احتياطي).
  static const Map<String, String> _builtin = {
    '00259E': 'Huawei', '286ED4': 'Huawei', '3CDFBD': 'Huawei',
    'ACE215': 'Huawei', 'E468A3': 'Huawei',
    '0015EB': 'ZTE', '289E97': 'ZTE', '9CA9E4': 'ZTE', 'C864C7': 'ZTE',
    '50C7BF': 'TP-Link', 'AC84C6': 'TP-Link', 'C006C3': 'TP-Link',
    'C83A35': 'Tenda', 'D83ADD': 'Tenda',
    'D4CA6D': 'MikroTik', 'CC2DE0': 'MikroTik',
    '001B2F': 'Nokia', '4CBC98': 'Nokia',
  };

  /// يحمّل الجدول مرة واحدة (idempotent).
  static Future<void> ensureLoaded() async {
    if (_table != null) return;
    final t = <String, String>{..._builtin};
    try {
      final raw =
          await rootBundle.loadString('assets/network_quality/oui.json');
      final j = jsonDecode(raw);
      if (j is Map) {
        j.forEach((k, v) {
          final key = k.toString().toUpperCase();
          if (key.length == 6 && v is String) t[key] = v;
        });
      }
    } catch (e) {
      debugPrint('[OUI] asset load skipped: $e');
    }
    _table = t;
  }

  /// يُعيد اسم الشركة من MAC أو '' إن لم يُعرف.
  static String lookup(String mac) {
    final table = _table ?? _builtin;
    final norm =
        mac.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    if (norm.length < 6) return '';
    final prefix = norm.substring(0, 6);
    return table[prefix] ?? '';
  }
}
