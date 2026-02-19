/// 🎨 Accounting Light Theme (XONEPROO Style)
/// ثيم فاتح لصفحات المحاسبة - خلفية رمادية فاتحة + بطاقات بيضاء + أيقونات ملونة
/// يستخدم **نفس أسماء الخصائص** مثل EnergyDashboardTheme لسهولة التبديل
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ثيم المحاسبة الفاتح - XONEPROO Style
/// Drop-in replacement لـ EnergyDashboardTheme في صفحات المحاسبة
class AccountingTheme {
  AccountingTheme._();

  // ═══════════════════════════════════════════════════════════════
  // 🎨 الألوان الرئيسية - Light Dashboard (XONEPROO)
  // ═══════════════════════════════════════════════════════════════

  // الخلفيات (فاتحة)
  static const Color bgPrimary = Color(0xFFF5F6FA);
  static const Color bgSecondary = Color(0xFFEEEFF5);
  static const Color bgCard = Colors.white;
  static const Color bgCardHover = Color(0xFFF0F4FF);
  static const Color bgSidebar = Color(0xFF2C3E50);

  // ألوان حيوية (XONEPROO)
  static const Color neonGreen = Color(0xFF2ECC71);
  static const Color neonBlue = Color(0xFF3498DB);
  static const Color neonPurple = Color(0xFF8E44AD);
  static const Color neonOrange = Color(0xFFE67E22);
  static const Color neonPink = Color(0xFFE91E63);
  static const Color neonYellow = Color(0xFFF1C40F);

  // ألوان الحالة
  static const Color success = Color(0xFF2ECC71);
  static const Color warning = Color(0xFFF39C12);
  static const Color danger = Color(0xFFE74C3C);
  static const Color info = Color(0xFF3498DB);

  // ألوان النصوص (داكنة - للخلفية الفاتحة)
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF444444);
  static const Color textMuted = Color(0xFF777777);
  static const Color textAccent = Color(0xFF2ECC71);

  // على الخلفية الداكنة (toolbar)
  static const Color textOnDark = Color(0xFFFFFFFF);
  static const Color textOnDarkSecondary = Color(0xFFCBD5E1);
  static const Color textOnDarkMuted = Color(0xFF94A3B8);

  // حدود
  static const Color borderColor = Color(0xFFE8E8E8);
  static const Color borderGlow = Color(0xFF3498DB);

  // ═══════════════════════════════════════════════════════════════
  // 💰 ألوان مالية
  // ═══════════════════════════════════════════════════════════════

  static const Color debitFill = Color(0xFFE8F8F0);
  static const Color creditFill = Color(0xFFFDE8E8);
  static const Color debitText = Color(0xFF27AE60);
  static const Color creditText = Color(0xFFE74C3C);

  static const Map<String, Color> salaryStatusColors = {
    'Pending': Color(0xFFF39C12),
    'Paid': Color(0xFF2ECC71),
    'PartiallyPaid': Color(0xFF3498DB),
    'Cancelled': Color(0xFFE74C3C),
  };

  static Color statusColor(String status) =>
      salaryStatusColors[status] ?? textMuted;

  // الجداول
  static const Color tableHeaderBg = Color(0xFF2C3E50);
  static const Color tableHeaderText = Color(0xFFFFFFFF);
  static const Color tableRowAlt = Color(0x08000000);

  // ═══════════════════════════════════════════════════════════════
  // 🔗 أسماء بديلة للتوافق مع EnergyDashboardTheme
  // ═══════════════════════════════════════════════════════════════

  static const Color primaryColor = neonBlue;
  static const Color accentColor = neonGreen;
  static const Color backgroundColor = bgPrimary;
  static const Color surfaceColor = bgCard;
  static const Color warningColor = warning;
  static const Color dangerColor = danger;
  static const Color infoColor = info;
  static const Color successColor = success;

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
  // 🌈 التدرجات
  // ═══════════════════════════════════════════════════════════════

  static const LinearGradient neonGreenGradient = LinearGradient(
    colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
  );
  static const LinearGradient neonBlueGradient = LinearGradient(
    colors: [Color(0xFF3498DB), Color(0xFF2980B9)],
  );
  static const LinearGradient primaryGradient = neonBlueGradient;
  static const LinearGradient accentGradient = neonGreenGradient;
  static const LinearGradient neonPurpleGradient = LinearGradient(
    colors: [Color(0xFF8E44AD), Color(0xFF7D3C98)],
  );
  static const LinearGradient neonOrangeGradient = LinearGradient(
    colors: [Color(0xFFE67E22), Color(0xFFD35400)],
  );
  static const LinearGradient neonPinkGradient = LinearGradient(
    colors: [Color(0xFFE91E63), Color(0xFFC2185B)],
  );

  // ═══════════════════════════════════════════════════════════════
  // 📐 أبعاد
  // ═══════════════════════════════════════════════════════════════

  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 20.0;
  static const double radiusRound = 50.0;

  static const double paddingSmall = 8.0;
  static const double paddingMedium = 12.0;
  static const double paddingLarge = 16.0;
  static const double paddingXLarge = 20.0;
  static const double paddingXXLarge = 24.0;

  static const double fontSizeBody = 14.0;
  static const double fontSizeSmall = 12.0;
  static const double fontSizeCaption = 10.0;

  // ═══════════════════════════════════════════════════════════════
  // 🎯 ظلال
  // ═══════════════════════════════════════════════════════════════

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0x14000000),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ];

  // ═══════════════════════════════════════════════════════════════
  // 📦 تزيينات
  // ═══════════════════════════════════════════════════════════════

  /// شريط الأدوات (Toolbar) - كحلي داكن
  static BoxDecoration get toolbar => BoxDecoration(
        color: bgSidebar,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      );

  /// بطاقة عادية
  static BoxDecoration get card => BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(10),
        boxShadow: cardShadow,
      );

  /// رأس الجدول
  static BoxDecoration get tableHeader => BoxDecoration(
        color: tableHeaderBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      );

  /// حقل إدخال المدين
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
          borderSide: BorderSide(color: success.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: const BorderSide(color: success, width: 2),
        ),
      );

  /// حقل إدخال الدائن
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

  /// زر رئيسي
  static ButtonStyle get primaryButton => ElevatedButton.styleFrom(
        backgroundColor: neonBlue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      );

  /// عرض خطأ
  static Widget errorView(String message, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: danger, size: 64),
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

  /// SnackBar
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
}
