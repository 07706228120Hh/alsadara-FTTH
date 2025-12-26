import 'auth_context.dart';

/// ناتج الدمج مع إمكانية تتبع المصدر لكل صلاحية (اختياري مستقبلاً)
class EffectivePermissions {
  final Map<String, bool> values;
  EffectivePermissions(this.values);
  bool operator [](String key) => values[key] ?? false;
}

class PermissionsMerger {
  static EffectivePermissions merge({
    required Map<String, bool> defaults,
    required Map<String, bool> stored,
    required AuthContext? authCtx,
    required List<String> apiPermissions, // displayValue قائمة من
  }) {
    final out = Map<String, bool>.from(defaults);

    // 1. stored overrides
    for (final e in stored.entries) {
      out[e.key] = e.value;
    }

    // 2. JWT roles implied
    if (authCtx != null) {
      if (authCtx.hasRole('ZoneAdmin')) {
        out['zones'] = true;
        out['export'] = true;
        out['accounts'] = true;
        out['account_records'] = true; // غالباً مطلوب للإدارة
      }
      if (authCtx.hasRole('ContractorMember')) {
        out['users'] = true;
        out['subscriptions'] = true;
        out['tasks'] = true;
      }
    }

    bool hasApi(String contains) =>
        apiPermissions.any((p) => p.contains(contains));

    if (hasApi('Query Zones')) out['zones'] = true;
    if (hasApi('Query Dashboard')) out['users'] = true;
    if (hasApi('Can Transfer')) out['accounts'] = true;

    return EffectivePermissions(out);
  }
}
