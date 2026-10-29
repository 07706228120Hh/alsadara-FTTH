import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sadara_design/sadara_design.dart';
import '../../providers/agent_auth_provider.dart';

/// تسجيل دخول الوكيل — موحّد على نظام تصميم الصدارة (3D).
class AgentLoginPage extends StatefulWidget {
  const AgentLoginPage({super.key});
  @override
  State<AgentLoginPage> createState() => _AgentLoginPageState();
}

class _AgentLoginPageState extends State<AgentLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _obscure = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final agentAuth = context.read<AgentAuthProvider>();
      final rememberMe = await agentAuth.agentApi.getRememberMe();
      if (rememberMe) {
        final saved = await agentAuth.agentApi.getSavedCredentials();
        if (mounted && saved.code != null) {
          setState(() {
            _rememberMe = true;
            _codeController.text = saved.code!;
            if (saved.password != null) {
              _passwordController.text = saved.password!;
            }
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final agentAuth = context.read<AgentAuthProvider>();
      final success = await agentAuth.login(
        _codeController.text.trim(),
        _passwordController.text,
        rememberMe: _rememberMe,
      );
      if (success && _rememberMe) {
        await agentAuth.agentApi.saveCredentials(
            _codeController.text.trim(), _passwordController.text);
      } else if (!_rememberMe) {
        await agentAuth.agentApi.clearCredentials();
      }
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          context.go('/agent/home');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(agentAuth.error ?? 'فشل تسجيل الدخول'),
            backgroundColor: SdColors.danger,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('خطأ: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: SdColors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SdPage(
      maxWidth: 460,
      appBar: SdAppBar(title: 'دخول الوكيل', onBack: () => context.go('/')),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: SdSpace.md),
            Center(
              child: SdIconCube(
                  icon: Icons.storefront_rounded,
                  group: SdGroup.field,
                  size: 64),
            ),
            const SizedBox(height: SdSpace.sm),
            Center(child: Text('بوابة الوكلاء', style: SdText.title)),
            const SizedBox(height: SdSpace.xl),
            TextFormField(
              controller: _codeController,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'كود الوكيل',
                hintText: 'AG-xxxx',
                prefixIcon: Icon(Icons.badge_rounded),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'أدخل كود الوكيل' : null,
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
              ],
            ),
            const SizedBox(height: SdSpace.sm),
            SdButton(
              label: 'دخول',
              icon: Icons.login_rounded,
              kind: SdButtonKind.accent,
              expand: true,
              isLoading: _isLoading,
              onPressed: _login,
            ),
          ],
        ),
      ),
    );
  }
}
