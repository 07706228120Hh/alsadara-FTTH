import 'dart:async';
import 'package:flutter/material.dart';
import '../services/unified_auth_manager.dart';

/// Widget لمراقبة حالة المصادقة وعرض إشعارات التوكن
class AuthStatusMonitor extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSessionExpired;
  final bool showNotifications;

  const AuthStatusMonitor({
    super.key,
    required this.child,
    this.onSessionExpired,
    this.showNotifications = true,
  });

  @override
  State<AuthStatusMonitor> createState() => _AuthStatusMonitorState();
}

class _AuthStatusMonitorState extends State<AuthStatusMonitor> {
  late StreamSubscription<AuthState> _authStateSubscription;
  late StreamSubscription<TokenStatus> _tokenStatusSubscription;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    // مراقبة حالة المصادقة
    _authStateSubscription = UnifiedAuthManager.instance.authStateStream.listen(
      (state) {
        if (mounted) {
          _handleAuthStateChange(state);
        }
      },
    );

    // مراقبة حالة التوكن
    _tokenStatusSubscription =
        UnifiedAuthManager.instance.tokenStatusStream.listen(
      (status) {
        if (mounted && widget.showNotifications) {
          _handleTokenStatusChange(status);
        }
      },
    );
  }

  void _handleAuthStateChange(AuthState state) {
    if (!widget.showNotifications) {
      return; // إخفاء جميع الإشعارات إذا كان showNotifications = false
    }

    switch (state) {
      case AuthState.unauthenticated:
        _showSessionExpiredDialog();
        break;
      case AuthState.error:
        _showErrorMessage('حدث خطأ في نظام المصادقة');
        break;
      case AuthState.authenticated:
        _showSuccessMessage('تم تسجيل الدخول بنجاح');
        break;
      default:
        break;
    }
  }

  void _handleTokenStatusChange(TokenStatus status) {
    switch (status) {
      case TokenStatus.expiringSoon:
        _showTokenExpiringWarning();
        break;
      case TokenStatus.refreshing:
        _showTokenRefreshingInfo();
        break;
      case TokenStatus.refreshed:
        _showTokenRefreshedSuccess();
        break;
      case TokenStatus.expired:
        _showTokenExpiredError();
        break;
      case TokenStatus.revoked:
        _showTokenRevokedError();
        break;
      default:
        break;
    }
  }

  void _showSessionExpiredDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: Colors.orange, size: 48),
        title: const Text('انتهت جلسة العمل'),
        content: const Text(
          'انتهت صلاحية جلستك، يرجى تسجيل الدخول مرة أخرى للمتابعة.',
          textAlign: TextAlign.center,
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onSessionExpired?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('تسجيل الدخول'),
          ),
        ],
      ),
    );
  }

  void _showTokenExpiringWarning() {
    _showSnackBar(
      '⏰ سيتم تجديد الجلسة قريباً',
      backgroundColor: Colors.orange.withValues(alpha: 0.9),
      duration: const Duration(seconds: 3),
    );
  }

  void _showTokenRefreshingInfo() {
    _showSnackBar(
      '🔄 جاري تجديد الجلسة...',
      backgroundColor: Colors.blue.withValues(alpha: 0.9),
      duration: const Duration(seconds: 2),
    );
  }

  void _showTokenRefreshedSuccess() {
    _showSnackBar(
      '✅ تم تجديد الجلسة بنجاح',
      backgroundColor: Colors.green.withValues(alpha: 0.9),
      duration: const Duration(seconds: 2),
    );
  }

  void _showTokenExpiredError() {
    _showSnackBar(
      '❌ انتهت صلاحية الجلسة',
      backgroundColor: Colors.red.withValues(alpha: 0.9),
      duration: const Duration(seconds: 4),
    );
  }

  void _showTokenRevokedError() {
    _showSnackBar(
      '🚪 تم إلغاء الجلسة',
      backgroundColor: Colors.red.withValues(alpha: 0.9),
      duration: const Duration(seconds: 3),
    );
  }

  void _showSuccessMessage(String message) {
    _showSnackBar(
      message,
      backgroundColor: Colors.green.withValues(alpha: 0.9),
      duration: const Duration(seconds: 2),
    );
  }

  void _showErrorMessage(String message) {
    _showSnackBar(
      message,
      backgroundColor: Colors.red.withValues(alpha: 0.9),
      duration: const Duration(seconds: 4),
    );
  }

  void _showSnackBar(
    String message, {
    Color? backgroundColor,
    Duration? duration,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: backgroundColor ?? Colors.blue.withValues(alpha: 0.9),
        duration: duration ?? const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  void dispose() {
    _authStateSubscription.cancel();
    _tokenStatusSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Widget لعرض معلومات التوكن (للتطوير والاختبار)
class TokenInfoWidget extends StatelessWidget {
  const TokenInfoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: UnifiedAuthManager.instance.authStateStream,
      builder: (context, snapshot) {
        final authManager = UnifiedAuthManager.instance;
        final tokenInfo = authManager.tokenInfo;
        final userSession = authManager.userSession;
        final authState = snapshot.data ?? AuthState.checking;

        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text(
                      'معلومات الجلسة',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    _buildStatusChip(authState),
                  ],
                ),
                const Divider(),
                if (userSession != null) ...[
                  _buildInfoRow('المستخدم', userSession.username),
                  _buildInfoRow(
                      'وقت التسجيل', _formatDateTime(userSession.loginTime)),
                  _buildInfoRow('مدة الجلسة',
                      _formatDuration(userSession.sessionDuration)),
                ],
                if (tokenInfo != null) ...[
                  const SizedBox(height: 8),
                  _buildInfoRow('حالة التوكن', _getTokenStatusText(tokenInfo)),
                  _buildInfoRow(
                      'ينتهي خلال', _formatDuration(tokenInfo.timeToExpiry)),
                  _buildInfoRow('تجديد ينتهي خلال',
                      _formatDuration(tokenInfo.timeToRefreshExpiry)),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _getTokenProgressValue(tokenInfo),
                    backgroundColor: Colors.grey.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _getTokenProgressColor(tokenInfo),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(AuthState state) {
    Color color;
    String text;
    IconData icon;

    switch (state) {
      case AuthState.authenticated:
        color = Colors.green;
        text = 'متصل';
        icon = Icons.check_circle;
        break;
      case AuthState.authenticating:
        color = Colors.blue;
        text = 'جاري التصل';
        icon = Icons.sync;
        break;
      case AuthState.refreshing:
        color = Colors.orange;
        text = 'جاري التجديد';
        icon = Icons.refresh;
        break;
      case AuthState.unauthenticated:
        color = Colors.red;
        text = 'غير متصل';
        icon = Icons.error;
        break;
      case AuthState.checking:
        color = Colors.grey;
        text = 'فحص';
        icon = Icons.help;
        break;
      case AuthState.error:
        color = Colors.red;
        text = 'خطأ';
        icon = Icons.error;
        break;
    }

    return Chip(
      avatar: Icon(icon, color: Colors.white, size: 16),
      label: Text(text, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const Text(': '),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  String _getTokenStatusText(TokenInfo tokenInfo) {
    if (tokenInfo.isExpired) return '❌ منتهي الصلاحية';
    if (tokenInfo.timeToExpiry.inMinutes < 5) return '⚠️ ينتهي قريباً';
    if (tokenInfo.timeToExpiry.inMinutes < 15) return '🟡 يحتاج تجديد';
    return '✅ صالح';
  }

  double _getTokenProgressValue(TokenInfo tokenInfo) {
    const totalMinutes = 60; // افتراض أن التوكن صالح لساعة
    final remainingMinutes = tokenInfo.timeToExpiry.inMinutes;
    return (remainingMinutes / totalMinutes).clamp(0.0, 1.0);
  }

  Color _getTokenProgressColor(TokenInfo tokenInfo) {
    final remainingMinutes = tokenInfo.timeToExpiry.inMinutes;
    if (remainingMinutes < 5) return Colors.red;
    if (remainingMinutes < 15) return Colors.orange;
    return Colors.green;
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative) return 'منتهي';

    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    if (hours > 0) {
      return '$hoursس $minutesد';
    } else {
      return '$minutesد';
    }
  }
}
