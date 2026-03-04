/// خدمة المصادقة المخصصة
/// تدير تسجيل الدخول لجميع أنواع المستخدمين
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tenant.dart';
import '../models/tenant_user.dart';
import '../models/super_admin.dart';
import 'firebase_availability.dart';

/// نوع المستخدم المسجل
enum AuthUserType {
  superAdmin,
  tenantUser,
}

/// نتيجة تسجيل الدخول
class AuthResult {
  final bool success;
  final String? errorMessage;
  final AuthUserType? userType;
  final SuperAdmin? superAdmin;
  final TenantUser? tenantUser;
  final Tenant? tenant;

  AuthResult({
    required this.success,
    this.errorMessage,
    this.userType,
    this.superAdmin,
    this.tenantUser,
    this.tenant,
  });

  factory AuthResult.success({
    required AuthUserType userType,
    SuperAdmin? superAdmin,
    TenantUser? tenantUser,
    Tenant? tenant,
  }) {
    return AuthResult(
      success: true,
      userType: userType,
      superAdmin: superAdmin,
      tenantUser: tenantUser,
      tenant: tenant,
    );
  }

  factory AuthResult.failure(String message) {
    return AuthResult(
      success: false,
      errorMessage: message,
    );
  }
}

class CustomAuthService {
  /// تحميل كسول لتجنب خطأ [core/no-app]
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // المستخدم الحالي
  static SuperAdmin? currentSuperAdmin;
  static TenantUser? currentUser;
  static Tenant? currentTenant;
  static AuthUserType? currentUserType;

  /// تشفير كلمة المرور
  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// تسجيل دخول Super Admin
  Future<AuthResult> loginSuperAdmin(String username, String password) async {
    if (!FirebaseAvailability.isAvailable)
      return AuthResult.failure('Firebase غير متاح على هذه المنصة');
    try {
      final hashedPassword = hashPassword(password);

      // البحث عن المدير
      final querySnapshot = await _firestore
          .collection('super_admins')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return AuthResult.failure('اسم المستخدم أو كلمة المرور غير صحيحة');
      }

      final doc = querySnapshot.docs.first;
      final admin = SuperAdmin.fromFirestore(doc);

      // التحقق من كلمة المرور
      if (admin.passwordHash != hashedPassword) {
        return AuthResult.failure('اسم المستخدم أو كلمة المرور غير صحيحة');
      }

      // تحديث آخر تسجيل دخول
      await _firestore.collection('super_admins').doc(admin.id).update({
        'lastLogin': FieldValue.serverTimestamp(),
      });

      // حفظ المستخدم الحالي
      currentSuperAdmin = admin;
      currentUserType = AuthUserType.superAdmin;
      currentUser = null;
      currentTenant = null;

      return AuthResult.success(
        userType: AuthUserType.superAdmin,
        superAdmin: admin,
      );
    } catch (e) {
      return AuthResult.failure('حدث خطأ أثناء تسجيل الدخول: $e');
    }
  }

  /// تسجيل دخول مستخدم الشركة
  /// يمكن البحث بالاسم أو الكود
  Future<AuthResult> loginTenantUser(
      String tenantNameOrCode, String username, String password) async {
    if (!FirebaseAvailability.isAvailable)
      return AuthResult.failure('Firebase غير متاح على هذه المنصة');
    try {
      print('🔍 البحث عن الشركة: $tenantNameOrCode');

      // التحقق من كود مدير النظام (Super Admin)
      if (tenantNameOrCode == '1' ||
          tenantNameOrCode.toUpperCase() == 'ADMIN' ||
          tenantNameOrCode.toUpperCase() == 'SUPER') {
        print('🔐 محاولة تسجيل دخول كمدير نظام...');
        return await loginSuperAdmin(username, password);
      }

      // البحث عن الشركة بالكود أولاً
      var tenantQuery = await _firestore
          .collection('tenants')
          .where('code', isEqualTo: tenantNameOrCode.toUpperCase())
          .limit(1)
          .get();

      // إذا لم يتم العثور بالكود، ابحث بالاسم
      if (tenantQuery.docs.isEmpty) {
        print('🔍 لم يتم العثور بالكود، جاري البحث بالاسم...');
        tenantQuery = await _firestore
            .collection('tenants')
            .where('name', isEqualTo: tenantNameOrCode)
            .limit(1)
            .get();
      }

      // إذا لم يتم العثور، جرب البحث بالاسم مع تجاهل المسافات
      if (tenantQuery.docs.isEmpty) {
        print('🔍 جاري البحث في جميع الشركات...');
        final allTenants = await _firestore.collection('tenants').get();
        for (var doc in allTenants.docs) {
          final data = doc.data();
          final name = (data['name'] ?? '').toString().trim();
          final code = (data['code'] ?? '').toString().trim();
          // مقارنة بتجاهل حالة الأحرف
          if (name.toLowerCase() == tenantNameOrCode.toLowerCase() ||
              code.toLowerCase() == tenantNameOrCode.toLowerCase()) {
            tenantQuery = await _firestore
                .collection('tenants')
                .where(FieldPath.documentId, isEqualTo: doc.id)
                .get();
            break;
          }
        }
      }

      print('📊 عدد الشركات المطابقة: ${tenantQuery.docs.length}');

      if (tenantQuery.docs.isEmpty) {
        return AuthResult.failure(
            'لم يتم العثور على الشركة. تأكد من كتابة اسم الشركة بشكل صحيح.');
      }

      final tenantDoc = tenantQuery.docs.first;
      final tenant = Tenant.fromFirestore(tenantDoc);

      // التحقق من حالة الشركة
      if (!tenant.isActive) {
        return AuthResult.failure(
            'حساب الشركة معلق. السبب: ${tenant.suspensionReason ?? "غير محدد"}');
      }

      // التحقق من انتهاء الاشتراك
      if (tenant.isExpired) {
        return AuthResult.failure(
            'اشتراك الشركة منتهي. يرجى التواصل مع المدير لتجديد الاشتراك.');
      }

      // البحث عن المستخدم
      final hashedPassword = hashPassword(password);
      final userQuery = await _firestore
          .collection('tenants')
          .doc(tenant.id)
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        return AuthResult.failure('اسم المستخدم أو كلمة المرور غير صحيحة');
      }

      final userDoc = userQuery.docs.first;
      final user = TenantUser.fromFirestore(userDoc, tenant.id);

      // التحقق من كلمة المرور
      if (user.passwordHash != hashedPassword) {
        return AuthResult.failure('اسم المستخدم أو كلمة المرور غير صحيحة');
      }

      // التحقق من حالة المستخدم
      if (!user.isActive) {
        return AuthResult.failure('حسابك معطل. يرجى التواصل مع مدير الشركة.');
      }

      // تحديث آخر تسجيل دخول
      await _firestore
          .collection('tenants')
          .doc(tenant.id)
          .collection('users')
          .doc(user.id)
          .update({
        'lastLogin': FieldValue.serverTimestamp(),
      });

      // حفظ المستخدم الحالي
      currentUser = user;
      currentTenant = tenant;
      currentUserType = AuthUserType.tenantUser;
      currentSuperAdmin = null;

      return AuthResult.success(
        userType: AuthUserType.tenantUser,
        tenantUser: user,
        tenant: tenant,
      );
    } catch (e) {
      return AuthResult.failure('حدث خطأ أثناء تسجيل الدخول: $e');
    }
  }

  /// تسجيل الخروج
  Future<void> logout() async {
    currentSuperAdmin = null;
    currentUser = null;
    currentTenant = null;
    currentUserType = null;
  }

  /// التحقق من تسجيل الدخول
  bool get isLoggedIn =>
      currentSuperAdmin != null ||
      (currentUser != null && currentTenant != null);

  /// هل المستخدم Super Admin؟
  bool get isSuperAdmin => currentUserType == AuthUserType.superAdmin;

  /// الحصول على معرف الشركة الحالية
  String? get currentTenantId => currentTenant?.id;

  /// إنشاء Super Admin جديد (للإعداد الأولي فقط)
  Future<bool> createSuperAdmin(
      String username, String password, String name) async {
    if (!FirebaseAvailability.isAvailable) return false;
    try {
      final hashedPassword = hashPassword(password);

      await _firestore.collection('super_admins').add({
        'username': username,
        'passwordHash': hashedPassword,
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  /// إنشاء شركة جديدة
  Future<String?> createTenant({
    required String name,
    required String code,
    String? email,
    String? phone,
    String? address,
    required DateTime subscriptionEnd,
    String subscriptionPlan = 'monthly',
    int maxUsers = 10,
  }) async {
    if (!FirebaseAvailability.isAvailable) return null;
    try {
      // التحقق من عدم وجود كود مكرر
      final existing = await _firestore
          .collection('tenants')
          .where('code', isEqualTo: code)
          .get();

      if (existing.docs.isNotEmpty) {
        return null;
      }

      final docRef = await _firestore.collection('tenants').add({
        'name': name,
        'code': code,
        'email': email,
        'phone': phone,
        'address': address,
        'isActive': true,
        'subscriptionStart': FieldValue.serverTimestamp(),
        'subscriptionEnd': Timestamp.fromDate(subscriptionEnd),
        'subscriptionPlan': subscriptionPlan,
        'maxUsers': maxUsers,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': currentSuperAdmin?.id ?? 'system',
      });

      return docRef.id;
    } catch (e) {
      return null;
    }
  }

  /// إنشاء مستخدم للشركة
  Future<String?> createTenantUser({
    required String tenantId,
    required String username,
    required String password,
    required String fullName,
    String? email,
    String? phone,
    UserRole role = UserRole.employee,
    String? department,
    String? center,
    Map<String, bool>? firstSystemPermissions,
    Map<String, bool>? secondSystemPermissions,
  }) async {
    if (!FirebaseAvailability.isAvailable) return null;
    try {
      // التحقق من عدم وجود اسم مستخدم مكرر في نفس الشركة
      final existing = await _firestore
          .collection('tenants')
          .doc(tenantId)
          .collection('users')
          .where('username', isEqualTo: username)
          .get();

      if (existing.docs.isNotEmpty) {
        return null;
      }

      final hashedPassword = hashPassword(password);

      // استخدام صلاحيات المدير إذا كان الدور admin
      final first = role == UserRole.admin
          ? adminFirstSystemPermissions
          : (firstSystemPermissions ?? defaultFirstSystemPermissions);
      final second = role == UserRole.admin
          ? adminSecondSystemPermissions
          : (secondSystemPermissions ?? defaultSecondSystemPermissions);

      final docRef = await _firestore
          .collection('tenants')
          .doc(tenantId)
          .collection('users')
          .add({
        'username': username,
        'passwordHash': hashedPassword,
        'plainPassword': password, // حفظ كلمة المرور للعرض لاحقاً
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'role': role.value,
        'department': department,
        'center': center,
        'isActive': true,
        'firstSystemPermissions': first,
        'secondSystemPermissions': second,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': currentUser?.id ?? currentSuperAdmin?.id ?? 'system',
      });

      return docRef.id;
    } catch (e) {
      return null;
    }
  }

  /// تغيير كلمة مرور المستخدم
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    if (!FirebaseAvailability.isAvailable) return false;
    try {
      if (currentUser == null || currentTenant == null) return false;

      final oldHash = hashPassword(oldPassword);
      if (currentUser!.passwordHash != oldHash) return false;

      final newHash = hashPassword(newPassword);

      await _firestore
          .collection('tenants')
          .doc(currentTenant!.id)
          .collection('users')
          .doc(currentUser!.id)
          .update({
        'passwordHash': newHash,
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  /// تعليق/إلغاء تعليق شركة
  Future<bool> toggleTenantSuspension(
      String tenantId, bool suspend, String? reason) async {
    if (!FirebaseAvailability.isAvailable) return false;
    try {
      await _firestore.collection('tenants').doc(tenantId).update({
        'isActive': !suspend,
        'suspensionReason': suspend ? reason : null,
        'suspendedAt': suspend ? FieldValue.serverTimestamp() : null,
        'suspendedBy': suspend ? currentSuperAdmin?.id : null,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// تمديد اشتراك شركة
  Future<bool> extendSubscription(String tenantId, DateTime newEndDate) async {
    if (!FirebaseAvailability.isAvailable) return false;
    try {
      await _firestore.collection('tenants').doc(tenantId).update({
        'subscriptionEnd': Timestamp.fromDate(newEndDate),
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// الحصول على جميع الشركات (للـ Super Admin)
  Stream<List<Tenant>> getAllTenants() {
    if (!FirebaseAvailability.isAvailable) return Stream.value([]);
    return _firestore
        .collection('tenants')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Tenant.fromFirestore(doc)).toList());
  }

  /// الحصول على مستخدمي شركة معينة
  Stream<List<TenantUser>> getTenantUsers(String tenantId) {
    if (!FirebaseAvailability.isAvailable) return Stream.value([]);
    return _firestore
        .collection('tenants')
        .doc(tenantId)
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TenantUser.fromFirestore(doc, tenantId))
            .toList());
  }
}
