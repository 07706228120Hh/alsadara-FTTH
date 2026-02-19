import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';

/// لوحة تحكم المواطن - تصميم فخم مع قائمة جانبية قابلة للإخفاء
class CitizenDashboard extends StatefulWidget {
  const CitizenDashboard({super.key});

  @override
  State<CitizenDashboard> createState() => _CitizenDashboardState();
}

class _CitizenDashboardState extends State<CitizenDashboard>
    with TickerProviderStateMixin {
  // حالة القائمة الجانبية - مخفية افتراضياً
  bool _isSidebarExpanded = false;

  // Animation Controllers
  late AnimationController _sidebarController;
  late AnimationController _backgroundController;
  late Animation<double> _sidebarAnimation;

  @override
  void initState() {
    super.initState();

    _sidebarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _sidebarAnimation = CurvedAnimation(
      parent: _sidebarController,
      curve: Curves.easeInOutCubic,
    );

    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _sidebarController.dispose();
    _backgroundController.dispose();
    super.dispose();
  }

  void _toggleSidebar() {
    setState(() {
      _isSidebarExpanded = !_isSidebarExpanded;
      if (_isSidebarExpanded) {
        _sidebarController.forward();
      } else {
        _sidebarController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 900;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            _buildAnimatedBackground(),
            SafeArea(
              child: Row(
                children: [
                  if (isWide) _buildAnimatedSidebar(context),
                  Expanded(
                    child: Column(
                      children: [
                        _buildLuxuryHeader(context, isWide),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildWelcomeCard(context),
                                const SizedBox(height: 20),
                                _buildQuickServices(context, isWide),
                                const SizedBox(height: 20),
                                _buildRecentRequests(context),
                                const SizedBox(height: 20),
                                _buildCurrentSubscription(context),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: isWide ? null : _buildBottomNav(context),
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: _backgroundController,
      builder: (context, child) {
        return CustomPaint(
          painter: _LuxuryBackgroundPainter(
            progress: _backgroundController.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }

  Widget _buildAnimatedSidebar(BuildContext context) {
    return AnimatedBuilder(
      animation: _sidebarAnimation,
      builder: (context, child) {
        final width = 52.0 + (128.0 * _sidebarAnimation.value);
        return Container(
          width: width,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1a1a2e), Color(0xFF16213e), Color(0xFF0f3460)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(2, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildSidebarHeader(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    _buildAnimatedMenuItem(
                      Icons.home_rounded,
                      'الرئيسية',
                      true,
                      '/citizen/home',
                    ),
                    _buildAnimatedMenuItem(
                      Icons.wifi_rounded,
                      'الإنترنت',
                      false,
                      '/citizen/internet',
                    ),
                    _buildAnimatedMenuItem(
                      Icons.credit_card_rounded,
                      'الماستر',
                      false,
                      '/citizen/master',
                    ),
                    _buildAnimatedMenuItem(
                      Icons.store_rounded,
                      'المتجر',
                      false,
                      '/citizen/store',
                    ),
                    _buildAnimatedMenuItem(
                      Icons.receipt_long_rounded,
                      'طلباتي',
                      false,
                      '/citizen/requests',
                    ),
                    _buildAnimatedMenuItem(
                      Icons.location_on_rounded,
                      'التتبع',
                      false,
                      '/citizen/track',
                    ),
                    _buildAnimatedMenuItem(
                      Icons.support_agent_rounded,
                      'الدعم',
                      false,
                      '/citizen/support',
                    ),
                    _buildAnimatedMenuItem(
                      Icons.person_rounded,
                      'حسابي',
                      false,
                      '/citizen/profile',
                    ),
                  ],
                ),
              ),
              _buildLogoutButton(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.wifi, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  Widget _buildAnimatedMenuItem(
    IconData icon,
    String title,
    bool isActive,
    String route,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.go(route),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              gradient: isActive
                  ? const LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    )
                  : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: _sidebarAnimation.value > 0.5
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isActive ? Colors.white : Colors.white70,
                  size: 18,
                ),
                if (_sidebarAnimation.value > 0.5) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Opacity(
                      opacity: (_sidebarAnimation.value - 0.5) * 2,
                      child: Text(
                        title,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white70,
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Container(
      margin: const EdgeInsets.all(6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await context.read<AuthProvider>().logout();
            if (mounted) context.go('/');
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: _sidebarAnimation.value > 0.5
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                const Icon(Icons.logout_rounded, color: Colors.red, size: 18),
                if (_sidebarAnimation.value > 0.5) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Opacity(
                      opacity: (_sidebarAnimation.value - 0.5) * 2,
                      child: const Text(
                        'خروج',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLuxuryHeader(BuildContext context, bool isWide) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 20 : 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (isWide)
            _buildToggleButton()
          else
            IconButton(
              icon: const Icon(Icons.menu_rounded, size: 22),
              onPressed: () => _showMobileDrawer(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'لوحة التحكم',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1a1a2e),
                  ),
                ),
                Text(
                  'مرحباً بك في منصة الصدارة',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          _buildNotificationButton(),
          const SizedBox(width: 8),
          _buildProfileButton(isWide),
        ],
      ),
    );
  }

  Widget _buildToggleButton() {
    return GestureDetector(
      onTap: _toggleSidebar,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: _isSidebarExpanded
              ? const LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                )
              : null,
          color: _isSidebarExpanded ? null : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: AnimatedRotation(
          turns: _isSidebarExpanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 300),
          child: Icon(
            Icons.menu_open_rounded,
            color: _isSidebarExpanded ? Colors.white : Colors.grey[700],
            size: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        icon: Stack(
          children: [
            const Icon(
              Icons.notifications_outlined,
              color: Color(0xFF1a1a2e),
              size: 20,
            ),
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        onPressed: () => context.go('/citizen/notifications'),
        iconSize: 20,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }

  Widget _buildProfileButton(bool isWide) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        return GestureDetector(
          onTap: () => context.go('/citizen/profile'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF667eea).withOpacity(0.1),
                  const Color(0xFF764ba2).withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF667eea).withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      auth.citizen?.fullName.isNotEmpty == true
                          ? auth.citizen!.fullName[0]
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                if (isWide) ...[
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        auth.citizen?.fullName ?? 'مستخدم',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: Color(0xFF1a1a2e),
                        ),
                      ),
                      Text(
                        'مواطن',
                        style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMobileDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildMobileDrawer(context),
    );
  }

  Widget _buildMobileDrawer(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1a1a2e), Color(0xFF16213e), Color(0xFF0f3460)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.wifi, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                const Text(
                  'منصة الصدارة',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                _buildMobileMenuItem(
                  Icons.home_rounded,
                  'الرئيسية',
                  '/citizen/home',
                ),
                _buildMobileMenuItem(
                  Icons.wifi_rounded,
                  'خدمات الإنترنت',
                  '/citizen/internet',
                ),
                _buildMobileMenuItem(
                  Icons.credit_card_rounded,
                  'خدمة الماستر',
                  '/citizen/master',
                ),
                _buildMobileMenuItem(
                  Icons.store_rounded,
                  'المتجر',
                  '/citizen/store',
                ),
                _buildMobileMenuItem(
                  Icons.receipt_long_rounded,
                  'طلباتي',
                  '/citizen/requests',
                ),
                _buildMobileMenuItem(
                  Icons.location_on_rounded,
                  'تتبع الفني',
                  '/citizen/track',
                ),
                _buildMobileMenuItem(
                  Icons.support_agent_rounded,
                  'الدعم الفني',
                  '/citizen/support',
                ),
                _buildMobileMenuItem(
                  Icons.person_rounded,
                  'حسابي',
                  '/citizen/profile',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await context.read<AuthProvider>().logout();
                  if (mounted) context.go('/');
                },
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text(
                  'تسجيل الخروج',
                  style: TextStyle(fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.2),
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileMenuItem(IconData icon, String title, String route) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      leading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      trailing: const Icon(
        Icons.arrow_back_ios,
        color: Colors.white30,
        size: 12,
      ),
      onTap: () {
        Navigator.pop(context);
        context.go(route);
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _buildWelcomeCard(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF667eea).withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مرحباً، ${auth.citizen?.fullName ?? 'مستخدم'}! 👋',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ماذا تريد أن تفعل اليوم؟',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () => context.go('/citizen/internet'),
                      icon: const Icon(Icons.explore, size: 14),
                      label: const Text(
                        'استكشف الخدمات',
                        style: TextStyle(fontSize: 11),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF667eea),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.rocket_launch_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickServices(BuildContext context, bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.flash_on, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 8),
            const Text(
              'الوصول السريع',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1a1a2e),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: isWide ? 4 : 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: isWide ? 1.4 : 0.95,
          children: [
            _buildLuxuryServiceCard(
              context,
              icon: Icons.wifi_rounded,
              title: 'الإنترنت',
              subtitle: 'اشتراك • تجديد',
              gradient: const [Color(0xFF667eea), Color(0xFF764ba2)],
              onTap: () => context.go('/citizen/internet'),
            ),
            _buildLuxuryServiceCard(
              context,
              icon: Icons.credit_card_rounded,
              title: 'ماستر كارد',
              subtitle: 'طلب • شحن',
              gradient: const [Color(0xFFf093fb), Color(0xFFf5576c)],
              onTap: () => context.go('/citizen/master'),
            ),
            _buildLuxuryServiceCard(
              context,
              icon: Icons.shopping_cart_rounded,
              title: 'المتجر',
              subtitle: 'راوترات • أجهزة',
              gradient: const [Color(0xFF4facfe), Color(0xFF00f2fe)],
              onTap: () => context.go('/citizen/store'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLuxuryServiceCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withOpacity(0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradient),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Color(0xFF1a1a2e),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 9, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentRequests(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF667eea).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.history,
                      color: Color(0xFF667eea),
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'طلباتي الأخيرة',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1a1a2e),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => context.go('/citizen/requests'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(36, 28),
                ),
                child: const Text('الكل', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildRequestItem(
            icon: Icons.build_circle,
            title: 'طلب صيانة',
            status: 'قيد التنفيذ',
            gradient: const [Color(0xFFf5af19), Color(0xFFf12711)],
            date: '30 يناير',
          ),
          const Divider(height: 14),
          _buildRequestItem(
            icon: Icons.autorenew,
            title: 'تجديد اشتراك',
            status: 'مكتمل',
            gradient: const [Color(0xFF11998e), Color(0xFF38ef7d)],
            date: '25 يناير',
          ),
          const Divider(height: 14),
          _buildRequestItem(
            icon: Icons.shopping_bag,
            title: 'طلب من المتجر',
            status: 'قيد التوصيل',
            gradient: const [Color(0xFF4facfe), Color(0xFF00f2fe)],
            date: '22 يناير',
          ),
        ],
      ),
    );
  }

  Widget _buildRequestItem({
    required IconData icon,
    required String title,
    required String status,
    required List<Color> gradient,
    required String date,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: Colors.white, size: 14),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1a1a2e),
                  fontSize: 12,
                ),
              ),
              Text(
                date,
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                gradient[0].withOpacity(0.15),
                gradient[1].withOpacity(0.15),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            status,
            style: TextStyle(
              color: gradient[0],
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentSubscription(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF11998e).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.wifi_tethering,
                  color: Color(0xFF11998e),
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'اشتراكي الحالي',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1a1a2e),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.wifi, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'باقة 50 ميجا',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1a1a2e),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 10,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'ينتهي: 15 فبراير 2026',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => context.go('/citizen/internet/renewal'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF11998e),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('تجديد', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'المتبقي',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
              const Text(
                '15 يوم',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF11998e),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Container(
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(2.5),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerRight,
              widthFactor: 0.5,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF11998e), Color(0xFF38ef7d)],
                  ),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                Icons.home_rounded,
                'الرئيسية',
                true,
                '/citizen/home',
              ),
              _buildNavItem(
                Icons.wifi_rounded,
                'الإنترنت',
                false,
                '/citizen/internet',
              ),
              _buildNavItem(
                Icons.credit_card_rounded,
                'الماستر',
                false,
                '/citizen/master',
              ),
              _buildNavItem(
                Icons.store_rounded,
                'المتجر',
                false,
                '/citizen/store',
              ),
              _buildNavItem(
                Icons.person_rounded,
                'حسابي',
                false,
                '/citizen/profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    IconData icon,
    String label,
    bool isActive,
    String route,
  ) {
    return GestureDetector(
      onTap: () => context.go(route),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                )
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? Colors.white : Colors.grey[600],
              size: 20,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey[600],
                fontSize: 9,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LuxuryBackgroundPainter extends CustomPainter {
  final double progress;
  _LuxuryBackgroundPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFf5f7fa), Color(0xFFe8ecef), Color(0xFFf0f2f5)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final circlePaint = Paint()..style = PaintingStyle.fill;

    circlePaint.shader =
        RadialGradient(
          colors: [
            const Color(0xFF667eea).withOpacity(0.05),
            const Color(0xFF764ba2).withOpacity(0.01),
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.85, size.height * 0.15),
            radius: 120 + math.sin(progress * math.pi * 2) * 12,
          ),
        );
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.15),
      120 + math.sin(progress * math.pi * 2) * 12,
      circlePaint,
    );

    circlePaint.shader =
        RadialGradient(
          colors: [
            const Color(0xFFf093fb).withOpacity(0.03),
            const Color(0xFFf5576c).withOpacity(0.01),
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.15, size.height * 0.7),
            radius: 80 + math.cos(progress * math.pi * 2) * 8,
          ),
        );
    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.7),
      80 + math.cos(progress * math.pi * 2) * 8,
      circlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LuxuryBackgroundPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
