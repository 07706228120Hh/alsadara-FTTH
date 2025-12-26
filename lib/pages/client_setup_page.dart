/// اسم الصفحة: إعداد العملاء
/// وصف الصفحة: صفحة إعداد وتكوين العملاء الجدد
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import '../services/config_manager.dart';

/// شاشة الإعداد الأولي للعميل
class ClientSetupPage extends StatefulWidget {
  const ClientSetupPage({super.key});

  @override
  State<ClientSetupPage> createState() => _ClientSetupPageState();
}

class _ClientSetupPageState extends State<ClientSetupPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Controllers for form fields
  final _companyNameController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _whatsappApiController = TextEditingController();

  bool _isLoading = false;
  bool _apiKeyVisible = false;
  bool _clientSecretVisible = false;
  bool _whatsappApiVisible = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _companyNameController.dispose();
    _apiKeyController.dispose();
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _whatsappApiController.dispose();
    super.dispose();
  }

  Future<void> _completeSetup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final success = await ConfigManager.instance.setupClient(
        companyName: _companyNameController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        clientId: _clientIdController.text.trim().isNotEmpty
            ? _clientIdController.text.trim()
            : null,
        clientSecret: _clientSecretController.text.trim().isNotEmpty
            ? _clientSecretController.text.trim()
            : null,
      );

      if (success) {
        // حفظ مفتاح واتساب إذا تم إدخاله
        if (_whatsappApiController.text.trim().isNotEmpty) {
          await ConfigManager.instance.setSecureValue(
            'whatsapp_api_key',
            _whatsappApiController.text.trim(),
          );
        }

        // إظهار رسالة النجاح
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم إعداد التطبيق بنجاح!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );

          // الانتقال إلى الشاشة الرئيسية
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/home');
          }
        }
      } else {
        _showError('فشل في إعداد التطبيق. يرجى المحاولة مرة أخرى.');
      }
    } catch (e) {
      _showError('حدث خطأ في الإعداد: $e');
    }

    setState(() => _isLoading = false);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1976D2),
              Color(0xFF64B5F6),
              Colors.white,
            ],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const SizedBox(height: 40),
          _buildHeader(),
          const SizedBox(height: 40),
          _buildSetupForm(),
          const SizedBox(height: 40),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.settings_applications,
            size: 60,
            color: Color(0xFF1976D2),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'مرحباً بك في تطبيق الصدارة',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'يرجى إدخال إعدادات شركتك لبدء الاستخدام',
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withValues(alpha: 0.9),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSetupForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('معلومات الشركة'),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _companyNameController,
              label: 'اسم الشركة',
              hint: 'أدخل اسم شركتك',
              icon: Icons.business,
              isRequired: true,
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('إعدادات API'),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _apiKeyController,
              label: 'مفتاح API',
              hint: 'أدخل مفتاح API الخاص بك',
              icon: Icons.key,
              isRequired: true,
              isPassword: !_apiKeyVisible,
              suffixIcon: IconButton(
                icon: Icon(
                    _apiKeyVisible ? Icons.visibility : Icons.visibility_off),
                onPressed: () =>
                    setState(() => _apiKeyVisible = !_apiKeyVisible),
              ),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _clientIdController,
              label: 'معرف العميل (اختياري)',
              hint: 'أدخل معرف العميل',
              icon: Icons.account_circle,
              isRequired: false,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _clientSecretController,
              label: 'كلمة سر العميل (اختياري)',
              hint: 'أدخل كلمة سر العميل',
              icon: Icons.lock,
              isRequired: false,
              isPassword: !_clientSecretVisible,
              suffixIcon: IconButton(
                icon: Icon(_clientSecretVisible
                    ? Icons.visibility
                    : Icons.visibility_off),
                onPressed: () => setState(
                    () => _clientSecretVisible = !_clientSecretVisible),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('إعدادات الواتساب (اختياري)'),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _whatsappApiController,
              label: 'مفتاح واتساب API',
              hint: 'أدخل مفتاح واتساب API',
              icon: Icons.chat,
              isRequired: false,
              isPassword: !_whatsappApiVisible,
              suffixIcon: IconButton(
                icon: Icon(_whatsappApiVisible
                    ? Icons.visibility
                    : Icons.visibility_off),
                onPressed: () =>
                    setState(() => _whatsappApiVisible = !_whatsappApiVisible),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1976D2),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isRequired,
    bool isPassword = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF1976D2)),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1976D2), width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      validator: isRequired
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return 'هذا الحقل مطلوب';
              }
              return null;
            }
          : null,
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _completeSetup,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 8,
            ),
            child: _isLoading
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text('جاري الإعداد...'),
                    ],
                  )
                : const Text(
                    'إتمام الإعداد',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            // إظهار معلومات المساعدة
            _showHelpDialog();
          },
          child: const Text(
            'هل تحتاج مساعدة؟',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('معلومات المساعدة'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '📋 معلومات الشركة:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('• اسم الشركة: سيظهر في التطبيق والتقارير'),
              SizedBox(height: 12),
              Text(
                '🔑 إعدادات API:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('• مفتاح API: مطلوب للاتصال بالخادم'),
              Text('• معرف العميل: اختياري للمصادقة المتقدمة'),
              Text('• كلمة سر العميل: تستخدم مع معرف العميل'),
              SizedBox(height: 12),
              Text(
                '💬 إعدادات الواتساب:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('• اختيارية لتفعيل ميزة إرسال الرسائل'),
              Text('• يمكن إعدادها لاحقاً من الإعدادات'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('فهمت'),
          ),
        ],
      ),
    );
  }
}
