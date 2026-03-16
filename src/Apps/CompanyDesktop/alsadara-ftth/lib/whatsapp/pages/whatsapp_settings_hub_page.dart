import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../pages/whatsapp_bulk_sender_page.dart';
import '../../ftth/whatsapp/whatsapp_bottom_window.dart';
import 'whatsapp_server_settings_page.dart';
import '../../pages/whatsapp_templates_page.dart';
import 'whatsapp_system_settings_page.dart';
import '../services/whatsapp_permissions_service.dart';
import '../../services/custom_auth_service.dart';
import '../../services/vps_auth_service.dart';

/// صفحة إعدادات الواتساب الموحدة - تصميم فخم وعصري
class WhatsAppSettingsHubPage extends StatefulWidget {
  const WhatsAppSettingsHubPage({super.key});

  @override
  State<WhatsAppSettingsHubPage> createState() =>
      _WhatsAppSettingsHubPageState();
}

class _WhatsAppSettingsHubPageState extends State<WhatsAppSettingsHubPage>
    with SingleTickerProviderStateMixin {
  UserWhatsAppCapabilities? _capabilities;
  bool _isLoading = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _loadCapabilities();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadCapabilities() async {
    final caps = await WhatsAppPermissionsService.getCurrentUserCapabilities();
    if (mounted) {
      setState(() {
        _capabilities = caps;
        _isLoading = false;
      });
      _animController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: _isLoading
            ? _buildLoadingState()
            : CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  _buildSliverAppBar(),
                  SliverToBoxAdapter(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // تحذير إذا لم تكن هناك أنظمة متاحة
                            if (_capabilities != null &&
                                !_capabilities!.hasAnySystem)
                              _buildNoSystemsWarning(),

                            // بطاقة واتساب ويب
                            if (_capabilities?.hasSystem(WhatsAppSystem.web) ??
                                true)
                              _buildPremiumSystemCard(
                                title: 'واتساب ويب',
                                subtitle: 'للرد على المحادثات',
                                description:
                                    'فتح واتساب ويب داخل التطبيق للرد على رسائل العملاء مباشرة',
                                icon: Icons.language_rounded,
                                gradientColors: const [
                                  Color(0xFF128C7E),
                                  Color(0xFF25D366)
                                ],
                                features: [
                                  'الرد على رسائل العملاء',
                                  'متابعة المحادثات',
                                  'إرسال ملفات ووسائط',
                                ],
                                onTap: () => _openWhatsAppWeb(context),
                                delay: 0,
                              ),

                            // بطاقة واتساب API
                            if (_capabilities?.hasSystem(WhatsAppSystem.api) ??
                                true)
                              _buildPremiumSystemCard(
                                title: 'واتساب API',
                                subtitle: 'Meta Business API',
                                description:
                                    'إعدادات WhatsApp Business API الرسمي من Meta للإرسال الجماعي',
                                icon: Icons.api_rounded,
                                gradientColors: const [
                                  Color(0xFF075E54),
                                  Color(0xFF128C7E)
                                ],
                                features: [
                                  'إرسال رسائل جماعية',
                                  'قوالب رسائل معتمدة',
                                  'تقارير الإرسال',
                                ],
                                isPremium: true,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const WhatsAppBulkSenderPage(),
                                  ),
                                ),
                                delay: 100,
                              ),

                            // بطاقة واتساب سيرفر
                            if (_capabilities
                                    ?.hasSystem(WhatsAppSystem.server) ??
                                true)
                              _buildPremiumSystemCard(
                                title: 'واتساب سيرفر',
                                subtitle: 'VPS Server',
                                description:
                                    'الاتصال بسيرفر الواتساب الخاص للإرسال التلقائي',
                                icon: Icons.dns_rounded,
                                gradientColors: const [
                                  Color(0xFF1E88E5),
                                  Color(0xFF42A5F5)
                                ],
                                features: [
                                  'إرسال تلقائي بدون API',
                                  'لا يحتاج موافقة Meta',
                                  'مرونة في الرسائل',
                                ],
                                isPremium: true,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => WhatsAppServerSettingsPage(
                                      tenantId:
                                          CustomAuthService().currentTenantId ??
                                              VpsAuthService.instance.currentCompanyId ??
                                              'default',
                                    ),
                                  ),
                                ),
                                delay: 200,
                              ),

                            // بطاقة النظام العادي
                            if (_capabilities
                                    ?.hasSystem(WhatsAppSystem.normal) ??
                                true)
                              _buildPremiumSystemCard(
                                title: 'النظام العادي',
                                subtitle: 'تطبيق الواتساب',
                                description:
                                    'إرسال الرسائل عبر تطبيق الواتساب المثبت على الجهاز',
                                icon: Icons.phone_android_rounded,
                                gradientColors: const [
                                  Color(0xFF25D366),
                                  Color(0xFF5EE896)
                                ],
                                features: [
                                  'إرسال يدوي سريع',
                                  'لا يحتاج إعدادات',
                                  'مناسب للتجديدات',
                                ],
                                onTap: () => _showNormalSystemInfo(context),
                                delay: 300,
                              ),

                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF25D366), Color(0xFF128C7E)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'جاري التحميل...',
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 100,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF25D366),
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF25D366),
                Color(0xFF128C7E),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 40, right: 60, left: 60),
              child: Text(
                'إعدادات الواتساب',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
      leading: IconButton(
        icon:
            const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        // زر نظام الواتساب
        if (_capabilities?.canEditTemplates ?? false)
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.tune_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            tooltip: 'نظام الواتساب',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const WhatsAppSystemSettingsPage()),
            ),
          ),
        // زر القوالب
        if (_capabilities?.canEditTemplates ?? false)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: ElevatedButton.icon(
              icon: const Icon(
                Icons.description_rounded,
                color: Color(0xFF7C3AED),
                size: 24,
              ),
              label: Text(
                'القوالب',
                style: GoogleFonts.cairo(
                  color: Color(0xFF7C3AED),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                elevation: 3,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const WhatsAppTemplatesPage()),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNoSystemsWarning() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.orange.shade400,
            Colors.deepOrange.shade500,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'لا توجد أنظمة واتساب متاحة',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'تواصل مع مدير النظام لتفعيل أنظمة الواتساب للشركة',
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.9),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumSystemCard({
    required String title,
    required String subtitle,
    required String description,
    required IconData icon,
    required List<Color> gradientColors,
    required List<String> features,
    required VoidCallback onTap,
    required int delay,
    bool isPremium = false,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: gradientColors[0].withOpacity(0.25),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradientColors,
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    style: GoogleFonts.cairo(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (isPremium) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFFD700),
                                          Color(0xFFFFA500)
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.star_rounded,
                                          color: Colors.white,
                                          size: 10,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Pro',
                                          style: GoogleFonts.cairo(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              subtitle,
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white.withOpacity(0.7),
                        size: 18,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: -30,
                  right: -30,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openWhatsAppWeb(BuildContext context) {
    Navigator.pop(context);
    Future.delayed(const Duration(milliseconds: 300), () {
      WhatsAppBottomWindow.showBottomWindow(context, '', '');
    });
  }

  void _showNormalSystemInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFF0FDF4)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF25D366), Color(0xFF5EE896)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF25D366).withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.phone_android_rounded,
                  color: Colors.white,
                  size: 52,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'النظام العادي',
                style: GoogleFonts.cairo(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF25D366),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'هذا النظام لا يحتاج إعدادات خاصة.\n\nعند إرسال رسالة، سيتم فتح تطبيق الواتساب المثبت على جهازك مباشرة مع النص والرقم جاهزين.',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  color: Colors.grey[700],
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'حسناً، فهمت',
                    style: GoogleFonts.cairo(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
