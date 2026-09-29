import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../api/staff_api.dart';
import '../theme/tokens.dart';
import '../widgets/banner.dart';

/// نموذج إنشاء مشترك جديد في SAS (SAS: POST user) بحمولة كاملة.
/// يجلب الباقات (للاختيار) و — للشركة — قائمة الوكلاء لاختيار المالك (parent).
/// للوكيل: يُثبّت الباكند parent_id على وكيله تلقائياً فنُخفي اختيار المالك.
class SasSubscriberForm extends StatefulWidget {
  final StaffApi api;
  final int companyId;
  final bool isAgent;
  const SasSubscriberForm({
    super.key,
    required this.api,
    required this.companyId,
    this.isAgent = false,
  });

  @override
  State<SasSubscriberForm> createState() => _SasSubscriberFormState();
}

class _SasSubscriberFormState extends State<SasSubscriberForm> {
  final _form = GlobalKey<FormState>();

  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _firstname = TextEditingController();
  final _lastname = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _nationalId = TextEditingController();
  final _contractId = TextEditingController();
  final _staticIp = TextEditingController();
  final _notes = TextEditingController();
  final _sessions = TextEditingController(text: '1');

  bool _enabled = true;
  bool _macAuth = false;
  bool _autoRenew = false;

  List<Map<String, dynamic>> _profiles = const [];
  List<Map<String, dynamic>> _managers = const [];
  int? _profileId;
  int? _parentId;

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    for (final c in [
      _username, _password, _confirm, _firstname, _lastname, _email, _phone,
      _city, _address, _nationalId, _contractId, _staticIp, _notes, _sessions,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final profiles = await widget.api.sasProfiles(widget.companyId);
      List<Map<String, dynamic>> managers = const [];
      if (!widget.isAgent) {
        final m = await widget.api.sasManagers(widget.companyId, count: 500);
        managers = m.rows;
      }
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _managers = managers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_profileId == null) {
      toast(context, 'اختر الباقة', kind: BannerKind.error);
      return;
    }
    if (!widget.isAgent && _parentId == null) {
      toast(context, 'اختر الوكيل المالك', kind: BannerKind.error);
      return;
    }
    final payload = <String, dynamic>{
      'username': _username.text.trim(),
      'password': _password.text,
      'confirm_password': _confirm.text,
      'enabled': _enabled ? 1 : 0,
      'profile_id': _profileId,
      if (!widget.isAgent) 'parent_id': _parentId,
      'mac_auth': _macAuth ? 1 : 0,
      'auto_renew': _autoRenew ? 1 : 0,
      'firstname': _firstname.text.trim(),
      'lastname': _lastname.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'city': _city.text.trim(),
      'address': _address.text.trim(),
      'national_id': _nationalId.text.trim(),
      'contract_id': _contractId.text.trim(),
      'static_ip': _staticIp.text.trim().isEmpty ? null : _staticIp.text.trim(),
      'notes': _notes.text.trim(),
      'simultaneous_sessions': int.tryParse(_sessions.text.trim()) ?? 1,
      'user_type': '0',
    };
    setState(() => _saving = true);
    try {
      await widget.api.sasCreateUser(widget.companyId, payload);
      if (!mounted) return;
      toast(context, 'تم إنشاء المشترك «${payload['username']}»', kind: BannerKind.success);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, 'فشل الإنشاء: $e', kind: BannerKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('مشترك جديد')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(Space.xl),
                    child: PBanner.error('تعذّر جلب الباقات/الوكلاء: $_loadError'),
                  ))
                : Form(
                    key: _form,
                    child: ListView(
                      padding: const EdgeInsets.all(Space.lg),
                      children: [
                        _section('بيانات الدخول'),
                        _text(_username, 'اسم المستخدم *', required: true),
                        _text(_password, 'كلمة المرور *', required: true, obscure: true),
                        _text(_confirm, 'تأكيد كلمة المرور *', required: true, obscure: true,
                            validator: (v) => v != _password.text ? 'غير مطابقة' : null),
                        _section('الاشتراك'),
                        _dropdownProfiles(),
                        if (!widget.isAgent) _dropdownManagers(),
                        _text(_sessions, 'عدد الجلسات المتزامنة',
                            keyboard: TextInputType.number),
                        SwitchListTile(
                          value: _enabled,
                          onChanged: (v) => setState(() => _enabled = v),
                          title: const Text('مُفعَّل'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          value: _autoRenew,
                          onChanged: (v) => setState(() => _autoRenew = v),
                          title: const Text('تجديد تلقائي'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          value: _macAuth,
                          onChanged: (v) => setState(() => _macAuth = v),
                          title: const Text('مصادقة MAC'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        _section('البيانات الشخصية'),
                        _text(_firstname, 'الاسم الأول'),
                        _text(_lastname, 'الاسم الأخير'),
                        _text(_phone, 'الهاتف', keyboard: TextInputType.phone),
                        _text(_email, 'البريد الإلكتروني', keyboard: TextInputType.emailAddress),
                        _text(_nationalId, 'الهوية الوطنية'),
                        _text(_contractId, 'رقم العقد'),
                        _section('العنوان والشبكة'),
                        _text(_city, 'المدينة'),
                        _text(_address, 'العنوان'),
                        _text(_staticIp, 'IP ثابت (اختياري)'),
                        _text(_notes, 'ملاحظات', maxLines: 3),
                        const SizedBox(height: Space.lg),
                        FilledButton.icon(
                          onPressed: _saving ? null : _submit,
                          icon: _saving
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(PhosphorIconsBold.userPlus, size: 18),
                          label: const Text('إنشاء المشترك'),
                        ),
                        const SizedBox(height: Space.xl),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: Space.lg, bottom: Space.sm),
        child: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      );

  Widget _text(TextEditingController c, String label, {
    bool required = false,
    bool obscure = false,
    int maxLines = 1,
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: c,
        obscureText: obscure,
        maxLines: obscure ? 1 : maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        validator: validator ??
            (required ? (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null : null),
      ),
    );
  }

  Widget _dropdownProfiles() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: DropdownButtonFormField<int>(
          initialValue: _profileId,
          decoration: const InputDecoration(
            labelText: 'الباقة *', isDense: true, border: OutlineInputBorder()),
          items: [
            for (final p in _profiles)
              DropdownMenuItem(
                value: (p['id'] as num?)?.toInt(),
                child: Text('${p['name'] ?? p['id']}'),
              ),
          ],
          onChanged: (v) => setState(() => _profileId = v),
        ),
      );

  Widget _dropdownManagers() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: DropdownButtonFormField<int>(
          initialValue: _parentId,
          decoration: const InputDecoration(
            labelText: 'الوكيل المالك *', isDense: true, border: OutlineInputBorder()),
          items: [
            for (final m in _managers)
              DropdownMenuItem(
                value: (m['id'] as num?)?.toInt(),
                child: Text('${m['username'] ?? m['id']}'
                    '${m['firstname'] != null ? ' — ${m['firstname']}' : ''}'),
              ),
          ],
          onChanged: (v) => setState(() => _parentId = v),
        ),
      );
}
