/// مخزن القوالب — تحميل/حفظ القوالب (مدمجة + تعديلات المستخدم) محلياً.
///
/// يعتمد `SharedPreferences` الآن؛ الواجهة مجرّدة كي يستبدلها لاحقاً مخزن مدعوم
/// بالباكند (مزامنة عبر الأجهزة) دون تغيير المستهلِكين.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/wa_template.dart';
import 'default_templates.dart';

/// العقد — أي مخزن قوالب يوفّره.
abstract class TemplateStore {
  Future<List<WaTemplate>> load();
  Future<void> save(WaTemplate tpl);
  Future<void> delete(String id);

  /// يعيد قالباً بمعرّفه (أو المدمج الافتراضي إن وُجد).
  Future<WaTemplate?> byId(String id);
}

/// مخزن محلي عبر SharedPreferences. يدمج المدمجة مع تعديلات المستخدم:
/// المدمج المعدَّل يُخزَّن بنسخته الجديدة؛ حذف مدمج = إعادته لأصله.
class LocalTemplateStore implements TemplateStore {
  static const _key = 'wa_templates_v1';

  @override
  Future<List<WaTemplate>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    final overrides = <String, WaTemplate>{};
    final custom = <WaTemplate>[];
    if (raw != null && raw.isNotEmpty) {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      for (final j in list) {
        final t = WaTemplate.fromJson(j);
        if (t.builtin) {
          overrides[t.id] = t;
        } else {
          custom.add(t);
        }
      }
    }
    // المدمجة أولاً (بنسخة المستخدم إن عُدِّلت) ثم القوالب المخصّصة.
    final builtins = kDefaultTemplates.map((d) => overrides[d.id] ?? d).toList();
    return [...builtins, ...custom];
  }

  @override
  Future<void> save(WaTemplate tpl) async {
    final all = await load();
    final idx = all.indexWhere((t) => t.id == tpl.id);
    if (idx >= 0) {
      all[idx] = tpl;
    } else {
      all.add(tpl);
    }
    await _persist(all);
  }

  @override
  Future<void> delete(String id) async {
    final all = await load();
    // المدمج لا يُحذف — يُعاد لأصله (بإزالة النسخة المعدَّلة من التخزين).
    all.removeWhere((t) => t.id == id && !t.builtin);
    await _persist(all);
  }

  @override
  Future<WaTemplate?> byId(String id) async {
    final all = await load();
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// يخزّن فقط ما يختلف عن الافتراضي (المخصّصة + المدمجة المعدَّلة) لتوفير المساحة.
  Future<void> _persist(List<WaTemplate> all) async {
    final sp = await SharedPreferences.getInstance();
    final toStore = <WaTemplate>[];
    for (final t in all) {
      if (!t.builtin) {
        toStore.add(t);
        continue;
      }
      WaTemplate? def;
      for (final d in kDefaultTemplates) {
        if (d.id == t.id) {
          def = d;
          break;
        }
      }
      if (def != null && (def.body != t.body || def.title != t.title)) {
        toStore.add(t); // مدمج معدَّل فقط
      }
    }
    await sp.setString(_key, jsonEncode(toStore.map((t) => t.toJson()).toList()));
  }
}
