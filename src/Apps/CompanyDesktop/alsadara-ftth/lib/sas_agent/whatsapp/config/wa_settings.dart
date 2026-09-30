/// إعدادات واتساب المحفوظة + مصنع المُرسِل — نقطة التبديل بين الأنماط.
///
/// تغيير النمط في مكان واحد؛ كل الواجهة تستهلك `WaSender` المجرّد فلا تتأثّر.
/// النمط وعنوان الخادم يُحفظان في SharedPreferences (بلا أي أسرار).
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../core/wa_mode.dart';
import '../core/wa_sender.dart';
import '../senders/api_sender.dart';
import '../senders/app_sender.dart';
import '../senders/server_sender.dart';

/// إعدادات واتساب القابلة للحفظ.
class WaSettings {
  final WaMode mode;

  /// عنوان الخادم المحلي (لنمط server).
  final String serverUrl;

  const WaSettings({
    this.mode = WaMode.app,
    this.serverUrl = defaultServerUrl,
  });

  static const defaultServerUrl = 'http://127.0.0.1:3100';

  WaSettings copyWith({WaMode? mode, String? serverUrl}) => WaSettings(
        mode: mode ?? this.mode,
        serverUrl: serverUrl ?? this.serverUrl,
      );

  /// يبني المُرسِل المطابق للنمط الحالي. `web` غير مُفعَّل → يسقط إلى `app`.
  WaSender buildSender() => switch (mode) {
        WaMode.app => const AppSender(),
        WaMode.server => ServerSender(baseUrl: serverUrl),
        WaMode.api => const ApiSender(),
        WaMode.web => const AppSender(), // مؤجّل — يسقط للنمط اليدوي مؤقتاً
      };
}

/// تحميل/حفظ الإعدادات عبر SharedPreferences.
class WaSettingsStore {
  static const _kMode = 'wa_mode';
  static const _kServer = 'wa_server_url';

  Future<WaSettings> load() async {
    final sp = await SharedPreferences.getInstance();
    return WaSettings(
      mode: WaMode.fromKey(sp.getString(_kMode)),
      serverUrl: sp.getString(_kServer) ?? WaSettings.defaultServerUrl,
    );
  }

  Future<void> save(WaSettings s) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kMode, s.mode.key);
    await sp.setString(_kServer, s.serverUrl);
  }
}
