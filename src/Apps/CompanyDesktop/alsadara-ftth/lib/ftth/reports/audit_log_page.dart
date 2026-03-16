/// اسم الصفحة: سجل التدقيق
/// وصف الصفحة: صفحة سجل التدقيق والعمليات
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../auth/auth_error_handler.dart';

// صفحة سجل التدقيق لعرض (الأنواع، الملخص، السجلات) مع ترشيح و ترقيم صفحات
class AuditLogPage extends StatefulWidget {
  final String authToken;
  final String customerId;
  final String customerName;
  // تمرير قيم هيدر اختيارية إن توفرت من السياق الأعلى
  final String? userRoleHeader; // مثال: '0'
  final String? clientAppHeader; // مثال: '53d57a7f-...'
  const AuditLogPage(
      {super.key,
      required this.authToken,
      required this.customerId,
      required this.customerName,
      this.userRoleHeader,
      this.clientAppHeader});
  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  // الحالة العامة
  bool _initialLoading =
      true; // التحميل الأولي (الأنواع + الملخص + الصفحة الأولى)
  bool _pageLoading = false; // تحميل صفحة إضافية
  bool _refreshing = false; // عند التحديث الكامل
  String _error = '';

  // البيانات (تم حذف الحقول المتعلقة بالترشيح)
  double? _totalAmount; // الملخص (إجمالي المبالغ)
  int _pageNumber = 1;
  final int _pageSize = 10;
  bool _hasMore = true;
  final List<Map<String, dynamic>> _items = [];
  final ScrollController _scrollController = ScrollController();
  bool _showToTop = false; // زر الرجوع للأعلى
  final Set<String> _expandedIds = {}; // العناصر المفتوحة للتفاصيل السريعة

  // ترتيب افتراضي حسب تاريخ الإنشاء تنازلي
  final String _sortProperty = 'CreatedAt';
  final String _sortDir = 'desc';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final shouldShow = _scrollController.offset > 420;
    if (shouldShow != _showToTop && mounted) {
      setState(() => _showToTop = shouldShow);
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _error = '';
      _items.clear();
      _pageNumber = 1;
      _hasMore = true;
    });
    try {
      await Future.wait([
        _fetchSummary(),
        _fetchPage(reset: true),
      ]);
    } catch (e) {
      _error = 'خطأ أثناء التحميل';
    } finally {
      if (mounted) setState(() => _initialLoading = false);
    }
  }

  // أزيلت _fetchEventTypes لعدم الحاجة للفلاتر

  Future<void> _fetchSummary() async {
    try {
      final url =
          'https://admin.ftth.iq/api/audit-logs/summary?customerId=${widget.customerId}';
      final r = await AuthService.instance.authenticatedRequest('GET', url, headers: _headers());
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final model = (data is Map) ? data['model'] : null;
        if (model is Map && model['totalAmount'] != null) {
          _totalAmount = double.tryParse(model['totalAmount'].toString());
        }
      } else if (r.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      }
    } catch (_) {}
  }

  Future<void> _fetchPage({bool reset = false}) async {
    if (_pageLoading) return; // منع طلبات متكررة
    if (!_hasMore && !reset) return;
    setState(() => _pageLoading = true);
    try {
      if (reset) {
        _items.clear();
        _pageNumber = 1;
        _hasMore = true;
      }
      final query = {
        'pageSize': _pageSize.toString(),
        'pageNumber': _pageNumber.toString(),
        'sortCriteria.property': _sortProperty,
        'sortCriteria.direction': _sortDir,
        'customerId': widget.customerId,
      };
      final url = Uri.https('admin.ftth.iq', '/api/audit-logs', query).toString();
      final r = await AuthService.instance.authenticatedRequest('GET', url, headers: _headers());
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final totalCount = (data is Map && data['totalCount'] != null)
            ? int.tryParse(data['totalCount'].toString())
            : null;
        final items = (data is Map ? data['items'] : null) as List?;
        if (items != null) {
          final newOnes = items
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList();
          _items.addAll(newOnes);
          // تحديد ما إذا بقي المزيد
          if (totalCount != null) {
            _hasMore = _items.length < totalCount;
          } else {
            // تقدير: إذا أقل من pageSize نفترض لا مزيد
            _hasMore = newOnes.length == _pageSize;
          }
          if (_hasMore) _pageNumber += 1;
        } else {
          _hasMore = false;
        }
      } else if (r.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      } else if (r.statusCode == 403) {
        _error =
            'ممنوع (403): لا تملك صلاحية عرض سجل التدقيق. تأكد من إرسال الرؤوس المطلوبة (x-user-role / x-client-app) والصلاحيات.';
      } else {
        _error = 'فشل تحميل الصفحة (${r.statusCode})';
      }
    } catch (e) {
      _error = 'خطأ';
    } finally {
      if (mounted) setState(() => _pageLoading = false);
    }
  }

  Map<String, String> _headers() {
    return {
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'ar',
      'x-user-role': widget.userRoleHeader ?? '0',
      'x-client-app': widget.clientAppHeader ?? '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
    };
  }

  Future<void> _onRefresh() async {
    setState(() => _refreshing = true);
    try {
      await _fetchSummary();
      await _fetchPage(reset: true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // تم حذف _applyFilter

  String _fmtDateTime(String? d) {
    if (d == null || d.isEmpty) return 'غير معروف';
    try {
      final dt = DateTime.parse(d);
      final date =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$date $hh:$mm';
    } catch (_) {
      return d;
    }
  }

  Color _eventColor(String type) {
    if (type.contains('Extend')) return Colors.green.shade700;
    // لون أخضر مميز لحدث Change حسب طلب المستخدم
    if (type.contains('Change')) return Colors.green.shade900;
    if (type.contains('Suspend')) return Colors.red.shade800;
    if (type.contains('Renew')) return Colors.blue.shade800;
    return Colors.blueGrey.shade700;
  }

  // تحويل اسم الحدث (بالإنجليزية) إلى عنوان عربي مناسب للعرض
  String _arabicEventTitle(String raw) {
    final t = raw.toLowerCase();
    String base;
    if (t.contains('extend')) {
      base = 'تمديد';
    } else if (t.contains('change'))
      base = 'تغيير';
    else if (t.contains('suspend'))
      base = 'إيقاف';
    else if (t.contains('renew'))
      base = 'تجديد';
    else if (t.contains('activate'))
      base = 'تفعيل';
    else if (t.contains('deactivate'))
      base = 'تعطيل';
    else if (t.contains('create'))
      base = 'إنشاء';
    else if (t.contains('update'))
      base = 'تحديث';
    else if (t.contains('delete') || t.contains('remove'))
      base = 'حذف';
    else if (t.contains('login'))
      base = 'تسجيل دخول';
    else if (t.contains('logout'))
      base = 'تسجيل خروج';
    else if (t.contains('payment') || t.contains('pay'))
      base = 'دفع';
    else if (t.contains('refund'))
      base = 'استرجاع';
    else if (t.contains('assign'))
      base = 'تعيين';
    else if (t.contains('unassign'))
      base = 'إزالة تعيين';
    else if (t.contains('reset'))
      base = 'إعادة تعيين';
    else if (t.contains('verify'))
      base = 'تحقق';
    else if (t.contains('approve'))
      base = 'موافقة';
    else if (t.contains('reject'))
      base = 'رفض';
    else if (t.contains('sync'))
      base = 'مزامنة';
    else if (t.contains('export'))
      base = 'تصدير';
    else if (t.contains('import'))
      base = 'استيراد';
    else
      base = raw; // إن لم يُعرف نعيده كما هو
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [
                    Colors.blue.shade800,
                    Colors.blue.shade600,
                    Colors.blue.shade400
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  stops: const [0, .55, 1])),
        ),
        title: Text('سجل التدقيق - ${widget.customerName}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              onPressed: _onRefresh,
              tooltip: 'تحديث',
              icon: _refreshing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.refresh_rounded))
        ],
      ),
      floatingActionButton: AnimatedSlide(
        duration: const Duration(milliseconds: 250),
        offset: _showToTop ? Offset.zero : const Offset(0, 2),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: _showToTop ? 1 : 0,
          child: FloatingActionButton(
            heroTag: 'toTop',
            onPressed: () {
              _scrollController.animateTo(0,
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutQuad);
            },
            backgroundColor: Colors.blue.shade700,
            child: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF0F181F), const Color(0xFF132736)]
                    : [Colors.blue.shade50, Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter)),
        child: SafeArea(
          child: _initialLoading
              ? const Center(child: CircularProgressIndicator())
              : _error.isNotEmpty
                  ? _errorView()
                  : Column(children: [
                      _summaryBar(),
                      // أخفي شريط الفلاتر (الصلاحيات) حسب الطلب
                      // _filtersChipsBar(),
                      Expanded(child: _buildList()),
                    ]),
        ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, color: Colors.red.shade400, size: 60),
            const SizedBox(height: 16),
            Text(_error,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade700)),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
                onPressed: _loadInitial,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'))
          ]),
        ),
      );

  Widget _summaryBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        elevation: 4,
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(colors: [
                Colors.blue.shade600,
                Colors.blue.shade500,
                Colors.blue.shade400
              ], begin: Alignment.topRight, end: Alignment.bottomLeft)),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.summarize, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الملخص',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                            position: anim.drive(Tween(
                                begin: const Offset(0, .2), end: Offset.zero))),
                      ),
                      child: Text(
                        _totalAmount == null
                            ? 'غير متوفر'
                            : 'إجمالي المبالغ: ${_totalAmount!.toStringAsFixed(0)}',
                        key: ValueKey(_totalAmount),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white),
                      ),
                    ),
                  ]),
            ),
            IconButton(
                tooltip: 'تحديث الملخص',
                onPressed: _refreshing
                    ? null
                    : () async {
                        setState(() => _refreshing = true);
                        await _fetchSummary();
                        if (mounted) setState(() => _refreshing = false);
                      },
                icon: _refreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh, color: Colors.white))
          ]),
        ),
      ),
    );
  }

  // أزلنا شريط الفلاتر حسب طلب المستخدم

  Widget _buildList() {
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _onRefresh,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          radius: const Radius.circular(16),
          child: ListView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 90),
              Icon(Icons.inbox_outlined, size: 72, color: Colors.blue.shade200),
              const SizedBox(height: 16),
              Center(
                  child: Text('لا توجد سجلات',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700))),
              const SizedBox(height: 8),
              Center(
                  child: Text('حاول تغيير نوع الحدث أو التحديث',
                      style: TextStyle(
                          fontSize: 12, color: Colors.blueGrey.shade600))),
              const SizedBox(height: 180),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        trackVisibility: true,
        interactive: true,
        radius: const Radius.circular(16),
        child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            itemCount: _items.length + 1,
            itemBuilder: (ctx, i) {
              if (i == _items.length) {
                if (_hasMore) {
                  // جدولة جلب الصفحة التالية بعد انتهاء البناء الحالي لتفادي setState أثناء البناء
                  if (!_pageLoading) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_pageLoading && _hasMore) {
                        _fetchPage();
                      }
                    });
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                        child: _pageLoading
                            ? const CircularProgressIndicator()
                            : const SizedBox()),
                  );
                } else {
                  return const SizedBox(height: 40);
                }
              }
              final widgetItem = _itemTile(_items[i]);
              return _AnimatedAppear(
                  index: i,
                  child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: widgetItem));
            }),
      ),
    );
  }

  Widget _itemTile(Map<String, dynamic> m) {
    final type = (m['eventType'] ?? '').toString();
    final typeAr = _arabicEventTitle(type);
    final id = (m['id'] ?? '').toString();
    final amount = m['amount']?.toString();
    final isMonetary = m['isMonetary'] == true;
    final success = m['isSuccessful'] == true;
    final actor = (m['actor'] is Map) ? m['actor'] as Map : null;
    final username = actor == null ? '' : (actor['username'] ?? '').toString();
    final ip = actor == null ? '' : (actor['ipAddress'] ?? '').toString();
    final createdAt = _fmtDateTime((m['createdAt'] ?? '').toString());
    final color = _eventColor(type);
    final walletOwnerType = (m['walletOwnerType'] is Map)
        ? m['walletOwnerType']['displayValue']?.toString()
        : null;
    final accountType = (actor != null && actor['accountType'] is Map)
        ? actor['accountType']['displayValue']?.toString()
        : null;
    final expanded = _expandedIds.contains(id);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgTint = isDark ? color.withValues(alpha: .20) : color.withValues(alpha: .09);
    final borderClr = isDark ? color.withValues(alpha: .35) : color.withValues(alpha: .22);
    final shadowClr =
        isDark ? Colors.black.withValues(alpha: .35) : color.withValues(alpha: .18);

    return InkWell(
      onTap: () => _toggleExpand(id),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        child: Stack(children: [
          Positioned.fill(
              child: Row(children: [
            Container(
                width: 5,
                decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(18), right: Radius.circular(4)))),
            Expanded(
                child: Container(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: bgTint,
                  border: Border.all(color: borderClr, width: 1.1),
                  boxShadow: [
                    BoxShadow(
                        color: shadowClr,
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ]),
            ))
          ])),
          // المحتوى
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.history_rounded, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(typeAr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                letterSpacing: .3,
                                color: color)),
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(Icons.access_time,
                              size: 12, color: color.withValues(alpha: .7)),
                          const SizedBox(width: 4),
                          Text(createdAt,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: color.withValues(alpha: .7),
                                  fontWeight: FontWeight.w500)),
                        ])
                      ])),
                  const SizedBox(width: 8),
                  Column(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: success
                              ? Colors.green.shade600
                              : Colors.red.shade600,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: (success ? Colors.green : Colors.red)
                                    .withValues(alpha: .25),
                                blurRadius: 8,
                                offset: const Offset(0, 3))
                          ]),
                      child: Row(children: [
                        Icon(success ? Icons.check_circle : Icons.error_outline,
                            color: Colors.white, size: 17),
                        const SizedBox(width: 4),
                        Text(success ? 'ناجح' : 'فشل',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700))
                      ]),
                    ),
                    IconButton(
                        tooltip: expanded ? 'إخفاء التفاصيل' : 'إظهار التفاصيل',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _toggleExpand(id),
                        icon: AnimatedRotation(
                          turns: expanded ? .5 : 0,
                          duration: const Duration(milliseconds: 300),
                          child: Icon(Icons.keyboard_arrow_down_rounded,
                              color: color),
                        ))
                  ])
                ]),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _infoBadge('المستخدم', username.isEmpty ? '—' : username,
                      Icons.person, _badgeColor('المستخدم', color)),
                  _infoBadge('التاريخ', createdAt, Icons.access_time,
                      _badgeColor('التاريخ', color)),
                  _infoBadge(
                      'المبلغ',
                      (isMonetary && amount != null && amount.isNotEmpty)
                          ? amount
                          : '—',
                      Icons.attach_money,
                      _badgeColor('المبلغ', color)),
                  _infoBadge(
                      'نوع الحساب',
                      (accountType == null || accountType.isEmpty)
                          ? '—'
                          : accountType,
                      Icons.badge_outlined,
                      _badgeColor('نوع الحساب', color)),
                  _infoBadge(
                      'نوع مالك المحفظة',
                      (walletOwnerType == null || walletOwnerType.isEmpty)
                          ? '—'
                          : walletOwnerType,
                      Icons.account_balance_wallet,
                      _badgeColor('نوع مالك المحفظة', color)),
                ]),
                const SizedBox(height: 10),
                AnimatedCrossFade(
                  firstChild: Row(children: [
                    Icon(Icons.touch_app_outlined,
                        size: 14, color: color.withValues(alpha: .65)),
                    const SizedBox(width: 6),
                    Text('انقر لعرض تفاصيل سريعة',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: color.withValues(alpha: .65)))
                  ]),
                  secondChild: _inlineDetails(m, color, id, amount, isMonetary,
                      walletOwnerType, accountType, username, ip),
                  crossFadeState: expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 350),
                  sizeCurve: Curves.easeOutCubic,
                )
              ],
            ),
          )
        ]),
      ),
    );
  }

  void _toggleExpand(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  Color _badgeColor(String label, Color fallback) {
    switch (label) {
      case 'المستخدم':
        return Colors.deepPurple.shade600;
      case 'التاريخ':
        return Colors.blue.shade600;
      case 'المبلغ':
        return Colors.green.shade700;
      case 'نوع الحساب':
        return Colors.teal.shade700;
      case 'نوع مالك المحفظة':
        return Colors.indigo.shade600;
      default:
        return fallback;
    }
  }

  Widget _inlineDetails(
      Map<String, dynamic> m,
      Color color,
      String id,
      String? amount,
      bool isMonetary,
      String? walletOwnerType,
      String? accountType,
      String username,
      String ip) {
    final createdAt = _fmtDateTime((m['createdAt'] ?? '').toString());
    final customerName = (m['customer'] is Map)
        ? m['customer']['displayValue']?.toString()
        : null;
    final zone =
        (m['zone'] is Map) ? m['zone']['displayValue']?.toString() : null;
    Widget row(String label, String value, IconData icon) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 16, color: color.withValues(alpha: .8)),
            const SizedBox(width: 6),
            Expanded(
                child: RichText(
                    text: TextSpan(
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade800,
                            height: 1.3),
                        children: [
                  TextSpan(
                      text: '$label: ',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: color.withValues(alpha: .9))),
                  TextSpan(text: value)
                ])))
          ]),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        row('المعرف', id.isEmpty ? '—' : id, Icons.confirmation_number),
        if (customerName != null && customerName.isNotEmpty)
          row('العميل', customerName, Icons.person_pin_circle),
        row('التاريخ', createdAt, Icons.access_time_filled),
        if (zone != null && zone.isNotEmpty)
          row('المنطقة/المنفذ', zone, Icons.router_outlined),
        if (isMonetary && amount != null)
          row('المبلغ', amount, Icons.attach_money),
        if (walletOwnerType != null && walletOwnerType.isNotEmpty)
          row('نوع مالك المحفظة', walletOwnerType,
              Icons.account_balance_wallet),
        if (accountType != null && accountType.isNotEmpty)
          row('نوع الحساب', accountType, Icons.badge_outlined),
        if (username.isNotEmpty) row('المستخدم', username, Icons.person),
        if (ip.isNotEmpty) row('IP', ip, Icons.public),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => _showDetails(m),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('تفاصيل كاملة'),
            style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                foregroundColor: color.darken()),
          ),
        )
      ]),
    );
  }

  // _chip حذفت لاستخدام تصميم جديد _infoBadge

  Widget _infoBadge(
          String label, String value, IconData icon, Color baseColor) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black87, width: 1),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .08),
                  blurRadius: 6,
                  offset: const Offset(0, 3))
            ]),
        constraints: const BoxConstraints(minWidth: 110, maxWidth: 200),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 32,
                margin: const EdgeInsetsDirectional.only(end: 8, top: 2),
                decoration: BoxDecoration(
                    color: baseColor, borderRadius: BorderRadius.circular(4)),
              ),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Icon(icon, size: 14, color: baseColor),
                        const SizedBox(width: 4),
                        Expanded(
                            child: Text(label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    height: 1,
                                    letterSpacing: .3,
                                    color: Colors.black.withValues(alpha: .85),
                                    fontWeight: FontWeight.w700))),
                      ]),
                      const SizedBox(height: 4),
                      Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade900,
                              fontWeight: FontWeight.w600))
                    ]),
              )
            ]),
      );

  // عرض التفاصيل الموسعة في BottomSheet
  void _showDetails(Map<String, dynamic> m) {
    final actor = (m['actor'] is Map) ? m['actor'] as Map : null;
    final walletOwnerType = (m['walletOwnerType'] is Map)
        ? m['walletOwnerType']['displayValue']?.toString()
        : null;
    final accountType = (actor != null && actor['accountType'] is Map)
        ? actor['accountType']['displayValue']?.toString()
        : null;
    final customerName = (m['customer'] is Map)
        ? m['customer']['displayValue']?.toString()
        : null;
    final zone =
        (m['zone'] is Map) ? m['zone']['displayValue']?.toString() : null;
    final createdAt = _fmtDateTime((m['createdAt'] ?? '').toString());
    final jsonPretty = const JsonEncoder.withIndent('  ').convert(m);
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) {
          return DraggableScrollableSheet(
              expand: false,
              maxChildSize: 0.95,
              initialChildSize: 0.85,
              builder: (c, scrollController) {
                return Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24))),
                    child: Row(children: [
                      const Icon(Icons.info, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                        _arabicEventTitle((m['eventType'] ?? 'حدث').toString()),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      )),
                      IconButton(
                          tooltip: 'نسخ JSON',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: jsonPretty));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('تم النسخ'),
                                    duration: Duration(seconds: 2)));
                          },
                          icon:
                              const Icon(Icons.copy_all, color: Colors.white)),
                      IconButton(
                          tooltip: 'إغلاق',
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close, color: Colors.white))
                    ]),
                  ),
                  Expanded(
                      child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailRow('المعرف', m['id']),
                          _detailRow(
                              'النوع',
                              _arabicEventTitle(
                                  (m['eventType'] ?? '').toString())),
                          _detailRow('العميل', customerName),
                          _detailRow('المبلغ', m['amount']),
                          _detailRow('نقدي؟', m['isMonetary']),
                          _detailRow('ناجح؟', m['isSuccessful']),
                          _detailRow('منطقة/منفذ', zone),
                          _detailRow('نوع مالك المحفظة', walletOwnerType),
                          _detailRow('المستخدم المنفذ', actor?['username']),
                          _detailRow('IP', actor?['ipAddress']),
                          _detailRow('نوع الحساب', accountType),
                          _detailRow('تاريخ الإنشاء', createdAt),
                          const SizedBox(height: 14),
                          Text('البيانات الخام (JSON):',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700)),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.grey.shade900,
                                borderRadius: BorderRadius.circular(12)),
                            child: SelectableText(jsonPretty,
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: Colors.white70)),
                          ),
                        ]),
                  ))
                ]);
              });
        });
  }

  Widget _detailRow(String label, dynamic value) {
    String txt;
    if (value == null || (value is String && value.isEmpty)) {
      txt = '—';
    } else if (value is bool) {
      txt = value ? 'نعم' : 'لا';
    } else {
      txt = value.toString();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300)),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700))),
        const SizedBox(width: 12),
        Expanded(
            flex: 2,
            child: Text(txt,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
    );
  }
}

// عنصر ظهور متدرج بسيط لكل عنصر قائمة
class _AnimatedAppear extends StatelessWidget {
  final Widget child;
  final int index;
  const _AnimatedAppear({required this.child, required this.index});

  @override
  Widget build(BuildContext context) {
    final delay = (index % 12) * 30; // ms
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + delay),
      curve: Curves.easeOutCubic,
      builder: (ctx, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: c),
      ),
      child: child,
    );
  }
}

extension _ColorDarkenExt on Color {
  Color darken([double amount = .12]) {
    assert(amount >= 0 && amount <= 1);
    final f = 1 - amount;
    return Color.fromARGB(
        alpha, (red * f).round(), (green * f).round(), (blue * f).round());
  }
}
