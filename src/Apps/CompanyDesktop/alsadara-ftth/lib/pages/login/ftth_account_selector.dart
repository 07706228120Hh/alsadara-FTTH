/// حوار اختيار حساب FTTH عند وجود أكثر من حساب مرتبط نشط.
///
/// يُستخدم في المسار الجديد للحسابات المرتبطة المتعددة: عند تسجيل دخول الصدارة
/// إذا كان للمستخدم أكثر من حساب FTTH نشط، يُعرض هذا الحوار لاختيار الحساب،
/// ثم يُسجَّل الدخول خادمياً بالحساب المختار (بلا كلمة مرور على العميل).
library;

import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../../services/linked_accounts_service.dart';

class FtthAccountSelector {
  FtthAccountSelector._();

  /// يعرض حوار الاختيار ويُرجع الحساب المختار أو null عند الإلغاء.
  static Future<LinkedAccount?> show(
    BuildContext context,
    List<LinkedAccount> accounts,
  ) {
    // الحساب الأساسي كافتراضي (إن وُجد)
    LinkedAccount initial = accounts.first;
    for (final a in accounts) {
      if (a.isPrimary) {
        initial = a;
        break;
      }
    }

    return showDialog<LinkedAccount>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _FtthAccountSelectorDialog(
        accounts: accounts,
        initial: initial,
      ),
    );
  }
}

class _FtthAccountSelectorDialog extends StatefulWidget {
  const _FtthAccountSelectorDialog({
    required this.accounts,
    required this.initial,
  });

  final List<LinkedAccount> accounts;
  final LinkedAccount initial;

  @override
  State<_FtthAccountSelectorDialog> createState() =>
      _FtthAccountSelectorDialogState();
}

class _FtthAccountSelectorDialogState
    extends State<_FtthAccountSelectorDialog> {
  late LinkedAccount _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l = context.sd;
    final size = MediaQuery.of(context).size;
    // عرض محدود + ارتفاع محدود لمنع ارتفاع غير منتهٍ (ListView داخل Column).
    final dialogWidth = l.isPhone ? size.width * 0.92 : 460.0;
    final maxHeight = size.height * 0.72;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogWidth,
            maxHeight: maxHeight,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: SdColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: SdColors.primaryTintEdge),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    itemCount: widget.accounts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _accountTile(widget.accounts[i]),
                  ),
                ),
                _footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [SdColors.primary, SdColors.primaryEdge],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.hub_rounded, color: SdColors.gold, size: 24),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'اختر حساب FTTH للدخول',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'لديك أكثر من حساب مرتبط — اختر الحساب المناسب',
                  style: TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'إلغاء',
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _accountTile(LinkedAccount account) {
    final bool isSel = account.id == _selected.id;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _selected = account),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSel ? SdColors.primaryTint : SdColors.ground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSel ? SdColors.primary : SdColors.primaryTintEdge,
            width: isSel ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSel ? SdColors.primary : SdColors.primaryTintEdge,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.router_rounded,
                color: isSel ? Colors.white : SdColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          account.label.isNotEmpty
                              ? account.label
                              : account.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: SdColors.ink,
                          ),
                        ),
                      ),
                      if (account.isPrimary) ...[
                        const SizedBox(width: 8),
                        _primaryBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    account.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: SdColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSel
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: isSel ? SdColors.primary : SdColors.faint,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _primaryBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: SdColors.gold.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SdColors.gold.withValues(alpha: 0.6)),
      ),
      child: const Text(
        'أساسي',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: SdColors.gold,
        ),
      ),
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: SdColors.muted,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('إلغاء',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(_selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: SdColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text(
                'دخول',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
