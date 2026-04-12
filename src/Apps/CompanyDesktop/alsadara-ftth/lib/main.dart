/// اسم الملف: الملف الرئيسي
/// وصف الملف: نقطة البداية الرئيسية لتطبيق السدارة
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:firebase_core/firebase_core.dart'; // تفعيل Firebase
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
// ✅ صفحات تسجيل دخول الشركات
import 'pages/login/premium_login_page.dart'; // ✨ صفحة تسجيل دخول فخمة ومتجاوبة
// 🔄 صفحة تسجيل الدخول الكلاسيكية
// جلسة FTTH الجديدة
import 'services/auth/session_manager.dart';
import 'services/auth/session_provider.dart';

import 'dart:async';
import 'widgets/permissions_gate.dart';
import 'widgets/app_lifecycle_manager.dart';
import 'widgets/window_close_handler_fixed.dart';
export 'widgets/window_close_handler_fixed.dart' show navigatorKey;
import 'services/notification_service.dart';
import 'services/location_foreground_service.dart';
import 'services/ticket_updates_service.dart';
import 'services/collection_tasks_polling_service.dart';
import 'services/badge_service.dart';
import 'services/responsive_text_service.dart'; // إضافة الخدمة الجديدة
import 'services/app_text_scale.dart';
import 'widgets/in_app_notification_overlay.dart';
import 'pages/settings_text_scale_page.dart';
import 'utils/app_typography.dart';
import 'theme/app_theme.dart';
import 'services/firebase_auth_service.dart'; // ✅ خدمة Firebase
import 'services/unified_auth_manager.dart'; // ✅ نظام مصادقة موحد
// ✅ خدمة VPS API
import 'services/security/error_reporter_service.dart'; // 📊 خدمة تقارير الأخطاء
import 'config/app_secrets.dart'; // 🔒 إدارة المفاتيح السرية
import 'services/logger_service.dart'; // 📝 خدمة التسجيل
import 'services/firebase_availability.dart'; // 🔥 التحقق من توفر Firebase
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🧹 مسح كل التوكنات والجلسات القديمة عند بدء التطبيق
  // يضمن أن كل تشغيل يبدأ بجلسة نظيفة 100%
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('token_expiry');
    await prefs.remove('refresh_expiry');
    await prefs.remove('agents_access_token');
    await prefs.remove('agents_refresh_token');
    await prefs.remove('agents_guest_token');
    await prefs.remove('agents_token_expiry');
    await prefs.remove('dual_auth_ftth_linked');
    await prefs.remove('dual_auth_ftth_username');
  } catch (_) {}

  // 🔒 تهيئة المفاتيح السرية من Environment Variables
  await AppSecrets.instance.initialize();
  AppSecrets.instance.warnIfInsecure();

  // 📊 تهيئة Error Reporter لتسجيل الأخطاء
  await ErrorReporterService.instance.initialize();

  // 🛡️ التقاط أخطاء Flutter تلقائياً (مع حماية من التكرار السريع الذي يجمّد التطبيق)
  FlutterError.onError = (FlutterErrorDetails details) {
    // حماية كاملة: لا نسمح لأي خطأ بالتسرب للـ debugger حتى لا يتجمد التطبيق
    try {
      ErrorReporterService.instance.captureFlutterError(details);
    } catch (_) {
      // تجاهل أخطاء التسجيل نفسها
    }
    // طباعة مختصرة بدل presentError الثقيلة التي تعيد رسم الخطأ وتسبب حلقة تجمد
    if (kDebugMode) {
      debugPrint('⚡ Flutter Error: ${details.exception}');
      debugPrint('📍 ${details.context}');
    }
  };

  // 🛡️ التقاط أخطاء Dart غير المعالجة (async errors etc.) لمنع تجمد التطبيق في الـ debugger
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      debugPrint('⚡ Unhandled Error');
    }
    try {
      ErrorReporterService.instance.reportError(
        error: error,
        stackTrace: stack,
        context: 'PlatformDispatcher.onError',
      );
    } catch (_) {}
    return true; // ← true يعني أنه تم معالجة الخطأ (لا تُوقف التطبيق)
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
    FirebaseAvailability.markInitialized(); // ✅ تسجيل نجاح التهيئة
    logSuccess('Firebase initialized', tag: 'Init');
    // تسجيل معالج رسائل الخلفية (يجب قبل استقبال أي رسالة في الخلفية)
    try {
      FirebaseMessaging.onBackgroundMessage(
          NotificationService.firebaseMessagingBackgroundHandler);
      logSuccess('تم تسجيل معالج رسائل الخلفية FCM', tag: 'FCM');
    } catch (e) {
      logWarning('تعذر تسجيل معالج الخلفية', tag: 'FCM');
    }
  } catch (e) {
    logFailure('فشل تهيئة Firebase (التطبيق سيعمل بدون Firebase)',
        tag: 'Init');
  }

  // تهيئة خدمة الإشعارات (محلية + FCM)
  try {
    await NotificationService.initialize();
    LocationForegroundService.init(); // تهيئة خدمة الموقع في الخلفية
    logSuccess('تم تهيئة خدمة الإشعارات', tag: 'Notifications');
    // تشغيل خدمة التذاكر الخلفية (Polling) لبيئة Windows فقط بدون انتظار
    TicketUpdatesService.instance.start();
    // تشغيل خدمة مراقبة مهام التحصيل المكتملة (Polling)
    CollectionTasksPollingService.instance.start();
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
    // الاشتراك في مهام التحصيل المكتملة لزيادة الشارة
    CollectionTasksPollingService.instance.completedTasksStream.listen((tasks) {
      if (tasks.isNotEmpty) {
        BadgeService.instance.setUnread(
          BadgeService.instance.unreadCount + tasks.length,
        );
      }
    });
  } catch (notificationError) {
    logWarning('فشل في تهيئة الإشعارات: $notificationError',
        tag: 'Notifications');
  }

  // تحميل متغيرات البيئة بشكل آمن
  try {
    await dotenv.load(fileName: ".env");
    logSuccess('تم تحميل متغيرات البيئة', tag: 'Init');
  } catch (e) {
    logWarning('فشل في تحميل متغيرات البيئة', tag: 'Init');
  }

  // تحميل الجلسة (إن وُجدت) مبكراً للاستفادة من سياق الهوية لاحقاً
  try {
    await SessionManager.instance.loadFromStorage();
    // تهيئة نظام المصادقة الموحد
    await UnifiedAuthManager.instance.initialize();
    logSuccess('تم تهيئة UnifiedAuthManager', tag: 'Auth');
  } catch (e) {
    // عدم إيقاف التطبيق إذا فشل التحميل
    logWarning('فشل تحميل الجلسة الأولية', tag: 'Auth');
  }

  // ✅ استعادة جلسة Firebase إن وجدت (فقط إذا كان Firebase متاحاً)
  if (FirebaseAvailability.isAvailable) {
    try {
      await FirebaseAuthService.restoreSession();
      logSuccess('تم استعادة جلسة Firebase', tag: 'Auth');
    } catch (e) {
      logDebug('لم يتم العثور على جلسة Firebase سابقة', tag: 'Auth');
    }
  }

  // ✅ لا نستعيد جلسة VPS تلقائياً - سيقوم المستخدم بتسجيل الدخول
  // هذا يضمن ظهور صفحة تسجيل الدخول دائماً

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

              return MaterialApp(
                  navigatorKey: navigatorKey, // إضافة المفتاح Global
                  debugShowCheckedModeBanner: false,
                  title: 'FTTH Project',
                  // تحديد مقياس النص لمنع تضخم الخطوط بسبب إعدادات حجم الخط في النظام
                  builder: (context, child) {
                    final mq = MediaQuery.of(context);
                    final systemScale = mq.textScaler.scale(1.0);
                    final bool isMobile = Platform.isAndroid || Platform.isIOS;
                    // على الموبايل نسمح بمقياس أكبر لتحسين القراءة
                    final double clampedScale = isMobile
                        ? (systemScale * 1.4).clamp(1.2, 1.6)
                        : systemScale.clamp(0.85, 1.0);
                    return InAppNotificationOverlay(
                      child: MediaQuery(
                        data: mq.copyWith(
                          textScaler: TextScaler.linear(clampedScale),
                        ),
                        child: child ?? const SizedBox.shrink(),
                      ),
                    );
                  },
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
                  locale: const Locale('ar'),
                  home: const AppInitializer(),
                  routes: {
                    '/settings/text-scale': (_) =>
                        const SettingsTextScalePage(),
                  },
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

    // تأخير مصغّر فقط لضمان اكتمال الـ frame الأول
    await Future.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      // تهيئة خدمة النصوص المتجاوبة
      ResponsiveTextService.instance.initialize(context);

      // ✅ الانتقال مباشرة لصفحة تسجيل دخول الشركات
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) {
            const loginPage = PremiumLoginPage();
            return permissionsGranted
                ? loginPage
                : PermissionsGate(child: loginPage);
          },
        ),
      );
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
