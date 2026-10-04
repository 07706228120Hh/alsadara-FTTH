import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_admin_agent.dart';
import '../models/sas_report.dart' show SasVerdict, SasVerdictX;
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_state_views.dart';

/// شاشة «إدارة الوكلاء» (البلنك الموحّد) — للأدمن فقط.
///
/// تعرض وكلاء الشركة (ملّاك حسابات الساس) مع حساباتهم ومقاطعتها (المُصرَّح
/// مقابل الفعلي) وحُكم كل حساب (matched / company_suspicious /
/// agent_suspicious / no_report). البيانات من `GET /api/sas-agent/admin/agents`
/// عبر [SasAgentApiService.getAdminAgents].
///
/// الحماية النهائية في الخادم: رد `403` يُترجَم لحالة «هذه الصفحة للمشرفين
/// فقط»؛ تعذّر خدمة الساس يُترجَم لـ «تعذّر جلب المقاطعة» لكل حساب بلا انهيار.
///
/// عرض فقط — لا كتابة ولا أسرار. RTL عربي، بمقاسات ثابتة (shim `sas_metrics`).
class SasAdminAgentsPage extends StatefulWidget {
  const SasAdminAgentsPage({super.key});

  @override
  State<SasAdminAgentsPage> createState() => _SasAdminAgentsPageState();
}

class _SasAdminAgentsPageState extends State<SasAdminAgentsPage> {
  final _api = SasAgentApiService.instance;

  bool _loading = true;
  bool _forbidden = false;
  String? _error;
  List<SasAdminAgent> _agents = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _clean(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _forbidden = false;
      _error = null;
    });
    try {
      final agents = await _api.getAdminAgents();
      if (!mounted) return;
      setState(() {
        _agents = agents;
        _loading = false;
      });
    } on SasAdminForbiddenException {
      if (!mounted) return;
      setState(() {
        _forbidden = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _clean(e);
        _loading = false;
      });
    }
  }

  // ─────────────────────────── المجاميع العلوية ───────────────────────────

  int get _totalAgents => _agents.length;
  int get _totalDeclared =>
      _agents.fold(0, (s, a) => s + a.totals.declared);
  int get _totalActual => _agents.fold(0, (s, a) => s + a.totals.actual);

  /// عدد الحسابات المطابقة (حكم matched) عبر كل الوكلاء.
  int get _matchedCount => _agents
      .expand((a) => a.verdicts)
      .where((v) => v == SasVerdict.matched)
      .length;

  /// عدد الحسابات المشبوهة (شركة أو وكيل) عبر كل الوكلاء.
  int get _suspiciousCount => _agents
      .expand((a) => a.verdicts)
      .where((v) =>
          v == SasVerdict.companySuspicious || v == SasVerdict.agentSuspicious)
      .length;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          elevation: 0,
          toolbarHeight: 60,
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.blueGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.30)),
                ),
                child: const Icon(Icons.groups_2_rounded,
                    size: 19, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('إدارة الوكلاء',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w800, fontSize: 17)),
                    Text('البلنك الموحّد — المُصرَّح مقابل الفعلي',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.75))),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const SasLoadingView(message: 'جارٍ جلب الوكلاء والبلنك الموحّد…');
    }
    if (_forbidden) {
      return const SasEmptyView(
        icon: Icons.admin_panel_settings_rounded,
        message:
            'هذه الصفحة للمشرفين فقط.\nليست لديك صلاحية عرض إدارة الوكلاء (البلنك الموحّد).',
      );
    }
    if (_error != null) {
      return SasErrorView(message: _error!, onRetry: _load);
    }

    return RefreshIndicator(
      color: AppTheme.primaryColor,
      onRefresh: _load,
      child: _agents.isEmpty
          ? ListView(
              // قائمة قابلة للتمرير كي يعمل السحب-للتحديث حتى مع الفراغ.
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 80),
                SasEmptyView(
                  icon: Icons.groups_2_rounded,
                  message:
                      'لا وكلاء بعد.\nلم تُربَط أي حسابات ساس لوكلاء ضمن هذه الشركة.',
                ),
              ],
            )
          : SasContentWrap(
              maxWidth: 1180,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 24.h),
                children: [
                  _summary(),
                  SizedBox(height: 18.h),
                  SasSectionHeader(
                    title: 'الوكلاء',
                    icon: Icons.badge_rounded,
                    trailingText: '$_totalAgents',
                  ),
                  SizedBox(height: 10.h),
                  for (final a in _agents) ...[
                    _AgentCard(agent: a),
                    SizedBox(height: 10.h),
                  ],
                ],
              ),
            ),
    );
  }

  // ─────────────────────────── البطاقات المجمّعة ───────────────────────────

  Widget _summary() {
    return LayoutBuilder(
      builder: (context, c) {
        // بطاقتان في كل صف على العرض الضيّق، أربعٌ على العريض.
        final twoPerRow = c.maxWidth < 620;
        final itemWidth = twoPerRow
            ? (c.maxWidth - 12.w) / 2
            : (c.maxWidth - 3 * 12.w) / 4;
        return Wrap(
          spacing: 12.w,
          runSpacing: 12.h,
          children: [
            SizedBox(
              width: itemWidth,
              child: SasStatCard(
                label: 'إجمالي الوكلاء',
                value: '$_totalAgents',
                color: AppTheme.primaryColor,
                icon: Icons.groups_2_rounded,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: SasStatCard(
                label: 'إجمالي التصريح',
                value: '$_totalDeclared',
                color: AppTheme.infoColor,
                icon: Icons.assignment_turned_in_rounded,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: SasStatCard(
                label: 'إجمالي الفعلي',
                value: '$_totalActual',
                color: AppTheme.successColor,
                icon: Icons.fact_check_rounded,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: SasStatCard(
                label: 'مطابق / مشبوه',
                value: '$_matchedCount / $_suspiciousCount',
                color: _suspiciousCount > 0
                    ? AppTheme.warningColor
                    : AppTheme.successColor,
                icon: Icons.rule_rounded,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────── ألوان/أيقونات الأحكام ───────────────────────────

/// لون دلالي للحكم (matched=أخضر · company_suspicious=برتقالي ·
/// agent_suspicious=أحمر · no_report=رمادي).
Color _verdictColor(SasVerdict v) {
  switch (v) {
    case SasVerdict.matched:
      return AppTheme.successColor;
    case SasVerdict.companySuspicious:
      return AppTheme.warningColor;
    case SasVerdict.agentSuspicious:
      return AppTheme.errorColor;
    case SasVerdict.noReport:
      return Colors.grey;
  }
}

/// أيقونة دلالية للحكم.
IconData _verdictIcon(SasVerdict v) {
  switch (v) {
    case SasVerdict.matched:
      return Icons.check_circle_rounded;
    case SasVerdict.companySuspicious:
      return Icons.trending_up_rounded;
    case SasVerdict.agentSuspicious:
      return Icons.trending_down_rounded;
    case SasVerdict.noReport:
      return Icons.remove_circle_outline_rounded;
  }
}

String _fmtDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}/${two(l.month)}/${two(l.day)} · ${two(l.hour)}:${two(l.minute)}';
}

// ─────────────────────────── بطاقة وكيل قابلة للتوسّع ───────────────────────────

/// بطاقة وكيل واحد: رأس (الاسم + اسم المستخدم + عدد الحسابات + مجاميعه) قابل
/// للتوسّع يُظهر حساباته، ولكل حساب شارة حكم + (تصريح/فعلي/فارق) + آخر مزامنة.
class _AgentCard extends StatelessWidget {
  final SasAdminAgent agent;
  const _AgentCard({required this.agent});

  @override
  Widget build(BuildContext context) {
    final diff = agent.totals.diff;
    final diffColor = diff == 0
        ? Colors.grey.shade600
        : (diff > 0 ? AppTheme.warningColor : AppTheme.errorColor);

    return Container(
      decoration: SasUi.card(),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // إزالة الخطوط الفاصلة الافتراضية لـ ExpansionTile.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
          childrenPadding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 12.h),
          leading: Container(
            width: 42.w,
            height: 42.w,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_rounded,
                color: AppTheme.primaryColor, size: 22.sp),
          ),
          title: Text(
            agent.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
                fontSize: 14.sp,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1A1A2E)),
          ),
          subtitle: Padding(
            padding: EdgeInsets.only(top: 3.h),
            child: Text(
              '${agent.username.isNotEmpty ? '@${agent.username} · ' : ''}'
              '${agent.totals.accounts} حساب',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.cairo(
                  fontSize: 11.5.sp, color: Colors.grey[600]),
            ),
          ),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('تصريح ${agent.totals.declared} · فعلي ${agent.totals.actual}',
                  style: GoogleFonts.cairo(
                      fontSize: 10.5.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[700])),
              SizedBox(height: 2.h),
              Text(
                diff == 0 ? 'فارق 0' : 'فارق ${diff > 0 ? '+' : ''}$diff',
                style: GoogleFonts.cairo(
                    fontSize: 10.5.sp,
                    fontWeight: FontWeight.w800,
                    color: diffColor),
              ),
            ],
          ),
          children: [
            if (agent.accounts.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 10.h),
                child: Text('لا حسابات ساس لهذا الوكيل.',
                    style: GoogleFonts.cairo(
                        fontSize: 12.sp, color: Colors.grey[600])),
              )
            else
              for (final acc in agent.accounts) _AccountRow(account: acc),
          ],
        ),
      ),
    );
  }
}

/// صفّ حساب ساس واحد داخل بطاقة الوكيل: الليبل + شارة حكم ملوّنة +
/// (تصريح/فعلي/فارق) + آخر مزامنة — أو «تعذّر جلب المقاطعة» عند غيابها.
class _AccountRow extends StatelessWidget {
  final SasAdminAccount account;
  const _AccountRow({required this.account});

  @override
  Widget build(BuildContext context) {
    final recon = account.reconciliation;
    final hasRecon = recon != null;
    final verdict = recon?.verdict ?? SasVerdict.noReport;
    final color = _verdictColor(verdict);

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: SasUi.pageBg,
        borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_rounded, size: 16.sp, color: AppTheme.primaryColor),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  account.displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                      fontSize: 12.5.sp,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A2E)),
                ),
              ),
              SizedBox(width: 8.w),
              if (hasRecon)
                SasStatusBadge(
                  label: verdict.labelAr,
                  color: color,
                  icon: _verdictIcon(verdict),
                )
              else
                const SasStatusBadge(
                  label: 'تعذّر جلب المقاطعة',
                  color: Colors.grey,
                  icon: Icons.cloud_off_rounded,
                ),
            ],
          ),
          if (!account.isActive) ...[
            SizedBox(height: 6.h),
            Text('الحساب غير مفعّل',
                style: GoogleFonts.cairo(
                    fontSize: 10.5.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[600])),
          ],
          if (hasRecon) ...[
            SizedBox(height: 10.h),
            Row(
              children: [
                _mini('تصريح', '${recon.declaredTotal}', AppTheme.infoColor),
                _mini('فعلي', '${recon.actualTotal}', AppTheme.successColor),
                _mini(
                  'فارق',
                  recon.diff == 0
                      ? '0'
                      : '${recon.diff > 0 ? '+' : ''}${recon.diff}',
                  recon.diff == 0 ? Colors.grey.shade600 : color,
                ),
              ],
            ),
            if (recon.lastSync != null) ...[
              SizedBox(height: 8.h),
              Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 13.sp, color: Colors.grey[500]),
                  SizedBox(width: 4.w),
                  Text('آخر مزامنة: ${_fmtDate(recon.lastSync!)}',
                      style: GoogleFonts.cairo(
                          fontSize: 10.5.sp, color: Colors.grey[600])),
                ],
              ),
            ],
          ] else ...[
            SizedBox(height: 8.h),
            Text('خدمة الساس غير متاحة حالياً لهذا الحساب — أعد المحاولة لاحقاً.',
                style: GoogleFonts.cairo(
                    fontSize: 10.5.sp, color: Colors.grey[600], height: 1.4)),
          ],
        ],
      ),
    );
  }

  Widget _mini(String label, String value, Color color) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.cairo(
                    fontSize: 10.5.sp, color: Colors.grey[600])),
            SizedBox(height: 1.h),
            Text(value,
                style: GoogleFonts.cairo(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w900,
                    color: color)),
          ],
        ),
      );
}
