import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../permissions/permissions.dart';
import '../services/vps_auth_service.dart';
import 'login/premium_login_page.dart';

// استيراد الصفحات
import 'users_page_vps.dart';
import '../task/task_list_screen.dart';
import 'track_users_map_page.dart';
import 'hr_hub_page.dart';
import 'search_users_page.dart';
import 'super_admin/sadara_portal_page.dart';
import 'accounting/accounting_dashboard_page.dart';
import '../task/follow_up_page.dart';
import '../task/audit_dashboard_page.dart';
import 'my_dashboard_page.dart';

class ModernHomePage extends StatefulWidget {
  final String username;
  final String permissions;
  final String department;
  final String center;
  final String salary;
  final String? tenantId;
  final String? tenantCode;
  final bool isSuperAdminMode;

  const ModernHomePage({
    super.key,
    required this.username,
    required this.permissions,
    required this.department,
    required this.center,
    required this.salary,
    this.tenantId,
    this.tenantCode,
    this.isSuperAdminMode = false,
  });

  @override
  State<ModernHomePage> createState() => _ModernHomePageState();
}

class _ModernHomePageState extends State<ModernHomePage>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isSidebarExpanded = true;
  late AnimationController _animationController;

  // الألوان الفخمة
  final Color _primaryColor = const Color(0xFF0F172A); // Slate 900
  final Color _secondaryColor = const Color(0xFF1E293B); // Slate 800
  final Color _accentColor = const Color(0xFF38BDF8); // Cyan 400
  final Color _goldColor = const Color(0xFFF59E0B); // Amber 500
  final Color _surfaceColor = const Color(0xFFF8FAFC); // Slate 50

  late Timer _timeTimer;
  String _currentTime = '';
  String _currentDate = '';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _updateTime();
    _timeTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  @override
  void dispose() {
    _timeTimer.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _currentTime = DateFormat('hh:mm a', 'ar').format(now);
        _currentDate = DateFormat('EEEE، d MMMM yyyy', 'ar').format(now);
      });
    }
  }

  void _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.red),
            SizedBox(width: 10),
            Text('تسجيل الخروج', style: TextStyle(fontFamily: 'Cairo')),
          ],
        ),
        content: const Text('هل أنت متأكد من رغبتك في تسجيل الخروج؟',
            style: TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء',
                style: TextStyle(color: Colors.grey, fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد',
                style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await VpsAuthService.instance.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PremiumLoginPage()),
          (route) => false,
        );
      }
    }
  }

  // قائمة العناصر المتاحة بناءً على الصلاحيات
  List<_SidebarItem> _getAvailableItems() {
    final pm = PermissionManager.instance;
    final items = <_SidebarItem>[
      _SidebarItem(
          title: 'الرئيسية', icon: Icons.dashboard_rounded, id: 'dashboard'),
    ];

    if (pm.canView('agent')) {
      items.add(_SidebarItem(
          title: 'صفحة الوكيل',
          icon: Icons.support_agent_rounded,
          id: 'agent'));
    }
    if (pm.canView('tasks')) {
      items.add(_SidebarItem(
          title: 'المهام', icon: Icons.task_alt_rounded, id: 'tasks'));
    }
    if (pm.canView('zones')) {
      items.add(
          _SidebarItem(title: 'الزونات', icon: Icons.map_rounded, id: 'zones'));
    }
    if (pm.canView('hr')) {
      items.add(_SidebarItem(
          title: 'الموارد البشرية', icon: Icons.people_alt_rounded, id: 'hr'));
    }
    if (pm.canView('ai_search')) {
      items.add(_SidebarItem(
          title: 'البحث الذكي',
          icon: Icons.psychology_rounded,
          id: 'ai_search'));
    }
    if (pm.canView('sadara_portal')) {
      items.add(_SidebarItem(
          title: 'منصة الصدارة', icon: Icons.hub_rounded, id: 'sadara_portal'));
    }
    if (pm.canView('accounting')) {
      items.add(_SidebarItem(
          title: 'الحسابات',
          icon: Icons.account_balance_wallet_rounded,
          id: 'accounting'));
    }
    if (pm.canView('follow_up')) {
      items.add(_SidebarItem(
          title: 'المتابعة',
          icon: Icons.track_changes_rounded,
          id: 'follow_up'));
    }
    if (pm.canView('audit_dashboard')) {
      items.add(_SidebarItem(
          title: 'التدقيق',
          icon: Icons.analytics_rounded,
          id: 'audit_dashboard'));
    }
    if (pm.canView('my_dashboard')) {
      items.add(_SidebarItem(
          title: 'شاشتي', icon: Icons.person_pin_rounded, id: 'my_dashboard'));
    }

    return items;
  }

  Widget _getPageForId(String id) {
    switch (id) {
      case 'dashboard':
        return _buildDashboardContent();
      case 'agent':
        return UsersPageVPS(
          companyId: widget.tenantId ?? '',
          companyName: widget.department,
          permissions: const {'users': true},
        );
      case 'tasks':
        return TaskListScreen(
          username: widget.username,
          permissions: widget.permissions,
          department: widget.department,
          center: widget.center,
        );
      case 'zones':
        return const TrackUsersMapPage();
      case 'hr':
        return HrHubPage(
          username: widget.username,
          permissions: widget.permissions,
          department: widget.department,
          center: widget.center,
          tenantId: widget.tenantId,
          tenantCode: widget.tenantCode,
        );
      case 'ai_search':
        return const SearchUsersPage();
      case 'sadara_portal':
        return const SadaraPortalPage();
      case 'accounting':
        return const AccountingDashboardPage();
      case 'follow_up':
        return FollowUpPage(
          username: widget.username,
          permissions: widget.permissions,
          department: widget.department,
          center: widget.center,
        );
      case 'audit_dashboard':
        return AuditDashboardPage(
          username: widget.username,
          permissions: widget.permissions,
          department: widget.department,
          center: widget.center,
        );
      case 'my_dashboard':
        return MyDashboardPage(
          username: widget.username,
          permissions: widget.permissions,
          center: widget.center,
        );
      default:
        return _buildDashboardContent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _getAvailableItems();

    return Scaffold(
      backgroundColor: _surfaceColor,
      body: Row(
        children: [
          // الشريط الجانبي (Sidebar)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: _isSidebarExpanded ? 260 : 80,
            decoration: BoxDecoration(
              color: _primaryColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(2, 0),
                ),
              ],
            ),
            child: Column(
              children: [
                // ترويسة الشريط الجانبي
                Container(
                  height: 80,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: _isSidebarExpanded
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bolt_rounded, color: _accentColor, size: 32),
                      if (_isSidebarExpanded) ...[
                        const SizedBox(width: 12),
                        const Text(
                          'رمز الصدارة',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),

                // زر طي/توسيع الشريط
                InkWell(
                  onTap: () =>
                      setState(() => _isSidebarExpanded = !_isSidebarExpanded),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    child: Icon(
                      _isSidebarExpanded
                          ? Icons.chevron_right_rounded
                          : Icons.chevron_left_rounded,
                      color: Colors.white54,
                    ),
                  ),
                ),

                // قائمة العناصر
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final isSelected = _selectedIndex == index;

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(() => _selectedIndex = index),
                            borderRadius: BorderRadius.circular(12),
                            hoverColor: Colors.white.withOpacity(0.05),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _accentColor.withOpacity(0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? _accentColor.withOpacity(0.5)
                                      : Colors.transparent,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: _isSidebarExpanded
                                    ? MainAxisAlignment.start
                                    : MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    item.icon,
                                    color: isSelected
                                        ? _accentColor
                                        : Colors.white70,
                                    size: 24,
                                  ),
                                  if (_isSidebarExpanded) ...[
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.white70,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          fontFamily: 'Cairo',
                                          fontSize: 15,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // تذييل الشريط الجانبي (تسجيل الخروج)
                const Divider(color: Colors.white12, height: 1),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: InkWell(
                    onTap: _logout,
                    borderRadius: BorderRadius.circular(12),
                    hoverColor: Colors.red.withOpacity(0.1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 16),
                      child: Row(
                        mainAxisAlignment: _isSidebarExpanded
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.logout_rounded,
                              color: Colors.redAccent, size: 24),
                          if (_isSidebarExpanded) ...[
                            const SizedBox(width: 16),
                            const Text(
                              'تسجيل الخروج',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // منطقة المحتوى الرئيسية
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _surfaceColor,
                    const Color(0xFFE2E8F0), // Slate 200
                  ],
                ),
              ),
              child: Column(
                children: [
                  // الشريط العلوي (Header)
                  Container(
                    height: 80,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // عنوان الصفحة الحالية
                        Text(
                          items[_selectedIndex].title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const Spacer(),

                        // الوقت والتاريخ
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _currentTime,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF334155),
                              ),
                            ),
                            Text(
                              _currentDate,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 24),

                        // معلومات المستخدم
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _surfaceColor,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: _accentColor.withOpacity(0.2),
                                child: Text(
                                  widget.username.isNotEmpty
                                      ? widget.username[0]
                                      : 'U',
                                  style: TextStyle(
                                      color: _accentColor,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.username,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                  Text(
                                    widget.permissions,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // المحتوى المتغير
                  Expanded(
                    child: ClipRRect(
                      child: _getPageForId(items[_selectedIndex].id),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // محتوى لوحة التحكم (الرئيسية)
  Widget _buildDashboardContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // قسم الترحيب (Hero Section)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_primaryColor, _secondaryColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _primaryColor.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              children: [
                // تأثيرات بصرية في الخلفية
                Positioned(
                  right: -50,
                  top: -50,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.05),
                    ),
                  ),
                ),
                Positioned(
                  left: 100,
                  bottom: -80,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _accentColor.withOpacity(0.1),
                    ),
                  ),
                ),

                // المحتوى
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.waving_hand_rounded,
                              color: Colors.amber, size: 32),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'مرحباً بك مجدداً، ${widget.username}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'إليك نظرة عامة على أداء الشركة اليوم',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 16,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // معلومات إضافية
                    Row(
                      children: [
                        _buildHeroInfoChip(
                            Icons.business_rounded, 'القسم', widget.department),
                        const SizedBox(width: 24),
                        _buildHeroInfoChip(
                            Icons.location_on_rounded, 'المركز', widget.center),
                        const SizedBox(width: 24),
                        _buildHeroInfoChip(Icons.shield_rounded, 'الصلاحية',
                            widget.permissions),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // الإحصائيات السريعة
          const Text(
            'نظرة عامة',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                  child: _buildStatCard('المهام المنجزة', '124',
                      Icons.task_alt_rounded, Colors.green)),
              const SizedBox(width: 24),
              Expanded(
                  child: _buildStatCard('التذاكر المفتوحة', '18',
                      Icons.support_agent_rounded, Colors.orange)),
              const SizedBox(width: 24),
              Expanded(
                  child: _buildStatCard('الموظفين الحاضرين', '45',
                      Icons.people_alt_rounded, Colors.blue)),
              const SizedBox(width: 24),
              Expanded(
                  child: _buildStatCard('الإيرادات اليومية', 'IQD 2.5M',
                      Icons.account_balance_wallet_rounded, Colors.purple)),
            ],
          ),

          const SizedBox(height: 40),

          // الوصول السريع
          const Text(
            'الوصول السريع',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: _getAvailableItems()
                .where((item) => item.id != 'dashboard')
                .map((item) => _buildQuickActionCard(item))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroInfoChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _accentColor, size: 18),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
                fontFamily: 'Cairo'),
          ),
          Text(
            value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 14,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(_SidebarItem item) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          final index = _getAvailableItems().indexWhere((i) => i.id == item.id);
          if (index != -1) {
            setState(() => _selectedIndex = index);
          }
        },
        borderRadius: BorderRadius.circular(16),
        hoverColor: _accentColor.withOpacity(0.05),
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _surfaceColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, color: _primaryColor, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                item.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF1E293B),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem {
  final String title;
  final IconData icon;
  final String id;

  _SidebarItem({required this.title, required this.icon, required this.id});
}
