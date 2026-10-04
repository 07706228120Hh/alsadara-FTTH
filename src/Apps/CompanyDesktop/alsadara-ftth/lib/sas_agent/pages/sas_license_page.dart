import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../../utils/responsive_helper.dart';
import '../models/sas_account.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_state_views.dart';

/// شاشة «الترخيص والصلاحيات» — تعرض استجابة `sasGet(id,'auth')`:
/// حالة الترخيص · تاريخ الانتهاء · الإصدار · الميزات المفعّلة · الصلاحيات.
class SasLicensePage extends StatefulWidget {
  final SasAccount account;
  const SasLicensePage({super.key, required this.account});

  @override
  State<SasLicensePage> createState() => _SasLicensePageState();
}

class _SasLicensePageState extends State<SasLicensePage> {
  final _api = SasAgentApiService.instance;

  Map<String, dynamic>? _info;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.sasGet(widget.account.id, 'auth');
      final data = (r is Map)
          ? (r['data'] is Map
              ? (r['data'] as Map).cast<String, dynamic>()
              : r.cast<String, dynamic>())
          : <String, dynamic>{};
      if (mounted) setState(() => _info = data);
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.blueGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Text('الترخيص والصلاحيات',
              style:
                  GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 17)),
          actions: [
            IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded)),
          ],
        ),
        body: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const SasLoadingView(message: 'جاري جلب الترخيص…');
    if (_error != null) return SasErrorView(message: _error!, onRetry: _load);
    final info = _info ?? const {};
    if (info.isEmpty) {
      return SasEmptyView(
        message: 'لا تتوفّر بيانات ترخيص لهذا الحساب',
        icon: Icons.verified_user_outlined,
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('تحديث', style: GoogleFonts.cairo()),
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: context.responsive.maxContentWidth),
        child: ListView(
          padding: EdgeInsets.all(14.w),
          children: [
            _kvCard('الترخيص', Icons.workspace_premium_rounded,
                AppTheme.blueGradient, {
              'الحالة': info['license_status'] ?? info['status'],
              'تاريخ الانتهاء':
                  info['license_expiration'] ?? info['expiration'],
              'الإصدار': info['version'],
            }),
            SizedBox(height: 14.h),
            _listCard('الميزات المفعّلة', Icons.auto_awesome_rounded,
                AppTheme.greenGradient, info['features']),
            SizedBox(height: 14.h),
            _listCard('الصلاحيات', Icons.shield_rounded,
                AppTheme.orangeGradient, info['permissions']),
          ],
        ),
      ),
    );
  }

  Widget _kvCard(String title, IconData icon, List<Color> gradient,
      Map<String, dynamic> kv) {
    final entries = kv.entries
        .where((e) => e.value != null && '${e.value}'.trim().isNotEmpty)
        .toList();
    return _card(title, icon, gradient, [
      if (entries.isEmpty)
        Text('لا بيانات',
            style: GoogleFonts.cairo(fontSize: 12.sp, color: Colors.grey[500]))
      else
        for (final e in entries)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 6.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 140.w,
                  child: Text(e.key,
                      style: GoogleFonts.cairo(
                          fontSize: 12.5.sp, color: Colors.grey[700])),
                ),
                Expanded(
                  child: Text('${e.value}',
                      style: GoogleFonts.cairo(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryColor)),
                ),
              ],
            ),
          ),
    ]);
  }

  Widget _listCard(
      String title, IconData icon, List<Color> gradient, dynamic value) {
    final items = <String>[];
    if (value is List) {
      items.addAll(value.map((e) => '$e'));
    } else if (value is Map) {
      value.forEach((k, v) {
        if (v == true || v == 1) items.add('$k');
      });
    }
    return _card(title, icon, gradient, [
      if (items.isEmpty)
        Text('لا بيانات',
            style: GoogleFonts.cairo(fontSize: 12.sp, color: Colors.grey[500]))
      else
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            for (final it in items)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                decoration: BoxDecoration(
                  color: gradient.first.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20.r),
                  border:
                      Border.all(color: gradient.first.withValues(alpha: 0.28)),
                ),
                child: Text(it,
                    style: GoogleFonts.cairo(
                        fontSize: 11.5.sp,
                        fontWeight: FontWeight.w700,
                        color: gradient.first)),
              ),
          ],
        ),
    ]);
  }

  Widget _card(String title, IconData icon, List<Color> gradient,
      List<Widget> children) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SasUi.gradientBadge(
                  icon: icon, colors: gradient, size: 34, iconSize: 17),
              SizedBox(width: 10.w),
              Text(title,
                  style: GoogleFonts.cairo(
                      fontSize: 14.5.sp,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A2E))),
            ],
          ),
          SizedBox(height: 10.h),
          ...children,
        ],
      ),
    );
  }
}
