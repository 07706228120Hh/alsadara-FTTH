/// اسم الصفحة: الخطط والباقات
/// وصف الصفحة: صفحة إدارة الخطط والباقات المتاحة
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth/auth_error_handler.dart';
import '../../services/auth_service.dart';
// يمكن لاحقاً استخدام نظام الألوان الذكي إن لزم

/// صفحة عرض نتائج واجهة الباقات والعروض
/// المصدر: GET https://admin.ftth.iq/api/plans/bundles?includePrices=false
class PlansBundlesPage extends StatefulWidget {
  final String authToken;
  const PlansBundlesPage({super.key, required this.authToken});

  @override
  State<PlansBundlesPage> createState() => _PlansBundlesPageState();
}

class _PlansBundlesPageState extends State<PlansBundlesPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _raw; // كامل الاستجابة
  String? _rawBody; // جسم الاستجابة نصياً للتشخيص

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      debugPrint('[PlansBundles] fetching bundles...');
      final resp = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/plans/bundles?includePrices=false',
      );
      if (!mounted) return;
      if (resp.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      }
      if (resp.statusCode == 200) {
        _rawBody = resp.body;
        Map<String, dynamic>? data;
        try {
          final decoded = jsonDecode(resp.body);
          if (decoded is Map<String, dynamic>) {
            data = decoded;
          } else {
            debugPrint(
                '[PlansBundles] unexpected root JSON: ${decoded.runtimeType}');
            _error = 'بنية غير متوقعة للبيانات';
          }
        } catch (e) {
          debugPrint('[PlansBundles] JSON decode error');
          _error = 'تعذر قراءة البيانات';
        }
        if (data != null) {
          debugPrint('[PlansBundles] success keys: ${data.keys}');
          setState(() => _raw = data);
        } else {
          setState(() {});
        }
      } else {
        debugPrint('[PlansBundles] server error code=${resp.statusCode}');
        setState(() => _error = 'فشل الجلب: ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('[PlansBundles] exception');
      if (mounted) setState(() => _error = 'خطأ');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.indigo.shade600,
        foregroundColor: Colors.white,
        elevation: 1,
        title: const Text('الباقات و العروض',
            style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loading ? null : _fetch,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: Colors.red[400]),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
            if (_rawBody != null)
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: SizedBox(
                  width: 340,
                  child: Text(
                    _rawBody!.length > 500
                        ? '${_rawBody!.substring(0, 500)}...'
                        : _rawBody!,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              )
          ],
        ),
      );
    }
    if (_raw == null) {
      return const Center(child: Text('لا توجد بيانات'));
    }
    final plans = _extractPlans(_raw!);
    if (plans.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined, size: 68, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('لا توجد نتائج معروضة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'قد تكون البينات في مفتاح مختلف أو فارغة. سيتم إظهار معاينة خام للمساعدة في التشخيص.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            if (_rawBody != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  _rawBody!.length > 1200
                      ? '${_rawBody!.substring(0, 1200)}...'
                      : _rawBody!,
                  style: const TextStyle(fontSize: 11, height: 1.3),
                ),
              ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('تحديث'),
            ),
          ],
        ),
      );
    }

    // تجميع حسب السرعة المستخرجة من اسم الخطة
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final plan in plans) {
      final rawName =
          (plan['planName'] ?? plan['name'] ?? plan['title'] ?? '').toString();
      final key = _extractSpeedKey(rawName);
      grouped.putIfAbsent(key, () => []).add(plan);
    }
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) => _speedNumeric(a).compareTo(_speedNumeric(b)));

    return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        itemCount: sortedKeys.length,
        itemBuilder: (ctx, idx) {
          final speedKey = sortedKeys[idx];
          final list = grouped[speedKey]!;
          list.sort(
              (a, b) => _planVisibleName(a).compareTo(_planVisibleName(b)));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 12, bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.speed, size: 18, color: Colors.indigo.shade600),
                    const SizedBox(width: 6),
                    Text(
                      speedKey,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${list.length} خطة',
                          style: TextStyle(
                              fontSize: 11, color: Colors.indigo.shade600)),
                    ),
                  ],
                ),
              ),
              // بطاقات ممتدة بكامل العرض
              ...list.map((plan) {
                final planName = _planVisibleName(plan);
                final desc =
                    (plan['description'] ?? plan['desc'] ?? '').toString();
                final List offers =
                    (plan['offers'] ?? plan['items'] ?? []) as List;
                final simplified = offers
                    .map((o) => _simplifyOffer(o))
                    .where((m) => m.isNotEmpty)
                    .toList();
                simplified.sort((a, b) =>
                    (a['period'] as int).compareTo(b['period'] as int));
                return _PlanCard(
                  name: planName,
                  description: desc,
                  offers: simplified.cast<Map<String, dynamic>>(),
                );
              }),
            ],
          );
        });
  }

  List<Map<String, dynamic>> _extractPlans(Map<String, dynamic> root) {
    // احتمالات: root['items'] -> [ { items:[plans] } ] أو مباشرة قائمة خطط
    final List<Map<String, dynamic>> out = [];
    dynamic candidate = root['items'] ?? root['data'];
    if (candidate is List) {
      // قد يكون إما قائمة Bundles أو قائمة Plans مباشرة
      if (candidate.isNotEmpty &&
          candidate.first is Map &&
          (candidate.first as Map).containsKey('items')) {
        // نفترض أنها Bundles: نأخذ items لأول Bundle فقط أو ندمجها كلها
        for (final b in candidate) {
          if (b is Map && b['items'] is List) {
            for (final p in (b['items'] as List)) {
              if (p is Map<String, dynamic>) out.add(p);
            }
          }
        }
      } else {
        // نفترض أنها خطط مباشرة
        for (final p in candidate) {
          if (p is Map<String, dynamic>) out.add(p);
        }
      }
    } else if (candidate is Map && candidate['items'] is List) {
      for (final p in (candidate['items'] as List)) {
        if (p is Map<String, dynamic>) out.add(p);
      }
    }
    return out;
  }

  Map<String, dynamic> _simplifyOffer(dynamic raw) {
    if (raw is! Map<String, dynamic>) return {};
    final id = raw['id']?.toString() ?? '';
    final price =
        (raw['discountPrice'] is Map && raw['discountPrice']['value'] != null)
            ? raw['discountPrice']['value']
            : null;
    // محاولة استخراج مدة الالتزام + نوع الحالة من ID
    // الصيغة الشائعة: PREFIX_AREA_SPEED_PERIOD_TYPE => نأخذ الجزء قبل الأخير كرقم (إن وجد)
    final parts = id.split('_');
    int period = 0;
    String state = '';
    if (parts.length >= 2) {
      // ابحث عن أول جزء يمكن تحويله لعدد من النهاية باتجاه البداية
      for (int i = parts.length - 2; i >= 0; i--) {
        final p = int.tryParse(parts[i]);
        if (p != null) {
          period = p;
          break;
        }
      }
      state = parts.last; // D / DR / U
    }
    return {
      'id': id,
      'price': price,
      'period': period,
      'state': state,
      'from': raw['validAt']?['from'],
      'to': raw['validAt']?['to'],
    };
  }
}

class _PlanCard extends StatefulWidget {
  final String name;
  final String description;
  final List<Map<String, dynamic>> offers;
  const _PlanCard(
      {required this.name, required this.description, required this.offers});

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  @override
  Widget build(BuildContext context) {
    final offers = widget.offers;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        initiallyExpanded: false,
        onExpansionChanged: (v) {/* إمكانية التوسعة لاحقاً */},
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        collapsedShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(widget.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: widget.description.isEmpty
            ? null
            : Text(widget.description,
                maxLines: 2, overflow: TextOverflow.ellipsis),
        leading: CircleAvatar(
          backgroundColor: Colors.indigo.shade100,
          child: Text(widget.name.split(' ').last,
              style: TextStyle(color: Colors.indigo.shade800, fontSize: 11)),
        ),
        children: [
          if (offers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('لا توجد عروض متاحة'),
            )
          else
            _PeriodsSection(offers: offers),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PeriodsSection extends StatelessWidget {
  final List<Map<String, dynamic>> offers;
  const _PeriodsSection({required this.offers});

  Map<int, List<Map<String, dynamic>>> _group() {
    final map = <int, List<Map<String, dynamic>>>{};
    for (final o in offers) {
      final p = (o['period'] is int) ? o['period'] as int : 0;
      map.putIfAbsent(p, () => []).add(o);
    }
    final sortedKeys = map.keys.toList()..sort();
    return {for (final k in sortedKeys) k: map[k]!};
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _group();
    final dateFmt = DateFormat('dd/MM/yyyy');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: grouped.entries.map((e) {
          final period = e.key;
          final list = e.value;
          // ترتيب حسب نوع الحالة ثم السعر
          list.sort((a, b) => _stateRank((a['state'] ?? '').toString())
              .compareTo(_stateRank((b['state'] ?? '').toString())));
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: 0.025),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.indigo.withValues(alpha: 0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule,
                        size: 18, color: Colors.indigo.shade500),
                    const SizedBox(width: 6),
                    Text('${period == 0 ? '?' : period} شهر',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo.shade700)),
                    const Spacer(),
                    Text('${list.length} عرض',
                        style: TextStyle(
                            fontSize: 11, color: Colors.indigo.shade400)),
                  ],
                ),
                const SizedBox(height: 8),
                ...list.map((o) {
                  final state = (o['state'] ?? '').toString();
                  final price = o['price'];
                  final from = _formatDate(o['from'], dateFmt);
                  final to = _formatDate(o['to'], dateFmt);
                  final color = _stateColor(state);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 2, horizontal: 8),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(_arabicLabel(state),
                              style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_priceString(price),
                                  style: TextStyle(
                                      color: color.darken(0.15),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.date_range,
                                      size: 14, color: Colors.grey.shade600),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      '${from ?? '-'} → ${to ?? '-'}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade700),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ===== أدوات عرض (مساعدة) =====
int _stateRank(String s) {
  switch (s) {
    case 'D':
      return 0; // جديد
    case 'DR':
      return 1; // تجديد
    case 'U':
      return 2; // ترقية
    default:
      return 3;
  }
}

Color _stateColor(String s) {
  switch (s) {
    case 'DR':
      return Colors.orange.shade600;
    case 'U':
      return Colors.teal.shade600;
    case 'D':
    default:
      return Colors.blue.shade600;
  }
}

String _arabicLabel(String s) {
  switch (s) {
    case 'DR':
      return 'تجديد';
    case 'U':
      return 'ترقية';
    case 'D':
    default:
      return 'جديد';
  }
}

String _priceString(dynamic v) {
  if (v == null) return '--';
  try {
    final num n = v is num ? v : num.parse(v.toString());
    if (n % 1 == 0) {
      final s = n.toInt().toString();
      return '${_addSeparators(s)} IQD';
    }
    return '${n.toStringAsFixed(2)} IQD';
  } catch (_) {
    return v.toString();
  }
}

String _addSeparators(String s) {
  final buf = StringBuffer();
  int count = 0;
  for (int i = s.length - 1; i >= 0; i--) {
    buf.write(s[i]);
    count++;
    if (count == 3 && i != 0) {
      buf.write(',');
      count = 0;
    }
  }
  return buf.toString().split('').reversed.join();
}

String? _formatDate(dynamic v, DateFormat fmt) {
  if (v == null) return null;
  try {
    final dt = DateTime.tryParse(v.toString());
    if (dt == null) return null;
    return fmt.format(dt.toLocal());
  } catch (_) {
    return null;
  }
}

extension _ColorShade on Color {
  Color darken([double amount = .1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}

// ===== دوال مساعدة للتجميع والتنظيم =====
String _extractSpeedKey(String name) {
  final regex = RegExp(r'(\d+\s?(?:M|MB|Mb|ميك))', caseSensitive: false);
  final match = regex.firstMatch(name);
  if (match != null) {
    return match.group(0)!.replaceAll(' ', '').toUpperCase();
  }
  if (name.trim().isEmpty) return 'أخرى';
  return name.split(' ').first;
}

int _speedNumeric(String key) {
  final digits = RegExp(r'\d+').firstMatch(key);
  if (digits == null) return 0;
  return int.tryParse(digits.group(0)!) ?? 0;
}

String _planVisibleName(Map<String, dynamic> plan) {
  return (plan['planName'] ?? plan['name'] ?? plan['title'] ?? 'خطة')
      .toString();
}
