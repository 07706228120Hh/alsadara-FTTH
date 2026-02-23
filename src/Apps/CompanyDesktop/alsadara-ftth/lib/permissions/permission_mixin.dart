/// ═══════════════════════════════════════════════════════════════
/// Mixin الصلاحيات — للاستخدام في StatefulWidget
/// ═══════════════════════════════════════════════════════════════
///
/// الاستخدام:
/// ```dart
/// class _MyPageState extends State<MyPage> with PermissionCheckerMixin {
///   @override
///   void initState() {
///     super.initState();
///     initPermissions();
///   }
///
///   Widget build(BuildContext context) {
///     if (!canView('accounting')) return UnauthorizedWidget();
///     // ...
///   }
/// }
/// ```
library;

import 'package:flutter/widgets.dart';
import 'permission_manager.dart';

/// Mixin لاستخدامه في أي StatefulWidget يحتاج فحص صلاحيات
mixin PermissionCheckerMixin<T extends StatefulWidget> on State<T> {
  PermissionManager get _pm => PermissionManager.instance;

  /// تحميل الصلاحيات — يُستدعى في initState
  Future<void> initPermissions() async {
    if (!_pm.isLoaded) {
      await _pm.loadPermissions();
    }
  }

  /// هل يمكن عرض هذه الميزة؟
  bool canView(String feature) => _pm.canView(feature);

  /// هل يمكن إضافة عنصر؟
  bool canAdd(String feature) => _pm.canAdd(feature);

  /// هل يمكن تعديل عنصر؟
  bool canEdit(String feature) => _pm.canEdit(feature);

  /// هل يمكن حذف عنصر؟
  bool canDelete(String feature) => _pm.canDelete(feature);

  /// هل يمكن تصدير؟
  bool canExport(String feature) => _pm.canExport(feature);

  /// هل يمكن استيراد؟
  bool canImport(String feature) => _pm.canImport(feature);

  /// هل يمكن طباعة؟
  bool canPrint(String feature) => _pm.canPrint(feature);

  /// هل يمكن إرسال؟
  bool canSend(String feature) => _pm.canSend(feature);

  /// فحص إجراء مخصص
  bool hasAction(String feature, String action) =>
      _pm.hasAction(feature, action);
}
