/// اسم الصفحة: تفاصيل التذكرة
/// وصف الصفحة: صفحة تفاصيل تذكرة دعم فني محددة
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart'; // لاستخدام Clipboard
import '../../services/auth_service.dart';
import '../../task/add_task_api_dialog.dart'; // تأكد من استيراد صفحة AddTaskApiDialog
// import 'utils/status_translator.dart'; // لم يعد مستخدماً بعد إخفاء زر مؤشرات SLA
import 'package:url_launcher/url_launcher.dart'; // لفتح رابط التذكرة في المتصفح
import '../auth/auth_error_handler.dart';

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
  // بيانات إضافية للمشترك (هاتف، FBG، FAT)
  String _customerPhone = '';
  String _fbgValue = '';
  String _fatValue = '';
  bool _loadingExtraInfo = true;
  // حالة التعليقات
  bool _loadingComments = false;
  String? _commentsError;
  List<dynamic> _comments = [];
  bool _commentsFetched = false; // حتى لا نعيد الجلب دون طلب المستخدم
  bool _commentsVisible = false; // التحكم في إظهار/إخفاء التعليقات بعد الجلب
  bool _postingComment = false;
  final TextEditingController _commentController = TextEditingController();
  int _commentsTotalCount = 0; // العدد الكلي من الخادم

  // أحجام متجاوبة — تُحسب في build() حسب حجم الشاشة
  late double kLabelFont;
  late double kValueFont;
  late double kIconSizeInfo;
  late double kRowHPad;
  late double kRowVPad;
  late double kInlineGap;

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
    _fetchExtraCustomerInfo();
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

  /// جلب بيانات إضافية عن المشترك (الهاتف، FBG، FAT)
  Future<void> _fetchExtraCustomerInfo() async {
    if (widget.authToken == null) return;
    final tktat = widget.tktat;
    if (tktat is! Map) return;

    // استخراج معرف المشترك
    String? customerId;
    final customerObj = tktat['customer'];
    if (customerObj is Map && customerObj['id'] != null) {
      customerId = customerObj['id'].toString();
    } else if (tktat['customerId'] != null) {
      customerId = tktat['customerId'].toString();
    } else if (tktat['userId'] != null) {
      customerId = tktat['userId'].toString();
    }

    if (customerId == null || customerId.isEmpty) return;

    // 1) جلب بيانات المشترك (رقم الهاتف)
    try {
      final r = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/customers/$customerId',
        headers: {'Accept': 'application/json'},
      );
      if (r.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      }
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final model = (data is Map ? (data['model'] ?? data) : data);
        if (model is Map) {
          final pc = model['primaryContact'];
          if (pc is Map) {
            final mobile = pc['mobile']?.toString() ?? '';
            if (mobile.isNotEmpty && mounted) {
              setState(() => _customerPhone = mobile);
            }
          }
        }
      }
    } catch (_) {}

    // 2) جلب بيانات الاشتراك (FBG, FAT)
    try {
      final r = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/customers/subscriptions?customerId=$customerId',
        headers: {'Accept': 'application/json'},
      );
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final items = data['items'] as List?;
        if (items != null && items.isNotEmpty) {
          final sub = items.first;
          if (sub is Map) {
            final dd = sub['deviceDetails'];
            if (dd is Map) {
              final fbg = dd['fbg'];
              if (fbg is Map) {
                _fbgValue = fbg['displayValue']?.toString() ?? '';
              }
              final fat = dd['fat'];
              if (fat is Map) {
                _fatValue = fat['displayValue']?.toString() ?? '';
              }
            }
          }
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _loadingExtraInfo = false);
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
    // حساب الأحجام نسبياً من ارتفاع الشاشة لتملأ المساحة
    final screenH = MediaQuery.of(context).size.height;
    // معامل التحجيم: 1.0 عند 800px، يزيد مع الشاشات الأكبر
    final double s = (screenH / 800).clamp(0.85, 1.5);

    kLabelFont = 14.0 * s;
    kValueFont = 14.0 * s;
    kIconSizeInfo = 17.0 * s;
    kRowHPad = 12.0 * s;
    kRowVPad = 6.0 * s;
    kInlineGap = 8.0 * s;

    final double cardPadH = 10.0 * s;
    final double cardPadV = 8.0 * s;
    final double headingFont = 15.0 * s;
    final double headingIconSize = 17.0 * s;
    final double gapBetweenCards = 8.0 * s;
    final double bodyPadH = 14.0 * s;
    final double bodyPadV = 10.0 * s;
    final double rowMarginBottom = 5.0 * s;

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
              icon: Icons.copy_all,
              color: Colors.amber,
              tooltip: 'نسخ معلومات التذكرة والمشترك',
              iconSize: 28,
              boxSize: 50,
              onTap: () {
                final lines = <String>[
                  '--- معلومات التذكرة ---',
                  'رقم التذكرة: $ticketNumber',
                  'العنوان: $title',
                  'الخلاصة: $summary',
                  '',
                  '--- معلومات المشترك ---',
                  'العميل: $customer',
                  'رقم الهاتف: ${_customerPhone.isNotEmpty ? _customerPhone : 'غير متوفر'}',
                  'FBG: $zone',
                  'FAT: ${_fatValue.isNotEmpty ? _fatValue : 'غير متوفر'}',
                ];
                Clipboard.setData(ClipboardData(text: lines.join('\n')));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ المعلومات')),
                );
              },
            ),
            const SizedBox(width: 8),
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
                  builder: (context) => AddTaskApiDialog(
                    currentUsername: 'اسم المستخدم',
                    currentUserRole: 'Admin',
                    currentUserDepartment: 'FTTH',
                    initialNotes:
                        combinedText, // تمرير المعلومات إلى حقل الملاحظات
                    onTaskCreated: (Map<String, dynamic> data) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم إضافة المهمة بنجاح')),
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
          padding: EdgeInsets.symmetric(horizontal: bodyPadH, vertical: bodyPadV),
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // بطاقة SLA المختصرة
                _buildSlaCard(
                  categoryName: _categoryName,
                  target: targetStr,
                  elapsed: elapsedVerbose,
                  remaining: remainingVerbose,
                  slaStatus: slaStatus,
                  progress: _targetSla.inSeconds == 0
                      ? 0
                      : (elapsed.inSeconds / _targetSla.inSeconds).clamp(0, 1),
                ),
                SizedBox(height: gapBetweenCards),
                // المجموعة 1: معلومات التذكرة
                _buildGroupCard(
                  heading: 'معلومات التذكرة',
                  startColor: Colors.blue.shade50,
                  endColor: Colors.blue.shade100,
                  cardPadH: cardPadH, cardPadV: cardPadV,
                  headingFont: headingFont, headingIconSize: headingIconSize,
                  rows: [
                    _buildInfoRow(
                        icon: Icons.confirmation_number,
                        label: 'رقم التذكرة',
                        value: ticketNumber,
                        iconColor: Colors.indigo,
                        rowMargin: rowMarginBottom),
                    _buildInfoRow(
                        icon: Icons.title,
                        label: 'العنوان',
                        value: title,
                        iconColor: Colors.blue,
                        rowMargin: rowMarginBottom),
                    _buildInfoRow(
                        icon: Icons.description,
                        label: 'الخلاصة',
                        value: summary,
                        iconColor: Colors.teal,
                        rowMargin: rowMarginBottom),
                  ],
                ),
                SizedBox(height: gapBetweenCards),
                // المجموعة 2: معلومات المشترك
                _buildGroupCard(
                  heading: 'معلومات المشترك',
                  startColor: Colors.orange.shade50,
                  endColor: Colors.orange.shade100,
                  cardPadH: cardPadH, cardPadV: cardPadV,
                  headingFont: headingFont, headingIconSize: headingIconSize,
                  rows: [
                    _buildInfoRow(
                        icon: Icons.person,
                        label: 'العميل',
                        value: customer,
                        iconColor: Colors.orange,
                        showCopyButton: true,
                        rowMargin: rowMarginBottom),
                    _buildInfoRow(
                        icon: Icons.badge,
                        label: 'معرف المستخدم',
                        value: userId,
                        iconColor: Colors.deepOrange,
                        rowMargin: rowMarginBottom),
                    _buildInfoRow(
                        icon: Icons.phone,
                        label: 'رقم الهاتف',
                        value: _loadingExtraInfo
                            ? 'جاري التحميل...'
                            : (_customerPhone.isNotEmpty
                                ? _customerPhone
                                : 'غير متوفر'),
                        iconColor: Colors.green,
                        showCopyButton: _customerPhone.isNotEmpty,
                        rowMargin: rowMarginBottom),
                    _buildInfoRow(
                        icon: Icons.router,
                        label: 'FBG',
                        value: zone,
                        iconColor: Colors.teal,
                        rowMargin: rowMarginBottom),
                    _buildInfoRow(
                        icon: Icons.cable,
                        label: 'FAT',
                        value: _loadingExtraInfo
                            ? 'جاري التحميل...'
                            : (_fatValue.isNotEmpty
                                ? _fatValue
                                : 'غير متوفر'),
                        iconColor: Colors.indigo,
                        rowMargin: rowMarginBottom),
                  ],
                ),
                SizedBox(height: gapBetweenCards),
                // المجموعة 3: معلومات أخرى
                _buildGroupCard(
                  heading: 'معلومات أخرى',
                  startColor: Colors.green.shade50,
                  endColor: Colors.green.shade100,
                  compact: true,
                  cardPadH: cardPadH, cardPadV: cardPadV,
                  headingFont: headingFont, headingIconSize: headingIconSize,
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
                      padding: const EdgeInsets.only(top: 2),
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
                Text('الرسالة'),
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
          SnackBar(content: Text('خطأ أثناء فتح الرابط')),
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
      final url =
          'https://admin.ftth.iq/api/support/tickets/$ticketGuid/comments?pageSize=10&pageNumber=1';
      final resp = await AuthService.instance.authenticatedRequest(
        'GET',
        url,
        headers: {'Accept': 'application/json'},
      );
      if (resp.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      }
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
        _commentsError = 'خطأ';
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
      final url =
          'https://admin.ftth.iq/api/support/tickets/$ticketGuid/comments';
      final body = jsonEncode({
        'body': text,
        'ticketId': ticketGuid,
      });
      final resp = await AuthService.instance.authenticatedRequest(
        'POST',
        url,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (resp.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      }
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
          .showSnackBar(SnackBar(content: Text('خطأ أثناء الإرسال')));
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
    double cardPadH = 10,
    double cardPadV = 6,
    double headingFont = 15,
    double headingIconSize = 17,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: cardPadH, vertical: cardPadV),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (startColor ?? Colors.blue.shade50),
            (endColor ?? Colors.blue.shade100),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_open, size: headingIconSize, color: Colors.black54),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  heading,
                  style: TextStyle(
                    fontSize: headingFont,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (actions != null)
                ...actions.map((w) =>
                    Padding(padding: const EdgeInsets.only(left: 4), child: w)),
            ],
          ),
          const SizedBox(height: 2),
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
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black12, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: iconColor ?? Colors.indigo),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    height: 1.15),
                children: [
                  TextSpan(
                      text: '$label: ',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: value),
                ],
              ),
              maxLines: 2,
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
    double rowMargin = 4,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: rowMargin),
      padding: EdgeInsets.symmetric(horizontal: kRowHPad, vertical: kRowVPad),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black12, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: kIconSizeInfo, color: iconColor ?? Colors.indigo),
          SizedBox(width: kInlineGap),
          Expanded(
            child: SelectionArea(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                      fontSize: kValueFont,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      height: 1.15),
                  children: [
                    TextSpan(
                        text: '$label: ',
                        style: TextStyle(
                            fontSize: kLabelFont,
                            fontWeight: FontWeight.w800)),
                    TextSpan(text: value),
                  ],
                ),
                maxLines: 3,
              ),
            ),
          ),
          if (showCopyButton)
            InkWell(
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
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy, size: 14, color: Colors.black54),
              ),
            ),
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
              colors: [
                color.withValues(alpha: .95),
                color.withValues(alpha: .70)
              ],
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
            border: Border.all(
                color: Colors.white.withValues(alpha: .55), width: 1),
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
    final bool warning = !breached && progress >= 0.75;
    final Color mainColor = breached
        ? Colors.red.shade600
        : warning
            ? Colors.orange.shade700
            : Colors.green.shade600;
    final pct = '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: mainColor.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mainColor.withValues(alpha: .3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, color: mainColor, size: 18),
              const SizedBox(width: 6),
              Text('SLA', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: mainColor)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: mainColor.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(slaStatus, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: mainColor)),
              ),
              if (categoryName.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(categoryName, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
              const Spacer(),
              Text('المنقضي: $elapsed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: progress,
                    backgroundColor: mainColor.withValues(alpha: .15),
                    valueColor: AlwaysStoppedAnimation<Color>(mainColor),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(pct, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: mainColor)),
            ],
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
