/// ماسح رموز QR بالكاميرا — لسجل العقارات (العنوان الوطني).
///
/// يفتح الكاميرا (ويندوز/أندرويد/iOS عبر حزمة camera)، يلتقط إطارات دورياً
/// ويفكّ تشفير أي رمز QR عبر zxing2 (Dart خالص) بعيداً عن الخيط الرئيسي
/// (compute). عند العثور على رمز يُعيده نصّاً خاماً (مثل `SADARA|P:<token>`)
/// ليُكمِل مسار الحلّ القائم في قائمة العقارات.
library;

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import '../../frontend/tokens/sd_colors.dart';

/// يفكّ تشفير رمز QR من بايتات صورة — يُشغَّل في isolate عبر [compute].
/// يُعيد نصّ الرمز أو null إن لم يُعثر على رمز صالح.
String? decodeQrFromImageBytes(Uint8List bytes) {
  try {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    final source = RGBLuminanceSource(
      image.width,
      image.height,
      image
          .convert(numChannels: 4)
          .getBytes(order: img.ChannelOrder.abgr)
          .buffer
          .asInt32List(),
    );
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    final result = QRCodeReader().decode(bitmap);
    final text = result.text.trim();
    return text.isEmpty ? null : text;
  } catch (_) {
    // لا رمز في هذا الإطار (NotFoundException) أو صورة غير قابلة للفكّ.
    return null;
  }
}

/// شاشة مسح QR بالكاميرا. تُعيد عبر [Navigator.pop] نصّ الرمز المكتشَف.
class PropertyQrScannerScreen extends StatefulWidget {
  const PropertyQrScannerScreen({super.key});

  @override
  State<PropertyQrScannerScreen> createState() =>
      _PropertyQrScannerScreenState();
}

class _PropertyQrScannerScreenState extends State<PropertyQrScannerScreen> {
  CameraController? _controller;
  Timer? _timer;
  bool _busy = false;
  bool _found = false;
  bool _disposed = false;
  String? _error;

  // فترة المسح الدوري (التقاط + فكّ تشفير).
  static const _scanInterval = Duration(milliseconds: 700);

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        _setError('لا توجد كاميرا متاحة على هذا الجهاز');
        return;
      }
      // على الهاتف نُفضّل الكاميرا الخلفية؛ على سطح المكتب أول كاميرا.
      final cam = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final controller = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (_disposed) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      _timer = Timer.periodic(_scanInterval, (_) => _scanTick());
    } catch (e) {
      _setError('تعذّر فتح الكاميرا: $e');
    }
  }

  void _setError(String m) {
    if (_disposed) return;
    setState(() => _error = m);
  }

  Future<void> _scanTick() async {
    if (_busy || _found || _disposed) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _busy = true;
    try {
      final shot = await c.takePicture();
      final bytes = await shot.readAsBytes();
      final text = await compute(decodeQrFromImageBytes, bytes);
      if (text != null && !_found && !_disposed) {
        _found = true;
        _timer?.cancel();
        if (mounted) Navigator.of(context).pop(text);
      }
    } catch (_) {
      // تجاهل أخطاء الالتقاط العابرة؛ تُعاد المحاولة في النبضة التالية.
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('مسح رمز QR بالكاميرا',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        body: _error != null
            ? _buildError()
            : _controller == null
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : _buildPreview(),
      ),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded,
                  color: Colors.white70, size: 56),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                    backgroundColor: SdColors.primary),
                child: Text('رجوع',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ],
          ),
        ),
      );

  Widget _buildPreview() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(child: CameraPreview(_controller!)),
        // إطار استهداف.
        IgnorePointer(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: SdColors.primary, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          bottom: 28,
          left: 24,
          right: 24,
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'وجّه الكاميرا نحو رمز QR — يُمسح تلقائياً',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _scanTick,
                style: FilledButton.styleFrom(
                  backgroundColor: SdColors.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.center_focus_strong_rounded,
                    color: Colors.white),
                label: Text('التقاط الآن',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
