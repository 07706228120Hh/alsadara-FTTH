/// اسم الملف: خدمة إدارة الشركات
/// وصف الملف: خدمة للمدير لإضافة وإدارة الشركات (Organizations) - Multi-Tenant
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_auth_service.dart';
import 'firebase_availability.dart';

/// خدمة إدارة الشركات - Multi-Tenant Isolation
class OrganizationsService {
  /// تحميل كسول لتجنب خطأ [core/no-app]
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// إنشاء شركة جديدة (للمدير فقط)
  static Future<Map<String, dynamic>> createOrganization({
    required String name,
    required String description,
    String? logoUrl,
  }) async {
    if (!FirebaseAvailability.isAvailable)
      return {'success': false, 'message': 'Firebase غير متاح'};
    try {
      // التحقق من صلاحيات المدير
      final currentRole = await FirebaseAuthService.getUserRole();
      if (currentRole != 'super_admin') {
        return {
          'success': false,
          'message': 'ليس لديك صلاحية لإنشاء شركات',
        };
      }

      if (name.trim().isEmpty) {
        return {
          'success': false,
          'message': 'الرجاء إدخال اسم الشركة',
        };
      }

      // إنشاء الشركة
      final docRef = await _firestore.collection('organizations').add({
        'name': name.trim(),
        'description': description.trim(),
        'logoUrl': logoUrl,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': FirebaseAuthService.currentUserId ?? '',
        'settings': {
          'allowedFeatures': [],
          'maxUsers': 100,
        },
        'stats': {
          'usersCount': 0,
          'tasksCount': 0,
          'subscriptionsCount': 0,
        },
      });

      print('✅ تم إنشاء الشركة: ${docRef.id}');
      return {
        'success': true,
        'message': 'تم إنشاء الشركة بنجاح',
        'organizationId': docRef.id,
      };
    } catch (e) {
      print('❌ خطأ في إنشاء الشركة');
      return {
        'success': false,
        'message': 'خطأ في إنشاء الشركة',
      };
    }
  }

  /// جلب جميع الشركات (للمدير فقط)
  static Future<List<Map<String, dynamic>>> getAllOrganizations() async {
    if (!FirebaseAvailability.isAvailable) return [];
    try {
      final currentRole = await FirebaseAuthService.getUserRole();
      if (currentRole != 'super_admin') {
        return [];
      }

      final snapshot = await _firestore
          .collection('organizations')
          .orderBy('createdAt', descending: true)
          .get();

      List<Map<String, dynamic>> organizations = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        organizations.add(data);
      }

      return organizations;
    } catch (e) {
      print('❌ خطأ في جلب الشركات');
      return [];
    }
  }

  /// جلب شركة واحدة
  static Future<Map<String, dynamic>?> getOrganization(
      String organizationId) async {
    if (!FirebaseAvailability.isAvailable) return null;
    try {
      final doc = await _firestore
          .collection('organizations')
          .doc(organizationId)
          .get();

      if (!doc.exists) return null;

      final data = doc.data()!;
      data['id'] = doc.id;
      return data;
    } catch (e) {
      print('❌ خطأ في جلب بيانات الشركة');
      return null;
    }
  }

  /// تحديث بيانات الشركة
  static Future<bool> updateOrganization(
      String organizationId, Map<String, dynamic> updates) async {
    if (!FirebaseAvailability.isAvailable) return false;
    try {
      final currentRole = await FirebaseAuthService.getUserRole();
      if (currentRole != 'super_admin') {
        return false;
      }

      updates['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore
          .collection('organizations')
          .doc(organizationId)
          .update(updates);

      print('✅ تم تحديث الشركة: $organizationId');
      return true;
    } catch (e) {
      print('❌ خطأ في تحديث الشركة');
      return false;
    }
  }

  /// تفعيل/تعطيل شركة
  static Future<bool> toggleOrganizationStatus(
      String organizationId, bool isActive) async {
    return await updateOrganization(organizationId, {'isActive': isActive});
  }

  /// حذف شركة (حذف ناعم)
  static Future<bool> deleteOrganization(String organizationId) async {
    if (!FirebaseAvailability.isAvailable) return false;
    try {
      final currentRole = await FirebaseAuthService.getUserRole();
      if (currentRole != 'super_admin') {
        return false;
      }

      // حذف ناعم - تعطيل فقط
      await _firestore.collection('organizations').doc(organizationId).update({
        'isActive': false,
        'deletedAt': FieldValue.serverTimestamp(),
      });

      print('✅ تم تعطيل الشركة: $organizationId');
      return true;
    } catch (e) {
      print('❌ خطأ في حذف الشركة');
      return false;
    }
  }

  /// جلب مستخدمي شركة معينة
  static Future<List<Map<String, dynamic>>> getOrganizationUsers(
      String organizationId) async {
    if (!FirebaseAvailability.isAvailable) return [];
    try {
      final currentRole = await FirebaseAuthService.getUserRole();
      final currentOrgId = await FirebaseAuthService.getStoredOrganizationId();

      // السماح للمدير العام أو مدير الشركة
      if (currentRole != 'super_admin' && currentOrgId != organizationId) {
        return [];
      }

      final snapshot = await _firestore
          .collection('users')
          .where('organizationId', isEqualTo: organizationId)
          .get();

      List<Map<String, dynamic>> users = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        users.add(data);
      }

      return users;
    } catch (e) {
      print('❌ خطأ في جلب مستخدمي الشركة');
      return [];
    }
  }

  /// إضافة مستخدم إلى شركة
  static Future<Map<String, dynamic>> addUserToOrganization({
    required String organizationId,
    required String username,
    required String password,
    required String displayName,
    String role = 'user',
  }) async {
    if (!FirebaseAvailability.isAvailable)
      return {'success': false, 'message': 'Firebase غير متاح'};
    try {
      final currentRole = await FirebaseAuthService.getUserRole();
      if (currentRole != 'super_admin') {
        return {
          'success': false,
          'message': 'ليس لديك صلاحية لإضافة مستخدمين',
        };
      }

      // إنشاء المستخدم
      final result = await FirebaseAuthService.createUser(
        username: username,
        password: password,
        displayName: displayName,
        organizationId: organizationId,
        role: role,
      );

      if (result['success']) {
        // تحديث عدد المستخدمين في الشركة
        await _firestore
            .collection('organizations')
            .doc(organizationId)
            .update({
          'stats.usersCount': FieldValue.increment(1),
        });
      }

      return result;
    } catch (e) {
      return {
        'success': false,
        'message': 'خطأ',
      };
    }
  }

  /// نقل مستخدم من شركة لأخرى
  static Future<bool> moveUserToOrganization(
      String userId, String newOrganizationId) async {
    if (!FirebaseAvailability.isAvailable) return false;
    try {
      final currentRole = await FirebaseAuthService.getUserRole();
      if (currentRole != 'super_admin') {
        return false;
      }

      // جلب organizationId القديم
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final oldOrgId = userDoc.data()?['organizationId'];

      // تحديث organizationId
      await _firestore.collection('users').doc(userId).update({
        'organizationId': newOrganizationId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // تحديث الإحصائيات
      if (oldOrgId != null) {
        await _firestore.collection('organizations').doc(oldOrgId).update({
          'stats.usersCount': FieldValue.increment(-1),
        });
      }

      await _firestore
          .collection('organizations')
          .doc(newOrganizationId)
          .update({
        'stats.usersCount': FieldValue.increment(1),
      });

      return true;
    } catch (e) {
      print('❌ خطأ في نقل المستخدم');
      return false;
    }
  }

  /// الاستماع للشركات (Real-time)
  static Stream<List<Map<String, dynamic>>> watchOrganizations() {
    if (!FirebaseAvailability.isAvailable) return Stream.value([]);
    return _firestore
        .collection('organizations')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      List<Map<String, dynamic>> organizations = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        organizations.add(data);
      }
      return organizations;
    });
  }

  /// إحصائيات الشركة
  static Future<Map<String, dynamic>> getOrganizationStats(
      String organizationId) async {
    try {
      final org = await getOrganization(organizationId);
      if (org == null) {
        return {
          'usersCount': 0,
          'tasksCount': 0,
          'subscriptionsCount': 0,
        };
      }

      return org['stats'] ??
          {
            'usersCount': 0,
            'tasksCount': 0,
            'subscriptionsCount': 0,
          };
    } catch (e) {
      return {
        'usersCount': 0,
        'tasksCount': 0,
        'subscriptionsCount': 0,
      };
    }
  }
}
