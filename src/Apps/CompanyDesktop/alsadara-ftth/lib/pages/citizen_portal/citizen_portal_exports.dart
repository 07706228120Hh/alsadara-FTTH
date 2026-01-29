/// نظام المواطن (Citizen Portal)
/// يظهر فقط للشركة المرتبطة بنظام المواطن
///
/// هذا الملف يصدّر جميع شاشات ومكونات نظام المواطن
library;

// الشاشات الرئيسية
export 'citizen_portal_dashboard.dart';
export 'citizens_list_page.dart';
export 'citizen_details_page.dart';
export 'citizen_requests_page.dart';
export 'citizen_subscriptions_page.dart';
export 'citizen_payments_page.dart';
export 'subscription_plans_page.dart';

// المكونات المشتركة
export 'widgets/citizen_card.dart';
export 'widgets/citizen_stats_card.dart';
export 'widgets/request_status_badge.dart';

// الخدمات
export 'services/citizen_portal_service.dart';

// النماذج
export 'models/citizen_portal_models.dart';
