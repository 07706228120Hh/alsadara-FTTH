/// ═══════════════════════════════════════════════════════════════
/// مدير الصلاحيات الموحد — Singleton مع دعم هرمي
/// ═══════════════════════════════════════════════════════════════
///
/// القاعدة الهرمية:
///   - إذا الأب مغلق ← جميع الأبناء مغلقة تلقائياً
///   - إذا الأب مفتوح + الابن غير محدد ← يرث من الأب
///   - إذا الأب مفتوح + الابن محدد ← يستخدم قيمة الابن
///
/// الاستخدام:
/// ```dart
/// final pm = PermissionManager.instance;
/// if (pm.canView('accounting.journals'))  // ...
/// if (pm.canAdd('hr.employees'))          // ...
/// if (pm.hasAction('tasks', 'edit'))      // ...
/// ```
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'permission_service.dart';
import 'permission_registry.dart';

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
      case PermissionAction.export:
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

/// مدير الصلاحيات الموحد — Singleton
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

  // ══════════════════════════════════════════
  // تحميل وحفظ الصلاحيات
  // ══════════════════════════════════════════

  /// تحميل الصلاحيات من PermissionService (SharedPreferences)
  Future<void> loadPermissions() async {
    try {
      _firstSystemV2 = await PermissionService.getFirstSystemPermissionsV2();
      _secondSystemV2 = await PermissionService.getSecondSystemPermissionsV2();
      _loaded = true;
      debugPrint('✅ PermissionManager: تم تحميل الصلاحيات');
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

    await PermissionService.saveFirstSystemPermissionsV2(firstSystem);
    await PermissionService.saveSecondSystemPermissionsV2(secondSystem);

    debugPrint('💾 PermissionManager: تم حفظ الصلاحيات');
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
          for (final action in PermissionService.availableActions) {
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
            result[feature] = {};
            for (final action in PermissionService.availableActions) {
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
  Map<String, bool> _v1ToV2Actions(bool v1Value) {
    return {
      for (final action in PermissionService.availableActions)
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

  // ══════════════════════════════════════════
  // اختصارات للإجراءات الشائعة
  // ══════════════════════════════════════════

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

  // ══════════════════════════════════════════
  // إدارة الصلاحيات
  // ══════════════════════════════════════════

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

  /// بناء خريطة pageAccess (V1 style) — للتوافق مع الكود القديم
  @Deprecated('استخدم canView() مباشرة بدلاً من pageAccess')
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
      for (final action in PermissionService.availableActions) {
        actions[action] = true;
      }
      _firstSystemV2[feature] = actions;
    }
    _loaded = true;
  }

  /// منح جميع صلاحيات النظامين (للسوبر أدمن)
  void grantAllSystems() {
    final actions = <String, bool>{
      for (final action in PermissionService.availableActions) action: true,
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
        for (final a in PermissionService.availableActions)
          a: entry.value['actions']?.contains(a) ?? false,
      };

      if (PermissionRegistry.allFirstSystemKeys.contains(entry.key)) {
        firstPerms[entry.key] = actions;
      } else if (PermissionRegistry.allSecondSystemKeys.contains(entry.key)) {
        secondPerms[entry.key] = actions;
      }
    }

    await savePermissions(firstSystem: firstPerms, secondSystem: secondPerms);
  }
}
