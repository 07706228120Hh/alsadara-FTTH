/// ورقة الإرسال الجماعي — بثيم الصدارة (Cairo/AppTheme/SasUi).
///
/// تختار قالباً، تعاين، وترسل لدفعة مستلِمين. تتكيّف مع قدرات النمط: الآلي (خادم)
/// يعرض شريط تقدّم وإلغاء؛ اليدوي (app) يعرض «نسخ الكل» و«فتح تِباعاً». لا تعرف
/// الورقة النمط — تقرأ الإعدادات وتبني `WaSender` المجرّد.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';
import '../../widgets/sas_state_views.dart';
import '../config/wa_settings.dart';
import '../core/wa_mode.dart';
import '../core/wa_sender.dart';
import '../models/wa_message.dart';
import '../models/wa_recipient.dart';
import '../models/wa_template.dart';
import '../server/wa_server_launcher.dart';
import '../templates/template_store.dart';

const Color _kWaGreen = Color(0xFF25D366);

/// يفتح ورقة الإرسال الجماعي لقائمة مستلِمين.
Future<void> showWaBulkSheet(
    BuildContext context, List<WaRecipient> recipients) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(SasUi.radius.r)),
    ),
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

  List<WaRecipient> get _valid =>
      widget.recipients.where((r) => r.sendable).toList();
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
      _snack('نُسخت ${msgs.length} رسالة مع الأرقام');
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.cairo()),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
    ));
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
          _snack('خطأ الإرسال: $e', error: true);
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
    if (_loading) {
      return const SasLoadingView(message: 'جاري التحضير…');
    }
    final cap = _sender!.capabilities;
    final automated = cap.automated;
    final serverBlocked = _settings.mode.isAvailable &&
        cap.needsSession &&
        !_status.ready; // خادم غير مربوط

    return Column(
      children: [
        _header(),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 16.h),
            children: [
              _SummaryRow(
                  total: widget.recipients.length,
                  valid: _valid.length,
                  skipped: _skipped),
              SizedBox(height: 14.h),
              Text('القالب',
                  style: GoogleFonts.cairo(
                      fontSize: 12.sp, fontWeight: FontWeight.w800)),
              SizedBox(height: 8.h),
              DropdownButtonFormField<WaTemplate>(
                initialValue: _template,
                isExpanded: true,
                style: GoogleFonts.cairo(fontSize: 13.sp, color: Colors.black87),
                decoration: const InputDecoration(isDense: true),
                items: [
                  for (final t in _templates)
                    DropdownMenuItem(
                        value: t,
                        child: Text(t.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged:
                    _sending ? null : (t) => setState(() => _template = t),
              ),
              SizedBox(height: 14.h),
              if (_template != null && _valid.isNotEmpty) ...[
                Text(
                    'معاينة (${_valid.first.name.isEmpty ? _valid.first.phone : _valid.first.name})',
                    style: GoogleFonts.cairo(
                        fontSize: 12.sp, fontWeight: FontWeight.w800)),
                SizedBox(height: 8.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(13.w),
                  decoration: BoxDecoration(
                    color: _kWaGreen.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
                    border:
                        Border.all(color: _kWaGreen.withValues(alpha: 0.28)),
                  ),
                  child: Text(
                    _template!.render(_valid.first.templateVars),
                    style:
                        GoogleFonts.cairo(fontSize: 12.5.sp, height: 1.55),
                  ),
                ),
                SizedBox(height: 14.h),
              ],
              if (serverBlocked) _serverBlockedNotice(),
              if (_progress != null)
                _ProgressCard(progress: _progress!, cancelled: _cancelled),
            ],
          ),
        ),
        _actionBar(automated: automated, serverBlocked: serverBlocked),
      ],
    );
  }

  Widget _header() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 10.h),
      child: Row(
        children: [
          SasUi.gradientBadge(
            icon: Icons.send_rounded,
            colors: const [_kWaGreen, Color(0xFF128C7E)],
            size: 38,
            iconSize: 18,
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text('إرسال واتساب جماعي',
                style: GoogleFonts.cairo(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1A2E))),
          ),
          SasStatusBadge(
              label: _settings.mode.label,
              color: AppTheme.primaryColor,
              icon: _settings.mode == WaMode.server
                  ? Icons.dns_rounded
                  : Icons.open_in_new_rounded),
        ],
      ),
    );
  }

  Widget _serverBlockedNotice() {
    return Container(
      padding: EdgeInsets.all(12.w),
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: AppTheme.warningColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
        border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18.sp, color: AppTheme.warningColor),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              _status.state == WaConnState.unavailable
                  ? 'الخادم المحلي غير مشغّل — شغّله أو بدّل إلى النمط اليدوي من الإعدادات.'
                  : 'الخادم غير مربوط — امسح رمز QR من إعدادات واتساب أولاً.',
              style: GoogleFonts.cairo(
                  fontSize: 11.5.sp, color: Colors.grey[700], height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBar({required bool automated, required bool serverBlocked}) {
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 12.h),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: _sending
            ? OutlinedButton.icon(
                onPressed: _cancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.errorColor,
                  side: BorderSide(
                      color: AppTheme.errorColor.withValues(alpha: 0.45)),
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  minimumSize: Size(double.infinity, 0),
                ),
                icon: const Icon(Icons.stop_rounded),
                label: Text('إيقاف',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
              )
            : automated
                ? FilledButton.icon(
                    onPressed:
                        (_valid.isEmpty || serverBlocked || _template == null)
                            ? null
                            : _send,
                    style: FilledButton.styleFrom(
                      backgroundColor: _kWaGreen,
                      disabledBackgroundColor:
                          Colors.grey.withValues(alpha: 0.30),
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                      minimumSize: Size(double.infinity, 0),
                    ),
                    icon: const Icon(Icons.send_rounded),
                    label: Text('إرسال (${_valid.length})',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _valid.isEmpty ? null : _copyAll,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryColor,
                            side: BorderSide(
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.45)),
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                          ),
                          icon: const Icon(Icons.copy_rounded),
                          label: Text('نسخ الكل',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700, fontSize: 12.5.sp)),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (_valid.isEmpty || _template == null)
                              ? null
                              : _send,
                          style: FilledButton.styleFrom(
                            backgroundColor: _kWaGreen,
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                          ),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: Text('فتح تِباعاً',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w800, fontSize: 12.5.sp)),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final int total, valid, skipped;
  const _SummaryRow(
      {required this.total, required this.valid, required this.skipped});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatBox(label: 'الكل', value: total, color: AppTheme.primaryColor),
        SizedBox(width: 8.w),
        _StatBox(label: 'صالح', value: valid, color: _kWaGreen),
        SizedBox(width: 8.w),
        _StatBox(label: 'مُستبعَد', value: skipped, color: AppTheme.warningColor),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatBox(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 11.h),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          children: [
            Text('$value',
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w900, fontSize: 19.sp, color: color)),
            SizedBox(height: 1.h),
            Text(label,
                style: GoogleFonts.cairo(
                    fontSize: 11.sp,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w700)),
          ],
        ),
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
    final done = progress.done || cancelled;
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                done ? (cancelled ? 'أُوقف' : 'اكتمل') : 'جارٍ الإرسال…',
                style: GoogleFonts.cairo(
                    fontSize: 13.sp, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text('${progress.processed}/${progress.total}',
                  style: GoogleFonts.cairo(
                      fontSize: 12.5.sp, fontWeight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: 10.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(6.r),
            child: LinearProgressIndicator(
              value: progress.total == 0 ? 0 : progress.fraction,
              minHeight: 9.h,
              backgroundColor: _kWaGreen.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation<Color>(_kWaGreen),
            ),
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  size: 14.sp, color: AppTheme.successColor),
              SizedBox(width: 4.w),
              Text('نجح: ${progress.sent}',
                  style: GoogleFonts.cairo(
                      fontSize: 11.5.sp,
                      color: AppTheme.successColor,
                      fontWeight: FontWeight.w700)),
              SizedBox(width: 16.w),
              Icon(Icons.cancel_rounded, size: 14.sp, color: AppTheme.errorColor),
              SizedBox(width: 4.w),
              Text('فشل: ${progress.failed}',
                  style: GoogleFonts.cairo(
                      fontSize: 11.5.sp,
                      color: AppTheme.errorColor,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          if (progress.last != null && progress.last!.error != null)
            Padding(
              padding: EdgeInsets.only(top: 6.h),
              child: Text(
                'آخر خطأ: ${progress.last!.error}',
                style: GoogleFonts.cairo(
                    fontSize: 11.sp, color: AppTheme.errorColor),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
