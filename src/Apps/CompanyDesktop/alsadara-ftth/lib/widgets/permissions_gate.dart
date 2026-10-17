import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'permissions_storage.dart';
import '../pages/login/premium_login_page.dart';
import '../frontend/frontend.dart';

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
      return const SdPage(
        scrollable: false,
        body: Center(
          child: CircularProgressIndicator(color: SdColors.primary),
        ),
      );
    }
    // إذا لم يُمنح الإذن، أظهر زر طلب الإذن
    return SdPage(
      scrollable: false,
      maxWidth: SdSpace.formMax,
      body: Center(
        child: SdCard(
          tone: SdGroup.field.tone,
          child: SdEmptyState(
            icon: Icons.location_on_rounded,
            status: SdStatus.info,
            title: 'إذن الموقع مطلوب',
            message: 'يحتاج التطبيق إلى إذن الوصول إلى موقعك للمتابعة.',
            action: SdButton(
              label: 'السماح للتطبيق بالوصول للموقع',
              icon: Icons.location_on,
              onPressed: _requestLocationPermissionOnInstall,
            ),
          ),
        ),
      ),
    );
  }
}
