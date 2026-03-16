import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// خدمة إدارة الميزانية التقديرية — تخزين محلي عبر SharedPreferences
class BudgetService {
  BudgetService._();
  static BudgetService? _instance;
  static BudgetService get instance => _instance ??= BudgetService._();

  String _key(String companyId, int year) => 'budgets_${companyId}_$year';

  Future<List<Map<String, dynamic>>> getBudgets(
      String companyId, int year) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(companyId, year));
    if (raw == null) return [];
    try {
      return (json.decode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> setBudget({
    required String companyId,
    required String accountId,
    required String accountCode,
    required String accountName,
    required int year,
    required int month,
    required double budgetAmount,
    String? notes,
  }) async {
    final budgets = await getBudgets(companyId, year);
    // حذف أي سجل سابق لنفس الحساب والشهر
    budgets.removeWhere(
        (b) => b['accountId'] == accountId && b['month'] == month);
    budgets.add({
      'accountId': accountId,
      'accountCode': accountCode,
      'accountName': accountName,
      'year': year,
      'month': month,
      'budgetAmount': budgetAmount,
      'notes': notes,
      'createdAt': DateTime.now().toIso8601String(),
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(companyId, year), json.encode(budgets));
  }

  Future<void> deleteBudget(
      String companyId, int year, String accountId, int month) async {
    final budgets = await getBudgets(companyId, year);
    budgets.removeWhere(
        (b) => b['accountId'] == accountId && b['month'] == month);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(companyId, year), json.encode(budgets));
  }

  Future<void> copyBudgets(String companyId, int fromYear, int fromMonth,
      int toYear, int toMonth) async {
    final source = await getBudgets(companyId, fromYear);
    final monthBudgets = source.where((b) => b['month'] == fromMonth).toList();
    for (final b in monthBudgets) {
      await setBudget(
        companyId: companyId,
        accountId: b['accountId'],
        accountCode: b['accountCode'],
        accountName: b['accountName'],
        year: toYear,
        month: toMonth,
        budgetAmount: (b['budgetAmount'] as num).toDouble(),
        notes: b['notes'],
      );
    }
  }

  Future<List<Map<String, dynamic>>> getVarianceReport({
    required String companyId,
    required int year,
    required int month,
    required List<dynamic> accounts,
  }) async {
    final budgets = await getBudgets(companyId, year);
    final monthBudgets = budgets.where((b) => b['month'] == month).toList();
    return monthBudgets.map((b) {
      final account = accounts.firstWhere(
        (a) => a['Id']?.toString() == b['accountId']?.toString(),
        orElse: () => <String, dynamic>{},
      );
      final actual = ((account['CurrentBalance'] ??
                  account['Balance'] ??
                  0) as num)
              .toDouble()
              .abs();
      final budget = (b['budgetAmount'] as num).toDouble();
      final variance = actual - budget;
      final variancePercent = budget > 0 ? (variance / budget * 100) : 0.0;
      return {
        'accountId': b['accountId'],
        'accountCode': b['accountCode'],
        'accountName': b['accountName'],
        'budget': budget,
        'actual': actual,
        'variance': variance,
        'variancePercent': variancePercent,
        'overBudget': variance > 0,
      };
    }).toList();
  }
}
