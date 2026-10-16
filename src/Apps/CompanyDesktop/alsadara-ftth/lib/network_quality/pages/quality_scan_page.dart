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
import '../widgets/depth_3d.dart';
import 'quality_results_page.dart';

class QualityScanPage extends StatefulWidget {
  const QualityScanPage({super.key});

  @override
  State<QualityScanPage> createState() => _QualityScanPageState();
}

class _QualityScanPageState extends State<QualityScanPage> {

  final _controller = NetworkQualityController();
  // الفحص يبدأ تلقائياً فور فتح الشاشة ⇒ تبدأ الواجهة على مشهد التقدّم مباشرةً.
  bool _running = true;
  bool _inFlight = false; // حارس يمنع بدء فحصين متوازيين
  QualityStage _stage = QualityStage.idle;
  double _progress = 0;
  double _liveMbps = 0;
  String _error = '';
  String _discoveryStatus = '';

  // كل الخدمات مُفعّلة دائماً (لا شاشة مفاتيح).
  // ملاحظة: تتبّع المسار (Traceroute) نُقل إلى زرّ عند الطلب داخل صفحة النتائج،
  // ولا يُشغَّل أثناء الفحص.

  // WebView (ويندوز) لقراءة بصريات هواوي — مُركَّب دائماً خلف طبقة معتمة ولا
  // يظهر للمستخدم إطلاقاً (قراءة صامتة عبر JS/XHR). WebView2 يحتاج تركيباً
  // فعلياً في الشجرة ليعمل، لذا نُبقيه مرسوماً لكن محجوباً بالكامل.
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
    // ابدأ الفحص تلقائياً بعد أوّل إطار (setState داخل _start آمن حينها).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
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

  /// بعد الفحص: اقرأ بصريات ONU هواوي عبر WebView خفيّ (محجوب بالكامل، صامت).
  Future<void> _augmentOptical(FullQualityReport report) async {
    if (!Platform.isWindows || !_webReady) return;
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
    // فعّل الـWebView الخفيّ (مرسوم خلف طبقة معتمة — لا يراه المستخدم).
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
    if (_inFlight) return; // يمنع بدء فحصين متوازيين
    _inFlight = true;
    if (mounted) {
      setState(() {
        _running = true;
        _error = '';
        _liveMbps = 0;
        _progress = 0;
      });
    }
    try {
      await _ensurePermission();
      // كل الخدمات مُفعّلة دائماً (التتبّع عند الطلب في النتائج).
      final report = await _controller.run(
        now: DateTime.now(),
        options: const QualityTestOptions(
          testDevices: true,
          testOptical: true,
          testSpeed: true,
          testTraceroute: false,
        ),
      );
      // قراءة بصريات هواوي عبر WebView الخفيّ الصامت (ويندوز).
      await _augmentOptical(report);
      if (!mounted) return;
      // استبدال الشاشة: يعود زرّ الرجوع من النتائج إلى «اختر الأداة».
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => QualityResultsPage(report: report)),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = 'حدث خطأ أثناء الفحص: $e';
        });
      }
    } finally {
      _inFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Nq3d.ground,
        appBar: nq3dAppBar('فحص جودة الإنترنت'),
        body: Stack(
          children: [
            // الواجهة الطبيعية هي الطبقة الأساسية (كاملة الشاشة).
            // أثناء الفحص: تملأ شاشة واحدة بلا تمرير (تحجيم متجاوب). عند الخطأ:
            // محتوى قصير مُوسَّط (قابل للتمرير احتياطاً فقط).
            Positioned.fill(
              child: Container(
                color: Nq3d.ground,
                child: SafeArea(
                  child: _running
                      ? _buildRunning()
                      : Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480),
                              child: _buildError(),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            // WebView2 (ويندوز) يرسم طبقة native فوق Flutter ولا يمكن حجبه بطبقة
            // Flutter؛ لذا نركّبه فقط أثناء القراءة الصامتة بحجم 1×1 في الزاوية
            // (غير مرئي عملياً) ومتجاهِلاً للمؤشّر، حتى لا يغطّي الواجهة ولا
            // تنهار أحداث المؤشّر. القراءة تتم عبر JS/XHR على المتحكّم نفسه.
            if (Platform.isWindows && _webReady && _webBusy)
              Positioned(
                left: 0,
                top: 0,
                width: 1,
                height: 1,
                child: IgnorePointer(
                  ignoring: true,
                  child: wvwin.Webview(_webCtrl),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════ الواجهة (تصميم ثلاثي الأبعاد) ═══════════════════

  /// واجهة الخطأ الوحيدة غير «جارٍ الفحص»: رسالة + زرّ إعادة المحاولة.
  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.error_outline_rounded,
            color: Color(0xFFC62828), size: 56),
        const SizedBox(height: 14),
        const Text('تعذّر إكمال الفحص',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 19, color: Nq3d.ink)),
        const SizedBox(height: 6),
        Text(
          _error.isNotEmpty ? _error : 'حدث خطأ غير متوقّع أثناء الفحص.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Nq3d.muted, height: 1.7),
        ),
        const SizedBox(height: 22),
        Raised3D(
          onTap: _start,
          radius: 16,
          depth: 6,
          padding: EdgeInsets.zero,
          edgeColor: Nq3d.indigoDark,
          glowColor: const Color(0x990F1660),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF283593), Nq3d.indigo],
          ),
          semanticLabel: 'إعادة المحاولة',
          child: const SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.refresh_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text('إعادة المحاولة',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// مراحل الفحص الفعلية بالترتيب الذي يبثّه NetworkQualityController
  /// (كل الخدمات مُفعّلة دائماً).
  static const List<QualityStage> _plannedStages = [
    QualityStage.device,
    QualityStage.devices,
    QualityStage.wifi,
    QualityStage.optical,
    QualityStage.ping,
    QualityStage.dns,
    QualityStage.download,
    QualityStage.upload,
  ];

  Widget _buildRunning() {
    final showSpeed = (_stage == QualityStage.download ||
            _stage == QualityStage.upload) &&
        _liveMbps > 0;
    final label = _webBusy ? 'قراءة الإشارة الضوئية (صامتة)' : _stage.arabicLabel;
    final indeterminate = _progress == 0 || _webBusy;

    final String hint;
    if (_webBusy) {
      hint = 'جارٍ قراءة بيانات الـONU تلقائياً دون فتح واجهته — لحظات...';
    } else if (_stage == QualityStage.devices && _discoveryStatus.isNotEmpty) {
      hint = _discoveryStatus;
    } else {
      hint = 'جارٍ الفحص — قد يستغرق حتى دقيقة';
    }

    final stages = _plannedStages;
    final allDone = _stage == QualityStage.done || _webBusy;
    final cur = stages.indexOf(_webBusy ? QualityStage.optical : _stage);

    // تحجيم متجاوب يملأ شاشة واحدة بلا تمرير: نشتقّ الأحجام من الارتفاع والعرض
    // المتاحين (LayoutBuilder يعطي أبعاد المساحة أسفل الشريط ضمن SafeArea).
    return LayoutBuilder(
      builder: (ctx, c) {
        final h = c.maxHeight.isFinite ? c.maxHeight : 640.0;
        final w = c.maxWidth.isFinite ? c.maxWidth : 360.0;
        final isPhone = w < 600;
        final isDesktop = w >= 1024;
        final pad = h < 560 ? 10.0 : 16.0;
        final innerW = (w - pad * 2).clamp(240.0, 480.0).toDouble();

        // قرص التقدّم: محدود بعرض المحتوى وبنسبة من الارتفاع (ارتفاع القرص ≈
        // العرض × 0.75 داخل ProgressDisc3D).
        final discByW = isDesktop ? 300.0 : (isPhone ? 230.0 : 280.0);
        final discW =
            innerW.clamp(0.0, discByW).clamp(0.0, (h * 0.40) / 0.75).toDouble();
        final pct = (_progress * 100).round();
        final pctSize = (discW * 0.17).clamp(26.0, 54.0).toDouble();

        // مشهد المرحلة: نسبة التصميم 150/360؛ نحدّ عرضه بحيث لا يتجاوز
        // ارتفاعه الحيّز المخصّص (المتبقّي بعد بقية العناصر).
        final sceneH = (h * (isPhone ? 0.22 : 0.26)).clamp(70.0, 150.0).toDouble();
        final sceneW = (sceneH / (150 / 360)).clamp(220.0, innerW).toDouble();

        return Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1) قرص التقدّم + النسبة/السرعة.
              ProgressDisc3D(
                progress: indeterminate ? null : _progress,
                maxWidth: discW,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_webBusy)
                      Icon(Icons.fiber_manual_record,
                          color: Nq3d.teal, size: pctSize * 0.85)
                    else
                      Text('$pct%',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: pctSize,
                              height: 1.05,
                              color: Nq3d.indigo)),
                    if (showSpeed)
                      Text(
                        '${_liveMbps.toStringAsFixed(1)} Mbps ${_stage == QualityStage.upload ? '↑' : '↓'}',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                            fontSize: (discW * 0.06).clamp(12.0, 16.0),
                            fontWeight: FontWeight.w800,
                            color: Nq3d.teal),
                      ),
                  ],
                ),
              ),
              // 2) بطاقة مشهد المرحلة 3D (مرنة الحجم) + اسم المرحلة والتلميح.
              Flexible(
                child: Container(
                  padding: EdgeInsets.fromLTRB(12, pad * 0.6, 12, pad * 0.8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow:
                        raisedShadow(depth: 5, glow: const Color(0x661A237E)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StageScene3D(
                        stage: _webBusy ? QualityStage.optical : _stage,
                        maxWidth: sceneW,
                      ),
                      SizedBox(height: pad * 0.4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(label,
                            key: ValueKey(label),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: isPhone ? 15 : 17,
                                color: Nq3d.ink)),
                      ),
                      const SizedBox(height: 2),
                      Text(hint,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: Nq3d.muted)),
                    ],
                  ),
                ),
              ),
              // 3) شريط المراحل الأفقي (horizontal stepper) + اسم المرحلة.
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: pad * 0.5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow:
                      raisedShadow(depth: 4, glow: const Color(0x661A237E)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StageStrip3D(
                      stages: stages,
                      currentIndex: cur,
                      allDone: allDone,
                      maxBadge: isPhone ? 28 : 34,
                    ),
                    SizedBox(height: pad * 0.35),
                    Text(
                      allDone
                          ? 'اكتمل الفحص'
                          : 'المرحلة ${cur < 0 ? 1 : cur + 1} من ${stages.length}: ${(_webBusy ? QualityStage.optical : _stage).arabicLabel}',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Nq3d.indigo),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
