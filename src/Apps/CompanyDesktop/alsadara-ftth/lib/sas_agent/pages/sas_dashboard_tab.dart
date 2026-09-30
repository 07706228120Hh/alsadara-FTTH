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
          Text(
            widget.account.displayName,
            style: GoogleFonts.cairo(
                fontSize: 16.sp, fontWeight: FontWeight.w800),
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
}
