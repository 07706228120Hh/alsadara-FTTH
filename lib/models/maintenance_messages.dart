class MaintenanceMessages {
  final String openTaskMessage;
  final String inProgressMessage;
  final String completedMessage;
  final String cancelledMessage;
  final String defaultMessage;
  final String supportPhone;
  final String companyName;
  final DateTime lastUpdated;
  final String updatedBy;

  MaintenanceMessages({
    required this.openTaskMessage,
    required this.inProgressMessage,
    required this.completedMessage,
    required this.cancelledMessage,
    required this.defaultMessage,
    required this.supportPhone,
    required this.companyName,
    required this.lastUpdated,
    required this.updatedBy,
  });

  /// القيم الافتراضية للرسائل
  factory MaintenanceMessages.defaultMessages() {
    return MaintenanceMessages(
      openTaskMessage: '''
🔄 المهمة قيد المراجعة وسيتم التواصل معكم قريباً لتحديد موعد الصيانة.

للاستفسار يرجى الاتصال على: 07801234567''',
      inProgressMessage: '''
⚡ المهمة قيد التنفيذ حالياً. فريق الصيانة يعمل على حل المشكلة.

في حالة وجود أي استفسار، يرجى التواصل مع الفني المختص.''',
      completedMessage: '''
✅ تم إنجاز المهمة بنجاح!

نرجو التأكد من عمل الخدمة بشكل طبيعي. في حالة وجود أي مشاكل أخرى، يرجى التواصل معنا.''',
      cancelledMessage: '''
❌ تم إلغاء المهمة.

في حالة الحاجة لإعادة فتح التذكرة أو وجود استفسارات، يرجى التواصل معنا.''',
      defaultMessage: '''
📞 للاستفسار أو المتابعة، يرجى التواصل مع فريق الدعم الفني.''',
      supportPhone: '07801234567',
      companyName: 'شركة الألياف البصرية',
      lastUpdated: DateTime.now(),
      updatedBy: 'النظام',
    );
  }

  /// تحويل إلى Map للحفظ
  Map<String, dynamic> toMap() {
    return {
      'openTaskMessage': openTaskMessage,
      'inProgressMessage': inProgressMessage,
      'completedMessage': completedMessage,
      'cancelledMessage': cancelledMessage,
      'defaultMessage': defaultMessage,
      'supportPhone': supportPhone,
      'companyName': companyName,
      'lastUpdated': lastUpdated.toIso8601String(),
      'updatedBy': updatedBy,
    };
  }

  /// إنشاء من Map
  factory MaintenanceMessages.fromMap(Map<String, dynamic> map) {
    return MaintenanceMessages(
      openTaskMessage: map['openTaskMessage'] ?? '',
      inProgressMessage: map['inProgressMessage'] ?? '',
      completedMessage: map['completedMessage'] ?? '',
      cancelledMessage: map['cancelledMessage'] ?? '',
      defaultMessage: map['defaultMessage'] ?? '',
      supportPhone: map['supportPhone'] ?? '07801234567',
      companyName: map['companyName'] ?? 'شركة الألياف البصرية',
      lastUpdated: DateTime.parse(map['lastUpdated']),
      updatedBy: map['updatedBy'] ?? 'غير معروف',
    );
  }

  /// نسخ مع تعديلات
  MaintenanceMessages copyWith({
    String? openTaskMessage,
    String? inProgressMessage,
    String? completedMessage,
    String? cancelledMessage,
    String? defaultMessage,
    String? supportPhone,
    String? companyName,
    DateTime? lastUpdated,
    String? updatedBy,
  }) {
    return MaintenanceMessages(
      openTaskMessage: openTaskMessage ?? this.openTaskMessage,
      inProgressMessage: inProgressMessage ?? this.inProgressMessage,
      completedMessage: completedMessage ?? this.completedMessage,
      cancelledMessage: cancelledMessage ?? this.cancelledMessage,
      defaultMessage: defaultMessage ?? this.defaultMessage,
      supportPhone: supportPhone ?? this.supportPhone,
      companyName: companyName ?? this.companyName,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  /// الحصول على الرسالة حسب حالة المهمة
  String getMessageForStatus(String status) {
    switch (status) {
      case 'مفتوحة':
        return openTaskMessage;
      case 'قيد التنفيذ':
        return inProgressMessage;
      case 'مكتملة':
        return completedMessage;
      case 'ملغية':
        return cancelledMessage;
      default:
        return defaultMessage;
    }
  }
}
