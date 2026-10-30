import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../inventory/services/inventory_api_service.dart';
import '../utils/responsive_helper.dart';
import '../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)

/// تسجيل تشخيصي يعمل في وضع التطوير فقط، فلا تتسرّب السجلّات (نتائج API)
/// إلى سجلّات أجهزة الإصدار (release). خلافاً لـ debugPrint الذي يطبع في كل الأوضاع.
void _devLog(String message) {
  if (kDebugMode) debugPrint(message);
}

// ═══════════════════════════════════════════════════════════
//  نافذة إضافة مواد مصروفة مباشرة من بطاقة المهمة
// ═══════════════════════════════════════════════════════════

Future<bool> showDispenseMaterialsDialog(
  BuildContext context, {
  required String companyId,
  required String taskGuid,
  required String techId,
}) async {
  if (companyId.isEmpty || taskGuid.isEmpty) return false;

  // تحميل عُهدة الفني + كل المواد المتاحة
  List<Map<String, dynamic>> holdings = [];
  List<Map<String, dynamic>> allItems = [];
  bool loading = true;
  bool saving = false; // يمنع الصرف المزدوج (نقرة مزدوجة) أثناء تنفيذ الطلب
  final rows = <_MaterialRow>[];

  bool saved = false;
  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setD) {
        if (loading) {
          Future.microtask(() async {
            try {
              // جلب عُهدة الفني
              if (techId.isNotEmpty) {
                final res = await InventoryApiService.instance
                    .getTechnicianHoldings(techId);
                holdings = ((res['data'] as List?) ?? [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
              }
              // جلب كل المواد المتاحة بالنظام
              final itemsRes = await InventoryApiService.instance
                  .getItems(companyId: companyId);
              allItems = ((itemsRes['data'] as List?) ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            } catch (e) {
              // فشل جلب العُهدة/المواد غير حرج — يُكمل الحوار بقوائم فارغة.
              _devLog('⚠️ تعذّر جلب مواد صرف المهمة: $e');
            }
            if (ctx.mounted) setD(() => loading = false);
          });
        }

        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(children: [
              Icon(Icons.inventory_2, color: SdColors.warning, size: 20),
              SizedBox(width: 8),
              Text('صرف مواد للعميل', style: TextStyle(fontSize: 16)),
            ]),
            content: SizedBox(
              width: context.responsive.isMobile
                  ? context.responsive.availableWidth * 0.9
                  : 550,
              child: loading
                  ? const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()))
                  : allItems.isEmpty && holdings.isEmpty && rows.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                              child: Text('لا توجد مواد في النظام.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 14, color: SdColors.faint))),
                        )
                      : SingleChildScrollView(
                          child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // عرض المواد المتوفرة بعُهدة الفني
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: SdColors.infoTint,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Row(children: [
                                Icon(Icons.info_outline,
                                    size: 16, color: SdColors.info),
                                const SizedBox(width: 6),
                                Expanded(
                                    child: Text(
                                        'اختر المواد المستخدمة (يمكن الصرف حتى بدون رصيد بالعُهدة)',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: SdColors.info,
                                            fontWeight: FontWeight.w600))),
                              ]),
                            ),
                            const SizedBox(height: 12),

                            ...rows.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final row = entry.value;
                              // حساب المتوفر
                              final selected = holdings.where((h) =>
                                  (h['InventoryItemId'] ??
                                          h['inventoryItemId'])
                                      ?.toString() ==
                                  row.itemId);
                              final available = selected.isNotEmpty
                                  ? (selected.first['RemainingQuantity'] ??
                                      selected.first['remainingQuantity'] ??
                                      0)
                                  : 0;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(children: [
                                  Expanded(
                                    flex: 3,
                                    child: DropdownButtonFormField<String>(
                                      value: row.itemId.isEmpty
                                          ? null
                                          : row.itemId,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                          labelText: 'المادة',
                                          border: OutlineInputBorder(),
                                          isDense: true),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black87),
                                      items: () {
                                        // دمج كل المواد مع رصيد العُهدة
                                        final Map<String,
                                            Map<String, dynamic>> merged = {};
                                        for (final item in allItems) {
                                          final id =
                                              (item['Id'] ?? item['id'])
                                                      ?.toString() ??
                                                  '';
                                          if (id.isEmpty) continue;
                                          merged[id] = {
                                            'id': id,
                                            'name':
                                                (item['Name'] ?? item['name'])
                                                        ?.toString() ??
                                                    '',
                                            'holding': 0
                                          };
                                        }
                                        for (final h in holdings) {
                                          final id = (h['InventoryItemId'] ??
                                                      h['inventoryItemId'])
                                                  ?.toString() ??
                                              '';
                                          final rem =
                                              (h['RemainingQuantity'] ??
                                                  h['remainingQuantity'] ??
                                                  0) as num;
                                          if (merged.containsKey(id)) {
                                            merged[id]!['holding'] = rem;
                                          } else {
                                            merged[id] = {
                                              'id': id,
                                              'name': (h['ItemName'] ??
                                                          h['itemName'])
                                                      ?.toString() ??
                                                  '',
                                              'holding': rem
                                            };
                                          }
                                        }
                                        return merged.values.map((m) {
                                          final hld = m['holding'] as num;
                                          final suffix =
                                              hld > 0 ? ' (عُهدة: $hld)' : '';
                                          return DropdownMenuItem<String>(
                                              value: m['id'] as String,
                                              child: Text(
                                                  '${m['name']}$suffix',
                                                  overflow:
                                                      TextOverflow.ellipsis));
                                        }).toList();
                                      }(),
                                      onChanged: (v) =>
                                          setD(() => row.itemId = v ?? ''),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 70,
                                    child: TextFormField(
                                      initialValue: '${row.quantity}',
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      decoration: InputDecoration(
                                          labelText: 'العدد',
                                          border: const OutlineInputBorder(),
                                          isDense: true,
                                          helperText: available > 0
                                              ? 'عُهدة: $available'
                                              : 'بدون عُهدة',
                                          helperStyle: TextStyle(
                                              fontSize: 9,
                                              color: available > 0
                                                  ? SdColors.success
                                                  : SdColors.warning)),
                                      style: const TextStyle(fontSize: 13),
                                      onChanged: (v) =>
                                          row.quantity = int.tryParse(v) ?? 1,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  InkWell(
                                      onTap: () =>
                                          setD(() => rows.removeAt(idx)),
                                      child: const Icon(Icons.remove_circle,
                                          size: 22, color: SdColors.danger)),
                                ]),
                              );
                            }),

                            Center(
                                child: TextButton.icon(
                              onPressed: () =>
                                  setD(() => rows.add(_MaterialRow())),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('إضافة مادة'),
                            )),

                            if (rows.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Center(
                                    child: Text(
                                        'اضغط "إضافة مادة" لتحديد المواد المستخدمة',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: SdColors.faint))),
                              ),
                          ],
                        )),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: SdColors.warning),
                onPressed: (rows.isEmpty || saving)
                    ? null
                    : () async {
                        if (saving) return; // حماية عمق: يغلق نافذة النقرة المزدوجة في نفس الإطار
                        final validItems = rows
                            .where(
                                (r) => r.itemId.isNotEmpty && r.quantity > 0)
                            .toList();
                        if (validItems.isEmpty) return;
                        setD(() => saving = true); // تعطيل الزر أثناء التنفيذ
                        try {
                          await InventoryApiService.instance
                              .useFromTechnicianHoldings(data: {
                            'technicianId': techId,
                            'serviceRequestId': taskGuid,
                            'companyId': companyId,
                            'items': validItems
                                .map((r) => {
                                      'inventoryItemId': r.itemId,
                                      'quantity': r.quantity
                                    })
                                .toList(),
                          });
                          if (ctx.mounted) Navigator.pop(ctx);
                          saved = true;
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('تم صرف المواد من عُهدة الفني'),
                                    backgroundColor: SdColors.success));
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setD(() => saving = false); // السماح بإعادة المحاولة
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                content: Text('خطأ: $e'),
                                backgroundColor: SdColors.danger));
                          }
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('حفظ'),
              ),
            ],
          ),
        );
      });
    },
  );
  return saved;
}

class _MaterialRow {
  String itemId = '';
  int quantity = 1;
}
