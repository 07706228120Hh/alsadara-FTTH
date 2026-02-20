import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// خدمة إدارة أسعار الباقات - تحفظ الأسعار الحقيقية (بدون خصم)
/// لمقارنتها مع المبالغ الفعلية في المعاملات واكتشاف الخصومات
class PlanPricingService {
  static PlanPricingService? _instance;
  static PlanPricingService get instance =>
      _instance ??= PlanPricingService._internal();
  PlanPricingService._internal();

  static const String _storageKey = 'ftth_plan_prices';

  /// خريطة: اسم الباقة → السعر الحقيقي (بالدينار العراقي)
  Map<String, double> _prices = {};
  bool _loaded = false;

  /// تحميل الأسعار المحفوظة
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_storageKey);
    if (json != null) {
      final Map<String, dynamic> data = jsonDecode(json);
      _prices = data.map((k, v) => MapEntry(k, (v as num).toDouble()));
    }
    _loaded = true;
  }

  /// حفظ الأسعار
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_prices));
  }

  /// الحصول على جميع الأسعار
  Map<String, double> get allPrices => Map.unmodifiable(_prices);

  /// الحصول على سعر باقة معينة (null إذا غير محدد)
  double? getPrice(String planName) {
    if (planName.isEmpty) return null;
    // بحث مباشر
    if (_prices.containsKey(planName)) return _prices[planName];
    // بحث جزئي - إذا اسم الباقة يحتوي على اسم مسعّر
    for (final entry in _prices.entries) {
      if (planName.contains(entry.key) || entry.key.contains(planName)) {
        return entry.value;
      }
    }
    return null;
  }

  /// تعيين سعر باقة
  Future<void> setPrice(String planName, double price) async {
    _prices[planName] = price;
    await _save();
  }

  /// حذف سعر باقة
  Future<void> removePrice(String planName) async {
    _prices.remove(planName);
    await _save();
  }

  /// تعيين أسعار متعددة
  Future<void> setPrices(Map<String, double> prices) async {
    _prices.addAll(prices);
    await _save();
  }

  /// حساب الخصم: السعر الحقيقي - المبلغ الفعلي
  /// يُرجع null إذا لا يوجد سعر محدد للباقة
  double? getDiscount(String planName, double actualAmount) {
    final price = getPrice(planName);
    if (price == null) return null;
    final discount = price - actualAmount.abs();
    return discount > 0 ? discount : null;
  }

  /// الأسعار الافتراضية للباقات الشائعة
  static Map<String, double> get defaultPrices => {
        'FIBER 35': 35000,
        'FIBER 50': 50000,
        'FIBER 75': 75000,
        'FIBER 150': 150000,
      };
}
