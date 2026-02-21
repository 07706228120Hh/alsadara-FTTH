import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show NumberFormat;
import '../../services/accounting_service.dart';
import '../../services/auth_service.dart';

/// صفحة ربط مشغلي FTTH بمستخدمي خادمنا
/// تعرض المشغلين من FTTH (كما في زر الفريق) وتسمح بربط كل مشغل بموظف من نظامنا
class FtthOperatorLinkingPage extends StatefulWidget {
  final String? companyId;
  const FtthOperatorLinkingPage({super.key, this.companyId});

  @override
  State<FtthOperatorLinkingPage> createState() =>
      _FtthOperatorLinkingPageState();
}

class _FtthOperatorLinkingPageState extends State<FtthOperatorLinkingPage> {
  final _currencyFormat = NumberFormat('#,##0', 'en_US');
  bool _isLoading = true;
  String? _error;

  // مشغلو FTTH (من admin.ftth.iq)
  List<Map<String, dynamic>> _ftthOperators = [];
  int _totalCount = 0;
  String _filterRole = 'الكل';

  // موظفونا (من خادمنا)
  List<Map<String, dynamic>> _ourUsers = [];
  bool _loadingOurUsers = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // جلب المشغلين من FTTH + موظفينا بالتوازي
    await Future.wait([
      _loadFtthOperators(),
      _loadOurUsers(),
    ]);

    if (mounted) setState(() => _isLoading = false);
  }

  /// جلب مشغلي FTTH (نفس API صفحة الفريق)
  Future<void> _loadFtthOperators() async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
          'GET', 'https://admin.ftth.iq/api/teams/members');
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _ftthOperators = List<Map<String, dynamic>>.from(data['items'] ?? []);
        _totalCount = data['totalCount'] ?? _ftthOperators.length;
      } else {
        _error = 'خطأ في جلب المشغلين: ${response.statusCode}';
      }
    } catch (e) {
      _error = 'خطأ: $e';
    }
  }

  /// جلب موظفينا مع حالة الربط
  Future<void> _loadOurUsers() async {
    setState(() => _loadingOurUsers = true);
    try {
      final result = await AccountingService.instance
          .getOperatorsLinking(companyId: widget.companyId);
      if (result['success'] == true) {
        final data = result['data'];
        List items;
        if (data is List) {
          items = data;
        } else if (data is Map && data['data'] is List) {
          items = data['data'];
        } else {
          items = [];
        }
        _ourUsers = items
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingOurUsers = false);
  }

  /// البحث عن الموظف المربوط بمشغل FTTH
  Map<String, dynamic>? _findLinkedUser(String ftthUsername) {
    if (ftthUsername.isEmpty) return null;
    final lower = ftthUsername.toLowerCase();
    for (final u in _ourUsers) {
      final linked = u['FtthUsername']?.toString().toLowerCase() ?? '';
      if (linked == lower) return u;
    }
    return null;
  }

  /// ربط مشغل FTTH بموظف
  Future<void> _linkOperator(Map<String, dynamic> ftthOp) async {
    final ftthUsername = ftthOp['username']?.toString() ?? '';
    final firstName = ftthOp['firstName']?.toString() ?? '';
    final lastName = ftthOp['lastName']?.toString() ?? '';
    final opName = '$firstName $lastName'.trim();

    // الموظف المربوط حالياً
    final currentLinked = _findLinkedUser(ftthUsername);

    // الموظفون غير المربوطين بأي مشغل + الموظف المربوط الحالي
    final availableUsers = _ourUsers.where((u) {
      final uFtth = u['FtthUsername']?.toString().toLowerCase() ?? '';
      return uFtth.isEmpty || uFtth == ftthUsername.toLowerCase();
    }).toList();

    String? selectedUserId = currentLinked?['Id']?.toString();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.link, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ربط المشغل: ${opName.isNotEmpty ? opName : ftthUsername}',
                  style: GoogleFonts.cairo(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // معلومات المشغل
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person, color: Colors.teal.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('اسم المستخدم في FTTH: $ftthUsername',
                                style: GoogleFonts.cairo(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                            if (opName.isNotEmpty)
                              Text('الاسم: $opName',
                                  style: GoogleFonts.cairo(
                                      fontSize: 12,
                                      color: Colors.grey.shade700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('اختر الموظف من نظامنا لربطه بهذا المشغل:',
                    style: GoogleFonts.cairo(fontSize: 13)),
                const SizedBox(height: 8),
                // قائمة الموظفين
                if (availableUsers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('لا يوجد موظفون متاحون للربط',
                        style: TextStyle(color: Colors.grey)),
                  )
                else
                  Container(
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      itemCount: availableUsers.length,
                      itemBuilder: (_, i) {
                        final u = availableUsers[i];
                        final userId = u['Id']?.toString() ?? '';
                        final isSelected = userId == selectedUserId;
                        final fullName = u['FullName']?.toString() ?? '-';
                        final username = u['Username']?.toString() ?? '-';
                        final phone = u['PhoneNumber']?.toString() ?? '';

                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor: Colors.teal.shade50,
                          leading: Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 18,
                            color: isSelected ? Colors.teal : Colors.grey,
                          ),
                          title: Text(fullName,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500)),
                          subtitle: Text(
                              '$username${phone.isNotEmpty ? ' • $phone' : ''}',
                              style: const TextStyle(fontSize: 11)),
                          onTap: () =>
                              setDialogState(() => selectedUserId = userId),
                        );
                      },
                    ),
                  ),
                if (_loadingOurUsers)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            if (currentLinked != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, '__UNLINK__'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('إزالة الربط'),
              ),
            ElevatedButton(
              onPressed: selectedUserId == null || selectedUserId!.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, selectedUserId),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal, foregroundColor: Colors.white),
              child: const Text('ربط'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    setState(() => _isLoading = true);
    try {
      if (result == '__UNLINK__' && currentLinked != null) {
        // إزالة الربط
        await AccountingService.instance.linkFtthAccount(
          userId: currentLinked['Id'].toString(),
          ftthUsername: '',
        );
      } else {
        // ربط جديد
        await AccountingService.instance.linkFtthAccount(
          userId: result,
          ftthUsername: ftthUsername,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result == '__UNLINK__'
                  ? 'تم إزالة ربط $ftthUsername'
                  : 'تم ربط $ftthUsername بنجاح',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredOperators {
    if (_filterRole == 'الكل') return _ftthOperators;
    return _ftthOperators.where((m) {
      final role = (m['role'] as Map?)?['displayValue']?.toString() ?? '';
      return role == _filterRole;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // حساب الملخصات
    int linkedCount = 0;
    int unlinkedCount = 0;
    double totalBalance = 0;
    final roleCounts = <String, int>{};

    for (final m in _ftthOperators) {
      final username = m['username']?.toString() ?? '';
      if (_findLinkedUser(username) != null) {
        linkedCount++;
      } else {
        unlinkedCount++;
      }
      final wallet = m['walletSetup'] as Map<String, dynamic>?;
      if (wallet != null) {
        totalBalance += (wallet['balance'] as num?)?.toDouble() ?? 0;
      }
      final role =
          (m['role'] as Map?)?['displayValue']?.toString() ?? 'غير محدد';
      roleCounts[role] = (roleCounts[role] ?? 0) + 1;
    }

    final filtered = _filteredOperators;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text('ربط المشغلين ($_totalCount مشغل)',
              style:
                  GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700)),
          backgroundColor: Colors.teal.shade700,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: Colors.red.shade400),
                        const SizedBox(height: 8),
                        Text(_error!,
                            style: TextStyle(color: Colors.red.shade700)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _loadData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // بطاقات الملخص
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            _summaryCard('إجمالي المشغلين', '$_totalCount',
                                Icons.people, Colors.teal),
                            const SizedBox(width: 8),
                            _summaryCard('مربوطون', '$linkedCount', Icons.link,
                                Colors.green),
                            const SizedBox(width: 8),
                            _summaryCard('غير مربوطين', '$unlinkedCount',
                                Icons.link_off, Colors.orange),
                            const SizedBox(width: 8),
                            _summaryCard(
                                'إجمالي الأرصدة',
                                _currencyFormat.format(totalBalance),
                                Icons.monetization_on,
                                totalBalance >= 0 ? Colors.blue : Colors.red),
                          ],
                        ),
                      ),
                      // فلتر الأدوار
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _roleChip('الكل', _ftthOperators.length),
                              ...roleCounts.entries
                                  .map((e) => _roleChip(e.key, e.value)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // الجدول
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: SingleChildScrollView(
                            child: SizedBox(
                              width: double.infinity,
                              child: _buildTable(filtered),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _roleChip(String label, int count) {
    final isSelected = _filterRole == label;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: FilterChip(
        label: Text('$label ($count)',
            style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.teal.shade800)),
        selected: isSelected,
        selectedColor: Colors.teal.shade600,
        backgroundColor: Colors.teal.shade50,
        onSelected: (_) => setState(() => _filterRole = label),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(value,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: color)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> list) {
    if (list.isEmpty) return const Center(child: Text('لا توجد بيانات'));

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DataTable(
        columnSpacing: 0,
        horizontalMargin: 8,
        headingRowHeight: 42,
        dataRowMinHeight: 38,
        dataRowMaxHeight: 54,
        headingRowColor: WidgetStateProperty.all(Colors.teal.shade50),
        columns: const [
          DataColumn(
              label: Expanded(
                  child: Center(
                      child: Text('#',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold))))),
          DataColumn(
              label: Expanded(
                  child: Center(
                      child: Text('المستخدم',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold))))),
          DataColumn(
              label: Expanded(
                  child: Center(
                      child: Text('الاسم',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold))))),
          DataColumn(
              label: Expanded(
                  child: Center(
                      child: Text('الهاتف',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold))))),
          DataColumn(
              label: Expanded(
                  child: Center(
                      child: Text('الدور',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold))))),
          DataColumn(
              label: Expanded(
                  child: Center(
                      child: Text('الرصيد',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold))))),
          DataColumn(
              label: Expanded(
                  child: Center(
                      child: Text('الموظف المربوط',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold))))),
          DataColumn(
              label: Expanded(
                  child: Center(
                      child: Text('الحالة',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold))))),
          DataColumn(
              label: Expanded(
                  child: Center(
                      child: Text('إجراء',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold))))),
        ],
        rows: list.asMap().entries.map((entry) {
          final i = entry.key;
          final m = entry.value;
          final role = (m['role'] as Map?)?['displayValue']?.toString() ?? '-';
          final firstName = m['firstName']?.toString() ?? '';
          final lastName = m['lastName']?.toString() ?? '';
          final fullName = '$firstName $lastName'.trim();
          final phone = m['phoneNumber']?.toString() ?? '-';
          final username = m['username']?.toString() ?? '-';
          final wallet = m['walletSetup'] as Map<String, dynamic>?;
          final balance = (wallet?['balance'] as num?)?.toDouble() ?? 0;

          // البحث عن الموظف المربوط
          final linkedUser = _findLinkedUser(username);
          final hasLink = linkedUser != null;
          final linkedName = linkedUser?['FullName']?.toString() ?? '-';

          Color roleColor;
          switch (role) {
            case 'Super Admin Member':
              roleColor = Colors.red.shade700;
              break;
            case 'Zone Admin':
              roleColor = Colors.blue.shade700;
              break;
            case 'Field Worker':
              roleColor = Colors.green.shade700;
              break;
            case 'Contractor':
              roleColor = Colors.purple.shade700;
              break;
            default:
              roleColor = Colors.grey.shade700;
          }

          return DataRow(
            color: WidgetStateProperty.resolveWith((states) {
              if (hasLink) return Colors.green.shade50;
              return null;
            }),
            cells: [
              DataCell(Center(
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)))),
              DataCell(Center(
                  child: Text(username,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)))),
              DataCell(Center(
                  child: Text(fullName.isNotEmpty ? fullName : '-',
                      style: const TextStyle(fontSize: 12)))),
              DataCell(Center(
                  child: Text(phone, style: const TextStyle(fontSize: 12)))),
              DataCell(Center(
                  child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(role,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: roleColor)),
              ))),
              DataCell(Center(
                  child: Text(
                _currencyFormat.format(balance),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: balance > 0
                        ? Colors.green.shade700
                        : balance < 0
                            ? Colors.red.shade700
                            : Colors.grey.shade400),
              ))),
              // الموظف المربوط
              DataCell(Center(
                  child: Text(
                hasLink ? linkedName : '-',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: hasLink ? FontWeight.w700 : FontWeight.w400,
                  color: hasLink ? Colors.teal.shade700 : Colors.grey,
                ),
              ))),
              // حالة الربط
              DataCell(Center(
                  child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      hasLink ? Colors.green.shade100 : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  hasLink ? 'مربوط' : 'غير مربوط',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: hasLink
                        ? Colors.green.shade800
                        : Colors.orange.shade800,
                  ),
                ),
              ))),
              // إجراء
              DataCell(Center(
                  child: ElevatedButton.icon(
                onPressed: () => _linkOperator(m),
                icon: Icon(hasLink ? Icons.edit : Icons.link, size: 14),
                label: Text(hasLink ? 'تعديل' : 'ربط',
                    style: const TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      hasLink ? Colors.blue.shade600 : Colors.teal.shade600,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                ),
              ))),
            ],
          );
        }).toList(),
      ),
    );
  }
}
