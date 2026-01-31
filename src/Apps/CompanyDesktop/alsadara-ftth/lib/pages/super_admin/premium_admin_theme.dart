/// 🎨 ثيم فخم لنظام مدير النظام (Premium Admin Theme)
/// تصميم عصري وفخم مع تأثيرات Glass Morphism
/// متوافق مع RTL ومريح للعين
library;

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ثيم فخم موحد لجميع شاشات الإدارة
class PremiumAdminTheme {
  PremiumAdminTheme._();

  // ═══════════════════════════════════════════════════════════════
  // 🎨 الألوان الرئيسية - Premium Color Palette
  // ═══════════════════════════════════════════════════════════════

  // الألوان الأساسية - Royal Purple & Gold
  static const Color primary = Color(0xFF6C5CE7); // Purple
  static const Color primaryLight = Color(0xFF8B7CF6);
  static const Color primaryDark = Color(0xFF5441D6);
  static const Color primarySoft = Color(0xFFEDE9FE); // Very light purple

  // الألوان الثانوية - Emerald Success
  static const Color accent = Color(0xFF00D9A5); // Teal/Emerald
  static const Color accentLight = Color(0xFF5EFCE8);
  static const Color accentDark = Color(0xFF00B894);

  // ألوان الحالة
  static const Color success = Color(0xFF00D9A5);
  static const Color warning = Color(0xFFFFB347);
  static const Color danger = Color(0xFFFF6B6B);
  static const Color info = Color(0xFF54A0FF);

  // ألوان الخلفية - Dark Elegant
  static const Color bgDark = Color(0xFF0F0E17);
  static const Color bgDarkLight = Color(0xFF1A1A2E);
  static const Color bgDarkCard = Color(0xFF16213E);
  static const Color bgDarkSurface = Color(0xFF1E2746);

  // ألوان الخلفية - Light Clean
  static const Color bgLight = Color(0xFFF7F8FC);
  static const Color bgLightCard = Color(0xFFFFFFFF);
  static const Color bgLightSurface = Color(0xFFF1F3F8);

  // ألوان النصوص
  static const Color textDark = Color(0xFF1A1A2E);
  static const Color textMedium = Color(0xFF6B7280);
  static const Color textLight = Color(0xFF9CA3AF);
  static const Color textWhite = Color(0xFFF7F8FC);

  // ألوان الحدود
  static const Color border = Color(0xFFE5E7EB);
  static const Color borderDark = Color(0xFF2D3748);
  static const Color borderLight = Color(0xFFF3F4F6);

  // ═══════════════════════════════════════════════════════════════
  // 🌈 التدرجات الفخمة - Premium Gradients
  // ═══════════════════════════════════════════════════════════════

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF11998e), Color(0xFF38ef7d)],
  );

  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF2994A), Color(0xFFF2C94C)],
  );

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
  );

  static const LinearGradient sidebarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1A1A2E), Color(0xFF0F0E17)],
  );

  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x40FFFFFF),
      Color(0x10FFFFFF),
    ],
  );

  // ═══════════════════════════════════════════════════════════════
  // 🌟 الظلال الفخمة - Premium Shadows
  // ═══════════════════════════════════════════════════════════════

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.02),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get elevatedShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 30,
          offset: const Offset(0, 15),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ];

  static List<BoxShadow> glowShadow(Color color) => [
        BoxShadow(
          color: color.withOpacity(0.4),
          blurRadius: 20,
          spreadRadius: 1,
        ),
      ];

  // ═══════════════════════════════════════════════════════════════
  // 📦 تزيينات البطاقات - Card Decorations
  // ═══════════════════════════════════════════════════════════════

  /// بطاقة عادية بيضاء
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: bgLightCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: cardShadow,
      );

  /// بطاقة زجاجية (Glass Morphism)
  static BoxDecoration glassDecoration({
    Color? color,
    double opacity = 0.1,
    double borderRadius = 20,
  }) =>
      BoxDecoration(
        color: (color ?? Colors.white).withOpacity(opacity),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1.5,
        ),
      );

  /// بطاقة مع تدرج
  static BoxDecoration gradientCardDecoration(LinearGradient gradient) =>
      BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: cardShadow,
      );

  /// بطاقة Sidebar Item نشطة
  static BoxDecoration sidebarActiveDecoration = BoxDecoration(
    gradient: primaryGradient,
    borderRadius: BorderRadius.circular(14),
    boxShadow: glowShadow(primary),
  );

  /// بطاقة Sidebar Item عادية
  static BoxDecoration sidebarItemDecoration = BoxDecoration(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(14),
  );

  // ═══════════════════════════════════════════════════════════════
  // 🔘 أنماط الأزرار - Button Styles
  // ═══════════════════════════════════════════════════════════════

  /// زر أساسي فخم
  static ButtonStyle get primaryButton => ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.cairo(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      );

  /// زر ثانوي
  static ButtonStyle get secondaryButton => ElevatedButton.styleFrom(
        backgroundColor: bgLightSurface,
        foregroundColor: textDark,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: border),
        ),
        textStyle: GoogleFonts.cairo(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      );

  /// زر نجاح
  static ButtonStyle get successButton => ElevatedButton.styleFrom(
        backgroundColor: success,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  /// زر خطر
  static ButtonStyle get dangerButton => ElevatedButton.styleFrom(
        backgroundColor: danger,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  /// زر شفاف مع حدود
  static ButtonStyle get outlinedButton => OutlinedButton.styleFrom(
        foregroundColor: primary,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: const BorderSide(color: primary, width: 1.5),
      );

  /// زر أيقونة دائري
  static ButtonStyle iconButtonStyle(Color color) => IconButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(12),
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
          color: textMedium,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: GoogleFonts.cairo(
          color: textLight,
          fontSize: 14,
        ),
        floatingLabelStyle: GoogleFonts.cairo(
          color: primary,
          fontWeight: FontWeight.w600,
        ),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: textLight, size: 20)
            : null,
        suffix: suffix,
        filled: true,
        fillColor: bgLightSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: danger, width: 1),
        ),
      );

  // ═══════════════════════════════════════════════════════════════
  // 🏗️ Widgets جاهزة - Ready-to-use Widgets
  // ═══════════════════════════════════════════════════════════════

  /// بطاقة إحصائية فخمة
  static Widget statCard({
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
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: bgLightCard,
          borderRadius: BorderRadius.circular(20),
          boxShadow: cardShadow,
          border: Border.all(color: border.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // أيقونة مع خلفية ملونة
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                // سهم الاتجاه إن وجد
                if (trend != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (isPositive ? success : danger).withOpacity(0.1),
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
                          size: 16,
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
            // القيمة الكبيرة
            Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: textDark,
                height: 1,
              ),
            ),
            const SizedBox(height: 8),
            // العنوان
            Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: textMedium,
                fontWeight: FontWeight.w500,
              ),
            ),
            // العنوان الفرعي
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  color: textLight,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// شريط بحث فخم
  static Widget searchBar({
    required String hint,
    required ValueChanged<String> onChanged,
    TextEditingController? controller,
    VoidCallback? onFilter,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: bgLightCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: softShadow,
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: GoogleFonts.cairo(color: textDark),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: GoogleFonts.cairo(color: textLight),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: textLight, size: 22),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
            ),
          ),
          if (onFilter != null) ...[
            Container(
              height: 30,
              width: 1,
              color: border,
            ),
            IconButton(
              onPressed: onFilter,
              icon: const Icon(Icons.tune_rounded, color: textMedium),
              tooltip: 'فلترة',
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  /// شارة حالة فخمة
  static Widget statusBadge({
    required String text,
    required Color color,
    IconData? icon,
    bool filled = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? color : color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: filled ? null : Border.all(color: color.withOpacity(0.3)),
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
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// مؤشر تحميل فخم
  static Widget loadingIndicator({String? message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: bgLightCard,
              borderRadius: BorderRadius.circular(20),
              boxShadow: cardShadow,
            ),
            child: const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: primary,
                strokeWidth: 3,
              ),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 20),
            Text(
              message,
              style: GoogleFonts.cairo(
                color: textMedium,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// رسالة خطأ فخمة
  static Widget errorWidget({
    required String message,
    String? details,
    VoidCallback? onRetry,
  }) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: bgLightCard,
          borderRadius: BorderRadius.circular(24),
          boxShadow: cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: danger.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline_rounded, size: 48, color: danger),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: GoogleFonts.cairo(
                color: textDark,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (details != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: bgLightSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  details,
                  style: GoogleFonts.cairo(
                    color: textMedium,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 24),
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

  /// رسالة فارغة فخمة
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
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 56, color: primary.withOpacity(0.6)),
          ),
          const SizedBox(height: 24),
          Text(
            message,
            style: GoogleFonts.cairo(
              color: textMedium,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
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

  /// نافذة حوار فخمة
  static Future<T?> showPremiumDialog<T>({
    required BuildContext context,
    required String title,
    required IconData icon,
    Color iconColor = primary,
    required Widget content,
    List<Widget>? actions,
  }) {
    return showDialog<T>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: bgLightCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
        contentPadding: const EdgeInsets.all(28),
        actionsPadding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.cairo(
                  color: textDark,
                  fontSize: 20,
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

  /// بطاقة قائمة فخمة
  static Widget listTile({
    required String title,
    String? subtitle,
    required IconData icon,
    Color? iconColor,
    Widget? trailing,
    VoidCallback? onTap,
    bool selected = false,
  }) {
    final color = iconColor ?? primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected ? primary.withOpacity(0.08) : bgLightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? primary.withOpacity(0.3) : border,
        ),
        boxShadow: selected ? null : softShadow,
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.w600,
            color: selected ? primary : textDark,
            fontSize: 15,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: GoogleFonts.cairo(
                  color: textMedium,
                  fontSize: 13,
                ),
              )
            : null,
        trailing: trailing,
      ),
    );
  }

  /// AppBar فخم
  static PreferredSizeWidget appBar({
    required String title,
    IconData? icon,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,
    bool showBackButton = false,
  }) {
    return AppBar(
      backgroundColor: bgLightCard,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: showBackButton,
      iconTheme: const IconThemeData(color: textDark),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: primaryGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: glowShadow(primary.withOpacity(0.3)),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
          ],
          Text(
            title,
            style: GoogleFonts.cairo(
              color: textDark,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
        ],
      ),
      actions: actions,
      bottom: bottom,
    );
  }

  /// TabBar فخم
  static TabBar tabBar({
    required TabController controller,
    required List<String> tabs,
    List<IconData>? icons,
  }) {
    return TabBar(
      controller: controller,
      isScrollable: true,
      indicatorColor: primary,
      indicatorWeight: 3,
      indicatorSize: TabBarIndicatorSize.tab,
      labelColor: primary,
      unselectedLabelColor: textLight,
      labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelStyle:
          GoogleFonts.cairo(fontWeight: FontWeight.w500, fontSize: 14),
      indicator: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: primary, width: 3),
        ),
      ),
      tabs: List.generate(tabs.length, (index) {
        return Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icons != null && index < icons.length) ...[
                Icon(icons[index], size: 18),
                const SizedBox(width: 8),
              ],
              Text(tabs[index]),
            ],
          ),
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 🔧 Extension للتطبيق السهل
// ═══════════════════════════════════════════════════════════════

extension PremiumContext on BuildContext {
  /// الحصول على عرض الشاشة
  double get screenWidth => MediaQuery.of(this).size.width;

  /// الحصول على ارتفاع الشاشة
  double get screenHeight => MediaQuery.of(this).size.height;

  /// هل الشاشة واسعة (Desktop)
  bool get isWideScreen => screenWidth >= 1024;

  /// هل الشاشة متوسطة (Tablet)
  bool get isMediumScreen => screenWidth >= 600 && screenWidth < 1024;

  /// هل الشاشة صغيرة (Mobile)
  bool get isSmallScreen => screenWidth < 600;
}
