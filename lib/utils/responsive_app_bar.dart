import 'package:flutter/material.dart';
import 'responsive_text_sizes.dart';
import 'smart_text_color.dart';

class ResponsiveAppBar {
  /// إنشاء AppBar متجاوب موحد
  static PreferredSizeWidget build({
    required BuildContext context,
    required String title,
    List<Widget>? actions,
    Widget? leading,
    bool automaticallyImplyLeading = true,
    Color? backgroundColor,
    bool centerTitle = true,
    IconData? leadingIcon,
    VoidCallback? onLeadingPressed,
    List<Color>? gradientColors,
  }) {
    final textSizes = ResponsiveTextSizes.getTextSizes(context);
    final deviceType = ResponsiveTextSizes.getDeviceType(
      MediaQuery.of(context).size.width,
    );

    // جعل AppBar أكثر نحافة: تقليل طفيف لأحجام العنوان والأيقونات
    const double compactScale = 0.9;
    final double titleSize = (textSizes.appBarTitle * compactScale);
    final double iconSize = (textSizes.appBarIconSize * compactScale);

    // الألوان الافتراضية للتدرج
    final defaultGradient = [
      Color(0xFF283593),
      Color(0xFF1976D2),
      Color(0xFF64B5F6)
    ];
    final finalGradientColors = gradientColors ?? defaultGradient;

    // تحديد لون النص بطريقة ذكية
    final smartTextColor = SmartTextColor.getAppBarTextColorWithGradient(
        context, finalGradientColors);
    final smartIconColor = smartTextColor;

    return AppBar(
      elevation: deviceType == DeviceType.desktop ? 4 : 8,
      shadowColor: Colors.blue.withValues(alpha: 0.15),
      backgroundColor: backgroundColor ?? Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: finalGradientColors,
          ),
        ),
      ),
      centerTitle: centerTitle,
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading ??
          (leadingIcon != null
              ? IconButton(
                  icon: Icon(
                    leadingIcon,
                    color: smartIconColor,
                    size: iconSize,
                  ),
                  onPressed:
                      onLeadingPressed ?? () => Navigator.of(context).pop(),
                )
              : null),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(deviceType == DeviceType.mobile ? 6 : 10),
            decoration: BoxDecoration(
              color: smartTextColor == Colors.white
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.business_center_rounded,
              color: smartIconColor,
              size: iconSize * 0.95,
            ),
          ),
          SizedBox(width: deviceType == DeviceType.mobile ? 10 : 14),
          Flexible(
            child: Text(
              title,
              style: SmartTextColor.getSmartTextStyle(
                context: context,
                fontSize: titleSize,
                fontWeight: FontWeight.bold,
                gradientColors: finalGradientColors,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
      actions: actions?.map((action) {
        if (action is IconButton) {
          return IconButton(
            icon: Icon(
              (action.icon as Icon).icon,
              color: smartIconColor,
              size: iconSize,
            ),
            onPressed: action.onPressed,
            tooltip: action.tooltip,
            padding: EdgeInsets.all(deviceType == DeviceType.mobile ? 8 : 10),
          );
        }
        return action;
      }).toList(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(deviceType == DeviceType.desktop ? 24 : 20),
        ),
      ),
    );
  }

  /// إنشاء عنوان صفحة متجاوب
  static Widget buildPageTitle({
    required BuildContext context,
    required String title,
    IconData? icon,
    Color? color,
    Widget? trailing,
  }) {
    final textSizes = ResponsiveTextSizes.getTextSizes(context);
    final spacing = ResponsiveTextSizes.getSpacing(context);

    return Container(
      padding: ResponsiveTextSizes.getCardPadding(context),
      margin: EdgeInsets.only(bottom: spacing * 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: EdgeInsets.all(spacing),
              decoration: BoxDecoration(
                color: (color ?? Colors.blue).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color ?? Colors.blue[600],
                size: textSizes.iconSize,
              ),
            ),
            SizedBox(width: spacing * 1.5),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: textSizes.pageTitle,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF2C3E50),
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  /// إنشاء عنوان قسم متجاوب
  static Widget buildSectionTitle({
    required BuildContext context,
    required String title,
    IconData? icon,
    Color? color,
    Widget? trailing,
  }) {
    final textSizes = ResponsiveTextSizes.getTextSizes(context);
    final spacing = ResponsiveTextSizes.getSpacing(context);

    return Padding(
      padding: EdgeInsets.only(bottom: spacing),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: color ?? Colors.grey[600],
              size: textSizes.iconSize * 0.8,
            ),
            SizedBox(width: spacing),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: textSizes.sectionTitle,
                fontWeight: FontWeight.bold,
                color: color ?? const Color(0xFF2C3E50),
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  /// إنشاء بطاقة متجاوبة
  static Widget buildCard({
    required BuildContext context,
    required Widget child,
    EdgeInsets? margin,
    EdgeInsets? padding,
    Color? color,
    double? elevation,
  }) {
    final deviceType = ResponsiveTextSizes.getDeviceType(
      MediaQuery.of(context).size.width,
    );
    final spacing = ResponsiveTextSizes.getSpacing(context);

    return Container(
      margin: margin ?? EdgeInsets.only(bottom: spacing * 2),
      padding: padding ?? ResponsiveTextSizes.getCardPadding(context),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(
          deviceType == DeviceType.desktop ? 20 : 16,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius:
                elevation ?? (deviceType == DeviceType.desktop ? 12 : 8),
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  /// إنشاء زر متجاوب
  static Widget buildButton({
    required BuildContext context,
    required String text,
    required VoidCallback onPressed,
    IconData? icon,
    Color? backgroundColor,
    Color? textColor,
    bool isOutlined = false,
    bool isLoading = false,
  }) {
    final textSizes = ResponsiveTextSizes.getTextSizes(context);
    final spacing = ResponsiveTextSizes.getSpacing(context);

    if (isOutlined) {
      return OutlinedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? SizedBox(
                width: textSizes.iconSize * 0.7,
                height: textSizes.iconSize * 0.7,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: textSizes.iconSize * 0.8),
        label: Text(
          text,
          style: TextStyle(
            fontSize: textSizes.button,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(
            horizontal: spacing * 2,
            vertical: spacing * 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? SizedBox(
              width: textSizes.iconSize * 0.7,
              height: textSizes.iconSize * 0.7,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: textSizes.iconSize * 0.8),
      label: Text(
        text,
        style: TextStyle(
          fontSize: textSizes.button,
          fontWeight: FontWeight.w600,
          color: textColor ?? Colors.white,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? const Color(0xFF1976D2),
        padding: EdgeInsets.symmetric(
          horizontal: spacing * 2,
          vertical: spacing * 1.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
