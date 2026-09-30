import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ftth/tickets/tickets_login_page.dart';
import '../../theme/app_theme.dart';

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
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84.w,
              height: 84.w,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.confirmation_number_rounded,
                  size: 40.sp, color: AppTheme.primaryColor),
            ),
            SizedBox(height: 16.h),
            Text(
              'تذاكر الدعم',
              style: GoogleFonts.cairo(
                fontSize: 18.sp,
                fontWeight: FontWeight.w800,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'تُدار التذاكر عبر نظام الدعم القائم في التطبيق.\n'
              'اضغط للانتقال إلى تذاكرك (دخول تلقائي بحساب المستخدم الميداني).',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(fontSize: 13.sp, color: Colors.grey[600]),
            ),
            SizedBox(height: 20.h),
            FilledButton.icon(
              onPressed: () => _openTickets(context),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text('فتح نظام التذاكر',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
