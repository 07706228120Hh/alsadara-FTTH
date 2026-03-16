/// خدمة إدارة الشركات (Tenants)
/// تدير جميع عمليات الشركات من إضافة وتعديل وحذف
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tenant.dart';
import '../models/tenant_user.dart';
import 'custom_auth_service.dart';
import 'firebase_availability.dart';

class TenantService {
  /// تحميل كسول لتجنب خطأ [core/no-app]
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// إنشاء شركة جديدة مع المدير الأول
  Future<TenantCreationResult> createTenantWithAdmin({
    required String tenantName,
    required String tenantCode,
    String? tenantEmail,
    String? tenantPhone,
    String? tenantAddress,
    required DateTime subscriptionEnd,
    String subscriptionPlan = 'monthly',
    int maxUsers = 10,
    required String adminUsername,
    required String adminPassword,
    required String adminFullName,
    String? adminEmail,
    String? adminPhone,
  }) async {
    if (!FirebaseAvailability.isAvailable)
      return TenantCreationResult.failure('Firebase غير متاح');
    try {
      final existingTenant = await _firestore
          .collection('tenants')
          .where('code', isEqualTo: tenantCode)
          .get();

      if (existingTenant.docs.isNotEmpty) {
        return TenantCreationResult.failure('كود الشركة مستخدم بالفعل');
      }

      // إنشاء الشركة
      final tenantRef = await _firestore.collection('tenants').add({
        'name': tenantName,
        'code': tenantCode,
        'email': tenantEmail,
        'phone': tenantPhone,
        'address': tenantAddress,
        'isActive': true,
        'subscriptionStart': FieldValue.serverTimestamp(),
        'subscriptionEnd': Timestamp.fromDate(subscriptionEnd),
        'subscriptionPlan': subscriptionPlan,
        'maxUsers': maxUsers,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': CustomAuthService.currentSuperAdmin?.id ?? 'system',
      });

      // إنشاء المدير الأول للشركة
      final hashedPassword = CustomAuthService.hashPassword(adminPassword);

      await _firestore
          .collection('tenants')
          .doc(tenantRef.id)
          .collection('users')
          .add({
        'username': adminUsername,
        'passwordHash': hashedPassword,
        'plainPassword': adminPassword, // حفظ كلمة المرور للعرض لاحقاً
        'fullName': adminFullName,
        'email': adminEmail,
        'phone': adminPhone,
        'role': UserRole.admin.value,
        'isActive': true,
        'firstSystemPermissions': buildAdminFirstSystemPermissionsV2(),
        'secondSystemPermissions': buildAdminSecondSystemPermissionsV2(),
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': 'system',
      });

      return TenantCreationResult.success(tenantRef.id);
    } catch (e) {
      return TenantCreationResult.failure('حدث خطأ');
    }
  }

  /// الحصول على شركة بالمعرف
  Future<Tenant?> getTenantById(String tenantId) async {
    if (!FirebaseAvailability.isAvailable) return null;
    try {
      final doc = await _firestore.collection('tenants').doc(tenantId).get();
      if (doc.exists) {
        return Tenant.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// الحصول على شركة بالكود
  Future<Tenant?> getTenantByCode(String code) async {
    if (!FirebaseAvailability.isAvailable) return null;
    try {
      final query = await _firestore
          .collection('tenants')
          .where('code', isEqualTo: code)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        return Tenant.fromFirestore(query.docs.first);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// تحديث بيانات الشركة
  Future<bool> updateTenant(String tenantId, Map<String, dynamic> data) async {
    if (!FirebaseAvailability.isAvailable) return false;
    try {
      await _firestore.collection('tenants').doc(tenantId).update(data);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// تعليق شركة
  Future<bool> suspendTenant(String tenantId, String reason) async {
    if (!FirebaseAvailability.isAvailable) return false;
    try {
      await _firestore.collection('tenants').doc(tenantId).update({
        'isActive': false,
        'suspensionReason': reason,
        'suspendedAt': FieldValue.serverTimestamp(),
        'suspendedBy': CustomAuthService.currentSuperAdmin?.id ?? 'system',
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// إعادة تفعيل شركة
  Future<bool> reactivateTenant(String tenantId) async {
    if (!FirebaseAvailability.isAvailable) return false;
    try {
      await _firestore.collection('tenants').doc(tenantId).update({
        'isActive': true,
        'suspensionReason': null,
        'suspendedAt': null,
        'suspendedBy': null,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// تمديد الاشتراك
  Future<bool> extendSubscription(
      String tenantId, DateTime newEndDate, String? newPlan) async {
    if (!FirebaseAvailability.isAvailable) return false;
    try {
      final updates = <String, dynamic>{
        'subscriptionEnd': Timestamp.fromDate(newEndDate),
      };
      if (newPlan != null) {
        updates['subscriptionPlan'] = newPlan;
      }
      await _firestore.collection('tenants').doc(tenantId).update(updates);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// الحصول على إحصائيات الشركة
  Future<TenantStats?> getTenantStats(String tenantId) async {
    if (!FirebaseAvailability.isAvailable) return null;
    try {
      // عدد المستخدمين
      final usersSnapshot = await _firestore
          .collection('tenants')
          .doc(tenantId)
          .collection('users')
          .get();

      final activeUsers = usersSnapshot.docs
          .where((doc) => doc.data()['isActive'] == true)
          .length;

      // يمكن إضافة المزيد من الإحصائيات لاحقاً
      return TenantStats(
        totalUsers: usersSnapshot.docs.length,
        activeUsers: activeUsers,
      );
    } catch (e) {
      return null;
    }
  }

  /// الحصول على الشركات التي ستنتهي قريباً
  Stream<List<Tenant>> getExpiringTenants(int daysThreshold) {
    if (!FirebaseAvailability.isAvailable) return Stream.value([]);
    final thresholdDate = DateTime.now().add(Duration(days: daysThreshold));

    return _firestore
        .collection('tenants')
        .where('subscriptionEnd',
            isLessThanOrEqualTo: Timestamp.fromDate(thresholdDate))
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Tenant.fromFirestore(doc)).toList());
  }

  /// الحصول على الشركات المعلقة
  Stream<List<Tenant>> getSuspendedTenants() {
    if (!FirebaseAvailability.isAvailable) return Stream.value([]);
    return _firestore
        .collection('tenants')
        .where('isActive', isEqualTo: false)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Tenant.fromFirestore(doc)).toList());
  }

  /// حذف شركة (مع جميع بياناتها)
  /// يقوم بحذف جميع المجموعات الفرعية ثم وثيقة الشركة
  Future<DeleteTenantResult> deleteTenant(String tenantId) async {
    if (!FirebaseAvailability.isAvailable)
      return DeleteTenantResult.failure('Firebase غير متاح');
    try {
      int deletedUsers = 0;
      int deletedSubcollections = 0;

      // قائمة المجموعات الفرعية المحتملة تحت الشركة
      final subcollections = [
        'users',
        'settings',
        'logs',
        'audit_logs',
        'notifications',
        'activity_logs',
      ];

      // حذف جميع المجموعات الفرعية باستخدام Batch للأداء الأفضل
      for (final subcollection in subcollections) {
        bool hasMore = true;
        while (hasMore) {
          // جلب مجموعة من الوثائق (حد 500 للـ batch)
          final snapshot = await _firestore
              .collection('tenants')
              .doc(tenantId)
              .collection(subcollection)
              .limit(500)
              .get();

          if (snapshot.docs.isEmpty) {
            hasMore = false;
            continue;
          }

          // استخدام Batch للحذف
          final batch = _firestore.batch();
          for (final doc in snapshot.docs) {
            batch.delete(doc.reference);
            if (subcollection == 'users') {
              deletedUsers++;
            } else {
              deletedSubcollections++;
            }
          }
          await batch.commit();

          // إذا كان العدد أقل من 500، انتهينا
          if (snapshot.docs.length < 500) {
            hasMore = false;
          }
        }
      }

      // حذف وثيقة الشركة الرئيسية
      await _firestore.collection('tenants').doc(tenantId).delete();

      return DeleteTenantResult.success(
        deletedUsers: deletedUsers,
        deletedSubcollections: deletedSubcollections,
      );
    } catch (e) {
      return DeleteTenantResult.failure('فشل في حذف الشركة');
    }
  }

  /// الحصول على عدد البيانات قبل الحذف (للتأكيد)
  Future<TenantDataCount> getTenantDataCount(String tenantId) async {
    if (!FirebaseAvailability.isAvailable)
      return TenantDataCount(usersCount: 0, otherDataCount: 0);
    try {
      int usersCount = 0;
      int otherDataCount = 0;

      // عدد المستخدمين
      final usersSnapshot = await _firestore
          .collection('tenants')
          .doc(tenantId)
          .collection('users')
          .count()
          .get();
      usersCount = usersSnapshot.count ?? 0;

      // يمكن إضافة عد للمجموعات الأخرى هنا إذا لزم الأمر

      return TenantDataCount(
        usersCount: usersCount,
        otherDataCount: otherDataCount,
      );
    } catch (e) {
      return TenantDataCount(usersCount: 0, otherDataCount: 0);
    }
  }
}

/// نتيجة حذف الشركة
class DeleteTenantResult {
  final bool success;
  final int deletedUsers;
  final int deletedSubcollections;
  final String? errorMessage;

  DeleteTenantResult({
    required this.success,
    this.deletedUsers = 0,
    this.deletedSubcollections = 0,
    this.errorMessage,
  });

  factory DeleteTenantResult.success({
    required int deletedUsers,
    required int deletedSubcollections,
  }) {
    return DeleteTenantResult(
      success: true,
      deletedUsers: deletedUsers,
      deletedSubcollections: deletedSubcollections,
    );
  }

  factory DeleteTenantResult.failure(String message) {
    return DeleteTenantResult(success: false, errorMessage: message);
  }
}

/// عدد بيانات الشركة
class TenantDataCount {
  final int usersCount;
  final int otherDataCount;

  TenantDataCount({
    required this.usersCount,
    required this.otherDataCount,
  });

  int get totalCount => usersCount + otherDataCount;
}

/// نتيجة إنشاء شركة
class TenantCreationResult {
  final bool success;
  final String? tenantId;
  final String? errorMessage;

  TenantCreationResult({
    required this.success,
    this.tenantId,
    this.errorMessage,
  });

  factory TenantCreationResult.success(String tenantId) {
    return TenantCreationResult(success: true, tenantId: tenantId);
  }

  factory TenantCreationResult.failure(String message) {
    return TenantCreationResult(success: false, errorMessage: message);
  }
}

/// إحصائيات الشركة
class TenantStats {
  final int totalUsers;
  final int activeUsers;

  TenantStats({
    required this.totalUsers,
    required this.activeUsers,
  });
}
