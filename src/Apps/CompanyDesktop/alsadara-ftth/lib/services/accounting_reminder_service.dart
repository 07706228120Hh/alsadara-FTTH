import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'accounting_service.dart';

class AccountingReminderService {
  AccountingReminderService._();
  static AccountingReminderService? _instance;
  static AccountingReminderService get instance =>
      _instance ??= AccountingReminderService._();

  Timer? _checkTimer;

  void startChecks(String companyId) {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _runAllChecks(companyId);
    });
    _runAllChecks(companyId);
  }

  void stopChecks() { _checkTimer?.cancel(); }

  Future<void> _runAllChecks(String companyId) async {
    await _checkUnpaidFixedExpenses(companyId);
    await _checkSalaryGeneration(companyId);
  }

  // Check 1: Fixed expenses not paid this month (after day 5)
  Future<void> _checkUnpaidFixedExpenses(String companyId) async {
    final now = DateTime.now();
    if (now.day < 5) return;
    final prefs = await SharedPreferences.getInstance();
    final dismissKey = 'reminder_fixed_${now.year}_${now.month}';
    if (prefs.getBool(dismissKey) == true) return;

    try {
      final paymentsResult = await AccountingService.instance.getFixedExpensePayments(
        companyId: companyId, month: now.month, year: now.year,
      );
      final fixedResult = await AccountingService.instance.getFixedExpenses(
        companyId: companyId,
      );
      if (paymentsResult['success'] == true && fixedResult['success'] == true) {
        final payments = (paymentsResult['data'] is List) ? paymentsResult['data'] as List : [];
        final fixed = (fixedResult['data'] is List) ? fixedResult['data'] as List : [];
        final paidIds = payments.map((p) => p['FixedExpenseId']).toSet();
        final unpaidCount = fixed.where((f) => !paidIds.contains(f['Id'])).length;
        if (unpaidCount > 0) {
          // Store reminder state - pages can check this
          await prefs.setString('reminder_fixed_msg', 'يوجد $unpaidCount مصروف ثابت غير مسدد');
        }
      }
    } catch (_) {}
  }

  // Check 2: Salary generation (after day 25)
  Future<void> _checkSalaryGeneration(String companyId) async {
    final now = DateTime.now();
    if (now.day < 25) return;
    final prefs = await SharedPreferences.getInstance();
    final dismissKey = 'reminder_salary_${now.year}_${now.month}';
    if (prefs.getBool(dismissKey) == true) return;

    try {
      final result = await AccountingService.instance.getSalaries(
        companyId: companyId, month: now.month, year: now.year,
      );
      if (result['success'] == true) {
        final salaries = (result['data'] is List) ? result['data'] as List : [];
        if (salaries.isEmpty) {
          await prefs.setString('reminder_salary_msg', 'لم يتم توليد رواتب شهر ${now.month}/${now.year}');
        }
      }
    } catch (_) {}
  }

  Future<void> dismiss(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }

  Future<String?> getFixedExpenseReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    if (prefs.getBool('reminder_fixed_${now.year}_${now.month}') == true) return null;
    return prefs.getString('reminder_fixed_msg');
  }

  Future<String?> getSalaryReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    if (prefs.getBool('reminder_salary_${now.year}_${now.month}') == true) return null;
    return prefs.getString('reminder_salary_msg');
  }
}
