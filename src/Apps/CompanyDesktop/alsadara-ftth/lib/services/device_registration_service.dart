/// خدمة تسجيل الأجهزة المعتمدة
/// تدير صلاحيات الأجهزة للتخزين المحلي
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'custom_auth_service.dart';

/// معلومات الجهاز المسجل
class RegisteredDevice {
  final String deviceId;
  final String deviceName;
  final String platform;
  final String registeredBy;
  final String registeredByName;
  final DateTime registeredAt;
  final DateTime? lastUsed;
  final bool isActive;

  RegisteredDevice({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.registeredBy,
    required this.registeredByName,
    required this.registeredAt,
    this.lastUsed,
    this.isActive = true,
  });

  factory RegisteredDevice.fromMap(Map<String, dynamic> data, String id) {
    return RegisteredDevice(
      deviceId: id,
      deviceName: data['deviceName'] ?? 'جهاز غير معروف',
      platform: data['platform'] ?? 'unknown',
      registeredBy: data['registeredBy'] ?? '',
      registeredByName: data['registeredByName'] ?? '',
      registeredAt:
          (data['registeredAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastUsed: (data['lastUsed'] as Timestamp?)?.toDate(),
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceName': deviceName,
      'platform': platform,
      'registeredBy': registeredBy,
      'registeredByName': registeredByName,
      'registeredAt': Timestamp.fromDate(registeredAt),
      'lastUsed': lastUsed != null ? Timestamp.fromDate(lastUsed!) : null,
      'isActive': isActive,
    };
  }

  String get platformIcon {
    switch (platform.toLowerCase()) {
      case 'windows':
        return '🖥️';
      case 'android':
        return '📱';
      case 'ios':
        return '📱';
      case 'macos':
        return '💻';
      case 'linux':
        return '🐧';
      default:
        return '💻';
    }
  }

  String get platformName {
    switch (platform.toLowerCase()) {
      case 'windows':
        return 'Windows';
      case 'android':
        return 'Android';
      case 'ios':
        return 'iOS';
      case 'macos':
        return 'macOS';
      case 'linux':
        return 'Linux';
      default:
        return platform;
    }
  }
}

/// كود التفعيل
class ActivationCode {
  final String code;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool used;

  ActivationCode({
    required this.code,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    required this.expiresAt,
    this.used = false,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isValid => !used && !isExpired;

  Duration get remainingTime => expiresAt.difference(DateTime.now());

  factory ActivationCode.fromMap(Map<String, dynamic> data, String code) {
    return ActivationCode(
      code: code,
      createdBy: data['createdBy'] ?? '',
      createdByName: data['createdByName'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      used: data['used'] ?? false,
    );
  }
}

/// خدمة تسجيل الأجهزة
class DeviceRegistrationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // Cache لمعرف الجهاز
  static String? _cachedDeviceId;
  static String? _cachedDeviceName;

  static String? get _currentTenantId => CustomAuthService.currentTenant?.id;

  // المسارات
  static String _devicesPath(String tenantId) =>
      'tenants/$tenantId/settings/approved_devices/devices';

  static String _codesPath(String tenantId) =>
      'tenants/$tenantId/settings/approved_devices/activation_codes';

  // ═══════════════════════════════════════════════════════════
  // معلومات الجهاز الحالي
  // ═══════════════════════════════════════════════════════════

  /// الحصول على معرف فريد للجهاز
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    try {
      if (Platform.isWindows) {
        final info = await _deviceInfo.windowsInfo;
        // deviceId قد يكون null في بعض الأجهزة
        _cachedDeviceId = info.deviceId.isNotEmpty
            ? info.deviceId
            : 'win_${info.computerName}_${DateTime.now().millisecondsSinceEpoch}';
        _cachedDeviceName = info.computerName;
      } else if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        _cachedDeviceId = info.id;
        _cachedDeviceName = '${info.brand} ${info.model}';
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        _cachedDeviceId = info.identifierForVendor ??
            'ios_${DateTime.now().millisecondsSinceEpoch}';
        _cachedDeviceName = info.name;
      } else if (Platform.isMacOS) {
        final info = await _deviceInfo.macOsInfo;
        _cachedDeviceId =
            info.systemGUID ?? 'mac_${DateTime.now().millisecondsSinceEpoch}';
        _cachedDeviceName = info.computerName;
      } else if (Platform.isLinux) {
        final info = await _deviceInfo.linuxInfo;
        _cachedDeviceId =
            info.machineId ?? 'linux_${DateTime.now().millisecondsSinceEpoch}';
        _cachedDeviceName = info.prettyName;
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب معرف الجهاز');
    }

    // إذا فشل، استخدم معرف عشوائي (غير مستحسن)
    _cachedDeviceId ??= 'device_${DateTime.now().millisecondsSinceEpoch}';
    _cachedDeviceName ??= 'جهاز غير معروف';

    return _cachedDeviceId!;
  }

  /// الحصول على اسم الجهاز
  static Future<String> getDeviceName() async {
    if (_cachedDeviceName != null) return _cachedDeviceName!;
    await getDeviceId(); // سيملأ الـ cache
    return _cachedDeviceName ?? 'جهاز غير معروف';
  }

  /// الحصول على نوع المنصة
  static String getPlatform() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  // ═══════════════════════════════════════════════════════════
  // التحقق من صلاحية الجهاز
  // ═══════════════════════════════════════════════════════════

  /// التحقق من أن الجهاز الحالي معتمد
  static Future<bool> isCurrentDeviceApproved({String? tenantId}) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return false;

      final deviceId = await getDeviceId();
      final doc =
          await _firestore.collection(_devicesPath(tid)).doc(deviceId).get();

      if (!doc.exists) return false;

      final data = doc.data();
      return data?['isActive'] == true;
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من صلاحية الجهاز');
      return false;
    }
  }

  /// تحديث آخر استخدام للجهاز
  static Future<void> updateLastUsed({String? tenantId}) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return;

      final deviceId = await getDeviceId();
      final docRef = _firestore.collection(_devicesPath(tid)).doc(deviceId);

      final doc = await docRef.get();
      if (doc.exists && doc.data()?['isActive'] == true) {
        await docRef.update({
          'lastUsed': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في تحديث آخر استخدام');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // إدارة الأجهزة (للمدير)
  // ═══════════════════════════════════════════════════════════

  /// الحصول على قائمة الأجهزة المعتمدة
  static Future<List<RegisteredDevice>> getApprovedDevices(
      {String? tenantId}) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return [];

      final snapshot = await _firestore
          .collection(_devicesPath(tid))
          .orderBy('registeredAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => RegisteredDevice.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('❌ خطأ في جلب الأجهزة');
      return [];
    }
  }

  /// إلغاء صلاحية جهاز
  static Future<bool> revokeDevice(String deviceId, {String? tenantId}) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return false;

      await _firestore
          .collection(_devicesPath(tid))
          .doc(deviceId)
          .update({'isActive': false});

      debugPrint('✅ تم إلغاء صلاحية الجهاز: $deviceId');
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في إلغاء صلاحية الجهاز');
      return false;
    }
  }

  /// إعادة تفعيل جهاز
  static Future<bool> reactivateDevice(String deviceId,
      {String? tenantId}) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return false;

      await _firestore
          .collection(_devicesPath(tid))
          .doc(deviceId)
          .update({'isActive': true});

      debugPrint('✅ تم إعادة تفعيل الجهاز: $deviceId');
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في إعادة تفعيل الجهاز');
      return false;
    }
  }

  /// حذف جهاز نهائياً
  static Future<bool> deleteDevice(String deviceId, {String? tenantId}) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return false;

      await _firestore.collection(_devicesPath(tid)).doc(deviceId).delete();

      debugPrint('✅ تم حذف الجهاز: $deviceId');
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في حذف الجهاز');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // أكواد التفعيل
  // ═══════════════════════════════════════════════════════════

  /// توليد كود تفعيل جديد
  static Future<ActivationCode?> generateActivationCode({
    String? tenantId,
    int validMinutes = 10,
  }) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return null;

      final user = CustomAuthService.currentUser;
      if (user == null) return null;

      // توليد كود من 6 أرقام
      final random = Random();
      final code = List.generate(6, (_) => random.nextInt(10)).join();

      final now = DateTime.now();
      final expiresAt = now.add(Duration(minutes: validMinutes));

      final codeData = {
        'createdBy': user.id,
        'createdByName': user.fullName,
        'createdAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'used': false,
      };

      await _firestore.collection(_codesPath(tid)).doc(code).set(codeData);

      debugPrint('✅ تم توليد كود تفعيل: $code');

      return ActivationCode(
        code: code,
        createdBy: user.id,
        createdByName: user.fullName,
        createdAt: now,
        expiresAt: expiresAt,
      );
    } catch (e) {
      debugPrint('❌ خطأ في توليد كود التفعيل');
      return null;
    }
  }

  /// تفعيل الجهاز بكود
  static Future<({bool success, String message})> activateDeviceWithCode(
    String code, {
    String? tenantId,
  }) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) {
        return (success: false, message: 'لا يوجد tenant محدد');
      }

      // التحقق من الكود
      final codeDoc =
          await _firestore.collection(_codesPath(tid)).doc(code).get();

      if (!codeDoc.exists) {
        return (success: false, message: 'كود التفعيل غير صحيح');
      }

      final codeData = ActivationCode.fromMap(codeDoc.data()!, code);

      if (codeData.used) {
        return (success: false, message: 'تم استخدام هذا الكود مسبقاً');
      }

      if (codeData.isExpired) {
        return (success: false, message: 'انتهت صلاحية كود التفعيل');
      }

      // تسجيل الجهاز
      final deviceId = await getDeviceId();
      final deviceName = await getDeviceName();
      final platform = getPlatform();
      final user = CustomAuthService.currentUser;

      final deviceData = {
        'deviceName': deviceName,
        'platform': platform,
        'registeredBy': user?.id ?? '',
        'registeredByName': user?.fullName ?? '',
        'registeredAt': FieldValue.serverTimestamp(),
        'lastUsed': FieldValue.serverTimestamp(),
        'isActive': true,
        'activationCode': code,
      };

      // حفظ الجهاز
      await _firestore
          .collection(_devicesPath(tid))
          .doc(deviceId)
          .set(deviceData);

      // تحديث الكود كمستخدم
      await _firestore.collection(_codesPath(tid)).doc(code).update({
        'used': true,
        'usedBy': deviceId,
        'usedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ تم تفعيل الجهاز بنجاح: $deviceId');
      return (success: true, message: 'تم تسجيل الجهاز بنجاح!');
    } catch (e) {
      debugPrint('❌ خطأ في تفعيل الجهاز');
      return (success: false, message: 'حدث خطأ');
    }
  }

  /// حذف الأكواد المنتهية الصلاحية (تنظيف)
  static Future<void> cleanupExpiredCodes({String? tenantId}) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return;

      final snapshot = await _firestore
          .collection(_codesPath(tid))
          .where('expiresAt', isLessThan: Timestamp.now())
          .get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.isNotEmpty) {
        debugPrint('🧹 تم حذف ${snapshot.docs.length} كود منتهي الصلاحية');
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في تنظيف الأكواد');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // إحصائيات
  // ═══════════════════════════════════════════════════════════

  /// عدد الأجهزة المعتمدة النشطة
  static Future<int> getActiveDevicesCount({String? tenantId}) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return 0;

      final snapshot = await _firestore
          .collection(_devicesPath(tid))
          .where('isActive', isEqualTo: true)
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      return 0;
    }
  }
}
