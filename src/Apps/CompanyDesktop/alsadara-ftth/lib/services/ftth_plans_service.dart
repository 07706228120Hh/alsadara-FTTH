import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// مصدر الحقيقة الموحّد لباقات FTTH.
///
/// يجلب أسماء الباقات ديناميكياً من واجهة المزوّد `/api/plans/bundles`
/// (المصدر: `applicableSubscriptionsNames` — مثل BASIC/PLUS/TURBO/PRO MAX)
/// ويخزّنها مؤقتاً في SharedPreferences لسرعة الإقلاع والعمل دون اتصال.
///
/// يوفّر أيضاً أسماء الباقات القديمة (FIBER 35/50/75/100/150) كاحتياطي في
/// قوائم الفلاتر والتقارير حتى لا تنكسر البيانات التاريخية المسجّلة بالأسماء القديمة.
class FtthPlansService {
  FtthPlansService._();
  static final FtthPlansService instance = FtthPlansService._();

  static const String _cachePlansKey = 'ftth_active_plans_cache_v1';
  static const String _cachePricesKey = 'ftth_plan_prices_cache_v1';

  /// أسماء الباقات القديمة — للبيانات التاريخية في التقارير/الفلاتر فقط.
  static const List<String> legacyPlanNames = <String>[
    'FIBER 35',
    'FIBER 50',
    'FIBER 75',
    'FIBER 100',
    'FIBER 150',
  ];

  /// احتياطي نهائي إن تعذّر الجلب والكاش (الباقات الحالية المعروفة).
  static const List<String> fallbackActivePlans = <String>[
    'BASIC',
    'PLUS',
    'TURBO',
    'PRO MAX',
  ];

  /// ربط الباقة (قديمة أو جديدة) بمرادفها الفعّال — مطابق لجدول `plansDisplayInfo`
  /// في `/api/configurations` بالبوّابة الرسمية (نفس الفئة/السرعة):
  /// FIBER 35→BASIC(60)، FIBER 50→PLUS(125)، FIBER 75→TURBO(250)، FIBER 150→PRO MAX(500).
  /// الخادم يقبل اسم الباقة الفعّالة فقط في `services[].value` عند الـChange/التجديد،
  /// لذا نحوّل الاسم القديم إلى مرادفه قبل الإرسال (كما يفعل البورتل تماماً).
  static const Map<String, String> _activeEquivalentByPlan = <String, String>{
    'FIBER 35': 'BASIC',
    'FIBER 50': 'PLUS',
    'FIBER 75': 'TURBO',
    'FIBER 150': 'PRO MAX',
    'BASIC': 'BASIC',
    'PLUS': 'PLUS',
    'TURBO': 'TURBO',
    'PRO MAX': 'PRO MAX',
  };

  /// الاسم العربي المعروض لكل فئة (مطابق `plansDisplayInfo.arabicName`).
  static const Map<String, String> _arabicNameByTier = <String, String>{
    'BASIC': 'أساسي',
    'PLUS': 'بلس',
    'TURBO': 'تيربو',
    'PRO MAX': 'برو ماكس',
  };

  static String _normalizePlanKey(String? name) =>
      (name ?? '').trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

  /// الباقة الفعّالة المكافئة لأي باقة (قديمة أو جديدة)، أو null إن تعذّر التحويل.
  static String? activeEquivalentPlan(String? plan) {
    final k = _normalizePlanKey(plan);
    if (k.isEmpty) return null;
    return _activeEquivalentByPlan[k];
  }

  /// الاسم العربي المعروض للباقة (مثل البوّابة: «Fiber 35» → «أساسي»)،
  /// وإلا يُعيد الاسم كما هو.
  static String displayName(String? plan) {
    final tier = activeEquivalentPlan(plan);
    if (tier != null) return _arabicNameByTier[tier] ?? tier;
    return (plan ?? '').trim();
  }

  List<String>? _activePlans; // كاش في الذاكرة
  Map<String, double>? _prices; // كاش أسعار في الذاكرة

  /// أسماء الباقات الفعّالة حالياً (تُستخدم في قوائم الاختيار: التجديد/الشراء).
  Future<List<String>> getActivePlanNames({
    String? subscriptionId,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _activePlans != null && _activePlans!.isNotEmpty) {
      return _activePlans!;
    }

    // 1) كاش مخزّن (يظهر فوراً ريثما يصل الجلب الحيّ)
    if (!forceRefresh) {
      final cached = await _readCachedPlans();
      if (cached.isNotEmpty) _activePlans = cached;
    }

    // 2) جلب حيّ من الـ API
    try {
      final base =
          'https://admin.ftth.iq/api/plans/bundles?includePrices=false';
      final url = (subscriptionId != null && subscriptionId.isNotEmpty)
          ? '$base&subscriptionId=$subscriptionId'
          : base;
      final resp = await AuthService.instance
          .authenticatedRequest('GET', url)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final parsed = parsePlanNames(jsonDecode(resp.body));
        if (parsed.isNotEmpty) {
          _activePlans = parsed;
          await _writeCachedPlans(parsed);
        }
      }
    } catch (_) {
      // نتجاهل الخطأ ونعتمد على الكاش/الاحتياطي
    }

    if (_activePlans != null && _activePlans!.isNotEmpty) return _activePlans!;
    final cached = await _readCachedPlans();
    return cached.isNotEmpty ? cached : List<String>.from(fallbackActivePlans);
  }

  /// قائمة موحّدة للفلاتر/التقارير: الباقات الفعّالة + القديمة + أي أسماء من البيانات.
  /// تضمن ظهور الأسماء القديمة والجديدة معاً فلا تنكسر التقارير التاريخية.
  Future<List<String>> getFilterPlanNames({
    Iterable<String> fromData = const <String>[],
  }) async {
    final active = await getActivePlanNames();
    final result = <String>[];
    void addAll(Iterable<String> src) {
      for (final p in src) {
        final s = p.trim();
        if (s.isNotEmpty && !result.contains(s)) result.add(s);
      }
    }

    addAll(active);
    addAll(legacyPlanNames);
    addAll(fromData);
    return result;
  }

  /// أسعار الباقات (لكشف الخصومات) من bundles مع includePrices=true.
  /// المفتاح = اسم الباقة، القيمة = السعر الأساسي (IQD).
  Future<Map<String, double>> getPlanPrices({bool forceRefresh = false}) async {
    if (!forceRefresh && _prices != null && _prices!.isNotEmpty) {
      return _prices!;
    }
    final cached = await _readCachedPrices();
    if (cached.isNotEmpty) _prices = cached;

    try {
      final resp = await AuthService.instance
          .authenticatedRequest('GET',
              'https://admin.ftth.iq/api/plans/bundles?includePrices=true')
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final p = _parsePrices(jsonDecode(resp.body));
        if (p.isNotEmpty) {
          _prices = p;
          await _writeCachedPrices(p);
        }
      }
    } catch (_) {}

    return _prices ?? cached;
  }

  /// تحليل استجابة bundles لاستخراج أسماء الباقات المتاحة.
  static List<String> parsePlanNames(dynamic data) {
    try {
      final items = (data is Map) ? data['items'] : null;
      if (items is! List || items.isEmpty) return const <String>[];
      final names = <String>[];
      for (final item in items) {
        if (item is! Map) continue;
        final appNames = item['applicableSubscriptionsNames'];
        if (appNames is List) {
          for (final n in appNames) {
            final s = n?.toString().trim() ?? '';
            if (s.isNotEmpty && !names.contains(s)) names.add(s);
          }
        }
      }
      // مصدر بديل إن غابت applicableSubscriptionsNames: basePlanId/planName
      if (names.isEmpty) {
        for (final item in items) {
          if (item is! Map) continue;
          final subs = item['applicableSubscriptions'];
          if (subs is List) {
            for (final s in subs) {
              if (s is Map) {
                final p =
                    (s['basePlanId'] ?? s['planName'])?.toString().trim() ?? '';
                if (p.isNotEmpty && !names.contains(p)) names.add(p);
              }
            }
          }
        }
      }
      return names;
    } catch (_) {
      return const <String>[];
    }
  }

  Map<String, double> _parsePrices(dynamic data) {
    final map = <String, double>{};
    try {
      final items = (data is Map) ? data['items'] : null;
      if (items is! List) return map;
      for (final item in items) {
        if (item is! Map) continue;
        final subs = item['applicableSubscriptions'];
        if (subs is! List) continue;
        for (final s in subs) {
          if (s is! Map) continue;
          final name = (s['planName'] ?? s['basePlanId'])?.toString().trim() ??
              '';
          if (name.isEmpty) continue;
          final priceObj = s['price'] ?? s['billingPrice'];
          double? val;
          if (priceObj is Map && priceObj['value'] != null) {
            val = double.tryParse(priceObj['value'].toString());
          }
          if (val != null && val > 0) map[name] = val;
        }
      }
    } catch (_) {}
    return map;
  }

  Future<List<String>> _readCachedPlans() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachePlansKey);
      if (raw == null) return const <String>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _writeCachedPlans(List<String> plans) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachePlansKey, jsonEncode(plans));
    } catch (_) {}
  }

  Future<Map<String, double>> _readCachedPrices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachePricesKey);
      if (raw == null) return <String, double>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, double>{};
      return decoded.map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()));
    } catch (_) {
      return <String, double>{};
    }
  }

  Future<void> _writeCachedPrices(Map<String, double> prices) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachePricesKey, jsonEncode(prices));
    } catch (_) {}
  }
}
