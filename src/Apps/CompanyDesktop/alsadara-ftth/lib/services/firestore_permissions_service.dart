/// اسم الملف: خدمة الصلاحيات من Firestore
/// وصف الملف: خدمة لتحميل الصلاحيات من Firestore حسب Organization Multi-Tenant
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_auth_service.dart';
import 'firebase_availability.dart';

/// خدمة الصلاحيات من Firestore - Multi-Tenant Support
class FirestorePermissionsService {
  /// تحميل كسول لتجنب خطأ [core/no-app]
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// جلب الصلاحيات من Firestore حسب Organization ID + User ID
  static Future<Map<String, bool>> getPermissionsFromFirestore({
    required String organizationId,
    required String userId,
  }) async {
    if (!FirebaseAvailability.isAvailable) return _getDefaultPermissions();
    try {
      // 1. جلب بيانات المستخدم
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists) {
        return _getDefaultPermissions();
      }

      final userData = userDoc.data()!;
      final String? role = userData['role'];

      // 2. إذا كان super_admin أو admin: جميع الصلاحيات
      if (role == 'super_admin' || role == 'admin') {
        return _getAllPermissions();
      }

      // 3. جلب صلاحيات المستخدم من permissions collection
      final permDoc = await _firestore
          .collection('permissions')
          .doc(organizationId)
          .collection('users')
          .doc(userId)
          .get();

      if (!permDoc.exists) {
        return _getDefaultPermissions();
      }

      final permsData = permDoc.data()!;
      return _mergePermissions(permsData);
    } catch (e) {
      print('خطأ في جلب الصلاحيات من Firestore');
      return _getDefaultPermissions();
    }
  }

  /// جلب الصلاحيات من Firestore حسب Organization ID + User Role (الطريقة القديمة)
  ///
  /// إذا كان المستخدم admin/مدير: يحصل على كل الصلاحيات
  /// إذا كان المستخدم user: يحصل على الصلاحيات المخصصة له في organization
  static Future<Map<String, bool>> getPermissionsFromFirestoreOld() async {
    try {
      // هذه الدالة للتوافق فقط - استخدم الدالة الجديدة
      return _getDefaultPermissions();
    } catch (e) {
      print('خطأ في جلب الصلاحيات من Firestore');
      return _getDefaultPermissions();
    }
  }

  /// دمج الصلاحيات من Firestore مع الافتراضيات
  static Map<String, bool> _mergePermissions(
      Map<String, dynamic> firestorePerms) {
    final permissions = <String, bool>{};

    // جميع الصلاحيات
    for (var key in [..._firstSystemKeys, ..._secondSystemKeys]) {
      permissions[key] = firestorePerms[key] == true;
    }

    return permissions;
  }

  /// الحصول على جميع الصلاحيات (للمديرين)
  static Map<String, bool> _getAllPermissions() {
    final permissions = <String, bool>{};

    for (var key in _firstSystemKeys) {
      permissions[key] = true;
    }

    for (var key in _secondSystemKeys) {
      permissions[key] = true;
    }

    return permissions;
  }

  /// الحصول على الصلاحيات الافتراضية (جميعها مغلقة)
  static Map<String, bool> _getDefaultPermissions() {
    final permissions = <String, bool>{};

    // النظام الأول
    for (var key in _firstSystemKeys) {
      permissions[key] = false;
    }

    // النظام الثاني
    for (var key in _secondSystemKeys) {
      permissions[key] = false;
    }

    return permissions;
  }

  /// حفظ الصلاحيات محلياً (Cache)
  static Future<void> cachePermissionsLocally(
      Map<String, bool> permissions) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // حفظ كل صلاحية
      for (var entry in permissions.entries) {
        await prefs.setBool('cached_permission_${entry.key}', entry.value);
      }

      // حفظ وقت التخزين المؤقت
      await prefs.setString(
          'cached_permissions_time', DateTime.now().toIso8601String());
    } catch (e) {
      print('خطأ في حفظ الصلاحيات محلياً');
    }
  }

  /// جلب الصلاحيات المحفوظة محلياً
  static Future<Map<String, bool>?> getCachedPermissions() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // التحقق من وجود cache
      final cachedTime = prefs.getString('cached_permissions_time');
      if (cachedTime == null) {
        return null;
      }

      // التحقق من صلاحية الـ cache (24 ساعة)
      final cacheDate = DateTime.parse(cachedTime);
      final now = DateTime.now();
      if (now.difference(cacheDate).inHours > 24) {
        return null; // انتهت صلاحية الـ cache
      }

      // جلب الصلاحيات
      final permissions = <String, bool>{};

      for (var key in _firstSystemKeys) {
        permissions[key] = prefs.getBool('cached_permission_$key') ?? false;
      }

      for (var key in _secondSystemKeys) {
        permissions[key] = prefs.getBool('cached_permission_$key') ?? false;
      }

      return permissions;
    } catch (e) {
      return null;
    }
  }

  /// مفاتيح النظام الأول (من PermissionsService)
  static const List<String> _firstSystemKeys = [
    'attendance',
    'agent',
    'tasks',
    'zones',
    'ai_search',
  ];

  /// مفاتيح النظام الثاني (من PermissionsService)
  static const List<String> _secondSystemKeys = [
    'users',
    'subscriptions',
    'tasks',
    'zones',
    'accounts',
    'account_records',
    'export',
    'agents',
    'google_sheets',
    'whatsapp',
    'wallet_balance',
    'expiring_soon',
    'quick_search',
    'technicians',
    'transactions',
    'notifications',
    'audit_logs',
    'whatsapp_link',
    'whatsapp_settings',
    'plans_bundles',
    'whatsapp_business_api',
    'whatsapp_bulk_sender',
    'whatsapp_conversations_fab',
    'local_storage',
    'local_storage_import',
  ];

  /// تحديث الصلاحيات في Firestore (للمديرين فقط)
  static Future<bool> updateUserPermissions({
    required String organizationId,
    required String userId,
    required Map<String, bool> permissions,
  }) async {
    if (!FirebaseAvailability.isAvailable) return false;
    try {
      // التحقق من أن المستخدم الحالي super_admin أو admin
      final currentRole = await FirebaseAuthService.getUserRole();
      if (currentRole != 'super_admin' && currentRole != 'admin') {
        print('⚠️ ليس لديك صلاحية تحديث الصلاحيات');
        return false;
      }

      // حفظ الصلاحيات في permissions/{orgId}/users/{userId}
      await _firestore
          .collection('permissions')
          .doc(organizationId)
          .collection('users')
          .doc(userId)
          .set(permissions);

      print('✅ تم تحديث صلاحيات المستخدم $userId');
      return true;
    } catch (e) {
      print('❌ خطأ في تحديث الصلاحيات');
      return false;
    }
  }
}
