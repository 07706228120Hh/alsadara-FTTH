import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../pages/vps_tenant_login_page.dart';

class AuthGuard extends StatefulWidget {
  final Widget child;

  const AuthGuard({super.key, required this.child});

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  late Stream<bool> _authStateStream;

  @override
  void initState() {
    super.initState();
    _authStateStream = AuthService.instance.authStateStream;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _authStateStream,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data == false) {
          // إذا انتهت الجلسة، انتقل إلى صفحة تسجيل الدخول
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                    builder: (context) => const VpsTenantLoginPage()),
                (route) => false,
              );
            }
          });
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // إذا كانت الجلسة صالحة، اعرض المحتوى
        return widget.child;
      },
    );
  }
}

// مكون لفحص الجلسة عند بداية التطبيق
class SessionChecker extends StatefulWidget {
  final Widget child;
  final Widget loginPage;

  const SessionChecker({
    super.key,
    required this.child,
    required this.loginPage,
  });

  @override
  State<SessionChecker> createState() => _SessionCheckerState();
}

class _SessionCheckerState extends State<SessionChecker> {
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final isValid = await AuthService.instance.isValidSession();
    setState(() {
      _isAuthenticated = isValid;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'جاري التحقق من الجلسة...',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return _isAuthenticated ? widget.child : widget.loginPage;
  }
}
