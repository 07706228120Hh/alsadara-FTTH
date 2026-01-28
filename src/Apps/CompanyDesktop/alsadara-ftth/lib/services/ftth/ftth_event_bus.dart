import 'dart:async';

/// قناة أحداث بسيطة داخل نظام FTTH لطلب تحديثات فورية عبر الصفحات.
class FtthEventBus {
  FtthEventBus._();
  static final FtthEventBus instance = FtthEventBus._();

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
class FtthEvents {
  static const String forceRefresh = 'force_refresh';
}
