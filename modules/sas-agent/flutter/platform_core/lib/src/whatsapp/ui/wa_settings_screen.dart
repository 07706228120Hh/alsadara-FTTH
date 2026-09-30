/// شاشة إعدادات واتساب — اختيار النمط، عنوان الخادم، ربط QR، وفتح القوالب.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../config/wa_settings.dart';
import '../core/wa_mode.dart';
import '../core/wa_sender.dart';
import '../senders/server_sender.dart';
import '../server/wa_server_launcher.dart';
import 'wa_templates_screen.dart';

class WaSettingsScreen extends StatefulWidget {
  const WaSettingsScreen({super.key});
  @override
  State<WaSettingsScreen> createState() => _WaSettingsScreenState();
}

class _WaSettingsScreenState extends State<WaSettingsScreen> {
  final _store = WaSettingsStore();
  late final TextEditingController _serverUrl;

  WaMode _mode = WaMode.app;
  bool _loading = true;

  // حالة الخادم
  ServerSender? _probe;
  WaStatus? _status;
  bool _checking = false;
  int _qrTick = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _serverUrl = TextEditingController(text: WaSettings.defaultServerUrl);
    _load();
  }

  Future<void> _load() async {
    final s = await _store.load();
    if (!mounted) return;
    setState(() {
      _mode = s.mode;
      _serverUrl.text = s.serverUrl;
      _loading = false;
    });
    if (_mode == WaMode.server) _checkServer();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _probe?.dispose();
    _serverUrl.dispose();
    super.dispose();
  }

  Future<void> _persist() async {
    await _store.save(WaSettings(mode: _mode, serverUrl: _serverUrl.text.trim()));
  }

  ServerSender _freshProbe() {
    _probe?.dispose();
    return _probe = ServerSender(baseUrl: _serverUrl.text.trim());
  }

  Future<void> _checkServer() async {
    setState(() => _checking = true);
    // شغّل الخادم المدمج تلقائياً إن لم يكن يعمل (لا تنصيب يدوي).
    await WaServerLauncher.instance.ensureRunning(baseUrl: _serverUrl.text.trim());
    final probe = _freshProbe();
    final st = await probe.status();
    if (!mounted) return;
    setState(() {
      _status = st;
      _checking = false;
    });
    _managePolling(st);
  }

  void _managePolling(WaStatus st) {
    _poll?.cancel();
    // نستمر بالفحص أثناء انتظار مسح QR أو الاتصال.
    if (st.state == WaConnState.needsQr || st.state == WaConnState.connecting) {
      _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
        final s = await (_probe ?? _freshProbe()).status();
        if (!mounted) return;
        setState(() {
          _status = s;
          if (s.state == WaConnState.needsQr) _qrTick++;
        });
        if (s.ready || s.state == WaConnState.unavailable) _poll?.cancel();
      });
    }
  }

  Future<void> _startSession() async {
    final probe = _freshProbe();
    setState(() => _checking = true);
    await probe.initSession();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _checkServer();
  }

  Future<void> _resetSession() async {
    await (_probe ?? _freshProbe()).resetSession();
    await _checkServer();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إعدادات واتساب'),
          actions: [
            IconButton(
              tooltip: 'القوالب',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WaTemplatesScreen()),
              ),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('نمط الإرسال', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  for (final m in WaMode.values) _modeTile(m),
                  const SizedBox(height: 16),

                  if (_mode == WaMode.server) ...[
                    Text('الخادم المحلي', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _serverUrl,
                      decoration: const InputDecoration(
                        labelText: 'عنوان الخادم',
                        hintText: 'http://127.0.0.1:3100',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => _persist(),
                    ),
                    const SizedBox(height: 10),
                    _serverStatusCard(),
                  ],

                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WaTemplatesScreen()),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('تحرير قوالب الرسائل'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _modeTile(WaMode m) {
    final enabled = m.isAvailable;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: RadioListTile<WaMode>(
        value: m,
        // ignore: deprecated_member_use
        groupValue: _mode,
        // ignore: deprecated_member_use
        onChanged: enabled
            ? (v) async {
                setState(() => _mode = v!);
                await _persist();
                if (v == WaMode.server) _checkServer();
              }
            : null,
        title: Row(children: [
          Flexible(child: Text(m.label)),
          if (!enabled)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: _SoonTag(),
            ),
        ]),
        subtitle: Text(m.description),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _serverStatusCard() {
    final st = _status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _statusChip(st),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _checking ? null : _checkServer,
              icon: _checking
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
              label: const Text('فحص'),
            ),
          ]),
          if (st != null && st.state == WaConnState.needsQr) ...[
            const SizedBox(height: 12),
            const Text('امسح رمز QR من تطبيق واتساب على هاتفك (الأجهزة المرتبطة):'),
            const SizedBox(height: 8),
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.white,
                child: Image.network(
                  '${_probe?.qrImageUrl() ?? ''}?n=$_qrTick',
                  width: 220,
                  height: 220,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(child: Text('جارٍ توليد الرمز…')),
                  ),
                ),
              ),
            ),
          ],
          if (st != null && st.state == WaConnState.unavailable) ...[
            const SizedBox(height: 8),
            Text(
              st.detail ?? 'الخادم غير متاح. شغّل خادم واتساب المحلي أولاً '
                  '(المجلد whatsapp-server → start_whatsapp_server.bat).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _startSession,
                icon: const Icon(Icons.qr_code),
                label: const Text('ربط / تحديث'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _resetSession,
                icon: const Icon(Icons.link_off),
                label: const Text('قطع الربط'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _statusChip(WaStatus? st) {
    final (String txt, Color c) = switch (st?.state) {
      WaConnState.ready => ('متصل${st?.phone != null ? ' · ${st!.phone}' : ''}', Colors.green),
      WaConnState.needsQr => ('يحتاج مسح QR', Colors.orange),
      WaConnState.connecting => ('جارٍ الاتصال…', Colors.blue),
      WaConnState.disconnected => ('غير متصل', Colors.red),
      WaConnState.unavailable => ('الخادم متوقّف', Colors.red),
      null => ('لم يُفحَص', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 10, color: c),
        const SizedBox(width: 6),
        Text(txt, style: TextStyle(color: c, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _SoonTag extends StatelessWidget {
  const _SoonTag();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
      child: const Text('قريباً', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
