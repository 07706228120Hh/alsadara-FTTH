/// أداة «تعديل WiFi الراوتر» — Network Quality (فحص متقدّم، حسّاس)
///
/// تكتب إلى جهاز حقيقي. ضمانات: إدخال اعتماد صريح (لا دخول صامت)، قراءة الحالي
/// أولاً، تحقّق من الإدخال، حوار تأكيد صريح، تطبيق ثم تحقّق بإعادة القراءة، وعدم
/// طباعة/حفظ أي سرّ (dispose للـcontrollers). يدعم Huawei/ZTE.
library;

import 'package:flutter/material.dart';

import '../services/router_wifi_service.dart';
import '../services/url_opener.dart';
import '../widgets/depth_3d.dart';

class RouterWifiEditPage extends StatefulWidget {
  const RouterWifiEditPage({super.key, this.gatewayIp, this.api});

  final String? gatewayIp;

  /// واجهة الشبكة (تُحقن في الاختبار لعزل الاتصال الفعلي).
  final RouterWifiApi? api;

  @override
  State<RouterWifiEditPage> createState() => _RouterWifiEditPageState();
}

class _RouterWifiEditPageState extends State<RouterWifiEditPage> {
  late final RouterWifiApi _api = widget.api ?? RouterWifiService();

  final _host = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _newSsid = TextEditingController();
  final _newPass = TextEditingController();

  bool _reading = false;
  bool _applying = false;
  bool _obscurePass = true;
  bool _obscureNewPass = true;
  // نوع الراوتر اليدوي: null = تلقائي؛ أو Huawei/ZTE/Tenda/Mercusys.
  String? _brandOverride;
  RouterWifiConfig? _config; // قُرئ بنجاح ⇒ تظهر حقول التعديل
  String? _error;
  String? _resultMsg;
  bool _resultOk = false;
  bool _resultVerified = false;

  @override
  void initState() {
    super.initState();
    _host.text = widget.gatewayIp ?? '';
  }

  @override
  void dispose() {
    // مسح الأسرار من الذاكرة قدر الإمكان + تحرير الـcontrollers.
    _host.clear();
    _host.dispose();
    _user.clear();
    _user.dispose();
    _pass.clear();
    _pass.dispose();
    _newSsid.dispose();
    _newPass.clear();
    _newPass.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final host = _host.text.trim();
    if (host.isEmpty || _user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error =
          'أدخل عنوان الراوتر واسم مستخدم المدير وكلمة المرور أولاً.');
      return;
    }
    // حصر المضيف بشبكة محلية خاصة قبل إرسال أي اعتماد (يمنع التسريب لمضيف خارجي).
    if (!RouterWifiService.isPrivateLanHost(host)) {
      setState(() => _error = RouterWifiService.invalidHostMessage);
      return;
    }
    setState(() {
      _reading = true;
      _error = null;
      _resultMsg = null;
    });
    final r = await _api.read(
        host: host,
        user: _user.text.trim(),
        pass: _pass.text,
        brandOverride: _brandOverride);
    if (!mounted) return;
    setState(() {
      _reading = false;
      if (r.ok && r.config != null) {
        _config = r.config;
        _newSsid.text = r.config!.ssid;
      } else {
        _config = null;
        _error = r.error.isNotEmpty ? r.error : 'تعذّر قراءة الإعداد.';
      }
    });
  }

  /// يفتح واجهة الراوتر في المتصفح الافتراضي (حلّ مضمون لأي فيرموير).
  Future<void> _openRouterWeb() async {
    final host = _host.text.trim();
    if (host.isEmpty) {
      setState(() => _error = 'أدخل عنوان الراوتر أولاً.');
      return;
    }
    if (!RouterWifiService.isPrivateLanHost(host)) {
      setState(() => _error = RouterWifiService.invalidHostMessage);
      return;
    }
    final ok = await openUrlRobust('http://$host');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذّر فتح http://$host')));
    }
  }

  Future<void> _apply() async {
    final cfg = _config;
    if (cfg == null) return;
    final newSsid = _newSsid.text.trim();
    final newPass = _newPass.text;
    // تحقّق الإدخال.
    if (newSsid.isEmpty) {
      setState(() => _error = 'اسم الشبكة (SSID) لا يمكن أن يكون فارغاً.');
      return;
    }
    if (newPass.isNotEmpty && newPass.length < 8) {
      setState(() => _error = 'كلمة مرور WPA2 يجب ألّا تقلّ عن 8 محارف.');
      return;
    }
    final ssidChanged = newSsid != cfg.ssid;
    final passChanged = newPass.isNotEmpty;
    if (!ssidChanged && !passChanged) {
      setState(() => _error = 'لم تُدخِل أي تغيير.');
      return;
    }
    setState(() => _error = null);

    // حوار تأكيد صريح (لا تطبيق بلا تأكيد).
    final confirmed = await _confirmDialog(cfg, newSsid, passChanged);
    if (confirmed != true || !mounted) return;

    setState(() {
      _applying = true;
      _resultMsg = null;
    });
    final res = await _api.apply(
      host: _host.text.trim(),
      user: _user.text.trim(),
      pass: _pass.text,
      newSsid: ssidChanged ? newSsid : null,
      newPassword: passChanged ? newPass : null,
      brandOverride: _brandOverride,
    );
    if (!mounted) return;
    setState(() {
      _applying = false;
      _resultOk = res.ok;
      _resultVerified = res.verified;
      _resultMsg = res.message;
      if (res.ok) {
        // حدّث العرض ونظّف كلمة المرور الجديدة من الذاكرة.
        if (ssidChanged) {
          _config = RouterWifiConfig(ssid: newSsid, model: cfg.model);
        }
        _newPass.clear();
      }
    });
  }

  Future<bool?> _confirmDialog(
      RouterWifiConfig cfg, String newSsid, bool passChanged) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد تعديل WiFi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'سيتغيّر اسم/كلمة مرور شبكتك — ستحتاج إعادة توصيل كل أجهزتك '
                  'بالكلمة الجديدة، وقد ينقطع اتصالك بالراوتر لحظياً. متابعة؟'),
              const SizedBox(height: 10),
              if (newSsid != cfg.ssid)
                Text('الاسم: ${cfg.ssid}  ↦  $newSsid',
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              if (passChanged)
                const Text('كلمة المرور: ستُستبدل بالجديدة',
                    style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تأكيد',
                    style: TextStyle(
                        color: Color(0xFFC62828), fontWeight: FontWeight.w900))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Nq3d.ground,
        appBar: nq3dAppBar('تعديل WiFi الراوتر'),
        body: LayoutBuilder(
          builder: (ctx, c) {
            final w = c.maxWidth;
            final isPhone = w < 600;
            final maxContentWidth = isPhone ? w : (w >= 1024 ? 640.0 : 560.0);
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _securityNote(),
                      const SizedBox(height: 12),
                      _credentialsCard(),
                      if (_config != null) ...[
                        const SizedBox(height: 14),
                        _editCard(),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        _banner(_error!, const Color(0xFFC62828),
                            Icons.error_outline_rounded),
                        const SizedBox(height: 10),
                        // عند الفشل: اجعل فتح المتصفح بارزاً (حلّ مضمون).
                        _accessWebButton(prominent: true),
                      ],
                      if (_resultMsg != null) ...[
                        const SizedBox(height: 12),
                        // أخضر: نجاح مؤكَّد (SSID تحقّق). أصفر: أُرسل بلا تأكيد
                        // (كلمة مرور فقط). أحمر: فشل.
                        _banner(
                            _resultMsg!,
                            !_resultOk
                                ? const Color(0xFFC62828)
                                : _resultVerified
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFFE65100),
                            !_resultOk
                                ? Icons.error_outline_rounded
                                : _resultVerified
                                    ? Icons.check_circle_rounded
                                    : Icons.info_outline_rounded),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _securityNote() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFCC80)),
        ),
        child: Row(
          children: [
            const Icon(Icons.shield_outlined,
                color: Color(0xFFE65100), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'ميزة حسّاسة تكتب إلى راوترك. أدخل اعتماد مدير الراوتر صراحةً. '
                'يدعم حالياً Huawei/ZTE/Tenda؛ راوترات TP‑Link/Mercusys تستخدم '
                'دخولاً مشفّراً غير مدعوم بعد — استخدم واجهة الراوتر لها.',
                style: TextStyle(
                    fontSize: 11.5,
                    color: const Color(0xFF8A4B00),
                    height: 1.4),
              ),
            ),
          ],
        ),
      );

  Widget _credentialsCard() {
    return _card(
      icon: Icons.lock_outline_rounded,
      title: 'اعتماد مدير الراوتر',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(_host, 'عنوان الراوتر (مثل 192.168.100.1)',
              keyboard: TextInputType.number),
          const SizedBox(height: 10),
          _brandDropdown(),
          const SizedBox(height: 10),
          _field(_user, 'اسم مستخدم المدير'),
          const SizedBox(height: 10),
          _field(_pass, 'كلمة مرور المدير',
              obscure: _obscurePass,
              toggleObscure: () =>
                  setState(() => _obscurePass = !_obscurePass)),
          const SizedBox(height: 14),
          _primaryButton(
            label: _config == null ? 'قراءة الإعداد الحالي' : 'إعادة القراءة',
            icon: Icons.download_rounded,
            busy: _reading,
            onTap: _read,
          ),
          const SizedBox(height: 10),
          // حلّ مضمون لأي راوتر/فيرموير: فتح الواجهة في المتصفح.
          _accessWebButton(prominent: false),
        ],
      ),
    );
  }

  Widget _brandDropdown() {
    const items = <(String?, String)>[
      (null, 'تلقائي (كشف تلقائي)'),
      ('Huawei', 'Huawei'),
      ('ZTE', 'ZTE'),
      ('Tenda', 'Tenda'),
      ('Mercusys', 'TP-Link / Mercusys'),
    ];
    return DropdownButtonFormField<String?>(
      initialValue: _brandOverride,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'نوع الراوتر',
        labelStyle: const TextStyle(fontSize: 12.5),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF5F7FB),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
      items: [
        for (final it in items)
          DropdownMenuItem<String?>(
              value: it.$1,
              child: Text(it.$2, style: const TextStyle(fontSize: 13))),
      ],
      onChanged: (v) => setState(() => _brandOverride = v),
    );
  }

  Widget _accessWebButton({required bool prominent}) {
    return Material(
      color: prominent
          ? const Color(0xFF00695C)
          : const Color(0xFF00695C).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _openRouterWeb,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.open_in_browser_rounded,
                  size: 20,
                  color: prominent ? Colors.white : const Color(0xFF00695C)),
              const SizedBox(width: 8),
              Flexible(
                child: Text('فتح واجهة الراوتر في المتصفح',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color:
                            prominent ? Colors.white : const Color(0xFF00695C))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editCard() {
    final cfg = _config!;
    return _card(
      icon: Icons.wifi_rounded,
      title: 'الإعداد الحالي (${cfg.model})',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('الاسم الحالي: ${cfg.ssid}',
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: Nq3d.ink)),
          if (cfg.security.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('التأمين: ${cfg.security}',
                  style: TextStyle(fontSize: 11, color: Nq3d.muted)),
            ),
          const Divider(height: 22),
          _field(_newSsid, 'اسم الشبكة الجديد (SSID)'),
          const SizedBox(height: 10),
          _field(_newPass, 'كلمة المرور الجديدة (اختياري، ≥ 8 محارف)',
              obscure: _obscureNewPass,
              toggleObscure: () =>
                  setState(() => _obscureNewPass = !_obscureNewPass)),
          const SizedBox(height: 6),
          Text('اترك كلمة المرور فارغة للإبقاء عليها دون تغيير.',
              style: TextStyle(fontSize: 10.5, color: Nq3d.muted)),
          const SizedBox(height: 14),
          _primaryButton(
            label: 'تطبيق التغييرات',
            icon: Icons.save_rounded,
            busy: _applying,
            danger: true,
            onTap: _apply,
          ),
        ],
      ),
    );
  }

  // ═══════════════ عناصر مساعدة ═══════════════
  Widget _card(
      {required IconData icon,
      required String title,
      required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: raisedShadow(depth: 5, glow: const Color(0x661A237E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Nq3d.indigo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Nq3d.ink)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {bool obscure = false,
      VoidCallback? toggleObscure,
      TextInputType? keyboard}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboard,
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12.5),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF5F7FB),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        suffixIcon: toggleObscure == null
            ? null
            : IconButton(
                icon: Icon(
                    obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 18),
                onPressed: toggleObscure,
              ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required bool busy,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return Raised3D(
      onTap: busy ? null : onTap,
      radius: 14,
      depth: 5,
      padding: EdgeInsets.zero,
      edgeColor: danger ? const Color(0xFF9B1C1C) : Nq3d.indigoDark,
      glowColor: const Color(0x990F1660),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: danger
            ? const [Color(0xFFE53935), Color(0xFFB71C1C)]
            : const [Color(0xFF283593), Nq3d.indigo],
      ),
      semanticLabel: label,
      child: SizedBox(
        height: 50,
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _banner(String msg, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
