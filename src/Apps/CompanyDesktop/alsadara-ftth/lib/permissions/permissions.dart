/// ═══════════════════════════════════════════════════════════════
/// نظام الصلاحيات الموحد — مجلد مستقل للصيانة والتطوير
/// ═══════════════════════════════════════════════════════════════
///
/// الاستخدام:
/// ```dart
/// import '../permissions/permissions.dart';
///
/// // فحص صلاحية
/// if (PermissionManager.instance.canView('accounting.journals')) { ... }
///
/// // حارس عنصر
/// PermissionGate(permission: 'hr.employees', action: 'edit', child: editBtn)
///
/// // حارس صفحة
/// PermissionGate.page(permission: 'accounting', child: AccountingPage())
///
/// // Mixin في StatefulWidget
/// class _MyState extends State<MyPage> with PermissionCheckerMixin { ... }
/// ```
library;

export 'permission_registry.dart';
export 'permission_manager.dart';
export 'permission_gate.dart';
export 'permission_service.dart';
export 'permission_mixin.dart';
