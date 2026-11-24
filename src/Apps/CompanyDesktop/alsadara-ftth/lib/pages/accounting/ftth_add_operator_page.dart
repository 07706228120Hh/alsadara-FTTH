import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show NumberFormat;
import '../../frontend/frontend.dart';
import '../../services/ftth_connect_service.dart';
import '../../services/linked_accounts_service.dart';

/// شاشة إضافة مشغّل جديد لحساب شريك FTTH مختار.
///
/// التدفّق: اختيار الشريك من قائمة منسدلة ← دخول خادمي لحساب الشريك الرئيسي
/// عبر بوّابة الصدارة (`/linked-accounts/partners/{id}/login`) للحصول على توكنه
/// المؤقّت ← تحميل الأدوار/المناطق/سياسة كلمة المرور بذلك التوكن ← إنشاء المشغّل.
/// إنشاء مشغّل بمحفظة ورصيد يحرّك مالاً — لذا هناك خطوة تأكيد صريحة قبل الإرسال.
/// ترجع `true` عبر Navigator.pop عند نجاح الإنشاء.
class FtthAddOperatorPage extends StatefulWidget {
  const FtthAddOperatorPage({super.key});

  @override
  State<FtthAddOperatorPage> createState() => _FtthAddOperatorPageState();
}

class _FtthAddOperatorPageState extends State<FtthAddOperatorPage> {
  final _ftth = FtthConnectService.instance;
  final _linked = LinkedAccountsService.instance;
  final _formKey = GlobalKey<FormState>();
  final _currency = NumberFormat('#,##0', 'en_US');

  // ─── الشركاء ───
  bool _loadingPartners = true;
  String? _partnersError;
  List<Map<String, dynamic>> _partners = [];
  Map<String, dynamic>? _selectedPartner;
  String? _partnerToken;
  String? _partnerServerUrl;

  // ─── البيانات المرجعية للشريك المختار ───
  bool _loadingRefs = false;
  String? _refsError;
  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _zones = []; // موحّدة: {id, name}
  List<Map<String, dynamic>> _policies = [];

  // ─── الحقول ───
  final _usernameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();

  Map<String, dynamic>? _selectedRole;
  final Set<String> _selectedZones = {};
  bool _hasWallet = false;
  bool _obscurePassword = true;

  Timer? _usernameDebounce;
  bool _checkingUsername = false;
  bool? _usernameAvailable;
  bool _submitting = false;

  // سياسة كلمة المرور
  int _minLength = 8;
  bool _needUpper = false;
  bool _needLower = false;
  bool _needDigit = false;

  @override
  void initState() {
    super.initState();
    _passwordCtrl.addListener(() => setState(() {}));
    _loadPartners();
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _usernameCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════
  //  تحميل الشركاء
  // ═══════════════════════════════════════════
  Future<void> _loadPartners() async {
    setState(() {
      _loadingPartners = true;
      _partnersError = null;
    });
    try {
      final res = await _linked.getPartners();
      if (!mounted) return;
      if (res['success'] == true) {
        _partners = _asList(res['data'])
            .where((p) => (p['isActive'] ?? true) != false)
            .toList();
        setState(() => _loadingPartners = false);
        // اختيار تلقائي إن كان هناك شريك واحد فقط
        if (_partners.length == 1) _onPartnerChanged(_partners.first);
      } else {
        setState(() {
          _partnersError = res['message']?.toString() ?? 'تعذّر جلب الشركاء';
          _loadingPartners = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _partnersError = 'تعذّر جلب الشركاء';
        _loadingPartners = false;
      });
    }
  }

  List<Map<String, dynamic>> _asList(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (data is Map) {
      final inner = data['data'] ?? data['items'];
      if (inner is List) {
        return inner
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return [];
  }

  // ═══════════════════════════════════════════
  //  اختيار شريك → دخول خادمي + تحميل المراجع
  // ═══════════════════════════════════════════
  Future<void> _onPartnerChanged(Map<String, dynamic>? p) async {
    if (p == null) return;
    setState(() {
      _selectedPartner = p;
      _partnerToken = null;
      _partnerServerUrl = null;
      _roles = [];
      _zones = [];
      _policies = [];
      _selectedRole = null;
      _selectedZones.clear();
      _usernameAvailable = null;
      _checkingUsername = false;
      _loadingRefs = true;
      _refsError = null;
    });
    try {
      final login = await _linked.loginPartner(p['id'].toString());
      if (!mounted) return;
      if (login['success'] != true) {
        throw Exception(login['message']?.toString() ?? 'فشل الدخول');
      }
      final raw = login['data'];
      final payload = (raw is Map && raw['data'] is Map)
          ? Map<String, dynamic>.from(raw['data'] as Map)
          : (raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});
      _partnerToken = payload['accessToken']?.toString();
      _partnerServerUrl =
          payload['serverUrl']?.toString() ?? p['serverUrl']?.toString();
      if (_partnerToken == null || _partnerToken!.isEmpty) {
        throw Exception('لم يُعِد الخادم توكناً');
      }

      final results = await Future.wait([
        _ftth.getTeamRoles(token: _partnerToken, baseUrl: _partnerServerUrl),
        _ftth.getZones(token: _partnerToken, baseUrl: _partnerServerUrl),
        _ftth.getPasswordPolicies(
            token: _partnerToken, baseUrl: _partnerServerUrl),
      ]);
      if (!mounted) return;
      _roles = results[0];
      _zones = _normalizeZones(results[1]);
      _policies = results[2];
      _applyPasswordPolicy();
      setState(() => _loadingRefs = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _refsError =
            'تعذّر تحميل بيانات الشريك — تأكّد من صحّة اعتماد الحساب الرئيسي';
        _loadingRefs = false;
      });
    }
  }

  List<Map<String, dynamic>> _normalizeZones(List<Map<String, dynamic>> raw) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final z in raw) {
      final self = z['self'] as Map<String, dynamic>?;
      final id = (self?['id'] ?? z['id'] ?? z['zoneId'])?.toString() ?? '';
      final name = (self?['displayValue'] ??
                  z['displayValue'] ??
                  z['zoneName'] ??
                  z['name'] ??
                  id)
              ?.toString() ??
          id;
      if (id.isEmpty || !seen.add(id)) continue;
      out.add({'id': id, 'name': name});
    }
    return out;
  }

  void _applyPasswordPolicy() {
    _minLength = 8;
    _needUpper = _needLower = _needDigit = false;
    for (final p in _policies) {
      final type = (p['type'] as Map?)?['displayValue']?.toString() ?? '';
      final value = p['value']?.toString();
      switch (type) {
        case 'MinimumLength':
          _minLength = int.tryParse(value ?? '') ?? _minLength;
          break;
        case 'UppercaseCharacters':
          _needUpper = true;
          break;
        case 'LowercaseCharacters':
          _needLower = true;
          break;
        case 'Digits':
          _needDigit = true;
          break;
      }
    }
  }

  // ─── تحقّق اسم المستخدم ───
  void _onUsernameChanged(String value) {
    _usernameDebounce?.cancel();
    setState(() {
      _usernameAvailable = null;
      _checkingUsername = false;
    });
    final v = value.trim();
    if (v.isEmpty || _partnerToken == null) return;
    _usernameDebounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      setState(() => _checkingUsername = true);
      try {
        final available = await _ftth.isTeamUsernameAvailable(v,
            token: _partnerToken, baseUrl: _partnerServerUrl);
        if (!mounted || _usernameCtrl.text.trim() != v) return;
        setState(() {
          _usernameAvailable = available;
          _checkingUsername = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _checkingUsername = false);
      }
    });
  }

  // ─── تقييم كلمة المرور ───
  List<(String, bool)> get _passwordChecks {
    final p = _passwordCtrl.text;
    return [
      ('على الأقل $_minLength أحرف', p.length >= _minLength),
      if (_needUpper) ('حرف كبير (A-Z)', p.contains(RegExp(r'[A-Z]'))),
      if (_needLower) ('حرف صغير (a-z)', p.contains(RegExp(r'[a-z]'))),
      if (_needDigit) ('رقم (0-9)', p.contains(RegExp(r'[0-9]'))),
    ];
  }

  bool get _passwordValid => _passwordChecks.every((c) => c.$2);

  bool get _zonesRequired =>
      !((_selectedRole?['canAccessAllPartnerZones'] as bool?) ?? false);

  // ═══════════════════════════════════════════
  //  مُنتقي المناطق (قائمة بمربعات اختيار + تحديد الكل + بحث)
  // ═══════════════════════════════════════════
  Future<void> _openZonePicker() async {
    final temp = Set<String>.from(_selectedZones);
    final searchCtrl = TextEditingController();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final q = searchCtrl.text.trim().toLowerCase();
          final filtered = q.isEmpty
              ? _zones
              : _zones
                  .where((z) => z['name'].toString().toLowerCase().contains(q))
                  .toList();
          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            title: Row(
              children: [
                const Icon(Icons.map_outlined, color: SdColors.accent, size: 20),
                const SizedBox(width: 8),
                const Text('اختيار المناطق',
                    style: TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('${temp.length} مختارة',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        color: SdColors.accent,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            content: SizedBox(
              width: 460,
              height: 520,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setD(() {}),
                    decoration: _dec('بحث عن منطقة...',
                        suffix: const Icon(Icons.search,
                            size: 18, color: SdColors.muted)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => setD(() =>
                            temp.addAll(_zones.map((z) => z['id'].toString()))),
                        icon: const Icon(Icons.done_all, size: 18),
                        label: const Text('تحديد الكل',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                        style: TextButton.styleFrom(
                            foregroundColor: SdColors.accent),
                      ),
                      TextButton.icon(
                        onPressed: () => setD(() => temp.clear()),
                        icon: const Icon(Icons.remove_done, size: 18),
                        label: const Text('إلغاء تحديد الكل',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                        style: TextButton.styleFrom(
                            foregroundColor: SdColors.danger),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text('لا توجد مناطق مطابقة',
                                style: TextStyle(
                                    fontFamily: 'Cairo', color: SdColors.faint)))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final z = filtered[i];
                              final id = z['id'].toString();
                              final on = temp.contains(id);
                              return CheckboxListTile(
                                dense: true,
                                value: on,
                                activeColor: SdColors.accent,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(z['name'].toString(),
                                    style: const TextStyle(
                                        fontFamily: 'Cairo', fontSize: 13)),
                                onChanged: (v) => setD(() {
                                  if (v == true) {
                                    temp.add(id);
                                  } else {
                                    temp.remove(id);
                                  }
                                }),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, temp),
                style: ElevatedButton.styleFrom(
                    backgroundColor: SdColors.accent,
                    foregroundColor: Colors.white),
                child: Text('تم (${temp.length})',
                    style: const TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
    if (result != null) {
      setState(() {
        _selectedZones
          ..clear()
          ..addAll(result);
      });
    }
  }

  // ═══════════════════════════════════════════
  //  الإرسال
  // ═══════════════════════════════════════════
  Future<void> _submit() async {
    if (_selectedPartner == null || _partnerToken == null) {
      _snack('اختر الشريك أولاً', SdStatus.warning);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedRole == null) {
      _snack('اختر دور المشغّل', SdStatus.warning);
      return;
    }
    if (!_passwordValid) {
      _snack('كلمة المرور لا تطابق السياسة', SdStatus.warning);
      return;
    }
    if (_zonesRequired && _selectedZones.isEmpty) {
      _snack('اختر منطقة واحدة على الأقل لهذا الدور', SdStatus.warning);
      return;
    }
    if (_usernameAvailable == false) {
      _snack('اسم المستخدم مأخوذ', SdStatus.warning);
      return;
    }

    final balance =
        _hasWallet ? (num.tryParse(_balanceCtrl.text.trim()) ?? 0) : 0;

    final confirmed = await _confirmDialog(balance);
    if (confirmed != true) return;

    setState(() => _submitting = true);
    final result = await _ftth.createTeamMember(
      username: _usernameCtrl.text.trim(),
      firstName: _firstNameCtrl.text.trim(),
      lastName: _lastNameCtrl.text.trim(),
      phoneNumber: _phoneCtrl.text.trim(),
      password: _passwordCtrl.text,
      zoneIds: _zonesRequired ? _selectedZones.toList() : const [],
      roleId: _selectedRole!['id'].toString(),
      hasWallet: _hasWallet,
      walletBalance: balance,
      token: _partnerToken,
      baseUrl: _partnerServerUrl,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (result['success'] == true) {
      _snack('تم إنشاء المشغّل بنجاح', SdStatus.success);
      Navigator.of(context).pop(true);
    } else {
      _snack(result['error']?.toString() ?? 'فشل الإنشاء', SdStatus.danger);
    }
  }

  Future<bool?> _confirmDialog(num balance) {
    final name =
        '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'.trim();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد إنشاء المشغّل',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _confirmRow(
                'الشريك', _selectedPartner?['name']?.toString() ?? '-'),
            _confirmRow('المستخدم', _usernameCtrl.text.trim()),
            if (name.isNotEmpty) _confirmRow('الاسم', name),
            _confirmRow('الهاتف', _phoneCtrl.text.trim()),
            _confirmRow(
                'الدور', _selectedRole?['displayValue']?.toString() ?? '-'),
            if (_zonesRequired)
              _confirmRow('المناطق', '${_selectedZones.length} منطقة'),
            const SizedBox(height: 10),
            if (_hasWallet && balance > 0)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: SdColors.warningTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SdColors.warningTintEdge),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet,
                        color: Color(0xFF8D6E00), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'سيُنشأ للمشغّل محفظة برصيد ${_currency.format(balance)} د.ع — هذا يحرّك مالاً من محفظة الشريك.',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF8D6E00)),
                      ),
                    ),
                  ],
                ),
              )
            else
              const Text('سيُنشأ المشغّل بدون رصيد محفظة.',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      color: SdColors.muted)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: SdColors.accent, foregroundColor: Colors.white),
            child: const Text('تأكيد وإنشاء',
                style:
                    TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _confirmRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text('$label: ',
                style: const TextStyle(
                    fontFamily: 'Cairo', fontSize: 12.5, color: SdColors.muted)),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  void _snack(String msg, SdStatus status) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: status.tone.base,
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  البناء
  // ═══════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: true,
      maxWidth: 720,
      appBar: SdAppBar(title: 'إضافة مشغّل جديد'),
      body: _loadingPartners
          ? const SizedBox(
              height: 400, child: Center(child: CircularProgressIndicator()))
          : _partnersError != null
              ? SizedBox(
                  height: 400,
                  child: Center(
                    child: SdEmptyState(
                      title: _partnersError!,
                      icon: Icons.error_outline,
                      status: SdStatus.danger,
                      action: SdButton(
                          label: 'إعادة المحاولة',
                          icon: Icons.refresh,
                          onPressed: _loadPartners),
                    ),
                  ),
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _partnerCard(),
                      const SizedBox(height: 14),
                      if (_selectedPartner == null)
                        _hintCard(
                            'اختر الشريك أولاً لإظهار بقية حقول إنشاء المشغّل')
                      else if (_loadingRefs)
                        const SizedBox(
                            height: 220,
                            child: Center(child: CircularProgressIndicator()))
                      else if (_refsError != null)
                        _refsErrorCard()
                      else
                        ..._formBody(),
                    ],
                  ),
                ),
    );
  }

  Widget _partnerCard() {
    return SdCard(
      title: 'الشريك',
      subtitle: 'اختر حساب الشريك الذي يُنشأ المشغّل تحته',
      icon: Icons.handshake_outlined,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _partners.isEmpty
            ? const Text(
                'لا يوجد شركاء — أضِف شريكاً من «الشركاء الرئيسيون» أولاً.',
                style: TextStyle(fontFamily: 'Cairo', color: SdColors.faint))
            : DropdownButtonFormField<Map<String, dynamic>>(
                value: _selectedPartner,
                isExpanded: true,
                decoration: _dec('اختر الشريك *'),
                items: _partners
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            p['name']?.toString() ??
                                p['mainUsername']?.toString() ??
                                '-',
                            style: const TextStyle(
                                fontFamily: 'Cairo', fontSize: 13.5),
                          ),
                        ))
                    .toList(),
                onChanged: _submitting ? null : _onPartnerChanged,
              ),
      ),
    );
  }

  Widget _hintCard(String text) => SdCard(
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: SdColors.info, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color: SdColors.muted)),
            ),
          ],
        ),
      );

  Widget _refsErrorCard() => SdCard(
        child: Column(
          children: [
            SdEmptyState(
              title: _refsError!,
              icon: Icons.error_outline,
              status: SdStatus.danger,
              action: SdButton(
                  label: 'إعادة المحاولة',
                  icon: Icons.refresh,
                  onPressed: () => _onPartnerChanged(_selectedPartner)),
            ),
          ],
        ),
      );

  List<Widget> _formBody() {
    return [
      // ─── معلومات المشغّل ───
      SdCard(
        title: 'معلومات المشغّل',
        icon: Icons.badge_outlined,
        child: Column(
          children: [
            const SizedBox(height: 8),
            TextFormField(
              controller: _usernameCtrl,
              decoration: _dec('اسم المستخدم *', suffix: _usernameSuffix()),
              onChanged: _onUsernameChanged,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstNameCtrl,
                    decoration: _dec('الاسم الأول *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lastNameCtrl,
                    decoration: _dec('الاسم الأخير *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                LengthLimitingTextInputFormatter(14),
              ],
              decoration: _dec('رقم الهاتف *', hint: '07XXXXXXXXX'),
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.isEmpty) return 'مطلوب';
                if (s.replaceAll('+', '').length < 10) return 'رقم غير صحيح';
                return null;
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // ─── كلمة المرور ───
      SdCard(
        title: 'كلمة المرور',
        icon: Icons.lock_outline,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              decoration: _dec(
                'كلمة المرور *',
                suffix: IconButton(
                  icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: 20,
                      color: SdColors.muted),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (_) => _passwordValid ? null : 'لا تطابق السياسة',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: _passwordChecks
                  .map((c) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              c.$2
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 15,
                              color:
                                  c.$2 ? SdColors.success : SdColors.faint),
                          const SizedBox(width: 4),
                          Text(c.$1,
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11.5,
                                  color: c.$2
                                      ? SdColors.success
                                      : SdColors.muted)),
                        ],
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // ─── الدور ───
      SdCard(
        title: 'الدور',
        icon: Icons.admin_panel_settings_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            DropdownButtonFormField<Map<String, dynamic>>(
              value: _selectedRole,
              isExpanded: true,
              decoration: _dec('اختر الدور *'),
              items: _roles
                  .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text(r['displayValue']?.toString() ?? '-',
                            style: const TextStyle(
                                fontFamily: 'Cairo', fontSize: 13.5)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() {
                _selectedRole = v;
                if (!_zonesRequired) _selectedZones.clear();
              }),
              validator: (v) => v == null ? 'مطلوب' : null,
            ),
            if (_selectedRole != null && _selectedRole!['description'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_selectedRole!['description'].toString(),
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        color: SdColors.muted)),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // ─── المناطق ───
      if (_zonesRequired)
        SdCard(
          title: 'المناطق (الزونات) *',
          subtitle: 'المناطق التي يصل إليها المشغّل',
          icon: Icons.map_outlined,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: _zones.isEmpty ? null : _openZonePicker,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: SdColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: SdColors.edge),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.checklist_rtl,
                            size: 20, color: SdColors.muted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _selectedZones.isEmpty
                                ? 'اختر المناطق'
                                : '${_selectedZones.length} منطقة مختارة',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13.5,
                                color: _selectedZones.isEmpty
                                    ? SdColors.faint
                                    : SdColors.primary,
                                fontWeight: _selectedZones.isEmpty
                                    ? FontWeight.w400
                                    : FontWeight.w700),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down,
                            color: SdColors.muted),
                      ],
                    ),
                  ),
                ),
                if (_selectedZones.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _selectedZones.map((id) {
                      final z = _zones.firstWhere(
                          (e) => e['id'].toString() == id,
                          orElse: () => {'id': id, 'name': id});
                      return Chip(
                        label: Text(z['name'].toString(),
                            style: const TextStyle(
                                fontFamily: 'Cairo', fontSize: 11)),
                        backgroundColor: SdColors.accentTint,
                        side: BorderSide(color: SdColors.accentTintEdge),
                        onDeleted: () =>
                            setState(() => _selectedZones.remove(id)),
                        deleteIconColor: SdColors.danger,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        )
      else
        const SdCard(
          title: 'المناطق',
          icon: Icons.public,
          child: Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('هذا الدور يصل إلى كل مناطق الشريك.',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    color: SdColors.muted)),
          ),
        ),
      const SizedBox(height: 14),

      // ─── المحفظة ───
      SdCard(
        title: 'المحفظة',
        icon: Icons.account_balance_wallet_outlined,
        tone: SdStatus.warning.tone,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'إنشاء محفظة للمشغّل'
                    '${_hasWallet ? ' — تحديد الرصيد يحرّك مالاً' : ''}',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                SdToggle(
                  value: _hasWallet,
                  onChanged: (v) => setState(() => _hasWallet = v),
                ),
              ],
            ),
            if (_hasWallet) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _balanceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _dec('الرصيد المبدئي (د.ع)', hint: '0'),
              ),
              const SizedBox(height: 6),
              const Text(
                '⚠️ الرصيد يُخصم من محفظة الشريك الرئيسية على نظام FTTH.',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    color: Color(0xFF8D6E00),
                    fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),

      SdButton(
        label: 'إنشاء المشغّل',
        icon: Icons.person_add_alt_1,
        kind: SdButtonKind.accent,
        expand: true,
        isLoading: _submitting,
        onPressed: _submitting ? null : _submit,
      ),
      const SizedBox(height: 8),
    ];
  }

  Widget? _usernameSuffix() {
    if (_checkingUsername) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_usernameAvailable == true) {
      return const Icon(Icons.check_circle, color: SdColors.success, size: 20);
    }
    if (_usernameAvailable == false) {
      return const Icon(Icons.cancel, color: SdColors.danger, size: 20);
    }
    return null;
  }

  InputDecoration _dec(String label, {String? hint, Widget? suffix}) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffix,
      labelStyle: const TextStyle(fontFamily: 'Cairo', color: SdColors.muted),
      hintStyle: const TextStyle(fontFamily: 'Cairo', color: SdColors.faint),
      filled: true,
      fillColor: SdColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: border(SdColors.edge),
      enabledBorder: border(SdColors.edge),
      focusedBorder: border(SdColors.accent, 1.5),
      errorBorder: border(SdColors.danger),
      focusedErrorBorder: border(SdColors.danger, 1.5),
    );
  }
}
