import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../models/sas_subscriber.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_state_views.dart';
import 'sas_subscriber_detail_page.dart';
import 'sas_subscriber_form_page.dart';

/// تبويب «مشتركون» — قائمة مشتركي الوكيل للحساب المحدد مع بحث.
class SasSubscribersTab extends StatefulWidget {
  final SasAccount account;
  const SasSubscribersTab({super.key, required this.account});

  @override
  State<SasSubscribersTab> createState() => _SasSubscribersTabState();
}

class _SasSubscribersTabState extends State<SasSubscribersTab> {
  final _api = SasAgentApiService.instance;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<SasSubscriber> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SasSubscribersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.id != widget.account.id) {
      _searchCtrl.clear();
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _api.getSubscribers(
        widget.account.id,
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        pageSize: 100,
      );
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', '').trim());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _load);
  }

  /// يفتح تفاصيل مشترك؛ يعيد التحميل إن حُذف/عُدّل من الشاشة الداخلية.
  Future<void> _openDetail(SasSubscriber s) async {
    if (s.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذّر فتح المشترك: معرّف غير متاح',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SasSubscriberDetailPage(
          account: widget.account,
          userId: s.id,
          username: s.username,
        ),
      ),
    );
    if (changed == true && mounted) _load();
  }

  /// يفتح نموذج إنشاء مشترك جديد؛ يعيد التحميل عند النجاح.
  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SasSubscriberFormPage(account: widget.account),
      ),
    );
    if (created == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 8.h),
          child: Row(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(SasUi.radius.r),
                    boxShadow: SasUi.cardShadow(),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    onSubmitted: (_) => _load(),
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'بحث عن مشترك…',
                      hintStyle: GoogleFonts.cairo(color: Colors.grey[500]),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.search_rounded,
                          color: AppTheme.primaryColor),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: Icon(Icons.clear_rounded,
                                  color: Colors.grey[500]),
                              onPressed: () {
                                _searchCtrl.clear();
                                _load();
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(SasUi.radius.r),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(SasUi.radius.r),
                        borderSide: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.16)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(SasUi.radius.r),
                        borderSide: const BorderSide(
                            color: AppTheme.primaryColor, width: 1.6),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              SizedBox(
                height: 50.h,
                child: FilledButton.icon(
                  onPressed: _openCreate,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(SasUi.radius.r)),
                  ),
                  icon: const Icon(Icons.person_add_rounded, size: 19),
                  label: Text('إنشاء مشترك',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const SasLoadingView(message: 'جاري جلب المشتركين…');
    if (_error != null) return SasErrorView(message: _error!, onRetry: _load);
    if (_rows.isEmpty) {
      return const SasEmptyView(
        message: 'لا يوجد مشتركون لعرضهم',
        icon: Icons.people_outline_rounded,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 12.h),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => SizedBox(height: 8.h),
        itemBuilder: (_, i) => _subscriberCard(_rows[i]),
      ),
    );
  }

  Widget _subscriberCard(SasSubscriber s) {
    final statusColor = s.isActive ? AppTheme.successColor : AppTheme.errorColor;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(SasUi.radius.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        onTap: () => _openDetail(s),
        child: Container(
          padding: EdgeInsets.all(12.w),
          decoration: SasUi.card(),
          child: Row(
            children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44.w,
                height: 44.w,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      statusColor.withValues(alpha: 0.18),
                      statusColor.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: statusColor.withValues(alpha: 0.22)),
                ),
                child: Icon(Icons.person_rounded,
                    color: statusColor, size: 21.sp),
              ),
              if (s.online)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 13.w,
                    height: 13.w,
                    decoration: BoxDecoration(
                      color: AppTheme.successColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.2),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.username.isEmpty ? '-' : s.username,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A2E)),
                ),
                SizedBox(height: 3.h),
                Text(
                  '${s.fullName.isEmpty ? '' : '${s.fullName} · '}باقة: ${s.profileLabel}'
                  '${s.expiration != null ? ' · انتهاء: ${s.expiration}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                      fontSize: 11.5.sp,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
              SizedBox(width: 8.w),
              SasStatusBadge(
                label: s.isActive ? 'نشط' : 'موقوف',
                color: statusColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
