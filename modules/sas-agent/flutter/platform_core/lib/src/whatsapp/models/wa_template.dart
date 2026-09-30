/// قالب رسالة قابل للتعديل مع متغيّرات `{name}` `{expiration}` … إلخ.
library;

/// قالب رسالة. `body` يحوي عناصر نائبة بالصيغة `{key}` تُستبدل بقيم المستلِم.
class WaTemplate {
  /// معرّف ثابت (لا يُترجم) — يُستخدم للتخزين والاستدعاء البرمجي.
  final String id;

  /// عنوان معروض للمستخدم.
  final String title;

  /// نصّ القالب مع عناصر نائبة `{key}`.
  final String body;

  /// هل هو قالب مدمج (لا يُحذف، يُعاد ضبطه فقط)؟
  final bool builtin;

  const WaTemplate({
    required this.id,
    required this.title,
    required this.body,
    this.builtin = false,
  });

  /// المتغيّرات المتوفّرة داخل النصّ (أسماء العناصر النائبة).
  List<String> get variables {
    final re = RegExp(r'\{(\w+)\}');
    return re.allMatches(body).map((m) => m.group(1)!).toSet().toList();
  }

  /// يملأ العناصر النائبة بقيم `vars`؛ أي متغيّر مفقود يُستبدل بفراغ ويُنظَّف السطر.
  String render(Map<String, String> vars) {
    var out = body;
    out = out.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
      final v = vars[m.group(1)] ?? '';
      return v.trim();
    });
    // نظّف الأسطر التي أصبحت فارغة بعد إزالة متغيّر غير موجود.
    out = out
        .split('\n')
        .where((line) => line.trim().isNotEmpty || line.isEmpty)
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return out;
  }

  WaTemplate copyWith({String? title, String? body}) => WaTemplate(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        builtin: builtin,
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'body': body, 'builtin': builtin};

  factory WaTemplate.fromJson(Map<String, dynamic> j) => WaTemplate(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        builtin: (j['builtin'] as bool?) ?? false,
      );
}
