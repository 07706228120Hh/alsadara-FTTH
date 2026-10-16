/// معرض مكوّنات نظام التصميم — للمراجعة فقط، غير مربوط بأي مسار في التطبيق.
///
/// لفتحه مؤقتاً من أي مكان أثناء التطوير:
/// `Navigator.push(context, MaterialPageRoute(builder: (_) => const SdGalleryPage()));`
library;

import 'package:flutter/material.dart';

import '../frontend.dart';

class SdGalleryPage extends StatefulWidget {
  const SdGalleryPage({super.key});

  @override
  State<SdGalleryPage> createState() => _SdGalleryPageState();
}

class _SdGalleryPageState extends State<SdGalleryPage> {
  SdGroup? _filter;
  bool _toggle = true;

  bool _show(SdGroup g) => _filter == null || _filter == g;

  @override
  Widget build(BuildContext context) {
    return SdPage(
      appBar: SdAppBar(
        title: 'معرض نظام التصميم',
        subtitle: 'FTTH متصل',
        subtitleOk: true,
        actions: [
          SdAppBarAction(icon: Icons.my_location_rounded, label: 'تتبّع الكادر', onPressed: () {}),
          SdAppBarAction(icon: Icons.notifications_rounded, label: 'الإشعارات', badge: 3, onPressed: () {}),
          SdAppBarAction(icon: Icons.location_off_rounded, label: 'الموقع متوقف', danger: true, onPressed: () {}),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // المؤشرات
          LayoutBuilder(builder: (ctx, c) {
            final stats = [
              const SdStatPedestal(value: 80, max: 208, label: 'طلبات الوكلاء', group: SdGroup.field),
              const SdStatPedestal(value: 208, max: 208, label: 'المهام المفتوحة', group: SdGroup.admin),
              const SdStatPedestal(value: 0, max: 208, label: 'طلبات الموظفين', group: SdGroup.platform),
            ];
            return SdTileGrid(minTileWidth: 260, phoneColumns: 1, children: stats);
          }),
          const SizedBox(height: SdSpace.xl),

          SdFilterChips<SdGroup?>(
            selected: _filter,
            onSelected: (g) => setState(() => _filter = g),
            options: const [
              SdFilterOption(null, 'الكل'),
              SdFilterOption(SdGroup.field, 'العمليات الميدانية'),
              SdFilterOption(SdGroup.admin, 'الإدارة والموارد'),
              SdFilterOption(SdGroup.comms, 'التواصل'),
              SdFilterOption(SdGroup.platform, 'المنصّات والبيانات'),
            ],
          ),
          const SizedBox(height: SdSpace.xl),

          if (_show(SdGroup.field)) ...[
            SdSectionHeader(title: SdGroup.field.arabicLabel, tone: SdGroup.field.tone),
            SdTileGrid(children: [
              SdMenuTile(title: 'صفحة الوكيل', subtitle: 'إدارة خدمات العملاء', icon: Icons.person_rounded, group: SdGroup.field, badge: 80, onTap: () {}),
              SdMenuTile(title: 'المهام', subtitle: 'إدارة المهام اليومية', icon: Icons.task_alt_rounded, group: SdGroup.field, badge: 120, onTap: () {}),
              SdMenuTile(title: 'الزونات', subtitle: 'إدارة المناطق الجغرافية', icon: Icons.map_rounded, group: SdGroup.field, onTap: () {}),
              SdMenuTile(title: 'مشترك جديد', subtitle: 'تسجيل مشترك FTTH جديد', icon: Icons.person_add_alt_1_rounded, group: SdGroup.field, onTap: () {}),
            ]),
            const SizedBox(height: SdSpace.xl),
          ],
          if (_show(SdGroup.admin) || _show(SdGroup.comms)) ...[
            SdSectionHeader(title: 'الإدارة والموارد · التواصل', tone: SdGroup.admin.tone),
            SdTileGrid(children: [
              if (_show(SdGroup.admin)) ...[
                SdMenuTile(title: 'HR', subtitle: 'الموارد البشرية والحضور والرواتب', icon: Icons.groups_rounded, group: SdGroup.admin, onTap: () {}),
                SdMenuTile(title: 'الحسابات', subtitle: 'النظام المالي والمحاسبي', icon: Icons.account_balance_wallet_rounded, group: SdGroup.admin, onTap: () {}),
              ],
              if (_show(SdGroup.comms)) ...[
                SdMenuTile(title: 'المحادثة', subtitle: 'محادثات الموظفين الداخلية', icon: Icons.chat_bubble_rounded, group: SdGroup.comms, badge: 14, onTap: () {}),
                SdMenuTile(title: 'التبليغات', subtitle: 'الإعلانات والتبليغات', icon: Icons.campaign_rounded, group: SdGroup.comms, onTap: () {}),
              ],
            ]),
            const SizedBox(height: SdSpace.xl),
          ],
          if (_show(SdGroup.platform)) ...[
            SdSectionHeader(title: SdGroup.platform.arabicLabel, tone: SdGroup.platform.tone),
            SdTileGrid(children: [
              SdMenuTile(title: 'منصة الصدارة', subtitle: 'طلبات المواطن والوكيل', icon: Icons.hub_rounded, group: SdGroup.platform, onTap: () {}),
              const SdMenuTile(title: 'سجل العقارات', subtitle: 'بلا صلاحية (مثال)', icon: Icons.home_work_rounded, group: SdGroup.platform, enabled: false, onTap: null),
            ]),
            const SizedBox(height: SdSpace.xl),
          ],

          // بطاقة + أزرار + شارات + مفتاح + حالة فراغ
          SdCard(
            title: 'بطاقة تفاصيل',
            subtitle: 'مثال على البطاقة الموحّدة',
            icon: Icons.info_rounded,
            trailing: const SdStatusChip('ممتاز', status: SdStatus.success),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SdInfoRow(label: 'عنوان IP', value: '192.168.1.1', icon: Icons.router_rounded, ltrValue: true),
                const SdInfoRow(label: 'الحالة', value: 'متصل', icon: Icons.check_circle_rounded),
                const SizedBox(height: SdSpace.sm),
                Wrap(spacing: 8, runSpacing: 8, children: const [
                  SdStatusChip('ممتاز', status: SdStatus.success),
                  SdStatusChip('قيد التنفيذ', status: SdStatus.warning),
                  SdStatusChip('مرفوض', status: SdStatus.danger),
                  SdStatusChip('معلومة', status: SdStatus.info),
                  SdBadge(count: 7),
                ]),
                const SizedBox(height: SdSpace.md),
                Row(children: [
                  SdToggle(value: _toggle, label: 'مثال مفتاح', onChanged: (v) => setState(() => _toggle = v)),
                  const SizedBox(width: 10),
                  const Text('مفتاح مجسّم', style: SdText.label),
                ]),
                const SizedBox(height: SdSpace.md),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  SdButton(label: 'حفظ', icon: Icons.check_rounded, onPressed: () {}),
                  SdButton(label: 'فحص', icon: Icons.play_arrow_rounded, kind: SdButtonKind.accent, onPressed: () {}),
                  SdButton(label: 'إلغاء', kind: SdButtonKind.secondary, onPressed: () {}),
                  SdButton(label: 'حذف', icon: Icons.delete_rounded, kind: SdButtonKind.danger, onPressed: () {}),
                  const SdButton(label: 'معطّل', onPressed: null),
                ]),
              ],
            ),
          ),
          const SizedBox(height: SdSpace.xl),
          // لوحتان: جنباً إلى جنب على الآيباد الأفقي وسطح المكتب، ومتراصّتان على الهاتف.
          const SdTwoPane(
            primary: SdCard(
              title: 'القائمة',
              icon: Icons.list_rounded,
              child: Text('على الهاتف تظهر هذه اللوحة فوق التفاصيل.', style: SdText.bodySm),
            ),
            secondary: SdCard(
              title: 'التفاصيل',
              icon: Icons.article_rounded,
              child: Text('على الآيباد الأفقي وسطح المكتب تظهر بجانب القائمة.', style: SdText.bodySm),
            ),
          ),
          const SizedBox(height: SdSpace.xl),
          const SdCard(
            child: SdEmptyState(
              title: 'لا توجد نتائج',
              message: 'جرّب تغيير الفلاتر أو البحث بكلمة أخرى.',
              icon: Icons.search_off_rounded,
            ),
          ),
        ],
      ),
    );
  }
}
