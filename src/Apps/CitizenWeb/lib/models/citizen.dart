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
      id: json['id'] ?? json['Id'] ?? '',
      fullName: json['fullName'] ?? json['FullName'] ?? '',
      phoneNumber: json['phoneNumber'] ?? json['PhoneNumber'] ?? '',
      email: json['email'] ?? json['Email'],
      city: json['city'] ?? json['City'],
      district: json['district'] ?? json['District'],
      fullAddress: json['fullAddress'] ?? json['FullAddress'],
      profileImageUrl: json['profileImageUrl'] ?? json['ProfileImageUrl'],
      companyId: json['companyId'] ?? json['CompanyId'] ?? '',
      companyName: json['companyName'] ?? json['CompanyName'],
      companyLogo: json['companyLogo'] ?? json['CompanyLogo'],
      isActive: json['isActive'] ?? json['IsActive'] ?? true,
      language: json['language'] ?? json['Language'],
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
