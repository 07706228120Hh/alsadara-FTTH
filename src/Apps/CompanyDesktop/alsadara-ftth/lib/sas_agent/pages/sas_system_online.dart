import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_format.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_state_views.dart';

/// قسم «المتصلون الآن» ضمن نظام الساس — جدول جلسات نشطة عبر [getOnline]:
/// المستخدم/الباقة · IP المشترك/NAS/MAC/بروتوكول · مدّة الجلسة · تنزيل/رفع.
class SasSystemOnline extends StatefulWidget {
  final SasAccount account;
  const SasSystemOnline({super.key, required this.account});

  @override
  State<SasSystemOnline> createState() => _SasSystemOnlineState();
}

class _SasSystemOnlineState extends State<SasSystemOnline> {
  final _api = SasAgentApiService.instance;
  List<Map<String, dynamic>> _rows = const [];
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
      final rows = await _api.getOnline(widget.account.id);
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _clean(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SasLoadingView(message: 'جاري جلب المتصلين…');
    }
    if (_error != null) return SasErrorView(message: _error!, onRetry: _load);
    if (_rows.isEmpty) {
      return SasEmptyView(
        message: 'لا جلسات متصلة الآن',
        icon: Icons.wifi_off_rounded,
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
                child: Text('الإجمالي المتصل: ${_rows.length}',
                    style: GoogleFonts.cairo(
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[700])),
              ),
            );
          }
          return _sessionCard(_rows[i]);
        },
      ),
    );
  }

  Widget _sessionCard(Map<String, dynamic> s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 11.h),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // اسم المستخدم + الباقة
          Row(
            children: [
              Icon(Icons.wifi_rounded,
                  size: 18.sp, color: AppTheme.successColor),
              SizedBox(width: 8.w),
              Expanded(
                child: Text('${s['username'] ?? '-'}',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w800, fontSize: 14.sp),
                    overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  '${s['user_profile_name'] ?? s['profile_id'] ?? '-'}',
                  style: GoogleFonts.cairo(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2E7D32)),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          // عناوين الشبكة (LTR دائماً)
          Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(
              spacing: 16.w,
              runSpacing: 4.h,
              children: [
                _mono('IP', '${s['framedipaddress'] ?? '-'}'),
                _mono('NAS', '${s['nasipaddress'] ?? '-'}'),
                if (s['callingstationid'] != null)
                  _mono('MAC', '${s['callingstationid']}'),
                if (s['framedprotocol'] != null)
                  _mono('بروتوكول', '${s['framedprotocol']}'),
              ],
            ),
          ),
          SizedBox(height: 6.h),
          // مدّة/رفع/تنزيل
          Wrap(
            spacing: 16.w,
            runSpacing: 4.h,
            children: [
              SasInfoChip(
                  icon: Icons.timer_outlined,
                  label: 'المدّة',
                  value: sasDuration(s['acctsessiontime'])),
              SasInfoChip(
                  icon: Icons.download_rounded,
                  label: 'تنزيل',
                  value: sasBytes(s['acctoutputoctets']),
                  color: AppTheme.infoColor),
              SasInfoChip(
                  icon: Icons.upload_rounded,
                  label: 'رفع',
                  value: sasBytes(s['acctinputoctets']),
                  color: AppTheme.warningColor),
              if (s['fup'] != null)
                SasInfoChip(
                    icon: Icons.data_usage_rounded,
                    label: 'FUP',
                    value: '${s['fup']}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mono(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.cairo(fontSize: 9.5.sp, color: Colors.grey[500])),
        Text(value,
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5.sp,
                color: Colors.grey[800])),
      ],
    );
  }
}
