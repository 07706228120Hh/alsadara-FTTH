/// نماذج بيانات نظام المواطن
library;

import 'package:flutter/material.dart';

/// حالة طلب الخدمة
enum ServiceRequestStatus {
  pending(0, 'جديد', Colors.blue, Icons.hourglass_empty),
  reviewing(1, 'قيد المراجعة', Colors.orange, Icons.visibility),
  approved(2, 'موافق عليه', Colors.teal, Icons.check_circle_outline),
  assigned(3, 'تم التعيين', Colors.purple, Icons.person_add),
  inProgress(4, 'قيد التنفيذ', Colors.indigo, Icons.engineering),
  completed(5, 'مكتمل', Colors.green, Icons.check_circle),
  cancelled(6, 'ملغي', Colors.grey, Icons.cancel),
  rejected(7, 'مرفوض', Colors.red, Icons.block),
  onHold(8, 'معلق', Colors.amber, Icons.pause_circle);

  final int value;
  final String nameAr;
  final Color color;
  final IconData icon;

  const ServiceRequestStatus(this.value, this.nameAr, this.color, this.icon);

  static ServiceRequestStatus fromValue(int value) {
    return ServiceRequestStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ServiceRequestStatus.pending,
    );
  }
}

/// أولوية الطلب
enum RequestPriority {
  low(0, 'منخفضة', Colors.grey),
  normal(1, 'عادية', Colors.blue),
  high(2, 'عالية', Colors.orange),
  urgent(3, 'عاجلة', Colors.red);

  final int value;
  final String nameAr;
  final Color color;

  const RequestPriority(this.value, this.nameAr, this.color);

  static RequestPriority fromValue(int value) {
    return RequestPriority.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RequestPriority.normal,
    );
  }
}

/// نموذج المواطن
class CitizenModel {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String? email;
  final String? profileImageUrl;
  final String? city;
  final String? district;
  final String? fullAddress;
  final double? latitude;
  final double? longitude;
  final String? companyId;
  final bool isActive;
  final bool isPhoneVerified;
  final bool isBanned;
  final String? banReason;
  final int totalRequests;
  final double totalPaid;
  final int loyaltyPoints;
  final DateTime? lastLoginAt;
  final DateTime createdAt;

  CitizenModel({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    this.email,
    this.profileImageUrl,
    this.city,
    this.district,
    this.fullAddress,
    this.latitude,
    this.longitude,
    this.companyId,
    this.isActive = true,
    this.isPhoneVerified = false,
    this.isBanned = false,
    this.banReason,
    this.totalRequests = 0,
    this.totalPaid = 0,
    this.loyaltyPoints = 0,
    this.lastLoginAt,
    required this.createdAt,
  });

  factory CitizenModel.fromJson(Map<String, dynamic> json) {
    return CitizenModel(
      id: json['id'] ?? '',
      fullName: json['fullName'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      email: json['email'],
      profileImageUrl: json['profileImageUrl'],
      city: json['city'],
      district: json['district'],
      fullAddress: json['fullAddress'],
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      companyId: json['companyId'],
      isActive: json['isActive'] ?? true,
      isPhoneVerified: json['isPhoneVerified'] ?? false,
      isBanned: json['isBanned'] ?? false,
      banReason: json['banReason'],
      totalRequests: json['totalRequests'] ?? 0,
      totalPaid: (json['totalPaid'] ?? 0).toDouble(),
      loyaltyPoints: json['loyaltyPoints'] ?? 0,
      lastLoginAt: json['lastLoginAt'] != null
          ? DateTime.parse(json['lastLoginAt'])
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'email': email,
      'profileImageUrl': profileImageUrl,
      'city': city,
      'district': district,
      'fullAddress': fullAddress,
      'latitude': latitude,
      'longitude': longitude,
      'companyId': companyId,
      'isActive': isActive,
      'isPhoneVerified': isPhoneVerified,
      'isBanned': isBanned,
      'banReason': banReason,
      'totalRequests': totalRequests,
      'totalPaid': totalPaid,
      'loyaltyPoints': loyaltyPoints,
      'lastLoginAt': lastLoginAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

/// نموذج طلب الخدمة
class ServiceRequestModel {
  final String id;
  final String requestNumber;
  final int serviceId;
  final String? serviceName;
  final int operationTypeId;
  final String? operationTypeName;
  final String citizenId;
  final String? citizenName;
  final String? citizenPhone;
  final String? companyId;
  final ServiceRequestStatus status;
  final String? statusNote;
  final RequestPriority priority;
  final String? details;
  final String? address;
  final String? assignedToId;
  final String? assignedToName;
  final double? estimatedCost;
  final double? finalCost;
  final DateTime requestedAt;
  final DateTime? assignedAt;
  final DateTime? completedAt;

  ServiceRequestModel({
    required this.id,
    required this.requestNumber,
    required this.serviceId,
    this.serviceName,
    required this.operationTypeId,
    this.operationTypeName,
    required this.citizenId,
    this.citizenName,
    this.citizenPhone,
    this.companyId,
    required this.status,
    this.statusNote,
    this.priority = RequestPriority.normal,
    this.details,
    this.address,
    this.assignedToId,
    this.assignedToName,
    this.estimatedCost,
    this.finalCost,
    required this.requestedAt,
    this.assignedAt,
    this.completedAt,
  });

  factory ServiceRequestModel.fromJson(Map<String, dynamic> json) {
    return ServiceRequestModel(
      id: json['id'] ?? '',
      requestNumber: json['requestNumber'] ?? '',
      serviceId: json['serviceId'] ?? 0,
      serviceName: json['serviceName'],
      operationTypeId: json['operationTypeId'] ?? 0,
      operationTypeName: json['operationTypeName'],
      citizenId: json['citizenId'] ?? '',
      citizenName: json['citizenName'],
      citizenPhone: json['citizenPhone'],
      companyId: json['companyId'],
      status: ServiceRequestStatus.fromValue(json['status'] ?? 0),
      statusNote: json['statusNote'],
      priority: RequestPriority.fromValue(json['priority'] ?? 1),
      details: json['details'],
      address: json['address'],
      assignedToId: json['assignedToId'],
      assignedToName: json['assignedToName'],
      estimatedCost: json['estimatedCost']?.toDouble(),
      finalCost: json['finalCost']?.toDouble(),
      requestedAt: json['requestedAt'] != null
          ? DateTime.parse(json['requestedAt'])
          : DateTime.now(),
      assignedAt: json['assignedAt'] != null
          ? DateTime.parse(json['assignedAt'])
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : null,
    );
  }
}

/// نموذج اشتراك المواطن
class CitizenSubscriptionModel {
  final String id;
  final String citizenId;
  final String? citizenName;
  final String planId;
  final String? planName;
  final double price;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;
  final bool autoRenew;
  final DateTime createdAt;

  CitizenSubscriptionModel({
    required this.id,
    required this.citizenId,
    this.citizenName,
    required this.planId,
    this.planName,
    required this.price,
    required this.startDate,
    required this.endDate,
    this.isActive = true,
    this.autoRenew = false,
    required this.createdAt,
  });

  int get daysRemaining => endDate.difference(DateTime.now()).inDays;
  bool get isExpired => DateTime.now().isAfter(endDate);
  bool get isExpiringSoon => daysRemaining <= 7 && daysRemaining >= 0;

  factory CitizenSubscriptionModel.fromJson(Map<String, dynamic> json) {
    return CitizenSubscriptionModel(
      id: json['id'] ?? '',
      citizenId: json['citizenId'] ?? '',
      citizenName: json['citizenName'],
      planId: json['planId'] ?? '',
      planName: json['planName'],
      price: (json['price'] ?? 0).toDouble(),
      startDate: json['startDate'] != null
          ? DateTime.parse(json['startDate'])
          : DateTime.now(),
      endDate: json['endDate'] != null
          ? DateTime.parse(json['endDate'])
          : DateTime.now().add(const Duration(days: 30)),
      isActive: json['isActive'] ?? true,
      autoRenew: json['autoRenew'] ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}

/// نموذج دفعة المواطن
class CitizenPaymentModel {
  final String id;
  final String citizenId;
  final String? citizenName;
  final String? subscriptionId;
  final String? requestId;
  final double amount;
  final String paymentMethod;
  final String status; // pending, success, failed
  final String? transactionId;
  final DateTime createdAt;
  final DateTime? paidAt;

  CitizenPaymentModel({
    required this.id,
    required this.citizenId,
    this.citizenName,
    this.subscriptionId,
    this.requestId,
    required this.amount,
    required this.paymentMethod,
    required this.status,
    this.transactionId,
    required this.createdAt,
    this.paidAt,
  });

  factory CitizenPaymentModel.fromJson(Map<String, dynamic> json) {
    return CitizenPaymentModel(
      id: json['id'] ?? '',
      citizenId: json['citizenId'] ?? '',
      citizenName: json['citizenName'],
      subscriptionId: json['subscriptionId'],
      requestId: json['requestId'],
      amount: (json['amount'] ?? 0).toDouble(),
      paymentMethod: json['paymentMethod'] ?? 'cash',
      status: json['status'] ?? 'pending',
      transactionId: json['transactionId'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      paidAt: json['paidAt'] != null ? DateTime.parse(json['paidAt']) : null,
    );
  }
}

/// نموذج خطة الاشتراك
class SubscriptionPlanModel {
  final String id;
  final String name;
  final String? description;
  final double price;
  final int durationDays;
  final String? features; // JSON
  final bool isActive;
  final int displayOrder;

  SubscriptionPlanModel({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    required this.durationDays,
    this.features,
    this.isActive = true,
    this.displayOrder = 0,
  });

  factory SubscriptionPlanModel.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlanModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      price: (json['price'] ?? 0).toDouble(),
      durationDays: json['durationDays'] ?? 30,
      features: json['features'],
      isActive: json['isActive'] ?? true,
      displayOrder: json['displayOrder'] ?? 0,
    );
  }
}

/// إحصائيات نظام المواطن
class CitizenPortalStats {
  final int totalCitizens;
  final int activeCitizens;
  final int totalRequests;
  final int pendingRequests;
  final int completedRequests;
  final int activeSubscriptions;
  final double totalRevenue;
  final double monthlyRevenue;

  CitizenPortalStats({
    this.totalCitizens = 0,
    this.activeCitizens = 0,
    this.totalRequests = 0,
    this.pendingRequests = 0,
    this.completedRequests = 0,
    this.activeSubscriptions = 0,
    this.totalRevenue = 0,
    this.monthlyRevenue = 0,
  });

  factory CitizenPortalStats.fromJson(Map<String, dynamic> json) {
    return CitizenPortalStats(
      totalCitizens: json['totalCitizens'] ?? 0,
      activeCitizens: json['activeCitizens'] ?? 0,
      totalRequests: json['totalRequests'] ?? 0,
      pendingRequests: json['pendingRequests'] ?? 0,
      completedRequests: json['completedRequests'] ?? 0,
      activeSubscriptions: json['activeSubscriptions'] ?? 0,
      totalRevenue: (json['totalRevenue'] ?? 0).toDouble(),
      monthlyRevenue: (json['monthlyRevenue'] ?? 0).toDouble(),
    );
  }
}
