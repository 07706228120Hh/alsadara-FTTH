import 'package:shared_preferences/shared_preferences.dart';

class CutSettings {
  final bool enabled;
  final String host;
  final int port;
  final int delayMs;
  final int feedLines;
  const CutSettings({
    required this.enabled,
    required this.host,
    required this.port,
    required this.delayMs,
    required this.feedLines,
  });

  CutSettings copyWith({
    bool? enabled,
    String? host,
    int? port,
    int? delayMs,
    int? feedLines,
  }) => CutSettings(
        enabled: enabled ?? this.enabled,
        host: host ?? this.host,
        port: port ?? this.port,
        delayMs: delayMs ?? this.delayMs,
        feedLines: feedLines ?? this.feedLines,
      );
}

class PrinterSettingsStorage {
  static const _kEnabled = 'escpos_cut_enabled';
  static const _kHost = 'escpos_printer_host';
  static const _kPort = 'escpos_printer_port';
  static const _kDelay = 'escpos_cut_delay_ms';
  static const _kFeed = 'escpos_feed_lines_before_cut';

  static Future<CutSettings> loadCutSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kEnabled) ?? false;
    final host = prefs.getString(_kHost) ?? '';
    final port = prefs.getInt(_kPort) ?? 9100; // شائع لطابعات الشبكة
    final delayMs = prefs.getInt(_kDelay) ?? 1500; // انتظار قبل القطع
    final feedLines = prefs.getInt(_kFeed) ?? 3; // تغذية قبل القطع
    return CutSettings(
      enabled: enabled,
      host: host,
      port: port,
      delayMs: delayMs,
      feedLines: feedLines,
    );
  }

  static Future<void> saveCutSettings(CutSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, settings.enabled);
    await prefs.setString(_kHost, settings.host);
    await prefs.setInt(_kPort, settings.port);
    await prefs.setInt(_kDelay, settings.delayMs);
    await prefs.setInt(_kFeed, settings.feedLines);
  }
}
