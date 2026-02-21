import 'api/api_client.dart';
import 'api/api_response.dart';

/// خدمة المحاسبة - تتصل بـ AccountingController على السيرفر
class AccountingService {
  static AccountingService? _instance;
  static AccountingService get instance =>
      _instance ??= AccountingService._internal();

  AccountingService._internal();

  final _client = ApiClient.instance;

  /// تحويل ApiResponse إلى Map
  Map<String, dynamic> _toMap<T>(ApiResponse<T> response) {
    if (response.success) {
      return {
        'success': true,
        'data': response.data,
        'statusCode': response.statusCode,
      };
    } else {
      return {
        'success': false,
        'message': response.message ?? 'خطأ غير معروف',
        'error': response.message ?? 'خطأ غير معروف',
        'statusCode': response.statusCode,
      };
    }
  }

  // ═══════════════════════════════════════════
  // شجرة الحسابات - Chart of Accounts
  // ═══════════════════════════════════════════

  /// جلب قائمة الحسابات
  Future<Map<String, dynamic>> getAccounts({String? companyId}) async {
    String query = '/accounting/accounts';
    if (companyId != null) query += '?companyId=$companyId';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// جلب شجرة الحسابات الهرمية
  Future<Map<String, dynamic>> getAccountsTree({String? companyId}) async {
    String query = '/accounting/accounts/tree';
    if (companyId != null) query += '?companyId=$companyId';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// إنشاء حساب جديد
  Future<Map<String, dynamic>> createAccount({
    required String code,
    required String name,
    String? nameEn,
    required String accountType,
    String? parentAccountId,
    double openingBalance = 0,
    String? description,
    required String companyId,
  }) async {
    final body = {
      'Code': code,
      'Name': name,
      'NameEn': nameEn,
      'AccountType': accountType,
      'ParentAccountId': parentAccountId,
      'OpeningBalance': openingBalance,
      'Description': description,
      'CompanyId': companyId,
    };
    body.removeWhere((key, value) => value == null);
    final response =
        await _client.post('/accounting/accounts', body, (json) => json);
    return _toMap(response);
  }

  /// تعديل حساب
  Future<Map<String, dynamic>> updateAccount(
    String id, {
    required String name,
    String? nameEn,
    String? description,
    bool? isActive,
    double? openingBalance,
  }) async {
    final body = <String, dynamic>{
      'Name': name,
      'NameEn': nameEn,
      'Description': description,
      'IsActive': isActive,
      'OpeningBalance': openingBalance,
    };
    body.removeWhere((key, value) => value == null);
    final response =
        await _client.put('/accounting/accounts/$id', body, (json) => json);
    return _toMap(response);
  }

  /// حذف حساب
  Future<Map<String, dynamic>> deleteAccount(String id) async {
    final response =
        await _client.delete('/accounting/accounts/$id', (json) => json);
    return _toMap(response);
  }

  /// تهيئة الحسابات الافتراضية
  Future<Map<String, dynamic>> seedAccounts({required String companyId}) async {
    final response = await _client.post(
      '/accounting/accounts/seed',
      {'CompanyId': companyId},
      (json) => json,
    );
    return _toMap(response);
  }

  // ═══════════════════════════════════════════
  // القيود المحاسبية - Journal Entries
  // ═══════════════════════════════════════════

  /// جلب القيود المحاسبية
  Future<Map<String, dynamic>> getJournalEntries({
    String? companyId,
    String? status,
    String? fromDate,
    String? toDate,
  }) async {
    String query = '/accounting/journal-entries?';
    if (companyId != null) query += 'companyId=$companyId&';
    if (status != null) query += 'status=$status&';
    if (fromDate != null) query += 'fromDate=$fromDate&';
    if (toDate != null) query += 'toDate=$toDate&';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// جلب قيد بالمعرف
  Future<Map<String, dynamic>> getJournalEntry(String id) async {
    final response =
        await _client.get('/accounting/journal-entries/$id', (json) => json);
    return _toMap(response);
  }

  /// إنشاء قيد محاسبي
  Future<Map<String, dynamic>> createJournalEntry({
    required String description,
    required String companyId,
    String? notes,
    String? createdById,
    required List<Map<String, dynamic>> lines,
  }) async {
    final body = <String, dynamic>{
      'Description': description,
      'CompanyId': companyId,
      'Notes': notes,
      'CreatedById': createdById,
      'Lines': lines,
    };
    body.removeWhere((key, value) => value == null);
    final response = await _client.post(
      '/accounting/journal-entries',
      body,
      (json) => json,
    );
    return _toMap(response);
  }

  /// ترحيل قيد
  Future<Map<String, dynamic>> postJournalEntry(String id,
      {String? approvedById}) async {
    final body = <String, dynamic>{
      'ApprovedById': approvedById,
    };
    body.removeWhere((key, value) => value == null);
    final response = await _client.post(
      '/accounting/journal-entries/$id/post',
      body,
      (json) => json,
    );
    return _toMap(response);
  }

  /// إلغاء قيد
  Future<Map<String, dynamic>> voidJournalEntry(String id,
      {String? reason}) async {
    final response = await _client.post(
      '/accounting/journal-entries/$id/void',
      {'Reason': reason},
      (json) => json,
    );
    return _toMap(response);
  }

  // ═══════════════════════════════════════════
  // الصناديق - Cash Boxes
  // ═══════════════════════════════════════════

  /// جلب الصناديق
  Future<Map<String, dynamic>> getCashBoxes({String? companyId}) async {
    String query = '/accounting/cashboxes';
    if (companyId != null) query += '?companyId=$companyId';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// تحويل نوع الصندوق من نص إلى رقم enum
  static int _cashBoxTypeToInt(String type) {
    switch (type) {
      case 'Main':
        return 0;
      case 'PettyCash':
        return 1;
      case 'Bank':
        return 2;
      default:
        return 0;
    }
  }

  /// إنشاء صندوق
  Future<Map<String, dynamic>> createCashBox({
    required String name,
    required String cashBoxType,
    double initialBalance = 0,
    String? responsibleUserId,
    String? linkedAccountId,
    String? notes,
    required String companyId,
  }) async {
    final body = <String, dynamic>{
      'Name': name,
      'CashBoxType': _cashBoxTypeToInt(cashBoxType),
      'InitialBalance': initialBalance,
      'ResponsibleUserId': responsibleUserId,
      'LinkedAccountId': linkedAccountId,
      'Notes': notes,
      'CompanyId': companyId,
    };
    body.removeWhere((key, value) => value == null);
    final response =
        await _client.post('/accounting/cashboxes', body, (json) => json);
    return _toMap(response);
  }

  /// جلب معاملات صندوق
  Future<Map<String, dynamic>> getCashBoxTransactions(String cashBoxId) async {
    final response = await _client.get(
      '/accounting/cashboxes/$cashBoxId/transactions',
      (json) => json,
    );
    return _toMap(response);
  }

  /// إيداع في صندوق
  Future<Map<String, dynamic>> depositToCashBox(
    String cashBoxId, {
    required double amount,
    required String description,
  }) async {
    final response = await _client.post(
      '/accounting/cashboxes/$cashBoxId/deposit',
      {'Amount': amount, 'Description': description},
      (json) => json,
    );
    return _toMap(response);
  }

  /// سحب من صندوق
  Future<Map<String, dynamic>> withdrawFromCashBox(
    String cashBoxId, {
    required double amount,
    required String description,
  }) async {
    final response = await _client.post(
      '/accounting/cashboxes/$cashBoxId/withdraw',
      {'Amount': amount, 'Description': description},
      (json) => json,
    );
    return _toMap(response);
  }

  // ═══════════════════════════════════════════
  // الرواتب - Salaries
  // ═══════════════════════════════════════════

  /// جلب الرواتب
  Future<Map<String, dynamic>> getSalaries({
    String? companyId,
    int? month,
    int? year,
    String? status,
  }) async {
    String query = '/accounting/salaries?';
    if (companyId != null) query += 'companyId=$companyId&';
    if (month != null) query += 'month=$month&';
    if (year != null) query += 'year=$year&';
    if (status != null) query += 'status=$status&';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// توليد رواتب الشهر
  Future<Map<String, dynamic>> generateSalaries({
    required int month,
    required int year,
    required String companyId,
  }) async {
    final response = await _client.post(
      '/accounting/salaries/generate',
      {'Month': month, 'Year': year, 'CompanyId': companyId},
      (json) => json,
    );
    return _toMap(response);
  }

  /// تعديل راتب
  Future<Map<String, dynamic>> updateSalary(
    String id, {
    double? allowances,
    double? deductions,
    double? bonuses,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'Allowances': allowances,
      'Deductions': deductions,
      'Bonuses': bonuses,
      'Notes': notes,
    };
    body.removeWhere((key, value) => value == null);
    final response =
        await _client.put('/accounting/salaries/$id', body, (json) => json);
    return _toMap(response);
  }

  /// صرف راتب واحد
  Future<Map<String, dynamic>> paySalary(String id) async {
    final response =
        await _client.post('/accounting/salaries/$id/pay', {}, (json) => json);
    return _toMap(response);
  }

  /// صرف جميع الرواتب
  Future<Map<String, dynamic>> payAllSalaries({
    required int month,
    required int year,
    required String companyId,
  }) async {
    final response = await _client.post(
      '/accounting/salaries/pay-all',
      {'Month': month, 'Year': year, 'CompanyId': companyId},
      (json) => json,
    );
    return _toMap(response);
  }

  // ═══════════════════════════════════════════
  // تحصيلات الفنيين - Technician Collections
  // ═══════════════════════════════════════════

  /// جلب التحصيلات
  Future<Map<String, dynamic>> getCollections({
    String? companyId,
    String? technicianId,
    bool? isDelivered,
    String? fromDate,
    String? toDate,
  }) async {
    String query = '/accounting/collections?';
    if (companyId != null) query += 'companyId=$companyId&';
    if (technicianId != null) query += 'technicianId=$technicianId&';
    if (isDelivered != null) query += 'isDelivered=$isDelivered&';
    if (fromDate != null) query += 'fromDate=$fromDate&';
    if (toDate != null) query += 'toDate=$toDate&';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// إضافة تحصيل
  Future<Map<String, dynamic>> createCollection({
    required String technicianId,
    String? citizenId,
    String? serviceRequestId,
    required double amount,
    required String description,
    String? paymentMethod,
    String? receiptNumber,
    String? receivedBy,
    String? notes,
    required String companyId,
  }) async {
    final body = <String, dynamic>{
      'TechnicianId': technicianId,
      'CitizenId': citizenId,
      'ServiceRequestId': serviceRequestId,
      'Amount': amount,
      'Description': description,
      'PaymentMethod': paymentMethod,
      'ReceiptNumber': receiptNumber,
      'ReceivedBy': receivedBy,
      'Notes': notes,
      'CompanyId': companyId,
    };
    body.removeWhere((key, value) => value == null);
    final response =
        await _client.post('/accounting/collections', body, (json) => json);
    return _toMap(response);
  }

  /// تسليم تحصيل للصندوق
  Future<Map<String, dynamic>> deliverCollection(
    String id, {
    required String cashBoxId,
  }) async {
    final response = await _client.post(
      '/accounting/collections/$id/deliver',
      {'CashBoxId': cashBoxId},
      (json) => json,
    );
    return _toMap(response);
  }

  /// ملخص تحصيلات فني
  Future<Map<String, dynamic>> getTechnicianCollectionSummary(
      String technicianId) async {
    final response = await _client.get(
      '/accounting/collections/technician/$technicianId/summary',
      (json) => json,
    );
    return _toMap(response);
  }

  // ═══════════════════════════════════════════
  // مستحقات الفنيين - Technician Dues
  // ═══════════════════════════════════════════

  /// جلب ملخص مستحقات جميع الفنيين
  Future<Map<String, dynamic>> getTechnicianDues() async {
    final response = await _client.get(
      '/techniciantransactions/all-dues',
      (json) => json,
    );
    return _toMap(response);
  }

  /// جلب معاملات فني محدد
  Future<Map<String, dynamic>> getTechnicianTransactions(String technicianId,
      {int page = 1, int pageSize = 50}) async {
    final response = await _client.get(
      '/techniciantransactions/by-technician/$technicianId?page=$page&pageSize=$pageSize',
      (json) => json,
    );
    return _toMap(response);
  }

  /// تسجيل تسديد من فني
  Future<Map<String, dynamic>> recordTechnicianPayment({
    required String technicianId,
    required double amount,
    String? description,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'TechnicianId': technicianId,
      'Amount': amount,
      'Description': description,
      'Notes': notes,
    };
    body.removeWhere((key, value) => value == null);
    final response = await _client.post(
      '/techniciantransactions/record-payment',
      body,
      (json) => json,
    );
    return _toMap(response);
  }

  /// تعديل معاملة فني
  Future<Map<String, dynamic>> updateTechnicianTransaction({
    required String transactionId,
    double? amount,
    String? description,
    String? notes,
    int? type,
    int? category,
    String? referenceNumber,
    String? receivedBy,
  }) async {
    final body = <String, dynamic>{
      if (amount != null) 'Amount': amount,
      if (description != null) 'Description': description,
      if (notes != null) 'Notes': notes,
      if (type != null) 'Type': type,
      if (category != null) 'Category': category,
      if (referenceNumber != null) 'ReferenceNumber': referenceNumber,
      if (receivedBy != null) 'ReceivedBy': receivedBy,
    };
    final response = await _client.put(
      '/techniciantransactions/$transactionId',
      body,
      (json) => json,
    );
    return _toMap(response);
  }

  /// حذف معاملة فني
  Future<Map<String, dynamic>> deleteTechnicianTransaction(
      String transactionId) async {
    final response = await _client.delete(
      '/techniciantransactions/$transactionId',
      (json) => json,
    );
    return _toMap(response);
  }

  // ═══════════════════════════════════════════
  // المصروفات - Expenses
  // ═══════════════════════════════════════════

  /// جلب المصروفات
  Future<Map<String, dynamic>> getExpenses({
    String? companyId,
    String? fromDate,
    String? toDate,
    String? category,
  }) async {
    String query = '/accounting/expenses?';
    if (companyId != null) query += 'companyId=$companyId&';
    if (fromDate != null) query += 'fromDate=$fromDate&';
    if (toDate != null) query += 'toDate=$toDate&';
    if (category != null) query += 'category=${Uri.encodeComponent(category)}&';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// إضافة مصروف
  Future<Map<String, dynamic>> createExpense({
    required String accountId,
    required double amount,
    required String description,
    String? category,
    String? paidFromCashBoxId,
    String? attachmentUrl,
    String? notes,
    required String companyId,
    String? createdById,
  }) async {
    final body = <String, dynamic>{
      'AccountId': accountId,
      'Amount': amount,
      'Description': description,
      'Category': category,
      'PaidFromCashBoxId': paidFromCashBoxId,
      'AttachmentUrl': attachmentUrl,
      'Notes': notes,
      'CompanyId': companyId,
      'CreatedById': createdById,
    };
    body.removeWhere((key, value) => value == null);
    final response =
        await _client.post('/accounting/expenses', body, (json) => json);
    return _toMap(response);
  }

  // ═══════════════════════════════════════════
  // التقارير ولوحة القيادة
  // ═══════════════════════════════════════════

  /// لوحة القيادة المالية
  Future<Map<String, dynamic>> getDashboard({String? companyId}) async {
    String query = '/accounting/dashboard';
    if (companyId != null) query += '?companyId=$companyId';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// كشف حساب
  Future<Map<String, dynamic>> getAccountStatement(
    String accountId, {
    String? fromDate,
    String? toDate,
  }) async {
    String query = '/accounting/accounts/$accountId/statement?';
    if (fromDate != null) query += 'fromDate=$fromDate&';
    if (toDate != null) query += 'toDate=$toDate&';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// ميزان المراجعة
  Future<Map<String, dynamic>> getTrialBalance({String? companyId}) async {
    String query = '/accounting/reports/trial-balance';
    if (companyId != null) query += '?companyId=$companyId';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  // ═══════════════════════════════════════════
  // تعديل وحذف - Edit & Delete
  // ═══════════════════════════════════════════

  /// تعديل مصروف
  Future<Map<String, dynamic>> updateExpense(
      String id, Map<String, dynamic> body) async {
    final response =
        await _client.put('/accounting/expenses/$id', body, (json) => json);
    return _toMap(response);
  }

  /// حذف مصروف
  Future<Map<String, dynamic>> deleteExpense(String id) async {
    final response =
        await _client.delete('/accounting/expenses/$id', (json) => json);
    return _toMap(response);
  }

  /// تعديل تحصيل
  Future<Map<String, dynamic>> updateCollection(
      String id, Map<String, dynamic> body) async {
    final response =
        await _client.put('/accounting/collections/$id', body, (json) => json);
    return _toMap(response);
  }

  /// حذف تحصيل
  Future<Map<String, dynamic>> deleteCollection(String id) async {
    final response =
        await _client.delete('/accounting/collections/$id', (json) => json);
    return _toMap(response);
  }

  /// تعديل صندوق
  Future<Map<String, dynamic>> updateCashBox(
      String id, Map<String, dynamic> body) async {
    final response =
        await _client.put('/accounting/cashboxes/$id', body, (json) => json);
    return _toMap(response);
  }

  /// حذف صندوق
  Future<Map<String, dynamic>> deleteCashBox(String id) async {
    final response =
        await _client.delete('/accounting/cashboxes/$id', (json) => json);
    return _toMap(response);
  }

  /// تعديل قيد محاسبي
  Future<Map<String, dynamic>> updateJournalEntry(
      String id, Map<String, dynamic> body) async {
    final response = await _client.put(
        '/accounting/journal-entries/$id', body, (json) => json);
    return _toMap(response);
  }

  /// حذف قيد محاسبي
  Future<Map<String, dynamic>> deleteJournalEntry(String id) async {
    final response =
        await _client.delete('/accounting/journal-entries/$id', (json) => json);
    return _toMap(response);
  }

  /// حذف راتب
  Future<Map<String, dynamic>> deleteSalary(String id) async {
    final response =
        await _client.delete('/accounting/salaries/$id', (json) => json);
    return _toMap(response);
  }

  /// جلب موظفي الشركة (للبحث عن الفنيين)
  Future<List<Map<String, dynamic>>> getCompanyEmployees(
      String companyId) async {
    final response = await _client.get(
      '/internal/companies/$companyId/employees',
      (json) => json,
      useInternalKey: true,
    );
    if (response.success && response.data != null) {
      final data = response.data;
      List items;
      if (data is List) {
        items = data;
      } else if (data is Map) {
        items = (data['data'] ?? data['users'] ?? []) as List;
      } else {
        items = [];
      }
      return items
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return [];
  }

  // ═══════════════════════════════════════════
  // تكامل FTTH - ربط المشغلين والمزامنة
  // ═══════════════════════════════════════════

  /// جلب قائمة المشغلين مع حالة الربط
  Future<Map<String, dynamic>> getOperatorsLinking({String? companyId}) async {
    String query = '/ftth-accounting/operators-linking';
    if (companyId != null) query += '?companyId=$companyId';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// ربط حساب FTTH بمستخدم
  Future<Map<String, dynamic>> linkFtthAccount({
    required String userId,
    required String ftthUsername,
    String? ftthPasswordEncrypted,
  }) async {
    final response = await _client.post(
      '/ftth-accounting/link-ftth-account',
      {
        'userId': userId,
        'ftthUsername': ftthUsername,
        'ftthPasswordEncrypted': ftthPasswordEncrypted,
      },
      (json) => json,
    );
    return _toMap(response);
  }

  /// مزامنة عمليات FTTH دفعة واحدة
  Future<Map<String, dynamic>> syncFtthTransactions({
    String? companyId,
    required List<Map<String, dynamic>> transactions,
  }) async {
    final response = await _client.post(
      '/ftth-accounting/sync-ftth-transactions',
      {
        'companyId': companyId,
        'transactions': transactions,
      },
      (json) => json,
    );
    return _toMap(response);
  }

  /// تسليم نقد سريع من مشغل
  Future<Map<String, dynamic>> quickDeliver({
    required String operatorUserId,
    required double amount,
    required String companyId,
    String? notes,
  }) async {
    final response = await _client.post(
      '/ftth-accounting/quick-deliver',
      {
        'operatorUserId': operatorUserId,
        'amount': amount,
        'companyId': companyId,
        'notes': notes,
      },
      (json) => json,
    );
    return _toMap(response);
  }

  /// جلب عملاء الآجل غير المسددين لمشغل معين
  Future<Map<String, dynamic>> getCreditCustomers({
    required String operatorUserId,
    String? companyId,
  }) async {
    String query = '/ftth-accounting/credit-customers/$operatorUserId';
    if (companyId != null) query += '?companyId=$companyId';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// تحصيل آجل سريع
  Future<Map<String, dynamic>> quickCollect({
    required String operatorUserId,
    required double amount,
    required String companyId,
    String? notes,
    List<int>? subscriptionLogIds,
    String? customerName,
  }) async {
    final body = <String, dynamic>{
      'operatorUserId': operatorUserId,
      'amount': amount,
      'companyId': companyId,
      'notes': notes,
    };
    if (subscriptionLogIds != null && subscriptionLogIds.isNotEmpty) {
      body['subscriptionLogIds'] = subscriptionLogIds;
    }
    if (customerName != null) {
      body['customerName'] = customerName;
    }
    final response = await _client.post(
      '/ftth-accounting/quick-collect',
      body,
      (json) => json,
    );
    return _toMap(response);
  }

  /// جلب لوحة المشغلين
  Future<Map<String, dynamic>> getOperatorsDashboard({
    String? companyId,
    DateTime? from,
    DateTime? to,
  }) async {
    String query = '/ftth-accounting/operators-dashboard';
    final params = <String>[];
    if (companyId != null) params.add('companyId=$companyId');
    if (from != null)
      params.add('from=${from.toIso8601String().split('T')[0]}');
    if (to != null) params.add('to=${to.toIso8601String().split('T')[0]}');
    if (params.isNotEmpty) query += '?${params.join('&')}';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// جلب ملخص مشغل محدد
  Future<Map<String, dynamic>> getOperatorSummary(
    String userId, {
    String? companyId,
    DateTime? from,
    DateTime? to,
  }) async {
    String query = '/ftth-accounting/operator-summary/$userId';
    final params = <String>[];
    if (companyId != null) params.add('companyId=$companyId');
    if (from != null)
      params.add('from=${from.toIso8601String().split('T')[0]}');
    if (to != null) params.add('to=${to.toIso8601String().split('T')[0]}');
    if (params.isNotEmpty) query += '?${params.join('&')}';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// جلب لوحة مراقبة الأموال الموحدة
  Future<Map<String, dynamic>> getFundsOverview({String? companyId}) async {
    String query = '/ftth-accounting/funds-overview';
    if (companyId != null) query += '?companyId=$companyId';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// تحديد دورة التجديد المكرر لسجل اشتراك
  Future<Map<String, dynamic>> setRenewalCycle({
    required int logId,
    int? cycleMonths,
    int? paidMonths,
  }) async {
    final body = <String, dynamic>{
      'logId': logId,
      'cycleMonths': cycleMonths,
      'paidMonths': paidMonths ?? 0,
    };
    final response = await _client.post(
      '/ftth-accounting/set-renewal-cycle',
      body,
      (json) => json,
    );
    return _toMap(response);
  }

  /// تحصيل شهر واحد من اشتراك مكرر
  Future<Map<String, dynamic>> collectRenewalMonth({
    required int logId,
    required String companyId,
    int? monthsCount,
  }) async {
    final body = <String, dynamic>{
      'logId': logId,
      'companyId': companyId,
      'monthsCount': monthsCount ?? 1,
    };
    final response = await _client.post(
      '/ftth-accounting/collect-renewal-month',
      body,
      (json) => json,
    );
    return _toMap(response);
  }
}
