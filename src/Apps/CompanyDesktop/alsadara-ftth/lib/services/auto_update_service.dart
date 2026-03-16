/// خدمة التحديث التلقائي للتطبيق
/// تتحقق من وجود تحديثات جديدة على GitHub وتقوم بتحميلها وتثبيتها تلقائياً
/// يدعم Windows (EXE/MSIX) و Android (APK)
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// معلومات التحديث
class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final String publishedAt;
  final int downloadSize;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
    this.downloadSize = 0,
  });

  factory UpdateInfo.fromGitHubRelease(Map<String, dynamic> json) {
    String downloadUrl = '';
    int downloadSize = 0;

    final assets = json['assets'] as List<dynamic>? ?? [];

    if (Platform.isAndroid) {
      // === Android: البحث عن ملف APK ===
      for (var asset in assets) {
        final name = asset['name']?.toString().toLowerCase() ?? '';
        if (name.endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] ?? '';
          downloadSize = asset['size'] ?? 0;
          break;
        }
      }
    } else {
      // === Windows: الأولوية: Setup.exe → أي .exe → .zip ===

      // المرحلة 1: البحث عن ملف Setup.exe (المثبّت)
      for (var asset in assets) {
        final name = asset['name']?.toString().toLowerCase() ?? '';
        if (name.contains('setup') && name.endsWith('.exe')) {
          downloadUrl = asset['browser_download_url'] ?? '';
          downloadSize = asset['size'] ?? 0;
          break;
        }
      }

      // المرحلة 2: إذا لم نجد Setup، نبحث عن أي .exe
      if (downloadUrl.isEmpty) {
        for (var asset in assets) {
          final name = asset['name']?.toString().toLowerCase() ?? '';
          if (name.endsWith('.exe')) {
            downloadUrl = asset['browser_download_url'] ?? '';
            downloadSize = asset['size'] ?? 0;
            break;
          }
        }
      }

      // المرحلة 3: zip كخيار أخير
      if (downloadUrl.isEmpty) {
        for (var asset in assets) {
          final name = asset['name']?.toString().toLowerCase() ?? '';
          if (name.endsWith('.zip')) {
            downloadUrl = asset['browser_download_url'] ?? '';
            downloadSize = asset['size'] ?? 0;
            break;
          }
        }
      }
    }

    return UpdateInfo(
      version: (json['tag_name'] ?? '').toString().replaceAll('v', ''),
      downloadUrl: downloadUrl,
      releaseNotes: json['body'] ?? 'لا توجد ملاحظات',
      publishedAt: json['published_at'] ?? '',
      downloadSize: downloadSize,
    );
  }
}

/// خدمة التحديث التلقائي
class AutoUpdateService {
  // إعدادات مستودع GitHub
  static const String githubOwner = '07706228120Hh';
  static const String githubRepo = 'alsadara-FTTH';
  static const String githubApiUrl =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  static AutoUpdateService? _instance;
  static AutoUpdateService get instance => _instance ??= AutoUpdateService._();

  AutoUpdateService._();

  // مفاتيح SharedPreferences لآلية snooze
  static const String _snoozeVersionKey = 'update_snooze_version';
  static const String _snoozeTimeKey = 'update_snooze_time';
  // 2 ساعة كحد أدنى بين كل محاولة للإصدار نفسه
  static const Duration _snoozeDuration = Duration(hours: 2);

  /// تسجيل بدء محاولة تثبيت إصدار معين (لمنع الحلقة)
  Future<void> markUpdateAttempted(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_snoozeVersionKey, version);
      await prefs.setString(_snoozeTimeKey, DateTime.now().toIso8601String());
      debugPrint('⏳ [AutoUpdate] تم تسجيل محاولة تثبيت: $version');
    } catch (_) {}
  }

  /// تخطي التحديث الحالي يدوياً (لمدة أطول)
  Future<void> snoozeUpdate(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_snoozeVersionKey, version);
      // تخطي يدوي = 24 ساعة
      await prefs.setString(
          _snoozeTimeKey,
          DateTime.now()
              .subtract(const Duration(hours: 22)) // يُغطي 24 - 2 = 22 ساعة
              .add(const Duration(hours: 24))
              .toIso8601String());
      debugPrint('⏸️ [AutoUpdate] تم تخطي الإصدار $version لمدة 24 ساعة');
    } catch (_) {}
  }

  /// هل يجب تخطي عرض التحديث الآن؟
  Future<bool> _isSnoozed(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final snoozeVersion = prefs.getString(_snoozeVersionKey);
      if (snoozeVersion != version) return false;
      final snoozeTimeStr = prefs.getString(_snoozeTimeKey);
      if (snoozeTimeStr == null) return false;
      final snoozeTime = DateTime.tryParse(snoozeTimeStr);
      if (snoozeTime == null) return false;
      return DateTime.now().isBefore(snoozeTime.add(_snoozeDuration));
    } catch (_) {
      return false;
    }
  }

  /// التحقق من وجود تحديث جديد
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse(githubApiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final updateInfo = UpdateInfo.fromGitHubRelease(data);

        // مقارنة الإصدارات
        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;

        if (_isNewerVersion(updateInfo.version, currentVersion)) {
          // تحقق إذا كان هذا الإصدار في فترة التخطي
          if (await _isSnoozed(updateInfo.version)) {
            debugPrint(
                '⏸️ [AutoUpdate] الإصدار ${updateInfo.version} في فترة snooze — تم التخطي');
            return null;
          }
          return updateInfo;
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من التحديثات');
    }
    return null;
  }

  /// مقارنة الإصدارات
  bool _isNewerVersion(String newVersion, String currentVersion) {
    try {
      final newParts = newVersion.split('.').map(int.parse).toList();
      final currentParts = currentVersion.split('.').map(int.parse).toList();

      // التأكد من أن كلا القائمتين بنفس الطول
      while (newParts.length < 3) newParts.add(0);
      while (currentParts.length < 3) currentParts.add(0);

      for (int i = 0; i < 3; i++) {
        if (newParts[i] > currentParts[i]) return true;
        if (newParts[i] < currentParts[i]) return false;
      }
    } catch (e) {
      debugPrint('❌ خطأ في مقارنة الإصدارات');
    }
    return false;
  }

  /// تحميل التحديث
  Future<String?> downloadUpdate(
    UpdateInfo updateInfo, {
    Function(double)? onProgress,
  }) async {
    try {
      // على Android نستخدم مجلد التخزين الخارجي لأن FileProvider يحتاج الوصول
      final Directory downloadDir;
      if (Platform.isAndroid) {
        // استخدام مجلد cache الخارجي المتاح لـ FileProvider
        final extDirs = await getExternalCacheDirectories();
        downloadDir = (extDirs != null && extDirs.isNotEmpty)
            ? extDirs.first
            : await getTemporaryDirectory();
      } else {
        downloadDir = await getTemporaryDirectory();
      }

      final fileName = updateInfo.downloadUrl.split('/').last;
      final sep = Platform.pathSeparator;
      final filePath = '${downloadDir.path}$sep$fileName';

      // تحقق إذا كان الملف محمّل مسبقاً بنفس الحجم
      final existingFile = File(filePath);
      if (existingFile.existsSync() && updateInfo.downloadSize > 0) {
        final existingSize = existingFile.lengthSync();
        if (existingSize == updateInfo.downloadSize) {
          debugPrint('✅ الملف محمّل مسبقاً: $filePath');
          onProgress?.call(1.0);
          return filePath;
        }
      }

      final request = http.Request('GET', Uri.parse(updateInfo.downloadUrl));
      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        final contentLength = response.contentLength ?? updateInfo.downloadSize;
        final file = File(filePath);
        final sink = file.openWrite();

        int downloaded = 0;
        await for (var chunk in response.stream) {
          sink.add(chunk);
          downloaded += chunk.length;

          if (onProgress != null && contentLength > 0) {
            onProgress(downloaded / contentLength);
          }
        }

        await sink.close();
        debugPrint(
            '✅ تم تحميل التحديث: $filePath (${file.lengthSync()} bytes)');
        return filePath;
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل التحديث');
    }
    return null;
  }

  /// تثبيت التحديث
  /// Windows: المثبت الصامت (EXE/MSIX)
  /// Android: فتح ملف APK بمثبّت النظام
  Future<bool> installUpdate(String filePath) async {
    try {
      if (filePath.endsWith('.apk')) {
        // === Android: فتح APK بمثبّت النظام ===
        debugPrint('📱 تثبيت APK: $filePath');
        final result = await OpenFile.open(filePath);
        debugPrint('📱 نتيجة فتح APK: ${result.type} - ${result.message}');
        // ResultType.done = تم فتح الملف بنجاح (يظهر مثبّت Android)
        return result.type == ResultType.done;
      } else if (filePath.endsWith('.exe')) {
        // === Windows: تشغيل المثبّت بالوضع الصامت ===
        // استخراج الإصدار من اسم الملف (مثل: Alsadara_v1.6.5_Setup.exe → 1.6.5)
        final versionMatch =
            RegExp(r'v(\d+\.\d+\.\d+)').firstMatch(filePath.split(r'\').last);
        if (versionMatch != null) {
          await markUpdateAttempted(versionMatch.group(1)!);
        }
        await Process.start(filePath, [
          '/SILENT',
          '/CLOSEAPPLICATIONS',
          '/RESTARTAPPLICATIONS',
          '/NOCANCEL',
          '/SP-',
        ]);
        exit(0);
      } else if (filePath.endsWith('.msix')) {
        await Process.start('powershell', [
          '-Command',
          'Add-AppxPackage',
          '-Path',
          filePath,
        ]);
        exit(0);
      }
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في تثبيت التحديث');
    }
    return false;
  }

  /// الحصول على الإصدار الحالي
  Future<String> getCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      return '1.0.0';
    }
  }
}
