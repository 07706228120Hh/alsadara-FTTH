import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import '../widgets/landing_painters.dart';
import '../widgets/landing_widgets.dart';

/// الصفحة الرئيسية الفخمة (Landing Page)
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  // Controllers
  final ScrollController _scrollController = ScrollController();
  final PageController _servicesController = PageController(
    viewportFraction: 0.85,
  );
  final int _currentServiceIndex = 0;
  Timer? _autoScrollTimer;

  // Animation
  late AnimationController _particleController;
  late List<Particle> _particles;
  bool _isNavBarFloating = false;

  // بيانات الخدمات
  final List<_ServiceInfo> _services = [
    _ServiceInfo(
      icon: Icons.wifi_rounded,
      title: 'خدمات الإنترنت',
      description: 'اشتراك جديد • تجديد • ترقية الباقة • صيانة فورية',
      gradient: const [Color(0xFF667eea), Color(0xFF764ba2)],
      features: ['سرعات فائقة', 'دعم 24/7', 'تتبع مباشر'],
      route: '/citizen/internet',
    ),
    _ServiceInfo(
      icon: Icons.credit_card_rounded,
      title: 'ماستر كارد توصيل',
      description: 'طلب بطاقة جديدة • شحن رصيد • توصيل سريع لباب منزلك',
      gradient: const [Color(0xFFf093fb), Color(0xFFf5576c)],
      features: ['توصيل مجاني', 'بطاقات متنوعة', 'شحن فوري'],
      route: '/citizen/master',
    ),
    _ServiceInfo(
      icon: Icons.store_rounded,
      title: 'المتجر الإلكتروني',
      description: 'راوترات • إكسسوارات • أجهزة شبكات احترافية',
      gradient: const [Color(0xFF4facfe), Color(0xFF00f2fe)],
      features: ['منتجات أصلية', 'ضمان سنة', 'توصيل مجاني'],
      route: '/citizen/store',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _particles = generateParticles(40);
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
    _scrollController.addListener(_onScroll);
    _startAutoScroll();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    _servicesController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final shouldFloat = _scrollController.offset > 100;
    if (shouldFloat != _isNavBarFloating) {
      setState(() => _isNavBarFloating = shouldFloat);
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_servicesController.hasClients) {
        int nextPage = (_currentServiceIndex + 1) % _services.length;
        _servicesController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 800;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            // المحتوى الرئيسي
            SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  _buildHeroSection(context, isWide),
                  _buildStatsSection(context, isWide),
                  _buildServicesSection(context, isWide),
                  _buildFeaturesSection(context, isWide),
                  _buildTestimonialsSection(context, isWide),
                  _buildCTASection(context, isWide),
                  _buildFooter(context, isWide),
                ],
              ),
            ),
            // NavBar عائمة
            _buildStickyNavBar(context, isWide),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // NavBar عائمة مع Glassmorphism
  // ═══════════════════════════════════════════════════════════════
  Widget _buildStickyNavBar(BuildContext context, bool isWide) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.symmetric(
          horizontal: isWide ? 40 : 16,
          vertical: _isNavBarFloating ? 8 : 16,
        ),
        decoration: BoxDecoration(
          color: _isNavBarFloating
              ? const Color(0xFF0D1B2A).withValues(alpha: 0.85)
              : Colors.transparent,
          boxShadow: _isNavBarFloating
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                  ),
                ]
              : [],
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: _isNavBarFloating
                ? ImageFilter.blur(sigmaX: 15, sigmaY: 15)
                : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  // الشعار
                  _buildLogo(),
                  const Spacer(),
                  // الأزرار
                  if (isWide) ...[
                    _buildNavButton(
                      'إنشاء حساب',
                      Icons.person_add_rounded,
                      const Color(0xFF667eea),
                      () => context.go('/citizen/register'),
                    ),
                    const SizedBox(width: 8),
                    _buildNavButton(
                      'دخول وكيل',
                      Icons.support_agent_rounded,
                      const Color(0xFFFF9800),
                      () => context.go('/agent/login'),
                    ),
                    const SizedBox(width: 8),
                    _buildNavButton(
                      'دخول مواطن',
                      Icons.login_rounded,
                      const Color(0xFF4CAF50),
                      () => context.go('/citizen/login'),
                    ),
                  ] else
                    IconButton(
                      icon: const Icon(Icons.menu_rounded, color: Colors.white),
                      onPressed: () => _showMobileMenu(context),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF667eea).withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.wifi_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 10),
        const Text(
          'الصدارة',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildNavButton(
    String text,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMobileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a1a2e), Color(0xFF0D2137)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _buildMobileMenuBtn(
              ctx,
              'إنشاء حساب',
              Icons.person_add_rounded,
              const Color(0xFF667eea),
              '/citizen/register',
            ),
            const SizedBox(height: 10),
            _buildMobileMenuBtn(
              ctx,
              'دخول مواطن',
              Icons.login_rounded,
              const Color(0xFF4CAF50),
              '/citizen/login',
            ),
            const SizedBox(height: 10),
            _buildMobileMenuBtn(
              ctx,
              'دخول وكيل',
              Icons.support_agent_rounded,
              const Color(0xFFFF9800),
              '/agent/login',
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileMenuBtn(
    BuildContext ctx,
    String t,
    IconData ic,
    Color c,
    String r,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.pop(ctx);
          context.go(r);
        },
        icon: Icon(ic, size: 20),
        label: Text(t, style: const TextStyle(fontSize: 15)),
        style: ElevatedButton.styleFrom(
          backgroundColor: c,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Hero Section مع Particles + Typed Text
  // ═══════════════════════════════════════════════════════════════
  Widget _buildHeroSection(BuildContext context, bool isWide) {
    return SizedBox(
      height: isWide ? 700 : 650,
      child: Stack(
        children: [
          // خلفية الجسيمات
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _particleController,
              builder: (_, __) => CustomPaint(
                painter: ParticleBackgroundPainter(
                  progress: _particleController.value,
                  particles: _particles,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          // المحتوى
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 24),
                child: Column(
                  children: [
                    SizedBox(height: isWide ? 120 : 80),
                    if (isWide)
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: _buildHeroContent()),
                            const SizedBox(width: 40),
                            Expanded(child: _buildHeroVisual()),
                          ],
                        ),
                      )
                    else
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildHeroContent(),
                            const SizedBox(height: 30),
                            SizedBox(height: 200, child: _buildHeroVisual()),
                          ],
                        ),
                      ),
                    // سهم التمرير المتحرك
                    _buildScrollIndicator(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FadeInOnScroll(
          delay: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF667eea).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF667eea).withValues(alpha: 0.3),
              ),
            ),
            child: const Text(
              '✨ منصة الصدارة للخدمات الإلكترونية',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        TypedTextWidget(
          text: 'خدماتك الرقمية\nفي مكان واحد',
          style: const TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.3,
          ),
          charDuration: const Duration(milliseconds: 50),
        ),
        const SizedBox(height: 18),
        FadeInOnScroll(
          delay: const Duration(milliseconds: 1800),
          child: Text(
            'إنترنت • ماستر كارد • متجر إلكتروني • شحن أرصدة\nاشترك، جدد، وادفع بكل سهولة وأمان',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.7,
            ),
          ),
        ),
        const SizedBox(height: 28),
        FadeInOnScroll(
          delay: const Duration(milliseconds: 2200),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: () => context.go('/citizen/register'),
                icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                label: const Text('ابدأ الآن'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667eea),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 8,
                  shadowColor: const Color(0xFF667eea).withValues(alpha: 0.5),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/citizen/login'),
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('تسجيل الدخول'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroVisual() {
    final serviceIcons = [
      const _HeroServiceIcon(
        Icons.wifi_rounded,
        'إنترنت',
        Color(0xFF667eea),
        Color(0xFF764ba2),
      ),
      const _HeroServiceIcon(
        Icons.credit_card_rounded,
        'ماستر كارد',
        Color(0xFFf093fb),
        Color(0xFFf5576c),
      ),
      const _HeroServiceIcon(
        Icons.store_rounded,
        'المتجر',
        Color(0xFF4facfe),
        Color(0xFF00f2fe),
      ),
      const _HeroServiceIcon(
        Icons.account_balance_wallet_rounded,
        'شحن رصيد',
        Color(0xFF11998e),
        Color(0xFF38ef7d),
      ),
    ];

    return FadeInOnScroll(
      delay: const Duration(milliseconds: 800),
      slideOffset: const Offset(40, 0),
      child: SizedBox(
        width: 380,
        height: 380,
        child: AnimatedBuilder(
          animation: _particleController,
          builder: (context, _) {
            final t = _particleController.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                // الحلقات المدارية
                CustomPaint(
                  size: const Size(380, 380),
                  painter: _HeroOrbitalPainter(progress: t),
                ),
                // اللوغو المركزي
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF667eea).withValues(
                          alpha: 0.35 + 0.15 * math.sin(t * math.pi * 2),
                        ),
                        blurRadius: 25 + 8 * math.sin(t * math.pi * 2),
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.hub_rounded, color: Colors.white, size: 28),
                      Text(
                        'الصدارة',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                // أيقونات الخدمات الأربعة
                ...List.generate(serviceIcons.length, (i) {
                  final angle =
                      (t * math.pi * 2 * 0.15) +
                      (i * math.pi * 2 / serviceIcons.length);
                  final radius = 140.0;
                  final dx = radius * math.cos(angle);
                  final dy = radius * math.sin(angle);
                  final svc = serviceIcons[i];
                  return Transform.translate(
                    offset: Offset(dx, dy),
                    child: _buildFloatingServiceIcon(svc, t, i),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFloatingServiceIcon(_HeroServiceIcon svc, double t, int index) {
    final bob = math.sin(t * math.pi * 4 + index * 1.5) * 4;
    return Transform.translate(
      offset: Offset(0, bob),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [svc.color1, svc.color2],
          ),
          boxShadow: [
            BoxShadow(
              color: svc.color1.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(svc.icon, color: Colors.white, size: 24),
            const SizedBox(height: 3),
            Text(
              svc.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollIndicator() {
    return FadeInOnScroll(
      delay: const Duration(milliseconds: 3000),
      child: Column(
        children: [
          Text(
            'اكتشف المزيد',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.white.withValues(alpha: 0.5),
            size: 24,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // قسم الإحصائيات المتحركة
  // ═══════════════════════════════════════════════════════════════
  Widget _buildStatsSection(BuildContext context, bool isWide) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 16, vertical: 50),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D2137), Color(0xFF1E3A5F)],
        ),
      ),
      child: FadeInOnScroll(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 20,
          runSpacing: 16,
          children: const [
            StatCard(
              icon: Icons.people_rounded,
              value: 10000,
              suffix: '+',
              label: 'مشترك نشط',
              gradient: [Color(0xFF667eea), Color(0xFF764ba2)],
            ),
            StatCard(
              icon: Icons.location_city_rounded,
              value: 15,
              suffix: '+',
              label: 'مدينة مغطاة',
              gradient: [Color(0xFF4facfe), Color(0xFF00f2fe)],
            ),
            StatCard(
              icon: Icons.verified_rounded,
              value: 99,
              suffix: '%',
              label: 'وقت التشغيل',
              gradient: [Color(0xFF11998e), Color(0xFF38ef7d)],
            ),
            StatCard(
              icon: Icons.support_agent_rounded,
              value: 24,
              suffix: '/7',
              label: 'دعم متواصل',
              gradient: [Color(0xFFf093fb), Color(0xFFf5576c)],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // قسم الخدمات المحسن
  // ═══════════════════════════════════════════════════════════════
  Widget _buildServicesSection(BuildContext context, bool isWide) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 60, horizontal: isWide ? 80 : 20),
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          FadeInOnScroll(
            child: Column(
              children: [
                const Text(
                  'خدماتنا المميزة',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 60,
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'كل ما تحتاجه في مكان واحد',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          // شبكة البطاقات
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Wrap(
              spacing: 20,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              children: List.generate(_services.length, (index) {
                return FadeInOnScroll(
                  delay: Duration(milliseconds: 200 + index * 150),
                  slideOffset: const Offset(0, 40),
                  child: SizedBox(
                    width: isWide ? 400 : double.infinity,
                    child: LuxuryServiceCard(
                      icon: _services[index].icon,
                      title: _services[index].title,
                      description: _services[index].description,
                      gradient: _services[index].gradient,
                      features: _services[index].features,
                      route: _services[index].route,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // قسم المميزات مع Scroll Animations
  // ═══════════════════════════════════════════════════════════════
  Widget _buildFeaturesSection(BuildContext context, bool isWide) {
    final features = [
      _FeatureInfo(
        Icons.speed_rounded,
        'سرعة في الإنجاز',
        'خدماتك تصل بأسرع وقت',
      ),
      _FeatureInfo(
        Icons.security_rounded,
        'أمان عالي',
        'حماية بياناتك أولويتنا',
      ),
      _FeatureInfo(
        Icons.support_agent_rounded,
        'دعم متواصل',
        'فريق دعم على مدار الساعة',
      ),
      _FeatureInfo(
        Icons.location_on_rounded,
        'تتبع مباشر',
        'اعرف موقع الفني لحظة بلحظة',
      ),
      _FeatureInfo(
        Icons.payment_rounded,
        'دفع إلكتروني',
        'طرق دفع متعددة وآمنة',
      ),
      _FeatureInfo(
        Icons.phone_android_rounded,
        'منصة متعددة',
        'ويب وتطبيق موبايل',
      ),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 24, vertical: 70),
      color: Colors.white,
      child: Column(
        children: [
          FadeInOnScroll(
            child: Column(
              children: [
                const Text(
                  'لماذا منصة الصدارة؟',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 60,
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          Wrap(
            spacing: 32,
            runSpacing: 28,
            alignment: WrapAlignment.center,
            children: features.asMap().entries.map((entry) {
              return FadeInOnScroll(
                delay: Duration(milliseconds: entry.key * 120),
                child: _buildFeatureCard(entry.value),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(_FeatureInfo f) {
    return SizedBox(
      width: 170,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667eea), Color(0xFF764ba2)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667eea).withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(f.icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            f.title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Color(0xFF1E293B),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            f.desc,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // قسم آراء العملاء
  // ═══════════════════════════════════════════════════════════════
  Widget _buildTestimonialsSection(BuildContext context, bool isWide) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 16, vertical: 60),
      color: const Color(0xFFF1F5F9),
      child: Column(
        children: [
          FadeInOnScroll(
            child: Column(
              children: [
                const Text(
                  'ماذا يقول عملاؤنا؟',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 60,
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          FadeInOnScroll(
            delay: const Duration(milliseconds: 200),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: const [
                  TestimonialCard(
                    name: 'أحمد محمد',
                    role: 'مشترك منذ 2024',
                    quote:
                        'خدمة ممتازة وسرعة إنترنت رائعة. التطبيق سهل الاستخدام وفريق الدعم سريع الاستجابة.',
                    stars: 5,
                  ),
                  TestimonialCard(
                    name: 'فاطمة علي',
                    role: 'مشتركة منذ 2023',
                    quote:
                        'أفضل خدمة إنترنت تعاملت معها. التجديد والدفع أصبح سهلاً جداً من خلال المنصة.',
                    stars: 5,
                  ),
                  TestimonialCard(
                    name: 'علي حسين',
                    role: 'صاحب مكتب',
                    quote:
                        'سرعة الإنترنت مستقرة والأسعار منافسة. خدمة التوصيل سريعة وممتازة.',
                    stars: 4,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CTA Section محسن
  // ═══════════════════════════════════════════════════════════════
  Widget _buildCTASection(BuildContext context, bool isWide) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 24, vertical: 70),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
        ),
      ),
      child: FadeInOnScroll(
        child: Column(
          children: [
            const Text(
              'جاهز للبدء؟ 🚀',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'انضم إلى آلاف المشتركين واستمتع بخدماتنا المميزة',
              style: TextStyle(
                fontSize: 17,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: () => context.go('/citizen/register'),
                  icon: const Icon(Icons.person_add_rounded),
                  label: const Text('إنشاء حساب مجاني'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF667eea),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 8,
                    shadowColor: Colors.black.withValues(alpha: 0.2),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/citizen/login'),
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('تسجيل الدخول'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70, width: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Footer محسن
  // ═══════════════════════════════════════════════════════════════
  Widget _buildFooter(BuildContext context, bool isWide) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 24, vertical: 40),
      color: const Color(0xFF0D1B2A),
      child: Column(
        children: [
          if (isWide)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFooterCol('عن الشركة', [
                  'من نحن',
                  'رؤيتنا',
                  'فريق العمل',
                ]),
                _buildFooterCol('خدماتنا', [
                  'إنترنت منزلي',
                  'إنترنت أعمال',
                  'الدعم الفني',
                ]),
                _buildFooterCol('تواصل معنا', [
                  '📞 920012345',
                  '📧 info@sadara.iq',
                  '📍 العراق',
                ]),
                _buildFooterCol('تابعنا', [
                  '📘 Facebook',
                  '🐦 Twitter',
                  '📸 Instagram',
                ]),
              ],
            )
          else
            _buildFooterCol('تواصل معنا', [
              '📞 920012345',
              '📧 info@sadara.iq',
              '📍 العراق',
            ]),
          const SizedBox(height: 30),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 20),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            child: Text(
              '© 2026 منصة الصدارة. جميع الحقوق محفوظة',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterCol(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 14),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              item,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Data Models
// ═══════════════════════════════════════════════════════════════

class _ServiceInfo {
  final IconData icon;
  final String title;
  final String description;
  final List<Color> gradient;
  final List<String> features;
  final String route;

  _ServiceInfo({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradient,
    required this.features,
    required this.route,
  });
}

class _FeatureInfo {
  final IconData icon;
  final String title;
  final String desc;
  _FeatureInfo(this.icon, this.title, this.desc);
}

class _HeroServiceIcon {
  final IconData icon;
  final String label;
  final Color color1;
  final Color color2;
  const _HeroServiceIcon(this.icon, this.label, this.color1, this.color2);
}

/// رسام المدارات المتحركة حول اللوغو
class _HeroOrbitalPainter extends CustomPainter {
  final double progress;
  _HeroOrbitalPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final orbits = [
      _OrbitConfig(
        radius: 100,
        dotCount: 4,
        speed: 1.0,
        color: const Color(0xFF667eea),
      ),
      _OrbitConfig(
        radius: 130,
        dotCount: 6,
        speed: -0.7,
        color: const Color(0xFF764ba2),
      ),
      _OrbitConfig(
        radius: 155,
        dotCount: 3,
        speed: 0.5,
        color: const Color(0xFF4facfe),
      ),
    ];

    for (final orbit in orbits) {
      // الحلقة
      final ringPaint = Paint()
        ..color = orbit.color.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, orbit.radius, ringPaint);

      // النقاط المتوهجة
      for (int i = 0; i < orbit.dotCount; i++) {
        final angle =
            (progress * orbit.speed * math.pi * 2) +
            (i * 2 * math.pi / orbit.dotCount);
        final dotX = center.dx + orbit.radius * math.cos(angle);
        final dotY = center.dy + orbit.radius * math.sin(angle);
        final dotCenter = Offset(dotX, dotY);

        final glowPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              orbit.color.withValues(alpha: 0.5),
              orbit.color.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: dotCenter, radius: 12));
        canvas.drawCircle(dotCenter, 12, glowPaint);

        final dotPaint = Paint()
          ..color = orbit.color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(dotCenter, 3.5, dotPaint);
      }
    }

    // توهج مركزي
    final centerGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF667eea).withValues(alpha: 0.06),
          const Color(0xFF667eea).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 80));
    canvas.drawCircle(center, 80, centerGlow);
  }

  @override
  bool shouldRepaint(covariant _HeroOrbitalPainter old) =>
      old.progress != progress;
}

class _OrbitConfig {
  final double radius;
  final int dotCount;
  final double speed;
  final Color color;
  const _OrbitConfig({
    required this.radius,
    required this.dotCount,
    required this.speed,
    required this.color,
  });
}
