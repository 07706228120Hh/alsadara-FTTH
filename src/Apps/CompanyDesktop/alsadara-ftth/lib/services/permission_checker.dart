/// 🔐 نظام فحص الصلاحيات الموحد V3 — هرمي دقيق
/// يوفر طريقة مركزية للتحقق من الصلاحيات على مستوى الإجراءات
/// يدعم المفاتيح الهرمية مثل 'accounting.journals'
///
/// القاعدة الهرمية:
///   - إذا الأب مغلق ← جميع الأبناء مغلقة تلقائياً
///   - إذا الأب مفتوح + الابن غير محدد ← يرث من الأب
///   - إذا الأب مفتوح + الابن محدد ← يستخدم قيمة الابن
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
///   if (canView('accounting'))            // هل يرى المحاسبة؟
///   if (canView('accounting.journals'))   // هل يرى القيود اليومية؟
///   if (canAdd('accounting.journals'))    // هل يضيف قيد؟
///   if (canEdit('hr.salaries'))           // هل يعدل الرواتب؟
/// }
/// ```
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'permissions_service.dart';
import '../config/permission_registry.dart';

/// أنواع الإجراءات المتاحة
enum PermissionAction {
  view,
  add,
  edit,
  delete,
  export,
  import_,
  print_,
  send,
}

/// تحويل الإجراء إلى مفتاح نصي
extension PermissionActionExt on PermissionAction {
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
      case PermissionAction.export:
        return 'export';
      case PermissionAction.import_:
        return 'import';
      case PermissionAction.print_:
        return 'print';
      case PermissionAction.send:
        return 'send';
    }
  }
}

/// مدير الصلاحيات V3 — Singleton مع دعم هرمي
class PermissionManager {
  static PermissionManager? _instance;
  static PermissionManager get instance =>
      _instance ??= PermissionManager._internal();
  PermissionManager._internal();

  /// صلاحيات V2 — النظام الأول
  /// {feature: {action: bool}}
  Map<String, Map<String, bool>> _firstSystemV2 = {};

  /// صلاحيات V2 — النظام الثاني
  Map<String, Map<String, bool>> _secondSystemV2 = {};

  /// هل تم تحميل الصلاحيات؟
  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// تحميل الصلاحيات من PermissionsService (SharedPreferences)
  Future<void> loadPermissions() async {
    try {
      _firstSystemV2 = await PermissionsService.getFirstSystemPermissionsV2();
      _secondSystemV2 = await PermissionsService.getSecondSystemPermissionsV2();
      _loaded = true;
      debugPrint('✅ PermissionManager: تم تحميل صلاحيات V3');
      debugPrint('   النظام الأول: ${_firstSystemV2.keys.length} ميزة');
      debugPrint('   النظام الثاني: ${_secondSystemV2.keys.length} ميزة');
    } catch (e) {
      debugPrint('❌ PermissionManager: خطأ في تحميل الصلاحيات: $e');
    }
  }

  /// حفظ صلاحيات V2 (تُستدعى عند تسجيل الدخول)
  Future<void> savePermissions({
    required Map<String, Map<String, bool>> firstSystem,
    required Map<String, Map<String, bool>> secondSystem,
  }) async {
    _firstSystemV2 = firstSystem;
    _secondSystemV2 = secondSystem;
    _loaded = true;

    // حفظ في SharedPreferences
    await PermissionsService.saveFirstSystemPermissionsV2(firstSystem);
    await PermissionsService.saveSecondSystemPermissionsV2(secondSystem);

    debugPrint('💾 PermissionManager: تم حفظ صلاحيات V3');
  }

  /// تحديث صلاحيات V2 من بيانات API خام
  /// يتعامل مع كلا الصيغتين: V1 (flat bool) و V2 (nested actions)
  Future<void> updateFromRawJson({
    dynamic firstSystemV1Json,
    dynamic firstSystemV2Json,
    dynamic secondSystemV1Json,
    dynamic secondSystemV2Json,
  }) async {
    final firstV2 = _parseV2WithFallback(firstSystemV1Json, firstSystemV2Json);
    final secondV2 =
        _parseV2WithFallback(secondSystemV1Json, secondSystemV2Json);

    await savePermissions(firstSystem: firstV2, secondSystem: secondV2);
  }

  /// معالجة بيانات V2 مع الرجوع إلى V1 إذا لزم الأمر
  Map<String, Map<String, bool>> _parseV2WithFallback(
    dynamic v1Source,
    dynamic v2Source,
  ) {
    final result = <String, Map<String, bool>>{};

    // أولاً: حاول V2
    final v2Data = _decodeJsonSource(v2Source);
    if (v2Data != null) {
      v2Data.forEach((feature, value) {
        if (value is Map) {
          result[feature] = {};
          for (final action in PermissionsService.availableActions) {
            result[feature]![action] = value[action] == true;
          }
        } else if (value == true) {
          // V1 format في حقل V2 — حوّل إلى V2
          result[feature] = _v1ToV2Actions(true);
        }
      });
    }

    // ثانياً: أضف ما ينقص من V1
    final v1Data = _decodeJsonSource(v1Source);
    if (v1Data != null) {
      v1Data.forEach((feature, value) {
        if (!result.containsKey(feature)) {
          if (value is Map) {
            // V2 format في حقل V1
            result[feature] = {};
            for (final action in PermissionsService.availableActions) {
              result[feature]![action] = value[action] == true;
            }
          } else {
            result[feature] = _v1ToV2Actions(value == true);
          }
        }
      });
    }

    return result;
  }

  /// تحويل V1 (bool) إلى V2 (actions map)
  /// إذا كان true → view=true والباقي false
  /// إذا كان false → الكل false
  Map<String, bool> _v1ToV2Actions(bool v1Value) {
    return {
      for (final action in PermissionsService.availableActions)
        action: action == 'view' ? v1Value : false,
    };
  }

  /// فك تشفير مصدر JSON (String أو Map)
  Map<String, dynamic>? _decodeJsonSource(dynamic source) {
    if (source == null) return null;

    if (source is Map) {
      return source.map((k, v) => MapEntry(k.toString(), v));
    }

    if (source is String && source.isNotEmpty && source != 'null') {
      try {
        final decoded = jsonDecode(source);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {}
    }

    return null;
  }

  // ══════════════════════════════════════════
  // دوال الفحص الهرمي
  // ══════════════════════════════════════════

  /// فحص إجراء محدد لميزة محددة مع دعم الهرمية
  ///
  /// القاعدة:
  /// 1. إذا المفتاح فرعي (يحتوي نقطة مثل 'accounting.journals'):
  ///    - أولاً: تحقق من الأب ('accounting') → إذا مغلق = false فوراً
  ///    - ثانياً: إذا الأب مفتوح + المفتاح الفرعي موجود → استخدم قيمته
  ///    - ثالثاً: إذا الأب مفتوح + المفتاح الفرعي غير موجود → ورّث من الأب
  /// 2. إذا المفتاح رئيسي: تحقق مباشرة
  bool hasAction(String feature, String action) {
    // تحقق هل هذا مفتاح فرعي
    final entry = PermissionRegistry.findByKey(feature);
    if (entry != null && entry.parent != null) {
      // ──── مفتاح فرعي ← تحقق من الأب أولاً ────
      final parentAllowed = _checkDirect(entry.parent!, action);
      if (!parentAllowed) return false; // الأب مغلق = الابن مغلق

      // الأب مفتوح → تحقق من الابن
      final childResult = _checkDirect(feature, action);
      // إذا الابن غير محدد في البيانات، ورّث من الأب
      if (!_hasKey(feature)) return parentAllowed;
      return childResult;
    }

    // ──── مفتاح رئيسي ← تحقق مباشرة ────
    return _checkDirect(feature, action);
  }

  /// هل المفتاح موجود في البيانات المحملة؟
  bool _hasKey(String feature) {
    return _firstSystemV2.containsKey(feature) ||
        _secondSystemV2.containsKey(feature);
  }

  /// فحص مباشر بدون هرمية
  bool _checkDirect(String feature, String action) {
    final firstActions = _firstSystemV2[feature];
    if (firstActions != null) {
      return firstActions[action] ?? false;
    }

    final secondActions = _secondSystemV2[feature];
    if (secondActions != null) {
      return secondActions[action] ?? false;
    }

    return false;
  }

  /// هل يمكن عرض هذه الميزة؟
  bool canView(String feature) => hasAction(feature, 'view');

  /// هل يمكن إضافة عنصر في هذه الميزة؟
  bool canAdd(String feature) => hasAction(feature, 'add');

  /// هل يمكن تعديل عنصر في هذه الميزة؟
  bool canEdit(String feature) => hasAction(feature, 'edit');

  /// هل يمكن حذف عنصر في هذه الميزة؟
  bool canDelete(String feature) => hasAction(feature, 'delete');

  /// هل يمكن تصدير بيانات هذه الميزة؟
  bool canExport(String feature) => hasAction(feature, 'export');

  /// هل يمكن استيراد بيانات لهذه الميزة؟
  bool canImport(String feature) => hasAction(feature, 'import');

  /// هل يمكن طباعة بيانات هذه الميزة؟
  bool canPrint(String feature) => hasAction(feature, 'print');

  /// هل يمكن إرسال من هذه الميزة؟
  bool canSend(String feature) => hasAction(feature, 'send');

  /// مسح جميع الصلاحيات (عند تسجيل الخروج)
  void clear() {
    _firstSystemV2.clear();
    _secondSystemV2.clear();
    _loaded = false;
  }

  /// الحصول على جميع صلاحيات النظام الأول
  Map<String, Map<String, bool>> get firstSystemPermissions => _firstSystemV2;

  /// الحصول على جميع صلاحيات النظام الثاني
  Map<String, Map<String, bool>> get secondSystemPermissions => _secondSystemV2;

  /// بناء خريطة pageAccess (V1 style) من صلاحيات V2
  /// تُستخدم للتوافق مع الكود القديم الذي يتوقع Map<String, bool>
  Map<String, bool> buildPageAccess() {
    final map = <String, bool>{};
    for (final entry in _firstSystemV2.entries) {
      map[entry.key] = entry.value['view'] == true;
    }
    for (final entry in _secondSystemV2.entries) {
      map[entry.key] = entry.value['view'] == true;
    }
    return map;
  }

  /// منح جميع الصلاحيات (للسوبر أدمن)
  void grantAll(List<String> features) {
    for (final feature in features) {
      final actions = <String, bool>{};
      for (final action in PermissionsService.availableActions) {
        actions[action] = true;
      }
      _firstSystemV2[feature] = actions;
    }
    _loaded = true;
  }

  /// منح جميع صلاحيات النظامين (للسوبر أدمن)
  void grantAllSystems() {
    final actions = <String, bool>{
      for (final action in PermissionsService.availableActions) action: true,
    };
    for (final e in PermissionRegistry.firstSystem) {
      _firstSystemV2[e.key] = Map.from(actions);
    }
    for (final e in PermissionRegistry.secondSystem) {
      _secondSystemV2[e.key] = Map.from(actions);
    }
    _loaded = true;
  }

  /// تطبيق قالب صلاحيات
  Future<void> applyTemplate(String templateName) async {
    final template = PermissionRegistry.getTemplate(templateName);
    final firstPerms = <String, Map<String, bool>>{};
    final secondPerms = <String, Map<String, bool>>{};

    for (final entry in template.entries) {
      final actions = <String, bool>{
        for (final a in PermissionsService.availableActions)
          a: entry.value['actions']?.contains(a) ?? false,
      };

      // حدد أي نظام ينتمي إليه هذا المفتاح
      if (PermissionRegistry.allFirstSystemKeys.contains(entry.key)) {
        firstPerms[entry.key] = actions;
      } else if (PermissionRegistry.allSecondSystemKeys.contains(entry.key)) {
        secondPerms[entry.key] = actions;
      }
    }

    await savePermissions(firstSystem: firstPerms, secondSystem: secondPerms);
  }
}

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

/// Widget لإخفاء/إظهار عنصر حسب الصلاحية
/// أبسط من FeatureGate — يُخفي العنصر بدون رسالة
class PermissionGuard extends StatelessWidget {
  final String feature;
  final String action;
  final Widget child;
  final Widget? fallback;

  const PermissionGuard({
    super.key,
    required this.feature,
    this.action = 'view',
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final pm = PermissionManager.instance;
    if (pm.hasAction(feature, action)) {
      return child;
    }
    return fallback ?? const SizedBox.shrink();
  }
}
