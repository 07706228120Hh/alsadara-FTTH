import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/sadara_api_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../premises/ui/premises_list_screen.dart';
import '../whatsapp/whatsapp.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_state_views.dart';
import 'sas_explorer_page.dart';

/// تبويب «الإعدادات» — مركز إعداد وحدة «وكيل الساس» بثيم منصّة الصدارة.
///
/// منقول ومكيّف من `settings_screen.dart` في تطبيق الوكلاء المرجعي؛ يشمل:
///  • الحساب: هوية المستخدم/الوكيل ودوره ونطاقه.
///  • الخادم: العنوان الحالي وفحص الاتصال الحيّ.
///  • حسابات الساس: تلخيص الحساب المحدّد + مدخل سريع لتبويب «الحسابات».
///  • الواتساب: إعدادات المُرسِل + القوالب (شاشات wa بثيم الصدارة).
///  • مستكشف الساس: متصفّح مدمج يلتقط طلبات الـ API لتحليلها.
///  • العقارات: العنوان الوطني (مدخل سريع).
///  • متقدّم — ميزات محفوظة: قدرات المنصّة (OLT/المراقبة…) كمداخل مؤجّلة.
///
/// لا يخزّن أي أسرار ولا يعرض كلمات مرور؛ يعتمد الجلسة الحيّة عبر
/// [VpsAuthService] وبوّابة الصدارة فقط.
class SasSettingsTab extends StatefulWidget {
  /// الحساب المحدّد حالياً (قد يكون null إن لم يُحدَّد بعد).
  final SasAccount? selected;

  /// ينتقل لتبويب «الحسابات» لإدارة/تحديد حساب ساس.
  final VoidCallback? onGoToAccounts;

  const SasSettingsTab({
    super.key,
    this.selected,
    this.onGoToAccounts,
  });

  @override
  State<SasSettingsTab> createState() => _SasSettingsTabState();
}

class _SasSettingsTabState extends State<SasSettingsTab> {
  final _api = SadaraApiService.instance;

  bool? _healthOk;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  Future<void> _checkHealth() async {
    setState(() => _checking = true);
    bool ok;
    try {
      await _api.get('/server/health');
      ok = true;
    } catch (_) {
      ok = false;
    }
    if (mounted) {
      setState(() {
        _healthOk = ok;
        _checking = false;
      });
    }
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _checkHealth,
      child: ListView(
        padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 28.h),
        children: [
          _banner(),
          SizedBox(height: 16.h),

          // ── الحساب ──
          const SasSectionHeader(title: 'الحساب', icon: Icons.badge_rounded),
          SizedBox(height: 10.h),
          _accountCard(),

          SizedBox(height: 20.h),

          // ── الخادم ──
          const SasSectionHeader(
            title: 'الخادم',
            icon: Icons.dns_rounded,
            gradient: AppTheme.greenGradient,
          ),
          SizedBox(height: 10.h),
          _serverCard(),

          SizedBox(height: 20.h),

          // ── حسابات الساس ──
          const SasSectionHeader(
            title: 'حسابات الساس',
            icon: Icons.hub_rounded,
          ),
          SizedBox(height: 10.h),
          _sasAccountsCard(),

          SizedBox(height: 20.h),

          // ── الواتساب ──
          const SasSectionHeader(
            title: 'الواتساب',
            icon: Icons.chat_rounded,
            gradient: AppTheme.greenGradient,
          ),
          SizedBox(height: 10.h),
          _whatsappCard(),

          SizedBox(height: 20.h),

          // ── أدوات ──
          const SasSectionHeader(
            title: 'أدوات',
            icon: Icons.build_rounded,
            gradient: AppTheme.orangeGradient,
          ),
          SizedBox(height: 10.h),
          _toolsCard(),

          SizedBox(height: 20.h),

          // ── متقدّم — ميزات محفوظة ──
          const SasSectionHeader(
            title: 'متقدّم — ميزات محفوظة',
            icon: Icons.inventory_2_rounded,
          ),
          SizedBox(height: 6.h),
          Padding(
            padding: EdgeInsets.fromLTRB(4.w, 0, 4.w, 8.h),
            child: Text(
              'هذه القدرات محفوظة في الخادم للاستفادة منها لاحقاً — غير مفعّلة '
              'في واجهة الوكيل حالياً.',
              style: GoogleFonts.cairo(
                fontSize: 12.sp,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
          ),
          _preservedCard(),

          SizedBox(height: 20.h),

          // ── حول ──
          const SasSectionHeader(
            title: 'حول الوحدة',
            icon: Icons.info_outline_rounded,
          ),
          SizedBox(height: 10.h),
          _aboutCard(),
        ],
      ),
    );
  }

  // ─────────────────────────── الرأس ───────────────────────────

  Widget _banner() {
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
            child: Icon(Icons.settings_rounded, color: Colors.white, size: 24.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إعدادات وكيل الساس',
                  style: GoogleFonts.cairo(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'الحساب · الخادم · الواتساب · أدوات · ميزات محفوظة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

  // ─────────────────────────── بطاقة الحساب ───────────────────────────

  Widget _accountCard() {
    final u = VpsAuthService.instance.currentUser;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
      decoration: SasUi.card(),
      child: Column(
        children: [
          _kvRow('المستخدم', u?.username ?? '—'),
          _divider(),
          _kvRow('الاسم', (u?.fullName.trim().isNotEmpty ?? false) ? u!.fullName : '—'),
          _divider(),
          _kvRow('الدور', _roleAr(u?.role ?? '')),
          if ((u?.phone ?? '').isNotEmpty) ...[
            _divider(),
            _kvRow('الهاتف', u!.phone!),
          ],
          if ((u?.department ?? '').isNotEmpty) ...[
            _divider(),
            _kvRow('القسم', u!.department!),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────── بطاقة الخادم ───────────────────────────

  Widget _serverCard() {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kvRow('العنوان', SadaraApiService.baseUrl),
          _divider(),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 10.h),
            child: Row(
              children: [
                _healthChip(),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _checking ? null : _checkHealth,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: BorderSide(
                        color: AppTheme.primaryColor.withValues(alpha: 0.40)),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(SasUi.radiusSm.r)),
                  ),
                  icon: _checking
                      ? SizedBox(
                          width: 16.w,
                          height: 16.w,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.wifi_tethering_rounded, size: 18.sp),
                  label: Text('فحص الاتصال',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _healthChip() {
    final ok = _healthOk;
    if (ok == null) {
      return const SasStatusBadge(
        label: 'جارٍ الفحص…',
        color: Colors.grey,
        icon: Icons.hourglass_empty_rounded,
      );
    }
    return ok
        ? const SasStatusBadge(
            label: 'الخادم متصل',
            color: AppTheme.successColor,
            icon: Icons.check_circle_rounded,
          )
        : const SasStatusBadge(
            label: 'لا اتصال بالخادم',
            color: AppTheme.errorColor,
            icon: Icons.error_outline_rounded,
          );
  }

  // ─────────────────────────── حسابات الساس ───────────────────────────

  Widget _sasAccountsCard() {
    final acc = widget.selected;
    return Container(
      decoration: SasUi.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (acc != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
              child: Column(
                children: [
                  _kvRow('الحساب الفعّال', acc.displayName),
                  _divider(),
                  _kvRow('النوع', acc.accountType.labelAr),
                  _divider(),
                  _kvRow('الخادم', acc.serverUrl),
                  _divider(),
                  _kvRow('الحالة', acc.isActive ? 'مفعّل' : 'غير مفعّل',
                      valueColor: acc.isActive
                          ? AppTheme.successColor
                          : Colors.grey.shade600),
                ],
              ),
            )
          else
            Padding(
              padding: EdgeInsets.all(14.w),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colors.grey[500], size: 20.sp),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(
                      'لم يُحدَّد حساب ساس بعد — اذهب لتبويب «الحسابات» لربط/تحديد حساب.',
                      style: GoogleFonts.cairo(
                          fontSize: 12.5.sp,
                          color: Colors.grey[700],
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          _tile(
            icon: Icons.manage_accounts_rounded,
            iconColor: AppTheme.primaryColor,
            title: 'إدارة حسابات الساس',
            subtitle: 'ربط · تعديل · حذف · اختبار · مزامنة · تحديد الحساب الفعّال',
            onTap: widget.onGoToAccounts,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── الواتساب ───────────────────────────

  Widget _whatsappCard() {
    return Container(
      decoration: SasUi.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _tile(
            icon: Icons.settings_suggest_rounded,
            iconColor: AppTheme.successColor,
            title: 'إعدادات الواتساب',
            subtitle: 'وضع الإرسال (تطبيق/خادم محلي/Meta) وضبط الاتصال',
            onTap: () => _open(const WaSettingsScreen()),
          ),
          const Divider(height: 1),
          _tile(
            icon: Icons.description_rounded,
            iconColor: AppTheme.infoColor,
            title: 'قوالب الرسائل',
            subtitle: 'قوالب التذكير/التجديد القابلة للتعديل بالمتغيّرات',
            onTap: () => _open(const WaTemplatesScreen()),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── أدوات ───────────────────────────

  Widget _toolsCard() {
    final acc = widget.selected;
    return Container(
      decoration: SasUi.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _tile(
            icon: Icons.travel_explore_rounded,
            iconColor: AppTheme.infoColor,
            title: 'مستكشف الساس — التقاط الطلبات',
            subtitle: acc == null
                ? 'حدّد حساباً أولاً لفتح المستكشف'
                : 'متصفّح مدمج يفتح لوحة الساس ويلتقط طلبات الـ API لتحليلها',
            onTap: acc == null
                ? null
                : () => _open(SasExplorerPage(account: acc)),
          ),
          const Divider(height: 1),
          _tile(
            icon: Icons.maps_home_work_rounded,
            iconColor: AppTheme.warningColor,
            title: 'العقارات (العنوان الوطني)',
            subtitle: 'إدارة العقارات وربط الاشتراكات بالعنوان الوطني NPN',
            onTap: () => _open(const PremisesListScreen()),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── متقدّم — ميزات محفوظة ───────────────────────────

  Widget _preservedCard() {
    return Container(
      decoration: SasUi.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < _preserved.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _preservedTile(_preserved[i]),
          ],
        ],
      ),
    );
  }

  Widget _preservedTile(_Feature f) {
    return ListTile(
      leading: Container(
        width: 40.w,
        height: 40.w,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(11.r),
        ),
        child: Icon(f.icon, color: Colors.grey[500], size: 20.sp),
      ),
      title: Text(f.title,
          style: GoogleFonts.cairo(
              fontSize: 13.5.sp, fontWeight: FontWeight.w800)),
      subtitle: Text(f.desc,
          style: GoogleFonts.cairo(fontSize: 11.5.sp, color: Colors.grey[600])),
      trailing: const SasStatusBadge(
        label: 'محفوظ',
        color: Colors.grey,
        icon: Icons.inventory_2_rounded,
      ),
      onTap: () => _showPreservedInfo(f),
    );
  }

  void _showPreservedInfo(_Feature f) {
    showDialog<void>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(children: [
            Icon(f.icon, color: AppTheme.primaryColor),
            SizedBox(width: 8.w),
            Expanded(
                child: Text(f.title,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w800))),
          ]),
          content: Text(
            '${f.desc}\n\nهذه الميزة محفوظة في الخادم (لم تُحذف) وستُفعَّل في '
            'واجهة الوكيل عند الحاجة لاحقاً.',
            style: GoogleFonts.cairo(height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text('حسناً', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── حول ───────────────────────────

  Widget _aboutCard() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('وحدة وكيل الساس — منصّة الصدارة',
              style: GoogleFonts.cairo(
                  fontSize: 14.sp, fontWeight: FontWeight.w800)),
          SizedBox(height: 6.h),
          Text(
            'إدارة عمل الوكيل عبر نظام الساس الخاص بمزوّده — مشتركون · نظام · '
            'تجديد · تقارير · تصريح (بلنك) · تذاكر · عقارات — عبر بوّابة الصدارة '
            'الآمنة (عزل ثلاثي: شركة + مالك + صلاحية).',
            style: GoogleFonts.cairo(
                fontSize: 12.sp, color: Colors.grey[600], height: 1.6),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── مساعدات عرض ───────────────────────────

  Widget _tile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return ListTile(
      enabled: enabled,
      leading: Container(
        width: 40.w,
        height: 40.w,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(11.r),
        ),
        child: Icon(icon, color: iconColor, size: 20.sp),
      ),
      title: Text(title,
          style: GoogleFonts.cairo(
              fontSize: 13.5.sp, fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle,
          style: GoogleFonts.cairo(fontSize: 11.5.sp, color: Colors.grey[600])),
      trailing: Icon(Icons.chevron_left_rounded,
          size: 20.sp, color: enabled ? Colors.grey[500] : Colors.grey[300]),
      onTap: onTap,
    );
  }

  Widget _kvRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: GoogleFonts.cairo(
                    fontSize: 12.5.sp,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600)),
          ),
          SizedBox(width: 10.w),
          Expanded(
            flex: 3,
            child: Text(value,
                textAlign: TextAlign.end,
                style: GoogleFonts.cairo(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? AppTheme.primaryColor)),
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      Divider(height: 1, color: Colors.grey.withValues(alpha: 0.10));

  static String _roleAr(String r) {
    switch (r.toLowerCase()) {
      case 'admin':
        return 'مدير';
      case 'operator':
        return 'مشغّل';
      case 'agent':
        return 'وكيل';
      default:
        return r.isEmpty ? '—' : r;
    }
  }
}

/// وصف ميزة محفوظة (مؤجّلة) تُعرَض كمدخل غير مفعّل.
class _Feature {
  final String title;
  final String desc;
  final IconData icon;
  const _Feature(this.title, this.desc, this.icon);
}

/// قدرات المنصّة المحفوظة في الخادم (تُعرَض كمداخل مؤجّلة — لا تُحذف).
const List<_Feature> _preserved = [
  _Feature('إدارة أجهزة OLT', 'الاتصال بأجهزة Huawei OLT عبر SSH/Telnet وإدارتها.',
      Icons.dns_rounded),
  _Feature('المراقبة اللحظية',
      'مراقبة دورية للقياسات والقدرة الضوئية مع تنبيهات.', Icons.monitor_heart_rounded),
  _Feature('التزويد التلقائي (FTTH)',
      'تدفّقات تزويد المشتركين وتسلسل الأوامر الآمن.', Icons.electrical_services_rounded),
  _Feature('SNMP والإنذارات',
      'استقبال Traps والاستعلام عبر OID وربطها بالتنبيهات.', Icons.notifications_active_rounded),
  _Feature('التشخيص الذكي',
      'محرك تشخيص بالقواعد الخبيرة من أدلة HCIA/HCIP.', Icons.medical_services_rounded),
  _Feature('اللوحة الوطنية والحوكمة',
      'صور اللوحة الوطنية وطبقات GIS والحوكمة.', Icons.map_rounded),
  _Feature('العبور و DFOS',
      'شبكات العبور ومراقبة الألياف DFOS.', Icons.account_tree_rounded),
  _Feature('المساعد الذكي (AI)',
      'مساعد ذكاء اصطناعي هجين للدعم الفني.', Icons.smart_toy_rounded),
];
