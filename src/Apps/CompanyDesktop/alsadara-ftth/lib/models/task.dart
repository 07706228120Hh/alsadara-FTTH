import 'package:intl/intl.dart';

class Task {
  final String id; // معرف المهمة
  final String title; // عنوان المهمة
  final String status; // حالة المهمة (مفتوحة، قيد التنفيذ، مكتملة، ملغية)
  final String department; // القسم المسؤول عن المهمة
  final String leader; // الليدر المسؤول عن المهمة
  final String technician; // الفني المسؤول عن المهمة
  final String username; // اسم المستخدم الذي أضاف المهمة
  final String phone; // رقم هاتف المستخدم
  final String fbg; // FBG المرتبط بالمهمة
  final String fat; // FAT المرتبط بالمهمة
  final String location; // موقع المهمة
  final String notes; // ملاحظات إضافية
  final DateTime createdAt; // تاريخ ووقت إنشاء المهمة (مطلوب دائمًا)
  final DateTime?
      closedAt; // تاريخ ووقت إغلاق المهمة (يمكن أن يكون null في البداية)
  final String summary; // ملخص المهمة
  final String priority; // أولوية المهمة (منخفض، متوسط، عالي، عاجل)
  final List<String> agents; // الوكلاء المرتبطين بالمهمة
  final List<StatusHistory> statusHistory; // سجل حالة المهمة
  final String createdBy; // الشخص الذي أنشأ المهمة
  final String amount; // المبلغ المرتبط بالمهمة (تمت إضافته)
  final String technicianPhone; // رقم هاتف الفني (العمود T)

  /// **البناء الأساسي لمهمة جديدة**
  Task({
    required this.id,
    required this.title,
    required this.status,
    required this.department,
    required this.leader,
    required this.technician,
    required this.username,
    required this.phone,
    required this.fbg,
    required this.fat,
    required this.location,
    required this.notes,
    required this.createdAt, // مطلوب دائمًا
    this.closedAt, // يمكن أن يكون null في البداية
    required this.summary,
    required this.priority,
    required this.agents,
    required this.statusHistory,
    required this.createdBy,
    this.amount = '', // تمت إضافة المبلغ مع قيمة افتراضية
    this.technicianPhone = '', // تمت إضافة رقم هاتف الفني مع قيمة افتراضية
  }) {
    // التحقق من القيم المنطقية
    if (status == 'مكتملة' || status == 'ملغية') {
      assert(closedAt != null, 'يجب تعيين closedAt عند إكمال أو إلغاء المهمة');
    }
  }

  /// **نسخة معدلة من المهمة**: لإنشاء نسخة جديدة مع قيم محدثة
  Task copyWith({
    String? id,
    String? title,
    String? status,
    String? department,
    String? leader,
    String? technician,
    String? username,
    String? phone,
    String? fbg,
    String? fat,
    String? location,
    String? notes,
    DateTime? createdAt,
    DateTime? closedAt,
    String? summary,
    String? priority,
    List<String>? agents,
    List<StatusHistory>? statusHistory,
    String? createdBy,
    String? amount, // تمت إضافة المبلغ هنا
    String? technicianPhone, // تمت إضافة رقم هاتف الفني هنا
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      department: department ?? this.department,
      leader: leader ?? this.leader,
      technician: technician ?? this.technician,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      fbg: fbg ?? this.fbg,
      fat: fat ?? this.fat,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      closedAt: closedAt ?? this.closedAt,
      summary: summary ?? this.summary,
      priority: priority ?? this.priority,
      agents: agents ?? this.agents,
      statusHistory: statusHistory ?? this.statusHistory,
      createdBy: createdBy ?? this.createdBy,
      amount: amount ?? this.amount, // تمت إضافة المبلغ هنا
      technicianPhone: technicianPhone ?? this.technicianPhone, // تمت إضافة رقم هاتف الفني هنا
    );
  }

  /// **التحقق مما إذا كانت المهمة مكتملة**
  bool get isCompleted => status == 'مكتملة';

  /// **التحقق مما إذا كانت المهمة ملغية**
  bool get isCancelled => status == 'ملغية';

  /// **تحويل المهمة إلى صيغة نصية**
  @override
  String toString() {
    return '''
المهمة: $title
الحالة: $status
القسم: $department
الليدر: $leader
الفني: $technician
اسم المستخدم: $username
رقم الهاتف: $phone
FBG: $fbg
FAT: $fat
الموقع: $location
ملاحظات: $notes
تاريخ الإنشاء: ${DateFormat('yyyy-MM-dd – HH:mm').format(createdAt)}
تاريخ الإغلاق: ${closedAt != null ? DateFormat('yyyy-MM-dd – HH:mm').format(closedAt!) : 'غير محدد'}
الملخص: $summary
الأولوية: $priority
الوكلاء: ${agents.join(', ')}
أنشأها: $createdBy
المبلغ: $amount
رقم هاتف الفني: $technicianPhone
سجل الحالة:
${statusHistory.map((history) => '  - $history').join('\n')}
''';
  }
}

class StatusHistory {
  final String fromStatus; // الحالة السابقة
  final String toStatus; // الحالة الحالية
  final String notes; // الملاحظات المتعلقة بالتغيير
  final String changedBy; // الشخص الذي قام بالتغيير
  final DateTime changedAt; // وقت التغيير

  StatusHistory({
    required this.fromStatus,
    required this.toStatus,
    required this.notes,
    required this.changedBy,
    DateTime? changedAt,
  }) : changedAt = changedAt ??
            DateTime.now(); // إذا لم يتم توفير وقت، يتم التعيين للوقت الحالي

  /// **تغيير إلى صيغة نصية**
  @override
  String toString() {
    return 'من: $fromStatus إلى: $toStatus بواسطة: $changedBy في ${DateFormat('yyyy-MM-dd – HH:mm').format(changedAt)}';
  }
}
