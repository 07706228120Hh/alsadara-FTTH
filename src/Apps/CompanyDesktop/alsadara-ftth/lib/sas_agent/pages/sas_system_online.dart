import 'package:flutter/material.dart';

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../models/sas_account.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_format.dart';
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
      return SdEmptyState(
        title: 'لا جلسات متصلة الآن',
        icon: Icons.wifi_off_rounded,
        action: SdButton(
          label: 'تحديث',
          icon: Icons.refresh_rounded,
          kind: SdButtonKind.secondary,
          onPressed: _load,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: SasContentWrap(
        child: ListView.separated(
          padding: const EdgeInsets.all(SdSpace.sm),
          itemCount: _rows.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: SdSpace.xs),
          itemBuilder: (context, i) {
            if (i == _rows.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: SdSpace.sm),
                child: Center(
                  child: Text('الإجمالي المتصل: ${_rows.length}',
                      style: SdText.caption),
                ),
              );
            }
            return _sessionCard(_rows[i]);
          },
        ),
      ),
    );
  }

  Widget _sessionCard(Map<String, dynamic> s) {
    return SdCard(
      tone: SdGroup.field.tone,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // اسم المستخدم + الباقة
          Row(
            children: [
              const Icon(Icons.wifi_rounded, size: 18, color: SdColors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${s['username'] ?? '-'}',
                    style: SdText.label, overflow: TextOverflow.ellipsis),
              ),
              SdStatusChip(
                '${s['user_profile_name'] ?? s['profile_id'] ?? '-'}',
                status: SdStatus.success,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // عناوين الشبكة (LTR دائماً)
          Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
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
          const SizedBox(height: 6),
          // مدّة/رفع/تنزيل
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              SasInfoChip(
                  icon: Icons.timer_outlined,
                  label: 'المدّة',
                  value: sasDuration(s['acctsessiontime'])),
              SasInfoChip(
                  icon: Icons.download_rounded,
                  label: 'تنزيل',
                  value: sasBytes(s['acctoutputoctets']),
                  color: SdColors.info),
              SasInfoChip(
                  icon: Icons.upload_rounded,
                  label: 'رفع',
                  value: sasBytes(s['acctinputoctets']),
                  color: SdColors.warning),
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
            style: const TextStyle(
                fontFamily: SdText.family,
                fontSize: 11.5,
                color: SdColors.faint)),
        Text(value,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: SdColors.ink)),
      ],
    );
  }
}
