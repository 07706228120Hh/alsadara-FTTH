// أداة موحدة لترجمة حالة التذاكر إلى العربية
// أي قيمة غير معروفة تُعاد كما هي

import 'package:flutter/material.dart';

// خريطة ترجمات الحالات. أضفنا مرادفات متعددة لضمان الترجمة مهما كان شكل النص القادم من الـ API
const Map<String, String> _statusMap = {
  // الحالات الأساسية
  'in progress': 'قيد المعالجة',
  'progress': 'قيد المعالجة',
  'processing': 'قيد المعالجة',
  'working': 'قيد المعالجة',
  'open': 'مفتوحة',
  'opened': 'مفتوحة',
  'new': 'جديدة',
  'created': 'جديدة',
  'assigned': 'مُعيّنة',
  'accepted': 'مقبولة',
  'received': 'مستلمة',

  // الإنهاء والإغلاق
  'completed': 'مكتملة',
  'done': 'مكتملة',
  'closed': 'مغلقة',
  'resolved': 'مُحلّة',
  'finished': 'مكتملة',
  'closed successfully': 'أُغلقت بنجاح',

  // الانتظار / الإيقاف
  'pending': 'في الانتظار',
  'on hold': 'معلّقة',
  'hold': 'معلّقة',
  'waiting': 'في الانتظار',
  'waiting for customer': 'بانتظار العميل',
  'waiting for support': 'بانتظار الدعم',
  'waiting for response': 'بانتظار الرد',
  'waiting for customer response': 'بانتظار رد العميل',
  'awaiting response': 'بانتظار الرد',
  'awaiting customer response': 'بانتظار رد العميل',
  'deferred': 'مؤجلة',

  // الإلغاء / الفشل
  'cancelled': 'ملغاة',
  'canceled': 'ملغاة',
  'rejected': 'مرفوضة',
  'failed': 'فاشلة',

  // التصعيد / إعادة الفتح
  'escalated': 'مُصعّدة',
  'reopened': 'أُعيد فتحها',
  're-opened': 'أُعيد فتحها',

  // أخرى محتملة
  'scheduled': 'مجدولة',
  'investigating': 'قيد التحقيق',
  'verifying': 'قيد التحقق',
  'testing': 'قيد الاختبار',
  'queued': 'في قائمة الانتظار',
  'draft': 'مسودة',
  'archived': 'مؤرشفة',
  'partial': 'منجزة جزئياً',
  'partially completed': 'منجزة جزئياً',
  'partially resolved': 'محلولة جزئياً',
  'temporary fix': 'حل مؤقت',
  'monitoring': 'قيد المراقبة',
  'follow up': 'متابعة',
  'follow-up': 'متابعة',

  // أكواد رقمية محتملة (إذا عاد الـ API بأرقام للحالات)
  '0': 'جديدة',
  '1': 'قيد المعالجة',
  '2': 'مكتملة',
  '3': 'مغلقة',
  '4': 'في الانتظار',
  '5': 'ملغاة',
  '6': 'مُصعّدة',
};

// خريطة تعيد الحالة إلى نموذج قياسي للاستخدام المنطقي (فلترة، تصنيف)
// مهما كانت الصيغة (in-progress / IN_PROGRESS / Processing) تُعاد إلى واحدة من:
// in progress, completed, pending, cancelled, new, assigned
const Map<String, String> _canonicalMap = {
  'in progress': 'in progress',
  'progress': 'in progress',
  'processing': 'in progress',
  'working': 'in progress',
  'open': 'new',
  'opened': 'new',
  'created': 'new',
  'new': 'new',
  'assigned': 'assigned',
  'accepted': 'assigned',
  'received': 'assigned',
  'completed': 'completed',
  'done': 'completed',
  'finished': 'completed',
  'resolved': 'completed',
  'closed successfully': 'completed',
  'pending': 'pending',
  'on hold': 'pending',
  'hold': 'pending',
  'waiting': 'pending',
  'waiting for customer': 'pending',
  'waiting for support': 'pending',
  'waiting for response': 'pending',
  'waiting for customer response': 'pending',
  'awaiting response': 'pending',
  'awaiting customer response': 'pending',
  'queued': 'pending',
  'cancelled': 'cancelled',
  'canceled': 'cancelled',
  'rejected': 'cancelled',
  'failed': 'cancelled',
  // أكواد رقمية
  '0': 'new',
  '1': 'in progress',
  '2': 'completed',
  '3': 'completed',
  '4': 'pending',
  '5': 'cancelled',
  '6': 'in progress',
};

String canonicalStatusKey(String? status) {
  if (status == null) return '';
  final normalized = status
      .toLowerCase()
      .replaceAll(RegExp(r'[\n\r\t]'), ' ')
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (_canonicalMap.containsKey(normalized)) return _canonicalMap[normalized]!;
  // محاولة مطابقة جزئية: أول مفتاح موجود ضمن النص
  for (final k in _canonicalMap.keys) {
    if (normalized.contains(k)) return _canonicalMap[k]!;
  }
  return normalized; // يُعاد كـ raw إذا غير معروف
}

String translateTicketStatus(String? status) {
  if (status == null) return 'غير متوفر';
  // تنظيف أساسي: إزالة الرموز والفواصل السفلية وتحويل المسافات المتعددة لمسافة واحدة
  final normalized = status
      .toLowerCase()
      .replaceAll(RegExp(r'[\n\r\t]'), ' ')
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // محاولة المطابقة مباشرة أولاً
  if (_statusMap.containsKey(normalized)) return _statusMap[normalized]!;
  // إذا لم توجد مطابقة مباشرة نحاول بعض المعالجات البسيطة
  // مثال: إزالة كلمة ticket أو status إن وجدت في البداية
  final cleaned = normalized.replaceFirst(RegExp(r'^(ticket|status) '), '');
  if (_statusMap.containsKey(cleaned)) return _statusMap[cleaned]!;
  // إعادة الأصل إن لم تُعرف
  return status;
}

Color statusColor(String? status) {
  final s = status?.toLowerCase().trim();
  switch (s) {
    case 'in progress':
    case 'progress':
    case 'processing':
    case 'working':
      return Colors.orange;
    case 'completed':
    case 'done':
    case 'finished':
    case 'resolved':
    case 'closed successfully':
      return Colors.green;
    case 'pending':
    case 'on hold':
    case 'hold':
    case 'waiting':
    case 'waiting for customer':
    case 'waiting for support':
    case 'queued':
      return Colors.blue;
    case 'cancelled':
    case 'canceled':
    case 'rejected':
    case 'failed':
      return Colors.red;
    case 'new':
    case 'open':
    case 'opened':
    case 'created':
      return Colors.purple;
    case 'assigned':
    case 'accepted':
    case 'received':
      return Colors.teal;
    case 'escalated':
      return Colors.deepOrange;
    case 'reopened':
    case 're-opened':
      return Colors.indigo;
    case 'monitoring':
    case 'verifying':
    case 'investigating':
      return Colors.amber;
    case 'draft':
    case 'archived':
      return Colors.grey;
    default:
      // محاولة تلوين الأكواد الرقمية حسب معناها
      if (s == '0') return Colors.purple; // جديدة
      if (s == '1') return Colors.orange; // قيد المعالجة
      if (s == '2') return Colors.green; // مكتملة
      if (s == '3') return Colors.grey; // مغلقة
      if (s == '4') return Colors.blue; // انتظار
      if (s == '5') return Colors.red; // ملغاة
      if (s == '6') return Colors.deepOrange; // مُصعّدة
      return Colors.grey;
  }
}
