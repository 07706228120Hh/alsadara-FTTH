import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../providers/agent_auth_provider.dart';
import '../../services/agent_api_service.dart';

/// لوحة تحكم الوكيل - تصميم فخم ومتجاوب
class AgentDashboard extends StatefulWidget {
  const AgentDashboard({super.key});

  @override
  State<AgentDashboard> createState() => _AgentDashboardState();
}

class _AgentDashboardState extends State<AgentDashboard>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _isSidebarCollapsed = true;
  bool _isTransactionsExpanded = false;
  AgentAccountingSummaryData? _summary;
  AgentData? _agent;
  List<AgentTransactionData> _recentTransactions = [];

  late AnimationController _sidebarAnimController;
  late Animation<double> _sidebarAnim;

  // ألوان التدرج الفخمة للقائمة الجانبية
  static const _sidebarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0D47A1), // أزرق داكن جداً
      Color(0xFF1565C0), // أزرق داكن
      Color(0xFF0D2B56), // كحلي غامق
    ],
  );

  // ألوان التدرجات لبطاقات الإحصائيات
  static const List<List<Color>> _statGradients = [
    [Color(0xFF667eea), Color(0xFF764ba2)], // بنفسجي-أزرق
    [Color(0xFFf093fb), Color(0xFFf5576c)], // وردي-أحمر
    [Color(0xFF4facfe), Color(0xFF00f2fe)], // أزرق فاتح
    [Color(0xFFfa709a), Color(0xFFfee140)], // وردي-أصفر
  ];

  @override
  void initState() {
    super.initState();
    _sidebarAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _sidebarAnim = CurvedAnimation(
      parent: _sidebarAnimController,
      curve: Curves.easeInOutCubic,
    );
    // القائمة مخفية افتراضياً
    _sidebarAnimController.value = 1.0;
    _loadDashboardData();
  }

  @override
  void dispose() {
    _sidebarAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    final agentAuth = context.read<AgentAuthProvider>();
    _agent = agentAuth.agent;

    try {
      final summary = await agentAuth.getAccountingSummary();
      final transactions = await agentAuth.getTransactions(pageSize: 5);

      if (mounted) {
        setState(() {
          _summary = summary;
          _recentTransactions = transactions;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleSidebar() {
    setState(() {
      _isSidebarCollapsed = !_isSidebarCollapsed;
      if (_isSidebarCollapsed) {
        _sidebarAnimController.forward();
      } else {
        _sidebarAnimController.reverse();
      }
    });
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'صباح الخير';
    if (hour < 17) return 'مساء الخير';
    return 'مساء النور';
  }

  // ═══════════════════════════════════════════════════════════════
  // القائمة الجانبية
  // ═══════════════════════════════════════════════════════════════

  final List<_SidebarSection> _sections = [
    _SidebarSection(
      title: 'القائمة',
      items: [
        _MenuItem(
          title: 'الرئيسية',
          icon: Icons.dashboard_rounded,
          route: '/agent/home',
        ),
      ],
    ),
    _SidebarSection(
      title: 'الإدارة',
      items: [
        _MenuItem(
          title: 'سجل العمليات',
          icon: Icons.receipt_long_rounded,
          route: '/agent/transactions',
        ),
        _MenuItem(
          title: 'التقارير',
          icon: Icons.analytics_rounded,
          route: '/agent/reports',
        ),
        _MenuItem(
          title: 'الإعدادات',
          icon: Icons.settings_rounded,
          route: '/agent/settings',
        ),
      ],
    ),
  ];

  int get _flatMenuIndex {
    int idx = 0;
    for (final section in _sections) {
      for (final item in section.items) {
        if (idx == _selectedIndex) return idx;
        idx++;
      }
    }
    return 0;
  }

  String _getRouteForIndex(int index) {
    int idx = 0;
    for (final section in _sections) {
      for (final item in section.items) {
        if (idx == index) return item.route;
        idx++;
      }
    }
    return '/agent/home';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 900;
    final isMedium = screenWidth > 600;

    return Theme(
      data: AppTheme.agentTheme,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFFF0F2F5),
          body: Row(
            children: [
              if (isWide) _buildPremiumSidebar(),
              Expanded(
                child: Column(
                  children: [
                    _buildPremiumAppBar(isWide),
                    Expanded(
                      child: _isLoading
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    color: AppTheme.agentColor,
                                    strokeWidth: 3,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'جارٍ تحميل البيانات...',
                                    style: TextStyle(color: AppTheme.textGrey),
                                  ),
                                ],
                              ),
                            )
                          : _buildResponsiveContent(isWide, isMedium),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // bottomNavigationBar removed — الخدمات السريعة تكفي
          drawer: isWide ? null : SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: Drawer(child: _buildPremiumSidebar()),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // القائمة الجانبية الفخمة
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPremiumSidebar() {
    final isDrawer = MediaQuery.of(context).size.width <= 900;
    final expandedWidth = 260.0;
    final collapsedWidth = 78.0;
    final currentWidth = isDrawer ? double.infinity : (_isSidebarCollapsed ? collapsedWidth : expandedWidth);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      width: currentWidth,
      decoration: const BoxDecoration(
        gradient: _sidebarGradient,
        boxShadow: [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 20,
            offset: Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // ─── رأس القائمة مع معلومات الوكيل ───
          _buildSidebarHeader(),

          // ─── عناصر القائمة ───
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: _buildSidebarMenuItems(),
            ),
          ),

          // ─── زر طي / فتح ───
          _buildCollapseButton(),

          // ─── تسجيل خروج ───
          _buildLogoutButton(),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isSidebarCollapsed ? 8 : 20,
        vertical: 24,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: const Border(
          bottom: BorderSide(color: Color(0x33FFFFFF), width: 1),
        ),
      ),
      child: Column(
        children: [
          // صورة / أيقونة الوكيل مع حالة النشاط
          Stack(
            children: [
              Container(
                width: _isSidebarCollapsed ? 44 : 72,
                height: _isSidebarCollapsed ? 44 : 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    _isSidebarCollapsed ? 12 : 18,
                  ),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF42A5F5), Color(0xFF1565C0)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.storefront_rounded,
                  size: _isSidebarCollapsed ? 22 : 36,
                  color: Colors.white,
                ),
              ),
              // نقطة النشاط
              Positioned(
                bottom: 0,
                left: 0,
                child: Container(
                  width: _isSidebarCollapsed ? 12 : 16,
                  height: _isSidebarCollapsed ? 12 : 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF0D47A1),
                      width: 2.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!_isSidebarCollapsed) ...[
            const SizedBox(height: 14),
            Text(
              _agent?.name ?? 'الوكيل',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.tag_rounded,
                    color: Colors.white60,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _agent?.agentCode ?? '',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildSidebarMenuItems() {
    final widgets = <Widget>[];
    int flatIndex = 0;

    for (final section in _sections) {
      // عنوان القسم
      if (!_isSidebarCollapsed) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(right: 20, top: 16, bottom: 6),
            child: Text(
              section.title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
        );
      } else {
        widgets.add(const SizedBox(height: 12));
        widgets.add(
          Center(
            child: Container(
              width: 30,
              height: 1,
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
        );
        widgets.add(const SizedBox(height: 6));
      }

      // عناصر القسم
      for (final item in section.items) {
        final isSelected = _selectedIndex == flatIndex;
        final currentFlatIndex = flatIndex;
        widgets.add(_buildSidebarItem(item, isSelected, currentFlatIndex));
        flatIndex++;
      }
    }
    return widgets;
  }

  Widget _buildSidebarItem(_MenuItem item, bool isSelected, int index) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _isSidebarCollapsed ? 10 : 12,
        vertical: 2,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() => _selectedIndex = index);
            if (Scaffold.of(context).hasDrawer &&
                Scaffold.of(context).isDrawerOpen) {
              Navigator.pop(context);
            }
            context.go(item.route);
          },
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          splashColor: Colors.white.withValues(alpha: 0.15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: _isSidebarCollapsed ? 0 : 14,
              vertical: 11,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.transparent,
              border: isSelected
                  ? Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              mainAxisAlignment: _isSidebarCollapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                // شريط مضيء على الجانب
                if (isSelected && !_isSidebarCollapsed)
                  Container(
                    width: 3,
                    height: 22,
                    margin: const EdgeInsets.only(left: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF42A5F5),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF42A5F5).withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                Icon(
                  item.icon,
                  color: isSelected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.6),
                  size: _isSidebarCollapsed ? 22 : 20,
                ),
                if (!_isSidebarCollapsed) ...[
                  const SizedBox(width: 12),
                  Text(
                    item.title,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.7),
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 14,
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

  Widget _buildCollapseButton() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleSidebar,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Icon(
              _isSidebarCollapsed
                  ? Icons.keyboard_double_arrow_left
                  : Icons.keyboard_double_arrow_right,
              color: Colors.white54,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: _isSidebarCollapsed ? 10 : 14,
        vertical: 12,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await context.read<AgentAuthProvider>().logout();
            if (context.mounted) context.go('/');
          },
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.red.withValues(alpha: 0.15),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: _isSidebarCollapsed ? 0 : 14,
              vertical: 11,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: _isSidebarCollapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  Icons.logout_rounded,
                  color: Colors.red.shade300,
                  size: 20,
                ),
                if (!_isSidebarCollapsed) ...[
                  const SizedBox(width: 12),
                  Text(
                    'تسجيل الخروج',
                    style: TextStyle(color: Colors.red.shade300, fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // شريط التطبيق العلوي الفخم
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPremiumAppBar(bool isWide) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (!isWide)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded, color: AppTheme.textDark),
                onPressed: () {
                  setState(() => _isSidebarCollapsed = false);
                  Scaffold.of(ctx).openDrawer();
                },
              ),
            ),
          if (isWide)
            IconButton(
              icon: Icon(
                _isSidebarCollapsed
                    ? Icons.menu_open_rounded
                    : Icons.menu_rounded,
                color: AppTheme.textDark,
              ),
              onPressed: _toggleSidebar,
              tooltip: _isSidebarCollapsed ? 'فتح القائمة' : 'طي القائمة',
            ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'لوحة التحكم',
                style: TextStyle(
                  fontSize: isWide ? 20 : 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              Text(
                '${_getGreeting()} 👋',
                style: const TextStyle(fontSize: 12, color: AppTheme.textGrey),
              ),
            ],
          ),
          const Spacer(),
          // شارة الرصيد
          if (_agent != null)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? 16 : 10,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF43A047), Color(0xFF2E7D32)],
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_formatNumber(_agent!.netBalance)} د.ع',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textGrey),
            onPressed: _loadDashboardData,
            tooltip: 'تحديث',
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // المحتوى المتجاوب - يملأ الشاشة بالكامل
  // ═══════════════════════════════════════════════════════════════

  Widget _buildResponsiveContent(bool isWide, bool isMedium) {
    if (isWide) {
      return _buildDesktopLayout();
    }
    return _buildMobileLayout(isMedium);
  }

  /// تخطيط سطح المكتب - كل شيء ضمن الشاشة
  Widget _buildDesktopLayout() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // الصف الأول: الإحصائيات - 4 بطاقات
          _buildStatsRow(),
          const SizedBox(height: 24),
          // فاصل بصري
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '⚡ الخدمات السريعة',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
            ],
          ),
          const SizedBox(height: 16),
          // الصف الثاني: الخدمات السريعة - صف أفقي واحد
          _buildQuickServicesRow(),
          const SizedBox(height: 24),
          // زر آخر العمليات
          _buildTransactionsButton(),
        ],
      ),
    );
  }

  /// تخطيط الهاتف - scroll عمودي
  Widget _buildMobileLayout(bool isMedium) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildMobileStatsGrid(isMedium),
          const SizedBox(height: 24),
          // فاصل بصري
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '⚡ الخدمات السريعة',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
            ],
          ),
          const SizedBox(height: 16),
          _buildQuickServicesRow(),
          const SizedBox(height: 24),
          _buildTransactionsButton(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // بطاقات الإحصائيات بتدرجات لونية (سطح المكتب)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStatsRow() {
    final stats = _getStats();
    return SizedBox(
      height: 120,
      child: Row(
        children: List.generate(stats.length, (i) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i < stats.length - 1 ? 12 : 0),
              child: _buildGradientStatCard(stats[i], _statGradients[i]),
            ),
          );
        }),
      ),
    );
  }

  /// إحصائيات الهاتف - شبكة 2x2
  Widget _buildMobileStatsGrid(bool isMedium) {
    final stats = _getStats();
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 400;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMedium ? 4 : 2,
        childAspectRatio: isMedium ? 1.6 : (isSmall ? 3.2 : 3.0),
        crossAxisSpacing: isSmall ? 8 : 10,
        mainAxisSpacing: isSmall ? 8 : 10,
      ),
      itemCount: stats.length,
      itemBuilder: (context, i) =>
          _buildGradientStatCard(stats[i], _statGradients[i]),
    );
  }

  List<Map<String, dynamic>> _getStats() {
    return [
      {
        'title': 'إجمالي الشحن',
        'value': _formatNumber(
          _summary?.totalCharges ?? _agent?.totalCharges ?? 0,
        ),
        'unit': 'د.ع',
        'icon': Icons.trending_up_rounded,
      },
      {
        'title': 'إجمالي التسديد',
        'value': _formatNumber(
          _summary?.totalPayments ?? _agent?.totalPayments ?? 0,
        ),
        'unit': 'د.ع',
        'icon': Icons.trending_down_rounded,
      },
      {
        'title': 'الرصيد الصافي',
        'value': _formatNumber(_summary?.netBalance ?? _agent?.netBalance ?? 0),
        'unit': 'د.ع',
        'icon': Icons.account_balance_rounded,
      },
      {
        'title': 'العمليات',
        'value': (_summary?.transactionsCount ?? 0).toString(),
        'unit': 'عملية',
        'icon': Icons.receipt_long_rounded,
      },
    ];
  }

  Widget _buildGradientStatCard(Map<String, dynamic> stat, List<Color> colors) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: colors[0].withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // أيقونة خلفية مع توهج
            Positioned(
              left: -12,
              bottom: -12,
              child: Icon(
                stat['icon'] as IconData,
                size: 50,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    stat['icon'] as IconData,
                    color: Colors.white.withValues(alpha: 0.9),
                    size: 16,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stat['value'] as String,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Roboto',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stat['title'] as String,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // زر آخر العمليات
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTransactionsButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go('/agent/transactions'),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.agentColor.withValues(alpha: 0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.agentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: AppTheme.agentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'سجل العمليات',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              if (_recentTransactions.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.agentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_recentTransactions.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.agentColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Icon(
                Icons.arrow_back_ios_rounded,
                size: 16,
                color: AppTheme.agentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // الخدمات السريعة - صف أفقي واحد
  // ═══════════════════════════════════════════════════════════════

  Widget _buildQuickServicesRow() {
    final services = [
      _QuickService(
        'تفعيل مشترك',
        Icons.person_add_rounded,
        const Color(0xFF43A047),
        '/agent/activate',
      ),
      _QuickService(
        'شحن ماستر',
        Icons.credit_card_rounded,
        const Color(0xFF9C27B0),
        '/agent/master-recharge',
      ),
      _QuickService(
        'طلب رصيد',
        Icons.account_balance_wallet_rounded,
        const Color(0xFF1565C0),
        '/agent/balance-request',
      ),
      _QuickService(
        'سداد مديونية',
        Icons.payments_rounded,
        const Color(0xFFE65100),
        '/agent/debt-payment',
      ),
    ];

    return Row(
      children: services
          .map((s) => Expanded(child: _buildServiceButton(s)))
          .toList(),
    );
  }

  Widget _buildServiceButton(_QuickService service) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => context.go(service.route),
          borderRadius: BorderRadius.circular(16),
          hoverColor: service.color.withValues(alpha: 0.08),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  service.color.withValues(alpha: 0.08),
                  service.color.withValues(alpha: 0.03),
                ],
              ),
              border: Border.all(
                color: service.color.withValues(alpha: 0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: service.color.withValues(alpha: 0.1),
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
                    color: service.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(service.icon, color: service.color, size: 20),
                ),
                const SizedBox(height: 6),
                Text(
                  service.title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: service.color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // آخر العمليات - قابل للطي
  // ═══════════════════════════════════════════════════════════════

  Widget _buildCollapsibleTransactions({bool isMobile = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // العنوان - قابل للنقر
          Material(
            color: Colors.transparent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: InkWell(
              onTap: () => setState(
                () => _isTransactionsExpanded = !_isTransactionsExpanded,
              ),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppTheme.agentColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'آخر العمليات',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.agentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_recentTransactions.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.agentColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => context.go('/agent/transactions'),
                      icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                      label: const Text(
                        'عرض الكل',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _isTransactionsExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.textGrey,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // المحتوى القابل للطي
          if (_isTransactionsExpanded) ...[
            const Divider(height: 1, indent: 20, endIndent: 20),
            if (isMobile)
              _buildTransactionsList(isMobile: true)
            else
              Expanded(child: _buildTransactionsList()),
          ],
        ],
      ),
    );
  }

  Widget _buildTransactionsList({bool isMobile = false}) {
    if (_recentTransactions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_rounded,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            const Text(
              'لا توجد عمليات بعد',
              style: TextStyle(color: AppTheme.textGrey, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: isMobile,
      physics: isMobile ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _recentTransactions.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, index) =>
          _buildTransactionItem(_recentTransactions[index]),
    );
  }

  // ignore: unused_element
  Widget _buildRecentTransactionsCard({bool isMobile = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppTheme.agentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'آخر العمليات',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => context.go('/agent/transactions'),
                  icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                  label: const Text('عرض الكل', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
          const Divider(height: 24, indent: 20, endIndent: 20),
          // العمليات
          Expanded(
            flex: isMobile ? 0 : 1,
            child: _recentTransactions.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_long_rounded,
                            size: 48,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'لا توجد عمليات بعد',
                            style: TextStyle(
                              color: AppTheme.textGrey,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: isMobile,
                    physics: isMobile
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _recentTransactions.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 56),
                    itemBuilder: (context, index) {
                      final tx = _recentTransactions[index];
                      return _buildTransactionItem(tx);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(AgentTransactionData tx) {
    final isIncoming = tx.isIncoming;
    final color = isIncoming
        ? const Color(0xFF43A047)
        : const Color(0xFFE53935);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isIncoming ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description ?? tx.typeName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${tx.createdAt.day}/${tx.createdAt.month} - ${tx.createdAt.hour}:${tx.createdAt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: AppTheme.textGrey,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${isIncoming ? "+" : "-"} ${_formatNumber(tx.amount)}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // أدوات مساعدة
  // ═══════════════════════════════════════════════════════════════

  String _formatNumber(double number) {
    final intStr = number.toStringAsFixed(0);
    // إضافة فواصل الآلاف
    final result = StringBuffer();
    int count = 0;
    for (int i = intStr.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0 && intStr[i] != '-') {
        result.write(',');
      }
      result.write(intStr[i]);
      count++;
    }
    return result.toString().split('').reversed.join();
  }

  // ═══════════════════════════════════════════════════════════════
  // شريط التنقل السفلي للهاتف
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPremiumBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                0,
                Icons.dashboard_rounded,
                'الرئيسية',
                '/agent/home',
              ),
              _buildNavItem(
                1,
                Icons.person_add_rounded,
                'تفعيل',
                '/agent/activate',
              ),
              _buildNavItem(
                2,
                Icons.receipt_long_rounded,
                'العمليات',
                '/agent/transactions',
              ),
              _buildNavItem(
                4,
                Icons.settings_rounded,
                'الإعدادات',
                '/agent/settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, String route) {
    final isSelected = _selectedIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _selectedIndex = index);
          context.go(route);
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 16 : 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.agentColor.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? AppTheme.agentColor : AppTheme.textGrey,
                size: 22,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppTheme.agentColor : AppTheme.textGrey,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// نماذج البيانات المساعدة
// ═══════════════════════════════════════════════════════════════

class _SidebarSection {
  final String title;
  final List<_MenuItem> items;
  const _SidebarSection({required this.title, required this.items});
}

class _MenuItem {
  final String title;
  final IconData icon;
  final String route;
  const _MenuItem({
    required this.title,
    required this.icon,
    required this.route,
  });
}

class _QuickService {
  final String title;
  final IconData icon;
  final Color color;
  final String route;
  const _QuickService(this.title, this.icon, this.color, this.route);
}
