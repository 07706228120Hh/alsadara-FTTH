import 'package:flutter/material.dart';

/// مجموعة عناصر واجهة موحدة للأزرار والحوار لضمان تناسق عبر الشاشات
class UiKit {
  // زر أساسي بحجم متوسط
  static Widget primaryButton({
    required String label,
    required VoidCallback onPressed,
    IconData? icon,
  }) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: 8),
        ],
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );

    return ElevatedButton(onPressed: onPressed, child: child);
  }

  // زر ثانوي بإطار
  static Widget secondaryButton({
    required String label,
    required VoidCallback onPressed,
    IconData? icon,
  }) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: 8),
        ],
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );

    return OutlinedButton(onPressed: onPressed, child: child);
  }

  // حوار تأكيد موحد يرجع true/false
  static Future<bool?> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    String cancelText = 'إلغاء',
    String confirmText = 'تأكيد',
    Color? confirmColor,
    IconData icon = Icons.help_outline,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Flexible(child: Text(title)),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancelText),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor,
              ),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );
  }
}
