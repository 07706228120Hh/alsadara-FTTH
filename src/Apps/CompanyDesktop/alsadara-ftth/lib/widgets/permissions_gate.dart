import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'permissions_storage.dart';
import '../pages/login/premium_login_page.dart';

class PermissionsGate extends StatefulWidget {
  final Widget child;
  const PermissionsGate({super.key, required this.child});

  @override
  State<PermissionsGate> createState() => _PermissionsGateState();
}

class _PermissionsGateState extends State<PermissionsGate> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _requestLocationPermissionOnInstall();
  }

  Future<void> _requestLocationPermissionOnInstall() async {
    // تحقق إذا تم منح الإذن مسبقًا
    final alreadyGranted = await PermissionsStorage.getPermissionsGranted();
    if (alreadyGranted) {
      _goToLogin();
      return;
    }
    // اطلب إذن الموقع فقط
    final status = await Permission.location.request();
    if (status.isGranted) {
      await PermissionsStorage.setPermissionsGranted(true);
      _goToLogin();
    } else {
      setState(() {
        _loading = false;
      });
    }
  }

  void _goToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const PremiumLoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // إذا لم يُمنح الإذن، أظهر زر طلب الإذن
    return Scaffold(
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.location_on),
          label: const Text('السماح للتطبيق بالوصول للموقع'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[800],
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            textStyle: const TextStyle(fontSize: 18),
          ),
          onPressed: _requestLocationPermissionOnInstall,
        ),
      ),
    );
  }
}
