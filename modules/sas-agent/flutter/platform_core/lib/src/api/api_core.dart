import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../session.dart';

/// خطأ API برسالة عربية جاهزة للعرض + رمز الحالة.
class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  bool get unauthorized => status == 401;
  @override
  String toString() => message;
}

/// نواة عميل الـ API — طلبات REST بمهلة موحّدة وتوكن الجلسة.
class ApiCore {
  final String base;
  ApiCore({String? base}) : base = base ?? PlatformConfig.apiBase;

  Map<String, String> _headers({bool json = false}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json';
    if (Session.loggedIn) h['Authorization'] = 'Bearer ${Session.token}';
    return h;
  }

  Uri _u(String path, [Map<String, String?>? q]) {
    final uri = Uri.parse('$base$path');
    if (q == null) return uri;
    final qp = <String, String>{};
    q.forEach((k, v) {
      if (v != null && v.isNotEmpty) qp[k] = v;
    });
    return uri.replace(queryParameters: {...uri.queryParameters, ...qp});
  }

  Future<dynamic> get(String path, {Map<String, String?>? query}) async {
    final r = await http
        .get(_u(path, query), headers: _headers())
        .timeout(PlatformConfig.httpTimeout, onTimeout: _timeout);
    return _decode(r);
  }

  Future<dynamic> post(String path, Object? body) async {
    final r = await http
        .post(_u(path), headers: _headers(json: true), body: body == null ? null : jsonEncode(body))
        .timeout(PlatformConfig.httpTimeout, onTimeout: _timeout);
    return _decode(r);
  }

  Future<dynamic> patch(String path, Object? body) async {
    final r = await http
        .patch(_u(path), headers: _headers(json: true), body: body == null ? null : jsonEncode(body))
        .timeout(PlatformConfig.httpTimeout, onTimeout: _timeout);
    return _decode(r);
  }

  Future<dynamic> delete(String path) async {
    final r = await http
        .delete(_u(path), headers: _headers())
        .timeout(PlatformConfig.httpTimeout, onTimeout: _timeout);
    return _decode(r);
  }

  http.Response _timeout() => http.Response('{"detail":"انتهت مهلة الاتصال بالخادم"}', 599);

  dynamic _decode(http.Response r) {
    final text = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      String msg = 'خطأ ${r.statusCode}';
      try {
        final j = jsonDecode(text);
        if (j is Map && j['detail'] != null) {
          final d = j['detail'];
          msg = d is String ? d : (d is List && d.isNotEmpty ? '${d.first['msg'] ?? d.first}' : '$d');
        }
      } catch (_) {
        if (r.statusCode == 599) msg = 'انتهت مهلة الاتصال بالخادم';
      }
      if (r.statusCode == 0) msg = 'تعذّر الوصول إلى الخادم';
      throw ApiException(r.statusCode, msg);
    }
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }
}
