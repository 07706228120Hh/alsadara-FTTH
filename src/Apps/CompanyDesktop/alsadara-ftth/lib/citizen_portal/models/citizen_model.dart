/// نموذج المواطن من API
class CitizenModel {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String? email;
  final String? profileImageUrl;
  final String? city;
  final String? district;
  final String? fullAddress;
  final String companyId;
  final bool isActive;
  final bool isPhoneVerified;
  final bool isBanned;
  final DateTime? bannedAt;
  final String? banReason;
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
    required this.companyId,
    required this.isActive,
    required this.isPhoneVerified,
    required this.isBanned,
    this.bannedAt,
    this.banReason,
    required this.createdAt,
  });

  factory CitizenModel.fromJson(Map<String, dynamic> json) {
    return CitizenModel(
      id: json['id'] as String,
      fullName: json['fullName'] as String,
      phoneNumber: json['phoneNumber'] as String,
      email: json['email'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
      city: json['city'] as String?,
      district: json['district'] as String?,
      fullAddress: json['fullAddress'] as String?,
      companyId: json['companyId'] as String,
      isActive: json['isActive'] as bool,
      isPhoneVerified: json['isPhoneVerified'] as bool,
      isBanned: json['isBanned'] as bool,
      bannedAt: json['bannedAt'] != null
          ? DateTime.parse(json['bannedAt'] as String)
          : null,
      banReason: json['banReason'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
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
      'companyId': companyId,
      'isActive': isActive,
      'isPhoneVerified': isPhoneVerified,
      'isBanned': isBanned,
      'bannedAt': bannedAt?.toIso8601String(),
      'banReason': banReason,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
