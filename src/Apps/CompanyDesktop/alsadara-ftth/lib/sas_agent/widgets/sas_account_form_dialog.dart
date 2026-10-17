import 'package:flutter/material.dart';

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../models/sas_account.dart';

/// نتيجة نموذج حساب الساس (إنشاء/تعديل).
class SasAccountFormResult {
  final String label;
  final String serverUrl;
  final String username;

  /// كلمة المرور — إدخال فقط؛ فارغة في التعديل تعني «بلا تغيير».
  final String password;
  final SasAccountType accountType;
  final bool isActive;

  /// مُضاعِف القيم المالية من SAS4 إلى الدينار الحقيقي (افتراضي 1000).
  final num amountMultiplier;

  const SasAccountFormResult({
    required this.label,
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.accountType,
    required this.isActive,
    this.amountMultiplier = 1000,
  });
}

/// حوار ربط/تعديل حساب ساس بثيم الصدارة الموحّد (sd).
///
/// ⚠️ كلمة المرور حقل إدخال فقط؛ لا تُعرَض قيمة قائمة ولا تُطبَع في أي مكان.
class SasAccountFormDialog extends StatefulWidget {
  /// الحساب المراد تعديله (null = إنشاء جديد).
  final SasAccount? existing;

  const SasAccountFormDialog({super.key, this.existing});

  @override
  State<SasAccountFormDialog> createState() => _SasAccountFormDialogState();
}

class _SasAccountFormDialogState extends State<SasAccountFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelCtrl;
  late final TextEditingController _serverCtrl;
  late final TextEditingController _userCtrl;
  final _passCtrl = TextEditingController();
  late final TextEditingController _multiplierCtrl;

  late SasAccountType _accountType;
  late bool _isActive;
  bool _obscure = true;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _labelCtrl = TextEditingController(text: e?.label ?? '');
    _serverCtrl = TextEditingController(text: e?.serverUrl ?? '');
    _userCtrl = TextEditingController(text: e?.username ?? '');
    _accountType = e?.accountType ?? SasAccountType.sasManager;
    _isActive = e?.isActive ?? true;
    _multiplierCtrl = TextEditingController(
        text: (e?.amountMultiplier ?? 1000).toString());
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _multiplierCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      SasAccountFormResult(
        label: _labelCtrl.text.trim(),
        serverUrl: _serverCtrl.text.trim(),
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
        accountType: _accountType,
        isActive: _isActive,
        amountMultiplier: () {
          final v = num.tryParse(_multiplierCtrl.text.trim());
          return (v != null && v > 0) ? v : 1000;
        }(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(SdRadius.lg)),
        clipBehavior: Clip.antiAlias,
        backgroundColor: SdColors.surface,
        child: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: _body(),
              ),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  /// رأس نيلي بارز مع أيقونة وعنوان.
  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const BoxDecoration(
        color: SdColors.primary,
        border: Border(
          bottom: BorderSide(color: SdColors.primaryEdge, width: 4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(SdRadius.sm),
              border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            ),
            child: Icon(
              _isEdit ? Icons.edit_rounded : Icons.add_link_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _isEdit ? 'تعديل حساب الساس' : 'ربط حساب ساس',
            style: const TextStyle(
              fontFamily: SdText.family,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: SdButton(
              label: 'إلغاء',
              kind: SdButtonKind.secondary,
              height: 48,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: SdButton(
              label: _isEdit ? 'حفظ التعديلات' : 'ربط الحساب',
              icon: _isEdit ? Icons.save_rounded : Icons.link_rounded,
              height: 48,
              onPressed: _submit,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(
              controller: _labelCtrl,
              label: 'التسمية',
              icon: Icons.label_outline_rounded,
              hint: 'اسم يميّز الحساب (اختياري)',
            ),
            const SizedBox(height: 12),
            _field(
              controller: _serverCtrl,
              label: 'عنوان خادم الساس',
              icon: Icons.dns_rounded,
              hint: 'https://sas.example.com',
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'عنوان الخادم مطلوب'
                  : null,
            ),
            const SizedBox(height: 12),
            _field(
              controller: _userCtrl,
              label: 'اسم المستخدم',
              icon: Icons.person_outline_rounded,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'اسم المستخدم مطلوب'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passCtrl,
              obscureText: _obscure,
              style: const TextStyle(fontFamily: SdText.family),
              decoration: InputDecoration(
                labelText: 'كلمة المرور',
                hintText: _isEdit ? 'اتركها فارغة لعدم التغيير' : null,
                hintStyle: const TextStyle(
                    fontFamily: SdText.family, color: SdColors.faint),
                prefixIcon: const Icon(Icons.lock_outline_rounded,
                    color: SdColors.primary, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: SdColors.muted,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) {
                // في الإنشاء كلمة المرور مطلوبة؛ في التعديل اختيارية.
                if (!_isEdit && (v == null || v.isEmpty)) {
                  return 'كلمة المرور مطلوبة';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SasAccountType>(
              initialValue: _accountType,
              decoration: const InputDecoration(
                labelText: 'نوع الحساب',
                prefixIcon: Icon(Icons.category_outlined,
                    color: SdColors.primary, size: 20),
                labelStyle: TextStyle(fontFamily: SdText.family),
              ),
              style: const TextStyle(
                  fontFamily: SdText.family,
                  fontWeight: FontWeight.w600,
                  color: SdColors.ink),
              items: SasAccountType.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t.labelAr,
                            style: const TextStyle(fontFamily: SdText.family)),
                      ))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _accountType = v ?? _accountType),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _multiplierCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontFamily: SdText.family),
              decoration: const InputDecoration(
                labelText: 'مُضاعِف القيمة المالية',
                helperText:
                    'قيم الساس تُضرب بهذا الرقم للدينار الحقيقي (16 → 16000). الافتراضي 1000.',
                helperStyle: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 11,
                    color: SdColors.muted),
                prefixIcon: Icon(Icons.calculate_outlined,
                    color: SdColors.primary, size: 20),
                labelStyle: TextStyle(fontFamily: SdText.family),
              ),
              validator: (v) {
                final n = num.tryParse((v ?? '').trim());
                if (n == null || n <= 0) return 'أدخل رقماً موجباً (مثل 1000)';
                return null;
              },
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              title: const Text('الحساب مُفعَّل',
                  style: TextStyle(fontFamily: SdText.family)),
              activeThumbColor: SdColors.primary,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(
          fontFamily: SdText.family, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle:
            const TextStyle(fontFamily: SdText.family, color: SdColors.faint),
        prefixIcon: Icon(icon, color: SdColors.primary, size: 20),
        labelStyle: const TextStyle(fontFamily: SdText.family),
      ),
      validator: validator,
    );
  }
}
