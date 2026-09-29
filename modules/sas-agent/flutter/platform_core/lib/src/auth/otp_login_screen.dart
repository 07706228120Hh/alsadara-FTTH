import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../api/api_core.dart';
import '../api/subscriber_api.dart';
import '../theme/brand.dart';
import '../theme/tokens.dart';
import '../widgets/banner.dart';
import '../widgets/inputs.dart';
import 'auth_scaffold.dart';

/// دخول المشترك: رقم الهاتف → رمز واتساب (6 أرقام) → جلسة. بنفس التخطيط الموحّد.
class OtpLoginScreen extends StatefulWidget {
  final SubscriberApi api;
  final VoidCallback onLoggedIn;
  const OtpLoginScreen({super.key, required this.api, required this.onLoggedIn});
  @override
  State<OtpLoginScreen> createState() => _OtpLoginScreenState();
}

class _OtpLoginScreenState extends State<OtpLoginScreen> {
  final _phone = TextEditingController();
  final _pin = GlobalKey<PinFieldState>();
  bool _sent = false;
  bool _busy = false;
  String? _error;
  String _masked = '';
  String? _devCode;
  String _code = '';
  int _seconds = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    super.dispose();
  }

  void _startTimer(int s) {
    _timer?.cancel();
    setState(() => _seconds = s);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _seconds = (_seconds - 1).clamp(0, 9999));
      if (_seconds == 0) t.cancel();
    });
  }

  Future<void> _request() async {
    if (!PhoneField.isValid(_phone.text)) {
      setState(() => _error = 'أدخل رقم هاتف عراقياً صحيحاً مثل 07701234567');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.api.requestOtp(PhoneField.normalize(_phone.text));
      setState(() {
        _sent = true;
        _masked = r.masked;
        _devCode = r.devCode;
        _code = '';
      });
      _startTimer(r.expiresIn.clamp(30, 600));
    } on ApiException catch (e) {
      setState(() => _error = e.status == 404
          ? 'لا يوجد اشتراك مرتبط بهذا الرقم — تأكّد أن شركتك سجّلت رقمك'
          : e.message);
    } catch (_) {
      setState(() => _error = 'تعذّر الاتصال بالخادم');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify([String? code]) async {
    final c = (code ?? _code).trim();
    if (c.length < 4) {
      setState(() => _error = 'أدخل الرمز المرسَل إلى واتساب');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.verifyOtp(PhoneField.normalize(_phone.text), c);
      widget.onLoggedIn();
    } on ApiException catch (e) {
      setState(() => _error = e.status == 404
          ? 'لا يوجد اشتراك مرتبط بهذا الرقم — تأكّد أن شركتك سجّلت رقمك'
          : (e.unauthorized || e.status == 400 ? 'الرمز غير صحيح أو انتهت صلاحيته' : e.message));
      _pin.currentState?.clear();
    } catch (_) {
      setState(() => _error = 'تعذّر الاتصال بالخادم');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pal = context.pal;
    return AuthScaffold(
      brand: AppBrand.subscribers,
      formTitle: _sent ? 'أدخل رمز التحقّق' : 'الدخول برقم الهاتف',
      hint: _sent
          ? 'أُرسل رمز من 6 أرقام إلى واتساب على الرقم $_masked'
          : 'سنرسل رمز الدخول إلى واتساب على رقمك المسجّل لدى شركة الإنترنت — لا حاجة لكلمة مرور',
      highlights: const [
        'اشتراكاتك لدى كل الشركات في مكان واحد',
        'قدّم شكوى أو طلباً وتابع الردّ لحظة بلحظة',
        'دخول آمن برمز واتساب — بلا كلمة مرور',
      ],
      form: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (!_sent) ...[
          PhoneField(controller: _phone, enabled: !_busy, autofocus: true, onSubmitted: (_) => _request()),
        ] else ...[
          PinField(
            key: _pin,
            enabled: !_busy,
            onChanged: (v) => _code = v,
            onCompleted: (v) {
              _code = v;
              _verify(v);
            },
          ),
          if (_devCode != null) ...[
            const SizedBox(height: 10),
            PBanner.warning('وضع التطوير — الرمز: $_devCode', dense: true),
          ],
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _sent = false;
                        _code = '';
                        _error = null;
                      }),
              icon: const Icon(PhosphorIconsBold.pencilSimple, size: 14),
              label: const Text('تغيير الرقم'),
            ),
            TextButton(
              onPressed: (_seconds > 0 || _busy) ? null : _request,
              child: Text(_seconds > 0 ? 'إعادة الإرسال بعد $_seconds ث' : 'إعادة الإرسال'),
            ),
          ]),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          PBanner.error(_error!),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _busy ? null : (_sent ? () => _verify() : _request),
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(_sent ? PhosphorIconsBold.signIn : PhosphorIconsBold.whatsappLogo, size: 18),
          label: Text(_busy ? 'لحظة…' : (_sent ? 'دخول' : 'إرسال الرمز عبر واتساب')),
        ),
        if (!_sent) ...[
          const SizedBox(height: 14),
          Text('يجب أن يكون الرقم مسجّلاً لدى شركة الإنترنت التي تشترك بها.',
              textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: pal.textMuted)),
        ],
      ]),
    );
  }
}
