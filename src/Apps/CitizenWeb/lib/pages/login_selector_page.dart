import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../config/app_theme.dart';

/// صفحة اختيار نوع المستخدم (مواطن / وكيل)
/// User Type Selection Page (Citizen / Agent)
class LoginSelectorPage extends StatelessWidget {
  const LoginSelectorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 800;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
          child: Stack(
            children: [
              // Background Pattern
              Positioned.fill(
                child: CustomPaint(painter: _BackgroundPatternPainter()),
              ),

              // Content
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Back Button
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            onPressed: () => context.go('/'),
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Logo
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Icon(
                            Icons.wifi,
                            size: 60,
                            color: Colors.white,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Title
                        const Text(
                          'منصة الصدارة',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          'اختر نوع الحساب للمتابعة',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 18,
                          ),
                        ),

                        const SizedBox(height: 48),

                        // Selection Cards
                        isWide
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildSelectionCard(
                                    context,
                                    icon: Icons.person,
                                    title: 'أنا مواطن',
                                    subtitle: 'تسجيل دخول أو إنشاء حساب جديد',
                                    description:
                                        'للاستفادة من خدمات الإنترنت، الماستر كارد، والمتجر الإلكتروني',
                                    color: AppTheme.internetColor,
                                    onTap: () => context.go('/citizen/login'),
                                  ),
                                  const SizedBox(width: 24),
                                  _buildSelectionCard(
                                    context,
                                    icon: Icons.storefront,
                                    title: 'أنا وكيل',
                                    subtitle: 'تسجيل دخول الوكلاء',
                                    description:
                                        'لإدارة الرصيد، تفعيل المشتركين، ومتابعة المعاملات',
                                    color: AppTheme.agentColor,
                                    onTap: () => context.go('/agent/login'),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  _buildSelectionCard(
                                    context,
                                    icon: Icons.person,
                                    title: 'أنا مواطن',
                                    subtitle: 'تسجيل دخول أو إنشاء حساب جديد',
                                    description:
                                        'للاستفادة من خدمات الإنترنت، الماستر كارد، والمتجر الإلكتروني',
                                    color: AppTheme.internetColor,
                                    onTap: () => context.go('/citizen/login'),
                                    fullWidth: true,
                                  ),
                                  const SizedBox(height: 20),
                                  _buildSelectionCard(
                                    context,
                                    icon: Icons.storefront,
                                    title: 'أنا وكيل',
                                    subtitle: 'تسجيل دخول الوكلاء',
                                    description:
                                        'لإدارة الرصيد، تفعيل المشتركين، ومتابعة المعاملات',
                                    color: AppTheme.agentColor,
                                    onTap: () => context.go('/agent/login'),
                                    fullWidth: true,
                                  ),
                                ],
                              ),

                        const SizedBox(height: 40),

                        // Help Link
                        TextButton.icon(
                          onPressed: () {
                            // TODO: Open help page
                          },
                          icon: const Icon(
                            Icons.help_outline,
                            color: Colors.white70,
                          ),
                          label: const Text(
                            'تحتاج مساعدة؟',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildSelectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String description,
    required Color color,
    required VoidCallback onTap,
    bool fullWidth = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: fullWidth ? double.infinity : 300,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              // Icon Container
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 44, color: color),
              ),

              const SizedBox(height: 20),

              // Title
              Text(
                title,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),

              const SizedBox(height: 8),

              // Subtitle
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppTheme.textDark,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 12),

              // Description
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textGrey,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 24),

              // Button
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'متابعة',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// رسم النمط الخلفي
class _BackgroundPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..style = PaintingStyle.fill;

    // رسم دوائر ديكورية
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.1), 120, paint);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.3), 80, paint);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.7), 100, paint);
    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.9), 150, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
