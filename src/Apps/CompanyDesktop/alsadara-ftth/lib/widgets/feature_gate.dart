import 'package:flutter/material.dart';
import '../services/permissions_service.dart';
import '../services/permission_checker.dart';

/// أنواع الإجراءات المتاحة للصلاحيات V2
enum PermissionAction {
  view,
  add,
  edit,
  delete,
  export_,
  import_,
  print_,
  send,
}

extension PermissionActionExtension on PermissionAction {
  String get key {
    switch (this) {
      case PermissionAction.view:
        return 'view';
      case PermissionAction.add:
        return 'add';
      case PermissionAction.edit:
        return 'edit';
      case PermissionAction.delete:
        return 'delete';
      case PermissionAction.export_:
        return 'export';
      case PermissionAction.import_:
        return 'import';
      case PermissionAction.print_:
        return 'print';
      case PermissionAction.send:
        return 'send';
    }
  }

  String get labelAr {
    switch (this) {
      case PermissionAction.view:
        return 'عرض';
      case PermissionAction.add:
        return 'إضافة';
      case PermissionAction.edit:
        return 'تعديل';
      case PermissionAction.delete:
        return 'حذف';
      case PermissionAction.export_:
        return 'تصدير';
      case PermissionAction.import_:
        return 'استيراد';
      case PermissionAction.print_:
        return 'طباعة';
      case PermissionAction.send:
        return 'إرسال';
    }
  }
}

/// نظام الصلاحيات (أول أو ثاني)
enum PermissionSystem { first, second }

/// FeatureGate - حارس الصلاحيات على مستوى العناصر
///
/// يخفي أو يُعطّل العنصر الفرعي بناءً على صلاحيات المستخدم.
/// يدعم V1 (boolean بسيط) و V2 (إجراءات تفصيلية).
///
/// مثال استخدام:
/// ```dart
/// FeatureGate(
///   permission: 'accounting',
///   action: PermissionAction.edit,
///   child: ElevatedButton(onPressed: _edit, child: Text('تعديل')),
///   fallback: SizedBox.shrink(), // اختياري
/// )
/// ```
class FeatureGate extends StatelessWidget {
  /// مفتاح الصلاحية (مثل 'accounting', 'users', 'tasks')
  final String permission;

  /// الإجراء المطلوب (اختياري - إذا لم يُحدد يتحقق من V1 فقط)
  final PermissionAction? action;

  /// نظام الصلاحيات (أول أو ثاني)
  final PermissionSystem system;

  /// العنصر الذي يظهر إذا كانت الصلاحية متاحة
  final Widget child;

  /// العنصر البديل إذا لم تكن الصلاحية متاحة (افتراضي: مخفي)
  final Widget? fallback;

  /// بدلاً من الإخفاء، يُعطّل العنصر فقط (يجعله رمادي)
  final bool disableInsteadOfHide;

  /// رسالة تظهر عند الضغط على عنصر مُعطل
  final String? disabledMessage;

  const FeatureGate({
    super.key,
    required this.permission,
    this.action,
    this.system = PermissionSystem.first,
    required this.child,
    this.fallback,
    this.disableInsteadOfHide = false,
    this.disabledMessage,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkPermission(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // أثناء التحميل، أخفي العنصر لتجنب الوميض
          return const SizedBox.shrink();
        }

        final hasPermission = snapshot.data ?? false;

        if (hasPermission) {
          return child;
        }

        if (disableInsteadOfHide) {
          return Opacity(
            opacity: 0.4,
            child: IgnorePointer(
              child: Tooltip(
                message: disabledMessage ?? 'ليس لديك صلاحية لهذا الإجراء',
                child: child,
              ),
            ),
          );
        }

        return fallback ?? const SizedBox.shrink();
      },
    );
  }

  Future<bool> _checkPermission() async {
    // V2: استخدام PermissionManager كمصدر وحيد
    final pm = PermissionManager.instance;
    if (!pm.isLoaded) await pm.loadPermissions();

    if (action != null) {
      return pm.hasAction(permission, action!.key);
    } else {
      return pm.canView(permission);
    }
  }
}

/// FeatureGateBuilder - مثل FeatureGate لكن يعطيك التحكم الكامل
///
/// مثال:
/// ```dart
/// FeatureGateBuilder(
///   permission: 'users',
///   action: PermissionAction.delete,
///   builder: (context, hasPermission) {
///     return IconButton(
///       onPressed: hasPermission ? _delete : null,
///       icon: Icon(Icons.delete),
///     );
///   },
/// )
/// ```
class FeatureGateBuilder extends StatelessWidget {
  final String permission;
  final PermissionAction? action;
  final PermissionSystem system;
  final Widget Function(BuildContext context, bool hasPermission) builder;

  const FeatureGateBuilder({
    super.key,
    required this.permission,
    this.action,
    this.system = PermissionSystem.first,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkPermission(),
      builder: (context, snapshot) {
        final hasPermission = snapshot.data ?? false;
        return builder(context, hasPermission);
      },
    );
  }

  Future<bool> _checkPermission() async {
    if (action != null) {
      if (system == PermissionSystem.first) {
        return PermissionsService.hasFirstSystemPermissionAction(
            permission, action!.key);
      } else {
        return PermissionsService.hasSecondSystemPermissionAction(
            permission, action!.key);
      }
    } else {
      if (system == PermissionSystem.first) {
        return PermissionsService.hasFirstSystemPermission(permission);
      } else {
        return PermissionsService.hasSecondSystemPermission(permission);
      }
    }
  }
}

/// حارس الصفحات - يتحقق من الصلاحية قبل عرض الصفحة
///
/// يعرض صفحة "غير مصرح" إذا لم يكن لدى المستخدم الصلاحية.
///
/// مثال:
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => PageGuard(
///     permission: 'accounting',
///     system: PermissionSystem.first,
///     child: AccountingDashboardPage(),
///   ),
/// ));
/// ```
class PageGuard extends StatelessWidget {
  final String permission;
  final PermissionAction? action;
  final PermissionSystem system;
  final Widget child;
  final String? pageName;

  const PageGuard({
    super.key,
    required this.permission,
    this.action,
    this.system = PermissionSystem.first,
    required this.child,
    this.pageName,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkPermission(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0a0a0a),
            body: Center(
              child: CircularProgressIndicator(color: Colors.amber),
            ),
          );
        }

        final hasPermission = snapshot.data ?? false;

        if (hasPermission) {
          return child;
        }

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: const Color(0xFF0a0a0a),
            appBar: AppBar(
              title: Text(pageName ?? 'غير مصرح'),
              backgroundColor: const Color(0xFF1a1a2e),
              foregroundColor: Colors.white,
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, color: Colors.red, size: 80),
                  const SizedBox(height: 24),
                  const Text(
                    'غير مصرح بالوصول',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'ليس لديك صلاحية للوصول إلى ${pageName ?? "هذه الصفحة"}',
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'تواصل مع المشرف لتفعيل الصلاحية',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('رجوع'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[700],
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _checkPermission() async {
    // V2: استخدام PermissionManager كمصدر وحيد
    final pm = PermissionManager.instance;
    if (!pm.isLoaded) await pm.loadPermissions();

    if (action != null) {
      return pm.hasAction(permission, action!.key);
    } else {
      return pm.canView(permission);
    }
  }
}
