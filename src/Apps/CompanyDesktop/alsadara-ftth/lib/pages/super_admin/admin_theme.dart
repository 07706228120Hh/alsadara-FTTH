/// ⚠️ ملف قديم - تم التوحيد في EnergyDashboardTheme
/// @deprecated استخدم lib/theme/energy_dashboard_theme.dart بدلاً من هذا الملف
/// ثيم عصري لنظام مدير النظام
/// تصميم نظيف وحديث بألوان فاتحة ومريحة للعين
library;

import 'package:flutter/material.dart';

class AdminTheme {
  // ألوان رئيسية عصرية
  static const Color primaryColor = Color(0xFF6366F1); // Indigo
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color primaryDark = Color(0xFF4F46E5);

  static const Color accentColor = Color(0xFF10B981); // Emerald
  static const Color accentLight = Color(0xFF34D399);

  static const Color warningColor = Color(0xFFF59E0B); // Amber
  static const Color dangerColor = Color(0xFFEF4444); // Red
  static const Color infoColor = Color(0xFF3B82F6); // Blue

  // ألوان الخلفية
  static const Color backgroundColor = Color(0xFFF8FAFC); // Slate-50
  static const Color surfaceColor = Colors.white;
  static const Color cardColor = Colors.white;

  // ألوان النص
  static const Color textPrimary = Color(0xFF1E293B); // Slate-800
  static const Color textSecondary = Color(0xFF64748B); // Slate-500
  static const Color textMuted = Color(0xFF94A3B8); // Slate-400

  // ألوان الحدود
  static const Color borderColor = Color(0xFFE2E8F0); // Slate-200
  static const Color dividerColor = Color(0xFFF1F5F9); // Slate-100

  // ألوان الشريط الجانبي
  static const Color sidebarBg = Color(0xFF1E293B); // Slate-800
  static const Color sidebarText = Colors.white;
  static const Color sidebarActiveItem = Color(0xFF6366F1);

  // التدرجات
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Colors.white, Color(0xFFF8FAFC)],
  );

  // ظلال
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.02),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get buttonShadow => [
        BoxShadow(
          color: primaryColor.withOpacity(0.3),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];

  // تنسيقات الكروت
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: cardShadow,
      );

  static BoxDecoration get statCardDecoration => BoxDecoration(
        gradient: cardGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: cardShadow,
        border: Border.all(color: borderColor, width: 1),
      );

  // تنسيقات الأزرار
  static ButtonStyle get primaryButton => ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  static ButtonStyle get secondaryButton => ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFF1F5F9),
        foregroundColor: textPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  static ButtonStyle get dangerButton => ElevatedButton.styleFrom(
        backgroundColor: dangerColor,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  // تنسيقات حقول الإدخال
  static InputDecoration inputDecoration({
    required String label,
    IconData? icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        color: textSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      floatingLabelStyle: const TextStyle(
        color: primaryColor,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      prefixIcon: icon != null ? Icon(icon, color: textMuted, size: 20) : null,
    );
  }

  // تنسيقات AppBar
  static AppBar buildAppBar({
    required String title,
    IconData? icon,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,
  }) {
    return AppBar(
      backgroundColor: surfaceColor,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            title,
            style: const TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      ),
      iconTheme: const IconThemeData(color: textPrimary),
      bottom: bottom,
      actions: actions,
    );
  }

  // تنسيقات TabBar
  static TabBar buildTabBar({
    required TabController controller,
    required List<String> tabs,
    List<IconData>? icons,
  }) {
    return TabBar(
      controller: controller,
      isScrollable: true,
      indicatorColor: primaryColor,
      indicatorWeight: 3,
      indicatorSize: TabBarIndicatorSize.tab,
      labelColor: primaryColor,
      unselectedLabelColor: textMuted,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
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

  // تنسيقات نافذة الحوار
  static AlertDialog buildDialog({
    required BuildContext context,
    required String title,
    required IconData icon,
    Color iconColor = primaryColor,
    required Widget content,
    List<Widget>? actions,
  }) {
    return AlertDialog(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.all(24),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Text(
            title,
            style: const TextStyle(
              color: textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: content,
      actions: actions,
    );
  }

  // بطاقة إحصائية عصرية
  static Widget buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: cardShadow,
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                if (onTap != null)
                  Icon(Icons.arrow_forward_ios, color: textMuted, size: 14),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                color: textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // بطاقة قائمة عصرية
  static Widget buildListTile({
    required String title,
    String? subtitle,
    required IconData icon,
    Color? iconColor,
    Widget? trailing,
    VoidCallback? onTap,
    bool selected = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected ? primaryColor.withOpacity(0.05) : surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? primaryColor.withOpacity(0.3) : borderColor,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (iconColor ?? primaryColor).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor ?? primaryColor, size: 22),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? primaryColor : textPrimary,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: const TextStyle(color: textSecondary, fontSize: 13),
              )
            : null,
        trailing: trailing,
      ),
    );
  }

  // شريط بحث عصري
  static Widget buildSearchBar({
    required String hint,
    required ValueChanged<String> onChanged,
    TextEditingController? controller,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: cardShadow,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: textMuted),
          prefixIcon: const Icon(Icons.search, color: textMuted),
          filled: true,
          fillColor: surfaceColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  // مؤشر تحميل عصري
  static Widget buildLoadingIndicator({String? message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: cardShadow,
            ),
            child: const CircularProgressIndicator(
              color: primaryColor,
              strokeWidth: 3,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: textSecondary, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  // رسالة خطأ عصرية
  static Widget buildErrorWidget({
    required String message,
    String? details,
    VoidCallback? onRetry,
  }) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: dangerColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(Icons.error_outline, size: 48, color: dangerColor),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(
                color: textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (details != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  details,
                  style: const TextStyle(color: textSecondary, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
                style: primaryButton,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // شارة حالة
  static Widget buildStatusBadge({
    required String text,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
