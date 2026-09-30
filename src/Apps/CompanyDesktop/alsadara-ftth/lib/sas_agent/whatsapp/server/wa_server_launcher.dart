/// مُشغّل الخادم المحلي — يطلق خادم واتساب المدمج تلقائياً ويوقفه، مربوطاً بدورة
/// حياة التطبيق (ويندوز فقط). لا يحتاج تنصيباً يدوياً: الخادم مُضمَّن مع التطبيق.
///
/// الإطلاق مخفيّ عبر `run_hidden.vbs` (بلا نافذة طرفية)؛ الإيقاف بقتل العملية عبر
/// ملف الـ PID الذي يكتبه الخادم في `%LOCALAPPDATA%\Alsadara\whatsapp\server.pid`.
///
/// إن تعذّر إيجاد/تشغيل الخادم، تكتفي الواجهة بالنمط `app` (wa.me) بلا خادم.
library;

import 'dart:async';
import 'dart:io';

class WaServerLauncher {
  WaServerLauncher._();
  static final WaServerLauncher instance = WaServerLauncher._();

  bool _starting = false;

  /// يضمن أن الخادم المحلي يعمل ويستجيب. يُعيد true عند الجاهزية.
  /// على غير ويندوز: يكتفي بفحص الصحّة (لا إطلاق تلقائي).
  Future<bool> ensureRunning({String baseUrl = 'http://127.0.0.1:3100'}) async {
    if (await _health(baseUrl)) return true;
    if (!Platform.isWindows) return false;
    if (_starting) return _waitHealthy(baseUrl);
    _starting = true;
    try {
      final dir = _findServerDir();
      if (dir == null) return false;
      final vbs = '${dir.path}${Platform.pathSeparator}run_hidden.vbs';
      if (!File(vbs).existsSync()) return false;
      // إطلاق مخفيّ عبر wscript (يشغّل node مخفيّاً ثم يخرج؛ node يستمرّ).
      await Process.start(
        'wscript.exe',
        [vbs],
        mode: ProcessStartMode.detached,
        workingDirectory: dir.path,
      );
      return await _waitHealthy(baseUrl);
    } catch (_) {
      return false;
    } finally {
      _starting = false;
    }
  }

  /// يوقف الخادم المحلي (يقتل node ومتصفّحه) عبر ملف الـ PID.
  Future<void> stop() async {
    if (!Platform.isWindows) return;
    try {
      final local = Platform.environment['LOCALAPPDATA'];
      if (local == null) return;
      final pidFile = File('$local\\Alsadara\\whatsapp\\server.pid');
      if (!pidFile.existsSync()) return;
      final pid = int.tryParse((await pidFile.readAsString()).trim());
      if (pid == null) return;
      await Process.run('taskkill', ['/F', '/T', '/PID', '$pid']);
    } catch (_) {
      /* ignore */
    }
  }

  /// يحدّد مجلد الخادم المدمج بتجربة مسارات مرشّحة حسب التخطيط (منصَّب/تطوير).
  Directory? _findServerDir() {
    final sep = Platform.pathSeparator;
    final exeDir = File(Platform.resolvedExecutable).parent;
    final candidates = <String>[
      // منصَّب: {app}\app\alsadara.exe → {app}\whatsapp-server
      '${exeDir.parent.path}${sep}whatsapp-server',
      // مدمج بجوار الـ exe: {dir}\whatsapp-server
      '${exeDir.path}${sep}whatsapp-server',
      // احتياطي التطوير (تخطيط مستودع الصدارة)
      r'C:\SadaraPlatform\modules\sas-agent\whatsapp-server',
    ];
    for (final c in candidates) {
      final d = Directory(c);
      if (d.existsSync() && File('${d.path}${sep}server.js').existsSync()) {
        return d;
      }
    }
    return null;
  }

  Future<bool> _health(String baseUrl) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client
          .getUrl(Uri.parse('$baseUrl/'))
          .timeout(const Duration(seconds: 2));
      final resp = await req.close().timeout(const Duration(seconds: 2));
      await resp.drain<void>();
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _waitHealthy(String baseUrl) async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (await _health(baseUrl)) return true;
    }
    return false;
  }
}
