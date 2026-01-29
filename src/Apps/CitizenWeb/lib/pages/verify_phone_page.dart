import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class VerifyPhonePage extends StatefulWidget {
  final String citizenId;

  const VerifyPhonePage({super.key, required this.citizenId});

  @override
  State<VerifyPhonePage> createState() => _VerifyPhonePageState();
}

class _VerifyPhonePageState extends State<VerifyPhonePage> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authProvider = context.read<AuthProvider>();
    authProvider.clearError();

    final success = await authProvider.verifyPhone(
      widget.citizenId,
      _codeController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تفعيل حسابك بنجاح!'),
          backgroundColor: Colors.green,
        ),
      );
      context.go('/login');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.error ?? 'رمز التحقق غير صحيح'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تفعيل الحساب')),
        body: Consumer<AuthProvider>(
          builder: (context, auth, child) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.verified_user,
                      size: 100,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'تفعيل الحساب',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'أدخل رمز التحقق المرسل إلى هاتفك',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // Verification Code Field
                    TextFormField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        letterSpacing: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'رمز التحقق',
                        border: OutlineInputBorder(),
                        hintText: '123456',
                      ),
                      maxLength: 6,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'الرجاء إدخال رمز التحقق';
                        }
                        if (value.length != 6) {
                          return 'رمز التحقق يجب أن يكون 6 أرقام';
                        }
                        if (!RegExp(r'^\d+$').hasMatch(value)) {
                          return 'رمز التحقق يجب أن يحتوي على أرقام فقط';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),

                    // Verify Button
                    ElevatedButton(
                      onPressed: auth.isLoading ? null : _verify,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: auth.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('تفعيل', style: TextStyle(fontSize: 16)),
                    ),
                    const SizedBox(height: 24),

                    // Resend Code Button
                    TextButton(
                      onPressed: auth.isLoading
                          ? null
                          : () {
                              // TODO: Implement resend code
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم إعادة إرسال الرمز'),
                                ),
                              );
                            },
                      child: const Text('إعادة إرسال الرمز'),
                    ),
                    const SizedBox(height: 16),

                    // Back to Login Link
                    TextButton(
                      onPressed: () {
                        context.go('/login');
                      },
                      child: const Text('العودة لتسجيل الدخول'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
