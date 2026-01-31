/// اسم الملف: الملف الرئيسي
/// وصف الملف: نقطة البداية الرئيسية لتطبيق السدارة
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:firebase_core/firebase_core.dart'; // تفعيل Firebase
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'pages/vps_tenant_login_page.dart'; // ✅ صفحة تسجيل دخول الشركات
// جلسة FTTH الجديدة
import 'services/auth/session_manager.dart';
import 'services/auth/session_provider.dart';
import 'ftth/widgets/pikachu_overlay.dart'; // بيكاتشو العائم
import 'dart:async';
import 'widgets/permissions_gate.dart';
import 'widgets/app_lifecycle_manager.dart';
import 'widgets/window_close_handler_fixed.dart';
import 'widgets/update_dialog.dart'; // ✅ نافذة التحديث التلقائي
export 'widgets/window_close_handler_fixed.dart' show navigatorKey;
import 'services/notification_service.dart';
import 'services/ticket_updates_service.dart';
import 'services/badge_service.dart';
import 'services/responsive_text_service.dart'; // إضافة الخدمة الجديدة
import 'services/app_text_scale.dart';
import 'pages/settings_text_scale_page.dart';
import 'utils/app_typography.dart';
import 'theme/app_theme.dart';
import 'services/firebase_auth_service.dart'; // ✅ خدمة Firebase
import 'services/unified_auth_manager.dart'; // ✅ نظام مصادقة موحد
// ✅ خدمة VPS API
import 'services/security/error_reporter_service.dart'; // 📊 خدمة تقارير الأخطاء
import 'config/app_secrets.dart'; // 🔒 إدارة المفاتيح السرية

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔒 تهيئة المفاتيح السرية من Environment Variables
  await AppSecrets.instance.initialize();
  AppSecrets.instance.warnIfInsecure();

  // 📊 تهيئة Error Reporter لتسجيل الأخطاء
  await ErrorReporterService.instance.initialize();

  // 🛡️ التقاط أخطاء Flutter تلقائياً
  FlutterError.onError = (FlutterErrorDetails details) {
    ErrorReporterService.instance.captureFlutterError(details);
    // الاستمرار بالسلوك الافتراضي في وضع Debug
    FlutterError.presentError(details);
  };

  // إعداد مدير النوافذ للديسكتوب
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      // فتح التطبيق مكبراً مع الحفاظ على شريط العنوان الافتراضي وأزرار النظام دائماً
      // ملاحظة: إزالة الشفافية مهم لأن الخلفية الشفافة تجعل أزرار الإغلاق لا تظهر إلا عند المرور بالماوس
      size: Size(1200, 800), // حجم مبدئي قبل التكبير
      center: true,
      // backgroundColor: Colors.transparent, // تم التعليق للتأكد من ظهور أزرار النظام دائماً
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      // تكبير النافذة لملء الشاشة مع بقاء أزرار التحكم في الأعلى
      // نفضل maximize بدلاً من fullScreen لإبقاء أزرار النظام متاحة
      if (await windowManager.isMaximized() == false) {
        await windowManager.maximize();
      }
      await windowManager.focus();
    });
  }

  // تحميل مقياس النص الداخلي للتطبيق
  await AppTextScale.instance.load();

  try {
    // تهيئة Firebase قبل أي استخدام لـ FCM
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase initialized');
    // تسجيل معالج رسائل الخلفية (يجب قبل استقبال أي رسالة في الخلفية)
    try {
      FirebaseMessaging.onBackgroundMessage(
          NotificationService.firebaseMessagingBackgroundHandler);
      print('✅ تم تسجيل معالج رسائل الخلفية FCM');
    } catch (e) {
      print('⚠️ تعذر تسجيل معالج الخلفية: $e');
    }
  } catch (e) {
    print('❌ فشل تهيئة Firebase: $e');
  }

  // تهيئة خدمة الإشعارات (محلية + FCM)
  try {
    await NotificationService.initialize();
    print('✅ تم تهيئة خدمة الإشعارات (محلي + FCM) بنجاح');
    // تشغيل خدمة التذاكر الخلفية (Polling) لبيئة Windows فقط بدون انتظار
    TicketUpdatesService.instance.start();
    // تهيئة شارة الأيقونة
    await BadgeService.instance.initialize();
    // الاشتراك في التذاكر الجديدة لزيادة الشارة
    TicketUpdatesService.instance.newTicketsStream.listen((tickets) {
      if (tickets.isNotEmpty) {
        BadgeService.instance.setUnread(
          BadgeService.instance.unreadCount + tickets.length,
        );
      }
    });
  } catch (notificationError) {
    print('⚠️ فشل في تهيئة الإشعارات: $notificationError');
  }

  // تحميل متغيرات البيئة بشكل آمن
  try {
    await dotenv.load(fileName: ".env");
    print('✅ تم تحميل متغيرات البيئة');
  } catch (e) {
    print('⚠️ فشل في تحميل متغيرات البيئة: $e');
  }

  // تحميل الجلسة (إن وُجدت) مبكراً للاستفادة من سياق الهوية لاحقاً
  try {
    await SessionManager.instance.loadFromStorage();
    // تهيئة نظام المصادقة الموحد
    await UnifiedAuthManager.instance.initialize();
    print('✅ تم تهيئة UnifiedAuthManager بنجاح');
  } catch (e) {
    // عدم إيقاف التطبيق إذا فشل التحميل
    // ignore: avoid_print
    print('⚠️ فشل تحميل الجلسة الأولية: $e');
  }

  // ✅ استعادة جلسة Firebase إن وجدت
  try {
    await FirebaseAuthService.restoreSession();
    print('✅ تم استعادة جلسة Firebase');
  } catch (e) {
    print('⚠️ لم يتم العثور على جلسة Firebase سابقة: $e');
  }

  // ✅ لا نستعيد جلسة VPS تلقائياً - سيقوم المستخدم بتسجيل الدخول
  // هذا يضمن ظهور صفحة تسجيل الدخول دائماً
  /*
  if (DataSourceConfig.useVpsApi) {
    try {
      final restored = await VpsAuthService.instance.restoreSession();
      if (restored) {
        print('✅ تم استعادة جلسة VPS API');
      }
    } catch (e) {
      print('⚠️ لم يتم العثور على جلسة VPS سابقة: $e');
    }
  }
  */

  runApp(WindowCloseHandlerFixed(
    child: const SessionBootstrap(child: MyApp()),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // إعداد مدير دورة حياة التطبيق مع إدارة السيرفر
    return AppLifecycleManager(
      child: ScreenUtilInit(
        // تحديد حجم مرجعي مناسب لجميع الأجهزة
        designSize: Size(375, 812), // iPhone X size as base
        minTextAdapt: true,
        splitScreenMode: true,
        useInheritedMediaQuery: true,
        builder: (context, child) {
          return ValueListenableBuilder<double>(
            valueListenable: AppTextScale.instance.notifier,
            builder: (context, scale, _) {
              final s = scale; // 0.8 .. 1.3
              // تحديد معامل إضافي حسب نوع الجهاز (اختياري لطيف)
              final width = MediaQuery.of(context).size.width;
              double deviceScale; // يجعل الحاسوب أصغر قليلاً
              if (width >= 1200) {
                deviceScale = 0.90; // شاشات مكتبية كبيرة
              } else if (width >= 900) {
                deviceScale = 0.95; // لابتوب/ديسكتوب متوسط
              } else if (width >= 600) {
                deviceScale = 1.0; // تابلت
              } else {
                deviceScale = 1.0; // موبايل
              }

              final overallScale = s * deviceScale; // المقياس النهائي

              return PikachuMouseTracker(
                child: MaterialApp(
                  navigatorKey: navigatorKey, // إضافة المفتاح Global
                  debugShowCheckedModeBanner: false,
                  title: 'FTTH Project',
                  theme: AppTheme.lightTheme.copyWith(
                    // دمج نظام القياسات الطباعية الحالي
                    extensions: [
                      AppTypography.build(overallScale, fontFamily: 'Cairo'),
                    ],
                  ),
                  darkTheme: AppTheme.darkTheme.copyWith(
                    extensions: [
                      AppTypography.build(overallScale, fontFamily: 'Cairo'),
                    ],
                  ),
                  // 🎨 فرض الثيم الفاتح دائماً لضمان أفضل مظهر
                  themeMode: ThemeMode.light,
                  // تمكين دعم اللغات والتعريب (العربية)
                  localizationsDelegates: [
                    // حزم التعريب الأساسية لـ Flutter
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: const [
                    Locale('ar'),
                    Locale('en'),
                  ],
                  home: const AppInitializer(),
                  routes: {
                    '/settings/text-scale': (_) =>
                        const SettingsTextScalePage(),
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// غلاف يوفر SessionProvider محدث باستمرار فوق الشجرة.
class SessionBootstrap extends StatefulWidget {
  final Widget child;
  const SessionBootstrap({super.key, required this.child});

  @override
  State<SessionBootstrap> createState() => _SessionBootstrapState();
}

class _SessionBootstrapState extends State<SessionBootstrap> {
  final _manager = SessionManager.instance;
  late StreamSubscription _sub;
  @override
  void initState() {
    super.initState();
    // الاشتراك للتحديث (نستخدم setState لإعادة بناء SessionProvider)
    _sub = _manager.states.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SessionProvider(
      manager: _manager,
      contextData: _manager.context,
      child: widget.child,
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final prefs = await SharedPreferences.getInstance();
    final permissionsGranted = prefs.getBool('permissions_granted') ?? false;

    // تأخير بسيط للسماح للشاشة بالتحميل
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      // تهيئة خدمة النصوص المتجاوبة
      ResponsiveTextService.instance.initialize(context);

      // ✅ فحص التحديثات عند بدء التطبيق
      _checkForUpdates();

      // ✅ الانتقال مباشرة لصفحة تسجيل دخول الشركات
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) {
            // تهيئة بيكاتشو العائم بعد بناء الصفحة الجديدة
            WidgetsBinding.instance.addPostFrameCallback((_) {
              PikachuOverlay.init(context);
            });

            // الذهاب إلى صفحة تسجيل دخول الشركات
            const loginPage = VpsTenantLoginPage();

            return permissionsGranted
                ? loginPage
                : PermissionsGate(child: loginPage);
          },
        ),
      );
    }
  }

  /// فحص التحديثات في الخلفية
  Future<void> _checkForUpdates() async {
    // تأخير بسيط لضمان تحميل الواجهة
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      await UpdateManager.checkAndShowUpdateDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
