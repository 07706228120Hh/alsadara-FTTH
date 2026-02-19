import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/agent_auth_provider.dart';
import 'providers/theme_provider.dart';
import 'config/router.dart';
import 'config/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthProvider _authProvider;
  late final AgentAuthProvider _agentAuthProvider;
  late final ThemeProvider _themeProvider;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _agentAuthProvider = AgentAuthProvider();
    _themeProvider = ThemeProvider();

    // إنشاء الراوتر مع ربط حالة المصادقة
    _router = createRouter(
      authProvider: _authProvider,
      agentAuthProvider: _agentAuthProvider,
    );

    // تهيئة استعادة الجلسة بالتوازي
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    await Future.wait([
      _authProvider.initialize(),
      _agentAuthProvider.initialize(),
    ]);
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _agentAuthProvider),
        ChangeNotifierProvider.value(value: _themeProvider),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp.router(
            title: 'منصة الصدارة',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            routerConfig: _router,
          );
        },
      ),
    );
  }
}
