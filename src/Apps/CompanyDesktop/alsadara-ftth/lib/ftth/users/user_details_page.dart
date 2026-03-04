/// اسم الصفحة: تفاصيل المستخدم
/// وصف الصفحة: صفحة تفاصيل مستخدم محدد
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../subscriptions/subscription_details_page.dart';
// إضافة زر فتح نافذة إضافة مهمة
import '../../task/add_task_api_dialog.dart';
import '../tickets/customer_tickets_page.dart';
import '../reports/audit_log_page.dart';

// أنماط نص موحدة مختصرة
class _TextStyles {
  static const TextStyle appBarTitle =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white);
  static const TextStyle sectionHeader =
      TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue);
}

class UserDetailsPage extends StatefulWidget {
  final String userId;
  final String userName;
  final String userPhone;
  final String authToken;
  final String activatedBy;
  final bool hasServerSavePermission;
  final bool hasWhatsAppPermission;
  // صلاحيات النظام الأول (للتأكد من إظهار زر إضافة مهمة فقط للمدير/ليدر)
  final String? firstSystemPermissions;
  // علم إداري صريح يتم تمريره من الصفحة الرئيسية إذا كان المستخدم مديرا
  final bool? isAdminFlag;
  // تمرير القسم / المركز / الراتب من النظام الأول عند الحاجة
  final String? firstSystemDepartment;
  final String? firstSystemCenter;
  final String? firstSystemSalary;
  // تمرير جميع صلاحيات نظام FTTH (الخريطة المحلية) إن وُجدت
  final Map<String, bool>? ftthPermissions;
  // رؤوس إضافية لازمة لبعض واجهات الـ API (مثل سجل التدقيق)
  final String? userRoleHeader; // مثال: hierarchyLevel أو قيمة الدور الفعلية
  final String? clientAppHeader; // معرف التطبيق الثابت
  // قائمة الصلاحيات المهمة (مفلترة) القادمة من الصفحة الرئيسية
  final List<String>? importantFtthApiPermissions;
  const UserDetailsPage(
      {super.key,
      required this.userId,
      required this.userName,
      required this.userPhone,
      required this.authToken,
      required this.activatedBy,
      this.hasServerSavePermission = false,
      this.hasWhatsAppPermission = false,
      this.firstSystemPermissions,
      this.isAdminFlag,
      this.firstSystemDepartment,
      this.firstSystemCenter,
      this.firstSystemSalary,
      this.ftthPermissions,
      this.userRoleHeader,
      this.clientAppHeader,
      this.importantFtthApiPermissions});
  @override
  UserDetailsPageState createState() => UserDetailsPageState();
}

class UserDetailsPageState extends State<UserDetailsPage> {
  Map<String, dynamic>? subscriptionDetails;
  List<Map<String, dynamic>> _allSubscriptions = [];
  int _selectedSubscriptionIndex = 0;
  Map<String, dynamic>? deviceOntInfo;
  Map<String, dynamic>? _customerDataMain;
  String _resolvedPhone = ''; // رقم الهاتف المُحلَّل
  bool _isFetchingPhone = false; // جاري جلب الهاتف
  bool isLoading = true;
  bool isLoadingOntInfo = false;
  String errorMessage = '';
  String ontErrorMessage = '';
  final bool _compactMode = true;
  // تم استبدال عرض التذاكر في حوار بصفحة مستقلة CustomerTicketsPage

  @override
  void initState() {
    super.initState();
    fetchDetails();
    _fetchAndStoreCustomerDetails();
  }

  // يسمح بإضافة مهمة إذا تحقق أحد الشروط: isAdminFlag أو نص الصلاحيات يحتوي مفاتيح إدارية
  bool get _canAddTask {
    if (widget.isAdminFlag == true) {
      debugPrint('[UserDetailsPage] isAdminFlag=true => السماح بزر المهمة');
      return true;
    }
    final raw = widget.firstSystemPermissions ?? '';
    final perms = raw.toLowerCase().replaceAll(RegExp(r'[\s_]+'), ' ');
    if (perms.isEmpty) {
      debugPrint(
          '[UserDetailsPage] لا توجد صلاحيات نصية ولا isAdminFlag => إخفاء زر المهمة');
      return false;
    }
    final tokens = [
      'مدير',
      'ليدر',
    ];
    final allowed = tokens.any((t) {
      final tt = t.toLowerCase();
      return perms.contains(tt);
    });
    debugPrint(
        '[UserDetailsPage] فحص زر المهمة - raw:"$raw" => normalized:"$perms" allowed=$allowed');
    return allowed;
  }

  // Responsive helpers
  bool _isMobile(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final platform = defaultTargetPlatform;
    final platformMobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    return w < 700 || platformMobile;
  }

  ButtonStyle _renewButtonStyle(BuildContext context) {
    final c = _compactMode;
    final isMobile = _isMobile(context);
    final double fontSize = isMobile ? 16 : (c ? 18 : 20);
    final double vPad = isMobile ? 10 : (c ? 14 : 16);
    final double hPad = isMobile ? 20 : (c ? 28 : 36);
    final Size minSize =
        Size(isMobile ? 160 : (c ? 200 : 240), isMobile ? 44 : (c ? 52 : 58));
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.green,
      foregroundColor: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      minimumSize: minSize,
      textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: isMobile
          ? const VisualDensity(horizontal: -1, vertical: -1)
          : VisualDensity.standard,
    );
  }

  // ---------------- API -----------------
  Future<void> fetchDetails() async {
    try {
      final r = await http.get(
          Uri.parse(
              'https://admin.ftth.iq/api/customers/subscriptions?customerId=${widget.userId}'),
          headers: {
            'Authorization': 'Bearer ${widget.authToken}',
            'Accept': 'application/json'
          });
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final items = data['items'] as List?;
        debugPrint('[fetchDetails] keys=${data.keys.toList()} totalCount=${data['totalCount']} itemsCount=${items?.length}');
        if (mounted) {
          setState(() {
            _allSubscriptions =
                items?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
            _selectedSubscriptionIndex = 0;
            subscriptionDetails =
                (_allSubscriptions.isNotEmpty) ? _allSubscriptions.first : null;
          });
        }
      } else if (mounted) {
        setState(
            () => errorMessage = 'فشل جلب بيانات الاشتراك: ${r.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => errorMessage = 'خطأ: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
        if (subscriptionDetails != null) {
          fetchDeviceOntInfo();
          final id = _extractSubscriptionId(subscriptionDetails!);
          if (id != null && id.isNotEmpty) fetchFullSubscriptionDetails(id);
        }
      }
    }
  }

  Future<void> fetchFullSubscriptionDetails(String id) async {
    try {
      final r = await http.get(
          Uri.parse('https://admin.ftth.iq/api/subscriptions/$id'),
          headers: {
            'Authorization': 'Bearer ${widget.authToken}',
            'Accept': 'application/json'
          });
      if (r.statusCode == 200 && mounted && subscriptionDetails != null) {
        final full = jsonDecode(r.body);
        final merged = Map<String, dynamic>.from({...subscriptionDetails!, ...full});
        setState(() {
          subscriptionDetails = merged;
          // تحديث _allSubscriptions[i] بالبيانات الكاملة حتى لا تُفقد عند التبديل بين الاشتراكات
          if (_selectedSubscriptionIndex < _allSubscriptions.length) {
            _allSubscriptions[_selectedSubscriptionIndex] = Map<String, dynamic>.from(merged);
          }
        });
      }
    } catch (_) {}
  }

  void fetchUserDetailsAndSubscription() {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = '';
      ontErrorMessage = '';
      deviceOntInfo = null;
      _allSubscriptions = [];
      _selectedSubscriptionIndex = 0;
    });
    fetchDetails();
  }

  Future<void> fetchDeviceOntInfo() async {
    if (subscriptionDetails == null) return;
    final deviceDetails = _safeGetMap(subscriptionDetails!['deviceDetails']);
    final username = _safeGetString(deviceDetails?['username']);
    if (username == null || username.trim().isEmpty) {
      if (mounted) {
        setState(() => ontErrorMessage = 'اسم المستخدم للجهاز غير متوفر');
      }
      return;
    }
    if (mounted) {
      setState(() {
        isLoadingOntInfo = true;
        ontErrorMessage = '';
        deviceOntInfo = null;
      });
    }
    try {
      final r = await http.get(
          Uri.parse(
              'https://admin.ftth.iq/api/subscriptions/device/ont?username=${username.trim()}'),
          headers: {
            'Authorization': 'Bearer ${widget.authToken}',
            'Accept': 'application/json'
          });
      if (!mounted) return;
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        setState(() {
          deviceOntInfo = data;
          isLoadingOntInfo = false;
        });
      } else {
        setState(() {
          ontErrorMessage = 'فشل جلب معلومات الجهاز: ${r.statusCode}';
          isLoadingOntInfo = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          ontErrorMessage = 'خطأ: $e';
          isLoadingOntInfo = false;
        });
      }
    }
  }

  Future<void> _fetchAndStoreCustomerDetails() async {
    final data = await _fetchCustomerDetails();
    if (!mounted) return;
    if (data != null) {
      setState(() {
        _customerDataMain = data;
        _resolvedPhone = _extractPhoneFromData(data, null);
      });
    }
  }

  /// استخراج رقم الهاتف من كل الحقول الممكنة
  String _extractPhoneFromData(
      Map<String, dynamic>? customerData, Map<String, dynamic>? subData) {
    String? check(dynamic v) {
      final s = v?.toString().trim();
      return (s != null && s.isNotEmpty && s != 'null') ? s : null;
    }

    return check(customerData?['primaryContact']?['mobile']) ??
        check(customerData?['phone']) ??
        check(customerData?['phoneNumber']) ??
        check(customerData?['mobilePhone']) ??
        check(subData?['customerPhone']) ??
        check(subData?['phoneNumber']) ??
        check(subData?['phone']) ??
        check(subData?['customer']?['phone']) ??
        check(subData?['customer']?['mobile']) ??
        (widget.userPhone != 'غير متوفر' ? check(widget.userPhone) : null) ??
        '';
  }

  /// جلب رقم الهاتف يدوياً عند الضغط على الزر
  Future<void> _fetchPhoneManually() async {
    if (_isFetchingPhone) return;
    setState(() => _isFetchingPhone = true);
    try {
      final data = await _fetchCustomerDetails();
      if (!mounted) return;
      setState(() {
        if (data != null) _customerDataMain = data;
        _resolvedPhone = _extractPhoneFromData(
            data ?? _customerDataMain, subscriptionDetails);
        _isFetchingPhone = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isFetchingPhone = false);
    }
  }

  // ---------------- Helpers -----------------
  String? _safeGetString(dynamic v) => v?.toString();
  Map<String, dynamic>? _safeGetMap(dynamic v) =>
      v is Map<String, dynamic> ? v : null;
  List<dynamic>? _safeGetList(dynamic v) => v is List<dynamic> ? v : null;
  String? _extractSubscriptionId(Map<String, dynamic> d) {
    for (final k in ['id', 'subscriptionId', 'subscription_id', 'subId']) {
      final v = _safeGetString(d[k]);
      if (v != null && v.isNotEmpty) return v;
    }
    final self = _safeGetMap(d['self']);
    final sid = _safeGetString(self?['id']);
    return (sid != null && sid.isNotEmpty) ? sid : null;
  }

  int _days(String? end) {
    if (end == null || end.isEmpty) return 0;
    try {
      return DateTime.parse(end).difference(DateTime.now()).inDays;
    } catch (_) {
      return 0;
    }
  }

  Color _daysColor(int d) {
    if (d > 0) return Colors.green;
    if (d < 0) return Colors.red;
    return Colors.orange;
  }

  int? _durationDays(String? start, String? end) {
    if (start == null || start.isEmpty || end == null || end.isEmpty) {
      return null;
    }
    try {
      final s = DateTime.parse(start);
      final e = DateTime.parse(end);
      return e.difference(s).inDays.abs();
    } catch (_) {
      return null;
    }
  }

  Widget _metricTile(
    IconData icon,
    String label,
    String value, {
    Color? accent,
    bool highlightBg = false,
    double? labelFontSize,
    double? valueFontSize,
    int valueMaxLines = 1,
  }) {
    final color = accent ?? Colors.blueGrey;
    // Darker look when highlighted (e.g., Active)
    final Color bgColor =
        highlightBg ? color.withValues(alpha: 0.16) : Colors.grey.shade50;
    final Color brColor =
        highlightBg ? color.withValues(alpha: 0.40) : Colors.grey.shade200;
    final Color iconBg = highlightBg
        ? color.withValues(alpha: 0.22)
        : color.withValues(alpha: 0.12);
    final bool isMobile = _isMobile(context);
    final double lblSize = labelFontSize ?? (isMobile ? 11 : 12);
    final double valSize = valueFontSize ?? (isMobile ? 13 : 14);
    return Container(
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: brColor),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: iconBg, borderRadius: BorderRadius.circular(6)),
            child: Icon(icon, size: 16, color: color)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: lblSize,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: valueMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: valSize, fontWeight: FontWeight.w700)),
              ]),
        )
      ]),
    );
  }

  Widget _twoPerRowGrid(List<Widget> tiles) {
    if (tiles.isEmpty) return const SizedBox();
    final double width = MediaQuery.of(context).size.width;
    // On very small phones, use a single column for better readability.
    final bool singleColumn = width < 380;
    if (singleColumn) {
      return Column(
        children: [
          for (int i = 0; i < tiles.length; i++) ...[
            tiles[i],
            if (i + 1 < tiles.length) const SizedBox(height: 8),
          ],
        ],
      );
    }
    final children = <Widget>[];
    for (int i = 0; i < tiles.length; i += 2) {
      final left = Expanded(child: tiles[i]);
      final right = (i + 1 < tiles.length)
          ? Expanded(child: tiles[i + 1])
          : const Expanded(child: SizedBox());
      children.add(Row(children: [left, const SizedBox(width: 8), right]));
      if (i + 2 < tiles.length) children.add(const SizedBox(height: 8));
    }
    return Column(children: children);
  }

  String _baseService(List<dynamic>? services) {
    if (services == null) return 'لا توجد خدمة أساسية';
    for (final s in services) {
      if (s is Map<String, dynamic>) {
        final t = _safeGetMap(s['type']);
        if (t != null && t['displayValue'] == 'Base') {
          return _safeGetString(s['displayValue']) ?? 'لا توجد';
        }
      }
    }
    return 'لا توجد خدمة أساسية';
  }

  String _fmtDate(String? d) {
    if (d == null || d.isEmpty) return 'غير محدد';
    return d.contains('T') ? d.split('T')[0] : d;
  }

  String _fmtDateTime(String? d) {
    if (d == null || d.isEmpty) return 'غير محدد';
    try {
      final dt = DateTime.parse(d);
      final date =
          '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      int h12 = dt.hour % 12;
      if (h12 == 0) h12 = 12;
      final hh = h12.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour < 12 ? 'ص' : 'م';
      return '$date $hh:$mm $period';
    } catch (_) {
      if (d.contains('T')) {
        final parts = d.split('T');
        final timePart = parts.length > 1 ? parts[1] : '';
        final core =
            timePart.split(RegExp(r'[Zz]|[+-]')).first; // strip zone/offset
        final hhmm = core.split(':');
        if (hhmm.length >= 2) {
          final h24 = int.tryParse(hhmm[0]) ?? 0;
          int h12 = h24 % 12;
          if (h12 == 0) h12 = 12;
          final hh = h12.toString().padLeft(2, '0');
          final mm = hhmm[1].padLeft(2, '0');
          final period = h24 < 12 ? 'ص' : 'م';
          return '${parts[0]} $hh:$mm $period';
        }
      }
      return _fmtDate(d);
    }
  }

  String _fmtPhone(String p) {
    var t = p.trim();
    if (t.isEmpty) return 'غير متوفر';
    t = t.replaceAll(RegExp(r'\s+'), '');
    if (t.startsWith('+')) return t; // already has country code
    if (t.startsWith('00')) return '+${t.substring(2)}';
    if (t.startsWith('964')) return '+$t';
    if (t.startsWith('0')) return '+964 ${t.substring(1)}';
    return '+964 $t';
  }

  String _fmtTime(int secs) {
    final h = (secs ~/ 3600).toString().padLeft(2, '0');
    final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // تحويل حالة الجهاز من up/down إلى شغال/طافي
  String _localizedDeviceStatus(String? raw) {
    if (raw == null || raw.isEmpty) return 'غير معروف';
    final v = raw.toLowerCase();
    if (v == 'up') return 'شغال';
    if (v == 'down') return 'طافي';
    return raw; // إن كانت قيمة أخرى نعيدها كما هي (قد تكون عربية بالفعل)
  }

  // تعريب حالة الاشتراك (Active, Inactive, Suspended, Expired, Pending ..)
  String _localizedSubscriptionStatus(String? raw) {
    if (raw == null || raw.isEmpty) return 'غير معروف';
    final v = raw.trim().toLowerCase();
    if (v == 'active' || v == 'connected' || v == 'متصل') return 'فعال';
    if (v == 'inactive' || v == 'disconnected' || v == 'غير فعال') {
      return 'غير فعال';
    }
    if (v == 'suspended' || v == 'hold') return 'معلق';
    if (v == 'expired') return 'منتهي';
    if (v == 'pending' || v == 'processing') return 'قيد المعالجة';
    if (v == 'blocked') return 'محظور';
    if (v == 'disabled') return 'معطل';
    if (v == 'canceled' || v == 'cancelled') return 'ملغى';
    return raw; // fallback
  }

  // Local display phone (starts with 07...)
  String _fmtPhoneLocal(String p) {
    var t = p.trim();
    if (t.isEmpty) return 'غير متوفر';
    t = t.replaceAll(RegExp(r'\s+'), '');
    if (t.startsWith('+964')) {
      t = t.substring(4);
    } else if (t.startsWith('00964'))
      t = t.substring(5);
    else if (t.startsWith('964')) t = t.substring(3);
    if (t.startsWith('0')) return t; // already local
    if (t.startsWith('7')) return '0$t';
    // fallback
    return '0$t';
  }

  // (Removed flexible nested getters; not used in current dialog)

  // ----------- FBG/FAT helpers -----------
  String? _extractFbgFromFdtDisplay(String? fdtDisplay) {
    if (fdtDisplay == null) return null;
    final re = RegExp(r'FBG[\w\d-]+');
    final m = re.firstMatch(fdtDisplay);
    return m?.group(0);
  }

  (String?, String?) _getFbgFat() {
    final dev = subscriptionDetails == null
        ? null
        : _safeGetMap(subscriptionDetails!['deviceDetails']);
    String? fbg = _safeGetString(_safeGetMap(dev?['fbg'])?['displayValue']);
    String? fat = _safeGetString(_safeGetMap(dev?['fat'])?['displayValue']);
    if ((fbg == null || fbg.isEmpty)) {
      final fdtDisp = _safeGetString(_safeGetMap(dev?['fdt'])?['displayValue']);
      fbg = _extractFbgFromFdtDisplay(fdtDisp);
    }
    return (fbg, fat);
  }

  // FBG/FAT are integrated as full tiles in subscription details

  // ---------------- UI Sections -----------------
  Widget _subscriptionDetails() {
    if (subscriptionDetails == null) return const SizedBox();
    final statusRaw = subscriptionDetails!['status'];
    final statusTxt = statusRaw is String
        ? statusRaw
        : _safeGetString(statusRaw?['displayValue']) ?? 'غير فعال';
    final normStatus = statusTxt.toString().trim().toLowerCase();
    final bool isActive = (normStatus == 'active' || normStatus == 'متصل');
    final String statusDisplay = isActive ? 'فعال' : 'غير فعال';
    final endDate = _safeGetString(subscriptionDetails!['endDate']) ??
        _safeGetString(subscriptionDetails!['expires']);
    final startedAt = _safeGetString(subscriptionDetails!['startedAt']) ??
        _safeGetString(subscriptionDetails!['startDate']);
    final services = _safeGetList(subscriptionDetails!['services']);
    final d = _days(endDate);
    final dc = _daysColor(d);
    // Darker accent for active/inactive
    final sc = isActive ? Colors.green.shade800 : Colors.red.shade800;
    final dur = _durationDays(startedAt, endDate);
    final fbgFat = _getFbgFat();
    final fbg = fbgFat.$1;
    final fat = fbgFat.$2;

    final tiles = <Widget>[];
    final bool isMobile = _isMobile(context);
    final double lblSize = isMobile ? 11 : 12;
    final double valSize = isMobile ? 13 : 14;
    final int valueLines = isMobile ? 2 : 1;

    tiles.add(_metricTile(
      isActive ? Icons.verified : Icons.error_outline,
      'الحالة',
      statusDisplay,
      accent: sc,
      labelFontSize: lblSize,
      valueFontSize: valSize,
      valueMaxLines: valueLines,
    ));
    tiles.add(_metricTile(
      Icons.category,
      'الحزمة',
      _baseService(services),
      labelFontSize: lblSize,
      valueFontSize: valSize,
      valueMaxLines: valueLines,
    ));
    if (fbg != null && fbg.isNotEmpty) {
      tiles.add(_metricTile(
        Icons.router,
        'FBG',
        fbg,
        labelFontSize: lblSize,
        valueFontSize: valSize,
        valueMaxLines: valueLines,
      ));
    }
    if (fat != null && fat.isNotEmpty) {
      tiles.add(_metricTile(
        Icons.hub,
        'FAT',
        fat,
        labelFontSize: lblSize,
        valueFontSize: valSize,
        valueMaxLines: valueLines,
      ));
    }
    if (startedAt != null && startedAt.isNotEmpty) {
      tiles.add(_metricTile(
        Icons.play_circle,
        'تاريخ البدء',
        _fmtDate(startedAt),
        labelFontSize: lblSize,
        valueFontSize: valSize,
        valueMaxLines: valueLines,
      ));
    }
    tiles.add(_metricTile(
      Icons.event,
      'تاريخ الانتهاء',
      _fmtDateTime(endDate),
      labelFontSize: lblSize,
      valueFontSize: valSize,
      valueMaxLines: valueLines,
    ));
    if (dur != null) {
      tiles.add(_metricTile(
        Icons.schedule,
        'مدة الاشتراك',
        '$dur يوم',
        labelFontSize: lblSize,
        valueFontSize: valSize,
        valueMaxLines: valueLines,
      ));
    }
    tiles.add(_metricTile(
      d > 0
          ? Icons.check_circle
          : (d < 0 ? Icons.warning_amber_rounded : Icons.schedule),
      d > 0 ? 'الأيام المتبقية' : (d < 0 ? 'منتهي منذ' : 'ينتهي اليوم'),
      d > 0 ? '$d يوم' : (d < 0 ? '${d.abs()} يوم' : 'اليوم'),
      accent: dc,
      labelFontSize: lblSize,
      valueFontSize: valSize,
      valueMaxLines: valueLines,
    ));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _twoPerRowGrid(tiles),
    ]);
  }

  Widget _deviceBox(Map<String, dynamic> dev) {
    return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    'اليوز نيم : ${_safeGetString(dev['username']) ?? 'غير متوفر'}',
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text('Serial: ${_safeGetString(dev['serial']) ?? 'غير متوفر'}',
                    overflow: TextOverflow.ellipsis),
              ])),
          const SizedBox(width: 8),
          ElevatedButton.icon(
              onPressed: () {
                if (subscriptionDetails == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('لا يمكن العثور على البيانات'),
                      backgroundColor: Colors.red));
                  return;
                }
                final id = _extractSubscriptionId(subscriptionDetails!);
                if (id == null || id.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('لا يمكن العثور على معرف الاشتراك'),
                      backgroundColor: Colors.red));
                  return;
                }
                final username = _safeGetString(dev['username']) ?? '';
                final serial = _safeGetString(dev['serial']) ?? '';
                final mac = _safeGetString(dev['macAddress']) ?? '';
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => EditDevicePage(
                            subscriptionId: id,
                            authToken: widget.authToken,
                            username: username,
                            serial: serial,
                            macAddress: mac))).then((_) {
                  fetchUserDetailsAndSubscription();
                });
              },
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('تعديل'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
              ))
        ]));
  }

  Widget _sessionBox(Map<String, dynamic> s) {
    final start = _fmtDate(_safeGetString(s['startedAt']));
    final duration = _fmtTime(
        int.tryParse(_safeGetString(s['sessionTimeInSeconds']) ?? '0') ?? 0);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.wifi, color: Colors.green.shade600, size: 15),
            const SizedBox(width: 6),
            const Text('الجلسة النشطة:',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.green)),
          ]),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade300)),
                    child: Text(start,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87)),
                  ),
                  const SizedBox(width: 24),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade300)),
                    child: Text(duration,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87)),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ontInfoSection() {
    if (isLoadingOntInfo) {
      return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (ontErrorMessage.isNotEmpty) {
      return _msgBox(ontErrorMessage, Colors.red, Icons.error_outline);
    }
    if (deviceOntInfo == null) {
      return _msgBox('لا توجد معلومات تقنية متاحة للجهاز', Colors.grey,
          Icons.info_outline);
    }
    final model = _safeGetMap(deviceOntInfo!['model']);
    final status = _safeGetMap(model?['status']);
    final rxPower = model?['rxPower'];
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.device_unknown;
    final rawStatusDisp = _safeGetString(status?['displayValue']);
    final statusVal = rawStatusDisp?.toLowerCase() ?? '';
    if (statusVal == 'up') {
      statusColor = Colors.green;
      statusIcon = Icons.signal_wifi_4_bar;
    } else if (statusVal == 'down') {
      statusColor = Colors.red;
      statusIcon = Icons.signal_wifi_off;
    }
    final localizedStatus = _localizedDeviceStatus(rawStatusDisp);
    Color powerColor = Colors.grey;
    String powerStatus = '';
    if (rxPower != null) {
      try {
        final p = double.parse(rxPower.toString());
        if (p >= -20) {
          powerColor = Colors.green;
          powerStatus = 'ممتازة';
        } else if (p >= -25) {
          powerColor = Colors.orange;
          powerStatus = 'جيدة';
        } else if (p >= -30) {
          powerColor = Colors.amber;
          powerStatus = 'متوسطة';
        } else {
          powerColor = Colors.red;
          powerStatus = 'ضعيفة';
        }
      } catch (_) {}
    }
    return Column(children: [
      Row(children: [
        Expanded(
            child: _statusTile(
                statusIcon, 'حالة الجهاز', localizedStatus, statusColor)),
        const SizedBox(width: 8),
        Expanded(
            child: _statusTile(null, 'قوة الإشارة',
                '${_safeGetString(rxPower) ?? 'غير معروف'} dBm', powerColor,
                badge: powerStatus)),
      ]),
      const SizedBox(height: 6),
      _hint(),
    ]);
  }

  Widget _statusTile(IconData? icon, String label, String value, Color c,
          {String? badge}) =>
      Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: c.withValues(alpha: .1),
              border: Border.all(color: c.withValues(alpha: .3)),
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            if (icon != null) ...[
              Icon(icon, color: c, size: 15),
              const SizedBox(width: 10)
            ],
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  Row(children: [
                    Text(value,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: c)),
                    if (badge != null && badge.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: c.withValues(alpha: .2),
                              borderRadius: BorderRadius.circular(12)),
                          child: Text(badge,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: c)))
                    ]
                  ])
                ]))
          ]));
  Widget _hint() => Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
      child: const Row(children: [
        Icon(Icons.info_outline, color: Colors.blue, size: 15),
        SizedBox(width: 6),
        Expanded(
            child: Text('قوة الإشارة الأفضل أعلى من -25 dBm',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue,
                    fontStyle: FontStyle.italic)))
      ]));
  Widget _msgBox(String msg, Color color, IconData icon) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          border: Border.all(color: color.withValues(alpha: .3)),
          borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 6),
        Expanded(child: Text(msg, style: TextStyle(color: color)))
      ]));

  // ---------------- Customer Details Dialog (Extra Info) -----------------
  Future<void> _showCustomerDetailsDialog() async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 3),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'جاري تحميل معلومات المشترك...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      final customerDetails = await _fetchCustomerDetails();
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading dialog
      if (customerDetails != null) {
        _showCustomerDetailsContent(customerDetails);
      } else {
        _showErrorDialog('فشل في تحميل معلومات المشترك');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showErrorDialog('حدث خطأ أثناء تحميل البيانات: $e');
    }
  }

  Future<Map<String, dynamic>?> _fetchCustomerDetails() async {
    try {
      final r = await http.get(
          Uri.parse('https://admin.ftth.iq/api/customers/${widget.userId}'),
          headers: {
            'Authorization': 'Bearer ${widget.authToken}',
            'Accept': 'application/json',
          });
      debugPrint('📞 [fetchCustomerDetails] status=${r.statusCode}');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        debugPrint('📞 [fetchCustomerDetails] keys=${data is Map<String,dynamic> ? data.keys.toList() : "NOT_MAP"}');
        if (data is Map<String, dynamic>) {
          final model = data['model'];
          debugPrint('📞 [fetchCustomerDetails] model keys=${model is Map<String,dynamic> ? model.keys.toList() : "NO_MODEL"}');
          if (model is Map<String, dynamic>) {
            debugPrint('📞 [fetchCustomerDetails] primaryContact=${model['primaryContact']}');
            return model;
          }
          debugPrint('📞 [fetchCustomerDetails] primaryContact=${data['primaryContact']}');
          return data;
        }
      } else {
        debugPrint('📞 [fetchCustomerDetails] body=${r.body.substring(0, r.body.length.clamp(0, 200))}');
      }
      return null;
    } catch (e) {
      debugPrint('📞 [fetchCustomerDetails] ERROR=$e');
      return null;
    }
  }

  void _showCustomerDetailsContent(Map<String, dynamic> customerData) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.92,
            height: MediaQuery.of(context).size.height * 0.85,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Colors.blue.shade600, Colors.blue.shade800]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(children: [
                    Icon(Icons.person_search, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text('معلومات تفصيلية عن المشترك',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold))),
                  ]),
                ),
                const SizedBox(height: 12),
                Expanded(
                    child: SingleChildScrollView(
                        child: _buildCustomerInfoSection(customerData))),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    label: const Text('إغلاق'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade600,
                        foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomerInfoSection(Map<String, dynamic> customerData) {
    final primaryContact = _safeGetMap(customerData['primaryContact']);
    final nationalIdCard = _safeGetMap(customerData['nationalIdCard']);
    final addresses = _safeGetList(customerData['addresses']);
    final customerType = _safeGetMap(customerData['customerType']);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildInfoCard('المعلومات الأساسية', [
        _buildDetailRow(
            'الاسم',
            _safeGetString(
                    _safeGetMap(customerData['self'])?['displayValue']) ??
                'غير متوفر',
            Icons.person),
        _buildDetailRow(
            'رقم الهاتف',
            _safeGetString(primaryContact?['mobile']) ?? 'غير متوفر',
            Icons.phone),
        _buildDetailRow(
            'البريد الإلكتروني',
            _safeGetString(primaryContact?['email']) ?? 'غير متوفر',
            Icons.email),
        _buildDetailRow(
            'اسم الأم',
            _safeGetString(customerData['motherName']) ?? 'غير متوفر',
            Icons.family_restroom),
        _buildDetailRow(
            'نوع العميل',
            _safeGetString(customerType?['displayValue']) ?? 'غير متوفر',
            Icons.category),
        _buildDetailRow(
            'رمز الإحالة',
            _safeGetString(customerData['usrReferralCode']) ?? 'غير متوفر',
            Icons.code),
      ]),
      const SizedBox(height: 12),
      if (nationalIdCard != null) ...[
        _buildInfoCard('بيانات الهوية الوطنية', [
          _buildDetailRow(
              'رقم الهوية',
              _safeGetString(nationalIdCard['idNumber']) ?? 'غير متوفر',
              Icons.badge),
          _buildDetailRow(
              'رقم العائلة',
              _safeGetString(nationalIdCard['familyNumber']) ?? 'غير متوفر',
              Icons.groups),
          _buildDetailRow(
              'مكان الإصدار',
              _safeGetString(nationalIdCard['placeOfIssue']) ?? 'غير متوفر',
              Icons.location_on),
          _buildDetailRow(
              'تاريخ الإصدار',
              _fmtDate(_safeGetString(nationalIdCard['issuedAt'])),
              Icons.date_range),
        ]),
        const SizedBox(height: 12),
      ],
      if (addresses != null && addresses.isNotEmpty) ...[
        _buildInfoCard('معلومات العنوان', [
          for (var address in addresses) ...[
            _buildDetailRow(
                'العنوان الكامل',
                _safeGetString(_safeGetMap(address)?['displayValue']) ??
                    'غير متوفر',
                Icons.location_city),
            _buildDetailRow(
                'المحافظة',
                _safeGetString(
                        _safeGetMap(_safeGetMap(address)?['governorate'])?[
                            'displayValue']) ??
                    'غير متوفر',
                Icons.location_on),
            _buildDetailRow(
                'المنطقة',
                _safeGetString(_safeGetMap(
                        _safeGetMap(address)?['district'])?['displayValue']) ??
                    'غير متوفر',
                Icons.place),
            _buildDetailRow(
                'الحي',
                _safeGetString(_safeGetMap(address)?['neighborhood']) ??
                    'غير متوفر',
                Icons.home),
            _buildDetailRow(
                'الشارع',
                '${_safeGetMap(address)?['street'] ?? 'غير محدد'}',
                Icons.location_on),
            _buildDetailRow('رقم المنزل',
                '${_safeGetMap(address)?['house'] ?? 'غير محدد'}', Icons.house),
            if (_safeGetMap(address)?['gpsCoordinate'] != null) ...[
              _buildCopyableCoordinateRow(
                  _safeGetMap(address)!['gpsCoordinate']['latitude'],
                  _safeGetMap(address)!['gpsCoordinate']['longitude']),
            ],
          ],
        ]),
      ],
    ]);
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.white, Colors.grey.shade50]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [Colors.blue.shade400, Colors.blue.shade600]),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14), topRight: Radius.circular(14)),
          ),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6)),
                child: Icon(_getIconForSection(title),
                    color: Colors.white, size: 18)),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ]),
        ),
        Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children)),
      ]),
    );
  }

  IconData _getIconForSection(String title) {
    switch (title) {
      case 'المعلومات الأساسية':
        return Icons.person;
      case 'بيانات الهوية الوطنية':
        return Icons.badge;
      case 'معلومات العنوان':
        return Icons.location_on;
      default:
        return Icons.info;
    }
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(6)),
            child: Icon(icon, size: 16, color: Colors.blue.shade700)),
        const SizedBox(width: 10),
        Expanded(
            flex: 2,
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                    fontSize: 14))),
        const SizedBox(width: 8),
        Expanded(
            flex: 3,
            child: Text(value,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                textAlign: TextAlign.right)),
      ]),
    );
  }

  Widget _buildCopyableCoordinateRow(dynamic latitude, dynamic longitude) {
    if (latitude == null || longitude == null) {
      return _buildDetailRow('الإحداثيات', 'غير متوفرة', Icons.gps_off);
    }
    final String coordinates = '$latitude,$longitude';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.green.shade300)),
          child: Row(children: [
            const SizedBox(width: 4),
            Expanded(
                child: SelectableText(coordinates,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace'))),
            IconButton(
                onPressed: () => _copyToClipboard(coordinates),
                icon: const Icon(Icons.copy, color: Colors.green)),
          ]),
        )
      ]),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم نسخ الإحداثيات إلى الحافظة'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2)));
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('خطأ'),
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('موافق'))
          ],
        );
      },
    );
  }

  // فتح صفحة التذاكر الخاصة بالمشترك
  void _openCustomerTicketsPage() {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CustomerTicketsPage(
                  authToken: widget.authToken,
                  customerId: widget.userId,
                  customerName: widget.userName,
                )));
  }

  // فتح صفحة سجل التدقيق
  void _openAuditLogPage() {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AuditLogPage(
                  authToken: widget.authToken,
                  customerId: widget.userId,
                  customerName: widget.userName,
                  userRoleHeader: widget.userRoleHeader ?? '0',
                  clientAppHeader: widget.clientAppHeader ??
                      '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
                )));
  }

  // (Bottom sheet version was removed; replaced with detailed dialog via _showCustomerDetailsDialog)

  // ---------------- Header Info (username/phone etc.) -----------------
  Widget _headerInfoGrid(BuildContext context,
      {Color? tileBg, Color? tileBorder, Color? iconBg}) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        // عرض صندوق الهاتف وصندوق معرف المستخدم كلٌ في صف مستقل على جميع المنصات
        const int cols = 1;
        const spacing = 8.0;
        final contentWidth = w - (spacing * (cols - 1));
        final tileW = contentWidth / cols;

        final tiles = <Widget>[
          _buildPhoneTile(tileW, tileBg, tileBorder, iconBg),
          _headerInfoItem(Icons.badge, 'معرف المستخدم', widget.userId, tileW,
              backgroundColor: tileBg,
              borderColor: tileBorder,
              iconBgColor: iconBg),
        ];

        return Wrap(spacing: spacing, runSpacing: spacing, children: tiles);
      },
    );
  }

  Widget _buildPhoneTile(double width, Color? tileBg, Color? tileBorder,
      Color? iconBg) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: tileBg ?? Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tileBorder ?? Colors.grey.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // أيقونة الهاتف
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: iconBg ?? Colors.green.shade100,
                  borderRadius: BorderRadius.circular(6)),
              child: Icon(Icons.phone, size: 16, color: Colors.green.shade700),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('رقم الهاتف',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  if (_resolvedPhone.isNotEmpty)
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        _fmtPhoneLocal(_resolvedPhone),
                        style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                            fontWeight: FontWeight.w600),
                      ),
                    )
                  else
                    Text('غير متوفر',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade500)),
                ],
              ),
            ),
            // زر إظهار الرقم أو نسخه
            if (_resolvedPhone.isNotEmpty)
              Tooltip(
                message: 'نسخ رقم الهاتف',
                child: IconButton(
                  icon:
                      Icon(Icons.copy_rounded, size: 20, color: Colors.green.shade700),
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: _fmtPhoneLocal(_resolvedPhone)));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('تم نسخ رقم الهاتف'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ));
                  },
                ),
              )
            else if (_isFetchingPhone)
              const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Tooltip(
                message: 'جلب رقم الهاتف من النظام',
                child: TextButton.icon(
                  onPressed: _fetchPhoneManually,
                  icon: Icon(Icons.search, size: 16,
                      color: Colors.blue.shade700),
                  label: Text('إظهار الرقم',
                      style: TextStyle(
                          fontSize: 12, color: Colors.blue.shade700)),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    backgroundColor: Colors.blue.shade50,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _headerInfoItem(
      IconData icon, String label, String value, double width,
      {bool ltr = false,
      String? tooltip,
      Color? backgroundColor,
      Color? borderColor,
      Color? iconBgColor}) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor ?? Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor ?? Colors.grey.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: iconBgColor ?? Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(6)),
              child: Icon(icon, size: 16, color: Colors.blue.shade700),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Builder(
                    builder: (_) {
                      final valWidget = ltr
                          ? Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600)))
                          : Text(value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600));
                      return tooltip != null
                          ? Tooltip(message: tooltip, child: valWidget)
                          : valWidget;
                    },
                  ),
                ],
              ),
            ),
            if (label == 'معرف المستخدم')
              Tooltip(
                message: 'نسخ المعرف',
                child: IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 32),
                  color: Colors.blue.shade700,
                  onPressed: () => _copyUserId(value),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _copyUserId(String id) {
    Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ معرف المستخدم'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _userNameRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(6)),
            child: Icon(Icons.person, size: 16, color: Colors.blue.shade700),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.userName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          // زر نسخ الاسم
          Tooltip(
            message: 'نسخ الاسم',
            child: IconButton(
              icon: Icon(Icons.copy_rounded, size: 18, color: Colors.blue.shade700),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.userName));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('تم نسخ الاسم'),
                  backgroundColor: Colors.blue,
                  duration: Duration(seconds: 2),
                ));
              },
            ),
          ),
          // زر نسخ الاسم + الرقم معاً
          if (_resolvedPhone.isNotEmpty)
            Tooltip(
              message: 'نسخ الاسم والرقم معاً',
              child: IconButton(
                icon: Icon(Icons.contact_page_rounded, size: 18,
                    color: Colors.teal.shade700),
                onPressed: () {
                  final text =
                      '${widget.userName}\n${_fmtPhoneLocal(_resolvedPhone)}';
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('تم نسخ الاسم والرقم'),
                    backgroundColor: Colors.teal,
                    duration: Duration(seconds: 2),
                  ));
                },
              ),
            ),
        ],
      ),
    );
  }

  void _onRenewPressed() {
    if (subscriptionDetails == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لا توجد بيانات اشتراك'), backgroundColor: Colors.red));
      return;
    }
    _prepareRenewAndNavigate();
  }

  /// تنفيذ جلب متطلبات التجديد (نفس التسلسل المطلوب) قبل فتح صفحة تفاصيل الاشتراك
  Future<void> _prepareRenewAndNavigate() async {
    final subBasic = subscriptionDetails!;
    final id = _extractSubscriptionId(subBasic) ?? '';
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('معرف الاشتراك غير صالح'),
          backgroundColor: Colors.red));
      return;
    }

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
              content: SizedBox(
                  width: 220,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 14),
                      Expanded(child: Text('جار التحضير للتجديد...')),
                    ],
                  )),
            ));

    Map<String, dynamic>? fullSub;
    Map<String, dynamic>? allowedActions;
    Map<String, dynamic>? bundles;
    Map<String, dynamic>? partnerWallet;
    Map<String, dynamic>? customerWallet;
    double? partnerWalletBalance;
    double? customerWalletBalance;
    try {
      Future<Map<String, dynamic>?> get(String url) async {
        final r = await http.get(Uri.parse(url), headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json'
        }).timeout(const Duration(seconds: 20));
        if (r.statusCode == 200) {
          try {
            return jsonDecode(r.body) as Map<String, dynamic>;
          } catch (_) {
            return null;
          }
        }
        return null;
      }

      // 1) تفاصيل الاشتراك كاملة (نحتاج partnerId)
      fullSub = await get(
          'https://admin.ftth.iq/api/subscriptions/$id?customerId=${widget.userId}');
      final partner = (fullSub?['partner'] as Map?) ?? {};
      final partnerId = partner['id']?.toString() ??
          ((partner['self'] is Map) ? partner['self']['id']?.toString() : '');

      // 2-5) باقي الطلبات (محاولة متوازية)
      final futures = await Future.wait([
        get('https://admin.ftth.iq/api/subscriptions/allowed-actions?subscriptionIds=$id&customerId=${widget.userId}'),
        get('https://admin.ftth.iq/api/plans/bundles?includePrices=false&subscriptionId=$id'),
        partnerId != null && partnerId.isNotEmpty
            ? get(
                'https://admin.ftth.iq/api/partners/$partnerId/wallets/balance')
            : Future.value(null),
        get('https://admin.ftth.iq/api/customers/${widget.userId}/wallets/balance'),
      ]);
      allowedActions = futures[0];
      bundles = futures[1];
      partnerWallet = futures[2];
      customerWallet = futures[3];

      // استخراج الأرصدة
      try {
        final model = partnerWallet?['model'];
        if (model is Map && model['balance'] != null) {
          partnerWalletBalance = double.tryParse(model['balance'].toString());
        } else if (partnerWallet?['balance'] != null) {
          partnerWalletBalance =
              double.tryParse(partnerWallet!['balance'].toString());
        }
      } catch (_) {}
      try {
        final model = customerWallet?['model'];
        if (model is Map && model['balance'] != null) {
          customerWalletBalance = double.tryParse(model['balance'].toString());
        } else if (customerWallet?['balance'] != null) {
          customerWalletBalance =
              double.tryParse(customerWallet!['balance'].toString());
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('⚠️ فشل التحضير المسبق للتجديد: $e');
    } finally {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context, rootNavigator: false).pop();
      }
    }

    // تحضير الحقول المُمررة (استخدام البيانات الأساسية إن لم تتوفر الكاملة)
    final mergedSub = fullSub ?? subBasic;
    final status = _safeGetMap(mergedSub['status']);
    final deviceDetails = _safeGetMap(mergedSub['deviceDetails']);
    final services = _safeGetList(mergedSub['services']);
    final endDate = _safeGetString(mergedSub['endDate']) ??
        _safeGetString(mergedSub['expires']);
    final startedAt = _safeGetString(mergedSub['startedAt']) ??
        _safeGetString(mergedSub['startDate']);
    final currentStatusRaw = _safeGetString(status?['displayValue']) ?? '';
    final currentStatus = _localizedSubscriptionStatus(currentStatusRaw);
    final deviceUsername = _safeGetString(deviceDetails?['username']) ?? '';
    final fdtDisplay =
        _safeGetString(_safeGetMap(deviceDetails?['fdt'])?['displayValue']) ??
            '';
    final fatDisplay =
        _safeGetString(_safeGetMap(deviceDetails?['fat'])?['displayValue']) ??
            '';

    // استخراج معلومات إضافية من البيانات المتاحة
    final deviceOntData = deviceOntInfo;
    final customerData = _customerDataMain;
    final coordinates = _extractCoordinates(customerData);

    // استخراج معلومات الشبكة (FBG/FAT/FDT)
    final fbgFatData = _getFbgFat();
    final fbgValue = fbgFatData.$1;
    final fatValue = fbgFatData.$2;

    // استخراج معلومات الجهاز الإضافية
    String? deviceSerial;
    String? macAddress;
    String? deviceModel;
    String? gpsLatitude;
    String? gpsLongitude;

    if (deviceOntData != null) {
      final ontModel = _safeGetMap(deviceOntData['model']);
      if (ontModel != null) {
        deviceSerial = _safeGetString(ontModel['serialNumber']);
        macAddress = _safeGetString(ontModel['macAddress']);
        deviceModel = _safeGetString(ontModel['model']);
      }
    }

    // استخراج معلومات GPS من بيانات العميل
    if (coordinates != null) {
      gpsLatitude = coordinates.$1;
      gpsLongitude = coordinates.$2;
    }

    // استخراج معلومات إضافية من بيانات الاشتراك
    String? customerAddress;
    if (customerData != null) {
      final addresses = _safeGetList(customerData['addresses']);
      if (addresses != null && addresses.isNotEmpty) {
        final firstAddress = addresses.first;
        customerAddress =
            _safeGetString(_safeGetMap(firstAddress)?['displayValue']);
      }
    }

    // طباعة debugging للمعلومات الإضافية
    debugPrint('📋 === معلومات إضافية يتم تمريرها لصفحة التفاصيل ===');
    debugPrint('🔧 deviceSerial: $deviceSerial');
    debugPrint('🌐 macAddress: $macAddress');
    debugPrint('📱 deviceModel: $deviceModel');
    debugPrint('🌍 GPS Latitude: $gpsLatitude');
    debugPrint('🌍 GPS Longitude: $gpsLongitude');
    debugPrint('🏠 customerAddress: $customerAddress');
    debugPrint('📊 deviceOntInfo available: ${deviceOntData != null}');
    debugPrint('👤 customerDataMain available: ${customerData != null}');
    // إضافة معلومات الشبكة
    debugPrint('🌐 === معلومات الشبكة ===');
    debugPrint('🔗 FBG Value: $fbgValue');
    debugPrint('🔗 FAT Value: $fatValue');
    debugPrint('🔗 FDT Display: $fdtDisplay');
    debugPrint('🔗 FAT Display: $fatDisplay');
    debugPrint('🔐 firstSystemPermissions: ${widget.firstSystemPermissions}');
    debugPrint('👨‍💼 isAdminFlag: ${widget.isAdminFlag}');
    debugPrint('🏢 firstSystemDepartment: ${widget.firstSystemDepartment}');
    debugPrint('🏢 firstSystemCenter: ${widget.firstSystemCenter}');
    debugPrint('💰 firstSystemSalary: ${widget.firstSystemSalary}');
    debugPrint(
        '✅ ftthPermissions available: ${widget.ftthPermissions != null}');
    debugPrint('👤 userRoleHeader: ${widget.userRoleHeader}');
    debugPrint('📱 clientAppHeader: ${widget.clientAppHeader}');
    debugPrint('==========================================');

    if (!mounted) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => SubscriptionDetailsPage(
                  userId: widget.userId,
                  subscriptionId: id,
                  authToken: widget.authToken,
                  activatedBy: widget.activatedBy,
                  userName: widget.userName,
                  userPhone: widget.userPhone,
                  currentStatus: currentStatus,
                  currentBaseService: _baseService(services),
                  deviceUsername: deviceUsername,
                  remainingDays: _days(endDate),
                  expires: endDate,
                  startedAt: startedAt,
                  services: services,
                  fdtDisplayValue: fdtDisplay,
                  fatDisplayValue: fatDisplay,
                  hasServerSavePermission: widget.hasServerSavePermission,
                  hasWhatsAppPermission: widget.hasWhatsAppPermission,
                  importantFtthApiPermissions:
                      widget.importantFtthApiPermissions,
                  initialAllowedActions: allowedActions,
                  initialBundles: bundles,
                  initialPartnerWalletBalance: partnerWalletBalance,
                  initialCustomerWalletBalance: customerWalletBalance,
                  // معلومات إضافية جديدة
                  deviceSerial: deviceSerial,
                  macAddress: macAddress,
                  deviceModel: deviceModel,
                  gpsLatitude: gpsLatitude,
                  gpsLongitude: gpsLongitude,
                  customerAddress: customerAddress,
                  deviceOntInfo: deviceOntData,
                  customerDataMain: customerData,
                  // === معلومات الشبكة ===
                  fbgValue: fbgValue,
                  fatValue: fatValue,
                  // معلومات النظام الأول والصلاحيات
                  firstSystemPermissions: widget.firstSystemPermissions,
                  isAdminFlag: widget.isAdminFlag,
                  firstSystemDepartment: widget.firstSystemDepartment,
                  firstSystemCenter: widget.firstSystemCenter,
                  firstSystemSalary: widget.firstSystemSalary,
                  ftthPermissions: widget.ftthPermissions,
                  userRoleHeader: widget.userRoleHeader,
                  clientAppHeader: widget.clientAppHeader,
                ))).then((_) {
      // تحديث بعد العودة
      fetchUserDetailsAndSubscription();
    });
  }

  Widget _renewButton(BuildContext context, {bool fullWidth = false}) {
    final button = MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.0)),
      child: ElevatedButton(
        onPressed: _onRenewPressed,
        style: _renewButtonStyle(context),
        child: const Text('تجديد'),
      ),
    );
    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }

  // ---------------- Build -----------------
  @override
  Widget build(BuildContext context) {
    final c = _compactMode;
    final bool isMobile = _isMobile(context);
    final double s = isMobile ? 1.0 : 1.15;
    final pad = (c ? 10.0 : 16.0) * s;
    final gap = c ? 3.0 : 6.0;
    final cardGap = c ? 6.0 : 8.0;
    final titleSize = c ? 16.0 : 18.0;
    final coords = _extractCoordinates(_customerDataMain);
    final deviceDetails = subscriptionDetails == null
        ? null
        : _safeGetMap(subscriptionDetails!['deviceDetails']);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72, // زيادة ارتفاع الشريط العلوي
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        title: Text('تفاصيل المستخدم',
            style: _TextStyles.appBarTitle.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
                shadows: const [
                  Shadow(
                      color: Colors.black26,
                      blurRadius: 3,
                      offset: Offset(0, 1.2))
                ])),
        centerTitle: true,
        leading: Builder(
          builder: (ctx) {
            final canPop = Navigator.of(ctx).canPop();
            if (!canPop) return const SizedBox();
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14)),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    size: 30, color: Colors.white),
                padding: const EdgeInsets.all(14),
                constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
                onPressed: () => Navigator.of(ctx).pop(),
                tooltip: 'رجوع',
              ),
            );
          },
        ),
        actions: [
          if (_canAddTask)
            Tooltip(
              message: 'إضافة مهمة',
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00B86B), Color(0xFF00894F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x8800B86B),
                        blurRadius: 14,
                        spreadRadius: 1,
                        offset: Offset(0, 4)),
                    BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 4,
                        offset: Offset(0, 1)),
                  ],
                  border: Border.all(color: Color(0xAAFFFFFF), width: 1.4),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _openAddTaskDialog,
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_task, size: 34, color: Colors.white),
                          SizedBox(width: 8),
                          Text('مهمة',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Tooltip(
            message: 'القائمة',
            child: Builder(
              builder: (ctx) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14)),
                child: IconButton(
                  icon: const Icon(Icons.menu, size: 30, color: Colors.white),
                  padding: const EdgeInsets.all(14),
                  constraints:
                      const BoxConstraints(minWidth: 64, minHeight: 64),
                  onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                ),
              ),
            ),
          ),
        ],
      ),
      endDrawer: _sideMenu(),
      body: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(s)),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage.isNotEmpty
                ? Center(
                    child: Text('خطأ: $errorMessage',
                        style: const TextStyle(color: Colors.red)))
                : SingleChildScrollView(
                    padding: EdgeInsets.all(pad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          margin: EdgeInsets.only(bottom: cardGap),
                          color: Colors.blue.shade100.withValues(alpha: 0.8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.blue.shade200)),
                          child: Padding(
                            padding: EdgeInsets.all(pad),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // هيدر البطاقة مع زر نسخ الكل
                                Row(
                                  children: [
                                    Icon(Icons.person_outline,
                                        size: 18,
                                        color: Colors.blue.shade800),
                                    const SizedBox(width: 6),
                                    Text('معلومات المستخدم',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.blue.shade800)),
                                    const Spacer(),
                                    // زر نسخ كل المعلومات
                                    Tooltip(
                                      message: 'نسخ كل المعلومات',
                                      child: InkWell(
                                        onTap: () {
                                          final phone = _resolvedPhone.isNotEmpty
                                              ? _fmtPhoneLocal(_resolvedPhone)
                                              : 'غير متوفر';
                                          final text =
                                              'الاسم: ${widget.userName}\nرقم الهاتف: $phone\nالمعرف: ${widget.userId}';
                                          Clipboard.setData(
                                              ClipboardData(text: text));
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                            content: Text('تم نسخ كل المعلومات'),
                                            backgroundColor: Colors.teal,
                                            duration: Duration(seconds: 2),
                                          ));
                                        },
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: Colors.teal.shade50,
                                            border: Border.all(
                                                color: Colors.teal.shade200),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.contact_page_rounded,
                                                  size: 14,
                                                  color: Colors.teal.shade700),
                                              const SizedBox(width: 4),
                                              Text('نسخ الكل',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.teal.shade700,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: gap),
                                _userNameRow(),
                                SizedBox(height: gap),
                                _headerInfoGrid(context,
                                    tileBg: Colors.white.withValues(alpha: 0.7),
                                    tileBorder: Colors.blue.shade200,
                                    iconBg: Colors.blue.shade100),
                                SizedBox(height: gap),
                                _renewButton(context, fullWidth: true),
                              ],
                            ),
                          ),
                        ),
                        if (subscriptionDetails != null) ...[
                          (() {
                            final statusRaw = subscriptionDetails!['status'];
                            final statusTxt = statusRaw is String
                                ? statusRaw
                                : _safeGetString(statusRaw?['displayValue']) ??
                                    'Inactive';
                            final norm =
                                statusTxt.toString().trim().toLowerCase();
                            final bool active =
                                (norm == 'active' || norm == 'متصل');
                            final Color bg = active
                                ? Colors.green.shade50
                                : Colors.red.shade100;
                            final Color border = active
                                ? Colors.green.shade300
                                : const Color.fromARGB(255, 205, 7, 7);
                            final Color header = active
                                ? Colors.green.shade700
                                : const Color.fromARGB(255, 88, 3, 3);
                            return Card(
                              margin: EdgeInsets.only(bottom: cardGap),
                              color: bg,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: border)),
                              child: Padding(
                                padding: EdgeInsets.all(pad),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('تفاصيل الاشتراك',
                                        style: _TextStyles.sectionHeader
                                            .copyWith(
                                                fontSize: titleSize,
                                                color: header)),
                                    if (_allSubscriptions.length > 1) ...[
                                      SizedBox(height: gap),
                                      SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: List.generate(
                                            _allSubscriptions.length,
                                            (i) {
                                              final sub = _allSubscriptions[i];
                                              final devDetails = _safeGetMap(sub['deviceDetails']);
                                              final devUsername = _safeGetString(devDetails?['username']) ?? '';
                                              final subStatus = sub['status'] is String
                                                  ? sub['status'] as String
                                                  : _safeGetString((sub['status'] as Map?)?['displayValue']) ?? '';
                                              final isActive = subStatus.toLowerCase() == 'active';
                                              final isSelected = _selectedSubscriptionIndex == i;
                                              // لون الـ pill: أزرق للمختار، أخضر للفعّال، رمادي للمنتهي
                                              final pillColor = isSelected
                                                  ? Colors.blue[700]!
                                                  : isActive
                                                      ? Colors.green[100]!
                                                      : Colors.grey[200]!;
                                              final textColor = isSelected
                                                  ? Colors.white
                                                  : isActive
                                                      ? Colors.green[800]!
                                                      : Colors.black87;
                                              final pillLabel = devUsername.isNotEmpty
                                                  ? devUsername
                                                  : 'اشتراك ${i + 1}';
                                              return GestureDetector(
                                                onTap: () {
                                                  setState(() {
                                                    _selectedSubscriptionIndex = i;
                                                    subscriptionDetails = _allSubscriptions[i];
                                                    deviceOntInfo = null;
                                                    ontErrorMessage = '';
                                                  });
                                                  fetchDeviceOntInfo();
                                                  final id = _extractSubscriptionId(_allSubscriptions[i]);
                                                  if (id != null && id.isNotEmpty)
                                                    fetchFullSubscriptionDetails(id);
                                                },
                                                child: Container(
                                                  margin: const EdgeInsetsDirectional.only(end: 8),
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                                  decoration: BoxDecoration(
                                                    color: pillColor,
                                                    borderRadius: BorderRadius.circular(20),
                                                    border: Border.all(
                                                      color: isSelected
                                                          ? Colors.blue[700]!
                                                          : isActive
                                                              ? Colors.green[400]!
                                                              : Colors.grey[400]!,
                                                    ),
                                                  ),
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        pillLabel,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w700,
                                                          color: textColor,
                                                        ),
                                                      ),
                                                      Text(
                                                        isActive ? 'فعّال' : 'منتهي',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: isSelected
                                                              ? Colors.white70
                                                              : isActive
                                                                  ? Colors.green[700]!
                                                                  : Colors.red[400]!,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                    SizedBox(height: gap),
                                    _subscriptionDetails(),
                                  ],
                                ),
                              ),
                            );
                          })(),
                          Card(
                            margin: EdgeInsets.only(bottom: cardGap),
                            child: Padding(
                              padding: EdgeInsets.all(pad),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('معلومات الجهاز',
                                      style: _TextStyles.sectionHeader
                                          .copyWith(fontSize: titleSize)),
                                  SizedBox(height: gap),
                                  if (deviceDetails != null) ...[
                                    _deviceBox(deviceDetails),
                                    SizedBox(height: gap)
                                  ],
                                  _ontInfoSection()
                                ],
                              ),
                            ),
                          ),
                          if (activeSession != null)
                            Card(
                              margin: EdgeInsets.only(bottom: cardGap),
                              child: Padding(
                                  padding: EdgeInsets.all(pad),
                                  child: _sessionBox(activeSession!)),
                            ),
                          if (coords != null)
                            Card(
                              margin: EdgeInsets.only(bottom: cardGap),
                              child: Padding(
                                padding: EdgeInsets.all(pad),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('موقع المشترك',
                                        style: _TextStyles.sectionHeader
                                            .copyWith(fontSize: titleSize)),
                                    SizedBox(height: gap),
                                    _buildCopyableCoordinateRow(
                                        coords.$1, coords.$2)
                                  ],
                                ),
                              ),
                            ),
                        ] else ...[
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('لا توجد تفاصيل اشتراك متاحة',
                                  style: TextStyle(color: Colors.grey)),
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
      ),
    );
  }

  // القائمة الجانبية (End Drawer)
  Widget _sideMenu() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.blue.shade700,
                    Colors.blue.shade500,
                  ]),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(widget.userName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('ID: ${widget.userId}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: .9),
                            fontSize: 12)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    const SizedBox(height: 12),
                    _drawerAction(
                      title: 'معلومات المشترك',
                      icon: Icons.person_search,
                      color: Colors.blue,
                      onTap: () {
                        Navigator.pop(context);
                        _showCustomerDetailsDialog();
                      },
                    ),
                    _drawerAction(
                      title: 'التذاكر',
                      icon: Icons.confirmation_number,
                      color: Colors.deepPurple,
                      onTap: () {
                        Navigator.pop(context);
                        _openCustomerTicketsPage();
                      },
                    ),
                    _drawerAction(
                      title: 'سجل التدقيق',
                      icon: Icons.history,
                      color: Colors.brown,
                      onTap: () {
                        Navigator.pop(context);
                        _openAuditLogPage();
                      },
                    ),
                    _drawerAction(
                      title: 'تحديث البيانات',
                      icon: Icons.refresh,
                      color: Colors.teal,
                      onTap: () {
                        Navigator.pop(context);
                        fetchUserDetailsAndSubscription();
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('القائمة',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600)),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerAction({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final Color base = color;
    final Color bg = base.withValues(alpha: .10);
    final Color border = base.withValues(alpha: .35);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border, width: 1.2),
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    base.withValues(alpha: .18),
                    bg,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: base.withValues(alpha: .12),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: base.withValues(alpha: .15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: base, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: base,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_back_ios_new,
                      size: 16, color: base.withValues(alpha: .8)),
                ],
              ),
            )),
      ),
    );
  }

  // Extract first available latitude/longitude from customer details
  (String, String)? _extractCoordinates(Map<String, dynamic>? customer) {
    if (customer == null) return null;
    final addresses = _safeGetList(customer['addresses']);
    if (addresses == null) return null;
    for (final a in addresses) {
      final am = _safeGetMap(a);
      final gps = _safeGetMap(am?['gpsCoordinate']);
      final lat = _safeGetString(gps?['latitude']);
      final lon = _safeGetString(gps?['longitude']);
      if (lat != null && lon != null && lat.isNotEmpty && lon.isNotEmpty) {
        return (lat, lon);
      }
    }
    return null;
  }
}

// فتح نافذة إضافة مهمة (إرجاع الامتداد بعد تنظيفه)
extension _AddTaskExtension on UserDetailsPageState {
  void _openAddTaskDialog() {
    final initialNotes = _composeInitialNotes();
    showDialog(
        context: context,
        builder: (context) {
          return AddTaskApiDialog(
            currentUsername: widget.activatedBy,
            currentUserRole: 'مستخدم',
            currentUserDepartment: 'عام',
            initialCustomerName: widget.userName,
            initialCustomerPhone: _fmtPhoneLocal(widget.userPhone),
            initialCustomerLocation: _extractInitialLocation(),
            initialFBG: _getFbgFat().$1 ?? '',
            initialFAT: _getFbgFat().$2 ?? '',
            initialNotes: initialNotes,
            onTaskCreated: (Map<String, dynamic> data) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('تمت إضافة المهمة'),
                  backgroundColor: Colors.green));
            },
          );
        });
  }

  String _composeInitialNotes() {
    try {
      final sub = subscriptionDetails;
      final dev = sub == null ? null : _safeGetMap(sub['deviceDetails']);
      final statusRaw = sub?['status'];
      String subscriptionStatus = '';
      if (statusRaw != null) {
        if (statusRaw is Map) {
          subscriptionStatus = _safeGetString(statusRaw['displayValue']) ?? '';
        } else {
          subscriptionStatus = statusRaw.toString();
        }
      }
      subscriptionStatus = _localizedSubscriptionStatus(subscriptionStatus);
      final endDate = sub == null
          ? ''
          : (_safeGetString(sub['endDate']) ??
              _safeGetString(sub['expires']) ??
              '');
      final endDateFmt = endDate.isEmpty ? '' : _fmtDateTime(endDate);
      final username = _safeGetString(dev?['username']) ?? '';
      final serial = _safeGetString(dev?['serial']) ?? '';
      // محاولة استخراج حالة الجهاز وقوة الإشارة من deviceOntInfo
      String deviceStatus = '';
      String signalQuality = '';
      String rxPowerStr = '';
      final ont = deviceOntInfo;
      if (ont != null) {
        final model = _safeGetMap(ont['model']);
        final st = _safeGetMap(model?['status']);
        deviceStatus =
            _localizedDeviceStatus(_safeGetString(st?['displayValue']));
        final rxPower = model?['rxPower'];
        if (rxPower != null) {
          rxPowerStr = rxPower.toString();
          try {
            final p = double.parse(rxPowerStr);
            if (p >= -20) {
              signalQuality = 'ممتازة';
            } else if (p >= -25)
              signalQuality = 'جيدة';
            else if (p >= -30)
              signalQuality = 'متوسطة';
            else
              signalQuality = 'ضعيفة';
          } catch (_) {}
        }
      }
      final parts = <String>[];
      if (subscriptionStatus.isNotEmpty) {
        parts.add('حالة الاشتراك: $subscriptionStatus');
      }
      if (deviceStatus.isNotEmpty) parts.add('حالة الجهاز: $deviceStatus');
      if (signalQuality.isNotEmpty) {
        parts.add(
            'قوة الإشارة: $signalQuality${rxPowerStr.isNotEmpty ? ' ($rxPowerStr dBm)' : ''}');
      }
      if (endDateFmt.isNotEmpty) parts.add('تاريخ الانتهاء: $endDateFmt');
      if (username.isNotEmpty) parts.add('اليوزر نيم: $username');
      if (serial.isNotEmpty) parts.add('Serial: $serial');
      if (parts.isEmpty) return '';
      return parts.join(' | ');
    } catch (e) {
      return '';
    }
  }

  String _extractInitialLocation() {
    final c = _extractCoordinates(_customerDataMain);
    if (c == null) return '';
    // إرجاع الإحداثيات بالصيغة المطلوبة: latitude,longitude بدون مسافات أو نصوص إضافية
    final lat = c.$1.trim();
    final lon = c.$2.trim();
    return '$lat,$lon';
  }

  Map<String, dynamic>? get activeSession {
    final sd = subscriptionDetails;
    if (sd == null) return null;
    final direct = _safeGetMap(sd['activeSession']);
    if (direct != null) return direct;
    final sessions = _safeGetList(sd['sessions']);
    if (sessions != null) {
      for (final s in sessions) {
        final sm = _safeGetMap(s);
        if (sm == null) continue;
        final status = _safeGetString(sm['status']) ??
            _safeGetString(_safeGetMap(sm['status'])?['displayValue']);
        if (status != null && status.toLowerCase().contains('active')) {
          return sm;
        }
      }
    }
    return null;
  }
}

class EditDevicePage extends StatefulWidget {
  final String subscriptionId;
  final String authToken;
  final String username;
  final String serial;
  final String macAddress;
  const EditDevicePage(
      {super.key,
      required this.subscriptionId,
      required this.authToken,
      required this.username,
      required this.serial,
      required this.macAddress});
  @override
  EditDevicePageState createState() => EditDevicePageState();
}

class EditDevicePageState extends State<EditDevicePage> {
  late TextEditingController usernameController,
      serialController,
      macController;
  bool isLoading = false;
  String errorMessage = '';
  @override
  void initState() {
    super.initState();
    usernameController = TextEditingController(text: widget.username);
    serialController = TextEditingController(text: widget.serial);
    macController = TextEditingController(text: widget.macAddress);
  }

  Future<void> updateDeviceInfo() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = '';
    });
    final body = {
      'username': usernameController.text.trim(),
      'ontSerial': serialController.text.trim(),
      'macAddress': macController.text.trim()
    };
    final url = Uri.parse(
        'https://admin.ftth.iq/api/subscriptions/${widget.subscriptionId}/device');
    try {
      final r = await http.put(url,
          headers: {
            'Authorization': 'Bearer ${widget.authToken}',
            'Content-Type': 'application/json',
            'Accept': 'application/json'
          },
          body: jsonEncode(body));
      if (!mounted) return;
      if (r.statusCode == 200) {
        setState(() => errorMessage = 'تم التحديث بنجاح');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.of(context).pop(true);
        });
      } else {
        setState(() => errorMessage = 'فشل: ${r.statusCode} - ${r.body}');
      }
    } catch (e) {
      if (mounted) setState(() => errorMessage = 'خطأ: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    usernameController.dispose();
    serialController.dispose();
    macController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            title: const Text('تعديل الجهاز', style: _TextStyles.appBarTitle),
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  if (errorMessage.isNotEmpty)
                    Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                            color: errorMessage.contains('نجاح')
                                ? Colors.green.shade50
                                : Colors.red.shade50,
                            border: Border.all(
                                color: errorMessage.contains('نجاح')
                                    ? Colors.green
                                    : Colors.red),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(errorMessage,
                            style: TextStyle(
                                color: errorMessage.contains('نجاح')
                                    ? Colors.green.shade700
                                    : Colors.red.shade700))),
                  _field('اسم المستخدم', usernameController),
                  const SizedBox(height: 12),
                  _field('Serial', serialController),
                  const SizedBox(height: 12),
                  _field('MAC Address', macController),
                  const SizedBox(height: 20),
                  ElevatedButton(
                      onPressed: updateDeviceInfo, child: const Text('حفظ'))
                ])));
  }

  Widget _field(String label, TextEditingController c) => TextField(
      controller: c,
      decoration: InputDecoration(
          labelText: label, border: const OutlineInputBorder()));
}
