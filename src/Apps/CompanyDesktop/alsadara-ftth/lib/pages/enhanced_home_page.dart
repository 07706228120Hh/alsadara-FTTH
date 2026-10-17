/// اسم الصفحة: الصفحة الرئيسية المحسنة
/// وصف الصفحة: الصفحة الرئيسية المحسنة مع ميزات إضافية
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import '../services/unified_auth_manager.dart';
import '../widgets/auth_status_monitor.dart';
import 'login/premium_login_page.dart';
import '../permissions/permissions.dart';
import '../frontend/tokens/sd_colors.dart' show SdColors;
import '../frontend/components/sd_app_bar.dart';

/// صفحة رئيسية محسنة مع نظام المصادقة الموحد
class EnhancedHomePage extends StatefulWidget {
  final String username;
  final String permissions;
  final String department;
  final String salary;
  final String center;
  const EnhancedHomePage({
    super.key,
    required this.username,
    required this.permissions,
    required this.department,
    required this.salary,
    required this.center,
  });

  @override
  State<EnhancedHomePage> createState() => _EnhancedHomePageState();
}

class _EnhancedHomePageState extends State<EnhancedHomePage> {
  bool _showTokenInfo = false;

  @override
  Widget build(BuildContext context) {
    return AuthStatusMonitor(
      onSessionExpired: _handleSessionExpired,
      showNotifications: true,
      child: Scaffold(
        appBar: SdAppBar(title: 'الصفحة الرئيسية المحسنة', actions: [
            // زر عرض معلومات التوكن (للتطوير)
            if (_showTokenInfo)
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () =>
                    setState(() => _showTokenInfo = !_showTokenInfo),
                tooltip: 'معلومات التوكن',
              ),

            // زر الإعدادات
            PopupMenuButton<String>(
              onSelected: _handleMenuSelection,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'token_info',
                  child: ListTile(
                    leading: Icon(Icons.info),
                    title: Text('معلومات الجلسة'),
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'refresh_token',
                  child: ListTile(
                    leading: Icon(Icons.refresh),
                    title: Text('تجديد الجلسة'),
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    leading: Icon(Icons.logout, color: SdColors.danger),
                    title: Text('تسجيل الخروج',
                        style: TextStyle(color: SdColors.danger)),
                    dense: true,
                  ),
                ),
              ],
            ),
          ]),
        body: Column(
          children: [
            // معلومات التوكن (قابلة للإخفاء)
            if (_showTokenInfo) const TokenInfoWidget(),

            // المحتوى الرئيسي
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // بطاقة المستخدم
                    _buildUserCard(),

                    const SizedBox(height: 20),

                    // حالة الاتصال
                    _buildConnectionStatusCard(),

                    const SizedBox(height: 20),

                    // قائمة الصفحات المتاحة
                    _buildPagesGrid(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: SdColors.info,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مرحباً ${widget.username}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${widget.department} - ${widget.permissions}',
                      style: const TextStyle(
                        color: SdColors.faint,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildUserInfoItem('المركز', widget.center),
                if (widget.salary.isNotEmpty)
                  _buildUserInfoItem('الراتب', widget.salary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfoItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: SdColors.faint,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionStatusCard() {
    return StreamBuilder<AuthState>(
      stream: UnifiedAuthManager.instance.authStateStream,
      builder: (context, snapshot) {
        final authState = snapshot.data ?? AuthState.checking;
        final tokenInfo = UnifiedAuthManager.instance.tokenInfo;

        Color statusColor;
        String statusText;
        IconData statusIcon;

        switch (authState) {
          case AuthState.authenticated:
            statusColor = SdColors.success;
            statusText = 'متصل';
            statusIcon = Icons.check_circle;
            break;
          case AuthState.refreshing:
            statusColor = SdColors.warning;
            statusText = 'جاري التجديد';
            statusIcon = Icons.refresh;
            break;
          default:
            statusColor = SdColors.danger;
            statusText = 'غير متصل';
            statusIcon = Icons.error;
        }

        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 24),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'حالة الاتصال: $statusText',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                    if (tokenInfo != null)
                      Text(
                        'ينتهي خلال: ${_formatDuration(tokenInfo.timeToExpiry)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: SdColors.faint,
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                if (authState == AuthState.refreshing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPagesGrid() {
    // V2: بناء قائمة الصفحات المتاحة من PermissionManager فقط
    final pm = PermissionManager.instance;
    final allPerms = <String, bool>{};
    for (final entry in pm.firstSystemPermissions.entries) {
      allPerms[entry.key] = entry.value['view'] == true;
    }
    for (final entry in pm.secondSystemPermissions.entries) {
      allPerms[entry.key] = entry.value['view'] == true;
    }
    final availablePages = allPerms.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الصفحات المتاحة',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
          ),
          itemCount: availablePages.length,
          itemBuilder: (context, index) {
            final pageName = availablePages[index];
            return _buildPageCard(pageName);
          },
        ),
      ],
    );
  }

  Widget _buildPageCard(String pageName) {
    IconData icon;
    String title;
    Color color;

    switch (pageName) {
      case 'home':
        icon = Icons.home;
        title = 'الرئيسية';
        color = SdColors.info;
        break;
      case 'home_page1':
        icon = Icons.dashboard;
        title = 'لوحة التحكم';
        color = SdColors.success;
        break;
      case 'home_page_tasks':
        icon = Icons.task_alt;
        title = 'المهام';
        color = SdColors.warning;
        break;
      case 'home_page2':
        icon = Icons.analytics;
        title = 'التحليلات';
        color = SdColors.platformBase;
        break;
      default:
        icon = Icons.pages;
        title = pageName;
        color = SdColors.faint;
    }

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () => _navigateToPage(pageName),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleMenuSelection(String value) async {
    switch (value) {
      case 'token_info':
        setState(() => _showTokenInfo = !_showTokenInfo);
        break;
      case 'refresh_token':
        await _refreshToken();
        break;
      case 'logout':
        await _logout();
        break;
    }
  }

  Future<void> _refreshToken() async {
    try {
      final token = await UnifiedAuthManager.instance.getValidAccessToken();
      if (token != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم تجديد الجلسة بنجاح'),
              backgroundColor: SdColors.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل تجديد الجلسة'),
            backgroundColor: SdColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: SdColors.danger),
            child: const Text('تسجيل الخروج',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await UnifiedAuthManager.instance.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const PremiumLoginPage()),
          (route) => false,
        );
      }
    }
  }

  void _handleSessionExpired() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const PremiumLoginPage()),
      (route) => false,
    );
  }

  void _navigateToPage(String pageName) {
    // هنا يمكن إضافة التنقل للصفحات المختلفة
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('الانتقال إلى: $pageName')),
    );
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
