import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:sadara_design/sadara_design.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

/// تسجيل دخول المواطن — موحّد على نظام تصميم الصدارة (3D).
class CitizenLoginPage extends StatefulWidget {
  const CitizenLoginPage({super.key});
  @override
  State<CitizenLoginPage> createState() => _CitizenLoginPageState();
}

class _CitizenLoginPageState extends State<CitizenLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _apiService = ApiService();
  bool _rememberMe = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final rememberMe = await _apiService.getRememberMe();
    if (rememberMe) {
      final saved = await _apiService.getSavedCredentials();
      if (saved.phone != null && mounted) {
        setState(() {
          _phoneController.text = saved.phone!;
          _passwordController.text = saved.password ?? '';
          _rememberMe = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      _phoneController.text.trim(),
      _passwordController.text,
      rememberMe: _rememberMe,
    );
    if (success && mounted) {
      if (_rememberMe) {
        await _apiService.saveLoginCredentials(
            _phoneController.text.trim(), _passwordController.text);
      } else {
        await _apiService.clearSavedCredentials();
      }
      if (mounted) context.go('/citizen/home');
    } else if (authProvider.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(authProvider.error!),
        backgroundColor: SdColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return SdPage(
      maxWidth: 460,
      appBar: SdAppBar(title: 'دخول المواطن', onBack: () => context.go('/')),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: SdSpace.md),
            const _Brand(),
            const SizedBox(height: SdSpace.xl),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف',
                hintText: '07xx xxx xxxx',
                prefixIcon: Icon(Icons.phone_rounded),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'أدخل رقم الهاتف' : null,
            ),
            const SizedBox(height: SdSpace.sm),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'كلمة المرور',
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'أدخل كلمة المرور' : null,
              onFieldSubmitted: (_) => _login(),
            ),
            const SizedBox(height: SdSpace.xs),
            Row(
              children: [
                Checkbox(
                  value: _rememberMe,
                  onChanged: (v) => setState(() => _rememberMe = v ?? false),
                ),
                GestureDetector(
                  onTap: () => setState(() => _rememberMe = !_rememberMe),
                  child: Text('تذكّرني', style: SdText.bodySm),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {},
                  child: const Text('نسيت كلمة المرور؟'),
                ),
              ],
            ),
            const SizedBox(height: SdSpace.sm),
            SdButton(
              label: 'دخول',
              icon: Icons.login_rounded,
              expand: true,
              isLoading: auth.isLoading,
              onPressed: _login,
            ),
            const SizedBox(height: SdSpace.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('ليس لديك حساب؟ ', style: SdText.bodySm),
                GestureDetector(
                  onTap: () => context.go('/citizen/register'),
                  child: Text('سجّل الآن',
                      style: SdText.label.copyWith(color: SdColors.accent)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// شعار الصدارة المجسّم.
class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [SdColors.primarySoft, SdColors.primaryEdge],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: SdColors.goldLight, width: 1.4),
            boxShadow: const [
              BoxShadow(color: Color(0x66132A5E), blurRadius: 24, offset: Offset(0, 10)),
            ],
          ),
          child: const Text('ص',
              style: TextStyle(
                  fontFamily: SdText.family,
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: SdSpace.sm),
        Text('منصة الصدارة', style: SdText.title),
      ],
    );
  }
}
