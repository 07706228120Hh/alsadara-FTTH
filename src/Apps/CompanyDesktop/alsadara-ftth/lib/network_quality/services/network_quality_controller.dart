/// منسّق فحص الجودة الكامل — Network Quality
///
/// يشغّل مراحل الفحص بالتتابع ويبثّ التقدّم عبر callbacks، ثم يبني التقرير
/// النهائي بالدرجة الكلّية والتوصيات.
library;

import 'package:flutter/foundation.dart';

import '../models/device_models.dart';
import '../models/quality_models.dart';
import 'device_discovery_service.dart';
import 'device_info_service.dart';
import 'device_inspector_service.dart';
import 'latency_service.dart';
import 'optical_signal_service.dart';
import 'quality_scorer.dart';
import 'speed_test_service.dart';
import 'wifi_signal_service.dart';

/// مرحلة الفحص الحالية (للعرض في الواجهة).
enum QualityStage {
  idle,
  devices,
  device,
  wifi,
  optical,
  ping,
  dns,
  download,
  upload,
  traceroute,
  done,
}

extension QualityStageX on QualityStage {
  String get arabicLabel {
    switch (this) {
      case QualityStage.idle:
        return 'جاهز';
      case QualityStage.devices:
        return 'اكتشاف أجهزة الشبكة وفحصها';
      case QualityStage.device:
        return 'قراءة مواصفات جهاز الفحص';
      case QualityStage.wifi:
        return 'فحص إشارة WiFi';
      case QualityStage.optical:
        return 'قراءة الإشارة الضوئية (الفايبر)';
      case QualityStage.ping:
        return 'قياس زمن الاستجابة والتذبذب';
      case QualityStage.dns:
        return 'قياس استجابة DNS';
      case QualityStage.download:
        return 'قياس سرعة التنزيل';
      case QualityStage.upload:
        return 'قياس سرعة الرفع';
      case QualityStage.traceroute:
        return 'تتبّع المسار';
      case QualityStage.done:
        return 'اكتمل الفحص';
    }
  }
}

class QualityTestOptions {
  final bool testDevices; // اكتشاف وفحص أجهزة الشبكة
  final bool testOptical;
  final bool testSpeed;
  final bool testTraceroute;
  final String pingHost;

  const QualityTestOptions({
    this.testDevices = true,
    this.testOptical = true,
    this.testSpeed = true,
    this.testTraceroute = false,
    this.pingHost = '8.8.8.8',
  });
}

class NetworkQualityController {
  /// callbacks للتحديث الحيّ.
  void Function(QualityStage stage, double overallProgress)? onStage;
  void Function(double mbps, double fraction)? onSpeedTick;
  void Function(String status)? onDiscoveryStatus;

  bool _running = false;
  bool get isRunning => _running;

  /// يشغّل الفحص الكامل ويُعيد التقرير النهائي.
  Future<FullQualityReport> run({
    QualityTestOptions options = const QualityTestOptions(),
    required DateTime now,
  }) async {
    _running = true;
    try {
      // 1. مواصفات جهاز الفحص (ثانوي)
      _emit(QualityStage.device, 0.03);
      final device = await DeviceInfoService.collect();

      // 2. اكتشاف أجهزة الشبكة وفحصها العميق
      DiscoveryResult? discovery;
      if (options.testDevices) {
        _emit(QualityStage.devices, 0.08);
        final disc = DeviceDiscoveryService()
          ..onStatus = (s) => onDiscoveryStatus?.call(s);
        discovery = await disc.discover(scanClients: true);
        // فحص عميق للأجهزة البنيوية (ONU/راوتر/AP) بالاعتماد الافتراضي.
        final structural = discovery.devices
            .where((d) => d.isOnu || d.isGateway || d.hasWebUi)
            .toList();
        for (var i = 0; i < structural.length; i++) {
          final d = structural[i];
          onDiscoveryStatus?.call('فحص ${d.displayName} (${d.ip})...');
          _emit(QualityStage.devices,
              0.08 + 0.17 * ((i + 1) / structural.length));
          await DeviceInspectorService.inspect(d);
          // بصريات هواوي الحديثة تحتاج دخولاً عبر المتصفح (حارس جلسة) —
          // تُقرأ لاحقاً في شاشة الفحص عبر WebView مُركَّب خفيّ (onNeedWebViewOptic).
        }
      }

      // 3. WiFi
      _emit(QualityStage.wifi, 0.27);
      final wifi = await WifiSignalService.read();

      // 3. الإشارة الضوئية (اختياري)
      OpticalSignalInfo optical = OpticalSignalInfo.none;
      if (options.testOptical) {
        _emit(QualityStage.optical, 0.33);
        optical = await OpticalSignalService.read();
        // إن فشلت القراءة الخاملة، استعمل قراءة الـONU المكتشَف (عبر المتصفح).
        if (!optical.available && discovery != null) {
          final onu = discovery.devices
              .where((d) => d.isOnu && d.optical != null)
              .toList();
          if (onu.isNotEmpty) {
            final r = onu.first.optical!;
            optical = OpticalSignalInfo(
              available: true,
              rxPowerDbm: r.rxPowerDbm,
              txPowerDbm: r.txPowerDbm,
              voltage: r.voltage,
              biasCurrentMa: r.biasCurrentMa,
              temperatureC: r.temperatureC,
              source: 'ONU ${onu.first.ip}',
            );
          }
        }
      }

      // 4. Ping / Jitter / Loss
      _emit(QualityStage.ping, 0.40);
      final ping = await LatencyService.measurePing(host: options.pingHost);

      // 5. DNS
      _emit(QualityStage.dns, 0.50);
      final dns = await LatencyService.measureDns();
      final hasNet = ping.received > 0 || await LatencyService.hasInternet();

      // 6. سرعة التنزيل/الرفع (اختياري)
      double? down;
      double? up;
      if (options.testSpeed && hasNet) {
        _emit(QualityStage.download, 0.60);
        down = await SpeedTestService.download(
          onProgress: (p) => onSpeedTick?.call(p.mbps, p.fraction),
        );
        _emit(QualityStage.upload, 0.80);
        up = await SpeedTestService.upload();
      }

      // 7. Traceroute (اختياري)
      List<String> trace = const [];
      if (options.testTraceroute && hasNet) {
        _emit(QualityStage.traceroute, 0.90);
        trace = await LatencyService.traceroute(host: options.pingHost);
      }

      final perf = InternetPerfResult(
        pingMs: ping.avg,
        minPingMs: ping.minVal,
        maxPingMs: ping.maxVal,
        jitterMs: ping.jitter,
        packetLossPercent: ping.packetLossPercent,
        downloadMbps: down,
        uploadMbps: up,
        dnsMs: dns,
        hasInternet: hasNet,
        traceroute: trace,
      );

      final score = QualityScorer.overall(
        performance: perf,
        optical: optical,
        wifi: wifi,
        device: device,
      );
      final report = FullQualityReport(
        device: device,
        wifi: wifi,
        optical: optical,
        performance: perf,
        overallScore: score,
        overallRating: QualityScorer.ratingFromScore(score),
        recommendations: QualityScorer.buildRecommendations(
          p: perf,
          o: optical,
          w: wifi,
          d: device,
        ),
        timestamp: now,
        discovery: discovery,
      );

      _emit(QualityStage.done, 1.0);
      return report;
    } catch (e) {
      debugPrint('[QualityController] error: $e');
      rethrow;
    } finally {
      _running = false;
    }
  }

  void _emit(QualityStage s, double p) => onStage?.call(s, p);
}
