import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_state_views.dart';

/// نموذج إنشاء/تعديل مشترك ساس بثيم الصدارة.
///
/// - وضع الإنشاء: [existing] = null → يستدعي `createUser` بحمولة كاملة.
/// - وضع التعديل: [existing] = خريطة تفاصيل المشترك → يستدعي `updateUser` بالحقول
///   القابلة للتعديل فقط (لا يُعاد إرسال اسم المستخدم/كلمة المرور إلا عند إدخالها).
///
/// ⚠️ كلمة المرور حقل إدخال فقط؛ لا تُعرَض قيمة قائمة ولا تُطبَع في أي مكان.
class SasSubscriberFormPage extends StatefulWidget {
  final SasAccount account;

  /// خريطة تفاصيل المشترك للتعديل (null = إنشاء جديد).
  final Map<String, dynamic>? existing;

  const SasSubscriberFormPage({
    super.key,
    required this.account,
    this.existing,
  });

  @override
  State<SasSubscriberFormPage> createState() => _SasSubscriberFormPageState();
}

class _SasSubscriberFormPageState extends State<SasSubscriberFormPage> {
  final _api = SasAgentApiService.instance;
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
  bool _obscurePw = true;
  bool _obscureConfirm = true;

  List<Map<String, dynamic>> _profiles = const [];
  int? _profileId;

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _prefillFromExisting();
    _loadProfiles();
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

  void _prefillFromExisting() {
    final e = widget.existing;
    if (e == null) return;
    _username.text = (e['username'] ?? '').toString();
    _firstname.text = (e['firstname'] ?? '').toString();
    _lastname.text = (e['lastname'] ?? '').toString();
    _email.text = (e['email'] ?? '').toString();
    _phone.text = (e['phone'] ?? '').toString();
    _city.text = (e['city'] ?? '').toString();
    _address.text = (e['address'] ?? '').toString();
    _nationalId.text = (e['national_id'] ?? '').toString();
    _contractId.text = (e['contract_id'] ?? '').toString();
    _staticIp.text = (e['static_ip'] ?? '').toString();
    _notes.text = (e['notes'] ?? '').toString();
    _sessions.text = (e['simultaneous_sessions'] ?? 1).toString();
    _enabled = e['enabled'] == 1 || e['enabled'] == true;
    _macAuth = e['mac_auth'] == 1 || e['mac_auth'] == true;
    _autoRenew = e['auto_renew'] == 1 || e['auto_renew'] == true;
    _profileId = _asInt(e['profile_id']);
  }

  Future<void> _loadProfiles() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final profiles = await _api.getPackages(widget.account.id);
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        // إن كان بروفايل المشترك الحالي غير موجود في القائمة نُبقيه فارغاً بأمان.
        if (_profileId != null &&
            !_profiles.any((p) => _asInt(p['id']) == _profileId)) {
          _profileId = null;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString().replaceFirst('Exception: ', '').trim();
        _loading = false;
      });
    }
  }

  static int? _asInt(dynamic v) =>
      v is int ? v : (v == null ? null : int.tryParse(v.toString()));

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_profileId == null) {
      _toast('اختر الباقة', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _saveEdit();
      } else {
        await _saveCreate();
      }
      if (!mounted) return;
      _toast(_isEdit
          ? 'تم تحديث بيانات المشترك'
          : 'تم إنشاء المشترك «${_username.text.trim()}»');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        _toast(
          '${_isEdit ? 'فشل التعديل' : 'فشل الإنشاء'}: '
          '${e.toString().replaceFirst('Exception: ', '').trim()}',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveCreate() async {
    final payload = <String, dynamic>{
      'username': _username.text.trim(),
      'password': _password.text,
      'confirm_password': _confirm.text,
      'enabled': _enabled ? 1 : 0,
      'profile_id': _profileId,
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
      'static_ip':
          _staticIp.text.trim().isEmpty ? null : _staticIp.text.trim(),
      'notes': _notes.text.trim(),
      'simultaneous_sessions': int.tryParse(_sessions.text.trim()) ?? 1,
      'user_type': '0',
    };
    await _api.createUser(widget.account.id, payload);
  }

  Future<void> _saveEdit() async {
    // في التعديل: نرسل الحقول القابلة للتعديل فقط. كلمة المرور تُرسَل فقط عند إدخالها.
    final payload = <String, dynamic>{
      'enabled': _enabled ? 1 : 0,
      'profile_id': _profileId,
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
      'static_ip':
          _staticIp.text.trim().isEmpty ? null : _staticIp.text.trim(),
      'notes': _notes.text.trim(),
      'simultaneous_sessions': int.tryParse(_sessions.text.trim()) ?? 1,
      if (_password.text.isNotEmpty) 'password': _password.text,
    };
    final uid = (widget.existing?['id'] ?? '').toString();
    await _api.updateUser(widget.account.id, uid, payload);
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
        backgroundColor:
            isError ? AppTheme.errorColor : AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          elevation: 0,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.blueGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Text(
            _isEdit ? 'تعديل المشترك' : 'مشترك جديد',
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.w800, color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: _loading
            ? const SasLoadingView(message: 'جاري تحميل الباقات…')
            : _loadError != null
                ? SasErrorView(message: _loadError!, onRetry: _loadProfiles)
                : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Form(
          key: _form,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 28.h),
            children: [
              _sectionCard(
                title: 'بيانات الدخول',
                icon: Icons.badge_rounded,
                gradient: AppTheme.blueGradient,
                children: [
                  _field(_username, 'اسم المستخدم *',
                      required: true, enabled: !_isEdit),
                  _field(
                    _password,
                    _isEdit ? 'كلمة مرور جديدة (اختياري)' : 'كلمة المرور *',
                    required: !_isEdit,
                    obscure: _obscurePw,
                    toggleObscure: () =>
                        setState(() => _obscurePw = !_obscurePw),
                  ),
                  _field(
                    _confirm,
                    _isEdit ? 'تأكيد كلمة المرور' : 'تأكيد كلمة المرور *',
                    required: !_isEdit,
                    obscure: _obscureConfirm,
                    toggleObscure: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                    validator: (v) {
                      if (_password.text.isEmpty) return null;
                      return v != _password.text ? 'غير مطابقة' : null;
                    },
                  ),
                ],
              ),
              _sectionCard(
                title: 'الاشتراك',
                icon: Icons.wifi_rounded,
                gradient: AppTheme.greenGradient,
                children: [
                  _profileDropdown(),
                  _field(_sessions, 'عدد الجلسات المتزامنة',
                      keyboard: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ]),
                  _switchRow('مُفعَّل', _enabled,
                      (v) => setState(() => _enabled = v)),
                  _switchRow('تجديد تلقائي', _autoRenew,
                      (v) => setState(() => _autoRenew = v)),
                  _switchRow('مصادقة MAC', _macAuth,
                      (v) => setState(() => _macAuth = v)),
                ],
              ),
              _sectionCard(
                title: 'البيانات الشخصية',
                icon: Icons.person_rounded,
                gradient: AppTheme.orangeGradient,
                children: [
                  _field(_firstname, 'الاسم الأول'),
                  _field(_lastname, 'الاسم الأخير'),
                  _field(_phone, 'الهاتف', keyboard: TextInputType.phone),
                  _field(_email, 'البريد الإلكتروني',
                      keyboard: TextInputType.emailAddress),
                  _field(_nationalId, 'الهوية الوطنية'),
                  _field(_contractId, 'رقم العقد'),
                ],
              ),
              _sectionCard(
                title: 'العنوان والشبكة',
                icon: Icons.location_on_rounded,
                gradient: const [Color(0xFF7B1FA2), Color(0xFF9C27B0)],
                children: [
                  _field(_city, 'المدينة'),
                  _field(_address, 'العنوان'),
                  _field(_staticIp, 'IP ثابت (اختياري)'),
                  _field(_notes, 'ملاحظات', maxLines: 3),
                ],
              ),
              SizedBox(height: 8.h),
              _submitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Color> gradient,
    required List<Widget> children,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 14.h),
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SasSectionHeader(title: title, icon: icon, gradient: gradient),
          SizedBox(height: 10.h),
          ...children,
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
    bool obscure = false,
    bool enabled = true,
    int maxLines = 1,
    TextInputType? keyboard,
    List<TextInputFormatter>? inputFormatters,
    VoidCallback? toggleObscure,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: TextFormField(
        controller: c,
        obscureText: obscure,
        enabled: enabled,
        maxLines: obscure ? 1 : maxLines,
        keyboardType: keyboard,
        inputFormatters: inputFormatters,
        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.cairo(color: Colors.grey[600]),
          isDense: true,
          filled: true,
          fillColor: enabled ? Colors.white : Colors.grey.withValues(alpha: 0.06),
          suffixIcon: toggleObscure == null
              ? null
              : IconButton(
                  icon: Icon(
                    obscure
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 20,
                    color: Colors.grey[500],
                  ),
                  onPressed: toggleObscure,
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
            borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.16)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
            borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.16)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
            borderSide:
                const BorderSide(color: AppTheme.primaryColor, width: 1.6),
          ),
        ),
        validator: validator ??
            (required
                ? (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null
                : null),
      ),
    );
  }

  Widget _profileDropdown() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: DropdownButtonFormField<int>(
        initialValue: _profileId,
        isExpanded: true,
        style: GoogleFonts.cairo(
            fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E)),
        decoration: InputDecoration(
          labelText: 'الباقة *',
          labelStyle: GoogleFonts.cairo(color: Colors.grey[600]),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
            borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.16)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
            borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.16)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
            borderSide:
                const BorderSide(color: AppTheme.primaryColor, width: 1.6),
          ),
        ),
        items: [
          for (final p in _profiles)
            DropdownMenuItem(
              value: _asInt(p['id']),
              child: Text('${p['name'] ?? p['id']}',
                  overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() => _profileId = v),
        validator: (v) => v == null ? 'اختر الباقة' : null,
      ),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeThumbColor: AppTheme.primaryColor,
      title: Text(label,
          style: GoogleFonts.cairo(
              fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E))),
    );
  }

  Widget _submitButton() {
    return SizedBox(
      height: 50,
      child: FilledButton.icon(
        onPressed: _saving ? null : _submit,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
          ),
        ),
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white),
              )
            : Icon(_isEdit ? Icons.save_rounded : Icons.person_add_rounded,
                size: 20),
        label: Text(
          _isEdit ? 'حفظ التعديلات' : 'إنشاء المشترك',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
    );
  }
}
