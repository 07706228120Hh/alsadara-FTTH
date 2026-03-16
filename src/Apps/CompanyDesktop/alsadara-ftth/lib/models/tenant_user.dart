/// نموذج مستخدم الشركة
/// يحتوي على بيانات المستخدم وصلاحياته
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../permissions/permission_registry.dart';

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
  final Map<String, Map<String, bool>> firstSystemPermissionsV2;
  final Map<String, Map<String, bool>> secondSystemPermissionsV2;

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
    required this.firstSystemPermissionsV2,
    required this.secondSystemPermissionsV2,
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
      firstSystemPermissionsV2: _parsePermissionsV2(
        data['firstSystemPermissions'],
        PermissionRegistry.firstSystem,
      ),
      secondSystemPermissionsV2: _parsePermissionsV2(
        data['secondSystemPermissions'],
        PermissionRegistry.secondSystem,
      ),
    );
  }

  /// تحليل صلاحيات V2 مع توافق V1
  /// إذا كانت البيانات بصيغة V1 (flat bool)، يتم تحويلها إلى V2
  /// إذا كانت بصيغة V2 (nested map)، تُستخدم مباشرة
  static Map<String, Map<String, bool>> _parsePermissionsV2(
    dynamic data,
    List<PermissionEntry> registry,
  ) {
    if (data == null) return {};
    if (data is! Map) return {};

    final result = <String, Map<String, bool>>{};

    for (final entry in data.entries) {
      final key = entry.key.toString();
      final value = entry.value;

      if (value is Map) {
        // V2 format: nested map of actions
        result[key] = Map<String, bool>.from(
          value.map((k, v) => MapEntry(k.toString(), v == true)),
        );
      } else if (value is bool) {
        // V1 format: flat bool — convert to V2 (all actions = that bool value)
        final registryEntry = PermissionRegistry.findByKey(key);
        final actions =
            registryEntry?.allowedActions ?? PermissionRegistry.getAllowedActions(key);
        result[key] = {for (final action in actions) action: value};
      }
    }

    return result;
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
      'firstSystemPermissions': firstSystemPermissionsV2,
      'secondSystemPermissions': secondSystemPermissionsV2,
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
    Map<String, Map<String, bool>>? firstSystemPermissionsV2,
    Map<String, Map<String, bool>>? secondSystemPermissionsV2,
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
      firstSystemPermissionsV2:
          firstSystemPermissionsV2 ?? this.firstSystemPermissionsV2,
      secondSystemPermissionsV2:
          secondSystemPermissionsV2 ?? this.secondSystemPermissionsV2,
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

/// بناء صلاحيات V2 الافتراضية (جميعها مغلقة) للنظام الأول
Map<String, Map<String, bool>> buildDefaultFirstSystemPermissionsV2() {
  final result = <String, Map<String, bool>>{};
  for (final entry in PermissionRegistry.firstSystem) {
    final actions = entry.allowedActions ?? PermissionRegistry.getAllowedActions(entry.key);
    result[entry.key] = {for (final a in actions) a: false};
  }
  return result;
}

/// بناء صلاحيات V2 الافتراضية (جميعها مغلقة) للنظام الثاني
Map<String, Map<String, bool>> buildDefaultSecondSystemPermissionsV2() {
  final result = <String, Map<String, bool>>{};
  for (final entry in PermissionRegistry.secondSystem) {
    final actions = entry.allowedActions ?? PermissionRegistry.getAllowedActions(entry.key);
    result[entry.key] = {for (final a in actions) a: false};
  }
  return result;
}

/// بناء صلاحيات V2 كاملة (للمدير) للنظام الأول
Map<String, Map<String, bool>> buildAdminFirstSystemPermissionsV2() {
  final result = <String, Map<String, bool>>{};
  for (final entry in PermissionRegistry.firstSystem) {
    final actions = entry.allowedActions ?? PermissionRegistry.getAllowedActions(entry.key);
    result[entry.key] = {for (final a in actions) a: true};
  }
  return result;
}

/// بناء صلاحيات V2 كاملة (للمدير) للنظام الثاني
Map<String, Map<String, bool>> buildAdminSecondSystemPermissionsV2() {
  final result = <String, Map<String, bool>>{};
  for (final entry in PermissionRegistry.secondSystem) {
    final actions = entry.allowedActions ?? PermissionRegistry.getAllowedActions(entry.key);
    result[entry.key] = {for (final a in actions) a: true};
  }
  return result;
}
