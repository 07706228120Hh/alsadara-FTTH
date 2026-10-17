/// شاشة تفاصيل جهاز شبكة — Network Quality
///
/// تعرض التقرير الكامل لجهاز بنية (ONU/راوتر/AP) وتتيح إدخال اعتماد يدوي
/// محفوظ وإعادة الفحص.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart' as wvwin;

import '../../frontend/frontend.dart';
import '../models/device_models.dart';
import '../models/quality_models.dart';
import '../services/device_credentials_service.dart';
import '../services/device_inspector_service.dart';
import '../services/quality_scorer.dart';
import '../services/url_opener.dart';
import '../services/webview_optical_reader.dart';
import '../widgets/quality_widgets.dart';
import 'router_wifi_edit_page.dart';

class DeviceDetailPage extends StatefulWidget {
  final NetworkDevice device;
  const DeviceDetailPage({super.key, required this.device});

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  static const _indigo = SdColors.primary;
  bool _busy = false;

  // WebView خفيّ (ويندوز) للقراءة الصامتة لبصريات هواوي — محجوب بالكامل خلف
  // طبقة معتمة، لا تظهر واجهة الجهاز للمستخدم إطلاقاً.
  final wvwin.WebviewController _webCtrl = wvwin.WebviewController();
  bool _webReady = false;
  bool _webBusy = false;

  NetworkDevice get d => widget.device;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    if (!Platform.isWindows) return;
    try {
      await _webCtrl.initialize();
      await _webCtrl.setBackgroundColor(Colors.white);
      if (mounted) setState(() => _webReady = true);
    } catch (e) {
      debugPrint('[DeviceDetail] webview init failed: $e');
    }
  }

  @override
  void dispose() {
    if (_webReady) {
      try {
        _webCtrl.dispose();
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _reinspect({DeviceCredential? manual}) async {
    setState(() => _busy = true);
    try {
      await DeviceInspectorService.inspect(d, manual: manual);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enterCredentials() async {
    final userCtrl = TextEditingController(
        text: (await DeviceCredentialsService.getSaved(d.ip))?.user ?? '');
    final passCtrl = TextEditingController();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('اعتماد الدخول — ${d.ip}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(
                    labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'كلمة المرور', prefixIcon: Icon(Icons.lock)),
              ),
            ],
          ),
          actions: [
            SdButton(
              label: 'إلغاء',
              kind: SdButtonKind.secondary,
              height: 44,
              onPressed: () => Navigator.pop(ctx, false),
            ),
            SdButton(
              label: 'فحص',
              icon: Icons.search_rounded,
              height: 44,
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _reinspect(manual: DeviceCredential(userCtrl.text.trim(), passCtrl.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SdPage(
      padding: EdgeInsets.zero,
      appBar: SdAppBar(
        title: d.displayName,
        actions: [
          SdAppBarAction(
            icon: Icons.refresh_rounded,
            label: 'إعادة الفحص',
            onPressed: _busy ? null : () => _reinspect(),
          ),
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // WebView2 (ويندوز) يرسم طبقة native فوق Flutter؛ نركّبه فقط أثناء
          // القراءة الصامتة بحجم 1×1 (غير مرئي عملياً) ومتجاهِلاً للمؤشّر،
          // والقراءة تتم عبر JS/XHR على المتحكّم نفسه.
          if (Platform.isWindows && _webReady && _webBusy)
            SizedBox(
              width: 1,
              height: 1,
              child: IgnorePointer(
                ignoring: true,
                child: wvwin.Webview(_webCtrl),
              ),
            ),
          _buildIdentity(),
          _buildAccess(),
          if (d.status == InspectStatus.needsCredentials) _buildNeedsCreds(),
          if (d.optical != null)
            _buildOptical()
          else if (d.isOnu)
            _buildOpticalFailed(),
          if (d.report != null && d.report!.hasAnyData) _buildReport(),
          if (d.report?.clients.isNotEmpty ?? false) _buildClients(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildIdentity() {
    return SectionCard(
      title: 'هوية الجهاز',
      icon: Icons.devices_other_rounded,
      accent: _indigo,
      trailing: _statusChip(),
      child: Column(
        children: [
          InfoRow('النوع', d.type.arabicLabel),
          InfoRow('عنوان IP', d.ip),
          if (d.mac.isNotEmpty) InfoRow('MAC', d.mac),
          if (d.vendor.isNotEmpty) InfoRow('الشركة المصنّعة', d.vendor),
          if (d.brandGuess.isNotEmpty) InfoRow('الماركة', d.brandGuess),
          if (d.pageTitle.isNotEmpty) InfoRow('عنوان الواجهة', d.pageTitle),
          InfoRow('بوّابة؟', d.isGateway ? 'نعم' : 'لا'),
        ],
      ),
    );
  }

  // ═══════════════ الوصول إلى الجهاز ═══════════════

  /// بطاقة أزرار الوصول: فتح واجهة الجهاز في المتصفح + (للراوتر) تعديل WiFi.
  Widget _buildAccess() {
    final isRouter = d.isGateway || d.type == DeviceType.router;
    return SectionCard(
      title: 'الوصول إلى الجهاز',
      icon: Icons.open_in_browser_rounded,
      accent: _indigo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SdButton(
            icon: Icons.language_rounded,
            label: 'فتح واجهة الجهاز (${d.ip})',
            expand: true,
            onPressed: _openDeviceWeb,
          ),
          if (isRouter) ...[
            const SizedBox(height: 10),
            SdButton(
              icon: Icons.wifi_password_rounded,
              label: 'تعديل WiFi',
              kind: SdButtonKind.accent,
              expand: true,
              onPressed: _openWifiEdit,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'تُفتح صفحة دخول الجهاز في المتصفح الافتراضي — المسار الموثوق للدخول على كل المنصّات.',
            style: SdText.caption,
          ),
        ],
      ),
    );
  }

  Future<void> _openDeviceWeb() async {
    final ok = await openUrlRobust('http://${d.ip}');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر فتح http://${d.ip}')),
      );
    }
  }

  void _openWifiEdit() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RouterWifiEditPage(gatewayIp: d.ip)),
    );
  }

  Widget _statusChip() {
    String text;
    SdStatus status;
    switch (d.status) {
      case InspectStatus.authenticated:
        text = 'تم الفحص';
        status = SdStatus.success;
        break;
      case InspectStatus.needsCredentials:
        text = 'يلزم اعتماد';
        status = SdStatus.warning;
        break;
      case InspectStatus.unreachableUi:
        text = 'جهاز متصل';
        status = SdStatus.info;
        break;
      case InspectStatus.error:
        text = 'خطأ';
        status = SdStatus.danger;
        break;
      case InspectStatus.notInspected:
        text = 'لم يُفحص';
        status = SdStatus.neutral;
        break;
    }
    return SdStatusChip(text, status: status);
  }

  Widget _buildNeedsCreds() {
    return SectionCard(
      title: 'يلزم اعتماد الدخول',
      icon: Icons.key_rounded,
      accent: SdColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تعذّر الدخول بالاعتماد الافتراضي لهذا الجهاز. أدخل اسم المستخدم وكلمة المرور ليُفحص بالتفصيل (يُحفظ مشفّراً للمرّة القادمة).',
            style: SdText.bodySm,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SdButton(
              icon: Icons.login_rounded,
              label: 'إدخال اعتماد الدخول',
              onPressed: _busy ? null : _enterCredentials,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptical() {
    final o = d.optical!;
    return SectionCard(
      title: 'الإشارة الضوئية',
      icon: Icons.fiber_manual_record,
      accent: SdColors.accent,
      child: Column(
        children: [
          MetricTile(MetricResult(
            name: 'قدرة الاستقبال (Rx)',
            displayValue:
                o.rxPowerDbm != null ? '${o.rxPowerDbm!.toStringAsFixed(2)} dBm' : '—',
            rating: QualityScorer.rateOpticalRx(o.rxPowerDbm),
            note: 'النطاق الصحّي: -8 إلى -27 dBm',
          )),
          if (o.txPowerDbm != null)
            InfoRow('قدرة الإرسال (Tx)', '${o.txPowerDbm!.toStringAsFixed(2)} dBm'),
          if (o.voltage != null) InfoRow('الفولتية', '${o.voltage!.toStringAsFixed(2)} V'),
          if (o.biasCurrentMa != null)
            InfoRow('تيار الانحياز', '${o.biasCurrentMa!.toStringAsFixed(2)} mA'),
          if (o.temperatureC != null)
            InfoRow('حرارة الوحدة', '${o.temperatureC!.toStringAsFixed(1)} °C'),
        ],
      ),
    );
  }

  /// قراءة صامتة لبصريات الجهاز عبر WebView الخفيّ (دون إظهار واجهة الجهاز).
  Future<void> _silentWebViewRead() async {
    if (!Platform.isWindows || !_webReady) return;
    // اعتمادات مرشّحة (المحفوظ + الافتراضي للماركة) بصيغة [[user, pass], ...].
    final cands = await DeviceCredentialsService.candidatesFor(
        d.ip, d.brandGuess.isNotEmpty ? d.brandGuess : d.vendor);
    final creds = cands.map((c) => [c.user, c.pass]).toList();
    if (!mounted) return;
    setState(() => _webBusy = true);
    // مهلة لرسم الـWebView الخفيّ قبل تشغيل السكربتات.
    await Future.delayed(const Duration(milliseconds: 600));
    try {
      final reading = await WebViewOpticalReader.readWith(
        _webCtrl,
        d.ip,
        creds: creds.isNotEmpty
            ? creds
            : const [
                ['telecomadmin', 'admintelecom']
              ],
      );
      if (reading != null && mounted) {
        setState(() {
          d.optical = reading;
          d.error = '';
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذّرت القراءة الصامتة — جرّب إدخال اعتماد يدوي'),
        ));
      }
    } catch (e) {
      debugPrint('[DeviceDetail] silent optical read error: $e');
    } finally {
      if (mounted) setState(() => _webBusy = false);
    }
  }

  Widget _buildOpticalFailed() {
    return SectionCard(
      title: 'الإشارة الضوئية',
      icon: Icons.fiber_manual_record,
      accent: SdColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.error.isNotEmpty
                ? d.error
                : 'تعذّر قراءة الإشارة الضوئية — جرّب إدخال اعتماد telecomadmin يدوياً.',
            style: SdText.bodySm,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (Platform.isWindows)
                SdButton(
                  icon: _webBusy
                      ? Icons.hourglass_top_rounded
                      : Icons.auto_fix_high_rounded,
                  label: _webBusy
                      ? 'جارٍ القراءة الصامتة...'
                      : 'قراءة متقدمة صامتة (موصى به)',
                  kind: SdButtonKind.accent,
                  onPressed: (_busy || _webBusy) ? null : _silentWebViewRead,
                ),
              SdButton(
                icon: Icons.login_rounded,
                label: 'إدخال اعتماد وإعادة المحاولة',
                kind: SdButtonKind.secondary,
                onPressed: _busy ? null : _enterCredentials,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReport() {
    final r = d.report!;
    return SectionCard(
      title: 'تفاصيل الجهاز',
      icon: Icons.info_rounded,
      accent: _indigo,
      child: Column(
        children: [
          if (r.model.isNotEmpty) InfoRow('الموديل', r.model),
          if (r.firmware.isNotEmpty) InfoRow('الفيرموير', r.firmware),
          if (r.hardwareVersion.isNotEmpty) InfoRow('نسخة العتاد', r.hardwareVersion),
          if (r.uptime.isNotEmpty) InfoRow('مدة التشغيل', r.uptime),
          if (r.wanConnectionType.isNotEmpty)
            InfoRow('نوع اتصال WAN', r.wanConnectionType),
          if (r.pppoeUser.isNotEmpty) InfoRow('مستخدم PPPoE', r.pppoeUser),
          if (r.wanIp.isNotEmpty) InfoRow('عنوان WAN', r.wanIp),
          if (r.lanIp.isNotEmpty) InfoRow('عنوان LAN', r.lanIp),
          if (r.macAddress.isNotEmpty) InfoRow('MAC', r.macAddress),
          if (r.wifiSsid.isNotEmpty) InfoRow('اسم WiFi', r.wifiSsid),
          if (r.wifiBand.isNotEmpty) InfoRow('النطاق', r.wifiBand),
          if (r.wifiChannel != null) InfoRow('القناة', '${r.wifiChannel}'),
          if (r.cpuUsagePercent != null)
            InfoRow('استهلاك المعالج', '${r.cpuUsagePercent!.toStringAsFixed(0)}%'),
          if (r.memUsagePercent != null)
            InfoRow('استهلاك الذاكرة', '${r.memUsagePercent!.toStringAsFixed(0)}%'),
          if (r.temperatureC != null)
            InfoRow('الحرارة', '${r.temperatureC!.toStringAsFixed(1)} °C'),
          ...r.extra.entries.map((e) => InfoRow(e.key, e.value)),
        ],
      ),
    );
  }

  Widget _buildClients() {
    final clients = d.report!.clients;
    return SectionCard(
      title: 'الأجهزة المتصلة (${clients.length})',
      icon: Icons.group_rounded,
      accent: SdGroup.neutral.tone.base,
      child: Column(
        children: clients
            .map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.smartphone_rounded,
                          size: 16, color: SdColors.faint),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.hostname.isNotEmpty ? c.hostname : c.ip,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 12.5)),
                            Text('${c.ip}  •  ${c.mac}',
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    color: SdColors.muted,
                                    fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                      if (c.vendor.isNotEmpty)
                        Text(c.vendor,
                            style: const TextStyle(
                                fontSize: 11.5, color: SdColors.faint)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}
