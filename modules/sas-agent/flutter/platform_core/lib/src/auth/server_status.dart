import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../theme/tokens.dart';

enum ServerState { checking, online, offline }

/// فاحص صحّة الباكند (GET /api/health) — مشترك بين شاشات الدخول.
class ServerStatus extends ChangeNotifier {
  ServerStatus({this.interval = const Duration(seconds: 30)});
  final Duration interval;
  ServerState state = ServerState.checking;
  String? version;
  int? latencyMs;
  Timer? _timer;

  void start() {
    check();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => check());
  }

  Future<void> check() async {
    final sw = Stopwatch()..start();
    try {
      final r = await http
          .get(Uri.parse('${PlatformConfig.apiBase}/api/health'))
          .timeout(const Duration(seconds: 6));
      sw.stop();
      if (r.statusCode >= 200 && r.statusCode < 300) {
        try {
          final j = jsonDecode(utf8.decode(r.bodyBytes));
          if (j is Map) version = (j['version'] ?? j['app'])?.toString();
        } catch (_) {}
        latencyMs = sw.elapsedMilliseconds;
        state = ServerState.online;
      } else {
        state = ServerState.offline;
      }
    } catch (_) {
      state = ServerState.offline;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// نقطة حالة الخادم + نص — تظهر أسفل شاشة الدخول؛ الضغط يعيد الفحص ويعرض العنوان.
class ServerStatusDot extends StatelessWidget {
  final ServerStatus status;
  const ServerStatusDot({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return AnimatedBuilder(
      animation: status,
      builder: (context, _) {
        final (color, label) = switch (status.state) {
          ServerState.checking => (pal.textMuted, 'جارٍ فحص الاتصال بالخادم…'),
          ServerState.online => (pal.success, 'الخادم متّصل${status.latencyMs != null ? ' · ${status.latencyMs} ms' : ''}'),
          ServerState.offline => (pal.danger, 'تعذّر الوصول إلى الخادم'),
        };
        return Tooltip(
          message: PlatformConfig.apiBase,
          child: InkWell(
            borderRadius: Radii.rSm,
            onTap: status.check,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: status.state == ServerState.online ? Elev.glow(color, 0.6) : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: pal.textMuted)),
              ]),
            ),
          ),
        );
      },
    );
  }
}
