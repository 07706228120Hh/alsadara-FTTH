import 'package:flutter/material.dart';
import '../services/app_close_handler.dart';

/// Widget يدير دورة حياة التطبيق
class AppLifecycleManager extends StatefulWidget {
  final Widget child;

  const AppLifecycleManager({
    required this.child,
    super.key,
  });

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // الاشتراك في تغييرات دورة حياة التطبيق
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // التطبيق عاد للمقدمة
        debugPrint('📱 التطبيق عاد للمقدمة');
        break;
      case AppLifecycleState.paused:
        // التطبيق في الخلفية
        debugPrint('📱 التطبيق في الخلفية');
        break;
      case AppLifecycleState.detached:
        // التطبيق سيتم إغلاقه
        debugPrint('📱 التطبيق سيتم إغلاقه - مسح بيانات تسجيل الدخول...');
        AppCloseHandler.clearAllLoginData();
        break;
      case AppLifecycleState.inactive:
        // التطبيق غير نشط مؤقتاً
        break;
      case AppLifecycleState.hidden:
        // التطبيق مخفي
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
