/// نموذج الشركة/المستأجر
/// يحتوي على جميع بيانات الشركة واشتراكها
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class Tenant {
  final String id;
  final String name;
  final String code;
  final String? email;
  final String? phone;
  final String? address;
  final String? logo;
  final bool isActive;
  final String? suspensionReason;
  final DateTime? suspendedAt;
  final String? suspendedBy;
  final DateTime subscriptionStart;
  final DateTime subscriptionEnd;
  final String subscriptionPlan;
  final int maxUsers;
  final DateTime createdAt;
  final String createdBy;
  // صلاحيات الشركة - ما يمكن لمستخدمي الشركة الوصول إليه
  final Map<String, bool> enabledFirstSystemFeatures;
  final Map<String, bool> enabledSecondSystemFeatures;

  Tenant({
    required this.id,
    required this.name,
    required this.code,
    this.email,
    this.phone,
    this.address,
    this.logo,
    required this.isActive,
    this.suspensionReason,
    this.suspendedAt,
    this.suspendedBy,
    required this.subscriptionStart,
    required this.subscriptionEnd,
    required this.subscriptionPlan,
    required this.maxUsers,
    required this.createdAt,
    required this.createdBy,
    required this.enabledFirstSystemFeatures,
    required this.enabledSecondSystemFeatures,
  });

  /// الأيام المتبقية من الاشتراك
  int get daysRemaining => subscriptionEnd.difference(DateTime.now()).inDays;

  /// هل الاشتراك منتهي؟
  bool get isExpired => DateTime.now().isAfter(subscriptionEnd);

  /// هل ينتهي قريباً (خلال 7 أيام)؟
  bool get isExpiringSoon => daysRemaining <= 7 && daysRemaining >= 0;

  /// هل يحتاج تحذير (خلال 30 يوم)؟
  bool get needsWarning => daysRemaining <= 30 && daysRemaining > 7;

  /// حالة الاشتراك
  SubscriptionStatus get status {
    if (!isActive) return SubscriptionStatus.suspended;
    if (isExpired) return SubscriptionStatus.expired;
    if (isExpiringSoon) return SubscriptionStatus.critical;
    if (needsWarning) return SubscriptionStatus.warning;
    return SubscriptionStatus.active;
  }

  /// لون حالة الاشتراك
  Color get subscriptionStatusColor {
    switch (status) {
      case SubscriptionStatus.active:
        return Colors.green;
      case SubscriptionStatus.warning:
        return Colors.orange;
      case SubscriptionStatus.critical:
        return Colors.deepOrange;
      case SubscriptionStatus.expired:
        return Colors.red;
      case SubscriptionStatus.suspended:
        return Colors.grey;
    }
  }

  /// تحويل من Firestore
  factory Tenant.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Tenant(
      id: doc.id,
      name: data['name'] ?? '',
      code: data['code'] ?? '',
      email: data['email'],
      phone: data['phone'],
      address: data['address'],
      logo: data['logo'],
      isActive: data['isActive'] ?? true,
      suspensionReason: data['suspensionReason'],
      suspendedAt: data['suspendedAt'] != null
          ? (data['suspendedAt'] as Timestamp).toDate()
          : null,
      suspendedBy: data['suspendedBy'],
      subscriptionStart: data['subscriptionStart'] != null
          ? (data['subscriptionStart'] as Timestamp).toDate()
          : DateTime.now(),
      subscriptionEnd: data['subscriptionEnd'] != null
          ? (data['subscriptionEnd'] as Timestamp).toDate()
          : DateTime.now().add(const Duration(days: 30)),
      subscriptionPlan: data['subscriptionPlan'] ?? 'monthly',
      maxUsers: data['maxUsers'] ?? 10,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      enabledFirstSystemFeatures:
          _parseFeatures(data['enabledFirstSystemFeatures']),
      enabledSecondSystemFeatures:
          _parseFeatures(data['enabledSecondSystemFeatures']),
    );
  }

  static Map<String, bool> _parseFeatures(dynamic data) {
    if (data == null) {
      // افتراضياً: جميع الميزات مفعلة
      return {};
    }
    if (data is Map) {
      return Map<String, bool>.from(
        data.map((key, value) => MapEntry(key.toString(), value == true)),
      );
    }
    return {};
  }

  /// التحقق من تفعيل ميزة للشركة
  bool isFirstSystemFeatureEnabled(String feature) {
    // إذا لم يتم تحديد الميزة، تكون مفعلة افتراضياً
    if (!enabledFirstSystemFeatures.containsKey(feature)) return true;
    return enabledFirstSystemFeatures[feature] ?? true;
  }

  bool isSecondSystemFeatureEnabled(String feature) {
    if (!enabledSecondSystemFeatures.containsKey(feature)) return true;
    return enabledSecondSystemFeatures[feature] ?? true;
  }

  /// تحويل إلى Map للحفظ في Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'code': code,
      'email': email,
      'phone': phone,
      'address': address,
      'logo': logo,
      'isActive': isActive,
      'suspensionReason': suspensionReason,
      'suspendedAt':
          suspendedAt != null ? Timestamp.fromDate(suspendedAt!) : null,
      'suspendedBy': suspendedBy,
      'subscriptionStart': Timestamp.fromDate(subscriptionStart),
      'subscriptionEnd': Timestamp.fromDate(subscriptionEnd),
      'subscriptionPlan': subscriptionPlan,
      'maxUsers': maxUsers,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'enabledFirstSystemFeatures': enabledFirstSystemFeatures,
      'enabledSecondSystemFeatures': enabledSecondSystemFeatures,
    };
  }

  /// نسخة معدلة
  Tenant copyWith({
    String? id,
    String? name,
    String? code,
    String? email,
    String? phone,
    String? address,
    String? logo,
    bool? isActive,
    String? suspensionReason,
    DateTime? suspendedAt,
    String? suspendedBy,
    DateTime? subscriptionStart,
    DateTime? subscriptionEnd,
    String? subscriptionPlan,
    int? maxUsers,
    DateTime? createdAt,
    String? createdBy,
    Map<String, bool>? enabledFirstSystemFeatures,
    Map<String, bool>? enabledSecondSystemFeatures,
  }) {
    return Tenant(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      logo: logo ?? this.logo,
      isActive: isActive ?? this.isActive,
      suspensionReason: suspensionReason ?? this.suspensionReason,
      suspendedAt: suspendedAt ?? this.suspendedAt,
      suspendedBy: suspendedBy ?? this.suspendedBy,
      subscriptionStart: subscriptionStart ?? this.subscriptionStart,
      subscriptionEnd: subscriptionEnd ?? this.subscriptionEnd,
      subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
      maxUsers: maxUsers ?? this.maxUsers,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      enabledFirstSystemFeatures:
          enabledFirstSystemFeatures ?? this.enabledFirstSystemFeatures,
      enabledSecondSystemFeatures:
          enabledSecondSystemFeatures ?? this.enabledSecondSystemFeatures,
    );
  }
}

/// حالات الاشتراك
enum SubscriptionStatus {
  active, // نشط
  warning, // تحذير (أقل من 30 يوم)
  critical, // حرج (أقل من 7 أيام)
  expired, // منتهي
  suspended, // معلق يدوياً
}
