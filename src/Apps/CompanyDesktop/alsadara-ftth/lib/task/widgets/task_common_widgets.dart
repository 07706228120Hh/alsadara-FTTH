import 'package:flutter/material.dart';

/// مكوّنات واجهة مشتركة لشاشات المهام.
///
/// كل مكوّن هنا مستخرَج **حرفياً** من نسخته الأصلية في إحدى شاشات المهام دون
/// أي تغيير بصري (نفس الحشوات/الألوان/الحواف/الخطوط/الأحجام). الهدف إزالة
/// التكرار فقط — لا يجوز تعديل المظهر عند الاستبدال.
///
/// ملاحظة أداء: كل هذه المكوّنات `StatelessWidget` خفيفة بلا `AnimationController`
/// ولا `CustomPainter`، متوافقة مع إصلاحات الأداء الموثّقة.

/// ثوابت ألوان أساسية مكرّرة في شاشات المهام (بلا تغيير بصري — نفس القيم).
class TaskUiColors {
  TaskUiColors._();

  /// كحلي داكن — خلفية/عناوين شاشة المتابعة (follow_up_page).
  static const Color darkNavy = Color(0xFF1A1A2E);

  /// نيلي — عناوين/تمييز شاشة أداء الفنيين (technician_performance_page).
  static const Color indigo = Color(0xFF1A237E);
}

/// بطاقة معلومة صغيرة: أيقونة داخل مربّع ملوّن + label صغير + value.
///
/// مستخرجة حرفياً من `follow_up_page._buildInfoTile` — نفس الحشوات والألوان
/// والحواف والأحجام تماماً.
class AppInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const AppInfoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, size: 11, color: color),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
                ),
                Text(
                  value.isNotEmpty ? value : '-',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة إحصائية: أيقونة أعلى + قيمة كبيرة + عنوان صغير أسفلها، بخلفية ملوّنة.
///
/// مستخرجة حرفياً من `reports_page._buildStatCard` — نفس الحشوات والألوان
/// والأحجام و`FittedBox`. المعامل [isSmallScreen] يتحكّم بالأحجام كما في الأصل.
class AppStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool isSmallScreen;

  const AppStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.isSmallScreen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 8.0 : 12.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isSmallScreen ? 24 : 32, color: color),
          SizedBox(height: isSmallScreen ? 6 : 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          SizedBox(height: isSmallScreen ? 2 : 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              style: TextStyle(
                fontSize: isSmallScreen ? 10 : 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// chip فلتر مخصّص (أيقونة + label) مع حالة مُختارة/غير مُختارة.
///
/// مستخرج حرفياً من `follow_up_page._buildFilterChip` — نفس `AnimatedContainer`
/// (200ms، تحوّل لون/حدود فقط، بلا `AnimationController`) والحشوات والألوان
/// والحواف والظلال والأحجام تماماً.
///
/// [currentFilter] القيمة الحالية المختارة؛ يُحسب التحديد بمطابقتها مع [label].
/// [onSelected] يُستدعى بـ[label] عند الضغط (يترك للمُستدعي تبديل الحالة).
class AppFilterChip extends StatelessWidget {
  final String label;
  final String currentFilter;
  final ValueChanged<String> onSelected;
  final IconData icon;
  final Color color;

  const AppFilterChip({
    super.key,
    required this.label,
    required this.currentFilter,
    required this.onSelected,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = currentFilter == label;
    return GestureDetector(
      onTap: () => onSelected(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14, color: isSelected ? Colors.white : Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
