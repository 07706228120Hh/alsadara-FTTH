/// خدمة التحديث التلقائي للتطبيق
/// تتحقق من وجود تحديثات جديدة على GitHub وتقوم بتحميلها وتثبيتها تلقائياً
/// يدعم Windows (EXE/MSIX) و Android (APK)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تصنيف سبب فشل فحص التحديث — كي تُظهر الواجهة رسالة دقيقة بدل
/// «لا يوجد اتصال بالإنترنت» العامة المضلِّلة.
enum UpdateCheckErrorKind {
  /// لا اتصال فعلي بالشبكة (SocketException / مهلة).
  network,

  /// تجاوز حدّ معدّل GitHub (403/429) — شائع على شبكة مكتب بـ IP مشترك.
  rateLimited,

  /// تعذّر الوصول لخادم التحديث تحديداً (حجب/TLS/شهادة) رغم وجود إنترنت.
  blocked,

  /// الخادم ردّ بخطأ (5xx أو رد غير متوقع).
  server,

  /// سبب غير معروف.
  unknown,
}

/// استثناء فحص التحديث يحمل التصنيف + رسالة عربية جاهزة للعرض.
class UpdateCheckException implements Exception {
  final UpdateCheckErrorKind kind;
  final String technical;
  UpdateCheckException(this.kind, [this.technical = '']);

  /// رسالة عربية مناسبة للمستخدم حسب نوع الخطأ.
  String get userMessage {
    switch (kind) {
      case UpdateCheckErrorKind.network:
        return 'تعذّر التحقق من التحديثات — تأكد من اتصال الإنترنت';
      case UpdateCheckErrorKind.rateLimited:
        return 'تم تجاوز حدّ فحص التحديثات مؤقتاً على هذه الشبكة.\n'
            'التطبيق سيُحدَّث تلقائياً لاحقاً — أو حاول بعد قليل.';
      case UpdateCheckErrorKind.blocked:
        return 'تعذّر الوصول إلى خادم التحديثات (قد يكون محجوباً على هذه الشبكة).';
      case UpdateCheckErrorKind.server:
        return 'خادم التحديثات لا يستجيب حالياً — حاول لاحقاً.';
      case UpdateCheckErrorKind.unknown:
        return 'تعذّر التحقق من التحديثات — حاول لاحقاً.';
    }
  }

  @override
  String toString() => 'UpdateCheckException($kind): $technical';
}

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
    final assets = (json['assets'] as List<dynamic>? ?? [])
        .map((a) => (
              name: (a['name']?.toString() ?? ''),
              url: (a['browser_download_url']?.toString() ?? ''),
              size: (a['size'] is int ? a['size'] as int : 0),
            ))
        .where((a) => a.url.isNotEmpty)
        .toList();

    final selected = selectAsset(assets);

    return UpdateInfo(
      version: (json['tag_name'] ?? '').toString().replaceAll('v', ''),
      downloadUrl: selected?.url ?? '',
      releaseNotes: json['body'] ?? 'لا توجد ملاحظات',
      publishedAt: json['published_at'] ?? '',
      downloadSize: selected?.size ?? 0,
    );
  }

  /// بناء من بيانات صفحة إصدارات GitHub (مسار fallback بلا حدّ معدّل).
  /// الحجم غير معروف من HTML (0) — كود التحميل يعتمد `contentLength` من الرد.
  factory UpdateInfo.fromHtmlAssets({
    required String version,
    required List<String> downloadUrls,
  }) {
    final assets = downloadUrls
        .map((u) => (name: u.split('/').last, url: u, size: 0))
        .toList();
    final selected = selectAsset(assets);
    return UpdateInfo(
      version: version.replaceAll('v', ''),
      downloadUrl: selected?.url ?? '',
      releaseNotes: 'لا توجد ملاحظات',
      publishedAt: '',
      downloadSize: 0,
    );
  }

  /// اختيار الأصل المناسب للمنصّة الحالية بأولوية:
  /// Android: `.apk` · Windows: Setup.exe → أي .exe → .zip.
  static ({String name, String url, int size})? selectAsset(
      List<({String name, String url, int size})> assets) {
    bool ok(({String name, String url, int size}) a, bool Function(String) f) =>
        f(a.name.toLowerCase());

    if (Platform.isAndroid) {
      for (final a in assets) {
        if (ok(a, (n) => n.endsWith('.apk'))) return a;
      }
      return null;
    }
    // Windows (وغيره): Setup.exe أولاً
    for (final a in assets) {
      if (ok(a, (n) => n.contains('setup') && n.endsWith('.exe'))) return a;
    }
    for (final a in assets) {
      if (ok(a, (n) => n.endsWith('.exe'))) return a;
    }
    for (final a in assets) {
      if (ok(a, (n) => n.endsWith('.zip'))) return a;
    }
    return null;
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

  // GitHub يتطلب User-Agent وإلا ردّ 403؛ وبعض الشبكات بطيئة ⇒ مهلة صريحة.
  static const String _userAgent = 'Alsadara-FTTH-Updater';
  static const Duration _httpTimeout = Duration(seconds: 20);
  static const Map<String, String> _apiHeaders = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': _userAgent,
    'X-GitHub-Api-Version': '2022-11-28',
  };

  /// صفحة «آخر إصدار» على github.com (ليست API ⇒ بلا حدّ 60/ساعة).
  static const String _releasesLatestUrl =
      'https://github.com/$githubOwner/$githubRepo/releases/latest';

  /// التحقق من وجود تحديث جديد (تلقائي عند بدء التطبيق).
  /// يبتلع الأخطاء بصمت (يرجع null) لأنه خلفي؛ التشخيص عبر debugPrint فقط.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final updateInfo = await _resolveLatest();
      final packageInfo = await PackageInfo.fromPlatform();
      if (_isNewerVersion(updateInfo.version, packageInfo.version)) {
        if (await _isSnoozed(updateInfo.version)) {
          debugPrint(
              '⏸️ [AutoUpdate] الإصدار ${updateInfo.version} في فترة snooze — تم التخطي');
          return null;
        }
        return updateInfo;
      }
    } on UpdateCheckException catch (e) {
      debugPrint('❌ [AutoUpdate] تعذّر الفحص التلقائي: $e');
    } catch (e) {
      debugPrint('❌ [AutoUpdate] خطأ غير متوقع في الفحص التلقائي: $e');
    }
    return null;
  }

  /// فحص يدوي للتحديثات (زر «التحقق من التحديثات» في شاشة الدخول).
  ///
  /// يختلف عن [checkForUpdate] التلقائي في أنه:
  ///   * يتجاوز آلية snooze (المستخدم طلب الفحص صراحةً).
  ///   * يرمي [UpdateCheckException] مصنَّفاً عند الفشل بدل ابتلاعه، كي تعرض
  ///     الواجهة سبباً دقيقاً (حدّ معدّل / حجب / لا إنترنت) لا رسالة عامة.
  ///
  /// يرجع [UpdateInfo] إن توفّر إصدار أحدث، أو null إن كان المستخدم على الأحدث.
  Future<UpdateInfo?> checkForUpdateManual() async {
    final updateInfo = await _resolveLatest();
    final packageInfo = await PackageInfo.fromPlatform();
    if (_isNewerVersion(updateInfo.version, packageInfo.version)) {
      return updateInfo;
    }
    return null;
  }

  /// يحاول عبر GitHub API أولاً؛ وعند حدّ المعدّل (403/429) أو فشل الوصول
  /// للـ API يسقط تلقائياً إلى صفحة github.com (بلا حدّ معدّل).
  /// يرمي [UpdateCheckException] مصنَّفاً إن فشل المساران.
  Future<UpdateInfo> _resolveLatest() async {
    try {
      return await _fetchViaApi();
    } on UpdateCheckException catch (apiErr) {
      // الـ fallback مفيد لحدّ المعدّل أو خطأ الخادم أو حجب api.github.com.
      // لا فائدة منه عند خطأ تنسيق فقط، لكن المحاولة آمنة.
      debugPrint('ℹ️ [AutoUpdate] API فشل (${apiErr.kind}) — fallback إلى github.com');
      try {
        return await _fetchViaHtml();
      } on UpdateCheckException catch (htmlErr) {
        // إن كان الفشل الثاني شبكياً، أعطِ الأولوية لتصنيف API الأدق.
        if (htmlErr.kind == UpdateCheckErrorKind.network &&
            apiErr.kind != UpdateCheckErrorKind.network) {
          throw apiErr;
        }
        rethrow;
      }
    }
  }

  /// المسار الأساسي: GitHub REST API.
  Future<UpdateInfo> _fetchViaApi() async {
    final http.Response response;
    try {
      response = await http
          .get(Uri.parse(githubApiUrl), headers: _apiHeaders)
          .timeout(_httpTimeout);
    } catch (e) {
      throw _classifyNetworkError(e);
    }

    if (response.statusCode == 200) {
      try {
        return UpdateInfo.fromGitHubRelease(json.decode(response.body));
      } catch (e) {
        throw UpdateCheckException(
            UpdateCheckErrorKind.server, 'bad JSON: $e');
      }
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      // حدّ معدّل GitHub (شائع على IP مكتب مشترك).
      throw UpdateCheckException(
          UpdateCheckErrorKind.rateLimited, 'API ${response.statusCode}');
    }
    if (response.statusCode >= 500) {
      throw UpdateCheckException(
          UpdateCheckErrorKind.server, 'API ${response.statusCode}');
    }
    throw UpdateCheckException(
        UpdateCheckErrorKind.unknown, 'API ${response.statusCode}');
  }

  /// مسار احتياطي بلا حدّ معدّل: نقرأ وسم الإصدار من إعادة توجيه
  /// `releases/latest` ثم روابط الأصول من `expanded_assets/<tag>`.
  Future<UpdateInfo> _fetchViaHtml() async {
    final client = http.Client();
    try {
      // 1) حلّ الوسم عبر إعادة التوجيه (بلا متابعة) → Location: .../tag/vX.Y.Z
      String? tag;
      try {
        final req = http.Request('GET', Uri.parse(_releasesLatestUrl))
          ..followRedirects = false
          ..headers['User-Agent'] = _userAgent;
        final resp = await client.send(req).timeout(_httpTimeout);
        final location = resp.headers['location'];
        await resp.stream.drain<void>(); // تحرير الاتصال
        if (location != null) {
          tag = RegExp(r'/tag/([^/?#]+)').firstMatch(location)?.group(1);
        }
      } catch (e) {
        throw _classifyNetworkError(e);
      }
      if (tag == null || tag.isEmpty) {
        throw UpdateCheckException(
            UpdateCheckErrorKind.server, 'no tag in redirect');
      }

      // 2) روابط التحميل من جزء الأصول الموسّع.
      final assetsUrl =
          'https://github.com/$githubOwner/$githubRepo/releases/expanded_assets/$tag';
      final http.Response assetsResp;
      try {
        assetsResp = await http.get(Uri.parse(assetsUrl),
            headers: {'User-Agent': _userAgent}).timeout(_httpTimeout);
      } catch (e) {
        throw _classifyNetworkError(e);
      }
      if (assetsResp.statusCode != 200) {
        throw UpdateCheckException(
            UpdateCheckErrorKind.server, 'assets ${assetsResp.statusCode}');
      }

      final links = RegExp(r'href="(/[^"]+/releases/download/[^"]+)"')
          .allMatches(assetsResp.body)
          .map((m) => 'https://github.com${m.group(1)}')
          .toSet()
          .toList();

      final info =
          UpdateInfo.fromHtmlAssets(version: tag, downloadUrls: links);
      if (info.downloadUrl.isEmpty) {
        throw UpdateCheckException(
            UpdateCheckErrorKind.server, 'no matching asset for platform');
      }
      return info;
    } finally {
      client.close();
    }
  }

  /// تحويل خطأ شبكة خام إلى تصنيف مفهوم للمستخدم.
  UpdateCheckException _classifyNetworkError(Object e) {
    if (e is UpdateCheckException) return e;
    if (e is TimeoutException) {
      return UpdateCheckException(UpdateCheckErrorKind.network, 'timeout');
    }
    if (e is SocketException) {
      // فشل DNS/الاتصال: لا شبكة أو الخادم محجوب على هذه الشبكة.
      return UpdateCheckException(UpdateCheckErrorKind.network, 'socket: ${e.osError?.message ?? e.message}');
    }
    if (e is HandshakeException || e is TlsException) {
      // فشل TLS (شهادة/بروتوكول) على ويندوز قديم ⇒ وصول محجوب عملياً.
      return UpdateCheckException(UpdateCheckErrorKind.blocked, 'tls: $e');
    }
    if (e is HttpException) {
      return UpdateCheckException(UpdateCheckErrorKind.blocked, 'http: $e');
    }
    return UpdateCheckException(UpdateCheckErrorKind.unknown, e.toString());
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
      if (existingFile.existsSync()) {
        if (updateInfo.downloadSize > 0) {
          final existingSize = existingFile.lengthSync();
          if (existingSize == updateInfo.downloadSize) {
            debugPrint('✅ الملف محمّل مسبقاً: $filePath');
            onProgress?.call(1.0);
            return filePath;
          }
        }
        // حذف الملف القديم إذا كان الحجم مختلف (ملف تالف أو إصدار قديم)
        existingFile.deleteSync();
        debugPrint('🗑️ حذف ملف قديم بحجم مختلف: $filePath');
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
        // === Android: تثبيت APK عبر Native Intent ===
        debugPrint('📱 تثبيت APK: $filePath');

        // حفظ مسار APK لإعادة التثبيت بعد الحذف
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_apk_path', filePath);

        // الطريقة 1: Native MethodChannel (FileProvider + Intent)
        try {
          const channel = MethodChannel('com.alsadara/installer');
          final result = await channel.invokeMethod('installApk', {'filePath': filePath});
          if (result == true) return true;
        } catch (e) {
          debugPrint('📱 Native installer failed: $e');
        }

        // الطريقة 2: Fallback — OpenFilex
        try {
          final result = await OpenFilex.open(filePath, type: 'application/vnd.android.package-archive');
          debugPrint('📱 OpenFilex: ${result.type} - ${result.message}');
          return result.type == ResultType.done;
        } catch (e) {
          debugPrint('📱 OpenFilex failed: $e');
        }
        return false;
      } else if (filePath.endsWith('.exe')) {
        // === Windows: تشغيل المثبّت بالوضع الصامت ===
        // استخراج الإصدار من اسم الملف (مثل: Alsadara_v1.6.5_Setup.exe → 1.6.5)
        final versionMatch =
            RegExp(r'v(\d+\.\d+\.\d+)').firstMatch(filePath.split(r'\').last);
        if (versionMatch != null) {
          await markUpdateAttempted(versionMatch.group(1)!);
        }

        // إزالة حظر SmartScreen (Zone Identifier) عن الملف المحمّل
        try {
          await Process.run('powershell', [
            '-Command',
            'Unblock-File',
            '-Path',
            '"$filePath"',
          ]);
          debugPrint('🔓 [AutoUpdate] تم إلغاء حظر SmartScreen');
        } catch (_) {
          debugPrint('⚠️ [AutoUpdate] تعذر إلغاء حظر SmartScreen');
        }

        // تحديد مسار التطبيق الحالي لتثبيت التحديث في نفس المكان
        final currentExeDir = File(Platform.resolvedExecutable).parent.path;
        debugPrint('📂 [AutoUpdate] مسار التثبيت: $currentExeDir');

        await Process.start(filePath, [
          '/SILENT',
          '/FORCECLOSEAPPLICATIONS',
          '/RESTARTAPPLICATIONS',
          '/NOCANCEL',
          '/SP-',
          '/DIR=$currentExeDir',
          '/TASKS=desktopicon',
        ]);
        // تأخير قصير للسماح للمثبّت بالبدء قبل إغلاق التطبيق
        await Future.delayed(const Duration(seconds: 2));
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

  /// فتح شاشة حذف التطبيق — عند فشل التحديث بسبب اختلاف التوقيع
  Future<bool> requestUninstall() async {
    try {
      if (!Platform.isAndroid) return false;
      const channel = MethodChannel('com.alsadara/installer');
      final result = await channel.invokeMethod('uninstallApp');
      return result == true;
    } catch (e) {
      debugPrint('📱 Uninstall request failed: $e');
      return false;
    }
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
