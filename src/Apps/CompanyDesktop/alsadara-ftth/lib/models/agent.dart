/// نموذج الوكيل
/// يحتوي على جميع بيانات الوكيل ومحاسبته
library;

/// نوع الوكيل
enum AgentType {
  privateAgent, // خاص
  publicAgent; // عام

  static AgentType fromInt(int value) {
    switch (value) {
      case 0:
        return privateAgent;
      case 1:
        return publicAgent;
      default:
        return privateAgent;
    }
  }

  int get intValue {
    switch (this) {
      case privateAgent:
        return 0;
      case publicAgent:
        return 1;
    }
  }

  String get displayName {
    switch (this) {
      case privateAgent:
        return 'وكيل خاص';
      case publicAgent:
        return 'وكيل عام';
    }
  }
}

/// حالة الوكيل
enum AgentStatus {
  active, // نشط
  suspended, // معلق
  banned, // محظور
  inactive; // غير مفعل

  static AgentStatus fromInt(int value) {
    switch (value) {
      case 0:
        return active;
      case 1:
        return suspended;
      case 2:
        return banned;
      case 3:
        return inactive;
      default:
        return active;
    }
  }

  static AgentStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'active':
        return active;
      case 'suspended':
        return suspended;
      case 'banned':
        return banned;
      case 'inactive':
        return inactive;
      default:
        return active;
    }
  }

  int get intValue {
    switch (this) {
      case active:
        return 0;
      case suspended:
        return 1;
      case banned:
        return 2;
      case inactive:
        return 3;
    }
  }

  String get displayName {
    switch (this) {
      case active:
        return 'نشط';
      case suspended:
        return 'معلق';
      case banned:
        return 'محظور';
      case inactive:
        return 'غير مفعل';
    }
  }
}

/// نوع المعاملة المالية
enum TransactionType {
  charge, // أجور
  payment, // تسديد
  discount, // خصم
  adjustment; // تعديل

  static TransactionType fromInt(int value) {
    switch (value) {
      case 0:
        return charge;
      case 1:
        return payment;
      case 2:
        return discount;
      case 3:
        return adjustment;
      default:
        return charge;
    }
  }

  String get displayName {
    switch (this) {
      case charge:
        return 'أجور';
      case payment:
        return 'تسديد';
      case discount:
        return 'خصم';
      case adjustment:
        return 'تعديل';
    }
  }
}

/// فئة المعاملة
enum TransactionCategory {
  newSubscription,
  renewalSubscription,
  maintenance,
  billCollection,
  installation,
  serviceTransfer,
  cashPayment,
  bankTransfer,
  other;

  static TransactionCategory fromInt(int value) {
    switch (value) {
      case 0:
        return newSubscription;
      case 1:
        return renewalSubscription;
      case 2:
        return maintenance;
      case 3:
        return billCollection;
      case 4:
        return installation;
      case 5:
        return serviceTransfer;
      case 6:
        return cashPayment;
      case 7:
        return bankTransfer;
      default:
        return other;
    }
  }

  int get intValue {
    switch (this) {
      case newSubscription:
        return 0;
      case renewalSubscription:
        return 1;
      case maintenance:
        return 2;
      case billCollection:
        return 3;
      case installation:
        return 4;
      case serviceTransfer:
        return 5;
      case cashPayment:
        return 6;
      case bankTransfer:
        return 7;
      case other:
        return 99;
    }
  }

  String get displayName {
    switch (this) {
      case newSubscription:
        return 'تسجيل مشترك جديد';
      case renewalSubscription:
        return 'تجديد اشتراك';
      case maintenance:
        return 'صيانة';
      case billCollection:
        return 'تحصيل فواتير';
      case installation:
        return 'تركيب جديد';
      case serviceTransfer:
        return 'نقل خدمة';
      case cashPayment:
        return 'تسديد نقدي';
      case bankTransfer:
        return 'تحويل بنكي';
      case other:
        return 'أخرى';
    }
  }
}

/// ============================
/// نموذج الوكيل
/// ============================
class AgentModel {
  final String id;
  final String agentCode;
  final String name;
  final AgentType type;
  final String phoneNumber;
  final String? email;
  final String? city;
  final String? area;
  final String? fullAddress;
  final double? latitude;
  final double? longitude;
  final String? pageId;
  final String companyId;
  final String? companyName;
  final AgentStatus status;
  final String? profileImageUrl;
  final String? notes;
  final String? plainPassword;
  final DateTime? lastLoginAt;
  final double totalCharges;
  final double totalPayments;
  final double netBalance;
  final DateTime createdAt;
  final DateTime? updatedAt;

  AgentModel({
    required this.id,
    required this.agentCode,
    required this.name,
    required this.type,
    required this.phoneNumber,
    this.email,
    this.city,
    this.area,
    this.fullAddress,
    this.latitude,
    this.longitude,
    this.pageId,
    required this.companyId,
    this.companyName,
    required this.status,
    this.profileImageUrl,
    this.notes,
    this.plainPassword,
    this.lastLoginAt,
    this.totalCharges = 0,
    this.totalPayments = 0,
    this.netBalance = 0,
    required this.createdAt,
    this.updatedAt,
  });

  factory AgentModel.fromJson(Map<String, dynamic> json) {
    return AgentModel(
      id: json['id'] ?? '',
      agentCode: json['agentCode'] ?? '',
      name: json['name'] ?? '',
      type: json['typeValue'] != null
          ? AgentType.fromInt(json['typeValue'])
          : AgentType.privateAgent,
      phoneNumber: json['phoneNumber'] ?? '',
      email: json['email'],
      city: json['city'],
      area: json['area'],
      fullAddress: json['fullAddress'],
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      pageId: json['pageId'],
      companyId: json['companyId'] ?? '',
      companyName: json['companyName'],
      status: json['statusValue'] != null
          ? AgentStatus.fromInt(json['statusValue'])
          : AgentStatus.fromString(json['status'] ?? 'active'),
      profileImageUrl: json['profileImageUrl'],
      notes: json['notes'],
      plainPassword: json['plainPassword'],
      lastLoginAt: json['lastLoginAt'] != null
          ? DateTime.tryParse(json['lastLoginAt'])
          : null,
      totalCharges: (json['totalCharges'] ?? 0).toDouble(),
      totalPayments: (json['totalPayments'] ?? 0).toDouble(),
      netBalance: (json['netBalance'] ?? 0).toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'agentCode': agentCode,
      'name': name,
      'type': type.intValue,
      'phoneNumber': phoneNumber,
      'email': email,
      'city': city,
      'area': area,
      'fullAddress': fullAddress,
      'latitude': latitude,
      'longitude': longitude,
      'pageId': pageId,
      'companyId': companyId,
      'status': status.intValue,
      'notes': notes,
      'plainPassword': plainPassword,
      'profileImageUrl': profileImageUrl,
    };
  }

  /// هل عليه ديون؟
  bool get hasDebt => netBalance > 0;

  /// هل له رصيد إيجابي (دائن)؟
  bool get hasCredit => netBalance < 0;

  /// الرصيد المعروض (بالقيمة المطلقة)
  double get displayBalance => netBalance.abs();

  AgentModel copyWith({
    String? name,
    AgentType? type,
    String? phoneNumber,
    String? email,
    String? city,
    String? area,
    String? fullAddress,
    double? latitude,
    double? longitude,
    String? pageId,
    AgentStatus? status,
    String? notes,
    String? profileImageUrl,
  }) {
    return AgentModel(
      id: id,
      agentCode: agentCode,
      name: name ?? this.name,
      type: type ?? this.type,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      city: city ?? this.city,
      area: area ?? this.area,
      fullAddress: fullAddress ?? this.fullAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      pageId: pageId ?? this.pageId,
      companyId: companyId,
      companyName: companyName,
      status: status ?? this.status,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      notes: notes ?? this.notes,
      plainPassword: plainPassword,
      lastLoginAt: lastLoginAt,
      totalCharges: totalCharges,
      totalPayments: totalPayments,
      netBalance: netBalance,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// ============================
/// نموذج المعاملة المالية
/// ============================
class AgentTransactionModel {
  final int id;
  final String agentId;
  final TransactionType type;
  final TransactionCategory category;
  final double amount;
  final double balanceAfter;
  final String description;
  final String? referenceNumber;
  final String? serviceRequestId;
  final String? citizenId;
  final String? createdById;
  final String? notes;
  final String? journalEntryId;
  final String? journalEntryNumber;
  final DateTime createdAt;

  AgentTransactionModel({
    required this.id,
    required this.agentId,
    required this.type,
    required this.category,
    required this.amount,
    required this.balanceAfter,
    required this.description,
    this.referenceNumber,
    this.serviceRequestId,
    this.citizenId,
    this.createdById,
    this.notes,
    this.journalEntryId,
    this.journalEntryNumber,
    required this.createdAt,
  });

  factory AgentTransactionModel.fromJson(Map<String, dynamic> json) {
    return AgentTransactionModel(
      id: json['id'] ?? 0,
      agentId: json['agentId'] ?? '',
      type: TransactionType.fromInt(json['typeValue'] ?? 0),
      category: TransactionCategory.fromInt(json['categoryValue'] ?? 99),
      amount: (json['amount'] ?? 0).toDouble(),
      balanceAfter: (json['balanceAfter'] ?? 0).toDouble(),
      description: json['description'] ?? '',
      referenceNumber: json['referenceNumber'],
      serviceRequestId: json['serviceRequestId'],
      citizenId: json['citizenId'],
      createdById: json['createdById'],
      notes: json['notes'],
      journalEntryId: json['journalEntryId']?.toString(),
      journalEntryNumber: json['journalEntryNumber']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  /// هل هي عملية خصم من الوكيل (أجور)؟
  bool get isCharge => type == TransactionType.charge;

  /// هل هي عملية تسديد؟
  bool get isPayment => type == TransactionType.payment;
}

/// ============================
/// نموذج ملخص المحاسبة
/// ============================
class AgentAccountingSummary {
  final int totalAgents;
  final int activeAgents;
  final double totalCharges;
  final double totalPayments;
  final double totalNetBalance;
  final int agentsWithDebt;
  final int agentsWithCredit;

  AgentAccountingSummary({
    required this.totalAgents,
    required this.activeAgents,
    required this.totalCharges,
    required this.totalPayments,
    required this.totalNetBalance,
    required this.agentsWithDebt,
    required this.agentsWithCredit,
  });

  factory AgentAccountingSummary.fromJson(Map<String, dynamic> json) {
    return AgentAccountingSummary(
      totalAgents: json['totalAgents'] ?? 0,
      activeAgents: json['activeAgents'] ?? 0,
      totalCharges: (json['totalCharges'] ?? 0).toDouble(),
      totalPayments: (json['totalPayments'] ?? 0).toDouble(),
      totalNetBalance: (json['totalNetBalance'] ?? 0).toDouble(),
      agentsWithDebt: json['agentsWithDebt'] ?? 0,
      agentsWithCredit: json['agentsWithCredit'] ?? 0,
    );
  }
}
