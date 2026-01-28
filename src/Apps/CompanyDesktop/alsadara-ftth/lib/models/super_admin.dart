/// نموذج مدير النظام (Super Admin)
/// يحتوي على بيانات مدير النظام الرئيسي
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class SuperAdmin {
  final String id;
  final String username;
  final String passwordHash;
  final String name;
  final String? email;
  final String? phone;
  final DateTime createdAt;
  final DateTime? lastLogin;

  SuperAdmin({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.name,
    this.email,
    this.phone,
    required this.createdAt,
    this.lastLogin,
  });

  /// تحويل من Firestore
  factory SuperAdmin.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SuperAdmin(
      id: doc.id,
      username: data['username'] ?? '',
      passwordHash: data['passwordHash'] ?? '',
      name: data['name'] ?? '',
      email: data['email'],
      phone: data['phone'],
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      lastLogin: data['lastLogin'] != null
          ? (data['lastLogin'] as Timestamp).toDate()
          : null,
    );
  }

  /// تحويل إلى Map للحفظ في Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'username': username,
      'passwordHash': passwordHash,
      'name': name,
      'email': email,
      'phone': phone,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLogin': lastLogin != null ? Timestamp.fromDate(lastLogin!) : null,
    };
  }
}
