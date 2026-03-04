import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import '../services/app_close_handler.dart';

// مفتاح global للوصول للNavigator
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Widget محسن يراقب إغلاق النافذة الرئيسية ويعطي خيارات متعددة للإغلاق
class WindowCloseHandlerFixed extends StatefulWidget {
  final Widget child;

  const WindowCloseHandlerFixed({
    required this.child,
    super.key,
  });

  @override
  State<WindowCloseHandlerFixed> createState() =>
      _WindowCloseHandlerFixedState();
}

class _WindowCloseHandlerFixedState extends State<WindowCloseHandlerFixed>
    with WindowListener {
  bool _isClosing = false; // منع استدعاءات متعددة

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
      _setupWindowProtection();
      debugPrint('🔧 تم تسجيل WindowCloseHandlerFixed كمستمع لأحداث النافذة');
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
    debugPrint('🚨 تم استدعاء onWindowClose - معالجة مع الحماية المفعلة');
    final shouldClose = await _handleCloseRequest();
    if (shouldClose) {
      await windowManager.destroy();
    }
  }

  /// الدالة الأساسية لمعالجة طلبات الإغلاق (تعمل مع الإصدارات الجديدة)
  Future<bool> onWindowCloseRequested() async {
    debugPrint('🪟 تم طلب إغلاق النافذة - onWindowCloseRequested');
    return await _handleCloseRequest();
  }

  /// معالجة طلب إغلاق النافذة الموحدة
  Future<bool> _handleCloseRequest() async {
    if (_isClosing) {
      debugPrint('⏳ عملية الإغلاق قيد التنفيذ بالفعل');
      return false;
    }

    _isClosing = true;
    debugPrint('📋 بدء معالجة طلب إغلاق النافذة');

    try {
      // الحصول على السياق
      final context = navigatorKey.currentContext;
      debugPrint(
          '🗝️ السياق: ${context != null && context.mounted ? 'صالح' : 'غير صالح'}');

      if (context != null && context.mounted) {
        debugPrint('📱 عرض dialog تأكيد الإغلاق مع خيارات متعددة');
        final closeOption = await _showCloseConfirmationDialog(context);

        if (closeOption == 'clear_and_close') {
          debugPrint('✅ المستخدم اختار: مسح البيانات والإغلاق');

          // إظهار مؤشر التحميل أثناء المسح
          if (context.mounted) {
            _showClearingDataDialog(context);
          }

          // تنفيذ مسح البيانات قبل الإغلاق
          await AppCloseHandler.clearSavedLoginCredentials();
          debugPrint('🗑️ تم مسح بيانات تسجيل الدخول المحفوظة فقط');

          // مسح توكنات FTTH دائماً عند الإغلاق
          await AppCloseHandler.clearFtthSessionTokens();

          // إزالة الحماية للسماح بالإغلاق
          await windowManager.setPreventClose(false);
          debugPrint('🔓 تم إلغاء حماية النافذة');

          // إغلاق dialog التحميل إذا كان مفتوحاً
          if (context.mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }

          return true;
        } else if (closeOption == 'close_only') {
          debugPrint('✅ المستخدم اختار: الإغلاق فقط بدون مسح البيانات');

          // مسح توكنات FTTH دائماً عند الإغلاق (للأمان)
          await AppCloseHandler.clearFtthSessionTokens();

          // إزالة الحماية للسماح بالإغلاق بدون مسح البيانات
          await windowManager.setPreventClose(false);
          debugPrint('🔓 تم إلغاء حماية النافذة للإغلاق المباشر');

          return true;
        } else {
          debugPrint('❌ المستخدم ألغى عملية الإغلاق');
          return false;
        }
      } else {
        debugPrint('⚠️ لا يوجد context صالح - السماح بالإغلاق المباشر');
        await windowManager.setPreventClose(false);
        return true;
      }
    } catch (e) {
      debugPrint('❌ خطأ في معالجة طلب الإغلاق: $e');
      await windowManager.setPreventClose(false);
      return true;
    } finally {
      _isClosing = false;
    }
  }

  /// إظهار dialog مسح البيانات
  void _showClearingDataDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text(
                'جاري مسح بيانات تسجيل الدخول المحفوظة...',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        );
      },
    );
  }

  /// إظهار dialog تأكيد الإغلاق مع خيارات متعددة
  Future<String?> _showCloseConfirmationDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.logout_rounded,
                color: Colors.blue,
                size: 28,
              ),
              SizedBox(width: 12),
              Text(
                'اختر طريقة إغلاق التطبيق',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'كيف تريد إغلاق التطبيق؟',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
              SizedBox(height: 20),

              // خيار مسح البيانات والإغلاق
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.delete_sweep,
                            color: Colors.red[600], size: 24),
                        SizedBox(width: 8),
                        Text(
                          'مسح البيانات والإغلاق',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.red[700],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• سيتم مسح بيانات تسجيل الدخول المحفوظة',
                      style: TextStyle(fontSize: 13, color: Colors.red[600]),
                    ),
                    Text(
                      '• ستحتاج لتسجيل الدخول مرة أخرى',
                      style: TextStyle(fontSize: 13, color: Colors.red[600]),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 12),

              // خيار الإغلاق فقط
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.exit_to_app,
                            color: Colors.green[600], size: 24),
                        SizedBox(width: 8),
                        Text(
                          'الإغلاق فقط',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• ستبقى بيانات تسجيل الدخول محفوظة',
                      style: TextStyle(fontSize: 13, color: Colors.green[600]),
                    ),
                    Text(
                      '• يمكنك الدخول تلقائياً في المرة القادمة',
                      style: TextStyle(fontSize: 13, color: Colors.green[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(null); // إلغاء الإغلاق
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[600],
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop('close_only'); // إغلاق فقط
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                elevation: 2,
              ),
              child: Text(
                'إغلاق فقط',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop('clear_and_close'); // مسح والإغلاق
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                elevation: 2,
              ),
              child: Text(
                'مسح والإغلاق',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
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
