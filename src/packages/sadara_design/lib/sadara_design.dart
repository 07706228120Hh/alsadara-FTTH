/// نظام تصميم الصدارة الموحّد (Sadara Design — sd).
///
/// المصدر المركزي الوحيد للهوية البصرية عبر تطبيقات المنصة (التطبيق الرئيسي
/// وتطبيق المواطن/الوكيل). يُستورد باستيراد واحد:
/// ```dart
/// import 'package:sadara_design/sadara_design.dart';
/// ```
library;

// الرموز (tokens)
export 'tokens/sd_colors.dart';
export 'tokens/sd_metrics.dart';
export 'tokens/sd_typography.dart';
export 'tokens/sd_responsive.dart';

// الثيم
export 'theme/sd_theme.dart';

// المكوّنات الجوهرية (3D)
export 'components/sd_raised.dart';
export 'components/sd_cube.dart';
export 'components/sd_basics.dart';
export 'components/sd_segmented.dart';
export 'components/sd_app_bar.dart';
export 'components/sd_menu_tile.dart';
export 'components/sd_side_nav.dart';
export 'components/sd_ui_kit.dart';
export 'components/sd_dash_kit.dart';
export 'components/sd_stat_pedestal.dart';
export 'components/sd_page.dart';
