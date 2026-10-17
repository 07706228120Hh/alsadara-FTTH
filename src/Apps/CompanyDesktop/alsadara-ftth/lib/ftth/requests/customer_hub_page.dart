/// صفحة مركز المشترك الجديد — Hub
/// تجمع: إضافة طلب مشترك + إعداد مشترك بعد الموافقة
library;

import 'package:flutter/material.dart';
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../tasks/customer_search_connect_page.dart';
import 'customer_onboarding_page.dart';

class CustomerHubPage extends StatelessWidget {
  final String authToken;
  const CustomerHubPage({super.key, required this.authToken});

  @override
  Widget build(BuildContext context) {
    return SdPage(
      maxWidth: SdSpace.formMax,
      appBar: const SdAppBar(title: 'مشترك جديد'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── إضافة طلب مشترك ───
          SdMenuTile(
            title: 'إضافة طلب مشترك',
            subtitle: 'تقديم طلب تسجيل مشترك جديد',
            icon: Icons.note_add_rounded,
            group: SdGroup.field,
            layout: SdTileLayout.horizontal,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => CustomerOnboardingPage(authToken: authToken)),
            ),
          ),
          const SizedBox(height: SdSpace.sm),
          // ─── إعداد مشترك ───
          SdMenuTile(
            title: 'إعداد مشترك',
            subtitle: 'إعداد وتوصيل مشترك تمت الموافقة عليه',
            icon: Icons.build_circle_rounded,
            group: SdGroup.field,
            layout: SdTileLayout.horizontal,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CustomerSearchConnectPage()),
            ),
          ),
        ],
      ),
    );
  }
}
