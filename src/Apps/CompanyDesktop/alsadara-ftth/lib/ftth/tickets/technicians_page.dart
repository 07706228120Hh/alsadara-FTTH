/// اسم الصفحة: الفنيين
/// وصف الصفحة: صفحة إدارة الفنيين والصيانة
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../permissions/permissions.dart';
import '../../frontend/tokens/sd_colors.dart' show SdColors;
import '../../frontend/components/sd_app_bar.dart';

/// صفحة محلية لإدارة فني التوصيل (اسم + رقم)
/// يتم حفظ البيانات محلياً في SharedPreferences تحت المفتاح 'local_technicians_list'
class TechniciansPage extends StatefulWidget {
  const TechniciansPage({super.key});

  @override
  State<TechniciansPage> createState() => _TechniciansPageState();
}

class _TechniciansPageState extends State<TechniciansPage> {
  static const String storageKey = 'local_technicians_list';
  List<Map<String, String>> technicians = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          technicians = decoded
              .whereType<Map>()
              .map((e) => {
                    'name': (e['name'] ?? '').toString(),
                    'phone': (e['phone'] ?? '').toString(),
                  })
              .toList();
        }
      } catch (_) {}
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(technicians));
  }

  void _addOrEdit({Map<String, String>? existing, int? index}) {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final phoneCtrl = TextEditingController(text: existing?['phone'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: SdColors.groundAlt,
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(
                existing == null ? Icons.person_add : Icons.edit,
                color: SdColors.muted,
              ),
            ),
            const SizedBox(width: 12),
            Text(existing == null ? 'إضافة فني جديد' : 'تعديل بيانات الفني'),
          ],
        ),
        content: SizedBox(
          width: min(400, MediaQuery.of(context).size.width * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  labelText: 'اسم الفني',
                  hintText: 'أدخل الاسم الكامل',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: 'رقم الهاتف',
                  hintText: '07XXXXXXXXX',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final phone = phoneCtrl.text.trim();
              if (name.isEmpty || phone.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('يرجى إدخال الاسم ورقم الهاتف'),
                    backgroundColor: SdColors.danger,
                  ),
                );
                return;
              }
              setState(() {
                if (existing == null) {
                  technicians.add({'name': name, 'phone': phone});
                } else if (index != null &&
                    index >= 0 &&
                    index < technicians.length) {
                  technicians[index] = {'name': name, 'phone': phone};
                }
              });
              _persist();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(existing == null
                      ? 'تم إضافة الفني بنجاح'
                      : 'تم تحديث بيانات الفني'),
                  backgroundColor: SdColors.success,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.save),
            label: const Text('حفظ'),
          )
        ],
      ),
    );
  }

  void _delete(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: SdColors.dangerTint,
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(Icons.warning, color: SdColors.danger),
            ),
            const SizedBox(width: 12),
            const Text('تأكيد الحذف'),
          ],
        ),
        content: Text(
            'هل أنت متأكد من حذف الفني "${technicians[index]['name']}"؟\nلا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton.icon(
            onPressed: () {
              setState(() => technicians.removeAt(index));
              _persist();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم حذف الفني بنجاح'),
                  backgroundColor: SdColors.warning,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SdColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.delete),
            label: const Text('حذف'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SdAppBar(
        title: 'فني التوصيل',
        actions: [
          if (PermissionManager.instance.canAdd('technicians'))
            IconButton(
              tooltip: 'إضافة فني جديد',
              onPressed: () => _addOrEdit(),
              icon: const Icon(Icons.add_circle_outline),
            ),
        ],
      ),
      floatingActionButton: PermissionManager.instance.canAdd('technicians')
          ? FloatingActionButton.extended(
              onPressed: () => _addOrEdit(),
              backgroundColor: SdColors.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('إضافة فني',
                  style: TextStyle(color: Colors.white)),
            )
          : null,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : technicians.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: SdColors.groundAlt,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Icon(
                          Icons.engineering,
                          size: 80,
                          color: SdColors.faint,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'لا يوجد فنيون مضافون',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: SdColors.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'أضف الفنيين لتسهيل التواصل معهم',
                        style: TextStyle(
                          fontSize: 14,
                          color: SdColors.faint,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (PermissionManager.instance.canAdd('technicians'))
                        ElevatedButton.icon(
                          onPressed: () => _addOrEdit(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SdColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25)),
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة أول فني'),
                        )
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: technicians.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final tech = technicians[i];
                    return Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: LinearGradient(
                            colors: [Colors.white, SdColors.surfaceAlt],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: Container(
                            width: 55,
                            height: 55,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [SdColors.primary, SdColors.primaryLight],
                              ),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: Center(
                              child: Text(
                                tech['name']!.isNotEmpty
                                    ? tech['name']!
                                        .characters
                                        .first
                                        .toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            tech['name'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              const Icon(Icons.phone,
                                  size: 16, color: SdColors.faint),
                              const SizedBox(width: 4),
                              Text(
                                tech['phone'] ?? '',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: SdColors.successTint,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: IconButton(
                                  tooltip: 'اتصال',
                                  icon: Icon(Icons.call,
                                      size: 20, color: SdColors.success),
                                  onPressed: () async {
                                    final phone = tech['phone'] ?? '';
                                    if (phone.isNotEmpty) {
                                      await Clipboard.setData(
                                          ClipboardData(text: phone));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text('تم نسخ رقم الهاتف'),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                decoration: BoxDecoration(
                                  color: SdColors.infoTint,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: PermissionManager.instance
                                        .canEdit('technicians')
                                    ? IconButton(
                                        tooltip: 'تعديل',
                                        icon: Icon(Icons.edit,
                                            size: 20,
                                            color: SdColors.info),
                                        onPressed: () => _addOrEdit(
                                            existing: tech, index: i),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                decoration: BoxDecoration(
                                  color: SdColors.dangerTint,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: PermissionManager.instance
                                        .canDelete('technicians')
                                    ? IconButton(
                                        tooltip: 'حذف',
                                        icon: Icon(Icons.delete_forever,
                                            size: 20,
                                            color: SdColors.danger),
                                        onPressed: () => _delete(i),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
