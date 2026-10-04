/// شاشة إعدادات واتساب — بثيم الصدارة (Cairo/AppTheme/SasUi).
///
/// اختيار النمط (app/server) + عنوان الخادم + بطاقة حالة + عرض QR للربط
/// (Image.network على `/qr-image` مع polling) عند نمط الخادم + مدخل القوالب.
/// النمط وعنوان الخادم يُحفظان في SharedPreferences (بلا أي أسرار).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';
import '../../widgets/sas_metrics.dart';
import '../../widgets/sas_state_views.dart';
import '../config/wa_settings.dart';
import '../core/wa_mode.dart';
import '../core/wa_sender.dart';
import '../senders/server_sender.dart';
import '../server/wa_server_launcher.dart';
import 'wa_templates_screen.dart';

const Color _kWaGreen = Color(0xFF25D366);

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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: AppTheme.primaryColor,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.blueGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text('إعدادات واتساب',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800, fontSize: 17, color: Colors.white)),
          actions: [
            IconButton(
              tooltip: 'القوالب',
              icon: const Icon(Icons.chat_bubble_outline_rounded,
                  color: Colors.white),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WaTemplatesScreen()),
              ),
            ),
          ],
        ),
        body: _loading
            ? const SasLoadingView(message: 'جاري تحميل الإعدادات…')
            : SasContentWrap(
                maxWidth: 820,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 24.h),
                  children: [
                    SasSectionHeader(
                      title: 'نمط الإرسال',
                      icon: Icons.send_rounded,
                      gradient: const [_kWaGreen, Color(0xFF128C7E)],
                    ),
                    SizedBox(height: 12.h),
                    for (final m in WaMode.values) _modeCard(m),
                    if (_mode == WaMode.server) ...[
                      SizedBox(height: 18.h),
                      SasSectionHeader(
                        title: 'الخادم المحلي',
                        icon: Icons.dns_rounded,
                      ),
                      SizedBox(height: 12.h),
                      _serverSettingsCard(),
                      SizedBox(height: 12.h),
                      _serverStatusCard(),
                    ],
                    SizedBox(height: 18.h),
                    _templatesButton(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _modeCard(WaMode m) {
    final enabled = m.isAvailable;
    final selected = _mode == m;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        margin: EdgeInsets.only(bottom: 10.h),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(SasUi.radius.r),
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor.withValues(alpha: 0.45)
                : Colors.grey.withValues(alpha: 0.16),
            width: selected ? 1.6 : 1.2,
          ),
          boxShadow: selected
              ? SasUi.cardShadow(AppTheme.primaryColor)
              : SasUi.cardShadow(),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(SasUi.radius.r),
            onTap: enabled
                ? () async {
                    setState(() => _mode = m);
                    await _persist();
                    if (m == WaMode.server) _checkServer();
                  }
                : null,
            child: Padding(
              padding: EdgeInsets.all(13.w),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected
                        ? AppTheme.primaryColor
                        : Colors.grey.withValues(alpha: 0.55),
                    size: 22.sp,
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                m.label,
                                style: GoogleFonts.cairo(
                                    fontSize: 13.5.sp,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF1A1A2E)),
                              ),
                            ),
                            if (!enabled) ...[
                              SizedBox(width: 6.w),
                              const SasStatusBadge(
                                  label: 'قريباً', color: Colors.grey),
                            ],
                          ],
                        ),
                        SizedBox(height: 3.h),
                        Text(
                          m.description,
                          style: GoogleFonts.cairo(
                              fontSize: 11.sp,
                              color: Colors.grey[600],
                              height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _serverSettingsCard() {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('عنوان الخادم',
              style: GoogleFonts.cairo(
                  fontSize: 12.sp, fontWeight: FontWeight.w800)),
          SizedBox(height: 8.h),
          TextField(
            controller: _serverUrl,
            style: GoogleFonts.cairo(fontSize: 13.sp),
            decoration: const InputDecoration(
              hintText: 'http://127.0.0.1:3100',
              isDense: true,
              prefixIcon: Icon(Icons.link_rounded, size: 18),
            ),
            onChanged: (_) => _persist(),
            onSubmitted: (_) => _checkServer(),
          ),
        ],
      ),
    );
  }

  Widget _serverStatusCard() {
    final st = _status;
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _statusBadge(st),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _checking ? null : _checkServer,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: BorderSide(
                      color: AppTheme.primaryColor.withValues(alpha: 0.45)),
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                ),
                icon: _checking
                    ? SizedBox(
                        width: 15.w,
                        height: 15.w,
                        child: const CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.primaryColor))
                    : Icon(Icons.refresh_rounded, size: 17.sp),
                label: Text('فحص',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w700, fontSize: 12.sp)),
              ),
            ],
          ),
          if (st != null && st.state == WaConnState.needsQr) ...[
            SizedBox(height: 14.h),
            Text(
              'امسح رمز QR من تطبيق واتساب على هاتفك (الأجهزة المرتبطة):',
              style: GoogleFonts.cairo(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700]),
            ),
            SizedBox(height: 10.h),
            Center(
              child: Container(
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.20)),
                  boxShadow: SasUi.cardShadow(_kWaGreen),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8.r),
                  child: Image.network(
                    '${_probe?.qrImageUrl() ?? ''}?n=$_qrTick',
                    width: 220,
                    height: 220,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      width: 220,
                      height: 220,
                      child: Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: _kWaGreen),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (st != null && st.state == WaConnState.unavailable) ...[
            SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.all(11.w),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
                border: Border.all(
                    color: AppTheme.warningColor.withValues(alpha: 0.30)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18.sp, color: AppTheme.warningColor),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      st.detail ??
                          'الخادم غير متاح. سيُشغَّل تلقائياً عند الفحص إن كان مثبّتاً، '
                              'أو استخدم النمط اليدوي (wa.me) بلا خادم.',
                      style: GoogleFonts.cairo(
                          fontSize: 11.5.sp,
                          color: Colors.grey[700],
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 14.h),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _checking ? null : _startSession,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kWaGreen,
                    padding: EdgeInsets.symmetric(vertical: 11.h),
                  ),
                  icon: Icon(Icons.qr_code_rounded, size: 18.sp),
                  label: Text('ربط / تحديث',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800, fontSize: 12.5.sp)),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _checking ? null : _resetSession,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.errorColor,
                    side: BorderSide(
                        color: AppTheme.errorColor.withValues(alpha: 0.45)),
                    padding: EdgeInsets.symmetric(vertical: 11.h),
                  ),
                  icon: Icon(Icons.link_off_rounded, size: 18.sp),
                  label: Text('قطع الربط',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w700, fontSize: 12.5.sp)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(WaStatus? st) {
    final (String txt, Color c, IconData icon) = switch (st?.state) {
      WaConnState.ready => (
          'متصل${st?.phone != null ? ' · ${st!.phone}' : ''}',
          AppTheme.successColor,
          Icons.check_circle_rounded
        ),
      WaConnState.needsQr => (
          'يحتاج مسح QR',
          AppTheme.warningColor,
          Icons.qr_code_rounded
        ),
      WaConnState.connecting => (
          'جارٍ الاتصال…',
          AppTheme.infoColor,
          Icons.sync_rounded
        ),
      WaConnState.disconnected => (
          'غير متصل',
          AppTheme.errorColor,
          Icons.link_off_rounded
        ),
      WaConnState.unavailable => (
          'الخادم متوقّف',
          AppTheme.errorColor,
          Icons.cloud_off_rounded
        ),
      null => ('لم يُفحَص', Colors.grey, Icons.help_outline_rounded),
    };
    return SasStatusBadge(label: txt, color: c, icon: icon);
  }

  Widget _templatesButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WaTemplatesScreen()),
        ),
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          decoration: SasUi.card(),
          child: Row(
            children: [
              SasUi.gradientBadge(
                icon: Icons.chat_bubble_rounded,
                colors: const [_kWaGreen, Color(0xFF128C7E)],
                size: 38,
                iconSize: 18,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('قوالب الرسائل',
                        style: GoogleFonts.cairo(
                            fontSize: 13.5.sp, fontWeight: FontWeight.w800)),
                    SizedBox(height: 2.h),
                    Text('تذكير · تجديد · انتهاء + قوالب مخصّصة',
                        style: GoogleFonts.cairo(
                            fontSize: 11.sp, color: Colors.grey[600])),
                  ],
                ),
              ),
              Icon(Icons.chevron_left_rounded,
                  color: Colors.grey[400], size: 24.sp),
            ],
          ),
        ),
      ),
    );
  }
}
