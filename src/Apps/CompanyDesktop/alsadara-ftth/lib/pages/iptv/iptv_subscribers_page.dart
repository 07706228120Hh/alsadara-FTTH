import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../services/iptv_service.dart';
import '../../services/custom_auth_service.dart';
import '../../services/vps_auth_service.dart';
import '../../services/local_database_service.dart';
import '../../whatsapp/services/whatsapp_sender_service.dart';
import '../../whatsapp/services/whatsapp_system_settings_service.dart'
    show WhatsAppOperationType;

/// صفحة إدارة مشتركي IPTV
class IptvSubscribersPage extends StatefulWidget {
  const IptvSubscribersPage({super.key});

  @override
  State<IptvSubscribersPage> createState() => _IptvSubscribersPageState();
}

class _IptvSubscribersPageState extends State<IptvSubscribersPage> {
  List<Map<String, dynamic>> _subscribers = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _searchQuery = '';
  String _statusFilter = 'all'; // all, active, inactive

  String? get _companyId =>
      CustomAuthService().currentTenantId ??
      VpsAuthService.instance.currentCompanyId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (_companyId == null) return;
    setState(() => _loading = true);

    try {
      final data = await IptvService.getAll(_companyId!);
      if (!mounted) return;

      // جلب حالة اشتراك FTTH للمرتبطين
      await _enrichWithFtthStatus(data);

      setState(() {
        _subscribers = data;
        _applyFilters();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// إضافة حالة اشتراك FTTH من البيانات المحلية
  Future<void> _enrichWithFtthStatus(List<Map<String, dynamic>> data) async {
    try {
      final allLocal = await LocalDatabaseService.instance.getAllSubscribers();
      if (allLocal.isEmpty) return;

      // بناء خريطة سريعة بـ subscription_id
      final localMap = <String, Map<String, dynamic>>{};
      for (final s in allLocal) {
        final subId = s['subscription_id']?.toString() ?? '';
        if (subId.isNotEmpty) localMap[subId] = s;
      }

      for (final iptv in data) {
        final linkedId = iptv['subscriptionId']?.toString();
        if (linkedId != null &&
            linkedId.isNotEmpty &&
            localMap.containsKey(linkedId)) {
          final ftth = localMap[linkedId]!;
          iptv['_ftthStatus'] = ftth['status'] ?? '';
          iptv['_ftthExpires'] = ftth['expires'] ?? '';
          iptv['_ftthDisplayName'] = ftth['display_name'] ?? '';
          iptv['_ftthProfileName'] = ftth['profile_name'] ?? '';
          iptv['_ftthZone'] = ftth['zone_name'] ?? ftth['zone_id'] ?? '';
        }
      }
    } catch (_) {}
  }

  void _applyFilters() {
    var result = List<Map<String, dynamic>>.from(_subscribers);

    // فلتر الحالة
    if (_statusFilter == 'active') {
      result = result.where((s) => s['isActive'] == true).toList();
    } else if (_statusFilter == 'inactive') {
      result = result.where((s) => s['isActive'] != true).toList();
    }

    // فلتر البحث
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((s) {
        final name = (s['customerName'] ?? '').toString().toLowerCase();
        final phone = (s['phone'] ?? '').toString().toLowerCase();
        final user = (s['iptvUsername'] ?? '').toString().toLowerCase();
        final code = (s['iptvCode'] ?? '').toString().toLowerCase();
        final location = (s['location'] ?? '').toString().toLowerCase();
        final zone = (s['_ftthZone'] ?? '').toString().toLowerCase();
        return name.contains(q) ||
            phone.contains(q) ||
            user.contains(q) ||
            code.contains(q) ||
            location.contains(q) ||
            zone.contains(q);
      }).toList();
    }

    _filtered = result;
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _subscribers.where((s) => s['isActive'] == true).length;
    final inactiveCount = _subscribers.length - activeCount;

    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'مشتركي IPTV',
          actions: [
            SdAppBarAction(
              icon: Icons.refresh_rounded,
              label: 'تحديث',
              onPressed: _loadData,
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddEditDialog(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('إضافة مشترك',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: SdColors.primary,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        body: SafeArea(
          top: false,
          child: Column(
          children: [
            // شريط الإحصائيات والبحث
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _buildStatChip(
                    'الكل',
                    _subscribers.length,
                    SdColors.platformBase,
                    _statusFilter == 'all',
                    () => setState(() {
                      _statusFilter = 'all';
                      _applyFilters();
                    }),
                  ),
                  const SizedBox(width: 8),
                  _buildStatChip(
                    'فعال',
                    activeCount,
                    SdColors.success,
                    _statusFilter == 'active',
                    () => setState(() {
                      _statusFilter = 'active';
                      _applyFilters();
                    }),
                  ),
                  const SizedBox(width: 8),
                  _buildStatChip(
                    'غير فعال',
                    inactiveCount,
                    SdColors.danger,
                    _statusFilter == 'inactive',
                    () => setState(() {
                      _statusFilter = 'inactive';
                      _applyFilters();
                    }),
                  ),
                  const Spacer(),
                  // حقل البحث
                  SizedBox(
                    width: 300,
                    child: TextField(
                      style: const TextStyle(
                          color: SdColors.ink, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'بحث بالاسم، الهاتف، اليوزر، الكود...',
                        hintStyle: TextStyle(
                            color: SdColors.faint, fontSize: 13),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: SdColors.faint, size: 20),
                        filled: true,
                        fillColor: SdColors.surfaceAlt,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() {
                        _searchQuery = v;
                        _applyFilters();
                      }),
                    ),
                  ),
                ],
              ),
            ),

            // الجدول
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: SdColors.platformBase))
                  : _filtered.isEmpty
                      ? Center(
                          child: SdEmptyState(
                            icon: Icons.live_tv_rounded,
                            title: _subscribers.isEmpty
                                ? 'لا يوجد مشتركين IPTV'
                                : 'لا توجد نتائج',
                          ),
                        )
                      : _buildDataTable(),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildStatChip(
      String label, int count, Color color, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : SdColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: selected ? color : SdColors.muted,
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataTable() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(SdColors.primary),
            dataRowColor: WidgetStateProperty.all(Colors.white),
            columnSpacing: 16,
            horizontalMargin: 16,
            headingTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13),
            dataTextStyle:
                const TextStyle(color: SdColors.ink, fontSize: 13),
            columns: const [
              DataColumn(label: Text('#')),
              DataColumn(label: Text('الاسم')),
              DataColumn(label: Text('الهاتف')),
              DataColumn(label: Text('يوزر IPTV')),
              DataColumn(label: Text('باسوورد')),
              DataColumn(label: Text('الكود')),
              DataColumn(label: Text('المدة')),
              DataColumn(label: Text('حالة IPTV')),
              DataColumn(label: Text('اشتراك FTTH')),
              DataColumn(label: Text('المنطقة')),
              DataColumn(label: Text('الإجراءات')),
            ],
            rows: List.generate(_filtered.length, (i) {
              final sub = _filtered[i];
              final isActive = sub['isActive'] == true;

              return DataRow(
                color: WidgetStateProperty.resolveWith((states) =>
                    i.isEven ? Colors.white : SdColors.surfaceAlt),
                cells: [
                  DataCell(Text('${i + 1}',
                      style: TextStyle(color: SdColors.faint))),
                  DataCell(Text(sub['customerName'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w500))),
                  DataCell(Text(sub['phone'] ?? '-')),
                  DataCell(SelectableText(sub['iptvUsername'] ?? '-',
                      style: const TextStyle(
                          color: SdColors.platformBase,
                          fontSize: 13,
                          fontWeight: FontWeight.w500))),
                  DataCell(SelectableText(sub['iptvPassword'] ?? '-',
                      style: const TextStyle(fontSize: 13))),
                  DataCell(SelectableText(sub['iptvCode'] ?? '-',
                      style: const TextStyle(fontSize: 13))),
                  DataCell(Text('${sub['durationMonths'] ?? 0} شهر')),
                  DataCell(Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive
                          ? SdColors.success.withValues(alpha: 0.1)
                          : SdColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isActive ? 'فعال' : 'غير فعال',
                      style: TextStyle(
                        color: isActive
                            ? SdColors.successEdge
                            : SdColors.dangerEdge,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )),
                  // حالة اشتراك FTTH
                  DataCell(_buildFtthStatusCell(sub)),
                  DataCell(_buildLocationCell(sub)),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildActionButton(
                        icon: Icons.send_rounded,
                        color: SdColors.success,
                        tooltip: 'إرسال عبر واتساب',
                        onTap: () => _sendWhatsApp(sub),
                      ),
                      const SizedBox(width: 4),
                      _buildActionButton(
                        icon: Icons.copy_rounded,
                        color: SdColors.info,
                        tooltip: 'نسخ البيانات',
                        onTap: () => _copyData(sub),
                      ),
                      const SizedBox(width: 4),
                      _buildActionButton(
                        icon: Icons.edit_rounded,
                        color: SdColors.warning,
                        tooltip: 'تعديل',
                        onTap: () => _showAddEditDialog(existing: sub),
                      ),
                      const SizedBox(width: 4),
                      _buildActionButton(
                        icon: Icons.delete_outline_rounded,
                        color: SdColors.danger,
                        tooltip: 'حذف',
                        onTap: () => _confirmDelete(sub),
                      ),
                    ],
                  )),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildFtthStatusCell(Map<String, dynamic> sub) {
    final ftthStatus = sub['_ftthStatus']?.toString() ?? '';
    final ftthExpires = sub['_ftthExpires']?.toString() ?? '';
    final ftthProfile = sub['_ftthProfileName']?.toString() ?? '';
    final hasLink = sub['subscriptionId'] != null &&
        sub['subscriptionId'].toString().isNotEmpty;

    if (!hasLink) {
      return Text('غير مرتبط',
          style: TextStyle(color: SdColors.faint, fontSize: 12));
    }

    if (ftthStatus.isEmpty) {
      return Text('لا توجد بيانات',
          style: TextStyle(color: SdColors.warning, fontSize: 12));
    }

    final isActiveFtth =
        ftthStatus.toLowerCase() == 'active' || ftthStatus == 'فعال';

    // حساب هل الاشتراك منتهي بالتاريخ
    bool isExpired = false;
    String expiresLabel = '';
    int daysLeft = 0;
    if (ftthExpires.isNotEmpty) {
      final expDate = DateTime.tryParse(ftthExpires);
      if (expDate != null) {
        isExpired = expDate.isBefore(DateTime.now());
        expiresLabel = DateFormat('yyyy-MM-dd').format(expDate);
        daysLeft = expDate.difference(DateTime.now()).inDays;
      }
    }

    final color = isActiveFtth && !isExpired ? SdColors.success : SdColors.danger;
    final colorEdge =
        isActiveFtth && !isExpired ? SdColors.successEdge : SdColors.dangerEdge;

    final statusText =
        isExpired ? 'منتهي' : (isActiveFtth ? 'فعال' : ftthStatus);

    return Tooltip(
      message: [
        'الحالة: $statusText',
        if (ftthProfile.isNotEmpty) 'الباقة: $ftthProfile',
        if (expiresLabel.isNotEmpty) 'ينتهي: $expiresLabel',
        if (!isExpired && daysLeft > 0) 'متبقي: $daysLeft يوم',
      ].join('\n'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_rounded, size: 13, color: colorEdge),
            const SizedBox(width: 4),
            Text(statusText,
                style: TextStyle(
                    color: colorEdge,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCell(Map<String, dynamic> sub) {
    final ftthZone = sub['_ftthZone']?.toString() ?? '';
    final manualLocation = sub['location']?.toString() ?? '';

    if (ftthZone.isNotEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on_rounded,
                  size: 13, color: SdColors.info),
              const SizedBox(width: 3),
              Flexible(
                child: Text(ftthZone,
                    style: TextStyle(
                        color: SdColors.infoEdge,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (manualLocation.isNotEmpty && manualLocation != ftthZone)
            Text(manualLocation,
                style: TextStyle(color: SdColors.faint, fontSize: 10),
                overflow: TextOverflow.ellipsis),
        ],
      );
    }

    return Text(manualLocation.isNotEmpty ? manualLocation : '-',
        style: TextStyle(color: SdColors.muted));
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  // =============== إرسال واتساب ===============

  Future<void> _sendWhatsApp(Map<String, dynamic> sub) async {
    final phone = sub['phone']?.toString() ?? '';
    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد رقم هاتف لهذا المشترك'),
          backgroundColor: SdColors.danger,
        ),
      );
      return;
    }

    final name = sub['customerName'] ?? '';
    final username = sub['iptvUsername'] ?? '';
    final password = sub['iptvPassword'] ?? '';
    final code = sub['iptvCode'] ?? '';

    final message = '''مرحباً $name

بيانات اشتراك IPTV الخاصة بك:

اسم المستخدم: $username
كلمة المرور: $password
الكود: $code

شكراً لاختياركم خدماتنا''';

    final result = await WhatsAppSenderService.sendMessage(
      phone: phone,
      message: message,
      operationType: WhatsAppOperationType.renewal,
      context: context,
      skipPermissionCheck: true,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success
            ? 'تم إرسال البيانات بنجاح'
            : result.error ?? 'فشل الإرسال'),
        backgroundColor: result.success ? SdColors.success : SdColors.danger,
      ),
    );
  }

  // =============== نسخ البيانات ===============

  void _copyData(Map<String, dynamic> sub) {
    final text = '''اسم المستخدم: ${sub['iptvUsername'] ?? '-'}
كلمة المرور: ${sub['iptvPassword'] ?? '-'}
الكود: ${sub['iptvCode'] ?? '-'}''';

    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ البيانات'),
        backgroundColor: SdColors.info,
        duration: Duration(seconds: 1),
      ),
    );
  }

  // =============== حذف ===============

  Future<void> _confirmDelete(Map<String, dynamic> sub) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('تأكيد الحذف',
              style: TextStyle(
                  color: SdColors.ink, fontWeight: FontWeight.bold)),
          content: Text(
            'هل تريد حذف المشترك "${sub['customerName']}"؟',
            style: const TextStyle(color: SdColors.muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  Text('إلغاء', style: TextStyle(color: SdColors.muted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: SdColors.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    final id = sub['id'];
    if (id == null) return;

    final success = await IptvService.delete(
        id is int ? id : int.tryParse(id.toString()) ?? 0);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('تم الحذف بنجاح'), backgroundColor: SdColors.success),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل الحذف'), backgroundColor: SdColors.danger),
      );
    }
  }

  // =============== إضافة / تعديل ===============

  Future<void> _showAddEditDialog({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;

    final nameCtrl =
        TextEditingController(text: existing?['customerName'] ?? '');
    final phoneCtrl = TextEditingController(text: existing?['phone'] ?? '');
    final usernameCtrl =
        TextEditingController(text: existing?['iptvUsername'] ?? '');
    final passwordCtrl =
        TextEditingController(text: existing?['iptvPassword'] ?? '');
    final codeCtrl = TextEditingController(text: existing?['iptvCode'] ?? '');
    final durationCtrl = TextEditingController(
        text: (existing?['durationMonths'] ?? 1).toString());
    final locationCtrl =
        TextEditingController(text: existing?['location'] ?? '');
    final notesCtrl = TextEditingController(text: existing?['notes'] ?? '');

    bool isActive = existing?['isActive'] ?? true;
    DateTime? activationDate;
    if (existing?['activationDate'] != null) {
      activationDate =
          DateTime.tryParse(existing!['activationDate'].toString());
    }
    String? linkedSubscriptionId = existing?['subscriptionId'];

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              isEdit ? 'تعديل مشترك IPTV' : 'إضافة مشترك IPTV',
              style: const TextStyle(
                  color: SdColors.ink, fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: min(500, MediaQuery.of(context).size.width * 0.85),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ربط بمشترك FTTH
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: SdColors.platformBase.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: SdColors.platformBase.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.link_rounded,
                              color: SdColors.platformLight, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              linkedSubscriptionId != null
                                  ? 'مرتبط بمشترك FTTH: $linkedSubscriptionId'
                                  : 'غير مرتبط بمشترك FTTH',
                              style: TextStyle(
                                color: linkedSubscriptionId != null
                                    ? SdColors.platformBase
                                    : SdColors.faint,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final selected = await _selectFtthSubscriber(ctx);
                              if (selected != null) {
                                setDialogState(() {
                                  linkedSubscriptionId =
                                      selected['subscription_id']?.toString();
                                  if (nameCtrl.text.isEmpty) {
                                    nameCtrl.text =
                                        selected['display_name'] ?? '';
                                  }
                                  if (phoneCtrl.text.isEmpty) {
                                    phoneCtrl.text = selected['phone'] ?? '';
                                  }
                                });
                              }
                            },
                            child: Text(
                              linkedSubscriptionId != null ? 'تغيير' : 'ربط',
                              style: const TextStyle(
                                  color: SdColors.platformBase, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // الحقول
                    _buildTextField(nameCtrl, 'اسم العميل', Icons.person),
                    const SizedBox(height: 10),
                    _buildTextField(phoneCtrl, 'رقم الهاتف', Icons.phone),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                            child: _buildTextField(usernameCtrl, 'يوزر IPTV',
                                Icons.account_circle)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _buildTextField(
                                passwordCtrl, 'باسوورد', Icons.lock)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                            child: _buildTextField(
                                codeCtrl, 'الكود', Icons.qr_code)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _buildTextField(
                                durationCtrl, 'المدة (أشهر)', Icons.timer,
                                isNumber: true)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildTextField(locationCtrl, 'الموقع', Icons.location_on),
                    const SizedBox(height: 10),
                    _buildTextField(notesCtrl, 'ملاحظات', Icons.notes),
                    const SizedBox(height: 12),

                    // تاريخ التفعيل + الحالة
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: activationDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) {
                                setDialogState(() => activationDate = picked);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 14),
                              decoration: BoxDecoration(
                                color: SdColors.surfaceAlt,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: SdColors.divider),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today_rounded,
                                      color: SdColors.faint, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    activationDate != null
                                        ? DateFormat('yyyy-MM-dd')
                                            .format(activationDate!)
                                        : 'تاريخ التفعيل',
                                    style: TextStyle(
                                      color: activationDate != null
                                          ? SdColors.ink
                                          : SdColors.faint,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Row(
                          children: [
                            Text('فعال',
                                style: TextStyle(
                                    color: SdColors.muted, fontSize: 13)),
                            Switch(
                              value: isActive,
                              activeColor: SdColors.success,
                              onChanged: (v) =>
                                  setDialogState(() => isActive = v),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('إلغاء',
                    style: TextStyle(color: SdColors.muted)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.platformBase,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(isEdit ? 'تحديث' : 'إضافة'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result != true || !mounted) return;
    if (nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('اسم العميل مطلوب'), backgroundColor: SdColors.warning),
      );
      return;
    }

    if (isEdit) {
      final id = existing['id'];
      final success = await IptvService.update(
        id: id is int ? id : int.tryParse(id.toString()) ?? 0,
        subscriptionId: linkedSubscriptionId,
        customerName: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        iptvUsername: usernameCtrl.text.trim(),
        iptvPassword: passwordCtrl.text.trim(),
        iptvCode: codeCtrl.text.trim(),
        activationDate: activationDate,
        durationMonths: int.tryParse(durationCtrl.text) ?? 1,
        isActive: isActive,
        location: locationCtrl.text.trim(),
        notes: notesCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'تم التعديل بنجاح' : 'فشل التعديل'),
          backgroundColor: success ? SdColors.success : SdColors.danger,
        ),
      );
    } else {
      if (_companyId == null || _companyId!.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('خطأ: لم يتم تحديد معرف الشركة'),
              backgroundColor: SdColors.danger),
        );
        return;
      }
      Map<String, dynamic>? created;
      String? createError;
      try {
        created = await IptvService.create(
          companyId: _companyId!,
          subscriptionId: linkedSubscriptionId,
          customerName: nameCtrl.text.trim(),
          phone: phoneCtrl.text.trim(),
          iptvUsername: usernameCtrl.text.trim(),
          iptvPassword: passwordCtrl.text.trim(),
          iptvCode: codeCtrl.text.trim(),
          activationDate: activationDate,
          durationMonths: int.tryParse(durationCtrl.text) ?? 1,
          isActive: isActive,
          location: locationCtrl.text.trim(),
          notes: notesCtrl.text.trim(),
        );
      } catch (e) {
        createError = e.toString();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(created != null
              ? 'تم الإضافة بنجاح'
              : 'فشل الإضافة${createError != null ? ': $createError' : ''}'),
          backgroundColor: created != null ? SdColors.success : SdColors.danger,
        ),
      );
    }

    _loadData();
  }

  Widget _buildTextField(
      TextEditingController ctrl, String label, IconData icon,
      {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: SdColors.ink, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: SdColors.faint, fontSize: 13),
        prefixIcon: Icon(icon, color: SdColors.faint, size: 18),
        filled: true,
        fillColor: SdColors.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: SdColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: SdColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SdColors.platformBase, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        isDense: true,
      ),
    );
  }

  // =============== اختيار مشترك FTTH ===============

  Future<Map<String, dynamic>?> _selectFtthSubscriber(BuildContext ctx) async {
    final allSubs = await LocalDatabaseService.instance.getAllSubscribers();
    if (allSubs.isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد بيانات محلية - قم بالمزامنة أولاً'),
          backgroundColor: SdColors.warning,
        ),
      );
      return null;
    }

    String searchText = '';
    List<Map<String, dynamic>> filteredSubs = allSubs;

    return showDialog<Map<String, dynamic>>(
      context: ctx,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('اختيار مشترك FTTH',
                style: TextStyle(
                    color: SdColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: min(400, MediaQuery.of(context).size.width * 0.85),
              height: min(400, MediaQuery.of(context).size.height * 0.6),
              child: Column(
                children: [
                  TextField(
                    style:
                        const TextStyle(color: SdColors.ink, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'بحث...',
                      hintStyle: TextStyle(color: SdColors.faint),
                      prefixIcon: Icon(Icons.search_rounded,
                          color: SdColors.faint, size: 18),
                      filled: true,
                      fillColor: SdColors.surfaceAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      setDlgState(() {
                        searchText = v.toLowerCase();
                        filteredSubs = allSubs.where((s) {
                          final name = (s['display_name'] ?? '')
                              .toString()
                              .toLowerCase();
                          final phone =
                              (s['phone'] ?? '').toString().toLowerCase();
                          return name.contains(searchText) ||
                              phone.contains(searchText);
                        }).toList();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount:
                          filteredSubs.length > 50 ? 50 : filteredSubs.length,
                      itemBuilder: (_, i) {
                        final s = filteredSubs[i];
                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          title: Text(s['display_name'] ?? '',
                              style: const TextStyle(
                                  color: SdColors.ink, fontSize: 13)),
                          subtitle: Text(
                            '${s['phone'] ?? '-'} | ${s['zone_name'] ?? ''}',
                            style: TextStyle(
                                color: SdColors.faint, fontSize: 11),
                          ),
                          onTap: () => Navigator.pop(dlgCtx, s),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: Text('إلغاء',
                    style: TextStyle(color: SdColors.muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
