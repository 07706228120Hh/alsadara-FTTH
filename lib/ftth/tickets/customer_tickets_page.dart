/// اسم الصفحة: تذاكر العملاء
/// وصف الصفحة: صفحة تذاكر الدعم الفني للعملاء
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../tickets/tktat_details_page.dart';

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
      final r = await http.get(url, headers: {
        'Authorization': 'Bearer ${widget.authToken}',
        'Accept': 'application/json'
      });
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
        setState(() {
          _error = 'انتهت صلاحية الجلسة (401)';
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'فشل الجلب: ${r.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'خطأ: $e';
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

  Color _statusColor(String s) {
    final l = s.toLowerCase();
    if (l.contains('مفت')) return Colors.orange;
    if (l.contains('مغل')) return Colors.green;
    if (l.contains('قيد')) return Colors.indigo;
    if (l.contains('معلق')) return Colors.amber;
    return Colors.blueGrey;
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
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 4,
        toolbarHeight: 72,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.blue[700]!,
                Colors.blue[500]!,
                Colors.indigo[400]!
              ],
            ),
          ),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('تذاكر المشترك',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            if (widget.customerName != null)
              Text(widget.customerName!,
                  style: TextStyle(
                      fontSize: 11, color: Colors.white.withValues(alpha: .9))),
            if (!_loading)
              Text('$_total تذكرة',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: .95)))
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _fetch(reset: true),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() => Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: .05),
                blurRadius: 6,
                offset: const Offset(0, 3))
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(children: [
          const Icon(Icons.search, color: Colors.blueGrey, size: 20),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 52, color: Colors.red),
            const SizedBox(height: 12),
            Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.red, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
                onPressed: () => _fetch(reset: true),
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'))
          ]),
        ),
      );

  Widget _emptyWidget() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.support_agent, size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Text('لا توجد تذاكر لهذا المشترك',
                style: TextStyle(
                    color: Colors.black54, fontWeight: FontWeight.w600)),
          ]),
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

    final stColor = _statusColor(status);
    return InkWell(
      onTap: () => _openDetails(t.cast<String, dynamic>()),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.white, Colors.grey.shade50]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: stColor.withValues(alpha: .35), width: 1.2),
          boxShadow: [
            BoxShadow(
                color: stColor.withValues(alpha: .15),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: stColor.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(status,
                  style: TextStyle(
                      color: stColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12)),
            ),
            const Spacer(),
            if (displayId.isNotEmpty)
              Text('#$displayId',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          SelectableText(summary,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, height: 1.25)),
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
          color: Colors.blueGrey.shade50,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.blueGrey.shade200),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.blueGrey.shade700),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey.shade800)),
        ]),
      );
}
