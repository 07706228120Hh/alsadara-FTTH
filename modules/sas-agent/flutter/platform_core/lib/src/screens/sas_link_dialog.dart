import 'package:flutter/material.dart';

import '../api/subscriber_api.dart';
import '../widgets/banner.dart';

/// حوار ربط اعتماد بوابة SAS بحساب المشترك (يُطلب مرة واحدة قبل العمليات الكتابية).
/// يُرجع true عند نجاح الربط.
Future<bool> showSasLinkDialog(
  BuildContext context, {
  required SubscriberApi api,
  required int accountId,
  String? initialUsername,
}) async {
  final userCtl = TextEditingController(text: initialUsername ?? '');
  final passCtl = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      bool busy = false;
      return StatefulBuilder(
        builder: (ctx2, setLocal) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('ربط حساب بوابة SAS'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'أدخل اسم المستخدم وكلمة المرور الخاصّة بحسابك في بوابة المزوّد '
                  'لتفعيل العمليات (تغيير كلمة المرور، استبدال كرت…). تُحفظ مشفّرة.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userCtl,
                  decoration: const InputDecoration(
                      labelText: 'اسم المستخدم', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passCtl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'كلمة المرور', isDense: true, border: OutlineInputBorder()),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx2, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (userCtl.text.trim().isEmpty || passCtl.text.isEmpty) {
                          toast(ctx2, 'أدخل اسم المستخدم وكلمة المرور', kind: BannerKind.error);
                          return;
                        }
                        setLocal(() => busy = true);
                        try {
                          final ok = await api.sasLink(
                              accountId, userCtl.text.trim(), passCtl.text);
                          if (ctx2.mounted) Navigator.pop(ctx2, ok);
                        } catch (e) {
                          setLocal(() => busy = false);
                          if (ctx2.mounted) {
                            toast(ctx2, 'فشل الربط: $e', kind: BannerKind.error);
                          }
                        }
                      },
                child: busy
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('ربط'),
              ),
            ],
          ),
        ),
      );
    },
  );
  return result == true;
}
