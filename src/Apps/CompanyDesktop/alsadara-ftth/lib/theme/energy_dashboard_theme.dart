/// 🎨 Energy Management Dashboard Theme
/// مستوحى من تصاميم Energy/Solar Dashboard الحديثة
/// خلفية داكنة + ألوان نيون متوهجة + Glassmorphism
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ثيم Energy Dashboard - تصميم عصري مع تأثيرات Neon
class EnergyDashboardTheme {
  EnergyDashboardTheme._();

  // ═══════════════════════════════════════════════════════════════
  // 🎨 الألوان الرئيسية - Modern Bright Dashboard
  // ═══════════════════════════════════════════════════════════════

  // الخلفيات (كحلي داكن - Navy Dark)
  static const Color bgPrimary = Color(0xFF1E3A5F); // كحلي رئيسي
  static const Color bgSecondary = Color(0xFF162D4D); // كحلي أغمق
  static const Color bgCard =
      Color(0xFF2A4A72); // كحلي أفتح للبطاقات - تباين أعلى
  static const Color bgCardHover = Color(0xFF345A88); // كحلي hover
  static const Color bgSidebar = Color(0xFF0F1D33); // الشريط الجانبي أغمق

  // ألوان حيوية مبهجة
  static const Color neonGreen = Color(0xFF10B981); // أخضر زمردي
  static const Color neonBlue = Color(0xFF3B82F6); // أزرق حيوي
  static const Color neonPurple = Color(0xFF8B5CF6); // بنفسجي مشرق
  static const Color neonOrange = Color(0xFFF59E0B); // برتقالي ذهبي
  static const Color neonPink = Color(0xFFEC4899); // وردي جميل
  static const Color neonYellow = Color(0xFFFBBF24); // أصفر مشمس

  // ألوان الحالة (حيوية ومبهجة)
  static const Color success = Color(0xFF10B981); // أخضر زمردي
  static const Color warning = Color(0xFFF59E0B); // برتقالي ذهبي
  static const Color danger = Color(0xFFEF4444); // أحمر حيوي
  static const Color info = Color(0xFF3B82F6); // أزرق سماوي

  // ألوان النصوص (فاتحة - للخلفية الداكنة)
  static const Color textPrimary = Color(0xFFF1F5F9); // أبيض رمادي
  static const Color textSecondary = Color(0xFFCBD5E1); // رمادي فاتح
  static const Color textMuted = Color(0xFF94A3B8); // رمادي متوسط
  static const Color textAccent = Color(0xFF10B981); // أخضر زمردي

  // ألوان النصوص (فاتحة - للشريط الجانبي)
  static const Color textOnDark = Color(0xFFFFFFFF); // أبيض
  static const Color textOnDarkSecondary = Color(0xFFCBD5E1); // رمادي فاتح
  static const Color textOnDarkMuted = Color(0xFF94A3B8); // رمادي
  static const Color textOnDarkAccent = Color(0xFF10B981); // أخضر زمردي

  // ألوان الحدود
  static const Color borderColor = Color(0xFF4A7AAF); // أزرق حدود أوضح
  static const Color borderGlow = Color(0xFF10B981);

  // ═══════════════════════════════════════════════════════════════
  // � ألوان مالية / محاسبية - Financial / Accounting Colors
  // ═══════════════════════════════════════════════════════════════

  /// خلفية حقل المدين (أخضر داكن)
  static const Color debitFill = Color(0xFF0D3320);

  /// خلفية حقل الدائن (أحمر داكن)
  static const Color creditFill = Color(0xFF3D1515);

  /// لون نص المدين
  static const Color debitText = Color(0xFF059669);

  /// لون نص الدائن
  static const Color creditText = Color(0xFFDC2626);

  /// ألوان الحالة المالية (رواتب / عمليات)
  static const Map<String, Color> salaryStatusColors = {
    'Pending': Color(0xFFF59E0B),
    'Paid': Color(0xFF10B981),
    'PartiallyPaid': Color(0xFF3B82F6),
    'Cancelled': Color(0xFFEF4444),
  };

  /// الحصول على لون الحالة
  static Color statusColor(String status) =>
      salaryStatusColors[status] ?? textMuted;

  // الجداول
  static const Color tableHeaderBg = Color(0xFF152A45);
  static const Color tableHeaderText = Color(0xFFFFFFFF);
  static const Color tableRowAlt = Color(0x15FFFFFF);

  /// رأس الجدول
  static BoxDecoration get tableHeader => BoxDecoration(
        color: tableHeaderBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      );

  /// حقل إدخال المدين (أخضر)
  static InputDecoration get debitInput => InputDecoration(
        hintText: '0',
        hintStyle: TextStyle(color: textMuted.withOpacity(0.5)),
        filled: true,
        fillColor: debitFill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: neonGreen.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: const BorderSide(color: neonGreen, width: 2),
        ),
      );

  /// حقل إدخال الدائن (أحمر)
  static InputDecoration get creditInput => InputDecoration(
        hintText: '0',
        hintStyle: TextStyle(color: textMuted.withOpacity(0.5)),
        filled: true,
        fillColor: creditFill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: danger.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: const BorderSide(color: danger, width: 2),
        ),
      );

  /// شريط الأدوات
  static BoxDecoration get toolbar => BoxDecoration(
        color: bgCard,
        border: Border(bottom: BorderSide(color: borderColor)),
      );

  /// حاوية ملخص (نتائج أسفل الصفحة)
  static BoxDecoration get summaryBar => BoxDecoration(
        color: bgCard,
        border: Border(
          top: BorderSide(color: neonGreen.withOpacity(0.2)),
        ),
      );

  /// عرض خطأ
  static Widget errorView(String message, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: danger, size: 64),
          const SizedBox(height: 16),
          Text(
            message,
            style: GoogleFonts.cairo(color: textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text('إعادة المحاولة', style: GoogleFonts.cairo()),
            style: primaryButton,
          ),
        ],
      ),
    );
  }

  /// حالة فارغة
  static Widget emptyState(String message, {IconData icon = Icons.inbox}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: textMuted, size: 64),
          const SizedBox(height: 16),
          Text(message, style: GoogleFonts.cairo(color: textMuted)),
        ],
      ),
    );
  }

  /// SnackBar مساعد
  static void showSnack(BuildContext context, String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.cairo()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium)),
      ),
    );
  }

  /// حوار تأكيد
  static Future<bool?> confirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'تأكيد',
    String cancelLabel = 'إلغاء',
    Color? confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge)),
        title: Text(title, style: GoogleFonts.cairo(color: textPrimary)),
        content: Text(message, style: GoogleFonts.cairo(color: textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text(cancelLabel, style: GoogleFonts.cairo(color: textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor ?? neonGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radiusMedium)),
            ),
            child: Text(confirmLabel, style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // �🔗 أسماء بديلة للتوافق - Compatibility Aliases
  // ═══════════════════════════════════════════════════════════════

  /// الألوان الرئيسية (أسماء بديلة)
  static const Color primaryColor = neonBlue;
  static const Color accentColor = neonGreen;
  static const Color backgroundColor = bgPrimary;
  static const Color surfaceColor = bgCard;
  static const Color warningColor = warning;
  static const Color dangerColor = danger;
  static const Color infoColor = info;
  static const Color successColor = success;

  /// أسماء PremiumAdmin البديلة
  static const Color primary = neonBlue;
  static const Color accent = neonGreen;
  static const Color bgLight = bgPrimary;
  static const Color bgLightCard = bgCard;
  static const Color bgLightSurface = bgSecondary;
  static const Color bgDark = bgSidebar;
  static const Color textDark = textPrimary;
  static const Color textMedium = textSecondary;
  static const Color textLight = textMuted;

  // ═══════════════════════════════════════════════════════════════
  // 📐 أحجام النصوص الموحدة - Unified Font Sizes
  // ═══════════════════════════════════════════════════════════════

  /// حجم العنوان الرئيسي (H1)
  static const double fontSizeH1 = 28.0;

  /// حجم العنوان الثانوي (H2)
  static const double fontSizeH2 = 24.0;

  /// حجم العنوان الفرعي (H3)
  static const double fontSizeH3 = 20.0;

  /// حجم العنوان الصغير (H4)
  static const double fontSizeH4 = 18.0;

  /// حجم النص العادي
  static const double fontSizeBody = 14.0;

  /// حجم النص الصغير
  static const double fontSizeSmall = 12.0;

  /// حجم التسمية التوضيحية
  static const double fontSizeCaption = 10.0;

  /// حجم الأرقام الكبيرة (للإحصائيات)
  static const double fontSizeStatValue = 32.0;

  /// حجم الأرقام المتوسطة
  static const double fontSizeStatMedium = 24.0;

  // ═══════════════════════════════════════════════════════════════
  // 📏 الأبعاد الموحدة - Unified Dimensions
  // ═══════════════════════════════════════════════════════════════

  /// أنصاف الأقطار
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 20.0;
  static const double radiusRound = 50.0;

  /// المسافات الداخلية
  static const double paddingXSmall = 4.0;
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 12.0;
  static const double paddingLarge = 16.0;
  static const double paddingXLarge = 20.0;
  static const double paddingXXLarge = 24.0;

  /// المسافات بين العناصر
  static const double spacingXSmall = 4.0;
  static const double spacingSmall = 8.0;
  static const double spacingMedium = 12.0;
  static const double spacingLarge = 16.0;
  static const double spacingXLarge = 20.0;
  static const double spacingXXLarge = 24.0;

  /// أحجام الأيقونات
  static const double iconSizeSmall = 16.0;
  static const double iconSizeMedium = 20.0;
  static const double iconSizeLarge = 24.0;
  static const double iconSizeXLarge = 28.0;

  // ═══════════════════════════════════════════════════════════════
  // 📱 التجاوب مع الشاشات - Responsive Helpers
  // ═══════════════════════════════════════════════════════════════

  /// نقاط الكسر للشاشات
  static const double breakpointMobile = 600.0;
  static const double breakpointTablet = 900.0;
  static const double breakpointDesktop = 1200.0;
  static const double breakpointLarge = 1536.0;

  /// التحقق من نوع الشاشة
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < breakpointMobile;

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= breakpointMobile && width < breakpointDesktop;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= breakpointDesktop;

  /// الحصول على padding تجاوبي
  static double getResponsivePadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < breakpointMobile) return paddingMedium;
    if (width < breakpointTablet) return paddingLarge;
    if (width < breakpointDesktop) return paddingXLarge;
    return paddingXXLarge;
  }

  /// الحصول على عرض القائمة الجانبية تجاوبي
  static double getResponsiveSidebarWidth(BuildContext context,
      {bool collapsed = false}) {
    if (collapsed) return 70.0;
    final width = MediaQuery.of(context).size.width;
    if (width < breakpointTablet) return 200.0;
    if (width < breakpointDesktop) return 240.0;
    return 280.0;
  }

  /// الحصول على عدد الأعمدة للـ Grid
  static int getResponsiveColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < breakpointMobile) return 1;
    if (width < breakpointTablet) return 2;
    if (width < breakpointDesktop) return 3;
    return 4;
  }

  /// الحصول على حجم النص التجاوبي
  static double getResponsiveFontSize(BuildContext context, double baseSize) {
    final width = MediaQuery.of(context).size.width;
    if (width < breakpointMobile) return baseSize * 0.85;
    if (width < breakpointTablet) return baseSize * 0.92;
    return baseSize;
  }

  // ═══════════════════════════════════════════════════════════════
  // 🌈 التدرجات - Modern Gradients
  // ═══════════════════════════════════════════════════════════════

  // تدرج الخلفية الرئيسي (كحلي داكن)
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1E3A5F),
      Color(0xFF162D4D),
      Color(0xFF1E3A5F),
    ],
  );

  // تدرج أخضر زمردي (للأزرار الرئيسية)
  static const LinearGradient neonGreenGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10B981), Color(0xFF059669)],
  );

  // تدرج أزرق حيوي
  static const LinearGradient neonBlueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
  );

  /// اسم بديل للتوافق
  static const LinearGradient primaryGradient = neonBlueGradient;
  static const LinearGradient accentGradient = neonGreenGradient;

  // تدرج نيون بنفسجي
  static const LinearGradient neonPurpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
  );

  // تدرج نيون برتقالي
  static const LinearGradient neonOrangeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
  );

  // تدرج نيون وردي
  static const LinearGradient neonPinkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEC4899), Color(0xFFBE185D)],
  );

  // تدرج البطاقات الزجاجية
  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x15FFFFFF),
      Color(0x05FFFFFF),
    ],
  );

  // تدرج الشريط الجانبي
  static const LinearGradient sidebarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0F1629), Color(0xFF080C15)],
  );

  // تدرج بطاقة الطاقة (كحلي)
  static const LinearGradient energyCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF2A4A72),
      Color(0xFF1E3A5F),
    ],
  );

  // ═══════════════════════════════════════════════════════════════
  // ✨ تأثيرات التوهج - Glow Effects
  // ═══════════════════════════════════════════════════════════════

  /// توهج نيون أخضر
  static List<BoxShadow> get glowGreen => [
        BoxShadow(
          color: neonGreen.withOpacity(0.5),
          blurRadius: 20,
          spreadRadius: 0,
        ),
        BoxShadow(
          color: neonGreen.withOpacity(0.3),
          blurRadius: 40,
          spreadRadius: 0,
        ),
      ];

  /// توهج نيون أزرق
  static List<BoxShadow> get glowBlue => [
        BoxShadow(
          color: neonBlue.withOpacity(0.5),
          blurRadius: 20,
          spreadRadius: 0,
        ),
        BoxShadow(
          color: neonBlue.withOpacity(0.3),
          blurRadius: 40,
          spreadRadius: 0,
        ),
      ];

  /// توهج نيون بنفسجي
  static List<BoxShadow> get glowPurple => [
        BoxShadow(
          color: neonPurple.withOpacity(0.5),
          blurRadius: 20,
          spreadRadius: 0,
        ),
        BoxShadow(
          color: neonPurple.withOpacity(0.3),
          blurRadius: 40,
          spreadRadius: 0,
        ),
      ];

  /// توهج مخصص
  static List<BoxShadow> glowCustom(Color color, {double intensity = 0.5}) => [
        BoxShadow(
          color: color.withOpacity(intensity),
          blurRadius: 20,
          spreadRadius: 0,
        ),
        BoxShadow(
          color: color.withOpacity(intensity * 0.6),
          blurRadius: 40,
          spreadRadius: 0,
        ),
      ];

  /// ظل البطاقة الناعم (معزز للخلفية الداكنة)
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.25),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.15),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  /// ظل البطاقة العادي
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.15),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  /// ظل مرتفع (للعناصر البارزة)
  static List<BoxShadow> get elevatedShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.35),
          blurRadius: 30,
          offset: const Offset(0, 15),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ];

  // ═══════════════════════════════════════════════════════════════
  // 📦 تزيينات البطاقات - Card Decorations
  // ═══════════════════════════════════════════════════════════════

  /// بطاقة زجاجية
  static BoxDecoration get glassCard => BoxDecoration(
        gradient: glassGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: softShadow,
      );

  /// بطاقة مع توهج نيون
  static BoxDecoration glowingCard(Color glowColor) => BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: glowColor.withOpacity(0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      );

  /// بطاقة إحصائيات الطاقة
  static BoxDecoration energyStatCard(Color accentColor) => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bgCard,
            accentColor.withOpacity(0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: accentColor.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      );

  /// بطاقة الشريط الجانبي النشطة
  static BoxDecoration sidebarActiveItem(Color color) => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            color.withOpacity(0.2),
            color.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          right: BorderSide(
            color: color,
            width: 3,
          ),
        ),
      );

  // ═══════════════════════════════════════════════════════════════
  // 🔘 أنماط الأزرار - Button Styles
  // ═══════════════════════════════════════════════════════════════

  /// زر نيون أخضر رئيسي
  static ButtonStyle get primaryButton => ElevatedButton.styleFrom(
        backgroundColor: neonGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.cairo(
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      );

  /// زر نيون أزرق
  static ButtonStyle get secondaryButton => ElevatedButton.styleFrom(
        backgroundColor: neonBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  /// زر شفاف مع حدود نيون
  static ButtonStyle outlinedButton(Color color) => OutlinedButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: color, width: 1.5),
      );

  /// زر خطر
  static ButtonStyle get dangerButton => ElevatedButton.styleFrom(
        backgroundColor: danger,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  // ═══════════════════════════════════════════════════════════════
  // 📝 أنماط النصوص الموحدة - Unified Text Styles
  // ═══════════════════════════════════════════════════════════════

  /// نص العنوان الرئيسي (H1) - للعناوين الكبيرة
  static TextStyle get headingH1 => GoogleFonts.cairo(
        fontSize: fontSizeH1,
        fontWeight: FontWeight.bold,
        color: textPrimary,
        height: 1.3,
      );

  /// نص العنوان الثانوي (H2) - لعناوين الأقسام
  static TextStyle get headingH2 => GoogleFonts.cairo(
        fontSize: fontSizeH2,
        fontWeight: FontWeight.bold,
        color: textPrimary,
        height: 1.3,
      );

  /// نص العنوان الفرعي (H3) - للعناوين الفرعية
  static TextStyle get headingH3 => GoogleFonts.cairo(
        fontSize: fontSizeH3,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        height: 1.4,
      );

  /// نص العنوان الصغير (H4)
  static TextStyle get headingH4 => GoogleFonts.cairo(
        fontSize: fontSizeH4,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        height: 1.4,
      );

  /// نص الجسم العادي
  static TextStyle get bodyText => GoogleFonts.cairo(
        fontSize: fontSizeBody,
        fontWeight: FontWeight.normal,
        color: textSecondary,
        height: 1.5,
      );

  /// نص الجسم الغامق
  static TextStyle get bodyTextBold => GoogleFonts.cairo(
        fontSize: fontSizeBody,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        height: 1.5,
      );

  /// نص صغير
  static TextStyle get smallText => GoogleFonts.cairo(
        fontSize: fontSizeSmall,
        fontWeight: FontWeight.normal,
        color: textSecondary,
        height: 1.4,
      );

  /// نص التسمية التوضيحية
  static TextStyle get captionText => GoogleFonts.cairo(
        fontSize: fontSizeCaption,
        fontWeight: FontWeight.normal,
        color: textMuted,
        height: 1.3,
      );

  /// نص قيمة الإحصائية الكبيرة
  static TextStyle get statValueText => GoogleFonts.cairo(
        fontSize: fontSizeStatValue,
        fontWeight: FontWeight.bold,
        color: textPrimary,
        height: 1.1,
      );

  /// نص قيمة الإحصائية المتوسطة
  static TextStyle get statValueMediumText => GoogleFonts.cairo(
        fontSize: fontSizeStatMedium,
        fontWeight: FontWeight.bold,
        color: textPrimary,
        height: 1.1,
      );

  /// نص النجاح (أخضر)
  static TextStyle get successText => GoogleFonts.cairo(
        fontSize: fontSizeBody,
        fontWeight: FontWeight.w600,
        color: success,
      );

  /// نص التحذير (برتقالي)
  static TextStyle get warningText => GoogleFonts.cairo(
        fontSize: fontSizeBody,
        fontWeight: FontWeight.w600,
        color: warning,
      );

  /// نص الخطر (أحمر)
  static TextStyle get dangerText => GoogleFonts.cairo(
        fontSize: fontSizeBody,
        fontWeight: FontWeight.w600,
        color: danger,
      );

  /// نص مع لون مخصص
  static TextStyle customText({
    required Color color,
    double? fontSize,
    FontWeight? fontWeight,
  }) =>
      GoogleFonts.cairo(
        fontSize: fontSize ?? fontSizeBody,
        fontWeight: fontWeight ?? FontWeight.normal,
        color: color,
      );

  // ═══════════════════════════════════════════════════════════════
  // 📝 حقول الإدخال - Input Decorations
  // ═══════════════════════════════════════════════════════════════

  static InputDecoration inputDecoration({
    required String label,
    String? hint,
    IconData? prefixIcon,
    Widget? suffix,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.cairo(
          color: textSecondary,
          fontSize: 14,
        ),
        hintStyle: GoogleFonts.cairo(
          color: textMuted,
          fontSize: 14,
        ),
        floatingLabelStyle: GoogleFonts.cairo(
          color: neonGreen,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: textMuted, size: 20)
            : null,
        suffix: suffix,
        filled: true,
        fillColor: bgCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: neonGreen, width: 2),
        ),
      );

  // ═══════════════════════════════════════════════════════════════
  // 🏗️ Widgets جاهزة - Ready-to-use Widgets
  // ═══════════════════════════════════════════════════════════════

  /// بطاقة إحصائية بأسلوب Energy Dashboard
  static Widget energyStatWidget({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
    String? trend,
    bool isPositive = true,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: energyStatCard(color),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الأيقونة والاتجاه
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: glowCustom(color, intensity: 0.2),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                if (trend != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isPositive ? success : danger).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPositive
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded,
                          color: isPositive ? success : danger,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          trend,
                          style: GoogleFonts.cairo(
                            color: isPositive ? success : danger,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // القيمة
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    unit,
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // العنوان
            Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// شريط بحث بأسلوب Energy
  static Widget searchBar({
    required String hint,
    required ValueChanged<String> onChanged,
    TextEditingController? controller,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.cairo(color: textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.cairo(color: textMuted),
          prefixIcon: const Icon(Icons.search_rounded, color: textMuted),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }

  /// شارة حالة متوهجة
  static Widget glowingBadge({
    required String text,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: GoogleFonts.cairo(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// مؤشر دائري للطاقة
  static Widget energyGauge({
    required double value,
    required double maxValue,
    required Color color,
    required String label,
    double size = 120,
  }) {
    final percentage = (value / maxValue).clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // الخلفية
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 8,
              backgroundColor: bgCard,
              valueColor: AlwaysStoppedAnimation(borderColor),
            ),
          ),
          // القيمة
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: percentage,
              strokeWidth: 8,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          // النص
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${(percentage * 100).toInt()}%',
                style: GoogleFonts.cairo(
                  fontSize: size * 0.2,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: size * 0.1,
                  color: textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// بطاقة قائمة
  static Widget listTile({
    required String title,
    String? subtitle,
    required IconData icon,
    Color? iconColor,
    Widget? trailing,
    VoidCallback? onTap,
    bool selected = false,
  }) {
    final color = iconColor ?? neonGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(0.1) : bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? color.withOpacity(0.3) : borderColor,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.w600,
            color: textPrimary,
            fontSize: 14,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: GoogleFonts.cairo(
                  color: textMuted,
                  fontSize: 12,
                ),
              )
            : null,
        trailing: trailing,
      ),
    );
  }

  /// نافذة حوار
  static Future<T?> showEnergyDialog<T>({
    required BuildContext context,
    required String title,
    required IconData icon,
    Color iconColor = neonGreen,
    required Widget content,
    List<Widget>? actions,
  }) {
    return showDialog<T>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.all(24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.cairo(
                  color: textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: content,
        actions: actions,
      ),
    );
  }

  /// مؤشر التحميل
  static Widget loadingIndicator({String? message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: glassCard,
            child: SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: neonGreen,
                strokeWidth: 3,
              ),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message,
              style: GoogleFonts.cairo(
                color: textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// رسالة فارغة
  static Widget emptyWidget({
    required String message,
    IconData icon = Icons.inbox_rounded,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: neonBlue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: neonBlue.withOpacity(0.6)),
          ),
          const SizedBox(height: 20),
          Text(
            message,
            style: GoogleFonts.cairo(
              color: textSecondary,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded),
              label: Text(actionLabel, style: GoogleFonts.cairo()),
              style: primaryButton,
            ),
          ],
        ],
      ),
    );
  }

  /// رسالة خطأ موحدة
  static Widget errorWidget({
    required String message,
    String? details,
    VoidCallback? onRetry,
  }) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: glassCard,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: danger.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline_rounded, size: 48, color: danger),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: GoogleFonts.cairo(
                color: textPrimary,
                fontSize: fontSizeH4,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (details != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bgSecondary,
                  borderRadius: BorderRadius.circular(radiusMedium),
                ),
                child: Text(
                  details,
                  style: GoogleFonts.cairo(
                    color: textSecondary,
                    fontSize: fontSizeSmall,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text('إعادة المحاولة', style: GoogleFonts.cairo()),
                style: primaryButton,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// بطاقة إحصائية موحدة بسيطة
  static Widget unifiedStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    String? trend,
    bool isPositive = true,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(paddingXXLarge),
        decoration: glowingCard(color),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // أيقونة مع خلفية ملونة
                Container(
                  padding: const EdgeInsets.all(paddingMedium),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(radiusMedium),
                  ),
                  child: Icon(icon, color: color, size: iconSizeLarge),
                ),
                // سهم الاتجاه إن وجد
                if (trend != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (isPositive ? success : danger).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(radiusRound),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPositive
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded,
                          color: isPositive ? success : danger,
                          size: iconSizeSmall,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          trend,
                          style: GoogleFonts.cairo(
                            color: isPositive ? success : danger,
                            fontSize: fontSizeSmall,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: spacingXLarge),
            // القيمة الكبيرة
            Text(
              value,
              style: statValueText,
            ),
            const SizedBox(height: spacingSmall),
            // العنوان
            Text(
              title,
              style: bodyText,
            ),
            // العنوان الفرعي
            if (subtitle != null) ...[
              const SizedBox(height: spacingXSmall),
              Text(
                subtitle,
                style: captionText,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// AppBar موحد
  static PreferredSizeWidget unifiedAppBar({
    required String title,
    IconData? icon,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,
    bool showBackButton = false,
  }) {
    return AppBar(
      backgroundColor: bgCard,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: showBackButton,
      iconTheme: const IconThemeData(color: textPrimary),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(paddingSmall),
              decoration: BoxDecoration(
                gradient: neonGreenGradient,
                borderRadius: BorderRadius.circular(radiusMedium),
                boxShadow: glowCustom(neonGreen, intensity: 0.3),
              ),
              child: Icon(icon, color: Colors.white, size: iconSizeMedium),
            ),
            const SizedBox(width: spacingMedium),
          ],
          Text(
            title,
            style: headingH3,
          ),
        ],
      ),
      bottom: bottom,
      actions: actions,
    );
  }

  /// حاوية تجاوبية
  static Widget responsiveContainer({
    required BuildContext context,
    required Widget child,
    EdgeInsets? customPadding,
  }) {
    final padding =
        customPadding ?? EdgeInsets.all(getResponsivePadding(context));
    return Padding(
      padding: padding,
      child: child,
    );
  }

  /// Grid تجاوبي
  static Widget responsiveGrid({
    required BuildContext context,
    required List<Widget> children,
    double? spacing,
    double? runSpacing,
  }) {
    final columns = getResponsiveColumns(context);
    final gap = spacing ?? spacingLarge;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: runSpacing ?? gap,
          children: children.map((child) {
            return SizedBox(
              width: itemWidth,
              child: child,
            );
          }).toList(),
        );
      },
    );
  }

  /// TabBar موحد
  static TabBar unifiedTabBar({
    required TabController controller,
    required List<String> tabs,
    List<IconData>? icons,
  }) {
    return TabBar(
      controller: controller,
      isScrollable: true,
      indicatorColor: neonGreen,
      indicatorWeight: 3,
      indicatorSize: TabBarIndicatorSize.tab,
      labelColor: neonGreen,
      unselectedLabelColor: textMuted,
      labelStyle: GoogleFonts.cairo(
          fontWeight: FontWeight.w600, fontSize: fontSizeBody),
      unselectedLabelStyle: GoogleFonts.cairo(
          fontWeight: FontWeight.w500, fontSize: fontSizeBody),
      tabs: List.generate(tabs.length, (index) {
        return Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icons != null && index < icons.length) ...[
                Icon(icons[index], size: iconSizeMedium),
                const SizedBox(width: spacingSmall),
              ],
              Text(tabs[index]),
            ],
          ),
        );
      }),
    );
  }

  /// زر أيقونة موحد
  static Widget iconButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    String? tooltip,
    double? size,
  }) {
    final iconColor = color ?? neonGreen;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radiusMedium),
          child: Container(
            padding: const EdgeInsets.all(paddingSmall),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(radiusMedium),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: size ?? iconSizeMedium,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔗 دوال التوافق - Compatibility Helpers
  // ═══════════════════════════════════════════════════════════════

  /// ظل متوهج (بديل لـ PremiumAdminTheme.glowShadow)
  static List<BoxShadow> glowShadow(Color color) =>
      glowCustom(color, intensity: 0.4);

  /// زر أيقونة دائري (بديل لـ PremiumAdminTheme.iconButtonStyle)
  static ButtonStyle iconButtonStyle(Color color) => IconButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium)),
        padding: const EdgeInsets.all(12),
      );

  /// شارة حالة (بديل لـ PremiumAdminTheme.statusBadge)
  static Widget statusBadge({
    required String text,
    required Color color,
    IconData? icon,
    bool filled = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? color : color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(radiusRound),
        border: filled ? null : Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: filled ? Colors.white : color, size: 14),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: GoogleFonts.cairo(
              color: filled ? Colors.white : color,
              fontSize: fontSizeSmall,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// بطاقة إحصائيات (بديل لـ AdminTheme.buildStatCard)
  static Widget buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    VoidCallback? onTap,
  }) =>
      unifiedStatCard(
        title: title,
        value: value,
        icon: icon,
        color: color,
        subtitle: subtitle,
        onTap: onTap,
      );

  /// شريط بحث (بديل لـ AdminTheme.buildSearchBar)
  static Widget buildSearchBar({
    required String hint,
    required ValueChanged<String> onChanged,
    TextEditingController? controller,
  }) =>
      searchBar(hint: hint, onChanged: onChanged, controller: controller);

  /// مؤشر تحميل (بديل لـ AdminTheme.buildLoadingIndicator)
  static Widget buildLoadingIndicator({String? message}) =>
      loadingIndicator(message: message);

  /// رسالة خطأ (بديل لـ AdminTheme.buildErrorWidget)
  static Widget buildErrorWidget({
    required String message,
    String? details,
    VoidCallback? onRetry,
  }) =>
      errorWidget(message: message, details: details, onRetry: onRetry);

  /// تزيين عنصر الشريط الجانبي النشط (بديل لـ PremiumAdminTheme.sidebarActiveDecoration)
  static BoxDecoration get sidebarActiveDecoration =>
      sidebarActiveItem(neonGreen);
}

// ═══════════════════════════════════════════════════════════════
// 🎭 Animated Widgets - تأثيرات متحركة
// ═══════════════════════════════════════════════════════════════

/// زر متوهج متحرك
class GlowingButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final Color color;
  final IconData? icon;

  const GlowingButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.color = EnergyDashboardTheme.neonGreen,
    this.icon,
  });

  @override
  State<GlowingButton> createState() => _GlowingButtonState();
}

class _GlowingButtonState extends State<GlowingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.6).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(_animation.value),
                blurRadius: 20,
                spreadRadius: 0,
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.text,
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// بطاقة متوهجة متحركة
class AnimatedGlowCard extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final double borderRadius;

  const AnimatedGlowCard({
    super.key,
    required this.child,
    this.glowColor = EnergyDashboardTheme.neonGreen,
    this.borderRadius = 20,
  });

  @override
  State<AnimatedGlowCard> createState() => _AnimatedGlowCardState();
}

class _AnimatedGlowCardState extends State<AnimatedGlowCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.1, end: 0.25).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: EnergyDashboardTheme.bgCard,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: widget.glowColor.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withOpacity(_animation.value),
                blurRadius: 30,
                spreadRadius: 0,
              ),
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}
