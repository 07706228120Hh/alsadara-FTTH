// ⚠️ مهمل (17-10-2026): لم يعد مستخدماً في أي شاشة — البديل SdUiKit (lib/frontend/components/sd_ui_kit.dart).
// يُحذف في المرحلة 7 من docs/ui-unification/THEME_CLEANUP_PLAN.md بعد موافقة المالك.
/// 🎨 Accounting Light Theme (XONEPROO Style)
/// ثيم فاتح لصفحات المحاسبة - خلفية رمادية فاتحة + بطاقات بيضاء + أيقونات ملونة
/// يستخدم **نفس أسماء الخصائص** مثل EnergyDashboardTheme لسهولة التبديل
library;

import 'package:flutter/material.dart';
import '../frontend/tokens/sd_colors.dart';

/// ثيم المحاسبة الفاتح - XONEPROO Style
/// Drop-in replacement لـ EnergyDashboardTheme في صفحات المحاسبة
class AccountingTheme {
  AccountingTheme._();

  // ═══════════════════════════════════════════════════════════════
  // 🎨 الألوان الرئيسية - Light Dashboard (XONEPROO)
  // ═══════════════════════════════════════════════════════════════

  // الخلفيات (فاتحة)
  static const Color bgPrimary = SdColors.ground;
  static const Color bgSecondary = SdColors.groundAlt;
  static const Color bgCard = SdColors.surface;
  static const Color bgCardHover = SdColors.surfaceAlt;
  static const Color bgSidebar = SdColors.primary;

  // ألوان حيوية (XONEPROO)
  static const Color neonGreen = SdColors.success;
  static const Color neonBlue = SdColors.primary;
  static const Color neonPurple = SdColors.platformBase;
  static const Color neonOrange = SdColors.warning;
  static const Color neonPink = SdColors.platformLight;
  static const Color neonYellow = SdColors.warning;

  // ألوان الحالة
  static const Color success = SdColors.success;
  static const Color warning = SdColors.warning;
  static const Color danger = SdColors.danger;
  static const Color info = SdColors.info;

  // ألوان النصوص (داكنة - للخلفية الفاتحة)
  static const Color textPrimary = SdColors.ink;
  static const Color textSecondary = SdColors.muted;
  static const Color textMuted = SdColors.faint;
  static const Color textAccent = SdColors.success;

  // على الخلفية الداكنة (toolbar)
  static const Color textOnDark = SdColors.surface;
  static const Color textOnDarkSecondary = SdColors.sideShade;
  static const Color textOnDarkMuted = SdColors.faint;

  // حدود
  static const Color borderColor = SdColors.divider;
  static const Color borderGlow = SdColors.info;

  // ═══════════════════════════════════════════════════════════════
  // 💰 ألوان مالية
  // ═══════════════════════════════════════════════════════════════

  static const Color debitFill = SdColors.successTint;
  static const Color creditFill = SdColors.dangerTint;
  static const Color debitText = SdColors.success;
  static const Color creditText = SdColors.danger;

  static const Map<String, Color> salaryStatusColors = {
    'Pending': SdColors.warning,
    'Paid': SdColors.success,
    'PartiallyPaid': SdColors.info,
    'Cancelled': SdColors.danger,
  };

  static Color statusColor(String status) =>
      salaryStatusColors[status] ?? textMuted;

  // الجداول
  static const Color tableHeaderBg = SdColors.primary;
  static const Color tableHeaderText = SdColors.surface;
  static const Color tableRowAlt = SdColors.surfaceAlt;

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
    colors: [SdColors.success, SdColors.successEdge],
  );
  static const LinearGradient neonBlueGradient = LinearGradient(
    colors: [SdColors.primary, SdColors.primaryEdge],
  );
  static const LinearGradient primaryGradient = neonBlueGradient;
  static const LinearGradient accentGradient = neonGreenGradient;
  static const LinearGradient neonPurpleGradient = LinearGradient(
    colors: [SdColors.platformBase, SdColors.platformEdge],
  );
  static const LinearGradient neonOrangeGradient = LinearGradient(
    colors: [SdColors.warning, SdColors.warningEdge],
  );
  static const LinearGradient neonPinkGradient = LinearGradient(
    colors: [SdColors.platformLight, SdColors.platformBase],
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
            style: TextStyle(fontFamily: 'Cairo', color: textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text('إعادة المحاولة', style: TextStyle(fontFamily: 'Cairo')),
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
          Text(message, style: TextStyle(fontFamily: 'Cairo', color: textMuted)),
        ],
      ),
    );
  }

  /// SnackBar
  static void showSnack(BuildContext context, String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(fontFamily: 'Cairo')),
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
        title: Text(title, style: TextStyle(fontFamily: 'Cairo', color: textPrimary)),
        content: Text(message, style: TextStyle(fontFamily: 'Cairo', color: textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text(cancelLabel, style: TextStyle(fontFamily: 'Cairo', color: textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor ?? neonGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radiusMedium)),
            ),
            child: Text(confirmLabel, style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }
}
