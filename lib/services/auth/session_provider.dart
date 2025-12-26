import 'package:flutter/widgets.dart';
import 'session_manager.dart';
import 'auth_context.dart';

class SessionProvider extends InheritedWidget {
  final SessionManager manager;
  final AuthContext? contextData;

  const SessionProvider(
      {super.key,
      required this.manager,
      required this.contextData,
      required super.child});

  static SessionProvider? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionProvider>();

  @override
  bool updateShouldNotify(SessionProvider oldWidget) =>
      oldWidget.contextData?.rawToken != contextData?.rawToken;
}
