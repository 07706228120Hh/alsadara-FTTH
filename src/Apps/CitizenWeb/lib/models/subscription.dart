class InternetPlan {
  final String id;
  final String name;
  final String nameAr;
  final String? description;
  final int speedMbps;
  final int? dataLimitGB;
  final double monthlyPrice;
  final double? installationFee;
  final String? features;
  final bool isActive;
  final bool isFeatured;

  InternetPlan({
    required this.id,
    required this.name,
    required this.nameAr,
    this.description,
    required this.speedMbps,
    this.dataLimitGB,
    required this.monthlyPrice,
    this.installationFee,
    this.features,
    this.isActive = true,
    this.isFeatured = false,
  });

  factory InternetPlan.fromJson(Map<String, dynamic> json) {
    return InternetPlan(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      nameAr: json['nameAr'] ?? '',
      description: json['description'],
      speedMbps: json['speedMbps'] ?? 0,
      dataLimitGB: json['dataLimitGB'],
      monthlyPrice: (json['monthlyPrice'] ?? 0).toDouble(),
      installationFee: json['installationFee']?.toDouble(),
      features: json['features'],
      isActive: json['isActive'] ?? true,
      isFeatured: json['isFeatured'] ?? false,
    );
  }
}

class Subscription {
  final String id;
  final String subscriptionNumber;
  final String planName;
  final int planSpeed;
  final String companyName;
  final String? companyLogo;
  final String status;
  final String statusAr;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime? nextRenewalDate;
  final bool autoRenew;
  final double agreedPrice;
  final double totalPaid;
  final double outstandingBalance;

  Subscription({
    required this.id,
    required this.subscriptionNumber,
    required this.planName,
    required this.planSpeed,
    required this.companyName,
    this.companyLogo,
    required this.status,
    required this.statusAr,
    required this.startDate,
    this.endDate,
    this.nextRenewalDate,
    required this.autoRenew,
    required this.agreedPrice,
    required this.totalPaid,
    required this.outstandingBalance,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'] ?? '',
      subscriptionNumber: json['subscriptionNumber'] ?? '',
      planName: json['planName'] ?? '',
      planSpeed: json['planSpeed'] ?? 0,
      companyName: json['companyName'] ?? '',
      companyLogo: json['companyLogo'],
      status: json['status'] ?? '',
      statusAr: json['statusAr'] ?? '',
      startDate: DateTime.parse(json['startDate']),
      endDate: json['endDate'] != null ? DateTime.parse(json['endDate']) : null,
      nextRenewalDate: json['nextRenewalDate'] != null
          ? DateTime.parse(json['nextRenewalDate'])
          : null,
      autoRenew: json['autoRenew'] ?? false,
      agreedPrice: (json['agreedPrice'] ?? 0).toDouble(),
      totalPaid: (json['totalPaid'] ?? 0).toDouble(),
      outstandingBalance: (json['outstandingBalance'] ?? 0).toDouble(),
    );
  }
}
