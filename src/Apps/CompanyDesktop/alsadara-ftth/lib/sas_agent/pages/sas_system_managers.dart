import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_format.dart';
import '../widgets/sas_state_views.dart';

/// قسم «الوكلاء (Managers)» ضمن نظام الساس — قائمة الوكلاء عبر [getManagers]
/// وإجراءات مالية عبر [managerAction] (إيداع/سحب/نقاط/سداد دين/تعديل/حذف)
/// بتأكيدات. يعالج حجب الوكيل (403) بعرض حالة واضحة بدل خطأ فجّ.
class SasSystemManagers extends StatefulWidget {
  final SasAccount account;
  const SasSystemManagers({super.key, required this.account});

  @override
  State<SasSystemManagers> createState() => _SasSystemManagersState();
}

class _SasSystemManagersState extends State<SasSystemManagers> {
  final _api = SasAgentApiService.instance;
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  bool _forbidden = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  bool _isForbidden(String msg) {
    final m = msg.toLowerCase();
    return m.contains('403') ||
        m.contains('forbidden') ||
        m.contains('غير مصرّح') ||
        m.contains('غير مصرح');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _forbidden = false;
    });
    try {
      final rows = await _api.getManagers(widget.account.id);
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (e) {
      final msg = _clean(e);
      if (mounted) {
        setState(() {
          _error = msg;
          _forbidden = _isForbidden(msg);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SasLoadingView(message: 'جاري جلب الوكلاء…');
    if (_forbidden) {
      return SasEmptyView(
        message:
            'إدارة الوكلاء غير متاحة لحسابك.\nهذا الحساب لا يملك صلاحية إدارة وكلاء فرعيين في نظام الساس.',
        icon: Icons.lock_outline_rounded,
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('إعادة المحاولة', style: GoogleFonts.cairo()),
        ),
      );
    }
    if (_error != null) return SasErrorView(message: _error!, onRetry: _load);
    if (_rows.isEmpty) {
      return SasEmptyView(
        message: 'لا وكلاء فرعيون لهذا الحساب',
        icon: Icons.badge_outlined,
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('تحديث', style: GoogleFonts.cairo()),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.all(12.w),
        itemCount: _rows.length + 1,
        separatorBuilder: (_, __) => SizedBox(height: 8.h),
        itemBuilder: (context, i) {
          if (i == _rows.length) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              child: Center(
                child: Text('إجمالي الوكلاء: ${_rows.length}',
                    style: GoogleFonts.cairo(
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[700])),
              ),
            );
          }
          return _managerCard(_rows[i]);
        },
      ),
    );
  }

  Widget _managerCard(Map<String, dynamic> m) {
    final name = ('${m['firstname'] ?? ''} ${m['lastname'] ?? ''}').trim();
    final enabled = m['enabled'] != false;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(SasUi.radius.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        onTap: () => _openActions(m),
        child: Container(
          padding: EdgeInsets.all(12.w),
          decoration: SasUi.card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SasUi.gradientBadge(
                    icon: Icons.badge_rounded,
                    colors: enabled
                        ? const [AppTheme.secondaryColor, AppTheme.primaryColor]
                        : const [Color(0xFF9E9E9E), Color(0xFF757575)],
                    size: 40,
                    iconSize: 20,
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m['username'] ?? '-'}',
                            style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w800, fontSize: 14.sp)),
                        if (name.isNotEmpty)
                          Text(name,
                              style: GoogleFonts.cairo(
                                  fontSize: 11.5.sp, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  if (!enabled) const SasStatusBadge(label: 'معطّل', color: Colors.grey),
                  const Icon(Icons.more_vert_rounded, color: Colors.grey),
                ],
              ),
              SizedBox(height: 8.h),
              Wrap(
                spacing: 16.w,
                runSpacing: 4.h,
                children: [
                  SasInfoChip(
                      icon: Icons.people_rounded,
                      label: 'المشتركون',
                      value: '${m['users_count'] ?? 0}',
                      color: const Color(0xFF009688)),
                  SasInfoChip(
                      icon: Icons.account_balance_wallet_rounded,
                      label: 'الرصيد',
                      value: '${m['balance'] ?? 0}',
                      color: AppTheme.successColor),
                  SasInfoChip(
                      icon: Icons.stars_rounded,
                      label: 'النقاط',
                      value: '${m['reward_points'] ?? 0}',
                      color: AppTheme.warningColor),
                  if (m['city'] != null)
                    SasInfoChip(
                        icon: Icons.location_city_rounded,
                        label: 'المدينة',
                        value: '${m['city']}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── ورقة الإجراءات ───────────────────────────

  void _openActions(Map<String, dynamic> m) {
    final mid = (m['id'] ?? '').toString();
    if (mid.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (_) => _ManagerActionsSheet(
        account: widget.account,
        mid: mid,
        manager: m,
        onChanged: _load,
      ),
    );
  }
}

/// ورقة إجراءات وكيل (إيداع/سحب/نقاط/سداد دين/تعديل/حذف) بتأكيدات.
class _ManagerActionsSheet extends StatefulWidget {
  final SasAccount account;
  final String mid;
  final Map<String, dynamic> manager;
  final VoidCallback onChanged;
  const _ManagerActionsSheet({
    required this.account,
    required this.mid,
    required this.manager,
    required this.onChanged,
  });

  @override
  State<_ManagerActionsSheet> createState() => _ManagerActionsSheetState();
}

class _ManagerActionsSheetState extends State<_ManagerActionsSheet> {
  final _api = SasAgentApiService.instance;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.manager;
    final name = ('${m['firstname'] ?? ''} ${m['lastname'] ?? ''}').trim();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 20.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40.w,
                height: 4.h,
                margin: EdgeInsets.only(bottom: 12.h),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4.r),
                ),
              ),
            ),
            Row(
              children: [
                SasUi.gradientBadge(
                    icon: Icons.badge_rounded,
                    colors: const [AppTheme.secondaryColor, AppTheme.primaryColor],
                    size: 40,
                    iconSize: 20),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${m['username'] ?? '-'}',
                          style: GoogleFonts.cairo(
                              fontWeight: FontWeight.w800, fontSize: 15.sp)),
                      if (name.isNotEmpty)
                        Text(name,
                            style: GoogleFonts.cairo(
                                fontSize: 11.5.sp, color: Colors.grey[600])),
                    ],
                  ),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded)),
              ],
            ),
            Divider(height: 20.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                _act('إيداع رصيد', Icons.add_card_rounded, AppTheme.successColor,
                    () => _amount('deposit', 'إيداع رصيد')),
                _act('سحب رصيد', Icons.money_off_rounded, AppTheme.warningColor,
                    () => _amount('withdraw', 'سحب رصيد')),
                _act('إضافة نقاط', Icons.stars_rounded, const Color(0xFFFFB300),
                    () => _points('addRewardPoints', 'إضافة نقاط مكافأة')),
                _act('خصم نقاط', Icons.remove_circle_outline_rounded,
                    const Color(0xFFFF7043),
                    () => _points('deductRewardPoints', 'خصم نقاط مكافأة')),
                _act('سداد دين', Icons.receipt_long_rounded,
                    const Color(0xFF009688),
                    () => _amount('payDebt', 'سداد دين')),
                _act('تعديل', Icons.edit_rounded, AppTheme.secondaryColor,
                    _edit),
                _act('حذف', Icons.delete_forever_rounded, AppTheme.errorColor,
                    _delete),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _act(String label, IconData icon, Color color, VoidCallback onTap) {
    return FilledButton.tonalIcon(
      onPressed: _busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.12),
        foregroundColor: color,
      ),
      icon: Icon(icon, size: 18),
      label: Text(label,
          style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 12.5.sp)),
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.cairo()),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
    ));
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() call, String ok) async {
    setState(() => _busy = true);
    try {
      final res = await call();
      final msg = (res['message'] ?? res['status'] ?? ok).toString();
      _snack('تم: $msg');
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      final clean = e.toString().replaceFirst('Exception: ', '').trim();
      final forbidden = clean.contains('403') ||
          clean.toLowerCase().contains('forbidden');
      _snack(
          forbidden ? 'غير مصرّح لك بهذا الإجراء' : 'فشل: $clean',
          error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _amount(String action, String title) async {
    final ctl = TextEditingController();
    final ok = await _dialog(title, ctl, 'المبلغ',
        keyboard: const TextInputType.numberWithOptions(decimal: true));
    final amount = double.tryParse(ctl.text.trim());
    if (ok == true && amount != null && amount > 0) {
      if (!await _confirm(title, 'تنفيذ «$title» بقيمة $amount؟')) return;
      await _run(
          () => _api.managerAction(widget.account.id, widget.mid, action,
              params: {'amount': amount}),
          title);
    }
  }

  Future<void> _points(String action, String title) async {
    final ctl = TextEditingController();
    final ok = await _dialog(title, ctl, 'النقاط',
        keyboard: TextInputType.number);
    final pts = int.tryParse(ctl.text.trim());
    if (ok == true && pts != null && pts > 0) {
      if (!await _confirm(title, 'تنفيذ «$title» بمقدار $pts نقطة؟')) return;
      await _run(
          () => _api.managerAction(widget.account.id, widget.mid, action,
              params: {'points': pts}),
          title);
    }
  }

  Future<void> _edit() async {
    final m = widget.manager;
    final firstCtl =
        TextEditingController(text: (m['firstname'] ?? '').toString());
    final lastCtl =
        TextEditingController(text: (m['lastname'] ?? '').toString());
    final phoneCtl = TextEditingController(text: (m['phone'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تعديل بيانات الوكيل',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(firstCtl, 'الاسم الأول'),
              SizedBox(height: 10.h),
              _field(lastCtl, 'الاسم الأخير'),
              SizedBox(height: 10.h),
              _field(phoneCtl, 'الهاتف', keyboard: TextInputType.phone),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('إلغاء', style: GoogleFonts.cairo())),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('حفظ', style: GoogleFonts.cairo())),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run(
          () => _api.managerAction(widget.account.id, widget.mid, 'edit',
              params: {
                'firstname': firstCtl.text.trim(),
                'lastname': lastCtl.text.trim(),
                'phone': phoneCtl.text.trim(),
              }),
          'تعديل الوكيل');
    }
  }

  Future<void> _delete() async {
    final username = widget.manager['username'] ?? '';
    if (!await _confirm('حذف الوكيل',
        'هل أنت متأكّد من حذف الوكيل «$username»؟\nهذا الإجراء لا يمكن التراجع عنه.',
        danger: true)) {
      return;
    }
    if (!await _confirm('تأكيد نهائي',
        'تأكيد أخير: سيُحذف الوكيل بشكل دائم. المتابعة؟',
        danger: true)) {
      return;
    }
    await _run(() async {
      final ok = await _api.deleteManager(widget.account.id, widget.mid);
      return {'message': ok ? 'تم الحذف' : 'تعذّر الحذف'};
    }, 'حذف الوكيل');
  }

  // ─── حوارات مساعدة ───

  Widget _field(TextEditingController ctl, String label,
      {TextInputType? keyboard}) {
    return TextField(
      controller: ctl,
      keyboardType: keyboard,
      style: GoogleFonts.cairo(fontSize: 13.sp),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(fontSize: 12.5.sp),
      ),
    );
  }

  Future<bool?> _dialog(
      String title, TextEditingController ctl, String fieldLabel,
      {TextInputType? keyboard}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:
              Text(title, style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          content: _field(ctl, fieldLabel, keyboard: keyboard),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('إلغاء', style: GoogleFonts.cairo())),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('متابعة', style: GoogleFonts.cairo())),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(String title, String body, {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:
              Text(title, style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          content: Text(body, style: GoogleFonts.cairo()),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('إلغاء', style: GoogleFonts.cairo())),
            FilledButton(
              style: danger
                  ? FilledButton.styleFrom(backgroundColor: AppTheme.errorColor)
                  : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(danger ? 'تأكيد الحذف' : 'تأكيد',
                  style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }
}
