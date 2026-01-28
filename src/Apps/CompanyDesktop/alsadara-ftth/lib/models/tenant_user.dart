/// نموذج مستخدم الشركة
/// يحتوي على بيانات المستخدم وصلاحياته
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class TenantUser {
  final String id;
  final String tenantId;
  final String username;
  final String passwordHash;
  final String? plainPassword; // كلمة المرور الأصلية للعرض
  final String fullName;
  final String? email;
  final String? phone;
  final UserRole role;
  final String? code;
  final String? department;
  final String? center;
  final String? salary;
  final bool isActive;
  final DateTime createdAt;
  final String createdBy;
  final DateTime? lastLogin;
  final Map<String, bool> firstSystemPermissions;
  final Map<String, bool> secondSystemPermissions;

  TenantUser({
    required this.id,
    required this.tenantId,
    required this.username,
    required this.passwordHash,
    this.plainPassword,
    required this.fullName,
    this.email,
    this.phone,
    required this.role,
    this.code,
    this.department,
    this.center,
    this.salary,
    required this.isActive,
    required this.createdAt,
    required this.createdBy,
    this.lastLogin,
    required this.firstSystemPermissions,
    required this.secondSystemPermissions,
  });

  /// هل هو مدير الشركة؟
  bool get isAdmin => role == UserRole.admin;

  /// هل هو مدير أو مشرف؟
  bool get isManagerOrAbove =>
      role == UserRole.admin || role == UserRole.manager;

  /// تحويل من Firestore
  factory TenantUser.fromFirestore(DocumentSnapshot doc, String tenantId) {
    final data = doc.data() as Map<String, dynamic>;
    return TenantUser(
      id: doc.id,
      tenantId: tenantId,
      username: data['username'] ?? '',
      passwordHash: data['passwordHash'] ?? '',
      plainPassword: data['plainPassword'],
      fullName: data['fullName'] ?? '',
      email: data['email'],
      phone: data['phone'],
      role: UserRole.fromString(data['role'] ?? 'employee'),
      code: data['code'],
      department: data['department'],
      center: data['center'],
      salary: data['salary'],
      isActive: data['isActive'] ?? true,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      lastLogin: data['lastLogin'] != null
          ? (data['lastLogin'] as Timestamp).toDate()
          : null,
      firstSystemPermissions: _parsePermissions(data['firstSystemPermissions']),
      secondSystemPermissions:
          _parsePermissions(data['secondSystemPermissions']),
    );
  }

  static Map<String, bool> _parsePermissions(dynamic data) {
    if (data == null) return {};
    if (data is Map) {
      return Map<String, bool>.from(
        data.map((key, value) => MapEntry(key.toString(), value == true)),
      );
    }
    return {};
  }

  /// تحويل إلى Map للحفظ في Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'username': username,
      'passwordHash': passwordHash,
      'plainPassword': plainPassword,
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'role': role.value,
      'code': code,
      'department': department,
      'center': center,
      'salary': salary,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'lastLogin': lastLogin != null ? Timestamp.fromDate(lastLogin!) : null,
      'firstSystemPermissions': firstSystemPermissions,
      'secondSystemPermissions': secondSystemPermissions,
    };
  }

  /// نسخة معدلة
  TenantUser copyWith({
    String? id,
    String? tenantId,
    String? username,
    String? passwordHash,
    String? plainPassword,
    String? fullName,
    String? email,
    String? phone,
    UserRole? role,
    String? code,
    String? department,
    String? center,
    String? salary,
    bool? isActive,
    DateTime? createdAt,
    String? createdBy,
    DateTime? lastLogin,
    Map<String, bool>? firstSystemPermissions,
    Map<String, bool>? secondSystemPermissions,
  }) {
    return TenantUser(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      plainPassword: plainPassword ?? this.plainPassword,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      code: code ?? this.code,
      department: department ?? this.department,
      center: center ?? this.center,
      salary: salary ?? this.salary,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      lastLogin: lastLogin ?? this.lastLogin,
      firstSystemPermissions:
          firstSystemPermissions ?? this.firstSystemPermissions,
      secondSystemPermissions:
          secondSystemPermissions ?? this.secondSystemPermissions,
    );
  }
}

/// أدوار المستخدمين
enum UserRole {
  admin('admin', 'مدير'),
  manager('manager', 'مشرف'),
  technicalLeader('technical_leader', 'ليدر فني'),
  technician('technician', 'فني'),
  employee('employee', 'موظف'),
  viewer('viewer', 'مشاهد');

  final String value;
  final String arabicName;
  const UserRole(this.value, this.arabicName);

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (role) => role.value == value,
      orElse: () => UserRole.employee,
    );
  }
}

/// صلاحيات النظام الأول الافتراضية
const Map<String, bool> defaultFirstSystemPermissions = {
  'attendance': false,
  'agent': false,
  'tasks': false,
  'zones': false,
  'ai_search': false,
};

/// صلاحيات النظام الثاني الافتراضية
const Map<String, bool> defaultSecondSystemPermissions = {
  'users': false,
  'subscriptions': false,
  'tasks': false,
  'zones': false,
  'accounts': false,
  'account_records': false,
  'export': false,
  'agents': false,
  'google_sheets': false,
  'whatsapp': false,
  'wallet_balance': false,
  'expiring_soon': false,
  'quick_search': false,
  'technicians': false,
  'transactions': false,
  'notifications': false,
  'audit_logs': false,
  'whatsapp_link': false,
  'whatsapp_settings': false,
  'plans_bundles': false,
  'whatsapp_business_api': false,
  'whatsapp_bulk_sender': false,
  'whatsapp_conversations_fab': false,
  'local_storage': false,
  'local_storage_import': false,
};

/// صلاحيات كاملة للمدير
Map<String, bool> get adminFirstSystemPermissions =>
    defaultFirstSystemPermissions.map((key, _) => MapEntry(key, true));

Map<String, bool> get adminSecondSystemPermissions =>
    defaultSecondSystemPermissions.map((key, _) => MapEntry(key, true));
