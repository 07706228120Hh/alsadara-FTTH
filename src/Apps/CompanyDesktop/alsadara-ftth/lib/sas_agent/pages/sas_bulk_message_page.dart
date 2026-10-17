import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../../frontend/frontend.dart';
import '../models/sas_account.dart';
import '../models/sas_subscriber.dart';
import '../services/sas_agent_api_service.dart';
import '../whatsapp/whatsapp.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_state_views.dart';

/// صفحة «إرسال جماعي» — ترسل رسالة واتساب (قالب أو نصّ مخصّص) لمجموعة مشتركين
/// **مفلترة** حسب: الباقة (profile) · المدير الفرعي (parent) · الحالة (نشط/منتهٍ).
///
/// تعيد استخدام البنية القائمة:
///  • [SasAgentApiService.getLocalSubscribers] لجلب المشتركين سريعاً من قاعدة
///    الصدارة (بعد المزامنة) بحدٍّ معقول، لا تحميل حيّ ثقيل من الساس.
///  • نموذج [SasSubscriber] (اسم/يوزر/باقة/حالة/هاتف/انتهاء + `raw` للمدير).
///  • ورقة الإرسال الجماعي [showWaBulkSheet] التي تتولّى القالب/النصّ المخصّص/
///    الخادم/المعاينة/التقدّم. فلا نفرض قالباً هنا.
///
/// الفلترة **client-side** على المجلوب. لا منطق مالي — رسائل واتساب فقط.
/// العزل (شركة + مالك + صلاحية `sas_agent`) يفرضه الخادم؛ لا نمرّر أي هوية هنا.
class SasBulkMessagePage extends StatefulWidget {
  final SasAccount account;
  const SasBulkMessagePage({super.key, required this.account});

  @override
  State<SasBulkMessagePage> createState() => _SasBulkMessagePageState();
}

/// فلتر الحالة.
enum _StatusFilter { all, active, expired }

class _SasBulkMessagePageState extends State<SasBulkMessagePage> {
  final _api = SasAgentApiService.instance;

  /// حدّ أقصى منطقي لجلب دفعة واحدة — لا نُثقل الواجهة. إن بلغه الإجمالي المحلي
  /// ننبّه المستخدم أن القائمة مقتطعة.
  static const int _fetchLimit = 500;

  /// أزرار الأيام السريعة لفلتر «المنتهي قريباً».
  static const _quickDays = <int>[1, 2, 3, 7];

  List<SasSubscriber> _all = [];
  int _localTotal = 0;
  bool _truncated = false;

  bool _loading = false;
  bool _fetched = false;
  String? _error;

  // فلاتر مُختارة
  String? _profile; // null = كل الباقات
  String? _parent; // null = كل المدراء
  _StatusFilter _status = _StatusFilter.all;

  // فلتر «المنتهي قريباً» — مفعّل افتراضياً، N=1 يوم.
  bool _expiringSoon = true;
  int _soonDays = 1;
  final _customDaysCtl = TextEditingController();

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _customDaysCtl.dispose();
    super.dispose();
  }

  void _setSoonDays(int days) {
    if (days < 1) days = 1;
    if (days > 365) days = 365;
    setState(() {
      _soonDays = days;
      _expiringSoon = true;
    });
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
      backgroundColor: error ? SdColors.danger : SdColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
      _fetched = true;
    });
    try {
      final page = await _api.getLocalSubscribers(
        widget.account.id,
        count: _fetchLimit,
      );
      if (!mounted) return;
      final rows = page.subscribers.map(SasSubscriber.fromJson).toList();
      setState(() {
        _all = rows;
        _localTotal = page.total;
        _truncated = page.total > rows.length;
        // أعد ضبط الفلاتر التي لم تعد قيمها موجودة.
        if (_profile != null && !_profiles.contains(_profile)) _profile = null;
        if (_parent != null && !_parents.contains(_parent)) _parent = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────────────── استخراج الحقول ───────────────────────────

  /// رقم هاتف المشترك من الحقول الخام (أُضيف خادمياً كـ`phone`).
  String _phoneOf(SasSubscriber s) =>
      (s.raw['phone'] ?? s.raw['phone_norm'] ?? s.raw['mobile'] ?? '')
          .toString()
          .trim();

  /// المدير الفرعي (parent) من الحقول الخام — الشكل يعتمد على نظام الساس،
  /// نقرأ بمرونة؛ قد يغيب فيعود فارغاً.
  String _parentOf(SasSubscriber s) => (s.raw['parent'] ??
          s.raw['parent_username'] ??
          s.raw['parentUsername'] ??
          s.raw['owner'] ??
          s.raw['owner_username'] ??
          s.raw['manager'] ??
          s.raw['manager_name'] ??
          s.raw['reseller'] ??
          s.raw['admin_name'] ??
          s.raw['created_by'] ??
          '')
      .toString()
      .trim();

  String _profileOf(SasSubscriber s) => s.profileLabel == '-' ? '' : s.profileLabel;

  /// يحسب الأيام المتبقّية حتى تاريخ الانتهاء (قد يكون سالباً إن انتهى)؛
  /// نفس منطق `sas_reminders_page._daysUntil`. يعود null إن غاب/تعذّر التاريخ.
  int? _daysUntil(String? expiry) {
    if (expiry == null || expiry.trim().isEmpty) return null;
    final datePart = expiry.split(' ').first;
    final dt = DateTime.tryParse(datePart);
    if (dt == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    return target.difference(today).inDays;
  }

  /// قيم الباقات الفريدة (مرتّبة) المستخرَجة من القائمة.
  List<String> get _profiles {
    final set = <String>{};
    for (final s in _all) {
      final p = _profileOf(s);
      if (p.isNotEmpty) set.add(p);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// قيم المدراء الفرعيّين الفريدة (مرتّبة).
  List<String> get _parents {
    final set = <String>{};
    for (final s in _all) {
      final p = _parentOf(s);
      if (p.isNotEmpty) set.add(p);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// هل أي مشترك يحمل مديراً فرعياً؟ (لإظهار الفلتر فقط عند توفّر البيانات).
  bool get _hasParents => _parents.isNotEmpty;

  // ─────────────────────────── الفلترة ───────────────────────────

  List<SasSubscriber> get _filtered {
    return _all.where((s) {
      if (_profile != null && _profileOf(s) != _profile) return false;
      if (_parent != null && _parentOf(s) != _parent) return false;
      switch (_status) {
        case _StatusFilter.active:
          if (!s.isActive) return false;
          break;
        case _StatusFilter.expired:
          if (s.isActive) return false;
          break;
        case _StatusFilter.all:
          break;
      }
      // «المنتهي قريباً»: يبقى على الانتهاء ≤ N يوماً و ≥ 0 (يشمل اليوم).
      // المشتركون بلا تاريخ انتهاء صالح يُستبعَدون عند تفعيل الفلتر.
      if (_expiringSoon) {
        final d = _daysUntil(s.expiration);
        if (d == null || d < 0 || d > _soonDays) return false;
      }
      return true;
    }).toList();
  }

  /// يبني مستلِم واتساب من مشترك (نفس نمط `sas_reminders_page._recipientOf`).
  WaRecipient _recipientOf(SasSubscriber s) => WaRecipient(
        name: s.displayName,
        rawPhone: _phoneOf(s),
        vars: {
          if (s.username.isNotEmpty) 'username': s.username,
          if (_profileOf(s).isNotEmpty) 'profile': _profileOf(s),
          if (s.expiration != null && s.expiration!.trim().isNotEmpty)
            'expiration': (s.expiration ?? '').split(' ').first,
        },
      );

  int get _sendableCount =>
      _filtered.where((s) => _recipientOf(s).sendable).length;

  Future<void> _sendNow() async {
    final filtered = _filtered;
    if (filtered.isEmpty) {
      _snack('لا يوجد مشتركون ضمن الفلتر الحالي', error: true);
      return;
    }
    final recipients = filtered.map(_recipientOf).toList();
    final sendable = recipients.where((r) => r.sendable).length;
    if (sendable == 0) {
      _snack('لا يوجد أرقام هواتف صالحة ضمن الفلتر الحالي', error: true);
      return;
    }
    await showWaBulkSheet(context, recipients);
  }

  // ─────────────────────────── البناء ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return SdPage(
      maxWidth: 1000,
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: SdAppBar(
        title: 'إرسال جماعي',
        actions: [
          SdAppBarAction(
            icon: Icons.refresh_rounded,
            label: 'إعادة الجلب',
            onPressed: _loading ? null : _fetch,
          ),
        ],
      ),
      body: SasContentWrap(
        maxWidth: 1000,
        child: Column(
          children: [
            Expanded(child: _body()),
            if (_fetched && !_loading && _error == null && _all.isNotEmpty)
              _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const SasLoadingView(message: 'جاري جلب المشتركين…');
    }
    if (_error != null) {
      return SasErrorView(message: _error!, onRetry: _fetch);
    }
    if (_all.isEmpty) {
      return SasEmptyView(
        message:
            'لا مشتركون محليّون بعد — زامن المشتركين من تبويب «مشتركون» ثم أعد المحاولة',
        icon: Icons.people_outline_rounded,
        action: OutlinedButton.icon(
          onPressed: _fetch,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('إعادة الجلب', style: TextStyle(fontFamily: 'Cairo', )),
        ),
      );
    }
    final filtered = _filtered;
    return Column(
      children: [
        _filtersBar(),
        _summaryBar(filtered),
        Expanded(
          child: filtered.isEmpty
              ? const SasEmptyView(
                  message: 'لا مشتركون يطابقون الفلتر الحالي',
                  icon: Icons.filter_alt_off_rounded,
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 12.h),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => SizedBox(height: 8.h),
                  itemBuilder: (_, i) => _subscriberCard(filtered[i]),
                ),
        ),
      ],
    );
  }

  // ─────────────────────────── شريط الفلاتر ───────────────────────────

  Widget _filtersBar() {
    return Container(
      margin: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 6.h),
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt_rounded,
                  size: 18.sp, color: SdColors.primary),
              SizedBox(width: 8.w),
              Text('فلترة المستلِمين',
                  style: TextStyle(fontFamily: 'Cairo', 
                      fontSize: 13.sp, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (_profile != null || _parent != null ||
                  _status != _StatusFilter.all || _expiringSoon)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _profile = null;
                    _parent = null;
                    _status = _StatusFilter.all;
                    _expiringSoon = false;
                  }),
                  icon: Icon(Icons.clear_all_rounded, size: 16.sp),
                  label: Text('مسح',
                      style: TextStyle(fontFamily: 'Cairo', 
                          fontWeight: FontWeight.w700, fontSize: 12.sp)),
                ),
            ],
          ),
          SizedBox(height: 10.h),
          // المنتهي قريباً — مفتاح تفعيل + منتقي عدد الأيام N.
          _expiringSoonSection(),
          SizedBox(height: 12.h),
          // الحالة — رقائق.
          Text('الحالة',
              style: TextStyle(fontFamily: 'Cairo', 
                  fontSize: 11.5.sp,
                  fontWeight: FontWeight.w700,
                  color: SdColors.muted)),
          SizedBox(height: 6.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              _statusChip('الكل', _StatusFilter.all),
              _statusChip('نشط', _StatusFilter.active),
              _statusChip('منتهٍ', _StatusFilter.expired),
            ],
          ),
          SizedBox(height: 12.h),
          // الباقة + المدير — منسدلات.
          Wrap(
            spacing: 12.w,
            runSpacing: 10.h,
            children: [
              _dropdown(
                label: 'الباقة',
                icon: Icons.inventory_2_rounded,
                value: _profile,
                items: _profiles,
                onChanged: (v) => setState(() => _profile = v),
              ),
              if (_hasParents)
                _dropdown(
                  label: 'المدير الفرعي',
                  icon: Icons.supervisor_account_rounded,
                  value: _parent,
                  items: _parents,
                  onChanged: (v) => setState(() => _parent = v),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// قسم فلتر «المنتهي قريباً»: مفتاح تفعيل + أزرار أيام سريعة + حقل مخصّص.
  Widget _expiringSoonSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule_rounded,
                size: 17.sp, color: SdColors.warning),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                'المنتهي قريباً — ينتهي خلال $_soonDays يوماً',
                style: TextStyle(fontFamily: 'Cairo', 
                    fontSize: 12.sp, fontWeight: FontWeight.w700),
              ),
            ),
            Switch.adaptive(
              value: _expiringSoon,
              activeThumbColor: SdColors.primary,
              onChanged: (v) => setState(() => _expiringSoon = v),
            ),
          ],
        ),
        if (_expiringSoon) ...[
          SizedBox(height: 6.h),
          Text('يبقى على انتهائهم عدد أيام أو أقل:',
              style: TextStyle(fontFamily: 'Cairo', 
                  fontSize: 11.5.sp,
                  fontWeight: FontWeight.w700,
                  color: SdColors.muted)),
          SizedBox(height: 6.h),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (final d in _quickDays)
                ChoiceChip(
                  selected: _soonDays == d,
                  onSelected: (_) => _setSoonDays(d),
                  label: Text('$d يوم',
                      style: TextStyle(fontFamily: 'Cairo', 
                          fontWeight: FontWeight.w700,
                          color: _soonDays == d
                              ? Colors.white
                              : SdColors.muted)),
                  selectedColor: SdColors.primary,
                  backgroundColor: SdColors.faint.withValues(alpha: 0.10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
                ),
              SizedBox(
                width: 150.w,
                child: TextField(
                  controller: _customDaysCtl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: TextStyle(fontFamily: 'Cairo', 
                      fontWeight: FontWeight.w700, fontSize: 13.sp),
                  onSubmitted: (v) {
                    final n = int.tryParse(v.trim());
                    if (n != null && n > 0) _setSoonDays(n);
                  },
                  decoration: InputDecoration(
                    labelText: 'عدد مخصّص',
                    labelStyle: TextStyle(fontFamily: 'Cairo', 
                        color: SdColors.muted, fontSize: 11.5.sp),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(Icons.check_rounded, size: 18.sp),
                      onPressed: () {
                        final n = int.tryParse(_customDaysCtl.text.trim());
                        if (n != null && n > 0) _setSoonDays(n);
                      },
                    ),
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(SasUi.radiusSm.r)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _statusChip(String label, _StatusFilter value) {
    final selected = _status == value;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => setState(() => _status = value),
      label: Text(label,
          style: TextStyle(fontFamily: 'Cairo', 
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : SdColors.muted)),
      selectedColor: SdColors.primary,
      backgroundColor: SdColors.faint.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
    );
  }

  Widget _dropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: 230.w,
      child: DropdownButtonFormField<String?>(
        initialValue: value,
        isExpanded: true,
        style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5.sp, color: Colors.black87),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              TextStyle(fontFamily: 'Cairo', color: SdColors.muted, fontSize: 11.5.sp),
          isDense: true,
          prefixIcon: Icon(icon, size: 17.sp, color: SdColors.primary),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
        ),
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text('الكل',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          ),
          for (final it in items)
            DropdownMenuItem<String?>(
              value: it,
              child: Text(it, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  // ─────────────────────────── شريط العدّادات ───────────────────────────

  Widget _summaryBar(List<SasSubscriber> filtered) {
    final total = filtered.length;
    final sendable = _sendableCount;
    final noPhone = total - sendable;
    return Container(
      margin: EdgeInsets.fromLTRB(14.w, 2.h, 14.w, 2.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              SasStatusBadge(
                label: 'المفلتَر: $total',
                color: SdColors.primary,
                icon: Icons.people_rounded,
              ),
              SasStatusBadge(
                label: 'سيصلهم: $sendable',
                color: SdColors.success,
                icon: Icons.chat_rounded,
              ),
              if (noPhone > 0)
                SasStatusBadge(
                  label: 'بلا رقم: $noPhone',
                  color: SdColors.warning,
                  icon: Icons.phone_disabled_rounded,
                ),
            ],
          ),
          if (_truncated) ...[
            SizedBox(height: 8.h),
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14.sp, color: SdColors.warning),
                SizedBox(width: 6.w),
                Expanded(
                  child: Text(
                    'عُرِض ${_all.length} من إجمالي $_localTotal مشترك '
                    '(الحدّ $_fetchLimit) — ضيّق الفلاتر لإرسال دُفعات أصغر.',
                    style: TextStyle(fontFamily: 'Cairo', 
                        fontSize: 10.5.sp,
                        color: SdColors.muted,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _subscriberCard(SasSubscriber s) {
    final sendable = _recipientOf(s).sendable;
    final phone = _phoneOf(s);
    final parent = _parentOf(s);
    final daysLeft = _daysUntil(s.expiration);
    final statusColor =
        s.isActive ? SdColors.success : SdColors.danger;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        border: Border.all(
          color: sendable
              ? SdColors.faint.withValues(alpha: 0.16)
              : SdColors.warning.withValues(alpha: 0.40),
          width: sendable ? 1.2 : 1.4,
        ),
        boxShadow: SasUi.cardShadow(),
      ),
      child: Row(
        children: [
          Icon(
            sendable ? Icons.chat_rounded : Icons.phone_disabled_rounded,
            size: 22.sp,
            color: sendable ? SdColors.whatsapp : SdColors.warning,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'Cairo', 
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w800,
                            color: SdColors.ink),
                      ),
                    ),
                    if (daysLeft != null) ...[
                      SasStatusBadge(
                        label: daysLeft <= 0 ? 'منتهٍ' : 'باقٍ $daysLeft يوم',
                        color: daysLeft <= 0
                            ? SdColors.danger
                            : (daysLeft <= 2
                                ? SdColors.warning
                                : SdColors.primary),
                      ),
                      SizedBox(width: 6.w),
                    ],
                    SasStatusBadge(
                      label: s.isActive ? 'نشط' : 'منتهٍ',
                      color: statusColor,
                    ),
                  ],
                ),
                SizedBox(height: 3.h),
                Text(
                  [
                    if (s.username.isNotEmpty) s.username,
                    if (_profileOf(s).isNotEmpty) 'باقة: ${_profileOf(s)}',
                    if (parent.isNotEmpty) 'مدير: $parent',
                    if (s.expiration != null && s.expiration!.isNotEmpty)
                      'انتهاء: ${(s.expiration ?? '').split(' ').first}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Cairo', 
                      fontSize: 11.5.sp, color: SdColors.muted),
                ),
                SizedBox(height: 2.h),
                Text(
                  sendable
                      ? 'الهاتف: $phone'
                      : (phone.isNotEmpty
                          ? 'رقم غير صالح لواتساب: $phone'
                          : 'لا يوجد رقم هاتف — لن يصله الإرسال'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Cairo', 
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                    color: sendable ? SdColors.muted : SdColors.warning,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── شريط الإرسال السفلي ───────────────────────────

  Widget _bottomBar() {
    final sendable = _sendableCount;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SasUi.radius.r)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 12.h),
        child: Row(
          children: [
            Expanded(
              child: Text(
                sendable > 0
                    ? 'سيُرسَل إلى $sendable مشترك عبر واتساب (اختَر القالب أو نصّاً مخصّصاً)'
                    : 'لا يوجد أرقام صالحة ضمن الفلتر الحالي',
                style: TextStyle(fontFamily: 'Cairo', 
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: SdColors.muted),
              ),
            ),
            SizedBox(width: 10.w),
            FilledButton.icon(
              onPressed: sendable == 0 ? null : _sendNow,
              style: FilledButton.styleFrom(
                backgroundColor: SdColors.whatsapp,
                disabledBackgroundColor: SdColors.faint.withValues(alpha: 0.30),
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 13.h),
              ),
              icon: Icon(Icons.send_rounded, size: 18.sp),
              label: Text('إرسال جماعي الآن',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
