import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_context.dart';
import '../auth_service.dart';

/// إدارة جلسة موحدة فوق AuthService الحالي بدون كسر السلوك القائم.
/// لاحقاً يمكن تحويل الطلبات كلها لاستخدام Dio + Interceptor.
class SessionManager {
  static SessionManager? _instance;
  static SessionManager get instance =>
      _instance ??= SessionManager._internal();
  SessionManager._internal();

  final _stateController = StreamController<SessionState>.broadcast();
  AuthContext? _ctx;
  bool _initialLoaded = false;
  Timer? _preemptiveTimer;

  Stream<SessionState> get states => _stateController.stream;
  AuthContext? get context => _ctx;

  Future<void> loadFromStorage() async {
    if (_initialLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token != null) {
      _ctx = AuthContext.fromJwt(token);
      _emit(SessionState.authenticated(_ctx!));
      _schedulePreemptiveRefresh();
    } else {
      _emit(const SessionState.unauthenticated());
    }
    _initialLoaded = true;
  }

  Future<void> refreshIfExpiring({int thresholdSeconds = 180}) async {
    final rem = _ctx?.remainingSeconds;
    if (rem != null && rem <= thresholdSeconds) {
      final ok =
          await AuthService.instance.getAccessToken(); // سيجدد داخلياً إذا لزم
      if (ok != null) {
        final prefs = await SharedPreferences.getInstance();
        final newTok = prefs.getString('access_token');
        if (newTok != null) {
          _ctx = AuthContext.fromJwt(newTok);
          _emit(SessionState.authenticated(_ctx!));
          _schedulePreemptiveRefresh();
        }
      } else {
        _emit(const SessionState.unauthenticated());
      }
    }
  }

  void _schedulePreemptiveRefresh() {
    _preemptiveTimer?.cancel();
    final rem = _ctx?.remainingSeconds;
    if (rem == null || rem <= 0) return;
    // جدولة قبل الانتهاء بـ 160 ثانية (قابلة للتعديل)
    final fireIn = Duration(seconds: (rem - 160).clamp(30, rem));
    _preemptiveTimer = Timer(fireIn, () => refreshIfExpiring());
  }

  Future<void> onLoginCompleted() async {
    _initialLoaded = false; // لإجبار إعادة القراءة
    await loadFromStorage();
  }

  Future<void> logout() async {
    await AuthService.instance.logout();
    _ctx = null;
    _emit(const SessionState.unauthenticated());
  }

  void _emit(SessionState s) {
    if (!_stateController.isClosed) _stateController.add(s);
  }

  void dispose() {
    _preemptiveTimer?.cancel();
    _stateController.close();
  }
}

/// حالة الجلسة
class SessionState {
  final bool isAuthenticated;
  final AuthContext? context;
  final String? reason;
  const SessionState._(this.isAuthenticated, this.context, this.reason);
  const SessionState.unauthenticated({String? reason})
      : this._(false, null, reason);
  const SessionState.authenticated(AuthContext ctx) : this._(true, ctx, null);
}
