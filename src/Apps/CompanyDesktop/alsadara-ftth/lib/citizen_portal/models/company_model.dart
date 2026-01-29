/// نموذج الشركة من API (متوافق مع CompanyDto في .NET)
class CompanyModel {
  final String id;
  final String name;
  final String code;
  final String? email;
  final String? phone;
  final String? address;
  final String? logoUrl;
  final bool isActive;
  final String? suspensionReason;
  final DateTime subscriptionStartDate;
  final DateTime subscriptionEndDate;
  final String subscriptionPlan;
  final int maxUsers;
  final int daysRemaining;
  final bool isExpired;
  final bool isLinkedToCitizenPortal;
  final DateTime? linkedToCitizenPortalAt;
  final DateTime createdAt;

  CompanyModel({
    required this.id,
    required this.name,
    required this.code,
    this.email,
    this.phone,
    this.address,
    this.logoUrl,
    required this.isActive,
    this.suspensionReason,
    required this.subscriptionStartDate,
    required this.subscriptionEndDate,
    required this.subscriptionPlan,
    required this.maxUsers,
    required this.daysRemaining,
    required this.isExpired,
    required this.isLinkedToCitizenPortal,
    this.linkedToCitizenPortalAt,
    required this.createdAt,
  });

  factory CompanyModel.fromJson(Map<String, dynamic> json) {
    return CompanyModel(
      id: json['id'] as String,
      name: json['name'] as String,
      code: json['code'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      logoUrl: json['logoUrl'] as String?,
      isActive: json['isActive'] as bool,
      suspensionReason: json['suspensionReason'] as String?,
      subscriptionStartDate:
          DateTime.parse(json['subscriptionStartDate'] as String),
      subscriptionEndDate:
          DateTime.parse(json['subscriptionEndDate'] as String),
      subscriptionPlan: json['subscriptionPlan'] as String,
      maxUsers: json['maxUsers'] as int,
      daysRemaining: json['daysRemaining'] as int,
      isExpired: json['isExpired'] as bool,
      isLinkedToCitizenPortal: json['isLinkedToCitizenPortal'] as bool,
      linkedToCitizenPortalAt: json['linkedToCitizenPortalAt'] != null
          ? DateTime.parse(json['linkedToCitizenPortalAt'] as String)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'email': email,
      'phone': phone,
      'address': address,
      'logoUrl': logoUrl,
      'isActive': isActive,
      'suspensionReason': suspensionReason,
      'subscriptionStartDate': subscriptionStartDate.toIso8601String(),
      'subscriptionEndDate': subscriptionEndDate.toIso8601String(),
      'subscriptionPlan': subscriptionPlan,
      'maxUsers': maxUsers,
      'daysRemaining': daysRemaining,
      'isExpired': isExpired,
      'isLinkedToCitizenPortal': isLinkedToCitizenPortal,
      'linkedToCitizenPortalAt': linkedToCitizenPortalAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
