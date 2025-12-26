/// اسم الصفحة: تفاصيل التذكرة
/// وصف الصفحة: صفحة تفاصيل تذكرة دعم فني محددة
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart'; // لاستخدام Clipboard
import 'package:http/http.dart' as http;
import '../../task/add_task_dialog.dart'; // تأكد من استيراد صفحة AddTKTATDialog
// import 'utils/status_translator.dart'; // لم يعد مستخدماً بعد إخفاء زر مؤشرات SLA
import 'package:url_launcher/url_launcher.dart'; // لفتح رابط التذكرة في المتصفح

// دوال مساعدة للاستخراج الآمن

String _safeString(dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  return v.toString();
}

String _getDisplayValue(dynamic obj) {
  if (obj is Map) {
    final dv = obj['displayValue'];
    if (dv is String && dv.trim().isNotEmpty) return dv.trim();
  }
  if (obj is String) return obj.trim();
  return '';
}

String extractTitle(Map<String, dynamic> m) {
  return _getDisplayValue(m['self']).trim().isNotEmpty
      ? _getDisplayValue(m['self'])
      : ['title', 'subject', 'name', 'ticketTitle']
          .map((k) => _safeString(m[k]))
          .firstWhere((s) => s.trim().isNotEmpty, orElse: () => 'بدون عنوان');
}

String extractSummary(Map<String, dynamic> m) {
  return ['summary', 'description', 'details']
      .map((k) => _safeString(m[k]))
      .firstWhere(
        (s) => s.trim().isNotEmpty,
        orElse: () => 'غير متوفر',
      );
}

String extractCustomer(Map<String, dynamic> m) {
  final candidates = [
    _getDisplayValue(m['customer']),
    _safeString(m['customerName']),
    _safeString(m['clientName']),
    _safeString(m['client']),
    _safeString(m['userName']),
    _safeString(m['user']),
  ];
  return candidates.firstWhere((s) => s.trim().isNotEmpty,
      orElse: () => 'غير متوفر');
}

String extractZone(Map<String, dynamic> m) {
  final candidates = [
    _getDisplayValue(m['zone']),
    _safeString(m['zone']),
    _safeString(m['region'])
  ];
  return candidates.firstWhere((s) => s.trim().isNotEmpty,
      orElse: () => 'غير متوفر');
}

String safeField(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v == null) return 'غير متوفر';
  if (v is Map) {
    final dv = v['displayValue'];
    if (dv is String && dv.trim().isNotEmpty) return dv;
    return v.toString();
  }
  return _safeString(v).isEmpty ? 'غير متوفر' : _safeString(v);
}

class TKTATDetailsPage extends StatefulWidget {
  final dynamic tktat;
  final String? authToken; // توكن اختياري لجلب التعليقات

  const TKTATDetailsPage({super.key, required this.tktat, this.authToken});

  @override
  State<TKTATDetailsPage> createState() => _TKTATDetailsPageState();
}

class _TKTATDetailsPageState extends State<TKTATDetailsPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _commentsKey = GlobalKey();
  DateTime? _createdAtUtc;
  Duration _targetSla = const Duration(hours: 24);
  String _categoryName = '';
  Timer? _timer;
  // حالة التعليقات
  bool _loadingComments = false;
  String? _commentsError;
  List<dynamic> _comments = [];
  bool _commentsFetched = false; // حتى لا نعيد الجلب دون طلب المستخدم
  bool _commentsVisible = false; // التحكم في إظهار/إخفاء التعليقات بعد الجلب
  bool _postingComment = false;
  final TextEditingController _commentController = TextEditingController();
  int _commentsTotalCount = 0; // العدد الكلي من الخادم

  // إعدادات تكبير (يمكن تعديلها لاحقاً بسهولة)
  static const double kLabelFont = 15.0; // حجم تسمية الحقول
  static const double kValueFont = 15.6; // حجم القيمة
  static const double kIconSizeInfo = 18.0; // حجم أيقونة صف المعلومات
  static const double kRowHPad = 14.0; // الحشو الأفقي للصف
  static const double kRowVPad = 6.0; // الحشو الرأسي للصف
  static const double kInlineGap = 10.0; // المسافة بين التسمية والقيمة
  static const double kSlaTitleFont = 22.0; // عنوان بطاقة SLA
  static const double kSlaTagFont = 14.0; // شارة التصنيف
  static const double kSlaProgressHeight = 10; // (مصغر) ارتفاع شريط التقدم

  // تحويل الأرقام الغربية إلى أرقام عربية شرقية
  String _toArabicDigits(String input) {
    const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    final sb = StringBuffer();
    for (final ch in input.split('')) {
      final idx = western.indexOf(ch);
      if (idx != -1) {
        sb.write(eastern[idx]);
      } else {
        sb.write(ch);
      }
    }
    return sb.toString();
  }

  String _arabicHourUnit(int h) {
    if (h == 1) return 'ساعة';
    if (h == 2) return 'ساعتين';
    if (h >= 3 && h <= 10) return 'ساعات';
    return 'ساعة';
  }

  String _arabicMinuteUnit(int m) {
    if (m == 1) return 'دقيقة';
    if (m == 2) return 'دقيقتين';
    if (m >= 3 && m <= 10) return 'دقائق';
    return 'دقيقة';
  }

  String _arabicSecondUnit(int s) {
    if (s == 1) return 'ثانية';
    if (s == 2) return 'ثانيتين';
    if (s >= 3 && s <= 10) return 'ثوانٍ';
    return 'ثانية';
  }

  @override
  void initState() {
    super.initState();
    _initSlaData();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // يعيد البناء لتحديث الزمن المتبقي
    });
  }

  void _initSlaData() {
    try {
      final tktat = widget.tktat;
      if (tktat is Map) {
        final rawCreated = tktat['createdAt'];
        if (rawCreated is String && rawCreated.trim().isNotEmpty) {
          try {
            _createdAtUtc = DateTime.parse(rawCreated).toUtc();
          } catch (_) {}
        }
        _categoryName = safeField(
          (tktat as Map<String, dynamic>)
              .map((k, v) => MapEntry(k.toString(), v)),
          'category',
        );
        final c = _categoryName.toLowerCase();
        if (c.contains('incident') ||
            c.contains('انقطاع') ||
            c.contains('قطع')) {
          _targetSla = const Duration(hours: 4);
        } else {
          _targetSla = const Duration(hours: 24);
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tktat = widget.tktat;
    try {
      // تحويل آمن: إذا كانت الخريطة تحوي مفاتيح غير String لن نفشل
      final Map<String, dynamic> ticketMap = () {
        if (tktat is Map) {
          final Map<String, dynamic> out = {};
          tktat.forEach((key, value) {
            out[key.toString()] = value; // تحويل المفتاح لنص دائماً
          });
          return out;
        }
        return <String, dynamic>{};
      }();

      final title = extractTitle(ticketMap);
      final summary = extractSummary(ticketMap);
      final customer = extractCustomer(ticketMap);
      final zone = extractZone(ticketMap);
      // final status = safeField(ticketMap, 'status'); // لم يعد مستخدماً بعد إزالة زر مؤشرات SLA

      // استخراج معرفات إضافية (تم حذف ticketId لأنه مكرر مع displayId)
      final ticketNumber = () {
        // رقم التذكرة النهائي (كان displayId)
        final direct = ticketMap['displayId'];
        if (direct != null && direct.toString().trim().isNotEmpty) {
          return direct.toString();
        }
        final self = ticketMap['self'];
        if (self is Map &&
            self['id'] != null &&
            self['id'].toString().trim().isNotEmpty) {
          return self['id'].toString();
        }
        if (ticketMap['id'] != null) return ticketMap['id'].toString();
        return 'غير متوفر';
      }();
      // نحتفظ بـ selfId للاستخدام المستقبلي (مثلاً في عمليات تحديث أو روابط خارجية)
      // ignore: unused_local_variable
      final selfId = () {
        final self = ticketMap['self'];
        if (self is Map && self['id'] != null) return self['id'].toString();
        return 'غير متوفر';
      }();
      final userId = () {
        final customerObj = ticketMap['customer'];
        if (customerObj is Map && customerObj['id'] != null) {
          return customerObj['id'].toString();
        }
        if (ticketMap['customerId'] != null) {
          return ticketMap['customerId'].toString();
        }
        if (ticketMap['userId'] != null) return ticketMap['userId'].toString();
        return 'غير متوفر';
      }();
      final ticketGuid = () {
        // معرف GUID الحقيقي لاستخدامه في API التعليقات
        // نحاول إيجاده عبر مفاتيح شائعة
        final self = ticketMap['self'];
        if (ticketMap['ticketId'] != null) {
          return ticketMap['ticketId'].toString();
        }
        if (ticketMap['id'] != null && ticketMap['id'].toString().length > 20) {
          return ticketMap['id'].toString();
        }
        if (self is Map &&
            self['id'] != null &&
            self['id'].toString().length > 20) {
          return self['id'].toString();
        }
        return null; // قد لا نحتاجه إن لم يكن متاحاً
      }();

      // الترجمة أصبحت عبر translateTicketStatus في utils/status_translator.dart

      // تم حذف دالة formatDateTime لعدم الحاجة لعرض التواريخ حالياً

      // حذف متغيري createdAt و updatedAt لعدم عرضهما حالياً

      // --- حساب SLA ديناميكي ---
      final nowUtc = DateTime.now().toUtc();
      Duration elapsed = _createdAtUtc == null
          ? Duration.zero
          : nowUtc.difference(_createdAtUtc!);
      if (elapsed.isNegative) elapsed = Duration.zero;
      Duration remaining = _targetSla - elapsed;
      if (remaining.isNegative) remaining = Duration.zero;

      String formatDurationCompact(Duration d) {
        final h = d.inHours;
        final m = d.inMinutes.remainder(60);
        final s = d.inSeconds.remainder(60);
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      }

      String formatDurationVerbose(Duration d) {
        if (d == Duration.zero) return '0 ثانية';
        final h = d.inHours;
        final m = d.inMinutes.remainder(60);
        final s = d.inSeconds.remainder(60);
        final parts = <String>[];
        String nbsp(int n, String unit) =>
            '$n\u00A0$unit'; // يحافظ على اقتران الرقم مع الكلمة
        if (h > 0) parts.add(nbsp(h, _arabicHourUnit(h)));
        if (m > 0) parts.add(nbsp(m, _arabicMinuteUnit(m)));
        if (s > 0 && h == 0) parts.add(nbsp(s, _arabicSecondUnit(s)));
        return parts.join(' و ');
      }

      final slaStatus = remaining.inSeconds == 0 ? 'متجاوز' : 'ضمن الحدود';
      final elapsedStr = _toArabicDigits(formatDurationCompact(elapsed));
      final remainingStr = _toArabicDigits(formatDurationCompact(remaining));
      final targetStr = _toArabicDigits(formatDurationCompact(_targetSla));
      final elapsedVerbose = _toArabicDigits(formatDurationVerbose(elapsed));
      final remainingVerbose =
          _toArabicDigits(formatDurationVerbose(remaining));
      // تم حذف عرض وقت الإنشاء والتحديث من البطاقة؛ لا حاجة للمتغيرات المحولة للأرقام العربية

      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 70,
          leadingWidth: 96,
          leading: _buildLeadingActions(context),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.indigo.shade600,
                  Colors.blue.shade600,
                  Colors.teal.shade400,
                ],
              ),
            ),
          ),
          titleSpacing: 0,
          title: const SizedBox.shrink(),
          actions: [
            _buildAppBarAction(
              icon: Icons.open_in_new,
              color: Colors.green,
              tooltip: 'فتح التذكرة في المتصفح',
              iconSize: 28,
              boxSize: 50,
              onTap: () {
                if (ticketGuid != null) {
                  _openTicketInBrowser(ticketGuid);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('لا يمكن تحديد معرف التذكرة لفتح الرابط')),
                  );
                }
              },
            ),
            const SizedBox(width: 8),
            _buildAppBarAction(
              icon: Icons.add,
              color: Colors.orange,
              tooltip: 'إضافة',
              iconSize: 28,
              boxSize: 50,
              onTap: () {
                // تجهيز النص المراد تمريره كملاحظات مبدئية في نافذة الإضافة
                final combinedText = [
                  'رقم التذكرة: $ticketNumber',
                  'العنوان: $title',
                  'الخلاصة: $summary',
                  'العميل: $customer',
                  'معرف المستخدم: $userId',
                  'المنطقة: $zone',
                ].join('\n');
                showDialog(
                  context: context,
                  builder: (context) => AddTaskDialog(
                    currentUsername: 'اسم المستخدم',
                    currentUserRole: 'Admin',
                    currentUserDepartment: 'FTTH',
                    initialNotes:
                        combinedText, // تمرير المعلومات إلى حقل الملاحظات
                    onTaskAdded: (newTask) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('تم إضافة TKTAT: ${newTask.title}')),
                      );
                      Navigator.pop(context);
                    },
                  ),
                );
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // بطاقة SLA المختصرة
                _buildSlaCard(
                  categoryName: _categoryName,
                  target: targetStr,
                  elapsed: '$elapsedStr  ($elapsedVerbose)',
                  remaining: '$remainingStr  ($remainingVerbose)',
                  slaStatus: slaStatus,
                  progress: _targetSla.inSeconds == 0
                      ? 0
                      : (elapsed.inSeconds / _targetSla.inSeconds).clamp(0, 1),
                ),
                const SizedBox(height: 8), // تقليل المسافة بعد بطاقة SLA
                // المجموعة 1: معلومات التذكرة
                _buildGroupCard(
                  heading: 'معلومات التذكرة',
                  startColor: Colors.blue.shade50,
                  endColor: Colors.blue.shade100,
                  rows: [
                    _buildInfoRow(
                        icon: Icons.confirmation_number,
                        label: 'رقم التذكرة',
                        value: ticketNumber,
                        iconColor: Colors.indigo),
                    _buildInfoRow(
                        icon: Icons.title,
                        label: 'العنوان',
                        value: title,
                        iconColor: Colors.blue),
                    _buildInfoRow(
                        icon: Icons.description,
                        label: 'الخلاصة',
                        value: summary,
                        iconColor: Colors.teal),
                  ],
                ),
                SizedBox(
                    height:
                        4), // تقليل المسافة بين بطاقة معلومات التذكرة وبطاقة المشترك
                // المجموعة 2: معلومات المشترك
                _buildGroupCard(
                  heading: 'معلومات المشترك',
                  startColor: Colors.orange.shade50,
                  endColor: Colors.orange.shade100,
                  rows: [
                    _buildInfoRow(
                        icon: Icons.person,
                        label: 'العميل',
                        value: customer,
                        iconColor: Colors.orange,
                        showCopyButton: true),
                    _buildInfoRow(
                        icon: Icons.badge,
                        label: 'معرف المستخدم',
                        value: userId,
                        iconColor: Colors.deepOrange),
                    _buildInfoRow(
                        icon: Icons.location_on,
                        label: 'المنطقة',
                        value: zone,
                        iconColor: Colors.deepPurple),
                  ],
                ),
                SizedBox(
                    height:
                        4), // تقليل المسافة بين بطاقة المشترك وبطاقة معلومات أخرى
                // المجموعة 3: معلومات أخرى (حذف وقت الإنشاء/التحديث ووضع زر التعليقات داخل البطاقة)
                _buildGroupCard(
                  heading: 'معلومات أخرى',
                  startColor: Colors.green.shade50,
                  endColor: Colors.green.shade100,
                  compact: true,
                  rows: [
                    _buildInfoRowCompact(
                        icon: Icons.attach_file,
                        label: 'عدد المرفقات',
                        value: safeField(ticketMap, 'attachmentsCount'),
                        iconColor: Colors.blueGrey),
                    _buildInfoRowCompact(
                        icon: Icons.comment,
                        label: 'عدد التعليقات',
                        value: safeField(ticketMap, 'commentsCount'),
                        iconColor: Colors.cyan),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _buildCommentsButton(ticketGuid),
                    ),
                  ],
                ),
                if (_commentsVisible) const SizedBox(height: 6),
                if (_commentsVisible)
                  KeyedSubtree(
                    key: _commentsKey,
                    child: _buildCommentsSection(),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (e, st) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل TKTAT')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('حدث خطأ أثناء عرض التفاصيل',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text('الرسالة: $e'),
                const SizedBox(height: 12),
                Text('StackTrace:\n$st',
                    style:
                        const TextStyle(fontSize: 11, fontFamily: 'monospace')),
              ],
            ),
          ),
        ),
      );
    }
  }

  // فتح رابط تفاصيل التذكرة في المتصفح الخارجي
  Future<void> _openTicketInBrowser(String guid) async {
    final uri = Uri.parse('https://admin.ftth.iq/tickets/details/$guid');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر فتح الرابط')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء فتح الرابط: $e')),
        );
      }
    }
  }

  // تم إزالة وظيفة النسخ حسب طلب المستخدم.

  // جلب التعليقات من API
  Future<void> _fetchComments(String ticketGuid) async {
    if (_loadingComments) return;
    setState(() {
      _loadingComments = true;
      _commentsError = null;
    });
    try {
      final token = widget.authToken;
      if (token == null || token.isEmpty) {
        setState(() {
          _commentsError =
              'لا يوجد توكن مصادقة - الرجاء الرجوع وتسجيل الدخول مجدداً';
          _commentsFetched = true;
        });
        return;
      }
      final url = Uri.parse(
          'https://admin.ftth.iq/api/support/tickets/$ticketGuid/comments?pageSize=10&pageNumber=1');
      final resp = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final items = (data['items'] as List?) ?? [];
        // ترتيب تنازلي بحسب createdAt (الأحدث أولاً) إن وجد
        items.sort((a, b) {
          try {
            final ad = DateTime.tryParse((a['createdAt'] ?? '').toString()) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bd = DateTime.tryParse((b['createdAt'] ?? '').toString()) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bd.compareTo(ad);
          } catch (_) {
            return 0;
          }
        });
        setState(() {
          _comments = items;
          _commentsTotalCount =
              data['totalCount'] is int ? data['totalCount'] : items.length;
          _commentsFetched = true;
        });
      } else {
        setState(() {
          _commentsError = 'فشل الجلب: ${resp.statusCode}';
          _commentsFetched = true;
        });
      }
    } catch (e) {
      setState(() {
        _commentsError = 'خطأ: $e';
        _commentsFetched = true;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingComments = false);
      }
    }
  }

  Future<void> _postComment(String ticketGuid) async {
    if (_postingComment) return;
    final text = _commentController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('أدخل نص التعليق أولاً')));
      return;
    }
    final token = widget.authToken;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('لا يوجد توكن مصادقة')));
      return;
    }
    setState(() {
      _postingComment = true;
    });
    try {
      final url = Uri.parse(
          'https://admin.ftth.iq/api/support/tickets/$ticketGuid/comments');
      final body = jsonEncode({
        'body': text,
        'ticketId': ticketGuid,
      });
      final resp = await http.post(url,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            'Content-Type': 'application/json'
          },
          body: body);
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        // إدراج تفاؤلي للتعليق
        final newComment = {
          'body': text,
          'content': text,
          'author': {'displayValue': 'أنت'},
          'createdAt': DateTime.now().toIso8601String(),
        };
        setState(() {
          _comments.insert(0, newComment);
          _commentsFetched = true;
          _commentController.clear();
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم إرسال التعليق')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل إرسال التعليق: ${resp.statusCode}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ أثناء الإرسال: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _postingComment = false;
        });
      }
    }
  }

  Widget _buildCommentsButton(String? ticketGuid) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.indigo.shade600,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: (ticketGuid == null)
            ? null
            : () {
                if (_loadingComments) return;
                if (!_commentsFetched) {
                  // أول مرة: جلب ثم إظهار
                  _fetchComments(ticketGuid).then((_) {
                    setState(() {
                      _commentsVisible = true;
                    });
                    _scrollToComments();
                  });
                } else {
                  if (_commentsVisible) {
                    // كانت ظاهرة -> إخفاء والتمرير للأعلى
                    setState(() {
                      _commentsVisible = false;
                    });
                    _scrollToTop();
                  } else {
                    // كانت مخفية -> إظهار فقط والتمرير للأسفل
                    setState(() {
                      _commentsVisible = true;
                    });
                    _scrollToComments();
                  }
                }
              },
        icon: _loadingComments
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white),
              )
            : Icon(_commentsVisible ? Icons.visibility_off : Icons.comment,
                color: Colors.white),
        label: Text(
          _loadingComments
              ? 'جاري تحميل التعليقات...'
              : !_commentsFetched
                  ? 'عرض التعليقات'
                  : _commentsVisible
                      ? 'إخفاء التعليقات'
                      : 'إظهار التعليقات',
          style: const TextStyle(
              fontSize: 17.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .3,
              color: Colors.white),
        ),
      ),
    );
  }

  void _scrollToComments() {
    if (!_commentsFetched) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _commentsKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        );
      }
    });
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Widget _buildCommentsSection() {
    if (_commentsError != null) {
      return _buildCommentContainer(
        child: Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_commentsError!,
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w700))),
          ],
        ),
      );
    }
    if (_comments.isEmpty) {
      // عرض رسالة عدم وجود تعليقات + مربع الإضافة
      return Column(
        children: [
          _buildCommentContainer(
            child: Row(
              children: const [
                Icon(Icons.info_outline, color: Colors.blueGrey),
                SizedBox(width: 8),
                Expanded(
                    child: Text('لا توجد تعليقات',
                        style: TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildAddCommentBox(),
        ],
      );
    }
    // عند وجود تعليقات نعرضها + مربع الإضافة كالسابق
    return Column(
      children: [
        _buildCommentContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.comment, color: Colors.indigo),
                  const SizedBox(width: 6),
                  Text('التعليقات (${_comments.length}/$_commentsTotalCount)',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              ..._comments.map((c) => _buildSingleComment(c)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _buildAddCommentBox(),
      ],
    );
  }

  Widget _buildAddCommentBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.indigo.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.add_comment, color: Colors.indigo),
              SizedBox(width: 6),
              Text('إضافة تعليق',
                  style:
                      TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            maxLines: 3,
            minLines: 2,
            decoration: InputDecoration(
              hintText: 'اكتب تعليقك هنا...',
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.indigo.shade200)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.indigo.shade200)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: Colors.indigo.shade400, width: 1.2)),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade600,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              onPressed: _postingComment
                  ? null
                  : () {
                      // محاولة استخراج المعرف المستخدم سابقاً في جلب التعليقات
                      final builtTicketGuid = () {
                        final t = widget.tktat;
                        if (t is Map) {
                          if (t['ticketId'] != null) {
                            return t['ticketId'].toString();
                          }
                          if (t['id'] != null &&
                              t['id'].toString().length > 20) {
                            return t['id'].toString();
                          }
                          final self = t['self'];
                          if (self is Map &&
                              self['id'] != null &&
                              self['id'].toString().length > 20) {
                            return self['id'].toString();
                          }
                        }
                        return null;
                      }();
                      if (builtTicketGuid == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'تعذر تحديد معرف التذكرة لإرسال التعليق')));
                        return;
                      }
                      _postComment(builtTicketGuid);
                    },
              icon: _postingComment
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : const Icon(Icons.send, size: 18, color: Colors.white),
              label: Text(_postingComment ? 'إرسال...' : 'إرسال',
                  style: TextStyle(
                      fontSize: 13.8,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCommentContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSingleComment(dynamic c) {
    // محاولة استخراج الحقول الشائعة
    String content = '';
    String author = '';
    String created = '';
    if (c is Map) {
      // شكل الخادم: self.displayValue يحمل النص
      if (content.trim().isEmpty) {
        final self = c['self'];
        if (self is Map &&
            (self['displayValue'] ?? '').toString().trim().isNotEmpty) {
          content = self['displayValue'].toString();
        }
      }
      // دعم الحقول القديمة
      if (content.trim().isEmpty) {
        content = (c['content'] ?? c['body'] ?? c['text'] ?? '').toString();
      }
      // المؤلف من createdBy.displayValue
      final createdBy = c['createdBy'];
      if (createdBy is Map &&
          (createdBy['displayValue'] ?? '').toString().trim().isNotEmpty) {
        author = createdBy['displayValue'].toString();
      }
      if (author.trim().isEmpty) {
        author = (c['author'] is Map)
            ? (c['author']['displayValue'] ?? c['author']['name'] ?? '')
                .toString()
            : (c['author'] ?? c['user'] ?? '').toString();
      }
      created = (c['createdAt'] ?? c['date'] ?? '').toString();
    } else {
      content = c.toString();
    }
    // تنسيق التاريخ إذا أمكن
    String formattedCreated = created;
    if (created.isNotEmpty) {
      try {
        final dt = DateTime.parse(created).toLocal();
        formattedCreated =
            '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, size: 16, color: Colors.indigo),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  author.isEmpty ? 'غير معروف' : author,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
              if (formattedCreated.isNotEmpty)
                Text(
                  formattedCreated,
                  style: const TextStyle(fontSize: 10.5, color: Colors.black54),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            content.isEmpty ? 'بدون محتوى' : content,
            style: const TextStyle(fontSize: 13),
            textAlign: TextAlign.start,
          ),
        ],
      ),
    );
  }

  // بطاقة مجموعة
  Widget _buildGroupCard({
    required String heading,
    required List<Widget> rows,
    Color? startColor,
    Color? endColor,
    bool compact = false,
    List<Widget>? actions,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10, vertical: compact ? 6 : 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (startColor ?? Colors.blue.shade50),
            (endColor ?? Colors.blue.shade100),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12, width: compact ? 0.7 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: compact ? 6 : 10,
            offset: Offset(0, compact ? 2 : 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_open,
                  size: compact ? 16 : 18, color: Colors.black54),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  heading,
                  style: TextStyle(
                    fontSize: compact ? 14.2 : 15.5,
                    fontWeight: compact ? FontWeight.w700 : FontWeight.w800,
                    color: Colors.black87,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (actions != null) ...[
                const SizedBox(width: 4),
                ...actions.map((w) =>
                    Padding(padding: const EdgeInsets.only(left: 4), child: w)),
              ],
            ],
          ),
          SizedBox(height: compact ? 4 : 6),
          ...rows,
        ],
      ),
    );
  }

  // نسخة مضغوطة لصف المعلومات
  Widget _buildInfoRowCompact({
    required IconData icon,
    required String label,
    required String value,
    Color? iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12, width: 0.6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: (iconColor ?? Colors.indigo).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: iconColor ?? Colors.indigo),
          ),
          SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                    fontSize: 12.6,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    height: 1.18),
                children: [
                  TextSpan(
                      text: '$label: ',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: value),
                ],
              ),
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }

  // صف لعرض مؤشر في الحوار السفلي
  // تم حذف _metricRow بعد إزالة زر مؤشرات SLA

  // صف معلومات
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? iconColor,
    bool showCopyButton = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.symmetric(horizontal: kRowHPad, vertical: kRowVPad),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12, width: 0.7),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: (iconColor ?? Colors.indigo).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon,
                size: kIconSizeInfo, color: iconColor ?? Colors.indigo),
          ),
          SizedBox(width: kInlineGap),
          Expanded(
            child: SelectionArea(
              // يجعل النص قابلاً للتحديد بدون تغيير التصميم أو الارتفاع
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                      fontSize: kValueFont,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      height: 1.30),
                  children: [
                    TextSpan(
                        text: '$label: ',
                        style: TextStyle(
                            fontSize: kLabelFont,
                            fontWeight: FontWeight.w800,
                            height: 1.25)),
                    TextSpan(text: value),
                  ],
                ),
                maxLines: 5,
              ),
            ),
          ),
          if (showCopyButton) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'نسخ',
              child: InkWell(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم نسخ "$value"'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12, width: 0.6),
                  ),
                  child:
                      const Icon(Icons.copy, size: 18, color: Colors.black87),
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildAppBarAction({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
    String? tooltip,
    double iconSize = 22,
    double boxSize = 46,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: boxSize,
          height: boxSize,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: .95), color.withValues(alpha: .70)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: .35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(color: Colors.white.withValues(alpha: .55), width: 1),
          ),
          child: Tooltip(
            message: tooltip ?? '',
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ),
      ),
    );
  }

  Widget _buildBackAction(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, top: 8, bottom: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(10),
          splashColor: Colors.black.withValues(alpha: .08),
          highlightColor: Colors.black.withValues(alpha: .04),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Icon(Icons.arrow_back_ios_new,
                  size: 20, color: Colors.black.withValues(alpha: .80)),
            ),
          ),
        ),
      ),
    );
  }

  // مجموعة الأزرار في الجهة اليسرى (عودة + تحديث)
  Widget _buildLeadingActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildBackAction(context),
        // زيادة المسافة بين زر الرجوع وزر التحديث بناءً على طلب المستخدم
        const SizedBox(width: 18),
        // زر التحديث مبسط بجانب العودة
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 8, bottom: 8),
          child: Material(
            color: Colors.blue.withValues(alpha: .60),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تحديث الصفحة!')),
                );
              },
              borderRadius: BorderRadius.circular(10),
              splashColor: Colors.white.withValues(alpha: .15),
              child: SizedBox(
                // تصغير زر التحديث حسب طلب المستخدم
                width: 34,
                height: 34,
                child: const Icon(Icons.refresh, size: 18, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // بطاقة SLA أعلى الصفحة
  Widget _buildSlaCard({
    required String categoryName,
    required String target,
    required String elapsed,
    required String remaining,
    required String slaStatus,
    required double progress,
  }) {
    final bool breached = slaStatus == 'متجاوز';
    final bool warning =
        !breached && progress >= 0.75; // اقترب من الانتهاء (تبقى <=25%)
    final Color mainColor = breached
        ? Colors.red.shade600
        : warning
            ? Colors.orange.shade700
            : Colors.green.shade600;
    final Color lightColor = breached
        ? Colors.red.shade100
        : warning
            ? Colors.orange.shade100
            : Colors.green.shade100;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 10), // تقليل الحشو
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [lightColor, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: mainColor.withValues(alpha: .45), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: mainColor.withValues(alpha: .18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6), // تقليل مساحة الأيقونة
                decoration: BoxDecoration(
                  color: mainColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.timer_outlined,
                    color: mainColor, size: 20), // تصغير الأيقونة
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'مؤشر SLA ($slaStatus)',
                  style: TextStyle(
                    fontSize: kSlaTitleFont - 3, // تصغير الخط
                    fontWeight: FontWeight.w800,
                    color: mainColor,
                    letterSpacing: .4,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 5), // تصغير الشارة
                decoration: BoxDecoration(
                  color: mainColor.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(30),
                  border:
                      Border.all(color: mainColor.withValues(alpha: .35), width: .8),
                ),
                child: Text(
                  categoryName,
                  style: TextStyle(
                      fontSize: kSlaTagFont - 2, // تصغير خط الشارة
                      fontWeight: FontWeight.w700,
                      color: mainColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8), // تقليل الفراغ
          _slaLine('الهدف', target, Icons.flag, mainColor),
          _slaLine('المنقضي', elapsed, Icons.timelapse, Colors.indigo.shade600),
          _slaLine(
              'المتبقي',
              remaining,
              Icons.hourglass_bottom,
              breached
                  ? Colors.red.shade700
                  : (warning ? Colors.orange.shade800 : Colors.teal.shade700)),
          const SizedBox(height: 6), // تقليل الفراغ قبل الشريط
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              minHeight: kSlaProgressHeight,
              value: progress,
              backgroundColor: mainColor.withValues(alpha: .18),
              valueColor: AlwaysStoppedAnimation<Color>(
                  breached ? Colors.red.shade400 : mainColor),
            ),
          ),
          const SizedBox(height: 4), // تقليل الفراغ بعد الشريط
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0%',
                  style:
                      TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
              Text('${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: mainColor)),
              const Text('100%',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _slaLine(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4), // تقليل المسافة بين الأسطر
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style:
                  const TextStyle(fontSize: 13.2, fontWeight: FontWeight.w800),
            ),
          ),
          SelectableText(
            value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color.darken()),
          ),
        ],
      ),
    );
  }
}

// لون حسب الزمن المتبقي كنسبة:
// تم حذف _colorForRemaining بعد إزالة زر مؤشرات SLA

// امتداد مبسط لتغميق لون
extension _ColorShade on Color {
  Color darken([double amount = .18]) {
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}
