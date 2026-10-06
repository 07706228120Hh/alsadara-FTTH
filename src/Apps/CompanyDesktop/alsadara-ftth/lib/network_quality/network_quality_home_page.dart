/// الواجهة الرئيسية لقسم «أدوات الراوتر والشبكة» (أوفلاين) — Network Quality
///
/// تظهر عند الضغط على زر «إعداد الراوتر (أوفلاين)» في شاشة الدخول، وتقدّم
/// خيارين:
///   1) إعداد الراوتر   → الأداة الحالية (OfflineRouterSetupPage) بلا تغيير.
///   2) فحص جودة الإنترنت → نظام الفحص الجديد (هذه الوحدة).
library;

import 'package:flutter/material.dart';

import '../pages/offline_router_setup_page.dart';
import 'pages/quality_scan_page.dart';

class NetworkToolsHomePage extends StatelessWidget {
  const NetworkToolsHomePage({super.key});

  static const _indigo = Color(0xFF1A237E);

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F4F8),
        appBar: AppBar(
          title: const Text('أدوات الراوتر والشبكة',
              style: TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: _indigo,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _indigo.withValues(alpha: 0.08),
                    ),
                    child: const Icon(Icons.router_rounded,
                        size: 48, color: _indigo),
                  ),
                  const SizedBox(height: 14),
                  const Text('اختر الأداة',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 20)),
                  const SizedBox(height: 4),
                  Text('أدوات تعمل بدون إنترنت — اتصال محلي بالراوتر',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600)),
                  const SizedBox(height: 24),
                  _toolCard(
                    context,
                    title: 'إعداد الراوتر',
                    subtitle:
                        'كشف الراوتر وضبط PPPoE وWiFi وTR-069 تلقائياً أو يدوياً',
                    icon: Icons.settings_input_antenna_rounded,
                    color: _indigo,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const OfflineRouterSetupPage()),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _toolCard(
                    context,
                    title: 'فحص جودة الإنترنت',
                    subtitle:
                        'فحص دقيق: السرعة، زمن الاستجابة، إشارة الفايبر الضوئية، WiFi، الجهاز',
                    icon: Icons.network_check_rounded,
                    color: const Color(0xFF00838F),
                    badge: 'جديد',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const QualityScanPage()),
                    ),
                  ),
                  SizedBox(height: isMobile ? 20 : 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 17)),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(badge,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade600,
                            height: 1.4)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
