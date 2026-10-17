/// الواجهة الرئيسية لقسم «أدوات الراوتر والشبكة» (أوفلاين) — Network Quality
///
/// تظهر عند الضغط على زر «إعداد الراوتر (أوفلاين)» في شاشة الدخول، وتقدّم
/// خيارين:
///   1) إعداد الراوتر   → الأداة الحالية (OfflineRouterSetupPage) بلا تغيير.
///   2) فحص جودة الإنترنت → نظام الفحص الجديد (هذه الوحدة).
///
/// التصميم ثلاثي الأبعاد: مشهد شبكة مجسّم (فايبر → ONU → راوتر) + بطاقات بارزة
/// تميل عند المرور وتغوص عند الضغط (widgets/depth_3d.dart).
library;

import 'package:flutter/material.dart';

import '../frontend/frontend.dart';
import '../pages/offline_router_setup_page.dart';
import 'pages/quality_scan_page.dart';
import 'widgets/depth_3d.dart';

class NetworkToolsHomePage extends StatelessWidget {
  const NetworkToolsHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return SdPage(
      maxWidth: 520,
      appBar: SdAppBar(
        title: 'أدوات الراوتر والشبكة',
        actions: [
          SdAppBarAction(
            icon: Icons.settings_input_antenna_rounded,
            label: 'إعداد الراوتر',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OfflineRouterSetupPage()),
            ),
          ),
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HomeNetworkScene3D(maxWidth: 380),
          const SizedBox(height: 6),
          const Text('اختر الأداة',
              style: TextStyle(
                  fontFamily: SdText.family,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  color: SdColors.ink)),
          const SizedBox(height: 2),
          const Text('أدوات تعمل بدون إنترنت — اتصال محلي بالراوتر',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: SdText.family, fontSize: 13, color: SdColors.muted)),
          const SizedBox(height: 22),
          _toolCard(
            title: 'فحص جودة الإنترنت',
            subtitle:
                'فحص دقيق: السرعة، زمن الاستجابة، إشارة الفايبر الضوئية، WiFi، الجهاز',
            icon: Icons.network_check_rounded,
            gradient: const [Color(0xFF26A69A), Nq3d.teal],
            iconEdge: Nq3d.tealDark,
            cardEdge: SdColors.accentTint,
            glow: const Color(0x7300838F),
            badge: 'جديد',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const QualityScanPage()),
            ),
          ),
          SizedBox(height: isMobile ? 12 : 32),
        ],
      ),
    );
  }

  Widget _toolCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required Color iconEdge,
    required Color cardEdge,
    required Color glow,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Raised3D(
      onTap: onTap,
      tilt: true,
      edgeColor: cardEdge,
      glowColor: glow,
      radius: 20,
      semanticLabel: title,
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: gradient,
              ),
              boxShadow: [
                BoxShadow(color: iconEdge, offset: const Offset(0, 6)),
                BoxShadow(
                    color: iconEdge.withValues(alpha: .5),
                    offset: const Offset(0, 14),
                    blurRadius: 18,
                    spreadRadius: -6),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              color: Nq3d.ink)),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 1),
                        decoration: BoxDecoration(
                          color: gradient.last,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                                color: iconEdge, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Text(badge,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12.5, color: Nq3d.muted, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_left_rounded, color: Nq3d.faint),
        ],
      ),
    );
  }
}
