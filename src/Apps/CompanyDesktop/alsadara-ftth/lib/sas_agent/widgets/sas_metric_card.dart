import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import 'sas_metrics.dart';

/// بطاقة عدّاد **فاخرة (premium)** لوحدة «وكيل الساس» — عرض فقط، بلا منطق أعمال.
///
/// عناصر الفخامة:
/// - **أرقام متحرّكة تتصاعد (count-up)**: عند أول ظهور ومع كل تغيّر قيمة يتحرّك
///   الرقم بسلاسة من القيمة **السابقة** إلى الجديدة عبر [TweenAnimationBuilder]
///   (منحنى `easeOutCubic`، ~800ms). التحديث الدوري (كل 45ث) لا يُسبّب وميضاً:
///   تبدأ الحركة من القيمة الحالية لا من صفر.
/// - **أرقام tabular** (بلا اهتزاز عرض) بخط Cairo عريض.
/// - **تدرّج + ظلّ متوهّج ملوّن (glow)** بلون المقياس لإحساس الارتفاع.
/// - **شارة أيقونة متدرّجة** بتوهّج خفيف.
/// - **micro-interaction** على سطح المكتب: `MouseRegion` + `AnimatedScale` + رفع
///   طفيف للظل عند المرور (hover).
///
/// ### منع الـoverflow في الشاشة الواحدة
/// المحتوى النصّي ملفوف بـ [FittedBox]`(scaleDown)` فيتقلّص بدل أن يفيض داخل
/// خلايا الشبكة الصغيرة (2×2). الحشوة/المقاسات مضغوطة وتتناسب مع الخلية.
class SasMetricCard extends StatefulWidget {
  /// القيمة العددية الحالية (يُحرّك العدّاد نحوها).
  final num value;

  /// منسّق العرض للرقم المتحرّك. الافتراضي: عدد صحيح بلا كسور.
  /// للمالية يُمرَّر منسّق M/K. يُستدعى على القيمة **المتحرّكة** كل إطار.
  final String Function(num animatedValue)? formatter;

  /// التسمية أسفل الرقم.
  final String label;

  /// لون المقياس (أخضر=نشط · برتقالي=منتهٍ · أزرق=متصل · بنفسجي=إجمالي…).
  final Color color;

  /// أيقونة الشارة.
  final IconData icon;

  /// نقرة اختيارية (تُظهر سهمًا خفيفًا وتفعّل تفاعل المرور).
  final VoidCallback? onTap;

  /// تخطيط أفقي مضغوط (أيقونة يمين الرقم) للخلايا القصيرة — الافتراضي أفقي
  /// لأن الشبكة 2×2 في الشاشة الواحدة قصيرة الارتفاع.
  final bool horizontal;

  const SasMetricCard({
    super.key,
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
    this.formatter,
    this.onTap,
    this.horizontal = true,
  });

  @override
  State<SasMetricCard> createState() => _SasMetricCardState();
}

class _SasMetricCardState extends State<SasMetricCard> {
  /// القيمة التي بدأت منها الحركة الحالية (سابقة القيمة) — تمنع البدء من الصفر
  /// عند كل تحديث دوري، فلا وميض.
  late num _from;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    // أوّل ظهور فقط: يتصاعد الرقم من 0 (تأثير الدخول الفاخر).
    // بعدها في [didUpdateWidget] يبدأ من القيمة **السابقة** فلا وميض عند التحديث.
    _from = 0;
  }

  @override
  void didUpdateWidget(covariant SasMetricCard old) {
    super.didUpdateWidget(old);
    // عند تغيّر القيمة: ابدأ الحركة الجديدة من القيمة **القديمة** (سلاسة بلا وميض).
    if (old.value != widget.value) {
      _from = old.value;
    }
  }

  String _format(num v) =>
      widget.formatter?.call(v) ?? '${v.round()}';

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final tappable = widget.onTap != null;

    final card = TweenAnimationBuilder<double>(
      // نحرّك مضاعِفًا من _from إلى value؛ المفتاح بالقيمة يضمن إعادة التشغيل
      // عند كل تغيّر فقط (لا AnimationController دائم — حركة لمرّة واحدة).
      key: ValueKey<num>(widget.value),
      tween: Tween<double>(
        begin: _from.toDouble(),
        end: widget.value.toDouble(),
      ),
      duration: const Duration(milliseconds: 820),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return _surface(
          color: color,
          tappable: tappable,
          numberText: _format(animated),
        );
      },
    );

    // micro-interaction: تكبير طفيف + رفع ظل عند المرور (سطح المكتب).
    final interactive = MouseRegion(
      cursor: tappable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: card,
      ),
    );

    if (!tappable) return interactive;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(20.r),
        onTap: widget.onTap,
        child: interactive,
      ),
    );
  }

  /// السطح المرئي: خلفية متدرّجة + حدّ متدرّج رفيع + ظل متوهّج ملوّن + محتوى.
  Widget _surface({
    required Color color,
    required bool tappable,
    required String numberText,
  }) {
    // ظل متوهّج ملوّن (glow) يرتفع عند المرور — لا رمادي فقط.
    final glow = <BoxShadow>[
      BoxShadow(
        color: color.withValues(alpha: _hover ? 0.32 : 0.20),
        blurRadius: _hover ? 22 : 15,
        spreadRadius: _hover ? -2 : -4,
        offset: Offset(0, _hover ? 9 : 6),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.03),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 11.h),
      decoration: BoxDecoration(
        // تدرّج ناعم مرتبط بلون المقياس.
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.16),
            color.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.35),
          ],
          stops: const [0.0, 0.55, 1.0],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20.r),
        // حدّ متدرّج رفيع (لمسة زجاجية).
        border: Border.all(
          color: color.withValues(alpha: _hover ? 0.42 : 0.26),
          width: 1.3,
        ),
        boxShadow: glow,
      ),
      child: widget.horizontal
          ? _horizontalContent(color, numberText, tappable)
          : _verticalContent(color, numberText, tappable),
    );
  }

  /// تخطيط أفقي مضغوط: شارة أيقونة + (رقم فوق تسمية) — مناسب للخلايا القصيرة.
  Widget _horizontalContent(Color color, String numberText, bool tappable) {
    return Row(
      children: [
        _iconBadge(color),
        SizedBox(width: 11.w),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _number(color, numberText),
                SizedBox(height: 2.h),
                _labelText(),
              ],
            ),
          ),
        ),
        if (tappable)
          Icon(Icons.chevron_left_rounded,
              size: 18.sp, color: color.withValues(alpha: 0.55)),
      ],
    );
  }

  /// تخطيط عمودي (أيقونة أعلى، رقم بارز، ثم تسمية) للبطاقات الأوسع.
  Widget _verticalContent(Color color, String numberText, bool tappable) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _iconBadge(color),
            const Spacer(),
            if (tappable)
              Icon(Icons.chevron_left_rounded,
                  size: 18.sp, color: color.withValues(alpha: 0.55)),
          ],
        ),
        SizedBox(height: 10.h),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: _number(color, numberText),
        ),
        SizedBox(height: 2.h),
        _labelText(),
      ],
    );
  }

  /// شارة أيقونة متدرّجة بتوهّج خفيف.
  Widget _iconBadge(Color color) {
    return Container(
      width: 38.w,
      height: 38.w,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.38),
            blurRadius: 9,
            spreadRadius: -2,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(widget.icon, color: Colors.white, size: 20.sp),
    );
  }

  /// الرقم البارز — أرقام tabular (بلا اهتزاز عرض) بخط Cairo عريض.
  Widget _number(Color color, String text) {
    return Text(
      text,
      maxLines: 1,
      style: GoogleFonts.cairo(
        fontSize: 21.sp,
        fontWeight: FontWeight.w900,
        color: color,
        height: 1.05,
        letterSpacing: 0.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _labelText() {
    return Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.cairo(
        fontSize: 11.sp,
        color: AppTheme.primaryColor.withValues(alpha: 0.62),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
