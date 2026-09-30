import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

/// نظام تصميم موحّد لوحدة «وكيل الساس» بثيم منصّة الصدارة.
///
/// ملف ودجات عرض فقط (حالات/بطاقات/رؤوس) — لا منطق أعمال ولا استدعاءات API.
/// يعتمد ألوان [AppTheme] وخط Cairo وحواف مستديرة وظلال ناعمة كما في بقية
/// شاشات المنصّة الفخمة (الرئيسية/الدخول/المخازن/المحاسبة).

/// أدوات تنسيق مشتركة للوحدة (ثوابت بصرية + مولّدات ديكور).
class SasUi {
  SasUi._();

  /// خلفية الوحدة (رمادي فاتح مريح كبقية الشاشات).
  static const Color pageBg = Color(0xFFF4F6FB);

  static const double radius = 16;
  static const double radiusSm = 12;
  static const double radiusPill = 40;

  /// ظل بطاقة ناعم (طبقتان) — نفس نبرة `_buildEnhancedMenuItem` في الرئيسية.
  static List<BoxShadow> cardShadow([Color? tint]) {
    final base = tint ?? AppTheme.primaryColor;
    return [
      BoxShadow(
        color: base.withValues(alpha: 0.07),
        blurRadius: 14,
        spreadRadius: -3,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.03),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  /// ديكور بطاقة بيضاء أنيقة (حدّ خفيف + ظل ناعم).
  static BoxDecoration card({
    Color? borderColor,
    double borderWidth = 1.2,
    List<BoxShadow>? shadow,
    double? radius,
  }) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular((radius ?? SasUi.radius).r),
      border: Border.all(
        color: borderColor ?? Colors.grey.withValues(alpha: 0.16),
        width: borderWidth,
      ),
      boxShadow: shadow ?? cardShadow(),
    );
  }

  /// أيقونة دائرية بتدرّج (شارة أنيقة للبطاقات/الرؤوس).
  static Widget gradientBadge({
    required IconData icon,
    required List<Color> colors,
    double size = 44,
    double iconSize = 22,
  }) {
    return Container(
      width: size.w,
      height: size.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.35),
            blurRadius: 10,
            spreadRadius: -2,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: iconSize.sp),
    );
  }
}

/// رأس قسم أنيق (شارة أيقونة متدرّجة + عنوان + عدّاد/زر اختياري).
class SasSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Color> gradient;
  final String? trailingText;
  final Widget? action;

  const SasSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.gradient = AppTheme.blueGradient,
    this.trailingText,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SasUi.gradientBadge(
          icon: icon,
          colors: gradient,
          size: 34,
          iconSize: 17,
        ),
        SizedBox(width: 10.w),
        Text(
          title,
          style: GoogleFonts.cairo(
            fontSize: 15.sp,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        if (trailingText != null) ...[
          SizedBox(width: 8.w),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
            decoration: BoxDecoration(
              color: gradient.first.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Text(
              trailingText!,
              style: GoogleFonts.cairo(
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
                color: gradient.first,
              ),
            ),
          ),
        ],
        const Spacer(),
        if (action != null) action!,
      ],
    );
  }
}

/// شارة حالة صغيرة (نص + لون دلالي) — pill.
class SasStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const SasStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SasUi.radiusPill.r),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12.sp, color: color),
            SizedBox(width: 4.w),
          ],
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 10.5.sp,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// حالة تحميل موحّدة لوحدة وكيل الساس.
///
/// ملفوفة بتمرير آمن (`_ScrollSafeCenter`) بمقاسات ثابتة معقولة — لا تعتمد على
/// `.w/.h/.sp` المتضخّمة على سطح المكتب، فلا يحدث تجاوز عمودي مهما ضاق ارتفاع
/// النافذة/حاوية التبويب.
class SasLoadingView extends StatelessWidget {
  final String? message;
  const SasLoadingView({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return _ScrollSafeCenter(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 3.2,
              valueColor:
                  const AlwaysStoppedAnimation(AppTheme.primaryColor),
              backgroundColor:
                  AppTheme.primaryColor.withValues(alpha: 0.10),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// حالة خطأ موحّدة مع زر إعادة المحاولة.
class SasErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const SasErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _ScrollSafeCenter(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppTheme.errorColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline_rounded,
                size: 42, color: AppTheme.errorColor),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: Text('إعادة المحاولة',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}

/// حالة فراغ موحّدة.
class SasEmptyView extends StatelessWidget {
  final String message;
  final IconData icon;
  final Widget? action;
  const SasEmptyView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_rounded,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return _ScrollSafeCenter(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 46,
                color: AppTheme.primaryColor.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}

/// يوسّط محتوى الحالة عمودياً وأفقياً مع تمرير آمن يمنع أي تجاوز عمودي
/// (`BOTTOM OVERFLOWED`) عندما يقلّ ارتفاع الحاوية عن ارتفاع المحتوى.
///
/// يستخدم `LayoutBuilder + ConstrainedBox(minHeight)` مع `IntrinsicHeight`
/// ليبقى المحتوى موسّطاً عند وفرة الارتفاع، ويتحوّل لتمرير عند شحّه.
class _ScrollSafeCenter extends StatelessWidget {
  final Widget child;
  const _ScrollSafeCenter({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight.isFinite
                  ? constraints.maxHeight - 48 // خصم الحشوة العلوية/السفلية
                  : 0,
            ),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

/// بطاقة إحصائية (رقم كبير + عنوان + أيقونة) بثيم الصدارة — تدرّج خفيف وظل ناعم.
class SasStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const SasStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.10),
            color.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.3),
        boxShadow: SasUi.cardShadow(color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42.w,
            height: 42.w,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.30),
                  blurRadius: 8,
                  spreadRadius: -1,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 21.sp),
          ),
          SizedBox(width: 12.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: GoogleFonts.cairo(
                  fontSize: 19.sp,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 1.h),
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 11.sp,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
