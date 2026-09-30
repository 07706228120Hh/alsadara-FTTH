import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

/// تبويب هيكلي «قيد الإنشاء» للتبويبات المؤجّلة (تجديد/بلنك/تذاكر).
/// يُوصَل بالبوّابة لاحقاً — الآن يعرض حالة واضحة للمستخدم.
class SasPlaceholderTab extends StatelessWidget {
  final String title;
  final IconData icon;
  final String note;

  const SasPlaceholderTab({
    super.key,
    required this.title,
    required this.icon,
    this.note = 'هذه الميزة قيد الإنشاء وسيتم ربطها قريباً.',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64.sp, color: Colors.grey[400]),
            SizedBox(height: 14.h),
            Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: 18.sp,
                fontWeight: FontWeight.w800,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              note,
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 13.sp,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
