import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../pages/home_page.dart';
import '../pages/login_page.dart';
import '../pages/register_page.dart';
import '../pages/verify_phone_page.dart';

final GoRouter router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    final authProvider = context.read<AuthProvider>();
    final isAuthenticated = authProvider.isAuthenticated;
    final isLoginPage = state.matchedLocation == '/login';
    final isRegisterPage = state.matchedLocation == '/register';
    final isVerifyPage = state.matchedLocation.startsWith('/verify');

    // If not authenticated and trying to access protected pages
    if (!isAuthenticated && !isLoginPage && !isRegisterPage && !isVerifyPage) {
      return '/login';
    }

    // If authenticated and trying to access login/register
    if (isAuthenticated && (isLoginPage || isRegisterPage)) {
      return '/home';
    }

    return null; // No redirect needed
  },
  routes: [
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
    GoRoute(
      path: '/store',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('صفحة المتجر - قيد التطوير')),
      ),
    ),
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
