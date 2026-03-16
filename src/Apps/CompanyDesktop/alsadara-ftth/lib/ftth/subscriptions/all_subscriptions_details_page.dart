/// اسم الصفحة: تفاصيل جميع الاشتراكات
/// وصف الصفحة: صفحة عرض تفاصيل جميع الاشتراكات الفعالة
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth/auth_error_handler.dart';
import '../../services/auth_service.dart';

class AllSubscriptionsDetailsPage extends StatefulWidget {
  final String authToken;
  const AllSubscriptionsDetailsPage({super.key, required this.authToken});
  @override
  State<AllSubscriptionsDetailsPage> createState() =>
      _AllSubscriptionsDetailsPageState();
}

class _AllSubscriptionsDetailsPageState
    extends State<AllSubscriptionsDetailsPage> {
  final List<Map<String, dynamic>> _subscriptions = [];
  bool _loading = true;
  bool _loadingDetails = false;
  String _statusMsg = 'جاري البدء...';
  double _progress = 0.0;
  bool _cancel = false;
  static const int _pageSize = 150;
  static const int _detailsBatchSize = 15;

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    try {
      int page = 1;
      int totalCount = 0;
      while (!_cancel) {
        final baseUrl =
            'https://admin.ftth.iq/api/subscriptions?sortCriteria.property=expires&sortCriteria.direction=asc&hierarchyLevel=0&pageSize=$_pageSize&pageNumber=$page';
        final resp = await AuthService.instance.authenticatedRequest(
          'GET',
          baseUrl,
        );
        if (resp.statusCode == 401) {
          if (mounted) AuthErrorHandler.handle401Error(context);
          return;
        }
        if (resp.statusCode != 200) {
          setState(() {
            _statusMsg = 'فشل جلب الصفحة $page: ${resp.statusCode}';
            _loading = false;
          });
          return;
        }
        final data = jsonDecode(resp.body);
        final items = (data['items'] as List?) ?? [];
        totalCount = data['totalCount'] ??
            (page == 1 ? items.length : _subscriptions.length + items.length);
        if (items.isEmpty) break;
        _subscriptions.addAll(items.cast<Map<String, dynamic>>());
        setState(() {
          _statusMsg =
              'تم جلب ${_subscriptions.length} / $totalCount (صفحة $page)';
          _progress =
              totalCount == 0 ? 0 : (_subscriptions.length / totalCount) * 0.4;
        });
        if (_subscriptions.length >= totalCount) break;
        page++;
      }
      if (_cancel) return;
      await _enrichCustomersSummary();
      if (_cancel) return;
      await _fetchDetailsForAll();
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMsg = 'خطأ';
        });
      }
    } finally {
      if (mounted && !_cancel) {
        setState(() {
          _loading = false;
          _statusMsg = 'اكتمل تحميل ${_subscriptions.length} اشتراك';
          _progress = 1.0;
        });
      }
    }
  }

  Future<void> _enrichCustomersSummary() async {
    final ids = _subscriptions
        .map((s) => s['customer']?['id']?.toString())
        .where((e) => e != null && e.toString().isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    const batchSize = 50;
    for (int i = 0; i < ids.length && !_cancel; i += batchSize) {
      final batch = ids.skip(i).take(batchSize).toList();
      try {
        final urlStr =
            'https://api.ftth.iq/api/customers/summary?ids=${batch.join(',')}';
        final resp = await AuthService.instance.authenticatedRequest(
          'GET',
          urlStr,
        );
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final summaryItems = (data['items'] as List?) ?? [];
          for (var sub in _subscriptions) {
            final cid = sub['customer']?['id']?.toString();
            if (cid != null) {
              final match = summaryItems.firstWhere(
                  (e) => e['id'].toString() == cid,
                  orElse: () => null);
              if (match != null) {
                sub['customerSummary'] = match;
              }
            }
          }
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _statusMsg =
              'تجهيز بيانات العملاء (${(i + batchSize).clamp(0, ids.length)}/$ids)';
          _progress = 0.4 + 0.2 * ((i + batchSize) / ids.length).clamp(0, 1);
        });
      }
      await Future.delayed(const Duration(milliseconds: 80));
    }
  }

  Future<void> _fetchDetailsForAll() async {
    setState(() {
      _loadingDetails = true;
    });
    final ids = _subscriptions
        .map((s) => s['self']?['id']?.toString())
        .where((e) => e != null && e.toString().isNotEmpty)
        .cast<String>()
        .toList();
    for (int i = 0; i < ids.length && !_cancel; i += _detailsBatchSize) {
      final batch = ids.skip(i).take(_detailsBatchSize).toList();
      final futures = batch.map((id) => _fetchSubscriptionDetails(id));
      final results = await Future.wait(futures);
      for (int j = 0; j < batch.length; j++) {
        final detail = results[j];
        if (detail != null) {
          final index = _subscriptions
              .indexWhere((s) => s['self']?['id']?.toString() == batch[j]);
          if (index != -1) {
            _subscriptions[index]['details'] = detail;
          }
        }
      }
      if (mounted) {
        setState(() {
          _statusMsg =
              'جلب تفاصيل الاشتراكات ${(i + batch.length)}/${ids.length}';
          _progress = 0.6 + 0.4 * ((i + batch.length) / ids.length);
        });
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }
    if (mounted && !_cancel) {
      setState(() {
        _loadingDetails = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _fetchSubscriptionDetails(String id) async {
    try {
      final resp = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/subscriptions/$id',
      );
      if (resp.statusCode == 200) return jsonDecode(resp.body);
    } catch (_) {}
    return null;
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    try {
      return DateFormat('yyyy-MM-dd').format(DateTime.parse(iso));
    } catch (_) {
      return iso.split('T').first;
    }
  }

  Color _statusColor(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'expired':
        return Colors.red;
      case 'suspended':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('كل الاشتراكات (تفاصيل كاملة)'),
        actions: [
          if (_loading)
            IconButton(
              icon: const Icon(Icons.cancel),
              tooltip: 'إلغاء',
              onPressed: () => setState(() {
                _cancel = true;
                _statusMsg = 'تم الإلغاء';
              }),
            )
        ],
      ),
      body: Column(
        children: [
          if (_loading || _loadingDetails)
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                    child: Text(_statusMsg,
                        style: const TextStyle(fontWeight: FontWeight.w500))),
                if (!_loading && !_loadingDetails)
                  Text('${_subscriptions.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(height: 0),
          Expanded(
              child: _subscriptions.isEmpty && !_loading
                  ? const Center(child: Text('لا توجد بيانات'))
                  : ListView.builder(
                      itemCount: _subscriptions.length,
                      itemBuilder: (c, i) {
                        final sub = _subscriptions[i];
                        final customer = sub['customer'] ?? {};
                        final status = sub['status']?.toString();
                        final details = sub['details'] ?? {};
                        final services = (sub['services'] as List?) ?? [];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  _statusColor(status).withValues(alpha: .15),
                              child:
                                  Icon(Icons.wifi, color: _statusColor(status)),
                            ),
                            title: Text(
                                customer['displayValue'] ??
                                    sub['username'] ??
                                    '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                'ID: ${customer['id'] ?? '—'} | ${status ?? ''}',
                                style: TextStyle(color: _statusColor(status))),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _kv('Username', sub['username']),
                                    _kv('الحالة', status),
                                    _kv('البداية', _fmtDate(sub['startedAt'])),
                                    _kv('الانتهاء', _fmtDate(sub['expires'])),
                                    _kv(
                                        'المنطقة',
                                        sub['zone']?['displayValue'] ??
                                            sub['zone']?['self']
                                                ?['displayValue']),
                                    _kv('الشريك',
                                        sub['partner']?['displayValue']),
                                    _kv('نوع البيع',
                                        sub['salesType']?['displayValue']),
                                    _kv(
                                        'الحزمة',
                                        sub['bundle']?['displayValue'] ??
                                            sub['bundleId']),
                                    _kv('مدة الالتزام',
                                        sub['commitmentPeriod']?.toString()),
                                    _kv('IP', sub['ipAddress']),
                                    _kv('MAC', sub['macAddress']),
                                    _kv('Public IPs',
                                        sub['publicIpsCount']?.toString()),
                                    if (sub['customerSummary'] != null)
                                      _kv(
                                          'هاتف',
                                          sub['customerSummary']
                                              ?['primaryPhone']),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: services.map((s) {
                                        final disp =
                                            s['displayValue']?.toString() ??
                                                s['id']?.toString() ??
                                                '';
                                        final type = s['type']?['displayValue']
                                                ?.toString() ??
                                            '';
                                        return Chip(
                                            label: Text(disp),
                                            backgroundColor: type == 'Base'
                                                ? Colors.blue.shade50
                                                : Colors.orange.shade50);
                                      }).toList(),
                                    ),
                                    const Divider(),
                                    Text('تفاصيل إضافية',
                                        style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontWeight: FontWeight.bold)),
                                    _kv(
                                        'sessionActive',
                                        sub['hasActiveSession'] == true
                                            ? 'نعم'
                                            : 'لا'),
                                    if (details.isNotEmpty) ...[
                                      _kv(
                                          'deviceUsername',
                                          details['deviceDetails']
                                              ?['username']),
                                      _kv('amountPaid',
                                          details['amountPaid']?.toString()),
                                      _kv('lastPaymentDate',
                                          _fmtDate(details['lastPaymentDate'])),
                                    ] else
                                      _kv('جاري تحميل التفاصيل', '...'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    )),
        ],
      ),
    );
  }

  Widget _kv(String k, dynamic v) {
    final val = (v == null || (v is String && v.isEmpty)) ? '—' : v.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 140,
              child: Text(k,
                  style: const TextStyle(fontSize: 12, color: Colors.black54))),
          Expanded(child: Text(val, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
