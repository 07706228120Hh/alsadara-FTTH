import 'dart:async';

/// قناة أحداث بسيطة داخل نظام المحاسبة لطلب تحديثات فورية عبر الصفحات.
class AccountingEventBus {
  AccountingEventBus._();
  static final AccountingEventBus instance = AccountingEventBus._();

  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  Stream<String> get stream => _controller.stream;

  void emit(String event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void dispose() {
    _controller.close();
  }
}

/// أسماء أحداث معيارية
class AccountingEvents {
  static const String journalCreated = 'journal_created';
  static const String journalUpdated = 'journal_updated';
  static const String expenseCreated = 'expense_created';
  static const String expenseUpdated = 'expense_updated';
  static const String salaryPaid = 'salary_paid';
  static const String collectionDelivered = 'collection_delivered';
  static const String cashBoxUpdated = 'cashbox_updated';
  static const String accountUpdated = 'account_updated';
  static const String forceRefresh = 'force_refresh';
}
