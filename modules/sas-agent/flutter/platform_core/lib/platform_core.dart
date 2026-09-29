/// الحزمة المشتركة لتطبيقات منصة العراق الرقمية (البوّابة · الوزارة · الشركات · الوكلاء · المشتركون).
///
/// تصدّر: الإعدادات، الجلسة، عميل API (موظّفون + مشتركون)، النماذج،
/// نظام التصميم الموحّد (tokens/brand/theme/typography)، الهيكل الموحّد (PlatformApp/AppShell)،
/// الودجات المشتركة، وشاشات الدخول والتذاكر.
library;

export 'src/config.dart';
export 'src/session.dart';
export 'src/api/api_core.dart';
export 'src/api/staff_api.dart';
export 'src/api/subscriber_api.dart';
export 'src/models/ticket.dart';
export 'src/models/portal_summary.dart';
export 'src/models/subscriber_row.dart';

// نظام التصميم
export 'src/theme/tokens.dart';
export 'src/theme/brand.dart';
export 'src/theme/typography.dart';
export 'src/theme/platform_theme.dart';
export 'src/theme/theme_controller.dart';
export 'src/theme/app_theme.dart'; // طبقة توافق (BrandColors/AppTheme)

// الهيكل والودجات
export 'src/shell/platform_app.dart';
export 'src/widgets/app_shell.dart';
export 'src/widgets/brand_widgets.dart';
export 'src/widgets/banner.dart';
export 'src/widgets/inputs.dart';
export 'src/widgets/states.dart';
export 'src/widgets/p_table.dart';
export 'src/widgets/common.dart';
export 'src/widgets/ticket_widgets.dart';
export 'src/utils/format.dart';

// الدخول
export 'src/auth/auth_scaffold.dart';
export 'src/auth/server_status.dart';
export 'src/auth/staff_login_screen.dart';
export 'src/auth/otp_login_screen.dart';

// الشاشات المشتركة
export 'src/screens/tickets_screen.dart';
export 'src/screens/ticket_detail_screen.dart';
export 'src/screens/sas_panel_screen.dart';
export 'src/screens/sas_reports.dart';                // مركز التقارير + عارض جدول عام
export 'src/screens/sas_aggregate_reports.dart';      // العملاء + إحصائيات التفعيل
export 'src/screens/sas_config_screen.dart';
export 'src/screens/sas_subscriber_detail.dart';
export 'src/screens/subscriber_portal_screen.dart';   // بوابة المشترك عبر SAS
export 'src/screens/sas_link_dialog.dart';            // حوار ربط حساب البوابة
