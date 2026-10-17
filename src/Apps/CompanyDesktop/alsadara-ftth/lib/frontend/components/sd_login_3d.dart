/// خلفية تسجيل الدخول ثلاثية الأبعاد الحقيقية — نظام تصميم الصدارة.
///
/// مدينة ليلية حقيقية (Three.js: إضاءة فيزيائية، انعكاسات، ظلال، ضباب، توهّج Bloom)
/// تملأ الشاشة كاملة: برج الصدارة الملتفّ في المركز وشعاره العائم، شبكة ألياف
/// تتدفّق فيها نبضات، سيارات وأضواء شوارع، ومبانٍ يمكن المرور عليها والدخول إليها.
///
/// يعمل بلا إنترنت: المشهد كاملاً (مع مكتبة Three.js) ملف واحد
/// `assets/login3d/city.html` يُحمَّل في WebView:
///  • ويندوز: webview_windows (WebView2).
///  • أندرويد/iOS: webview_flutter.
///  • غير ذلك أو عند فشل WebView: خلفية متدرّجة + [SdLoginScene] (البديل الخفيف).
///
/// [shiftX]: إزاحة أفقية لمركز المشهد بالبكسل (سالب = لليسار) لترك مكان بطاقة الدخول.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart' as wvf;
import 'package:webview_windows/webview_windows.dart' as wvwin;

import 'sd_login_scene.dart';

class SdLogin3DBackground extends StatefulWidget {
  const SdLogin3DBackground({
    super.key,
    this.shiftX = 0,
    this.lowQuality = false,
    this.interactive = true,
    this.htmlAsset = 'assets/login3d/city.html',
    this.logoAsset = 'assets/logo.png',
  });

  final double shiftX;
  final bool lowQuality;
  final bool interactive;
  final String htmlAsset;
  final String logoAsset;

  @override
  State<SdLogin3DBackground> createState() => _SdLogin3DBackgroundState();
}

enum _Mode { loading, windows, mobile, fallback }

class _SdLogin3DBackgroundState extends State<SdLogin3DBackground> {
  _Mode _mode = _Mode.loading;
  bool _ready = false; // يُظهر المشهد بتلاشٍ بعد اكتمال التحميل (بلا وميض أبيض)
  wvwin.WebviewController? _win;
  wvf.WebViewController? _mob;

  static const _bg = Color(0xFF0A1430);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<String> _buildHtml() async {
    final html = await rootBundle.loadString(widget.htmlAsset);
    String logo = '';
    try {
      final bytes = await rootBundle.load(widget.logoAsset);
      logo = 'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}';
    } catch (_) {}
    final cfg = jsonEncode({
      'shiftX': widget.shiftX,
      'quality': widget.lowQuality ? 'low' : 'high',
      'interactive': widget.interactive,
      'logo': logo,
    });
    return html.replaceFirst('/*SD_CONFIG*/', 'window.SD_CFG=$cfg;');
  }

  Future<void> _init() async {
    if (kIsWeb) return _fallback();
    try {
      if (Platform.isWindows) {
        final c = wvwin.WebviewController();
        await c.initialize();
        await c.setBackgroundColor(_bg);
        await c.setPopupWindowPolicy(wvwin.WebviewPopupWindowPolicy.deny);
        c.loadingState.listen((s) {
          if (s == wvwin.LoadingState.navigationCompleted && mounted) {
            Future.delayed(const Duration(milliseconds: 350), () {
              if (mounted) setState(() => _ready = true);
            });
          }
        });
        await c.loadStringContent(await _buildHtml());
        if (!mounted) return c.dispose();
        setState(() {
          _win = c;
          _mode = _Mode.windows;
        });
      } else if (Platform.isAndroid || Platform.isIOS) {
        final c = wvf.WebViewController()
          ..setJavaScriptMode(wvf.JavaScriptMode.unrestricted)
          ..setBackgroundColor(_bg)
          ..setNavigationDelegate(wvf.NavigationDelegate(
            onPageFinished: (_) => Future.delayed(const Duration(milliseconds: 350), () {
              if (mounted) setState(() => _ready = true);
            }),
            onWebResourceError: (_) => _fallback(),
          ));
        await c.loadHtmlString(await _buildHtml());
        if (!mounted) return;
        setState(() {
          _mob = c;
          _mode = _Mode.mobile;
        });
      } else {
        _fallback();
      }
    } catch (e) {
      debugPrint('SdLogin3DBackground: $e — يستخدم البديل');
      _fallback();
    }
  }

  void _fallback() {
    if (mounted) setState(() => _mode = _Mode.fallback);
  }

  @override
  void didUpdateWidget(covariant SdLogin3DBackground old) {
    super.didUpdateWidget(old);
    // تحديث الإزاحة عند تغيّر حجم النافذة دون إعادة تحميل المشهد.
    if (old.shiftX != widget.shiftX) {
      final js = 'window.SD_CFG && (window.SD_CFG.shiftX=${widget.shiftX});';
      _win?.executeScript(js);
      _mob?.runJavaScript(js);
    }
  }

  @override
  void dispose() {
    _win?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.4),
          radius: 1.3,
          colors: [Color(0xFF1A2C66), Color(0xFF0A1430), Color(0xFF050A1C)],
        ),
      ),
    );

    Widget? view;
    switch (_mode) {
      case _Mode.windows:
        view = wvwin.Webview(_win!);
      case _Mode.mobile:
        view = wvf.WebViewWidget(
          controller: _mob!,
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
          },
        );
      case _Mode.fallback:
        return Stack(
          fit: StackFit.expand,
          children: [
            gradient,
            Align(
              alignment: const Alignment(-0.35, -0.1),
              child: IgnorePointer(
                ignoring: !widget.interactive,
                child: const SdLoginScene(maxWidth: 560),
              ),
            ),
          ],
        );
      case _Mode.loading:
        view = null;
    }

    return Semantics(
      label: 'مدينة ثلاثية الأبعاد تفاعلية: برج الصدارة وشبكة الألياف. اسحب للتدوير واضغط على مبنى لعرض تفاصيله',
      child: Stack(
        fit: StackFit.expand,
        children: [
          gradient,
          if (view != null)
            AnimatedOpacity(
              opacity: _ready ? 1 : 0,
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              child: view,
            ),
        ],
      ),
    );
  }
}
