import 'dart:convert';
import 'package:intl/intl.dart';

class Task {
  final String id; // معرف المهمة (RequestNumber)
  final String guid; // المعرف الفريد من السيرفر (GUID)
  final String title; // عنوان المهمة
  final String status; // حالة المهمة (مفتوحة، قيد التنفيذ، مكتملة، ملغية)
  final String department; // القسم المسؤول عن المهمة
  final String leader; // الليدر المسؤول عن المهمة
  final String technician; // الفني المسؤول عن المهمة
  final String technicianId; // معرف الفني (GUID)
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
  final String agentName; // اسم الوكيل (إن كان طلب وكيل)
  final String agentCode; // رمز الوكيل
  final String pageId; // معرف صفحة الوكيل
  final String source; // مصدر الطلب (agent_portal أو companyDesktop)
  final String serviceType; // نوع الخدمة (35, 50, 75, 150)
  final String subscriptionDuration; // مدة الاشتراك
  final String createdByName; // اسم من أنشأ المهمة

  /// **البناء الأساسي لمهمة جديدة**
  Task({
    required this.id,
    this.guid = '',
    required this.title,
    required this.status,
    required this.department,
    required this.leader,
    required this.technician,
    this.technicianId = '',
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
    this.agentName = '', // اسم الوكيل
    this.agentCode = '', // رمز الوكيل
    this.pageId = '', // معرف صفحة الوكيل
    this.source = '', // مصدر الطلب
    this.serviceType = '', // نوع الخدمة
    this.subscriptionDuration = '', // مدة الاشتراك
    this.createdByName = '', // اسم من أنشأ المهمة
  });

  /// **نسخة معدلة من المهمة**: لإنشاء نسخة جديدة مع قيم محدثة
  Task copyWith({
    String? id,
    String? guid,
    String? title,
    String? status,
    String? department,
    String? leader,
    String? technician,
    String? technicianId,
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
    String? agentName,
    String? agentCode,
    String? pageId,
    String? source,
    String? serviceType,
    String? subscriptionDuration,
    String? createdByName,
  }) {
    return Task(
      id: id ?? this.id,
      guid: guid ?? this.guid,
      title: title ?? this.title,
      status: status ?? this.status,
      department: department ?? this.department,
      leader: leader ?? this.leader,
      technician: technician ?? this.technician,
      technicianId: technicianId ?? this.technicianId,
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
      technicianPhone: technicianPhone ??
          this.technicianPhone, // تمت إضافة رقم هاتف الفني هنا
      agentName: agentName ?? this.agentName,
      agentCode: agentCode ?? this.agentCode,
      pageId: pageId ?? this.pageId,
      source: source ?? this.source,
      serviceType: serviceType ?? this.serviceType,
      subscriptionDuration: subscriptionDuration ?? this.subscriptionDuration,
      createdByName: createdByName ?? this.createdByName,
    );
  }

  /// **التحقق مما إذا كانت المهمة مكتملة**
  bool get isCompleted => status == 'مكتملة';

  /// **التحقق مما إذا كانت المهمة ملغية**
  bool get isCancelled => status == 'ملغية';

  // ═══════ بناء من API ═══════

  /// إنشاء مهمة من استجابة API (ServiceRequest)
  factory Task.fromApiResponse(Map<String, dynamic> response) {
    // تحليل JSON المخزن في Details
    Map<String, dynamic> details = {};
    if (response['Details'] != null) {
      try {
        if (response['Details'] is String) {
          details = json.decode(response['Details']);
        } else if (response['Details'] is Map) {
          details = Map<String, dynamic>.from(response['Details'] as Map);
        }
      } catch (_) {}
    }

    // تحليل سجل الحالة
    List<StatusHistory> statusHistory = [];
    if (response['StatusHistory'] is List) {
      for (var h in response['StatusHistory']) {
        statusHistory.add(StatusHistory(
          fromStatus: mapApiStatusToArabic(h['FromStatus']?.toString() ?? ''),
          toStatus: mapApiStatusToArabic(h['ToStatus']?.toString() ?? ''),
          notes: h['Note']?.toString() ?? '',
          changedBy: h['ChangedBy']?.toString() ?? '',
          changedAt: DateTime.tryParse(h['ChangedAt']?.toString() ?? ''),
        ));
      }
    }

    return Task(
      id: response['RequestNumber']?.toString() ??
          response['Id']?.toString() ??
          '',
      guid: response['Id']?.toString() ?? '',
      title: details['taskType']?.toString() ??
          response['OperationTypeName']?.toString() ??
          response['RequestNumber']?.toString() ??
          '',
      status: mapApiStatusToArabic(response['Status']?.toString() ?? 'Pending'),
      department: details['department']?.toString().isNotEmpty == true
          ? details['department'].toString()
          : response['Department']?.toString() ?? '',
      leader: details['leader']?.toString() ?? '',
      technician: details['technician']?.toString() ??
          response['TechnicianName']?.toString() ??
          response['AssignedToName']?.toString() ??
          '',
      technicianId: response['TechnicianId']?.toString() ??
          response['AssignedToId']?.toString() ??
          '',
      username: details['customerName']?.toString() ??
          response['CitizenName']?.toString() ??
          '',
      phone: details['customerPhone']?.toString() ??
          response['ContactPhone']?.toString() ??
          '',
      fbg: details['fbg']?.toString() ?? '',
      fat: details['fat']?.toString() ?? '',
      location: response['Address']?.toString() ??
          details['location']?.toString() ??
          '',
      notes: [
          details['notes']?.toString() ?? '',
          response['StatusNote']?.toString() ?? '',
        ].where((s) => s.isNotEmpty).join(' | '),
      createdAt: _parseUtcDate(response['CreatedAt']?.toString()) ?? DateTime.now(),
      closedAt: response['CompletedAt'] != null
          ? _parseUtcDate(response['CompletedAt'].toString())
          : null,
      summary: details['summary']?.toString() ?? '',
      priority: _mapApiPriorityToArabic(response['Priority']),
      agents: [],
      statusHistory: statusHistory,
      createdBy: details['createdByName']?.toString() ??
          details['source']?.toString() ??
          '',
      createdByName: details['createdByName']?.toString() ?? '',
      serviceType: details['serviceType']?.toString() ?? '',
      subscriptionDuration: details['subscriptionDuration']?.toString() ?? '',
      amount: () {
        final raw = (details['subscriptionAmount'] ??
                response['EstimatedCost'] ??
                response['FinalCost'] ??
                '')
            .toString();
        // إزالة الكسور العشرية (60000.0 → 60000) لمنع تحولها لـ 600000 عند التنسيق
        final num? parsed = num.tryParse(raw);
        return parsed != null ? parsed.toInt().toString() : raw;
      }(),
      technicianPhone: details['technicianPhone']?.toString() ?? '',
      agentName: response['AgentName']?.toString() ?? '',
      agentCode: response['AgentCode']?.toString() ?? '',
      pageId: details['pageId']?.toString() ?? '',
      source: details['source']?.toString() ?? '',
    );
  }

  // ═══════ تحويل الحالات ═══════

  /// تحويل حالة API إلى عربي
  static String mapApiStatusToArabic(String status) {
    switch (status) {
      case 'Pending':
        return 'مفتوحة';
      case 'Reviewing':
        return 'قيد المراجعة';
      case 'Approved':
        return 'موافق عليه';
      case 'Assigned':
        return 'مفتوحة';
      case 'InProgress':
        return 'قيد التنفيذ';
      case 'Completed':
        return 'مكتملة';
      case 'Cancelled':
        return 'ملغية';
      case 'Rejected':
        return 'مرفوضة';
      case 'OnHold':
        return 'معلقة';
      default:
        return status;
    }
  }

  /// تحويل حالة عربية إلى API
  /// تحويل تاريخ من السيرفر (UTC بدون Z) إلى توقيت محلي
  static DateTime? _parseUtcDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    // السيرفر يرسل UTC بدون Z — نضيفها لضمان التحويل الصحيح
    String s = dateStr;
    if (!s.endsWith('Z') && !s.contains('+')) s += 'Z';
    return DateTime.tryParse(s)?.toLocal();
  }

  static String mapArabicStatusToApi(String status) {
    switch (status) {
      case 'مفتوحة':
        return 'Pending';
      case 'قيد المراجعة':
        return 'Reviewing';
      case 'موافق عليه':
        return 'Approved';
      case 'معينة':
        return 'Assigned';
      case 'قيد التنفيذ':
        return 'InProgress';
      case 'مكتملة':
        return 'Completed';
      case 'ملغية':
        return 'Cancelled';
      case 'مرفوضة':
        return 'Rejected';
      case 'معلقة':
        return 'OnHold';
      default:
        return status;
    }
  }

  /// تحويل أولوية API إلى عربي
  static String _mapApiPriorityToArabic(dynamic priority) {
    switch (priority) {
      case 1:
        return 'عاجل';
      case 2:
        return 'عالي';
      case 3:
        return 'متوسط';
      case 4:
        return 'منخفض';
      default:
        return 'متوسط';
    }
  }

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
