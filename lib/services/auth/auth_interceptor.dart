import 'package:dio/dio.dart';
import 'session_manager.dart';

/// Interceptor يقوم بحقن التوكن وتجديده عند الحاجة بصورة خفيفة
class AuthInterceptor extends Interceptor {
  final SessionManager session;
  bool _refreshing = false;
  final List<PendingRequest> _queue = [];

  AuthInterceptor(this.session);

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      await session.refreshIfExpiring();
      final token = session.context?.rawToken;
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {}
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      final req = PendingRequest(err.requestOptions, handler);
      _queue.add(req);
      if (_refreshing) return; // سيُعاد تنفيذ الطلبات بعد التجديد
      _refreshing = true;
      try {
        await session.refreshIfExpiring(
            thresholdSeconds: 3600); // إجبار محاولة تجديد كاملة
        final token = session.context?.rawToken;
        if (token == null) {
          _failQueue(err);
        } else {
          _retryQueue(token);
        }
      } catch (_) {
        _failQueue(err);
      } finally {
        _refreshing = false;
      }
    } else {
      handler.next(err);
    }
  }

  void _retryQueue(String token) {
    for (final p in _queue) {
      final opts = p.options;
      opts.headers['Authorization'] = 'Bearer $token';
      final dio =
          opts.cancelToken?.requestOptions?.extra['dio_instance'] as Dio?;
      // نحاول استخدام نفس الـ Dio العام (يجب تمريره في extra عند الإنشاء إن لزم)
      if (dio != null) {
        dio
            .fetch(opts)
            .then(p.handler.resolve)
            .catchError((e) => p.handler.reject(e));
      } else {
        // في حالة عدم توفر dio نعيد الخطأ الأصلي
        p.handler.reject(DioException(
            requestOptions: opts, error: 'No Dio reference for retry'));
      }
    }
    _queue.clear();
  }

  void _failQueue(DioException source) {
    for (final p in _queue) {
      p.handler.reject(source);
    }
    _queue.clear();
  }
}

class PendingRequest {
  final RequestOptions options;
  final ErrorInterceptorHandler handler;
  PendingRequest(this.options, this.handler);
}
