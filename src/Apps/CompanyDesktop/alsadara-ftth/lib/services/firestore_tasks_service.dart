/// اسم الملف: خدمة المهام عبر Firestore
/// وصف الملف: إدارة المهام باستخدام Cloud Firestore
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task.dart';
import '../models/filter_criteria.dart';
import 'firebase_auth_service.dart';
import 'firebase_availability.dart';

/// خدمة إدارة المهام عبر Firestore
class FirestoreTasksService {
  /// تحميل كسول لتجنب خطأ [core/no-app]
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// جلب جميع المهام من Firestore
  static Future<List<Task>> fetchTasks() async {
    if (!FirebaseAvailability.isAvailable) return [];
    try {
      // الحصول على organizationId للمستخدم الحالي
      final organizationId =
          await FirebaseAuthService.getStoredOrganizationId();

      QuerySnapshot querySnapshot;

      if (organizationId != null && organizationId.isNotEmpty) {
        // جلب المهام الخاصة بالمنظمة فقط
        querySnapshot = await _firestore
            .collection('tasks')
            .where('organizationId', isEqualTo: organizationId)
            .orderBy('dates.createdAt', descending: true)
            .get();
      } else {
        // إذا لم يكن هناك organizationId (مدير عام) - جلب الكل
        querySnapshot = await _firestore
            .collection('tasks')
            .orderBy('dates.createdAt', descending: true)
            .get();
      }

      print('📊 تم جلب ${querySnapshot.docs.length} مهمة من Firestore');

      List<Task> tasks = [];
      for (var doc in querySnapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          final task = _taskFromFirestore(doc.id, data);
          tasks.add(task);
        } catch (e) {
          print('⚠️ خطأ في تحويل المهمة ${doc.id}: $e');
        }
      }

      return tasks;
    } catch (e) {
      print('❌ خطأ في جلب المهام: $e');
      return [];
    }
  }

  /// جلب المهام بناءً على معايير الفلترة
  static Future<List<Task>> fetchFilteredTasks(FilterCriteria criteria) async {
    if (!FirebaseAvailability.isAvailable) return [];
    try {
      final organizationId =
          await FirebaseAuthService.getStoredOrganizationId();

      Query query = _firestore.collection('tasks');

      // فلترة حسب المنظمة
      if (organizationId != null && organizationId.isNotEmpty) {
        query = query.where('organizationId', isEqualTo: organizationId);
      }

      // فلترة حسب الحالة
      if (criteria.status != null && criteria.status!.isNotEmpty) {
        query = query.where('status', isEqualTo: criteria.status);
      }

      // فلترة حسب القسم
      if (criteria.department != null && criteria.department!.isNotEmpty) {
        query = query.where('department', isEqualTo: criteria.department);
      }

      // فلترة حسب الأولوية
      if (criteria.priority != null && criteria.priority!.isNotEmpty) {
        query = query.where('priority', isEqualTo: criteria.priority);
      }

      // فلترة حسب الفني
      if (criteria.technician != null && criteria.technician!.isNotEmpty) {
        query = query.where('assignedTo.displayName',
            isEqualTo: criteria.technician);
      }

      // الترتيب
      query = query.orderBy('dates.createdAt', descending: true);

      final querySnapshot = await query.get();

      List<Task> tasks = [];
      for (var doc in querySnapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          final task = _taskFromFirestore(doc.id, data);

          // فلترة إضافية في الذاكرة (للتاريخ والبحث النصي)
          if (_matchesTextSearch(task, criteria.searchText) &&
              _matchesDateRange(task, criteria.startDate, criteria.endDate)) {
            tasks.add(task);
          }
        } catch (e) {
          print('⚠️ خطأ في معالجة المهمة ${doc.id}: $e');
        }
      }

      return tasks;
    } catch (e) {
      print('❌ خطأ في جلب المهام المفلترة: $e');
      return [];
    }
  }

  /// إضافة مهمة جديدة
  static Future<String?> addTask(Task task) async {
    if (!FirebaseAvailability.isAvailable) return null;
    try {
      final organizationId =
          await FirebaseAuthService.getStoredOrganizationId();
      final currentUserId = FirebaseAuthService.currentUserId;

      final taskData = {
        'organizationId': organizationId ?? '',
        'title': task.title,
        'description': task.notes,
        'status': task.status,
        'priority': task.priority,
        'department': task.department,
        'assignedTo': {
          'displayName': task.technician,
          'phone': task.technicianPhone,
        },
        'customer': {
          'name': task.username,
          'phone': task.phone,
        },
        'location': {
          'address': task.location,
          'fbg': task.fbg,
          'fat': task.fat,
        },
        'dates': {
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'closedAt': task.closedAt,
        },
        'metadata': {
          'leader': task.leader,
          'summary': task.summary,
          'amount': task.amount,
          'agents': task.agents,
          'createdBy': currentUserId ?? task.createdBy,
        },
        'statusHistory': [],
      };

      final docRef = await _firestore.collection('tasks').add(taskData);
      print('✅ تم إنشاء المهمة: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ خطأ في إضافة المهمة: $e');
      return null;
    }
  }

  /// تحديث مهمة موجودة
  static Future<bool> updateTask(String taskId, Task task) async {
    if (!FirebaseAvailability.isAvailable) return false;
    try {
      final taskData = {
        'title': task.title,
        'description': task.notes,
        'status': task.status,
        'priority': task.priority,
        'department': task.department,
        'assignedTo': {
          'displayName': task.technician,
          'phone': task.technicianPhone,
        },
        'customer': {
          'name': task.username,
          'phone': task.phone,
        },
        'location': {
          'address': task.location,
          'fbg': task.fbg,
          'fat': task.fat,
        },
        'dates.updatedAt': FieldValue.serverTimestamp(),
        'dates.closedAt': task.closedAt,
        'metadata': {
          'leader': task.leader,
          'summary': task.summary,
          'amount': task.amount,
          'agents': task.agents,
        },
      };

      await _firestore.collection('tasks').doc(taskId).update(taskData);
      print('✅ تم تحديث المهمة: $taskId');
      return true;
    } catch (e) {
      print('❌ خطأ في تحديث المهمة: $e');
      return false;
    }
  }

  /// تحديث حالة المهمة
  static Future<bool> updateTaskStatus(String taskId, String newStatus) async {
    if (!FirebaseAvailability.isAvailable) return false;
    try {
      final updateData = {
        'status': newStatus,
        'dates.updatedAt': FieldValue.serverTimestamp(),
      };

      // إذا كانت الحالة مكتملة أو ملغية، إضافة تاريخ الإغلاق
      if (newStatus == 'مكتملة' || newStatus == 'ملغية') {
        updateData['dates.closedAt'] = FieldValue.serverTimestamp();
      }

      // إضافة إلى سجل الحالات
      await _firestore.collection('tasks').doc(taskId).update(updateData);

      await _firestore.collection('tasks').doc(taskId).update({
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': newStatus,
            'changedAt': FieldValue.serverTimestamp(),
            'changedBy': FirebaseAuthService.currentUserId ?? '',
          }
        ])
      });

      print('✅ تم تحديث حالة المهمة: $taskId إلى $newStatus');
      return true;
    } catch (e) {
      print('❌ خطأ في تحديث حالة المهمة: $e');
      return false;
    }
  }

  /// حذف مهمة
  static Future<bool> deleteTask(String taskId) async {
    if (!FirebaseAvailability.isAvailable) return false;
    try {
      await _firestore.collection('tasks').doc(taskId).delete();
      print('✅ تم حذف المهمة: $taskId');
      return true;
    } catch (e) {
      print('❌ خطأ في حذف المهمة: $e');
      return false;
    }
  }

  /// الاستماع للمهام في الوقت الفعلي (Real-time)
  static Stream<List<Task>> watchTasks() {
    if (!FirebaseAvailability.isAvailable) return Stream.value([]);
    return _firestore
        .collection('tasks')
        .orderBy('dates.createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      List<Task> tasks = [];
      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();
          final task = _taskFromFirestore(doc.id, data);
          tasks.add(task);
        } catch (e) {
          print('⚠️ خطأ في معالجة المهمة ${doc.id}: $e');
        }
      }
      return tasks;
    });
  }

  /// الاستماع لمهمة واحدة
  static Stream<Task?> watchTask(String taskId) {
    if (!FirebaseAvailability.isAvailable) return Stream.value(null);
    return _firestore.collection('tasks').doc(taskId).snapshots().map((doc) {
      if (!doc.exists) return null;
      try {
        final data = doc.data() as Map<String, dynamic>;
        return _taskFromFirestore(doc.id, data);
      } catch (e) {
        print('⚠️ خطأ في معالجة المهمة $taskId: $e');
        return null;
      }
    });
  }

  /// تحويل بيانات Firestore إلى Task object
  static Task _taskFromFirestore(String id, Map<String, dynamic> data) {
    final dates = data['dates'] as Map<String, dynamic>? ?? {};
    final assignedTo = data['assignedTo'] as Map<String, dynamic>? ?? {};
    final customer = data['customer'] as Map<String, dynamic>? ?? {};
    final location = data['location'] as Map<String, dynamic>? ?? {};
    final metadata = data['metadata'] as Map<String, dynamic>? ?? {};

    return Task(
      id: id,
      status: data['status'] ?? '',
      department: data['department'] ?? '',
      title: data['title'] ?? '',
      leader: metadata['leader'] ?? '',
      technician: assignedTo['displayName'] ?? '',
      username: customer['name'] ?? '',
      phone: customer['phone'] ?? '',
      fbg: location['fbg'] ?? '',
      fat: location['fat'] ?? '',
      location: location['address'] ?? '',
      notes: data['description'] ?? '',
      createdAt: (dates['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      closedAt: (dates['closedAt'] as Timestamp?)?.toDate(),
      summary: metadata['summary'] ?? '',
      priority: data['priority'] ?? '',
      agents: List<String>.from(metadata['agents'] ?? []),
      createdBy: metadata['createdBy'] ?? '',
      amount: metadata['amount'] ?? '',
      technicianPhone: assignedTo['phone'] ?? '',
      statusHistory: [], // يمكن إضافة التحويل إذا لزم الأمر
    );
  }

  /// فلترة نصية (في الذاكرة)
  static bool _matchesTextSearch(Task task, String? searchText) {
    if (searchText == null || searchText.trim().isEmpty) return true;

    final search = searchText.toLowerCase();
    return task.title.toLowerCase().contains(search) ||
        task.username.toLowerCase().contains(search) ||
        task.phone.contains(search) ||
        task.location.toLowerCase().contains(search) ||
        task.technician.toLowerCase().contains(search);
  }

  /// فلترة حسب النطاق الزمني
  static bool _matchesDateRange(
      Task task, DateTime? startDate, DateTime? endDate) {
    if (startDate == null && endDate == null) return true;

    if (startDate != null && task.createdAt.isBefore(startDate)) return false;
    if (endDate != null && task.createdAt.isAfter(endDate)) return false;

    return true;
  }

  /// إحصائيات المهام
  static Future<Map<String, int>> getTasksStats() async {
    if (!FirebaseAvailability.isAvailable)
      return {
        'total': 0,
        'pending': 0,
        'inProgress': 0,
        'completed': 0,
        'cancelled': 0
      };
    try {
      final organizationId =
          await FirebaseAuthService.getStoredOrganizationId();

      Query query = _firestore.collection('tasks');

      if (organizationId != null && organizationId.isNotEmpty) {
        query = query.where('organizationId', isEqualTo: organizationId);
      }

      final snapshot = await query.get();

      int total = snapshot.docs.length;
      int pending = 0;
      int inProgress = 0;
      int completed = 0;
      int cancelled = 0;

      for (var doc in snapshot.docs) {
        final status = doc.get('status') as String?;
        switch (status) {
          case 'معلقة':
            pending++;
            break;
          case 'قيد التنفيذ':
            inProgress++;
            break;
          case 'مكتملة':
            completed++;
            break;
          case 'ملغية':
            cancelled++;
            break;
        }
      }

      return {
        'total': total,
        'pending': pending,
        'inProgress': inProgress,
        'completed': completed,
        'cancelled': cancelled,
      };
    } catch (e) {
      print('❌ خطأ في جلب إحصائيات المهام: $e');
      return {
        'total': 0,
        'pending': 0,
        'inProgress': 0,
        'completed': 0,
        'cancelled': 0,
      };
    }
  }
}
