/// شاشة تشغيل فحص الجودة مع تقدّم حيّ — Network Quality
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_windows/webview_windows.dart' as wvwin;

import '../models/device_models.dart';
import '../models/quality_models.dart';
import '../services/device_credentials_service.dart';
import '../services/network_quality_controller.dart';
import '../services/webview_optical_reader.dart';
import 'quality_results_page.dart';

class QualityScanPage extends StatefulWidget {
  const QualityScanPage({super.key});

  @override
  State<QualityScanPage> createState() => _QualityScanPageState();
}

class _QualityScanPageState extends State<QualityScanPage> {
  static const _indigo = Color(0xFF1A237E);

  final _controller = NetworkQualityController();
  bool _running = false;
  QualityStage _stage = QualityStage.idle;
  double _progress = 0;
  double _liveMbps = 0;
  String _error = '';
  String _discoveryStatus = '';

  // خيارات الفحص (يتحكّم بها المستخدم).
  bool _optDevices = true;
  bool _optFiber = true;
  bool _optSpeed = true;
  bool _optTrace = false;

  // WebView (ويندوز) لقراءة بصريات هواوي — يظهر مرئياً أثناء القراءة فقط.
  final wvwin.WebviewController _webCtrl = wvwin.WebviewController();
  bool _webReady = false;
  bool _webBusy = false;

  @override
  void initState() {
    super.initState();
    _controller.onStage = (s, p) {
      if (mounted) setState(() {
            _stage = s;
            _progress = p;
          });
    };
    _controller.onSpeedTick = (mbps, frac) {
      if (mounted) setState(() => _liveMbps = mbps);
    };
    _controller.onDiscoveryStatus = (s) {
      if (mounted) setState(() => _discoveryStatus = s);
    };
    _initWebView();
  }

  Future<void> _initWebView() async {
    if (!Platform.isWindows) return;
    try {
      await _webCtrl.initialize();
      await _webCtrl.setBackgroundColor(Colors.white);
      if (mounted) setState(() => _webReady = true);
    } catch (e) {
      debugPrint('[Scan] webview init failed: $e');
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

  /// بعد الفحص: اقرأ بصريات ONU هواوي عبر WebView (يظهر مرئياً ~15ث).
  Future<void> _augmentOptical(FullQualityReport report) async {
    if (!Platform.isWindows || !_webReady || !_optFiber) return;
    final devices = report.discovery?.devices;
    if (devices == null) return;
    NetworkDevice? onu;
    for (final d in devices) {
      final s = '${d.brandGuess} ${d.vendor} ${d.pageTitle}'.toLowerCase();
      final huawei = s.contains('huawei') ||
          s.contains('hg8') ||
          s.contains('echolife') ||
          d.ip.endsWith('.100.1');
      if (d.isOnu && d.optical == null && huawei) {
        onu = d;
        break;
      }
    }
    if (onu == null) return;
    // أظهر WebView (WebView2 يحتاج ظهوراً فعلياً كي يعمل).
    if (mounted) setState(() => _webBusy = true);
    await Future.delayed(const Duration(milliseconds: 800));
    try {
      final creds = (await DeviceCredentialsService.candidatesFor(
              onu.ip, onu.brandGuess.isNotEmpty ? onu.brandGuess : onu.vendor))
          .map((c) => [c.user, c.pass])
          .toList();
      final r = await WebViewOpticalReader.readWith(_webCtrl, onu.ip, creds: creds);
      if (r != null) {
        onu.optical = r;
        onu.error = '';
      }
    } catch (e) {
      debugPrint('[Scan] augment optical error: $e');
    } finally {
      if (mounted) setState(() => _webBusy = false);
    }
  }

  Future<void> _ensurePermission() async {
    // على أندرويد تحتاج قراءة WiFi إذن الموقع.
    if (Platform.isAndroid) {
      final st = await Permission.location.status;
      if (!st.isGranted) await Permission.location.request();
    }
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _error = '';
      _liveMbps = 0;
      _progress = 0;
    });
    try {
      await _ensurePermission();
      final report = await _controller.run(
        now: DateTime.now(),
        options: QualityTestOptions(
          testDevices: _optDevices,
          testOptical: _optFiber,
          testSpeed: _optSpeed,
          testTraceroute: _optTrace,
        ),
      );
      // قراءة بصريات هواوي عبر WebView المرئي لحظياً (ويندوز).
      await _augmentOptical(report);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => QualityResultsPage(report: report)),
      );
      if (mounted) setState(() => _running = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = 'حدث خطأ أثناء الفحص: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F4F8),
        appBar: AppBar(
          title: const Text('فحص جودة الإنترنت',
              style: TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: _indigo,
          foregroundColor: Colors.white,
        ),
        body: Stack(
          children: [
            // WebView يظهر مرئياً أثناء قراءة البصريات فقط.
            if (Platform.isWindows && _webReady && _webBusy)
              Positioned.fill(child: wvwin.Webview(_webCtrl)),
            if (!_webBusy)
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: _running ? _buildRunning() : _buildIdle(),
                  ),
                ),
              ),
            if (_webBusy)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  color: _indigo,
                  child: const Row(
                    children: [
                      SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'جارٍ قراءة الإشارة الضوئية تلقائياً... (لا حاجة لأي تدخّل — سيختفي تلقائياً)',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdle() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.network_check_rounded, size: 72, color: _indigo),
        const SizedBox(height: 12),
        const Text('فحص شامل ودقيق لجودة الاتصال',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 6),
        Text(
          'يقيس زمن الاستجابة والتذبذب وفقدان الحزم والسرعة وإشارة الفايبر الضوئية وWiFi ومواصفات الجهاز.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.6),
        ),
        const SizedBox(height: 20),
        _optionTile('اكتشاف وفحص أجهزة الشبكة (ONU/راوتر/المتصلين)', _optDevices,
            (v) => setState(() => _optDevices = v), Icons.lan_rounded),
        _optionTile('فحص الإشارة الضوئية للفايبر (Rx/Tx)', _optFiber,
            (v) => setState(() => _optFiber = v), Icons.fiber_manual_record),
        _optionTile('قياس سرعة التنزيل/الرفع', _optSpeed,
            (v) => setState(() => _optSpeed = v), Icons.speed_rounded),
        _optionTile('تتبّع المسار (Traceroute)', _optTrace,
            (v) => setState(() => _optTrace = v), Icons.route_rounded),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('ابدأ الفحص',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _start,
          ),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(_error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _optionTile(
      String title, bool value, ValueChanged<bool> onChanged, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeColor: _indigo,
        dense: true,
        secondary: Icon(icon, color: _indigo, size: 20),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    );
  }

  Widget _buildRunning() {
    final showSpeed = _stage == QualityStage.download && _liveMbps > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        SizedBox(
          width: 150,
          height: 150,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: CircularProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                  strokeWidth: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation(_indigo),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${(_progress * 100).round()}%',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 26,
                          color: _indigo)),
                  if (showSpeed)
                    Text('${_liveMbps.toStringAsFixed(1)} Mbps',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(_stage.arabicLabel,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        if (_stage == QualityStage.devices && _discoveryStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_discoveryStatus,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          )
        else
          Text('جارٍ الفحص — قد يستغرق حتى دقيقة',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ],
    );
  }
}
