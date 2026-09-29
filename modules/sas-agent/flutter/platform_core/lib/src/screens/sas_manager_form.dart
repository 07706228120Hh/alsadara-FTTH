import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../api/staff_api.dart';
import '../theme/tokens.dart';
import '../widgets/banner.dart';

/// نموذج إضافة/تعديل وكيل (Manager) في نظام SAS.
/// - إضافة: SAS POST manager (كلمة المرور مطلوبة).
/// - تعديل: SAS POST manager/{id} (كلمة المرور فارغة = إبقاء الحالية).
/// محجوب عن الوكيل (الباكند يردّ 403) — يُستخدم من واجهة الشركة/الأدمن فقط.
class SasManagerForm extends StatefulWidget {
  final StaffApi api;
  final int companyId;

  /// صفّ الوكيل عند التعديل (من قائمة الوكلاء)؛ null = إضافة جديد.
  final Map<String, dynamic>? existing;

  const SasManagerForm({
    super.key,
    required this.api,
    required this.companyId,
    this.existing,
  });

  bool get isEdit => existing != null;

  @override
  State<SasManagerForm> createState() => _SasManagerFormState();
}

class _SasManagerFormState extends State<SasManagerForm> {
  final _form = GlobalKey<FormState>();

  late final TextEditingController _username;
  late final TextEditingController _firstname;
  late final TextEditingController _lastname;
  late final TextEditingController _phone;
  late final TextEditingController _city;
  late final TextEditingController _email;
  late final TextEditingController _discount;
  late final TextEditingController _maxUsers;
  late final TextEditingController _debtLimit;
  late final TextEditingController _aclGroup;
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _enabled = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? const {};
    _username = TextEditingController(text: '${e['username'] ?? ''}');
    _firstname = TextEditingController(text: '${e['firstname'] ?? ''}');
    _lastname = TextEditingController(text: '${e['lastname'] ?? ''}');
    _phone = TextEditingController(text: '${e['phone'] ?? ''}');
    _city = TextEditingController(text: '${e['city'] ?? ''}');
    _email = TextEditingController(text: '${e['email'] ?? ''}');
    _discount = TextEditingController(text: '${e['discount_rate'] ?? '0'}');
    _maxUsers = TextEditingController(text: '${e['max_users'] ?? '0'}');
    _debtLimit = TextEditingController(text: '${e['debt_limit'] ?? '0'}');
    _aclGroup = TextEditingController(text: '${e['acl_group_id'] ?? ''}');
    _enabled = (e['enabled'] ?? true) == true || e['enabled'] == 1;
  }

  @override
  void dispose() {
    for (final c in [
      _username, _firstname, _lastname, _phone, _city, _email,
      _discount, _maxUsers, _debtLimit, _aclGroup, _password, _confirm,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!widget.isEdit && _password.text.isEmpty) {
      toast(context, 'كلمة المرور مطلوبة عند الإضافة', kind: BannerKind.error);
      return;
    }
    if (_password.text.isNotEmpty && _password.text != _confirm.text) {
      toast(context, 'كلمتا المرور غير متطابقتين', kind: BannerKind.error);
      return;
    }
    final payload = <String, dynamic>{
      'username': _username.text.trim(),
      'enabled': _enabled ? 1 : 0,
      'firstname': _firstname.text.trim(),
      'lastname': _lastname.text.trim(),
      'phone': _phone.text.trim(),
      'city': _city.text.trim(),
      'email': _email.text.trim(),
      'discount_rate': _discount.text.trim(),
      'max_users': _maxUsers.text.trim(),
      'debt_limit': _debtLimit.text.trim(),
      if (_aclGroup.text.trim().isNotEmpty)
        'acl_group_id': int.tryParse(_aclGroup.text.trim()),
      if (_password.text.isNotEmpty) ...{
        'password': _password.text,
        'confirm_password': _confirm.text,
      },
    };
    setState(() => _saving = true);
    try {
      if (widget.isEdit) {
        final mid = (widget.existing!['id'] as num?)?.toInt() ?? 0;
        await widget.api.sasManagerEdit(widget.companyId, mid, payload);
      } else {
        await widget.api.sasManagerAdd(widget.companyId, payload);
      }
      if (!mounted) return;
      toast(context,
          widget.isEdit ? 'تم تعديل الوكيل' : 'تم إضافة الوكيل',
          kind: BannerKind.success);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, 'فشل الحفظ: $e', kind: BannerKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.isEdit ? 'تعديل وكيل' : 'وكيل جديد')),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(Space.lg),
            children: [
              _text(_username, 'اسم المستخدم *', required: true),
              _text(_password, widget.isEdit ? 'كلمة مرور جديدة (فارغة = إبقاء)' : 'كلمة المرور *',
                  obscure: true),
              _text(_confirm, 'تأكيد كلمة المرور', obscure: true),
              const Divider(height: 28),
              _text(_firstname, 'الاسم الأول'),
              _text(_lastname, 'الاسم الأخير'),
              _text(_phone, 'الهاتف', keyboard: TextInputType.phone),
              _text(_email, 'البريد الإلكتروني', keyboard: TextInputType.emailAddress),
              _text(_city, 'المدينة'),
              const Divider(height: 28),
              _text(_discount, 'نسبة الخصم %', keyboard: TextInputType.number),
              _text(_maxUsers, 'الحد الأقصى للمشتركين', keyboard: TextInputType.number),
              _text(_debtLimit, 'حدّ الدَّين', keyboard: TextInputType.number),
              _text(_aclGroup, 'مجموعة الصلاحيات (acl_group_id)', keyboard: TextInputType.number),
              SwitchListTile(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: const Text('مُفعَّل'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: Space.lg),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(widget.isEdit
                        ? PhosphorIconsBold.floppyDisk
                        : PhosphorIconsBold.userPlus, size: 18),
                label: Text(widget.isEdit ? 'حفظ التعديلات' : 'إضافة الوكيل'),
              ),
              const SizedBox(height: Space.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _text(TextEditingController c, String label, {
    bool required = false,
    bool obscure = false,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: c,
        obscureText: obscure,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null
            : null,
      ),
    );
  }
}
