import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../whatsapp/whatsapp.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_state_views.dart';
import 'sas_bulk_message_page.dart';
import 'sas_reminders_page.dart';
import 'sas_test_message_page.dart';

/// تبويب «الرسائل والواتساب» — مركز موحّد (hub) يجمع كل ما يخصّ الرسائل
/// والواتساب في مكان واحد بثيم منصّة الصدارة؛ يستبدل تشتّت المداخل التي كانت
/// موزّعة بين تبويبَي «تقارير» و«إعدادات».
///
/// يفتح (بنمط بطاقات `_tile` كتبويب «التقارير»):
///  • الإشعارات والتذكير → [SasRemindersPage] (فيها المجدوِل التلقائي أصلاً).
///  • إرسال جماعي → [SasBulkMessagePage].
///  • إعدادات الواتساب (النمط + QR) → [WaSettingsScreen].
///  • قوالب الرسائل → [WaTemplatesScreen].
///
/// يعمل على الحساب المحدّد فقط (العزل) في مداخل التذكير/الإرسال الجماعي؛ إعدادات
/// الواتساب وقوالبه عامّة للمستخدم (لا تعتمد حساباً بعينه).
class SasMessagingTab extends StatelessWidget {
  final SasAccount account;
  const SasMessagingTab({super.key, required this.account});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return SasContentWrap(
      maxWidth: 1180,
      child: LayoutBuilder(
        builder: (context, c) {
          // شبكة بطاقات تكيّفية: عمود واحد على الضيّق وعمودان على العريض.
          final cols = c.maxWidth >= 720 ? 2 : 1;
          const waGradient = [Color(0xFF25D366), Color(0xFF128C7E)];

          final messagingTiles = <Widget>[
            _tile(
              context,
              title: 'الإشعارات والتذكير',
              subtitle:
                  'تذكير المشتركين قرب الانتهاء عبر واتساب + المجدوِل التلقائي',
              icon: Icons.notifications_active_rounded,
              gradient: waGradient,
              onTap: () => _open(context, SasRemindersPage(account: account)),
            ),
            _tile(
              context,
              title: 'إرسال جماعي',
              subtitle:
                  'رسالة واتساب لمجموعة مشتركين مفلترة (الباقة/المدير/الحالة)',
              icon: Icons.send_rounded,
              gradient: waGradient,
              onTap: () => _open(context, SasBulkMessagePage(account: account)),
            ),
            _tile(
              context,
              title: 'إرسال رسالة تجريبية',
              subtitle:
                  'محاكاة رسالة ما بعد التفعيل على رقم تختاره لاختبار القالب والإرسال',
              icon: Icons.bug_report_rounded,
              gradient: waGradient,
              onTap: () => _open(context, const SasTestMessagePage()),
            ),
          ];

          final setupTiles = <Widget>[
            _tile(
              context,
              title: 'قوالب الرسائل',
              subtitle: 'قوالب التذكير/التجديد القابلة للتعديل بالمتغيّرات',
              icon: Icons.description_rounded,
              gradient: AppTheme.orangeGradient,
              onTap: () => _open(context, const WaTemplatesScreen()),
            ),
          ];

          return ListView(
            padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 24.h),
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _settingsButton(context),
              ),
              SizedBox(height: 10.h),
              _banner(),
              SizedBox(height: 16.h),
              const SasSectionHeader(
                title: 'الإرسال',
                icon: Icons.outgoing_mail,
                gradient: [Color(0xFF25D366), Color(0xFF128C7E)],
              ),
              SizedBox(height: 10.h),
              _grid(messagingTiles, cols),
              SizedBox(height: 20.h),
              const SasSectionHeader(
                title: 'الإعداد والقوالب',
                icon: Icons.tune_rounded,
              ),
              SizedBox(height: 10.h),
              _grid(setupTiles, cols),
            ],
          );
        },
      ),
    );
  }

  /// يرتّب البطاقات في شبكة بعدد أعمدة [cols] بفراغات متساوية.
  Widget _grid(List<Widget> tiles, int cols) {
    if (cols == 1) {
      return Column(
        children: [
          for (int i = 0; i < tiles.length; i++) ...[
            if (i > 0) SizedBox(height: 8.h),
            tiles[i],
          ],
        ],
      );
    }
    final rows = <Widget>[];
    for (int i = 0; i < tiles.length; i += cols) {
      final cells = <Widget>[];
      for (int j = 0; j < cols; j++) {
        final idx = i + j;
        if (j > 0) cells.add(SizedBox(width: 10.w));
        cells.add(Expanded(
          child: idx < tiles.length ? tiles[idx] : const SizedBox.shrink(),
        ));
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: 10.h));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cells,
        ),
      ));
    }
    return Column(children: rows);
  }

  /// زر «الإعدادات» العلوي البارز — يفتح شاشة إعدادات الواتساب
  /// (وضع الإرسال + QR + ضبط الاتصال). نُقل من بطاقة ضمن القائمة إلى
  /// زرّ علوي بمحاذاة اليمين (RTL) بنمط منصّة الصدارة.
  Widget _settingsButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(SasUi.radius.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        onTap: () => _open(context, const WaSettingsScreen()),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: AppTheme.greenGradient),
            borderRadius: BorderRadius.circular(SasUi.radius.r),
            boxShadow: SasUi.cardShadow(AppTheme.greenGradient.first),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.settings_rounded, color: Colors.white, size: 18.sp),
              SizedBox(width: 7.w),
              Text(
                'الإعدادات',
                style: GoogleFonts.cairo(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF25D366), Color(0xFF128C7E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        boxShadow: SasUi.cardShadow(const Color(0xFF25D366)),
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
            child: Icon(Icons.forum_rounded, color: Colors.white, size: 24.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الرسائل والواتساب',
                  style: GoogleFonts.cairo(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'تذكير · إرسال جماعي · إعدادات وقوالب — للحساب «${account.displayName}»',
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

  Widget _tile(
    BuildContext context, {
    required String title,
    String? subtitle,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(SasUi.radius.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(12.w),
          decoration: SasUi.card(),
          child: Row(
            children: [
              SasUi.gradientBadge(
                  icon: icon, colors: gradient, size: 42, iconSize: 21),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.cairo(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1A1A2E))),
                    if (subtitle != null) ...[
                      SizedBox(height: 2.h),
                      Text(subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                              fontSize: 11.sp, color: Colors.grey[600])),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_left_rounded,
                  color: Colors.grey[400], size: 20.sp),
            ],
          ),
        ),
      ),
    );
  }
}
