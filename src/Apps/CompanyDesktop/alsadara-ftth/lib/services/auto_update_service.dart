/// خدمة التحديث التلقائي للتطبيق
/// تتحقق من وجود تحديثات جديدة على GitHub وتقوم بتحميلها وتثبيتها
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
    // البحث عن ملف exe أو zip في الأصول
    String downloadUrl = '';
    int downloadSize = 0;

    final assets = json['assets'] as List<dynamic>? ?? [];
    for (var asset in assets) {
      final name = asset['name']?.toString().toLowerCase() ?? '';
      if (name.endsWith('.exe') ||
          name.endsWith('.zip') ||
          name.endsWith('.msix')) {
        downloadUrl = asset['browser_download_url'] ?? '';
        downloadSize = asset['size'] ?? 0;
        break;
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
          return updateInfo;
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من التحديثات: $e');
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
      debugPrint('❌ خطأ في مقارنة الإصدارات: $e');
    }
    return false;
  }

  /// تحميل التحديث
  Future<String?> downloadUpdate(
    UpdateInfo updateInfo, {
    Function(double)? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = updateInfo.downloadUrl.split('/').last;
      final filePath = '${tempDir.path}\\$fileName';

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
        return filePath;
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل التحديث: $e');
    }
    return null;
  }

  /// تثبيت التحديث
  Future<bool> installUpdate(String filePath) async {
    try {
      if (filePath.endsWith('.exe')) {
        // تشغيل ملف المثبت
        await Process.start(filePath, ['/SILENT', '/CLOSEAPPLICATIONS']);
        // إغلاق التطبيق الحالي للسماح بالتحديث
        exit(0);
      } else if (filePath.endsWith('.zip')) {
        // فك الضغط واستبدال الملفات
        // يمكن إضافة منطق فك الضغط هنا
        debugPrint('📦 فك ضغط التحديث من: $filePath');
      } else if (filePath.endsWith('.msix')) {
        // تثبيت حزمة MSIX
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
      debugPrint('❌ خطأ في تثبيت التحديث: $e');
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
