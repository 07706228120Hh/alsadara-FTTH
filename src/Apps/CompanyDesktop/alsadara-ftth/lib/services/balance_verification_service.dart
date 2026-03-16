import 'accounting_service.dart';

/// خدمة تحقق التوازن المحاسبي
/// تتحقق أن مجموع المدين = مجموع الدائن عبر كل الحسابات
class BalanceVerificationService {
  BalanceVerificationService._internal();
  static BalanceVerificationService? _instance;
  static BalanceVerificationService get instance =>
      _instance ??= BalanceVerificationService._internal();

  /// التحقق من توازن الحسابات
  /// يعيد Map يحتوي:
  /// - isBalanced: bool
  /// - totalDebits: double
  /// - totalCredits: double
  /// - difference: double
  /// - accountCount: int
  static Future<Map<String, dynamic>> verify({String? companyId}) async {
    try {
      final result = await AccountingService.instance
          .getAccounts(companyId: companyId);

      if (result['success'] != true) {
        return {
          'isBalanced': false,
          'error': result['message'] ?? 'خطأ في جلب البيانات',
          'totalDebits': 0.0,
          'totalCredits': 0.0,
          'difference': 0.0,
          'accountCount': 0,
        };
      }

      final accounts = (result['data'] is List) ? result['data'] as List : [];
      final leafAccounts =
          accounts.where((a) => a is Map && a['IsLeaf'] == true).toList();

      double totalDebits = 0;
      double totalCredits = 0;

      for (final a in leafAccounts) {
        final bal =
            ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble();
        if (bal > 0) {
          totalDebits += bal;
        } else if (bal < 0) {
          totalCredits += bal.abs();
        }
      }

      final difference = (totalDebits - totalCredits).abs();

      return {
        'isBalanced': difference < 0.01,
        'totalDebits': totalDebits,
        'totalCredits': totalCredits,
        'difference': difference,
        'accountCount': leafAccounts.length,
      };
    } catch (e) {
      return {
        'isBalanced': false,
        'error': 'خطأ',
        'totalDebits': 0.0,
        'totalCredits': 0.0,
        'difference': 0.0,
        'accountCount': 0,
      };
    }
  }
}
