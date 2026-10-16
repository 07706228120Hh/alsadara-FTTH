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

  /// جدول أساسي مضمّن لأهم موردي FTTH في العراق + بادئات شائعة (احتياطي).
  /// المصدر الموثوق هو أصل oui.json؛ هذه بادئات معروفة لتحسين التغطية أوفلاين.
  static const Map<String, String> _builtin = {
    // موجّهات / ONU
    '00259E': 'Huawei', '286ED4': 'Huawei', '3CDFBD': 'Huawei',
    'ACE215': 'Huawei', 'E468A3': 'Huawei', '00E0FC': 'Huawei',
    '0015EB': 'ZTE', '289E97': 'ZTE', '9CA9E4': 'ZTE', 'C864C7': 'ZTE',
    '50C7BF': 'TP-Link', 'AC84C6': 'TP-Link', 'C006C3': 'TP-Link',
    '1C61B4': 'TP-Link', '9C5322': 'TP-Link',
    'C83A35': 'Tenda', 'D83ADD': 'Tenda',
    'D4CA6D': 'MikroTik', 'CC2DE0': 'MikroTik',
    '001B2F': 'Nokia', '4CBC98': 'Nokia',
    'D8075E': 'Mercusys',
    // هواتف / أجهزة شائعة
    '3C0754': 'Apple', 'A4B197': 'Apple', 'F0DBF8': 'Apple',
    '001451': 'Apple', '0017F2': 'Apple', 'AC87A3': 'Apple',
    '5CF938': 'Samsung', 'E8508B': 'Samsung', '34BE00': 'Samsung',
    '0012FB': 'Samsung', '001377': 'Samsung',
    '286C07': 'Xiaomi', '640980': 'Xiaomi', '8CBEBE': 'Xiaomi',
    'F8A45F': 'Xiaomi', '78110F': 'Xiaomi',
    '00A0C9': 'Intel', '001517': 'Intel', 'A0C589': 'Intel',
    '0017FA': 'Microsoft', '7CED8D': 'Microsoft',
    'F4F5D8': 'Google', '1844B5': 'Google',
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
