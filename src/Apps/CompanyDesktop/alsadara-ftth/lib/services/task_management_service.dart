import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/task.dart';
import '../services/notification_service.dart';

class TaskManagementService {
  static const String baseUrl =
      'YOUR_API_BASE_URL'; // يجب استبدالها بالرابط الحقيقي

  /// إضافة مهمة جديدة مع إرسال إشعارات
  static Future<bool> addNewTask({
    required Task task,
    required String createdBy,
    required List<String> notifyUsers,
    String? assignedTo,
  }) async {
    try {
      // 1. حفظ المهمة في قاعدة البيانات
      bool taskSaved = await _saveTaskToDatabase(task);

      if (taskSaved) {
        // 2. إرسال إشعارات للمستخدمين المحددين
        await NotificationService.notifyNewTask(
          task: task,
          assignedTo: assignedTo ?? 'غير محدد',
          notifyUsers: notifyUsers,
        );

        // 3. إشعار إضافي للمكلف بالمهمة
        if (assignedTo != null && assignedTo.isNotEmpty) {
          await _notifyAssignedUser(task: task, assignedTo: assignedTo);
        }

        // 4. إشعار إضافي للإدارة حسب القسم
        await _notifyDepartmentManagers(task: task);

        print('✅ تم إضافة المهمة وإرسال الإشعارات بنجاح');
        return true;
      }

      return false;
    } catch (e) {
      print('❌ خطأ في إضافة المهمة');
      return false;
    }
  }

  /// تحديث حالة المهمة مع إرسال إشعارات
  static Future<bool> updateTaskStatus({
    required String taskId,
    required String newStatus,
    required String updatedBy,
    String? notes,
  }) async {
    try {
      // 1. الحصول على المهمة الحالية
      Task? currentTask = await _getTaskById(taskId);
      if (currentTask == null) return false;

      String oldStatus = currentTask.status;

      // 2. إنشاء مهمة محدثة بدلاً من استخدام copyWith
      Task updatedTask = Task(
        id: currentTask.id,
        title: currentTask.title,
        status: newStatus,
        department: currentTask.department,
        leader: currentTask.leader,
        technician: currentTask.technician,
        username: currentTask.username,
        phone: currentTask.phone,
        fbg: currentTask.fbg,
        fat: currentTask.fat,
        location: currentTask.location,
        notes: notes ?? currentTask.notes,
        summary: currentTask.summary,
        priority: currentTask.priority,
        amount: currentTask.amount,
        createdAt: currentTask.createdAt,
        closedAt: newStatus == 'مكتملة' ? DateTime.now() : currentTask.closedAt,
        agents: currentTask.agents,
        createdBy: currentTask.createdBy,
        statusHistory: currentTask.statusHistory,
      );

      // 3. حفظ التحديث
      bool updateSaved = await _updateTaskInDatabase(updatedTask);

      if (updateSaved) {
        // 4. تحديد المستخدمين للإشعار
        List<String> notifyUsers =
            await _getUsersToNotifyForUpdate(updatedTask);

        // 5. إرسال إشعارات التحديث
        await NotificationService.notifyTaskStatusUpdate(
          task: updatedTask,
          oldStatus: oldStatus,
          newStatus: newStatus,
          notifyUsers: notifyUsers,
        );

        // 6. إشعارات خاصة حسب نوع التحديث
        await _handleSpecialStatusNotifications(
            updatedTask, oldStatus, newStatus);

        print('✅ تم تحديث المهمة وإرسال الإشعارات بنجاح');
        return true;
      }

      return false;
    } catch (e) {
      print('❌ خطأ في تحديث المهمة');
      return false;
    }
  }

  /// فحص المهام المتأخرة وإرسال إشعارات
  static Future<void> checkOverdueTasksAndNotify() async {
    try {
      List<Task> overdueTasks = await _getOverdueTasks();

      if (overdueTasks.isNotEmpty) {
        // تجميع المهام حسب المستخدم المكلف
        Map<String, List<Task>> tasksByUser = {};

        for (Task task in overdueTasks) {
          String assignee =
              task.technician.isNotEmpty ? task.technician : task.leader;
          if (!tasksByUser.containsKey(assignee)) {
            tasksByUser[assignee] = [];
          }
          tasksByUser[assignee]!.add(task);
        }

        // إرسال إشعارات لكل مستخدم
        for (String user in tasksByUser.keys) {
          await NotificationService.notifyOverdueTasks(
            overdueTasks: tasksByUser[user]!,
            notifyUsers: [user],
          );
        }

        // إشعار للإدارة
        List<String> managers = await _getDepartmentManagers();
        await NotificationService.notifyOverdueTasks(
          overdueTasks: overdueTasks,
          notifyUsers: managers,
        );
      }
    } catch (e) {
      print('❌ خطأ في فحص المهام المتأخرة');
    }
  }

  /// إعداد إشعارات دورية للمهام المتأخرة
  static Future<void> setupPeriodicOverdueCheck() async {
    // يمكن استخدام مكتبة مثل cron أو workmanager للجدولة
    // هذا مثال بسيط يمكن تطويره

    Stream.periodic(Duration(hours: 6)).listen((_) async {
      await checkOverdueTasksAndNotify();
    });
  }

  /// حفظ المهمة في قاعدة البيانات
  static Future<bool> _saveTaskToDatabase(Task task) async {
    try {
      // هنا يجب تنفيذ الحفظ في قاعدة البيانات
      // مثال مبسط:

      final response = await http.post(
        Uri.parse('$baseUrl/tasks'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(_taskToJson(task)),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('خطأ في حفظ المهمة');
      return false;
    }
  }

  /// تحديث المهمة في قاعدة البيانات
  static Future<bool> _updateTaskInDatabase(Task task) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/tasks/${task.id}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(_taskToJson(task)),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('خطأ في تحديث المهمة');
      return false;
    }
  }

  /// الحصول على مهمة بالمعرف
  static Future<Task?> _getTaskById(String taskId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/tasks/$taskId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> data = jsonDecode(response.body);
        return _taskFromJson(data);
      }

      return null;
    } catch (e) {
      print('خطأ في جلب المهمة');
      return null;
    }
  }

  /// الحصول على المهام المتأخرة
  static Future<List<Task>> _getOverdueTasks() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/tasks/overdue'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => _taskFromJson(json)).toList();
      }

      return [];
    } catch (e) {
      print('خطأ في جلب المهام المتأخرة');
      return [];
    }
  }

  /// تحويل Task إلى JSON
  static Map<String, dynamic> _taskToJson(Task task) {
    return {
      'id': task.id,
      'title': task.title,
      'status': task.status,
      'department': task.department,
      'leader': task.leader,
      'technician': task.technician,
      'username': task.username,
      'phone': task.phone,
      'fbg': task.fbg,
      'fat': task.fat,
      'location': task.location,
      'notes': task.notes,
      'summary': task.summary,
      'priority': task.priority,
      'amount': task.amount,
      'createdAt': task.createdAt.toIso8601String(),
      'closedAt': task.closedAt?.toIso8601String(),
      'agents': task.agents,
      'createdBy': task.createdBy,
      'statusHistory':
          task.statusHistory.map((status) => status.toString()).toList(),
    };
  }

  /// تحويل JSON إلى Task
  static Task _taskFromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      status: json['status'] ?? '',
      department: json['department'] ?? '',
      leader: json['leader'] ?? '',
      technician: json['technician'] ?? '',
      username: json['username'] ?? '',
      phone: json['phone'] ?? '',
      fbg: json['fbg'] ?? '',
      fat: json['fat'] ?? '',
      location: json['location'] ?? '',
      notes: json['notes'] ?? '',
      summary: json['summary'] ?? '',
      priority: json['priority'] ?? '',
      amount: json['amount'] ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      closedAt:
          json['closedAt'] != null ? DateTime.tryParse(json['closedAt']) : null,
      agents: List<String>.from(json['agents'] ?? []),
      createdBy: json['createdBy'] ?? '',
      statusHistory: [], // تم إصلاحها - قائمة فارغة من StatusHistory
    );
  }

  /// إشعار خاص للمستخدم المكلف بالمهمة
  static Future<void> _notifyAssignedUser({
    required Task task,
    required String assignedTo,
  }) async {
    await NotificationService.showLocalNotification(
      title: '🎯 مهمة جديدة مكلف بها',
      body:
          'تم تكليفك بمهمة جديدة: ${task.title}\nالقسم: ${task.department}\nالأولوية: ${task.priority}',
      payload: jsonEncode({
        'type': 'assigned_task',
        'taskId': task.id,
        'assignedTo': assignedTo,
      }),
    );
  }

  /// إشعار مدراء الأقسام
  static Future<void> _notifyDepartmentManagers({required Task task}) async {
    List<String> managers = await _getDepartmentManagers();

    for (int i = 0; i < managers.length; i++) {
      String managerName = managers[i];
      await NotificationService.showLocalNotification(
        title: '📋 مهمة جديدة في القسم',
        body:
            'تم إضافة مهمة جديدة في قسم ${task.department}: ${task.title}\nمدير: $managerName',
        payload: jsonEncode({
          'type': 'department_task',
          'taskId': task.id,
          'department': task.department,
          'manager': managerName,
        }),
      );
    }
  }

  /// معالجة إشعارات خاصة حسب تحديث الحالة
  static Future<void> _handleSpecialStatusNotifications(
    Task task,
    String oldStatus,
    String newStatus,
  ) async {
    // إشعارات خاصة عند إكمال المهمة
    if (newStatus == 'مكتملة' && oldStatus != 'مكتملة') {
      await NotificationService.showLocalNotification(
        title: '🎉 تم إكمال المهمة',
        body: 'تم إكمال المهمة "${task.title}" بنجاح!',
        payload: jsonEncode({
          'type': 'task_completed',
          'taskId': task.id,
        }),
      );
    }

    // إشعارات خاصة عند إلغاء المهمة
    if (newStatus == 'ملغية') {
      await NotificationService.showLocalNotification(
        title: '❌ تم إلغاء المهمة',
        body: 'تم إلغاء المهمة "${task.title}"',
        payload: jsonEncode({
          'type': 'task_cancelled',
          'taskId': task.id,
        }),
      );
    }

    // إشعارات خاصة للمهام عالية الأولوية
    if (task.priority == 'عاجل' || task.priority == 'مهم جداً') {
      await NotificationService.showLocalNotification(
        title: '⚡ مهمة عالية الأولوية',
        body: 'تحديث في مهمة عالية الأولوية: ${task.title}',
        payload: jsonEncode({
          'type': 'high_priority_update',
          'taskId': task.id,
          'priority': task.priority,
        }),
      );
    }
  }

  /// الحصول على المستخدمين للإشعار عند التحديث
  static Future<List<String>> _getUsersToNotifyForUpdate(Task task) async {
    List<String> users = [];

    // إضافة المكلف بالمهمة
    if (task.technician.isNotEmpty) users.add(task.technician);
    if (task.leader.isNotEmpty) users.add(task.leader);

    // إضافة مدراء القسم
    List<String> managers = await _getDepartmentManagers();
    users.addAll(managers);

    // إزالة التكرارات
    return users.toSet().toList();
  }

  /// الحصول على مدراء الأقسام
  static Future<List<String>> _getDepartmentManagers() async {
    // هذه قائمة ثابتة يمكن جعلها ديناميكية من قاعدة البيانات
    return [
      'مدير التقني',
      'مدير العمليات',
      'مدير المشاريع',
      'المشرف العام',
    ];
  }

  /// حفظ FCM Token للمستخدم عند تسجيل الدخول
  static Future<void> registerUserForNotifications(String userId) async {
    await NotificationService.saveFCMTokenForUser(userId);
  }
}
