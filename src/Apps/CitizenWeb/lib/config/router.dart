import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/agent_auth_provider.dart';

// ═══════════════════════════════════════════════════════════════
// الصفحات العامة
// ═══════════════════════════════════════════════════════════════
import '../pages/landing_page.dart';
import '../pages/login_selector_page.dart';
import '../pages/home_page.dart';
import '../pages/login_page.dart';
import '../pages/register_page.dart';
import '../pages/verify_phone_page.dart';

// ═══════════════════════════════════════════════════════════════
// صفحات المواطن
// ═══════════════════════════════════════════════════════════════
import '../pages/citizen/citizen_login_page.dart';
import '../pages/citizen/citizen_dashboard.dart';

// خدمات الإنترنت
import '../pages/citizen/internet/internet_services_page.dart';
import '../pages/citizen/internet/maintenance_request_page.dart';
import '../pages/citizen/internet/renewal_page.dart';
import '../pages/citizen/internet/upgrade_page.dart';
import '../pages/citizen/internet/new_subscription_page.dart';

// خدمات الماستر
import '../pages/citizen/master/master_services_page.dart';
import '../pages/citizen/master/recharge_card_page.dart';
import '../pages/citizen/master/new_master_card_page.dart';
import '../pages/citizen/master/delivery_withdrawal_page.dart';

// المتجر
import '../pages/citizen/store/store_page.dart';
import '../pages/citizen/store/cart_page.dart';
import '../pages/citizen/store/checkout_page.dart';

// الدفع
import '../pages/payment/payment_page.dart';

// صفحات إضافية للمواطن
import '../pages/citizen/profile/profile_page.dart';
import '../pages/citizen/support/support_page.dart';
import '../pages/citizen/notifications/notifications_page.dart';
import '../pages/citizen/orders/orders_page.dart';
import '../pages/citizen/kml_map_page.dart';

// ═══════════════════════════════════════════════════════════════
// صفحات الوكيل
// ═══════════════════════════════════════════════════════════════
import '../pages/agent/agent_login_page.dart';
import '../pages/agent/agent_dashboard.dart';
import '../pages/agent/activate_subscriber_page.dart';
import '../pages/agent/balance_request_page.dart';
import '../pages/agent/transactions_page.dart';
import '../pages/agent/reports_page.dart';
import '../pages/agent/master_recharge_page.dart';
import '../pages/agent/debt_payment_page.dart';
import '../pages/agent/agent_settings_page.dart';

/// إنشاء الراوتر مع حماية المسارات واستعادة الجلسة
GoRouter createRouter({
  required AuthProvider authProvider,
  required AgentAuthProvider agentAuthProvider,
}) {
  return GoRouter(
    initialLocation: '/',
    // إعادة تقييم التوجيه عند تغيير حالة المصادقة
    refreshListenable: Listenable.merge([authProvider, agentAuthProvider]),
    redirect: (context, state) {
      final path = state.matchedLocation;

      // ─── انتظار التهيئة ───
      if (!authProvider.isInitialized || !agentAuthProvider.isInitialized) {
        // أثناء التهيئة لا نوجه - نبقى في المكان الحالي
        return null;
      }

      final isCitizenAuth = authProvider.isAuthenticated;
      final isAgentAuth = agentAuthProvider.isAuthenticated;

      // الصفحات العامة التي لا تحتاج تسجيل دخول
      final publicPaths = [
        '/',
        '/login-selector',
        '/login',
        '/register',
        '/citizen/login',
        '/citizen/register',
        '/agent/login',
      ];
      final isPublicPage =
          publicPaths.contains(path) || path.startsWith('/verify');

      // ─── توجيه login-selector ───
      if (path == '/login-selector') {
        return '/citizen/login';
      }

      // ─── حماية مسارات المواطن ───
      if (path.startsWith('/citizen/') && !isPublicPage && !isCitizenAuth) {
        return '/citizen/login';
      }

      // ─── حماية مسارات الوكيل ───
      if (path.startsWith('/agent/') &&
          path != '/agent/login' &&
          !isAgentAuth) {
        return '/';
      }

      // ─── توجيه المسجلين بعيداً عن صفحات الدخول ───
      if (isCitizenAuth && (path == '/citizen/login' || path == '/login')) {
        return '/citizen/home';
      }
      if (isAgentAuth && path == '/agent/login') {
        return '/agent/home';
      }

      // ─── توجيه المسارات القديمة ───
      if (path == '/home' && isCitizenAuth) {
        return '/citizen/home';
      }
      if (path == '/store') {
        return '/citizen/store';
      }

      return null;
    },
    routes: [
      // ═══════════════════════════════════════════════════════════════
      // الصفحات العامة
      // ═══════════════════════════════════════════════════════════════

      /// الصفحة الرئيسية (Landing Page)
      GoRoute(path: '/', builder: (context, state) => const LandingPage()),

      /// صفحة اختيار نوع المستخدم
      GoRoute(
        path: '/login-selector',
        builder: (context, state) => const LoginSelectorPage(),
      ),

      // ═══════════════════════════════════════════════════════════════
      // صفحات المواطن (Citizen)
      // ═══════════════════════════════════════════════════════════════

      /// تسجيل دخول المواطن
      GoRoute(
        path: '/citizen/login',
        builder: (context, state) => const CitizenLoginPage(),
      ),

      /// تسجيل مواطن جديد
      GoRoute(
        path: '/citizen/register',
        builder: (context, state) => const RegisterPage(),
      ),

      /// الصفحة الرئيسية للمواطن (Dashboard)
      GoRoute(
        path: '/citizen/home',
        builder: (context, state) => const CitizenDashboard(),
      ),

      // ───────────────────────────────────────────────────────────────
      // خدمات الإنترنت
      // ───────────────────────────────────────────────────────────────

      /// صفحة خدمات الإنترنت الرئيسية
      GoRoute(
        path: '/citizen/internet',
        builder: (context, state) => const InternetServicesPage(),
      ),

      /// طلب صيانة
      GoRoute(
        path: '/citizen/internet/maintenance',
        builder: (context, state) => const MaintenanceRequestPage(),
      ),

      /// تجديد الاشتراك
      GoRoute(
        path: '/citizen/internet/renewal',
        builder: (context, state) => const RenewalPage(),
      ),

      /// ترقية الباقة
      GoRoute(
        path: '/citizen/internet/upgrade',
        builder: (context, state) => const UpgradePage(),
      ),

      /// اشتراك جديد
      GoRoute(
        path: '/citizen/internet/new',
        builder: (context, state) => const NewSubscriptionPage(),
      ),

      // ───────────────────────────────────────────────────────────────
      // خدمات الماستر كارد
      // ───────────────────────────────────────────────────────────────

      /// صفحة خدمات الماستر الرئيسية
      GoRoute(
        path: '/citizen/master',
        builder: (context, state) => const MasterServicesPage(),
      ),

      /// شحن رصيد الماستر
      GoRoute(
        path: '/citizen/master/recharge',
        builder: (context, state) => const RechargeCardPage(),
      ),

      /// طلب بطاقة جديدة
      GoRoute(
        path: '/citizen/master/new-card',
        builder: (context, state) => const NewMasterCardPage(),
      ),

      /// طلب سحب ديلفري
      GoRoute(
        path: '/citizen/master/delivery-withdraw',
        builder: (context, state) => const DeliveryWithdrawalPage(),
      ),

      /// كشف حساب (placeholder)
      GoRoute(
        path: '/citizen/master/statement',
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            title: const Text('كشف الحساب'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/citizen/master'),
            ),
          ),
          body: const Center(child: Text('صفحة كشف الحساب - قيد التطوير')),
        ),
      ),

      // ───────────────────────────────────────────────────────────────
      // المتجر
      // ───────────────────────────────────────────────────────────────

      /// صفحة المتجر الرئيسية
      GoRoute(
        path: '/citizen/store',
        builder: (context, state) => const StorePage(),
      ),

      /// سلة التسوق
      GoRoute(
        path: '/citizen/store/cart',
        builder: (context, state) => const CartPage(),
      ),

      /// إتمام الشراء
      GoRoute(
        path: '/citizen/store/checkout',
        builder: (context, state) => const CheckoutPage(),
      ),

      /// تفاصيل المنتج (placeholder)
      GoRoute(
        path: '/citizen/store/product/:id',
        builder: (context, state) {
          final productId = state.pathParameters['id'];
          return Scaffold(
            appBar: AppBar(
              title: const Text('تفاصيل المنتج'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/citizen/store'),
              ),
            ),
            body: Center(
              child: Text('تفاصيل المنتج #$productId - قيد التطوير'),
            ),
          );
        },
      ),

      // ───────────────────────────────────────────────────────────────
      // الدفع الإلكتروني
      // ───────────────────────────────────────────────────────────────

      /// صفحة الدفع
      GoRoute(
        path: '/citizen/payment',
        builder: (context, state) {
          final amount = state.uri.queryParameters['amount'];
          final type = state.uri.queryParameters['type'];
          return PaymentPage(amount: amount, type: type);
        },
      ),

      // ───────────────────────────────────────────────────────────────
      // صفحات إضافية للمواطن
      // ───────────────────────────────────────────────────────────────

      /// الملف الشخصي
      GoRoute(
        path: '/citizen/profile',
        builder: (context, state) => const ProfilePage(),
      ),

      /// الدعم الفني
      GoRoute(
        path: '/citizen/support',
        builder: (context, state) => const SupportPage(),
      ),

      /// الإشعارات
      GoRoute(
        path: '/citizen/notifications',
        builder: (context, state) => const NotificationsPage(),
      ),

      /// طلباتي والفواتير
      GoRoute(
        path: '/citizen/orders',
        builder: (context, state) => const OrdersPage(),
      ),

      /// خريطة تغطية الشبكة
      GoRoute(
        path: '/citizen/kml-map',
        builder: (context, state) => const KmlMapPage(),
      ),

      /// طلباتي (للتوافقية)
      GoRoute(
        path: '/citizen/requests',
        builder: (context, state) => const OrdersPage(),
      ),

      /// الإعدادات
      GoRoute(
        path: '/citizen/settings',
        builder: (context, state) => const ProfilePage(),
      ),

      // ═══════════════════════════════════════════════════════════════
      // صفحات الوكيل (Agent)
      // ═══════════════════════════════════════════════════════════════

      /// تسجيل دخول الوكيل
      GoRoute(
        path: '/agent/login',
        builder: (context, state) => const AgentLoginPage(),
      ),

      /// لوحة تحكم الوكيل
      GoRoute(
        path: '/agent/home',
        builder: (context, state) => const AgentDashboard(),
      ),

      /// تفعيل مشترك
      GoRoute(
        path: '/agent/activate',
        builder: (context, state) => const ActivateSubscriberPage(),
      ),

      /// شحن ماستر (للوكيل)
      GoRoute(
        path: '/agent/master-recharge',
        builder: (context, state) => const MasterRechargePage(),
      ),

      /// طلب رصيد
      GoRoute(
        path: '/agent/balance-request',
        builder: (context, state) => const BalanceRequestPage(),
      ),

      /// سداد مديونية
      GoRoute(
        path: '/agent/debt-payment',
        builder: (context, state) => const DebtPaymentPage(),
      ),

      /// سجل العمليات
      GoRoute(
        path: '/agent/transactions',
        builder: (context, state) => const TransactionsPage(),
      ),

      /// التقارير والإحصائيات
      GoRoute(
        path: '/agent/reports',
        builder: (context, state) => const AgentReportsPage(),
      ),

      /// إعدادات الوكيل
      GoRoute(
        path: '/agent/settings',
        builder: (context, state) => const AgentSettingsPage(),
      ),

      // ═══════════════════════════════════════════════════════════════
      // الصفحات القديمة (للتوافق)
      // ═══════════════════════════════════════════════════════════════
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/verify',
        builder: (context, state) {
          final citizenId = state.uri.queryParameters['citizenId'];
          if (citizenId == null) {
            return const Scaffold(
              body: Center(child: Text('معرف المواطن مفقود')),
            );
          }
          return VerifyPhonePage(citizenId: citizenId);
        },
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomePage()),
      GoRoute(
        path: '/subscriptions',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('صفحة الاشتراكات - قيد التطوير')),
        ),
      ),
      GoRoute(path: '/store', builder: (context, state) => const StorePage()),
      GoRoute(
        path: '/support',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('صفحة الدعم الفني - قيد التطوير')),
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('صفحة الملف الشخصي - قيد التطوير')),
        ),
      ),
    ],
  );
}
