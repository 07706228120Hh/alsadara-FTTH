/// لوحة «فحص متقدّم» — Network Quality
///
/// بطاقات أدوات 3D متجاوبة (عمود على الهاتف، شبكة عمودين على الآيباد/الحاسوب).
/// المرحلة 1: اختبار DNS + المراقبة الحيّة (بطاقتان فعّالتان) + بطاقتان «قريباً».
library;

import 'package:flutter/material.dart';

import '../../frontend/frontend.dart';
import '../widgets/depth_3d.dart';
import 'dns_benchmark_page.dart';
import 'history_trend_page.dart';
import 'live_monitor_page.dart';
import 'router_wifi_edit_page.dart';
import 'wifi_channel_analyzer_page.dart';

class AdvancedToolsPage extends StatelessWidget {
  const AdvancedToolsPage({super.key, this.gatewayIp, this.onuIp});

  /// معلومات مفيدة من التقرير (اختيارية) — تُستخدم مستقبلاً لأدوات الراوتر.
  final String? gatewayIp;
  final String? onuIp;

  @override
  Widget build(BuildContext context) {
    return SdPage(
      padding: EdgeInsets.zero,
      scrollable: false,
      maxWidth: double.infinity,
      appBar: const SdAppBar(title: 'فحص متقدم'),
      body: LayoutBuilder(
          builder: (ctx, c) {
            final w = c.maxWidth;
            final isPhone = w < 600;
            final twoCols = w >= 600; // آيباد/حاسوب: شبكة عمودين
            final maxContentWidth = isPhone ? w : (w >= 1024 ? 860.0 : 720.0);

            final cards = <Widget>[
              _ToolCard(
                title: 'اختبار ومقارنة DNS',
                subtitle: 'قياس أسرع مزوّد DNS واختيار الموصى به',
                icon: Icons.dns_rounded,
                gradient: const [SdColors.primaryLight, Nq3d.indigo],
                iconEdge: Nq3d.indigoDark,
                glow: const Color(0x591A237E),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DnsBenchmarkPage()),
                ),
              ),
              _ToolCard(
                title: 'المراقبة الحيّة',
                subtitle: 'مراقبة فورية لاستقرار الاتصال ورسم حيّ للـping',
                icon: Icons.monitor_heart_rounded,
                gradient: const [SdColors.fieldBase, Nq3d.teal],
                iconEdge: Nq3d.tealDark,
                glow: const Color(0x7300838F),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => LiveMonitorPage(host: gatewayIp ?? '8.8.8.8')),
                ),
              ),
              _ToolCard(
                title: 'محلّل قنوات WiFi',
                subtitle: 'عرض القنوات المزدحمة واقتراح الأفضل (2.4/5GHz)',
                icon: Icons.wifi_find_rounded,
                gradient: const [SdColors.primarySoft, SdColors.platformBase],
                iconEdge: SdColors.platformEdge,
                glow: const Color(0x595E35B1),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const WifiChannelAnalyzerPage()),
                ),
              ),
              _ToolCard(
                title: 'السجلّ والاتجاه',
                subtitle: 'اتجاه نتائج الفحوص عبر الوقت والفحوص السابقة',
                icon: Icons.timeline_rounded,
                gradient: const [SdColors.primarySoft, SdColors.primaryMid],
                iconEdge: Nq3d.indigoDark,
                glow: const Color(0x591A237E),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryTrendPage()),
                ),
              ),
              _ToolCard(
                title: 'تعديل إعدادات WiFi الراوتر',
                subtitle: 'تغيير اسم/كلمة مرور الشبكة (Huawei/ZTE)',
                icon: Icons.settings_input_antenna_rounded,
                gradient: const [SdColors.primarySoft, SdColors.primaryMid],
                iconEdge: Nq3d.indigoDark,
                glow: const Color(0x591A237E),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          RouterWifiEditPage(gatewayIp: gatewayIp)),
                ),
              ),
            ];

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('أدوات تشخيص متقدّمة',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontFamily: SdText.family,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              color: SdColors.ink)),
                      const SizedBox(height: 2),
                      const Text('أدوات إضافية لتحليل الشبكة ومراقبة الاتصال',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontFamily: SdText.family,
                              fontSize: 13,
                              color: SdColors.muted)),
                      const SizedBox(height: 18),
                      if (twoCols)
                        _grid(cards)
                      else
                        ...cards.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: e,
                            )),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
    );
  }

  /// شبكة عمودين (لا نستخدم stretch على Row بارتفاع غير محدود؛ كل بطاقة داخل
  /// Expanded بعرض محدود، والصفوف IntrinsicHeight لتساوي الارتفاع بأمان).
  Widget _grid(List<Widget> cards) {
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      final left = cards[i];
      final right = i + 1 < cards.length ? cards[i + 1] : null;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              const SizedBox(width: 14),
              Expanded(child: right ?? const SizedBox.shrink()),
            ],
          ),
        ),
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.iconEdge,
    required this.glow,
    this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final Color iconEdge;
  final Color glow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final card = Raised3D(
      onTap: onTap,
      tilt: !disabled,
      edgeColor: Nq3d.edge,
      glowColor: disabled ? const Color(0x22000000) : glow,
      radius: 20,
      semanticLabel: title,
      child: Opacity(
        opacity: disabled ? 0.6 : 1,
        child: Row(
          children: [
            RaisedIconTile(
              icon: icon,
              color: Colors.white,
              edgeColor: iconEdge,
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: gradient,
              ),
              size: 54,
              iconSize: 27,
              radius: 15,
              depth: 5,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: Nq3d.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: Nq3d.muted, height: 1.4)),
                ],
              ),
            ),
            if (!disabled) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_left_rounded, color: Nq3d.faint),
            ],
          ],
        ),
      ),
    );
    return card;
  }
}
