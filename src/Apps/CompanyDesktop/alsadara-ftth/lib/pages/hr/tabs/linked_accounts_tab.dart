/// تبويب «الحسابات المرتبطة» — يدير عدة حسابات FTTH (إنشاء/تعديل/حذف/تحقّق/أساسي)
/// وحسابات الساس (إنشاء/تعديل/حذف) + إظهار/نسخ كلمة المرور عبر endpoint مخصّص.
///
/// يتصل ببوّابة الصدارة الداخلية `/api/linked-accounts/*` عبر LinkedAccountsService.
/// لا يلمس وحدة الساس ولا ينادي أي endpoint ساس مباشرة.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../frontend/frontend.dart';
import '../../../services/linked_accounts_service.dart';
import '../partners_page.dart';

class LinkedAccountsTab extends StatefulWidget {
  /// معرّف المستخدم (الموظف) المالك للحسابات.
  final String userId;
  final String employeeName;

  const LinkedAccountsTab({
    super.key,
    required this.userId,
    this.employeeName = '',
  });

  @override
  State<LinkedAccountsTab> createState() => _LinkedAccountsTabState();
}

class _LinkedAccountsTabState extends State<LinkedAccountsTab> {
  final _service = LinkedAccountsService.instance;

  bool _loading = true;
  bool _busy = false; // عملية جارية (إنشاء/حذف/تحقّق/أساسي)
  String? _error;
  List<LinkedAccount> _accounts = const [];

  /// كلمات مرور FTTH المكشوفة مؤقتاً (id ← password) — لا تُخزَّن إلا في الذاكرة.
  final Map<String, String> _revealed = {};

  List<LinkedAccount> get _ftth => _accounts.where((a) => a.isFtth).toList();
  List<LinkedAccount> get _sas => _accounts.where((a) => a.isSas).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _service.getAccounts(widget.userId);
      if (!mounted) return;
      if (res['success'] == true) {
        setState(() {
          _accounts = (res['data'] as List?)?.cast<LinkedAccount>() ?? const [];
          _revealed.clear();
          _loading = false;
        });
      } else {
        setState(() {
          _error = (res['message'] ?? 'تعذّر جلب الحسابات المرتبطة').toString();
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'حدث خطأ أثناء جلب الحسابات المرتبطة';
        _loading = false;
      });
    }
  }

  void _toast(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ═══════════════ العمليات ═══════════════

  Future<void> _verify(LinkedAccount a) async {
    setState(() => _busy = true);
    final res = await _service.verifyFtth(a.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['success'] == true) {
      final data = res['data'];
      final verified =
          data is Map ? (data['verified'] == true || data['Verified'] == true) : false;
      final memberId = data is Map
          ? (data['ftthMemberId'] ?? data['FtthMemberId'])?.toString()
          : null;
      final String msg;
      if (!verified) {
        msg = 'فشل التحقّق — تأكّد من البيانات';
      } else if (memberId != null && memberId.isNotEmpty) {
        msg = 'تم التوثيق وجلب رقم العضو ($memberId) بنجاح';
      } else {
        msg = 'تم التوثيق (لم يُعثر على رقم عضو مطابق)';
      }
      _toast(msg, color: verified ? SdColors.success : SdColors.warning);
      _load();
    } else {
      _toast(res['message']?.toString() ?? 'تعذّر التحقّق', color: SdColors.danger);
    }
  }

  Future<void> _setPrimary(LinkedAccount a) async {
    setState(() => _busy = true);
    final res = await _service.setPrimaryFtth(a.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['success'] == true) {
      _toast('تم التعيين كحساب أساسي', color: SdColors.success);
      _load();
    } else {
      _toast(res['message']?.toString() ?? 'تعذّر التعيين', color: SdColors.danger);
    }
  }

  Future<void> _reveal(LinkedAccount a) async {
    setState(() => _busy = true);
    final res = await _service.revealFtth(a.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['success'] == true) {
      final data = res['data'];
      final pw = data is Map ? (data['password'] ?? data['Password'])?.toString() : null;
      if (pw != null) {
        setState(() => _revealed[a.id] = pw);
      } else {
        _toast('لم يتم استرجاع كلمة المرور', color: SdColors.warning);
      }
    } else if ((res['statusCode'] as int?) == 403) {
      _toast('إظهار كلمة المرور يتطلب صلاحية أدمن الشركة', color: SdColors.warning);
    } else {
      _toast(res['message']?.toString() ?? 'تعذّر إظهار كلمة المرور',
          color: SdColors.danger);
    }
  }

  /// كشف كلمة مرور حساب ساس — يعالج عقد الخادم الجديد:
  /// 403 الكشف معطّل (علَم OFF) · 403 يتطلب أدمن · 429 تجاوز المحاولات.
  Future<void> _revealSas(LinkedAccount a) async {
    setState(() => _busy = true);
    final res = await _service.revealSas(a.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['success'] == true) {
      final data = res['data'];
      final pw = data is Map ? (data['password'] ?? data['Password'])?.toString() : null;
      if (pw != null) {
        setState(() => _revealed[a.id] = pw);
      } else {
        _toast('لم يتم استرجاع كلمة المرور', color: SdColors.warning);
      }
      return;
    }
    final code = res['statusCode'] as int?;
    final msg = (res['message'] ?? '').toString();
    if (code == 429) {
      _toast('تجاوزت عدد المحاولات المسموح، حاول بعد قليل',
          color: SdColors.warning);
    } else if (code == 403) {
      // ميّز بين «الكشف معطّل» (العلَم OFF) و«يتطلب أدمن» حسب نص رسالة الخادم.
      final disabled =
          msg.contains('معطّل') || msg.contains('معطل') || msg.contains('مغلق');
      if (disabled) {
        _toast(msg.isNotEmpty ? msg : 'كشف اعتماد الساس معطّل',
            color: SdColors.info);
      } else if (msg.isEmpty ||
          msg.contains('أدمن') ||
          msg.contains('صلاحية')) {
        _toast('إظهار كلمة المرور يتطلب صلاحية أدمن الشركة',
            color: SdColors.warning);
      } else {
        // رسالة 403 أخرى من الخادم — اعرضها كما هي.
        _toast(msg, color: SdColors.warning);
      }
    } else {
      _toast(msg.isNotEmpty ? msg : 'تعذّر إظهار كلمة المرور',
          color: SdColors.danger);
    }
  }

  Future<void> _delete(LinkedAccount a) async {
    final kind = a.isSas ? 'الساس' : 'FTTH';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.warning_rounded, color: SdColors.danger),
              const SizedBox(width: 8),
              Text('تأكيد الحذف',
                  style: const TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'هل أنت متأكد من حذف حساب $kind «${a.label.isNotEmpty ? a.label : a.username}»؟',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: SdColors.danger),
              child: const Text('حذف',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    final res =
        a.isSas ? await _service.deleteSas(a.id) : await _service.deleteFtth(a.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['success'] == true) {
      _toast('تم حذف الحساب', color: SdColors.success);
      _load();
    } else {
      _toast(res['message']?.toString() ?? 'تعذّر الحذف', color: SdColors.danger);
    }
  }

  /// حوار إنشاء/تعديل حساب FTTH.
  Future<void> _openFtthDialog({LinkedAccount? existing}) async {
    final isEdit = existing != null;
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final userCtrl = TextEditingController(text: existing?.username ?? '');
    final passCtrl = TextEditingController();
    final serverCtrl = TextEditingController(text: existing?.serverUrl ?? '');
    bool isPrimary = existing?.isPrimary ?? false;
    bool showPass = false;
    bool saving = false;

    // ربط الحساب بشريك رئيسي — حالة الإضافة فقط.
    List<Map<String, dynamic>> partners = const [];
    bool partnersLoading = false;
    bool partnersLoaded = false;
    String? selectedPartnerId;
    List<Map<String, dynamic>> operators = const [];
    bool operatorsLoading = false;
    String? selectedOperator;

    List<Map<String, dynamic>> unwrap(dynamic data) {
      final List raw = data is List
          ? data
          : (data is Map ? (data['data'] ?? data['items'] ?? []) as List : []);
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        return StatefulBuilder(
          builder: (ctx, setD) {
            // تحميل الشركاء مرّة واحدة (إضافة وتعديل — لإسناد شريك لحساب قائم).
            if (!partnersLoaded && !partnersLoading) {
              partnersLoading = true;
              _service.getPartners().then((res) {
                if (!ctx.mounted) return;
                setD(() {
                  partnersLoaded = true;
                  partnersLoading = false;
                  if (res['success'] == true) {
                    partners = unwrap(res['data'])
                        .where((p) => (p['id'] ?? p['Id']) != null)
                        .toList();
                  }
                });
              });
            }
            return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: EdgeInsets.symmetric(
                  horizontal: screenWidth < 600 ? 16 : 40, vertical: 24),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: SdColors.accentTint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.router, color: SdColors.accent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isEdit ? 'تعديل حساب FTTH' : 'ربط حساب FTTH جديد',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _dialogField(labelCtrl, 'التسمية', Icons.label_outline),
                      const SizedBox(height: 12),
                      // ربط بشريك رئيسي + اختيار مشغّل (الإضافة فقط).
                      ...[
                        DropdownButtonFormField<String>(
                          initialValue: selectedPartnerId,
                          isDense: true,
                          isExpanded: true,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: SdColors.ink),
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: partnersLoading
                                ? 'الشريك (جارٍ التحميل…)'
                                : 'الشريك (اختياري)',
                            labelStyle: const TextStyle(
                                fontFamily: 'Cairo', fontSize: 12),
                            prefixIcon:
                                const Icon(Icons.handshake_outlined, size: 20),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          hint: const Text('بدون شريك',
                              style:
                                  TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                          items: partners.map((p) {
                            final id = (p['id'] ?? p['Id']).toString();
                            final name = (p['name'] ?? p['Name'] ?? id)
                                .toString();
                            return DropdownMenuItem(
                              value: id,
                              child: Text(name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontFamily: 'Cairo', fontSize: 13)),
                            );
                          }).toList(),
                          onChanged: partnersLoading
                              ? null
                              : (v) {
                                  setD(() {
                                    selectedPartnerId = v;
                                    // الإضافة: الاسم يُملأ من المشغّل؛ التعديل: الاسم ثابت.
                                    if (!isEdit) {
                                      selectedOperator = null;
                                      operators = const [];
                                      userCtrl.clear();
                                      operatorsLoading = v != null;
                                    }
                                  });
                                  if (!isEdit && v != null) {
                                    _service
                                        .getPartnerOperators(v)
                                        .then((res) {
                                      if (!ctx.mounted) return;
                                      setD(() {
                                        operatorsLoading = false;
                                        if (res['success'] == true) {
                                          operators = unwrap(res['data']);
                                        }
                                      });
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        if (!isEdit && selectedPartnerId != null)
                          DropdownButtonFormField<String>(
                            initialValue: selectedOperator,
                            isDense: true,
                            isExpanded: true,
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                color: SdColors.ink),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: operatorsLoading
                                  ? 'المشغّل (جارٍ التحميل…)'
                                  : 'المشغّل',
                              labelStyle: const TextStyle(
                                  fontFamily: 'Cairo', fontSize: 12),
                              prefixIcon: const Icon(
                                  Icons.account_circle_outlined,
                                  size: 20),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            items: operators.map((o) {
                              final username =
                                  (o['username'] ?? o['Username'] ?? '')
                                      .toString();
                              final display =
                                  (o['displayName'] ?? o['DisplayName'])
                                      ?.toString();
                              final text = (display != null &&
                                      display.isNotEmpty &&
                                      display != username)
                                  ? '$username — $display'
                                  : username;
                              return DropdownMenuItem(
                                value: username,
                                child: Text(text,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontFamily: 'Cairo', fontSize: 13)),
                              );
                            }).toList(),
                            onChanged: operatorsLoading
                                ? null
                                : (v) {
                                    setD(() {
                                      selectedOperator = v;
                                      if (v != null) userCtrl.text = v;
                                    });
                                  },
                          ),
                        if (!isEdit && selectedPartnerId != null)
                          const SizedBox(height: 12),
                        if (isEdit) const SizedBox(height: 12),
                      ],
                      _dialogField(
                        userCtrl,
                        'اسم المستخدم',
                        Icons.person_outline,
                        readOnly: !isEdit && selectedPartnerId != null,
                      ),
                      const SizedBox(height: 12),
                      _dialogField(
                        passCtrl,
                        isEdit
                            ? 'كلمة المرور (اتركها فارغة لعدم التغيير)'
                            : 'كلمة المرور',
                        Icons.vpn_key_outlined,
                        obscure: !showPass,
                        suffix: IconButton(
                          icon: Icon(
                              showPass
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 20),
                          onPressed: () => setD(() => showPass = !showPass),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _dialogField(serverCtrl, 'رابط الخادم (اختياري)',
                          Icons.dns_outlined),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: SdColors.accent,
                        value: isPrimary,
                        onChanged: (v) => setD(() => isPrimary = v),
                        title: const Text('تعيين كحساب أساسي',
                            style:
                                TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء',
                      style: TextStyle(fontFamily: 'Cairo')),
                ),
                ElevatedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (userCtrl.text.trim().isEmpty) {
                            _toast('اسم المستخدم مطلوب', color: SdColors.danger);
                            return;
                          }
                          if (!isEdit && passCtrl.text.isEmpty) {
                            _toast('كلمة المرور مطلوبة', color: SdColors.danger);
                            return;
                          }
                          setD(() => saving = true);
                          final Map<String, dynamic> res;
                          if (isEdit) {
                            res = await _service.updateFtth(
                              existing.id,
                              label: labelCtrl.text.trim(),
                              username: userCtrl.text.trim(),
                              password: passCtrl.text,
                              serverUrl: serverCtrl.text.trim(),
                              isPrimary: isPrimary,
                              partnerId: selectedPartnerId,
                            );
                          } else {
                            res = await _service.createFtth(
                              ownerUserId: widget.userId,
                              label: labelCtrl.text.trim(),
                              username: userCtrl.text.trim(),
                              password: passCtrl.text,
                              serverUrl: serverCtrl.text.trim(),
                              isPrimary: isPrimary,
                              partnerId: selectedPartnerId,
                            );
                          }
                          if (res['success'] == true) {
                            Navigator.pop(ctx, true);
                          } else {
                            setD(() => saving = false);
                            _toast(
                                res['message']?.toString() ??
                                    'تعذّر حفظ الحساب',
                                color: SdColors.danger);
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: const Text('حفظ', style: TextStyle(fontFamily: 'Cairo')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SdColors.accent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            );
          },
        );
      },
    );

    labelCtrl.dispose();
    userCtrl.dispose();
    passCtrl.dispose();
    serverCtrl.dispose();

    if (saved == true) {
      _toast(isEdit ? 'تم تعديل الحساب' : 'تم ربط الحساب', color: SdColors.success);
      _load();
    }
  }

  /// حوار إنشاء/تعديل حساب ساس.
  Future<void> _openSasDialog({LinkedAccount? existing}) async {
    final isEdit = existing != null;
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final serverCtrl = TextEditingController(text: existing?.serverUrl ?? '');
    final userCtrl = TextEditingController(text: existing?.username ?? '');
    final passCtrl = TextEditingController();
    // في التعديل نعبّئ المُضاعِف من القيمة الحالية (أو 1000)، وفي الإنشاء 1000.
    final multiplierCtrl = TextEditingController(
        text: (existing?.amountMultiplier ?? 1000)
            .toString()
            .replaceAll(RegExp(r'\.0$'), ''));
    // نوع الحساب: 0 = SasManager (صفحة وكيل) · 1 = SasUser (نظام ساس).
    // في التعديل نبدأ من القيمة الحالية (أو 0)، وفي الإنشاء الافتراضي 0.
    int accountType = existing?.accountType ?? 0;
    bool showPass = false;
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        return StatefulBuilder(
          builder: (ctx, setD) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: EdgeInsets.symmetric(
                  horizontal: screenWidth < 600 ? 16 : 40, vertical: 24),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: SdColors.platformTint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.support_agent_rounded,
                        color: SdColors.platformBase, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isEdit ? 'تعديل حساب ساس' : 'ربط حساب ساس جديد',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _dialogField(labelCtrl, 'التسمية', Icons.label_outline),
                      const SizedBox(height: 12),
                      _dialogField(serverCtrl, 'رابط خادم الساس',
                          Icons.dns_outlined),
                      const SizedBox(height: 12),
                      _dialogField(userCtrl, 'اسم المستخدم', Icons.person_outline),
                      const SizedBox(height: 12),
                      _dialogField(
                        passCtrl,
                        isEdit
                            ? 'كلمة المرور (اتركها فارغة لعدم التغيير)'
                            : 'كلمة المرور',
                        Icons.vpn_key_outlined,
                        obscure: !showPass,
                        suffix: IconButton(
                          icon: Icon(
                              showPass
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 20),
                          onPressed: () => setD(() => showPass = !showPass),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: accountType,
                        isDense: true,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: SdColors.ink),
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: 'نوع الحساب',
                          labelStyle:
                              const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                          prefixIcon:
                              const Icon(Icons.category_outlined, size: 20),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 0,
                            child: Text('صفحة وكيل (SasManager)',
                                style: TextStyle(
                                    fontFamily: 'Cairo', fontSize: 13)),
                          ),
                          DropdownMenuItem(
                            value: 1,
                            child: Text('نظام ساس (SasUser)',
                                style: TextStyle(
                                    fontFamily: 'Cairo', fontSize: 13)),
                          ),
                        ],
                        onChanged: (v) =>
                            setD(() => accountType = v ?? accountType),
                      ),
                      const SizedBox(height: 12),
                      _dialogField(
                        multiplierCtrl,
                        'مُضاعِف المبلغ (AmountMultiplier)',
                        Icons.close_rounded,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء',
                      style: TextStyle(fontFamily: 'Cairo')),
                ),
                ElevatedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (serverCtrl.text.trim().isEmpty) {
                            _toast('رابط خادم الساس مطلوب',
                                color: SdColors.danger);
                            return;
                          }
                          if (userCtrl.text.trim().isEmpty) {
                            _toast('اسم المستخدم مطلوب', color: SdColors.danger);
                            return;
                          }
                          if (!isEdit && passCtrl.text.isEmpty) {
                            _toast('كلمة المرور مطلوبة', color: SdColors.danger);
                            return;
                          }
                          final multiplier =
                              double.tryParse(multiplierCtrl.text.trim());
                          if (multiplier == null || multiplier <= 0) {
                            _toast('مُضاعِف المبلغ غير صالح',
                                color: SdColors.danger);
                            return;
                          }
                          setD(() => saving = true);
                          final Map<String, dynamic> res;
                          if (isEdit) {
                            res = await _service.updateSas(
                              existing.id,
                              label: labelCtrl.text.trim(),
                              serverUrl: serverCtrl.text.trim(),
                              username: userCtrl.text.trim(),
                              password: passCtrl.text,
                              accountType: accountType,
                              amountMultiplier: multiplier,
                            );
                          } else {
                            res = await _service.createSas(
                              ownerUserId: widget.userId,
                              label: labelCtrl.text.trim(),
                              serverUrl: serverCtrl.text.trim(),
                              username: userCtrl.text.trim(),
                              password: passCtrl.text,
                              accountType: accountType,
                              amountMultiplier: multiplier,
                            );
                          }
                          if (res['success'] == true) {
                            Navigator.pop(ctx, true);
                          } else {
                            setD(() => saving = false);
                            _toast(
                                res['message']?.toString() ??
                                    'تعذّر حفظ الحساب',
                                color: SdColors.danger);
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: const Text('حفظ', style: TextStyle(fontFamily: 'Cairo')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SdColors.platformBase,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    labelCtrl.dispose();
    serverCtrl.dispose();
    userCtrl.dispose();
    passCtrl.dispose();
    multiplierCtrl.dispose();

    if (saved == true) {
      _toast(isEdit ? 'تم تعديل الحساب' : 'تم ربط الحساب',
          color: SdColors.success);
      _load();
    }
  }

  Widget _dialogField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    bool readOnly = false,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      readOnly: readOnly,
      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        filled: readOnly,
        fillColor: readOnly ? SdColors.surfaceAlt : null,
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ═══════════════ البناء ═══════════════

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: SdColors.accent));
    }
    if (_error != null) {
      return SdEmptyState(
        icon: Icons.error_outline,
        status: SdStatus.danger,
        title: _error!,
        action: SdButton(
          label: 'إعادة المحاولة',
          icon: Icons.refresh,
          onPressed: _load,
        ),
      );
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // زر ربط حساب FTTH جديد
            Row(
              children: [
                Expanded(
                  child: Text(
                    'الحسابات المرتبطة',
                    style: SdText.titleSm,
                  ),
                ),
                SdButton(
                  label: 'الشركاء الرئيسيون',
                  icon: Icons.handshake_outlined,
                  kind: SdButtonKind.secondary,
                  height: 44,
                  onPressed: _busy
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const PartnersPage()),
                          ),
                ),
                const SizedBox(width: 8),
                SdButton(
                  label: 'ربط حساب FTTH جديد',
                  icon: Icons.add_link_rounded,
                  kind: SdButtonKind.accent,
                  height: 44,
                  onPressed: _busy ? null : () => _openFtthDialog(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ═══ قسم FTTH ═══
            SdSectionHeader(
              title: 'حسابات FTTH',
              count: _ftth.length,
            ),
            const SizedBox(height: 8),
            if (_ftth.isEmpty)
              _inlineEmpty('لا توجد حسابات FTTH مرتبطة — اضغط «ربط حساب FTTH جديد».')
            else
              ..._ftth.map(_ftthCard),

            const SizedBox(height: 24),

            // ═══ قسم الساس ═══
            Row(
              children: [
                Expanded(
                  child: SdSectionHeader(
                      title: 'حسابات الساس', count: _sas.length),
                ),
                SdButton(
                  label: 'ربط حساب ساس جديد',
                  icon: Icons.add_link_rounded,
                  kind: SdButtonKind.primary,
                  height: 40,
                  onPressed: _busy ? null : () => _openSasDialog(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SdColors.infoTint,
                borderRadius: BorderRadius.circular(SdRadius.sm),
                border: Border.all(color: SdColors.infoTintEdge),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: SdColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'يمكنك إضافة حسابات الساس وتعديلها وحذفها من هنا. '
                      'إظهار كلمة المرور متاح لأدمن الشركة فقط وعند تفعيل الخيار.',
                      style: SdText.bodySm,
                    ),
                  ),
                ],
              ),
            ),
            if (_sas.isEmpty)
              _inlineEmpty('لا توجد حسابات ساس مرتبطة بهذا الموظف.')
            else
              ..._sas.map(_sasCard),

            const SizedBox(height: 40),
          ],
        ),
        if (_busy)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0x33000000),
              child: const Center(
                  child: CircularProgressIndicator(color: SdColors.accent)),
            ),
          ),
      ],
    );
  }

  Widget _inlineEmpty(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SdRadius.md),
        border: Border.all(color: SdColors.divider),
      ),
      child: Column(
        children: [
          Icon(Icons.link_off_rounded, size: 32, color: SdColors.faint),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: SdText.bodySm),
        ],
      ),
    );
  }

  // ═══════════════ بطاقة حساب FTTH (إدارة كاملة) ═══════════════

  Widget _ftthCard(LinkedAccount a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الرأس: التسمية + شارات
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: SdColors.accentTint,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.router, color: SdColors.accent, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.label.isNotEmpty ? a.label : a.username,
                        style: SdText.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (a.role != null && a.role!.isNotEmpty)
                        Text(a.role!, style: SdText.caption),
                    ],
                  ),
                ),
                if (a.isPrimary)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: SdStatusChip('أساسي',
                        status: SdStatus.warning, icon: Icons.star_rounded),
                  ),
                _statusChip(a),
              ],
            ),
            const Divider(height: 20, color: SdColors.divider),

            // اسم المستخدم
            SdInfoRow(
              label: 'اسم المستخدم',
              value: a.username.isEmpty ? '—' : a.username,
              icon: Icons.person_outline,
              ltrValue: true,
            ),

            // رقم عضو الفريق على FTTH (يظهر بعد «توثيق»)
            if (a.ftthMemberId != null && a.ftthMemberId!.isNotEmpty)
              SdInfoRow(
                label: 'رقم العضو (FTTH)',
                value: a.ftthMemberId!,
                icon: Icons.badge_outlined,
                ltrValue: true,
              ),

            // كلمة المرور (مخفية + إظهار + نسخ)
            _passwordRow(a, _reveal),

            if (!a.isActive)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SdStatusChip('معطّل', status: SdStatus.neutral),
              ),

            const SizedBox(height: 12),

            // الأزرار
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionBtn('تحقّق', Icons.verified_outlined, SdColors.info,
                    () => _verify(a)),
                if (!a.isPrimary)
                  _actionBtn('تعيين كأساسي', Icons.star_outline,
                      SdColors.warning, () => _setPrimary(a)),
                _actionBtn('تعديل', Icons.edit_outlined, SdColors.accent,
                    () => _openFtthDialog(existing: a)),
                _actionBtn('حذف', Icons.delete_outline, SdColors.danger,
                    () => _delete(a)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordRow(
      LinkedAccount a, Future<void> Function(LinkedAccount) onReveal) {
    final revealed = _revealed[a.id];
    final shown = revealed != null;
    final display = shown
        ? (revealed.isEmpty ? '—' : revealed)
        : (a.hasSecret ? '••••••••' : '—');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.vpn_key_outlined, size: 18, color: SdColors.faint),
          const SizedBox(width: 8),
          Text('كلمة المرور', style: SdText.bodySm),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              display,
              textAlign: TextAlign.end,
              textDirection: TextDirection.ltr,
              style: shown ? SdText.mono : SdText.label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (a.hasSecret) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: _busy
                  ? null
                  : () {
                      if (shown) {
                        setState(() => _revealed.remove(a.id));
                      } else {
                        onReveal(a);
                      }
                    },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                    shown
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 18,
                    color: SdColors.accent),
              ),
            ),
            if (shown && revealed.isNotEmpty)
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: revealed));
                  _toast('تم نسخ كلمة المرور');
                },
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.copy_rounded, size: 18, color: SdColors.accent),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(LinkedAccount a) {
    final s = (a.status ?? '').toLowerCase();
    if (s == 'verified') {
      return const SdStatusChip('موثّق',
          status: SdStatus.success, icon: Icons.check_circle_outline);
    }
    if (s == 'invalid') {
      return const SdStatusChip('غير صالح',
          status: SdStatus.danger, icon: Icons.error_outline);
    }
    return const SdStatusChip('غير موثّق',
        status: SdStatus.neutral, icon: Icons.help_outline);
  }

  Widget _actionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════ بطاقة حساب الساس (عرض فقط) ═══════════════

  Widget _sasCard(LinkedAccount a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: SdColors.platformTint,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.support_agent_rounded,
                      color: SdColors.platformBase, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    a.label.isNotEmpty ? a.label : a.username,
                    style: SdText.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _statusChip(a),
              ],
            ),
            const Divider(height: 20, color: SdColors.divider),
            SdInfoRow(
              label: 'اسم المستخدم',
              value: a.username.isEmpty ? '—' : a.username,
              icon: Icons.person_outline,
              ltrValue: true,
            ),
            if (a.serverUrl != null && a.serverUrl!.isNotEmpty)
              SdInfoRow(
                label: 'رابط الخادم',
                value: a.serverUrl!,
                icon: Icons.dns_outlined,
                ltrValue: true,
              ),

            // كلمة المرور (مخفية + إظهار + نسخ) — الكشف متاح إن فُعّل علَم الخادم.
            _passwordRow(a, _revealSas),

            if (!a.isActive)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SdStatusChip('معطّل', status: SdStatus.neutral),
              ),

            const SizedBox(height: 12),

            // الأزرار
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionBtn('تعديل', Icons.edit_outlined, SdColors.platformBase,
                    () => _openSasDialog(existing: a)),
                _actionBtn('حذف', Icons.delete_outline, SdColors.danger,
                    () => _delete(a)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
