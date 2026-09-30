import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../permissions/permission_manager.dart';
import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_account_form_dialog.dart';
import '../widgets/sas_state_views.dart';

/// إدارة حسابات الساس: قائمة + ربط + تعديل + حذف + تحديد الحساب الفعّال.
class SasAccountsPage extends StatefulWidget {
  /// الحساب المحدد حالياً (للتظليل).
  final SasAccount? selected;

  /// يُستدعى عند تحديد حساب لتشغيل بقية التبويبات عليه.
  final ValueChanged<SasAccount> onSelect;

  const SasAccountsPage({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  State<SasAccountsPage> createState() => SasAccountsPageState();
}

class SasAccountsPageState extends State<SasAccountsPage> {
  final _api = SasAgentApiService.instance;

  List<SasAccount> _accounts = [];
  bool _loading = true;
  String? _error;

  bool get _canManage => PermissionManager.instance.canAdd('sas_agent');

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.getAccounts();
      if (!mounted) return;
      setState(() => _accounts = list);
      // تحديد تلقائي لأول حساب مفعّل إن لم يكن هناك تحديد.
      if (widget.selected == null && list.isNotEmpty) {
        final first =
            list.firstWhere((a) => a.isActive, orElse: () => list.first);
        widget.onSelect(first);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _clean(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.cairo()),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
    ));
  }

  Future<void> _openForm({SasAccount? existing}) async {
    final result = await showDialog<SasAccountFormResult>(
      context: context,
      builder: (_) => SasAccountFormDialog(existing: existing),
    );
    if (result == null) return;
    try {
      if (existing == null) {
        final created = await _api.createAccount(
          label: result.label,
          serverUrl: result.serverUrl,
          username: result.username,
          password: result.password,
          accountType: result.accountType,
          isActive: result.isActive,
        );
        _snack('تم ربط حساب الساس بنجاح');
        await reload();
        if (created != null) widget.onSelect(created);
      } else {
        await _api.updateAccount(
          existing.id,
          label: result.label,
          serverUrl: result.serverUrl,
          username: result.username,
          password: result.password, // فارغة = بلا تغيير
          accountType: result.accountType,
          isActive: result.isActive,
        );
        _snack('تم تعديل حساب الساس بنجاح');
        await reload();
      }
    } catch (e) {
      _snack(_clean(e), error: true);
    }
  }

  Future<void> _confirmDelete(SasAccount acc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('حذف الحساب', style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          content: Text(
            'هل أنت متأكّد من حذف حساب «${acc.displayName}»؟',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('حذف', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteAccount(acc.id);
      _snack('تم حذف الحساب');
      await reload();
    } catch (e) {
      _snack(_clean(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SasLoadingView(message: 'جاري تحميل الحسابات…');
    if (_error != null) {
      return SasErrorView(message: _error!, onRetry: reload);
    }
    if (_accounts.isEmpty) {
      return SasEmptyView(
        message: 'لا توجد حسابات ساس مربوطة بعد',
        icon: Icons.link_off_rounded,
        action: _canManage
            ? FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add_link_rounded),
                label: Text('ربط حساب ساس', style: GoogleFonts.cairo()),
              )
            : null,
      );
    }

    return RefreshIndicator(
      onRefresh: reload,
      child: ListView.separated(
        padding: EdgeInsets.all(12.w),
        itemCount: _accounts.length + (_canManage ? 1 : 0),
        separatorBuilder: (_, __) => SizedBox(height: 10.h),
        itemBuilder: (context, index) {
          if (_canManage && index == _accounts.length) {
            return Padding(
              padding: EdgeInsets.only(top: 6.h),
              child: OutlinedButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add_link_rounded),
                label: Text('ربط حساب ساس جديد', style: GoogleFonts.cairo()),
              ),
            );
          }
          final acc = _accounts[index];
          final isSelected = widget.selected?.id == acc.id;
          return _accountCard(acc, isSelected);
        },
      ),
    );
  }

  Widget _accountCard(SasAccount acc, bool isSelected) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSelect(acc),
        borderRadius: BorderRadius.circular(14.r),
        child: Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryColor
                  : Colors.grey.withValues(alpha: 0.25),
              width: isSelected ? 2 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46.w,
                height: 46.w,
                decoration: BoxDecoration(
                  color: (acc.isActive ? AppTheme.successColor : Colors.grey)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  acc.accountType == SasAccountType.sasManager
                      ? Icons.supervisor_account_rounded
                      : Icons.person_rounded,
                  color: acc.isActive ? AppTheme.successColor : Colors.grey,
                  size: 22.sp,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            acc.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (isSelected) ...[
                          SizedBox(width: 6.w),
                          Icon(Icons.check_circle_rounded,
                              size: 16.sp, color: AppTheme.primaryColor),
                        ],
                      ],
                    ),
                    SizedBox(height: 3.h),
                    Text(
                      '${acc.accountType.labelAr} · ${acc.serverUrl}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 11.5.sp,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (!acc.isActive)
                      Padding(
                        padding: EdgeInsets.only(top: 3.h),
                        child: Text(
                          'غير مفعّل',
                          style: GoogleFonts.cairo(
                            fontSize: 11.sp,
                            color: AppTheme.warningColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_canManage)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (v) {
                    if (v == 'edit') _openForm(existing: acc);
                    if (v == 'delete') _confirmDelete(acc);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        const Icon(Icons.edit_rounded, size: 18),
                        SizedBox(width: 8.w),
                        Text('تعديل', style: GoogleFonts.cairo()),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_rounded,
                            size: 18, color: AppTheme.errorColor),
                        SizedBox(width: 8.w),
                        Text('حذف',
                            style: GoogleFonts.cairo(color: AppTheme.errorColor)),
                      ]),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
