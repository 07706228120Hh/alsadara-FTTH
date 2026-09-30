/// ورقة الإرسال الجماعي — تختار قالباً، تعاين، وترسل لدفعة مستلِمين.
///
/// تتكيّف مع قدرات النمط: الآلي (خادم) يعرض شريط تقدّم وإلغاء؛ اليدوي (app) يعرض
/// «نسخ الكل» و«فتح تِباعاً». لا تعرف الورقة النمط — تقرأ الإعدادات وتبني المُرسِل.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/wa_settings.dart';
import '../core/wa_mode.dart';
import '../core/wa_sender.dart';
import '../models/wa_message.dart';
import '../models/wa_recipient.dart';
import '../models/wa_template.dart';
import '../server/wa_server_launcher.dart';
import '../templates/template_store.dart';

/// يفتح ورقة الإرسال الجماعي لقائمة مستلِمين.
Future<void> showWaBulkSheet(BuildContext context, List<WaRecipient> recipients) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: WaBulkSheet(recipients: recipients),
      ),
    ),
  );
}

class WaBulkSheet extends StatefulWidget {
  final List<WaRecipient> recipients;
  const WaBulkSheet({super.key, required this.recipients});
  @override
  State<WaBulkSheet> createState() => _WaBulkSheetState();
}

class _WaBulkSheetState extends State<WaBulkSheet> {
  final _store = LocalTemplateStore();

  WaSettings _settings = const WaSettings();
  WaSender? _sender;
  List<WaTemplate> _templates = [];
  WaTemplate? _template;

  WaStatus _status = WaStatus.alwaysReady;
  bool _loading = true;

  // حالة الإرسال
  StreamSubscription<WaBatchProgress>? _sub;
  WaBatchProgress? _progress;
  bool _sending = false;
  bool _cancelled = false;

  List<WaRecipient> get _valid => widget.recipients.where((r) => r.sendable).toList();
  int get _skipped => widget.recipients.length - _valid.length;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final settings = await WaSettingsStore().load();
    final templates = await _store.load();
    // في نمط الخادم: شغّل الخادم المدمج تلقائياً قبل فحص الحالة.
    if (settings.mode == WaMode.server) {
      await WaServerLauncher.instance.ensureRunning(baseUrl: settings.serverUrl);
    }
    final sender = settings.buildSender();
    final status = await sender.status();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _sender = sender;
      _templates = templates;
      _template = templates.isNotEmpty ? templates.first : null;
      _status = status;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sender?.dispose();
    super.dispose();
  }

  List<WaOutgoing> _buildMessages() {
    final tpl = _template;
    return _valid
        .map((r) => WaOutgoing(
              recipient: r,
              text: tpl == null ? '' : tpl.render(r.templateVars),
            ))
        .toList();
  }

  Future<void> _copyAll() async {
    final msgs = _buildMessages();
    final buf = StringBuffer();
    for (final m in msgs) {
      buf.writeln('${m.phone}\t${m.recipient.name}');
      buf.writeln(m.text);
      buf.writeln('—');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('نُسخت ${msgs.length} رسالة مع الأرقام')),
      );
    }
  }

  Future<void> _send() async {
    final sender = _sender;
    if (sender == null || _template == null) return;
    final msgs = _buildMessages();
    if (msgs.isEmpty) return;
    setState(() {
      _sending = true;
      _cancelled = false;
      _progress = WaBatchProgress(total: msgs.length);
    });
    _sub = sender.sendBulk(msgs).listen(
      (p) {
        if (mounted) setState(() => _progress = p);
      },
      onDone: () {
        if (mounted) setState(() => _sending = false);
      },
      onError: (Object e) {
        if (mounted) {
          setState(() => _sending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ الإرسال: $e'), backgroundColor: Colors.red),
          );
        }
      },
    );
  }

  void _cancel() {
    _sub?.cancel();
    setState(() {
      _cancelled = true;
      _sending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final cap = _sender!.capabilities;
    final automated = cap.automated;
    final serverBlocked = _settings.mode.isAvailable &&
        cap.needsSession &&
        !_status.ready; // خادم غير مربوط

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            const Icon(Icons.send, color: Color(0xFF25D366)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('إرسال واتساب جماعي', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            _ModeChip(label: _settings.mode.label),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              // ملخّص المستلِمين
              _SummaryRow(total: widget.recipients.length, valid: _valid.length, skipped: _skipped),
              const SizedBox(height: 12),

              // اختيار القالب
              Text('القالب', style: tt.labelLarge),
              const SizedBox(height: 6),
              DropdownButtonFormField<WaTemplate>(
                initialValue: _template,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: [
                  for (final t in _templates)
                    DropdownMenuItem(value: t, child: Text(t.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: _sending ? null : (t) => setState(() => _template = t),
              ),
              const SizedBox(height: 12),

              // معاينة (لأول مستلِم)
              if (_template != null && _valid.isNotEmpty) ...[
                Text('معاينة (${_valid.first.name.isEmpty ? _valid.first.phone : _valid.first.name})',
                    style: tt.labelLarge),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.3)),
                  ),
                  child: Text(_template!.render(_valid.first.templateVars), style: tt.bodyMedium),
                ),
                const SizedBox(height: 12),
              ],

              // تنبيه الخادم غير المربوط
              if (serverBlocked)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Icons.warning_amber, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _status.state == WaConnState.unavailable
                            ? 'الخادم المحلي غير مشغّل — شغّله أو بدّل إلى النمط اليدوي من الإعدادات.'
                            : 'الخادم غير مربوط — امسح رمز QR من إعدادات واتساب أولاً.',
                        style: tt.bodySmall,
                      ),
                    ),
                  ]),
                ),

              // شريط التقدّم
              if (_progress != null) _ProgressCard(progress: _progress!, cancelled: _cancelled),
            ],
          ),
        ),

        // أزرار الإجراء
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _sending
                ? Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _cancel,
                        icon: const Icon(Icons.stop),
                        label: const Text('إيقاف'),
                      ),
                    ),
                  ])
                : automated
                    ? Row(children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: (_valid.isEmpty || serverBlocked || _template == null) ? null : _send,
                            icon: const Icon(Icons.send),
                            label: Text('إرسال (${_valid.length})'),
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                          ),
                        ),
                      ])
                    : Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _valid.isEmpty ? null : _copyAll,
                            icon: const Icon(Icons.copy),
                            label: const Text('نسخ الكل'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: (_valid.isEmpty || _template == null) ? null : _send,
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('فتح تِباعاً'),
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                          ),
                        ),
                      ]),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final int total, valid, skipped;
  const _SummaryRow({required this.total, required this.valid, required this.skipped});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _StatBox(label: 'الكل', value: total, color: Colors.blueGrey),
      const SizedBox(width: 8),
      _StatBox(label: 'صالح', value: valid, color: const Color(0xFF25D366)),
      const SizedBox(width: 8),
      _StatBox(label: 'مُستبعَد', value: skipped, color: Colors.orange),
    ]);
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatBox({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text('$value', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: color)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final WaBatchProgress progress;
  final bool cancelled;
  const _ProgressCard({required this.progress, required this.cancelled});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final done = progress.done || cancelled;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(
              done ? (cancelled ? 'أُوقف' : 'اكتمل') : 'جارٍ الإرسال…',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text('${progress.processed}/${progress.total}', style: tt.bodyMedium),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress.total == 0 ? 0 : progress.fraction),
          const SizedBox(height: 8),
          Row(children: [
            Text('نجح: ${progress.sent}', style: tt.bodySmall?.copyWith(color: const Color(0xFF25D366))),
            const SizedBox(width: 16),
            Text('فشل: ${progress.failed}', style: tt.bodySmall?.copyWith(color: Colors.red)),
          ]),
          if (progress.last != null && progress.last!.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('آخر خطأ: ${progress.last!.error}',
                  style: tt.bodySmall?.copyWith(color: Colors.red), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
        ]),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  const _ModeChip({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
