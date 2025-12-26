/// اسم الصفحة: البيانات الخام للتذاكر
/// وصف الصفحة: صفحة البيانات الخام للتذاكر والطلبات
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TKTATRawPage extends StatelessWidget {
  final Map<String, dynamic> ticket;
  const TKTATRawPage({super.key, required this.ticket});

  String _prettyJson() {
    try {
      final encoder = const JsonEncoder.withIndent('  ');
      return encoder.convert(ticket);
    } catch (_) {
      return ticket.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = ticket.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('الحقول الخام للتذكرة', style: TextStyle(fontSize: 14)),
        actions: [
          IconButton(
            tooltip: 'نسخ JSON',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _prettyJson()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم نسخ JSON')),
              );
            },
          ),
        ],
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blueGrey[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: const TabBar(
                tabs: [
                  Tab(text: 'مفاتيح'),
                  Tab(text: 'JSON'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // المفاتيح
                  Scrollbar(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: keys.length,
                      itemBuilder: (ctx, i) {
                        final k = keys[i];
                        final v = ticket[k];
                        String shortVal;
                        if (v is Map) {
                          if (v.containsKey('displayValue')) {
                            shortVal = v['displayValue'].toString();
                          } else {
                            shortVal = '{${v.keys.take(5).join(', ')}}';
                          }
                        } else if (v is List) {
                          shortVal = '[${v.length} عناصر]';
                        } else {
                          shortVal = v?.toString() ?? 'null';
                        }
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: SelectableText(
                                    k,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blueGrey[700],
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 6,
                                  child: SelectableText(
                                    shortVal,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blueGrey[800],
                                    ),
                                    maxLines: 6,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'نسخ',
                                  icon: const Icon(Icons.copy, size: 16),
                                  onPressed: () {
                                    Clipboard.setData(
                                        ClipboardData(text: shortVal));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text('نُسخت القيمة: $k')),
                                    );
                                  },
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // JSON
                  Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _prettyJson(),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: Colors.greenAccent[100],
                            height: 1.25,
                          ),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
