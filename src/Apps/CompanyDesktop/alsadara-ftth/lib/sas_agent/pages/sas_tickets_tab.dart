import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ftth/tickets/tickets_login_page.dart';
import '../../theme/app_theme.dart';
import '../widgets/sas_state_views.dart';

/// تبويب «تذاكر» — يعيد استخدام نظام الدعم/التذاكر القائم في التطبيق.
///
/// لا نبني نظام تذاكر جديداً؛ بدلاً من ذلك نفتح تدفّق الدعم القائم
/// ([TicketsLoginPage] → [TKTATsPage]) الذي:
///  - يسجّل دخول المستخدم الميداني للشركة الحالية تلقائياً (عزل جلسات محفوظ).
///  - يعرض تذاكر المستخدم الحالي مع البحث والتفاصيل (قراءة/إدارة حسب النظام).
///
/// يُقدَّم هنا كمدخل ضمن التبويب (بطاقة + زر فتح) بثيم الصدارة؛ بذلك لا نعدّل
/// شاشات الدعم القائمة ونحترم عزل جلساتها ومصادقتها المستقلّة.
class SasTicketsTab extends StatelessWidget {
  const SasTicketsTab({super.key});

  void _openTickets(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TicketsLoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // مقاسات ثابتة + تمرير آمن يوسّط البطاقة عند وفرة الارتفاع ويسمح بالتمرير
    // عند شحّه — فلا تجاوز عمودي على النوافذ القصيرة. لا نعتمد على `.w/.h/.sp`.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: SasUi.card(radius: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SasUi.gradientBadge(
                icon: Icons.confirmation_number_rounded,
                colors: AppTheme.blueGradient,
                size: 84,
                iconSize: 40,
              ),
              const SizedBox(height: 18),
              Text(
                'تذاكر الدعم',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'تُدار التذاكر عبر نظام الدعم القائم في التطبيق.\n'
                'اضغط للانتقال إلى تذاكرك (دخول تلقائي بحساب المستخدم الميداني).',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                    fontSize: 13, color: Colors.grey[600], height: 1.6),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openTickets(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text('فتح نظام التذاكر',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
