/// اسم الملف: خدمة المصادقة عبر Firebase
/// وصف الملف: خدمة المصادقة Multi-Tenant مع عزل كامل للشركات - Username/Password
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'security/rate_limiter_service.dart'; // 🛡️ حماية من Brute Force

/// خدمة المصادقة عبر Firestore - Multi-Tenant مع عزل كامل للشركات
class FirebaseAuthService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // معلومات المستخدم الحالي المخزنة محلياً
  static String? _currentUserId;
  static Map<String, dynamic>? _currentUserData;

  // ===== معلومات المستخدم المصادق =====
  static String? get currentUserId => _currentUserId;
  static Map<String, dynamic>? get currentUserData => _currentUserData;
  static bool get isAuthenticated => _currentUserId != null;

  /// تشفير كلمة المرور
  static String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// تسجيل الدخول باستخدام اسم المستخدم وكلمة المرور
  static Future<Map<String, dynamic>> signInWithUsername(
      String username, String password) async {
    try {
      if (username.trim().isEmpty || password.isEmpty) {
        return {
          'success': false,
          'message': 'الرجاء إدخال اسم المستخدم وكلمة المرور',
        };
      }

      // 🛡️ فحص Rate Limiting - حماية من Brute Force
      final rateLimitCheck =
          await RateLimiterService.instance.canAttempt(username.trim());
      if (!rateLimitCheck.allowed) {
        print('🚫 Rate Limiter: محظور - ${rateLimitCheck.message}');
        return {
          'success': false,
          'message': rateLimitCheck.message ?? 'تم حظرك مؤقتاً. حاول لاحقاً',
          'isRateLimited': true,
          'lockoutMinutes': rateLimitCheck.lockoutRemaining?.inMinutes,
        };
      }

      // 1. البحث عن المستخدم باسم المستخدم
      final snapshot = await _firestore
          .collection('users')
          .where('username', isEqualTo: username.trim())
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        // 🛡️ تسجيل المحاولة الفاشلة
        final result = await RateLimiterService.instance
            .recordFailedAttempt(username.trim());
        return {
          'success': false,
          'message': 'اسم المستخدم أو كلمة المرور غير صحيحة',
          'remainingAttempts': result.remainingAttempts,
        };
      }

      final userDoc = snapshot.docs.first;
      final userData = userDoc.data();
      final userId = userDoc.id;

      // 2. التحقق من كلمة المرور
      final hashedPassword = _hashPassword(password);
      if (userData['password'] != hashedPassword) {
        // 🛡️ تسجيل المحاولة الفاشلة
        final result = await RateLimiterService.instance
            .recordFailedAttempt(username.trim());
        return {
          'success': false,
          'message': result.message ?? 'اسم المستخدم أو كلمة المرور غير صحيحة',
          'remainingAttempts': result.remainingAttempts,
        };
      }

      // 3. التحقق من تفعيل الحساب
      if (userData['isActive'] != true) {
        return {
          'success': false,
          'message': 'حسابك غير مفعّل. يرجى التواصل مع الإدارة',
        };
      }

      // 🛡️ إعادة تعيين Rate Limiter عند النجاح
      await RateLimiterService.instance
          .recordSuccessfulAttempt(username.trim());

      // 4. حفظ معلومات الجلسة
      _currentUserId = userId;
      _currentUserData = userData;
      _currentUserData!['id'] = userId;

      await _saveSessionLocally(userId, userData);

      // 5. تحديث آخر تسجيل دخول
      await _firestore.collection('users').doc(userId).update({
        'lastLogin': FieldValue.serverTimestamp(),
      });

      return {
        'success': true,
        'message': 'تم تسجيل الدخول بنجاح',
        'userId': userId,
        'userData': userData,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'خطأ في تسجيل الدخول: $e',
      };
    }
  }

  /// إنشاء حساب جديد (للمدير فقط)
  static Future<Map<String, dynamic>> createUser({
    required String username,
    required String password,
    required String displayName,
    required String organizationId,
    String role = 'user',
  }) async {
    try {
      // 1. التحقق من عدم وجود اسم المستخدم
      final existingUser = await _firestore
          .collection('users')
          .where('username', isEqualTo: username.trim())
          .limit(1)
          .get();

      if (existingUser.docs.isNotEmpty) {
        return {
          'success': false,
          'message': 'اسم المستخدم موجود بالفعل',
        };
      }

      // 2. تشفير كلمة المرور
      final hashedPassword = _hashPassword(password);

      // 3. إنشاء المستخدم في Firestore
      final docRef = await _firestore.collection('users').add({
        'username': username.trim(),
        'password': hashedPassword,
        'displayName': displayName,
        'organizationId': organizationId,
        'role': role,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': null,
      });

      return {
        'success': true,
        'message': 'تم إنشاء المستخدم بنجاح',
        'userId': docRef.id,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'خطأ في إنشاء المستخدم: $e',
      };
    }
  }

  /// تسجيل الخروج
  static Future<void> signOut() async {
    try {
      _currentUserId = null;
      _currentUserData = null;
      await _clearSessionLocally();
    } catch (e) {
      print('خطأ في تسجيل الخروج: $e');
    }
  }

  /// حفظ معلومات الجلسة محلياً
  static Future<void> _saveSessionLocally(
      String userId, Map<String, dynamic> userData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_user_id', userId);
      await prefs.setString('username', userData['username'] ?? '');
      await prefs.setString('display_name', userData['displayName'] ?? '');
      await prefs.setString(
          'organization_id', userData['organizationId'] ?? '');
      await prefs.setString('user_role', userData['role'] ?? 'user');
    } catch (e) {
      print('خطأ في حفظ الجلسة المحلية: $e');
    }
  }

  /// مسح معلومات الجلسة المحلية
  static Future<void> _clearSessionLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('current_user_id');
      await prefs.remove('username');
      await prefs.remove('display_name');
      await prefs.remove('organization_id');
      await prefs.remove('user_role');
    } catch (e) {
      print('خطأ في مسح الجلسة: $e');
    }
  }

  /// الحصول على بيانات المستخدم من Firestore
  static Future<Map<String, dynamic>> getUserData(String userId) async {
    try {
      final docSnapshot =
          await _firestore.collection('users').doc(userId).get();

      if (!docSnapshot.exists) {
        return {'exists': false};
      }

      final data = docSnapshot.data()!;
      data['id'] = userId;
      data['exists'] = true;
      return data;
    } catch (e) {
      print('خطأ في قراءة بيانات المستخدم: $e');
      return {'exists': false};
    }
  }

  /// استعادة الجلسة من التخزين المحلي
  static Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('current_user_id');

      if (userId == null || userId.isEmpty) {
        return false;
      }

      final userData = await getUserData(userId);
      if (userData['exists'] != true) {
        await _clearSessionLocally();
        return false;
      }

      _currentUserId = userId;
      _currentUserData = userData;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// تحديث Organization ID للمستخدم
  static Future<void> updateOrganizationId(
      String uid, String organizationId) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'organizationId': organizationId,
      });

      // حفظ محلياً أيضاً
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('organization_id', organizationId);
    } catch (e) {
      print('خطأ في تحديث Organization ID: $e');
    }
  }

  /// التحقق من صلاحية المستخدم
  static Future<bool> checkUserActive() async {
    if (!isAuthenticated) return false;

    try {
      if (_currentUserData != null) {
        return _currentUserData!['isActive'] == true;
      }
      final userData = await getUserData(_currentUserId!);
      return userData['isActive'] == true;
    } catch (e) {
      return false;
    }
  }

  /// الحصول على Organization ID المحفوظ محلياً
  static Future<String?> getStoredOrganizationId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('organization_id');
    } catch (e) {
      return null;
    }
  }

  /// الحصول على دور المستخدم
  static Future<String?> getUserRole() async {
    if (!isAuthenticated) return null;

    try {
      if (_currentUserData != null) {
        return _currentUserData!['role'];
      }
      final userData = await getUserData(_currentUserId!);
      return userData['role'];
    } catch (e) {
      return null;
    }
  }
}
