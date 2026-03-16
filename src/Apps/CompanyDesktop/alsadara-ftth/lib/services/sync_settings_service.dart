import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// إعدادات نوع واحد من الجلب
class FetchSettings {
  int pageSize;
  int parallelPages;

  FetchSettings({
    required this.pageSize,
    required this.parallelPages,
  });

  Map<String, dynamic> toJson() => {
        'pageSize': pageSize,
        'parallelPages': parallelPages,
      };

  factory FetchSettings.fromJson(Map<String, dynamic> json) {
    return FetchSettings(
      pageSize: json['pageSize'] ?? SyncSettingsService.defaultPageSize,
      parallelPages:
          json['parallelPages'] ?? SyncSettingsService.defaultParallelPages,
    );
  }

  FetchSettings copyWith({int? pageSize, int? parallelPages}) {
    return FetchSettings(
      pageSize: pageSize ?? this.pageSize,
      parallelPages: parallelPages ?? this.parallelPages,
    );
  }
}

/// خدمة إعدادات المزامنة - منفصلة لكل نوع
class SyncSettingsService {
  static final SyncSettingsService instance = SyncSettingsService._internal();
  factory SyncSettingsService() => instance;
  SyncSettingsService._internal() {
    // تهيئة القيم الافتراضية مباشرة
    _subscriptionsSettings = FetchSettings(
      pageSize: defaultPageSize,
      parallelPages: defaultParallelPages,
    );
    _usersSettings = FetchSettings(
      pageSize: defaultPageSize,
      parallelPages: defaultParallelPages,
    );
    _addressesSettings = FetchSettings(
      pageSize: defaultPageSize,
      parallelPages: defaultParallelPages,
    );
    // تحميل الإعدادات من الملف فور الإنشاء
    _loadSettingsSync();
  }

  /// تحميل الإعدادات بشكل متزامن (للمُنشئ)
  void _loadSettingsSync() {
    try {
      final homeDir = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
      if (homeDir.isEmpty) return;

      final settingsPath =
          '$homeDir/Documents/alsadara_local_db/sync_settings.json';
      final file = File(settingsPath);

      if (file.existsSync()) {
        final content = file.readAsStringSync();
        final data = json.decode(content);

        if (data['subscriptions'] != null) {
          _subscriptionsSettings =
              FetchSettings.fromJson(data['subscriptions']);
        }
        if (data['users'] != null) {
          _usersSettings = FetchSettings.fromJson(data['users']);
        }
        if (data['addresses'] != null) {
          _addressesSettings = FetchSettings.fromJson(data['addresses']);
        }

        _validateSettings();
        print(
            '⚙️ تم تحميل الإعدادات: اشتراكات=${_subscriptionsSettings.pageSize}/${_subscriptionsSettings.parallelPages}');
      }
    } catch (e) {
      print('⚠️ خطأ في تحميل الإعدادات المتزامن');
    }
  }

  // القيم الافتراضية
  static const int defaultPageSize = 150; // 150 IDs في كل طلب
  static const int defaultParallelPages =
      10; // 10 طلبات متوازية = 1500 سجل/دفعة

  // الحدود
  static const int minPageSize = 10;
  static const int maxPageSize = 200;
  static const int minParallelPages = 1;
  static const int maxParallelPages = 500; // زيادة الحد لجلب الهواتف

  // إعدادات كل نوع
  late FetchSettings _subscriptionsSettings;
  late FetchSettings _usersSettings;
  late FetchSettings _addressesSettings;

  bool _initialized = false;
  File? _settingsFile;

  /// إعدادات الاشتراكات
  FetchSettings get subscriptionsSettings => _subscriptionsSettings;

  /// إعدادات المشتركين
  FetchSettings get usersSettings => _usersSettings;

  /// إعدادات معلومات المشترك (العناوين)
  FetchSettings get addressesSettings => _addressesSettings;

  // للتوافق مع الكود القديم
  int get pageSize => _subscriptionsSettings.pageSize;
  int get parallelPages => _subscriptionsSettings.parallelPages;

  /// تهيئة الخدمة (تحميل من الملف)
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbDir = Directory('${documentsDir.path}/alsadara_local_db');

      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }

      _settingsFile = File('${dbDir.path}/sync_settings.json');

      if (await _settingsFile!.exists()) {
        final content = await _settingsFile!.readAsString();
        final data = json.decode(content);

        // تحميل إعدادات الاشتراكات
        if (data['subscriptions'] != null) {
          _subscriptionsSettings =
              FetchSettings.fromJson(data['subscriptions']);
        } else if (data['pageSize'] != null) {
          // التوافق مع الإعدادات القديمة
          _subscriptionsSettings = FetchSettings(
            pageSize: data['pageSize'] ?? defaultPageSize,
            parallelPages: data['parallelPages'] ?? defaultParallelPages,
          );
        }

        // تحميل إعدادات المشتركين
        if (data['users'] != null) {
          _usersSettings = FetchSettings.fromJson(data['users']);
        }

        // تحميل إعدادات العناوين
        if (data['addresses'] != null) {
          _addressesSettings = FetchSettings.fromJson(data['addresses']);
        }

        // التأكد من الحدود
        _validateSettings();
      }

      _initialized = true;
      print('⚙️ تم تحميل الإعدادات:');
      print(
          '   📋 الاشتراكات: ${_subscriptionsSettings.pageSize}/صفحة، ${_subscriptionsSettings.parallelPages} متوازي');
      print(
          '   👥 المشتركين: ${_usersSettings.pageSize}/صفحة، ${_usersSettings.parallelPages} متوازي');
      print(
          '   📍 العناوين: ${_addressesSettings.pageSize}/صفحة، ${_addressesSettings.parallelPages} متوازي');
    } catch (e) {
      print('⚠️ خطأ في تحميل الإعدادات');
      _initialized = true;
    }
  }

  /// التحقق من الحدود
  void _validateSettings() {
    _subscriptionsSettings = FetchSettings(
      pageSize: _subscriptionsSettings.pageSize.clamp(minPageSize, maxPageSize),
      parallelPages: _subscriptionsSettings.parallelPages
          .clamp(minParallelPages, maxParallelPages),
    );
    _usersSettings = FetchSettings(
      pageSize: _usersSettings.pageSize.clamp(minPageSize, maxPageSize),
      parallelPages: _usersSettings.parallelPages
          .clamp(minParallelPages, maxParallelPages),
    );
    _addressesSettings = FetchSettings(
      pageSize: _addressesSettings.pageSize.clamp(minPageSize, maxPageSize),
      parallelPages: _addressesSettings.parallelPages
          .clamp(minParallelPages, maxParallelPages),
    );
  }

  /// حفظ الإعدادات
  Future<void> _saveSettings() async {
    if (_settingsFile == null) return;

    try {
      final data = {
        'subscriptions': _subscriptionsSettings.toJson(),
        'users': _usersSettings.toJson(),
        'addresses': _addressesSettings.toJson(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await _settingsFile!.writeAsString(json.encode(data));
      print('💾 تم حفظ الإعدادات');
    } catch (e) {
      print('⚠️ خطأ في حفظ الإعدادات');
    }
  }

  /// تحديث إعدادات الاشتراكات
  Future<void> updateSubscriptionsSettings({
    int? pageSize,
    int? parallelPages,
  }) async {
    if (!_initialized) await initialize();

    _subscriptionsSettings = FetchSettings(
      pageSize: (pageSize ?? _subscriptionsSettings.pageSize)
          .clamp(minPageSize, maxPageSize),
      parallelPages: (parallelPages ?? _subscriptionsSettings.parallelPages)
          .clamp(minParallelPages, maxParallelPages),
    );

    await _saveSettings();
  }

  /// تحديث إعدادات المشتركين
  Future<void> updateUsersSettings({
    int? pageSize,
    int? parallelPages,
  }) async {
    if (!_initialized) await initialize();

    _usersSettings = FetchSettings(
      pageSize:
          (pageSize ?? _usersSettings.pageSize).clamp(minPageSize, maxPageSize),
      parallelPages: (parallelPages ?? _usersSettings.parallelPages)
          .clamp(minParallelPages, maxParallelPages),
    );

    await _saveSettings();
  }

  /// تحديث إعدادات العناوين
  Future<void> updateAddressesSettings({
    int? pageSize,
    int? parallelPages,
  }) async {
    if (!_initialized) await initialize();

    _addressesSettings = FetchSettings(
      pageSize: (pageSize ?? _addressesSettings.pageSize)
          .clamp(minPageSize, maxPageSize),
      parallelPages: (parallelPages ?? _addressesSettings.parallelPages)
          .clamp(minParallelPages, maxParallelPages),
    );

    await _saveSettings();
  }

  /// تحديث جميع الإعدادات (للتوافق مع الكود القديم)
  Future<void> updateSettings({int? pageSize, int? parallelPages}) async {
    await updateSubscriptionsSettings(
        pageSize: pageSize, parallelPages: parallelPages);
  }

  /// إعادة الإعدادات للقيم الافتراضية
  Future<void> resetToDefaults() async {
    _subscriptionsSettings = FetchSettings(
      pageSize: defaultPageSize,
      parallelPages: defaultParallelPages,
    );
    _usersSettings = FetchSettings(
      pageSize: defaultPageSize,
      parallelPages: defaultParallelPages,
    );
    _addressesSettings = FetchSettings(
      pageSize: defaultPageSize,
      parallelPages: defaultParallelPages,
    );
    await _saveSettings();
  }
}
