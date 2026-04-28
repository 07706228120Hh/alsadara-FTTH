/// تنسيق رقم بفاصل مراتب وبدون فاصلة عشرية
/// مثال: 10000.5 → "10,000"
String fmtN(dynamic value) {
  if (value == null) return '0';
  final n = value is num ? value : num.tryParse('$value') ?? 0;
  final s = n.toStringAsFixed(0);
  if (s.length <= 3) return s;
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// تنسيق مع إرجاع '-' إذا null
String fmtNullable(dynamic value) {
  if (value == null) return '-';
  return fmtN(value);
}

/// إزالة فواصل المراتب وتحويل لـ double
double parseN(String s) => double.tryParse(s.replaceAll(',', '')) ?? 0;
