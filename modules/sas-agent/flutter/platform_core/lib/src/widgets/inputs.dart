import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// حقل كلمة مرور بزر إظهار/إخفاء.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final TextInputAction textInputAction;
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'كلمة المرور',
    this.onSubmitted,
    this.enabled = true,
    this.textInputAction = TextInputAction.done,
  });
  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hide = true;
  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        obscureText: _hide,
        enabled: widget.enabled,
        autofillHints: const [AutofillHints.password],
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: const Icon(PhosphorIconsBold.lockKey, size: 18),
          suffixIcon: IconButton(
            tooltip: _hide ? 'إظهار' : 'إخفاء',
            icon: Icon(_hide ? PhosphorIconsBold.eye : PhosphorIconsBold.eyeSlash, size: 18),
            onPressed: () => setState(() => _hide = !_hide),
          ),
        ),
      );
}

/// مربّع «تذكّرني» — لحفظ اسم المستخدم وكلمة المرور محليّاً (مع [RememberedCredentials]).
class RememberMeCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final String label;
  const RememberMeCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.label = 'تذكّرني (حفظ اسم المستخدم وكلمة المرور)',
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: Radii.rSm,
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: enabled ? (v) => onChanged(v ?? false) : null,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.pal.textMuted)),
          ),
        ]),
      ),
    );
  }
}

/// تحويل الأرقام العربية-الهندية إلى لاتينية.
String latinDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in s.characters) {
    final i = ar.indexOf(ch);
    final j = fa.indexOf(ch);
    b.write(i >= 0 ? '$i' : (j >= 0 ? '$j' : ch));
  }
  return b.toString();
}

/// حقل رقم هاتف عراقي: LTR، رقمي، يقبل الأرقام العربية ويحوّلها، ويعرض +964 كبادئة ثابتة.
class PhoneField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool autofocus;
  const PhoneField({
    super.key,
    required this.controller,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
  });

  /// الرقم المطبَّع 07XXXXXXXXX (للإرسال إلى الباكند).
  static String normalize(String raw) {
    var d = latinDigits(raw).replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('00964')) d = d.substring(5);
    if (d.startsWith('964')) d = d.substring(3);
    if (d.startsWith('7') && d.length == 10) d = '0$d';
    return d;
  }

  static bool isValid(String raw) => RegExp(r'^07[3-9][0-9]{8}$').hasMatch(normalize(raw));

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        autofocus: autofocus,
        keyboardType: TextInputType.phone,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        style: PlatformType.mono(size: 16, color: context.pal.text),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-٠-٩۰-۹]')),
          LengthLimitingTextInputFormatter(16),
        ],
        autofillHints: const [AutofillHints.telephoneNumber],
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: 'رقم الهاتف',
          hintText: '0770 123 4567',
          prefixIcon: const Icon(PhosphorIconsBold.phone, size: 18),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: Center(
              widthFactor: 1,
              child: Text('+964', textDirection: TextDirection.ltr,
                  style: PlatformType.mono(size: 13, color: context.pal.textMuted)),
            ),
          ),
        ),
      );
}

/// حقل رمز OTP: خانات منفصلة، يقبل اللصق، ويُرسل تلقائياً عند الاكتمال.
class PinField extends StatefulWidget {
  final int length;
  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool autofocus;
  const PinField({
    super.key,
    this.length = 6,
    required this.onCompleted,
    this.onChanged,
    this.enabled = true,
    this.autofocus = true,
  });
  @override
  State<PinField> createState() => PinFieldState();
}

class PinFieldState extends State<PinField> {
  final _c = TextEditingController();
  final _f = FocusNode();

  String get value => _c.text;
  void clear() => setState(_c.clear);

  @override
  void initState() {
    super.initState();
    _f.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final primary = Theme.of(context).colorScheme.primary;
    final digits = _c.text;
    return GestureDetector(
      onTap: () => _f.requestFocus(),
      child: Stack(alignment: Alignment.center, children: [
        // الخانات المرئية
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < widget.length; i++) ...[
              AnimatedContainer(
                duration: Motion.fast,
                width: 44,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.isDark ? pal.surfaceVariant : Colors.white,
                  borderRadius: Radii.rMd,
                  border: Border.all(
                    color: (_f.hasFocus && i == digits.length.clamp(0, widget.length - 1)) ? primary : pal.outline,
                    width: (_f.hasFocus && i == digits.length.clamp(0, widget.length - 1)) ? 1.6 : 1,
                  ),
                ),
                child: Text(
                  i < digits.length ? digits[i] : '',
                  style: PlatformType.mono(size: 22, weight: FontWeight.w700, color: pal.text),
                ),
              ),
              if (i < widget.length - 1) const SizedBox(width: 8),
            ],
          ]),
        ),
        // الحقل الحقيقي (شفّاف) — يستقبل الإدخال واللصق والتعبئة التلقائية
        Opacity(
          opacity: 0,
          child: SizedBox(
            width: widget.length * 52.0,
            height: 52,
            child: TextField(
              controller: _c,
              focusNode: _f,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                TextInputFormatter.withFunction((o, n) => n.copyWith(
                      text: latinDigits(n.text),
                      selection: n.selection,
                    )),
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(widget.length),
              ],
              onChanged: (v) {
                setState(() {});
                widget.onChanged?.call(v);
                if (v.length == widget.length) widget.onCompleted(v);
              },
              onTap: () => setState(() {}),
              decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
            ),
          ),
        ),
      ]),
    );
  }
}
