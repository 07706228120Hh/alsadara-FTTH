/// ويدجات موحدة لصفحات السوبر أدمن
/// توفر بنية وتصميم متسق عبر كل الصفحات
library;

import 'package:flutter/material.dart';

import '../../../frontend/tokens/sd_colors.dart' show SdColors;
import '../../../frontend/components/sd_dash_kit.dart';
// ═══════════════════════════════════════════════════════════════
// 1. SAPageHeader — رأس الصفحة الموحد
// ═══════════════════════════════════════════════════════════════

/// رأس صفحة موحد بتدرج لوني + أيقونة + عنوان + أزرار
class SAPageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color? secondaryColor;
  final VoidCallback? onRefresh;
  final List<Widget>? actions;
  final Widget? trailing;

  const SAPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.secondaryColor,
    this.onRefresh,
    this.actions,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color2 = secondaryColor ?? SdColors.info;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.15),
            color2.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Icon box
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withOpacity(0.8)],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: SdDashKit.glowCustom(color, intensity: 0.15),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          // Title & subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: SdColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: SdColors.faint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Trailing widget (e.g. badge)
          if (trailing != null) ...[
            trailing!,
            const SizedBox(width: 8),
          ],
          // Extra actions
          if (actions != null) ...actions!,
          // Refresh button
          if (onRefresh != null)
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded,
                  color: SdColors.success, size: 22),
              tooltip: 'تحديث',
              style: IconButton.styleFrom(
                backgroundColor:
                    SdColors.success.withOpacity(0.1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 2. SAFilterBar — شريط الفلاتر الموحد
// ═══════════════════════════════════════════════════════════════

/// شريط فلاتر موحد: بحث + chips + ترتيب
class SAFilterBar extends StatelessWidget {
  final String? searchHint;
  final ValueChanged<String>? onSearchChanged;
  final List<SAFilterChip>? chips;
  final String? selectedChip;
  final ValueChanged<String>? onChipSelected;
  final List<SADropdownItem>? sortItems;
  final String? selectedSort;
  final ValueChanged<String>? onSortChanged;
  final List<Widget>? extraWidgets;

  const SAFilterBar({
    super.key,
    this.searchHint,
    this.onSearchChanged,
    this.chips,
    this.selectedChip,
    this.onChipSelected,
    this.sortItems,
    this.selectedSort,
    this.onSortChanged,
    this.extraWidgets,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Search
        if (onSearchChanged != null)
          Expanded(
            flex: 3,
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: SdColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SdColors.divider),
              ),
              child: TextField(
                onChanged: onSearchChanged,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: SdColors.ink, fontSize: 12),
                decoration: InputDecoration(
                  hintText: searchHint ?? 'بحث...',
                  hintStyle: TextStyle(
                      fontFamily: 'Cairo',
                      color: SdColors.faint, fontSize: 12),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: SdColors.faint, size: 18),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

        if (onSearchChanged != null && (chips != null || sortItems != null))
          const SizedBox(width: 10),

        // Filter chips
        if (chips != null)
          ...chips!.map((chip) {
            final isSelected = selectedChip == chip.key;
            return Padding(
              padding: const EdgeInsets.only(left: 4),
              child: InkWell(
                onTap: () => onChipSelected?.call(chip.key),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? chip.color.withOpacity(0.2)
                        : SdColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? chip.color
                          : SdColors.divider,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      chip.label,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: isSelected
                            ? chip.color
                            : SdColors.faint,
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),

        if (chips != null && sortItems != null) const SizedBox(width: 10),

        // Sort dropdown
        if (sortItems != null)
          SADropdown(
            items: sortItems!,
            value: selectedSort,
            onChanged: onSortChanged,
            icon: Icons.sort_rounded,
          ),

        // Extra widgets
        if (extraWidgets != null) ...extraWidgets!,
      ],
    );
  }
}

class SAFilterChip {
  final String key;
  final String label;
  final Color color;

  const SAFilterChip({
    required this.key,
    required this.label,
    required this.color,
  });
}

// ═══════════════════════════════════════════════════════════════
// 3. SADropdown — قائمة منسدلة موحدة
// ═══════════════════════════════════════════════════════════════

class SADropdownItem {
  final String value;
  final String label;

  const SADropdownItem({required this.value, required this.label});
}

class SADropdown extends StatelessWidget {
  final List<SADropdownItem> items;
  final String? value;
  final ValueChanged<String>? onChanged;
  final IconData? icon;

  const SADropdown({
    super.key,
    required this.items,
    this.value,
    this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SdColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: SdColors.surface,
          style: TextStyle(
              fontFamily: 'Cairo',
              color: SdColors.ink, fontSize: 11),
          icon: Icon(icon ?? Icons.keyboard_arrow_down_rounded,
              color: SdColors.faint, size: 18),
          items: items
              .map((i) => DropdownMenuItem(value: i.value, child: Text(i.label)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged?.call(v);
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 4. SAStatCard — بطاقة إحصائية موحدة
// ═══════════════════════════════════════════════════════════════

class SAStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final bool alert;
  final VoidCallback? onTap;

  const SAStatCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
    this.alert = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.18),
              color.withOpacity(0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(alert ? 0.6 : 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                if (alert)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: SdDashKit.glowCustom(color,
                          intensity: 0.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: SdColors.ink,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Cairo',
                color: SdColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: color.withOpacity(0.8),
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 5. SASection — قسم موحد (بطاقة مع عنوان)
// ═══════════════════════════════════════════════════════════════

class SASection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets? padding;

  const SASection({
    super.key,
    required this.title,
    required this.icon,
    this.iconColor,
    this.trailing,
    required this.child,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? SdColors.success;

    return Container(
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SdColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: SdColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          // Content
          Padding(
            padding: padding ?? const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 6. SATable — جدول موحد
// ═══════════════════════════════════════════════════════════════

class SATableColumn {
  final String label;
  final int flex;

  const SATableColumn({required this.label, this.flex = 1});
}

class SATableHeader extends StatelessWidget {
  final List<SATableColumn> columns;

  const SATableHeader({super.key, required this.columns});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: SdColors.groundAlt,
        border: Border(
          top: BorderSide(color: SdColors.divider),
          bottom: BorderSide(color: SdColors.divider),
        ),
      ),
      child: Row(
        children: columns
            .map((c) => Expanded(
                  flex: c.flex,
                  child: Text(
                    c.label,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: SdColors.faint,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class SATableRow extends StatelessWidget {
  final List<Widget> cells;
  final List<int>? flexes;
  final Color? highlightColor;
  final VoidCallback? onTap;

  const SATableRow({
    super.key,
    required this.cells,
    this.flexes,
    this.highlightColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: highlightColor,
          border: Border(
            bottom: BorderSide(
              color: SdColors.divider.withOpacity(0.3),
            ),
          ),
        ),
        child: Row(
          children: List.generate(cells.length, (i) {
            final flex = (flexes != null && i < flexes!.length) ? flexes![i] : 1;
            return Expanded(flex: flex, child: cells[i]);
          }),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 7. SAStatusBadge — شارة حالة موحدة
// ═══════════════════════════════════════════════════════════════

class SAStatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const SAStatusBadge({
    super.key,
    required this.text,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Cairo',
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 8. SAAlertBanner — شريط تنبيهات موحد
// ═══════════════════════════════════════════════════════════════

class SAAlertItem {
  final String type; // danger, warning, info
  final String title;
  final String message;

  const SAAlertItem({
    required this.type,
    required this.title,
    required this.message,
  });

  Color get color => type == 'danger'
      ? SdColors.danger
      : type == 'warning'
          ? SdColors.warning
          : SdColors.info;

  IconData get icon => type == 'danger'
      ? Icons.error_rounded
      : type == 'warning'
          ? Icons.warning_rounded
          : Icons.info_rounded;
}

class SAAlertBanner extends StatelessWidget {
  final List<SAAlertItem> alerts;

  const SAAlertBanner({super.key, required this.alerts});

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: SdColors.warning.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_rounded,
                  color: SdColors.warning, size: 16),
              const SizedBox(width: 8),
              Text(
                'تنبيهات النظام',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: SdColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              SACountBadge(
                  count: alerts.length,
                  color: SdColors.warning),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: alerts.map((a) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: a.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: a.color.withOpacity(0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(a.icon, color: a.color, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '${a.title} (${a.message})',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: a.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 9. SACountBadge — شارة عدد صغيرة
// ═══════════════════════════════════════════════════════════════

class SACountBadge extends StatelessWidget {
  final int count;
  final Color color;

  const SACountBadge({
    super.key,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontFamily: 'Cairo',
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 10. SAProgressBar — شريط تقدم موحد
// ═══════════════════════════════════════════════════════════════

class SAProgressBar extends StatelessWidget {
  final double value; // 0.0 - 1.0
  final Color? color;
  final double height;
  final bool showPercent;

  const SAProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = 6,
    this.showPercent = false,
  });

  @override
  Widget build(BuildContext context) {
    final barColor = color ??
        (value > 0.8
            ? SdColors.warning
            : SdColors.success);

    final row = Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(height / 2),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              backgroundColor: SdColors.groundAlt,
              valueColor: AlwaysStoppedAnimation(barColor),
              minHeight: height,
            ),
          ),
        ),
        if (showPercent) ...[
          const SizedBox(width: 6),
          Text(
            '${(value * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: SdColors.faint,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );

    return row;
  }
}

// ═══════════════════════════════════════════════════════════════
// 11. SADaysRemainingBadge — شارة الأيام المتبقية
// ═══════════════════════════════════════════════════════════════

class SADaysRemainingBadge extends StatelessWidget {
  final int days;

  const SADaysRemainingBadge({super.key, required this.days});

  Color get _color => days <= 0
      ? SdColors.danger
      : days <= 7
          ? SdColors.warning
          : days <= 30
              ? SdColors.warning
              : SdColors.success;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withOpacity(0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            days > 0 ? '$days' : 'منتهي',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: _color,
              fontSize: days > 0 ? 14 : 10,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
          if (days > 0)
            Text(
              'يوم',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: _color.withOpacity(0.7),
                fontSize: 9,
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 12. SACompanyAvatar — صورة/حرف الشركة الموحد
// ═══════════════════════════════════════════════════════════════

class SACompanyAvatar extends StatelessWidget {
  final String name;
  final Color color;
  final double size;

  const SACompanyAvatar({
    super.key,
    required this.name,
    required this.color,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0] : '?',
          style: TextStyle(
            fontFamily: 'Cairo',
            color: color,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Helpers — دوال مساعدة
// ═══════════════════════════════════════════════════════════════

/// يرجع لون الحالة حسب اسمها
Color saStatusColor(String status) {
  switch (status) {
    case 'active':
      return SdColors.success;
    case 'warning':
      return SdColors.warning;
    case 'critical':
      return SdColors.warning;
    case 'expired':
      return SdColors.danger;
    case 'suspended':
      return SdColors.faint;
    default:
      return SdColors.faint;
  }
}

/// يرجع اسم الحالة بالعربي
String saStatusLabel(String status) {
  switch (status) {
    case 'active':
      return 'نشطة';
    case 'warning':
      return 'تحذير';
    case 'critical':
      return 'حرجة';
    case 'expired':
      return 'منتهية';
    case 'suspended':
      return 'معلقة';
    default:
      return status;
  }
}

/// يحسب حالة الشركة من بياناتها
String saCompanyStatus({
  required bool isActive,
  required bool isExpired,
  required int daysRemaining,
}) {
  if (!isActive) return 'suspended';
  if (isExpired) return 'expired';
  if (daysRemaining <= 7) return 'critical';
  if (daysRemaining <= 30) return 'warning';
  return 'active';
}
