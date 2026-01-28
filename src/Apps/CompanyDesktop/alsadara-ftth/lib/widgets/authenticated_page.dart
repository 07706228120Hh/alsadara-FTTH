import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class AuthenticatedPage extends StatefulWidget {
  final Widget child;
  final String title;

  const AuthenticatedPage({
    super.key,
    required this.child,
    required this.title,
  });

  @override
  State<AuthenticatedPage> createState() => _AuthenticatedPageState();
}

class _AuthenticatedPageState extends State<AuthenticatedPage> {
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
          // إذا انتهت الجلسة، أظهر رسالة وانتقل إلى صفحة تسجيل الدخول
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showSessionExpiredDialog();
          });
        }

        return widget.child;
      },
    );
  }

  void _showSessionExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 10),
              Text('انتهت الجلسة'),
            ],
          ),
          content: Text(
            'انتهت صلاحية جلسة الدخول الخاصة بك. سيتم توجيهك إلى صفحة تسجيل الدخول.',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/',
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF1565C0),
              ),
              child: Text(
                'موافق',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}
