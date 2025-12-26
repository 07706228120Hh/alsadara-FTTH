import 'package:flutter/material.dart';

class LogoutDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmText;
  final String cancelText;
  final IconData? icon;
  final Color? iconColor;

  const LogoutDialog({
    super.key,
    this.title = 'تسجيل الخروج',
    this.message = 'هل تريد العودة إلى النظام الأول؟',
    this.confirmText = 'تسجيل الخروج',
    this.cancelText = 'إلغاء',
    this.icon = Icons.logout_rounded,
    this.iconColor,
  });

  @override
  State<LogoutDialog> createState() => _LogoutDialogState();
}

class _LogoutDialogState extends State<LogoutDialog> {
  bool _clearSavedCredentials = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      title: Row(
        children: [
          if (widget.icon != null) ...[
            Icon(
              widget.icon,
              color: widget.iconColor ?? Theme.of(context).colorScheme.error,
              size: 28,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.message,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'خيارات إضافية:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _clearSavedCredentials,
                  onChanged: (bool? value) {
                    setState(() {
                      _clearSavedCredentials = value ?? false;
                    });
                  },
                  title: const Text(
                    'مسح معلومات تسجيل الدخول المحفوظة',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    'سيتم حذف اسم المستخدم وكلمة المرور المحفوظين محلياً',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(
            widget.cancelText,
            style: const TextStyle(fontSize: 16),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop({
            'confirmed': true,
            'clearCredentials': _clearSavedCredentials,
          }),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            widget.confirmText,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

/// مساعد لعرض مربع حوار تسجيل الخروج المُحسن
class LogoutDialogHelper {
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    String? title,
    String? message,
    String? confirmText,
    String? cancelText,
    IconData? icon,
    Color? iconColor,
  }) async {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return LogoutDialog(
          title: title ?? 'تسجيل الخروج',
          message: message ?? 'هل تريد العودة إلى النظام الأول؟',
          confirmText: confirmText ?? 'تسجيل الخروج',
          cancelText: cancelText ?? 'إلغاء',
          icon: icon,
          iconColor: iconColor,
        );
      },
    );
  }
}
