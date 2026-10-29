import 'package:flutter/material.dart';
import 'package:sadara_design/sadara_design.dart';

/// ثيم منصة الصدارة (تطبيق المواطن/الوكيل).
///
/// ⚠️ موحّد مع نظام تصميم الصدارة المركزي (package:sadara_design).
/// هذا الملف أصبح «جسراً»: يحافظ على أسماء الأعضاء القديمة التي تستعملها الشاشات،
/// لكن قيمها كلها مشتقّة من رموز النظام الموحّد (SdColors / SdText / SdTheme).
/// أي تعديل على الهوية يتم في الحزمة المشتركة فينعكس على التطبيقين — بلا مزامنة يدوية.
class AppTheme {
  // ── الألوان الأساسية (من SdColors) ──
  static const Color primaryColor = SdColors.primary;      // كحلي ملكي
  static const Color primaryLight = SdColors.primaryLight;
  static const Color primaryDark = SdColors.primaryEdge;
  static const Color successColor = SdColors.success;
  static const Color accentColor = SdColors.accent;        // تركوازي (كان برتقالياً)
  static const Color errorColor = SdColors.danger;
  static const Color backgroundColor = SdColors.ground;
  static const Color white = Colors.white;
  static const Color textDark = SdColors.ink;
  static const Color textGrey = SdColors.muted;
  static const Color cardColor = SdColors.surface;
  static const Color borderColor = SdColors.outline;

  // ── ألوان الخدمات (من مجموعات/نبرات النظام الموحّد) ──
  static const Color internetColor = SdColors.accent;       // الفايبر = تركوازي
  static const Color masterCardColor = SdColors.platformBase; // بنفسجي المنصّات
  static const Color storeColor = SdColors.success;         // أخضر
  static const Color agentColor = SdColors.info;            // أزرق إداري
  static const Color infoColor = SdColors.info;
  static const Color warningColor = SdColors.warning;

  // ── التدرّجات ──
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [SdColors.primary, SdColors.primaryLight],
  );
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [SdColors.primaryEdge, SdColors.primary],
  );
  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF43A047), SdColors.success],
  );
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [SdColors.accentLight, SdColors.accent],
  );

  // ── الظلال (كوبالت ناعم موحّد) ──
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0x260B1B3F),
          blurRadius: 26,
          spreadRadius: -8,
          offset: const Offset(0, 13),
        ),
        const BoxShadow(
          color: Color(0x0D0B1B3F),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ];
  static List<BoxShadow> get buttonShadow => [
        BoxShadow(
          color: SdColors.primary.withValues(alpha: 0.3),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];

  // ── الأبعاد ──
  static const double borderRadius = SdRadius.md;
  static const double borderRadiusLarge = SdRadius.lg;
  static const double borderRadiusSmall = SdRadius.sm;
  static const double paddingSmall = SdSpace.xs;
  static const double paddingMedium = SdSpace.md;
  static const double paddingLarge = SdSpace.lg;
  static const double paddingXLarge = SdSpace.xxl;

  // ── أنماط النصوص (من SdText الموحّد) ──
  static const TextStyle headingLarge = SdText.display;
  static const TextStyle headingMedium = SdText.title;
  static const TextStyle headingSmall = SdText.titleSm;
  static const TextStyle bodyLarge = SdText.body;
  static const TextStyle bodyMedium = SdText.bodySm;
  static const TextStyle buttonText = SdText.label;

  // ── الثيمات: كلها من النظام الموحّد ──
  static ThemeData get lightTheme => SdTheme.light();
  // الوضع الليلي الموحّد مرحلة لاحقة؛ حالياً يتبع الثيم الموحّد الفاتح للاتساق.
  static ThemeData get darkTheme => SdTheme.light();
  static ThemeData get agentTheme => SdTheme.light();
}

/// أيقونات المنصة (كما هي — مستقلة عن الألوان).
class AppIcons {
  static const IconData internet = Icons.wifi;
  static const IconData masterCard = Icons.credit_card;
  static const IconData store = Icons.store;
  static const IconData agent = Icons.storefront;
  static const IconData citizen = Icons.person;
  static const IconData support = Icons.support_agent;
  static const IconData payment = Icons.payment;
  static const IconData location = Icons.location_on;
  static const IconData phone = Icons.phone;
  static const IconData email = Icons.email;
  static const IconData settings = Icons.settings;
  static const IconData logout = Icons.logout;
  static const IconData notifications = Icons.notifications;
  static const IconData search = Icons.search;
  static const IconData menu = Icons.menu;
  static const IconData back = Icons.arrow_back;
  static const IconData forward = Icons.arrow_forward;
  static const IconData check = Icons.check_circle;
  static const IconData close = Icons.close;
  static const IconData edit = Icons.edit;
  static const IconData delete = Icons.delete;
  static const IconData add = Icons.add;
  static const IconData refresh = Icons.refresh;
  static const IconData download = Icons.download;
  static const IconData upload = Icons.upload;
  static const IconData share = Icons.share;
  static const IconData copy = Icons.copy;
  static const IconData visibility = Icons.visibility;
  static const IconData visibilityOff = Icons.visibility_off;
}
