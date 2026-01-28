import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import '../services/app_close_handler.dart';

// مفتاح global للوصول للNavigator
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Widget يراقب إغلاق النافذة الرئيسية وينفذ مسح البيانات
class WindowCloseHandler extends StatefulWidget {
  final Widget child;

  const WindowCloseHandler({
    required this.child,
    super.key,
  });

  @override
  State<WindowCloseHandler> createState() => _WindowCloseHandlerState();
}

class _WindowCloseHandlerState extends State<WindowCloseHandler>
    with WindowListener {
  bool _isClosing = false; // منع استدعاءات متعددة

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
      // تأكد من أن النافذة لا تغلق بشكل مباشر
      _setupWindowProtection();
      debugPrint('🔧 تم تسجيل WindowCloseHandler كمستمع لأحداث النافذة');
    }
  }

  /// إعداد حماية النافذة من الإغلاق المباشر
  Future<void> _setupWindowProtection() async {
    try {
      await windowManager.setPreventClose(true);
      debugPrint('🔒 تم تفعيل حماية النافذة من الإغلاق المباشر');
    } catch (e) {
      debugPrint('⚠️ فشل في إعداد حماية النافذة: $e');
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (_isClosing) {
      debugPrint('⏳ عملية الإغلاق قيد التنفيذ بالفعل - تم تجاهل الطلب');
      return;
    }

    _isClosing = true;
    debugPrint('🪟 تم النقر على زر إغلاق النافذة - بدء معالجة الإغلاق');

    try {
      // الحصول على السياق أولاً
      final context = navigatorKey.currentContext;
      debugPrint(
          '🗝️ السياق المحدد: ${context != null ? 'موجود' : 'غير موجود'}');

      if (context != null && context.mounted) {
        debugPrint('📱 عرض dialog تأكيد الإغلاق');
        final closeOption = await _showCloseConfirmationDialog(context);

        if (closeOption == 'clear_and_close') {
          debugPrint('✅ المستخدم اختار: مسح البيانات والإغلاق');
          // تنفيذ مسح البيانات قبل الإغلاق
          await AppCloseHandler.clearSavedLoginCredentials();
          debugPrint('🗑️ تم مسح بيانات تسجيل الدخول');

          // إغلاق النافذة
          await windowManager.destroy();
          debugPrint('✅ تم إغلاق التطبيق نهائياً مع مسح البيانات');
        } else if (closeOption == 'close_only') {
          debugPrint('✅ المستخدم اختار: الإغلاق فقط');
          // إغلاق النافذة بدون مسح البيانات
          await windowManager.destroy();
          debugPrint('✅ تم إغلاق التطبيق نهائياً بدون مسح البيانات');
        } else {
          debugPrint('❌ المستخدم ألغى عملية الإغلاق');
          _isClosing = false; // إعادة تعيين الحالة
        }
      } else {
        debugPrint(
            '⚠️ لا يوجد context صالح - الإغلاق المباشر بدون مسح البيانات');
        // في حالة عدم وجود context، أغلق مباشرة بدون مسح البيانات
        await windowManager.destroy();
      }
    } catch (e) {
      debugPrint('❌ خطأ في معالجة إغلاق النافذة: $e');
      // في حالة حدوث خطأ، أغلق بدون مسح البيانات
      await windowManager.destroy();
    }
  }

  // إضافة onWindowCloseRequested للإصدار الجديد
  Future<bool> onWindowCloseRequested() async {
    if (_isClosing) {
      debugPrint('⏳ عملية الإغلاق قيد التنفيذ بالفعل - إرجاع false');
      return false; // منع الإغلاق إذا كانت العملية قيد التنفيذ
    }

    _isClosing = true;
    debugPrint('📋 تم طلب إغلاق النافذة - onWindowCloseRequested');

    try {
      // الحصول على السياق
      final context = navigatorKey.currentContext;
      debugPrint(
          '🗝️ السياق المحدد: ${context != null ? 'موجود' : 'غير موجود'}');

      if (context != null && context.mounted) {
        debugPrint('📱 عرض dialog تأكيد الإغلاق من onWindowCloseRequested');
        final closeOption = await _showCloseConfirmationDialog(context);

        if (closeOption == 'clear_and_close') {
          debugPrint('✅ المستخدم اختار: مسح البيانات والإغلاق');
          // تنفيذ مسح البيانات قبل الإغلاق
          await AppCloseHandler.clearSavedLoginCredentials();
          debugPrint('🗑️ تم مسح بيانات تسجيل الدخول');
          return true; // السماح بالإغلاق
        } else if (closeOption == 'close_only') {
          debugPrint('✅ المستخدم اختار: الإغلاق فقط');
          return true; // السماح بالإغلاق بدون مسح البيانات
        } else {
          debugPrint('❌ المستخدم ألغى عملية الإغلاق');
          _isClosing = false; // إعادة تعيين الحالة
          return false; // منع الإغلاق
        }
      } else {
        debugPrint('⚠️ لا يوجد context صالح - السماح بالإغلاق المباشر');
        // في حالة عدم وجود context، اسمح بالإغلاق بدون مسح البيانات
        return true; // السماح بالإغلاق
      }
    } catch (e) {
      debugPrint('❌ خطأ في معالجة onWindowCloseRequested: $e');
      // في حالة حدوث خطأ، اسمح بالإغلاق بدون مسح البيانات
      return true; // السماح بالإغلاق
    }
  }

  /// إظهار dialog تأكيد الإغلاق مع خيارات متعددة
  Future<String?> _showCloseConfirmationDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false, // منع الإغلاق بالنقر خارج الـ dialog
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.logout,
                color: Colors.blueAccent,
                size: 24,
              ),
              SizedBox(width: 8),
              Text(
                'تأكيد إغلاق التطبيق',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'اختر كيف تريد إغلاق التطبيق:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.delete_sweep, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'مسح البيانات والإغلاق',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Text(
                '• سيتم مسح بيانات تسجيل الدخول المحفوظة',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              Text(
                '• ستحتاج لتسجيل الدخول مرة أخرى',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.exit_to_app, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'الإغلاق فقط',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Text(
                '• ستبقى بيانات تسجيل الدخول محفوظة',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              Text(
                '• يمكنك الدخول تلقائياً في المرة القادمة',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text(
                'إلغاء',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop('close_only'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'إغلاق فقط',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop('clear_and_close'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'مسح والإغلاق',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
