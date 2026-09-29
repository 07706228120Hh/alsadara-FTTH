import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_core.dart';
import '../api/staff_api.dart';
import '../config.dart';
import '../session.dart';
import '../theme/brand.dart';
import '../widgets/banner.dart';
import '../widgets/inputs.dart';
import 'auth_scaffold.dart';

/// شاشة دخول الموظّفين (اسم مستخدم + كلمة مرور) — واحدة للوزارة والشركات والوكلاء.
/// ترفض الحساب إن لم يطابق نوع التطبيق [expected] وتوجّه المستخدم إلى التطبيق الصحيح.
class StaffLoginScreen extends StatefulWidget {
  final StaffApi api;

  /// نوع الحساب المتوقّع. إن كان null → يُقبل أي حساب موظّف (وكيل/شركة/رقابي)
  /// ويُترك التوجيه للتطبيق حسب النوع والدور (مفيد للتطبيق المستقل: وكيل + أدمن مبيّت).
  final AccountKind? expected;
  final AppBrand brand;
  final String? hint;
  final List<String> highlights;
  final VoidCallback onLoggedIn;

  /// توافق مع الاستدعاء القديم (appTitle/icon/brand:Color) — تُتجاهل، الهوية من [brand].
  const StaffLoginScreen({
    super.key,
    required this.api,
    this.expected,
    required this.brand,
    required this.onLoggedIn,
    this.hint,
    this.highlights = const [],
  });

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final _u = TextEditingController();
  final _p = TextEditingController();
  bool _busy = false;
  String? _error;
  AccountKind? _wrongKind;
  int _failures = 0;
  bool _remember = false;

  @override
  void initState() {
    super.initState();
    RememberedCredentials.load(widget.brand.slug).then((c) {
      if (c != null && mounted) {
        setState(() {
          _u.text = c.user;
          _p.text = c.pass;
          _remember = true;
        });
      }
    });
  }

  static const _defaultHints = {
    AccountKind.regulator: 'ادخل بحساب الجهة الرقابية الصادر من مدير المنصّة',
    AccountKind.company: 'ادخل بحساب الشركة الصادر من الجهة الرقابية',
    AccountKind.agent: 'ادخل بحساب الوكيل الذي أصدرته لك شركتك',
    AccountKind.subscriber: '',
  };

  static const _defaultHighlights = {
    AccountKind.regulator: [
      'نظرة وطنية على كل الشركات والوكلاء والمشتركين',
      'تدقيق بيانات SAS وكشف الدمج والمخالفات',
      'متابعة التذاكر المصعَّدة من الشركات',
    ],
    AccountKind.company: [
      'لوحة الشركة ومزامنة SAS تلقائياً',
      'إدارة الوكلاء وإصدار حساباتهم',
      'تذاكر المشتركين والتصعيد إلى الوزارة',
    ],
    AccountKind.agent: [
      'مشتركوك وحالة اشتراكاتهم من SAS',
      'تذاكر مشتركيك والردّ عليها',
      'تصريحك الشهري بعدد المشتركين',
    ],
    AccountKind.subscriber: <String>[],
  };

  @override
  void dispose() {
    _u.dispose();
    _p.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_u.text.trim().isEmpty || _p.text.isEmpty) {
      setState(() => _error = 'أدخل اسم المستخدم وكلمة المرور');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _wrongKind = null;
    });
    try {
      await widget.api.login(_u.text.trim(), _p.text, expected: widget.expected);
      if (_remember) {
        await RememberedCredentials.save(widget.brand.slug, _u.text.trim(), _p.text);
      } else {
        await RememberedCredentials.clear(widget.brand.slug);
      }
      widget.onLoggedIn();
    } on ApiException catch (e) {
      _failures++;
      setState(() {
        if (e.unauthorized) {
          _error = 'اسم المستخدم أو كلمة المرور غير صحيحة';
        } else if (e.status == 403) {
          _error = e.message;
          _wrongKind = _detectKind(e.message);
        } else if (e.status == 0 || e.status == 599) {
          _error = 'تعذّر الاتصال بالخادم — تحقّق من الشبكة أو أن الخادم يعمل';
        } else {
          _error = e.message;
        }
      });
    } catch (_) {
      setState(() => _error = 'تعذّر الاتصال بالخادم (${PlatformConfig.apiBase})');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  AccountKind? _detectKind(String msg) {
    if (msg.contains('تطبيق الوكلاء')) return AccountKind.agent;
    if (msg.contains('تطبيق الشركات')) return AccountKind.company;
    if (msg.contains('منصّة الوزارة')) return AccountKind.regulator;
    if (msg.contains('تطبيق المشتركين')) return AccountKind.subscriber;
    return null;
  }

  String _appPath(AccountKind k) => switch (k) {
        AccountKind.agent => 'agents/',
        AccountKind.company => 'companies/',
        AccountKind.regulator => 'ministry/',
        AccountKind.subscriber => 'subscribers/',
      };

  @override
  Widget build(BuildContext context) {
    final tooMany = _failures >= 5;
    return AuthScaffold(
      brand: widget.brand,
      hint: widget.hint ?? _defaultHints[widget.expected] ?? '',
      highlights: widget.highlights.isNotEmpty ? widget.highlights : (_defaultHighlights[widget.expected] ?? const []),
      form: AutofillGroup(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _u,
            enabled: !_busy,
            autofillHints: const [AutofillHints.username],
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'اسم المستخدم',
              prefixIcon: Icon(PhosphorIconsBold.user, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          PasswordField(controller: _p, enabled: !_busy, onSubmitted: (_) => _login()),
          const SizedBox(height: 6),
          RememberMeCheckbox(
            value: _remember,
            enabled: !_busy,
            onChanged: (v) => setState(() => _remember = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            PBanner.error(
              _error!,
              action: _wrongKind != null && _wrongKind != widget.expected
                  ? TextButton.icon(
                      onPressed: () {
                        final base = PlatformConfig.portalUrl.endsWith('/') ? PlatformConfig.portalUrl : '${PlatformConfig.portalUrl}/';
                        launchUrl(Uri.parse('$base${_appPath(_wrongKind!)}'), mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(PhosphorIconsBold.arrowSquareOut, size: 14),
                      label: const Text('فتح التطبيق المناسب'),
                    )
                  : null,
            ),
          ],
          if (tooMany) ...[
            const SizedBox(height: 10),
            const PBanner.warning('محاولات كثيرة فاشلة — تأكّد من بياناتك أو تواصل مع من أصدر حسابك', dense: true),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _login,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(PhosphorIconsBold.signIn, size: 18),
            label: Text(_busy ? 'جارٍ الدخول…' : 'تسجيل الدخول'),
          ),
          const SizedBox(height: 14),
          Text(
            widget.expected == AccountKind.regulator
                ? 'الحسابات تُدار من «إدارة الحسابات» داخل منصّة الوزارة'
                : 'الحساب يُصدره مدير شركتك أو الجهة الرقابية — لا يوجد تسجيل ذاتي',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      ),
    );
  }
}

/// زر خروج موحّد (يُستخدم في Rail/الإعدادات).
class LogoutButton extends StatelessWidget {
  final VoidCallback onLoggedOut;
  final bool asMenuItem;
  const LogoutButton({super.key, required this.onLoggedOut, this.asMenuItem = false});

  static Future<void> confirmAndLogout(BuildContext context, VoidCallback onLoggedOut) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تسجيل الخروج؟'),
        content: const Text('ستحتاج إلى إدخال بياناتك مجدداً للدخول.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('خروج')),
        ],
      ),
    );
    if (ok == true) {
      await Session.clear();
      onLoggedOut();
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'تسجيل الخروج',
        icon: const Icon(PhosphorIconsBold.signOut),
        onPressed: () => confirmAndLogout(context, onLoggedOut),
      );
}

/// عرض خطأ صلاحية موحّد.
String friendlyError(Object e) {
  if (e is ApiException) return e.message;
  return 'تعذّر الاتصال بالخادم';
}
