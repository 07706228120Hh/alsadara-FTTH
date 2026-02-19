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

  static ServiceRequestStatus fromValue(dynamic value) {
    if (value is int) {
      return ServiceRequestStatus.values.firstWhere(
        (e) => e.value == value,
        orElse: () => ServiceRequestStatus.pending,
      );
    }
    if (value is String) {
      return ServiceRequestStatus.values.firstWhere(
        (e) => e.name.toLowerCase() == value.toLowerCase(),
        orElse: () => ServiceRequestStatus.pending,
      );
    }
    return ServiceRequestStatus.pending;
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

  static RequestPriority fromValue(dynamic value) {
    if (value is int) {
      return RequestPriority.values.firstWhere(
        (e) => e.value == value,
        orElse: () => RequestPriority.normal,
      );
    }
    if (value is String) {
      return RequestPriority.values.firstWhere(
        (e) => e.name.toLowerCase() == value.toLowerCase(),
        orElse: () => RequestPriority.normal,
      );
    }
    return RequestPriority.normal;
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
  final String? agentId;
  final String? agentName;
  final String? agentCode;
  final double? agentNetBalance;
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
  final List<StatusHistoryItem> statusHistory;

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
    this.agentId,
    this.agentName,
    this.agentCode,
    this.agentNetBalance,
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
    this.statusHistory = const [],
  });

  factory ServiceRequestModel.fromJson(Map<String, dynamic> json) {
    return ServiceRequestModel(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      requestNumber: json['requestNumber'] ?? json['RequestNumber'] ?? '',
      serviceId: json['serviceId'] ?? json['ServiceId'] ?? 0,
      serviceName: json['serviceNameAr'] ??
          json['ServiceNameAr'] ??
          json['serviceName'] ??
          json['ServiceName'],
      operationTypeId: json['operationTypeId'] ?? json['OperationTypeId'] ?? 0,
      operationTypeName: json['operationTypeName'] ?? json['OperationTypeName'],
      citizenId: (json['citizenId'] ?? json['CitizenId'] ?? '').toString(),
      citizenName: json['citizenName'] ?? json['CitizenName'],
      citizenPhone: json['citizenPhone'] ?? json['CitizenPhone'],
      companyId: (json['companyId'] ?? json['CompanyId'])?.toString(),
      agentId: (json['agentId'] ?? json['AgentId'])?.toString(),
      agentName: json['agentName'] ?? json['AgentName'],
      agentCode: json['agentCode'] ?? json['AgentCode'],
      agentNetBalance:
          (json['agentNetBalance'] ?? json['AgentNetBalance'])?.toDouble(),
      status:
          ServiceRequestStatus.fromValue(json['status'] ?? json['Status'] ?? 0),
      statusNote: json['statusNote'] ?? json['StatusNote'],
      priority:
          RequestPriority.fromValue(json['priority'] ?? json['Priority'] ?? 1),
      details: json['details'] ?? json['Details'],
      address: json['address'] ?? json['Address'],
      assignedToId: (json['assignedToId'] ?? json['AssignedToId'])?.toString(),
      assignedToName: json['assignedToName'] ?? json['AssignedToName'],
      estimatedCost:
          (json['estimatedCost'] ?? json['EstimatedCost'])?.toDouble(),
      finalCost: (json['finalCost'] ?? json['FinalCost'])?.toDouble(),
      requestedAt: json['requestedAt'] != null
          ? DateTime.parse(json['requestedAt'])
          : json['RequestedAt'] != null
              ? DateTime.parse(json['RequestedAt'])
              : json['createdAt'] != null
                  ? DateTime.parse(json['createdAt'])
                  : json['CreatedAt'] != null
                      ? DateTime.parse(json['CreatedAt'])
                      : DateTime.now(),
      assignedAt: _parseDate(json['assignedAt'] ?? json['AssignedAt']),
      completedAt: _parseDate(json['completedAt'] ?? json['CompletedAt']),
      statusHistory: (json['statusHistory'] ?? json['StatusHistory']) != null
          ? (json['statusHistory'] ?? json['StatusHistory'] as List)
              .map<StatusHistoryItem>(
                  (h) => StatusHistoryItem.fromJson(h as Map<String, dynamic>))
              .toList()
          : [],
    );
  }

  /// نسخة جديدة مع سجل الحالات
  ServiceRequestModel copyWithHistory(List<StatusHistoryItem> history) {
    return ServiceRequestModel(
      id: id,
      requestNumber: requestNumber,
      serviceId: serviceId,
      serviceName: serviceName,
      operationTypeId: operationTypeId,
      operationTypeName: operationTypeName,
      citizenId: citizenId,
      citizenName: citizenName,
      citizenPhone: citizenPhone,
      companyId: companyId,
      agentId: agentId,
      agentName: agentName,
      agentCode: agentCode,
      agentNetBalance: agentNetBalance,
      status: status,
      statusNote: statusNote,
      priority: priority,
      details: details,
      address: address,
      assignedToId: assignedToId,
      assignedToName: assignedToName,
      estimatedCost: estimatedCost,
      finalCost: finalCost,
      requestedAt: requestedAt,
      assignedAt: assignedAt,
      completedAt: completedAt,
      statusHistory: history,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.parse(value.toString());
  }
}

/// سجل تغيير حالة الطلب
class StatusHistoryItem {
  final String fromStatus;
  final String toStatus;
  final String? note;
  final String? changedBy;
  final DateTime changedAt;

  StatusHistoryItem({
    required this.fromStatus,
    required this.toStatus,
    this.note,
    this.changedBy,
    required this.changedAt,
  });

  factory StatusHistoryItem.fromJson(Map<String, dynamic> json) {
    return StatusHistoryItem(
      fromStatus: (json['fromStatus'] ?? json['FromStatus'] ?? '').toString(),
      toStatus: (json['toStatus'] ?? json['ToStatus'] ?? '').toString(),
      note: json['note'] ?? json['Note'],
      changedBy: json['changedBy'] ?? json['ChangedBy'],
      changedAt: json['changedAt'] != null
          ? DateTime.parse(json['changedAt'].toString())
          : json['ChangedAt'] != null
              ? DateTime.parse(json['ChangedAt'].toString())
              : DateTime.now(),
    );
  }

  /// ترجمة اسم الحالة
  static String statusNameAr(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'جديد';
      case 'reviewing':
        return 'قيد المراجعة';
      case 'approved':
        return 'موافق عليه';
      case 'assigned':
        return 'تم التعيين';
      case 'inprogress':
        return 'قيد التنفيذ';
      case 'completed':
        return 'مكتمل';
      case 'cancelled':
        return 'ملغي';
      case 'rejected':
        return 'مرفوض';
      case 'onhold':
        return 'معلق';
      default:
        return status;
    }
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
