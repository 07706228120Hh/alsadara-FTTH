/// خدمة قراءة مواصفات الجهاز المضيف — Network Quality
///
/// تعتمد على device_info_plus الموجودة أصلاً في المشروع + استعلامات نظام
/// خفيفة (Windows) لجلب الذاكرة وعدد الأنوية بدقّة أعلى.
library;

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/quality_models.dart';

class DeviceInfoService {
  static final DeviceInfoPlugin _plugin = DeviceInfoPlugin();

  /// يجمع مواصفات الجهاز بحسب المنصّة.
  static Future<DeviceSpecs> collect() async {
    try {
      if (Platform.isAndroid) {
        return await _android();
      } else if (Platform.isWindows) {
        return await _windows();
      } else if (Platform.isIOS) {
        return await _ios();
      }
    } catch (e) {
      debugPrint('[DeviceInfo] error: $e');
    }
    return DeviceSpecs(platform: Platform.operatingSystem);
  }

  static Future<DeviceSpecs> _android() async {
    final a = await _plugin.androidInfo;
    final extra = <String, String>{
      'الجهاز': a.device,
      'المنتج': a.product,
      'العلامة': a.brand,
      'المعمارية': a.supportedAbis.isNotEmpty ? a.supportedAbis.first : '',
      'Android SDK': '${a.version.sdkInt}',
      'جهاز حقيقي': a.isPhysicalDevice ? 'نعم' : 'محاكي',
    };
    return DeviceSpecs(
      platform: 'Android',
      model: a.model,
      manufacturer: a.manufacturer,
      osVersion: 'Android ${a.version.release} (SDK ${a.version.sdkInt})',
      cpuCores: Platform.numberOfProcessors,
      cpuInfo: a.supportedAbis.isNotEmpty ? a.supportedAbis.first : '',
      deviceId: a.id,
      extra: extra,
    );
  }

  static Future<DeviceSpecs> _ios() async {
    final i = await _plugin.iosInfo;
    return DeviceSpecs(
      platform: 'iOS',
      model: i.utsname.machine,
      manufacturer: 'Apple',
      osVersion: '${i.systemName} ${i.systemVersion}',
      cpuCores: Platform.numberOfProcessors,
      deviceId: i.identifierForVendor ?? '',
      extra: {'الاسم': i.name, 'جهاز حقيقي': i.isPhysicalDevice ? 'نعم' : 'محاكي'},
    );
  }

  static Future<DeviceSpecs> _windows() async {
    final w = await _plugin.windowsInfo;
    int? ramMb;
    int? cores;
    String cpuName = '';

    // ذاكرة النظام عبر WMIC (متوفّر على كل ويندوز) — best-effort.
    try {
      final r = await Process.run(
        'wmic',
        ['ComputerSystem', 'get', 'TotalPhysicalMemory'],
        stdoutEncoding: const SystemEncoding(),
      ).timeout(const Duration(seconds: 5));
      final m = RegExp(r'(\d{6,})').firstMatch(r.stdout.toString());
      if (m != null) {
        ramMb = (int.parse(m.group(1)!) / (1024 * 1024)).round();
      }
    } catch (_) {}

    // اسم المعالج + عدد الأنوية عبر WMIC.
    try {
      final r = await Process.run(
        'wmic',
        ['cpu', 'get', 'Name,NumberOfCores,NumberOfLogicalProcessors'],
        stdoutEncoding: const SystemEncoding(),
      ).timeout(const Duration(seconds: 5));
      final lines = r.stdout
          .toString()
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (lines.length >= 2) {
        final data = lines[1];
        cpuName = data;
        final nums = RegExp(r'(\d+)\s+(\d+)\s*$').firstMatch(data);
        if (nums != null) cores = int.tryParse(nums.group(1)!);
      }
    } catch (_) {}

    cores ??= Platform.numberOfProcessors;
    ramMb ??= (w.systemMemoryInMegabytes > 0) ? w.systemMemoryInMegabytes : null;

    return DeviceSpecs(
      platform: 'Windows',
      model: w.productName,
      manufacturer: w.registeredOwner,
      osVersion:
          'Windows ${w.displayVersion.isNotEmpty ? w.displayVersion : w.releaseId} (Build ${w.buildNumber})',
      totalRamMb: ramMb,
      cpuCores: cores,
      cpuInfo: cpuName,
      deviceId: w.deviceId,
      extra: {
        'اسم الحاسبة': w.computerName,
        'المعالجات المنطقية': '${w.numberOfCores}',
        if (cpuName.isNotEmpty) 'المعالج': cpuName,
      },
    );
  }
}
