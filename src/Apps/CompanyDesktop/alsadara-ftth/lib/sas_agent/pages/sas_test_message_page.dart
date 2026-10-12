import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/vps_auth_service.dart';
import '../../theme/app_theme.dart';
import '../whatsapp/whatsapp.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_state_views.dart';

/// صفحة «إرسال رسالة تجريبية» — تحاكي رسالة واتساب ما بعد التفعيل على رقم
/// يختاره المستخدم، لاختبار التدفّق كاملاً (القالب + الإرسال) دون أي عملية مالية.
///
/// تعيد استخدام بنية الوحدة القائمة:
///  • [LocalTemplateStore] لجلب كل القوالب (الافتراضي [WaTemplateIds.renewed]).
///  • [WaTemplate.render] لبناء نصّ المعاينة الحيّ من الحقول القابلة للتعديل.
///  • [normalizeIraqiPhone] لتطبيع/التحقّق من الرقم.
///  • [WaSettingsStore.load] + `buildSender()` + `sendOne` للإرسال الفعلي
///    (آلي صامت للخادم، أو فتح wa.me للنمط اليدوي).
///
/// ⚠️ لا منطق مالي ولا أسرار — مجرّد إرسال رسالة اختبارية. العزل (شركة + مالك
/// + صلاحية `sas_agent`) يفرضه الخادم؛ لا نمرّر أي هوية هنا.
class SasTestMessagePage extends StatefulWidget {
  const SasTestMessagePage({super.key});

  @override
  State<SasTestMessagePage> createState() => _SasTestMessagePageState();
}

class _SasTestMessagePageState extends State<SasTestMessagePage> {
  // ─── الحقول القابلة للتعديل (مملوءة مسبقاً بقيم تجريبية منطقية) ───
  final _phoneCtl = TextEditingController();
  final _nameCtl = TextEditingController(text: 'مشترك تجريبي');
  final _usernameCtl = TextEditingController(text: 'test_user');
  final _planCtl = TextEditingController(text: 'باقة تجريبية');
  final _monthsCtl = TextEditingController(text: '1');
  final _priceCtl = TextEditingController(text: '25000');
  final _currencyCtl = TextEditingController(text: 'IQD');
  final _paymentCtl = TextEditingController(text: 'نقد');
  final _endDateCtl = TextEditingController();
  final _activatedByCtl = TextEditingController();
  final _daysCtl = TextEditingController(text: '1');

  /// كل القوالب المتاحة + القالب المختار حالياً.
  List<WaTemplate> _templates = [];
  String _selectedTemplateId = WaTemplateIds.renewed;
  bool _loadingTemplates = true;
  String? _templatesError;

  /// حالة الإرسال الجارية (لتعطيل الزر + مؤشّر).
  bool _sending = false;

  /// نتيجة آخر إرسال لعرضها كبطاقة حالة (null = لم يُرسَل بعد).
  _SendOutcome? _lastOutcome;
  String? _lastDetail;

  @override
  void initState() {
    super.initState();
    _endDateCtl.text = _readableDate(DateTime.now().add(const Duration(days: 30)));
    final currentName =
        VpsAuthService.instance.currentUser?.fullName.trim() ?? '';
    _activatedByCtl.text = currentName.isNotEmpty ? currentName : 'النظام';
    // أعِد بناء المعاينة مع أي تغيير في الحقول.
    for (final c in _allControllers) {
      c.addListener(_onChanged);
    }
    _loadTemplates();
  }

  List<TextEditingController> get _allControllers => [
        _phoneCtl,
        _nameCtl,
        _usernameCtl,
        _planCtl,
        _monthsCtl,
        _priceCtl,
        _currencyCtl,
        _paymentCtl,
        _endDateCtl,
        _activatedByCtl,
        _daysCtl,
      ];

  @override
  void dispose() {
    for (final c in _allControllers) {
      c.removeListener(_onChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// تاريخ مقروء بصيغة بسيطة (يوم/شهر/سنة).
  String _readableDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Future<void> _loadTemplates() async {
    setState(() {
      _loadingTemplates = true;
      _templatesError = null;
    });
    try {
      final list = await LocalTemplateStore().load();
      if (!mounted) return;
      setState(() {
        _templates = list;
        // ثبّت الافتراضي على «التفعيل/التجديد» إن وُجد؛ وإلا أوّل قالب.
        if (!list.any((t) => t.id == _selectedTemplateId) && list.isNotEmpty) {
          _selectedTemplateId = list.first.id;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _templatesError = _clean(e));
    } finally {
      if (mounted) setState(() => _loadingTemplates = false);
    }
  }

  String _clean(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();

  /// القالب المختار الحالي (أو null إن لم يُحمَّل بعد).
  WaTemplate? get _selectedTemplate {
    for (final t in _templates) {
      if (t.id == _selectedTemplateId) return t;
    }
    return _templates.isNotEmpty ? _templates.first : null;
  }

  /// خريطة المتغيّرات من الحقول الحالية (تُغذّي المعاينة والإرسال معاً).
  Map<String, String> _vars() {
    final name = _nameCtl.text.trim();
    final endDate = _endDateCtl.text.trim();
    return {
      'name': name,
      'username': _usernameCtl.text.trim(),
      'profile': _planCtl.text.trim(),
      'plan': _planCtl.text.trim(),
      'months': _monthsCtl.text.trim(),
      'price': _priceCtl.text.trim(),
      'currency': _currencyCtl.text.trim(),
      'paymentMethod': _paymentCtl.text.trim(),
      'endDate': endDate,
      'expiration': endDate,
      'activatedBy': _activatedByCtl.text.trim(),
      'days': _daysCtl.text.trim(),
    };
  }

  /// نصّ المعاينة الحيّ (القالب مملوءاً بالحقول الحالية).
  String get _preview {
    final tpl = _selectedTemplate;
    if (tpl == null) return '';
    return tpl.render(_vars());
  }

  /// الرقم المطبّع الحالي (أو null إن غير صالح).
  String? get _normalizedPhone => normalizeIraqiPhone(_phoneCtl.text);

  bool get _phoneValid => _normalizedPhone != null;

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// يبني ويُرسل الرسالة التجريبية عبر المُرسِل المضبوط حالياً.
  Future<void> _send() async {
    if (_sending) return;
    if (!_phoneValid) {
      _snack('أدخل رقم هاتف صالحاً أولاً', error: true);
      return;
    }
    final tpl = _selectedTemplate;
    if (tpl == null) {
      _snack('لا قالب متاح للإرسال', error: true);
      return;
    }

    setState(() {
      _sending = true;
      _lastOutcome = null;
      _lastDetail = null;
    });

    final name =
        _nameCtl.text.trim().isNotEmpty ? _nameCtl.text.trim() : 'مشترك تجريبي';
    final text = tpl.render(_vars());

    WaSender? sender;
    try {
      final settings = await WaSettingsStore().load();
      sender = settings.buildSender();

      // النمط اليدوي (app): sendOne يفتح wa.me — لا إرسال آلي.
      if (!sender.capabilities.automated) {
        final res = await sender.sendOne(
          WaOutgoing(
            recipient: WaRecipient(name: name, rawPhone: _phoneCtl.text.trim()),
            text: text,
          ),
        );
        _finish(
          res.ok ? _SendOutcome.opened : _SendOutcome.failed,
          detail: res.ok
              ? 'فُتحت نافذة واتساب — أرسل الرسالة يدوياً.'
              : (res.error ?? 'تعذّر فتح واتساب'),
        );
        return;
      }

      // النمط الآلي (خادم): تأكّد من الجاهزية قبل الإرسال الصامت.
      final status = await sender.status();
      if (!status.ready) {
        _finish(
          _SendOutcome.notReady,
          detail:
              'خادم واتساب غير جاهز — افتح إعدادات الواتساب واربط الجلسة (QR).',
        );
        return;
      }

      final res = await sender.sendOne(
        WaOutgoing(
          recipient: WaRecipient(name: name, rawPhone: _phoneCtl.text.trim()),
          text: text,
        ),
      );
      _finish(
        res.ok ? _SendOutcome.sent : _SendOutcome.failed,
        detail: res.ok
            ? 'أُرسلت الرسالة التجريبية إلى $_normalizedPhone'
            : (res.error ?? 'فشل الإرسال'),
      );
    } catch (e) {
      _finish(_SendOutcome.failed, detail: _clean(e));
    } finally {
      sender?.dispose();
    }
  }

  void _finish(_SendOutcome outcome, {String? detail}) {
    if (!mounted) return;
    setState(() {
      _sending = false;
      _lastOutcome = outcome;
      _lastDetail = detail;
    });
    _snack(
      outcome.label,
      error: outcome == _SendOutcome.failed || outcome == _SendOutcome.notReady,
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
          toolbarHeight: 56,
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.blueGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Text('إرسال رسالة تجريبية',
              style:
                  GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 17)),
        ),
        body: SasContentWrap(
          maxWidth: 900,
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loadingTemplates) {
      return const SasLoadingView(message: 'جاري تحميل القوالب…');
    }
    if (_templatesError != null) {
      return SasErrorView(message: _templatesError!, onRetry: _loadTemplates);
    }
    if (_templates.isEmpty) {
      return const SasEmptyView(
        message: 'لا توجد قوالب رسائل متاحة',
        icon: Icons.description_outlined,
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 24.h),
      children: [
        _banner(),
        SizedBox(height: 14.h),
        _phoneCard(),
        SizedBox(height: 12.h),
        _templateCard(),
        SizedBox(height: 12.h),
        _dataCard(),
        SizedBox(height: 12.h),
        _previewCard(),
        if (_lastOutcome != null) ...[
          SizedBox(height: 12.h),
          _outcomeCard(),
        ],
        SizedBox(height: 16.h),
        _sendButton(),
      ],
    );
  }

  // ─────────────────────────── لافتة تعريفية ───────────────────────────

  Widget _banner() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF25D366), Color(0xFF128C7E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        boxShadow: SasUi.cardShadow(const Color(0xFF25D366)),
      ),
      child: Row(
        children: [
          Container(
            width: 46.w,
            height: 46.w,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            ),
            child: Icon(Icons.send_rounded, color: Colors.white, size: 24.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'رسالة تجريبية (محاكاة ما بعد التفعيل)',
                  style: GoogleFonts.cairo(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'اختر رقماً وقالباً وعدّل البيانات لاختبار القالب + الإرسال فعلياً',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 11.5.sp,
                    color: Colors.white.withValues(alpha: 0.80),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── بطاقة رقم الهاتف ───────────────────────────

  Widget _phoneCard() {
    final normalized = _normalizedPhone;
    final hasInput = _phoneCtl.text.trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldHeader(Icons.phone_rounded, 'رقم الهاتف (يصله الاختبار)'),
          SizedBox(height: 10.h),
          TextField(
            controller: _phoneCtl,
            keyboardType: TextInputType.phone,
            style:
                GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 13.sp),
            decoration: InputDecoration(
              hintText: 'مثال: 07701234567',
              hintStyle: GoogleFonts.cairo(color: Colors.grey[400]),
              isDense: true,
              prefixIcon: const Icon(Icons.smartphone_rounded),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
            ),
          ),
          SizedBox(height: 8.h),
          if (!hasInput)
            _hintRow(
              Icons.info_outline_rounded,
              'أدخل رقم هاتف عراقياً ليُفعَّل زر الإرسال.',
              AppTheme.primaryColor,
            )
          else if (normalized != null)
            _hintRow(
              Icons.check_circle_rounded,
              'رقم صالح — سيُرسَل إلى: $normalized',
              AppTheme.successColor,
            )
          else
            _hintRow(
              Icons.warning_amber_rounded,
              'رقم غير صالح لواتساب — تأكّد من الصيغة (07XXXXXXXXX).',
              AppTheme.warningColor,
            ),
        ],
      ),
    );
  }

  // ─────────────────────────── بطاقة منتقي القالب ───────────────────────────

  Widget _templateCard() {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldHeader(Icons.description_rounded, 'القالب'),
          SizedBox(height: 10.h),
          DropdownButtonFormField<String>(
            initialValue: _selectedTemplateId,
            isExpanded: true,
            dropdownColor: Colors.white,
            iconEnabledColor: const Color(0xFF1A1A2E),
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.w700,
              fontSize: 13.sp,
              color: const Color(0xFF1A1A2E),
            ),
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
            ),
            items: [
              for (final t in _templates)
                DropdownMenuItem(
                  value: t.id,
                  child: Text(
                    t.title,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.sp,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _selectedTemplateId = v);
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── بطاقة البيانات القابلة للتعديل ───────────────────────────

  Widget _dataCard() {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldHeader(Icons.edit_note_rounded, 'بيانات القالب (قابلة للتعديل)'),
          SizedBox(height: 12.h),
          LayoutBuilder(
            builder: (context, c) {
              final two = c.maxWidth >= 560;
              final fields = <Widget>[
                _field(_nameCtl, 'الاسم', Icons.person_rounded),
                _field(_usernameCtl, 'اسم المستخدم', Icons.badge_rounded),
                _field(_planCtl, 'الباقة', Icons.wifi_rounded),
                _field(_monthsCtl, 'عدد الأشهر', Icons.calendar_month_rounded,
                    number: true),
                _field(_priceCtl, 'السعر', Icons.payments_rounded,
                    number: true),
                _field(_currencyCtl, 'العملة', Icons.attach_money_rounded),
                _field(_paymentCtl, 'طريقة الدفع', Icons.account_balance_wallet_rounded),
                _field(_endDateCtl, 'تاريخ الانتهاء', Icons.event_rounded),
                _field(_activatedByCtl, 'نفّذها', Icons.verified_user_rounded),
                _field(_daysCtl, 'الأيام', Icons.timelapse_rounded,
                    number: true),
              ];
              if (!two) {
                return Column(
                  children: [
                    for (int i = 0; i < fields.length; i++) ...[
                      if (i > 0) SizedBox(height: 10.h),
                      fields[i],
                    ],
                  ],
                );
              }
              final rows = <Widget>[];
              for (int i = 0; i < fields.length; i += 2) {
                if (rows.isNotEmpty) rows.add(SizedBox(height: 10.h));
                rows.add(Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: fields[i]),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: i + 1 < fields.length
                          ? fields[i + 1]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ));
              }
              return Column(children: rows);
            },
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctl, String label, IconData icon,
      {bool number = false}) {
    return TextField(
      controller: ctl,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 12.5.sp),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            GoogleFonts.cairo(color: Colors.grey[600], fontSize: 11.5.sp),
        isDense: true,
        prefixIcon: Icon(icon, size: 18.sp),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
      ),
    );
  }

  // ─────────────────────────── بطاقة المعاينة الحيّة ───────────────────────────

  Widget _previewCard() {
    final preview = _preview;
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldHeader(Icons.visibility_rounded, 'معاينة الرسالة'),
          SizedBox(height: 10.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: const Color(0xFFE7FFDB),
              borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
              border: Border.all(
                  color: const Color(0xFF25D366).withValues(alpha: 0.30)),
            ),
            child: Text(
              preview.isEmpty ? '— لا محتوى —' : preview,
              style: GoogleFonts.cairo(
                fontSize: 12.5.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A2E),
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── بطاقة نتيجة الإرسال ───────────────────────────

  Widget _outcomeCard() {
    final o = _lastOutcome!;
    final color = o.color;
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 1.3),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(o.icon, color: color, size: 22.sp),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.label,
                    style: GoogleFonts.cairo(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w800,
                        color: color)),
                if (_lastDetail != null && _lastDetail!.isNotEmpty) ...[
                  SizedBox(height: 3.h),
                  Text(_lastDetail!,
                      style: GoogleFonts.cairo(
                          fontSize: 11.5.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── زر الإرسال ───────────────────────────

  Widget _sendButton() {
    final enabled = _phoneValid && !_sending;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: enabled ? _send : null,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF25D366),
          disabledBackgroundColor: Colors.grey.withValues(alpha: 0.30),
          padding: EdgeInsets.symmetric(vertical: 14.h),
        ),
        icon: _sending
            ? SizedBox(
                width: 16.w,
                height: 16.w,
                child: const CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(Icons.send_rounded, size: 19.sp),
        label: Text(_sending ? 'جاري الإرسال…' : 'إرسال تجريبي',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
      ),
    );
  }

  // ─────────────────────────── مساعدات عرض ───────────────────────────

  Widget _fieldHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18.sp, color: AppTheme.primaryColor),
        SizedBox(width: 8.w),
        Text(title,
            style: GoogleFonts.cairo(
                fontSize: 13.sp, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _hintRow(IconData icon, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15.sp, color: color),
        SizedBox(width: 6.w),
        Expanded(
          child: Text(text,
              style: GoogleFonts.cairo(
                  fontSize: 11.sp, fontWeight: FontWeight.w600, color: color)),
        ),
      ],
    );
  }
}

/// نتيجة الإرسال التجريبي (لعرض بطاقة الحالة + SnackBar).
enum _SendOutcome { sent, opened, notReady, failed }

extension _SendOutcomeX on _SendOutcome {
  String get label {
    switch (this) {
      case _SendOutcome.sent:
        return 'أُرسلت الرسالة التجريبية ✓';
      case _SendOutcome.opened:
        return 'فُتحت نافذة واتساب — أرسلها يدوياً';
      case _SendOutcome.notReady:
        return 'خادم واتساب غير جاهز';
      case _SendOutcome.failed:
        return 'فشل الإرسال';
    }
  }

  IconData get icon {
    switch (this) {
      case _SendOutcome.sent:
        return Icons.check_circle_rounded;
      case _SendOutcome.opened:
        return Icons.open_in_new_rounded;
      case _SendOutcome.notReady:
        return Icons.link_off_rounded;
      case _SendOutcome.failed:
        return Icons.error_outline_rounded;
    }
  }

  Color get color {
    switch (this) {
      case _SendOutcome.sent:
        return AppTheme.successColor;
      case _SendOutcome.opened:
        return AppTheme.primaryColor;
      case _SendOutcome.notReady:
        return AppTheme.warningColor;
      case _SendOutcome.failed:
        return AppTheme.errorColor;
    }
  }
}
