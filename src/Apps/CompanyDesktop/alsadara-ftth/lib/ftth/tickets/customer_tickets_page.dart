/// اسم الصفحة: تذاكر العملاء
/// وصف الصفحة: صفحة تذاكر الدعم الفني للعملاء
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../tickets/tktat_details_page.dart';
import '../../services/auth_service.dart';
import '../auth/auth_error_handler.dart';

/// صفحة تعرض تذاكر (مهام) الدعم الخاصة بمشترك محدد بنفس تنسيق صفحة المهام العامة (مبسطة)
class CustomerTicketsPage extends StatefulWidget {
  final String authToken;
  final String customerId;
  final String? customerName;
  const CustomerTicketsPage(
      {super.key,
      required this.authToken,
      required this.customerId,
      this.customerName});

  @override
  State<CustomerTicketsPage> createState() => _CustomerTicketsPageState();
}

class _CustomerTicketsPageState extends State<CustomerTicketsPage> {
  bool _loading = true;
  String? _error;
  List<dynamic> _tickets = [];
  String _search = '';
  int _total = 0;
  int _page = 1;
  final ScrollController _scroll = ScrollController();
  Future<void> _fetch({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _tickets = [];
      _total = 0;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final url = Uri.parse(
        'https://admin.ftth.iq/api/support/tickets?pageSize=40&pageNumber=$_page&sortCriteria.property=UpdatedAt&sortCriteria.direction=desc&customerId=${widget.customerId}');
    try {
      final r = await AuthService.instance.authenticatedRequest(
        'GET',
        url.toString(),
        headers: {'Accept': 'application/json'},
      );
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final items = (data['items'] as List?) ?? [];
        setState(() {
          _tickets = items;
          _total =
              data['totalCount'] is int ? data['totalCount'] : items.length;
          _loading = false;
        });
      } else if (r.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      } else {
        setState(() {
          _error = 'فشل الجلب: ${r.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'خطأ';
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  String _localizedStatus(String? raw) {
    if (raw == null) return 'غير معروف';
    final v = raw.toLowerCase();
    if (v.contains('open')) return 'مفتوحة';
    if (v.contains('close')) return 'مغلقة';
    if (v.contains('progress') || v.contains('processing')) {
      return 'قيد المعالجة';
    }
    if (v.contains('pending')) return 'معلقة';
    return raw;
  }

  SdStatus _statusTone(String s) {
    final l = s.toLowerCase();
    if (l.contains('مفت')) return SdStatus.warning;
    if (l.contains('مغل')) return SdStatus.success;
    if (l.contains('قيد')) return SdStatus.info;
    if (l.contains('معلق')) return SdStatus.warning;
    return SdStatus.neutral;
  }

  List<dynamic> get _filtered {
    if (_search.trim().isEmpty) return _tickets;
    final q = _search.trim();
    return _tickets.where((t) {
      if (t is! Map) return false;
      final text = [
        t['summary'],
        t['description'],
        t['self'] is Map ? t['self']['displayValue'] : null,
        t['displayId'],
        t['id'],
      ].whereType().map((e) => e.toString()).join(' ').toLowerCase();
      return text.contains(q.toLowerCase());
    }).toList();
  }

  void _openDetails(Map<String, dynamic> t) {
    Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    TKTATDetailsPage(tktat: t, authToken: widget.authToken)))
        .then((_) => _fetch());
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (widget.customerName != null) widget.customerName!,
      if (!_loading) '$_total تذكرة',
    ].join('  •  ');
    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'تذاكر المشترك',
          subtitle: subtitle.isEmpty ? null : subtitle,
          actions: [
            SdAppBarAction(
              icon: Icons.refresh,
              label: 'تحديث',
              onPressed: () => _fetch(reset: true),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildSearchBar(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() => Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SdColors.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(color: SdColors.cardEdge, offset: Offset(0, 3)),
          ],
          border: Border.all(color: SdColors.divider),
        ),
        child: Row(children: [
          const Icon(Icons.search, color: SdColors.faint, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'بحث بالملخص أو الرقم...',
                isDense: true,
                border: InputBorder.none,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          if (_search.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => setState(() => _search = ''),
            )
        ]),
      );

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _errorWidget(_error!);
    }
    if (_tickets.isEmpty) {
      return _emptyWidget();
    }
    final list = _filtered;
    return RawScrollbar(
      controller: _scroll,
      thumbVisibility: true,
      radius: const Radius.circular(10),
      thickness: 8,
      child: ListView.builder(
        controller: _scroll,
        itemCount: list.length,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        itemBuilder: (_, i) => _ticketCard(list[i]),
      ),
    );
  }

  Widget _errorWidget(String msg) => Center(
        child: SdEmptyState(
          icon: Icons.error_outline,
          status: SdStatus.danger,
          title: msg,
          action: SdButton(
            label: 'إعادة المحاولة',
            icon: Icons.refresh,
            onPressed: () => _fetch(reset: true),
          ),
        ),
      );

  Widget _emptyWidget() => const Center(
        child: SdEmptyState(
          icon: Icons.support_agent,
          title: 'لا توجد تذاكر لهذا المشترك',
        ),
      );

  Widget _ticketCard(dynamic t) {
    if (t is! Map) return const SizedBox();
    final displayId = t['displayId']?.toString() ?? t['id']?.toString() ?? '';
    final summary =
        t['summary']?.toString() ?? t['description']?.toString() ?? 'بدون ملخص';
    final status = _localizedStatus(t['status']?.toString());
    final created = t['createdAt']?.toString();
    final zone =
        (t['zone'] is Map) ? t['zone']['displayValue']?.toString() : '';
    String fmtDate(String? d) {
      if (d == null || d.isEmpty) return '';
      try {
        final dt = DateTime.parse(d).toLocal();
        return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        return d;
      }
    }

    final stTone = _statusTone(status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SdRaised(
        onTap: () => _openDetails(t.cast<String, dynamic>()),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SdStatusChip(status, status: stTone),
            const Spacer(),
            if (displayId.isNotEmpty)
              Text('#$displayId',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: SdColors.muted)),
          ]),
          const SizedBox(height: 10),
          SelectableText(summary,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: SdColors.ink)),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 6, children: [
            if (zone != null && zone.isNotEmpty) _chip(Icons.location_on, zone),
            if (created != null) _chip(Icons.schedule, fmtDate(created)),
          ])
        ]),
      ),
    );
  }

  Widget _chip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: SdColors.surfaceAlt,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: SdColors.divider),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: SdColors.faint),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: SdColors.muted)),
        ]),
      );
}
