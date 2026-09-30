import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_state_views.dart';

/// تبويب «نظام الساس» — يعرض للحساب المحدد:
/// الباقات/البروفايلات · الملخّص المالي · صحّة النظام.
///
/// كل قسم يُجلب من نقطته المستقلّة (packages/finance/health)، بحالات
/// تحميل/خطأ/فراغ لكل قسم على حدة، وبتصميم بطاقات بثيم الصدارة.
class SasSystemTab extends StatefulWidget {
  final SasAccount account;
  const SasSystemTab({super.key, required this.account});

  @override
  State<SasSystemTab> createState() => _SasSystemTabState();
}

class _SasSystemTabState extends State<SasSystemTab> {
  final _api = SasAgentApiService.instance;

  // الباقات
  List<Map<String, dynamic>>? _packages;
  String? _packagesError;

  // المالية
  Map<String, dynamic>? _finance;
  String? _financeError;

  // الصحّة
  Map<String, dynamic>? _health;
  String? _healthError;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void didUpdateWidget(covariant SasSystemTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.id != widget.account.id) _loadAll();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _packages = null;
      _packagesError = null;
      _finance = null;
      _financeError = null;
      _health = null;
      _healthError = null;
    });

    final id = widget.account.id;
    // جلب الأقسام الثلاثة بالتوازي؛ كل قسم يلتقط خطأه بمعزل عن الآخرين.
    await Future.wait([
      _api.getPackages(id).then((v) => _packages = v).catchError((Object e) {
        _packagesError = _clean(e);
        return <Map<String, dynamic>>[];
      }),
      _api.getFinance(id).then((v) => _finance = v).catchError((Object e) {
        _financeError = _clean(e);
        return <String, dynamic>{};
      }),
      _api.getHealth(id).then((v) => _health = v).catchError((Object e) {
        _healthError = _clean(e);
        return <String, dynamic>{};
      }),
    ]);

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SasLoadingView(message: 'جاري جلب نظام الساس…');
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: EdgeInsets.all(14.w),
        children: [
          const SasSectionHeader(
            title: 'صحّة النظام',
            icon: Icons.health_and_safety_rounded,
            gradient: AppTheme.greenGradient,
          ),
          SizedBox(height: 10.h),
          _healthSection(),
          SizedBox(height: 20.h),
          const SasSectionHeader(
            title: 'الملخّص المالي',
            icon: Icons.account_balance_wallet_rounded,
            gradient: AppTheme.orangeGradient,
          ),
          SizedBox(height: 10.h),
          _financeSection(),
          SizedBox(height: 20.h),
          const SasSectionHeader(
            title: 'الباقات',
            icon: Icons.inventory_2_rounded,
          ),
          SizedBox(height: 10.h),
          _packagesSection(),
        ],
      ),
    );
  }

  // ─── الصحّة ───
  Widget _healthSection() {
    if (_healthError != null) {
      return _inlineError(_healthError!);
    }
    final h = _health ?? const {};
    if (h.isEmpty) {
      return _inlineEmpty('لا تتوفّر بيانات صحّة للنظام');
    }
    return _kvCard(h);
  }

  // ─── المالية ───
  Widget _financeSection() {
    if (_financeError != null) {
      return _inlineError(_financeError!);
    }
    final f = _finance ?? const {};
    if (f.isEmpty) {
      return _inlineEmpty('لا يتوفّر ملخّص مالي');
    }
    return _kvCard(f);
  }

  // ─── الباقات ───
  Widget _packagesSection() {
    if (_packagesError != null) {
      return _inlineError(_packagesError!);
    }
    final list = _packages ?? const [];
    if (list.isEmpty) {
      return _inlineEmpty('لا توجد باقات لعرضها');
    }
    return Column(
      children: [
        for (final p in list) ...[
          _packageCard(p),
          SizedBox(height: 8.h),
        ],
      ],
    );
  }

  Widget _packageCard(Map<String, dynamic> p) {
    final name = (p['name'] ??
            p['Name'] ??
            p['title'] ??
            p['profile'] ??
            p['label'] ??
            '')
        .toString();
    final price = (p['price'] ?? p['Price'] ?? p['cost'] ?? p['amount'])
        ?.toString();
    final speed = (p['speed'] ?? p['Speed'] ?? p['bandwidth'])?.toString();
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: SasUi.card(),
      child: Row(
        children: [
          SasUi.gradientBadge(
            icon: Icons.wifi_tethering_rounded,
            colors: const [AppTheme.infoColor, AppTheme.secondaryColor],
            size: 40,
            iconSize: 20,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? '-' : name,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A2E)),
                ),
                if (speed != null || price != null) ...[
                  SizedBox(height: 2.h),
                  Text(
                    [
                      if (speed != null) 'السرعة: $speed',
                      if (price != null) 'السعر: $price',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                        fontSize: 11.5.sp, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// بطاقة «مفتاح: قيمة» لعرض خرائط خام (المالية/الصحّة) بشكل مقروء.
  Widget _kvCard(Map<String, dynamic> map) {
    final entries = map.entries
        .where((e) => e.value is! Map && e.value is! List)
        .toList();
    if (entries.isEmpty) {
      return _inlineEmpty('لا توجد تفاصيل قابلة للعرض');
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
      decoration: SasUi.card(),
      child: Column(
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.grey.withValues(alpha: 0.10)),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      _labelFor(entries[i].key),
                      style: GoogleFonts.cairo(
                        fontSize: 12.5.sp,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '${entries[i].value}',
                      textAlign: TextAlign.end,
                      style: GoogleFonts.cairo(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// تسمية عربية مبسّطة للمفاتيح الشائعة، وإلا نعرض المفتاح كما هو.
  String _labelFor(String key) {
    switch (key.toLowerCase()) {
      case 'balance':
        return 'الرصيد';
      case 'credit':
        return 'الائتمان';
      case 'debt':
      case 'debit':
        return 'المديونية';
      case 'currency':
        return 'العملة';
      case 'status':
        return 'الحالة';
      case 'online':
        return 'متصل الآن';
      case 'total':
        return 'الإجمالي';
      case 'active':
        return 'نشط';
      case 'expired':
        return 'منتهٍ';
      case 'uptime':
        return 'مدة التشغيل';
      case 'version':
        return 'الإصدار';
      default:
        return key;
    }
  }

  Widget _inlineError(String msg) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppTheme.errorColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              color: AppTheme.errorColor, size: 20.sp),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              msg,
              style: GoogleFonts.cairo(
                  fontSize: 12.5.sp, color: Colors.grey[800]),
            ),
          ),
          TextButton(
            onPressed: _loadAll,
            child: Text('إعادة', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Widget _inlineEmpty(String msg) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(Icons.inbox_rounded, color: Colors.grey[400], size: 20.sp),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              msg,
              style: GoogleFonts.cairo(
                  fontSize: 12.5.sp, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }
}
