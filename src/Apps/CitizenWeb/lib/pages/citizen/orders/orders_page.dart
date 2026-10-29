import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sadara_design/sadara_design.dart';

/// الطلبات والفواتير — موحّدة على نظام تصميم الصدارة (3D).
class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  static final List<Map<String, dynamic>> _orders = [
    {'id': 'ORD-001', 'type': 'subscription', 'title': 'تجديد اشتراك إنترنت', 'description': 'باقة 100 ميجا - شهر واحد', 'amount': 299.0, 'status': 'completed', 'date': '2026-01-30', 'paymentMethod': 'visa'},
    {'id': 'ORD-002', 'type': 'upgrade', 'title': 'ترقية الباقة', 'description': 'من 50 ميجا إلى 100 ميجا', 'amount': 50.0, 'status': 'processing', 'date': '2026-01-28', 'paymentMethod': 'apple_pay'},
    {'id': 'ORD-003', 'type': 'store', 'title': 'راوتر واي فاي 6', 'description': 'TP-Link AX3000', 'amount': 450.0, 'status': 'shipping', 'date': '2026-01-25', 'paymentMethod': 'stc_pay'},
    {'id': 'ORD-004', 'type': 'master', 'title': 'شحن ماستر كارد', 'description': 'شحن رصيد 500 د.ع', 'amount': 500.0, 'status': 'completed', 'date': '2026-01-20', 'paymentMethod': 'visa'},
    {'id': 'ORD-005', 'type': 'maintenance', 'title': 'طلب صيانة', 'description': 'إصلاح انقطاع الخدمة', 'amount': 0.0, 'status': 'pending', 'date': '2026-01-15', 'paymentMethod': null},
  ];

  static final List<Map<String, dynamic>> _invoices = [
    {'id': 'INV-2026-001', 'period': 'يناير 2026', 'amount': 299.0, 'status': 'paid', 'dueDate': '2026-01-15', 'paidDate': '2026-01-10', 'items': [
      {'name': 'اشتراك إنترنت 100 ميجا', 'amount': 270.0}, {'name': 'ضريبة القيمة المضافة (15%)', 'amount': 29.0}]},
    {'id': 'INV-2026-002', 'period': 'فبراير 2026', 'amount': 349.0, 'status': 'unpaid', 'dueDate': '2026-02-15', 'paidDate': null, 'items': [
      {'name': 'اشتراك إنترنت 100 ميجا', 'amount': 270.0}, {'name': 'رسوم ترقية', 'amount': 50.0}, {'name': 'ضريبة القيمة المضافة (15%)', 'amount': 29.0}]},
    {'id': 'INV-2025-012', 'period': 'ديسمبر 2025', 'amount': 249.0, 'status': 'paid', 'dueDate': '2025-12-15', 'paidDate': '2025-12-14', 'items': [
      {'name': 'اشتراك إنترنت 50 ميجا', 'amount': 220.0}, {'name': 'ضريبة القيمة المضافة (15%)', 'amount': 29.0}]},
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: SdPage(
        scrollable: false,
        padding: EdgeInsets.zero,
        appBar: SdAppBar(
          title: 'الطلبات والفواتير',
          onBack: () => context.go('/citizen/home'),
          bottom: const SdTabBar(
            height: 50,
            tabs: [Tab(text: 'الطلبات'), Tab(text: 'الفواتير')],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(SdSpace.gutter, SdSpace.md, SdSpace.gutter, SdSpace.lg),
              children: [for (final o in _orders) _orderCard(o)],
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(SdSpace.gutter, SdSpace.md, SdSpace.gutter, SdSpace.lg),
              children: [for (final v in _invoices) _invoiceCard(v)],
            ),
          ],
        ),
      ),
    );
  }

  // ── بطاقة طلب ──
  Widget _orderCard(Map<String, dynamic> o) {
    final ty = _typeOf(o['type'] as String);
    final st = _statusOf(o['status'] as String);
    final amount = (o['amount'] as num);
    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.sm),
      child: SdRaised(
        radius: SdRadius.lg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SdIconCube(icon: ty.$1, tone: ty.$2, size: 44),
                const SizedBox(width: SdSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(o['title'] as String,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: SdText.label),
                      Text(o['description'] as String,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: SdText.caption),
                    ],
                  ),
                ),
                SdStatusChip(st.$2, status: st.$1),
              ],
            ),
            const Divider(height: SdSpace.lg),
            Row(
              children: [
                Text('#${o['id']}', style: SdText.caption),
                const SizedBox(width: SdSpace.sm),
                Text(o['date'] as String, style: SdText.caption),
                const Spacer(),
                if (amount > 0)
                  Text('${amount.toStringAsFixed(0)} د.ع',
                      style: SdText.titleSm.copyWith(color: SdColors.primary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── بطاقة فاتورة ──
  Widget _invoiceCard(Map<String, dynamic> v) {
    final paid = v['status'] == 'paid';
    final items = (v['items'] as List).cast<Map<String, dynamic>>();
    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.sm),
      child: SdRaised(
        radius: SdRadius.lg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SdIconCube(
                    icon: Icons.receipt_long_rounded,
                    group: SdGroup.admin,
                    size: 44),
                const SizedBox(width: SdSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('فاتورة ${v['period']}', style: SdText.label),
                      Text('#${v['id']}', style: SdText.caption),
                    ],
                  ),
                ),
                SdStatusChip(paid ? 'مدفوعة' : 'غير مدفوعة',
                    status: paid ? SdStatus.success : SdStatus.warning),
              ],
            ),
            const Divider(height: SdSpace.lg),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(it['name'] as String, style: SdText.bodySm)),
                    Text('${(it['amount'] as num).toStringAsFixed(0)} د.ع', style: SdText.bodySm),
                  ],
                ),
              ),
            const Divider(height: SdSpace.md),
            Row(
              children: [
                Text('الإجمالي', style: SdText.label),
                const Spacer(),
                Text('${(v['amount'] as num).toStringAsFixed(0)} د.ع',
                    style: SdText.titleSm.copyWith(color: SdColors.primary)),
              ],
            ),
            if (!paid) ...[
              const SizedBox(height: SdSpace.sm),
              Text('تاريخ الاستحقاق: ${v['dueDate']}',
                  style: SdText.caption.copyWith(color: SdColors.warningText)),
            ],
          ],
        ),
      ),
    );
  }

  static const SdTone _net = SdTone(
    light: SdColors.accentGlow, base: SdColors.accent, edge: SdColors.accentEdge,
    tint: SdColors.accentTint, tintEdge: SdColors.accentTintEdge, text: SdColors.accentEdge,
  );

  (IconData, SdTone) _typeOf(String t) {
    switch (t) {
      case 'subscription': return (Icons.wifi_rounded, _net);
      case 'upgrade': return (Icons.upgrade_rounded, SdStatus.success.tone);
      case 'store': return (Icons.shopping_cart_rounded, SdGroup.field.tone);
      case 'master': return (Icons.credit_card_rounded, SdGroup.platform.tone);
      case 'maintenance': return (Icons.build_rounded, SdStatus.warning.tone);
      default: return (Icons.receipt_rounded, SdGroup.neutral.tone);
    }
  }

  (SdStatus, String) _statusOf(String s) {
    switch (s) {
      case 'completed': return (SdStatus.success, 'مكتمل');
      case 'processing': return (SdStatus.info, 'قيد المعالجة');
      case 'shipping': return (SdStatus.warning, 'قيد الشحن');
      case 'pending': return (SdStatus.neutral, 'معلّق');
      case 'cancelled': return (SdStatus.danger, 'ملغي');
      default: return (SdStatus.neutral, s);
    }
  }
}
