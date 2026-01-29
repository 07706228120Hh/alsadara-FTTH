class Citizen {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String? email;
  final String? city;
  final String? district;
  final String? fullAddress;
  final String? profileImageUrl;
  final String companyId;
  final String? companyName;
  final String? companyLogo;
  final bool isActive;
  final String? language;

  Citizen({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    this.email,
    this.city,
    this.district,
    this.fullAddress,
    this.profileImageUrl,
    required this.companyId,
    this.companyName,
    this.companyLogo,
    this.isActive = true,
    this.language,
  });

  factory Citizen.fromJson(Map<String, dynamic> json) {
    return Citizen(
      id: json['id'] ?? '',
      fullName: json['fullName'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      email: json['email'],
      city: json['city'],
      district: json['district'],
      fullAddress: json['fullAddress'],
      profileImageUrl: json['profileImageUrl'],
      companyId: json['companyId'] ?? '',
      companyName: json['companyName'],
      companyLogo: json['companyLogo'],
      isActive: json['isActive'] ?? true,
      language: json['language'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'email': email,
      'city': city,
      'district': district,
      'fullAddress': fullAddress,
      'profileImageUrl': profileImageUrl,
      'companyId': companyId,
      'companyName': companyName,
      'companyLogo': companyLogo,
      'isActive': isActive,
      'language': language,
    };
  }
}
