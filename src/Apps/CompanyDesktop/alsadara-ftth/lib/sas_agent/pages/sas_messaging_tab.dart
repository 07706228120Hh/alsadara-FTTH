import 'package:flutter/material.dart';

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../models/sas_account.dart';
import '../whatsapp/whatsapp.dart';
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
          final commsTone = SdGroup.comms.tone;

          final messagingTiles = <Widget>[
            _tile(
              context,
              title: 'الإشعارات والتذكير',
              subtitle:
                  'تذكير المشتركين قرب الانتهاء عبر واتساب + المجدوِل التلقائي',
              icon: Icons.notifications_active_rounded,
              tone: commsTone,
              onTap: () => _open(context, SasRemindersPage(account: account)),
            ),
            _tile(
              context,
              title: 'إرسال جماعي',
              subtitle:
                  'رسالة واتساب لمجموعة مشتركين مفلترة (الباقة/المدير/الحالة)',
              icon: Icons.send_rounded,
              tone: commsTone,
              onTap: () => _open(context, SasBulkMessagePage(account: account)),
            ),
            _tile(
              context,
              title: 'إرسال رسالة تجريبية',
              subtitle:
                  'محاكاة رسالة ما بعد التفعيل على رقم تختاره لاختبار القالب والإرسال',
              icon: Icons.bug_report_rounded,
              tone: commsTone,
              onTap: () => _open(context, const SasTestMessagePage()),
            ),
          ];

          final setupTiles = <Widget>[
            _tile(
              context,
              title: 'قوالب الرسائل',
              subtitle: 'قوالب التذكير/التجديد القابلة للتعديل بالمتغيّرات',
              icon: Icons.description_rounded,
              tone: SdStatus.warning.tone,
              onTap: () => _open(context, const WaTemplatesScreen()),
            ),
          ];

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _settingsButton(context),
              ),
              const SizedBox(height: SdSpace.xs),
              _banner(),
              const SizedBox(height: SdSpace.md),
              SdSectionHeader(title: 'الإرسال', tone: SdGroup.comms.tone),
              const SizedBox(height: SdSpace.xs),
              _grid(messagingTiles, cols),
              const SizedBox(height: SdSpace.lg),
              const SdSectionHeader(title: 'الإعداد والقوالب'),
              const SizedBox(height: SdSpace.xs),
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
            if (i > 0) const SizedBox(height: SdSpace.xs),
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
        if (j > 0) cells.add(const SizedBox(width: SdSpace.xs));
        cells.add(Expanded(
          child: idx < tiles.length ? tiles[idx] : const SizedBox.shrink(),
        ));
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: SdSpace.xs));
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
  /// (وضع الإرسال + QR + ضبط الاتصال).
  Widget _settingsButton(BuildContext context) {
    return SdRaised(
      onTap: () => _open(context, const WaSettingsScreen()),
      radius: SdRadius.md,
      depth: SdDepth.button,
      color: SdColors.primary,
      edgeColor: SdColors.primaryEdge,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      semanticLabel: 'الإعدادات',
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.settings_rounded, color: Colors.white, size: 18),
          SizedBox(width: 7),
          Text('الإعدادات',
              style: TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ],
      ),
    );
  }

  Widget _banner() {
    final tone = SdGroup.comms.tone;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tone.light, tone.base],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SdRadius.lg),
        boxShadow: [BoxShadow(color: tone.edge, offset: const Offset(0, 5))],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            ),
            child:
                const Icon(Icons.forum_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('الرسائل والواتساب',
                    style: TextStyle(
                        fontFamily: SdText.family,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text(
                  'تذكير · إرسال جماعي · إعدادات وقوالب — للحساب «${account.displayName}»',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 11.5,
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
    required SdTone tone,
    required VoidCallback onTap,
  }) {
    return SdRaised(
      onTap: onTap,
      radius: SdRadius.lg,
      padding: const EdgeInsets.all(12),
      semanticLabel: title,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tone.tint,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: tone.tintEdge, offset: const Offset(0, 3))
              ],
            ),
            child: Icon(icon, color: tone.base, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SdText.label),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SdText.caption),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_left_rounded,
              color: SdColors.faint, size: 20),
        ],
      ),
    );
  }
}
