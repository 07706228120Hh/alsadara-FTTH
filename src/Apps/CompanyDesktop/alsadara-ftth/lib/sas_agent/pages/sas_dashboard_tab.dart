import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../models/sas_dashboard.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_state_views.dart';

/// تبويب «لوحة» — ملخّص الوكيل للحساب المحدد.
class SasDashboardTab extends StatefulWidget {
  final SasAccount account;
  const SasDashboardTab({super.key, required this.account});

  @override
  State<SasDashboardTab> createState() => _SasDashboardTabState();
}

class _SasDashboardTabState extends State<SasDashboardTab> {
  final _api = SasAgentApiService.instance;
  SasDashboard? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SasDashboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.id != widget.account.id) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api.getDashboard(widget.account.id);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e.toString().replaceFirst('Exception: ', '').trim());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SasLoadingView(message: 'جاري جلب اللوحة…');
    if (_error != null) return SasErrorView(message: _error!, onRetry: _load);

    final d = _data ?? const SasDashboard();
    final stats = <SasStatCard>[
      SasStatCard(
        label: 'الإجمالي',
        value: '${d.total ?? '-'}',
        color: AppTheme.primaryColor,
        icon: Icons.groups_rounded,
      ),
      SasStatCard(
        label: 'نشط',
        value: '${d.active ?? '-'}',
        color: AppTheme.successColor,
        icon: Icons.check_circle_rounded,
      ),
      SasStatCard(
        label: 'منتهٍ',
        value: '${d.expired ?? '-'}',
        color: AppTheme.warningColor,
        icon: Icons.timer_off_rounded,
      ),
      SasStatCard(
        label: 'متصل الآن',
        value: '${d.online ?? '-'}',
        color: AppTheme.infoColor,
        icon: Icons.wifi_rounded,
      ),
      SasStatCard(
        label: 'غير متصل',
        value: '${d.offline ?? '-'}',
        color: AppTheme.errorColor,
        icon: Icons.wifi_off_rounded,
      ),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(14.w),
        children: [
          _accountBanner(),
          SizedBox(height: 16.h),
          const SasSectionHeader(
            title: 'ملخّص الوكيل',
            icon: Icons.insights_rounded,
          ),
          SizedBox(height: 12.h),
          Wrap(
            spacing: 10.w,
            runSpacing: 10.h,
            children: stats,
          ),
        ],
      ),
    );
  }

  /// شريط علوي متدرّج يعرّف بالحساب النشِط.
  Widget _accountBanner() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppTheme.blueGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        boxShadow: SasUi.cardShadow(AppTheme.primaryColor),
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
            child: Icon(Icons.dashboard_rounded,
                color: Colors.white, size: 24.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.account.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'لوحة معلومات الحساب',
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
}
