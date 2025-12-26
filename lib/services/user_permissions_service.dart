import 'package:shared_preferences/shared_preferences.dart';

/// خدمة إدارة صلاحيات المستخدمين
class UserPermissionsService {
  static const String _userRoleKey = 'user_role';
  static const String _userNameKey = 'user_name';

  /// أدوار المستخدمين
  static const String MANAGER = 'مدير';
  static const String LEADER = 'ليدر';
  static const String TECHNICIAN = 'فني';

  /// حفظ دور المستخدم
  static Future<void> setUserRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userRoleKey, role);
  }

  /// حفظ اسم المستخدم
  static Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, name);
  }

  /// الحصول على دور المستخدم الحالي
  static Future<String> getCurrentUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userRoleKey) ?? TECHNICIAN;
  }

  /// الحصول على اسم المستخدم الحالي
  static Future<String> getCurrentUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userNameKey) ?? '';
  }

  /// التحقق من صلاحية التعديل
  static Future<bool> canEditTask() async {
    final role = await getCurrentUserRole();
    return role == MANAGER || role == LEADER;
  }

  /// التحقق من صلاحية الحذف
  static Future<bool> canDeleteTask() async {
    final role = await getCurrentUserRole();
    return role == MANAGER;
  }

  /// التحقق من صلاحية إضافة الوكلاء
  static Future<bool> canManageAgents() async {
    final role = await getCurrentUserRole();
    return role == MANAGER || role == LEADER;
  }

  /// التحقق من إمكانية رؤية المهمة (للفني يرى مهامه فقط)
  static Future<bool> canViewTask(String taskTechnician) async {
    final role = await getCurrentUserRole();
    final userName = await getCurrentUserName();

    if (role == MANAGER || role == LEADER) {
      return true; // المديرون والليدرز يرون جميع المهام
    }

    // الفنيون يرون مهامهم فقط
    return role == TECHNICIAN && taskTechnician.trim() == userName.trim();
  }

  /// الحصول على قائمة الأدوار المتاحة
  static List<String> getAvailableRoles() {
    return [MANAGER, LEADER, TECHNICIAN];
  }

  /// التحقق من صحة الدور
  static bool isValidRole(String role) {
    return getAvailableRoles().contains(role);
  }
}
