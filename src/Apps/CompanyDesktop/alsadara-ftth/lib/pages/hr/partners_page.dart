/// شاشة «الشركاء الرئيسيون» — تدير حسابات FTTH الرئيسية (الشركاء) للشركة.
///
/// «الشريك الرئيسي» = حساب FTTH رئيسي؛ حساباته الفرعية (مشغّلون) تُربط بالموظفين
/// من تبويب «الحسابات المرتبطة». تتصل ببوّابة الصدارة الداخلية
/// `/api/linked-accounts/partners/*` عبر LinkedAccountsService.
///
/// الخادم يفرض العزل (CompanyId من التوكن) والصلاحية؛ الأسرار لا تُعرض هنا.
library;

import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../../services/linked_accounts_service.dart';

/// نموذج شريك رئيسي — يطابق عقد `/api/linked-accounts/partners`.
/// لا يحمل أي كلمة مرور (لا تُعاد من الخادم إطلاقاً).
class _Partner {
  final String id;
  final String name;
  final String mainUsername;
  final String? serverUrl;
  final String? partnerAccountId;
  final bool isActive;
  final String? status;

  const _Partner({
    required this.id,
    required this.name,
    required this.mainUsername,
    this.serverUrl,
    this.partnerAccountId,
    this.isActive = true,
    this.status,
  });

  static bool _parseBool(dynamic v, {bool fallback = false}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    final s = v.toString().toLowerCase();
    return s == 'true' || s == '1';
  }

  factory _Partner.fromJson(Map<String, dynamic> j) {
    return _Partner(
      id: (j['id'] ?? j['Id'] ?? '').toString(),
      name: (j['name'] ?? j['Name'] ?? '').toString(),
      mainUsername: (j['mainUsername'] ?? j['MainUsername'] ?? '').toString(),
      serverUrl: (j['serverUrl'] ?? j['ServerUrl'])?.toString(),
      partnerAccountId:
          (j['partnerAccountId'] ?? j['PartnerAccountId'])?.toString(),
      isActive: _parseBool(j['isActive'] ?? j['IsActive'], fallback: true),
      status: (j['status'] ?? j['Status'])?.toString(),
    );
  }
}

class PartnersPage extends StatefulWidget {
  const PartnersPage({super.key});

  @override
  State<PartnersPage> createState() => _PartnersPageState();
}

class _PartnersPageState extends State<PartnersPage> {
  final _service = LinkedAccountsService.instance;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<_Partner> _partners = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _service.getPartners();
      if (!mounted) return;
      if (res['success'] == true) {
        final data = res['data'];
        final List rawList = data is List
            ? data
            : (data is Map ? (data['data'] ?? data['items'] ?? []) as List : []);
        setState(() {
          _partners = rawList
              .whereType<Map>()
              .map((e) => _Partner.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          _loading = false;
        });
      } else {
        setState(() {
          _error = (res['message'] ?? 'تعذّر جلب الشركاء الرئيسيين').toString();
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'حدث خطأ أثناء جلب الشركاء الرئيسيين';
        _loading = false;
      });
    }
  }

  void _toast(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ═══════════════ العمليات ═══════════════

  Future<void> _verify(_Partner p) async {
    setState(() => _busy = true);
    final res = await _service.verifyPartner(p.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['success'] == true) {
      final data = res['data'];
      final verified = data is Map
          ? (data['verified'] == true || data['Verified'] == true)
          : false;
      final accId = data is Map
          ? (data['partnerAccountId'] ?? data['PartnerAccountId'])?.toString()
          : null;
      final String msg;
      if (!verified) {
        msg = 'فشل التوثيق — تأكّد من بيانات الحساب الرئيسي';
      } else if (accId != null && accId.isNotEmpty) {
        msg = 'تم التوثيق وجلب معرّف الحساب ($accId) بنجاح';
      } else {
        msg = 'تم التوثيق بنجاح';
      }
      _toast(
        res['message']?.toString().isNotEmpty == true
            ? res['message'].toString()
            : msg,
        color: verified ? SdColors.success : SdColors.warning,
      );
      _load();
    } else {
      _toast(res['message']?.toString() ?? 'تعذّر التوثيق',
          color: SdColors.danger);
    }
  }

  Future<void> _delete(_Partner p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.warning_rounded, color: SdColors.danger),
              SizedBox(width: 8),
              Text('تأكيد الحذف',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'هل أنت متأكد من حذف الشريك «${p.name.isNotEmpty ? p.name : p.mainUsername}»؟',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: SdColors.danger),
              child: const Text('حذف',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    final res = await _service.deletePartner(p.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['success'] == true) {
      _toast(res['message']?.toString() ?? 'تم حذف الشريك',
          color: SdColors.success);
      _load();
    } else {
      _toast(res['message']?.toString() ?? 'تعذّر الحذف',
          color: SdColors.danger);
    }
  }

  /// حوار إضافة/تعديل شريك. كلمة المرور فارغة في التعديل = إبقاؤها بلا تغيير.
  Future<void> _openDialog({_Partner? existing}) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final userCtrl = TextEditingController(text: existing?.mainUsername ?? '');
    final passCtrl = TextEditingController();
    final serverCtrl = TextEditingController(text: existing?.serverUrl ?? '');
    bool isActive = existing?.isActive ?? true;
    bool showPass = false;
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        return StatefulBuilder(
          builder: (ctx, setD) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: EdgeInsets.symmetric(
                  horizontal: screenWidth < 600 ? 16 : 40, vertical: 24),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: SdColors.accentTint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.handshake_outlined,
                        color: SdColors.accent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isEdit ? 'تعديل شريك رئيسي' : 'إضافة شريك رئيسي',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _dialogField(nameCtrl, 'اسم الشريك', Icons.badge_outlined),
                      const SizedBox(height: 12),
                      _dialogField(userCtrl, 'اسم المستخدم الرئيسي',
                          Icons.person_outline),
                      const SizedBox(height: 12),
                      _dialogField(
                        passCtrl,
                        isEdit
                            ? 'كلمة المرور (اتركها فارغة لعدم التغيير)'
                            : 'كلمة المرور',
                        Icons.vpn_key_outlined,
                        obscure: !showPass,
                        suffix: IconButton(
                          icon: Icon(
                              showPass
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 20),
                          onPressed: () => setD(() => showPass = !showPass),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _dialogField(serverCtrl, 'رابط الخادم (اختياري)',
                          Icons.dns_outlined),
                      if (isEdit) ...[
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeColor: SdColors.accent,
                          value: isActive,
                          onChanged: (v) => setD(() => isActive = v),
                          title: const Text('شريك مُفعّل',
                              style: TextStyle(
                                  fontFamily: 'Cairo', fontSize: 13)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء',
                      style: TextStyle(fontFamily: 'Cairo')),
                ),
                ElevatedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (nameCtrl.text.trim().isEmpty) {
                            _toast('اسم الشريك مطلوب', color: SdColors.danger);
                            return;
                          }
                          if (userCtrl.text.trim().isEmpty) {
                            _toast('اسم المستخدم الرئيسي مطلوب',
                                color: SdColors.danger);
                            return;
                          }
                          if (!isEdit && passCtrl.text.isEmpty) {
                            _toast('كلمة المرور مطلوبة', color: SdColors.danger);
                            return;
                          }
                          setD(() => saving = true);
                          final Map<String, dynamic> res;
                          if (isEdit) {
                            res = await _service.updatePartner(
                              existing.id,
                              name: nameCtrl.text.trim(),
                              mainUsername: userCtrl.text.trim(),
                              mainPassword: passCtrl.text,
                              isActive: isActive,
                              serverUrl: serverCtrl.text.trim(),
                            );
                          } else {
                            res = await _service.createPartner(
                              name: nameCtrl.text.trim(),
                              mainUsername: userCtrl.text.trim(),
                              mainPassword: passCtrl.text,
                              serverUrl: serverCtrl.text.trim(),
                            );
                          }
                          if (res['success'] == true) {
                            Navigator.pop(ctx, true);
                          } else {
                            setD(() => saving = false);
                            _toast(
                                res['message']?.toString() ??
                                    'تعذّر حفظ الشريك',
                                color: SdColors.danger);
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 18),
                  label:
                      const Text('حفظ', style: TextStyle(fontFamily: 'Cairo')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SdColors.accent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    nameCtrl.dispose();
    userCtrl.dispose();
    passCtrl.dispose();
    serverCtrl.dispose();

    if (saved == true) {
      _toast(isEdit ? 'تم تعديل الشريك' : 'تمت إضافة الشريك',
          color: SdColors.success);
      _load();
    }
  }

  Widget _dialogField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ═══════════════ البناء ═══════════════

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SdColors.surfaceAlt,
        appBar: const SdAppBar(title: 'الشركاء الرئيسيون'),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: SdColors.accent));
    }
    if (_error != null) {
      return SdEmptyState(
        icon: Icons.error_outline,
        status: SdStatus.danger,
        title: _error!,
        action: SdButton(
          label: 'إعادة المحاولة',
          icon: Icons.refresh,
          onPressed: _load,
        ),
      );
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: SdSectionHeader(
                    title: 'الشركاء الرئيسيون',
                    count: _partners.length,
                  ),
                ),
                SdButton(
                  label: 'إضافة شريك',
                  icon: Icons.add_rounded,
                  kind: SdButtonKind.accent,
                  height: 44,
                  onPressed: _busy ? null : () => _openDialog(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SdColors.infoTint,
                borderRadius: BorderRadius.circular(SdRadius.sm),
                border: Border.all(color: SdColors.infoTintEdge),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: SdColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'الشريك الرئيسي حساب FTTH رئيسي؛ حساباته الفرعية (المشغّلون) '
                      'تُربط بالموظفين من تبويب «الحسابات المرتبطة».',
                      style: SdText.bodySm,
                    ),
                  ),
                ],
              ),
            ),
            if (_partners.isEmpty)
              _inlineEmpty('لا يوجد شركاء رئيسيون — اضغط «إضافة شريك».')
            else
              ..._partners.map(_partnerCard),
            const SizedBox(height: 40),
          ],
        ),
        if (_busy)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0x33000000),
              child: const Center(
                  child: CircularProgressIndicator(color: SdColors.accent)),
            ),
          ),
      ],
    );
  }

  Widget _inlineEmpty(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.md),
        border: Border.all(color: SdColors.divider),
      ),
      child: Column(
        children: [
          Icon(Icons.handshake_outlined, size: 32, color: SdColors.faint),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: SdText.bodySm),
        ],
      ),
    );
  }

  Widget _partnerCard(_Partner p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: SdColors.accentTint,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.handshake_outlined,
                      color: SdColors.accent, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p.name.isNotEmpty ? p.name : p.mainUsername,
                    style: SdText.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _statusChip(p),
              ],
            ),
            const Divider(height: 20, color: SdColors.divider),
            SdInfoRow(
              label: 'اسم المستخدم الرئيسي',
              value: p.mainUsername.isEmpty ? '—' : p.mainUsername,
              icon: Icons.person_outline,
              ltrValue: true,
            ),
            if (p.partnerAccountId != null && p.partnerAccountId!.isNotEmpty)
              SdInfoRow(
                label: 'معرّف الحساب',
                value: p.partnerAccountId!,
                icon: Icons.badge_outlined,
                ltrValue: true,
              ),
            if (p.serverUrl != null && p.serverUrl!.isNotEmpty)
              SdInfoRow(
                label: 'رابط الخادم',
                value: p.serverUrl!,
                icon: Icons.dns_outlined,
                ltrValue: true,
              ),
            if (!p.isActive)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: SdStatusChip('معطّل', status: SdStatus.neutral),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionBtn('توثيق', Icons.verified_outlined, SdColors.info,
                    () => _verify(p)),
                _actionBtn('تعديل', Icons.edit_outlined, SdColors.accent,
                    () => _openDialog(existing: p)),
                _actionBtn('حذف', Icons.delete_outline, SdColors.danger,
                    () => _delete(p)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(_Partner p) {
    final s = (p.status ?? '').toLowerCase();
    if (s == 'verified') {
      return const SdStatusChip('موثّق',
          status: SdStatus.success, icon: Icons.check_circle_outline);
    }
    if (s == 'invalid') {
      return const SdStatusChip('غير صالح',
          status: SdStatus.danger, icon: Icons.error_outline);
    }
    return const SdStatusChip('غير موثّق',
        status: SdStatus.neutral, icon: Icons.help_outline);
  }

  Widget _actionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
