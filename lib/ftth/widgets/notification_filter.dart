import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// فلتر إشعارات خاص بصفحات FTTH: يمنع ظهور رسالة فشل جلب الرصيد فقط
/// ويسمح بتمرير باقي الرسائل (نجاح / أخطاء أخرى).
class FtthNotificationFilter {
  static const String blockedMessage = 'لم يتم جلب الرصيد';

  /// تحديد ما إذا كان ينبغي إظهار الرسالة.
  /// نحجب فقط النص المطابق تماماً للرسالة المحجوبة.
  static bool shouldShow(String? message) {
    if (message == null) return false;
    return message.trim() !=
        blockedMessage; // السماح بكل شيء ما عدا الرسالة المحجوبة
  }

  /// إظهار إشعار في أعلى الشاشة مع اختفاء تلقائي
  static void showTopNotification(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    Color? backgroundColor,
    Color? textColor,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: backgroundColor ?? Colors.green.shade600,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              message,
              style: TextStyle(
                color: textColor ?? Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // إزالة تلقائية بعد المدة المحددة
    Future.delayed(duration, () {
      overlayEntry.remove();
    });
  }

  /// إظهار الـ SnackBar إذا لم تكن من الرسائل المحجوبة.
  static void show(BuildContext context, SnackBar snackBar) {
    String? text;
    final contentWidget = snackBar.content;
    if (contentWidget is Text) {
      text = contentWidget.data;
    }
    if (shouldShow(text)) {
      // بناء SnackBar جديد قابل للنسخ إذا كان المحتوى نصاً بسيطاً
      final copyable = _toCopyableSnackBar(snackBar, originalText: text);

      // إضافة مدة عرض وموضع في الأعلى
      final enhancedSnackBar = SnackBar(
        content: copyable.content,
        action: copyable.action,
        backgroundColor: copyable.backgroundColor,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 150,
          left: 20,
          right: 20,
        ),
        duration: const Duration(seconds: 3), // يختفي بعد 3 ثوانِ
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(enhancedSnackBar);
    } else {
      // تم حجب رسالة فشل جلب الرصيد.
    }
  }
}

/// دالة مساعدة مريحة.
/// دالة مساعدة سريعة لإظهار إشعار نجاح في الأعلى
void ftthShowSuccessNotification(BuildContext context, String message) {
  FtthNotificationFilter.showTopNotification(
    context,
    message,
    backgroundColor: Colors.green.shade600,
  );
}

/// دالة مساعدة سريعة لإظهار إشعار خطأ في الأعلى
void ftthShowErrorNotification(BuildContext context, String message) {
  FtthNotificationFilter.showTopNotification(
    context,
    message,
    backgroundColor: Colors.red.shade600,
    duration: const Duration(seconds: 4),
  );
}

/// دالة مساعدة سريعة لإظهار إشعار معلومات في الأعلى
void ftthShowInfoNotification(BuildContext context, String message) {
  FtthNotificationFilter.showTopNotification(
    context,
    message,
    backgroundColor: Colors.blue.shade600,
  );
}

void ftthShowSnackBar(BuildContext context, SnackBar snackBar) =>
    FtthNotificationFilter.show(context, snackBar);

/// دالة ذكية لتحويل النصوص إلى الإشعارات المناسبة
void ftthShowSmartNotification(BuildContext context, String message) {
  // كلمات مفاتيح للنجاح
  if (message.contains('تم') ||
      message.contains('نجح') ||
      message.contains('متاح') ||
      message.contains('حفظ') ||
      message.contains('مكتمل') ||
      message.contains('إرسال') ||
      message.contains('تسجيل الدخول')) {
    ftthShowSuccessNotification(context, message);
  }
  // كلمات مفاتيح للأخطاء
  else if (message.contains('خطأ') ||
      message.contains('فشل') ||
      message.contains('تعذر') ||
      message.contains('غير متوفر') ||
      message.contains('غير صحيح') ||
      message.contains('غير جاهز') ||
      message.contains('يرجى') ||
      message.contains('يجب')) {
    ftthShowErrorNotification(context, message);
  }
  // معلومات عامة
  else {
    ftthShowInfoNotification(context, message);
  }
}

/// يحول SnackBar إلى نسخة قابلة للنسخ (زر نسخ + تحديد).
SnackBar _toCopyableSnackBar(SnackBar original, {String? originalText}) {
  // إذا لا يوجد نص واضح، نعيد الأصلي كما هو.
  final text = originalText?.trim();
  if (text == null || text.isEmpty) return original;

  // لو لدى الـ SnackBar فعل (action) موجود مسبقاً، ندمج زر النسخ داخل المحتوى.
  final hasAction = original.action != null;

  Widget buildContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SelectableText(
            text,
            style: (original.content is Text)
                ? (original.content as Text).style
                : null,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'نسخ',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.copy, size: 18, color: Colors.white),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
          },
        ),
      ],
    );
  }

  return SnackBar(
    content: buildContent(),
    backgroundColor: original.backgroundColor,
    behavior: original.behavior,
    elevation: original.elevation,
    margin: original.margin,
    padding: original.padding,
    shape: original.shape,
    width: original.width,
    duration: original.duration,
    dismissDirection: original.dismissDirection,
    action: hasAction
        ? original.action // احتفظ بالفعل الأصلي إن وجد
        : null,
  );
}
