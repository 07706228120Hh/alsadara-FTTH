/// صفحة مركز المشترك الجديد — Hub
/// تجمع: إضافة طلب مشترك + إعداد مشترك بعد الموافقة
library;

import 'package:flutter/material.dart';
import '../tasks/customer_search_connect_page.dart';
import 'customer_onboarding_page.dart';

class CustomerHubPage extends StatelessWidget {
  final String authToken;
  const CustomerHubPage({super.key, required this.authToken});

  static const _primary = Color(0xFF1A237E);
  static const _accent1 = Color(0xFF667eea);
  static const _accent2 = Color(0xFF00897B);

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isSmall = w < 400;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: Text('مشترك جديد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: isSmall ? 16 : 20)),
          centerTitle: true,
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isSmall ? 16 : 24, vertical: 24),
            child: Column(
              children: [
                // ─── زر إضافة طلب ───
                _actionButton(
                  context: context,
                  icon: Icons.note_add_rounded,
                  title: 'إضافة طلب مشترك',
                  subtitle: 'تقديم طلب تسجيل مشترك جديد',
                  color: _accent1,
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => CustomerOnboardingPage(authToken: authToken))),
                ),
                const SizedBox(height: 14),
                // ─── زر إعداد مشترك ───
                _actionButton(
                  context: context,
                  icon: Icons.build_circle_rounded,
                  title: 'إعداد مشترك',
                  subtitle: 'إعداد وتوصيل مشترك تمت الموافقة عليه',
                  color: _accent2,
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CustomerSearchConnectPage())),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isSmall = MediaQuery.of(context).size.width < 400;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(isSmall ? 12 : 14),
      elevation: 1,
      shadowColor: color.withValues(alpha: 0.2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(isSmall ? 12 : 14),
        splashColor: color.withValues(alpha: 0.1),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: isSmall ? 14 : 18, vertical: isSmall ? 14 : 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isSmall ? 12 : 14),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Row(
            children: [
              // أيقونة
              Container(
                width: isSmall ? 40 : 50, height: isSmall ? 40 : 50,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(isSmall ? 10 : 12),
                ),
                child: Icon(icon, size: isSmall ? 22 : 26, color: color),
              ),
              SizedBox(width: isSmall ? 10 : 14),
              // نص
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: isSmall ? 14 : 16, fontWeight: FontWeight.bold, color: const Color(0xFF2C3E50))),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: isSmall ? 11 : 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              // سهم
              Icon(Icons.arrow_back_ios_new, size: isSmall ? 14 : 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
