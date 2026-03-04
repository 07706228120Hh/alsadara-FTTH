/// ═══════════════════════════════════════════════════════════════
/// حارس الصلاحيات الموحد — يحل محل جميع widgets القديمة
/// ═══════════════════════════════════════════════════════════════
///
/// يحل محل: FeatureGate, FeatureGateBuilder, PageGuard, PermissionGuard
///
/// الاستخدام:
/// ```dart
/// // إخفاء عنصر
/// PermissionGate(
///   permission: 'accounting.journals',
///   action: 'edit',
///   child: EditButton(),
/// )
///
/// // تعطيل عنصر (رمادي)
/// PermissionGate(
///   permission: 'hr.salaries',
///   action: 'delete',
///   disableInsteadOfHide: true,
///   child: DeleteButton(),
/// )
///
/// // حراسة صفحة كاملة
/// PermissionGate.page(
///   permission: 'accounting',
///   pageName: 'المحاسبة',
///   child: AccountingPage(),
/// )
///
/// // Builder pattern
/// PermissionGate.builder(
///   permission: 'users',
///   action: 'delete',
///   builder: (context, allowed) => IconButton(
///     onPressed: allowed ? _delete : null,
///     icon: Icon(Icons.delete),
///   ),
/// )
/// ```
library;

import 'package:flutter/material.dart';
import 'permission_manager.dart';

/// حارس الصلاحيات الموحد
class PermissionGate extends StatelessWidget {
  /// مفتاح الصلاحية (مثل 'accounting', 'accounting.journals', 'users')
  final String permission;

  /// الإجراء المطلوب (افتراضي: 'view')
  final String action;

  /// العنصر الذي يظهر إذا كانت الصلاحية متاحة
  final Widget? child;

  /// العنصر البديل إذا لم تكن الصلاحية متاحة (افتراضي: SizedBox.shrink)
  final Widget? fallback;

  /// بدلاً من الإخفاء، يُعطّل العنصر (رمادي + IgnorePointer)
  final bool disableInsteadOfHide;

  /// رسالة تظهر عند الضغط على عنصر مُعطل
  final String? disabledMessage;

  /// هل هذا حارس صفحة كاملة؟ (يعرض Scaffold "غير مصرح")
  final bool _isPageGuard;

  /// اسم الصفحة (يظهر في شاشة "غير مصرح")
  final String? pageName;

  /// Builder pattern — يمنح التحكم الكامل
  final Widget Function(BuildContext context, bool hasPermission)? _builder;

  /// الحارس الأساسي — يخفي أو يُعطّل العنصر
  const PermissionGate({
    super.key,
    required this.permission,
    this.action = 'view',
    this.child,
    this.fallback,
    this.disableInsteadOfHide = false,
    this.disabledMessage,
    this.pageName,
  })  : _isPageGuard = false,
        _builder = null;

  /// حارس صفحة كاملة — يعرض شاشة "غير مصرح" بدل الإخفاء
  const PermissionGate.page({
    super.key,
    required this.permission,
    this.action = 'view',
    this.child,
    this.pageName,
  })  : _isPageGuard = true,
        fallback = null,
        disableInsteadOfHide = false,
        disabledMessage = null,
        _builder = null;

  /// Builder — يعطيك bool ليُحدد سلوكك الخاص
  const PermissionGate.builder({
    super.key,
    required this.permission,
    this.action = 'view',
    required Widget Function(BuildContext context, bool hasPermission) builder,
  })  : _builder = builder,
        child = null,
        fallback = null,
        disableInsteadOfHide = false,
        disabledMessage = null,
        _isPageGuard = false,
        pageName = null;

  @override
  Widget build(BuildContext context) {
    final pm = PermissionManager.instance;

    // تأكد من تحميل الصلاحيات
    if (!pm.isLoaded) {
      return FutureBuilder<void>(
        future: pm.loadPermissions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            if (_isPageGuard) {
              return const Scaffold(
                backgroundColor: Color(0xFF0a0a0a),
                body: Center(
                  child: CircularProgressIndicator(color: Colors.amber),
                ),
              );
            }
            return const SizedBox.shrink();
          }
          return _buildContent(context, pm);
        },
      );
    }

    return _buildContent(context, pm);
  }

  Widget _buildContent(BuildContext context, PermissionManager pm) {
    final hasPermission = pm.hasAction(permission, action);

    // Builder pattern
    if (_builder != null) {
      return _builder(context, hasPermission);
    }

    // صلاحية متاحة
    if (hasPermission) {
      return child ?? const SizedBox.shrink();
    }

    // حارس صفحة — عرض "غير مصرح"
    if (_isPageGuard) {
      return _buildUnauthorizedPage(context);
    }

    // تعطيل بدل إخفاء
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

    // إخفاء (الافتراضي)
    return fallback ?? const SizedBox.shrink();
  }

  Widget _buildUnauthorizedPage(BuildContext context) {
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
